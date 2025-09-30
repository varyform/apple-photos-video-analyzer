#!/usr/bin/env ruby

require 'sqlite3'
require 'time'

class PhotosVideoAnalyzer
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

  def get_top_videos(limit = 100)
    puts "\nQuerying top #{limit} videos by duration..."

    query = <<-SQL
      SELECT
        ZDURATION,
        ZFILENAME,
        ZDATECREATED,
        ZWIDTH,
        ZHEIGHT,
        Z_PK as asset_id
      FROM ZASSET
      WHERE ZKIND = 1
        AND ZDURATION > 0
      ORDER BY ZDURATION DESC
      LIMIT #{limit}
    SQL

    puts "\nExecuting query..."

    begin
      results = @db.execute(query)
      puts "Found #{results.length} videos"
      return results
    rescue SQLite3::Exception => e
      puts "Error executing query: #{e.message}"
      return []
    end
  end

  def format_duration(seconds)
    return "N/A" unless seconds && seconds > 0

    total_seconds = seconds.to_i
    hours = total_seconds / 3600
    minutes = (total_seconds % 3600) / 60
    secs = total_seconds % 60

    if hours > 0
      sprintf("%d:%02d:%02d", hours, minutes, secs)
    else
      sprintf("%d:%02d", minutes, secs)
    end
  end

  def format_date(timestamp)
    return "N/A" unless timestamp

    # Apple Core Data uses reference date of 2001-01-01 00:00:00 UTC
    reference_date = Time.new(2001, 1, 1, 0, 0, 0, "+00:00")
    actual_date = reference_date + timestamp
    actual_date.strftime("%Y-%m-%d %H:%M:%S")
  rescue => e
    "Invalid date"
  end

  def format_dimensions(width, height)
    if width && height && width > 0 && height > 0
      "#{width}x#{height}"
    else
      "N/A"
    end
  end

  def format_file_size_mb(duration, width, height)
    # Rough estimation based on common video bitrates
    return "N/A" unless duration && width && height && duration > 0

    # Estimate bitrate based on resolution
    pixels = width * height
    bitrate_mbps = case
                   when pixels >= 8000000  # 4K+
                     25
                   when pixels >= 2000000  # 1080p
                     8
                   when pixels >= 900000   # 720p
                     5
                   else
                     3
                   end

    estimated_mb = (duration * bitrate_mbps / 8).round(1)
    "~#{estimated_mb} MB"
  end

  def get_database_stats
    stats = {}

    begin
      # Total videos
      result = @db.execute("SELECT COUNT(*) as count FROM ZASSET WHERE ZKIND = 1")
      stats[:total_videos] = result[0]['count']

      # Videos with duration > 0
      result = @db.execute("SELECT COUNT(*) as count FROM ZASSET WHERE ZKIND = 1 AND ZDURATION > 0")
      stats[:videos_with_duration] = result[0]['count']

      # Total photos
      result = @db.execute("SELECT COUNT(*) as count FROM ZASSET WHERE ZKIND = 0")
      stats[:total_photos] = result[0]['count']

      # Total duration of all videos
      result = @db.execute("SELECT SUM(ZDURATION) as total FROM ZASSET WHERE ZKIND = 1 AND ZDURATION > 0")
      stats[:total_duration] = result[0]['total'] || 0

    rescue SQLite3::Exception => e
      puts "Error getting database stats: #{e.message}"
    end

    stats
  end

  def display_results(results)
    return if results.empty?

    puts "\n" + "="*120
    puts "TOP #{results.length} VIDEOS BY DURATION"
    puts "="*120

    # Header
    printf("%-4s %-12s %-45s %-20s %-12s %-12s %s\n",
           "Rank", "Duration", "Filename", "Date Created", "Dimensions", "Est. Size", "ID")
    puts "-" * 120

    total_duration = 0

    results.each_with_index do |row, index|
      rank = index + 1
      duration = row['ZDURATION']
      duration_formatted = format_duration(duration)
      filename = row['ZFILENAME'] || "N/A"
      date = format_date(row['ZDATECREATED'])
      dimensions = format_dimensions(row['ZWIDTH'], row['ZHEIGHT'])
      estimated_size = format_file_size_mb(duration, row['ZWIDTH'], row['ZHEIGHT'])
      asset_id = row['asset_id']

      # Truncate long filenames
      display_filename = filename.length > 43 ? filename[0..40] + "..." : filename

      printf("%-4d %-12s %-45s %-20s %-12s %-12s %s\n",
             rank, duration_formatted, display_filename, date, dimensions, estimated_size, asset_id)

      total_duration += duration if duration
    end

    puts "-" * 120
    display_summary(results, total_duration)
  end

  def display_summary(results, total_duration)
    puts "SUMMARY:"
    puts "  Videos analyzed: #{results.length}"
    puts "  Total duration: #{format_duration(total_duration)}"

    if results.length > 0
      avg_duration = total_duration / results.length
      puts "  Average duration: #{format_duration(avg_duration)}"

      # Duration breakdown
      short_videos = results.count { |r| (r['ZDURATION'] || 0) < 60 }
      medium_videos = results.count { |r| (r['ZDURATION'] || 0).between?(60, 600) }
      long_videos = results.count { |r| (r['ZDURATION'] || 0) > 600 }

      puts "  Duration breakdown:"
      puts "    Short (< 1 min): #{short_videos}"
      puts "    Medium (1-10 min): #{medium_videos}"
      puts "    Long (> 10 min): #{long_videos}"

      # Resolution breakdown
      resolutions = results.group_by do |r|
        w, h = r['ZWIDTH'], r['ZHEIGHT']
        if w && h
          pixels = w * h
          case pixels
          when 0..500000 then "SD"
          when 500001..1500000 then "HD"
          when 1500001..3000000 then "Full HD"
          when 3000001..9000000 then "4K"
          else "8K+"
          end
        else
          "Unknown"
        end
      end

      puts "  Resolution breakdown:"
      resolutions.each { |res, videos| puts "    #{res}: #{videos.length}" }
    end
  end

  def display_database_stats(stats)
    puts "\nDATABASE STATISTICS:"
    puts "="*50
    puts "Total photos: #{stats[:total_photos] || 'N/A'}"
    puts "Total videos: #{stats[:total_videos] || 'N/A'}"
    puts "Videos with duration data: #{stats[:videos_with_duration] || 'N/A'}"
    puts "Total video duration: #{format_duration(stats[:total_duration])}"
  end

  def run
    connect

    begin
      stats = get_database_stats
      display_database_stats(stats)

      results = get_top_videos(100)
      display_results(results)
    rescue => e
      puts "Error during analysis: #{e.message}"
      puts e.backtrace.join("\n")
    ensure
      close
    end
  end
end

# Main execution
if __FILE__ == $0
  if ARGV.length != 1
    puts "Usage: ruby video_analyzer.rb <path_to_Photos.sqlite>"
    puts "Example: ruby video_analyzer.rb Photos.sqlite"
    puts ""
    puts "This script analyzes the Photos.sqlite database from Apple Photos"
    puts "and displays the top 100 videos by duration with detailed information."
    exit 1
  end

  db_path = ARGV[0]

  unless File.exist?(db_path)
    puts "Error: Database file not found: #{db_path}"
    exit 1
  end

  analyzer = PhotosVideoAnalyzer.new(db_path)
  analyzer.run
end
