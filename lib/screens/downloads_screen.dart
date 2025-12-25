import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/notification_service.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({Key? key}) : super(key: key);

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  late Future<List<dynamic>> _downloadsFuture;

  @override
  void initState() {
    super.initState();
    _downloadsFuture = ApiClient.getDownloads();
    _checkActiveDownloads();
  }

  Future<void> _checkActiveDownloads() async {
    // Periodically check and show notifications for active downloads
    Future.delayed(const Duration(seconds: 2), () async {
      try {
        final downloads = await ApiClient.getDownloads();
        for (var dl in downloads) {
          final state = dl['state'] as String? ?? 'unknown';
          if (state == 'downloading') {
            // Show notification for active downloads
            final speed = dl['dlspeed'] ?? '0 B/s';
            await NotificationService.showDownloadNotification(
              id: dl['hash'].hashCode,
              title: 'Downloading: ${dl['name']}',
              body: 'Speed: $speed',
            );
          }
        }
      } catch (e) {
        // Silently fail
      }
      if (mounted) {
        _checkActiveDownloads();
      }
    });
  }

  Color _getStateColor(String state) {
    switch (state) {
      case 'completed':
        return Colors.green;
      case 'downloading':
        return Colors.blue;
      case 'stalled':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _downloadsFuture = ApiClient.getDownloads();
        });
      },
      child: FutureBuilder<List<dynamic>>(
        future: _downloadsFuture,
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
                    Text('Error', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }

          final downloads = snapshot.data ?? [];

          if (downloads.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_download_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'No Downloads',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add magnets from the Ingest tab',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: downloads.length,
            itemBuilder: (context, index) {
              final dl = downloads[index] as Map<String, dynamic>;
              final state = dl['state'] as String? ?? 'unknown';
              final progress = (dl['progress'] as num?)?.toDouble() ?? 0.0;
              final ratio = dl['ratio'] as num? ?? 0;
              final numSeeds = dl['num_seeds'] ?? 0;
              final numLeechs = dl['num_leechs'] ?? 0;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dl['name'] ?? 'Unknown',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _getStateColor(state).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    state.toUpperCase(),
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: _getStateColor(state),
                                        ),
                                  ),
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
                                  title: const Text('Remove Download'),
                                  content: const Text('Are you sure you want to remove this download?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        ApiClient.removeDownload(dl['hash']).then((_) {
                                          Navigator.pop(context);
                                          setState(() {
                                            _downloadsFuture = ApiClient.getDownloads();
                                          });
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Download removed')),
                                          );
                                        }).catchError((e) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Error: $e')),
                                          );
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
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${(progress * 100).toStringAsFixed(1)}%',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            dl['eta'] ?? '∞',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('↓ ${dl['dlspeed'] ?? '0 B/s'}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blue)),
                              Text('↑ ${dl['upspeed'] ?? '0 B/s'}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green)),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Ratio: ${ratio.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodySmall),
                              Text('🌱 ${numSeeds} / 🔻 ${numLeechs}', style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Location: ${dl['save_path'] ?? 'Unknown'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
