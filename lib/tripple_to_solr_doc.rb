# frozen_string_literal: true

require 'redis'
require 'rdf'
require 'linkeddata'
include RDF

class TrippleToSolrDoc
  @@logger = NyplLogFormatter.new(STDOUT, level: 'debug')

  def self.convert!(file:, term_type:, authority_code:, authority_name:, unique_id_prefix:)
    all_subjects = {}
    statement_count = 0

    File.open(file,'r').each do |line|
      # Almost all predicates show up once per Subject, but a subject can have
      # multiple "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" predicates
      RDF::NTriples::Reader.new(line) do |reader|
        reader.each_statement do |statement|
          statement_count += 1
          predicate_string = statement.predicate.to_s
          @@logger.debug("parsing statement # #{statement_count}")
          subject_url = statement.subject.to_s

          if all_subjects[subject_url]
            # We've seen this subject before
            if predicate_string == 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
              if all_subjects[subject_url][predicate_string]
                all_subjects[subject_url][predicate_string] << statement.object.to_s
              else
                # This is the first time we've seen syntax-ns#type
                all_subjects[subject_url].merge!(predicate_string => [statement.object.to_s])
              end
            else
              all_subjects[subject_url].merge!(predicate_string => statement.object.to_s)
            end
          else
            # This is the first time we've seen this subject
            if predicate_string == 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'
              all_subjects[subject_url] = {
                predicate_string => [statement.object.to_s]
              }
            else
              all_subjects[subject_url] = {
                predicate_string => statement.object.to_s
              }
            end
          end
        end
      end
    end

    @@logger.info("before weeding out there were #{all_subjects.keys.length}")

    # Weed out out old /deprecated subjects,
    # changeNote predicates point to a bnode lines.
    # e.g.
    #  <http://id.loc.gov/vocabulary/graphicMaterials/tgm003368> <http://www.loc.gov/mads/rdf/v1#adminMetadata> _:bnode12683670136320746870
    #  ...and looking at _:bnode12683670136320746870
    #  :bnode12683670136320746870 <http://id.loc.gov/ontologies/RecordInfo#recordStatus'> "deprecated"
    all_subjects.reject! do |_subject, attributes|
      change_history = attributes['http://www.loc.gov/mads/rdf/v1#adminMetadata']
      all_subjects.dig(change_history, 'http://id.loc.gov/ontologies/RecordInfo#recordStatus') == 'deprecated'
    end

    @@logger.info("after weeding out deprecated there were #{all_subjects.keys.length}")

    # Weed out bnodes, you have to do this after weeding out deprecateds, not at the same time
    all_subjects.select! do |subject, _attributes|
      subject.include?('http')
    end
    @@logger.info("after weeding out bnodes there were #{all_subjects.keys.length}")

    solr_docs = all_subjects.map do |subject, attributes|
      {
        uri: subject,
        term: attributes.dig('http://www.loc.gov/mads/rdf/v1#authoritativeLabel'),
        term_idx: attributes.dig('http://www.loc.gov/mads/rdf/v1#authoritativeLabel'),
        term_type: (term_type == :auto) ? detect_term_type(attributes) : term_type,
        record_id: File.basename(subject),
        language: 'en',
        authority_code: authority_code,
        authority_name: authority_name,
        unique_id: "#{unique_id_prefix}_#{File.basename(subject)}",
        alternate_term_idx: attributes.dig('http://www.w3.org/2004/02/skos/core#prefLabel'),
        alternate_term: attributes.dig('http://www.w3.org/2004/02/skos/core#prefLabel')
      }
    end
    solr_docs
  end

  def self.detect_term_type(predicate_to_object_mapping)
    term_types = {
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
    }
    
    terms = term_types.keys    
    ns_types = predicate_to_object_mapping.dig('http://www.w3.org/1999/02/22-rdf-syntax-ns#type')
    
    term_types[(terms & ns_types)&.first]
  end
end
