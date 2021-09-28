require "rdf_triple"

class TestRdfTriple < Test::Unit::TestCase
  RDF_TEST_SUBJECT = "http://id.loc.gov/authorities/genreForms/gf2011026028"
  RDF_TEST_PREDICATE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
  RDF_TEST_OBJECT = "http://www.loc.gov/mads/rdf/v1#GenreForm"

  def create_triple_string(subject, predicate, object)
    "<#{subject}> <#{predicate}> <#{object}> ."
  end

  def test_parsing
    triple_string = create_triple_string(RDF_TEST_SUBJECT, RDF_TEST_PREDICATE, RDF_TEST_OBJECT)
    triple = RdfTriple.parse(triple_string)
    assert_equal triple.subject, RDF_TEST_SUBJECT
    assert_equal triple.predicate, RDF_TEST_PREDICATE
    assert_equal triple.object, RDF_TEST_OBJECT
  end

  def test_parse_invalid
    assert_raises RdfTriple::ParseError do
      RdfTriple.parse("this is an invalid rdf line")
    end
  end

  def test_valid_predicate
    triple_string = create_triple_string(RDF_TEST_SUBJECT, RDF_TEST_PREDICATE, RDF_TEST_OBJECT)
    triple = RdfTriple.parse(triple_string)
    assert_true triple.valid_predicate?
  end

  def test_invalid_predicate
    triple_string = create_triple_string(RDF_TEST_SUBJECT, "invalid predicate", RDF_TEST_OBJECT)
    triple = RdfTriple.parse(triple_string)
    assert_false triple.valid_predicate?
  end
end
