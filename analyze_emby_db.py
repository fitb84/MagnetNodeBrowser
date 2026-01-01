#!/usr/bin/env python
"""Analyze Emby library.db schema and sample data"""
import sqlite3
import json

db_path = r'C:\Users\fitb8\OneDrive\Desktop\library.db'

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Get all tables
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    tables = cursor.fetchall()
    
    print("=" * 80)
    print("EMBY LIBRARY.DB SCHEMA ANALYSIS")
    print("=" * 80)
    
    print("\n[TABLES FOUND]")
    for table in tables:
        table_name = table[0]
        cursor.execute(f"PRAGMA table_info({table_name})")
        columns = cursor.fetchall()
        print(f"\n{table_name}:")
        for col in columns:
            col_id, col_name, col_type, not_null, default, pk = col
            print(f"  - {col_name}: {col_type}")
    
    # Check for key tables
    key_tables = ['Library', 'LibraryFolders', 'MediaItems', 'Series', 'Season', 'ItemParents']
    
    print("\n" + "=" * 80)
    print("[SAMPLE DATA FROM KEY TABLES]")
    print("=" * 80)
    
    for table_name in key_tables:
        cursor.execute(f"SELECT name FROM sqlite_master WHERE type='table' AND name='{table_name}'")
        if cursor.fetchone():
            print(f"\n{table_name}:")
            cursor.execute(f"SELECT * FROM {table_name} LIMIT 5")
            rows = cursor.fetchall()
            if rows:
                cursor.execute(f"PRAGMA table_info({table_name})")
                cols = [col[1] for col in cursor.fetchall()]
                print(f"  Columns: {', '.join(cols)}")
                for row in rows:
                    print(f"  {row}")
            else:
                print("  (no data)")
    
    conn.close()
    print("\n" + "=" * 80)
    
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()
