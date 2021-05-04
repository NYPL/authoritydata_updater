## Genre & Form Terms
* ruby rdf_to_solr_docs.rb -s data/source/authoritiesGenreForms.nt.madsrdf -v lcgft -o data/output/lcgft.json -t 8

## Thesaurus for Graphic Materials
* ruby rdf_to_solr_docs.rb -s data/source/graphicMaterials.both.nt -v lctgm -o data/output/lctgm.json -t 8

## Subject Headings
* ruby rdf_to_solr_docs.rb -s data/source/lcsh.madsrdf.nt -v lcsh -o data/output/lcsh.json -t 8

## Art & Architecture Thesaurus
* ruby rdf_to_solr_docs.rb -s data/source/AATOut_full.nt -v aat -o data/output/aat.json -t 8

## Names Authority File
* ruby rdf_to_solr_docs.rb -s data/source/lcnaf.madsrdf.nt -v naf -o data/output/naf.json -t 8
