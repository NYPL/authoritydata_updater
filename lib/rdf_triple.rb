# frozen_string_literal: true

REGEX_RDF_TRIPPLES = /^(?<subject>.+?) <(?<predicate>.+?)> (?<object>.+?) \.$/

class RdfTriple
  attr_reader :subject, :predicate, :object

  def self.parse(triple_string)
    matches = triple_string.match(REGEX_RDF_TRIPPLES)
    raise ArgumentError unless matches

    new(matches[:subject], matches[:predicate], matches[:object])
  end

  def initialize(subject, predicate, object)
    @subject = subject
    @predicate = predicate
    @object = object
  end
end
