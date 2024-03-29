# frozen_string_literal: true

require "json"
require "set"
require "tty-command"
require "tty-progressbar"
require "tty-spinner"
require "zlib"

require "authoritative_record"
require "rdf_triple"

PROGRESS_BAR_FORMAT = "[:bar] [:current/:total] [:percent] [ET::elapsed] [ETA::eta] [:rate/s]"
PROGRESS_BAR_FREQUENCY = 2
PROGRESS_BAR_UPDATE_DOC_COUNT = 5_000

DOCUMENTS_PER_TEMPFILE = 1_000_000

class SolrDocGenerator
  def initialize(authority_code, source, output, verbose = false)
    @authority_code = authority_code
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
    authoritative_record = nil

    bar = TTY::ProgressBar.new(PROGRESS_BAR_FORMAT, total: sorted_lines, frequency: PROGRESS_BAR_FREQUENCY) if @verbose

    sorted_file.each do |line|
      triple = RdfTriple.parse(line)
      if(triple.valid_predicate?)
        if authoritative_record.nil?
          # first document encountered, happens only once
          authoritative_record = AuthoritativeRecord.new(@authority_code, triple.subject)
        elsif authoritative_record.subject != triple.subject
          # new subject, write the current one and start a new one
          generated_docs += 1 if write_solr_doc(authoritative_record, outfile) # TODO fix
          authoritative_record = AuthoritativeRecord.new(@authority_code, triple.subject)
        end

        authoritative_record.add_triple(triple)
      end

      progress += 1
      bar.advance(PROGRESS_BAR_UPDATE_DOC_COUNT) if progress % PROGRESS_BAR_UPDATE_DOC_COUNT == 0 if @verbose
    end

    generated_docs += 1 if write_solr_doc(authoritative_record, outfile) # TODO: fix
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

        if triple.deprecated?
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

    tempfile_readers = tempfiles.map { |f| Zlib::GzipReader.new(open(f.path, "r")) }

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

    mergefile_reader = Zlib::GzipReader.new(open(@mergefile.path, "r"))
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

  def write_solr_doc(authoritative_record, outfile)
    return unless authoritative_record.valid?
    return if @deprecated_metadata_nodes.include?(authoritative_record.metadata_node)
    outfile.puts(authoritative_record.to_json)
    return true
  end
end
