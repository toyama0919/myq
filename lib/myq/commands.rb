#!/usr/bin/env ruby
# coding: utf-8
require 'thor'
require 'mysql2-cs-bind'
require 'yajl'
require 'yaml'

module Myq
  class Commands < Thor
    class_option :host, aliases: '-h', type: :string, default: 'localhost', desc: 'host'
    class_option :username, aliases: '-u', type: :string, default: 'root', desc: 'username'
    class_option :password, aliases: '-p', type: :string, default: '', desc: 'password'
    class_option :port, type: :numeric, default: 3306, desc: 'port'
    class_option :database, aliases: '-d', type: :string, desc: 'database'
    class_option :profile, aliases: '--pr', type: :string, default: 'default', desc: 'profile by .database.yml'
    map '-q' => :query_inline
    map '-f' => :query_file
    map '-s' => :sample
    map '-v' => :version

    def initialize(args = [], options = {}, config = {})
      super(args, options, config)
      global_options = config[:shell].base.options
      if File.exist?("#{ENV['HOME']}/.database.yml")
        data = YAML.load_file("#{ENV['HOME']}/.database.yml")[global_options['profile']]
        host = data['host']
        username = data['username']
        password = data['password']
        database = data['database']
        port = data['port']
      else
        host = global_options['host']
        username = global_options['username']
        password = global_options['password']
        database = global_options['database']
        port = global_options['port']
      end
      @client = Mysql2::Client.new(host: host, username: username, password: password, database: database, port: port)
    end

    desc "-q [sql]", "inline query"
    def query_inline(query)
      query(query)
    end

    desc "-f [file]", "query by sql file"
    def query_file(file)
      query(File.read(file))
    end

    desc "-s [table name]", "sampling query, default limit 10"
    option :limit, type: :numeric, default: 10, aliases: '-n', desc: 'limit count'
    def sample(table)
      query("select * from #{table} limit #{options['limit']}")
    end

    desc "version", "show version"
    def version
      puts VERSION
    end

    private

    def query(query)
      result = []
      query.split(';').each do |sql|
        res = @client.xquery(sql)
        res.each do |record|
          puts Yajl::Encoder.encode(record)
        end
      end
    end
  end
end
