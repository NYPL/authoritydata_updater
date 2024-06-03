# Authority Data Updater

When users search for authority records in [MMS](https://github.com/nypl/mms), the
search queries a Solr index. The documents in that index need to be updated periodically. This tool parses Library of Congress and Getty vocabulary files and produces files containing Solr documents (in JSON format) that can be uploaded to the Solr index.

## Supported Vocabularies

- [Library of Congress Genre/Form Terms (lcgft)](https://id.loc.gov/authorities/genreForms.html): [source](https://id.loc.gov/download/authorities/genreForms.madsrdf.nt.gz)
- [Library of Congress Thesaurus for Graphic Materials (lctgm)](https://id.loc.gov/vocabulary/graphicMaterials.html) - [source](https://id.loc.gov/download/vocabulary/graphicMaterials.madsrdf.nt.gz)
- [Library of Congress Names (naf)](https://id.loc.gov/authorities/names.html) - [source](https://id.loc.gov/download/authorities/names.madsrdf.nt.gz)
- [Library of Congress Subject Headings (lcsh)](https://id.loc.gov/authorities/subjects.html) - [source](https://id.loc.gov/download/authorities/subjects.madsrdf.nt.gz)
- [Getty AAT (aat)](http://vocab.getty.edu/) - [source](http://aatdownloads.getty.edu/VocabData/full.zip)

## Building the container

Build the `webapp` container with `docker-compose build`. Then, enter it with `docker-compose run webapp bash`

## Tests

Run tests with the `run_tests.rb` script:

```console
$ bundle exec ruby test/run_tests.rb
```

## Running

### Generate Solr docs

With dependencies installed, run the `rdf_to_solr_docs.rb` script with required arguments. To see help text, use the `-h` flag:

```console
$ bundle exec ruby rdf_to_solr_docs.rb -h
Usage: rdf_to_solr_docs.rb [options]
    -v, --vocabulary [VOCABULARY]    Vocabulary type
    -s, --source [SOURCE]            Path or URL to vocabulary file
    -o, --output [OUTPUT]            Output file (optional)
```

For example, to process the Genre & Form Terms vocabulary:

```console
$ bundle exec ruby rdf_to_solr_docs.rb -v lcgft -s data/source/authoritiesgenreForms.madsrdf.nt -o data/output/lcgft.json
```

Names and Subjects are the largest dataset, and as of 2024, Subjects was larger than 80 GB. You'll need plenty of local hard drive space to unzip the source file. Formatting the data into json recently took approximately 3 days.

### Upload Solr docs

Now that you have generated solr docs, upload them to solr using the `post_to_solr.rb` script. To see help text, use the `-h` flag:

```console
$ bundle exec ruby post_to_solr.rb -h
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
$ bundle exec ruby post_to_solr.rb -s data/output/lcgft.json -d http://localhost:8981/solr/authoritydata
```

### Backup Solr docs

You can download a backup of existing solr docs using the `pull_from_solr.rb` script. To see help text, use the `-h` flag:

```console
$ bundle exec ruby pull_from_solr.rb -h
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
bundle exec ruby pull_from_solr.rb -d http://10.225.133.217:8983/solr/authoritydata
```
