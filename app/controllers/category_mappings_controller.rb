class CategoryMappingsController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_admin_access
  before_action :set_mapping, only: [ :edit, :update, :destroy ]
  before_action :set_categories, only: [ :index, :new, :edit, :create, :update ]

  def index
    @mappings = @workspace.category_mappings.includes(:category).order(updated_at: :desc)

    if params[:source].present? && params[:source] != "all" && CategoryMapping::SOURCES.include?(params[:source])
      @mappings = @mappings.where(source: params[:source])
    end

    render layout: false if turbo_frame_request?
  end

  def new
    @mapping = @workspace.category_mappings.build(match_type: "exact", source: "manual")
    render partial: "slideover_form", layout: false
  end

  def edit
    render partial: "slideover_form", layout: false
  end

  def create
    @mapping = @workspace.category_mappings.build(mapping_params)
    @mapping.source = "manual"

    if @mapping.save
      flash.now[:notice] = "분류 규칙이 추가되었습니다."
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to workspace_categories_path(@workspace) }
      end
    else
      render partial: "slideover_form", layout: false, status: :unprocessable_entity
    end
  end

  def update
    if @mapping.update(mapping_params)
      flash.now[:notice] = "분류 규칙이 수정되었습니다."
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to workspace_categories_path(@workspace) }
      end
    else
      render partial: "slideover_form", layout: false, status: :unprocessable_entity
    end
  end

  def destroy
    @mapping.destroy
    flash.now[:notice] = "분류 규칙이 삭제되었습니다."

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to workspace_categories_path(@workspace) }
    end
  end

  private

  def set_mapping
    @mapping = @workspace.category_mappings.find(params[:id])
  end

  def set_categories
    @categories = @workspace.categories.order(:name)
  end

  def mapping_params
    params.require(:category_mapping).permit(:merchant_pattern, :match_type, :amount, :category_id)
  end
end
