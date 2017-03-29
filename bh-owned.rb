#!/usr/bin/ruby env
#Encoding: UTF-8

# Written by: @porterhau5 - 3/29/17

require 'net/http'
require 'uri'
require 'json'
require 'optparse'

# Recommended to create the following indexes:
#   CREATE INDEX ON :Group(wave)
#   CREATE INDEX ON :User(wave)
#   CREATE INDEX ON :Computer(wave)
# Show indexes with ":schema"

# This method changes text color to a supplied integer value which correlates to Ruby's color representation
def colorize(text, color_code)
  "\e[#{color_code}m#{text}\e[0m"
end

# This method changes text color to red
def red(text)
  colorize(text, 31)
end

# This method changes text color to blue
def blue(text)
  colorize(text, 34)
end

# This method changes text color to green
def green(text)
  colorize(text, 32)
end

def examples()
  puts "Find all owned Domain Admins:"
  puts "MATCH (n:Group) WHERE n.name =~ '.*DOMAIN ADMINS.*' WITH n MATCH p=(n)<-[r:MemberOf*1..]-(m) WHERE exists(m.owned) RETURN nodes(p),relationships(p)"
  puts ""
  puts "Find Shortest Path from owned node to Domain Admins:"
  puts "MATCH p=shortestPath((n)-[*1..]->(m)) WHERE exists(n.owned) AND m.name=~ '.*DOMAIN ADMINS.*' RETURN p"
  puts ""
  puts "List all directly owned nodes:"
  puts "MATCH (n) WHERE exists(n.owned) RETURN n"
  puts ""
  puts "Find all nodes in wave $num:"
  puts "MATCH (n)-[r]->(m) WHERE n.wave=$num AND m.wave=$num RETURN n,r,m"
  puts ""
  puts "Show all waves up to and including wave $num:"
  puts "MATCH (n)-[r]->(m) WHERE n.wave<=$num RETURN n,r,m"
  puts ""
  puts "Set owned and wave properties for a node (named $name, compromised via $method in wave $num):"
  puts "MATCH (n) WHERE (n.name = '$name') SET n.owned = '$method', n.wave = $num"
  puts ""
  puts "Find spread of compromise for owned nodes in wave $num:"
  puts "OPTIONAL MATCH (n1:User {wave:$num}) WITH collect(distinct n1) as c1 OPTIONAL MATCH (n2:Computer {wave:$num}) WITH collect(distinct n2) + c1 as c2 UNWIND c2 as n OPTIONAL MATCH p=shortestPath((n)-[*..20]->(m)) WHERE not(exists(m.wave)) WITH DISTINCT(m) SET m.wave=$num"
  puts ""
  puts "Show clusters of password reuse:"
  puts "MATCH p=(n)-[r:SharesPasswordWith]-(m) RETURN p"
  exit
end

def craft(options)
  # get names of all nodes
  hash = Hash.new { |h,k| h[k] = [] }
  if options.nodes
    hash['statements'] << {'statement' => "MATCH (n) RETURN (n.name)"}
    return hash.to_json

  # remove owned and wave properties, delete SharesPasswordWith relationships
  elsif options.reset
    puts blue("[*]") + " Removing all custom properties and SharesPasswordWith relationships"
    hash['statements'] << {'statement' => "MATCH (n) WHERE exists(n.wave) OR exists(n.owned) REMOVE n.wave, n.owned"}
    hash['statements'] << {'statement' => "MATCH (n)-[r:SharesPasswordWith]-(m) DELETE r"}
    return hash.to_json

  # once nodes are added, set 'wave' for newly owned nodes
  elsif options.spread
    hash['statements'] << {'statement' => "OPTIONAL MATCH (n1:User {wave:#{options.wave}}) WITH collect(distinct n1) as c1 OPTIONAL MATCH (n2:Computer {wave:#{options.wave}}) WITH collect(distinct n2) + c1 as c2 UNWIND c2 as n OPTIONAL MATCH p=shortestPath((n)-[*..20]->(m)) WHERE not(exists(m.wave)) WITH DISTINCT(m) SET m.wave=#{options.wave} RETURN m.name, #{options.wave}", 'includeStats' => true}
    return hash.to_json

  # add 'owned' property to nodes from file
  elsif options.add
    File.foreach(options.add) do |node|
      name, method = node.split(',', 2)
      # if -w flag set, then overwrite previous property if it exists, otherwise don't overwrite
      if options.forceWave.nil?
        hash['statements'] << {'statement' => "MATCH (n) WHERE (n.name = \"#{name.chomp}\") SET n.owned = \"#{method.chomp}\", n.wave = #{options.wave} RETURN \'#{name.chomp}\', \'#{options.wave}\', \'#{method.chomp}\'", 'includeStats' => true}
      else
        # this uses a Cypher hack for doing if/else conditionals
        hash['statements'] << {'statement' => "MATCH (n) WHERE (n.name = \"#{name.chomp}\") FOREACH (ignoreMe in CASE WHEN exists(n.wave) THEN [1] ELSE [] END | SET n.wave=n.wave) FOREACH (ignoreMe in CASE WHEN not(exists(n.wave)) THEN [1] ELSE [] END | SET n.owned = \"#{method.chomp}\", n.wave = #{options.wave}) RETURN \'#{name.chomp}\',\'#{options.wave}\',\'#{method.chomp}\'", 'includeStats' => true}
      end
    end
    return hash.to_json

  # Create SharesPasswordWith relationships between all nodes in file
  elsif options.spw
    nodes = []
    File.foreach(options.spw) do |node|
      nodes.push(node)
    end
    nodes.combination(2).to_a.each do |n,m|
      hash['statements'] << {'statement' => "MATCH (n {name:\"#{n.chomp}\"}),(m {name:\"#{m.chomp}\"}) WITH n,m CREATE UNIQUE (n)-[:SharesPasswordWith]->(m) WITH n,m CREATE UNIQUE (n)<-[:SharesPasswordWith]-(m) RETURN \'#{n.chomp}\',\'#{m.chomp}\'", 'includeStats' => true}
    end
    return hash.to_json
  end
end

def sendrequest(options)
  uri = URI.parse(options.url)

  # Create the HTTP object
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri.request_uri)
  request["Accept"] = "application/json; charset=UTF-8"
  request.content_type = "application/json"
  request.basic_auth options.username, options.password
  if options.wave == -1
    hash = Hash.new { |h,k| h[k] = [] }
    hash['statements'] << {'statement' => "MATCH (n) WHERE exists(n.owned) RETURN max(n.wave)"}
    request.body = hash.to_json
  else
    request.body = craft(options)
  end

  # Send the request
  response = http.request(request)

  parse(options, response)
end

def parse(options, response)
  #
  # print all nodes
  #
  if options.nodes
    out = []
    data = JSON.parse(response.body)
    # cycle through results (should only be 1)
    data['results'].each do |r|
      # cycle through rows returned
      r['data'].each do |d|
        # add to array
        out.push(d['row'])
      end if r['data'].any?
    end if data['results'].any?
    # sort, uniq, display
    puts out.sort.uniq
  #
  # determine wave number
  #
  elsif options.wave == -1
    resp = JSON.parse(response.body)
    resp['results'].each do |r|
      r['data'].each do |d|
        if d['row'] == [nil]
          puts blue("[*]") + " No previously owned nodes found, setting wave to 1"
          options.wave = 1
        else
          options.wave = d['row'][0].to_i + 1
        end
      end if r['data'].any?
    end if resp['results'].any?
  #
  # parse spread of compromise
  #
  elsif options.spread
    resp = JSON.parse(response.body)
    resp['results'].each do |r|
      puts blue("[*]") + " Finding spread of compromise for wave #{options.wave}"
      r['stats'].each do |s|
        # check stats to see if properties were set
        if s.first == "properties_set" and s.last == 0
          # if there are records in data, then properties already set
          if r['data'].any?
            r['data'].each do |d|
              puts blue("[*]") + " No additional nodes found for wave #{options.wave}"
            end
          else
            puts red("[-]") + " No additional nodes found for wave #{options.wave}"
          end
        elsif s.first == "properties_set" and s.last != 0
          out = []
          count = 0
          # cycle through rows returned
          r['data'].each do |d|
            next unless not d['row'][0].to_s.empty?
            out.push(d['row'][0])
            count += 1
          end if r['data'].any?
          puts green("[+]") + " #{count} nodes found:"
          puts out.sort.uniq
        end
      end if r['stats'].any?
    end if resp['results'].any?
  #
  # parse nodes added
  #
  elsif options.add
    success = true
    resp = JSON.parse(response.body)
    resp['results'].each do |r|
      # node names provided are returned as columns
      names = []
      r['columns'].each do |c|
        names.push(c)
      end
      r['stats'].each do |s|
        # check stats to see if properties were set
        if s.first == "properties_set" and s.last == 0
          # if there are records in data, then properties already set
          if not r['data'].any?
            puts red("[-]") + " Properties not added for #{names.first} (node not found, check spelling?)"
            success = false
          end
        elsif s.first == "properties_set" and s.last == 2
          puts green("[+]") + " Success, marked #{names.first} as owned in wave #{names[1]} via #{names.last}"
        elsif s.first == "properties_set" and s.last == 1
          puts blue("[*]") + " Properties already exist for #{names.first}, skipping (overwrite with flag -w <num>)"
        end
      end if r['stats'].any?
    end if resp['results'].any? 
    # if all nodes were added successfully or skipped, find spread for new nodes
    if success
      options.spread = true
      sendrequest(options)
    else
      puts red("[-]") + " Skipping finding spread of compromise due to \"node not found\" error"
    end
  #
  # parse SharesPasswordWith
  #
  elsif options.spw
    resp = JSON.parse(response.body)
    resp['results'].each do |r|
      # node names provided are returned as columns
      names = []
      r['columns'].each do |c|
        names.push(c)
      end
      r['stats'].each do |s|
        # check stats to see if a relationship was created
        if s.first == "relationships_created" and s.last == 0
          # if there are records in data, then relationship already exists
          if r['data'].any?
            r['data'].each do |d|
              puts blue("[*]") + " Relationship already exists for #{names.first} and #{names.last}"
            end
          else
            puts red("[-]") + " Relationship not created for #{names.first} and #{names.last} (check spelling)"
          end
        elsif s.first == "relationships_created" and s.last == 2
          puts green("[+]") + " Created SharesPasswordWith relationship between #{names.first} and #{names.last}"
        elsif s.first == "relationships_created" and (s.last != 0 or s.last != 2)
          puts "Something went wrong when creating SharesPasswordWith relationship"
        end
      end if r['stats'].any?
    end if resp['results'].any?
  end
  # uncomment line below to debug
  #puts JSON.pretty_generate(JSON.parse(response.body))
end

def main()
  options = OpenStruct.new
  ARGV << '-h' if ARGV.empty?
  OptionParser.new do |opt|
    opt.banner = "Usage: ruby bh-owned.rb [options]"
    opt.on('-u', '--username <username>', 'Neo4j database username (default: \'neo4j\')') { |o| options.username = o }
    opt.on('-p', '--password <password>', 'Neo4j database password (default: \'BloodHound\')') { |o| options.password = o }
    opt.on('-U', '--url <url>', 'URL of Neo4j RESTful host  (default: \'http://127.0.0.1:7474/\')') { |o| options.url = o }
    opt.on('-n', '--nodes', 'get all node names') { |o| options.nodes = o }
    opt.on('-a', '--add <file>', 'add \'owned\' and \'wave\' property to nodes in <file>') { |o| options.add = o }
    opt.on('-s', '--spw <file>', 'add \'SharesPasswordWith\' relationship between all nodes in <file>') { |o| options.spw = o }
    opt.on('-w', '--wave <num>', Integer, 'value to set \'wave\' property (override default behavior)') { |o| options.wave = o }
    opt.on('--reset', 'remove all custom properties and SharesPasswordWith relationships') { |o| options.reset = o }
    opt.on('-e', '--examples', 'reference doc of customized Cypher queries for BloodHound') { |o| options.examples = o }
  end.parse!

  if options.examples
    examples()
  end

  if options.username.nil?
    options.username = 'neo4j'
    puts blue("[*]") + " Using default username: neo4j"
  end

  if options.password.nil?
    options.password = 'BloodHound'
    puts blue("[*]") + " Using default password: BloodHound"
  end

  if options.url.nil?
    options.url = 'http://127.0.0.1:7474/db/data/transaction/commit'
    puts blue("[*]") + " Using default URL: http://127.0.0.1:7474/"
  else
    options.url = options.url.gsub(/\/+$/, '') + '/db/data/transaction/commit'
    puts blue("[*]") + " URL set: #{options.url}"
  end

  if options.add
    if File.exist?(options.add) == false
      puts red("#{options.add} does not exist! Exiting.")
      exit 1
    elsif options.wave.nil?
      # -1 means we don't know current max "n.wave" value
      options.wave = -1
      sendrequest(options)
      options.forceWave = true
    end
  end

  if options.spw
    if File.exist?(options.spw) == false
      puts red("#{options.spw} does not exist! Exiting.")
      exit 1
    end
  end

  options.spread = false

  sendrequest(options)
end

main()
