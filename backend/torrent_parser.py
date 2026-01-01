"""
Torrent Title Parser
Extracts series name, season, and episode information from torrent titles
"""
import re
from typing import Dict, Optional, Tuple


class TorrentParser:
    """Parse torrent titles to extract metadata"""
    
    # Common patterns for series names followed by season/episode info
    SERIES_PATTERNS = [
        # "Series Name S01E02" or "Series.Name.S01E02"
        r'^([^S\[]*?)\s*[S\.]\s*(\d{1,2})\s*[Ee]\s*(\d{1,2})',
        # "Series Name Season 1 Episode 2"
        r'^([^S]*?)\s+[Ss]eason\s+(\d{1,2})\s+[Ee]pisode\s+(\d{1,2})',
        # "Series Name - Season 1" (without episode)
        r'^([^S\-]*?)\s*\-?\s*[Ss]eason\s+(\d{1,2})',
        # "Series Name S01" (without episode)
        r'^([^S\[]*?)\s*[S\.]\s*(\d{1,2})(?:\s|$|[^\d])',
    ]
    
    @staticmethod
    def parse_title(title: str) -> Dict[str, Optional[str]]:
        """
        Parse a torrent title to extract series and episode information.
        
        Returns dict with:
        - series_name: The extracted series name (normalized)
        - season_number: Season number (if found)
        - episode_number: Episode number (if found)
        - is_complete_season: Whether it's a complete season (e.g., "S01 COMPLETE")
        - is_multi_season: Whether it contains multiple seasons
        - original_title: The original title
        - confidence: 'high', 'medium', or 'low' based on pattern clarity
        """
        result = {
            'series_name': None,
            'season_number': None,
            'episode_number': None,
            'is_complete_season': False,
            'is_multi_season': False,
            'original_title': title,
            'confidence': 'low'
        }
        
        # Clean up common torrent artifacts
        clean_title = TorrentParser._clean_title(title)
        
        # Try each pattern and track which one matched (for confidence)
        pattern_index = -1
        for idx, pattern in enumerate(TorrentParser.SERIES_PATTERNS):
            match = re.search(pattern, clean_title, re.IGNORECASE)
            if match:
                pattern_index = idx
                series_name = match.group(1).strip()
                result['series_name'] = TorrentParser._normalize_series_name(series_name)
                
                if len(match.groups()) >= 2:
                    result['season_number'] = match.group(2)
                
                if len(match.groups()) >= 3:
                    result['episode_number'] = match.group(3)
                
                break
        
        # Check for complete season indicators
        if result['season_number'] and re.search(r'COMPLETE|FULL.*SEASON', title, re.IGNORECASE):
            result['is_complete_season'] = True
        
        # Check for multi-season packs
        if re.search(r'S\d{1,2}\s*-\s*S\d{1,2}|Season.*\d.*-.*\d', title, re.IGNORECASE):
            result['is_multi_season'] = True
        
        # Calculate confidence based on pattern match quality
        if result['series_name']:
            # Pattern 0 (S01E02 format): High confidence
            if pattern_index == 0:
                result['confidence'] = 'high'
            # Pattern 1 (Season 1 Episode 2): High confidence
            elif pattern_index == 1:
                result['confidence'] = 'high'
            # Pattern 2 or 3: Check for additional validation
            else:
                # If we have a series name + season number, medium confidence
                if result['season_number']:
                    result['confidence'] = 'medium'
                # If series name is very short or looks dubious, low confidence
                elif len(result['series_name']) < 3:
                    result['confidence'] = 'low'
                else:
                    result['confidence'] = 'medium'
        
        return result
    
    @staticmethod
    def _clean_title(title: str) -> str:
        """Remove common torrent artifacts from title"""
        # Remove file extensions
        title = re.sub(r'\.(mkv|avi|mp4|flv|wmv|mov)$', '', title, flags=re.IGNORECASE)
        
        # Remove quality indicators (at the end usually)
        title = re.sub(r'\d{3,4}p.*$', '', title, re.IGNORECASE)
        
        # Remove codec info like "x264", "x265", "HEVC"
        title = re.sub(r'[xX]\.?26[45]|HEVC|H\.?264|MPEG', '', title)
        
        # Remove common release group indicators
        title = re.sub(r'-\s*[A-Z]{2,}$', '', title)
        
        # Remove torrent site names
        title = re.sub(r'(torrent|tpb|eztv|rarbg|etc\.?)', '', title, flags=re.IGNORECASE)
        
        return title.strip()
    
    @staticmethod
    def _normalize_series_name(name: str) -> str:
        """Normalize series name for Emby matching"""
        # Replace underscores and dots with spaces
        name = re.sub(r'[._]+', ' ', name)
        
        # Remove extra spaces
        name = re.sub(r'\s+', ' ', name).strip()
        
        # Title case
        name = name.title()
        
        # Remove trailing year if present (will be in title)
        name = re.sub(r'\s*\(\d{4}\)\s*$', '', name).strip()
        name = re.sub(r'\s*\d{4}\s*$', '', name).strip()
        
        return name
    
    @staticmethod
    def extract_season_number(title: str) -> Optional[int]:
        """Extract just the season number from a title"""
        match = re.search(r'[Ss]eason\s+(\d{1,2})|[Ss]0*(\d{1,2})', title)
        if match:
            season = match.group(1) or match.group(2)
            return int(season)
        return None
    
    @staticmethod
    def suggest_destination_folder(series_name: str, season_number: int = None, 
                                   parent_path: str = None) -> str:
        """
        Suggest a destination folder path for a new series/season.
        
        If parent_path is provided, creates "Series Name" or "Series Name/Season N"
        Otherwise just returns the suggested folder name.
        """
        if not series_name:
            return None
        
        folder_name = series_name
        
        if season_number is not None:
            # Add season folder
            folder_name = f"{series_name}/Season {int(season_number):02d}"
        
        if parent_path:
            return f"{parent_path.rstrip('/')}/{folder_name}"
        
        return folder_name


def parse_download_metadata(magnet_title: str) -> Dict:
    """
    Parse a magnet/download title and return comprehensive metadata.
    
    Returns:
    {
        'series_name': str,
        'season_number': int or None,
        'episode_number': int or None,
        'is_new_series': bool (user should confirm),
        'is_new_season': bool (user should confirm),
        'is_complete_season': bool,
        'is_multi_season': bool,
        'suggested_folder': str,
        'confidence': 'high', 'medium', or 'low',
    }
    """
    parsed = TorrentParser.parse_title(magnet_title)
    
    return {
        'series_name': parsed['series_name'],
        'season_number': int(parsed['season_number']) if parsed['season_number'] else None,
        'episode_number': int(parsed['episode_number']) if parsed['episode_number'] else None,
        'is_complete_season': parsed['is_complete_season'],
        'is_multi_season': parsed['is_multi_season'],
        'is_new_series': False,  # User must set this
        'is_new_season': False,  # User must set this
        'suggested_folder': TorrentParser.suggest_destination_folder(
            parsed['series_name'],
            int(parsed['season_number']) if parsed['season_number'] else None
        ),
        'confidence': parsed['confidence'],
    }
