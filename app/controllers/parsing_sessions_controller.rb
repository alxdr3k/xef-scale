class ParsingSessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_access
  before_action :require_workspace_write_access, only: [ :create, :bulk_discard, :inline_update ]
  before_action :set_parsing_session, only: [ :inline_update ]

  def index
    @parsing_sessions = @workspace.parsing_sessions
                                  .includes(:processed_file, :duplicate_confirmations)
                                  .order(created_at: :desc)

    @pagy, @parsing_sessions = pagy(@parsing_sessions, items: 20)

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

  def create
    uploaded_files = Array(params[:files]).reject(&:blank?)

    if uploaded_files.empty?
      redirect_to workspace_parsing_sessions_path(@workspace), alert: "파일을 선택해 주세요."
      return
    end

    success_count = 0
    failed_count = 0

    uploaded_files.each do |uploaded_file|
      processed_file = @workspace.processed_files.build(
        filename: uploaded_file.original_filename,
        original_filename: uploaded_file.original_filename,
        status: "pending",
        uploaded_by: current_user
      )
      processed_file.file.attach(uploaded_file)

      if processed_file.save
        job_args = { institution_identifier: params[:institution_identifier] }.compact
        FileParsingJob.perform_later(processed_file.id, **job_args)
        success_count += 1
      else
        failed_count += 1
      end
    end

    if failed_count.zero?
      message = success_count == 1 ? "파일이 업로드되었습니다. 처리 중입니다..." : "#{success_count}개 파일이 업로드되었습니다. 처리 중입니다..."
      redirect_to workspace_parsing_sessions_path(@workspace), notice: message
    elsif success_count.zero?
      redirect_to workspace_parsing_sessions_path(@workspace), alert: "파일 업로드에 실패했습니다."
    else
      redirect_to workspace_parsing_sessions_path(@workspace),
                  notice: "#{success_count}개 파일 업로드 완료, #{failed_count}개 실패"
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
end
