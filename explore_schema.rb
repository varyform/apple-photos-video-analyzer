#!/usr/bin/env ruby

require 'sqlite3'

class PhotosSchemaExplorer
  def initialize(db_path)
    @db_path = db_path
    @db = nil
  end

  def connect
    @db = SQLite3::Database.new(@db_path)
    @db.results_as_hash = true
    puts "Connected to Photos database: #{@db_path}"
  rescue SQLite3::Exception => e
    puts "Error connecting to database: #{e.message}"
    exit 1
  end

  def close
    @db&.close
  end

  def explore_all_tables
    puts "\nAll tables in the database:"
    puts "=" * 50

    tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    tables.each_with_index do |table, index|
      puts "#{index + 1}. #{table['name']}"
    end
  end

  def explore_asset_tables
    puts "\nAsset-related tables:"
    puts "=" * 50

    tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    asset_tables = tables.select { |t| t['name'].upcase.include?('ASSET') }

    if asset_tables.empty?
      puts "No tables with 'ASSET' in name found."
      return nil
    end

    asset_tables.each_with_index do |table, index|
      puts "#{index + 1}. #{table['name']}"
    end

    asset_tables.first['name']
  end

  def analyze_table_structure(table_name)
    puts "\nTable: #{table_name}"
    puts "=" * 50

    columns = @db.execute("PRAGMA table_info(#{table_name})")

    puts sprintf("%-25s %-15s %-10s %-10s", "Column Name", "Type", "Not Null", "Default")
    puts "-" * 65

    columns.each do |col|
      puts sprintf("%-25s %-15s %-10s %-10s",
                   col['name'],
                   col['type'],
                   col['notnull'] == 1 ? "YES" : "NO",
                   col['dflt_value'] || "NULL")
    end

    puts "\nTotal columns: #{columns.length}"
  end

  def find_video_relevant_columns(table_name)
    puts "\nVideo-relevant columns in #{table_name}:"
    puts "=" * 50

    columns = @db.execute("PRAGMA table_info(#{table_name})")

    video_keywords = ['DURATION', 'WIDTH', 'HEIGHT', 'FILENAME', 'DATE', 'KIND', 'TYPE', 'MEDIA', 'VIDEO']

    relevant_columns = columns.select do |col|
      name = col['name'].upcase
      video_keywords.any? { |keyword| name.include?(keyword) }
    end

    if relevant_columns.empty?
      puts "No obviously video-relevant columns found."
      return
    end

    puts sprintf("%-30s %-15s %s", "Column Name", "Type", "Description")
    puts "-" * 70

    relevant_columns.each do |col|
      name = col['name']
      type = col['type']
      description = guess_column_purpose(name)
      puts sprintf("%-30s %-15s %s", name, type, description)
    end
  end

  def guess_column_purpose(column_name)
    name = column_name.upcase
    case
    when name.include?('DURATION')
      "Video duration in seconds"
    when name.include?('WIDTH') && name.include?('PIXEL')
      "Video/image width in pixels"
    when name.include?('HEIGHT') && name.include?('PIXEL')
      "Video/image height in pixels"
    when name.include?('FILENAME')
      "Original filename"
    when name.include?('DATE') && name.include?('CREATED')
      "Creation date"
    when name.include?('KIND') || name.include?('MEDIATYPE')
      "Media type (0=photo, 1=video)"
    else
      "Related to media properties"
    end
  end

  def sample_data(table_name, limit = 5)
    puts "\nSample data from #{table_name} (limit #{limit}):"
    puts "=" * 50

    begin
      # Try to get video entries first
      video_query = "SELECT * FROM #{table_name} WHERE ZKIND = 1 LIMIT #{limit}"
      results = @db.execute(video_query)

      if results.empty?
        # Fallback to any entries
        results = @db.execute("SELECT * FROM #{table_name} LIMIT #{limit}")
      end

      if results.empty?
        puts "No data found in table."
        return
      end

      # Show first few columns to avoid overwhelming output
      first_row = results.first
      columns_to_show = first_row.keys.first(10)

      puts sprintf("%-20s %s", "Column", "Sample Values")
      puts "-" * 50

      columns_to_show.each do |column|
        values = results.map { |row| row[column] }.compact.uniq.first(3)
        values_str = values.map(&:to_s).join(", ")
        values_str = values_str[0..40] + "..." if values_str.length > 40
        puts sprintf("%-20s %s", column, values_str)
      end

    rescue SQLite3::Exception => e
      puts "Error sampling data: #{e.message}"
    end
  end

  def count_media_types(table_name)
    puts "\nMedia type counts in #{table_name}:"
    puts "=" * 50

    begin
      # Try different possible column names for media type
      type_columns = ['ZKIND', 'ZMEDIATYPE', 'KIND', 'MEDIATYPE']

      type_columns.each do |col|
        begin
          query = "SELECT #{col}, COUNT(*) as count FROM #{table_name} GROUP BY #{col} ORDER BY #{col}"
          results = @db.execute(query)

          if !results.empty?
            puts "Using column: #{col}"
            results.each do |row|
              type_value = row[col]
              count = row['count']
              type_desc = case type_value
                         when 0 then "Photos"
                         when 1 then "Videos"
                         else "Unknown (#{type_value})"
                         end
              puts "  #{type_desc}: #{count}"
            end
            break
          end
        rescue SQLite3::Exception
          # Try next column
          next
        end
      end

    rescue SQLite3::Exception => e
      puts "Could not determine media type counts: #{e.message}"
    end
  end

  def run
    connect

    begin
      explore_all_tables
      main_table = explore_asset_tables

      if main_table
        analyze_table_structure(main_table)
        find_video_relevant_columns(main_table)
        count_media_types(main_table)
        sample_data(main_table)
      else
        puts "\nNo asset table found. Checking all tables for video-related content..."
        tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        tables.each do |table|
          table_name = table['name']
          next if table_name.start_with?('sqlite_')

          puts "\nChecking #{table_name}..."
          begin
            columns = @db.execute("PRAGMA table_info(#{table_name})")
            video_cols = columns.select { |col|
              col['name'].upcase.include?('DURATION') || col['name'].upcase.include?('VIDEO')
            }
            if !video_cols.empty?
              puts "Found potential video table: #{table_name}"
              find_video_relevant_columns(table_name)
              break
            end
          rescue SQLite3::Exception => e
            puts "Error checking #{table_name}: #{e.message}"
          end
        end
      end

    rescue => e
      puts "Error during exploration: #{e.message}"
      puts e.backtrace
    ensure
      close
    end
  end
end

# Main execution
if __FILE__ == $0
  if ARGV.length != 1
    puts "Usage: ruby explore_schema.rb <path_to_Photos.sqlite>"
    puts "Example: ruby explore_schema.rb Photos.sqlite"
    exit 1
  end

  db_path = ARGV[0]

  unless File.exist?(db_path)
    puts "Error: Database file not found: #{db_path}"
    exit 1
  end

  explorer = PhotosSchemaExplorer.new(db_path)
  explorer.run
end
