# frozen_string_literal: true

# USAGE: ruby ./push_to_solr file.nt.json

require 'nypl_log_formatter'
require 'optparse'
require File.join(__dir__, 'lib', 'solr_handler')

DOCS_PER_POST = 10000

@options = {}

opt_parser = OptionParser.new do |opts|
  opts.banner = 'Usage: ruby post_to_solr.rb --file lcgft_12345.json --solrUrl $SOLR_URL --username $USERNAME --password $PASSWORD'

  opts.on('-f=', '--file', 'The JSON file containing documents. (Output from authoritydata_updater.rb)') do |source|
    @options[:input_file] = source
  end

  opts.on('-s=', '--solrUrl', 'Path or URL to SOLR core') do |solr_url|
    @options[:solr_url] = solr_url
  end

  opts.on('-u=', '--username', 'Solr username') do |username|
    @options[:solr_username] = username
  end

  opts.on('-p=', '--password', 'Solr password') do |password|
    @options[:solr_password] = password
  end

  opts.on_tail('-n=', '--line-number', 'Start parsing on line (helpful if restarting)') do |start_at_line|
    @options[:start_at_line] = start_at_line.to_i
  end

  opts.on_tail('-h', '--help', 'Show this message') do
    puts opts
    exit
  end

end

opt_parser.parse!

SOLR_USERNAME = @options[:solr_username]
SOLR_PASSWORD = @options[:solr_password]

def post_to_solr(documents)
  puts "POSTing #{documents.length} documents to Solr"
  documents_as_hashes = documents.map { |document| JSON.parse(document) }
  response = SolrHandler.send_docs_to_solr(@options[:solr_url], documents_as_hashes)
end

document_buffer = []

File.open(@options[:input_file], 'r').each_with_index do |line, i|

  if @options[:start_at_line] && i < @options[:start_at_line]
    next
  end

  if i == 0
     authority_code = JSON.parse(line)['authority_code']
     throw "can't delete, won't continue" unless authority_code
     SolrHandler.delete_by_query(@options[:solr_url], "authority_code:#{authority_code}")
  end

  document_buffer << line
  if document_buffer.length == DOCS_PER_POST
    puts "POSTing at line #{i}"
    post_to_solr(document_buffer)
    document_buffer = []
  end
end

puts 'done reading file, flushing buffer'
post_to_solr(document_buffer) unless document_buffer.empty?
