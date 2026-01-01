#!/usr/bin/env python
"""Complete Emby library structure analysis"""
import sqlite3

db_path = r'C:\Users\fitb8\OneDrive\Desktop\library.db'
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

print("=" * 120)
print("[EMBY LIBRARY ROOT FOLDERS]")
print("=" * 120)

# Get actual library folders (type 4 = folder, type 3 = root folder)
cursor.execute("""
SELECT Id, Name, Path, type
FROM MediaItems 
WHERE (type = 4 OR type = 3) AND Path IS NOT NULL AND ParentId IS NULL
ORDER BY Name
""")

print("\nRoot Library Folders:")
print("-" * 120)
for row in cursor.fetchall():
    id_val, name, path, type_val = row
    path_str = path.replace('%RootFolderPath%', '[ROOT]').replace('%MetadataPath%', '[META]')
    print(f"ID {id_val:5d} | Type {type_val} | {name:20s} | {path_str}")

print("\n" + "=" * 120)
print("[SERIES AND SEASON STRUCTURE]")
print("=" * 120)

# Get series (type 7 typically means series)
cursor.execute("""
SELECT DISTINCT 
    Id, Name, Path, type, 
    (SELECT COUNT(*) FROM MediaItems m2 WHERE m2.ParentId = MediaItems.Id) as ChildCount
FROM MediaItems 
WHERE (IsSeries = 1 OR type = 6 OR type = 7) AND Path IS NOT NULL
ORDER BY Name
LIMIT 10
""")

print("\nSeries Items:")
print("-" * 120)
for row in cursor.fetchall():
    id_val, name, path, type_val, child_count = row
    path_str = path if path else "NULL"
    print(f"ID {id_val:6d} | Type {type_val} | {name:30s} | Children: {child_count} | Path: {path_str[:60]}")

print("\n" + "=" * 120)
print("[SUMMARY OF DATA FOUND]")
print("=" * 120)

# Count items by type
cursor.execute("SELECT type, COUNT(*) FROM MediaItems GROUP BY type ORDER BY type")
print("\nItems by Type:")
for row in cursor.fetchall():
    type_val, count = row
    print(f"  Type {type_val}: {count} items")

# Get a sample of what we can match
print("\n" + "=" * 120)
print("[MATCHING STRATEGY FOR DOWNLOADS]")
print("=" * 120)

print("""
The Emby library.db structure shows:

1. **Library Root Folders** - Type 3/4 items with ParentId IS NULL
   - Example: "Movies 4" -> C:\\Users\\fitb8\\Videos\\Movies 4
   - Example: "TV shows" -> C:\\Users\\fitb8\\Videos\\TV shows

2. **Series/Shows** - Items with IsSeries = 1 or similar
   - Example: "Sam & Cat" -> Path pointing to season folder
   - Has SeriesName field for matching

3. **Strategy for Downloads:**
   - When downloading, match the magnet/filename to series name in Emby DB
   - Look up the Series' Path field
   - Extract the parent folder (library location)
   - Use that as the final destination instead of manual library paths

4. **Key Fields:**
   - MediaItems.Name - Display name
   - MediaItems.Path - File system path
   - MediaItems.SeriesName - Series name (for episodes)
   - MediaItems.type - Media type
   - MediaItems.IsSeries - Boolean flag
   - MediaItems.IsMovie - Boolean flag
""")

conn.close()
