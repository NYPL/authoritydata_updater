# frozen_string_literal: true

require "optparse"
require "pry"
require "tty-command"
require "tty-progressbar"
require "tty-spinner"
require "json"
require "set"
require "zlib"

REGEX_RDF_TRIPPLES = /^(?<subject>.+?) <(?<predicate>.+?)> (?<object>.+?) \.$/  # matches each line in an RDF tripples file
REGEX_LITERAL_WITH_LANGUAGE = /^\"(?<value>.+)\"@(?<language>.\w+)$/            # e.g. "Abstract films"@en
REGEX_LITERAL = /^\"?(?<value>.+?)\"?$/                                         # literal without a language tag
REGEX_IRI = /^<(?<value>.+)>$/                                                  # e.g. <http://id.loc.gov/authorities/genreForms/gf2011026043>
REGEX_NOT_BLANK = /[^[:space:]]/                                                # equivalent to !ActiveSupport.blank?
REGEX_LOC_URI = /^https?:\/\/.*\.loc.gov/

PROGRESS_BAR_FORMAT = "[:bar] [:current/:total] [:percent] [ET::elapsed] [ETA::eta] [:rate/s]"
PROGRESS_BAR_FREQUENCY = 2 # updates per second
PROGRESS_BAR_UPDATE_DOC_COUNT = 5_000

DOCUMENTS_PER_TEMPFILE = 1_000_000

LOC_AUTHORITATIVE_LABEL = "http://www.loc.gov/mads/rdf/v1#authoritativeLabel"
LOC_ADMIN_METADATA = "http://www.loc.gov/mads/rdf/v1#adminMetadata"
LOC_RECORD_STATUS = "http://id.loc.gov/ontologies/RecordInfo#recordStatus"
LOC_STATUS_DEPRECATED = '"deprecated"^^<http://www.w3.org/2001/XMLSchema#string>'

W3_RDF_LABEL = "http://www.w3.org/2000/01/rdf-schema#label"
W3_PREF_LABEL = "http://www.w3.org/2004/02/skos/core#prefLabel"
W3_ALT_LABEL = "http://www.w3.org/2004/02/skos/core#altLabel"
W3_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

# predicates that occur a single time per subject
SINGULAR_PREDICATES = [
  LOC_ADMIN_METADATA,
  LOC_RECORD_STATUS,
  LOC_AUTHORITATIVE_LABEL,
  W3_RDF_LABEL,
].freeze

# predicates that may occur multiple times per subject
MULTI_PREDICATES = [
  W3_TYPE,
  W3_ALT_LABEL,
  W3_PREF_LABEL,
].freeze

ALL_PREDICATES = (SINGULAR_PREDICATES + MULTI_PREDICATES).freeze

TERM_TYPE_MAPPING = {
  "http://www.loc.gov/mads/rdf/v1#Topic" => "topic",
  "http://www.loc.gov/mads/rdf/v1#Geographic" => "geographic",
  "http://www.loc.gov/mads/rdf/v1#PersonalName" => "name_personal",
  "http://www.loc.gov/mads/rdf/v1#ComplexSubject" => "complex_subject",
  "http://www.loc.gov/mads/rdf/v1#CorporateName" => "name_corporate",
  "http://www.loc.gov/mads/rdf/v1#GenreForm" => "genreform",
  "http://www.loc.gov/mads/rdf/v1#Temporal" => "temporal",
  "http://www.loc.gov/mads/rdf/v1#NameTitle" => "name_title",
  "http://www.loc.gov/mads/rdf/v1#Title" => "title",
  "http://www.loc.gov/mads/rdf/v1#ConferenceName" => "name_conference",
}.freeze

VOCABULARIES = {
  lcgft: {
    authority_name: "Library of Congress Genre/Form Terms for Library and Archival Materials",
    term_type: "genreform",
  },
  lctgm: {
    authority_name: "Thesaurus for Graphic Materials",
    term_type: "concept",
  },
  lcsh: {
    authority_name: "Library of Congress subject headings",
  },
  naf: {
    authority_name: "LC/NACO authority file",
  },
  aat: {
    authority_name: "Art and Architecture Thesaurus",
    term_type: "concept",
  },
}.freeze

parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{File.basename($0)} [options]"

  opts.on("-s", "--source [SOURCE]", String, "Path or URL to vocabulary file")
  opts.on("-v", "--vocabulary [VOCABULARY]", String, "Vocabulary type")
  opts.on("-o", "--output [OUTPUT]", String, "Output file (optional)")
end

options = {}
parser.parse!(into: options)

if options[:source] !~ REGEX_NOT_BLANK
  # Require --source option
  puts "You need to supply a path or URL to the vocabulary file"
  puts parser
  exit
end

if options[:vocabulary] !~ REGEX_NOT_BLANK
  # Require --vocabulary option
  puts "You need to supply the vocabulary type"
  puts parser
  exit
elsif !VOCABULARIES.keys.map(&:to_s).include?(options[:vocabulary])
  puts "Invalid vocabulary type. Must be one of:"
  puts VOCABULARIES.keys.join(", ")
  exit
end

AUTHORITY_CODE = options[:vocabulary].to_s
VOCABULARY = VOCABULARIES[options[:vocabulary].to_sym]

if options[:output] !~ REGEX_NOT_BLANK
  source_dir = File.dirname(options[:source])
  source_file_no_ext = File.basename(options[:source], File.extname(options[:source]))
  options[:output] = File.join(source_dir, "#{source_file_no_ext}.json")
end

def parse_value(value)
  if match = value.match(REGEX_LITERAL_WITH_LANGUAGE)
    return match[:language] == "en" ? match[:value] : nil
  elsif match = value.match(REGEX_IRI)
    return match[:value]
  elsif match = value.match(REGEX_LITERAL)
    return match[:value]
  else
    raise "Unable to parse RDF value: #{value}"
  end
end

total_lines = 0
TTY::Spinner.new("Counting lines... :spinner").run do |spinner|
  cmd = TTY::Command.new(printer: :null)
  out, err = cmd.run("wc -l #{options[:source]}")
  total_lines = out.split.first.to_i
end

puts "Sorting into temp files..."
sorting_bar = TTY::ProgressBar.new(PROGRESS_BAR_FORMAT, total: total_lines, frequency: PROGRESS_BAR_FREQUENCY)
line_count = 0
matching_line_count = 0
tempfiles = []
bucket = []
DEPRECATED_METADATA_NODES = Set.new

def dump_bucket_to_tmp_file(bucket)
  bucket.sort!

  tempfile = Tempfile.new
  zipfile = Zlib::GzipWriter.wrap(tempfile)

  bucket.each do |subject, line|
    zipfile << line
  end
  zipfile.close

  tempfile
end

File.open(options[:source], "r").each do |line|
  if matches = line.match(REGEX_RDF_TRIPPLES)
    if bucket.length > DOCUMENTS_PER_TEMPFILE
      tempfiles << dump_bucket_to_tmp_file(bucket)
      bucket = []
    end

    if matches[:predicate] == LOC_RECORD_STATUS && matches[:object] == LOC_STATUS_DEPRECATED
      DEPRECATED_METADATA_NODES << matches[:subject]
    end

    bucket << [matches[:subject], line]
    matching_line_count += 1
  end

  line_count += 1
  sorting_bar.advance(PROGRESS_BAR_UPDATE_DOC_COUNT) if line_count % PROGRESS_BAR_UPDATE_DOC_COUNT == 0
end

tempfiles << dump_bucket_to_tmp_file(bucket) if bucket.any?
sorting_bar.finish

puts "Sorted into #{tempfiles.size} temp files"

puts "Merging into single file..."

tempfile_readers = tempfiles.map{ |f| Zlib::GzipReader.new(open(f.path)) }

heads = tempfile_readers.each_with_index.map do |tempfile, i|
  [tempfile.readline, i]
end
heads.sort!

mergefile = Tempfile.new
merging_bar = TTY::ProgressBar.new(PROGRESS_BAR_FORMAT, total: matching_line_count, frequency: PROGRESS_BAR_FREQUENCY)

merge_line_count = 0
while heads.any?
  next_line, file_num = heads[0]
  mergefile << next_line

  begin
    heads[0] = [tempfile_readers[file_num].readline, file_num]
    heads.sort!
  rescue EOFError
    heads.delete_if{ |value, n| n == file_num }
    tempfile_readers[file_num].close
    tempfiles[file_num].unlink
    tempfiles[file_num].close
  end

  merge_line_count += 1
  merging_bar.advance(PROGRESS_BAR_UPDATE_DOC_COUNT) if merge_line_count % PROGRESS_BAR_UPDATE_DOC_COUNT == 0
end

merging_bar.finish

puts "Created sorted temp file"

puts "Generating Solr docs..."

mergefile.rewind
outfile = File.open(options[:output], "w")
progress = 0
generated_doc_count = 0 # TODO: doesn't incriment
subject_data = nil

def write_solr_doc(subject_data, outfile, generated_doc_count)
  return if subject_data[:subject].start_with?("_") # bnode
  return if subject_data[:authority_code] == "lcsh" && !(subject_data[:subject] =~ REGEX_LOC_URI)
  return if DEPRECATED_METADATA_NODES.include?(subject_data[LOC_ADMIN_METADATA])

  term = nil
  if subject_data.include?(LOC_AUTHORITATIVE_LABEL)
    term = subject_data[LOC_AUTHORITATIVE_LABEL]
  elsif subject_data.include?(W3_PREF_LABEL)
    term = subject_data[W3_PREF_LABEL].first
  elsif subject_data.include?(W3_RDF_LABEL)
    term = subject_data[W3_RDF_LABEL]
  end
  return unless term

  term_type = VOCABULARY[:term_type]
  if !term_type
    # this vocabulary does not have a set term type, look it up for this document
    document_types = subject_data[W3_TYPE]
    if document_types
      TERM_TYPE_MAPPING.each do |term_type_iri, value|
        if document_types.include?(term_type_iri)
          term_type = value
          break
        end
      end
    end
  end
  return unless term_type

  return if AUTHORITY_CODE == "lcsh" && term_type == "complex_subject"

  record_id = File.basename(subject_data[:subject])

  doc = {
    uri: subject_data[:subject],
    term: term,
    term_idx: term,
    term_type: term_type,
    record_id: record_id,
    language: "en",
    authority_code: AUTHORITY_CODE,
    authority_name: VOCABULARY[:authority_name],
    unique_id: "#{AUTHORITY_CODE}_#{record_id}",
    alternate_term: subject_data[W3_ALT_LABEL]&.to_a,
    alternate_term_idx: subject_data[W3_ALT_LABEL]&.to_a,
  }

  outfile.puts(doc.to_json)
  generated_doc_count += 1
end

bar = TTY::ProgressBar.new(PROGRESS_BAR_FORMAT, total: matching_line_count, frequency: PROGRESS_BAR_FREQUENCY)
mergefile.each do |line|
  matches = line.match(REGEX_RDF_TRIPPLES)

  if ALL_PREDICATES.include?(matches[:predicate])
    subject = parse_value(matches[:subject])

    if subject_data.nil?
      # first document encountered, happens only once
      subject_data = {subject: subject}
    elsif subject_data[:subject] != subject
      # new subject, write the current one and start a new one
      write_solr_doc(subject_data, outfile, generated_doc_count)
      subject_data = {subject: subject}
    end

    predicate = parse_value(matches[:predicate])
    object = parse_value(matches[:object])

    if SINGULAR_PREDICATES.include?(predicate)
      subject_data[predicate] = object
    else
      subject_data[predicate] ||= Set.new
      subject_data[predicate] << object
    end
  end

  progress += 1
  bar.advance(PROGRESS_BAR_UPDATE_DOC_COUNT) if progress % PROGRESS_BAR_UPDATE_DOC_COUNT == 0
end

write_solr_doc(subject_data, outfile, generated_doc_count)
bar.finish

puts "Generated #{generated_doc_count} Solr docs"

mergefile.unlink
mergefile.close

puts "Done."
