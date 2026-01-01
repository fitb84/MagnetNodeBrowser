#!/usr/bin/env python
"""Query Emby library.db for library structure"""
import sqlite3

db_path = r'C:\Users\fitb8\OneDrive\Desktop\library.db'
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

print("=" * 100)
print("[LIBRARIES AND FOLDERS - ALL ITEMS WITH PATHS]")
print("=" * 100)

cursor.execute("""
SELECT Id, Name, Path, type, IsMovie, IsSeries 
FROM MediaItems 
WHERE Path IS NOT NULL 
ORDER BY Id
LIMIT 30
""")

print("\nID | Name | Path | Type | IsMovie | IsSeries")
print("-" * 100)
for row in cursor.fetchall():
    id_val, name, path, type_val, is_movie, is_series = row
    print(f"{id_val} | {name[:20]:<20} | {str(path)[:40]:<40} | {type_val} | {is_movie} | {is_series}")

print("\n" + "=" * 100)
print("[TV SERIES STRUCTURE]")
print("=" * 100)

cursor.execute("""
SELECT Id, Name, Path, SeriesName, ParentId, TopParentId
FROM MediaItems 
WHERE IsSeries = 1 OR ParentIndexNumber IS NOT NULL
ORDER BY TopParentId, Name
LIMIT 20
""")

print("\nID | Name | Path | SeriesName | ParentId | TopParentId")
print("-" * 100)
for row in cursor.fetchall():
    id_val, name, path, series_name, parent_id, top_parent_id = row
    path_str = str(path)[:40] if path else "None"
    print(f"{id_val} | {name[:20]:<20} | {path_str:<40} | {series_name} | {parent_id} | {top_parent_id}")

print("\n" + "=" * 100)
print("[LIBRARY FOLDERS (ROOT ITEMS)]")
print("=" * 100)

cursor.execute("""
SELECT Id, Name, Path
FROM MediaItems 
WHERE ParentId IS NULL AND Path IS NOT NULL
ORDER BY Name
""")

print("\nID | Name | Path")
print("-" * 100)
for row in cursor.fetchall():
    id_val, name, path = row
    print(f"{id_val} | {name} | {path}")

conn.close()
