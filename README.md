# Photos.sqlite Video Analyzer

A Ruby-based tool suite for analyzing video files stored in Apple Photos' SQLite database. This tool helps you find the largest videos by duration, apply various filters, and export results in multiple formats.

## Features

- 📊 **Database Analysis**: Get comprehensive statistics about your photo library
- 🎬 **Video Discovery**: Find the largest videos by duration, file size, or date
- 🔍 **Advanced Filtering**: Filter by resolution, date range, duration, and filename
- 📤 **Multiple Export Formats**: Export results as table, CSV, or JSON
- ⭐ **Metadata Support**: Shows favorites, hidden videos, and other metadata
- 📱 **Apple Photos Compatible**: Works with Photos.sqlite from macOS Photos app

## Files

- `video_analyzer.rb` - Basic video analyzer (top 100 videos by duration)
- `video_analyzer_enhanced.rb` - Advanced analyzer with filtering and export options
- `explore_schema.rb` - Database schema explorer for understanding the database structure
- `video_locator.rb` - Helper tool to locate videos in Photos app using analyzer results

## Requirements

- Ruby (tested with Ruby 2.7+)
- Bundler gem manager
- Access to Photos.sqlite file from Apple Photos

## Installation

1. Install dependencies using Bundler:
```bash
bundle install
```

Alternatively, install gems manually:
```bash
gem install sqlite3
```

## Finding Your Photos.sqlite File

The Photos.sqlite file is typically located at:
```
~/Pictures/Photos Library.photoslibrary/database/Photos.sqlite
```

**Note**: You may need to make a copy of this file to analyze it, as Photos might lock the database while running.

## Usage

### Basic Video Analyzer

```bash
ruby video_analyzer.rb Photos.sqlite
```

Shows the top 100 videos by duration with basic information.

### Enhanced Video Analyzer

```bash
ruby video_analyzer_enhanced.rb [options] Photos.sqlite
```

#### Command Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `-n, --limit NUMBER` | Number of results (0 for all) | `-n 50` |
| `-f, --format FORMAT` | Output format: table, csv, json | `-f csv` |
| `-o, --output FILE` | Output filename | `-o my_videos.csv` |
| `--min-duration SECONDS` | Minimum duration filter | `--min-duration 300` |
| `--max-duration SECONDS` | Maximum duration filter | `--max-duration 3600` |
| `--date-from DATE` | Filter from date (YYYY-MM-DD) | `--date-from 2023-01-01` |
| `--date-to DATE` | Filter to date (YYYY-MM-DD) | `--date-to 2023-12-31` |
| `-r, --resolution RES` | Filter by resolution | `-r 4k` |
| `-s, --search TERM` | Search filename | `-s "vacation"` |
| `--sort-by FIELD` | Sort by: duration, date, size, filename | `--sort-by date` |
| `--stats-only` | Show only database statistics | `--stats-only` |

#### Resolution Filters

- `sd` - Standard Definition (≤ 500K pixels)
- `hd` - HD (500K - 1.5M pixels)
- `fullhd` - Full HD (1.5M - 3M pixels)
- `4k` - 4K (3M - 9M pixels)
- `8k` - 8K+ (> 9M pixels)

## Examples

### Basic Usage
```bash
# Show top 100 videos by duration
ruby video_analyzer_enhanced.rb Photos.sqlite

# Show database statistics only
ruby video_analyzer_enhanced.rb --stats-only Photos.sqlite
```

### Filtering Examples
```bash
# Find long 4K videos (over 5 minutes)
ruby video_analyzer_enhanced.rb --min-duration 300 --resolution 4k Photos.sqlite

# Find videos from 2023
ruby video_analyzer_enhanced.rb --date-from 2023-01-01 --date-to 2023-12-31 Photos.sqlite

# Find .mov files sorted by date
ruby video_analyzer_enhanced.rb --search "mov" --sort-by date Photos.sqlite

# Find videos and get location instructions
ruby video_locator.rb --interactive Photos.sqlite
```

### Export Examples
```bash
# Export top 50 videos to CSV
ruby video_analyzer_enhanced.rb -n 50 --format csv -o my_videos.csv Photos.sqlite

# Export all 4K videos to JSON
ruby video_analyzer_enhanced.rb -n 0 --resolution 4k --format json Photos.sqlite
```

## Finding Videos in Photos App

The analyzer shows internal filenames like `E7CAFE34-EA72-4486-952A-809EDEE2AEC4.mov` which can't be searched directly in Photos app. Here's how to locate these videos:

### Method 1: Use the Video Locator Tool

```bash
# Interactive mode - browse and select videos for search instructions
ruby video_locator.rb --interactive Photos.sqlite

# Get instructions for a specific video by Asset ID
ruby video_locator.rb --id 8014 Photos.sqlite

# Export a complete search guide
ruby video_locator.rb --export-guide Photos.sqlite
```

### Method 2: Manual Search in Photos App

Use the **date created** and **duration** from the analyzer results:

1. **Filter by Date**:
   - Open Photos app → Library → All Photos
   - Navigate to the date shown in results (e.g., "2019-02-26")
   - Look for videos on that specific day

2. **Match Duration**:
   - Select videos and check duration in bottom-left corner
   - Match with the duration from analyzer (e.g., "2:57:21")

3. **Verify Resolution**:
   - Right-click video → Get Info
   - Check dimensions match (e.g., "1920x1080")

4. **Check Special Flags**:
   - ⭐ Look in Favorites album if flagged as favorite
   - 👁 Check Hidden album if marked as hidden

### Method 3: Smart Albums

1. Create a Smart Album: Albums → New Smart Album
2. Set conditions:
   - Media Type is Video
   - Duration is greater than X minutes
   - Date is in range
3. Browse results to find matching videos

## Output Information

The analyzer provides the following information for each video:

- **Rank**: Position in the sorted list
- **Duration**: Video length in HH:MM:SS format
- **Filename**: Original filename
- **Date Created**: When the video was created
- **Dimensions**: Width x Height in pixels
- **Estimated Size**: Rough file size estimate based on resolution and duration
- **Flags**: Special indicators (⭐ favorite, 👁 hidden, 🗑 trashed)
- **Asset ID**: Internal Photos database ID

## Database Schema Explorer

To understand the database structure:

```bash
ruby explore_schema.rb Photos.sqlite
```

This tool helps you:
- View all tables in the database
- Understand column structures
- See sample data
- Find video-related columns

## Sample Output

```
TOP 5 VIDEOS BY DURATION
================================================================================
Rank Duration     Filename                     Date Created  Dimensions   Est. Size
--------------------------------------------------------------------------------
1    2:57:21      vacation_2019.mov           2019-02-26    1920x1080    ~10642.0 MB
2    2:01:02      concert_recording.mov       2021-04-22    1920x1080    ~7262.0 MB
3    1:37:57      family_event_4k.mov         2024-08-14    3840x2160    ~18367.1 MB
4    1:27:36      portrait_video.mp4          2022-06-28    888x1920     ~3285.1 MB
5    1:10:04      presentation.mov            2022-05-13    1920x1080    ~4204.7 MB
```

## Technical Notes

- **Date Format**: Apple Photos stores dates as seconds since 2001-01-01 00:00:00 UTC
- **File Size Estimation**: Based on typical bitrates for different resolutions
- **Video Detection**: Uses `ZKIND = 1` to identify video assets
- **Performance**: Queries are optimized for large photo libraries

## Limitations

- Requires read access to Photos.sqlite file
- File size estimates are approximations
- Some metadata may not be available for all videos
- Photos app should be closed when analyzing to avoid database locks

## Troubleshooting

### Database Locked Error
```bash
cp "~/Pictures/Photos Library.photoslibrary/database/Photos.sqlite" ./Photos_copy.sqlite
ruby video_analyzer_enhanced.rb Photos_copy.sqlite
```

### Permission Denied
Make sure you have read permissions to the Photos library:
```bash
ls -la "~/Pictures/Photos Library.photoslibrary/database/"
```

### Missing Dependencies
Install dependencies using Bundler:
```bash
bundle install
```

Or install SQLite3 gem manually:
```bash
gem install sqlite3
```

## Contributing

Feel free to submit issues or pull requests to improve the analyzer functionality.

## License

This project is provided as-is for educational and personal use.
