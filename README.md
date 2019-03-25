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

## Running authoritydata_updater.rb

Looking at [docker-compose.yml](./docker-compose.yml), locally we pass in the values to the `--source` and `--vocabulary` options
through the environment variables in .env In production, we'd probably just set the values when we overwrite entrypoint.

## Confirming Solr Is Up

You can confirm that your solr core exists by going to: `http://localhost:8983/solr/admin/cores?action=STATUS&core=authoritydata`
You can see the Solr admin interface here: http://localhost:8983/solr/admin/

## Git Workflow

TODO: Write code to actually run.

## Deployment

TODO...
