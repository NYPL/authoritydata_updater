require "solr_doc_generator"

class TestSolrDocGenerator < Test::Unit::TestCase
  def test_initialize
    generator = SolrDocGenerator.new(AuthoritativeRecord::VOCABULARIES.keys.first, nil, nil)
  end
end
