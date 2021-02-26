# frozen_string_literal: true

require 'nypl_log_formatter'
require 'rdf'
require 'linkeddata'
require 'gdbm'
include RDF

class TrippleToSolrDoc
  # The intermediate, rdbm file can get GIANT with names
  # This strips deprecated subjects every Nth iteration
  COMPACT_EVERY = 1000000

  # Almost all predicates show up once per Subject, but a subject can have
  # multiple predicates e.g "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
  MULTI_PREDICATES = ['http://www.w3.org/1999/02/22-rdf-syntax-ns#type', 'http://www.w3.org/2004/02/skos/core#altLabel', 'http://www.w3.org/2004/02/skos/core#prefLabel'].freeze

  NS_TYPE_TO_TERM_TYPE_MAPPING = {
    'http://www.loc.gov/mads/rdf/v1#Topic' => 'topic',
    'http://www.loc.gov/mads/rdf/v1#Geographic' => 'geographic',
    'http://www.loc.gov/mads/rdf/v1#PersonalName' => 'name_personal',
    'http://www.loc.gov/mads/rdf/v1#ComplexSubject' => 'complex_subject',
    'http://www.loc.gov/mads/rdf/v1#CorporateName' => 'name_corporate',
    'http://www.loc.gov/mads/rdf/v1#GenreForm' => 'genreform',
    'http://www.loc.gov/mads/rdf/v1#Temporal' => 'temporal',
    'http://www.loc.gov/mads/rdf/v1#NameTitle' => 'name_title',
    'http://www.loc.gov/mads/rdf/v1#Title' => 'title',
    'http://www.loc.gov/mads/rdf/v1#ConferenceName' => 'name_conference'
  }.freeze

  @@logger = NyplLogFormatter.new(STDOUT, level: 'debug')

  def self.convert!(file:, term_type:, authority_code:, authority_name:, unique_id_prefix:, start_at_line:, db_file_name:)
    filename_string = db_file_name || "data/nypl/#{authority_code}_#{Time.now.utc.to_i}.db"
    @@gdbm = GDBM.new(filename_string)

    statement_count = 0

    File.open(file, 'r').each do |line|
      statement_count += 1
      if start_at_line && statement_count < start_at_line
        next
      end

      RDF::NTriples::Reader.new(line) do |reader|
        reader.each_statement do |statement|
          predicate_string = statement.predicate.to_s
          @@logger.debug("parsing statement # #{statement_count}") if statement_count % 1000 == 0
          subject_url = statement.subject.to_s

            if @@gdbm.has_key?(subject_url)
              # We've seen this subject before...
              this_subjects_attributes = Marshal.load(@@gdbm[subject_url])

              if MULTI_PREDICATES.include?(predicate_string)
                if this_subjects_attributes[predicate_string]
                  this_subjects_attributes[predicate_string] << statement.object
                else
                  # This is the first time we've seen syntax-ns#type
                  this_subjects_attributes[predicate_string] = [statement.object]
                end
              else
                this_subjects_attributes[predicate_string] = statement.object
              end
              @@gdbm[subject_url] = Marshal.dump(this_subjects_attributes)
            else
              # We've never seen this subject before
              if MULTI_PREDICATES.include?(predicate_string)
                initial_hash = Marshal.dump(predicate_string => [statement.object])
                @@gdbm[subject_url] = initial_hash
              else
                initial_hash = Marshal.dump(predicate_string => statement.object)
                @@gdbm[subject_url] = initial_hash
              end
            end
        end
      end

      if statement_count % COMPACT_EVERY == 0
        delete_and_compact
      end

    end

    @@logger.info("before weeding out there were #{@@gdbm.length}")
    delete_and_compact

    @@logger.info("after weeding out deprecated there were #{@@gdbm.length}")

    # Weed out bnodes, you have to do this after weeding out deprecateds, not at the same time
    deletable_bnodes = []
    @@gdbm.each_pair do |subject, attrs|
      if !subject.include?('http')
        deletable_bnodes << subject
      end
    end

    deletable_bnodes.each do |bnode_subject|
      @@gdbm.delete(bnode_subject)
    end

    @@logger.info("after weeding out bnodes there were #{@@gdbm.length}")

    # AAT has a lot of subjects that aren't about the term,
    # for example http://vocab.getty.edu/aat/term/1000471898-nl, and http://vocab.getty.edu/aat/rev/5002234393
    # Delete stuff that aren't terms (http://vocab.getty.edu/aat/300015004)
    if authority_code == 'aat'
      # http://vocab.getty.edu/aat/[ANY-NUMBER-OF-DIGITS][END-OF-STRING]
      aat_subject_regex = /http:\/\/vocab.getty.edu\/aat\/\d+\z/
      deletable_keys = []

      @@gdbm.each_pair do |subject, attrs|
        if (aat_subject_regex =~ subject).nil?
          deletable_keys << subject
        end
      end

      @@logger.info("deleting #{deletable_keys.length} weird AAT subjects")
      deletable_keys.each do |deletable_key|
        @@gdbm.delete(deletable_key)
      end

      @@logger.info("after weeding out weird AAT subjects there were #{@@gdbm.length}")

    end

    # solr_docs = []
    output_json_file = File.new(filename_string.gsub('db', 'json'), 'w')

    @@logger.info("writing output as JSON to #{output_json_file.path}")

    missing_terms = []

    @@gdbm.each_pair do |subject, attrs|
      attributes = Marshal.load(attrs)

      new_document = {
        uri: subject,
        term: look_for_term(attributes),
        term_idx: look_for_term(attributes),
        term_type: term_type == :auto ? detect_term_type(attributes) : term_type,
        record_id: File.basename(subject),
        language: 'en',
        authority_code: authority_code,
        authority_name: authority_name,
        unique_id: "#{unique_id_prefix}_#{File.basename(subject)}",
        alternate_term_idx: look_for_alt_terms(attributes),
        alternate_term: look_for_alt_terms(attributes)
      }

      if new_document[:term] !~ /[^[:space:]]/ # equivalent to ActiveSupport `blank?`
        missing_terms << new_document
      else
        output_json_file.puts(JSON.generate(new_document))
      end
    end

    @@logger.info("skipped #{missing_terms.size} documents missing terms")
  end

  # Terms are stored in different places depending on LOC or Getty
  def self.look_for_term(attributes)
    if attributes['http://www.loc.gov/mads/rdf/v1#authoritativeLabel']
      return attributes['http://www.loc.gov/mads/rdf/v1#authoritativeLabel'].to_s
    elsif attributes["http://www.w3.org/2004/02/skos/core#prefLabel"]
      return attributes["http://www.w3.org/2004/02/skos/core#prefLabel"].find{|label| label.language == :en }&.to_s
    elsif attributes["http://www.w3.org/2000/01/rdf-schema#label"]
      return attributes["http://www.w3.org/2000/01/rdf-schema#label"].to_s
    else
      return nil
    end
  end

  # Getty & LOC keep Alternate Terms in http://www.w3.org/2004/02/skos/core#altLabel
  def self.look_for_alt_terms(attributes)
    alt_term = attributes.dig('http://www.w3.org/2004/02/skos/core#altLabel')
    if alt_term
      return alt_term.map(&:to_s)
    end
  end

  def self.delete_and_compact
    @@logger.info("Compacting....")
    deletable_subjects = []
    @@gdbm.each_pair do |subject, attrs|
      attributes = Marshal.load(attrs)
      change_history = attributes['http://www.loc.gov/mads/rdf/v1#adminMetadata']

      deletable = change_history && @@gdbm[change_history.to_s] && Marshal.load(@@gdbm[change_history.to_s])['http://id.loc.gov/ontologies/RecordInfo#recordStatus'] == 'deprecated'
      if deletable
        deletable_subjects << subject
        @@logger.info('marking subject as deletable', subjectUrl: subject)
      end
    end
    @@logger.info("Deleting #{deletable_subjects.length} keys")
    if deletable_subjects.length > 0
      deletable_subjects.each do |subject|
        @@gdbm.delete(subject)
      end
    @@gdbm.reorganize
    end
  end

  def self.detect_term_type(predicate_to_object_mapping)
    terms = NS_TYPE_TO_TERM_TYPE_MAPPING.keys
    ns_types = predicate_to_object_mapping.dig('http://www.w3.org/1999/02/22-rdf-syntax-ns#type') || []
    NS_TYPE_TO_TERM_TYPE_MAPPING[(terms & ns_types)&.first]
  end
end
