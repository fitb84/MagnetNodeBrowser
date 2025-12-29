# Tixati Node Browser - Complete Executable Suite

Three standalone executables for complete Tixati node management and monitoring.

## Overview

| Executable | Purpose | Size | Type |
|-----------|---------|------|------|
| **TixatiWebScraper.exe** | Flask backend API server | 15.93 MB | Service |
| **TixatiNodeBrowserBackend.exe** | Backend API (same as above) | 15.92 MB | Service |
| **TixatiScraper.exe** | WebUI snapshot utility | 11.43 MB | Utility |

## 1. TixatiWebScraper.exe - Backend API Server

**Purpose:** Provides REST API for the mobile app to control Tixati

### Quick Start
```bash
TixatiWebScraper.exe
```

Starts listening on `http://localhost:5050`

### What It Does
- Scrapes Tixati WebUI in real-time
- Parses HTML with BeautifulSoup
- Provides JSON API endpoints
- Proxies torrent control commands to Tixati
- Serves to mobile app via REST API

### API Endpoints
```
GET  /api/downloads        - List all torrents (JSON)
GET  /api/stats            - Drive and library stats
POST /api/add              - Add magnet link
DELETE /api/downloads/<name>  - Remove torrent
GET  /bandwidth            - Bandwidth data
POST /transfers/action     - Control torrents
```

### Requirements
- Tixati running on localhost:8888
- No Python installation needed
- Windows 7+

### Output Example
```
MagnetNode Dashboard running at http://localhost:5050
```

## 2. TixatiNodeBrowserBackend.exe - Backend API (Alternative Name)

Identical to **TixatiWebScraper.exe** - different name, same functionality.

Use whichever name you prefer. They are the same executable.

## 3. TixatiScraper.exe - WebUI Snapshot Utility

**Purpose:** Create complete HTML snapshots of Tixati for testing, backup, or analysis

### Quick Start
```bash
TixatiScraper.exe --save snapshot.html
```

Creates `snapshot.html` with complete Tixati interface snapshot.

### What It Does
- Connects to Tixati WebUI
- Scrapes all pages (home, transfers, bandwidth, DHT, settings, help)
- Combines into single HTML file with tabbed interface
- Saves to file or prints to console

### Command Examples
```bash
# Display to console
TixatiScraper.exe

# Save to file
TixatiScraper.exe --save snapshot.html

# Custom host/port
TixatiScraper.exe --host 192.168.1.100 --port 9999

# Save with custom settings
TixatiScraper.exe --save out.html --host 192.168.1.1 --timeout 20
```

### Requirements
- Tixati running and accessible
- No Python installation needed
- Windows 7+

### Output Example
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

## Deployment Architecture

```
Mobile App (Android)
    ↓
Tailscale VPN
    ↓
Windows PC (Backend Machine)
    ├─ TixatiWebScraper.exe (running)
    │   ↓
    │   Scrapes Tixati WebUI
    │   ↓
    │   Provides JSON API
    │
    └─ Tixati (localhost:8888)
       ↓
       BitTorrent client
       ↓
       Torrents
```

## Deployment Guide

### Prerequisites
- Windows 7 or later
- Tixati BitTorrent client installed and configured
- Tailscale (for remote access) or local network

### Step-by-Step

#### 1. Prepare Backend Machine
```bash
# Copy TixatiWebScraper.exe to backend machine
# Create a folder, e.g., C:\TixatiNode\
```

#### 2. Start Tixati
- Launch Tixati
- Ensure WebUI is enabled (Settings → WebUI)
- Default: localhost:8888

#### 3. Start Backend Server
```bash
# Double-click TixatiWebScraper.exe
# OR from command line:
TixatiWebScraper.exe

# Should show:
# MagnetNode Dashboard running at http://localhost:5050
```

#### 4. Test Backend
Open browser on backend machine:
```
http://localhost:5050/api/downloads
```

Should return JSON with current torrents.

#### 5. Configure Mobile App
- Open app settings
- Backend URL: `http://<TAILSCALE_IP>:5050`
  - Get Tailscale IP: `ipconfig` or Tailscale app
  - Example: `http://100.64.0.2:5050`
- Save settings

#### 6. Test Mobile App
- Open mobile app
- Should see current downloads
- Try adding a magnet link
- Try stopping/starting torrents

### Optional: Create Snapshot

At any time, create a snapshot of Tixati state:
```bash
TixatiScraper.exe --save backup_$(date +%Y%m%d_%H%M%S).html
```

## File Locations

After build (in `backend/dist/`):
- `TixatiWebScraper.exe` - Backend server
- `TixatiNodeBrowserBackend.exe` - Backend server (alternative name)
- `TixatiScraper.exe` - Scraper utility

## Build Instructions

### Rebuild Backend
```bash
cd backend
python build_tixati_scraper.py
```

### Rebuild Scraper
```bash
cd backend
python build_scraper_exe.py
```

### Rebuild Both
```bash
cd backend
python build_tixati_scraper.py
python build_scraper_exe.py
```

## Troubleshooting

### Backend Issues

**Problem:** "Connection refused" in mobile app
- **Solution:** Ensure backend exe is running and Tixati is accessible

**Problem:** Backend shows "Tixati unavailable"
- **Solution:** Check Tixati is running, WebUI enabled, accessible at localhost:8888

**Problem:** "404 errors" in mobile app
- **Solution:** Verify backend URL in app settings (should include port 5050)

### Scraper Issues

**Problem:** "Cannot connect to Tixati"
- **Solution:** Ensure Tixati is running, try `--host 127.0.0.1 --port 8888`

**Problem:** Timeout errors
- **Solution:** Use `--timeout 30` for slower connections

**Problem:** Scraper produces large file
- **Solution:** Expected - complete WebUI = 300-500 KB. Use `--save` to compress.

## Summary

You now have:
1. ✓ **TixatiWebScraper.exe** - Full-featured backend for mobile app
2. ✓ **TixatiScraper.exe** - Utility for creating snapshots
3. ✓ **Mobile App APK** - Ready to install on Android

All three are **standalone executables** - no Python, dependencies, or setup required. Just copy and run!

## Next Steps

1. Copy `TixatiWebScraper.exe` to your backend machine
2. Double-click to start backend
3. Install `app-release.apk` on your Android device
4. Configure app with backend URL
5. Enjoy! 🎉

For detailed instructions, see:
- [Backend Deployment](DEPLOYMENT.md)
- [Scraper Usage](SCRAPER_README.md)
