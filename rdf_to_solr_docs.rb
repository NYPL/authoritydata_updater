# frozen_string_literal: true

require "optparse"
require "pry"
require "progress_bar"
require "json"
require "dalli"
require "set"

REGEX_RDF_TRIPPLES = /^(?<subject>.+?) <(?<predicate>.+?)> (?<object>.+?) \.$/  # matches each line in an RDF tripples file
REGEX_LITERAL_WITH_LANGUAGE = /^\"(?<value>.+)\"@(?<language>.\w+)$/            # e.g. "Abstract films"@en
REGEX_LITERAL = /^\"?(?<value>.+?)\"?$/                                         # literal without a language tag
REGEX_IRI = /^<(?<value>.+)>$/                                                  # e.g. <http://id.loc.gov/authorities/genreForms/gf2011026043>
REGEX_NOT_BLANK = /[^[:space:]]/                                                # equivalent to !ActiveSupport.blank?

LOC_AUTHORITATIVE_LABEL = "http://www.loc.gov/mads/rdf/v1#authoritativeLabel"
LOC_ADMIN_METADATA = "http://www.loc.gov/mads/rdf/v1#adminMetadata"
LOC_RECORD_STATUS = "http://id.loc.gov/ontologies/RecordInfo#recordStatus"

W3_RDF_LABEL = "http://www.w3.org/2000/01/rdf-schema#label"
W3_PREF_LABEL = "http://www.w3.org/2004/02/skos/core#prefLabel"
W3_ALT_LABEL = "http://www.w3.org/2004/02/skos/core#altLabel"
W3_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"

# labels used to identify terms vary by vocabulary,
# look them up in this order
TERM_LABELS = [
  LOC_AUTHORITATIVE_LABEL,
  W3_PREF_LABEL,
  W3_RDF_LABEL,
].freeze

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
  opts.on("-r", "--[no-]reset [RESET]", TrueClass, "Reset memcache (default: TRUE)")
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

vocabulary = VOCABULARIES[options[:vocabulary].to_sym]

if options[:output] !~ REGEX_NOT_BLANK
  # TODO: output to stdout instead?
  source_dir = File.dirname(options[:source])
  source_file_no_ext = File.basename(options[:source], File.extname(options[:source]))
  options[:output] = File.join(source_dir, "#{source_file_no_ext}.json")
end

options[:reset] = options[:reset].nil? ? true : !!options[:reset]

def parse_value(value)
  if match = value.match(REGEX_LITERAL_WITH_LANGUAGE)
    return match[:language] == "en" ? match[:value] : nil
  elsif match = value.match(REGEX_IRI)
    return match[:value]
  elsif match = value.match(REGEX_LITERAL)
    return match[:value]
  else
    binding.pry
  end
end

puts "Vocabulary: #{options[:vocabulary]}"
puts "Source: #{options[:source]}"
print "\tcounting lines... "
total_lines = %x{wc -l #{options[:source]}}.split.first.to_i
puts total_lines
puts "Output: #{options[:output]}"

all_subjects = Set.new

cache = Dalli::Client.new("localhost:11211", {})

options[:reset] = options[:reset].nil? ? true : !!options[:reset]
if options[:reset]
  puts "Flushing memcached"
  cache.flush_all
end

puts "\nParsing source file..."
bar = ProgressBar.new(total_lines)

File.open(options[:source], "r").each do |line|
  if matches = line.match(REGEX_RDF_TRIPPLES)
    next unless ALL_PREDICATES.include?(matches[:predicate])

    subject = parse_value(matches[:subject])
    subject_values = cache.get(subject) || {}
    predicate = parse_value(matches[:predicate])
    object = parse_value(matches[:object])

    if SINGULAR_PREDICATES.include?(predicate)
      next if subject_values.has_key?(predicate)
      subject_values[predicate] = object
    else
      if subject_values.has_key?(predicate)
        next if subject_values[predicate].include?(object)
        subject_values[predicate] << object
      else
        subject_values[predicate] = [object]
      end
    end

    all_subjects << subject
    cache.set(subject, subject_values)
  end

  bar.increment!
end

deprecated_count = 0

puts "\n\nGenerating solr docs..."

File.open(options[:output], "w") do |outfile|
  all_subjects.each do |subject|
    next if subject.start_with?("_") # bnode

    predicate_to_object_mapping = cache.get(subject)

    status = "unknown"
    metadata_node_name = predicate_to_object_mapping[LOC_ADMIN_METADATA]
    if metadata_node_name
      metadata_node = cache.get(metadata_node_name) || {}
      status = metadata_node[LOC_RECORD_STATUS]
    end

    if status == "deprecated"
      deprecated_count += 1
      next
    end

    term = nil

    TERM_LABELS.each do |term_label|
      if predicate_to_object_mapping.include?(term_label)
        term = predicate_to_object_mapping[term_label]
        break
      end
    end

    next unless term

    term_type = vocabulary["term_type"]
    if !term_type
      # this vocabulary does not have a set term type, look it up for this document
      document_types = predicate_to_object_mapping[W3_TYPE]
      if document_types
        TERM_TYPE_MAPPING.each do |term_type_iri, value|
          if document_types.include?(term_type_iri)
            term_type = value
            break
          end
        end
      end
    end

    next unless term_type

    record_id = File.basename(subject)

    doc = {
      uri: subject,
      term: term,
      term_idx: term,
      term_type: term_type,
      record_id: File.basename(subject),
      language: "en",
      authority_code: options[:vocabulary].to_s,
      authority_name: vocabulary[:authority_name],
      unique_id: "#{options[:vocabulary]}_#{record_id}",
      alternate_term: predicate_to_object_mapping[W3_ALT_LABEL],
      alternate_term_idx: predicate_to_object_mapping[W3_ALT_LABEL],
    }

    outfile.puts(doc.to_json)
  end
end

puts "Done."
