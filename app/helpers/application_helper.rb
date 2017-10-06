module ApplicationHelper
  def page_title(title)
    @page_title ||= []
    @page_title.push(title) if title.present?
    @page_title.join(' | ')
  end

  def path_for_result(result)
    if result.is_a? Collection
      community_collection_path(result.community, result)
    else
      polymorphic_path(result)
    end
  end

  def facetable_query_params(facet_name, value)
    query_params = { q: params[:q] }
    active_facets = params[:facets] || {}
    active_facets[facet_name] = value
    query_params[:facets] = active_facets

    query_params
  end
end
