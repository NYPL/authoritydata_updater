# frozen_string_literal: true

class RdfTriple
  REGEX_RDF_TRIPPLES = /^(?<subject>.+?) <(?<predicate>.+?)> (?<object>.+?) \.$/
  REGEX_LITERAL_WITH_LANGUAGE = /^\"(?<value>.+)\"@(?<language>.\w+)$/
  REGEX_LITERAL = /^\"?(?<value>.+?)\"?$/
  REGEX_IRI = /^<(?<value>.+)>$/

  LOC_AUTHORITATIVE_LABEL = "http://www.loc.gov/mads/rdf/v1#authoritativeLabel"
  LOC_ADMIN_METADATA = "http://www.loc.gov/mads/rdf/v1#adminMetadata"
  LOC_RECORD_STATUS = "http://id.loc.gov/ontologies/RecordInfo#recordStatus"
  LOC_STATUS_DEPRECATED = '"deprecated"^^<http://www.w3.org/2001/XMLSchema#string>'

  W3_RDF_LABEL = "http://www.w3.org/2000/01/rdf-schema#label"
  W3_PREF_LABEL = "http://www.w3.org/2004/02/skos/core#prefLabel"
  W3_ALT_LABEL = "http://www.w3.org/2004/02/skos/core#altLabel"
  W3_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

  # predicates that occur a single time per subject
  SINGULAR_PREDICATES = [
    LOC_ADMIN_METADATA,
    LOC_RECORD_STATUS,
    LOC_AUTHORITATIVE_LABEL,
    W3_RDF_LABEL,
  ].freeze

  # predicates that may occur multiple times per subject
  MULTI_PREDICATES = [
    W3_TYPE,
    W3_ALT_LABEL,
    W3_PREF_LABEL,
  ].freeze

  ALL_PREDICATES = (SINGULAR_PREDICATES + MULTI_PREDICATES).freeze

  class ParseError < StandardError; end;

  attr_reader :subject, :predicate, :object

  def self.parse(triple_string)
    matches = triple_string.match(REGEX_RDF_TRIPPLES)
    raise ParseError unless matches

    subject = parse_value(matches[:subject])
    predicate = parse_value(matches[:predicate])
    object = parse_value(matches[:object])

    new(subject, predicate, object)
  end

  def initialize(subject, predicate, object)
    @subject = subject
    @predicate = predicate
    @object = object
  end

  def valid_predicate?
    ALL_PREDICATES.include?(@predicate)
  end

  def singular_predicate?
    SINGULAR_PREDICATES.include?(@predicate)
  end

  def multi_predicate?
    MULTI_PREDICATES.include?(@predicate)
  end

  def deprecated?
    @predicate == LOC_RECORD_STATUS && @object == LOC_STATUS_DEPRECATED
  end

  private

  def self.parse_value(value)
    if match = value.match(REGEX_LITERAL_WITH_LANGUAGE)
      return match[:language] == "en" ? match[:value] : nil
    elsif match = value.match(REGEX_IRI)
      return match[:value]
    elsif match = value.match(REGEX_LITERAL)
      return match[:value]
    else
      raise "Unable to parse RDF value: #{value}"
    end
  end
end
