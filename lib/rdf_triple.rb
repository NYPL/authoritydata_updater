# frozen_string_literal: true

REGEX_RDF_TRIPPLES = /^(?<subject>.+?) <(?<predicate>.+?)> (?<object>.+?) \.$/
REGEX_LITERAL_WITH_LANGUAGE = /^\"(?<value>.+)\"@(?<language>.\w+)$/
REGEX_LITERAL = /^\"?(?<value>.+?)\"?$/
REGEX_IRI = /^<(?<value>.+)>$/

class RdfTriple
  class ParseError < StandardError; end;

  attr_reader :subject, :predicate, :object

  def self.parse(triple_string)
    matches = triple_string.match(REGEX_RDF_TRIPPLES)
    raise ParseError unless matches

    subject = parse_value(matches[:subject])
    predicate = parse_value(matches[:predicate])
    object = parse_value(matches[:object])

    new(subject, predicate, object)
  end

  def initialize(subject, predicate, object)
    @subject = subject
    @predicate = predicate
    @object = object
  end

  private

  def self.parse_value(value)
    if match = value.match(REGEX_LITERAL_WITH_LANGUAGE)
      return match[:language] == "en" ? match[:value] : nil
    elsif match = value.match(REGEX_IRI)
      return match[:value]
    elsif match = value.match(REGEX_LITERAL)
      return match[:value]
    else
      raise "Unable to parse RDF value: #{value}"
    end
  end
end
