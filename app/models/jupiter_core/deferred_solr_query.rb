class JupiterCore::DeferredSolrQuery

  include Enumerable
  include Kaminari::PageScopeMethods

  def initialize(klass)
    criteria[:model] = klass
  end

  def criteria
    @criteria ||= {}
  end

  def where(attributes)
    criteria[:where] ||= {}
    criteria[:where].merge!(attributes)
    self
  end

  def limit(num)
    criteria[:limit] = num
    self
  end

  def offset(num)
    criteria[:offset] = num
    self
  end

  def sort(attr)
    criteria[:sort] = attr
    self
  end

  def each
    reified_result_set.map do |res|
      obj = JupiterCore::LockedLdpObject.reify_solr_doc(res)
      yield(obj)
      obj
    end
  end

  # Kaminari integration

  def offset_value
    criteria[:offset]
  end

  def limit_value
    criteria[:limit]
  end

  def total_count
    af_model = criteria[:model].send(:derived_af_class)
    results_count, _ = JupiterCore::Search.perform_solr_query(q: where_clause,
                                                              restrict_to_model: af_model,
                                                              rows: 0,
                                                              start: criteria[:offset],
                                                              sort: criteria[:sort])
    results_count
  end

  private

  # Defer to Kaminari configuration in the +LockedLdpObject+ model
  def method_missing(method, *args, &block)
    if [:default_per_page, :max_per_page, :max_pages, :max_pages_per].include? method
      criteria[:model].send(method, *args, &block) if criteria[:model].respond_to?(method)
    else
      super
    end
  end

  def respond_to_missing?(method, include_private = false)
    super || criteria[:model].respond_to?(method, include_private)
  end

  def model
    criteria[:model]
  end

  def reified_result_set
    _, results, _ = JupiterCore::Search.perform_solr_query(q: where_clause,
                                                           restrict_to_model: criteria[:model].send(:derived_af_class),
                                                           rows: criteria[:limit],
                                                           start: criteria[:offset],
                                                           sort: criteria[:sort])
    results
  end

  def where_clause
    if criteria[:where].present?
      attr_queries = []
      attr_queries << criteria[:where].map do |k, v|
        solr_key = criteria[:model].attribute_metadata(k)[:solr_names].first
        %Q(_query_:"{!field f=#{solr_key}}#{v}")
      end
    else
      ''
    end
  end

end
