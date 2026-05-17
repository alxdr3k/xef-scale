class ProcessedFile < ApplicationRecord
  include Turbo::Broadcastable

  belongs_to :workspace
  belongs_to :uploaded_by, class_name: "User", optional: true
  has_one :parsing_session, dependent: :destroy
  has_many :import_issues, dependent: :nullify
  has_one_attached :file

  STATUSES = %w[pending processing completed failed].freeze

  MAX_FILE_SIZE = 20.megabytes
  ALLOWED_EXTENSIONS = %w[.jpg .jpeg .png .webp .heic].freeze
  ALLOWED_CONTENT_TYPES = %w[
    image/jpeg
    image/png
    image/webp
    image/heic
    image/heif
  ].freeze
  # Bytes of file signature we read to verify the upload really is the image
  # type its extension claims. The longest signature we care about (WebP:
  # "RIFF....WEBP") is 12 bytes.
  MAGIC_SNIFF_BYTES = 16

  validates :filename, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :uploaded_file_must_be_allowed
  validate :uploaded_file_must_be_within_size_limit

  scope :pending, -> { where(status: "pending") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :blob_purged, -> { where.not(blob_purged_at: nil) }
  scope :blob_retained, -> { where(blob_purged_at: nil) }

  def pending?
    status == "pending"
  end

  def processing?
    status == "processing"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def blob_purged?
    blob_purged_at.present?
  end

  # Returns true when the parsing session linked to this file is in a terminal
  # state (failed status, or review_status in committed/rolled_back/discarded)
  # and that state was entered at least `retention_days` ago. Used by the
  # cleanup job introduced for ADR-0002. Returns false when no parsing session
  # exists yet.
  def blob_eligible_for_purge?(retention_days: 180, now: Time.current)
    return false if blob_purged?
    return false unless file.attached?

    session = parsing_session
    return false unless session

    terminal_at = session_terminal_at(session)
    return false unless terminal_at

    now - terminal_at >= retention_days.days
  end

  def purge_blob!(now: Time.current)
    return false if blob_purged?
    return false unless file.attached?

    file.purge_later
    update!(blob_purged_at: now)
    true
  end

  def mark_processing!
    update!(status: "processing")
  end

  def mark_completed!
    update!(status: "completed")
  end

  def mark_failed!
    update!(status: "failed")
  end

  after_commit :broadcast_removal, if: -> {
    saved_change_to_status? && %w[completed failed].include?(status)
  }

  private

  # ADR-0002 defines terminal states narrowly: status == "failed", or
  # review_status in committed/rolled_back/discarded. A session whose parsing
  # is complete but whose review is still pending_review is NOT terminal — the
  # user has not yet acted on it, so the blob must stay.
  def session_terminal_at(session)
    return session.completed_at if session.status == "failed"

    case session.review_status
    when "committed"
      session.committed_at
    when "rolled_back"
      session.rolled_back_at
    when "discarded"
      # discarded_at is stamped by discard_all! and remains stable across
      # later unrelated edits (e.g. notes via inline_update). Pre-migration
      # rows are backfilled to updated_at by the schema migration; nil means
      # the row predates the column AND was never updated since — treat as
      # not-yet-eligible (safer than guessing).
      session.discarded_at
    end
  end

  def broadcast_removal
    broadcast_remove_to(workspace, target: "pending_file_row_#{id}")
    broadcast_remove_to(workspace, target: "pending_file_card_#{id}")
  end

  def uploaded_file_must_be_allowed
    return unless file.attached?

    extension = File.extname(filename.to_s).downcase
    unless ALLOWED_EXTENSIONS.include?(extension)
      errors.add(:file, "지원하지 않는 파일 형식입니다 (#{extension.presence || '확장자 없음'})")
      return
    end

    content_type = file.blob&.content_type
    if content_type.present? && !ALLOWED_CONTENT_TYPES.include?(content_type)
      errors.add(:file, "허용되지 않는 콘텐츠 타입입니다 (#{content_type})")
      return
    end

    # Sniff the first bytes via Marcel so a file with a lying extension or
    # spoofed content_type (e.g. a text blob renamed to .jpg) is rejected
    # before we ship it off to Gemini Vision. Marcel is called without the
    # filename hint so we only trust the actual bytes.
    sniffed = sniff_content_type
    return if sniffed.blank?
    return if sniffed.start_with?("image/")

    errors.add(:file, "파일 내용이 이미지가 아닙니다 (감지된 타입: #{sniffed})")
  end

  def sniff_content_type
    blob = file.blob
    return nil unless blob

    bytes = begin
      blob.open { |tmp| tmp.read(MAGIC_SNIFF_BYTES) }
    rescue ActiveStorage::FileNotFoundError, Errno::ENOENT
      nil
    end

    return nil if bytes.blank?

    Marcel::MimeType.for(StringIO.new(bytes))
  end

  def uploaded_file_must_be_within_size_limit
    return unless file.attached?
    return unless file.blob&.byte_size.to_i > MAX_FILE_SIZE

    errors.add(:file, "파일 크기는 #{MAX_FILE_SIZE / 1.megabyte}MB 이하여야 합니다")
  end
end
