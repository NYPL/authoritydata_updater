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
You can see the Solr admin interface here: http://localhost:8983/solr/admin/

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

* [LOC Carriers](http://id.loc.gov/vocabulary/carriers.json)
* [Graphic Materials (as N-Tripple/nt file)](http://id.loc.gov/static/data/downloads/vocabularygraphicMaterials.nt.both.zip)
