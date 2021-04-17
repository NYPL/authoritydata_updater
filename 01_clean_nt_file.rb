# frozen_string_literal: true

require "digest"
require "optparse"
require "rdf"
include RDF

# N-Triples files are FULL of statements we don't care about.
# Statements that we never use to post info to Solr.
# This file takes an input file and outputs a file with only relevant statements
WORTHWHILE_PREDICATES = [
  "http://www.w3.org/1999/02/22-rdf-syntax-ns#type",
  "http://www.loc.gov/mads/rdf/v1#adminMetadata",
  "http://id.loc.gov/ontologies/RecordInfo#recordStatus",
  "http://www.loc.gov/mads/rdf/v1#authoritativeLabel",
  "http://www.w3.org/2004/02/skos/core#prefLabel",
  "http://www.w3.org/2004/02/skos/core#altLabel",
  "http://www.w3.org/2000/01/rdf-schema#label",
].freeze

RDF_SUBJECT_PATTERN = /(.+?)\s/
BATCH_SIZE = 10000

options = {}
opt_parser = OptionParser.new do |opts|
  opts.banner = "Usage: ruby 01_clean_nt_file.rb [options]"
  opts.separator "Example: ruby 01_clean_nt_file.rb --source data/loc/lcnaf.madsrdf.nt --buckets 8 --output data/nypltemp/lcnaf.cleaned.nt"

  opts.on("-s", "--source [SOURCE]", String, "Path or URL to vocabulary file")
  opts.on("-b", "--buckets [BUCKETS]", Integer, "Split into [BUCKETS] buckets")
  opts.on("-o", "--output [OUTPUT]", String, "Output file")

  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end

opt_parser.parse!(into: options)

if options[:source].nil?
  puts "You need to supply a path or URL to the vocabulary file"
  puts opt_parser
  exit
end

options[:buckets] ||= 1
options[:output] ||= "output.nt"

output_file_names = if options[:buckets] == 1
    [options[:output]]
  else
    1.upto(options[:buckets]).map { |n| "#{options[:output]}.#{n}" }
  end

output_files = output_file_names.map do |filename|
  File.open(filename, "w")
end


statements = 0
File.open(options[:source], "r") do |input_file|
  input_file.lazy.each_slice(BATCH_SIZE) do |lines|
    statements += lines.size
    puts "Processing line #{statements}..."

    lines.each do |line|
      next unless WORTHWHILE_PREDICATES.any? { |predicate| line.include?(predicate) }

      match = line.match(RDF_SUBJECT_PATTERN)
      next unless match && match[1]
      subject = match[1]

      # determine the bucket for this subject by taking a MD5 hash of the subject URI,
      # converting that to an integer, modulo the number of buckets
      bucket = Digest::MD5.hexdigest(subject).to_i(16) % options[:buckets]

      output_files[bucket].write(line)
    end
  end
end

output_files.each do |file|
  file.close
end

puts "Finished."
