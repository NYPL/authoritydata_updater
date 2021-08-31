require "solr_doc_generator"

class TestSolrDocGenerator < Test::Unit::TestCase
  def test_initialize
    generator = SolrDocGenerator.new(:lctgm, nil, nil)

    assert_equal generator.authority_code, :lctgm
    assert_equal generator.authority_name, "Thesaurus for Graphic Materials"
    assert_equal generator.term_type, "concept"

    assert_false generator.verbose
  end
end
