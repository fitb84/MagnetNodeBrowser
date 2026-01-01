import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_client.dart';
import '../services/notification_service.dart';

class IngestScreen extends StatefulWidget {
  const IngestScreen({super.key});

  @override
  State<IngestScreen> createState() => _IngestScreenState();
}
// Batch item model
class BatchItem {
  final String id;
  String magnet;
  String category; // 'tv' or 'movie'
  String downloadLocation;
  Map<String, dynamic>? metadata; // Torrent parsing metadata

  BatchItem({
    required this.id,
    required this.magnet,
    required this.category,
    required this.downloadLocation,
    this.metadata,
  });

  factory BatchItem.fromMap(Map<String, dynamic> map) {
    final rawCategory = (map['category']?.toString() ?? 'movie').toLowerCase();
    return BatchItem(
      id: map['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      magnet: map['magnet']?.toString() ?? '',
      category: rawCategory == 'show' ? 'tv' : rawCategory,
      downloadLocation: map['downloadLocation']?.toString() ?? '',
      metadata: map['metadata'] is Map ? Map<String, dynamic>.from(map['metadata'] as Map) : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'magnet': magnet,
        'category': category,
        'downloadLocation': downloadLocation,
        if (metadata != null) 'metadata': metadata,
      };

  BatchItem copyWith({String? magnet, String? category, String? downloadLocation, Map<String, dynamic>? metadata}) {
    return BatchItem(
      id: id,
      magnet: magnet ?? this.magnet,
      category: category ?? this.category,
      downloadLocation: downloadLocation ?? this.downloadLocation,
      metadata: metadata ?? this.metadata,
    );
  }
}

class _IngestScreenState extends State<IngestScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const platform = MethodChannel('com.example.magnetnodebrowser/magnet');

  final _magnetController = TextEditingController();
  final _newSeriesController = TextEditingController();
  final _newLocationController = TextEditingController();
  String _newCategory = 'movie';
  List<BatchItem> _batch = [];
  bool _batchLoading = false;
  String? _batchError;
  bool _submitting = false;
  List<Map<String, dynamic>> _tvIndex = [];
  bool _tvIndexLoading = false;
  String? _tvIndexError;
  Map<String, List<Map<String, dynamic>>> _libraries = {'movie': [], 'show': []};
  bool _librariesLoading = false;
  String? _librariesError;

  @override
  void initState() {
    super.initState();
    _checkIncomingMagnetLink();
    _loadTvIndex();
    _loadLibraries();
    _loadPersistentBatch();
    platform.setMethodCallHandler((call) async {
      if (call.method == 'addToBatch') {
        final magnetLink = call.arguments['magnet'] as String?;
        if (magnetLink != null && mounted) {
          _showMagnetLinkModal(magnetLink);
        }
      }
      return null;
    });
  }

  @override
  void dispose() {
    _magnetController.dispose();
    _newSeriesController.dispose();
    _newLocationController.dispose();
    super.dispose();
  }

  Future<void> _loadTvIndex({bool refresh = false}) async {
    if (_tvIndex.isNotEmpty && !refresh) return;
    setState(() {
      _tvIndexLoading = true;
      _tvIndexError = null;
    });
    try {
      final index = await ApiClient.getTvIndex(refresh: refresh);
      if (!mounted) return;
      setState(() {
        _tvIndex = index;
        _tvIndexLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tvIndexError = e.toString();
        _tvIndexLoading = false;
      });
    }
  }

  Future<void> _loadPersistentBatch() async {
    setState(() {
      _batchLoading = true;
      _batchError = null;
    });
    try {
      final items = await ApiClient.getBatchItems();
      if (!mounted) return;
      setState(() {
        _batch = items.map(BatchItem.fromMap).toList();
        _batchLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _batchError = e.toString();
        _batchLoading = false;
      });
    }
  }

  Future<void> _loadLibraries() async {
    setState(() {
      _librariesLoading = true;
      _librariesError = null;
    });
    try {
      final libs = await ApiClient.getLibraries();
      if (!mounted) return;
      setState(() {
        _libraries = {
          'movie': (libs['movie'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
          'show': (libs['show'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        };
        _librariesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _librariesError = e.toString();
        _librariesLoading = false;
      });
    }
  }

  Future<void> _checkIncomingMagnetLink() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.startsWith('magnet:')) {
        setState(() {
          _magnetController.text = text;
        });
      }
    } catch (_) {}
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) return;
      setState(() {
        _magnetController.text = text;
      });
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read clipboard')),
      );
    }
  }
  Future<void> _upsertBatchItem({
    required String magnet,
    String category = 'movie',
    String downloadLocation = '',
    Map<String, dynamic>? metadata,
    bool showToast = false,
  }) async {
    try {
      final created = await ApiClient.addBatchItem(
        magnet: magnet,
        category: category,
        downloadLocation: downloadLocation,
        metadata: metadata,
      );
      if (!mounted) return;
      setState(() {
        _batch = [
          ..._batch.where(
            (b) => b.id != (created['id']?.toString() ?? '') && b.magnet != magnet,
          ),
          BatchItem.fromMap(created),
        ];
      });
      if (showToast && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to batch (saved)')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save batch item: $e')),
      );
    }
  }

  Future<void> _parseTorrentAndAdd(String magnet, String category) async {
    try {
      final displayName = _extractMagnetDisplayName(magnet) ?? magnet;
      final result = await ApiClient.parseAndMatch(displayName, category);
      
      if (!mounted) return;
      
      final metadata = result['metadata'] as Map<String, dynamic>?;
      final folderOptions = (result['folderOptions'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
      
      // If parsing succeeded and we have series_name, show the dialog
      if (metadata != null && metadata['series_name'] != null) {
        _showTorrentParsingDialog(magnet, category, metadata, folderOptions);
        return;
      }
      
      // Fallback: Parse the name from magnet display name and show dialog for manual entry
      final fallbackSeriesName = displayName
          .replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '')  // Remove file extensions
          .replaceAll(RegExp(r'[._-]'), ' ')  // Replace separators with spaces
          .trim();
      
      final fallbackMetadata = {
        'series_name': fallbackSeriesName.isNotEmpty ? fallbackSeriesName : 'Unknown',
        'season_number': null,
        'episode_number': null,
        'is_complete_season': false,
        'is_multi_season': false,
        'confidence': 'low',
        'suggested_folder': null,
      };
      
      // Show dialog with fallback metadata so user can edit
      if (mounted) {
        _showTorrentParsingDialog(magnet, category, fallbackMetadata, folderOptions);
      }
    } catch (e) {
      if (!mounted) return;
      
      // Even on error, try to extract name from magnet for fallback
      final displayName = _extractMagnetDisplayName(magnet) ?? magnet;
      final fallbackSeriesName = displayName
          .replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '')
          .replaceAll(RegExp(r'[._-]'), ' ')
          .trim();
      
      final fallbackMetadata = {
        'series_name': fallbackSeriesName.isNotEmpty ? fallbackSeriesName : 'Unknown',
        'season_number': null,
        'episode_number': null,
        'is_complete_season': false,
        'is_multi_season': false,
        'confidence': 'low',
        'suggested_folder': null,
      };
      
      if (mounted) {
        _showTorrentParsingDialog(magnet, category, fallbackMetadata, []);
      }
    }
  }

  Future<void> _showTorrentParsingDialog(
    String magnet, 
    String category, 
    Map<String, dynamic> metadata, 
    List<Map<String, dynamic>> folderOptions
  ) async {
    bool isNewSeries = false;
    bool isNewSeason = false;
    late TextEditingController seriesController;
    late TextEditingController seasonController;
    late TextEditingController episodeController;
    String? selectedFolder;
    
    final confidence = metadata['confidence'] as String? ?? 'medium';
    final confidenceColor = confidence == 'high' 
        ? Colors.green 
        : confidence == 'medium' 
            ? Colors.orange 
            : Colors.red;
    
    seriesController = TextEditingController(text: metadata['series_name'] ?? '');
    seasonController = TextEditingController(
      text: metadata['season_number'] != null ? '${metadata['season_number']}' : '',
    );
    episodeController = TextEditingController(
      text: metadata['episode_number'] != null ? '${metadata['episode_number']}' : '',
    );
    
    if (!mounted) return;
    
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(category == 'tv' ? 'TV Show Details' : 'Movie Details'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: confidenceColor.withOpacity(0.2),
                      border: Border.all(color: confidenceColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Confidence: ${confidence[0].toUpperCase()}${confidence.substring(1)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: confidenceColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Series Name', style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(
                  controller: seriesController,
                  decoration: const InputDecoration(
                    hintText: 'Enter series name',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(8),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Season', style: TextStyle(fontWeight: FontWeight.bold)),
                          TextField(
                            controller: seasonController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: 'e.g. 1',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.all(8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Episode', style: TextStyle(fontWeight: FontWeight.bold)),
                          TextField(
                            controller: episodeController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: 'e.g. 1',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.all(8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Folder options from Emby
                if (folderOptions.isNotEmpty) ...[
                  const Text('Destination Folder', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...folderOptions.map((option) {
                    final path = option['path'] as String? ?? '';
                    final label = option['label'] as String? ?? path;
                    final isSelected = selectedFolder == path;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => setState(() => selectedFolder = path),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.transparent,
                            border: Border.all(
                              color: isSelected ? Colors.blue : Colors.grey.withOpacity(0.3),
                              width: isSelected ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                color: isSelected ? Colors.blue : Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    Text(
                                      path,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 16),
                ],
                if (metadata['is_complete_season'] == true)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      border: Border.all(color: Colors.blue),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue, size: 18),
                        SizedBox(width: 8),
                        Expanded(child: Text('Complete season detected', style: TextStyle(fontSize: 12))),
                      ],
                    ),
                  ),
                if (metadata['is_multi_season'] == true) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      border: Border.all(color: Colors.blue),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue, size: 18),
                        SizedBox(width: 8),
                        Expanded(child: Text('Multi-season pack detected', style: TextStyle(fontSize: 12))),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text('Is this a new series?'),
                CheckboxListTile(
                  value: isNewSeries,
                  onChanged: (val) => setState(() => isNewSeries = val ?? false),
                  title: const Text('Yes, new series'),
                  contentPadding: EdgeInsets.zero,
                ),
                if (seasonController.text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Is this a new season?'),
                  CheckboxListTile(
                    value: isNewSeason,
                    onChanged: (val) => setState(() => isNewSeason = val ?? false),
                    title: const Text('Yes, new season'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final seriesName = seriesController.text.trim();
                if (category == 'tv' && seriesName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Series name is required')),
                  );
                  return;
                }
                
                if (folderOptions.isNotEmpty && selectedFolder == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select a destination folder')),
                  );
                  return;
                }
                
                Navigator.pop(context);
                
                int? seasonNum;
                int? episodeNum;
                
                try {
                  if (seasonController.text.isNotEmpty) {
                    seasonNum = int.parse(seasonController.text);
                  }
                  if (episodeController.text.isNotEmpty) {
                    episodeNum = int.parse(episodeController.text);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Season and episode must be numbers')),
                    );
                  }
                  return;
                }
                
                // Proceed to add with edited metadata
                await _upsertBatchItem(
                  magnet: magnet,
                  category: category,
                  downloadLocation: selectedFolder ?? '',
                  metadata: {
                    ...metadata,
                    'series_name': seriesName,
                    'season_number': seasonNum,
                    'episode_number': episodeNum,
                    'isNewSeries': isNewSeries,
                    'isNewSeason': isNewSeason,
                  },
                  showToast: true,
                );
                
                // Clear magnet field after successful add
                if (mounted) {
                  _magnetController.clear();
                }
              },
              child: const Text('Add to Batch'),
            ),
          ],
        ),
      ),
    );
    
    seriesController.dispose();
    seasonController.dispose();
    episodeController.dispose();
  }

  Future<void> _addToBatch() async {
    final magnet = _magnetController.text.trim();
    if (magnet.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a magnet link')),
      );
      return;
    }

    if (!magnet.startsWith('magnet:')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid magnet link')),
      );
      return;
    }
    
    final category = _newCategory;

    // Always parse and match for both TV and movies
    await _parseTorrentAndAdd(magnet, category);
    
    // Clear fields after adding
    _magnetController.clear();
    _newSeriesController.clear();
    _newLocationController.clear();
  }

  Future<void> _removeBatchItem(int index) async {
    final item = _batch[index];
    setState(() => _batch.removeAt(index));
    try {
      await ApiClient.deleteBatchItem(item.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
      await _loadPersistentBatch();
    }
  }

  Future<void> _editBatchItem(int index) async {
    try {
      final item = _batch[index];
      await _loadTvIndex();
      final result = await _showBatchItemEditDialog(item, index);
      if (result != null) {
        try {
          final saved = await ApiClient.updateBatchItem(
            id: result.id,
            magnet: result.magnet,
            category: result.category,
            downloadLocation: result.downloadLocation,
          );
          if (!mounted) return;
          setState(() {
            _batch[index] = BatchItem.fromMap(saved);
          });
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update: $e')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open editor: $e')),
      );
    }
  }

  Future<BatchItem?> _showBatchItemEditDialog(BatchItem item, int index) async {
    String category = item.category;
    final locationController = TextEditingController(text: item.downloadLocation);
    final tvSeriesController = TextEditingController();
    List<Map<String, dynamic>> libraries = [];
    Map<String, Map<String, dynamic>> libraryById = {};
    String? validationError;
    
    // Fetch libraries
    try {
      final libData = await ApiClient.getLibraries();
      final categoryLibs = category == 'movie' ? libData['movie'] : libData['show'];
      libraries = List<Map<String, dynamic>>.from(categoryLibs ?? []);
      libraryById = {
        for (final lib in libraries) (lib['id']?.toString() ?? ''): lib,
      };
    } catch (e) {
      print('Error loading libraries: $e');
    }
    

    final magnetName = _extractMagnetDisplayName(item.magnet) ?? item.magnet;
    final parsedSeason = _extractSeasonNumber(magnetName);
    final parsedSeries = _guessSeriesName(magnetName);
    if (parsedSeries != null && tvSeriesController.text.isEmpty) {
      tvSeriesController.text = parsedSeries;
    }
    final initialMatch = _matchSeries(tvSeriesController.text, _tvIndex);
    final initialSuggested = initialMatch != null
        ? _suggestLocationForEntry(initialMatch, parsedSeason, libraryById)
        : null;
    if (initialSuggested != null && locationController.text.isEmpty) {
      locationController.text = initialSuggested;
    }
    
    return showDialog<BatchItem>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Download Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Magnet: ${item.magnet.length > 60 ? item.magnet.substring(0, 60) + '...' : item.magnet}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                
                // Category selector
                Text('Type:', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(label: Text('Movie'), value: 'movie'),
                          ButtonSegment(label: Text('TV Show'), value: 'tv'),
                        ],
                        selected: {category},
                        onSelectionChanged: (value) async {
                          setState(() => category = value.first);
                          locationController.clear();
                          
                          // Reload libraries for new category
                          try {
                            final libData = await ApiClient.getLibraries();
                            final categoryLibs = category == 'movie' ? libData['movie'] : libData['show'];
                            setState(() {
                              libraries = List<Map<String, dynamic>>.from(categoryLibs ?? []);
                            });
                          } catch (e) {
                            print('Error loading libraries: $e');
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Location input
                if (category == 'movie') ...[
                  Text('Download Location:', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 8),
                  
                  // Movie library suggestions
                  if (libraries.isNotEmpty) ...[
                    Text('Quick Select:', style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.blue,
                    )),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: libraries.map((lib) {
                        return ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              locationController.text = lib['path'] ?? '';
                            });
                          },
                          icon: const Icon(Icons.folder, size: 16),
                          label: Text(
                            lib['label'] ?? 'Library',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            backgroundColor: const Color(0xFF222222),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  TextField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Download Location (optional)',
                      hintText: '/movies or custom path',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ] else ...[
                  // TV show folder picker
                  Text('TV Series Folder:', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 8),
                  if (_tvIndexLoading) ...[
                    Row(
                      children: const [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Loading local TV index...'),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ] else if (_tvIndexError != null) ...[
                    Text('Index error: $_tvIndexError', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red)),
                    TextButton(
                      onPressed: () => _loadTvIndex(refresh: true),
                      child: const Text('Retry index load'),
                    ),
                  ] else if (_tvIndex.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Smart suggestions', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blue)),
                        TextButton(
                          onPressed: () => _loadTvIndex(refresh: true),
                          child: const Text('Refresh index'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _tvIndex
                          .where((entry) {
                            final query = tvSeriesController.text.toLowerCase();
                            if (query.isEmpty) return true;
                            return (entry['series'] ?? '').toString().toLowerCase().contains(query);
                          })
                          .take(8)
                          .map((entry) {
                            return ActionChip(
                              label: Text(entry['series'] ?? 'Series'),
                              onPressed: () {
                                final suggested = _suggestLocationForEntry(entry, parsedSeason, libraryById);
                                setState(() {
                                  tvSeriesController.text = entry['series'] ?? '';
                                  if (suggested != null) {
                                    locationController.text = suggested;
                                  }
                                });
                              },
                            );
                          }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  // TV show library quick select
                  if (libraries.isNotEmpty) ...[
                    Text('Quick Select Series Folder:', style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.blue,
                    )),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: libraries.map((lib) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  locationController.text = lib['path'] ?? '';
                                  tvSeriesController.text = lib['label'] ?? '';
                                });
                              },
                              icon: const Icon(Icons.folder, size: 16),
                              label: Text(
                                lib['label'] ?? 'Series',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                backgroundColor: const Color(0xFF222222),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  TextField(
                    controller: tvSeriesController,
                    decoration: const InputDecoration(
                      labelText: 'Series Name',
                      hintText: 'e.g., Breaking Bad',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final matchedEntry = _matchSeries(tvSeriesController.text, _tvIndex);
                      final suggested = _suggestLocationForEntry(matchedEntry, parsedSeason, libraryById);
                      final fallback = tvSeriesController.text.isEmpty
                          ? '/tv/Series Name'
                          : '/tv/${tvSeriesController.text}';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '📁 Suggested location:',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.blue,
                            ),
                          ),
                          Text(
                            suggested ?? fallback,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (matchedEntry != null && (matchedEntry['seasonPaths'] as List?)?.isNotEmpty == true) ...[
                            const SizedBox(height: 8),
                            Text('Season shortcuts:', style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              children: (matchedEntry['seasonPaths'] as List)
                                  .cast<Map>()
                                  .map((season) => ActionChip(
                                        label: Text('S${season['season'].toString().padLeft(2, '0')}'),
                                        onPressed: () {
                                          setState(() {
                                            tvSeriesController.text = matchedEntry['series'] ?? tvSeriesController.text;
                                            locationController.text = season['path']?.toString() ?? locationController.text;
                                          });
                                        },
                                      ))
                                  .toList(),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: locationController,
                    decoration: const InputDecoration(
                      labelText: 'Download Location',
                      hintText: 'Required',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (validationError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(validationError!, style: const TextStyle(color: Colors.red)),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final location = locationController.text.trim();
                final matchedEntry = _matchSeries(tvSeriesController.text, _tvIndex);
                final suggested = _suggestLocationForEntry(matchedEntry, parsedSeason, libraryById);
                final finalLocation = location.isNotEmpty
                    ? location
                    : (category == 'tv' ? (suggested ?? '') : '');
                if (finalLocation.isEmpty) {
                  setState(() {
                    validationError = 'A library location is required';
                  });
                  return;
                }
                
                Navigator.pop(
                  context,
                  BatchItem(
                    id: item.id,
                    magnet: item.magnet,
                    category: category,
                    downloadLocation: finalLocation,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMagnetLinkModal(String magnetLink) async {
    if (!mounted) return;
    await _upsertBatchItem(
      magnet: magnetLink,
      category: 'movie',
      showToast: true,
    );
  }

  Future<void> _submitBatch() async {
    if (_batch.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Batch is empty')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      // Alert backend for each magnet being ingested
      for (final item in _batch) {
        try {
          await ApiClient.alertMagnetIngested(
            magnet: item.magnet,
            targetPath: item.downloadLocation,
            category: item.category,
          );
        } catch (e) {
          print('Warning: Could not alert backend for magnet: $e');
          // Continue even if alert fails - magnet will still be added
        }
      }
      
      final result = await ApiClient.submitBatch();
      final successCount = (result['successCount'] ?? 0) as int;
      final skippedCount = (result['skippedCount'] ?? 0) as int;
      final remainingMaps = (result['remaining'] as List<dynamic>? ?? [])
          .map((e) => BatchItem.fromMap(e as Map<String, dynamic>))
          .toList();

      await NotificationService.showBatchSubmitted(successCount);

      setState(() {
        _batch = remainingMaps;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Submitted $successCount item${successCount == 1 ? '' : 's'}${skippedCount > 0 ? ' • Skipped $skippedCount needing location' : ''}${remainingMaps.isNotEmpty ? ' (pending remain in batch)' : ''}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _submitting = false);
    }
  }

  String? _extractMagnetDisplayName(String magnet) {
    try {
      final uri = Uri.parse(magnet);
      final dn = uri.queryParameters['dn'];
      if (dn != null) return Uri.decodeComponent(dn);
    } catch (_) {}
    return null;
  }

  String _normalizeTitle(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String? _guessSeriesName(String name) {
    final cleaned = name.replaceAll('.', ' ').replaceAll('_', ' ');
    final seasonMatch = RegExp(r'(season\s*\d{1,2}|S\d{1,2})', caseSensitive: false).firstMatch(cleaned);
    final end = seasonMatch?.start ?? cleaned.length;
    final base = cleaned.substring(0, end).trim();
    if (base.isNotEmpty) return base;
    return cleaned.trim().isEmpty ? null : cleaned.trim();
  }

  int? _extractSeasonNumber(String name) {
    final m1 = RegExp(r'\bS(\d{1,2})\b', caseSensitive: false).firstMatch(name);
    if (m1 != null) return int.tryParse(m1.group(1) ?? '');
    final m2 = RegExp(r'\bseason\s*(\d{1,2})\b', caseSensitive: false).firstMatch(name);
    if (m2 != null) return int.tryParse(m2.group(1) ?? '');
    return null;
  }

  Map<String, dynamic>? _matchSeries(String? input, List<Map<String, dynamic>> index) {
    if (input == null || input.isEmpty) return null;
    final normalizedInput = _normalizeTitle(input);
    Map<String, dynamic>? best;
    int bestScore = 0;
    for (final entry in index) {
      final candidate = entry['series']?.toString() ?? '';
      if (candidate.isEmpty) continue;
      final normalizedCandidate = _normalizeTitle(candidate);
      int score = 0;
      if (normalizedCandidate == normalizedInput) {
        score = 100;
      } else if (normalizedCandidate.contains(normalizedInput) || normalizedInput.contains(normalizedCandidate)) {
        score = 80;
      } else if (normalizedCandidate.split(' ').first == normalizedInput.split(' ').first) {
        score = 60;
      }
      if (score > bestScore) {
        bestScore = score;
        best = entry;
      }
    }
    return best;
  }

  String? _suggestLocationForEntry(
    Map<String, dynamic>? entry,
    int? seasonHint,
    Map<String, Map<String, dynamic>> libraryById,
  ) {
    if (entry == null) return null;
    final seasonPaths = (entry['seasonPaths'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (seasonHint != null) {
      final match = seasonPaths.firstWhere(
        (s) => s['season']?.toString() == seasonHint.toString(),
        orElse: () => {},
      );
      if (match.isNotEmpty && (match['path'] ?? '').toString().isNotEmpty) {
        return match['path'].toString();
      }
    }
    if (seasonPaths.isNotEmpty && (seasonPaths.first['path'] ?? '').toString().isNotEmpty) {
      return seasonPaths.first['path'].toString();
    }
    final seriesPath = entry['seriesPath']?.toString();
    if (seriesPath != null && seriesPath.isNotEmpty) return seriesPath;

    final libKey = entry['libraryId']?.toString();
    if (libKey != null && libraryById.containsKey(libKey)) {
      final libPath = libraryById[libKey]?['path']?.toString();
      if (libPath != null && libPath.isNotEmpty) return libPath;
    }
    return null;
  }

  Map<String, Map<String, dynamic>> _buildLibraryById() {
    final Map<String, Map<String, dynamic>> all = {};
    for (final lib in _libraries['movie'] ?? []) {
      final key = lib['id']?.toString() ?? '';
      all[key] = Map<String, dynamic>.from(lib);
    }
    for (final lib in _libraries['show'] ?? []) {
      final key = lib['id']?.toString() ?? '';
      all[key] = Map<String, dynamic>.from(lib);
    }
    return all;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    // Wrap entire build in error handling
    try {
      final libraryById = _buildLibraryById();
      final matchedAddSeries = _matchSeries(_newSeriesController.text, _tvIndex);
      final suggestedAddLocation = _suggestLocationForEntry(
        matchedAddSeries,
        _extractSeasonNumber(_newSeriesController.text),
        libraryById,
      );
      
      return Scaffold(
        appBar: AppBar(
          title: const Text('Ingest'),
          actions: [
            if (_batchLoading)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Add Magnet Link', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _magnetController,
                        decoration: InputDecoration(
                          labelText: 'Magnet link',
                          hintText: 'Paste magnet link here...',
                          border: const OutlineInputBorder(),
                          helperText: 'We\'ll auto-detect the content and suggest folders',
                          suffixIcon: _magnetController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() => _magnetController.clear());
                                  },
                                )
                              : null,
                        ),
                        maxLines: 3,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(label: Text('Movie'), value: 'movie'),
                          ButtonSegment(label: Text('TV Show'), value: 'tv'),
                        ],
                        selected: {_newCategory},
                        onSelectionChanged: (value) {
                          setState(() => _newCategory = value.first);
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _addToBatch,
                              icon: const Icon(Icons.add),
                              label: const Text('Parse & Add to Batch'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            onPressed: _pasteFromClipboard,
                            icon: const Icon(Icons.content_paste),
                            tooltip: 'Paste from clipboard',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Paste your magnet link, select category, and we\'ll parse the content and match it with your library.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Batch Queue (${_batch.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (_batchLoading) ...[
                Row(
                  children: const [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Syncing saved batch...'),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (_batchError != null) ...[
                Text(
                  'Batch sync failed: $_batchError',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red),
                ),
                TextButton(
                  onPressed: _loadPersistentBatch,
                  child: const Text('Retry'),
                ),
              ],
              ..._batch.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                // Parse display name from magnet link
                final displayName = _extractMagnetDisplayName(item.magnet) ?? 
                    (item.magnet.length > 60 ? '${item.magnet.substring(0, 60)}...' : item.magnet);
                final locationParts = item.downloadLocation.split(RegExp(r'[/\\]'));
                final locationDisplay = locationParts.isNotEmpty && item.downloadLocation.isNotEmpty
                    ? locationParts.last 
                    : null;
                
                // Get confidence level from metadata if available
                final metadata = item.metadata as Map<String, dynamic>? ?? {};
                final confidence = metadata['confidence'] as String? ?? '';
                final confidenceColor = confidence == 'high' 
                    ? Colors.green 
                    : confidence == 'medium' 
                        ? Colors.orange 
                        : confidence == 'low'
                            ? Colors.red
                            : Colors.transparent;
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: item.downloadLocation.isEmpty 
                          ? Colors.red.withOpacity(0.3) 
                          : Colors.grey.withOpacity(0.2),
                    ),
                  ),
                  child: InkWell(
                    onTap: () => _editBatchItem(index),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Category badge and confidence indicator
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: item.category == 'tv' 
                                            ? Colors.purple.withOpacity(0.2) 
                                            : Colors.orange.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        item.category == 'tv' ? 'TV SHOW' : 'MOVIE',
                                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: item.category == 'tv' ? Colors.purple[300] : Colors.orange[300],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Confidence indicator
                                    if (confidence.isNotEmpty && item.category == 'tv')
                                      Tooltip(
                                        message: 'Parsing confidence: ${confidence[0].toUpperCase()}${confidence.substring(1)}',
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: confidenceColor.withOpacity(0.2),
                                            border: Border.all(color: confidenceColor, width: 1),
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                          child: Text(
                                            confidence == 'high' ? '✓' : confidence == 'medium' ? '○' : '⚠',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: confidenceColor,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                // Display name
                                Text(
                                  displayName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // Metadata display if available
                                if (item.category == 'tv' && metadata['series_name'] != null) ...[
                                  Text(
                                    'Series: ${metadata['series_name'] ?? 'Unknown'}' +
                                        (metadata['season_number'] != null ? ' • S${metadata['season_number'].toString().padLeft(2, '0')}' : '') +
                                        (metadata['episode_number'] != null ? 'E${metadata['episode_number'].toString().padLeft(2, '0')}' : ''),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.blue[300],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                // Location info
                                if (item.downloadLocation.isNotEmpty)
                                  Row(
                                    children: [
                                      Icon(Icons.folder, size: 14, color: Colors.blue[300]),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          locationDisplay ?? item.downloadLocation,
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Colors.blue[300],
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Row(
                                    children: [
                                      Icon(Icons.warning_amber, size: 14, color: Colors.red[300]),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Tap to set location',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Colors.red[300],
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: Tooltip(
                              message: 'Edit',
                              child: IconButton(
                                icon: const Icon(Icons.edit, color: Colors.orange),
                                onPressed: () => _editBatchItem(index),
                                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: Tooltip(
                              message: 'Delete',
                              child: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _removeBatchItem(index),
                                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting || _batch.isEmpty ? null : _submitBatch,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit Batch'),
                ),
              ),
            ],
          ),
        ),
      ));
    } catch (e, stack) {
      // Show error screen if build fails
      print('Ingest screen build error: $e');
      print('Stack: $stack');
      return Scaffold(
        appBar: AppBar(
          title: const Text('Ingest - Error'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load Ingest screen',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Error: $e',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      // Force rebuild
                    });
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }
}
