require 'nypl_log_formatter'
require 'open-uri'
require 'rsolr'
require 'rsolr/connection'

class RSolr::Connection
  protected
  def setup_raw_request_with_basic_auth request_context
    @logger = NyplLogFormatter.new(STDOUT, level: 'debug')
    begin
      raw_request = setup_raw_request_without_basic_auth(request_context)
      raw_request.basic_auth(SOLR_USERNAME, SOLR_PASSWORD)
      raw_request
    rescue Exception => e
      @logger.error("Error adding basic auth to solr request. #{e}")
    end
  end

  alias_method :setup_raw_request_without_basic_auth, :setup_raw_request
  alias_method :setup_raw_request, :setup_raw_request_with_basic_auth
end

class SolrHandler
  def self.send_docs_to_solr(solr_url, docs)
    solr = RSolr.connect(:url => solr_url)
    # Post to Solr in batches of 1,000
    docs.each_slice(1000) do |batch|
      solr.add(batch.compact)
      solr.commit
    end
  end
end
