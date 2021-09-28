# frozen_string_literal: true

class AuthoritativeRecord
  VOCABULARIES = {
    lcgft: {
      authority_name: "Library of Congress Genre/Form Terms for Library and Archival Materials",
      term_type: "genreform",
    },
    lctgm: {
      authority_name: "Thesaurus for Graphic Materials",
      term_type: "concept",
    },
    lcsh: {
      authority_name: "Library of Congress subject headings",
    },
    naf: {
      authority_name: "LC/NACO authority file",
    },
    aat: {
      authority_name: "Art and Architecture Thesaurus",
      term_type: "concept",
    },
  }.freeze

  attr_reader :authority_code, :authority_name, :subject

  def initialize(authority_code, subject)
    unless VOCABULARIES.keys.include?(authority_code)
      raise ArgumentError, "authority_code must be one of: #{VOCABULARIES.keys.join(", ")}"
    end

    @authority_code = authority_code
    @authority_name = VOCABULARIES[authority_code][:authority_name]
    @subject = subject
    @data = {}
  end

  def add_triple(triple)
    if triple.singular_predicate?
      @data[triple.predicate] = triple.object
    elsif triple.multi_predicate?
      @data[triple.predicate] ||= Set.new
      @data[triple.predicate] << triple.object
    end
  end

  def term
    if @data.include?(RdfTriple::LOC_AUTHORITATIVE_LABEL)
      return @data[RdfTriple::LOC_AUTHORITATIVE_LABEL]
    elsif @data.include?(RdfTriple::W3_PREF_LABEL)
      return @data[RdfTriple::W3_PREF_LABEL].first
    elsif @data.include?(RdfTriple::W3_RDF_LABEL)
      return @data[RdfTriple::W3_RDF_LABEL]
    end
  end

  def vocabulary
    VOCABULARIES[@authority_code]
  end

  def term_type
    if vocabulary.include?(:term_type)
      return vocabulary[:term_type]
    else
      document_types = @data[W3_TYPE]
      if document_types
        TERM_TYPE_MAPPING.each do |term_type_iri, value|
          if document_types.include?(term_type_iri)
            return value
          end
        end
      end
    end
  end

  def metadata_node
    @data[RdfTriple::LOC_ADMIN_METADATA]
  end

  def record_id
    File.basename(subject)
  end

  def alternate_term
    @data[RdfTriple::W3_ALT_LABEL]&.to_a
  end

  def valid?
    return false if subject.start_with?("_") # bnode
    return false if authority_code == :lcsh && !(subject =~ RdfTriple::REGEX_LOC_URI)
    return false if authority_code == :lcsh && term_type == "complex_subject"
    return false unless term && term_type
    true
  end

  def as_json(options={})
    {
      uri: @subject,
      term: term,
      term_idx: term,
      term_type: term_type,
      record_id: record_id,
      language: "en",
      authority_code: @authority_code,
      authority_name: @authority_name,
      unique_id: "#{@authority_code}_#{record_id}",
      alternate_term_idx: alternate_term,
      alternate_term: alternate_term,
    }
  end

  def to_json(*options)
    as_json(*options).to_json(*options)
  end
end
