module ApplicationHelper
  include Pagy::Frontend

  def pagy_nav(pagy, options = {})
    return '' if pagy.pages <= 1

    # Merge params option for preserving query parameters
    base_params = options[:params] || {}

    html = []
    html << '<nav class="flex justify-center">'
    html << '<ul class="inline-flex -space-x-px">'

    if pagy.prev
      html << "<li>#{link_to '이전', url_for(base_params.merge(page: pagy.prev)), class: 'px-3 py-2 ml-0 leading-tight text-gray-500 bg-white border border-gray-300 rounded-l-lg hover:bg-gray-100'}</li>"
    end

    pagy.series.each do |item|
      if item.is_a?(Integer)
        if item == pagy.page
          html << "<li><span class='px-3 py-2 leading-tight text-blue-600 bg-blue-50 border border-gray-300'>#{item}</span></li>"
        else
          html << "<li>#{link_to item, url_for(base_params.merge(page: item)), class: 'px-3 py-2 leading-tight text-gray-500 bg-white border border-gray-300 hover:bg-gray-100'}</li>"
        end
      elsif item == :gap
        html << "<li><span class='px-3 py-2 leading-tight text-gray-500 bg-white border border-gray-300'>...</span></li>"
      end
    end

    if pagy.next
      html << "<li>#{link_to '다음', url_for(base_params.merge(page: pagy.next)), class: 'px-3 py-2 leading-tight text-gray-500 bg-white border border-gray-300 rounded-r-lg hover:bg-gray-100'}</li>"
    end

    html << '</ul>'
    html << '</nav>'
    html.join.html_safe
  end
end
