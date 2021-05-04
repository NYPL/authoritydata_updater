# frozen_string_literal: true

require "optparse"
require "pry"
require "tty-progressbar"
require "json"
require "dalli"
require "set"

REGEX_RDF_TRIPPLES = /^(?<subject>.+?) <(?<predicate>.+?)> (?<object>.+?) \.$/  # matches each line in an RDF tripples file
REGEX_LITERAL_WITH_LANGUAGE = /^\"(?<value>.+)\"@(?<language>.\w+)$/            # e.g. "Abstract films"@en
REGEX_LITERAL = /^\"?(?<value>.+?)\"?$/                                         # literal without a language tag
REGEX_IRI = /^<(?<value>.+)>$/                                                  # e.g. <http://id.loc.gov/authorities/genreForms/gf2011026043>
REGEX_NOT_BLANK = /[^[:space:]]/                                                # equivalent to !ActiveSupport.blank?

PROGRESS_BAR_FORMAT = "[:bar] [:current/:total] [:percent] [ET::elapsed] [ETA::eta] [:rate/s]"
PROGRESS_BAR_FREQUENCY = 10 # updates per second

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
  opts.on("-t", "--threads [THREADS]", Integer, "Number of threads (default: 2)")
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

options[:threads] ||= 2

# create temp files for each thread and immediately unlink them
# https://ruby-doc.org/stdlib-2.7.3/libdoc/tempfile/rdoc/Tempfile.html#method-i-unlink-label-Unlink-before-close
tempfiles = options[:threads].times.map do |thread_number|
  file = Tempfile.new
  file.unlink
  file
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

begin
  puts "Vocabulary: #{options[:vocabulary]}"
  puts "Source: #{options[:source]}"
  print "\tcounting lines... "
  total_lines = %x{wc -l #{options[:source]}}.split.first.to_i
  puts total_lines
  puts "Output: #{options[:output]}"

  puts "\nSplitting input file into #{tempfiles.size} temp file buckets..."
  bucket_progress = TTY::ProgressBar.new("#{PROGRESS_BAR_FORMAT}", total: total_lines, frequency: PROGRESS_BAR_FREQUENCY)

  File.open(options[:source], "r").each do |line|
    if matches = line.match(REGEX_RDF_TRIPPLES)
      bucket = Digest::MD5.hexdigest(matches[:subject]).to_i(16) % tempfiles.count
      tempfiles[bucket] << line
    end

    bucket_progress.advance
  end

  puts "\nProcessing each bucket into memcached..."

  cache = Dalli::Client.new("localhost:11211", {})
  cache.flush_all

  all_subjects = Set.new
  threads = []
  main_progress_bar = TTY::ProgressBar::Multi.new("total progress #{PROGRESS_BAR_FORMAT}", frequency: PROGRESS_BAR_FREQUENCY)
  thread_progress_bars = []

  options[:threads].times do |bucket|
    tempfile = tempfiles[bucket]
    tempfile.rewind

    bucket_lines = tempfile.each.count
    tempfile.rewind

    thread_progress_bars[bucket] = main_progress_bar.register("bucket #{bucket} #{PROGRESS_BAR_FORMAT}", total: bucket_lines, frequency: PROGRESS_BAR_FREQUENCY)

    threads[bucket] = Thread.new do
      tempfile.each do |line|
        if matches = line.match(REGEX_RDF_TRIPPLES)
          if ALL_PREDICATES.include?(matches[:predicate])
            subject = parse_value(matches[:subject])
            subject_values = cache.get(subject) || {}
            predicate = parse_value(matches[:predicate])
            object = parse_value(matches[:object])

            if SINGULAR_PREDICATES.include?(predicate)
              subject_values[predicate] = object
            else
              subject_values[predicate] ||= Set.new
              subject_values[predicate] << object
            end

            all_subjects << subject
            cache.set(subject, subject_values)
          end
        end

        thread_progress_bars[bucket].advance
      end
    end
  end

  threads.each { |t| t.join }

  puts "\nGenerating solr docs..."

  docs_progress = TTY::ProgressBar.new("#{PROGRESS_BAR_FORMAT}", total: all_subjects.count, frequency: PROGRESS_BAR_FREQUENCY)
  docs_generated = 0

  File.open(options[:output], "w") do |outfile|
    docs_progress.iterate(all_subjects) do |subject|
      next if subject.start_with?("_") # bnode
  
      predicate_to_object_mapping = cache.get(subject)
  
      status = "unknown"
      metadata_node_name = predicate_to_object_mapping[LOC_ADMIN_METADATA]
      if metadata_node_name
        metadata_node = cache.get(metadata_node_name) || {}
        status = metadata_node[LOC_RECORD_STATUS]
      end
  
      next if status == "deprecated"
  
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
      docs_generated += 1
    end
  end
  
  puts "\n\nGenerated #{docs_generated} Solr documents."
ensure
  tempfiles.each { |f| f.close! }
end
