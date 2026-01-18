class CategoriesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_admin_access
  before_action :set_category, only: [:edit, :update, :destroy]

  def index
    @categories = @workspace.categories.order(:name)
  end

  def new
    @category = @workspace.categories.build
  end

  def create
    @category = @workspace.categories.build(category_params)

    if @category.save
      respond_to do |format|
        format.html { redirect_to workspace_categories_path(@workspace), notice: '카테고리가 추가되었습니다.' }
        format.turbo_stream { flash.now[:notice] = '카테고리가 추가되었습니다.' }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @category.update(category_params)
      respond_to do |format|
        format.html { redirect_to workspace_categories_path(@workspace), notice: '카테고리가 수정되었습니다.' }
        format.turbo_stream { flash.now[:notice] = '카테고리가 수정되었습니다.' }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @category.destroy

    respond_to do |format|
      format.html { redirect_to workspace_categories_path(@workspace), notice: '카테고리가 삭제되었습니다.' }
      format.turbo_stream { flash.now[:notice] = '카테고리가 삭제되었습니다.' }
    end
  end

  private

  def set_category
    @category = @workspace.categories.find(params[:id])
  end

  def category_params
    params.require(:category).permit(:name, :keyword, :color)
  end
end
