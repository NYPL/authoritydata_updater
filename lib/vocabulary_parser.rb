# frozen_string_literal: true

require 'nypl_log_formatter'
require 'open-uri'
require_relative 'tripple_to_solr_doc'
require_relative 'solr_handler'

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
    when 'genre_and_form'
      post_genre_and_form_to_solr(@source)
    end
    @logger.info("Finished posting #{@vocabulary} from #{@source} to #{@solr_url}")
  end

  def post_genre_and_form_to_solr(source)
    solr_docs = TrippleToSolrDoc.convert!(file: source,
      term_type: 'genreform',
      authority_code: 'lcgft',
      authority_name: 'Library of Congress Genre/Form Terms for Library and Archival Materials',
      unique_id_prefix: 'lcgft'
    )

    SolrHandler.send_docs_to_solr(@solr_url, solr_docs)
  end

  def post_graphic_materials_to_solr(source)
    solr_docs = TrippleToSolrDoc.convert!(file: source,
      term_type: 'concept',
      authority_code: 'lctgm',
      authority_name: 'Thesaurus for Graphic Materials',
      unique_id_prefix: 'lctgm'
    )

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
