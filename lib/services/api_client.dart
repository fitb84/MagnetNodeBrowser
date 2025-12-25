import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiClient {
  static const String baseUrl = 'http://100.120.201.83:5050';
  static const Duration timeout = Duration(seconds: 10);

  // Get dashboard stats
  static Future<Map<String, dynamic>> getStats() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/stats'),
      ).timeout(timeout);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('Failed to load stats');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  // Get downloads list
  static Future<List<dynamic>> getDownloads() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/downloads'),
      ).timeout(timeout);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['downloads'] ?? [];
      }
      throw Exception('Failed to load downloads');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  // Get TV folder suggestions
  static Future<List<String>> getTvFolders() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/tv-folders'),
      ).timeout(timeout);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<String> folders = List<String>.from(data['folders'] ?? []);
        return folders;
      }
      throw Exception('Failed to load TV folders');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  // Add magnet link
  static Future<void> addMagnet(String magnet, String category, String tvFolder) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'magnet': magnet,
          'category': category,
          'tv_folder_name': tvFolder,
        }),
      ).timeout(timeout);
      
      final data = jsonDecode(response.body);
      if (data['status'] != 'ok') {
        throw Exception(data['msg'] ?? 'Failed to add magnet');
      }
    } catch (e) {
      throw Exception('Failed to add magnet: $e');
    }
  }

  // Remove download
  static Future<void> removeDownload(String hash) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/downloads/$hash'),
      ).timeout(timeout);
      
      if (response.statusCode != 200) {
        throw Exception('Failed to remove download');
      }
    } catch (e) {
      throw Exception('Failed to remove download: $e');
    }
  }

  // Get library stats
  static Future<Map<String, dynamic>> getLibraries() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/stats'),
      ).timeout(timeout);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['libraries'] ?? {};
      }
      throw Exception('Failed to load libraries');
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  // Add library path
  static Future<void> addLibrary(String category, String path, String label) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/library'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'category': category,
          'path': path,
          'label': label,
        }),
      ).timeout(timeout);
      
      final data = jsonDecode(response.body);
      if (!data['success']) {
        throw Exception(data['msg'] ?? 'Failed to add library');
      }
    } catch (e) {
      throw Exception('Failed to add library: $e');
    }
  }

  // Remove library path
  static Future<void> removeLibrary(String category, String libId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/library'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'category': category,
          'id': libId,
        }),
      ).timeout(timeout);
      
      if (response.statusCode != 200) {
        throw Exception('Failed to remove library');
      }
    } catch (e) {
      throw Exception('Failed to remove library: $e');
    }
  }

  // Auto-manage downloads
  static Future<void> autoManageDownloads() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/downloads/auto-manage'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(timeout);
      
      if (response.statusCode != 200) {
        throw Exception('Failed to auto-manage downloads');
      }
    } catch (e) {
      throw Exception('Auto-manage error: $e');
    }
  }
}
