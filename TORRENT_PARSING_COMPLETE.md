# Torrent Parsing & Metadata Editing Implementation

## Overview
Enhanced the ingest workflow to automatically parse torrent titles, extract series/season/episode metadata, and provide confidence indicators with full editing capabilities before batch submission.

## Features Implemented

### 1. Backend Parser Enhancement
**File**: `backend/torrent_parser.py`

**Confidence Scoring System**:
- **HIGH**: Clear patterns like "Series.Name.S01E02" or "Series Name S01 COMPLETE"
- **MEDIUM**: Patterns with season info like "series.2016.s01" or fallback matches
- **LOW**: Ambiguous titles, short series names, or unclear parsing

**Supported Patterns**:
- `"Series.Name.S01E02"` → series="Series Name", season=1, episode=2
- `"Series Name Season 1 Episode 2"` → Full text pattern
- `"Series Name - Season 1"` → Season only (no episode)
- `"example.series.2016.s01"` → Complete season pack detection
- `"Series S01 COMPLETE"` → Complete season flag
- `"Series S01-S03"` → Multi-season pack detection

**Key Methods**:
- `TorrentParser.parse_title(title)` - Extracts metadata with confidence score
- `parse_download_metadata(magnet_title)` - Comprehensive metadata extraction

### 2. Flutter UI Integration

#### Parsing Dialog (`_showTorrentParsingDialog`)
**Features**:
- **Confidence Indicator**: Color-coded badges (✓ green, ○ orange, ⚠ red)
- **Editable Metadata Fields**:
  - Series Name (text input)
  - Season Number (number input, optional)
  - Episode Number (number input, optional)
- **Detection Flags**:
  - "Complete season detected" notification
  - "Multi-season pack detected" notification
- **New Series/Season Checkboxes**:
  - Allow user to confirm if new series or new season
  - Enables smart folder creation on move_worker

#### Batch Item Display
**Enhanced Card UI**:
- **Category Badge**: TV SHOW or MOVIE
- **Confidence Indicator**: Visual signal with tooltip
- **Metadata Preview**: Shows parsed series name + S##E## format
- **Location Warning**: Red warning if no location set
- **Edit/Delete Buttons**: Tap to modify or remove

### 3. API Integration

#### New API Client Methods
```dart
Future<Map<String, dynamic>> parseTorrent(String title)
  → POST /api/parse-torrent
  → Returns: series_name, season_number, episode_number, 
             is_complete_season, is_multi_season, confidence

Future<Map<String, dynamic>> createDestination(...)
  → POST /api/create-destination
  → Creates series/season folders with validation
```

#### Updated Methods
```dart
ApiClient.addBatchItem()
  → Now accepts optional metadata parameter
  → Stores torrent parsing results with batch item
```

### 4. Batch Item Model Enhancement

**Updated `BatchItem` class**:
```dart
class BatchItem {
  // ... existing fields
  Map<String, dynamic>? metadata;  // NEW: Stores parsed metadata
}
```

**Metadata Structure**:
```json
{
  "series_name": "Breaking Bad",
  "season_number": 1,
  "episode_number": 5,
  "is_complete_season": false,
  "is_multi_season": false,
  "is_new_series": false,
  "is_new_season": false,
  "suggested_folder": "Breaking Bad/Season 01",
  "confidence": "high"
}
```

## User Workflow

### For TV Shows:
1. User enters magnet link (e.g., "Breaking.Bad.S01E05.720p.mkv")
2. App auto-detects TV category → triggers parsing
3. Dialog shows parsed metadata with confidence badge
4. User can:
   - Edit series name if incorrect
   - Edit season/episode numbers
   - Confirm if new series/season
5. Metadata stored with batch item
6. Metadata available for move_worker to handle folder creation

### For Movies:
- Proceeds with original workflow (no parsing needed)
- No metadata dialog shown

## Batch Item Editing

Users can **Edit** any batch item by tapping on it:
- Revise all metadata fields
- Update download location
- Modify category (movie ↔ tv)
- All changes saved to persistent batch storage

## Confidence Indicator Benefits

**Why Confidence Matters**:
- **High**: Parser confident in extraction → user can submit directly
- **Medium**: Some parsing hints but might need review → user should verify
- **Low**: Ambiguous title → user MUST review and correct metadata

**Visual Signals**:
- ✓ GREEN (High) = Bold checkmark, high confidence safe to use
- ○ ORANGE (Medium) = Circle, moderate confidence should review
- ⚠ RED (Low) = Warning symbol, low confidence must verify

## Build Artifacts

### Backend EXE
- **Location**: `backend/dist/TixatiNodeBrowserBackend.exe`
- **Size**: 16.82 MB
- **Includes**: torrent_parser.py with confidence scoring

### Mobile APK  
- **Location**: `build/app/outputs/flutter-apk/app-release.apk`
- **Size**: 49.06 MB
- **Includes**: Full parsing dialog UI, confidence badges, metadata editing

## Technical Details

### Parser Patterns (Regex-based)
1. `^([^S\[]*?)\s*[S\.]\s*(\d{1,2})\s*[Ee]\s*(\d{1,2})` → High confidence
2. `^([^S]*?)\s+[Ss]eason\s+(\d{1,2})\s+[Ee]pisode\s+(\d{1,2})` → High confidence
3. `^([^S\-]*?)\s*\-?\s*[Ss]eason\s+(\d{1,2})` → Medium confidence
4. `^([^S\[]*?)\s*[S\.]\s*(\d{1,2})(?:\s|$|[^\d])` → Variable confidence

### Special Handling
- **Cleanup**: Removes quality indicators (1080p, x264), codecs, release groups
- **Normalization**: Converts dots/underscores to spaces, title-cases, removes years
- **Complete Season Detection**: Checks for "COMPLETE" or "FULL SEASON" in title
- **Multi-Season Detection**: Looks for "S01-S03" or "Season 1 - 3" patterns

## Integration Points

1. **Parsing Trigger**: Happens when TV category selected + magnet entered
2. **Dialog Flow**: Blocking modal allows user to review/edit before adding
3. **Batch Storage**: Metadata persisted with batch item in config.json
4. **Move Worker**: Uses metadata flags (isNewSeries, isNewSeason) during file moves

## Error Handling

- **Parse Failure**: Falls back with error message, user can manually enter
- **Invalid Input**: Required field validation before batch addition
- **Type Validation**: Numbers enforced for season/episode fields
- **Empty Fields**: Series name required, season/episode optional

## Example Scenarios

### Scenario 1: High Confidence Match
```
Input: "Breaking.Bad.S02E05.720p.HDTV.mkv"
→ Parser detects S## E## pattern
→ Confidence: HIGH (✓ green badge)
→ User can submit immediately
```

### Scenario 2: Medium Confidence Complete Season
```
Input: "example.series.2016.s01.complete"
→ Parser detects season + complete flag
→ Confidence: MEDIUM (○ orange badge)
→ Shows "Complete season detected" notification
→ User should verify before submit
```

### Scenario 3: Low Confidence Ambiguous
```
Input: "a.b.c.d.e.f"
→ Parser cannot clearly identify series
→ Confidence: LOW (⚠ red badge)
→ User MUST edit series name field
→ Cannot submit until edited
```

## Dependencies

- **Backend**: Python `re` module for regex parsing
- **Frontend**: Flutter color/badge widgets for confidence display
- **API**: `/api/parse-torrent` endpoint returns metadata JSON

## Testing

**To Test Parsing**:
1. Open ingest screen
2. Enter magnet/title with various formats
3. Switch to TV category
4. Observe parsed metadata
5. Try editing values in dialog
6. Add to batch and verify metadata stored
7. Edit batch item to verify persistence

**Test Cases**:
- ✓ Classic SxxExx format
- ✓ "Series Name Season X" format
- ✓ Complete season packs (S01 COMPLETE)
- ✓ Multi-season packs (S01-S03)
- ✓ Dirty titles with extra artifacts
- ✓ Empty/invalid inputs
- ✓ Year detection and removal
