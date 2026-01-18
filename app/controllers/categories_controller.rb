class CategoriesController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_admin_access
  before_action :set_category, only: [:edit, :update, :destroy]

  def index
    @categories = @workspace.categories.order(:name)
  end

  def new
    @category = @workspace.categories.build
    @slideover = params[:slideover] == 'true'
    @transaction_id = params[:transaction_id]

    if @slideover
      render partial: 'slideover_form', layout: false
    end
  end

  def create
    @category = @workspace.categories.build(category_params)
    @slideover = params[:slideover] == 'true'
    @transaction_id = params[:transaction_id]

    if @category.save
      if @slideover && @transaction_id.present?
        # Assign category to transaction and return turbo stream
        @transaction = @workspace.transactions.find(@transaction_id)
        @transaction.update(category_id: @category.id)
        @categories = @workspace.categories.order(:name)
        flash.now[:notice] = '카테고리가 추가되고 거래에 적용되었습니다.'
        render turbo_stream: [
          turbo_stream.replace(dom_id(@transaction), partial: 'transactions/transaction_row', locals: { transaction: @transaction }),
          turbo_stream.update('flash', partial: 'shared/flash'),
          turbo_stream.append('slideover-content', '<div data-controller="slideover-close"></div>'.html_safe)
        ]
      else
        respond_to do |format|
          format.html { redirect_to workspace_categories_path(@workspace), notice: '카테고리가 추가되었습니다.' }
          format.turbo_stream { flash.now[:notice] = '카테고리가 추가되었습니다.' }
        end
      end
    else
      if @slideover
        render partial: 'slideover_form', layout: false, status: :unprocessable_entity
      else
        render :new, status: :unprocessable_entity
      end
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
