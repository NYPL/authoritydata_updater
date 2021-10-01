require "rdf_triple"

class TestRdfTriple < Test::Unit::TestCase
  def test_parsing
    triple_string = "<subject> <predicate> <object> ."
    triple = RdfTriple.parse(triple_string)
    assert_equal "subject", triple.subject
    assert_equal "predicate", triple.predicate
    assert_equal "object", triple.object
  end

  def test_parse_invalid
    assert_raises RdfTriple::ParseError do
      RdfTriple.parse("this is an invalid rdf line")
    end
  end

  def test_valid_predicate
    triple_string = "<subject> <#{RdfTriple::LOC_AUTHORITATIVE_LABEL}> <object> ."
    triple = RdfTriple.parse(triple_string)
    assert_true triple.valid_predicate?
    assert_equal RdfTriple::LOC_AUTHORITATIVE_LABEL, triple.predicate
  end

  def test_invalid_predicate
    triple_string = "<subject> <invalid_predicate> <object> ."
    triple = RdfTriple.parse(triple_string)
    assert_false triple.valid_predicate?
  end

  def test_parse_value_literal
    triple_string = "<subject> <predicate> \"Abraham Lincoln\" ."
    triple = RdfTriple.parse(triple_string)
    assert_equal "Abraham Lincoln", triple.object
  end

  def test_parse_value_literal_with_language
    triple_string = "<subject> <predicate> \"Abraham Lincoln\"@en ."
    triple = RdfTriple.parse(triple_string)
    assert_equal "Abraham Lincoln", triple.object
  end

  def test_parse_value_literal_with_language_non_english
    triple_string = "<subject> <predicate> \"livre\"@fr ."
    triple = RdfTriple.parse(triple_string)
    assert_equal nil, triple.object
  end

  def test_parse_value_literal_with_diacritics
    triple_string = "<subject> <predicate> \"Miranda \\u00C1lvarez\" ."
    triple = RdfTriple.parse(triple_string)
    assert_equal "Miranda Álvarez", triple.object
  end

  def test_parse_value_iri
    triple_string = "<subject> <predicate> <some_iri> ."
    triple = RdfTriple.parse(triple_string)
    assert_equal "some_iri", triple.object
  end
end
