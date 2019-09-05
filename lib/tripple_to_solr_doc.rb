# frozen_string_literal: true

require 'redis'
require 'rdf'
require 'linkeddata'
require 'redis'
include RDF

class TrippleToSolrDoc
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

  WORTHWHILE_PREDICATES = [
    'http://www.w3.org/1999/02/22-rdf-syntax-ns#type',
    'http://www.loc.gov/mads/rdf/v1#adminMetadata',
    'http://id.loc.gov/ontologies/RecordInfo#recordStatus',
    'http://www.loc.gov/mads/rdf/v1#authoritativeLabel',
    'http://www.w3.org/2004/02/skos/core#prefLabel'
  ].freeze

  @@logger = NyplLogFormatter.new(STDOUT, level: 'debug')
  @@redis = Redis.new(url: ENV['REDIS_URL'])

  def self.convert!(file:, term_type:, authority_code:, authority_name:, unique_id_prefix:)
    statement_count = 0

    File.open(file, 'r').each do |line|
      # Almost all predicates show up once per Subject, but a subject can have
      # multiple "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" predicates
      RDF::NTriples::Reader.new(line) do |reader|
        reader.each_statement do |statement|
          statement_count += 1
          predicate_string = statement.predicate.to_s
          @@logger.debug("parsing statement # #{statement_count}")
          subject_url = statement.subject.to_s
          if worthwhile_statement?(statement)
            if @@redis.exists(subject_url)
              # We've seen this subject before...
              this_subjects_attributes = Marshal.load(@@redis.get(subject_url))

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

              @@redis.set(subject_url, Marshal.dump(this_subjects_attributes))
            else
              # We've never seen this subject before

              if predicate_string == 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
                inital_hash = Marshal.dump(predicate_string => [statement.object.to_s])
                @@redis.set(subject_url, inital_hash)
              else
                initial_hash = Marshal.dump(predicate_string => statement.object.to_s)
                @@redis.set(subject_url, initial_hash)
              end
            end
          else
            @@logger.info('skipping a statement')
          end
        end
      end
    end

    @@logger.info("before weeding out there were #{@@redis.dbsize}")

    # Weed out out old /deprecated subjects,
    # changeNote predicates point to a bnode lines.
    # e.g.
    #  <http://id.loc.gov/vocabulary/graphicMaterials/tgm003368> <http://www.loc.gov/mads/rdf/v1#adminMetadata> _:bnode12683670136320746870
    #  ...and looking at _:bnode12683670136320746870
    #  :bnode12683670136320746870 <http://id.loc.gov/ontologies/RecordInfo#recordStatus'> "deprecated"
    @@redis.scan_each do |subject|
      attributes = Marshal.load(@@redis.get(subject))
      change_history = attributes['http://www.loc.gov/mads/rdf/v1#adminMetadata']
      bnode_for_this = @@redis.get(change_history)

      if change_history && bnode_for_this
        bnodes_hash = Marshal.load(bnode_for_this)
        if bnodes_hash['http://id.loc.gov/ontologies/RecordInfo#recordStatus'] == 'deprecated'
          @@redis.del(subject)
        end
      end
    end

    @@logger.info("after weeding out deprecated there were #{@@redis.dbsize}")

    # Weed out bnodes, you have to do this after weeding out deprecateds, not at the same time
    @@redis.scan_each do |subject|
      @@redis.del(subject) unless subject.include?('http')
    end

    @@logger.info("after weeding out bnodes there were #{@@redis.dbsize}")

    solr_docs = []
    @@redis.scan_each do |subject|
      attributes = Marshal.load(@@redis.get(subject))

      new_document = {
        uri: subject,
        term: attributes.dig('http://www.loc.gov/mads/rdf/v1#authoritativeLabel'),
        term_idx: attributes.dig('http://www.loc.gov/mads/rdf/v1#authoritativeLabel'),
        term_type: term_type == :auto ? detect_term_type(attributes) : term_type,
        record_id: File.basename(subject),
        language: 'en',
        authority_code: authority_code,
        authority_name: authority_name,
        unique_id: "#{unique_id_prefix}_#{File.basename(subject)}",
        alternate_term_idx: attributes.dig('http://www.w3.org/2004/02/skos/core#prefLabel'),
        alternate_term: attributes.dig('http://www.w3.org/2004/02/skos/core#prefLabel')
      }

      solr_docs << new_document
    end
    solr_docs
  end

  # These files are FULL of statements we don't care about.
  # Statements that we never use to post info to Solr.
  # As we parse the N-tripple file, we can skip even considering
  # this line if it's dealing with a predicate we don't care about (e.g. http://www.w3.org/2000/01/rdf-schema#seeAlso)
  def self.worthwhile_statement?(statement)
    WORTHWHILE_PREDICATES.include?(statement.predicate.to_s)
  end

  def self.detect_term_type(predicate_to_object_mapping)
    terms = NS_TYPE_TO_TERM_TYPE_MAPPING.keys
    ns_types = predicate_to_object_mapping.dig('http://www.w3.org/1999/02/22-rdf-syntax-ns#type')

    term_types[(terms & ns_types)&.first]
  end
end
