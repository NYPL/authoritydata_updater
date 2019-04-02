require 'nypl_log_formatter'
require 'open-uri'
require_relative 'solr_handler.rb'

class VocabularyParser
  attr_reader :source, :vocabulary

  def initialize(vocabulary: nil, source: nil)
    @logger = NyplLogFormatter.new(STDOUT, level: 'debug')

    @source = source
    @vocabulary = vocabulary
  end

  def parse!
    case @vocabulary
    when 'carriers'
      post_carrier_authorities_to_solr(@source)
    end
    @logger.info("I just finished parsing #{@vocabulary} from #{@source}. I hope they'll all be so proud of me.")
  end
  
  def post_carrier_authorities_to_solr(source)
    # source http://id.loc.gov/vocabulary/carriers.json
    uri = URI.parse(source)
    json = JSON.parse(uri.read)
    solr_docs = [] 
    json.each do |json_carrier_doc|
      if json_carrier_doc["http://www.loc.gov/mads/rdf/v1#authoritativeLabel"]
        solr_doc = { 
          # "id"=>6293002, (maybe auto-generated by solr?)
          :uri => json_carrier_doc["@id"], 
          :term => json_carrier_doc["http://www.loc.gov/mads/rdf/v1#authoritativeLabel"].first["@value"], 
          :term_idx => json_carrier_doc["http://www.loc.gov/mads/rdf/v1#authoritativeLabel"].first["@value"], 
          :term_type => "carrier", 
          :record_id => json_carrier_doc["@id"].gsub('http://id.loc.gov/vocabulary/carriers/',''), 
          :language => "en", 
          :authority_code => "carriers", 
          :authority_name => "LOC carriers", 
          :unique_id => "carriers_#{json_carrier_doc["@id"].gsub('http://id.loc.gov/vocabulary/carriers/','')}", 
          :alternate_term_idx => json_carrier_doc["http://www.w3.org/2004/02/skos/core#prefLabel"].first["@value"], 
          :alternate_term => json_carrier_doc["http://www.w3.org/2004/02/skos/core#prefLabel"].first["@value"]
        }
        solr_docs << solr_doc
      end
    end
    
    response = SolrHandler.send_docs_to_solr(solr_docs)
    
    puts "I would convert these carriers #{uri} to #{solr_docs}."
  end
end
