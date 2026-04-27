class ParsingSessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_access
  before_action :require_workspace_write_access, only: [ :create, :text_parse, :bulk_discard, :inline_update, :retry, :destroy ]
  before_action :set_parsing_session, only: [ :inline_update, :retry, :destroy ]

  def index
    @parsing_sessions = @workspace.parsing_sessions
                                  .includes(:processed_file, :duplicate_confirmations)
                                  .order(created_at: :desc)

    month_range = nil
    if params[:year].present? && params[:month].present?
      year  = params[:year].to_i
      month = params[:month].to_i
      if year.between?(2000, 2100) && month.between?(1, 12)
        month_range = Date.new(year, month).beginning_of_month..Date.new(year, month).end_of_month
        @parsing_sessions = @parsing_sessions.joins(:transactions).where(transactions: { date: month_range }).distinct
      end
    end

    case params[:filter]
    when "needs_review"
      @parsing_sessions = @parsing_sessions.needs_review
    when "has_duplicates"
      dc_where = { status: "pending" }
      if month_range
        month_tx_ids = @workspace.transactions.where(date: month_range).select(:id)
        dc_where[:new_transaction_id] = month_tx_ids
      end
      @parsing_sessions = @parsing_sessions
                            .joins(:duplicate_confirmations)
                            .where(duplicate_confirmations: dc_where)
                            .distinct
    end

    @pagy, @parsing_sessions = pagy(@parsing_sessions, limit: 20)

    # 아직 parsing_session이 생성되지 않은 pending/processing 파일들
    @pending_files = @workspace.processed_files
                               .left_joins(:parsing_session)
                               .where(parsing_sessions: { id: nil })
                               .where(status: %w[pending processing])
                               .order(created_at: :desc)
  end

  def show
    @parsing_session = @workspace.parsing_sessions.find(params[:id])

    # Redirect to review page if session is completed
    if @parsing_session.completed?
      redirect_to review_workspace_parsing_session_path(@workspace, @parsing_session)
      return
    end

    @duplicate_confirmations = @parsing_session.duplicate_confirmations
                                               .includes(:original_transaction, :new_transaction)
                                               .order(:created_at)
  end

  def text_parse
    text = params[:text].to_s.strip

    if text.blank?
      redirect_to workspace_parsing_sessions_path(@workspace), alert: "텍스트를 입력해 주세요."
      return
    end

    if text.length > 10_000
      redirect_to workspace_parsing_sessions_path(@workspace), alert: "텍스트는 10,000자 이내로 입력해 주세요."
      return
    end

    return unless require_ai_consent!

    unless @workspace.ai_text_parsing_enabled?
      redirect_to workspace_parsing_sessions_path(@workspace),
                  alert: "AI 문자 파싱이 비활성화되어 있습니다. 워크스페이스 설정에서 활성화한 뒤 다시 시도해 주세요."
      return
    end

    parsing_session = @workspace.parsing_sessions.create!(
      source_type: "text_paste",
      status: "pending",
      review_status: "pending_review",
      notes: text
    )

    AiTextParsingJob.perform_later(parsing_session.id)

    redirect_to workspace_parsing_sessions_path(@workspace),
                notice: "AI 파싱 중입니다. 완료되면 검토 후 거래내역에 반영할 수 있습니다."
  end

  def create
    uploaded_files = Array(params[:files]).reject(&:blank?)

    if uploaded_files.empty?
      redirect_to workspace_parsing_sessions_path(@workspace), alert: "파일을 선택해 주세요."
      return
    end

    return unless require_ai_consent!

    unless @workspace.ai_image_parsing_enabled?
      redirect_to workspace_parsing_sessions_path(@workspace),
                  alert: "AI 스크린샷 파싱이 비활성화되어 있습니다. 워크스페이스 설정에서 활성화한 뒤 다시 시도해 주세요."
      return
    end

    success_count = 0
    failed_files = []

    uploaded_files.each do |uploaded_file|
      processed_file = @workspace.processed_files.build(
        filename: uploaded_file.original_filename,
        original_filename: uploaded_file.original_filename,
        status: "pending",
        uploaded_by: current_user,
        institution_identifier: params[:institution_identifier].presence
      )
      processed_file.file.attach(uploaded_file)

      if processed_file.save
        job_args = { institution_identifier: processed_file.institution_identifier }.compact
        FileParsingJob.perform_later(processed_file.id, **job_args)
        success_count += 1
      else
        failed_files << "#{uploaded_file.original_filename}: #{processed_file.errors.full_messages.join(', ')}"
      end
    end

    if failed_files.empty?
      message = success_count == 1 ? "파일이 업로드되었습니다. 처리 중입니다..." : "#{success_count}개 파일이 업로드되었습니다. 처리 중입니다..."
      redirect_to workspace_parsing_sessions_path(@workspace), notice: message
    elsif success_count.zero?
      redirect_to workspace_parsing_sessions_path(@workspace),
                  alert: "파일 업로드에 실패했습니다. #{summarize_failed_files(failed_files)}"
    else
      redirect_to workspace_parsing_sessions_path(@workspace),
                  notice: "#{success_count}개 업로드 완료. 실패: #{summarize_failed_files(failed_files)}"
    end
  end

  def inline_update
    field = params[:field]
    value = params[:value]

    unless field == "notes"
      head :unprocessable_entity
      return
    end

    if @parsing_session.update(notes: value)
      respond_to do |format|
        format.turbo_stream
      end
    else
      head :unprocessable_entity
    end
  end

  def retry
    unless @parsing_session.failed?
      redirect_to workspace_parsing_sessions_path(@workspace), alert: "실패한 세션만 재시도할 수 있습니다."
      return
    end

    processed_file = @parsing_session.processed_file

    if processed_file
      unless @workspace.ai_image_parsing_enabled?
        redirect_to workspace_parsing_sessions_path(@workspace),
                    alert: "AI 스크린샷 파싱이 비활성화되어 있습니다."
        return
      end
      return unless require_ai_consent!

      # 실패 세션을 삭제하고 새 파싱 세션 생성
      ActiveRecord::Base.transaction do
        @parsing_session.destroy!
        processed_file.update!(status: "pending")
      end
      job_args = { institution_identifier: processed_file.institution_identifier }.compact
      FileParsingJob.perform_later(processed_file.id, **job_args)
      redirect_to workspace_parsing_sessions_path(@workspace), notice: "재처리를 시작했습니다."
    else
      unless @workspace.ai_text_parsing_enabled?
        redirect_to workspace_parsing_sessions_path(@workspace),
                    alert: "AI 문자 파싱이 비활성화되어 있습니다."
        return
      end
      return unless require_ai_consent!

      # text_paste 세션: 실패 세션 삭제 후 새 파싱 세션 생성 (idempotency)
      source_type = @parsing_session.source_type
      notes       = @parsing_session.notes
      new_session = ActiveRecord::Base.transaction do
        @parsing_session.destroy!
        @workspace.parsing_sessions.create!(
          source_type: source_type,
          status: "pending",
          review_status: "pending_review",
          notes: notes
        )
      end
      AiTextParsingJob.perform_later(new_session.id)
      redirect_to workspace_parsing_sessions_path(@workspace), notice: "재처리를 시작했습니다."
    end
  end

  def destroy
    unless @parsing_session.failed? || @parsing_session.review_discarded?
      redirect_to workspace_parsing_sessions_path(@workspace), alert: "실패하거나 취소된 세션만 삭제할 수 있습니다."
      return
    end

    processed_file = @parsing_session.processed_file

    @parsing_session.transactions.find_each(&:rollback!) rescue nil
    @parsing_session.destroy!
    processed_file&.destroy

    redirect_to workspace_parsing_sessions_path(@workspace), notice: "세션이 삭제되었습니다."
  end

  def bulk_discard
    session_ids = params[:session_ids].to_s.split(",").map(&:to_i).reject(&:zero?)

    if session_ids.empty?
      redirect_to workspace_parsing_sessions_path(@workspace), alert: "선택된 항목이 없습니다."
      return
    end

    sessions = @workspace.parsing_sessions.where(id: session_ids)

    count = 0
    sessions.find_each do |session|
      if session.can_discard?
        session.discard_all!
        count += 1
      end
    end

    redirect_to workspace_parsing_sessions_path(@workspace),
                notice: "#{count}건의 업로드가 취소되었습니다."
  end

  private

  def set_parsing_session
    @parsing_session = @workspace.parsing_sessions.find(params[:id])
  end

  def summarize_failed_files(failed_files, limit: 3)
    shown = failed_files.first(limit)
    rest  = failed_files.size - shown.size
    rest > 0 ? "#{shown.join(" / ")} 외 #{rest}개" : shown.join(" / ")
  end

  # Hard gate: we will not send SMS text or screenshots to an external model
  # until the workspace has explicitly acknowledged the AI consent notice on
  # the settings page. Returns true if the caller may proceed, false if a
  # redirect has already been issued.
  def require_ai_consent!
    return true unless @workspace.ai_consent_required?

    redirect_to settings_workspace_path(@workspace),
                alert: "AI 기능을 사용하려면 워크스페이스 설정에서 외부 AI 사용 동의가 필요합니다."
    false
  end
end
