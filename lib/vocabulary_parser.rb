require 'nypl_log_formatter'
require 'open-uri'
require_relative 'solr_handler.rb'

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
    when 'carriers'
      post_carrier_authorities_to_solr(@source)
    end
    @logger.info("Finished parsing #{@vocabulary} from #{@source}.")
  end
  
  def post_carrier_authorities_to_solr(source='http://id.loc.gov/vocabulary/carriers.json')
    uri = URI.parse(source)
    json = JSON.parse(uri.read)
    solr_docs = [] 
    json.each do |json_carrier_doc|
      converted_doc = convert_json_carrier_doc(json_carrier_doc)
      solr_docs << converted_doc if converted_doc
    end
    
    response = SolrHandler.send_docs_to_solr(@solr_url, solr_docs)
    
    puts "Converted these carriers #{uri} to #{solr_docs}."
  end
  
  def convert_json_carrier_doc(json_carrier_doc)
    if json_carrier_doc["http://www.loc.gov/mads/rdf/v1#authoritativeLabel"]
      { 
        :uri => json_carrier_doc["@id"], 
        :term => json_carrier_doc["http://www.loc.gov/mads/rdf/v1#authoritativeLabel"].first["@value"], 
        :term_idx => json_carrier_doc["http://www.loc.gov/mads/rdf/v1#authoritativeLabel"].first["@value"], 
        :term_type => "carrier", 
        :record_id => json_carrier_doc["@id"].gsub('http://id.loc.gov/vocabulary/carriers/',''), 
        :language => "en", 
        :authority_code => "carriers", 
        :authority_name => "LOC carrier type", 
        :unique_id => "carriers_#{json_carrier_doc["@id"].gsub('http://id.loc.gov/vocabulary/carriers/','')}", 
        :alternate_term_idx => json_carrier_doc["http://www.w3.org/2004/02/skos/core#prefLabel"].first["@value"], 
        :alternate_term => json_carrier_doc["http://www.w3.org/2004/02/skos/core#prefLabel"].first["@value"]
      }
    else
      # Skip invalid carrier record.
      nil
    end
  end
end
