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
                      // Always intercept magnet links
                      if (url.startsWith('magnet:')) {
                        _handleMagnetLink(url);
                        return NavigationActionPolicy.CANCEL;
                      }
                      // Handle other unsupported schemes
                      if (!url.startsWith('http://') && 
                          !url.startsWith('https://') &&
                          !url.startsWith('file://')) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Unsupported link type: $url')),
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
    String? errorText;

    return showDialog<Map<String, String>?>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final tvOptions = _tvIndex
              .map((e) => DropdownMenuItem<String>(
                  value: e['id']?.toString(),
                  child: Text(e['series'] ?? 'Series'),
                ))
              .toList();

            return AlertDialog(
              title: const Text('Add to Batch'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(magnet.getDisplayString()),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: category,
                      items: const [
                        DropdownMenuItem(value: 'movie', child: Text('Movie')),
                        DropdownMenuItem(value: 'tv', child: Text('TV Series')),
                      ],
                      onChanged: (val) {
                        setState(() {
                          category = val ?? 'movie';
                          if (category != 'tv') {
                            selectedSeriesId = null;
                            selectedSeriesPath = null;
                          }
                          errorText = null;
                        });
                      },
                      decoration: const InputDecoration(labelText: 'Type'),
                    ),
                    if (category == 'tv') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedSeriesId,
                        items: tvOptions,
                        onChanged: (val) {
                          setState(() {
                            selectedSeriesId = val;
                            final match = _tvIndex.firstWhere(
                              (e) => e['id']?.toString() == val,
                              orElse: () => <String, dynamic>{},
                            );
                            selectedSeriesPath = match['seriesPath']?.toString();
                            errorText = null;
                          });
                        },
                        decoration: const InputDecoration(labelText: 'Series'),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final created = await _showCreateSeriesDialog();
                          if (created != null) {
                            await _ensureTvData();
                            setState(() {
                              selectedSeriesPath = created['seriesPath'];
                              final match = _tvIndex.firstWhere(
                                (e) => e['seriesPath'] == created['seriesPath'],
                                orElse: () => <String, dynamic>{},
                              );
                              selectedSeriesId = match['id']?.toString();
                              errorText = null;
                            });
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Create new series'),
                      ),
                      if (errorText != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(errorText!, style: const TextStyle(color: Colors.red)),
                        ),
                    ],
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
                    if (category == 'tv' && (selectedSeriesPath == null || selectedSeriesPath!.isEmpty)) {
                      setState(() => errorText = 'Select or create a series');
                      return;
                    }
                    Navigator.pop(context, {
                      'category': category,
                      'downloadLocation': category == 'tv' ? (selectedSeriesPath ?? '') : '',
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
    // Wait a moment for page to load
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (webViewController == null || !mounted) return;

    // Inject JavaScript to intercept magnet:? link clicks
    const magnetLinkScript = '''
    (function() {
      // Override window.open to catch magnet:? links
      const originalOpen = window.open;
      window.open = function(url, target, features) {
        if (url && url.startsWith('magnet:?')) {
          console.log('MAGNET_LINK:' + url);
          return null;
        }
        return originalOpen.apply(window, arguments);
      };

      // Handle all clicks on the document
      document.addEventListener('click', function(e) {
        let target = e.target;
        // Traverse up to find a link element
        while (target && target.tagName !== 'A') {
          target = target.parentElement;
        }
        if (target && target.href && target.href.startsWith('magnet:?')) {
          e.preventDefault();
          e.stopPropagation();
          e.stopImmediatePropagation();
          // Notify Flutter via console message
          console.log('MAGNET_LINK:' + target.href);
          return false;
        }
      }, true);
      // Also intercept touchstart for better mobile support
      document.addEventListener('touchstart', function(e) {
        let target = e.target;
        while (target && target.tagName !== 'A') {
          target = target.parentElement;
        }
        if (target && target.href && target.href.startsWith('magnet:?')) {
          e.preventDefault();
          e.stopPropagation();
          console.log('MAGNET_LINK:' + target.href);
          return false;
        }
      }, true);
    })();
    ''';

    try {
      await webViewController!.evaluateJavascript(source: magnetLinkScript);
    } catch (e) {
      print('Error injecting magnet link handler: \$e');
    }
  }
}