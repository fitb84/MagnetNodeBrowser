import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Tixati Node Browser Backend API Client
/// Points to the Flask backend which scrapes Tixati WebUI
class ApiClient {
  static String _baseUrl = 'http://100.120.201.83:5050';  // Backend server (not Tixati)
  static const Duration timeout = Duration(seconds: 10);

  static String get baseUrl => _baseUrl;
  static void setBaseUrl(String url) => _baseUrl = url.replaceAll(RegExp(r'/$'), '');

  // -------- Basic fetchers --------
  static Future<String> getBandwidthHtml() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/stats')).timeout(timeout);
    if (res.statusCode == 200) return res.body;
    throw Exception('Failed to load bandwidth');
  }

  static Future<String> getTransferDetailsHtml(String id, String subpage) async {
    final res = await http.get(Uri.parse('$_baseUrl/transfers/$id/$subpage')).timeout(timeout);
    if (res.statusCode == 200) return res.body;
    throw Exception('Failed to load $subpage for $id');
  }

  static Future<Map<String, dynamic>> getStats() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/stats')).timeout(timeout);
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Failed to load stats');
  }

  static Future<List<Map<String, dynamic>>> getDownloads() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/downloads')).timeout(timeout);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final downloads = data['downloads'] as List<dynamic>? ?? [];
      return downloads.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load downloads');
  }

  static Future<List<Map<String, dynamic>>> getCompleted() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/completed')).timeout(timeout);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final completed = data['completed'] as List<dynamic>? ?? [];
      return completed.cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to load completed torrents');
  }

  // -------- Actions --------
  static Future<void> startDownload(String id) async => _postAction('start=&$id=1');
  static Future<void> stopDownload(String id) async => _postAction('stop=&$id=1');
  static Future<void> changePriority(String id, {required bool up}) async => _postAction('${up ? 'priority_up' : 'priority_down'}=&$id=1');
  static Future<void> addMagnet(String magnet, String category, String tvFolder) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/add'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'magnet': magnet,
        'category': category,
        'downloadLocation': tvFolder,
      }),
    ).timeout(timeout);
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['msg'] ?? 'Failed to add magnet');
    }
  }

  // -------- Persistent batch (shared web + mobile) --------
  static Future<List<Map<String, dynamic>>> getBatchItems() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/batch')).timeout(timeout);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final batch = data['batch'] as List<dynamic>? ?? [];
      return batch.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    throw Exception('Failed to load batch');
  }

  static Future<Map<String, dynamic>> addBatchItem({
    required String magnet,
    String category = 'movie',
    String downloadLocation = '',
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/batch'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'magnet': magnet,
        'category': category,
        'downloadLocation': downloadLocation,
      }),
    ).timeout(timeout);
    if (res.statusCode == 200 || res.statusCode == 201) {
      return Map<String, dynamic>.from(jsonDecode(res.body));
    }
    final data = jsonDecode(res.body);
    throw Exception(data['error'] ?? 'Failed to add batch item');
  }

  static Future<Map<String, dynamic>> updateBatchItem({
    required String id,
    String? magnet,
    String? category,
    String? downloadLocation,
  }) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/api/batch/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (magnet != null) 'magnet': magnet,
        if (category != null) 'category': category,
        if (downloadLocation != null) 'downloadLocation': downloadLocation,
      }),
    ).timeout(timeout);
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(res.body));
    }
    final data = jsonDecode(res.body);
    throw Exception(data['error'] ?? 'Failed to update batch item');
  }

  static Future<void> deleteBatchItem(String id) async {
    final res = await http.delete(Uri.parse('$_baseUrl/api/batch/$id')).timeout(timeout);
    if (res.statusCode == 200) return;
    final data = jsonDecode(res.body);
    throw Exception(data['error'] ?? 'Failed to delete batch item');
  }

  static Future<Map<String, dynamic>> submitBatch() async {
    final res = await http.post(Uri.parse('$_baseUrl/api/batch/submit')).timeout(timeout);
    if (res.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(res.body));
    }
    final data = jsonDecode(res.body);
    throw Exception(data['error'] ?? 'Failed to submit batch');
  }
  static Future<void> removeDownload(String name) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/api/downloads/${Uri.encodeComponent(name)}')
    ).timeout(timeout);
    if (res.statusCode != 200) throw Exception('Failed to remove download');
  }

  static Future<void> _postAction(String body) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/transfers/action'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    ).timeout(timeout);
    if (res.statusCode != 200) throw Exception('Action failed (${res.statusCode})');
  }

  // -------- Parsers --------
  static Map<String, double> parseBandwidth(String html) {
    double extract(String id) {
      final match = RegExp('<td[^>]*id=["\']$id["\'][^>]*>([^<]*)<').firstMatch(html);
      if (match == null) return 0.0;
      final m = RegExp(r'([\d.]+)\s*(B|KB|MB|GB)/s').firstMatch(match.group(1) ?? '');
      if (m == null) return 0.0;
      double v = double.tryParse(m.group(1) ?? '') ?? 0.0;
      switch ((m.group(2) ?? '').toUpperCase()) {
        case 'GB': v *= 1024 * 1024; break;
        case 'MB': v *= 1024; break;
        case 'KB': break;
        case 'B': v /= 1024; break;
      }
      return v;
    }

    return {'in': extract('inrate'), 'out': extract('outrate')};
  }

  static String? parseMagnetLink(String html) => RegExp('<a[^>]+href=["\'](magnet:[^"\']+)["\']').firstMatch(html)?.group(1);

  static String? parseSavePath(String html) =>
      RegExp('<input[^>]+name=["\']save_path["\'][^>]+value=["\']([^"\']*)["\']').firstMatch(html)?.group(1) ?? '';

  static List<List<String>> _parseRows(String html) {
    // Grab table body if present, otherwise fall back to the raw HTML
    final tableBody = RegExp('<table[^>]*>([\s\S]*?)</table>', dotAll: true).firstMatch(html)?.group(1) ?? html;
    final rows = <List<String>>[];

    for (final rowMatch in RegExp('<tr[^>]*>([\s\S]*?)</tr>', dotAll: true).allMatches(tableBody)) {
      final cells = RegExp('<t[dh][^>]*>([\s\S]*?)</t[dh]>', dotAll: true)
          .allMatches(rowMatch.group(1) ?? '')
          .map((m) => m.group(1)?.replaceAll(RegExp('<[^>]+>'), '').trim() ?? '')
          .toList();
      if (cells.isNotEmpty) rows.add(cells);
    }

    return rows;
  }

  static List<Map<String, String>> parseFiles(String html) => _parseRows(html).map((cells) => {
        'name': cells.elementAtOrNull(0) ?? '',
        'size': cells.elementAtOrNull(1) ?? '',
        'priority': cells.elementAtOrNull(2) ?? '',
        'progress': cells.elementAtOrNull(3) ?? '',
      }).toList();

  static List<Map<String, String>> parseTrackers(String html) => _parseRows(html).map((cells) => {
        'url': cells.elementAtOrNull(0) ?? '',
        'status': cells.elementAtOrNull(1) ?? '',
      }).toList();

  static List<Map<String, String>> parsePeers(String html) => _parseRows(html).map((cells) => {
        'ip': cells.elementAtOrNull(0) ?? '',
        'client': cells.elementAtOrNull(1) ?? '',
        'progress': cells.elementAtOrNull(2) ?? '',
        'down': cells.elementAtOrNull(3) ?? '',
        'up': cells.elementAtOrNull(4) ?? '',
      }).toList();

  static List<String> parseEventLog(String html) =>
      RegExp('<pre[^>]*>(.*?)</pre>', dotAll: true).allMatches(html).map((m) => m.group(1)?.replaceAll(RegExp('<[^>]+>'), '').trim() ?? '').toList();

  static List<Map<String, dynamic>> _parseTransfersHtml(String html) {
    final List<Map<String, dynamic>> transfers = [];
    final tableMatch = RegExp('<table[^>]*class=["\']xferslist["\'][^>]*>([\s\S]*?)</table>', dotAll: true).firstMatch(html);
    if (tableMatch == null) return transfers;
    final rowMatches = RegExp('<tr>([\s\S]*?)</tr>', dotAll: true).allMatches(tableMatch.group(1) ?? '');

    for (final rowMatch in rowMatches) {
      final cells = RegExp('<td[^>]*>([\s\S]*?)</td>', dotAll: true)
          .allMatches(rowMatch.group(1) ?? '')
          .map((m) => m.group(1)?.replaceAll(RegExp('<[^>]+>'), '').trim() ?? '')
          .toList();
      if (cells.length < 9) continue;

      final id = RegExp('input[^>]+class=["\']selection["\'][^>]+name=["\']([^"\']+)["\']')
              .firstMatch(cells[0])
              ?.group(1) ??
          '';

      transfers.add({
        'id': id,
        'name': cells[1],
        'size': cells[2],
        'percent': cells[3],
        'status': cells[4],
        'bpsIn': cells[5],
        'bpsOut': cells[6],
        'priority': cells[7],
        'timeLeft': cells[8],
      });
    }

    return transfers;
  }

  // -------- Library Management --------
  static Future<List<String>> getTvFolders() async => [];
  
  static Future<Map<String, dynamic>> getLibraries() async {
    final stats = await getStats();
    return {
      'movie': (stats['libraries']?['movie'] ?? []) as List,
      'show': (stats['libraries']?['show'] ?? []) as List,
    };
  }
  
  static Future<void> addLibrary(String category, String path, String label) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/library'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'category': category,
        'path': path,
        'label': label.isEmpty ? path : label,
      }),
    ).timeout(timeout);
    if (res.statusCode != 200) {
      final data = jsonDecode(res.body);
      throw Exception(data['msg'] ?? 'Failed to add library');
    }
  }
  
  static Future<void> removeLibrary(String category, String libId) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/api/library'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'category': category,
        'id': libId,
      }),
    ).timeout(timeout);
    if (res.statusCode != 200) throw Exception('Failed to remove library');
  }
  
  static Future<void> autoManageDownloads() async => Future.value();

  // -------- Library index (TV cache) --------
  static Future<List<Map<String, dynamic>>> getTvIndex({bool refresh = false}) async {
    final uri = Uri.parse('$_baseUrl/api/library-index${refresh ? '/refresh' : ''}');
    final res = refresh
        ? await http.post(uri).timeout(timeout)
        : await http.get(uri).timeout(timeout);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final show = data['show'] as List<dynamic>? ?? [];
      return show.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    throw Exception('Failed to load TV index');
  }

  static Future<void> addTvIndexEntry({
    required String series,
    required String seriesPath,
    String? libraryId,
    List<Map<String, dynamic>> seasonPaths = const [],
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/library-index'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'series': series,
        'seriesPath': seriesPath,
        'libraryId': libraryId,
        'seasonPaths': seasonPaths,
      }),
    ).timeout(timeout);
    if (res.statusCode != 201) {
      throw Exception('Failed to add index entry');
    }
  }

  static Future<void> updateTvIndexEntry(String entryId, Map<String, dynamic> data) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/api/library-index/$entryId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    ).timeout(timeout);
    if (res.statusCode != 200) {
      throw Exception('Failed to update index entry');
    }
  }

  static Future<void> deleteTvIndexEntry(String entryId) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/api/library-index/$entryId'),
    ).timeout(timeout);
    if (res.statusCode != 200) {
      throw Exception('Failed to delete index entry');
    }
  }
}

// Safe element access helper
extension _ListSafeAccess<T> on List<T> {
  T? elementAtOrNull(int index) => index < length ? this[index] : null;
}

