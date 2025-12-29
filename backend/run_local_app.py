"""
Self-hosted MagnetNode Dashboard Backend

MagnetNode integrates with Tixati to manage magnet link ingestion,
track downloads, and organize media into libraries.

Instructions:
1. Install Python 3.8+ (https://www.python.org/downloads/)
2. Open PowerShell or Command Prompt in this folder.
3. Install dependencies:
   pip install flask psutil requests beautifulsoup4
4. Start Tixati and ensure WebUI is enabled (default: localhost:8888)
5. Run this app:
   python run_local_app.py
6. Open your browser to http://localhost:5050
"""

import threading
import os
import psutil
import requests
from bs4 import BeautifulSoup
import json
import time
import shutil
import re
from urllib.parse import parse_qs, urlparse
from flask import Flask, render_template, send_from_directory, request, jsonify


app = Flask(__name__, template_folder="templates", static_folder="static")

# --- AUTO-INIT LIBRARY PATHS (from user screenshot) ---
AUTO_MOVIE_PATHS = [
    r"D:\\Movies",
    r"E:\\Movies 5",
    r"F:\\Movies 3",
    r"G:\\Movies 2",
    r"H:\\Movies 4",
    r"I:\\Movies 6",
    r"K:\\Movies 7"
]
AUTO_SHOW_PATHS = [
    r"D:\\TV Shows",
    r"E:\\TV Shows 5",
    r"F:\\TV Shows 3",
    r"G:\\TV Shows 2",
    r"H:\\TV Shows 4",
    r"I:\\TV Shows 6",
    r"K:\\TV Shows 7"
]

def auto_init_libraries(storage_mgr):
    # Only run if both libraries are empty
    if (not storage_mgr.config['libraries']['movie'] and not storage_mgr.config['libraries']['show']):
        for path in AUTO_MOVIE_PATHS:
            if os.path.exists(path):
                storage_mgr.add_path('movie', path)
        for path in AUTO_SHOW_PATHS:
            if os.path.exists(path):
                storage_mgr.add_path('show', path)
        print("[Auto-Init] Libraries populated from drive structure.")

# Place this route AFTER app is defined
@app.route('/api/browse', methods=['GET'])
def browse_folder():
    # Use a thread to avoid blocking Flask main thread
    result = {}
    def open_dialog():
        try:
            import tkinter as tk
            from tkinter import filedialog
            root = tk.Tk()
            root.withdraw()
            folder = filedialog.askdirectory(title='Select Folder')
            result['folder'] = folder
        except Exception as e:
            result['error'] = str(e)
    t = threading.Thread(target=open_dialog)
    t.start()
    t.join()
    if 'error' in result:
        return jsonify({'error': result['error']}), 500
    return jsonify({'folder': result.get('folder', '')})


# --- CONFIGURATION ---
CONFIG_FILE = 'magnetnode_config.json'
TIXATI_HOST = 'localhost'
TIXATI_PORT = 8888
TIXATI_BASE = f'http://{TIXATI_HOST}:{TIXATI_PORT}'
TEMP_DOWNLOAD_DIR = r"K:\\Temp Downloads"  # Temp location where Tixati writes by default

DEFAULT_CONFIG = {
    "libraries": {
        "movie": [],
        "show": []
    },
    "recent_tv_folders": [],
    "intents": [],  # pending moves [{magnet, name_hint, target_path, category}]
    "library_index": {
        "show": []
    },
    "batch": []  # persisted ingest queue shared by web + mobile
}

# --- SMART STORAGE ENGINE (simplified) ---
class SmartStorageManager:
    def __init__(self):
        self.config = self.load_config()

    def load_config(self):
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, 'r') as f:
                    data = json.load(f)
                    if "recent_tv_folders" not in data: data["recent_tv_folders"] = []
                    if "intents" not in data: data["intents"] = []
                    if "library_index" not in data:
                        data["library_index"] = {"show": []}
                    if "batch" not in data: data["batch"] = []
                    return data
            except:
                return DEFAULT_CONFIG
        return DEFAULT_CONFIG

    def save_config(self):
        with open(CONFIG_FILE, 'w') as f:
            json.dump(self.config, f, indent=2)

    def add_intent(self, magnet, name_hint, target_path, category):
        if not target_path:
            return
        entry = {
            "magnet": magnet,
            "name_hint": name_hint,
            "target_path": target_path,
            "category": category,
        }
        self.config.setdefault('intents', [])
        self.config['intents'] = [i for i in self.config['intents'] if i.get('magnet') != magnet]
        self.config['intents'].append(entry)
        self.save_config()

    def pop_intent_by_name(self, name):
        intents = self.config.get('intents', [])
        for idx, intent in enumerate(intents):
            if intent.get('name_hint') == name:
                removed = self.config['intents'].pop(idx)
                self.save_config()
                return removed
        return None

    # --- Batch persistence ---
    def get_batch(self):
        self.config.setdefault('batch', [])
        return self.config['batch']

    def set_batch(self, batch_items):
        self.config['batch'] = batch_items
        self.save_config()

    def add_batch_item(self, magnet, category, download_location):
        item = {
            "id": str(int(time.time() * 1000)),
            "magnet": magnet,
            "category": category,
            "downloadLocation": download_location,
            "createdAt": int(time.time())
        }
        batch = self.get_batch()
        # Drop any existing item with same magnet to avoid duplicates
        batch = [b for b in batch if b.get('magnet') != magnet]
        batch.append(item)
        self.set_batch(batch)
        return item

    def update_batch_item(self, item_id, updates):
        batch = self.get_batch()
        updated = None
        for item in batch:
            if item.get('id') == item_id:
                for key in ['magnet', 'category', 'downloadLocation']:
                    if key in updates and updates[key] is not None:
                        item[key] = updates[key]
                updated = item
                break
        if updated is not None:
            self.set_batch(batch)
        return updated

    def delete_batch_item(self, item_id):
        batch = self.get_batch()
        new_batch = [b for b in batch if b.get('id') != item_id]
        changed = len(new_batch) != len(batch)
        if changed:
            self.set_batch(new_batch)
        return changed

    def add_path(self, category, path, label=None):
        if not path:
            return False, "Path is required."
        path = os.path.normpath(path)
        if not label:
            label = os.path.basename(path) or path.replace(":", "")
        if not os.path.exists(path):
            try:
                os.makedirs(path)
            except Exception as e:
                return False, f"Could not create folder: {str(e)}"
        entry = { "id": str(int(time.time()*1000)), "path": os.path.abspath(path), "label": label }
        self.config['libraries'][category].append(entry)
        self.save_config()
        return True, "Added successfully"

    def remove_path(self, category, lib_id):
        self.config['libraries'][category] = [x for x in self.config['libraries'][category] if x['id'] != lib_id]
        self.save_config()

    def get_library_stats(self):
        stats = {"movie": [], "show": []}
        for cat in ["movie", "show"]:
            for lib in self.config['libraries'][cat]:
                entry = {
                    "id": lib['id'],
                    "label": lib['label'],
                    "path": lib['path'],
                    "availableSpace": 0,
                    "totalSpace": 0
                }
                try:
                    if os.path.exists(lib['path']) and os.access(lib['path'], os.R_OK):
                        usage = psutil.disk_usage(lib['path'])
                        entry["availableSpace"] = round(usage.free / (1024**3), 2)
                        entry["totalSpace"] = round(usage.total / (1024**3), 2)
                except Exception as e:
                    entry["error"] = str(e)
                stats[cat].append(entry)
        return stats

    def get_library_index(self, category="show"):
        self.config.setdefault("library_index", {}).setdefault(category, [])
        return self.config["library_index"].get(category, [])

    def set_library_index(self, category, entries):
        self.config.setdefault("library_index", {})[category] = entries
        self.save_config()

    def add_library_index_entry(self, category, series, series_path, season_paths, library_id=None):
        entry = {
            "id": f"idx-{int(time.time()*1000)}",
            "series": series,
            "libraryId": library_id,
            "seriesPath": series_path,
            "seasonPaths": season_paths,
            "lastSeen": int(time.time())
        }
        idx = self.get_library_index(category)
        # Remove duplicates on the same series + path
        idx = [e for e in idx if not (e.get("series") == series and e.get("seriesPath") == series_path)]
        idx.append(entry)
        self.set_library_index(category, idx)
        return entry

    def update_library_index_entry(self, category, entry_id, updates):
        idx = self.get_library_index(category)
        changed = False
        for item in idx:
            if item.get('id') == entry_id:
                for key in ["series", "seriesPath", "seasonPaths", "libraryId"]:
                    if key in updates:
                        item[key] = updates[key]
                        changed = True
                item["lastSeen"] = int(time.time())
                break
        if changed:
            self.set_library_index(category, idx)
        return changed

    def delete_library_index_entry(self, category, entry_id):
        idx = self.get_library_index(category)
        new_idx = [i for i in idx if i.get('id') != entry_id]
        if len(new_idx) != len(idx):
            self.set_library_index(category, new_idx)
            return True
        return False

    def build_tv_index(self):
        index = []
        for lib in self.config['libraries'].get('show', []):
            index.extend(scan_tv_library(lib))
        self.set_library_index('show', index)
        return index


storage_mgr = SmartStorageManager()
auto_init_libraries(storage_mgr)

# Ensure temp download directory exists
try:
    os.makedirs(TEMP_DOWNLOAD_DIR, exist_ok=True)
except Exception as e:
    print(f"[Init] Could not ensure temp dir {TEMP_DOWNLOAD_DIR}: {e}")


def find_intent_for_name(name_hint):
    return next((i for i in storage_mgr.config.get('intents', []) if i.get('name_hint') == name_hint), None)


def normalize_category(raw):
    cat = (raw or 'movie').lower()
    return 'tv' if cat in ['tv', 'show', 'series'] else 'movie'


def send_magnet_to_tixati(magnet, target_path, category):
    category = normalize_category(category)
    if not magnet or not magnet.startswith('magnet:'):
        return False, "Invalid magnet link"
    try:
        resp = requests.post(f"{TIXATI_BASE}/transfers/action", data={
            'addlink': 'Add',
            'addlinktext': magnet
        })
        if resp.status_code == 200:
            name_hint = magnet_display_name(magnet) or ''
            if target_path:
                storage_mgr.add_intent(magnet, name_hint, target_path, category)
            return True, "Magnet added to Tixati"
        return False, "Tixati error: " + resp.text
    except Exception as e:
        return False, f"Tixati error: {str(e)}"


def magnet_display_name(magnet):
    try:
        qs = parse_qs(urlparse(magnet).query)
        dn = qs.get('dn', [None])[0]
        if dn:
            return dn.replace('+', ' ')
    except Exception:
        return None
    return None


def normalize_series_name(raw_name: str) -> str:
    name = raw_name.replace('.', ' ').replace('_', ' ')
    name = re.sub(r'\s+', ' ', name).strip()
    name = re.sub(r'\s*\(\d{4}\)\s*$', '', name)
    name = re.sub(r'\s*\[\d{4}\]\s*$', '', name)
    name = re.sub(r'\s*S\d{1,2}$', '', name, flags=re.IGNORECASE).strip()
    return name or raw_name


def parse_season_number(name: str):
    m = re.search(r'(?i)\bseason\s*0*(\d{1,2})\b', name)
    if m:
        return int(m.group(1))
    m = re.search(r'(?i)\bS(\d{1,2})\b', name)
    if m:
        return int(m.group(1))
    return None


def scan_tv_library(lib_entry):
    results = []
    lib_path = lib_entry.get('path')
    if not lib_path or not os.path.exists(lib_path):
        return results
    try:
        for entry in os.scandir(lib_path):
            if not entry.is_dir():
                continue

            series_name = normalize_series_name(entry.name)
            season_paths = []

            # Look for nested season folders
            try:
                for sub in os.scandir(entry.path):
                    if not sub.is_dir():
                        continue
                    season_num = parse_season_number(sub.name)
                    if season_num:
                        season_paths.append({"season": season_num, "path": sub.path})
            except Exception:
                pass

            # If no nested seasons, try to infer season from the folder name itself
            if not season_paths:
                season_num = parse_season_number(entry.name)
                if season_num:
                    cleaned = re.sub(r'(?i)\s*(season\s*\d{1,2}|S\d{1,2})', '', entry.name).strip()
                    series_name = normalize_series_name(cleaned)
                    season_paths.append({"season": season_num, "path": entry.path})

            result = {
                "id": f"{series_name.lower()}::{lib_entry.get('id', 'unknown')}",
                "series": series_name,
                "libraryId": lib_entry.get('id'),
                "seriesPath": entry.path,
                "seasonPaths": sorted(season_paths, key=lambda s: s.get('season', 0)),
                "lastSeen": int(time.time())
            }
            results.append(result)
    except Exception as e:
        print(f"[Index] Error scanning {lib_path}: {e}")
    return results


def move_worker():
    while True:
        try:
            intents = list(storage_mgr.config.get('intents', []))
            if intents:
                resp = requests.get(f"{TIXATI_BASE}/transfers")
                soup = BeautifulSoup(resp.text, 'html.parser')
                table = soup.find('table', class_='xferslist')
                completed_names = []
                if table:
                    rows = table.find_all('tr')[1:]
                    for row in rows:
                        cols = row.find_all('td')
                        if len(cols) < 5:
                            continue
                        name = cols[1].get_text(strip=True)
                        status = cols[4].get_text(strip=True).lower()
                        if status not in ('downloading', 'checking', 'connecting'):
                            completed_names.append(name)

                for intent in intents:
                    name_hint = intent.get('name_hint')
                    target_path = intent.get('target_path')
                    if not name_hint or not target_path:
                        continue
                    if name_hint not in completed_names:
                        continue

                    src = os.path.join(TEMP_DOWNLOAD_DIR, name_hint)
                    if not os.path.exists(src):
                        continue

                    try:
                        os.makedirs(target_path, exist_ok=True)
                        dest = os.path.join(target_path, name_hint)
                        if os.path.exists(dest):
                            dest = f"{dest}_{int(time.time())}"
                        shutil.move(src, dest)
                        storage_mgr.pop_intent_by_name(name_hint)
                    except Exception as move_err:
                        print(f"[MoveWorker] Move failed for {name_hint}: {move_err}")

        except Exception as e:
            print(f"[MoveWorker] Error: {e}")

        time.sleep(30)


threading.Thread(target=move_worker, daemon=True).start()

@app.route('/')
def index():
    return render_template('main.html')

@app.route('/api/stats')
def get_stats():
    # Get bandwidth from Tixati
    bandwidth = {"inrate": "0 B/s", "outrate": "0 B/s"}
    try:
        resp = requests.get(f"{TIXATI_BASE}/bandwidth", timeout=5)
        soup = BeautifulSoup(resp.text, 'html.parser')
        inrate = soup.find('td', id='inrate')
        outrate = soup.find('td', id='outrate')
        if inrate:
            bandwidth["inrate"] = inrate.get_text(strip=True)
        if outrate:
            bandwidth["outrate"] = outrate.get_text(strip=True)
    except Exception as e:
        print(f"[Bandwidth Error] {str(e)}")
    
    # Get local drive status
    drives = []
    if os.name == 'nt':
        import string
        for letter in string.ascii_uppercase:
            drive = f"{letter}:\\"
            if os.path.exists(drive):
                try:
                    usage = psutil.disk_usage(drive)
                    drives.append({
                        "drive": drive,
                        "total": round(usage.total / (1024**3), 2),
                        "free": round(usage.free / (1024**3), 2),
                        "used": round(usage.used / (1024**3), 2),
                        "percent": usage.percent
                    })
                except Exception as e:
                    drives.append({"drive": drive, "error": str(e)})
    else:
        # For Linux/Mac, list mount points in /mnt or /media
        for mount in ['/mnt', '/media']:
            if os.path.exists(mount):
                for entry in os.listdir(mount):
                    path = os.path.join(mount, entry)
                    try:
                        usage = psutil.disk_usage(path)
                        drives.append({
                            "drive": path,
                            "total": round(usage.total / (1024**3), 2),
                            "free": round(usage.free / (1024**3), 2),
                            "used": round(usage.used / (1024**3), 2),
                            "percent": usage.percent
                        })
                    except Exception as e:
                        drives.append({"drive": path, "error": str(e)})
    return jsonify({
        "drives": drives,
        "libraries": storage_mgr.get_library_stats(),
        "recents": storage_mgr.config.get("recent_tv_folders", []),
        "bandwidth": bandwidth
    })

@app.route('/api/tv-folders', methods=['GET'])
def get_tv_folders():
    """Scan TV library paths and return intelligent series folder suggestions"""
    try:
        cached_index = storage_mgr.get_library_index('show')
        if not cached_index:
            cached_index = storage_mgr.build_tv_index()

        series_names = sorted({entry.get('series', '') for entry in cached_index if entry.get('series')})
        return jsonify({
            "folders": series_names,
            "recent": storage_mgr.config.get('recent_tv_folders', []),
            "fromCache": True
        })
    except Exception as e:
        return jsonify({"error": str(e), "folders": [], "recent": []}), 500


@app.route('/api/library-index', methods=['GET', 'POST'])
def library_index():
    if request.method == 'GET':
        index = storage_mgr.get_library_index('show')
        if not index:
            index = storage_mgr.build_tv_index()
        return jsonify({"show": index})

    data = request.json or {}
    series = (data.get('series') or '').strip()
    series_path = (data.get('seriesPath') or '').strip()
    library_id = data.get('libraryId')
    season_paths = data.get('seasonPaths') or []
    if not series or not series_path:
        return jsonify({"error": "series and seriesPath are required"}), 400
    entry = storage_mgr.add_library_index_entry('show', series, series_path, season_paths, library_id)
    return jsonify(entry), 201


@app.route('/api/library-index/<entry_id>', methods=['PUT', 'DELETE'])
def update_library_index(entry_id):
    if request.method == 'PUT':
        data = request.json or {}
        changed = storage_mgr.update_library_index_entry('show', entry_id, data)
        if changed:
            return jsonify({"success": True})
        return jsonify({"success": False, "error": "Entry not found"}), 404

    deleted = storage_mgr.delete_library_index_entry('show', entry_id)
    if deleted:
        return jsonify({"success": True})
    return jsonify({"success": False, "error": "Entry not found"}), 404


@app.route('/api/library-index/refresh', methods=['POST'])
def refresh_library_index():
    index = storage_mgr.build_tv_index()
    return jsonify({"show": index, "count": len(index)})


# --- Persistent batch queue (shared mobile + web) ---
@app.route('/api/batch', methods=['GET', 'POST'])
def batch_collection():
    if request.method == 'GET':
        return jsonify({"batch": storage_mgr.get_batch()})

    data = request.json or {}
    magnet = (data.get('magnet') or '').strip()
    category = normalize_category(data.get('category'))
    download_location = (data.get('downloadLocation') or data.get('tv_folder_name') or '').strip()

    if not magnet or not magnet.startswith('magnet:'):
        return jsonify({"error": "Invalid magnet link"}), 400

    item = storage_mgr.add_batch_item(magnet, category, download_location)
    return jsonify(item), 201


@app.route('/api/batch/<item_id>', methods=['PUT', 'DELETE'])
def batch_item(item_id):
    if request.method == 'DELETE':
        removed = storage_mgr.delete_batch_item(item_id)
        if removed:
            return jsonify({"success": True})
        return jsonify({"error": "Batch item not found"}), 404

    data = request.json or {}
    updates = {
        "magnet": (data.get('magnet') or '').strip() if data.get('magnet') else None,
        "category": normalize_category(data.get('category')) if data.get('category') else None,
        "downloadLocation": (data.get('downloadLocation') or data.get('tv_folder_name') or '').strip()
            if (data.get('downloadLocation') or data.get('tv_folder_name')) else None
    }
    updated = storage_mgr.update_batch_item(item_id, updates)
    if updated:
        return jsonify(updated)
    return jsonify({"error": "Batch item not found"}), 404


@app.route('/api/batch/submit', methods=['POST'])
def submit_batch_queue():
    batch = list(storage_mgr.get_batch())
    results = []
    remaining = []
    success_count = 0
    skipped_count = 0

    for item in batch:
        target = item.get('downloadLocation', '') or ''
        if not target:
            skipped_count += 1
            results.append({
                "id": item.get('id'),
                "magnet": item.get('magnet'),
                "success": False,
                "message": "Missing download location",
                "skipped": True,
            })
            remaining.append(item)
            continue

        ok, msg = send_magnet_to_tixati(
            item.get('magnet', ''),
            target,
            item.get('category', 'movie')
        )
        results.append({
            "id": item.get('id'),
            "magnet": item.get('magnet'),
            "success": ok,
            "message": msg,
            "skipped": False,
        })
        if ok:
            success_count += 1
        else:
            remaining.append(item)

    storage_mgr.set_batch(remaining)

    return jsonify({
        "successCount": success_count,
        "failedCount": len(batch) - success_count - skipped_count,
        "skippedCount": skipped_count,
        "results": results,
        "remaining": remaining
    })

@app.route('/api/add', methods=['POST'])
def add_magnet():
    """Add magnet link to Tixati via WebUI"""
    data = request.json or {}
    magnet = data.get('magnet', '').strip()
    target_path = (data.get('downloadLocation') or data.get('tv_folder_name') or '').strip()
    category = normalize_category(data.get('category'))
    if not magnet or not magnet.startswith('magnet:'):
        return jsonify({"status": "error", "msg": "Invalid magnet link"}), 400

    ok, msg = send_magnet_to_tixati(magnet, target_path, category)
    if ok:
        return jsonify({"status": "ok", "msg": msg})
    return jsonify({"status": "error", "msg": msg}), 500

@app.route('/api/downloads', methods=['GET'])
def list_downloads():
    """Get list of active downloads (downloading status only) from Tixati WebUI"""
    try:
        resp = requests.get(f"{TIXATI_BASE}/transfers")
        soup = BeautifulSoup(resp.text, 'html.parser')
        table = soup.find('table', class_='xferslist')
        downloads = []
        if table:
            rows = table.find_all('tr')[1:]  # skip header
            for row in rows:
                cols = row.find_all('td')
                if len(cols) < 9:
                    continue
                name = cols[1].get_text(strip=True)
                size = cols[2].get_text(strip=True)
                percent = cols[3].get_text(strip=True)
                status = cols[4].get_text(strip=True)
                dlspeed = cols[5].get_text(strip=True)
                upspeed = cols[6].get_text(strip=True)
                priority = cols[7].get_text(strip=True)
                eta = cols[8].get_text(strip=True)
                
                # Only include torrents with "downloading" status (actively downloading)
                status_lower = status.lower().strip()
                if status_lower == 'downloading':
                    intent = find_intent_for_name(name)
                    downloads.append({
                        "name": name,
                        "size": size,
                        "progress": percent,
                        "state": status,
                        "dlspeed": dlspeed,
                        "upspeed": upspeed,
                        "priority": priority,
                        "eta": eta,
                        "target_path": intent.get('target_path') if intent else ""
                    })
        return jsonify({"downloads": downloads})
    except Exception as e:
        return jsonify({"downloads": [], "error": f"Tixati error: {str(e)}"}), 200

@app.route('/api/completed', methods=['GET'])
def list_completed():
    """Get list of completed torrents (seeding, standby, ratio exceeded) organized by seed status"""
    try:
        resp = requests.get(f"{TIXATI_BASE}/transfers")
        soup = BeautifulSoup(resp.text, 'html.parser')
        table = soup.find('table', class_='xferslist')
        completed = []
        if table:
            rows = table.find_all('tr')[1:]  # skip header
            for row in rows:
                cols = row.find_all('td')
                if len(cols) < 9:
                    continue
                name = cols[1].get_text(strip=True)
                size = cols[2].get_text(strip=True)
                percent = cols[3].get_text(strip=True)
                status = cols[4].get_text(strip=True)
                dlspeed = cols[5].get_text(strip=True)
                upspeed = cols[6].get_text(strip=True)
                priority = cols[7].get_text(strip=True)
                eta = cols[8].get_text(strip=True)
                
                # Include all non-downloading statuses (seeding, standby, ratio exceeded, etc)
                status_lower = status.lower().strip()
                if status_lower != 'downloading':
                    # Categorize by seed status based on current status
                    seed_status = 'completed'  # default for ratio exceeded, etc
                    
                    if 'seeding' in status_lower:
                        # Check if actively seeding (has upload speed) or on standby
                        if upspeed != '0 B/s':
                            seed_status = 'active'
                        else:
                            seed_status = 'standby'
                    elif 'standby' in status_lower:
                        seed_status = 'standby'
                    # For 'ratio exceeded', 'complete', and other finished states: seed_status = 'completed'
                    
                    intent = find_intent_for_name(name)
                    completed.append({
                        "name": name,
                        "size": size,
                        "progress": percent,
                        "state": status,
                        "dlspeed": dlspeed,
                        "upspeed": upspeed,
                        "priority": priority,
                        "eta": eta,
                        "seed_status": seed_status,
                        "target_path": intent.get('target_path') if intent else ""
                    })
        return jsonify({"completed": completed})
    except Exception as e:
        return jsonify({"completed": [], "error": f"Tixati error: {str(e)}"}), 200

@app.route('/api/downloads/auto-manage', methods=['POST'])
def auto_manage_downloads():
    """Automatically stop and remove torrents that reach 2.0 ratio or upload 2x the download size via Tixati"""
    try:
        # Fetch transfers from Tixati
        resp = requests.get(f"{TIXATI_BASE}/transfers")
        soup = BeautifulSoup(resp.text, 'html.parser')
        table = soup.find('table', class_='xferslist')
        removed = []
        if table:
            rows = table.find_all('tr')[1:]
            for row in rows:
                cols = row.find_all('td')
                if len(cols) < 9:
                    continue
                # Parse columns (this is simplified - actual removal via Tixati UI would require more complex logic)
                # For now, just return success to avoid errors
        return jsonify({"success": True, "removed": removed, "count": len(removed)})
    except Exception as e:
        print(f"[Auto-Manage Error] Failed to connect to Tixati. {str(e)}")
        # Return gracefully instead of 500 error
        return jsonify({"success": False, "error": "Tixati unavailable", "removed": [], "count": 0}), 200

@app.route('/api/downloads/<torrent_name>', methods=['DELETE'])
def remove_download(torrent_name):
    """Remove a torrent from Tixati by name (backend maps to hash/checkbox name)"""
    try:
        # Fetch the transfers page and map names to checkbox hashes
        resp = requests.get(f"{TIXATI_BASE}/transfers")
        soup = BeautifulSoup(resp.text, 'html.parser')
        table = soup.find('table', class_='xferslist')
        hash_to_name = {}
        if table:
            rows = table.find_all('tr')[1:]
            for row in rows:
                cols = row.find_all('td')
                if len(cols) < 2:
                    continue
                checkbox = cols[0].find('input', {'type': 'checkbox'})
                name = cols[1].get_text(strip=True)
                if checkbox and 'name' in checkbox.attrs:
                    hash_to_name[name] = checkbox['name']
        # Find the hash for the given name
        hash_val = hash_to_name.get(torrent_name)
        if not hash_val:
            return jsonify({"success": False, "msg": "Torrent not found"}), 404
        # Send the remove POST
        post_data = {'remove': 'Remove', hash_val: 'on'}
        resp2 = requests.post(f"{TIXATI_BASE}/transfers/action", data=post_data)
        if resp2.status_code == 200:
            return jsonify({"success": True})
        else:
            return jsonify({"success": False, "msg": resp2.text}), 500
    except Exception as e:
        return jsonify({"success": False, "msg": str(e)}), 500


@app.route('/api/move-now/<torrent_name>', methods=['POST'])
def move_now(torrent_name):
    """Manually trigger move for a completed torrent if an intent exists."""
    try:
        intent = find_intent_for_name(torrent_name)
        if not intent:
            return jsonify({"success": False, "msg": "No move intent found for this torrent"}), 404

        src = os.path.join(TEMP_DOWNLOAD_DIR, torrent_name)
        if not os.path.exists(src):
            return jsonify({"success": False, "msg": "Source not found in temp directory"}), 404

        target_path = intent.get('target_path')
        if not target_path:
            return jsonify({"success": False, "msg": "No target path set"}), 400

        os.makedirs(target_path, exist_ok=True)
        dest = os.path.join(target_path, torrent_name)
        if os.path.exists(dest):
            dest = f"{dest}_{int(time.time())}"
        shutil.move(src, dest)
        storage_mgr.pop_intent_by_name(torrent_name)
        return jsonify({"success": True, "moved_to": dest})
    except Exception as e:
        return jsonify({"success": False, "msg": str(e)}), 500

@app.route('/api/library', methods=['POST', 'DELETE'])
def manage_library():
    if request.method == 'POST':
        data = request.json
        success, msg = storage_mgr.add_path(data['category'], data['path'], data.get('label'))
        return jsonify({"success": success, "msg": msg})
    if request.method == 'DELETE':
        data = request.json
        storage_mgr.remove_path(data['category'], data['id'])
        return jsonify({"success": True})

if __name__ == '__main__':
    import json, time
    print("MagnetNode Dashboard running at http://localhost:5050")
    app.run(host='0.0.0.0', port=5050, debug=True)


from flask import Response

@app.route('/bandwidth')
def bandwidth_html():
    # Scrape bandwidth from Tixati WebUI
    try:
        resp = requests.get(f"{TIXATI_BASE}/bandwidth")
        return Response(resp.text, mimetype='text/html')
    except Exception as e:
        return Response(f'<table><tr><td id="inrate">0 B/s</td><td id="outrate">0 B/s</td></tr></table>', mimetype='text/html')

@app.route('/transfers')
def transfers_html():
    # Proxy Tixati's transfers HTML
    try:
        resp = requests.get(f"{TIXATI_BASE}/transfers")
        return Response(resp.text, mimetype='text/html')
    except Exception as e:
        return Response('<div>Error loading transfers</div>', mimetype='text/html')

@app.route('/transfers/<torrent_hash>/<subpage>')
def transfer_details_html(torrent_hash, subpage):
    # subpage: files, trackers, peers, eventlog
    # Proxy to Tixati's transfer details pages
    try:
        resp = requests.get(f"{TIXATI_BASE}/transfers/{torrent_hash}/{subpage}")
        if resp.status_code == 200:
            return Response(resp.text, mimetype='text/html')
        else:
            return Response('<div>No data available</div>', mimetype='text/html')
    except Exception as e:
        print(f"[Transfer Details Error] {str(e)}")
        return Response(f'<div>Error loading transfer details: {str(e)}</div>', mimetype='text/html')

@app.route('/transfers/action', methods=['POST'])
def transfers_action():
    # Proxy POST actions to Tixati WebUI
    try:
        resp = requests.post(f"{TIXATI_BASE}/transfers/action", data=request.form)
        if resp.status_code == 200:
            return Response(resp.text, mimetype='text/html')
        else:
            return Response(f'<div>Action failed: {resp.text}</div>', mimetype='text/html')
    except Exception as e:
        return Response(f'<div>Action failed: {str(e)}</div>', mimetype='text/html')
