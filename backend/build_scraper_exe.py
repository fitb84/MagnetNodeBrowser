#!/usr/bin/env python
"""
Build script for Tixati WebUI Interactive Scraper standalone executable.

This creates a single .exe that:
- Clicks through all Tixati UI elements
- Captures torrent details (most important)
- Auto-saves with timestamp filename
- Includes Selenium for interactive scraping

Requirements:
- PyInstaller: pip install pyinstaller
- Selenium: pip install selenium
- BeautifulSoup4: pip install beautifulsoup4
- Requests: pip install requests

Usage:
    python build_scraper_exe.py

Output:
    dist/TixatiScraper.exe - Interactive scraper executable
"""
import PyInstaller.__main__
import sys
import os

backend_dir = os.path.dirname(os.path.abspath(__file__))
main_script = os.path.join(backend_dir, 'tixati_scraper.py')

args = [
    main_script,
    '--name=TixatiScraper',
    '--onefile',
    '--console',
    '--icon=NONE',
    '--distpath=./dist',
    '--workpath=./build',
    '--specpath=.',
    '-y',
    # Hidden imports for interactive scraping
    '--hidden-import=selenium',
    '--hidden-import=selenium.webdriver',
    '--hidden-import=selenium.webdriver.chrome',
    '--hidden-import=selenium.webdriver.edge',
    '--hidden-import=selenium.webdriver.support',
    '--hidden-import=selenium.webdriver.support.ui',
    '--hidden-import=selenium.webdriver.common.by',
    '--hidden-import=bs4',
    '--hidden-import=requests',
    # Collect binaries for WebDriver support
    '--collect-all=selenium',
]

print("=" * 80)
print("Building Tixati Interactive WebUI Scraper")
print("=" * 80)
print(f"Input script: {main_script}")
print(f"Output: {backend_dir}\\dist\\TixatiScraper.exe")
print("Features:")
print("  - Interactive scraping (clicks all buttons)")
print("  - Captures torrent details")
print("  - Auto-saves with date/time filename")
print("  - Selenium + HTTP fallback support")
print("=" * 80 + "\n")

try:
    PyInstaller.__main__.run(args)
    print("\n" + "=" * 80)
    print("[✓] Build successful!")
    print("=" * 80)
    exe_path = os.path.join(backend_dir, 'dist', 'TixatiScraper.exe')
    if os.path.exists(exe_path):
        size_mb = os.path.getsize(exe_path) / (1024 * 1024)
        print(f"[✓] Executable: {exe_path}")
        print(f"[✓] Size: {size_mb:.2f} MB")
    print("\nUsage Examples:")
    print("  TixatiScraper.exe                      # Auto-saves to tixati_snapshot_YYYYMMDD_HHMMSS.html")
    print("  TixatiScraper.exe --console            # Print to console instead of saving")
    print("  TixatiScraper.exe --headless           # Run browser in headless mode")
    print("  TixatiScraper.exe --host 192.168.1.1   # Custom Tixati host")
    print("  TixatiScraper.exe --port 9999          # Custom Tixati port")
    print("  TixatiScraper.exe --save custom.html   # Save with custom filename")
    print("=" * 80)
except Exception as e:
    print("\n" + "=" * 80)
    print(f"[✗] Build failed: {e}")
    print("=" * 80)
    sys.exit(1)
