#!/usr/bin/env ruby

require 'sqlite3'
require 'time'
require 'optparse'

class PhotosVideoLocator
  def initialize(options = {})
    @db_path = options[:db_path]
    @asset_id = options[:asset_id]
    @interactive = options[:interactive]
    @export_search_guide = options[:export_search_guide]
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

    reference_date = Time.new(2001, 1, 1, 0, 0, 0, "+00:00")
    actual_date = reference_date + timestamp
    actual_date
  rescue => e
    nil
  end

  def get_video_details(asset_id)
    query = <<-SQL
      SELECT
        ZDURATION,
        ZFILENAME,
        ZDATECREATED,
        ZWIDTH,
        ZHEIGHT,
        Z_PK as asset_id,
        ZFAVORITE,
        ZHIDDEN,
        ZTRASHEDSTATE,
        ZADJUSTMENTSSTATE
      FROM ZASSET
      WHERE Z_PK = ? AND ZKIND = 1
    SQL

    results = @db.execute(query, [asset_id])
    results.first
  end

  def get_top_videos(limit = 20)
    query = <<-SQL
      SELECT
        ZDURATION,
        ZFILENAME,
        ZDATECREATED,
        ZWIDTH,
        ZHEIGHT,
        Z_PK as asset_id,
        ZFAVORITE,
        ZHIDDEN,
        ZTRASHEDSTATE
      FROM ZASSET
      WHERE ZKIND = 1 AND ZDURATION > 0
      ORDER BY ZDURATION DESC
      LIMIT ?
    SQL

    @db.execute(query, [limit])
  end

  def create_search_instructions(video)
    date = format_date(video['ZDATECREATED'])
    duration = format_duration(video['ZDURATION'])
    dimensions = "#{video['ZWIDTH']}x#{video['ZHEIGHT']}" if video['ZWIDTH'] && video['ZHEIGHT']

    puts "\n" + "="*80
    puts "HOW TO FIND THIS VIDEO IN PHOTOS APP"
    puts "="*80
    puts "Internal Filename: #{video['ZFILENAME']}"
    puts "Asset ID: #{video['asset_id']}"
    puts ""

    if date
      puts "📅 STEP 1: Filter by Date"
      puts "   • Open Photos app"
      puts "   • Go to Library → All Photos"
      puts "   • Look for videos on: #{date.strftime('%A, %B %d, %Y')}"
      puts "   • Approximate time: #{date.strftime('%I:%M %p')}"
      puts ""
    end

    puts "⏱️  STEP 2: Look for Duration"
    puts "   • Find videos with duration: #{duration}"
    puts "   • Video length shows in bottom-left corner when selected"
    puts ""

    if dimensions
      puts "📐 STEP 3: Check Video Resolution"
      puts "   • Right-click video → Get Info"
      puts "   • Look for dimensions: #{dimensions}"
      puts "   • This appears in the 'More Info' section"
      puts ""
    end

    flags = []
    flags << "⭐ Favorite" if video['ZFAVORITE'] == 1
    flags << "👁 Hidden (check Hidden album)" if video['ZHIDDEN'] == 1
    flags << "🗑 In Trash" if video['ZTRASHEDSTATE'] == 1

    if !flags.empty?
      puts "🏷️  STEP 4: Special Properties"
      flags.each { |flag| puts "   • #{flag}" }
      puts ""
    end

    puts "💡 ALTERNATIVE METHODS:"
    puts "   • Smart Albums → Videos → Filter by duration"
    puts "   • Search by approximate date in search bar"
    puts "   • Sort Videos album by duration (longest first)"
    puts ""
  end

  def interactive_search
    puts "\nINTERACTIVE VIDEO LOCATOR"
    puts "="*50

    top_videos = get_top_videos(50)

    puts "Top 50 longest videos:"
    puts ""
    printf("%-4s %-12s %-20s %-12s %s\n", "Rank", "Duration", "Date", "Dimensions", "ID")
    puts "-" * 65

    top_videos.each_with_index do |video, index|
      date = format_date(video['ZDATECREATED'])
      date_str = date ? date.strftime('%Y-%m-%d %H:%M') : "N/A"
      duration = format_duration(video['ZDURATION'])
      dimensions = video['ZWIDTH'] && video['ZHEIGHT'] ? "#{video['ZWIDTH']}x#{video['ZHEIGHT']}" : "N/A"

      printf("%-4d %-12s %-20s %-12s %s\n",
             index + 1, duration, date_str, dimensions, video['asset_id'])
    end

    puts ""
    print "Enter the rank number to get search instructions (1-50), or 'q' to quit: "
    input = gets.chomp

    if input.downcase == 'q'
      puts "Goodbye!"
      return
    end

    begin
      rank = input.to_i
      if rank >= 1 && rank <= top_videos.length
        selected_video = top_videos[rank - 1]
        create_search_instructions(selected_video)

        puts "Press Enter to select another video, or 'q' to quit..."
        next_input = gets.chomp
        interactive_search unless next_input.downcase == 'q'
      else
        puts "Invalid selection. Please enter a number between 1 and #{top_videos.length}"
        interactive_search
      end
    rescue
      puts "Invalid input. Please enter a number or 'q'"
      interactive_search
    end
  end

  def export_search_guide(filename = nil)
    filename ||= "photos_search_guide_#{Time.now.strftime('%Y%m%d_%H%M%S')}.txt"

    videos = get_top_videos(100)

    File.open(filename, 'w') do |file|
      file.puts "PHOTOS APP VIDEO SEARCH GUIDE"
      file.puts "Generated: #{Time.now}"
      file.puts "Database: #{@db_path}"
      file.puts "="*80
      file.puts ""

      videos.each_with_index do |video, index|
        date = format_date(video['ZDATECREATED'])
        duration = format_duration(video['ZDURATION'])
        dimensions = video['ZWIDTH'] && video['ZHEIGHT'] ? "#{video['ZWIDTH']}x#{video['ZHEIGHT']}" : "N/A"

        file.puts "VIDEO ##{index + 1}"
        file.puts "Internal ID: #{video['asset_id']}"
        file.puts "Filename: #{video['ZFILENAME']}"
        file.puts "Duration: #{duration}"
        file.puts "Date Created: #{date ? date.strftime('%A, %B %d, %Y at %I:%M %p') : 'N/A'}"
        file.puts "Dimensions: #{dimensions}"

        flags = []
        flags << "Favorite" if video['ZFAVORITE'] == 1
        flags << "Hidden" if video['ZHIDDEN'] == 1
        flags << "Trashed" if video['ZTRASHEDSTATE'] == 1
        file.puts "Flags: #{flags.empty? ? 'None' : flags.join(', ')}"

        file.puts "Search Tips:"
        if date
          file.puts "  - Filter Photos by date: #{date.strftime('%Y-%m-%d')}"
        end
        file.puts "  - Look for video duration: #{duration}"
        file.puts "  - Check dimensions in Get Info: #{dimensions}"
        file.puts ""
        file.puts "-" * 40
        file.puts ""
      end

      file.puts ""
      file.puts "GENERAL SEARCH TIPS FOR PHOTOS APP:"
      file.puts "1. Use View → Show in All Photos for chronological view"
      file.puts "2. Create Smart Album: Videos with custom duration filters"
      file.puts "3. Right-click any video → Get Info for detailed metadata"
      file.puts "4. Use Albums → Videos → sort by duration"
      file.puts "5. Search by approximate date in the search bar"
    end

    puts "Search guide exported to: #{filename}"
  end

  def find_by_id(asset_id)
    video = get_video_details(asset_id)

    if video
      create_search_instructions(video)
    else
      puts "Video with Asset ID #{asset_id} not found or is not a video."
    end
  end

  def run
    connect

    begin
      if @asset_id
        find_by_id(@asset_id)
      elsif @export_search_guide
        export_search_guide
      elsif @interactive
        interactive_search
      else
        puts "Please specify what you want to do:"
        puts "  --interactive     : Interactive video browser"
        puts "  --id ASSET_ID     : Find specific video by ID"
        puts "  --export-guide    : Export search guide to text file"
      end
    rescue => e
      puts "Error: #{e.message}"
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
    opts.banner = "Usage: ruby video_locator.rb [options] <Photos.sqlite>"
    opts.separator ""
    opts.separator "This tool helps you find videos from the analyzer results in the Photos app."
    opts.separator ""
    opts.separator "Options:"

    opts.on("-i", "--interactive", "Interactive mode - browse and select videos") do
      options[:interactive] = true
    end

    opts.on("--id ASSET_ID", Integer, "Get search instructions for specific Asset ID") do |id|
      options[:asset_id] = id
    end

    opts.on("-e", "--export-guide", "Export search guide to text file") do
      options[:export_search_guide] = true
    end

    opts.on("-h", "--help", "Show this help message") do
      puts opts
      puts ""
      puts "Examples:"
      puts "  # Interactive mode to browse videos"
      puts "  ruby video_locator.rb --interactive Photos.sqlite"
      puts ""
      puts "  # Find specific video by Asset ID (from analyzer output)"
      puts "  ruby video_locator.rb --id 8014 Photos.sqlite"
      puts ""
      puts "  # Export complete search guide"
      puts "  ruby video_locator.rb --export-guide Photos.sqlite"
      puts ""
      puts "Why use this tool?"
      puts "The video analyzer shows internal filenames like 'E7CAFE34-EA72-4486-952A-809EDEE2AEC4.mov'"
      puts "which can't be searched in Photos app. This tool helps you locate those videos"
      puts "using searchable attributes like date, duration, and dimensions."
      exit
    end

    opts.separator ""
  end.parse!

  if ARGV.length != 1
    puts "Error: Please provide the Photos.sqlite file path"
    puts "Use --help for usage information"
    exit 1
  end

  options[:db_path] = ARGV[0]

  unless File.exist?(options[:db_path])
    puts "Error: Database file not found: #{options[:db_path]}"
    exit 1
  end

  # Default to interactive mode if no specific action specified
  if !options[:asset_id] && !options[:export_search_guide]
    options[:interactive] = true
  end

  options
end

# Main execution
if __FILE__ == $0
  options = parse_options
  locator = PhotosVideoLocator.new(options)
  locator.run
end
