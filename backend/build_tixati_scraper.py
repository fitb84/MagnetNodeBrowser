#!/usr/bin/env python
"""
Build script for creating standalone Tixati Web Scraper executable.
This builds the Tixati Node Browser Backend into a single .exe file.

Usage:
    python build_tixati_scraper.py

Output:
    dist/TixatiWebScraper.exe - Standalone executable (no dependencies required)
"""
import PyInstaller.__main__
import sys
import os

# Get the backend directory
backend_dir = os.path.dirname(os.path.abspath(__file__))
main_script = os.path.join(backend_dir, 'run_local_app.py')

# PyInstaller arguments
args = [
    main_script,
    '--name=TixatiWebScraper',
    '--onefile',  # Single executable file
    '--console',  # Keep console window to show logs
    '--icon=NONE',  # No custom icon
    '--distpath=./dist',  # Output directory
    '--workpath=./build',  # Build directory
    '--specpath=.',  # Spec file location
    '--add-data=templates:templates',  # Include templates folder
    '-y',  # Overwrite without asking
]

print("=" * 70)
print("Building Tixati Web Scraper standalone executable")
print("=" * 70)
print(f"Main script: {main_script}")
print(f"Output: {backend_dir}\\dist\\TixatiWebScraper.exe")

try:
    PyInstaller.__main__.run(args)
    print("\n" + "=" * 70)
    print("[OK] Build successful!")
    print("=" * 70)
    print(f"Executable location: {backend_dir}\\dist\\TixatiWebScraper.exe")
    print("\nDeployment Instructions:")
    print("1. Copy 'TixatiWebScraper.exe' to target machine")
    print("2. Ensure Tixati is running on localhost:8888")
    print("3. Double-click the .exe to start the backend")
    print("4. Backend will listen on http://localhost:5050")
    print("=" * 70)
except Exception as e:
    print("\n" + "=" * 70)
    print(f"[ERROR] Build failed: {e}")
    print("=" * 70)
    sys.exit(1)
