# Authority Data Updater

When users search for authority records in [MMS](https://github.com/nypl/mms), the
search queries a Solr index. The documents in that index need to be updated periodically.

**This tool parses various vocabulary files and POSTS their contents to a Solr index.**

## Building

1.  `cp ./env.example ./.env`
1.  Fill in `.env`
2.  `docker-compose build`

## Running

`docker-compose up`

## Git Workflow

TODO: Write code to actually run.

## Deployment

TODO...
