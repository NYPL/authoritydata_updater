require "authoritative_record"

class TestAuthoritativeRecord < Test::Unit::TestCase
  RDF_TEST_SUBJECT = "http://id.loc.gov/authorities/genreForms/gf2011026028"
  RDF_TYPE_PREDICATE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
  RDF_TEST_OBJECT = "http://www.loc.gov/mads/rdf/v1#Temporal"
  TEST_AUTHORITY_CODE = :lcgft
  TEST_TERM = "test_term"
  TEST_TYPE_TYPE = "temporal"

  def create_triple_string(subject, predicate, object)
    "<#{subject}> <#{predicate}> <#{object}> ."
  end

  def test_initialize
    record = AuthoritativeRecord.new(TEST_AUTHORITY_CODE, RDF_TEST_SUBJECT)
    assert_equal record.subject, RDF_TEST_SUBJECT
  end

  def test_as_json
    record = AuthoritativeRecord.new(TEST_AUTHORITY_CODE, RDF_TEST_SUBJECT)
    record_json = record.as_json
    assert_equal record_json[:uri], RDF_TEST_SUBJECT
  end

  def test_to_json
    record = AuthoritativeRecord.new(TEST_AUTHORITY_CODE, RDF_TEST_SUBJECT)
    assert_not_nil record.to_json
  end

  def test_term_loc_authoritative_label
    record = AuthoritativeRecord.new(TEST_AUTHORITY_CODE, RDF_TEST_SUBJECT)
    record.add_triple(RdfTriple.parse(create_triple_string(
      RDF_TEST_SUBJECT,
      RdfTriple::LOC_AUTHORITATIVE_LABEL,
      TEST_TERM)))
    assert_equal record.term, TEST_TERM
  end

  def test_term_w3_pref_label
    record = AuthoritativeRecord.new(TEST_AUTHORITY_CODE, RDF_TEST_SUBJECT)
    record.add_triple(RdfTriple.parse(create_triple_string(
      RDF_TEST_SUBJECT,
      RdfTriple::W3_PREF_LABEL,
      TEST_TERM)))
    assert_equal record.term, TEST_TERM
  end

  def test_term_w3_rdf_label
    record = AuthoritativeRecord.new(TEST_AUTHORITY_CODE, RDF_TEST_SUBJECT)
    record.add_triple(RdfTriple.parse(create_triple_string(
      RDF_TEST_SUBJECT,
      RdfTriple::W3_RDF_LABEL,
      TEST_TERM)))
    assert_equal record.term, TEST_TERM
  end

  def test_term_type_lcgft
    record = AuthoritativeRecord.new(:lcgft, RDF_TEST_SUBJECT)
    assert_equal record.term_type, "genreform"
  end

  def test_term_type_naf
    record = AuthoritativeRecord.new(:naf, RDF_TEST_SUBJECT)
    assert_equal record.term_type, nil

    record.add_triple(RdfTriple.parse(create_triple_string(
      RDF_TEST_SUBJECT,
      RDF_TYPE_PREDICATE,
      RDF_TEST_OBJECT)))
      assert_equal record.term_type, TEST_TYPE_TYPE
  end
end
