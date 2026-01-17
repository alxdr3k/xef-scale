class ParsingSessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_access
  before_action :require_workspace_write_access, only: [:create]

  def index
    @parsing_sessions = @workspace.parsing_sessions
                                  .includes(:processed_file)
                                  .order(created_at: :desc)

    @pagy, @parsing_sessions = pagy(@parsing_sessions, items: 20)
  end

  def show
    @parsing_session = @workspace.parsing_sessions.find(params[:id])
    @duplicate_confirmations = @parsing_session.duplicate_confirmations
                                               .includes(:original_transaction, :new_transaction)
                                               .order(:created_at)
  end

  def create
    unless params[:file].present?
      redirect_to workspace_parsing_sessions_path(@workspace), alert: '파일을 선택해 주세요.'
      return
    end

    uploaded_file = params[:file]

    @processed_file = @workspace.processed_files.build(
      filename: uploaded_file.original_filename,
      original_filename: uploaded_file.original_filename,
      status: 'pending'
    )
    @processed_file.file.attach(uploaded_file)

    if @processed_file.save
      # Queue background job for parsing
      FileParsingJob.perform_later(@processed_file.id)
      redirect_to workspace_parsing_sessions_path(@workspace),
                  notice: '파일이 업로드되었습니다. 처리 중입니다...'
    else
      redirect_to workspace_parsing_sessions_path(@workspace),
                  alert: '파일 업로드에 실패했습니다.'
    end
  end
end
