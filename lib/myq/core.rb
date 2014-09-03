#!/usr/bin/env ruby
# coding: utf-8
require 'mysql2-cs-bind'
require 'active_support/core_ext/string'
require 'yaml'
require 'yajl'

module Myq
  class Core

    def initialize(profile)
      @profile = profile
      @client = Mysql2::Client.new(profile)
    end

    def make_bulk_insert_sql(table, data, update_columns)
      first = data.class == Array ? data.first : data
      auto_create_table(table, first)
      columns = table_info(table).to_a
      values_array = []
      if data.class == Array
        data.each do |record|
          values_array << to_value_string(columns, record)
        end
      else
        values_array << to_value_string(columns, data)
      end
      sql = %Q{
      INSERT INTO #{table}
      (#{columns.map { |column| "\`" + column['COLUMN_NAME'] + "\`" }.join(',')})
      VALUES
      #{values_array.join(",\n")}
      #{make_duplicate_key_update_sql(update_columns)}
      }
      sql
    end

    def make_duplicate_key_update_sql(update_columns)
      return "" if update_columns.empty?
      updates = []
      update_columns.each do |update_column|
        updates << "#{update_column}=VALUES(\`#{update_column}\`)"
      end
      "ON DUPLICATE KEY UPDATE " + updates.join(', ')
    end

    def to_value_string(columns, record)
      values_string = columns.map do |column|
        generate_value(record, column)
      end.join(',')
      '(' + values_string + ')'
    end

    def query(query)
      result = []
      query.split(';').each do |sql|
        next if sql.blank?
        res = @client.xquery(sql)
        next if res.nil?
        res.each do |record|
          result << record
        end
      end
      result
    end

    def count(table, keys)
      select_query = keys.empty? ? '' : "#{keys.join(',')},"
      group_by_query = keys.empty? ? '' : "group by #{keys.join(',')}"
      query(%Q{select #{select_query} count(*) as count from #{table} #{group_by_query} order by count desc})
    end

    def query_single(query)
      begin
        res = @client.xquery(query)
      rescue => e
        puts "\n#{e.message}\n#{e.backtrace.join("\n")}"
        puts query
      end
    end

    def auto_create_table(table, hash)
      res = table_info(table)
      if res.size == 0
        create_table_sql = %Q{CREATE TABLE #{table} (\n#{generate_create_table(hash)}\n)}
        query(create_table_sql)
      end
    end

    def create_database_utf8(database)
      @client.xquery("CREATE DATABASE #{database} CHARACTER SET 'UTF8'")
    end

    def tables(table_name)
      if table_name.nil?
        query('SELECT * FROM INFORMATION_SCHEMA.TABLES')
      else
        query("show full columns from #{table_name}")
      end
    end

    def databases
      query('show databases')
    end

    def processlist
      query('SELECT * FROM INFORMATION_SCHEMA.PROCESSLIST')
    end

    def table_info(table)
      @client.xquery("SELECT * FROM INFORMATION_SCHEMA.COLUMNS where TABLE_NAME = '#{table}'")
    end

    def generate_value(record, column)
      value = record[column['COLUMN_NAME']]
      return 'NULL' if value.nil?
      if value.class == String
        # is_time_format
        time = to_time_or_nil(value)
        if !time.nil?
          return "'" + time.strftime('%Y-%m-%d %H:%M:%S') + "'"
        end
        max_length = column['CHARACTER_MAXIMUM_LENGTH']
        return "'" + Mysql2::Client.escape(value) + "'" if max_length.nil?
        value = value.size > max_length ? value.slice(0, max_length) : value
        return "'" + Mysql2::Client.escape(value) + "'"
      elsif value.class == Hash
        escaped = Mysql2::Client.escape(Yajl::Encoder.encode(value))
        return "'" + escaped + "'"
      end
      "'#{value}'"
    end

    def generate_create_table(hash)
      results = hash.map do |k, v|
        generate_alter(k, v)
      end
      results << 'id integer NOT NULL auto_increment PRIMARY KEY' unless hash.keys.map(&:downcase).include?('id')
      results.compact.join(",\n")
    end

    def generate_alter(k, v)
      if v.nil?
        "\`#{k}\` varchar(255)"
      elsif k =~ /^id$/i
        "\`id\` integer NOT NULL auto_increment PRIMARY KEY"
      elsif v.class == String
        to_time_or_nil(v).nil? ? "\`#{k}\` varchar(255)" : "\`#{k}\` datetime"
      elsif v.class == Fixnum
        "\`#{k}\` integer"
      elsif v.class == Array
        "\`#{k}\` text"
      elsif v.class == Hash
        "\`#{k}\` text"
      elsif v.respond_to?(:strftime)
        "\`#{k}\` datetime"
      end
    end

    def to_time_or_nil(value)
      return nil if value.slice(0, 4) !~ /^[0-9][0-9][0-9][0-9]/
      begin
        time = value.to_time
        time.to_i >= 0 ? time : nil
      rescue => e
        nil
      end
    end

    def parse_json(buffer)
      begin
        data = Yajl::Parser.parse(buffer)
      rescue => e
        data = []
        buffer.split("\n").each do |line|
          data << Yajl::Parser.parse(line)
        end
      end
      data
    end

    def variables(like = nil)
      if like.nil?
        query('SHOW VARIABLES')
      else
        query("SHOW VARIABLES LIKE '%#{like}%'")
      end
    end

    def render_template(template_path = nil, output_template, format, params)
      system 'mkdir -p ' + File.dirname(output_template)
      database = @profile['database']
      tables = @client.xquery("SELECT * FROM INFORMATION_SCHEMA.TABLES where TABLE_SCHEMA = '#{database}'")
      tables.each do |table|
        table_name = table['TABLE_NAME']
        sql = %Q{SELECT * FROM INFORMATION_SCHEMA.COLUMNS where TABLE_SCHEMA = '#{database}' and TABLE_NAME = '#{table_name}'}
        columns = @client.xquery(sql)
        filepath = sprintf(output_template, parse_table(table_name, format))
        filewrite = File.open(filepath,'w')
        filewrite.puts ERB.new(File.read(template_path)).result(binding)
        filewrite.close
        puts "create #{table_name} => #{filepath}"
      end
    end

    def console
      cmd = <<-EOF
      mysql -A\
      -u #{@profile['username']}\
      -h #{@profile['host']}\
      -p #{@profile['database']}\
      --password='#{@profile['password']}'
      EOF
      system(cmd)
    end

    def dump(filepath = "#{@profile['database']}.dump")
      cmd = <<-EOF
      mysqldump \
      -u #{@profile['username']}\
      -h #{@profile['host']}\
      -p #{@profile['database']}\
      --password='#{@profile['password']}'\
      --default-character-set=binary\
       > #{filepath}
      EOF
      system(cmd)
    end

    def restore(filepath = "#{@profile['database']}.dump")
      cmd = <<-EOF
      mysql -A\
      -u #{@profile['username']}\
      -h #{@profile['host']}\
      -p #{@profile['database']}\
      --password='#{@profile['password']}'\
      --default-character-set=binary\
      -f < #{filepath}
      EOF
      system(cmd)
    end

    private

    def parse_table(table_name, format)
      return table_name if format.nil?
      eval("table_name.#{format}")
    end

  end
end
