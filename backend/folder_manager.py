"""
Folder Management for New Series/Seasons
Creates appropriate folder structures when new series or seasons are detected
"""
import os
import shutil
from pathlib import Path
from typing import Optional, Tuple


class FolderManager:
    """Manage folder creation for new series and seasons"""
    
    @staticmethod
    def create_series_folder(series_name: str, parent_library_path: str, 
                            season_number: int = None) -> Tuple[bool, str, str]:
        """
        Create a folder structure for a new series.
        
        Returns: (success: bool, path: str, message: str)
        """
        try:
            if not os.path.exists(parent_library_path):
                return False, None, f"Parent library path does not exist: {parent_library_path}"
            
            # Create series folder
            series_folder = os.path.join(parent_library_path, series_name)
            os.makedirs(series_folder, exist_ok=True)
            
            # If season specified, also create season subfolder
            if season_number is not None:
                season_folder = FolderManager._get_season_folder_name(series_folder, season_number)
                os.makedirs(season_folder, exist_ok=True)
                return True, season_folder, f"Created series and season folders: {season_folder}"
            
            return True, series_folder, f"Created series folder: {series_folder}"
        
        except Exception as e:
            return False, None, f"Error creating folder: {str(e)}"
    
    @staticmethod
    def create_season_folder(series_path: str, season_number: int) -> Tuple[bool, str, str]:
        """
        Create a season folder within an existing series folder.
        
        Returns: (success: bool, path: str, message: str)
        """
        try:
            if not os.path.exists(series_path):
                return False, None, f"Series path does not exist: {series_path}"
            
            season_folder = FolderManager._get_season_folder_name(series_path, season_number)
            os.makedirs(season_folder, exist_ok=True)
            
            return True, season_folder, f"Created season folder: {season_folder}"
        
        except Exception as e:
            return False, None, f"Error creating season folder: {str(e)}"
    
    @staticmethod
    def _get_season_folder_name(base_path: str, season_number: int) -> str:
        """Get the properly formatted season folder name"""
        season_str = f"Season {int(season_number):02d}"
        return os.path.join(base_path, season_str)
    
    @staticmethod
    def get_or_create_destination(series_name: str, season_number: Optional[int], 
                                  parent_library_path: str, 
                                  is_new_series: bool = False,
                                  is_new_season: bool = False) -> Tuple[bool, str, str]:
        """
        Get or create the appropriate destination folder for a download.
        
        If series exists, returns its path. If new_series, creates it.
        If season specified, returns/creates season subfolder.
        
        Returns: (success: bool, destination_path: str, message: str)
        """
        try:
            series_folder = os.path.join(parent_library_path, series_name)
            
            # Series doesn't exist and not marked as new
            if not os.path.exists(series_folder) and not is_new_series:
                return False, None, f"Series folder not found and not marked as new: {series_folder}"
            
            # Create series folder if needed
            if not os.path.exists(series_folder):
                os.makedirs(series_folder, exist_ok=True)
                msg = f"Created new series folder: {series_folder}"
            else:
                msg = f"Using existing series folder: {series_folder}"
            
            # Handle season subfolder
            if season_number is not None:
                season_folder = FolderManager._get_season_folder_name(series_folder, season_number)
                
                if not os.path.exists(season_folder):
                    if not is_new_season:
                        return False, None, f"Season folder not found and not marked as new: {season_folder}"
                    os.makedirs(season_folder, exist_ok=True)
                    msg += f" | Created new season folder: {season_folder}"
                else:
                    msg += f" | Using existing season folder: {season_folder}"
                
                return True, season_folder, msg
            
            return True, series_folder, msg
        
        except Exception as e:
            return False, None, f"Error managing destination: {str(e)}"
    
    @staticmethod
    def validate_library_path(library_path: str) -> Tuple[bool, str]:
        """
        Validate that a library path exists and is writable.
        
        Returns: (valid: bool, message: str)
        """
        if not library_path:
            return False, "Library path is empty"
        
        if not os.path.exists(library_path):
            return False, f"Library path does not exist: {library_path}"
        
        if not os.path.isdir(library_path):
            return False, f"Library path is not a directory: {library_path}"
        
        # Try to create a test file to verify write access
        try:
            test_file = os.path.join(library_path, '.write_test')
            with open(test_file, 'w') as f:
                f.write('')
            os.remove(test_file)
            return True, "Library path is valid and writable"
        except Exception as e:
            return False, f"Library path is not writable: {str(e)}"
