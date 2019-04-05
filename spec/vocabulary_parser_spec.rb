# spec/vocabulary_parser_spec.rb
require_relative 'spec_helper.rb'
require_relative '../lib/vocabulary_parser.rb'

describe "vocabulary parser" do

  it "should convert json documents into valid solr documents" do
    example_json = { "@id"=>"http://id.loc.gov/vocabulary/carriers/nn",
                      "@type"=>["http://www.loc.gov/mads/rdf/v1#Authority", "http://www.w3.org/2004/02/skos/core#Concept"],
                      "http://www.loc.gov/mads/rdf/v1#authoritativeLabel"=>[{"@value"=>"flipchart"}],
                      "http://www.w3.org/2004/02/skos/core#prefLabel"=>[{"@value"=>"flipchart"}]
                    }
                    
    converted_doc = VocabularyParser.new.convert_json_carrier_doc(example_json)
    
    expect(converted_doc).to eq({:uri=>"http://id.loc.gov/vocabulary/carriers/nn",
                                 :term=>"flipchart",
                                 :term_idx=>"flipchart",
                                 :term_type=>"rdacarrier",
                                 :record_id=>"nn",
                                 :language=>"en",
                                 :authority_code=>"rdacarriers",
                                 :authority_name=>"RDA carrier type",
                                 :unique_id=>"rdacarriers_nn",
                                 :alternate_term_idx=>"flipchart",
                                 :alternate_term=>"flipchart"})
  end
end