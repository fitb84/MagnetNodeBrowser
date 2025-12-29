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

  BatchItem({
    required this.id,
    required this.magnet,
    required this.category,
    required this.downloadLocation,
  });

  factory BatchItem.fromMap(Map<String, dynamic> map) {
    final rawCategory = (map['category']?.toString() ?? 'movie').toLowerCase();
    return BatchItem(
      id: map['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      magnet: map['magnet']?.toString() ?? '',
      category: rawCategory == 'show' ? 'tv' : rawCategory,
      downloadLocation: map['downloadLocation']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'magnet': magnet,
        'category': category,
        'downloadLocation': downloadLocation,
      };

  BatchItem copyWith({String? magnet, String? category, String? downloadLocation}) {
    return BatchItem(
      id: id,
      magnet: magnet ?? this.magnet,
      category: category ?? this.category,
      downloadLocation: downloadLocation ?? this.downloadLocation,
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
    bool showToast = false,
  }) async {
    try {
      final created = await ApiClient.addBatchItem(
        magnet: magnet,
        category: category,
        downloadLocation: downloadLocation,
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
    String location = _newLocationController.text.trim();

    final libraryById = _buildLibraryById();
    final seasonHint = _extractSeasonNumber(_extractMagnetDisplayName(magnet) ?? magnet);
    if (category == 'tv') {
      final matchedEntry = _matchSeries(_newSeriesController.text, _tvIndex);
      final suggested = _suggestLocationForEntry(matchedEntry, seasonHint, libraryById);
      if (location.isEmpty && suggested != null) {
        location = suggested;
        _newLocationController.text = suggested;
      }
      if (_newSeriesController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a series name for TV items')),
        );
        return;
      }
    }

    if (location.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a download location before adding')),
      );
      return;
    }

    await _upsertBatchItem(
      magnet: magnet,
      category: category,
      downloadLocation: location,
      showToast: true,
    );
    _magnetController.clear();
    _newSeriesController.clear();
    _newLocationController.clear();
    setState(() => _newCategory = 'movie');
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
    final seasonMatch = RegExp(r'(?i)(season\s*\d{1,2}|S\d{1,2})').firstMatch(cleaned);
    final end = seasonMatch?.start ?? cleaned.length;
    final base = cleaned.substring(0, end).trim();
    if (base.isNotEmpty) return base;
    return cleaned.trim().isEmpty ? null : cleaned.trim();
  }

  int? _extractSeasonNumber(String name) {
    final m1 = RegExp(r'(?i)\bS(\d{1,2})\b').firstMatch(name);
    if (m1 != null) return int.tryParse(m1.group(1) ?? '');
    final m2 = RegExp(r'(?i)\bseason\s*(\d{1,2})\b').firstMatch(name);
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
    final Map<String, Map<String, dynamic>> all = {
      ...{for (final lib in _libraries['movie'] ?? []) (lib['id']?.toString() ?? ''): Map<String, dynamic>.from(lib)},
      ...{for (final lib in _libraries['show'] ?? []) (lib['id']?.toString() ?? ''): Map<String, dynamic>.from(lib)},
    };
    return all;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final libraryById = _buildLibraryById();
    final matchedAddSeries = _matchSeries(_newSeriesController.text, _tvIndex);
    final suggestedAddLocation = _suggestLocationForEntry(
      matchedAddSeries,
      _extractSeasonNumber(_newSeriesController.text),
      libraryById,
    );
    return Scaffold(
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
                        decoration: const InputDecoration(
                          labelText: 'Magnet link',
                          hintText: 'magnet:?xt=urn:btih...',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(label: Text('Movie'), value: 'movie'),
                          ButtonSegment(label: Text('TV Show'), value: 'tv'),
                        ],
                        selected: {_newCategory},
                        onSelectionChanged: (value) {
                          setState(() {
                            _newCategory = value.first;
                            _newSeriesController.clear();
                            _newLocationController.clear();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (_newCategory == 'tv') ...[
                        TextField(
                          controller: _newSeriesController,
                          decoration: InputDecoration(
                            labelText: 'TV Series',
                            hintText: 'Series name (required)',
                            border: const OutlineInputBorder(),
                            suffixIcon: _tvIndexLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.refresh),
                                    tooltip: 'Refresh TV index',
                                    onPressed: _loadTvIndex,
                                  ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        if (_tvIndexError != null)
                          Text('TV index error: $_tvIndexError', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.red)),
                        if (_tvIndex.isNotEmpty) ...[
                          Text(
                            'Quick pick',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blue),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _tvIndex
                                .where((entry) {
                                  final q = _newSeriesController.text.toLowerCase();
                                  if (q.isEmpty) return true;
                                  return (entry['series'] ?? '').toString().toLowerCase().contains(q);
                                })
                                .take(8)
                                .map((entry) => ActionChip(
                                      label: Text(entry['series'] ?? 'Series'),
                                      onPressed: () {
                                        final suggested = _suggestLocationForEntry(entry, _extractSeasonNumber(_newSeriesController.text), libraryById);
                                        setState(() {
                                          _newSeriesController.text = entry['series'] ?? '';
                                          if (suggested != null) _newLocationController.text = suggested;
                                        });
                                      },
                                    ))
                                .toList(),
                          ),
                          const SizedBox(height: 8),
                        ],
                        TextField(
                          controller: _newLocationController,
                          decoration: InputDecoration(
                            labelText: 'TV Folder (required)',
                            hintText: 'Select or enter series folder',
                            border: const OutlineInputBorder(),
                            helperText: suggestedAddLocation != null ? 'Suggested: $suggestedAddLocation' : null,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_libraries['show']?.isNotEmpty == true) ...[
                          Text('Library quick select', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blue)),
                          const SizedBox(height: 6),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _libraries['show']!
                                  .map((lib) => Padding(
                                        padding: const EdgeInsets.only(right: 8.0),
                                        child: OutlinedButton.icon(
                                          onPressed: () {
                                            setState(() {
                                              _newLocationController.text = lib['path'] ?? '';
                                              if (_newSeriesController.text.isEmpty) {
                                                _newSeriesController.text = lib['label'] ?? '';
                                              }
                                            });
                                          },
                                          icon: const Icon(Icons.folder, size: 16),
                                          label: Text(lib['label'] ?? 'Library'),
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ] else ...[
                        TextField(
                          controller: _newLocationController,
                          decoration: const InputDecoration(
                            labelText: 'Download Location (required)',
                            hintText: '/movies or custom path',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_libraries['movie']?.isNotEmpty == true) ...[
                          Text('Library quick select', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blue)),
                          const SizedBox(height: 6),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _libraries['movie']!
                                  .map((lib) => Padding(
                                        padding: const EdgeInsets.only(right: 8.0),
                                        child: OutlinedButton.icon(
                                          onPressed: () {
                                            setState(() {
                                              _newLocationController.text = lib['path'] ?? '';
                                            });
                                          },
                                          icon: const Icon(Icons.folder, size: 16),
                                          label: Text(lib['label'] ?? 'Library'),
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _addToBatch,
                              child: const Text('Add to Batch'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _pasteFromClipboard,
                              child: const Text('Paste'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add downloads to batch, customize each with type and location, then submit.',
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
                final magnetPreview = item.magnet.length > 50
                    ? '${item.magnet.substring(0, 50)}...'
                    : item.magnet;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => _editBatchItem(index),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.category.toUpperCase(),
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: item.category == 'tv' ? Colors.purple : Colors.orange,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                magnetPreview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                                const SizedBox(height: 4),
                                if (item.downloadLocation.isNotEmpty)
                                  Text(
                                    '📁 ${item.downloadLocation}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.blue,
                                    ),
                                  )
                                else
                                  Text(
                                    'Set download location',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
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
      ),
    );
  }
}
