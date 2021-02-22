# Authority Data Updater

When users search for authority records in [MMS](https://github.com/nypl/mms), the
search queries a Solr index. The documents in that index need to be updated periodically.

**This tool parses various vocabulary files and POSTS their contents to a Solr index.**  
Locally - you can point it to [a dockerized Solr 3.5 that has a core named "authoritydata"](https://github.com/NYPL/authoritydata_solr_docker).
This repository's [docker-compose.yml](./docker-compose.yml) comes with that authoritydata solr 3.5 core.

## Building

1.  clone [NYPL/authoritydata_solr_docker](https://github.com/NYPL/authoritydata_solr_docker) into a sibling directory of this app.
2.  In this directory `cp ./.env.example ./.env`
3.  Fill in the `.env`
4.  `docker-compose build`
5.  **run with `docker-compose run updater bash`**.

See [./docs/running.md](running.md) for more context.

## Confirming Solr Is Up

You can confirm that your solr core exists by going to: `http://localhost:8983/solr/admin/cores?action=STATUS&core=authoritydata`
You can see the Solr admin interface here: <http://localhost:8983/solr/admin/>

## Running

Because, depending on the vocabulary, it can take a LONG time to complete these tasks -
we break the process into small scripts, and the output of one script acts as
the input of the next.

### Step 0: Start The Containers

1.  `docker-compose run updater bash`
2.  (from inside the container) go to `/opt/authoritydata_udpater`

### Step 1: Remove Unusable Statements

The bulk downloads from LOC contain statements that are helpful for linkeddata, but that we don't post to SOLR.
Running `01_clean_nt_file.rb` will remove rows that are inconsequential to us.
This makes the subsuquent input files MUCH easier to deal with.

**EXAMPLE:**

This removes inconsequential statements/rows from `authoritiessubjects.nt.madsrdf`,
and outputs a new file named `cleaner-subjects.nt`.

    $ ruby 01_clean_nt_file.rb authoritiessubjects.nt.madsrdf cleaner-subjects.nt

### Step 2: Convert Statements in `.nt` file to JSON

This can take a long time with big vocabularies (i.e. names).
It builds an intermediate key/value using [gdbm](https://ruby-doc.org/stdlib-2.5.3/libdoc/gdbm/rdoc/GDBM.html) of
the statements in the `-s` source file, then removes deprecated statements from that datastore.
(We don't want to post them to SOLR) - finally it outputs a .json file.

The JSON file is a newline delimited list of documents we want to post to Solr.

#### This Script Can Be Resumed if terminated too early.

See the optional `-n` and `-d` flags that can be used to resume parsing.

    $ ruby 02_convert_to_solr_docs.rb -h

    Usage: ruby authoritydata_updater.rb [options] \n Exaxmple: ruby authoritydata_updater.rb --vocabulary genre_and_form --source ./authority-file.nt

    Supported vocabularies: rdacarriers, graphic_materials, genre_and_form, names, subjects, aat

        -v, --vocabulary=                The type of vocabularies in the source file
        -s, --source=                    Path or URL to vocabulary file
        -n, --start-on-line=             Start parsing on this line of the .nt file
        -d, --db-file=                   Use an existing db file, probably used with -n because a previous run was interrupted
        -h, --help                       Show this message

### Step 3: Post JSON to Solr

    $ ruby 03_post_to_solr.rb -h
    Usage: ruby post_to_solr.rb --file lcgft_12345.json --solrUrl $SOLR_URL --username $USERNAME --password $PASSWORD
        -f, --file=                      The JSON file containing documents. (Output from authoritydata_updater.rb)
        -s, --solrUrl=                   Path or URL to SOLR core
        -u, --username=                  Solr username
        -p, --password=                  Solr password
        -n, --line-number=               Start parsing on line (helpful if restarting)
        -h, --help                       Show this message

#### This can also be resumed if it's terminated too early

1.  If no `-n` is passed (start POSTING records from midway through the file), we'll just POST new records to solr (from that starting point).

2.  If `-n` is NOT passed (start POSTING records from the beginning of the file), we will DELETE existing existing
    records of that authority_code, then post.

## Development

### Adding / Updating Gems

Once you have the app setup...

1.  Make your changes to `Gemfile` locally.

2.  `docker-compose run updater bash`  
    This starts a container, with your local directory mounted into into it.

3.  Go to where the app is mounted and run `bundle`.
    To find out where the app is mounted, refer to the configurations specificed in the docker-compose.yml.
    This makes the required changes to `Gemfile.lock`.  
    The _real_ installation will happen in the step 5.

4.  Exit the docker container. Locally, you should now see changes to both `Gemfile` and `Gemfile.lock`

5.  Rebuild the Docker image.
    `docker-compose build --no-cache updater`

### Git Workflow

`master` is considered production/stable.
Cut feature branches off of, and file pull requests against `master`.

### Deployment

When a remote Solr needs to be updated - this is run on developers' machines.  
It is not deployed to any remote environments.

## Supported Vocabularies

- [Library of Congress Genre/Form Terms](https://id.loc.gov/authorities/genreForms.html) - [authoritiesgenreForms.nt.madsrdf.zip](https://lds-downloads.s3.amazonaws.com/authoritiesgenreForms.nt.madsrdf.zip)
- [Library of Congress Thesaurus for Graphic Materials](https://id.loc.gov/vocabulary/graphicMaterials.html) - [vocabularygraphicMaterials.nt.both.zip](https://lds-downloads.s3.amazonaws.com/vocabularygraphicMaterials.nt.both.zip)
- [Library of Congress Names](https://id.loc.gov/authorities/names.html) - [lcnaf.madsrdf.nt.zip](https://lds-downloads.s3.amazonaws.com/lcnaf.madsrdf.nt.zip)
- [Library of Congress Subject Headings](https://id.loc.gov/authorities/subjects.html) - [lcsh.madsrdf.nt.zip](https://lds-downloads.s3.amazonaws.com/lcsh.madsrdf.nt.zip)
- [Getty AAT](http://vocab.getty.edu/) - [aat/full.zip](http://vocab.getty.edu/dataset/aat/full.zip)

## Adding A New Vocabulary

### Non-Static Fields

The [`term_type`](https://github.com/NYPL/authoritydata_solr_docker/blob/master/solr/conf/schema.xml#L69) field is often the same for an entire
vocabulary.  For example, all Genre/Form authority records are `term_type:lcgft`. But sometimes it's different depending on the record.
For example, in the [Names Records](http://id.loc.gov/authorities/names.html), the possible values are:

```ruby
['name_personal', 'name_corporate', 'name_conference', 'name_meeting']
```

When parsing a new vocabulary, you can do a facet-search in the existing Solr to figure out the possible values for a field.
By doing this:

    http://SOLR-HOST:SOLR-PORT/solr-3.5/authoritydata/select/?q=authority_code:THE-AUTHORITY-CODE&version=2.2&start=0&rows=1&indent=on&facet=true&facet.field=THE-FIELD-YOU-WANT-A-LIST-OF-VALUES-FOR&wt=json

#### Example

If you want a list of all `term_type`s of `authority_code:naf`:

    http://SOLR-HOST:SOLR-PORT/solr-3.5/authoritydata/select/?q=authority_code:naf&version=2.2&start=0&rows=1&indent=on&facet=true&facet.field=term_type&wt=json

Returns:

```json
{
  "responseHeader":{
    "status":0,
    "QTime":297},
  "response":{"numFound":8303410,"start":0,"docs":[
      {
        "id":6293002,
        "uri":"http://id.loc.gov/authorities/names/n82130233",
        "term":"Brown, Marc Tolon. Boat book",
        "term_idx":"Brown, Marc Tolon. Boat book",
        "term_type":"name_title",
        "record_id":"n82130233",
        "language":"en",
        "authority_code":"naf",
        "authority_name":"LC/NACO authority file",
        "unique_id":"naf_n82130233",
        "viaf_uri":"http://viaf.org/viaf/174589937",
        "alternate_term_idx":[
          "Brown, Marc Tolon. Marc Brown's Boat book"],
        "alternate_term":["Brown, Marc Tolon. Marc Brown's Boat book"]}]
  },
  "facet_counts":{
    "facet_queries":{},
    "facet_fields":{
      "term_type":[
        "name_personal",5582715,
        "name_corporate",1361929,
        "name_title",542367,
        "title",513364,
        "name_conference",176405,
        "geographic",126626,
        "complex_subject",4,
        "cartographics",0,
        "concept",0,
        "genre",0,
        "genreform",0,
        "geographicCode",0,
        "hierarchicalGeographic",0,
        "name",0,
        "name_corproate",0,
        "rdacarrier",0,
        "temporal",0,
        "titleInfo",0,
        "topic",0]},
    "facet_dates":{},
    "facet_ranges":{}}}
```
