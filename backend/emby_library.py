"""
Emby Library Database Interface
Queries the Emby library.db to find the correct download destinations
"""
import sqlite3
import os
import re
from pathlib import Path
from typing import Optional, Dict, List, Tuple


class EmbyLibraryDb:
    """Interface to Emby's library.db database"""
    
    def __init__(self, db_path: str):
        """Initialize with path to Emby's library.db"""
        self.db_path = db_path
        self.connected = False
        self.connection = None
        self._verify_connection()
    
    def _verify_connection(self) -> bool:
        """Verify the database file exists and is readable"""
        if not os.path.exists(self.db_path):
            return False
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) FROM MediaItems LIMIT 1")
            cursor.fetchone()
            conn.close()
            self.connected = True
            return True
        except Exception as e:
            print(f"[EmbyDb] Error verifying connection: {e}")
            return False
    
    def find_series_location(self, series_name: str) -> Optional[str]:
        """
        Find the library location for a series by name.
        Returns the parent season/series folder path.
        """
        if not self.connected:
            return None
        
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            # Query for series matching the name (case-insensitive partial match)
            normalized_name = series_name.lower().strip()
            
            # Try exact or partial match on SeriesName or Name
            cursor.execute("""
                SELECT DISTINCT Path
                FROM MediaItems
                WHERE (SeriesName IS NOT NULL OR IsSeries = 1)
                AND (LOWER(SeriesName) = ? OR LOWER(Name) LIKE ? OR LOWER(Name) = ?)
                AND Path IS NOT NULL
                LIMIT 1
            """, (normalized_name, f"%{normalized_name}%", normalized_name))
            
            result = cursor.fetchone()
            conn.close()
            
            if result and result[0]:
                path = result[0].strip()
                # Clean up Emby path variables if present
                path = path.replace('%RootFolderPath%', '').replace('%MetadataPath%', '')
                return path if path else None
            
            return None
        except Exception as e:
            print(f"[EmbyDb] Error finding series location: {e}")
            return None
    
    def find_movie_library(self, movie_name: str) -> Optional[str]:
        """
        Find the library folder for a movie by name.
        Returns the movies folder path.
        """
        if not self.connected:
            return None
        
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            normalized_name = movie_name.lower().strip()
            
            # Query for movies matching the name
            cursor.execute("""
                SELECT DISTINCT Path
                FROM MediaItems
                WHERE IsMovie = 1
                AND (LOWER(Name) = ? OR LOWER(Name) LIKE ?)
                AND Path IS NOT NULL
                LIMIT 1
            """, (normalized_name, f"%{normalized_name}%"))
            
            result = cursor.fetchone()
            conn.close()
            
            if result and result[0]:
                path = result[0].strip()
                # Clean up Emby path variables if present
                path = path.replace('%RootFolderPath%', '').replace('%MetadataPath%', '')
                # Get parent folder for movies
                return str(Path(path).parent) if path else None
            
            return None
        except Exception as e:
            print(f"[EmbyDb] Error finding movie library: {e}")
            return None
    
    def find_destination_by_series(self, series_name: str, is_movie: bool = False) -> Optional[str]:
        """
        Smart lookup: find the appropriate destination folder.
        For TV: Returns the season folder if it matches the pattern
        For Movies: Returns the movies folder
        """
        if not self.connected:
            return None
        
        try:
            if is_movie:
                return self.find_movie_library(series_name)
            else:
                return self.find_series_location(series_name)
        except Exception as e:
            print(f"[EmbyDb] Error finding destination: {e}")
            return None


def find_appropriate_season_folder(base_path: str, season_hint: int = None) -> Optional[str]:
    """
    Smart folder detection: find if a season folder already exists.
    If base_path contains a season folder structure, use that instead of creating nested folders.
    
    Returns the appropriate folder to place the episode file.
    """
    try:
        if not os.path.exists(base_path):
            return None
        
        # If base_path is already a season folder, return it
        if is_season_folder(base_path):
            return base_path
        
        # Look for season folders in subdirectories
        for item in os.listdir(base_path):
            item_path = os.path.join(base_path, item)
            if os.path.isdir(item_path) and is_season_folder(item):
                # If season_hint is provided, match it
                if season_hint is not None:
                    season_num = extract_season_number(item)
                    if season_num == season_hint:
                        return item_path
                else:
                    # Return first matching season folder
                    return item_path
        
        # No existing season folder found, return base path
        return base_path
    except Exception as e:
        print(f"[FolderDetect] Error finding season folder: {e}")
        return base_path


def is_season_folder(folder_name: str) -> bool:
    """Check if a folder name looks like a season folder"""
    folder_name_lower = str(folder_name).lower()
    # Match patterns like "Season 1", "S01", "season1", etc.
    return bool(re.search(r'season\s*0*(\d{1,2})|s0*(\d{1,2})(?:\s|$)', folder_name_lower))


def extract_season_number(name: str) -> Optional[int]:
    """Extract season number from a name"""
    # Try "Season 01" or "Season 1"
    match = re.search(r'season\s*0*(\d{1,2})', name, re.IGNORECASE)
    if match:
        return int(match.group(1))
    
    # Try "S01" or "S1"
    match = re.search(r'\bS0*(\d{1,2})\b', name, re.IGNORECASE)
    if match:
        return int(match.group(1))
    
    return None


def extract_season_episode_numbers(filename: str) -> Tuple[Optional[int], Optional[int]]:
    """Extract season and episode numbers from filename (e.g., 's01e02')"""
    # Match patterns like S01E02, S1E2, etc.
    match = re.search(r'[Ss]0*(\d{1,2})[Ee]0*(\d{1,2})', filename)
    if match:
        season = int(match.group(1))
        episode = int(match.group(2))
        return season, episode
    
    return None, None
