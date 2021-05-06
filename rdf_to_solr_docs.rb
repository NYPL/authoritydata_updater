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
REGEX_LOC_URI = /^https?:\/\/.*\.loc.gov/

PROGRESS_BAR_FORMAT = "[:bar] [:current/:total] [:percent] [ET::elapsed] [ETA::eta] [:rate/s]"
PROGRESS_BAR_FREQUENCY = 5 # updates per second
PROGRESS_BAR_UPDATE_DOC_COUNT = 1000

LOC_AUTHORITATIVE_LABEL = "http://www.loc.gov/mads/rdf/v1#authoritativeLabel"
LOC_ADMIN_METADATA = "http://www.loc.gov/mads/rdf/v1#adminMetadata"
LOC_RECORD_STATUS = "http://id.loc.gov/ontologies/RecordInfo#recordStatus"

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
  split_lines = 0
  bucket_progress = TTY::ProgressBar.new("#{PROGRESS_BAR_FORMAT}", total: total_lines, frequency: PROGRESS_BAR_FREQUENCY)

  File.open(options[:source], "r").each do |line|
    if matches = line.match(REGEX_RDF_TRIPPLES)
      bucket = Digest::MD5.hexdigest(matches[:subject]).to_i(16) % tempfiles.count
      tempfiles[bucket] << line
      split_lines += 1
      bucket_progress.advance(PROGRESS_BAR_UPDATE_DOC_COUNT) if split_lines % PROGRESS_BAR_UPDATE_DOC_COUNT == 0
    end
  end

  bucket_progress.finish

  puts "\nProcessing each bucket into memcached..."

  cache = Dalli::Client.new("localhost:11211", { namespace: vocabulary })
  cache.flush_all

  all_subjects = Set.new
  threads = []
  main_progress_bar = TTY::ProgressBar::Multi.new("total progress #{PROGRESS_BAR_FORMAT}", frequency: PROGRESS_BAR_FREQUENCY)

  options[:threads].times do |bucket|
    tempfile = tempfiles[bucket]
    tempfile.rewind

    bucket_lines = tempfile.each.count
    tempfile.rewind

    threads[bucket] = Thread.new do
      thread_progress_bar = main_progress_bar.register("bucket #{bucket} #{PROGRESS_BAR_FORMAT}", total: bucket_lines, frequency: PROGRESS_BAR_FREQUENCY)
      thread_cache = Dalli::Client.new("localhost:11211", { namespace: vocabulary })
      linecount = 0
      tempfile.each do |line|
        if matches = line.match(REGEX_RDF_TRIPPLES)
          if ALL_PREDICATES.include?(matches[:predicate])
            subject = parse_value(matches[:subject])
            subject_values = thread_cache.get(subject) || {}
            predicate = parse_value(matches[:predicate])
            object = parse_value(matches[:object])

            if SINGULAR_PREDICATES.include?(predicate)
              subject_values[predicate] = object
            else
              subject_values[predicate] ||= Set.new
              subject_values[predicate] << object
            end

            all_subjects << subject
            thread_cache.set(subject, subject_values)
          end
        end

        linecount += 1
        thread_progress_bar.advance(PROGRESS_BAR_UPDATE_DOC_COUNT) if linecount % PROGRESS_BAR_UPDATE_DOC_COUNT == 0
      end

      thread_progress_bar.finish
    end
  end

  threads.each { |t| t.join }

  puts "\nGenerating solr docs..."

  docs_progress = TTY::ProgressBar.new("#{PROGRESS_BAR_FORMAT}", total: all_subjects.count, frequency: PROGRESS_BAR_FREQUENCY)
  docs_generated = 0

  authority_code = options[:vocabulary].to_s

  skipped_bnode = 0
  skipped_non_loc_uri = 0
  skipped_no_mapping = 0
  skipped_deprecated = 0
  skipped_no_term = 0
  first_no_term = true
  skipped_no_term_type = 0
  first_no_type = true
  skipped_complex_subject = 0

  File.open(options[:output], "w") do |outfile|
    docs_progress.iterate(all_subjects) do |subject|
      #next if subject.start_with?("_") # bnode
      if subject.start_with?("_") # bnode
        skipped_bnode += 1
        next
      end

      #next if authority_code == "lcsh" && !(subject =~ REGEX_LOC_URI)
      if authority_code == "lcsh" && !(subject =~ REGEX_LOC_URI)
        skipped_non_loc_uri += 1
        next
      end

      predicate_to_object_mapping = cache.get(subject)
      #next unless predicate_to_object_mapping
      unless predicate_to_object_mapping
        skipped_no_mapping += 1
        next
      end

      status = "unknown"
      metadata_node_name = predicate_to_object_mapping[LOC_ADMIN_METADATA]
      if metadata_node_name
        metadata_node = cache.get(metadata_node_name) || {}
        status = metadata_node[LOC_RECORD_STATUS]
      end

      #next if status == "deprecated"
      if status == "deprecated"
        skipped_deprecated += 1
        next
      end

      term = nil
      if predicate_to_object_mapping.include?(LOC_AUTHORITATIVE_LABEL)
        term = predicate_to_object_mapping[LOC_AUTHORITATIVE_LABEL]
      elsif predicate_to_object_mapping.include?(W3_PREF_LABEL)
        term = predicate_to_object_mapping[W3_PREF_LABEL].first
      elsif predicate_to_object_mapping.include?(W3_RDF_LABEL)
        term = predicate_to_object_mapping[W3_RDF_LABEL]
      end

      unless term
        skipped_no_term += 1
        if first_no_term
          first_no_term = false
          #binding.pry
        end

        next
      end

      term_type = vocabulary[:term_type]
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

      #next unless term_type
      unless term_type
        skipped_no_term_type += 1
        if first_no_type
          first_no_type = false
          #binding.pry
        end
        next
      end

      #next if authority_code == "lcsh" && term_type == "complex_subject"
      if authority_code == "lcsh" && term_type == "complex_subject"
        skipped_complex_subject += 1
        next
      end

      record_id = File.basename(subject)

      doc = {
        uri: subject,
        term: term,
        term_idx: term,
        term_type: term_type,
        record_id: File.basename(subject),
        language: "en",
        authority_code: authority_code,
        authority_name: vocabulary[:authority_name],
        unique_id: "#{options[:vocabulary]}_#{record_id}",
        alternate_term: predicate_to_object_mapping[W3_ALT_LABEL]&.to_a,
        alternate_term_idx: predicate_to_object_mapping[W3_ALT_LABEL]&.to_a,
      }

      binding.pry
      exit

      outfile.puts(doc.to_json)
      docs_generated += 1
    end
  end

  puts "\n\nGenerated #{docs_generated} Solr documents."

  puts "skipped_bnode = #{skipped_bnode}"
  puts "skipped_non_loc_uri = #{skipped_non_loc_uri}"
  puts "skipped_no_mapping = #{skipped_no_mapping}"
  puts "skipped_deprecated = #{skipped_deprecated}"
  puts "skipped_no_term = #{skipped_no_term}"
  puts "skipped_no_term_type = #{skipped_no_term_type}"
  puts "skipped_complex_subject = #{skipped_complex_subject}"
ensure
  tempfiles.each { |f| f.close! }
end
