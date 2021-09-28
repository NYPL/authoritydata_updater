# frozen_string_literal: true

require "optparse"
require "rsolr"
require "tty-progressbar"
require "pry"

PROGRESS_BAR_FORMAT = "[:bar] [:current/:total] [:percent] [ET::elapsed] [ETA::eta] [:rate/s]"
REGEX_NOT_BLANK = /[^[:space:]]/
DOCS_PER_PAGE = 10000

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename($0)} [options]"

  opts.on("-d", "--solr_destination [SOLR_DESTINATION]", String, "URL to Solr")
  opts.on("-u", "--solr_username [USERNAME]", String, "Solr username (optional)")
  opts.on("-p", "--solr_password [PASSWORD]", String, "Solr password (optional)")
  opts.on("-a", "--authority_code [AUTHORITY_CODE]", "Authority code (optional)")
  opts.on("-o", "--output [OUTPUT]", String, "Output file")
end

options = {}
parser.parse!(into: options)

if options[:output] !~ REGEX_NOT_BLANK
  puts "You need to supply a path to the output file"
  puts parser
  exit
end

SOLR_USERNAME = options[:solr_username]
SOLR_PASSWORD = options[:solr_password]
SOLR = RSolr.connect(url: options[:solr_destination])

outfile = File.open(options[:output], "w")
solr_params = {q: "*:*"}

if options[:authority_code]
  solr_params[:q] = "authority_code:#{options[:authority_code]}"
end

current_page = 1
result = nil
bar = nil

while(current_page == 1 || result["response"]["docs"].size > 0) do
  result = SOLR.paginate(current_page, DOCS_PER_PAGE, "select", params: solr_params)

  if bar.nil?
    total_pages = (result["response"]["numFound"] / DOCS_PER_PAGE.to_f).ceil
    bar = TTY::ProgressBar.new(PROGRESS_BAR_FORMAT, total: total_pages)
  end

  bar.advance

  result["response"]["docs"].each do |doc|
    outfile.puts(doc.to_json)
  end

  current_page += 1
end
