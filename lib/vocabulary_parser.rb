# frozen_string_literal: true

require 'nypl_log_formatter'
require 'open-uri'
require_relative 'solr_handler.rb'
require 'rdf'
require 'linkeddata'
include RDF

class VocabularyParser
  attr_reader :source, :vocabulary, :solr_url

  def initialize(vocabulary: nil, source: nil, solr_url: nil)
    @logger = NyplLogFormatter.new(STDOUT, level: 'debug')

    @source = source
    @vocabulary = vocabulary
    @solr_url = solr_url
  end

  def parse!
    case @vocabulary
    when 'rdacarriers'
      post_carrier_authorities_to_solr(@source)
    when 'graphic_materials'
      post_graphic_materials_to_solr(@source)
    end
    @logger.info("Finished posting #{@vocabulary} from #{@source} to #{@solr_url}")
  end

  def post_graphic_materials_to_solr(source)
    all_subjects = {}
    statement_count = 0

    RDF::Reader.open(source) do |reader|
      reader.each_statement do |statement|
        statement_count = statement_count + 1
        @logger.debug("parsing statement # #{statement_count}")
        subject_url = statement.subject.to_s
        if all_subjects.keys.include?(subject_url)
          all_subjects[subject_url].merge!(statement.predicate.to_s => statement.object.to_s)
        else
          all_subjects[subject_url] = {
            statement.predicate.to_s => statement.object.to_s
          }
        end
      end
    end

    @logger.info("before weeding out there were #{all_subjects.keys.length}")

    # Weed out out old /deprecated subjects
    all_subjects.reject! do |_subject, attributes|
      change_history = attributes['http://www.w3.org/2004/02/skos/core#changeNote']
      all_subjects.dig(change_history, 'http://purl.org/vocab/changeset/schema#changeReason') == 'deprecated'
    end

    @logger.info("after weeding out deprecated there were #{all_subjects.keys.length}")

    # Weed out bnodes, you have to do this after weeding out deprecateds, not at the same time
    all_subjects.select! do |subject, _attributes|
      subject.include?('http')
    end
    @logger.info("after weeding out bnodes there were #{all_subjects.keys.length}")

    solr_docs = all_subjects.map do |subject, attributes|
      {
        uri: subject,
        term: attributes.dig('http://www.loc.gov/mads/rdf/v1#authoritativeLabel'),
        term_idx: attributes.dig('http://www.loc.gov/mads/rdf/v1#authoritativeLabel'),
        term_type: 'genreform',
        record_id: File.basename(subject),
        language: 'en',
        authority_code: 'lctgm',
        authority_name: 'Thesaurus for Graphic Materials',
        unique_id: "lctgm_#{File.basename(subject)}",
        alternate_term_idx: attributes.dig('http://www.w3.org/2004/02/skos/core#prefLabel'),
        alternate_term: attributes.dig('http://www.w3.org/2004/02/skos/core#prefLabel')
      }
    end
    SolrHandler.send_docs_to_solr(@solr_url, solr_docs)
  end

  def post_carrier_authorities_to_solr(source = 'http://id.loc.gov/vocabulary/carriers.json')
    uri = URI.parse(source)
    json = JSON.parse(uri.read)
    solr_docs = []
    json.each do |json_carrier_doc|
      converted_doc = convert_json_carrier_doc(json_carrier_doc)
      solr_docs << converted_doc if converted_doc
    end

    response = SolrHandler.send_docs_to_solr(@solr_url, solr_docs)
    @logger.info("Converted carriers from #{uri}.")
  end

  def convert_json_carrier_doc(json_carrier_doc)
    if json_carrier_doc['http://www.loc.gov/mads/rdf/v1#authoritativeLabel']
      {
        uri: json_carrier_doc['@id'],
        term: json_carrier_doc['http://www.loc.gov/mads/rdf/v1#authoritativeLabel'].first['@value'],
        term_idx: json_carrier_doc['http://www.loc.gov/mads/rdf/v1#authoritativeLabel'].first['@value'],
        term_type: 'rdacarrier',
        record_id: json_carrier_doc['@id'].gsub('http://id.loc.gov/vocabulary/carriers/', ''),
        language: 'en',
        authority_code: 'rdacarriers',
        authority_name: 'RDA carrier type',
        unique_id: "rdacarriers_#{json_carrier_doc['@id'].gsub('http://id.loc.gov/vocabulary/carriers/', '')}",
        alternate_term_idx: json_carrier_doc['http://www.w3.org/2004/02/skos/core#prefLabel'].first['@value'],
        alternate_term: json_carrier_doc['http://www.w3.org/2004/02/skos/core#prefLabel'].first['@value']
      }
    else
      @logger.warn("Invalid carrier doc found. #{json_carrier_doc}")
      nil
    end
  end
end
