require "rdf_triple"
require "pry"

class TestRdfTriple < Test::Unit::TestCase
  RDF_TEST_SUBJECT = "http://id.loc.gov/authorities/genreForms/gf2011026028"
  RDF_TEST_PREDICATE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
  RDF_TEST_OBJECT = "http://www.loc.gov/mads/rdf/v1#GenreForm"

  RDF_TRIPLE_LINE = "<#{RDF_TEST_SUBJECT}> <#{RDF_TEST_PREDICATE}> <#{RDF_TEST_OBJECT}> ."

  def test_parsing
    triple = RdfTriple.parse(RDF_TRIPLE_LINE)

    assert_equal triple.subject, RDF_TEST_SUBJECT
    assert_equal triple.predicate, RDF_TEST_PREDICATE
    assert_equal triple.object, RDF_TEST_OBJECT
  end

  def test_parse_invalid
    assert_raises RdfTriple::ParseError do
      RdfTriple.parse("this is an invalid rdf line")
    end
  end
end
