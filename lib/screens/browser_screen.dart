import 'package:flutter/material.dart';
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

  InAppWebViewController? webViewController;
  bool _webViewInitialized = false;
  final String homeUrl = 'https://ext.to';
  String _selectedCategory = 'movie';

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

  void _handleMagnetLink(String magnetLink) {
    final magnet = MagnetLink.parse(magnetLink);
    
    if (magnet == null || !magnet.isValid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid magnet link format')),
        );
      }
      return;
    }

    // Show confirmation dialog
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add Magnet Link?'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(magnet.getDisplayString()),
                const SizedBox(height: 16),
                const Text(
                  'Select category:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedCategory,
                  items: const [
                    DropdownMenuItem(value: 'movie', child: Text('Movie')),
                    DropdownMenuItem(value: 'tv', child: Text('TV Show')),
                    DropdownMenuItem(value: 'music', child: Text('Music')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedCategory = value;
                      });
                    }
                  },
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
                Navigator.pop(context);
                await _addMagnetToQueue(magnet.rawMagnetLink);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _addMagnetToQueue(String magnetLink) async {
    try {
      await ApiClient.addMagnet(magnetLink, _selectedCategory, '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Magnet link added to queue!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✗ Error adding magnet: $e')),
        );
      }
    }
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