# Finds whether an incoming pending transaction looks like an already-recorded
# committed transaction, and how confident that match is. The previous logic
# was binary (date + amount → duplicate), which produced too many false
# positives in everyday data (same-amount coffee, transit fares, subscriptions
# on the same day). This service ranks matches so the review UI can surface
# strong matches prominently and weak ones with a "low confidence" hint.
class DuplicateDetector
  Match = Struct.new(:transaction, :score, :confidence, keyword_init: true)

  CONFIDENCE_HIGH = "high".freeze
  CONFIDENCE_MEDIUM = "medium".freeze
  CONFIDENCE_LOW = "low".freeze

  HIGH_THRESHOLD = 90
  MEDIUM_THRESHOLD = 60
  LOW_THRESHOLD = 40

  def initialize(workspace, transaction)
    @workspace = workspace
    @transaction = transaction
  end

  # Returns the best Match for the given transaction, or nil if nothing scores
  # above LOW_THRESHOLD. Candidates are pre-filtered by amount and a small
  # date window so we don't scan the whole ledger.
  def find_match
    candidates = candidate_scope
    best = nil
    candidates.find_each do |candidate|
      score = score_against(candidate)
      next if score < LOW_THRESHOLD
      best = Match.new(transaction: candidate, score: score, confidence: confidence_for(score)) if best.nil? || score > best.score
    end
    best
  end

  def self.confidence_for(score)
    return CONFIDENCE_HIGH if score >= HIGH_THRESHOLD
    return CONFIDENCE_MEDIUM if score >= MEDIUM_THRESHOLD
    CONFIDENCE_LOW
  end

  private

  def confidence_for(score)
    self.class.confidence_for(score)
  end

  def candidate_scope
    scope = @workspace.transactions
                     .active
                     .where(amount: @transaction.amount)
                     .where(date: (@transaction.date - 1.day)..(@transaction.date + 1.day))
                     .where.not(id: @transaction.id)

    if @transaction.installment_month.present?
      scope = scope.where(installment_month: @transaction.installment_month)
    else
      scope = scope.where(installment_month: nil)
    end
    scope
  end

  # Heuristic score: amount match is required (filtered above). Date proximity
  # and merchant overlap then drive the confidence band.
  def score_against(candidate)
    score = 60 # amount + date in range is the floor

    score += 10 if candidate.date == @transaction.date
    score -= 10 if (candidate.date - @transaction.date).abs == 1

    if @transaction.financial_institution_id && candidate.financial_institution_id == @transaction.financial_institution_id
      score += 10
    end

    score += merchant_score(candidate)
    [ score, 100 ].min
  end

  def merchant_score(candidate)
    a = normalize_merchant(@transaction.merchant)
    b = normalize_merchant(candidate.merchant)
    return 0 if a.blank? || b.blank?
    return 30 if a == b
    return 15 if a.include?(b) || b.include?(a)
    overlap = (tokenize(a) & tokenize(b)).length
    return 10 if overlap >= 1
    -10
  end

  def normalize_merchant(value)
    value.to_s.strip.gsub(/\s+/, "").downcase
  end

  def tokenize(value)
    value.scan(/[\p{Hangul}A-Za-z0-9]+/)
  end
end
