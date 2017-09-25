class Item < JupiterCore::LockedLdpObject

  ldp_object_includes Hydra::Works::WorkBehavior

  VISIBILITY_EMBARGO = 'embargo'.freeze
  VISIBILITIES = (JupiterCore::VISIBILITIES + [VISIBILITY_EMBARGO]).freeze

  has_attribute :title, ::RDF::Vocab::DC.title, solrize_for: [:search, :facet, :sort]
  has_attribute :subject, ::RDF::Vocab::DC.subject, solrize_for: [:search, :facet]
  has_attribute :creator, ::RDF::Vocab::DC.creator, solrize_for: [:search, :facet]
  has_attribute :contributor, ::RDF::Vocab::DC.contributor, solrize_for: [:search, :facet]
  has_attribute :description, ::RDF::Vocab::DC.description, type: :text, solrize_for: :search
  has_attribute :publisher, ::RDF::Vocab::DC.publisher, solrize_for: [:search, :facet]
  has_attribute :date_created, ::RDF::Vocab::DC.created, type: :date, solrize_for: [:search, :sort]
  # has_attribute :date_modified, ::RDF::Vocab::DC.modified, type: :date, solrize_for: :sort
  has_attribute :language, ::RDF::Vocab::DC.language, solrize_for: [:search, :facet]
  has_attribute :doi, ::VOCABULARY[:ualib].doi, solrize_for: :exact_match

  has_multival_attribute :member_of_paths, ::VOCABULARY[:ualib].path, type: :path, solrize_for: :pathing
  has_attribute :embargo_end_date, ::RDF::Vocab::DC.modified, type: :date, solrize_for: [:sort]

  solr_index :doi_without_label, solrize_for: :exact_match,
                                 as: -> { doi.gsub('doi:', '') if doi.present? }

  def self.display_attribute_names
    super - [:member_of_paths]
  end

  def self.valid_visibilities
    super + [VISIBILITY_EMBARGO]
  end

  def each_community_collection
    member_of_paths.each do |path|
      community_id, collection_id = path.split('/')
      yield Community.find(community_id), Collection.find(collection_id)
    end
  end

  unlocked do
    validates :embargo_end_date, presence: true, if: ->(item) { item.visibility == VISIBILITY_EMBARGO }
    validates :embargo_end_date, absence: true, if: ->(item) { item.visibility != VISIBILITY_EMBARGO }
    validates :member_of_paths, presence: true
    validate :communities_and_collections_validations

    def add_to_path(community_id, collection_id)
      self.member_of_paths += ["#{community_id}/#{collection_id}"]
    end

    def communities_and_collections_validations
      return unless member_of_paths.present?
      member_of_paths.each do |path|
        community_id, collection_id = path.split('/')
        community = Community.where(id: community_id).first
        errors.add(:member_of_paths, :community_not_found, id: community_id) unless community.present?
        collection = Collection.where(id: collection_id).first
        errors.add(:member_of_paths, :collection_not_found, id: collection_id) unless collection.present?
      end
    end
  end

end