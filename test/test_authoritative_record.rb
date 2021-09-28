require "authoritative_record"

class TestAuthoritativeRecord < Test::Unit::TestCase
  RDF_TEST_SUBJECT = "http://id.loc.gov/authorities/genreForms/gf2011026028"
  RDF_TEST_PREDICATE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
  RDF_TEST_OBJECT = "http://www.loc.gov/mads/rdf/v1#GenreForm"

  def create_triple_string(subject, predicate, object)
    "<#{subject}> <#{predicate}> <#{object}> ."
  end

  def test_initialize
    record = AuthoritativeRecord.new(RDF_TEST_SUBJECT)
    assert_equal record.subject, RDF_TEST_SUBJECT
  end

  def test_as_json
    record = AuthoritativeRecord.new(RDF_TEST_SUBJECT)

    triple_string = create_triple_string(RDF_TEST_SUBJECT, RDF_TEST_PREDICATE, RDF_TEST_OBJECT)
    triple = RdfTriple.parse(triple_string)
    record.add_triple(triple)

    assert_equal record.as_json, {
      uri: RDF_TEST_SUBJECT
    }
  end

  def test_to_json
    record = AuthoritativeRecord.new(RDF_TEST_SUBJECT)

    triple_string = create_triple_string(RDF_TEST_SUBJECT, RDF_TEST_PREDICATE, RDF_TEST_OBJECT)
    triple = RdfTriple.parse(triple_string)
    record.add_triple(triple)

    assert_equal record.to_json, "{\"uri\":\"#{RDF_TEST_SUBJECT}\"}"
  end
end
