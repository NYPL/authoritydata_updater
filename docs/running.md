# Running The Authority Updater

The application is mounted to `/opt/authoritydata_udpater/` inside the container.
If you need files inside the container, put them in the app directory on your localhost.
To start a container run `docker-compose run updater bash` from the app directory on your localhost.

There's a multi-stage process to parse information from [N-Tripple](https://en.wikipedia.org/wiki/N-Triples), and post relevant information from it to Solr.

0. [(optional, but recommended) Trim irrelevant info from NT file](#trimmingStatements).
1. [Convert NT file into a newline-delimited file of JSON, to be posted to Solr](#convertingToJSON).
2. [Post the documents to Solr](#postToSolr).

<a name="trimmingStatements"><a/>
## Trimming Irrelevant Statements from NT File

N-Tripple/`.nt` files can be GIGANTIC.
For example, the Name Authority one is 96.8 GB / 748,879,531 lines.
  We don't careabout many of the statements in those files.
We don't use  those statements to post info to Solr.
For example, we never care about statements with the predicate `http://www.w3.org/2000/01/rdf-schema#seeAlso`.

```
ruby ./clean_nt_file.rb ./large-file.nt ./desired-smaller-file.nt
```

**The can shrink files by 66%** - making them MUCH faster to run through `authoritydata_updater.rb`.

<a name="convertingToJSON"></a>
## Convert NT file into a newline-delimited file of JSON, to be posted to Solr.

```
ruby /opt/authoritydata_udpater/authoritydata_updater.rb --vocabulary graphic_materials --source /opt/authoritydata_udpater/graphicMaterials.both.nt

# This can take days for the giant 'names' vocabulary.
# For all options see ruby /opt/authoritydata_udpater/authoritydata_updater.rb --help
```

This command would generate 2 files.

* lcgf_[timestamp].db
* lcgf_[timestamp].json

The `.db` file is a [gdbm](https://ruby-doc.org/stdlib-2.5.3/libdoc/gdbm/rdoc/GDBM.html) key/value store, used to roll-up
data that's spread across the NT files.

The `.json` file is a newline-delimited file of JSON documents, that will be posted to Solr.

### Recovering from an interrupted conversion

If this gets interrupted you can ask to start at a certain line of of the nt file, and re-use a `.db` file.

```
ruby /opt/authoritydata_udpater/authoritydata_updater.rb --vocabulary genre_and_form --source small_genre_and_form.nt -n 1000 -d lcgft_12345.db


# In the past, lcgft_12345.db was generated but processing pooped out on line 999.
```

<a name='postToSolr'></a>
## Post The Documents To Solr.

```
ruby post_to_solr -f lcgft_12345.json --solrUrl $SOLR_URL --username $USERNAME --password $PASSWORD
```
