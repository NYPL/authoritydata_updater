# spec/vocabulary_parser_spec.rb
require_relative 'spec_helper.rb'

describe "vocabulary parser" do

  it "should convert json documents into valid solr documents" do
    example_json = [{ "@id"=>"http://id.loc.gov/vocabulary/carriers/nn",
                      "@type"=>["http://www.loc.gov/mads/rdf/v1#Authority", "http://www.w3.org/2004/02/skos/core#Concept"],
                      "http://www.loc.gov/mads/rdf/v1#authoritativeLabel"=>[{"@value"=>"flipchart"}],
                      "http://www.w3.org/2004/02/skos/core#prefLabel"=>[{"@value"=>"flipchart"}]
                    }]
    
    expect(ENV['RACK_ENV']).to eq('test')
  end

end