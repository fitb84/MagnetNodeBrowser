# Complete Tixati Node Browser - System Architecture

## Overview

The Tixati Node Browser Mobile system consists of three main components:

```
┌─────────────────────────────────────────────────────────────────┐
│                    TIXATI NODE BROWSER SYSTEM                    │
└─────────────────────────────────────────────────────────────────┘
         │
         ├─────────────────┬──────────────────┬──────────────────┐
         │                 │                  │                  │
         ▼                 ▼                  ▼                  ▼
    ┌─────────┐    ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
    │  Mobile │    │   Backend    │  │   Scraper    │  │   Tixati     │
    │   App   │    │    Server    │  │   Utility    │  │    WebUI     │
    │ (Flutter│    │ (Flask/Python)  │ (Interactive)│  │  (Target)    │
    │   APK) │    │              │  │              │  │              │
    └────┬────┘    └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
         │                 │                 │                 │
         │                 │                 │                 │
         └────────────┬────┴────────┬────────┴────────┬────────┘
                      │            │                 │
                      ▼            ▼                 ▼
                  ┌──────────────────────────────────────┐
                  │   TIXATI ON localhost:8888           │
                  │   (Real Tixati WebUI Instance)       │
                  └──────────────────────────────────────┘
```

## Component Details

### 1. Mobile App (Flutter APK)
**File**: `/lib/services/api_client.dart`
**Purpose**: User interface for managing Tixati remotely

**Features**:
- View download list
- Check stats/bandwidth
- Remove downloads
- Browse settings
- Monitor transfers

**API Communication**:
```
Mobile App 
    ↓
Connects to: http://localhost:5050 (or remote IP:5050 via Tailscale)
    ↓
Uses endpoints: /api/downloads, /api/stats, /api/add
    ↓
Receives: JSON responses with torrent data
```

**Status**: ✅ Fully functional, tested with backend

---

### 2. Backend Server (TixatiNodeBrowserBackend.exe)
**File**: `/backend/run_local_app.py`
**Built As**: `TixatiNodeBrowserBackend.exe` (15.92 MB)
**Purpose**: REST API server that bridges mobile app and Tixati WebUI

**Features**:
- Listens on `http://localhost:5050`
- Scrapes Tixati WebUI using requests + BeautifulSoup4
- Provides JSON APIs for mobile app
- Auto-manages downloads
- Proxies to Tixati when needed

**API Endpoints**:
```
GET  /api/downloads           - List all downloads (JSON)
GET  /api/stats               - Server statistics (JSON)
POST /api/add                 - Add new magnet/torrent
DELETE /api/downloads/<name>  - Remove torrent by name
GET  /api/downloads/auto-manage
POST /transfers/<hash>/<page> - Proxy to Tixati detail pages
GET  /transfers_html          - Fallback HTML proxy
```

**Data Flow**:
```
Mobile App (APK)
    ↓ JSON Request (REST)
Backend Server (localhost:5050)
    ↓ HTTP Request (requests library)
Tixati WebUI (localhost:8888)
    ↓ HTML Response
Backend Server
    ↓ Parse HTML with BeautifulSoup
    ↓ Convert to JSON
Mobile App (APK)
    ↓ Display to user
```

**Status**: ✅ Fully functional, all qBittorrent references removed

---

### 3. Interactive Scraper (TixatiScraper.exe)
**File**: `/backend/tixati_scraper.py`
**Built As**: `TixatiScraper.exe` (11.68 MB)
**Purpose**: Standalone tool to capture complete WebUI snapshots

**Features**:
- Browser automation (Selenium)
- Clicks all buttons and options
- **Captures torrent details** (most important!)
- Auto-saves with timestamp
- HTTP fallback if browser unavailable
- Interactive HTML output

**Scraping Process**:
```
1. Initialize WebDriver (Chrome/Edge)
2. For each page (/home, /transfers, /bandwidth, /dht, /settings, /help):
   a. Load page in browser
   b. Click all buttons to trigger dynamic content
   c. Capture rendered HTML
3. Navigate to /transfers and click torrent rows:
   a. Click each torrent to show details
   b. Capture detail page HTML
   c. Back button to return to list
4. Combine all captured HTML into single interactive file
5. Auto-save as: tixati_snapshot_YYYYMMDD_HHMMSS.html
```

**Output Structure**:
```html
tixati_snapshot_20231228_143022.html
├── HEADER (metadata, generation time)
├── TABS
│   ├── HOME (home page data)
│   ├── TRANSFERS (downloads list)
│   ├── BANDWIDTH (bandwidth info)
│   ├── DHT (DHT information)
│   ├── SETTINGS (configuration)
│   ├── HELP (help pages)
│   └── TORRENT DETAILS (all captured torrent detail pages)
└── JAVASCRIPT (tab switching, expand/collapse)
```

**Usage**:
```cmd
# Default: auto-save with timestamp
TixatiScraper.exe

# Custom settings
TixatiScraper.exe --host 192.168.1.1 --port 8888 --headless
```

**Status**: ✅ Fully functional, interactive scraping working

---

### 4. Tixati WebUI (Target System)
**Location**: `http://localhost:8888`
**Purpose**: Real Tixati BitTorrent client web interface

**Pages Available**:
- `/home` - Home/status page
- `/transfers` - Downloads list with status
- `/bandwidth` - Bandwidth graphs
- `/dht` - DHT network info
- `/settings` - Configuration
- `/help` - Help documentation

**Authentication**: None required (default Tixati setup)

---

## Deployment Architecture

### Local Development Setup
```
Your Machine
├── Tixati (localhost:8888)
├── Backend Server (localhost:5050)
├── Flutter App (emulator/device)
└── Optional: Scraper for backups
```

### Remote Setup (via Tailscale)
```
Your Machine (Tailscale Client)
    ↓ Tailscale VPN
Remote Machine (Tailscale Server)
├── Tixati (localhost:8888)
├── Backend Server (localhost:5050)
└── Flutter App (via Tailscale IP:5050)
```

### Production Setup
```
Server Machine
├── Tixati running (localhost:8888)
├── Backend Server EXE (localhost:5050)
│   └── Double-click TixatiNodeBrowserBackend.exe
└── Scraper EXE (optional, for scheduled snapshots)
    └── Double-click TixatiScraper.exe

Client Machine (anywhere on network/internet with Tailscale)
├── Flutter App (mobile)
    └── Configure: Backend URL = [Tailscale IP]:5050
└── Desktop Scraper (optional)
    └── TixatiScraper.exe --host [Server IP/Tailscale IP]
```

---

## Data Flow Examples

### Example 1: View Downloads in Mobile App

```
1. User opens app → Taps "Transfers"
2. App makes request:
   GET http://127.0.0.1:5050/api/downloads
   
3. Backend receives request:
   - Connects to Tixati at http://localhost:8888/transfers
   - Scrapes HTML with BeautifulSoup
   - Finds all torrent rows
   - Extracts: name, size, status, progress, etc.
   
4. Backend returns JSON:
   {
     "torrents": [
       {
         "name": "Ubuntu-20.04.iso",
         "status": "downloading",
         "progress": 85,
         "size": 2847483648,
         "speed": 5242880
       },
       ...
     ]
   }
   
5. App displays list:
   ✓ Ubuntu-20.04.iso [=====>   ] 85% ↓5 MB/s
   ✓ Fedora-35.iso    [========>] 100% ✓
   ...
```

### Example 2: Capture Complete Snapshot

```
1. User runs: TixatiScraper.exe

2. Scraper initializes:
   - Starts Chrome WebDriver
   - Connects to Tixati on localhost:8888
   
3. For each page:
   - Loads /home, /transfers, /bandwidth, etc.
   - Clicks buttons to trigger dynamic content
   - Captures rendered HTML
   
4. For torrent details (most important):
   - Navigates to /transfers
   - Finds torrent rows in HTML
   - Clicks each torrent (5+ torrents)
   - Captures detail page HTML
   - Returns to list, repeats
   
5. Combines all data:
   - Creates HTML with tabs
   - Collapses large sections
   - Adds navigation
   
6. Auto-saves:
   tixati_snapshot_20231228_143022.html (8.5 MB)
   
7. User opens in browser:
   - Sees interactive tabbed interface
   - Can browse each page
   - Can expand torrent details
   - Contains complete snapshot of all UI
```

### Example 3: Add New Download via App

```
1. User enters magnet link in app
2. App sends POST request:
   POST http://127.0.0.1:5050/api/add
   Body: {"magnet": "magnet:?xt=urn:btih:..."}
   
3. Backend receives and:
   - Accesses Tixati /transfers page
   - Finds "Add" link
   - Submits magnet/link to Tixati
   - Tixati adds download
   
4. Tixati starts downloading

5. App refreshes download list
   - Gets new download from /api/downloads
   - Shows in UI immediately
```

---

## Technology Stack

### Mobile Frontend
- **Framework**: Flutter (Dart)
- **Build**: APK for Android
- **Communication**: HTTP REST Client
- **Data Format**: JSON

### Backend Server
- **Language**: Python 3.x
- **Framework**: Flask (lightweight web server)
- **HTML Parsing**: BeautifulSoup4
- **HTTP Client**: requests
- **Deployment**: PyInstaller → .exe (no Python needed on target)

### Interactive Scraper
- **Language**: Python 3.x
- **Browser Automation**: Selenium WebDriver
- **HTML Parsing**: BeautifulSoup4
- **HTTP Client**: requests
- **Deployment**: PyInstaller → .exe

### Target System
- **Tixati**: BitTorrent client with WebUI
- **WebUI**: HTML-based (localhost:8888)
- **No Authentication**: Default setup
- **Compatibility**: Windows, Linux, Mac

---

## File Structure

```
TixatiNodeBrowserMobile/
├── lib/
│   ├── main.dart
│   ├── screens/
│   │   ├── browser_screen.dart
│   │   ├── dashboard_screen.dart
│   │   ├── downloads_screen.dart
│   │   ├── ingest_screen.dart
│   │   └── settings_screen.dart
│   ├── services/
│   │   ├── api_client.dart          ← Connects to backend:5050
│   │   └── notification_service.dart
│   ├── theme/
│   │   └── app_theme.dart
│   └── utils/
│       └── magnet_parser.dart
│
├── backend/
│   ├── run_local_app.py             ← Backend server (Flask)
│   ├── tixati_scraper.py            ← Interactive scraper
│   ├── build_exe.py                 ← Builds backend EXE
│   ├── build_scraper_exe.py         ← Builds scraper EXE
│   ├── dist/
│   │   ├── TixatiNodeBrowserBackend.exe
│   │   ├── TixatiScraper.exe
│   │   └── TixatiWebScraper.exe
│   ├── templates/
│   │   └── main.html               ← Web UI template
│   ├── INTERACTIVE_SCRAPER_GUIDE.md
│   └── SCRAPER_ENHANCEMENT_SUMMARY.md
│
├── android/
│   └── app/
│       └── build/
│           └── outputs/
│               └── apk/
│                   └── release/
│                       └── app-release.apk
│
├── pubspec.yaml                     ← Flutter dependencies
├── analysis_options.yaml
├── SETUP_GUIDE.md
└── README.md
```

---

## Port Usage

| Port | Service | Component | Purpose |
|------|---------|-----------|---------|
| 8888 | HTTP | Tixati WebUI | Real Tixati interface |
| 5050 | HTTP | Backend Server | REST API for mobile app |
| 9999 | - | - | Reserved for future use |

---

## Environment Requirements

### Development Machine
- Python 3.x
- Flutter SDK
- Android SDK (for APK)
- Virtual environment (venv)
- PyInstaller (for building .exe files)

### Deployment Machine
- Windows 7+ (for .exe files)
- Tixati installed and running
- Network connectivity
- 100+ MB free disk space

### Mobile Device
- Android 6.0+ (Tixati Node Browser APK)
- Network access to backend server
- Tailscale (optional, for remote access)

---

## Security Considerations

### Current Implementation
- ✓ No authentication required (Tixati default)
- ✓ Local network only (by default)
- ✓ HTTP only (no HTTPS)
- ✓ No encryption

### For Remote Deployment
- ⚠️ Use Tailscale or VPN for secure access
- ⚠️ Don't expose port 5050 to public internet
- ⚠️ Protect snapshot files (contain all torrent data)
- ⚠️ Firewall rules to limit access

### Recommended Security
1. **Network**: Use Tailscale for remote access
2. **Firewall**: Only allow trusted IPs
3. **Data**: Encrypt sensitive snapshot files
4. **Access**: Run backend on local machine only
5. **Logging**: Monitor backend logs for suspicious activity

---

## Performance Characteristics

| Component | Startup | Response | Memory | Disk |
|-----------|---------|----------|--------|------|
| Backend | <5 sec | <500ms | 50-100 MB | 16 MB |
| Scraper | 5-10 sec | 30-60 sec | 100-300 MB | 8.5 MB per snapshot |
| Mobile App | 2-3 sec | <100ms | 100-200 MB | - |

---

## Troubleshooting Guide

### Backend won't connect to Tixati
```
Check:
1. Tixati is running (localhost:8888)
2. Firewall allows 8888
3. Try: curl http://localhost:8888/home
```

### Mobile app gets 404 errors
```
Check:
1. Backend is running (localhost:5050)
2. App has correct backend URL in settings
3. Network connectivity between app and backend
4. Try: http://YOUR_IP:5050/api/downloads
```

### Scraper won't find torrents
```
Check:
1. Tixati has active downloads
2. Correct Tixati host/port
3. Browser automation working (--headless test)
4. Try: TixatiScraper.exe --console
```

### Large output files
```
Normal for many torrents. Solution:
1. Reduce active torrents
2. Archive old snapshots
3. Compress HTML files (gzip)
```

---

## Maintenance

### Regular Tasks
- Monitor backend logs
- Archive old scraper snapshots
- Update dependencies if needed
- Test connectivity regularly

### Scheduled Backups
- Daily scraper snapshots (Windows Task Scheduler)
- Archive weekly
- Keep last 30 days

### Updates
- Check for Tixati updates
- Update Flutter/dependencies quarterly
- Rebuild executables after dependency updates

---

## Support Resources

1. **Backend Issues**: Check `run_local_app.py` logs
2. **Scraper Issues**: Run with `--console` for debug output
3. **Mobile App Issues**: Check network connectivity
4. **Tixati Issues**: Verify Tixati is running correctly

---

## Summary

This system provides:
- ✅ Remote management of Tixati via mobile app
- ✅ Complete data snapshots via interactive scraper
- ✅ Standalone executable deployment (no Python needed)
- ✅ Flexible architecture (local or remote via Tailscale)
- ✅ Automatic data capture and saving

**Current Status**: Production ready ✅

All components built, tested, and documented.

---

**Last Updated**: December 28, 2025
**Version**: Complete System v1.0
**Total Size**: 
- Backend EXE: 15.92 MB
- Scraper EXE: 11.68 MB
- Mobile APK: 47.8 MB
