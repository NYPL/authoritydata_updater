# frozen_string_literal: true

require "json"
require "set"
require "tty-command"
require "tty-progressbar"
require "tty-spinner"
require "zlib"

require "rdf_triple"

PROGRESS_BAR_FORMAT = "[:bar] [:current/:total] [:percent] [ET::elapsed] [ETA::eta] [:rate/s]"
PROGRESS_BAR_FREQUENCY = 2
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

class SolrDocGenerator
  attr_reader :authority_code, :authority_name, :term_type, :verbose

  def initialize(authority_code, source, output, verbose = false)
    unless VOCABULARIES.keys.include?(authority_code)
      raise ArgumentError, "vocabulary must be one of: #{VOCABULARIES.keys.join(", ")}"
    end

    @authority_code = authority_code
    @authority_name = VOCABULARIES[authority_code][:authority_name]
    @term_type = VOCABULARIES[authority_code][:term_type]
    @source = source
    @output = output
    @verbose = verbose
    @deprecated_metadata_nodes = Set.new
  end

  def run
    sorted_file, sorted_lines = create_sorted_file

    puts "Generating Solr docs..." if @verbose

    progress = 0
    generated_docs = 0
    outfile = File.open(@output, "w")
    subject_data = nil

    bar = TTY::ProgressBar.new(PROGRESS_BAR_FORMAT, total: sorted_lines, frequency: PROGRESS_BAR_FREQUENCY) if @verbose

    sorted_file.each do |line|
      triple = RdfTriple.parse(line)

      if ALL_PREDICATES.include?(triple.predicate)
        if subject_data.nil?
          # first document encountered, happens only once
          subject_data = { subject: triple.subject }
        elsif subject_data[:subject] != triple.subject
          # new subject, write the current one and start a new one
          generated_docs += 1 if write_solr_doc(subject_data, outfile)
          subject_data = { subject: triple.subject }
        end

        if SINGULAR_PREDICATES.include?(triple.predicate)
          subject_data[triple.predicate] = triple.object
        else
          subject_data[triple.predicate] ||= Set.new
          subject_data[triple.predicate] << triple.object
        end
      end

      progress += 1
      bar.advance(PROGRESS_BAR_UPDATE_DOC_COUNT) if progress % PROGRESS_BAR_UPDATE_DOC_COUNT == 0 if @verbose
    end

    generated_docs += 1 if write_solr_doc(subject_data, outfile)
    outfile.close

    if @verbose
      bar.finish
      puts "Generated #{generated_docs} Solr docs to #{outfile.path}"
    end

    sorted_file.close
    @mergefile.unlink

    puts "Done." if @verbose
  end

  private

  def create_sorted_file
    if @verbose
      source_lines = count_source_lines(@source)
      puts "Sorting into temp files..."
      bar = TTY::ProgressBar.new(PROGRESS_BAR_FORMAT, total: source_lines, frequency: PROGRESS_BAR_FREQUENCY)
    end

    tempfiles = []
    bucket = []
    read_lines = 0
    sorted_lines = 0

    File.open(@source, "r").each do |line|
      begin
        triple = RdfTriple.parse(line)

        if bucket.length >= DOCUMENTS_PER_TEMPFILE
          tempfiles << dump_bucket_to_tmp_file(bucket)
          bucket = []
        end

        if triple.predicate == LOC_RECORD_STATUS && triple.object == LOC_STATUS_DEPRECATED
          @deprecated_metadata_nodes << triple.subject
        end

        bucket << [triple.subject, line]
        sorted_lines += 1
      rescue RdfTriple::ParseError
        # ignore this invalid line
      end

      read_lines += 1
      bar.advance(PROGRESS_BAR_UPDATE_DOC_COUNT) if read_lines % PROGRESS_BAR_UPDATE_DOC_COUNT == 0 if @verbose
    end

    tempfiles << dump_bucket_to_tmp_file(bucket) if bucket.any?

    if @verbose
      bar.finish
      puts "Sorted into #{tempfiles.size} temp files."
      puts "Merging into single file..."
    end

    tempfile_readers = tempfiles.map { |f| Zlib::GzipReader.new(open(f.path)) }

    heads = tempfile_readers.each_with_index.map do |tempfile, i|
      [tempfile.readline, i]
    end
    heads.sort!

    @mergefile = Tempfile.new
    mergefile_writer = Zlib::GzipWriter.wrap(@mergefile)

    bar = TTY::ProgressBar.new(PROGRESS_BAR_FORMAT, total: sorted_lines, frequency: PROGRESS_BAR_FREQUENCY) if @verbose
    merge_line_count = 0

    while heads.any?
      next_line, file_num = heads[0]
      mergefile_writer << next_line

      begin
        heads[0] = [tempfile_readers[file_num].readline, file_num]
        heads.sort!
      rescue EOFError
        heads.delete_if { |value, n| n == file_num }
        tempfile_readers[file_num].close
        tempfiles[file_num].close
        tempfiles[file_num].unlink
      end

      merge_line_count += 1
      bar.advance(PROGRESS_BAR_UPDATE_DOC_COUNT) if merge_line_count % PROGRESS_BAR_UPDATE_DOC_COUNT == 0 if @verbose
    end

    bar.finish if @verbose

    if @verbose
      bar.finish
      puts "Created sorted temp file."
    end

    mergefile_writer.close

    mergefile_reader = Zlib::GzipReader.new(open(@mergefile.path))
    return mergefile_reader, merge_line_count
  end

  def count_source_lines(source)
    if @verbose
      spinner = TTY::Spinner.new("Counting lines... :spinner")
      spinner.auto_spin
    end

    cmd = TTY::Command.new(printer: :null)
    out, err = cmd.run("wc -l #{source}")
    source_lines = out.split.first.to_i

    if @verbose
      spinner.stop
      puts "#{source_lines} lines in source file."
    end

    return source_lines
  end

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

  def write_solr_doc(subject_data, outfile)
    return if subject_data[:subject].start_with?("_") # bnode
    return if subject_data[:authority_code] == "lcsh" && !(subject_data[:subject] =~ REGEX_LOC_URI)
    return if @deprecated_metadata_nodes.include?(subject_data[LOC_ADMIN_METADATA])

    term = nil
    if subject_data.include?(LOC_AUTHORITATIVE_LABEL)
      term = subject_data[LOC_AUTHORITATIVE_LABEL]
    elsif subject_data.include?(W3_PREF_LABEL)
      term = subject_data[W3_PREF_LABEL].first
    elsif subject_data.include?(W3_RDF_LABEL)
      term = subject_data[W3_RDF_LABEL]
    end
    return unless term

    term_type = @term_type
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

    return if @authority_code == :lcsh && term_type == "complex_subject"

    record_id = File.basename(subject_data[:subject])

    doc = {
      uri: subject_data[:subject],
      term: term,
      term_idx: term,
      term_type: term_type,
      record_id: record_id,
      language: "en",
      authority_code: @authority_code,
      authority_name: @authority_name,
      unique_id: "#{@authority_code}_#{record_id}",
      alternate_term_idx: subject_data[W3_ALT_LABEL]&.to_a,
      alternate_term: subject_data[W3_ALT_LABEL]&.to_a,
    }

    outfile.puts(doc.to_json)
    return true
  end
end
