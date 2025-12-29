# Tixati WebUI Scraper

Standalone tool to scrape the entire Tixati WebUI and output complete HTML snapshots.

## Overview

The Tixati scraper is a utility that:
- Connects to a running Tixati WebUI instance
- Scrapes all pages (home, transfers, bandwidth, DHT, settings, help)
- Combines them into a single HTML file with tabbed navigation
- Saves to file or prints to console

## Use Cases

1. **Development & Testing** - Get fresh HTML dumps for regex/parsing testing
2. **Backup & Analysis** - Save current Tixati state for later review
3. **Offline Reference** - Create offline copies of Tixati state
4. **Debugging** - Diagnose Tixati UI changes or API issues
5. **Documentation** - Generate snapshots of your setup

## Files

- **TixatiScraper.exe** (11.43 MB) - Standalone scraper executable
- **tixati_scraper.py** - Python source code

## Usage

### Basic Usage (Display to Console)
```bash
TixatiScraper.exe
```
Scrapes Tixati at `localhost:8888` and prints HTML to console.

### Save to File
```bash
TixatiScraper.exe --save snapshot.html
```
Saves complete snapshot to `snapshot.html` with tabbed interface.

### Custom Host/Port
```bash
TixatiScraper.exe --host 192.168.1.100 --port 8888
```

### Combination
```bash
TixatiScraper.exe --save out.html --host 192.168.1.1 --port 9999 --timeout 20
```

## Command-Line Options

```
--host HOST           Tixati WebUI host (default: localhost)
--port PORT           Tixati WebUI port (default: 8888)
--save SAVE           Save snapshot to file (omit to print to console)
--timeout TIMEOUT     Request timeout in seconds (default: 10)
-h, --help           Show this help message
```

## Example Outputs

### Console Output
```
Connecting to Tixati at http://localhost:8888...
Scraping Tixati WebUI (6 pages)...

  Scraping home... OK (45234 bytes)
  Scraping transfers... OK (128456 bytes)
  Scraping bandwidth... OK (5234 bytes)
  Scraping dht... OK (12345 bytes)
  Scraping settings... OK (98765 bytes)
  Scraping help... OK (34567 bytes)

Successfully scraped 6/6 pages

[OK] Scraping complete
```

### File Output
Creates an HTML file with:
- Header showing timestamp and pages captured
- Tab buttons for each page
- Full HTML content for each page
- Collapsible sections to reduce initial file size
- Interactive navigation

## Requirements

- **Tixati** running and accessible at specified host:port
- **Windows** (for .exe) or Python 3.8+ (for .py)
- Network access to Tixati WebUI

## Troubleshooting

### Connection Error
```
[ERROR] Cannot connect to Tixati at http://localhost:8888: ...
```
**Fix:** Ensure Tixati is running and WebUI is enabled at the specified host:port.

### Timeout Error
```
[ERROR] Connection timeout
```
**Fix:** Use `--timeout 30` to increase timeout for slow connections.

### No Pages Scraped
```
[ERROR] No pages scraped. Is Tixati running?
```
**Fix:** Check that Tixati is running and accessible.

## How to Deploy

1. Copy `TixatiScraper.exe` to any Windows machine with network access to Tixati
2. Run it: `TixatiScraper.exe --save snapshot.html`
3. Snapshot will be created in the current directory

## Building from Source

Requires Python 3.8+ with requests and PyInstaller:

```bash
pip install requests pyinstaller
python build_scraper_exe.py
```

Output: `dist/TixatiScraper.exe`

## Technical Details

### Pages Scraped
- `/home` - Dashboard and stats
- `/transfers` - Active transfers/torrents
- `/bandwidth` - Bandwidth graph
- `/dht` - DHT status
- `/settings` - Configuration
- `/help` - Help documentation

### Output Format
- **Console:** Raw HTML concatenated
- **File:** Combined HTML with tabbed interface
- **Size:** Typically 300-500 KB depending on number of active transfers

### Performance
- Typical scrape time: 1-5 seconds
- Network I/O bound (depends on Tixati responsiveness)
- All pages scraped sequentially

## Differences from Backend

| Component | Purpose |
|-----------|---------|
| **TixatiWebScraper.exe** | Flask backend that proxies API requests from mobile app |
| **TixatiScraper.exe** | Utility to scrape and save complete Tixati snapshots |

They are separate tools for different purposes:
- Backend: Serves API to mobile app (ongoing)
- Scraper: One-time snapshot utility (on-demand)

## Examples

### Create Daily Snapshots
```bash
for /L %i in (1,1,5) do (
  TixatiScraper.exe --save snapshot_%date:~-4,4%%date:~-10,2%%date:~-7,2%_%time:~0,2%.html
  timeout /t 3600
)
```

### Monitor Remote Tixati
```bash
TixatiScraper.exe --host 192.168.1.100 --save C:\Backups\tixati_snapshot.html
```

### Verify Configuration
```bash
TixatiScraper.exe --host 10.0.0.5 --port 9999 --timeout 15 --save test.html
```

## Support

If the scraper fails:
1. Test Tixati manually in browser: `http://host:port/home`
2. Check Tixati logs for errors
3. Ensure firewall allows access
4. Try increasing `--timeout` value

## License

Same as Tixati Node Browser project.
