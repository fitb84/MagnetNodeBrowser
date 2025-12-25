# MagnetNode Mobile

A native Flutter app for managing qBittorrent downloads and magnet ingestion on your Samsung phone, connecting via Tailscale to your desktop backend.

## Features

- **Dashboard** - Real-time drive space monitoring
- **Downloads** - View active torrents with speeds, ratios, seeds/leechers, and download location
- **Ingest** - Batch magnet link ingestion with category and TV folder organization
- **Settings** - Library management and configuration

## Prerequisites

1. **Flutter SDK** - [Install Flutter](https://flutter.dev/docs/get-started/install)
2. **Android SDK** - Included with Android Studio
3. **MagnetNode Backend** - Running on your desktop at `100.120.201.83:5050`
4. **Tailscale** - Configured on both desktop and phone for network access

## Setup Instructions

### 1. Install Flutter

```bash
# Windows
# Download from https://flutter.dev/docs/get-started/install/windows
# Extract and add to PATH

flutter doctor
```

### 2. Clone or Download Project

```bash
# Navigate to the project directory
cd C:\magnetnode_mobile
```

### 3. Get Dependencies

```bash
flutter pub get
```

### 4. Connect Your Phone

- Enable USB Debugging on your Samsung phone
- Connect via USB
- Or use WiFi debugging (advanced)

### 5. Build and Run

```bash
# List connected devices
flutter devices

# Run on device
flutter run

# Build APK for installation
flutter build apk
```

### 6. Install APK on Phone

For manual installation without USB:

```bash
# Generate release APK
flutter build apk --release

# Find APK at: build/app/outputs/flutter-apk/app-release.apk
# Transfer to phone and open with file manager to install
```

## Configuration

The app connects to your backend via Tailscale IP `100.120.201.83:5050`.

If you need to change the backend URL, edit `lib/services/api_client.dart`:

```dart
static const String baseUrl = 'http://100.120.201.83:5050';
```

## Building for Distribution

### Generate Keystore (one-time)

```bash
keytool -genkey -v -keystore ~/key.jks -keyalias magnetnode -keyalg RSA -keysize 2048 -validity 10000
```

### Build Release APK

```bash
flutter build apk --release

# Or build App Bundle for Play Store
flutter build appbundle
```

## Troubleshooting

### Connection Issues

- Ensure Tailscale is running on both desktop and phone
- Verify backend is accessible: Visit `http://100.120.201.83:5050` in phone browser
- Check firewall settings on desktop

### Flutter Issues

```bash
# Clean build cache
flutter clean

# Get fresh dependencies
flutter pub get

# Rebuild
flutter run
```

### Emulator Alternative

```bash
# List available emulators
flutter emulators

# Launch emulator
flutter emulators --launch <emulator_id>

# Run app on emulator
flutter run
```

## Architecture

- **Frontend**: Flutter (Dart) - Native Android UI
- **Backend**: Flask (Python) - Running on desktop at 100.120.201.83:5050
- **Network**: Tailscale VPN for secure remote connection
- **API**: RESTful JSON endpoints

## Project Structure

```
magnetnode_mobile/
├── lib/
│   ├── main.dart                 # App entry point
│   ├── theme/
│   │   └── app_theme.dart       # Dark theme styling
│   ├── services/
│   │   └── api_client.dart      # Backend API integration
│   └── screens/
│       ├── dashboard_screen.dart
│       ├── downloads_screen.dart
│       ├── ingest_screen.dart
│       └── settings_screen.dart
├── android/                      # Android native configuration
├── pubspec.yaml                  # Dependencies
└── README.md
```

## API Reference

The app communicates with these endpoints:

- `GET /api/stats` - Dashboard drive stats
- `GET /api/downloads` - Download list
- `POST /api/add` - Add magnet link
- `DELETE /api/downloads/<hash>` - Remove download
- `GET /api/tv-folders` - TV folder suggestions
- `GET /api/library` - Library configuration
- `POST /api/library` - Add library path
- `DELETE /api/library` - Remove library path

## Development Notes

- The app uses Material 3 design
- Dark theme by default matching desktop version
- 10-second timeout for API calls
- Auto-refresh on tab navigation

## Future Enhancements

- [ ] Push notifications for download completion
- [ ] QR code for easy Tailscale setup
- [ ] Advanced filtering and search
- [ ] Download speed graphs
- [ ] Notification settings

## License

Private project

## Support

For issues or questions, refer to the [MagnetNode GitHub repository](https://github.com/fitb84/MagnetNode)
