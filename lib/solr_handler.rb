require 'nypl_log_formatter'
require 'open-uri'
require 'rsolr'

class SolrHandler
  def self.send_docs_to_solr(docs)
    solr_url = 'http://localhost:8983/solr/'
    solr = RSolr.connect :url => solr_url
    solr.add docs
    solr.commit
  end
end