import 'package:flutter/material.dart';
import 'dart:async';
import '../services/api_client.dart';
import '../services/notification_service.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({Key? key}) : super(key: key);

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  late StreamController<List<dynamic>> _downloadsStreamController;
  late Stream<List<dynamic>> _downloadsStream;
  Timer? _pollingTimer;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _downloadsStreamController = StreamController<List<dynamic>>();
    _downloadsStream = _downloadsStreamController.stream.asBroadcastStream();
    _startPolling();
    _checkActiveDownloads();
  }

  void _startPolling() {
    // Initial fetch
    _fetchDownloads();
    
    // Poll every 2 seconds for real-time updates
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _fetchDownloads();
    });
  }

  Future<void> _fetchDownloads() async {
    try {
      final downloads = await ApiClient.getDownloads();
      _downloadsStreamController.add(downloads);
      _lastUpdated = DateTime.now();
    } catch (e) {
      print('Error fetching downloads: $e');
    }
  }

  Future<void> _checkActiveDownloads() async {
    // Periodically check and show notifications for active downloads
    Future.delayed(const Duration(seconds: 5), () async {
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

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _downloadsStreamController.close();
    super.dispose();
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
        _fetchDownloads();
      },
      child: StreamBuilder<List<dynamic>>(
        stream: _downloadsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
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
                    'Add magnets from the Browser tab',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              if (_lastUpdated != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.update, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text(
                        'Live • Updated ${_getTimeSinceUpdate()}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: downloads.length,
                  itemBuilder: (context, index) {
                    final dl = downloads[index] as Map<String, dynamic>;
                    final state = dl['state'] as String? ?? 'unknown';
                    final progress = (dl['progress'] as num?)?.toDouble() ?? 0.0;
                    final ratio = dl['ratio'] as num? ?? 0;
                    final numSeeds = dl['num_seeds'] ?? 0;
                    final numLeechs = dl['num_leechs'] ?? 0;
                    final dlSpeed = dl['dlspeed'] ?? '0 B/s';
                    final upSpeed = dl['upspeed'] ?? '0 B/s';

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
                                                _fetchDownloads();
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
                                minHeight: 8,
                                backgroundColor: Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${(progress * 100).toStringAsFixed(1)}% • ${_formatBytes(dl['downloaded'] as num? ?? 0)} / ${_formatBytes(dl['size'] as num? ?? 0)}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                                Text(
                                  'ETA: ${dl['eta'] ?? '∞'}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.grey[400],
                                      ),
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
                                    Text(
                                      '↓ $dlSpeed',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Colors.blue,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                    Text(
                                      '↑ $upSpeed',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: Colors.green,
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Ratio: ${ratio.toStringAsFixed(2)}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                          child: Text(
                                            '🌱 $numSeeds',
                                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                  color: Colors.green,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                          child: Text(
                                            '🔻 $numLeechs',
                                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                  color: Colors.orange,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getTimeSinceUpdate() {
    if (_lastUpdated == null) return 'never';
    final diff = DateTime.now().difference(_lastUpdated!);
    if (diff.inSeconds < 60) {
      return '${diff.inSeconds}s ago';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else {
      return '${diff.inHours}h ago';
    }
  }

  String _formatBytes(num bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int suffixIndex = 0;

    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }

    return '${size.toStringAsFixed(2)} ${suffixes[suffixIndex]}';
  }}