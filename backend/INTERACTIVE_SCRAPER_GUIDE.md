# TixatiScraper.exe - Interactive WebUI Scraper Guide

## Overview

**TixatiScraper.exe** is a powerful standalone tool that automatically:
- 🖱️ Clicks through **every button and option** in the Tixati WebUI
- 📋 Captures **torrent details** for all transfers
- 🔄 Navigates through multiple torrents and their sub-pages
- 💾 **Auto-saves** with a date/time-based filename (no arguments needed)
- 🔙 Falls back to HTTP scraping if browser automation unavailable

## Why Use This Scraper?

- **Complete Data Capture**: Gets everything from the UI, including interactive elements
- **Torrent Details**: Most important feature - captures detailed info on every torrent
- **Automated**: No manual clicking or arguments required (just double-click!)
- **Standalone**: Single .exe file, no Python or dependencies needed
- **Interactive HTML Output**: Browse results in tabbed format with collapsible sections

## Quick Start

### Simplest Usage (Recommended)
```cmd
TixatiScraper.exe
```
This automatically:
1. Connects to Tixati on localhost:8888
2. Clicks all buttons on each page
3. Captures torrent details
4. Saves to `tixati_snapshot_YYYYMMDD_HHMMSS.html` in the current directory

### Custom Host/Port
```cmd
TixatiScraper.exe --host 192.168.1.1 --port 8888
```

### Headless Mode (No Browser Window)
```cmd
TixatiScraper.exe --headless
```

### Print to Console Instead of Saving
```cmd
TixatiScraper.exe --console
```

### Save with Custom Filename
```cmd
TixatiScraper.exe --save my_snapshot.html
```

## Output Format

The generated HTML file contains:

### Main Tabs
- **HOME**: Home page data
- **TRANSFERS**: Download list with all states
- **BANDWIDTH**: Bandwidth information
- **DHT**: DHT network info
- **SETTINGS**: Configuration data
- **HELP**: Help information
- **TORRENT DETAILS**: Individual torrent details (most important)

### Torrent Details Section
For each torrent found:
- Name and status
- Complete HTML of torrent detail page
- Collapsible view for easy browsing

### Interactive Features
- **Tab Navigation**: Click tabs to switch between pages
- **Collapsible Sections**: Expand/collapse HTML content
- **Dark Theme**: Easy on the eyes
- **Timestamp**: See exactly when snapshot was taken

## Advanced Usage

### Remote Tixati Instance
```cmd
TixatiScraper.exe --host 192.168.1.100 --port 8888
```

### Long Timeout for Slow Connections
```cmd
TixatiScraper.exe --timeout 20
```

### Headless + Custom Host
```cmd
TixatiScraper.exe --headless --host 192.168.1.1
```

## How It Works

### Interactive Scraping (Primary Method)
1. **Browser Automation**: Uses Selenium with Chrome/Edge WebDriver
2. **Page Navigation**: Loads each Tixati page (/home, /transfers, etc.)
3. **Button Clicking**: Automatically clicks up to 10 buttons per page
4. **Torrent Details**: Clicks on torrent rows to capture detail pages
5. **HTML Capture**: Collects complete HTML from each state
6. **Fallback**: If Selenium fails, falls back to HTTP requests

### HTTP Fallback (When Browser Not Available)
- Uses `requests` library to fetch pages directly
- Works without installing browser drivers
- Still captures main pages, but not interactive button clicks

## Troubleshooting

### "Cannot connect to Tixati"
- Ensure Tixati is running on localhost:8888
- Try: `TixatiScraper.exe --host YOUR_IP --port 8888`
- Check firewall settings

### "No pages scraped"
- Verify Tixati WebUI is accessible
- Try accessing http://localhost:8888/home in a browser
- Check network connectivity

### Very Large Output File
- This is normal - HTML snapshots can be 5-50 MB
- Includes complete page HTML plus all torrent details
- Use file compression if needed

### Browser Window Not Closing
- Press Ctrl+C to force exit
- Or use `--headless` flag to avoid window

### Timeout Issues
- Increase timeout: `TixatiScraper.exe --timeout 30`
- Reduce system load and try again

## Output Locations

By default, snapshots save to the **current working directory**:

```
Current Directory/
└── tixati_snapshot_20231228_143022.html
```

### Changing Save Location
Use full path:
```cmd
TixatiScraper.exe --save C:\backups\tixati_snapshot.html
```

### Batch Processing
Create `scrape.bat`:
```batch
@echo off
cd /d "C:\Program Files\TixatiScraper"
TixatiScraper.exe --host YOUR_TIXATI_IP --port 8888 --save "%USERPROFILE%\Desktop\tixati_%date:~-10,2%%date:~-7,2%%date:~-4,4%_%time:~0,2%%time:~3,2%.html"
pause
```

## Features Breakdown

### Clicks All Buttons
- Navigates page controls
- Expands collapsible sections
- Triggers dynamic content loading

### Captures Torrent Details
**Most important feature!**
- Clicks on torrent rows in transfers list
- Captures full detail page HTML
- Gets info for multiple torrents from each status category
- Returns to transfers list and repeats

### Auto-Save
- No command-line arguments needed
- Automatic filename: `tixati_snapshot_YYYYMMDD_HHMMSS.html`
- Timestamp shows when snapshot was taken
- Can override with `--save` flag

### Resilient Scraping
- Tries Selenium first (interactive, complete)
- Falls back to HTTP if browser unavailable
- Still captures core data even if interactive features fail

## Integration Examples

### Scheduled Daily Snapshots
**Windows Task Scheduler:**
1. Create task to run: `TixatiScraper.exe --headless`
2. Set output directory in working folder
3. Schedule for daily at 10 AM
4. Archive old snapshots monthly

### Upload to Cloud
```batch
TixatiScraper.exe --headless
REM Wait a moment for file to be written
timeout /t 2
REM Upload latest snapshot
aws s3 cp tixati_snapshot_*.html s3://my-backups/tixati/
```

### Email Snapshot
```batch
TixatiScraper.exe --save snapshot.html
REM Send via email using your preferred tool
```

## Performance Notes

- **First Run**: May take 10-30 seconds (browser startup)
- **Typical Runtime**: 30-60 seconds for full scrape
- **Output Size**: 5-50 MB depending on torrent count
- **Memory Usage**: ~100-300 MB while running
- **Disk Space**: Ensure enough space for HTML files

## Data Security

⚠️ **Important**: Snapshot files contain all Tixati data including:
- Torrent names and states
- File lists
- Peer information
- Statistics
- Settings

**Protect snapshot files accordingly:**
- Store in secure location
- Don't share publicly
- Delete when no longer needed
- Consider encryption for sensitive backups

## Technical Details

### Requirements
- Windows 7+ (or Windows Server)
- 100 MB free disk space
- Network access to Tixati WebUI
- Chrome/Edge browser (Selenium) - optional, HTTP fallback included

### No Dependencies Needed
- All dependencies bundled in .exe
- No Python installation required
- No additional tools to install

### File Size
- TixatiScraper.exe: ~11.68 MB
- Single standalone executable
- Unpack size on disk: same as .exe size

## API/CLI Reference

```
TixatiScraper.exe [OPTIONS]

OPTIONS:
  --host HOST          Tixati host (default: localhost)
  --port PORT          Tixati port (default: 8888)
  --save FILENAME      Save to custom filename
  --console            Print to console instead
  --headless           No browser window
  --timeout SECONDS    Request timeout (default: 10)
  -h, --help          Show this help

RETURNS:
  Exit code 0: Success
  Exit code 1: Failed to scrape
  
CREATES:
  tixati_snapshot_YYYYMMDD_HHMMSS.html (auto-save)
  OR custom filename specified with --save
```

## Support & Issues

### Common Issues

| Issue | Solution |
|-------|----------|
| 404 errors on connect | Check Tixati is running on correct host:port |
| No torrents captured | Ensure Tixati has active transfers |
| Very slow scraping | Reduce active torrents or increase timeout |
| File too large | Normal for many torrents; consider archiving |
| Browser hangs | Use `--headless` flag |

### Getting Help

1. **Check this guide** for common issues
2. **Test connectivity**: Open http://localhost:8888 in browser
3. **Try with --console**: See detailed output
4. **Use --headless**: Avoid UI issues
5. **Check disk space**: Ensure room for output file

## Version Information

- **Current Version**: 1.0 (Interactive with Selenium)
- **Features**: Button clicking, torrent details, auto-save
- **Last Updated**: December 2025

## Changelog

### v1.0 - Interactive Scraper
- ✅ Selenium-based browser automation
- ✅ Clicks all buttons and options
- ✅ Captures torrent details (most important)
- ✅ Auto-saves with date/time filename
- ✅ HTTP fallback for compatibility
- ✅ Interactive HTML output with tabs
- ✅ Improved dark theme UI

### Previous Version (v0.1)
- Basic HTTP scraping only
- No button clicking
- Manual filename specification

## License & Distribution

This tool is provided as-is for use with Tixati WebUI scraping. Include all files when distributing.

---

**Last Updated**: December 28, 2025
**For Tixati WebUI Version**: 1.x+
**Compatibility**: Windows 7, 8, 10, 11, Server 2012+
