#!/usr/bin/env ruby

require 'sqlite3'
require 'time'
require 'optparse'
require 'csv'

class EnhancedPhotosVideoAnalyzer
  def initialize(options = {})
    @db_path = options[:db_path]
    @limit = options[:limit] || 100
    @output_format = options[:format] || 'table'
    @output_file = options[:output_file]
    @min_duration = options[:min_duration]
    @max_duration = options[:max_duration]
    @date_from = options[:date_from]
    @date_to = options[:date_to]
    @resolution = options[:resolution]
    @search_term = options[:search_term]
    @sort_by = options[:sort_by] || 'duration'
    @show_stats = options[:show_stats]
    @group_by = options[:group_by]
    @db = nil
  end

  def connect
    @db = SQLite3::Database.new(@db_path)
    @db.results_as_hash = true
    puts "Connected to Photos database: #{@db_path}" unless @output_format == 'csv'
  rescue SQLite3::Exception => e
    puts "Error connecting to database: #{e.message}"
    exit 1
  end

  def close
    @db&.close
  end

  def build_query
    select_clause = <<-SQL
      SELECT
        a.ZDURATION,
        COALESCE(c.ZORIGINALFILENAME, a.ZFILENAME) as ZFILENAME,
        a.ZDATECREATED,
        a.ZWIDTH,
        a.ZHEIGHT,
        a.Z_PK as asset_id,
        a.ZFAVORITE,
        a.ZHIDDEN,
        a.ZTRASHEDSTATE
      FROM ZASSET a
      LEFT JOIN ZCLOUDMASTER c ON a.ZMASTER = c.Z_PK
    SQL

    where_conditions = ['a.ZKIND = 1']

    # Duration filters
    where_conditions << 'a.ZDURATION > 0' unless @min_duration && @min_duration == 0
    where_conditions << "a.ZDURATION >= #{@min_duration}" if @min_duration && @min_duration > 0
    where_conditions << "a.ZDURATION <= #{@max_duration}" if @max_duration

    # Date filters (Apple Core Data timestamps)
    if @date_from
      timestamp = (@date_from.to_time - Time.new(2001, 1, 1, 0, 0, 0, "+00:00")).to_i
      where_conditions << "a.ZDATECREATED >= #{timestamp}"
    end

    if @date_to
      timestamp = (@date_to.to_time - Time.new(2001, 1, 1, 0, 0, 0, "+00:00")).to_i
      where_conditions << "a.ZDATECREATED <= #{timestamp}"
    end

    # Resolution filters
    if @resolution
      case @resolution.downcase
      when 'sd'
        where_conditions << "(a.ZWIDTH * a.ZHEIGHT) <= 500000"
      when 'hd'
        where_conditions << "(a.ZWIDTH * a.ZHEIGHT) BETWEEN 500001 AND 1500000"
      when 'fullhd', 'fhd'
        where_conditions << "(a.ZWIDTH * a.ZHEIGHT) BETWEEN 1500001 AND 3000000"
      when '4k'
        where_conditions << "(a.ZWIDTH * a.ZHEIGHT) BETWEEN 3000001 AND 9000000"
      when '8k'
        where_conditions << "(a.ZWIDTH * a.ZHEIGHT) > 9000000"
      end
    end

    # Search term filter
    if @search_term
      where_conditions << "COALESCE(c.ZORIGINALFILENAME, a.ZFILENAME) LIKE '%#{@search_term}%'"
    end

    where_clause = "WHERE #{where_conditions.join(' AND ')}"

    # Sort options
    case @sort_by.downcase
    when 'duration'
      order_clause = "ORDER BY a.ZDURATION DESC"
    when 'date'
      order_clause = "ORDER BY a.ZDATECREATED DESC"
    when 'size'
      order_clause = "ORDER BY (a.ZWIDTH * a.ZHEIGHT) DESC"
    when 'filename'
      order_clause = "ORDER BY COALESCE(c.ZORIGINALFILENAME, a.ZFILENAME) ASC"
    else
      order_clause = "ORDER BY a.ZDURATION DESC"
    end

    limit_clause = "LIMIT #{@limit}" if @limit > 0

    [select_clause, where_clause, order_clause, limit_clause].compact.join(' ')
  end

  def group_results_by_date(results)
    return results unless @group_by

    grouped = results.group_by do |row|
      timestamp = row['ZDATECREATED']
      next 'Unknown' unless timestamp

      reference_date = Time.new(2001, 1, 1, 0, 0, 0, "+00:00")
      actual_date = reference_date + timestamp

      case @group_by.downcase
      when 'day'
        actual_date.strftime("%Y-%m-%d")
      when 'month'
        actual_date.strftime("%Y-%m")
      when 'year'
        actual_date.strftime("%Y")
      else
        actual_date.strftime("%Y-%m-%d")
      end
    rescue => e
      'Unknown'
    end

    # Sort groups by date (newest first)
    grouped.sort_by { |date, _| date == 'Unknown' ? '0000' : date }.reverse.to_h
  end

  def get_videos
    query = build_query

    if @output_format != 'csv'
      puts "\nExecuting query..."
      puts query if ENV['DEBUG']
    end

    begin
      results = @db.execute(query)
      puts "Found #{results.length} videos" unless @output_format == 'csv'
      results
    rescue SQLite3::Exception => e
      puts "Error executing query: #{e.message}"
      []
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

  def format_date(timestamp, format = :standard)
    return "N/A" unless timestamp

    reference_date = Time.new(2001, 1, 1, 0, 0, 0, "+00:00")
    actual_date = reference_date + timestamp

    case format
    when :csv
      actual_date.strftime("%Y-%m-%d %H:%M:%S")
    when :short
      actual_date.strftime("%Y-%m-%d")
    else
      actual_date.strftime("%Y-%m-%d %H:%M:%S")
    end
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

  def get_resolution_category(width, height)
    return "Unknown" unless width && height

    pixels = width * height
    case pixels
    when 0..500000 then "SD"
    when 500001..1500000 then "HD"
    when 1500001..3000000 then "Full HD"
    when 3000001..9000000 then "4K"
    else "8K+"
    end
  end

  def estimate_file_size_mb(duration, width, height)
    return nil unless duration && width && height && duration > 0

    pixels = width * height
    bitrate_mbps = case pixels
                   when 0..500000 then 2
                   when 500001..1500000 then 5
                   when 1500001..3000000 then 8
                   when 3000001..9000000 then 25
                   else 50
                   end

    (duration * bitrate_mbps / 8).round(1)
  end

  def get_database_stats
    stats = {}

    begin
      result = @db.execute("SELECT COUNT(*) as count FROM ZASSET WHERE ZKIND = 1")
      stats[:total_videos] = result[0]['count']

      result = @db.execute("SELECT COUNT(*) as count FROM ZASSET WHERE ZKIND = 1 AND ZDURATION > 0")
      stats[:videos_with_duration] = result[0]['count']

      result = @db.execute("SELECT COUNT(*) as count FROM ZASSET WHERE ZKIND = 0")
      stats[:total_photos] = result[0]['count']

      result = @db.execute("SELECT SUM(ZDURATION) as total FROM ZASSET WHERE ZKIND = 1 AND ZDURATION > 0")
      stats[:total_duration] = result[0]['total'] || 0

      result = @db.execute("SELECT COUNT(*) as count FROM ZASSET WHERE ZKIND = 1 AND ZFAVORITE = 1")
      stats[:favorite_videos] = result[0]['count']

      result = @db.execute("SELECT COUNT(*) as count FROM ZASSET WHERE ZKIND = 1 AND ZHIDDEN = 1")
      stats[:hidden_videos] = result[0]['count']

      result = @db.execute("SELECT COUNT(*) as count FROM ZASSET WHERE ZKIND = 1 AND ZTRASHEDSTATE = 1")
      stats[:trashed_videos] = result[0]['count']

    rescue SQLite3::Exception => e
      puts "Error getting database stats: #{e.message}"
    end

    stats
  end

  def output_csv(results, filename = nil)
    filename ||= @output_file || "videos_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"

    CSV.open(filename, 'w') do |csv|
      # Headers
      if @group_by
        csv << ['Group', 'Rank', 'Duration (seconds)', 'Duration (formatted)', 'Original Filename', 'Date Created',
                'Width', 'Height', 'Resolution Category', 'Estimated Size (MB)', 'Asset ID',
                'Favorite', 'Hidden', 'Trashed']
      else
        csv << ['Rank', 'Duration (seconds)', 'Duration (formatted)', 'Original Filename', 'Date Created',
                'Width', 'Height', 'Resolution Category', 'Estimated Size (MB)', 'Asset ID',
                'Favorite', 'Hidden', 'Trashed']
      end

      if @group_by
        grouped_results = group_results_by_date(results)
        grouped_results.each do |group_name, group_results|
          group_duration = 0
          group_size = 0

          group_results.each_with_index do |row, index|
            duration = row['ZDURATION']
            estimated_size = estimate_file_size_mb(duration, row['ZWIDTH'], row['ZHEIGHT'])
            resolution_cat = get_resolution_category(row['ZWIDTH'], row['ZHEIGHT'])

            csv << [
              group_name,
              index + 1,
              duration,
              format_duration(duration),
              row['ZFILENAME'],
              format_date(row['ZDATECREATED'], :csv),
              row['ZWIDTH'],
              row['ZHEIGHT'],
              resolution_cat,
              estimated_size,
              row['asset_id'],
              row['ZFAVORITE'] == 1 ? 'Yes' : 'No',
              row['ZHIDDEN'] == 1 ? 'Yes' : 'No',
              row['ZTRASHEDSTATE'] == 1 ? 'Yes' : 'No'
            ]

            group_duration += duration if duration
            group_size += estimated_size if estimated_size
          end

          # Add group summary row
          csv << [
            "#{group_name} TOTAL",
            group_results.length,
            group_duration,
            format_duration(group_duration),
            "GROUP SUMMARY",
            "",
            "",
            "",
            "",
            group_size.round(1),
            "",
            "",
            "",
            ""
          ]
        end
      else
        results.each_with_index do |row, index|
          duration = row['ZDURATION']
          estimated_size = estimate_file_size_mb(duration, row['ZWIDTH'], row['ZHEIGHT'])
          resolution_cat = get_resolution_category(row['ZWIDTH'], row['ZHEIGHT'])

          csv << [
            index + 1,
            duration,
            format_duration(duration),
            row['ZFILENAME'],
            format_date(row['ZDATECREATED'], :csv),
            row['ZWIDTH'],
            row['ZHEIGHT'],
            resolution_cat,
            estimated_size,
            row['asset_id'],
            row['ZFAVORITE'] == 1 ? 'Yes' : 'No',
            row['ZHIDDEN'] == 1 ? 'Yes' : 'No',
            row['ZTRASHEDSTATE'] == 1 ? 'Yes' : 'No'
          ]
        end
      end
    end

    puts "Results exported to: #{filename}"
  end

  def output_json(results, filename = nil)
    require 'json'
    filename ||= @output_file || "videos_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"

    if @group_by
      grouped_results = group_results_by_date(results)
      formatted_results = {}

      grouped_results.each do |group_name, group_results|
        group_duration = 0
        group_size = 0

        videos = group_results.map.with_index do |row, index|
          duration = row['ZDURATION']
          estimated_size = estimate_file_size_mb(duration, row['ZWIDTH'], row['ZHEIGHT'])

          group_duration += duration if duration
          group_size += estimated_size if estimated_size

          {
            rank: index + 1,
            duration_seconds: duration,
            duration_formatted: format_duration(duration),
            filename: row['ZFILENAME'],
            date_created: format_date(row['ZDATECREATED'], :csv),
            width: row['ZWIDTH'],
            height: row['ZHEIGHT'],
            resolution_category: get_resolution_category(row['ZWIDTH'], row['ZHEIGHT']),
            estimated_size_mb: estimated_size,
            asset_id: row['asset_id'],
            favorite: row['ZFAVORITE'] == 1,
            hidden: row['ZHIDDEN'] == 1,
            trashed: row['ZTRASHEDSTATE'] == 1
          }
        end

        formatted_results[group_name] = {
          summary: {
            total_videos: group_results.length,
            total_duration_seconds: group_duration,
            total_duration_formatted: format_duration(group_duration),
            total_estimated_size_mb: group_size.round(1)
          },
          videos: videos
        }
      end
    else
      formatted_results = results.map.with_index do |row, index|
        {
          rank: index + 1,
          duration_seconds: row['ZDURATION'],
          duration_formatted: format_duration(row['ZDURATION']),
          filename: row['ZFILENAME'],
          date_created: format_date(row['ZDATECREATED'], :csv),
          width: row['ZWIDTH'],
          height: row['ZHEIGHT'],
          resolution_category: get_resolution_category(row['ZWIDTH'], row['ZHEIGHT']),
          estimated_size_mb: estimate_file_size_mb(row['ZDURATION'], row['ZWIDTH'], row['ZHEIGHT']),
          asset_id: row['asset_id'],
          favorite: row['ZFAVORITE'] == 1,
          hidden: row['ZHIDDEN'] == 1,
          trashed: row['ZTRASHEDSTATE'] == 1
        }
      end
    end

    File.write(filename, JSON.pretty_generate(formatted_results))
    puts "Results exported to: #{filename}"
  end

  def display_table_results(results)
    return if results.empty?

    if @group_by
      display_grouped_table_results(results)
    else
      display_ungrouped_table_results(results)
    end
  end

  def display_grouped_table_results(results)
    grouped_results = group_results_by_date(results)
    total_duration = 0
    total_videos = results.length

    puts "\n" + "="*140
    puts "TOP #{total_videos} VIDEOS GROUPED BY #{@group_by.upcase}"
    puts "="*140

    grouped_results.each do |group_name, group_results|
      puts "\n📅 #{group_name.upcase} (#{group_results.length} videos)"
      puts "-" * 140

      printf("%-4s %-12s %-45s %-20s %-12s %-12s %-8s %s\n",
             "Rank", "Duration", "Filename", "Date Created", "Dimensions", "Est. Size", "Flags", "ID")
      puts "-" * 140

      group_duration = 0
      group_size = 0

      group_results.each_with_index do |row, index|
        rank = index + 1
        duration = row['ZDURATION']
        duration_formatted = format_duration(duration)
        filename = row['ZFILENAME'] || "N/A"
        date = format_date(row['ZDATECREATED'], :short)
        dimensions = format_dimensions(row['ZWIDTH'], row['ZHEIGHT'])
        estimated_size = estimate_file_size_mb(duration, row['ZWIDTH'], row['ZHEIGHT'])
        estimated_size_str = estimated_size ? "~#{estimated_size} MB" : "N/A"
        asset_id = row['asset_id']

        # Flags
        flags = []
        flags << "⭐" if row['ZFAVORITE'] == 1
        flags << "👁" if row['ZHIDDEN'] == 1
        flags << "🗑" if row['ZTRASHEDSTATE'] == 1
        flags_str = flags.join('')

        display_filename = filename.length > 43 ? filename[0..40] + "..." : filename

        printf("%-4d %-12s %-45s %-20s %-12s %-12s %-8s %s\n",
               rank, duration_formatted, display_filename, date, dimensions,
               estimated_size_str, flags_str, asset_id)

        group_duration += duration if duration
        total_duration += duration if duration

        group_estimated_size = estimate_file_size_mb(duration, row['ZWIDTH'], row['ZHEIGHT'])
        group_size += group_estimated_size if group_estimated_size
      end

      group_size_str = group_size > 0 ? "~#{group_size.round(1)} MB" : "N/A"
      puts "    Group total: #{format_duration(group_duration)}, Size: #{group_size_str}"
    end

    puts "\n" + "="*140
    display_summary(results, total_duration)
  end

  def display_ungrouped_table_results(results)
    puts "\n" + "="*140
    puts "TOP #{results.length} VIDEOS BY #{@sort_by.upcase}"
    puts "="*140

    printf("%-4s %-12s %-45s %-20s %-12s %-12s %-8s %s\n",
           "Rank", "Duration", "Original Filename", "Date Created", "Dimensions", "Est. Size", "Flags", "ID")
    puts "-" * 140

    total_duration = 0

    results.each_with_index do |row, index|
      rank = index + 1
      duration = row['ZDURATION']
      duration_formatted = format_duration(duration)
      filename = row['ZFILENAME'] || "N/A"
      date = format_date(row['ZDATECREATED'], :short)
      dimensions = format_dimensions(row['ZWIDTH'], row['ZHEIGHT'])
      estimated_size = estimate_file_size_mb(duration, row['ZWIDTH'], row['ZHEIGHT'])
      estimated_size_str = estimated_size ? "~#{estimated_size} MB" : "N/A"
      asset_id = row['asset_id']

      # Flags
      flags = []
      flags << "⭐" if row['ZFAVORITE'] == 1
      flags << "👁" if row['ZHIDDEN'] == 1
      flags << "🗑" if row['ZTRASHEDSTATE'] == 1
      flags_str = flags.join('')

      display_filename = filename.length > 43 ? filename[0..40] + "..." : filename

      printf("%-4d %-12s %-45s %-20s %-12s %-12s %-8s %s\n",
             rank, duration_formatted, display_filename, date, dimensions,
             estimated_size_str, flags_str, asset_id)

      total_duration += duration if duration
    end

    puts "-" * 140
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
      resolutions = results.group_by { |r| get_resolution_category(r['ZWIDTH'], r['ZHEIGHT']) }
      puts "  Resolution breakdown:"
      resolutions.each { |res, videos| puts "    #{res}: #{videos.length}" }

      # Flags summary
      favorites = results.count { |r| r['ZFAVORITE'] == 1 }
      hidden = results.count { |r| r['ZHIDDEN'] == 1 }
      trashed = results.count { |r| r['ZTRASHEDSTATE'] == 1 }

      puts "  Special flags:"
      puts "    Favorites: #{favorites}"
      puts "    Hidden: #{hidden}"
      puts "    Trashed: #{trashed}"
    end
  end

  def display_database_stats(stats)
    puts "\nDATABASE STATISTICS:"
    puts "="*50
    puts "Total photos: #{stats[:total_photos] || 'N/A'}"
    puts "Total videos: #{stats[:total_videos] || 'N/A'}"
    puts "Videos with duration data: #{stats[:videos_with_duration] || 'N/A'}"
    puts "Favorite videos: #{stats[:favorite_videos] || 'N/A'}"
    puts "Hidden videos: #{stats[:hidden_videos] || 'N/A'}"
    puts "Trashed videos: #{stats[:trashed_videos] || 'N/A'}"
    puts "Total video duration: #{format_duration(stats[:total_duration])}"
  end

  def run
    connect

    begin
      if @show_stats
        stats = get_database_stats
        display_database_stats(stats)
        return
      end

      results = get_videos

      case @output_format
      when 'csv'
        output_csv(results)
      when 'json'
        output_json(results)
      else
        stats = get_database_stats
        display_database_stats(stats) unless @output_format == 'csv'
        display_table_results(results)
      end

    rescue => e
      puts "Error during analysis: #{e.message}"
      puts e.backtrace.join("\n") if ENV['DEBUG']
    ensure
      close
    end
  end
end

# Command-line interface
def parse_options
  options = {}

  OptionParser.new do |opts|
    opts.banner = "Usage: ruby video_analyzer_enhanced.rb [options] <Photos.sqlite>"
    opts.separator ""
    opts.separator "Options:"

    opts.on("-n", "--limit NUMBER", Integer, "Number of results to show (default: 100, 0 for all)") do |n|
      options[:limit] = n
    end

    opts.on("-f", "--format FORMAT", ["table", "csv", "json"], "Output format (table, csv, json)") do |f|
      options[:format] = f
    end

    opts.on("-o", "--output FILE", "Output filename (for CSV/JSON formats)") do |file|
      options[:output_file] = file
    end

    opts.on("--min-duration SECONDS", Float, "Minimum duration in seconds") do |min|
      options[:min_duration] = min
    end

    opts.on("--max-duration SECONDS", Float, "Maximum duration in seconds") do |max|
      options[:max_duration] = max
    end

    opts.on("--date-from DATE", "Filter videos from this date (YYYY-MM-DD)") do |date|
      options[:date_from] = Date.parse(date)
    end

    opts.on("--date-to DATE", "Filter videos to this date (YYYY-MM-DD)") do |date|
      options[:date_to] = Date.parse(date)
    end

    opts.on("-r", "--resolution RES", ["sd", "hd", "fullhd", "fhd", "4k", "8k"],
            "Filter by resolution (sd, hd, fullhd, 4k, 8k)") do |res|
      options[:resolution] = res
    end

    opts.on("-s", "--search TERM", "Search for filename containing term") do |term|
      options[:search_term] = term
    end

    opts.on("--sort-by FIELD", ["duration", "date", "size", "filename"],
            "Sort by field (duration, date, size, filename)") do |field|
      options[:sort_by] = field
    end

    opts.on("--stats-only", "Show only database statistics") do
      options[:show_stats] = true
    end

    opts.on("--group-by PERIOD", ["day", "month", "year"],
            "Group results by date period (day, month, year)") do |period|
      options[:group_by] = period
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end

    opts.separator ""
    opts.separator "Examples:"
    opts.separator "  ruby video_analyzer_enhanced.rb Photos.sqlite"
    opts.separator "  ruby video_analyzer_enhanced.rb -n 50 --format csv -o my_videos.csv Photos.sqlite"
    opts.separator "  ruby video_analyzer_enhanced.rb --min-duration 300 --resolution 4k Photos.sqlite"
    opts.separator "  ruby video_analyzer_enhanced.rb --date-from 2023-01-01 --date-to 2023-12-31 Photos.sqlite"
    opts.separator "  ruby video_analyzer_enhanced.rb --search \"mov\" --sort-by date Photos.sqlite"
    opts.separator "  ruby video_analyzer_enhanced.rb --group-by month --sort-by date Photos.sqlite"
    opts.separator "  ruby video_analyzer_enhanced.rb --group-by day --date-from 2023-06-01 --date-to 2023-06-30 Photos.sqlite"
  end.parse!

  if ARGV.length != 1
    puts "Error: Please provide the Photos.sqlite file path"
    exit 1
  end

  options[:db_path] = ARGV[0]

  unless File.exist?(options[:db_path])
    puts "Error: Database file not found: #{options[:db_path]}"
    exit 1
  end

  options
end

# Main execution
if __FILE__ == $0
  options = parse_options
  analyzer = EnhancedPhotosVideoAnalyzer.new(options)
  analyzer.run
end
