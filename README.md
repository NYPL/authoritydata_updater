# Authority Data Updater

When users search for authority records in [MMS](https://github.com/nypl/mms), the
search queries a Solr index. The documents in that index need to be updated periodically.

**This tool parses various vocabulary files and POSTS their contents to a Solr index.**  
Locally - you can point it to [a dockerized Solr 3.5 that has a core named "authoritydata"](https://github.com/NYPL/authoritydata_solr_docker).

## Building

1.  clone [NYPL/authoritydata_solr_docker](https://github.com/NYPL/authoritydata_solr_docker) into a sibling directory of this app.
2.  In this directory `cp ./.env.example ./.env`
3.  Fill in the `.env`
4.  `docker-compose build`

## Running

1.  `docker-compose up`

### Running authoritydata_updater.rb

Looking at [docker-compose.yml](./docker-compose.yml), locally we pass in the values to the `--source` and `--vocabulary` options
through the environment variables in .env In production, we'd probably just set the values when we overwrite entrypoint.

### Confirming Solr Is Up

You can confirm that your solr core exists by going to: `http://localhost:8983/solr/admin/cores?action=STATUS&core=authoritydata`
You can see the Solr admin interface here: <http://localhost:8983/solr/admin/>

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

As of now, when a remote Solr needs to be updated - this is run on developers'
machines. It is not deployed to any remote environments.

## Supported Vocabularies

This code _may_ work for a lot of vocabularies but these are the ones  
we've tested on:

-   [LOC Carriers](http://id.loc.gov/vocabulary/carriers.json)
-   [Graphic Materials (as N-Tripple/nt file)](http://id.loc.gov/static/data/downloads/vocabularygraphicMaterials.nt.both.zip)
-   [Genre & Form Terms (as N-Tripple/nt file)](http://id.loc.gov/static/data/downloads/authoritiesgenreForms.nt.madsrdf.zip)

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
