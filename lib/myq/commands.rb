#!/usr/bin/env ruby
# coding: utf-8
require 'thor'
require 'yajl'

module Myq
  class Commands < Thor
    class_option :profile, aliases: '-p', type: :string, default: 'default', desc: 'profile by .database.yml'
    class_option :pretty, aliases: '-P', type: :boolean, default: false, desc: 'pretty print'
    class_option :config, aliases: '--config', type: :string, default: "#{ENV['HOME']}/.database.yml", desc: 'config file'
    map '--ps' => :processlist
    map '-q' => :query_inline
    map '-c' => :count
    map '-f' => :query_file
    map '-s' => :sample
    map '-l' => :show_table
    map '--dbs' => :show_databases
    map '-v' => :show_variables
    map '-I' => :bulk_insert_json
    map '-V' => :version
    map '--set' => :set_variable
    map '-C' => :console
    map '-D' => :dump
    map '-R' => :restore
    map '--template' => :template

    def initialize(args = [], options = {}, config = {})
      super(args, options, config)
      @global_options = config[:shell].base.options
      @core = Myq::Core.new(get_profile(@global_options))
    end

    desc '-q [sql]', 'inline query'
    option :interval, type: :numeric, default: 0, aliases: '-i', desc: 'loop interval'
    def query_inline(query)
      loop do
        puts_json(@core.query(query))
        break if options['interval'] == 0
        sleep options['interval']
      end
    end

    desc '-I [table]', 'bulk insert json, auto create table!'
    option :update_columns, type: :array, aliases: '-u', default: [], desc: 'on duplicate key update columns'
    def bulk_insert_json(table)
      data = @core.parse_json(STDIN.read)
      sql = @core.make_bulk_insert_sql(table, data, options['update_columns'])
      @core.query_single(sql)
    end

    desc '-f [file]', 'query by sql file'
    def query_file(file)
      puts_json(@core.query(File.read(file)))
    end

    desc '-s [table name]', 'sampling query, default limit 10'
    option :where, type: :hash, default: nil,  aliases: '-w', desc: 'id'
    option :limit, type: :numeric, default: 10, aliases: '-n', desc: 'limit count'
    option :all, type: :boolean, default: false, aliases: '-a', desc: 'all'
    def sample(table)
      limit = options['all'] ? "" : "limit #{options['limit']}"
      where = options['where'].nil? ? "" : "where #{options['where'].map{ |k, v| k + ' = ' + v }.join(' and ') }"
      puts_json(@core.query("select * from #{table} #{where} order by id desc #{limit}"))
    end

    desc '-c [table name] -k [group by keys]', 'count record, group by keys'
    option :keys, type: :array, aliases: '-k', default: [], desc: 'group by keys'
    def count(table)
      puts_json(@core.count(table, options['keys']))
    end

    desc '-l [table name]', 'show table info '
    def show_table(table_name = nil)
      puts_json(@core.tables(table_name))
    end

    desc '--dbs', 'show databases'
    def show_databases
      puts_json(@core.databases)
    end

    desc '--ps', 'show processlist'
    def processlist
      puts_json(@core.processlist)
    end

    desc '-v [like query]', 'show variables '
    def show_variables(like = nil)
      puts_json(@core.variables(like))
    end

    desc '--template [erb]', 'show variables '
    option :output_template, aliases: '-o', type: :string, default: Dir.pwd, desc: 'output directory'
    option :format, aliases: '--format [camelcase or underscore]', type: :string, default: nil, desc: 'filename format'
    def template(template_path)
      @core.render_template(template_path, options['output_template'], options['format'])
    end

    desc '-C', 'mysql console'
    def console
      @core.console
    end

    desc '-D', 'mysql dump'
    def dump(filepath = "#{@profile['database']}.dump")
      @core.dump(filepath)
    end

    desc '-R', 'mysql restore'
    def restore(filepath = "#{@profile['database']}.dump")
      @core.restore(filepath)
    end

    desc 'create_db [database]', 'create database'
    def create_db(database)
      @core.create_database_utf8(database)
    end

    desc '--set -v key=value;', 'set global variable'
    option :variables, type: :hash, aliases: '-v', required: true, desc: 'set variables'
    def set_variable(key = nil, value = nil)
      options['variables'].each do |k, v|
        @core.query("SET GLOBAL #{k}=#{v}")
      end
    end

    desc 'version', 'show version'
    def version
      puts VERSION
      puts `mysql -V`
    end

    private

    def get_profile(options)
      if File.exist?(options['config'])
        profile = YAML.load_file(options['config'])[options['profile']]
      else
        puts "please create #{ENV['HOME']}/.database.yml"
        exit 1
      end
      profile
    end

    def puts_json(object)
      puts Yajl::Encoder.encode(object, pretty: @global_options['pretty'])
    end

  end
end
