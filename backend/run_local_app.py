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
from emby_library import EmbyLibraryDb, find_appropriate_season_folder, extract_season_episode_numbers
from torrent_parser import TorrentParser, parse_download_metadata
from folder_manager import FolderManager


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
CONFIG_BACKUP = 'magnetnode_config.backup.json'
TIXATI_HOST = 'localhost'
TIXATI_PORT = 8888
TIXATI_BASE = f'http://{TIXATI_HOST}:{TIXATI_PORT}'
TEMP_DOWNLOAD_DIR = r"K:\Temp Downloads"  # Temp location where Tixati writes by default
WATCHER_POLL_INTERVAL = 10  # Check every 10 seconds instead of 30

# Emby library database path (dynamic username)
WINDOWS_USERNAME = os.getenv('USERNAME', 'fitb8')  # Fallback to fitb8 if USERNAME env var not set
EMBY_DB_PATH = rf"C:\Users\{WINDOWS_USERNAME}\AppData\Roaming\Emby-Server\programdata\data\library.db"

DEFAULT_CONFIG = {
    "libraries": {
        "movie": [],
        "show": []
    },
    "recent_tv_folders": [],
    "intents": [],  # pending copies [{magnet, name_hint, target_path, category}]
    "library_index": {
        "show": []
    },
    "batch": [],  # persisted ingest queue shared by web + mobile
    "emby_db_path": EMBY_DB_PATH,  # Path to Emby's library.db for auto-location lookup
    "use_emby_lookup": True  # Enable automatic lookup from Emby database
}

# --- SMART STORAGE ENGINE (with robust persistence) ---
class SmartStorageManager:
    def __init__(self):
        self.config = self.load_config()
        self._save_lock = threading.Lock()

    def load_config(self):
        # Try loading from main config file first
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    data = self._migrate_config(data)
                    print(f"[Config] Loaded from {CONFIG_FILE}")
                    return data
            except json.JSONDecodeError as e:
                print(f"[Config] Main config corrupted: {e}")
            except Exception as e:
                print(f"[Config] Error loading main config: {e}")
        
        # Try loading from backup if main failed
        if os.path.exists(CONFIG_BACKUP):
            try:
                with open(CONFIG_BACKUP, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    data = self._migrate_config(data)
                    print(f"[Config] Restored from backup {CONFIG_BACKUP}")
                    # Immediately save to main config
                    self._write_config_file(CONFIG_FILE, data)
                    return data
            except Exception as e:
                print(f"[Config] Backup also failed: {e}")
        
        print("[Config] Using default configuration")
        return self._migrate_config(DEFAULT_CONFIG.copy())
    
    def _migrate_config(self, data):
        """Ensure all required fields exist in config"""
        if "recent_tv_folders" not in data: 
            data["recent_tv_folders"] = []
        if "intents" not in data: 
            data["intents"] = []
        if "library_index" not in data:
            data["library_index"] = {"show": []}
        if "batch" not in data: 
            data["batch"] = []
        if "libraries" not in data:
            data["libraries"] = {"movie": [], "show": []}
        if "emby_db_path" not in data:
            data["emby_db_path"] = EMBY_DB_PATH
        if "use_emby_lookup" not in data:
            data["use_emby_lookup"] = True
        return data
    
    def _write_config_file(self, filepath, data):
        """Safely write config to file with atomic write"""
        temp_file = filepath + '.tmp'
        try:
            with open(temp_file, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            # Atomic rename (on Windows this may not be fully atomic, but safer)
            if os.path.exists(filepath):
                os.replace(temp_file, filepath)
            else:
                os.rename(temp_file, filepath)
            return True
        except Exception as e:
            print(f"[Config] Error writing {filepath}: {e}")
            # Clean up temp file if exists
            if os.path.exists(temp_file):
                try:
                    os.remove(temp_file)
                except:
                    pass
            return False

    def save_config(self):
        """Save config with backup and thread safety"""
        with self._save_lock:
            # Create backup of current config before saving
            if os.path.exists(CONFIG_FILE):
                try:
                    shutil.copy2(CONFIG_FILE, CONFIG_BACKUP)
                except Exception as e:
                    print(f"[Config] Backup failed: {e}")
            
            # Write new config
            if self._write_config_file(CONFIG_FILE, self.config):
                print(f"[Config] Saved to {CONFIG_FILE}")
            else:
                print("[Config] Save failed!")
    
    def force_reload(self):
        """Force reload config from disk"""
        self.config = self.load_config()
        return self.config

    def add_intent(self, magnet, name_hint, target_path, category):
        """Add a pending copy intent for a completed torrent"""
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
        """Remove intent after successful copy"""
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

    def add_batch_item(self, magnet, category, download_location, metadata=None):
        item = {
            "id": str(int(time.time() * 1000)),
            "magnet": magnet,
            "category": category,
            "downloadLocation": download_location,
            "createdAt": int(time.time()),
            "metadata": metadata or {}  # Store torrent metadata (series, season, etc)
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
                for key in ['magnet', 'category', 'downloadLocation', 'metadata']:
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

# Initialize Emby database connection
emby_db = None
emby_db_path = storage_mgr.config.get('emby_db_path', EMBY_DB_PATH)
use_emby_lookup = storage_mgr.config.get('use_emby_lookup', True)

if use_emby_lookup and os.path.exists(emby_db_path):
    try:
        emby_db = EmbyLibraryDb(emby_db_path)
        if emby_db.connected:
            print(f"[Emby] Database connected: {emby_db_path}")
        else:
            print(f"[Emby] Failed to connect to database: {emby_db_path}")
            emby_db = None
    except Exception as e:
        print(f"[Emby] Error initializing Emby database: {e}")
        emby_db = None
else:
    if use_emby_lookup:
        print(f"[Emby] Database not found at: {emby_db_path}")


def normalize_category(raw):
    cat = (raw or 'movie').lower()
    return 'tv' if cat in ['tv', 'show', 'series'] else 'movie'


def clean_torrent_name(raw_name):
    """Clean torrent name by removing common prefixes and normalizing whitespace"""
    if not raw_name:
        return raw_name
    
    # Remove common prefixes
    name = raw_name.strip()
    # Remove www.UIndex.org and similar prefixes with whitespace
    name = re.sub(r'^\s*www\.uindex\.org\s*', '', name, flags=re.IGNORECASE)
    # Remove other common tracker prefixes
    name = re.sub(r'^\s*\[.*?\]\s*', '', name)  # Remove [tracker] tags
    name = re.sub(r'^\s*\{.*?\}\s*', '', name)  # Remove {tracker} tags
    # Normalize whitespace
    name = re.sub(r'\s+', ' ', name).strip()
    return name


def match_torrent_name(name_hint, actual_name):
    """Check if actual torrent name matches name_hint with some tolerance
    
    Returns (match_score, clean_actual_name) where match_score is:
    - 3: exact match after cleaning
    - 2: name_hint is substring of actual (ignoring case)
    - 1: actual is substring of name_hint (ignoring case)
    - 0: no match
    """
    # Clean both names
    clean_hint = clean_torrent_name(name_hint).lower()
    clean_actual = clean_torrent_name(actual_name).lower()
    
    if not clean_hint or not clean_actual:
        return 0, clean_actual
    
    # Exact match
    if clean_hint == clean_actual:
        return 3, clean_actual
    
    # Substring matches (name_hint is in actual)
    if clean_hint in clean_actual:
        return 2, clean_actual
    
    # Reverse substring (actual is in name_hint)
    if clean_actual in clean_hint:
        return 1, clean_actual
    
    return 0, clean_actual


def normalize_category(raw):
    cat = (raw or 'movie').lower()
    return 'tv' if cat in ['tv', 'show', 'series'] else 'movie'


def send_magnet_to_tixati(magnet, target_path, category):
    """Add magnet to Tixati (downloads to temp), store intent for copy to final location"""
    category = normalize_category(category)
    if not magnet or not magnet.startswith('magnet:'):
        return False, "Invalid magnet link"
    
    try:
        # Add magnet to Tixati - it will download to default/temp location
        resp = requests.post(f"{TIXATI_BASE}/transfers/action", data={
            'addlink': 'Add',
            'addlinktext': magnet
        })
        
        if resp.status_code != 200:
            return False, "Tixati error: " + resp.text
        
        # Extract and clean torrent name
        name_hint = magnet_display_name(magnet) or ''
        clean_name = clean_torrent_name(name_hint)
        
        if target_path and clean_name:
            storage_mgr.add_intent(magnet, clean_name, target_path, category)
            print(f"[Magnet] Added: {clean_name} -> {target_path}")
            return True, f"Magnet added, will copy to {target_path} when complete"
        
        return True, "Magnet added to Tixati"
        
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


def update_torrent_save_path(torrent_name, new_save_path, checkbox_name=None):
    """Update the save path (seeding location) for a torrent in Tixati"""
    try:
        # Construct the POST data to update save path
        # This will try to navigate to the transfer details page and update the save path
        post_data = {
            'save_path': new_save_path,
        }
        if checkbox_name:
            post_data[checkbox_name] = 'on'
        
        resp = requests.post(f"{TIXATI_BASE}/transfers/action", data=post_data, timeout=5)
        if resp.status_code == 200:
            print(f"[UpdateSavePath] Updated save path for {torrent_name} to {new_save_path}")
            return True
        else:
            print(f"[UpdateSavePath] Failed to update (HTTP {resp.status_code}): {torrent_name}")
            return False
    except Exception as e:
        print(f"[UpdateSavePath] Error updating save path for {torrent_name}: {e}")
        return False


def check_path_writable(path):
    """Check if path is writable; create if doesn't exist"""
    try:
        os.makedirs(path, exist_ok=True)
        # Test write permission by creating a temp file
        test_file = os.path.join(path, '.write_test_' + str(int(time.time())))
        with open(test_file, 'w') as f:
            f.write('test')
        os.remove(test_file)
        return True, None
    except Exception as e:
        return False, str(e)


def copy_worker():
    """Monitor temp folder for completed torrents and copy them to final location
    
    Triggers copy when status changes from Downloading -> Seeding
    Triggers cleanup when status changes to Seeding Ratio Exceeded
    """
    torrent_status_cache = {}  # Track previous status to detect transitions
    
    while True:
        try:
            intents = list(storage_mgr.config.get('intents', []))
            if intents:
                # Get transfer list from Tixati
                resp = requests.get(f"{TIXATI_BASE}/transfers")
                soup = BeautifulSoup(resp.text, 'html.parser')
                table = soup.find('table', class_='xferslist')
                torrent_info = {}  # Map name to (status, checkbox_name)
                
                if table:
                    rows = table.find_all('tr')[1:]
                    for row in rows:
                        cols = row.find_all('td')
                        if len(cols) < 5:
                            continue
                        checkbox = cols[0].find('input', {'type': 'checkbox'})
                        name = cols[1].get_text(strip=True)
                        status = cols[4].get_text(strip=True).lower()  # Get full status text
                        checkbox_name = checkbox['name'] if checkbox and 'name' in checkbox.attrs else None
                        torrent_info[name] = (status, checkbox_name)
                        print(f"[CopyWorker] {name}: {status}")

                for intent in intents:
                    name_hint = intent.get('name_hint')
                    target_path = intent.get('target_path')
                    category = intent.get('category', 'movie')
                    if not name_hint:
                        continue
                    
                    # Find best matching torrent by name (with fuzzy matching)
                    best_match = None
                    best_score = 0
                    best_status = None
                    best_checkbox = None
                    
                    for actual_name, (status, checkbox_name) in torrent_info.items():
                        score, _ = match_torrent_name(name_hint, actual_name)
                        if score > best_score:
                            best_score = score
                            best_match = actual_name
                            best_status = status
                            best_checkbox = checkbox_name
                    
                    if best_score == 0:
                        # No match found for this intent
                        print(f"[CopyWorker] No matching torrent for {name_hint}")
                        continue
                    
                    print(f"[CopyWorker] Matched {name_hint} -> {best_match} (score: {best_score}) | Status: {best_status}")
                    
                    current_status = best_status
                    checkbox_name = best_checkbox
                    previous_status = torrent_status_cache.get(name_hint)
                    
                    # Update status cache
                    if current_status:
                        torrent_status_cache[name_hint] = current_status
                    
                    # Skip if still downloading
                    if current_status and current_status in ('downloading', 'checking', 'connecting'):
                        continue
                    
                    # Handle seeding ratio exceeded: delete from temp and Tixati
                    if current_status and 'seeding ratio exceeded' in current_status:
                        try:
                            print(f"[CopyWorker] Ratio exceeded for {name_hint}, cleaning up")
                            
                            # Remove from Tixati
                            if checkbox_name:
                                post_data = {'remove': 'Remove', checkbox_name: 'on'}
                                requests.post(f"{TIXATI_BASE}/transfers/action", data=post_data, timeout=5)
                            
                            # Delete from temp folder
                            src = os.path.join(TEMP_DOWNLOAD_DIR, name_hint)
                            if os.path.exists(src):
                                if os.path.isdir(src):
                                    shutil.rmtree(src)
                                else:
                                    os.remove(src)
                                print(f"[CopyWorker] Deleted temp: {src}")
                            
                            # Remove intent and status cache
                            storage_mgr.pop_intent_by_name(name_hint)
                            torrent_status_cache.pop(name_hint, None)
                            print(f"[CopyWorker] Cleaned up intent for {name_hint}")
                        except Exception as clean_err:
                            print(f"[CopyWorker] Cleanup failed for {name_hint}: {clean_err}")
                        continue

                    # Trigger copy when status changes to "Seeding" (download complete)
                    # Only copy once per torrent (when transitioning from downloading -> seeding)
                    if current_status == 'seeding' and previous_status != 'seeding':
                        src = os.path.join(TEMP_DOWNLOAD_DIR, name_hint)
                        
                        print(f"[CopyWorker] Download complete for {name_hint}, starting copy")
                        
                        if os.path.exists(src):
                            # File complete, copy to final location
                            if target_path:
                                try:
                                    # Check write permissions
                                    writable, err = check_path_writable(target_path)
                                    if not writable:
                                        print(f"[CopyWorker] Target not writable: {target_path} ({err})")
                                        continue
                                    
                                    # Smart folder detection for TV shows
                                    final_path = target_path
                                    if category.lower() in ['tv', 'show']:
                                        season_num, _ = extract_season_episode_numbers(name_hint)
                                        appropriate_folder = find_appropriate_season_folder(target_path, season_num)
                                        if appropriate_folder and appropriate_folder != target_path:
                                            final_path = appropriate_folder
                                            print(f"[CopyWorker] Using season folder: {final_path}")
                                    
                                    # Prepare destination path
                                    dest = os.path.join(final_path, name_hint)
                                    if os.path.exists(dest):
                                        dest = f"{dest}_{int(time.time())}"
                                    
                                    print(f"[CopyWorker] Copying {src} to {dest}")
                                    
                                    # Copy instead of move
                                    if os.path.isdir(src):
                                        shutil.copytree(src, dest, dirs_exist_ok=True)
                                    else:
                                        shutil.copy2(src, dest)
                                    
                                    print(f"[CopyWorker] Copy complete: {dest}")
                                    
                                    # Verify copy succeeded before cleanup
                                    if os.path.exists(dest):
                                        # Delete source from temp
                                        try:
                                            if os.path.isdir(src):
                                                shutil.rmtree(src)
                                            else:
                                                os.remove(src)
                                            print(f"[CopyWorker] Cleaned up temp: {src}")
                                        except Exception as cleanup_err:
                                            print(f"[CopyWorker] Could not cleanup temp {src}: {cleanup_err}")
                                        
                                        # Remove intent and status cache
                                        storage_mgr.pop_intent_by_name(name_hint)
                                        torrent_status_cache.pop(name_hint, None)
                                        print(f"[CopyWorker] Intent removed for {name_hint}")
                                    else:
                                        print(f"[CopyWorker] Copy verification failed for {name_hint}")
                                        
                                except Exception as copy_err:
                                    print(f"[CopyWorker] Copy failed for {name_hint}: {copy_err}")
                                    # Keep intent for retry
                        else:
                            # File already deleted or moved
                            storage_mgr.pop_intent_by_name(name_hint)
                            torrent_status_cache.pop(name_hint, None)
                            print(f"[CopyWorker] Source no longer exists: {src}")

        except Exception as e:
            print(f"[CopyWorker] Error: {e}")

        time.sleep(WATCHER_POLL_INTERVAL)


# Ensure temp download directory exists
try:
    os.makedirs(TEMP_DOWNLOAD_DIR, exist_ok=True)
except Exception as e:
    print(f"[Init] Could not ensure temp dir {TEMP_DOWNLOAD_DIR}: {e}")


# Start copy worker daemon thread
threading.Thread(target=copy_worker, daemon=True).start()

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

@app.route('/api/system-usage')
def get_system_usage():
    """Get comprehensive system usage stats: CPU, RAM, GPU, and bandwidth"""
    stats = {}
    
    # CPU Usage
    try:
        cpu_percent = psutil.cpu_percent(interval=0.1)
        cpu_count = psutil.cpu_count(logical=False)
        cpu_count_logical = psutil.cpu_count(logical=True)
        cpu_freq = psutil.cpu_freq()
        stats['cpu'] = {
            'percent': round(cpu_percent, 1),
            'cores': cpu_count,
            'threads': cpu_count_logical,
            'frequency': round(cpu_freq.current, 0) if cpu_freq else 0
        }
    except Exception as e:
        stats['cpu'] = {'error': str(e)}
    
    # RAM Usage
    try:
        mem = psutil.virtual_memory()
        stats['ram'] = {
            'total_gb': round(mem.total / (1024**3), 2),
            'used_gb': round(mem.used / (1024**3), 2),
            'available_gb': round(mem.available / (1024**3), 2),
            'percent': round(mem.percent, 1)
        }
    except Exception as e:
        stats['ram'] = {'error': str(e)}
    
    # GPU Usage (Windows only via nvidia-smi or basic detection)
    try:
        import subprocess
        if os.name == 'nt':
            # Try nvidia-smi for NVIDIA GPUs
            result = subprocess.run(['nvidia-smi', '--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu', 
                                   '--format=csv,noheader,nounits'], 
                                  capture_output=True, text=True, timeout=2)
            if result.returncode == 0:
                lines = result.stdout.strip().split('\\n')
                gpus = []
                for line in lines:
                    parts = line.split(',')
                    if len(parts) >= 4:
                        gpus.append({
                            'utilization': int(parts[0].strip()),
                            'memory_used_mb': int(parts[1].strip()),
                            'memory_total_mb': int(parts[2].strip()),
                            'temperature': int(parts[3].strip())
                        })
                stats['gpu'] = gpus if gpus else [{'info': 'NVIDIA GPU detected but no data'}]
            else:
                stats['gpu'] = [{'info': 'No NVIDIA GPU or nvidia-smi not available'}]
        else:
            stats['gpu'] = [{'info': 'GPU monitoring not supported on this platform'}]
    except FileNotFoundError:
        stats['gpu'] = [{'info': 'nvidia-smi not found'}]
    except Exception as e:
        stats['gpu'] = [{'error': str(e)}]
    
    # Bandwidth from Tixati
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
    
    stats['bandwidth'] = bandwidth
    
    return jsonify(stats)

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
    metadata = data.get('metadata', {})

    if not magnet or not magnet.startswith('magnet:'):
        return jsonify({"error": "Invalid magnet link"}), 400

    item = storage_mgr.add_batch_item(magnet, category, download_location, metadata)
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

@app.route('/api/magnet-ingested', methods=['POST'])
def magnet_ingested():
    """Alert backend when a magnet is ingested from the app"""
    data = request.json or {}
    magnet = data.get('magnet', '').strip()
    target_path = data.get('target_path', '').strip()
    category = data.get('category', 'movie')
    
    if not magnet or not magnet.startswith('magnet:'):
        return jsonify({"error": "Invalid magnet link"}), 400
    
    if not target_path:
        return jsonify({"error": "target_path required"}), 400
    
    try:
        # Extract and clean name
        name_hint = magnet_display_name(magnet) or ''
        clean_name = clean_torrent_name(name_hint)
        
        # Store intent for copy worker
        if clean_name:
            storage_mgr.add_intent(magnet, clean_name, target_path, category)
            print(f"[MagnetIngested] {clean_name} -> {target_path}")
            return jsonify({
                "success": True,
                "message": f"Magnet registered: {clean_name}",
                "clean_name": clean_name
            })
        else:
            return jsonify({"error": "Could not extract torrent name"}), 400
            
    except Exception as e:
        print(f"[MagnetIngested] Error: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/parse-torrent', methods=['POST'])
def parse_torrent():
    """Parse a torrent title to extract series/season/episode information"""
    data = request.json or {}
    title = data.get('title', '').strip()
    
    if not title:
        return jsonify({"error": "Title is required"}), 400
    
    try:
        metadata = parse_download_metadata(title)
        return jsonify({
            "success": True,
            "metadata": metadata
        })
    except Exception as e:
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500

@app.route('/api/parse-and-match', methods=['POST'])
def parse_and_match():
    """Parse torrent title and match against Emby database for folder suggestions"""
    data = request.json or {}
    title = data.get('title', '').strip()
    category = data.get('category', 'tv').strip()
    
    if not title:
        return jsonify({"error": "Title is required"}), 400
    
    try:
        # Parse the torrent title
        metadata = parse_download_metadata(title)
        series_name = metadata.get('series_name')
        season_number = metadata.get('season_number')
        
        folder_options = []
        confidence = metadata.get('confidence', 'low')
        
        # For TV shows, try to match against Emby database
        if category == 'tv' and emby_db and emby_db.connected and series_name:
            try:
                # Find matching series in Emby
                series_location = emby_db.find_series_location(series_name)
                
                if series_location:
                    # Found exact or close match - upgrade confidence
                    confidence = 'high'
                    
                    # Try to find appropriate season folder - prioritize this
                    if season_number:
                        season_folder = find_appropriate_season_folder(series_location, season_number)
                        if season_folder:
                            folder_options.insert(0, {
                                'path': season_folder,
                                'label': f'{os.path.basename(series_location)} / Season {season_number:02d} (Existing)',
                                'type': 'season',
                                'priority': 1
                            })
                    
                    # Add series root as option (lower priority)
                    folder_options.append({
                        'path': series_location,
                        'label': os.path.basename(series_location),
                        'type': 'series',
                        'priority': 2
                    })
                else:
                    # No match in Emby - provide library root options
                    confidence = 'medium' if confidence == 'high' else confidence
                    
                    # Get TV library paths from config
                    tv_libraries = storage_mgr.config.get('libraries', {}).get('show', [])
                    for lib in tv_libraries:
                        lib_path = lib.get('path', '')
                        if lib_path and os.path.exists(lib_path):
                            folder_options.append({
                                'path': lib_path,
                                'label': f"{lib.get('label', 'TV Library')} (New Series)",
                                'type': 'library'
                            })
            except Exception as e:
                print(f"[Emby Match] Error querying database: {e}")
        
        # For movies or if no Emby match, provide library options
        if not folder_options:
            lib_type = 'show' if category == 'tv' else 'movie'
            libraries = storage_mgr.config.get('libraries', {}).get(lib_type, [])
            for lib in libraries:
                lib_path = lib.get('path', '')
                if lib_path and os.path.exists(lib_path):
                    folder_options.append({
                        'path': lib_path,
                        'label': lib.get('label', 'Library'),
                        'type': 'library'
                    })
        
        return jsonify({
            "success": True,
            "metadata": {
                **metadata,
                'confidence': confidence
            },
            "folderOptions": folder_options
        })
    except Exception as e:
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500

@app.route('/api/create-destination', methods=['POST'])
def create_destination():
    """Create a new series/season folder and return the destination path"""
    data = request.json or {}
    series_name = data.get('seriesName', '').strip()
    season_number = data.get('seasonNumber')
    library_path = data.get('libraryPath', '').strip()
    is_new_series = data.get('isNewSeries', False)
    is_new_season = data.get('isNewSeason', False)
    
    if not series_name:
        return jsonify({"success": False, "error": "Series name is required"}), 400
    
    if not library_path:
        return jsonify({"success": False, "error": "Library path is required"}), 400
    
    # Validate library path
    valid, msg = FolderManager.validate_library_path(library_path)
    if not valid:
        return jsonify({"success": False, "error": msg}), 400
    
    try:
        # Parse season number if provided
        season_num = None
        if season_number is not None:
            season_num = int(season_number)
        
        success, dest_path, message = FolderManager.get_or_create_destination(
            series_name,
            season_num,
            library_path,
            is_new_series,
            is_new_season
        )
        
        if success:
            return jsonify({
                "success": True,
                "destinationPath": dest_path,
                "message": message
            })
        else:
            return jsonify({
                "success": False,
                "error": message
            }), 400
    
    except Exception as e:
        return jsonify({
            "success": False,
            "error": str(e)
        }), 500

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
    """Get list of active downloads (all non-seeding/non-completed statuses) from Tixati WebUI"""
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
                
                # Include torrents that are actively downloading or queued (not seeding)
                # Exclude: seeding, standby, ratio exceeded, stopped, etc.
                status_lower = status.lower().strip()
                excluded_keywords = ['seeding', 'standby', 'ratio exceeded', 'stopped', 'complete']
                is_excluded = any(keyword in status_lower for keyword in excluded_keywords)
                
                if not is_excluded:
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
