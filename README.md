## Genre & Form Terms
* ruby rdf_to_solr_docs.rb -s data/source/authoritiesGenreForms.nt.madsrdf -v lcgft -o data/output/lcgft.json

## Thesaurus for Graphic Materials
* ruby rdf_to_solr_docs.rb -s data/source/graphicMaterials.both.nt -v lctgm -o data/output/lctgm.json

## Subject Headings
* ruby rdf_to_solr_docs.rb -s data/source/lcsh.madsrdf.nt -v lcsh -o data/output/lcsh.json

## Art & Architecture Thesaurus
* ruby rdf_to_solr_docs.rb -s data/source/AATOut_full.nt -v aat -o data/output/aat.json

## Names Authority File
* ruby rdf_bucketer.rb -s data/source/lcnaf.madsrdf.nt -b 8
* ruby rdf_to_solr_docs.rb -s data/source/lcnaf.madsrdf.nt.1 -v naf -o data/output/naf.1.json
* ruby rdf_to_solr_docs.rb -s data/source/lcnaf.madsrdf.nt.2 -v naf -o data/output/naf.2.json -r false
* ruby rdf_to_solr_docs.rb -s data/source/lcnaf.madsrdf.nt.3 -v naf -o data/output/naf.3.json -r false
* ruby rdf_to_solr_docs.rb -s data/source/lcnaf.madsrdf.nt.4 -v naf -o data/output/naf.4.json -r false
* ruby rdf_to_solr_docs.rb -s data/source/lcnaf.madsrdf.nt.5 -v naf -o data/output/naf.5.json -r false
* ruby rdf_to_solr_docs.rb -s data/source/lcnaf.madsrdf.nt.6 -v naf -o data/output/naf.6.json -r false
* ruby rdf_to_solr_docs.rb -s data/source/lcnaf.madsrdf.nt.7 -v naf -o data/output/naf.7.json -r false
* ruby rdf_to_solr_docs.rb -s data/source/lcnaf.madsrdf.nt.8 -v naf -o data/output/naf.8.json -r false
