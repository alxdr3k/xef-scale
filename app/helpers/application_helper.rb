module ApplicationHelper
  include Pagy::Frontend

  APP_NAME = "지출 추적"

  def app_name
    APP_NAME
  end

  def safe_return_to(fallback_path)
    return_to = params[:return_to]
    return fallback_path if return_to.blank?

    # Only allow relative paths starting with / but not //
    if return_to.start_with?("/") && !return_to.start_with?("//")
      return_to
    else
      fallback_path
    end
  end

  # Phase 5 cleanup (Scope C-1): helper-generated HTML도 ADR-0008 semantic 토큰
  # 계약을 따라야 한다. text-gray/bg-white/border-gray/text-blue/bg-blue 등 고정
  # 팔레트는 light-mode 전제라 다크 모드에서 깨진다. semantic 토큰으로 일관화.
  PAGY_LINK_CLASS = "px-3 py-2 leading-tight text-secondary bg-surface border border-divider hover:bg-elev".freeze
  PAGY_PREV_CLASS = "px-3 py-2 ml-0 leading-tight text-secondary bg-surface border border-divider rounded-l-lg hover:bg-elev".freeze
  PAGY_NEXT_CLASS = "px-3 py-2 leading-tight text-secondary bg-surface border border-divider rounded-r-lg hover:bg-elev".freeze
  PAGY_CURRENT_CLASS = "px-3 py-2 leading-tight text-action bg-action-subtle border border-divider".freeze
  PAGY_GAP_CLASS = "px-3 py-2 leading-tight text-secondary bg-surface border border-divider".freeze

  def pagy_nav(pagy, options = {})
    return "" if pagy.pages <= 1

    # Merge params option for preserving query parameters
    base_params = options[:params] || {}

    html = []
    html << '<nav class="flex justify-center">'
    html << '<ul class="inline-flex -space-x-px">'

    if pagy.prev
      html << "<li>#{link_to '이전', url_for(base_params.merge(page: pagy.prev)), class: PAGY_PREV_CLASS}</li>"
    end

    pagy.series.each do |item|
      if item.is_a?(Integer)
        if item == pagy.page
          html << "<li><span class='#{PAGY_CURRENT_CLASS}'>#{item}</span></li>"
        else
          html << "<li>#{link_to item, url_for(base_params.merge(page: item)), class: PAGY_LINK_CLASS}</li>"
        end
      elsif item == :gap
        html << "<li><span class='#{PAGY_GAP_CLASS}'>...</span></li>"
      end
    end

    if pagy.next
      html << "<li>#{link_to '다음', url_for(base_params.merge(page: pagy.next)), class: PAGY_NEXT_CLASS}</li>"
    end

    html << "</ul>"
    html << "</nav>"
    html.join.html_safe
  end
end
