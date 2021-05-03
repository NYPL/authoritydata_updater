# frozen_string_literal: true

require "digest"
require "optparse"
require "rdf"
include RDF

RDF_SUBJECT_PATTERN = /(.+?)\s/
BATCH_SIZE = 10000

options = {}
opt_parser = OptionParser.new do |opts|
  opts.on("-s", "--source [SOURCE]", String, "Path to source file")
  opts.on("-b", "--buckets [BUCKETS]", Integer, "Split into [BUCKETS] buckets")

  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end

opt_parser.parse!(into: options)

if options[:source].nil?
  puts "You need to supply a path to the source file"
  puts opt_parser
  exit
end

if options[:buckets].nil?
  puts "You need to supply the number of buckets"
  puts opt_parser
  exit
end

output_files = 1.upto(options[:buckets]).map do |n|
  File.open("#{options[:source]}.#{n}", "w")
end

statements = 0
File.open(options[:source], "r") do |input_file|
  input_file.lazy.each_slice(BATCH_SIZE) do |lines|
    statements += lines.size
    puts "Processing line #{statements}..."

    lines.each do |line|
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
