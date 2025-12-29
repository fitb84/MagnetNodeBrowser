"""
Tixati Web Interface Scraper - Interactive Edition

Scrapes the entire Tixati WebUI by clicking through all buttons and options,
capturing torrent details and all sub-pages. Automatically saves with date-based filenames.

Features:
- Clicks through every page, button, and option
- Captures torrent details for each status category
- Navigates torrent detail pages (most important)
- Automatically saves with timestamp filename
- Comprehensive data collection

Usage:
    python tixati_scraper.py                    # Scrape and auto-save (default)
    python tixati_scraper.py --host 192.168.1.1 --port 8888  # Custom host/port
    python tixati_scraper.py --headless         # Run browser in headless mode
"""

import requests
import argparse
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Set
from bs4 import BeautifulSoup
import json

# Try to import Selenium for interactive scraping
try:
    from selenium import webdriver
    from selenium.webdriver.common.by import By
    from selenium.webdriver.support.ui import WebDriverWait
    from selenium.webdriver.support import expected_conditions as EC
    from selenium.webdriver.chrome.options import Options
    SELENIUM_AVAILABLE = True
except ImportError:
    SELENIUM_AVAILABLE = False

class TixatiScraper:
    """Scrapes Tixati WebUI interactively, clicking all buttons and capturing details"""
    
    def __init__(self, host: str = "localhost", port: int = 8888, timeout: int = 10, headless: bool = False):
        self.base_url = f"http://{host}:{port}"
        self.timeout = timeout
        self.headless = headless
        self.driver = None
        self.scraped_content = {}
        self.pages = {
            'home': '/home',
            'transfers': '/transfers',
            'bandwidth': '/bandwidth',
            'dht': '/dht',
            'settings': '/settings',
            'help': '/help',
        }
        self.torrent_statuses = {}  # Will store torrent details by status
    
    def test_connection(self) -> bool:
        """Test if Tixati WebUI is accessible"""
        try:
            resp = requests.get(f"{self.base_url}/home", timeout=self.timeout)
            return resp.status_code == 200
        except Exception as e:
            print(f"[ERROR] Cannot connect to Tixati at {self.base_url}: {e}")
            return False
    
    def init_driver(self):
        """Initialize Selenium WebDriver"""
        if not SELENIUM_AVAILABLE:
            print("[WARNING] Selenium not installed. Using basic HTTP scraping instead.")
            return False
        
        try:
            print("[INFO] Initializing browser driver...")
            chrome_options = Options()
            if self.headless:
                chrome_options.add_argument("--headless")
            chrome_options.add_argument("--disable-blink-features=AutomationControlled")
            chrome_options.add_argument("user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
            chrome_options.add_argument("--no-sandbox")
            chrome_options.add_argument("--disable-dev-shm-usage")
            
            # Try to use Chrome
            try:
                self.driver = webdriver.Chrome(options=chrome_options)
            except:
                # Fallback to chromium or edge
                try:
                    self.driver = webdriver.Edge(options=chrome_options)
                except:
                    print("[WARNING] Could not initialize browser driver")
                    return False
            
            return True
        except Exception as e:
            print(f"[WARNING] Failed to initialize driver: {e}")
            return False
    
    def scrape_page_http(self, page_name: str, url: str) -> Optional[str]:
        """Scrape a single page using basic HTTP requests"""
        try:
            print(f"  Scraping {page_name}...", end=" ", flush=True)
            resp = requests.get(f"{self.base_url}{url}", timeout=self.timeout)
            if resp.status_code == 200:
                print(f"OK ({len(resp.text)} bytes)")
                return resp.text
            else:
                print(f"FAILED ({resp.status_code})")
                return None
        except Exception as e:
            print(f"ERROR: {e}")
            return None
    
    def click_element(self, xpath: str) -> bool:
        """Click an element if it exists"""
        try:
            element = self.driver.find_element(By.XPATH, xpath)
            self.driver.execute_script("arguments[0].scrollIntoView(true);", element)
            time.sleep(0.3)
            element.click()
            time.sleep(0.5)
            return True
        except:
            return False
    
    def get_page_html(self) -> str:
        """Get current page HTML"""
        try:
            return self.driver.page_source
        except:
            return ""
    
    def scrape_torrent_details(self) -> Dict[str, str]:
        """Scrape torrent details by clicking through torrents"""
        if not self.driver:
            return {}
        
        details = {}
        try:
            print("\n[INFO] Scraping torrent details...")
            
            # Click on transfers tab if not already there
            self.click_element("//a[contains(@href, '/transfers')]")
            time.sleep(1)
            
            # Try to find torrent rows and click them
            torrent_xpaths = [
                "//tr[@class='transfer-row']",
                "//tr[contains(@class, 'transfer')]",
                "//table//tr[position()>1]",  # Skip header
            ]
            
            torrent_elements = []
            for xpath in torrent_xpaths:
                try:
                    elements = self.driver.find_elements(By.XPATH, xpath)
                    if elements:
                        torrent_elements = elements[:5]  # Get first 5
                        break
                except:
                    continue
            
            if torrent_elements:
                for idx, element in enumerate(torrent_elements):
                    try:
                        # Click on the torrent row
                        self.driver.execute_script("arguments[0].scrollIntoView(true);", element)
                        time.sleep(0.3)
                        element.click()
                        time.sleep(0.8)
                        
                        # Get the details page HTML
                        html = self.get_page_html()
                        torrent_name = element.text.split('\n')[0] if element.text else f"torrent_{idx}"
                        details[torrent_name] = html
                        
                        print(f"    Captured torrent {idx+1}: {torrent_name[:50]}")
                        
                        # Go back to transfers list
                        self.driver.back()
                        time.sleep(0.5)
                    except Exception as e:
                        print(f"    Skipped torrent {idx+1}: {e}")
            else:
                print("    No torrent rows found in page")
            
        except Exception as e:
            print(f"[WARNING] Error scraping torrent details: {e}")
        
        return details
    
    def scrape_all_interactive(self) -> Dict[str, str]:
        """Scrape all pages interactively using Selenium"""
        print(f"\nConnecting to Tixati at {self.base_url}...")
        if not self.test_connection():
            return {}
        
        if not self.init_driver():
            print("[INFO] Falling back to HTTP-based scraping...")
            return self.scrape_all_http()
        
        try:
            print("[INFO] Starting interactive scraping...\n")
            
            # Scrape main pages
            for page_name, url in self.pages.items():
                try:
                    print(f"Navigating to {page_name}...", end=" ", flush=True)
                    self.driver.get(f"{self.base_url}{url}")
                    time.sleep(1)
                    
                    # Try to find and click all buttons on the page
                    print("clicking elements...", end=" ", flush=True)
                    buttons = self.driver.find_elements(By.TAG_NAME, "button")
                    for i, button in enumerate(buttons[:10]):  # Limit to 10 buttons per page
                        try:
                            self.driver.execute_script("arguments[0].scrollIntoView(true);", button)
                            time.sleep(0.2)
                            button.click()
                            time.sleep(0.3)
                        except:
                            pass
                    
                    # Get final page HTML
                    html = self.get_page_html()
                    self.scraped_content[page_name] = html
                    print(f"OK ({len(html)} bytes)")
                    
                except Exception as e:
                    print(f"ERROR: {e}")
            
            # Scrape torrent details (most important)
            torrent_details = self.scrape_torrent_details()
            self.scraped_content['torrent_details'] = torrent_details
            
            print(f"\n[OK] Interactive scraping complete")
            return self.scraped_content
            
        except Exception as e:
            print(f"[ERROR] Interactive scraping failed: {e}")
            print("[INFO] Falling back to HTTP-based scraping...")
            return self.scrape_all_http()
        finally:
            if self.driver:
                try:
                    self.driver.quit()
                except:
                    pass
    
    def scrape_all_http(self) -> Dict[str, str]:
        """Fallback: Scrape all pages using HTTP requests"""
        print(f"\nConnecting to Tixati at {self.base_url}...")
        if not self.test_connection():
            return {}
        
        print(f"Scraping Tixati WebUI ({len(self.pages)} pages)...\n")
        results = {}
        for page_name, url in self.pages.items():
            html = self.scrape_page_http(page_name, url)
            if html:
                results[page_name] = html
        
        print(f"\nSuccessfully scraped {len(results)}/{len(self.pages)} pages")
        return results
    
    def scrape_all(self) -> Dict:
        """Main scraping method - tries interactive first, falls back to HTTP"""
        # Try interactive scraping with Selenium
        result = self.scrape_all_interactive()
        
        # If interactive scraping failed, use HTTP fallback
        if not result:
            result = self.scrape_all_http()
        
        return result
    
    def create_combined_html(self, pages: Dict) -> str:
        """Combine all scraped pages into a single HTML file with tabs"""
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        
        html_parts = [
            '<!DOCTYPE html>',
            '<html>',
            '<head>',
            f'  <title>Tixati WebUI Interactive Snapshot - {timestamp}</title>',
            '  <meta charset="utf-8">',
            '  <style>',
            '    * { box-sizing: border-box; }',
            '    html, body { width: 100%; height: 100%; }',
            '    body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #0d0d0d; color: #e0e0e0; }',
            '    .header { background: #1a1a1a; padding: 20px; border-radius: 5px; margin-bottom: 20px; border-left: 4px solid #00a0ff; border: 1px solid #333; }',
            '    .header h1 { margin: 0 0 10px 0; color: #00d4ff; font-size: 1.8em; }',
            '    .header p { margin: 5px 0; color: #b0b0b0; font-size: 0.95em; }',
            '    .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 15px; margin-top: 15px; }',
            '    .info-item { background: #151515; padding: 12px; border-radius: 4px; border: 1px solid #333; }',
            '    .info-item strong { color: #00d4ff; }',
            '    .tabs { display: flex; gap: 5px; margin-bottom: 20px; border-bottom: 2px solid #333; flex-wrap: wrap; }',
            '    .tab-btn { padding: 12px 18px; background: #2a2a2a; border: 1px solid #444; border-bottom: none; color: #c0c0c0; cursor: pointer; border-radius: 5px 5px 0 0; font-size: 0.95em; transition: all 0.2s; font-weight: 500; }',
            '    .tab-btn:hover { background: #333; color: #fff; }',
            '    .tab-btn.active { background: #00a0ff; color: #000; font-weight: bold; border-color: #00a0ff; }',
            '    .tab-content { display: none; background: #0d0d0d; padding: 20px; border: 1px solid #333; border-radius: 0 5px 5px 5px; max-height: 85vh; overflow-y: auto; }',
            '    .tab-content.active { display: block; }',
            '    .page-snapshot { background: #151515; padding: 15px; border-radius: 5px; border: 1px solid #333; }',
            '    .page-snapshot h2 { margin-top: 0; color: #00d4ff; border-bottom: 2px solid #333; padding-bottom: 10px; font-size: 1.3em; }',
            '    .page-snapshot h3 { color: #00b8e6; margin: 15px 0 5px 0; }',
            '    .page-snapshot pre { background: #0a0a0a; color: #c0c0c0; padding: 15px; border-radius: 5px; overflow-x: auto; max-height: 600px; border-left: 4px solid #00a0ff; border: 1px solid #333; font-size: 0.9em; line-height: 1.4; }',
            '    details { margin: 15px 0; background: #151515; padding: 12px; border-radius: 5px; border-left: 4px solid #00a0ff; border: 1px solid #333; }',
            '    summary { cursor: pointer; color: #00d4ff; font-weight: bold; padding: 8px; user-select: none; font-size: 0.95em; }',
            '    summary:hover { color: #00ffff; background: #1a1a1a; border-radius: 3px; }',
            '    details[open] summary { color: #00ffff; }',
            '    .torrent-detail { background: #151515; margin: 10px 0; padding: 15px; border-radius: 5px; border-left: 4px solid #00a0ff; border: 1px solid #333; }',
            '    .torrent-detail h3 { margin: 0 0 10px 0; color: #00ffff; font-size: 1.1em; }',
            '    .torrent-detail p { margin: 5px 0; color: #c0c0c0; }',
            '    .section-count { background: #00a0ff; color: #000; padding: 4px 10px; border-radius: 3px; font-size: 0.85em; font-weight: bold; }',
            '    table { width: 100%; border-collapse: collapse; margin: 10px 0; background: #0a0a0a; }',
            '    th { background: #1a1a1a; color: #00d4ff; padding: 10px; text-align: left; border: 1px solid #333; font-weight: bold; }',
            '    td { padding: 8px; border: 1px solid #333; color: #c0c0c0; }',
            '    tr:nth-child(even) { background: #151515; }',
            '    tr:hover { background: #1a1a1a; }',
            '    a { color: #00a0ff; text-decoration: none; cursor: pointer; }',
            '    a:hover { color: #00ffff; text-decoration: underline; }',
            '    .content-frame { background: #0a0a0a; border: 1px solid #333; border-radius: 5px; padding: 10px; margin: 10px 0; }',
            '    .content-frame iframe { width: 100%; height: 600px; border: none; }',
            '    .torrent-tabs { display: flex; gap: 5px; margin-bottom: 15px; border-bottom: 2px solid #333; flex-wrap: wrap; }',
            '    .torrent-tab-btn { padding: 10px 14px; background: #2a2a2a; border: 1px solid #444; border-bottom: none; color: #c0c0c0; cursor: pointer; border-radius: 4px 4px 0 0; font-size: 0.9em; transition: all 0.2s; white-space: nowrap; }',
            '    .torrent-tab-btn:hover { background: #333; color: #00d4ff; }',
            '    .torrent-tab-btn.active { background: #00a0ff; color: #000; font-weight: bold; }',
            '    .torrent-detail-content { display: none; background: #0a0a0a; padding: 15px; border: 1px solid #333; border-radius: 0 4px 4px 4px; margin-bottom: 15px; }',
            '    .torrent-detail-content.active { display: block; }',
            '  </style>',
            '</head>',
            '<body>',
            '  <div class="header">',
            f'    <h1>🔍 Tixati WebUI Interactive Snapshot</h1>',
            f'    <p>Generated: {timestamp}</p>',
            '    <div class="info-grid">',
            f'      <div class="info-item"><strong>Pages captured:</strong> {len([p for p in pages if isinstance(pages[p], str)])} main pages</div>',
            f'      <div class="info-item"><strong>Torrent details:</strong> {len(pages.get("torrent_details", {})) if isinstance(pages.get("torrent_details"), dict) else "N/A"} torrents</div>',
            f'      <div class="info-item"><strong>Scraping method:</strong> Interactive (Selenium) + HTTP fallback</div>',
            f'      <div class="info-item"><strong>Data completeness:</strong> Full UI with button clicks and navigation</div>',
            '    </div>',
            '  </div>',
            '  <div class="tabs">',
        ]
        
        # Add main page tabs
        main_pages = [p for p in pages if isinstance(pages[p], str)]
        torrent_details = pages.get("torrent_details", {})
        if isinstance(torrent_details, dict) and torrent_details:
            main_pages.append("torrent_details")
        
        for i, page_name in enumerate(main_pages):
            active = 'active' if i == 0 else ''
            page_display = page_name.replace('_', ' ').upper()
            html_parts.append(f'    <button class="tab-btn {active}" onclick="showTab(event, \'{page_name}\')">{page_display}</button>')
        
        html_parts.append('  </div>')
        
        # Add main page content
        page_idx = 0
        for page_name, content in pages.items():
            if page_name == "torrent_details":
                continue  # Handle separately
            
            if not isinstance(content, str):
                continue
            
            active = 'active' if page_idx == 0 else ''
            page_display = page_name.replace('_', ' ').upper()
            html_parts.append(f'  <div id="{page_name}" class="tab-content {active}">')
            html_parts.append('    <div class="page-snapshot">')
            html_parts.append(f'      <h2>{page_display} Page</h2>')
            
            # Show preview
            preview = content[:2000] if len(content) > 2000 else content
            html_parts.append(f'      <details>')
            html_parts.append(f'        <summary>View HTML ({len(content)} bytes)</summary>')
            html_parts.append(f'        <pre>{content}</pre>')
            html_parts.append(f'      </details>')
            html_parts.append('    </div>')
            html_parts.append('  </div>')
            page_idx += 1
        
        # Add torrent details tab if available
        if isinstance(torrent_details, dict) and torrent_details:
            active = 'active' if page_idx == 0 else ''
            html_parts.append(f'  <div id="torrent_details" class="tab-content {active}">')
            html_parts.append('    <div class="page-snapshot">')
            html_parts.append(f'      <h2>TORRENT DETAILS <span class="section-count">{len(torrent_details)} torrents captured</span></h2>')
            html_parts.append('      <div class="torrent-tabs">')
            
            # Create sub-tabs for each torrent
            for i, torrent_name in enumerate(torrent_details.keys(), 1):
                safe_id = f"torrent_{i}".replace(' ', '_').replace('/', '_')
                active_sub = 'active' if i == 1 else ''
                html_parts.append(f'        <button class="torrent-tab-btn {active_sub}" onclick="showTorrentDetail(event, \'{safe_id}\')">')
                html_parts.append(f'          Torrent #{i}: {torrent_name[:50]}')
                html_parts.append(f'        </button>')
            
            html_parts.append('      </div>')
            
            # Create torrent detail sections
            for i, (torrent_name, torrent_html) in enumerate(torrent_details.items(), 1):
                safe_id = f"torrent_{i}".replace(' ', '_').replace('/', '_')
                active_sub = 'active' if i == 1 else ''
                html_parts.append(f'      <div id="{safe_id}" class="torrent-detail-content {active_sub}">')
                html_parts.append(f'        <h3>Torrent #{i}: {torrent_name}</h3>')
                html_parts.append(f'        <div style="margin-bottom: 15px; color: #b0b0b0; font-size: 0.9em;">')
                html_parts.append(f'          <strong>Size:</strong> {len(torrent_html):,} bytes')
                html_parts.append(f'        </div>')
                html_parts.append(f'        <details open>')
                html_parts.append(f'          <summary>View Full Details (Click to expand/collapse)</summary>')
                # Escape HTML content properly
                escaped_html = torrent_html.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;')
                html_parts.append(f'          <pre>{escaped_html}</pre>')
                html_parts.append(f'        </details>')
                html_parts.append(f'      </div>')
            
            html_parts.append('    </div>')
            html_parts.append('  </div>')
        
        html_parts.extend([
            '  <script>',
            '    function showTab(evt, tabName) {',
            '      const contents = document.querySelectorAll(".tab-content");',
            '      contents.forEach(c => c.classList.remove("active"));',
            '      const buttons = document.querySelectorAll(".tab-btn");',
            '      buttons.forEach(b => b.classList.remove("active"));',
            '      const tab = document.getElementById(tabName);',
            '      if (tab) {',
            '        tab.classList.add("active");',
            '        evt.currentTarget.classList.add("active");',
            '      }',
            '    }',
            '    function showTorrentDetail(evt, detailId) {',
            '      const contents = document.querySelectorAll(".torrent-detail-content");',
            '      contents.forEach(c => c.classList.remove("active"));',
            '      const buttons = document.querySelectorAll(".torrent-tab-btn");',
            '      buttons.forEach(b => b.classList.remove("active"));',
            '      const detail = document.getElementById(detailId);',
            '      if (detail) {',
            '        detail.classList.add("active");',
            '        evt.currentTarget.classList.add("active");',
            '      }',
            '    }',
            '  </script>',
            '</body>',
            '</html>',
        ])
        
        return '\n'.join(html_parts)
    
    def save_to_file(self, html: str, filepath: str = None) -> str:
        """Save HTML to file with auto-generated date-based filename"""
        if filepath is None:
            # Generate automatic filename with date and time
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filepath = f"tixati_snapshot_{timestamp}.html"
        
        try:
            # Create parent directories if needed
            Path(filepath).parent.mkdir(parents=True, exist_ok=True)
            
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(html)
            
            file_size = Path(filepath).stat().st_size / 1024  # KB
            print(f"\n[✓] Snapshot saved: {filepath} ({file_size:.1f} KB)")
            return filepath
        except Exception as e:
            print(f"[✗] Failed to save snapshot: {e}")
            return None
    
    def print_to_console(self, html: str):
        """Print HTML to console"""
        print("\n" + "="*80)
        print("TIXATI WEBUI INTERACTIVE SNAPSHOT")
        print("="*80 + "\n")
        print(html[:5000])
        print(f"\n... [Full content is {len(html)} bytes total]")

def main():
    parser = argparse.ArgumentParser(
        description='Interactive Tixati WebUI scraper - clicks all buttons and captures torrent details',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
EXAMPLES:
  python tixati_scraper.py                          # Auto-saves with timestamp
  python tixati_scraper.py --host 192.168.1.1      # Custom host
  python tixati_scraper.py --port 9999              # Custom port
  python tixati_scraper.py --headless               # Headless browser mode
  python tixati_scraper.py --console                # Print to console instead
  python tixati_scraper.py --save custom_name.html # Save with custom name

FEATURES:
  - Clicks all buttons on each page
  - Captures torrent details (most important)
  - Navigates through multiple torrents
  - Auto-saves with date/time filename
  - Falls back to HTTP if Selenium unavailable
  - Creates interactive tabbed HTML output
        '''
    )
    
    parser.add_argument('--host', type=str, default='localhost',
                        help='Tixati WebUI host (default: localhost)')
    parser.add_argument('--port', type=int, default=8888,
                        help='Tixati WebUI port (default: 8888)')
    parser.add_argument('--save', type=str, default=None,
                        help='Custom filename to save (auto-generates if not specified)')
    parser.add_argument('--console', action='store_true',
                        help='Print to console instead of saving')
    parser.add_argument('--headless', action='store_true',
                        help='Run browser in headless mode')
    parser.add_argument('--timeout', type=int, default=10,
                        help='Request timeout in seconds (default: 10)')
    
    args = parser.parse_args()
    
    print("="*80)
    print("TIXATI WEB SCRAPER - INTERACTIVE MODE")
    print("="*80)
    print(f"Target: http://{args.host}:{args.port}")
    print(f"Selenium: {'Available' if SELENIUM_AVAILABLE else 'Not installed - will use HTTP fallback'}")
    print("="*80)
    
    scraper = TixatiScraper(host=args.host, port=args.port, timeout=args.timeout, headless=args.headless)
    
    pages = scraper.scrape_all()
    
    if not pages:
        print("\n[✗] No pages scraped. Is Tixati running?")
        sys.exit(1)
    
    html = scraper.create_combined_html(pages)
    
    if args.console:
        scraper.print_to_console(html)
    else:
        # Default: auto-save with timestamp
        scraper.save_to_file(html, args.save)
    
    print("\n[✓] Scraping complete")

if __name__ == '__main__':
    main()
