#!/usr/bin/env python
"""
Build script for creating a standalone executable of the Tixati Node Browser backend.
Run with: python build_exe.py
"""
import PyInstaller.__main__
import sys
import os

# Get the backend directory
backend_dir = os.path.dirname(os.path.abspath(__file__))
main_script = os.path.join(backend_dir, 'run_local_app.py')
templates_dir = os.path.join(backend_dir, 'templates')

# PyInstaller arguments
args = [
    main_script,
    '--name=TixatiNodeBrowserBackend',
    '--onefile',  # Single executable file
    '--console',  # Keep console window to see output
    '--icon=NONE',  # No custom icon
    '--distpath=./dist',  # Output directory
    '--workpath=./build',  # Build directory
    '--specpath=.',  # Spec file location
    f'--add-data={templates_dir}:templates',  # Include templates folder
    '-y',  # Overwrite without asking
]

print("Building Tixati Node Browser Backend executable...")
print(f"Main script: {main_script}")

try:
    PyInstaller.__main__.run(args)
    print("\n[OK] Build successful!")
    print(f"Executable created at: {backend_dir}\\dist\\TixatiNodeBrowserBackend.exe")
except Exception as e:
    print(f"\n[ERROR] Build failed: {e}")
    sys.exit(1)
