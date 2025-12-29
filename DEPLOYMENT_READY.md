# Tixati Node Browser - Quick Reference

## Status: Ready for Deployment

All qBittorrent references have been removed and replaced with Tixati. The app now correctly connects to the backend instead of trying to reach Tixati directly.

## Backend Architecture

```
Mobile App (Flutter)
      ↓
Backend API (Flask) - localhost:5050
      ↓
Tixati WebUI (HTML Scraper) - localhost:8888
```

The app communicates **only** with the backend. The backend handles all Tixati WebUI scraping and control.

## Executables

### Main Backend
- **File:** `backend/dist/TixatiNodeBrowserBackend.exe`
- **Size:** ~16 MB
- **Startup:** Double-click, then backend runs on `http://localhost:5050`

### Alternative Build
- **File:** `backend/dist/TixatiWebScraper.exe`
- **Same executable** (renamed for clarity)
- **Use either one** - they are identical

### Mobile App
- **File:** `build/app/outputs/flutter-apk/app-release.apk`
- **Size:** ~48 MB
- **Install on Android device** via adb or manual transfer

## Deployment Checklist

### On Backend Machine (Windows)
1. [ ] Copy `TixatiNodeBrowserBackend.exe` or `TixatiWebScraper.exe`
2. [ ] Ensure Tixati is running (WebUI at localhost:8888)
3. [ ] Double-click the .exe
4. [ ] Backend should start listening on `http://localhost:5050`
5. [ ] Test in browser: `http://localhost:5050/api/downloads`

### On Android Device
1. [ ] Copy `app-release.apk` to phone
2. [ ] Install: Settings → Apps → Install Unknown Apps → Allow
3. [ ] Install the APK
4. [ ] Open the app
5. [ ] Settings → Configure Backend URL to: `http://<TAILSCALE_IP>:5050`
6. [ ] Save and refresh

## API Endpoints

All endpoints return JSON (except HTML proxy endpoints):

- `GET /api/stats` - Drive usage and libraries
- `GET /api/downloads` - List active torrents
- `GET /api/tv-folders` - Available TV series folders
- `POST /api/add` - Add magnet link (requires: `magnet`, `category`)
- `DELETE /api/downloads/<name>` - Remove torrent by name
- `POST /api/downloads/auto-manage` - Auto-remove at 2.0 ratio
- `GET /bandwidth` - Proxy bandwidth HTML
- `GET /transfers` - Proxy transfers HTML
- `POST /transfers/action` - Proxy Tixati actions (start/stop/remove)

## Build Instructions

### Rebuild Backend Executable
```bash
cd backend
python build_tixati_scraper.py
# Output: dist/TixatiWebScraper.exe
```

### Rebuild APK
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

## Troubleshooting

### App shows 404 errors
- **Cause:** Backend not running or URL incorrect
- **Fix:** Ensure backend .exe is running, check Settings → Backend URL

### Backend shows "Tixati unavailable"
- **Cause:** Tixati WebUI not accessible
- **Fix:** Ensure Tixati is running on localhost:8888

### App shows "Connection refused"
- **Cause:** Backend machine unreachable
- **Fix:** Check Tailscale connection, ensure IP address is correct

## Files Modified

### Backend
- `backend/run_local_app.py` - Removed all qBittorrent references
- `backend/build_tixati_scraper.py` - New PyInstaller script
- `backend/DEPLOYMENT.md` - Deployment guide

### Frontend (Dart)
- `lib/services/api_client.dart` - Updated to use backend API endpoints
- `backend/templates/main.html` - Updated remove button to use torrent names

## Clean Rebuild (if needed)

```bash
# Clean build artifacts
flutter clean
rm -rf backend/build backend/dist backend/.spec

# Rebuild everything
flutter build apk --release
cd backend && python build_tixati_scraper.py
```

## Key Changes Made

1. ✓ Removed all qBittorrent library imports and references
2. ✓ Replaced qBittorrent API calls with Tixati HTML scraping (requests + BeautifulSoup)
3. ✓ Updated auto-manage endpoint to work with Tixati
4. ✓ Fixed transfer_details endpoint to proxy Tixati pages
5. ✓ Updated API client to point to backend (localhost:5050) instead of Tixati (localhost:8888)
6. ✓ Updated API client to use `/api/downloads` JSON endpoint instead of HTML scraping
7. ✓ Fixed remove download to send torrent name instead of hash
8. ✓ Created standalone PyInstaller executable (no dependencies required)
9. ✓ Updated all documentation and error messages
10. ✓ Rebuilt APK with updated API endpoints

## Backend Requirements on Deployment Machine

- Windows 7+ (or Windows 11)
- Tixati running on localhost:8888
- **Nothing else** - Python, dependencies, etc. are bundled in the .exe

## Notes

- Tailscale provides network access; use its IP for the backend URL in the app
- Both backend executables are identical; choose based on preference
- The backend scrapes Tixati's HTML; any UI changes to Tixati may require parser updates
- All file operations (add, remove, start, stop) are proxied through the backend to Tixati
