class CommentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_transaction
  before_action :set_comment, only: [ :update, :destroy ]

  def index
    @comments = @transaction.comments.ordered.includes(:user, commentable_transaction: :workspace)

    respond_to do |format|
      format.json do
        html = render_to_string(
          partial: "comments/comment",
          collection: @comments,
          as: :comment,
          formats: [ :html ],
          locals: { current_user_id: current_user.id }
        )
        render json: { html: html, count: @comments.size }
      end
    end
  end

  def create
    @comment = @transaction.comments.build(comment_params)
    @comment.user = current_user

    if @comment.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: workspace_transactions_path(@workspace) }
      end
    else
      head :unprocessable_entity
    end
  end

  def update
    authorize_comment!
    if @comment.update(comment_params.merge(edited_at: Time.current))
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: workspace_transactions_path(@workspace) }
      end
    else
      head :unprocessable_entity
    end
  end

  def destroy
    authorize_comment!
    @comment.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: workspace_transactions_path(@workspace) }
    end
  end

  private

  def set_workspace
    @workspace = current_user.workspaces.find(params[:workspace_id])
  end

  def set_transaction
    @transaction = @workspace.transactions.find(params[:transaction_id])
  end

  def set_comment
    @comment = @transaction.comments.find(params[:id])
  end

  def authorize_comment!
    unless @comment.user_id == current_user.id || current_user.admin_of?(@workspace)
      head :forbidden
    end
  end

  def comment_params
    params.require(:comment).permit(:body)
  end
end
