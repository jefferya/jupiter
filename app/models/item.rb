class Item < JupiterCore::LockedLdpObject

  include ObjectProperties
  include ItemProperties
  # Needed for ActiveStorage (logo)...
  include GlobalID::Identification
  ldp_object_includes Hydra::Works::WorkBehavior

  # Contributors (faceted in `all_contributors`)
  has_attribute :creators, RDF::Vocab::BIBO.authorList, type: :json_array, solrize_for: [:search]
  # copying the creator values into an un-json'd field for Metadata consumption
  has_multival_attribute :unordered_creators, ::RDF::Vocab::DC11.creator, solrize_for: [:search]
  has_multival_attribute :contributors, ::RDF::Vocab::DC11.contributor, solrize_for: [:search]

  has_attribute :created, ::RDF::Vocab::DC.created, solrize_for: [:search, :sort]

  # Subject types (see `all_subjects` for faceting)
  has_multival_attribute :temporal_subjects, ::RDF::Vocab::DC.temporal, solrize_for: [:search]
  has_multival_attribute :spatial_subjects, ::RDF::Vocab::DC.spatial, solrize_for: [:search]

  has_attribute :description, ::RDF::Vocab::DC.description, type: :text, solrize_for: :search
  has_attribute :publisher, ::RDF::Vocab::DC.publisher, solrize_for: [:search, :facet]
  # has_attribute :date_modified, ::RDF::Vocab::DC.modified, type: :date, solrize_for: :sort
  has_multival_attribute :languages, ::RDF::Vocab::DC.language, solrize_for: [:search, :facet]
  has_attribute :license, ::RDF::Vocab::DC.license, solrize_for: [:search]

  # `type` is an ActiveFedora keyword, so we call it `item_type`
  # Note also the `item_type_with_status` below for searching, faceting and forms
  has_attribute :item_type, ::RDF::Vocab::DC.type, solrize_for: :exact_match
  has_attribute :source, ::RDF::Vocab::DC.source, solrize_for: :exact_match
  has_attribute :related_link, ::RDF::Vocab::DC.relation, solrize_for: :exact_match

  # Bibo attributes
  # This status is only for articles: either 'published' (alone) or two triples for 'draft'/'submitted'
  has_multival_attribute :publication_status, ::RDF::Vocab::BIBO.status, solrize_for: :exact_match

  # Solr only
  additional_search_index :doi_without_label, solrize_for: :exact_match,
                                              as: -> { doi.gsub('doi:', '') if doi.present? }

  # This combines both the controlled vocabulary codes from item_type and published_status above
  # (but only for items that are articles)
  additional_search_index :item_type_with_status,
                          solrize_for: :facet,
                          as: -> { item_type_with_status_code }

  # Combine creators and contributors for faceting (Thesis also uses this index)
  # Note that contributors is converted to an array because it can be nil
  additional_search_index :all_contributors, solrize_for: :facet, as: -> { creators + contributors.to_a }

  # Combine all the subjects for faceting
  additional_search_index :all_subjects, solrize_for: :facet, as: -> { all_subjects }

  # This is stored in solr: combination of item_type and publication_status
  def item_type_with_status_code
    return nil if item_type.blank?
    # Return the item type code unless it's an article, then append publication status code
    item_type_code = CONTROLLED_VOCABULARIES[:item_type].from_uri(item_type)
    return item_type_code unless item_type_code == :article
    return nil if publication_status.blank?
    publication_status_code = CONTROLLED_VOCABULARIES[:publication_status].from_uri(publication_status.first)
    # Next line of code means that 'article_submitted' exists, but 'article_draft' doesn't ("There can be only one!")
    publication_status_code = :submitted if publication_status_code == :draft
    "#{item_type_code}_#{publication_status_code}".to_sym
  rescue ArgumentError
    return nil
  end

  def all_subjects
    subject + temporal_subjects.to_a + spatial_subjects.to_a
  end

  unlocked do
    before_validation :populate_sort_year
    before_save :copy_creators_to_unordered_predicate

    validates :created, presence: true
    validates :sort_year, presence: true
    validates :languages, presence: true, uri: { in_vocabulary: :language }
    validates :item_type, presence: true, uri: { in_vocabulary: :item_type }
    validates :subject, presence: true
    validates :creators, presence: true
    validates :license, uri: { in_vocabularies: [:license, :old_license] }
    validates :publication_status, uri: { in_vocabulary: :publication_status }
    validate :publication_status_presence,
             if: ->(item) { item.item_type == CONTROLLED_VOCABULARIES[:item_type].article }
    validate :publication_status_absence, if: ->(item) { item.item_type != CONTROLLED_VOCABULARIES[:item_type].article }
    validate :publication_status_compound_uri, if: lambda { |item|
      item.item_type == CONTROLLED_VOCABULARIES[:item_type].article && item.publication_status.present?
    }
    validate :license_xor_rights_must_be_present

    def populate_sort_year
      self.sort_year = Date.parse(created).year.to_s if created.present?
    rescue ArgumentError
      # date was unparsable, try to pull out the first 4 digit number as a year
      capture = created.scan(/\d{4}/)
      self.sort_year = capture[0] if capture.present?
    end

    def copy_creators_to_unordered_predicate
      return unless creators_changed?
      self.unordered_creators = []
      creators.each { |c| self.unordered_creators += [c] }
    end

    def license_xor_rights_must_be_present
      # Must have one of license or rights, not both
      if license.blank?
        errors.add(:base, :need_either_license_or_rights) if rights.blank?
      elsif rights.present?
        errors.add(:base, :not_both_license_and_rights)
      end
    end

    def publication_status_presence
      errors.add(:publication_status, :required_for_article) if publication_status.blank?
    end

    def publication_status_absence
      errors.add(:publication_status, :must_be_absent_for_non_articles) if publication_status.present?
    end

    def publication_status_compound_uri
      ps_vocab = CONTROLLED_VOCABULARIES[:publication_status]
      statuses = publication_status.sort
      return unless statuses != [ps_vocab.published] && statuses != [ps_vocab.draft, ps_vocab.submitted]
      errors.add(:publication_status, :not_recognized)
    end
  end

end
