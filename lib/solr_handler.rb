require 'nypl_log_formatter'
require 'open-uri'
require 'rsolr'

class SolrHandler
  def self.send_docs_to_solr(solr_url, docs)
    solr = RSolr.connect :url => solr_url
    solr.add docs
    solr.commit
  end
end