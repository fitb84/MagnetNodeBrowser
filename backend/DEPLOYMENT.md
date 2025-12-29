# Tixati Node Browser Backend - Single-Click Deployment

## What You Have

A **standalone Windows executable** (`TixatiNodeBrowserBackend.exe`) that runs the entire Flask backend with zero dependencies.

- **File:** `TixatiNodeBrowserBackend.exe`
- **Size:** ~16 MB
- **Requirements:** Windows 7+, Tixati WebUI running on localhost:8888

## How to Deploy

### On the Backend Machine:

1. **Copy the executable** to any folder on the backend machine (e.g., `C:\TixatiNode\` or your Desktop).
2. **Double-click** `TixatiNodeBrowserBackend.exe` to start the backend server.
3. A console window will appear showing:
   ```
   MagnetNode Dashboard running at http://localhost:5050
   ```

### Configuration

The backend connects to Tixati on `localhost:8888` by default.

To change this, edit `TIXATI_HOST` and `TIXATI_PORT` in the source code and rebuild the executable.

## Testing the Backend

Open a browser on the backend machine and visit:
- `http://localhost:5050/api/downloads` - View active torrents

If you see JSON output, the backend is working correctly.

## Using with the Flutter App

1. Configure the app's backend URL in `lib/services/api_client.dart`:
   ```dart
   static const String baseUrl = 'http://YOUR_TAILSCALE_IP:5050';
   ```
   Replace `YOUR_TAILSCALE_IP` with the Tailscale IP of the backend machine.

2. Run the Flutter app on your mobile device.

3. The app will connect to the backend and display active torrents from Tixati.

## Troubleshooting

- **"Connection refused"** - Ensure the backend exe is running on the backend machine.
- **"Tixati error"** - Ensure Tixati is running and its WebUI is accessible on localhost:8888.
- **No torrents showing** - Check that Tixati has active transfers.

## Rebuilding the Executable

If you modify the backend code, rebuild the executable:

```bash
cd backend
python build_exe.py
```

The new executable will be created at `backend/dist/TixatiNodeBrowserBackend.exe`.

## What's Inside

The executable includes:
- Python 3.14.2 runtime
- Flask web framework
- BeautifulSoup4 HTML parser
- Requests library
- All required dependencies bundled into a single file

No Python installation or pip required on the deployment machine.
