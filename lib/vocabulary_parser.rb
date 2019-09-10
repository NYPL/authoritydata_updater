# frozen_string_literal: true
require_relative 'tripple_to_solr_doc'

class VocabularyParser
  attr_reader :source, :vocabulary, :solr_url

  def initialize(vocabulary: nil, source: nil, solr_url: nil, start_at_line: nil, db_file_name: nil)
    @source = source
    @vocabulary = vocabulary
    @start_at_line = start_at_line
    @db_file_name = db_file_name
  end

  def parse!
    case @vocabulary
    when 'rdacarriers'
      generate_carrier_solr_docs(@source)
    when 'graphic_materials'
      generate_graphic_materials_solr_docs(@source)
    when 'genre_and_form'
      generate_genre_and_form_solr_docs(@source)
    when 'names'
      generate_name_solr_docs(@source)
    end
    # @logger.info("Finished posting #{@vocabulary} from #{@source} to #{@solr_url}")
  end

  def generate_name_solr_docs(source)
    solr_docs = TrippleToSolrDoc.convert!(file: source,
      term_type: :auto,
      start_at_line: @start_at_line,
      db_file_name: @db_file_name,
      authority_code: 'naf',
      authority_name: 'LC/NACO authority file',
      unique_id_prefix: 'naf'
    )
  end

  def generate_genre_and_form_solr_docs(source)
    solr_docs = TrippleToSolrDoc.convert!(file: source,
      term_type: 'genreform',
      start_at_line: @start_at_line,
      db_file_name: @db_file_name,
      authority_code: 'lcgft',
      authority_name: 'Library of Congress Genre/Form Terms for Library and Archival Materials',
      unique_id_prefix: 'lcgft'
    )
  end

  def generate_graphic_materials_solr_docs(source)
    solr_docs = TrippleToSolrDoc.convert!(file: source,
      term_type: 'concept',
      start_at_line: @start_at_line,
      db_file_name: @db_file_name,
      authority_code: 'lctgm',
      authority_name: 'Thesaurus for Graphic Materials',
      unique_id_prefix: 'lctgm'
    )
  end

  # This needs to be reimplemented to  deal with N-Triples
  def generate_carrier_solr_docs(source = 'http://id.loc.gov/vocabulary/carriers.json')
    # uri = URI.parse(source)
    # json = JSON.parse(uri.read)
    # solr_docs = []
    # json.each do |json_carrier_doc|
    #   converted_doc = convert_json_carrier_doc(json_carrier_doc)
    #   solr_docs << converted_doc if converted_doc
    # end
    #
    # response = SolrHandler.send_docs_to_solr(@solr_url, solr_docs)
    # @logger.info("Converted carriers from #{uri}.")
  end

  # This needs to be reimplemented to  deal with N-Triples
  def convert_json_carrier_doc(json_carrier_doc)
    # if json_carrier_doc['http://www.loc.gov/mads/rdf/v1#authoritativeLabel']
    #   {
    #     uri: json_carrier_doc['@id'],
    #     term: json_carrier_doc['http://www.loc.gov/mads/rdf/v1#authoritativeLabel'].first['@value'],
    #     term_idx: json_carrier_doc['http://www.loc.gov/mads/rdf/v1#authoritativeLabel'].first['@value'],
    #     term_type: 'rdacarrier',
    #     record_id: json_carrier_doc['@id'].gsub('http://id.loc.gov/vocabulary/carriers/', ''),
    #     language: 'en',
    #     authority_code: 'rdacarriers',
    #     authority_name: 'RDA carrier type',
    #     unique_id: "rdacarriers_#{json_carrier_doc['@id'].gsub('http://id.loc.gov/vocabulary/carriers/', '')}",
    #     alternate_term_idx: json_carrier_doc['http://www.w3.org/2004/02/skos/core#prefLabel'].first['@value'],
    #     alternate_term: json_carrier_doc['http://www.w3.org/2004/02/skos/core#prefLabel'].first['@value']
    #   }
    # else
    #   @logger.warn("Invalid carrier doc found. #{json_carrier_doc}")
    #   nil
    # end
  end
end
