require 'optparse'
require File.join(__dir__, 'lib', 'vocabulary_parser')

options = {}
SUPPORTED_VOCABULARIES = ['carriers'].freeze

opt_parser = OptionParser.new do |opts|
  opts.banner = 'Usage: ruby authoritydata_updater.rb [options] \n Exaxmple: ruby authoritydata_updater.rb --vocabulary carriers --source http://example.com/authority-file.xml --solrUrl http://solr.example.com:8983/solr'
  opts.separator ''
  opts.separator "Supported vocabularies: #{SUPPORTED_VOCABULARIES.join(', ')}"
  opts.separator ''

  opts.on('-v=', '--vocabulary', 'The type of vocabularies in the source file') do |vocabulary|
    options[:vocabulary] = vocabulary
  end

  opts.on('-s=', '--source', 'Path or URL to vocabulary file') do |source|
    options[:source] = source
  end

  opts.on('-u=', '--solrUrl', 'Path or URL to SOLR core') do |solr_url|
    options[:solr_url] = solr_url
  end

  opts.on_tail('-h', '--help', 'Show this message') do
    puts opts
    exit
  end
end

opt_parser.parse!

# TODO: These's probably a nicer way to raise these exceptions or move this
# into VocabularyParser's initializer
unless SUPPORTED_VOCABULARIES.include?(options[:vocabulary])
  puts "You need to use a supported vocabulary like: #{SUPPORTED_VOCABULARIES.join(', ')}."
  puts opt_parser
  exit
end

if options[:source].nil?
  puts 'You need to supply a path or URL to the vocabulary file'
  puts opt_parser
  exit
end

if options[:solr_url].nil?
  puts 'You need to supply a valid solr url to post docs to'
  puts opt_parser
  exit
end

parser = VocabularyParser.new(vocabulary: options[:vocabulary], source: options[:source], solr_url: options[:solr_url])
parser.parse!
