# frozen_string_literal: true

require "optparse"
require "tty-command"
require "tty-progressbar"
require "tty-spinner"
require "rsolr"

require "pry"

PROGRESS_BAR_FORMAT = "[:bar] [:current/:total] [:percent] [ET::elapsed] [ETA::eta] [:rate/s]"
PROGRESS_BAR_FREQUENCY = 2
DOCS_PER_BATCH = 10000
#DOCS_PER_BATCH = 1


options = {}

opt_parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename($0)} [options]"

  opts.on("-s", "--source [SOURCE]", String, "The JSON file containing documents. (Output from rds_to_solr_docs.rb)")
  opts.on("-d", "--solr_destination [SOLR_DESTINATION]", String, "URL to Solr")
  opts.on("-u", "--solr_username [USERNAME]", String, "Solr username (optional)")
  opts.on("-p", "--solr_password [PASSWORD]", String, "Solr password (optional)")
  opts.on("-a", "--append", "Do not delete existing documents for this authority first")
end

opt_parser.parse!(into: options)

SOLR_USERNAME = options[:solr_username]
SOLR_PASSWORD = options[:solr_password]
SOLR = RSolr.connect(url: options[:solr_destination])

total_lines = 0
TTY::Spinner.new("Counting documents... :spinner").run do |spinner|
  cmd = TTY::Command.new(printer: :null)
  out, err = cmd.run("wc -l #{options[:source]}")
  total_lines = out.split.first.to_i
end

puts "\t#{total_lines} documents in source file"

unless options[:append]
  first_line = File.open(options[:source], "r").first
  first_document = JSON.parse(first_line)
  authority_code = first_document['authority_code']
  puts "Deleting documents where authority_code=#{authority_code}"
  SOLR.delete_by_query("authority_code:\"#{authority_code}\"")
  SOLR.commit
  puts "\tdone"
end

batches = total_lines / DOCS_PER_BATCH
batches += 1 if total_lines % DOCS_PER_BATCH > 0
puts "Posting documents to Solr in #{batches} batches of #{DOCS_PER_BATCH} documents..."

def post_batch(documents)
  return unless documents.any?
  begin
    SOLR.add(documents)
    SOLR.commit
  rescue StandardError => e
    puts "Got error: #{e.inspect}"
    exit 1
  end
end

batch = []
batches_complete = 0
bar = TTY::ProgressBar.new(PROGRESS_BAR_FORMAT, total: batches, frequency: PROGRESS_BAR_FREQUENCY)

File.open(options[:source], "r").each do |line|
  document = JSON.parse(line)
  batch << document

  if batch.length >= DOCS_PER_BATCH
    post_batch(batch)
    batch = []
    bar.advance
  end
end

post_batch(batch)
bar.finish

puts "Done."
