# Authority Data Updater

When users search for authority records in [MMS](https://github.com/nypl/mms), the
search queries a Solr index. The documents in that index need to be updated periodically. This tool parses Library of Congress and Getty vocabulary files and produces files containing Solr documents (in JSON format) that can be uploaded to the Solr index.

## Supported Vocabularies

- [Library of Congress Genre/Form Terms (lcgft)](https://id.loc.gov/authorities/genreForms.html): [source](https://lds-downloads.s3.amazonaws.com/authoritiesgenreForms.nt.madsrdf.zip)
- [Library of Congress Thesaurus for Graphic Materials (lctgm)](https://id.loc.gov/vocabulary/graphicMaterials.html) - [source](https://lds-downloads.s3.amazonaws.com/vocabularygraphicMaterials.nt.both.zip)
- [Library of Congress Names (naf)](https://id.loc.gov/authorities/names.html) - [source](https://lds-downloads.s3.amazonaws.com/lcnaf.madsrdf.nt.zip)
- [Library of Congress Subject Headings (lcsh)](https://id.loc.gov/authorities/subjects.html) - [source](https://lds-downloads.s3.amazonaws.com/lcsh.madsrdf.nt.zip)
- [Getty AAT (aat)](http://vocab.getty.edu/) - [source](http://vocab.getty.edu/dataset/aat/full.zip)

## Dependencies

* This script requires a [memcached](https://www.memcached.org/) server on `localhost:11211`. You can run that with [docker](https://hub.docker.com/_/memcached/) or install it on a Mac using [homebrew](https://formulae.brew.sh/formula/memcached). 
* Install gems with `bundle install`

## Running

With dependencies installed, run the `rdf_to_solr_docs.rb` with required arguments. To see help text, use the `-h` flag:

```console
$ ruby rdf_to_solr_docs.rb -h
Usage: rdf_to_solr_docs.rb [options]
    -s, --source [SOURCE]            Path or URL to vocabulary file
    -v, --vocabulary [VOCABULARY]    Vocabulary type
    -o, --output [OUTPUT]            Output file (optional)
    -t, --threads [THREADS]          Number of threads (default: 2)
```

For example, to process the Genre & Form Terms vocabulary:

```console
$ ruby rdf_to_solr_docs.rb -s data/source/authoritiesGenreForms.nt.madsrdf -v lcgft -o data/output/lcgft.json
```
