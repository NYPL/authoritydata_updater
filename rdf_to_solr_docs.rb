#!/usr/bin/env ruby

lib_dir = File.expand_path(File.join(File.dirname(__FILE__), "lib"))
$LOAD_PATH.unshift(lib_dir)

require "optparse"
require "solr_doc_generator"

REGEX_NOT_BLANK = /[^[:space:]]/

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename($0)} [options]"

  opts.on("-v", "--vocabulary [VOCABULARY]", String, "Vocabulary type")
  opts.on("-s", "--source [SOURCE]", String, "Path or URL to vocabulary file")
  opts.on("-o", "--output [OUTPUT]", String, "Output file (optional)")
end

options = {}
parser.parse!(into: options)

if options[:vocabulary] !~ REGEX_NOT_BLANK
  puts "You need to supply the vocabulary type"
  puts parser
  exit
else
  options[:vocabulary] = options[:vocabulary].to_sym
end

if options[:source] !~ REGEX_NOT_BLANK
  puts "You need to supply a path to the source file"
  puts parser
  exit
end

if options[:output] !~ REGEX_NOT_BLANK
  # default output file if none is provided
  source_dir = File.dirname(options[:source])
  source_file_no_ext = File.basename(options[:source], File.extname(options[:source]))
  options[:output] = File.join(source_dir, "#{source_file_no_ext}.json")
end

generator = SolrDocGenerator.new(
  options[:vocabulary],
  options[:source],
  options[:output],
  true
).run
