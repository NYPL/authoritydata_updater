# frozen_string_literal: true

class AuthoritativeRecord
  attr_reader :subject

  def initialize(subject)
    @subject = subject
    @data = {}
  end

  def add_triple(triple)
    if triple.singular_predicate?
      @data[triple.predicate] = triple.object
    elsif triple.multi_predicate?
      @data[triple.predicate] ||= Set.new
      @data[triple.predicate] << triple.object
    end
  end

  def term
    if @data.include?(LOC_AUTHORITATIVE_LABEL)
      @data[LOC_AUTHORITATIVE_LABEL]
    elsif @data.include?(W3_PREF_LABEL)
      @data[W3_PREF_LABEL].first
    elsif @data.include?(W3_RDF_LABEL)
      @data[W3_RDF_LABEL]
    end
  end

  def as_json(options={})
    {
      uri: @subject,
      term: term
    }
  end

  def to_json(*options)
    as_json(*options).to_json(*options)
  end
end
