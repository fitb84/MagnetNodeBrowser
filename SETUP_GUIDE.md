# MagnetNode Flutter Mobile App - Setup Guide

## Quick Start

Your complete native Flutter app is ready at `C:\magnetnode_mobile`

### What's Included

✅ **4 Complete Screens**
- Dashboard: Real-time drive monitoring
- Downloads: Torrent management with full metrics
- Ingest: Batch magnet link ingestion
- Settings: Library configuration

✅ **Full Backend Integration**
- API client connecting to `100.120.201.83:5050` via Tailscale
- All endpoints implemented (stats, downloads, TV folders, library management)
- Error handling and loading states

✅ **Native Material Design**
- Dark theme matching web version
- Touch-optimized UI
- Bottom navigation between screens
- Pull-to-refresh on all tabs

## Installation Steps

### Step 1: Install Flutter (Windows)

1. Download Flutter: https://flutter.dev/docs/get-started/install/windows
2. Extract to a permanent location (e.g., `C:\flutter`)
3. Add to PATH:
   - Open Environment Variables
   - Add `C:\flutter\bin` to PATH
4. Verify installation:
   ```bash
   flutter doctor
   ```

### Step 2: Install Android Requirements

```bash
# Accept Android licenses
flutter doctor --android-licenses
```

This sets up:
- Android SDK
- Android emulator
- Build tools

### Step 3: Prepare Your Phone

**Enable USB Debugging (Android)**
1. Go to Settings → About Phone
2. Tap "Build number" 7 times to unlock Developer Options
3. Go to Settings → Developer Options
4. Enable "USB Debugging"
5. Connect phone to PC via USB cable
6. Tap "Allow" when prompted on phone

**Alternative: WiFi Debugging (No Cable)**
1. Connect phone to same WiFi as PC
2. In Developer Options, find "Wireless debugging"
3. Enable it
4. Note the IP address shown

### Step 4: Build and Run

```bash
# Navigate to project
cd C:\magnetnode_mobile

# Get dependencies
flutter pub get

# List connected devices
flutter devices

# Run app on device
flutter run

# Build APK for manual installation
flutter build apk --release
```

### Step 5: Manual Installation (No Cable)

If you don't have a USB cable or prefer manual installation:

```bash
# Build release APK (creates ~50MB file)
flutter build apk --release

# APK location: C:\magnetnode_mobile\build\app\outputs\flutter-apk\app-release.apk

# Transfer to phone via:
# - Email, Google Drive, OneDrive
# - File sharing app
# - ADB over WiFi
```

Then on phone:
1. Open file manager
2. Navigate to Downloads (where you saved APK)
3. Tap the APK file
4. Tap "Install"
5. Grant permissions if prompted
6. Launch the app

## Connecting to Backend

The app automatically connects to `100.120.201.83:5050` via Tailscale.

**Verify connection works:**
1. Launch MagnetNode app
2. Go to Dashboard tab
3. You should see your drive information

If you get connection errors:
- ✓ Ensure Tailscale is running on both desktop and phone
- ✓ Verify backend is running: `python run_local_app.py` on desktop
- ✓ Test in browser: Open `http://100.120.201.83:5050` on phone

## Using the App

### Dashboard Tab
- See real-time drive space usage
- Visual progress bars for each drive
- Used/Free/Total space in GB
- Color indicators: Green (safe), Orange (warning), Red (full)
- Pull down to refresh

### Downloads Tab
- Lists all active torrents
- Shows: Name, Progress %, Speed (↓/↑), Ratio, Seeds/Leeches
- Download location path
- Tap delete icon to remove downloads
- Automatically refreshes every 2 seconds in background

### Ingest Tab
- Paste magnet links
- Select category: Movie or TV Show
- For TV Shows, select or type series name
- Suggested series folders appear as you type
- "Add to Batch" queues magnets
- See batch count and items queued
- "Submit Batch" sends all at once
- Batch clears after successful submission

### Settings Tab
- View all configured libraries
- See space stats for each library
- Delete library paths with confirmation
- Shows separate sections for Movies and Shows

## Building for Distribution

### Generate Signed APK

```bash
# Create keystore (one-time, keeps credentials safe)
keytool -genkey -v -keystore C:\magnetnode_mobile\key.jks ^
  -keyalg RSA -keysize 2048 -validity 10000 -alias magnetnode

# Build signed release APK
flutter build apk --release

# Result: C:\magnetnode_mobile\build\app\outputs\flutter-apk\app-release.apk
```

### Share APK with Friends

The release APK (~50MB) can be shared via:
- Google Drive
- OneDrive
- Email (if < 25MB)
- Telegram/WhatsApp
- Direct file transfer

## Project Structure

```
magnetnode_mobile/
├── lib/
│   ├── main.dart                      # App entry, tab navigation
│   ├── theme/
│   │   └── app_theme.dart            # Dark theme, colors, styling
│   ├── services/
│   │   └── api_client.dart           # REST API client (all endpoints)
│   └── screens/
│       ├── dashboard_screen.dart      # Drive monitoring
│       ├── downloads_screen.dart      # Torrent management
│       ├── ingest_screen.dart        # Batch magnet ingestion
│       └── settings_screen.dart      # Library configuration
├── android/                           # Android native configuration
├── pubspec.yaml                       # Dependencies (http, provider)
└── README.md
```

## Customization

### Change Backend URL

Edit `lib/services/api_client.dart` line 4:

```dart
static const String baseUrl = 'http://YOUR_TAILSCALE_IP:5050';
```

### Change App Name

Edit `android/app/build.gradle`:

```gradle
android {
    defaultConfig {
        applicationId = "com.example.magnetnode"
    }
}
```

### Change App Icon

Replace `android/app/src/main/res/mipmap-*/ic_launcher.png` with your images

## Troubleshooting

### Flutter Not Found
```bash
# Add Flutter to PATH manually
set PATH=%PATH%;C:\flutter\bin
flutter --version
```

### Device Not Detected
```bash
# Check connected devices
flutter devices

# If empty, try:
# 1. Check USB cable and connection
# 2. Verify USB Debugging is enabled
# 3. Run: adb kill-server && adb start-server
```

### Connection to Backend Fails
```bash
# Test connection in phone browser
http://100.120.201.83:5050

# Check if Tailscale is running on both devices
# Check if backend is running:
python run_local_app.py

# Check firewall on desktop (port 5050)
```

### Build Errors
```bash
flutter clean
flutter pub get
flutter run
```

### Android SDK Not Found
```bash
flutter doctor --android-licenses
```

## Development

For ongoing development:

```bash
# Hot reload (updates code instantly)
flutter run

# Then press 'r' in terminal to reload after changes
```

## GitHub Repository

This Flutter mobile project can be pushed to GitHub:

```bash
cd C:\magnetnode_mobile
git remote add origin https://github.com/fitb84/MagnetNode-Mobile.git
git branch -M main
git push -u origin main
```

## Next Steps

1. **Install Flutter SDK** following Step 1 above
2. **Enable USB Debugging** on your Samsung phone
3. **Run `flutter pub get`** to download dependencies
4. **Connect phone and run `flutter run`**
5. **Test the app** - Dashboard should show drive info immediately
6. **Build release APK** with `flutter build apk --release` for permanent installation

## Support

- Flutter docs: https://flutter.dev/docs
- Dart/Flutter issues: https://github.com/flutter/flutter/issues
- MagnetNode backend: https://github.com/fitb84/MagnetNode

---

**Questions?** Refer to the README.md in the project or test the web version at `http://100.120.201.83:5050` in your browser first to verify backend connectivity.
