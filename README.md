### BloodHound Owned

A collection of files for adding and leveraging custom properties in BloodHound. A thorough overview of the ideas that led to these Custom Queries & Ruby script can be found in this blog post: http://porterhau5.com/blog/extending-bloodhound-track-and-visualize-your-compromise/

These are intended, although not required, to be used with a forked version of BloodHound found here: https://github.com/porterhau5/BloodHound

Files in the `example-files` directory can be used with the Ruby script and the [BloodHoundExampleDB.graphdb](https://github.com/BloodHoundAD/BloodHound/tree/master/BloodHoundExampleDB.graphdb) for demonstration or development purposes. Usage examples are shown below.

#### Quickstart

Using these requires Neo4j, a populated database, and a BloodHound app.

The Ruby script (`bh-owned.rb`) and custom queries (`customqueries.json`) can be used with the official BloodHound app. However, the UI customizations are currently only available in the customized app found in this [forked BloodHound repo](https://github.com/porterhau5/BloodHound).

Current UI customizations include:
 * Node highlighting in custom queries
 * Custom properties displayed on Node Info tab
 * Run custom queries from Node Info tab

If you'd like to try out the features added in the customized BloodHound app, then follow the official BloodHound [install directions](https://github.com/BloodHoundAD/BloodHound/wiki/Getting-started) but substitute the forked repo URL (https://github.com/porterhau5/BloodHound) for the official repo URL in step 2 (cloning the repository).

You'll then need to build the custom app. Instructions for doing so are in [BloodHound's wiki](https://github.com/BloodHoundAD/BloodHound/wiki/Building-BloodHound-from-source).

To use the custom queries, first copy the `customqueries.json` file to the Electron project's home folder:
 * Windows: `~\AppData\Roaming\bloodhound\`
 * Mac: `~/Library/Application Support/bloodhound/`
 * Linux: I'm not sure. If someone does this on Linux and figures this out then let me know.

Refresh or restart BloodHound for the changes to take effect. They can be found in the Search Container (top-left) on the Queries tab underneath the Custom Queries header.

#### bh-owned.rb Usage

This script is the primary means for updating the Neo4j database to support the custom queries and UI enhancements.
```
$ ruby bh-owned.rb
Usage: ruby bh-owned.rb [options]
    -u, --username <username>        Neo4j database username (default: 'neo4j')
    -p, --password <password>        Neo4j database password (default: 'BloodHound')
    -U, --url <url>                  URL of Neo4j RESTful host  (default: 'http://127.0.0.1:7474/')
    -n, --nodes                      get all node names
    -a, --add <file>                 add 'owned' and 'wave' property to nodes in <file>
    -s, --spw <file>                 add 'SharesPasswordWith' relationship between all nodes in <file>
    -w, --wave <num>                 value to set 'wave' property (override default behavior)
        --reset                      remove all custom properties and SharesPasswordWith relationships
    -e, --examples                   reference doc of customized Cypher queries for BloodHound
```
It helps to create a few new indexes to help with query performance. This can be done using Neo4j's web browser or BloodHound's Raw Query feature (I recommend Neo4j's web browser for this):
```
CREATE INDEX ON :Group(wave)
CREATE INDEX ON :User(wave)
CREATE INDEX ON :Computer(wave)
```
Data is ingested using the script's `-a` flag with a file passed as an argument. Files should be in CSV format with the name of the compromised node first, followed by the method of compromise (these files can be found in the `example-files` dir):
```
$ cat 1st-wave.txt
BLOPER@INTERNAL.LOCAL,LLMNR wpad
JCARNEAL@INTERNAL.LOCAL,NBNS wpad

$ ruby bh-owned.rb -a 1st-wave.txt
[*] Using default username: neo4j
[*] Using default password: BloodHound
[*] Using default URL: http://127.0.0.1:7474/
[*] No previously owned nodes found, setting wave to 1
[+] Success, marked 'BLOPER@INTERNAL.LOCAL' as owned in wave '1' via 'LLMNR wpad'
[+] Success, marked 'JCARNEAL@INTERNAL.LOCAL' as owned in wave '1' via 'NBNS wpad'
[*] Finding spread of compromise for wave 1
[+] 2 nodes found:
DOMAIN USERS@INTERNAL.LOCAL
SYSTEM38.INTERNAL.LOCAL
```
The script will first query the database and determine the latest wave added. It then increments it by one so that the incoming additions will be in the new wave. You can override this behavior by setting the `-w` flag to the preferred wave value.

Once the wave number is determined, the script takes the following steps:

 * Creates the Cypher queries to add the nodes
 * Creates the Cypher query to find the spread of compromise for the new wave
 * Wraps it all in JSON
 * POSTs the request to the REST endpoint

Until more options and error-checking is thrown in, each wave should be added separately:
```
$ cat 2nd-wave.txt
ZDEVENS@INTERNAL.LOCAL,Password spray
BPICKEREL@INTERNAL.LOCAL,Password spray

$ ruby bh-owned.rb -a 2nd-wave.txt
[*] Using default username: neo4j
[*] Using default password: BloodHound
[*] Using default URL: http://127.0.0.1:7474/
[+] Success, marked 'ZDEVENS@INTERNAL.LOCAL' as owned in wave '2' via 'Password spray'
[+] Success, marked 'BPICKEREL@INTERNAL.LOCAL' as owned in wave '2' via 'Password spray'
[*] Finding spread of compromise for wave 2
[+] 5 nodes found:
BACKUP3@INTERNAL.LOCAL
BACKUP_SVC@INTERNAL.LOCAL
CONTRACTINGS@INTERNAL.LOCAL
DATABASE5.INTERNAL.LOCAL
MANAGEMENT3.INTERNAL.LOCAL
```
The `-n` flag can be used to dump the names of all nodes from the database:
```
$ ruby bh-owned.rb -n
[*] Using default username: neo4j
[*] Using default password: BloodHound
[*] Using default URL: http://127.0.0.1:7474/
AANSTETT@EXTERNAL.LOCAL
ABRENES@INTERNAL.LOCAL
ABROOKS@EXTERNAL.LOCAL
ABROOKS_A@EXTERNAL.LOCAL
ACASTERLINE@INTERNAL.LOCAL
ACHAVARIN@EXTERNAL.LOCAL
ACLAUSS@INTERNAL.LOCAL
<snipped>
```
The `-e` flag can be used to show examples of Cypher queries leveraging the custom properties. The juicy ones have been rolled up into the 'Custom Queries' available in the app:
```
$ ruby bh-owned.rb -e
Find all owned Domain Admins:
MATCH (n:Group) WHERE n.name =~ '.*DOMAIN ADMINS.*' WITH n MATCH p=(n)<-[r:MemberOf*1..]-(m) WHERE exists(m.owned) RETURN nodes(p),relationships(p)

Find Shortest Path from owned node to Domain Admins:
MATCH p=shortestPath((n)-[*1..]->(m)) WHERE exists(n.owned) AND m.name=~ '.*DOMAIN ADMINS.*' RETURN p

List all directly owned nodes:
MATCH (n) WHERE exists(n.owned) RETURN n

Find all nodes in wave $num:
MATCH (n)-[r]->(m) WHERE n.wave=$num AND m.wave=$num RETURN n,r,m

Show all waves up to and including wave $num:
MATCH (n)-[r]->(m) WHERE n.wave<=$num RETURN n,r,m

Set owned and wave properties for a node (named $name, compromised via $method in wave $num):
MATCH (n) WHERE (n.name = '$name') SET n.owned = '$method', n.wave = $num

Find spread of compromise for owned nodes in wave $num:
OPTIONAL MATCH (n1:User {wave:$num}) WITH collect(distinct n1) as c1 OPTIONAL MATCH (n2:Computer {wave:$num}) WITH collect(distinct n2) + c1 as c2 UNWIND c2 as n OPTIONAL MATCH p=shortestPath((n)-[*..20]->(m)) WHERE not(exists(m.wave)) WITH DISTINCT(m) SET m.wave=$num

Show clusters of password reuse:
MATCH p=(n)-[r:SharesPasswordWith]-(m) RETURN p
```
Use `-s` to add a file containing a list of nodes with the same password. This will create a new relationship, "SharesPasswordWith", between each node in the list. Useful for representing Computers with a common local admin password, or Users that use the same password for multiple accounts:
```
$ cat common-local-admins.txt
MANAGEMENT3.INTERNAL.LOCAL
FILESERVER6.INTERNAL.LOCAL
SYSTEM38.INTERNAL.LOCAL
DESKTOP40.EXTERNAL.LOCAL

$ ruby bh-owned.rb -s common-local-admins.txt
[*] Using default username: neo4j
[*] Using default password: BloodHound
[*] Using default URL: http://127.0.0.1:7474/
[+] Created SharesPasswordWith relationship between 'MANAGEMENT3.INTERNAL.LOCAL' and 'FILESERVER6.INTERNAL.LOCAL'
[+] Created SharesPasswordWith relationship between 'MANAGEMENT3.INTERNAL.LOCAL' and 'SYSTEM38.INTERNAL.LOCAL'
[+] Created SharesPasswordWith relationship between 'MANAGEMENT3.INTERNAL.LOCAL' and 'DESKTOP40.EXTERNAL.LOCAL'
[+] Created SharesPasswordWith relationship between 'FILESERVER6.INTERNAL.LOCAL' and 'SYSTEM38.INTERNAL.LOCAL'
[+] Created SharesPasswordWith relationship between 'FILESERVER6.INTERNAL.LOCAL' and 'DESKTOP40.EXTERNAL.LOCAL'
[+] Created SharesPasswordWith relationship between 'SYSTEM38.INTERNAL.LOCAL' and 'DESKTOP40.EXTERNAL.LOCAL'
```
If you want to start over and remove any custom properties & relationships from your database nodes, use `--reset`:
```
$ ruby bh-owned.rb --reset
[*] Using default username: neo4j
[*] Using default password: BloodHound
[*] Using default URL: http://127.0.0.1:7474/
[*] Removing all custom properties and SharesPasswordWith relationships
```

#### Custom Queries
There are currently four custom queries in this set:
 * __Find all owned Domain Admins__: Same as the "Find all Domain Admins" query, but instead only show Users with `owned` property.
 * __Find Shortest Paths from owned node to Domain Admins__: Same as the "Find Shortest Paths to Domain Admins" query, but instead only show paths originating from an `owned` node.
 * __Show wave__: Show only the nodes compromised in a selected wave. Useful for focusing in on newly-compromised nodes.
 * __Show delta for wave__: Show all compromised nodes up to a selected wave, and will highlight the nodes gained in that wave. Useful for visualizing privilege gains as access expands.

Check out the "[UI Customizations and Custom Queries](http://porterhau5.com/blog/extending-bloodhound-track-and-visualize-your-compromise/#ui-customizations-and-custom-queries)" section of the blog post to see examples of these custom queries in action.

#### Known Issues and Future Development
 * Add sanity check for nodes to see if they exist before trying to set new properties
 * Add additional queries to pull specific nodes from database and write to output file
 * Queries sometimes hang when dealing with data at a massive scale, then script crashes
 * Showing deltas for large waves can be stressful on the UI, should add ability to LIMIT results to a user-defined threshold
 * Verbose output for query results (ex: list of nodes added in spread of compromise, time taken to return results)
 * General HTTP error-checking
 * More, broader ideas [here](http://porterhau5.com/blog/extending-bloodhound-track-and-visualize-your-compromise/#next-steps)

#### Acknowledgements
[skawasec](https://twitter.com/skawasec) and [pfizzell](https://twitter.com/pfizzell) for the sound advice and feedback. [CptJesus](https://twitter.com/CptJesus), [_wald0](https://twitter.com/_wald0), and [harmj0y](https://twitter.com/harmj0y) for making a tremendous platform.
