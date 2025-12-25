import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_client.dart';
import '../services/notification_service.dart';

class IngestScreen extends StatefulWidget {
  const IngestScreen({Key? key}) : super(key: key);

  @override
  State<IngestScreen> createState() => _IngestScreenState();
}

class _IngestScreenState extends State<IngestScreen> {
  final _magnetController = TextEditingController();
  final _tvFolderController = TextEditingController();
  String _selectedCategory = 'movie';
  List<String> _tvFolders = [];
  List<Map<String, String>> _batch = [];
  bool _loadingFolders = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadTvFolders();
  }

  Future<void> _loadTvFolders() async {
    setState(() => _loadingFolders = true);
    try {
      final folders = await ApiClient.getTvFolders();
      setState(() => _tvFolders = folders);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading TV folders: $e')),
      );
    } finally {
      setState(() => _loadingFolders = false);
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      if (data?.text != null) {
        setState(() {
          _magnetController.text = data!.text!;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pasted from clipboard')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error accessing clipboard: $e')),
      );
    }
  }

  void _addToBatch() {
    if (_magnetController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a magnet link')),
      );
      return;
    }

    if (!_magnetController.text.startsWith('magnet:')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid magnet link')),
      );
      return;
    }

    setState(() {
      _batch.add({
        'magnet': _magnetController.text,
        'category': _selectedCategory,
        'tv_folder': _tvFolderController.text,
      });
      _magnetController.clear();
      _tvFolderController.clear();
    });
  }

  void _removeBatchItem(int index) {
    setState(() => _batch.removeAt(index));
  }

  Future<void> _submitBatch() async {
    if (_batch.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Batch is empty')),
      );
      return;
    }

    setState(() => _submitting = true);
    int successCount = 0;
    try {
      for (final item in _batch) {
        await ApiClient.addMagnet(
          item['magnet']!,
          item['category']!,
          item['tv_folder']!,
        );
        successCount++;
      }
      
      // Show notification
      await NotificationService.showBatchSubmitted(successCount);
      
      setState(() => _batch.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✓ Added $successCount magnet${successCount == 1 ? '' : 's'}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      Text(
                        'Add Magnet Link',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _magnetController,
                              decoration: InputDecoration(
                                hintText: 'Paste magnet link here',
                                prefixIcon: const Icon(Icons.link),
                                isDense: true,
                              ),
                              maxLines: null,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.paste),
                            onPressed: _pasteFromClipboard,
                            tooltip: 'Paste from clipboard',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButton<String>(
                              value: _selectedCategory,
                              isExpanded: true,
                              items: const [
                                DropdownMenuItem(value: 'movie', child: Text('Movie')),
                                DropdownMenuItem(value: 'show', child: Text('TV Show')),
                              ],
                              onChanged: (value) {
                                setState(() => _selectedCategory = value ?? 'movie');
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _tvFolderController,
                              decoration: InputDecoration(
                                hintText: _selectedCategory == 'show' ? 'Series name' : 'N/A',
                                isDense: true,
                              ),
                              enabled: _selectedCategory == 'show',
                            ),
                          ),
                        ],
                      ),
                      if (_selectedCategory == 'show' && _tvFolders.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 100,
                          child: ListView.builder(
                            itemCount: _tvFolders.length,
                            itemBuilder: (context, index) {
                              final folder = _tvFolders[index];
                              return ListTile(
                                dense: true,
                                title: Text(folder),
                                onTap: () {
                                  setState(() => _tvFolderController.text = folder);
                                  FocusScope.of(context).unfocus();
                                },
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _addToBatch,
                          child: const Text('Add to Batch'),
                        ),
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
              ..._batch.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
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
                                item['category']!.toUpperCase(),
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Colors.grey,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item['magnet']!.substring(0, 50) + '...',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (item['tv_folder']!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Folder: ${item['tv_folder']}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.blue,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () => _removeBatchItem(index),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
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

  @override
  void dispose() {
    _magnetController.dispose();
    _tvFolderController.dispose();
    super.dispose();
  }
}
