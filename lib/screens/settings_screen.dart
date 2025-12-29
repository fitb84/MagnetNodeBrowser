import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_client.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;
  String? _testResult;
  bool _isTesting = false;
  int _selectedTab = 0;

  late Future<Map<String, dynamic>> _librariesFuture;
  late Future<List<Map<String, dynamic>>> _tvIndexFuture;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: ApiClient.baseUrl);
    _librariesFuture = ApiClient.getLibraries();
    _tvIndexFuture = ApiClient.getTvIndex();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final stats = await ApiClient.getStats();
      setState(() {
        _testResult = 'Connected! Stats: ${stats.keys.join(', ')}';
        _isTesting = false;
      });
    } catch (e) {
      setState(() {
        _testResult = 'Connection Error: $e';
        _isTesting = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    final newUrl = _urlController.text.trim();
    if (newUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL cannot be empty')),
      );
      return;
    }

    ApiClient.setBaseUrl(newUrl);
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('API URL updated to: $newUrl')),
    );
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }

  Future<void> _refreshTvIndex({bool rescan = false}) async {
    setState(() {
      _tvIndexFuture = ApiClient.getTvIndex(refresh: rescan);
    });
  }

  Future<void> _openIndexEditor({Map<String, dynamic>? entry}) async {
    final seriesController = TextEditingController(text: entry?['series'] ?? '');
    final pathController = TextEditingController(text: entry?['seriesPath'] ?? '');
    final existingSeasonPaths = (entry?['seasonPaths'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final seasonsController = TextEditingController(
      text: existingSeasonPaths.isEmpty
          ? ''
          : existingSeasonPaths.map((e) => e['season']?.toString() ?? '').where((e) => e.isNotEmpty).join(', '),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry == null ? 'Add TV Index Entry' : 'Edit TV Index Entry'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: seriesController,
                decoration: const InputDecoration(labelText: 'Series Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pathController,
                decoration: const InputDecoration(labelText: 'Series Path', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: seasonsController,
                decoration: const InputDecoration(
                  labelText: 'Seasons (comma separated, optional)',
                  hintText: 'e.g., 1, 2, 3',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved != true) return;

    final series = seriesController.text.trim();
    final path = pathController.text.trim();
    if (series.isEmpty || path.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Series and path are required')),
      );
      return;
    }

    final seasons = seasonsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map(int.tryParse)
        .whereType<int>()
        .toList();

    final updatedSeasonPaths = seasons
        .map((s) {
          final existing = existingSeasonPaths.firstWhere(
            (p) => p['season']?.toString() == s.toString(),
            orElse: () => <String, dynamic>{},
          );
          return {
            'season': s,
            'path': existing['path'] ?? path,
          };
        })
        .toList();

    try {
      if (entry == null) {
        await ApiClient.addTvIndexEntry(
          series: series,
          seriesPath: path,
          seasonPaths: updatedSeasonPaths,
        );
      } else {
        await ApiClient.updateTvIndexEntry(entry['id'], {
          'series': series,
          'seriesPath': path,
          'seasonPaths': updatedSeasonPaths,
        });
      }
      if (mounted) {
        await _refreshTvIndex();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Index saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _deleteIndexEntry(String entryId) async {
    try {
      await ApiClient.deleteTvIndexEntry(entryId);
      await _refreshTvIndex();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Entry removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _showAddLibraryDialog(String category) async {
    final pathController = TextEditingController();
    final labelController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add ${category == 'movie' ? 'Movie' : 'TV Show'} Library'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pathController,
                decoration: const InputDecoration(
                  labelText: 'Library Path',
                  hintText: 'e.g., D:\\Movies or /mnt/media/movies',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'Label (optional)',
                  hintText: 'e.g., Primary Movies',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final path = pathController.text.trim();
              if (path.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Path cannot be empty')),
                );
                return;
              }

              try {
                await ApiClient.addLibrary(
                  category,
                  path,
                  labelController.text.trim(),
                );
                if (mounted) {
                  Navigator.pop(context);
                  setState(() {
                    _librariesFuture = ApiClient.getLibraries();
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✓ Library added successfully')),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF181818),
      ),
      backgroundColor: const Color(0xFF111111),
      body: _selectedTab == 0
          ? _buildAPISettings()
          : _buildLibrarySettings(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTab,
        onTap: (index) => setState(() => _selectedTab = index),
        backgroundColor: const Color(0xFF181818),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.api), label: 'API'),
          BottomNavigationBarItem(icon: Icon(Icons.folder), label: 'Libraries'),
        ],
      ),
    );
  }

  Widget _buildAPISettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'API Configuration',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFFffffff),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            style: const TextStyle(color: Color(0xFFffffff)),
            decoration: InputDecoration(
              hintText: 'http://ip:port',
              hintStyle: const TextStyle(color: Color(0xFFbbbbbb)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF222222)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF222222)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFff3b3b)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveSettings,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFff3b3b),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Save'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isTesting ? null : _testConnection,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF222222),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: _isTesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Test'),
                ),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _testResult!.contains('Connected')
                    ? Colors.green.withOpacity(0.2)
                    : Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _testResult!.contains('Connected')
                      ? Colors.green
                      : Colors.red,
                ),
              ),
              child: Text(
                _testResult!,
                style: TextStyle(
                  color: _testResult!.contains('Connected')
                      ? Colors.green
                      : Colors.red,
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
          const Text(
            'Current Configuration',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFFffffff),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              border: Border.all(color: const Color(0xFF222222)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'API Base URL',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFbbbbbb),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            ApiClient.baseUrl,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFFffffff),
                              fontFamily: 'Courier',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Color(0xFFff3b3b)),
                      onPressed: () => _copyToClipboard(ApiClient.baseUrl),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Troubleshooting',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFFbbbbbb),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '• Ensure the backend is running and accessible\n'
            '• Check that Tailscale is connected\n'
            '• Verify the IP and port are correct\n'
            '• Use the Test button to check connectivity',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFbbbbbb),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibrarySettings() {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _librariesFuture = ApiClient.getLibraries();
          _tvIndexFuture = ApiClient.getTvIndex(refresh: true);
        });
      },
      child: FutureBuilder<Map<String, dynamic>>(
        future: _librariesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Error loading libraries', style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
              ),
            );
          }

          final libraries = snapshot.data ?? {};
          final movies = List<Map<String, dynamic>>.from(libraries['movie'] ?? []);
          final shows = List<Map<String, dynamic>>.from(libraries['show'] ?? []);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Library Configuration',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Movies (${movies.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Color(0xFFff3b3b)),
                    onPressed: () => _showAddLibraryDialog('movie'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...movies.map((lib) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lib['label'] ?? 'Unknown',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                lib['path'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Free: ${(lib['availableSpace'] ?? 0).toStringAsFixed(1)} GB / Total: ${(lib['totalSpace'] ?? 0).toStringAsFixed(1)} GB',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blue),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Remove Library'),
                                content: Text('Remove ${lib['label']}?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      ApiClient.removeLibrary('movie', lib['id']).then((_) {
                                        Navigator.pop(context);
                                        setState(() {
                                          _librariesFuture = ApiClient.getLibraries();
                                        });
                                      });
                                    },
                                    child: const Text('Remove', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TV Shows (${shows.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Color(0xFFff3b3b)),
                    onPressed: () => _showAddLibraryDialog('show'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...shows.map((lib) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lib['label'] ?? 'Unknown',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                lib['path'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Free: ${(lib['availableSpace'] ?? 0).toStringAsFixed(1)} GB / Total: ${(lib['totalSpace'] ?? 0).toStringAsFixed(1)} GB',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blue),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Remove Library'),
                                content: Text('Remove ${lib['label']}?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      ApiClient.removeLibrary('show', lib['id']).then((_) {
                                        Navigator.pop(context);
                                        setState(() {
                                          _librariesFuture = ApiClient.getLibraries();
                                        });
                                      });
                                    },
                                    child: const Text('Remove', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TV Library Index',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => _refreshTvIndex(rescan: true),
                        child: const Text('Rescan'),
                      ),
                      const SizedBox(width: 4),
                      ElevatedButton(
                        onPressed: () => _openIndexEditor(),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF222222)),
                        child: const Text('Add Entry'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _tvIndexFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Index error: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                        TextButton(
                          onPressed: () => _refreshTvIndex(),
                          child: const Text('Retry'),
                        ),
                      ],
                    );
                  }
                  final entries = snapshot.data ?? [];
                  if (entries.isEmpty) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('No cached series yet.'),
                        TextButton(
                          onPressed: () => _refreshTvIndex(rescan: true),
                          child: const Text('Scan Libraries'),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: entries.map((entry) {
                      final seasons = (entry['seasonPaths'] as List?)?.length ?? 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(entry['series'] ?? 'Series'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(entry['seriesPath'] ?? ''),
                              Text('Seasons tracked: $seasons'),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.orange),
                                onPressed: () => _openIndexEditor(entry: entry),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () => _deleteIndexEntry(entry['id'] ?? ''),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
