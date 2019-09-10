# frozen_string_literal: true

require 'nypl_log_formatter'
require 'open-uri'
require 'rsolr'
require 'rsolr/connection'

class RSolr::Connection
  protected

  def setup_raw_request_with_basic_auth(request_context)
    @logger = NyplLogFormatter.new(STDOUT, level: 'debug')
    begin
      raw_request = setup_raw_request_without_basic_auth(request_context)
      raw_request.basic_auth(SOLR_USERNAME, SOLR_PASSWORD)
      raw_request
    rescue Exception => e
      @logger.error("Error adding basic auth to solr request. #{e}")
    end
  end

  alias setup_raw_request_without_basic_auth setup_raw_request
  alias setup_raw_request setup_raw_request_with_basic_auth
end

class SolrHandler
  @@logger = NyplLogFormatter.new(STDOUT, level: 'debug')

  def self.delete_by_query(solr_url, solr_query)
    solr = RSolr.connect(url: solr_url)
    delete_response = solr.delete_by_query(solr_query)
    @@logger.info("delete response: #{delete_response}")
    commit_response = solr.commit
    @@logger.info("deletion commit response: #{commit_response}")
  end

  def self.send_docs_to_solr(solr_url, docs)
    solr = RSolr.connect(url: solr_url)
    add_response = solr.add(docs.compact)
    @@logger.info("add response: #{add_response}")
    commit_response = solr.commit
    @@logger.info("delete commit response: #{commit_response}")
  end
end
