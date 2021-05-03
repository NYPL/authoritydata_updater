# frozen_string_literal: true

require "digest"
require "optparse"
require "progress_bar"

REGEX_RDF_TRIPPLES = /^(?<subject>.+?) <(?<predicate>.+?)> (?<object>.+?) \.$/  # matches each line in an RDF tripples file
REGEX_LITERAL_WITH_LANGUAGE = /^\"(?<value>.+)\"@(?<language>.\w+)$/            # e.g. "Abstract films"@en
REGEX_LITERAL = /^\"?(?<value>.+?)\"?$/                                         # literal without a language tag
REGEX_IRI = /^<(?<value>.+)>$/                                                  # e.g. <http://id.loc.gov/authorities/genreForms/gf2011026043>
REGEX_NOT_BLANK = /[^[:space:]]/                                                # equivalent to !ActiveSupport.blank?

READ_FILE_BATCH_SIZE = 10000

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

puts "Source: #{options[:source]}"
print "\tcounting lines... "
total_lines = %x{wc -l #{options[:source]}}.split.first.to_i
puts total_lines
bar = ProgressBar.new(total_lines)

File.open(options[:source], "r") do |file|
  file.lazy.each_slice(READ_FILE_BATCH_SIZE) do |batch|
    batch.each do |line|
      if matches = line.match(REGEX_RDF_TRIPPLES)
        bucket = Digest::MD5.hexdigest(matches[:subject]).to_i(16) % options[:buckets]
        output_files[bucket].write(line)
      end
    end

    bar.increment!(batch.size)
  end
end

output_files.each do |file|
  file.close
end

puts "Finished."
