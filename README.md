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

Install gems with `bundle install`

## Tests

Run tests with the `run_tests.rb` script:

```console
$ ruby test/run_tests.rb 
```

## Running

### Generate Solr docs

With dependencies installed, run the `rdf_to_solr_docs.rb` script with required arguments. To see help text, use the `-h` flag:

```console
$ ruby rdf_to_solr_docs.rb -h
Usage: rdf_to_solr_docs.rb [options]
    -v, --vocabulary [VOCABULARY]    Vocabulary type
    -s, --source [SOURCE]            Path or URL to vocabulary file
    -o, --output [OUTPUT]            Output file (optional)
```

For example, to process the Genre & Form Terms vocabulary:

```console
$ ruby rdf_to_solr_docs.rb -v lcgft -s data/source/authoritiesgenreForms.madsrdf.nt -o data/output/lcgft.json
```

### Upload Solr docs

Now that you have generated solr docs, upload them to solr using the `post_to_solr.rb` script. To see help text, use the `-h` flag:

```console
$ ruby post_to_solr.rb -h
Usage: post_to_solr.rb [options]
    -s, --source [SOURCE]            The JSON file containing documents. (Output from rds_to_solr_docs.rb)
    -d [SOLR_DESTINATION],           URL to Solr
        --solr_destination
    -u, --username [USERNAME]        Solr username
    -p, --password [PASSWORD]        Solr password
    -a, --append                     Do not delete existing documents for this authority first
```

For example, to upload the Genre & Form Terms generated from the above example to a Solr instance running on localhost:

```console
ruby post_to_solr.rb -s data/output/lcgft.json -d http://localhost:8981/solr/authoritydata
```

### Backup Solr docs

You can download a backup of existing solr docs using the `pull_from_solr.rb` script. To see help text, use the `-h` flag:

```console
$ ruby pull_from_solr.rb -h
Usage: pull_from_solr.rb [options]
    -d [SOLR_DESTINATION],           URL to Solr
        --solr_destination
    -u, --solr_username [USERNAME]   Solr username (optional)
    -p, --solr_password [PASSWORD]   Solr password (optional)
    -a, --append                     Do not delete existing documents for this authority first
    -o, --output [OUTPUT]            Output file (optional)
```

For example, to back up the NAF vocabulary from QA:

```console
ruby pull_from_solr.rb -d http://10.225.133.217:8983/solr/authoritydata
```
