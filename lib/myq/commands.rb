#!/usr/bin/env ruby
# coding: utf-8
require 'thor'
require 'mysql2-cs-bind'
require 'yajl'
require 'yaml'

module Myq
  class Commands < Thor
    class_option :profile, aliases: '-p', type: :string, default: 'default', desc: 'profile by .database.yml'
    map '-q' => :query_inline
    map '-f' => :query_file
    map '-s' => :sample
    map '-l' => :show_table
    map '-v' => :version

    def initialize(args = [], options = {}, config = {})
      super(args, options, config)
      global_options = config[:shell].base.options
      if File.exist?("#{ENV['HOME']}/.database.yml")
        data = YAML.load_file("#{ENV['HOME']}/.database.yml")[global_options['profile']]
      else
        puts "please create #{ENV['HOME']}/.database.yml"
        exit 1
      end
      @client = Mysql2::Client.new(data)
    end

    desc '-q [sql]', 'inline query'
    def query_inline(query)
      query(query)
    end

    desc '-f [file]', 'query by sql file'
    def query_file(file)
      query(File.read(file))
    end

    desc '-s [table name]', 'sampling query, default limit 10'
    option :limit, type: :numeric, default: 10, aliases: '-n', desc: 'limit count'
    def sample(table)
      query("select * from #{table} limit #{options['limit']}")
    end

    desc '-l [table name]', 'show table info '
    def show_table(table_name = nil)
      if table_name.nil?
        query('show tables')
      else
        query("show columns from #{table_name}")
      end
    end

    desc 'version', 'show version'
    def version
      puts VERSION
      puts `mysql -V`
    end

    private

    def query(query)
      result = []
      query.split(';').each do |sql|
        res = @client.xquery(sql, :cast => false)
        next if res.nil?
        res.each do |record|
          result << record
        end
      end
      puts Yajl::Encoder.encode(result)
    end
  end
end
