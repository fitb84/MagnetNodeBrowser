import 'package:flutter/material.dart';
import '../services/api_client.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<Map<String, dynamic>> _librariesFuture;

  @override
  void initState() {
    super.initState();
    _librariesFuture = ApiClient.getLibraries();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _librariesFuture = ApiClient.getLibraries();
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
              Text(
                'Movies (${movies.length})',
                style: Theme.of(context).textTheme.titleMedium,
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
              Text(
                'TV Shows (${shows.length})',
                style: Theme.of(context).textTheme.titleMedium,
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
            ],
          );
        },
      ),
    );
  }
}
