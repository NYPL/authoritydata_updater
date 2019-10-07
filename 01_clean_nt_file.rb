# frozen_string_literal: true

# N-Triples files are FULL of statements we don't care about.
# Statements that we never use to post info to Solr.
# This file takes an input file and outputs a file with only relevant statements
WORTHWHILE_PREDICATES = [
  'http://www.w3.org/1999/02/22-rdf-syntax-ns#type',
  'http://www.loc.gov/mads/rdf/v1#adminMetadata',
  'http://id.loc.gov/ontologies/RecordInfo#recordStatus',
  'http://www.loc.gov/mads/rdf/v1#authoritativeLabel',
  'http://www.w3.org/2004/02/skos/core#prefLabel',
  'http://www.w3.org/2004/02/skos/core#altLabel',
  'http://www.w3.org/2000/01/rdf-schema#label'
].freeze

input_file = File.open(ARGV[0], 'r')
output_file = File.open(ARGV[1], 'w')
line_count = 0
input_file.each do |line|
  line_count += 1

  if WORTHWHILE_PREDICATES.any? { |predicate| line.include?(predicate) }
    output_file.puts(line)
  end

  puts "line #{line_count}" if line_count % 100_000 == 0
end
input_file.close
output_file.close
