# Quick Start - Enhanced Tixati Scraper

## What's New? ✨

The **TixatiScraper.exe** now features:
- 🖱️ **Automatic button clicking** - navigates all UI elements
- 📋 **Captures torrent details** - most important feature!
- 💾 **Auto-save** - just double-click, no arguments needed
- ⏰ **Automatic filename** - uses date/time format

## Super Quick Start (30 seconds)

### Step 1: Run the Scraper
```cmd
cd C:\TixatiNodeBrowserMobile\backend\dist
TixatiScraper.exe
```

### Step 2: Wait for Completion
The scraper automatically:
- Connects to Tixati (localhost:8888)
- Clicks all buttons on each page
- Captures torrent details
- Saves to: `tixati_snapshot_20231228_143022.html`

### Step 3: View Results
- Open the generated HTML file in your browser
- Browse tabs for different pages
- Expand collapsible sections for full content

**Done! That's it!** ✅

---

## What Gets Captured?

```
✓ Home page
✓ Transfers list (all downloads)
✓ Bandwidth information
✓ DHT network info
✓ Settings
✓ Help documentation
✓ TORRENT DETAILS (most important - actual torrent info pages)
```

---

## Common Use Cases

### Use Case 1: Daily Backup
Just double-click: `TixatiScraper.exe`
Creates: `tixati_snapshot_YYYYMMDD_HHMMSS.html`
Done!

### Use Case 2: Specific Time
Want to capture at 3 PM? Use Windows Task Scheduler:
1. Create task
2. Set action: `TixatiScraper.exe --headless`
3. Schedule for 3 PM daily
4. Done!

### Use Case 3: Different Tixati Host
```cmd
TixatiScraper.exe --host 192.168.1.100 --port 8888
```
Creates: `tixati_snapshot_YYYYMMDD_HHMMSS.html`

### Use Case 4: Save Anywhere
```cmd
TixatiScraper.exe --save C:\backups\my_snapshot.html
```

### Use Case 5: See Details in Console
```cmd
TixatiScraper.exe --console
```
Prints output to terminal instead of saving

---

## Output File Details

**Filename Format**
```
tixati_snapshot_YYYYMMDD_HHMMSS.html

Example:
tixati_snapshot_20231228_143022.html
       ↑ Generated date/time automatically
```

**File Size**
- Typical: 5-50 MB
- Larger with more torrents
- Includes all page HTML + torrent details

**Location**
- Saved to: Current working directory
- Or: Your specified path with `--save`

---

## Browser View (What You'll See)

The HTML file opens with:

### Tabs at Top
```
[ HOME ] [ TRANSFERS ] [ BANDWIDTH ] [ DHT ] [ SETTINGS ] [ HELP ] [ TORRENT DETAILS ]
```

### Each Tab Contains
- Page title and generation timestamp
- Collapsible sections (click to expand)
- Complete HTML of that page

### Torrent Details Tab
Shows all captured torrent detail pages:
- Torrent #1 (expandable)
- Torrent #2 (expandable)
- Torrent #3 (expandable)
- ... and more

---

## Command Reference

```cmd
# Default (easiest) - auto-saves with timestamp
TixatiScraper.exe

# Custom host/port
TixatiScraper.exe --host 192.168.1.1 --port 8888

# Headless (no browser window)
TixatiScraper.exe --headless

# Print to console instead of saving
TixatiScraper.exe --console

# Custom filename
TixatiScraper.exe --save snapshot.html

# Long timeout (for slow connections)
TixatiScraper.exe --timeout 30

# Combine options
TixatiScraper.exe --headless --host 192.168.1.1 --save snapshot.html

# Show help
TixatiScraper.exe --help
```

---

## If Something Goes Wrong

### ❌ "Cannot connect to Tixati"
**Solution**: Make sure Tixati is running on localhost:8888
```cmd
# Test in browser first:
# Open: http://localhost:8888/home
# If that works, try the scraper again
```

### ❌ "No pages scraped"
**Solution**: Check Tixati WebUI is accessible
```cmd
# Try with explicit host:
TixatiScraper.exe --host YOUR_IP --port 8888

# Or try with console output:
TixatiScraper.exe --console
```

### ❌ Browser window hangs
**Solution**: Use headless mode
```cmd
TixatiScraper.exe --headless
```

### ❌ Takes too long
**Solution**: Some reasons it's slow
- First run (browser startup)
- Many active torrents
- Slow internet connection
- Use `--timeout 30` if timing out

---

## File Locations

**Executable**
```
C:\TixatiNodeBrowserMobile\backend\dist\TixatiScraper.exe
```

**Documentation**
```
C:\TixatiNodeBrowserMobile\
├── COMPLETE_SYSTEM_ARCHITECTURE.md
├── backend\
│   ├── INTERACTIVE_SCRAPER_GUIDE.md
│   └── SCRAPER_ENHANCEMENT_SUMMARY.md
```

---

## Key Features Comparison

| Feature | Before | Now |
|---------|--------|-----|
| Button clicking | ✗ | ✅ |
| Torrent details | ✗ | ✅ |
| Auto-save | ✗ | ✅ |
| No arguments | ✗ | ✅ |
| HTTP fallback | ✓ | ✓ |
| Interactive HTML | ✓ | ✅ Improved |
| File size | 2-5 MB | 5-50 MB |

---

## Integration Examples

### Windows Task Scheduler (Daily Backup)
1. Open Task Scheduler
2. Create Basic Task
3. Name: "Daily Tixati Snapshot"
4. Trigger: Daily at 10:00 AM
5. Action: Start program
6. Program: `C:\TixatiNodeBrowserMobile\backend\dist\TixatiScraper.exe`
7. Working directory: `C:\backups\`
8. Click OK

Now it runs daily and saves to C:\backups\ automatically!

### Command Line Batch File
Create `scrape.bat`:
```batch
@echo off
REM Daily Tixati snapshot backup
cd /d "C:\TixatiNodeBrowserMobile\backend\dist"
TixatiScraper.exe --headless
REM Optional: upload to cloud
REM aws s3 cp ..\dist\tixati_snapshot_*.html s3://my-bucket/
pause
```

---

## Tips & Tricks

### Tip 1: Silent Background Scraping
```cmd
TixatiScraper.exe --headless --timeout 20
```
No browser window, runs in background

### Tip 2: Check Detailed Output
```cmd
TixatiScraper.exe --console | tee output.txt
```
Saves output to file while viewing

### Tip 3: Clean Old Snapshots
```cmd
# Windows - delete older than 30 days
forfiles /S /M tixati_snapshot_*.html /D +30 /C "cmd /c del @file"
```

### Tip 4: Compress for Storage
```cmd
# Compress latest snapshot
tar.exe -czf backup.tar.gz tixati_snapshot_*.html
```

---

## What's Being Captured (Details)

### Static Pages (Basic HTML)
- /home
- /bandwidth
- /dht
- /settings
- /help

### Dynamic Pages (With Interactions)
- /transfers (after clicking buttons)

### Most Important: Torrent Details
The scraper now clicks on each torrent row and captures the detail page. This includes:
- Full torrent information
- File lists
- Peer details
- Progress information
- Current state/status

---

## Performance Notes

- **Startup**: 5-10 seconds (browser initialization)
- **Scraping**: 30-60 seconds (depends on button count and torrents)
- **Saving**: <1 second
- **File size**: 5-50 MB (larger = more torrents)

First run is slightly slower due to browser setup. Subsequent runs are similar.

---

## Storage Considerations

### File Sizes
- Home page: ~50 KB
- Transfers: ~100 KB
- Each torrent detail: ~50 KB
- Total per snapshot: 5-50 MB

### Storage for Archive
- Daily snapshots: ~200 MB per month
- Keep 30 days: ~6 GB
- Archive older than 30 days

### Cleanup
```cmd
# Keep only last 10 snapshots
dir /b /o-d tixati_snapshot_*.html | findstr /v /c:"." /v /l "1" | for /f %%A in ('more ^<') do @del %%A
```

---

## Frequently Asked Questions

**Q: Do I need Python installed?**
A: No! The .exe includes everything.

**Q: What if Tixati crashes?**
A: Scraper will fail gracefully. Restart Tixati and try again.

**Q: Can I use this on Linux/Mac?**
A: The .exe is Windows only. But the Python script (tixati_scraper.py) works on any OS!

**Q: How do I use on remote machine?**
A: Use Tailscale or VPN, then: `TixatiScraper.exe --host REMOTE_IP`

**Q: Does it delete torrents?**
A: No! It only reads/views data. No changes made to Tixati.

**Q: How often should I run it?**
A: Up to you! Daily is common for backups.

---

## Next Steps

1. **Run it**: Double-click `TixatiScraper.exe`
2. **View results**: Open generated HTML file
3. **Explore**: Browse all tabs and expand sections
4. **Schedule**: Set up daily backup (optional)

That's it! You now have complete Tixati snapshots with torrent details! 🎉

---

**Version**: Interactive v1.0
**Updated**: December 28, 2025
**Status**: Ready to use
