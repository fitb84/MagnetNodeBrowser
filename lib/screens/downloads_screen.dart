import 'package:flutter/material.dart';
import '../services/api_client.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({Key? key}) : super(key: key);

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _downloads = [];
  List<dynamic> _completed = [];
  bool _isLoading = true;
  String? _error;
  String _sortBy = 'status';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final downloads = await ApiClient.getDownloads();
      final completed = await ApiClient.getCompleted();
      setState(() {
        _downloads = downloads;
        _completed = _sortCompleted(completed);
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<dynamic> _sortCompleted(List<dynamic> items) {
    final sorted = List<dynamic>.from(items);
    if (_sortBy == 'status') {
      sorted.sort((a, b) {
        final aStatus = (a['seed_status'] ?? '').toString();
        final bStatus = (b['seed_status'] ?? '').toString();
        return aStatus.compareTo(bStatus);
      });
    } else if (_sortBy == 'name') {
      sorted.sort((a, b) {
        final aName = (a['name'] ?? '').toString();
        final bName = (b['name'] ?? '').toString();
        return aName.compareTo(bName);
      });
    } else if (_sortBy == 'size') {
      sorted.sort((a, b) {
        final aSize = _parseSizeToBytes(a['size']);
        final bSize = _parseSizeToBytes(b['size']);
        return bSize.compareTo(aSize);
      });
    }
    return sorted;
  }

  int _parseSizeToBytes(dynamic size) {
    if (size == null) return 0;
    final str = size.toString().toLowerCase();
    if (str.contains('gb')) {
      return (double.tryParse(str.replaceAll('gb', '').trim()) ?? 0 * 1024 * 1024 * 1024).toInt();
    } else if (str.contains('mb')) {
      return (double.tryParse(str.replaceAll('mb', '').trim()) ?? 0 * 1024 * 1024).toInt();
    } else if (str.contains('kb')) {
      return (double.tryParse(str.replaceAll('kb', '').trim()) ?? 0 * 1024).toInt();
    }
    return int.tryParse(str.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  void _changeSortOrder(String newSort) {
    setState(() {
      _sortBy = newSort;
      _completed = _sortCompleted(_completed);
    });
  }

  Color _getStateColor(String state) {
    state = state.toLowerCase();
    if (state.contains('download')) return Colors.blue;
    if (state.contains('seed')) return Colors.green;
    if (state.contains('queue') || state.contains('queued')) return Colors.orange;
    if (state.contains('stop') || state.contains('stopped')) return Colors.grey;
    return Colors.grey;
  }

  Color _getSeedStatusColor(String status) {
    status = status.toLowerCase();
    if (status == 'active') return Colors.green;
    if (status == 'standby') return Colors.orange;
    return Colors.grey;
  }

  void _showDeleteDialog(BuildContext context, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Torrent?'),
        content: Text('Remove "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ApiClient.removeDownload(name);
                _loadData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Removed "$name"')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Active Downloads'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Connection Error', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDownloadsTab(),
                    _buildCompletedTab(),
                  ],
                ),
    );
  }

  Widget _buildDownloadsTab() {
    if (_downloads.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_download_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text('No Active Downloads', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Add magnets from the Browser tab',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _downloads.length,
      itemBuilder: (context, index) {
        final dl = _downloads[index] as Map<String, dynamic>;
        final name = dl['name'] ?? 'Unknown';
        final size = dl['size'] ?? '0 B';
        final state = dl['state'] ?? 'unknown';
        final dlspeed = dl['dlspeed'] ?? '0 B/s';
        final upspeed = dl['upspeed'] ?? '0 B/s';
        final progress = dl['progress'] ?? '0%';

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Chip(
                      label: Text(state, style: const TextStyle(fontSize: 12)),
                      backgroundColor: _getStateColor(state).withOpacity(0.3),
                      labelStyle: TextStyle(color: _getStateColor(state)),
                    ),
                    const SizedBox(width: 8),
                    Text('$progress • $size', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.arrow_downward, size: 14, color: Colors.blue),
                    const SizedBox(width: 4),
                    Text(dlspeed, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 16),
                    const Icon(Icons.arrow_upward, size: 14, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(upspeed, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _showDeleteDialog(context, name),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompletedTab() {
    return Column(
      children: [
        // Sorting options
        Padding(
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                InputChip(
                  label: const Text('By Status'),
                  onPressed: () => _changeSortOrder('status'),
                  selected: _sortBy == 'status',
                  backgroundColor: _sortBy == 'status' ? Colors.blue : Colors.grey[300],
                  selectedColor: Colors.blue,
                ),
                const SizedBox(width: 8),
                InputChip(
                  label: const Text('By Name'),
                  onPressed: () => _changeSortOrder('name'),
                  selected: _sortBy == 'name',
                  backgroundColor: _sortBy == 'name' ? Colors.blue : Colors.grey[300],
                  selectedColor: Colors.blue,
                ),
                const SizedBox(width: 8),
                InputChip(
                  label: const Text('By Size'),
                  onPressed: () => _changeSortOrder('size'),
                  selected: _sortBy == 'size',
                  backgroundColor: _sortBy == 'size' ? Colors.blue : Colors.grey[300],
                  selectedColor: Colors.blue,
                ),
              ],
            ),
          ),
        ),
        // Completed torrents list
        Expanded(
          child: _completed.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text('No Completed Torrents', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                        'Completed torrents will appear here',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _completed.length,
                  itemBuilder: (context, index) {
                    final torrent = _completed[index] as Map<String, dynamic>;
                    final name = torrent['name'] ?? 'Unknown';
                    final size = torrent['size'] ?? '0 B';
                    final seedStatus = torrent['seed_status'] ?? 'completed';
                    final upspeed = torrent['upspeed'] ?? '0 B/s';

                    String seedStatusLabel = 'Completed';
                    if (seedStatus == 'active') {
                      seedStatusLabel = 'Active Seeding';
                    } else if (seedStatus == 'standby') {
                      seedStatusLabel = 'Standby Seeding';
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Chip(
                                  label: Text(seedStatusLabel, style: const TextStyle(fontSize: 12)),
                                  backgroundColor: _getSeedStatusColor(seedStatus).withOpacity(0.3),
                                  labelStyle: TextStyle(color: _getSeedStatusColor(seedStatus)),
                                ),
                                const SizedBox(width: 8),
                                Text(size, style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.arrow_upward, size: 14, color: Colors.green),
                                const SizedBox(width: 4),
                                Text(upspeed, style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _showDeleteDialog(context, name),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
