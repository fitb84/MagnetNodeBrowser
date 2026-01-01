import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/api_client.dart';
import '../utils/magnet_parser.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({Key? key}) : super(key: key);

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const platform = MethodChannel('com.example.magnetnodebrowser/magnet');
  InAppWebViewController? webViewController;
  bool _webViewInitialized = false;
  final String homeUrl = 'https://ext.to';
  List<Map<String, dynamic>> _tvIndex = [];
  List<Map<String, dynamic>> _showLibraries = [];
  List<Map<String, dynamic>> _movieLibraries = [];
  bool _tvDataLoading = false;

  @override
  void initState() {
    super.initState();
    // Delay webview initialization to after widget is fully built
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _webViewInitialized = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Incognito Browser'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _webViewInitialized
                ? InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(homeUrl)),
                    initialOptions: InAppWebViewGroupOptions(
                      crossPlatform: InAppWebViewOptions(
                        incognito: true,
                        javaScriptEnabled: true,
                        cacheEnabled: false,
                        clearCache: true,
                      ),
                      android: AndroidInAppWebViewOptions(
                        useHybridComposition: true,
                      ),
                    ),
                    onWebViewCreated: (controller) {
                      webViewController = controller;
                      _injectMagnetLinkHandler();
                    },
                    onLoadStop: (controller, url) async {
                      await _injectMagnetLinkHandler();
                    },
                    onConsoleMessage: (controller, consoleMessage) {
                      // Check if this is a magnet link message
                      if (consoleMessage.message.startsWith('MAGNET_LINK:')) {
                        final magnetLink = consoleMessage.message.substring(12);
                        _handleMagnetLink(magnetLink);
                      }
                    },
                    shouldOverrideUrlLoading: (controller, navigationAction) async {
                      final url = navigationAction.request.url.toString();
                      // Always intercept magnet links (with or without ?)
                      if (url.startsWith('magnet:')) {
                        _handleMagnetLink(url);
                        return NavigationActionPolicy.CANCEL;
                      }
                      // Handle other unsupported schemes
                      if (!url.startsWith('http://') && 
                          !url.startsWith('https://') &&
                          !url.startsWith('file://') &&
                          !url.startsWith('about:') &&
                          !url.startsWith('data:')) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Unsupported link type: ${url.length > 50 ? '${url.substring(0, 50)}...' : url}')),
                          );
                        }
                        return NavigationActionPolicy.CANCEL;
                      }
                      // Allow normal HTTP/HTTPS navigation
                      return NavigationActionPolicy.ALLOW;
                    },
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          Container(
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                  onPressed: () async {
                    if (webViewController != null && await webViewController!.canGoBack()) {
                      await webViewController!.goBack();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.home),
                  tooltip: 'Home',
                  onPressed: () async {
                    await webViewController?.loadUrl(
                      urlRequest: URLRequest(url: WebUri(homeUrl)),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Reload',
                  onPressed: () async {
                    await webViewController?.reload();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  void _handleMagnetLink(String magnetLink) async {
    final magnet = MagnetLink.parse(magnetLink);
    if (magnet == null || !magnet.isValid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid magnet link format')),
        );
      }
      return;
    }

    if (!mounted) return;
    final selection = await _showCategoryAndLocationDialog(magnet);
    if (selection == null) return;
    await _addMagnetToIngestBatch(
      magnetLink: magnet.rawMagnetLink,
      category: selection['category'] as String,
      downloadLocation: selection['downloadLocation'] as String,
    );
  }

  Future<void> _addMagnetToIngestBatch({
    required String magnetLink,
    required String category,
    required String downloadLocation,
  }) async {
    try {
      await ApiClient.addBatchItem(
        magnet: magnetLink,
        category: category,
        downloadLocation: downloadLocation,
      );
      // Notify Ingest tab to refresh immediately
      try {
        platform.invokeMethod('addToBatch', {'magnet': magnetLink});
      } catch (e) {
        print('Error sending to batch: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Magnet saved to batch for editing.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to queue magnet: $e')),
        );
      }
    }
  }

  Future<void> _ensureTvData() async {
    if (_tvDataLoading) return;
    setState(() => _tvDataLoading = true);
    try {
      final index = await ApiClient.getTvIndex();
      final libs = await ApiClient.getLibraries();
      if (!mounted) return;
      setState(() {
        _tvIndex = index.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _showLibraries = (libs['show'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
        _movieLibraries = (libs['movie'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('TV data load failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _tvDataLoading = false);
    }
  }

  Future<Map<String, String>?> _showCategoryAndLocationDialog(MagnetLink magnet) async {
    await _ensureTvData();
    String category = 'movie';
    String? selectedSeriesId;
    String? selectedSeriesPath;
    String movieLocation = '';
    String? errorText;
    final seriesController = TextEditingController();
    final locationController = TextEditingController();

    // Parse magnet for smart suggestions
    final magnetName = magnet.displayName ?? magnet.rawMagnetLink;
    final parsedSeason = _extractSeasonNumber(magnetName);
    
    return showDialog<Map<String, String>?>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // Build TV series options from index
            final tvOptions = _tvIndex
              .where((e) {
                final q = seriesController.text.toLowerCase();
                if (q.isEmpty) return true;
                return (e['series'] ?? '').toString().toLowerCase().contains(q);
              })
              .take(10)
              .map((e) => DropdownMenuItem<String>(
                  value: e['id']?.toString(),
                  child: Text(e['series'] ?? 'Series'),
                ))
              .toList();
            
            // Get movie libraries
            final movieLibraries = _showLibraries.isEmpty 
                ? <Map<String, dynamic>>[]
                : _showLibraries; // Both use show libraries for now

            return AlertDialog(
              title: const Text('Add to Batch'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Magnet display
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        magnetName.length > 80 ? '${magnetName.substring(0, 80)}...' : magnetName,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Category selector
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'movie', label: Text('Movie'), icon: Icon(Icons.movie)),
                        ButtonSegment(value: 'tv', label: Text('TV'), icon: Icon(Icons.tv)),
                      ],
                      selected: {category},
                      onSelectionChanged: (value) {
                        setState(() {
                          category = value.first;
                          selectedSeriesId = null;
                          selectedSeriesPath = null;
                          seriesController.clear();
                          locationController.clear();
                          movieLocation = '';
                          errorText = null;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    if (category == 'tv') ...[
                      // TV Series search field
                      TextField(
                        controller: seriesController,
                        decoration: const InputDecoration(
                          labelText: 'Search Series',
                          hintText: 'Start typing...',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      
                      // Quick pick chips from TV index
                      if (_tvIndex.isNotEmpty) ...[
                        const Text('Quick Select:', style: TextStyle(fontSize: 12, color: Colors.blue)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _tvIndex
                            .where((e) {
                              final q = seriesController.text.toLowerCase();
                              if (q.isEmpty) return true;
                              return (e['series'] ?? '').toString().toLowerCase().contains(q);
                            })
                            .take(6)
                            .map((e) => ActionChip(
                              label: Text(e['series'] ?? 'Series', style: const TextStyle(fontSize: 12)),
                              onPressed: () {
                                setState(() {
                                  selectedSeriesId = e['id']?.toString();
                                  seriesController.text = e['series'] ?? '';
                                  // Build suggested path
                                  selectedSeriesPath = _buildSeriesPath(e, parsedSeason);
                                  if (selectedSeriesPath != null) {
                                    locationController.text = selectedSeriesPath!;
                                  }
                                  errorText = null;
                                });
                              },
                            ))
                            .toList(),
                        ),
                        const SizedBox(height: 12),
                      ],
                      
                      // Location field
                      TextField(
                        controller: locationController,
                        decoration: const InputDecoration(
                          labelText: 'Download Location',
                          hintText: 'Required for TV',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.folder),
                        ),
                        onChanged: (val) {
                          setState(() {
                            selectedSeriesPath = val;
                            errorText = null;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      
                      // Create new series button
                      TextButton.icon(
                        onPressed: () async {
                          final created = await _showCreateSeriesDialog();
                          if (created != null) {
                            await _ensureTvData();
                            setState(() {
                              selectedSeriesPath = created['seriesPath'];
                              seriesController.text = created['series'] ?? '';
                              locationController.text = created['seriesPath'] ?? '';
                              final match = _tvIndex.firstWhere(
                                (e) => e['seriesPath'] == created['seriesPath'],
                                orElse: () => <String, dynamic>{},
                              );
                              selectedSeriesId = match['id']?.toString();
                              errorText = null;
                            });
                          }
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Create new series'),
                      ),
                    ] else ...[
                      // Movie category - show library quick picks
                      if (_movieLibraries.isNotEmpty) ...[
                        const Text('Select Library:', style: TextStyle(fontSize: 12, color: Colors.blue)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _movieLibraries.map((lib) => ActionChip(
                            label: Text(lib['label'] ?? 'Library', style: const TextStyle(fontSize: 12)),
                            avatar: const Icon(Icons.folder, size: 16),
                            onPressed: () {
                              setState(() {
                                movieLocation = lib['path'] ?? '';
                                locationController.text = movieLocation;
                                errorText = null;
                              });
                            },
                          )).toList(),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: locationController,
                        decoration: const InputDecoration(
                          labelText: 'Download Location (optional)',
                          hintText: 'Leave blank or select library',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.folder),
                        ),
                        onChanged: (val) {
                          setState(() {
                            movieLocation = val;
                            errorText = null;
                          });
                        },
                      ),
                    ],
                    
                    if (errorText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(errorText!, style: const TextStyle(color: Colors.red)),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final location = locationController.text.trim();
                    if (category == 'tv' && location.isEmpty) {
                      setState(() => errorText = 'Select or enter a series location');
                      return;
                    }
                    Navigator.pop(context, {
                      'category': category,
                      'downloadLocation': location,
                    });
                  },
                  child: const Text('Add to Batch'),
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  String? _buildSeriesPath(Map<String, dynamic> entry, int? seasonHint) {
    // Check for season paths first
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
    // Fall back to first season path or series path
    if (seasonPaths.isNotEmpty && (seasonPaths.first['path'] ?? '').toString().isNotEmpty) {
      return seasonPaths.first['path'].toString();
    }
    return entry['seriesPath']?.toString();
  }
  
  int? _extractSeasonNumber(String name) {
    final m1 = RegExp(r'(?i)\bS(\d{1,2})\b').firstMatch(name);
    if (m1 != null) return int.tryParse(m1.group(1) ?? '');
    final m2 = RegExp(r'(?i)\bseason\s*(\d{1,2})\b').firstMatch(name);
    if (m2 != null) return int.tryParse(m2.group(1) ?? '');
    return null;
  }

  Future<Map<String, String>?> _showCreateSeriesDialog() async {
    final nameController = TextEditingController();
    String? selectedLibId;
    String? errorText;

    return showDialog<Map<String, String>?>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final libItems = _showLibraries
                .map((lib) => DropdownMenuItem<String>(
                      value: lib['id']?.toString(),
                      child: Text(lib['label'] ?? lib['path'] ?? 'Library'),
                    ))
                .toList();
            return AlertDialog(
              title: const Text('Create Series'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Series name'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedLibId,
                    items: libItems,
                    onChanged: (val) {
                      setState(() {
                        selectedLibId = val;
                        errorText = null;
                      });
                    },
                    decoration: const InputDecoration(labelText: 'Library'),
                  ),
                  if (errorText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(errorText!, style: const TextStyle(color: Colors.red)),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty || selectedLibId == null) {
                      setState(() => errorText = 'Name and library are required');
                      return;
                    }
                    final lib = _showLibraries.firstWhere(
                      (l) => l['id']?.toString() == selectedLibId,
                      orElse: () => {},
                    );
                    final basePath = lib['path']?.toString() ?? '';
                    if (basePath.isEmpty) {
                      setState(() => errorText = 'Library path missing');
                      return;
                    }
                    final seriesPath = '$basePath/$name';
                    try {
                      await ApiClient.addTvIndexEntry(
                        series: name,
                        seriesPath: seriesPath,
                        libraryId: lib['id']?.toString(),
                      );
                      Navigator.pop(context, {
                        'series': name,
                        'seriesPath': seriesPath,
                      });
                    } catch (e) {
                      setState(() => errorText = e.toString());
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _injectMagnetLinkHandler() async {
    // Wait for page DOM to be ready
    await Future.delayed(const Duration(milliseconds: 300));
    
    if (webViewController == null || !mounted) return;

    // Robust JavaScript to intercept ALL magnet:? link clicks
    const magnetLinkScript = '''
    (function() {
      // Prevent double-injection
      if (window._magnetHandlerInjected) return;
      window._magnetHandlerInjected = true;
      
      function handleMagnetLink(url) {
        if (url && (url.startsWith('magnet:?') || url.startsWith('magnet:'))) {
          console.log('MAGNET_LINK:' + url);
          return true;
        }
        return false;
      }
      
      // Override window.open to catch magnet:? links
      const originalOpen = window.open;
      window.open = function(url, target, features) {
        if (handleMagnetLink(url)) return null;
        return originalOpen.apply(window, arguments);
      };
      
      // Override location assignment
      const originalLocationSet = Object.getOwnPropertyDescriptor(window, 'location');
      
      // Main click handler - capture phase for priority
      document.addEventListener('click', function(e) {
        let target = e.target;
        // Traverse up to find any link element
        while (target && target !== document) {
          // Check for anchor tags
          if (target.tagName === 'A') {
            const href = target.getAttribute('href') || target.href;
            if (handleMagnetLink(href)) {
              e.preventDefault();
              e.stopPropagation();
              e.stopImmediatePropagation();
              return false;
            }
          }
          // Check for onclick handlers that might trigger magnet links
          if (target.onclick) {
            const onclickStr = target.onclick.toString();
            const magnetMatch = onclickStr.match(/magnet:\?[^'"]+/);
            if (magnetMatch && handleMagnetLink(magnetMatch[0])) {
              e.preventDefault();
              e.stopPropagation();
              return false;
            }
          }
          target = target.parentElement;
        }
      }, true);
      
      // Touch handler for mobile - both touchstart and touchend
      ['touchstart', 'touchend'].forEach(function(eventType) {
        document.addEventListener(eventType, function(e) {
          let target = e.target;
          while (target && target !== document) {
            if (target.tagName === 'A') {
              const href = target.getAttribute('href') || target.href;
              if (handleMagnetLink(href)) {
                e.preventDefault();
                e.stopPropagation();
                return false;
              }
            }
            target = target.parentElement;
          }
        }, true);
      });
      
      // Also watch for dynamically added links via MutationObserver
      const observer = new MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
          mutation.addedNodes.forEach(function(node) {
            if (node.nodeType === 1) { // Element node
              const links = node.querySelectorAll ? node.querySelectorAll('a[href^="magnet:"]') : [];
              links.forEach(function(link) {
                link.addEventListener('click', function(e) {
                  if (handleMagnetLink(link.href)) {
                    e.preventDefault();
                    e.stopPropagation();
                  }
                }, true);
              });
            }
          });
        });
      });
      observer.observe(document.body, { childList: true, subtree: true });
      
      // Pre-process existing magnet links
      document.querySelectorAll('a[href^="magnet:"]').forEach(function(link) {
        link.addEventListener('click', function(e) {
          if (handleMagnetLink(link.href)) {
            e.preventDefault();
            e.stopPropagation();
          }
        }, true);
      });
    })();
    ''';

    try {
      await webViewController!.evaluateJavascript(source: magnetLinkScript);
    } catch (e) {
      print('Error injecting magnet link handler: $e');
    }
  }
}