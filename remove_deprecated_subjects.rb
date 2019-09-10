# frozen_string_literal: true

require 'gdbm'
require 'nypl_log_formatter'

@gdbm = GDBM.new(ARGV[0])
@logger = NyplLogFormatter.new(STDOUT, level: 'debug')
@logger.info("before weeding out there were #{@gdbm.length}")

# Usage:
#  ruby remove_deprecated_subjects.rb a_big_file.db
# Why:
#  TrippleToSolrDoc waits until the .nt file is entirely read until it weeds out deprecated subjects
#  The intermediate '.db' file can get VERY big (for name authorities specifically).
#  You may want to hault the a run of authoritydata_updater.rb, run remove_deprecated_subjects.rb, and resume authoritydata_updater.rb
#  with the -n & -d flags to resume the work.
# Future Work:
#  We _could_ change TrippleToSolrDoc to do this garbage collection every 10000 rows or so.

# Weed out out old /deprecated subjects,
# changeNote predicates point to a bnode lines.
# e.g.
#  <http://id.loc.gov/vocabulary/graphicMaterials/tgm003368> <http://www.loc.gov/mads/rdf/v1#adminMetadata> _:bnode12683670136320746870
#  ...and looking at _:bnode12683670136320746870
#  :bnode12683670136320746870 <http://id.loc.gov/ontologies/RecordInfo#recordStatus'> "deprecated"
@gdbm.delete_if do |subject, attrs|
  attributes = Marshal.load(attrs)
  change_history = attributes['http://www.loc.gov/mads/rdf/v1#adminMetadata']
  deletable = change_history && @gdbm[change_history] && Marshal.load(@gdbm[change_history])['http://id.loc.gov/ontologies/RecordInfo#recordStatus'] == 'deprecated'
  @logger.info('deleted subject', subjectUrl: subject) if deletable
  deletable
end

@logger.info("after weeding out there were #{@gdbm.length}")
