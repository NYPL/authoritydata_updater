# frozen_string_literal: true

class AuthoritativeRecord
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
    if @data.include?(LOC_AUTHORITATIVE_LABEL)
      return @data[LOC_AUTHORITATIVE_LABEL]
    elsif @data.include?(W3_PREF_LABEL)
      return @data[W3_PREF_LABEL].first
    elsif @data.include?(W3_RDF_LABEL)
      return @data[W3_RDF_LABEL]
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
    @data[LOC_ADMIN_METADATA]
  end

  def record_id
    File.basename(subject)
  end

  def as_json(options={})
    {
      uri: @subject,
      term: term,
      term_idx: term,
      term_type: term_type,
      record_id: record_id,
    }
  end

  def to_json(*options)
    as_json(*options).to_json(*options)
  end
end
