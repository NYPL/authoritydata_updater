Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require 'optparse'
require File.join(__dir__, 'lib', 'vocabulary_parser')

options = {}
SUPPORTED_VOCABULARIES = ['rdacarriers', 'graphic_materials', 'genre_and_form', 'names', 'subjects'].freeze

opt_parser = OptionParser.new do |opts|
  opts.banner = 'Usage: ruby authoritydata_updater.rb [options] \n Exaxmple: ruby authoritydata_updater.rb --vocabulary genre_and_form --source ./authority-file.nt'
  opts.separator ''
  opts.separator "Supported vocabularies: #{SUPPORTED_VOCABULARIES.join(', ')}"
  opts.separator ''

  opts.on('-v=', '--vocabulary', 'The type of vocabularies in the source file') do |vocabulary|
    options[:vocabulary] = vocabulary
  end

  opts.on('-s=', '--source', 'Path or URL to vocabulary file') do |source|
    options[:source] = source
  end

  opts.on('-n=', '--start-on-line', "Start parsing on this line of the .nt file") do |line_number|
    options[:start_at_line] = line_number.to_i
  end

  opts.on('-d=', '--db-file', "Use an existing db file, probably used with -n because a previous run was interrupted") do |db_file_name|
    options[:db_file_name] = db_file_name
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

parser = VocabularyParser.new(vocabulary: options[:vocabulary], source: options[:source], solr_url: options[:solr_url], start_at_line: options[:start_at_line], db_file_name: options[:db_file_name])
parser.parse!
