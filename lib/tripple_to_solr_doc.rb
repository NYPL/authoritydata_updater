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
    filename_string = db_file_name || "#{authority_code}_#{Time.now.utc.to_i}.db"
    @@gdbm = GDBM.new(filename_string)

    statement_count = 0

    File.open(file, 'r').each do |line|
      statement_count += 1
      if start_at_line && statement_count < start_at_line
        next
      end
      # Almost all predicates show up once per Subject, but a subject can have
      # multiple "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" predicates
      RDF::NTriples::Reader.new(line) do |reader|
        reader.each_statement do |statement|
          predicate_string = statement.predicate.to_s
          @@logger.debug("parsing statement # #{statement_count}")
          subject_url = statement.subject.to_s

            if @@gdbm.has_key?(subject_url)
              # We've seen this subject before...
              this_subjects_attributes = Marshal.load(@@gdbm[subject_url])

              if predicate_string == 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
                if this_subjects_attributes[predicate_string]
                  this_subjects_attributes[predicate_string] << statement.object.to_s
                else
                  # This is the first time we've seen syntax-ns#type
                  this_subjects_attributes[predicate_string] = [statement.object.to_s]
                end
              else
                this_subjects_attributes[predicate_string] = statement.object.to_s
              end
              @@gdbm[subject_url] = Marshal.dump(this_subjects_attributes)
            else
              # We've never seen this subject before
              if predicate_string == 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
                initial_hash = Marshal.dump(predicate_string => [statement.object.to_s])
                @@gdbm[subject_url] = initial_hash
              else
                initial_hash = Marshal.dump(predicate_string => statement.object.to_s)
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

    # solr_docs = []
    output_json_file = File.new(filename_string.gsub('db', 'json'), 'w')

    @@logger.info("writing output as JSON to #{output_json_file.path}")

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

      output_json_file.puts(JSON.generate(new_document))
    end
    output_json_file.close
  end

  # Terms are stored in different places depending on LOC or Getty
  def self.look_for_term(attributes)
    attributes.dig('http://www.loc.gov/mads/rdf/v1#authoritativeLabel')
  end

  # Alternate Terms are stored in different places depending on LOC or Getty
  def self.look_for_alt_terms(attributes)
    attributes.dig('http://www.w3.org/2004/02/skos/core#prefLabel')
  end

  def self.delete_and_compact
    @@logger.info("Compacting....")
    deletable_subjects = []
    @@gdbm.each_pair do |subject, attrs|
      attributes = Marshal.load(attrs)
      change_history = attributes['http://www.loc.gov/mads/rdf/v1#adminMetadata']

      deletable = change_history && @@gdbm[change_history] && Marshal.load(@@gdbm[change_history])['http://id.loc.gov/ontologies/RecordInfo#recordStatus'] == 'deprecated'
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
    ns_types = predicate_to_object_mapping.dig('http://www.w3.org/1999/02/22-rdf-syntax-ns#type')
    NS_TYPE_TO_TERM_TYPE_MAPPING[(terms & ns_types)&.first]
  end
end
