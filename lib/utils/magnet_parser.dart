import 'dart:convert';

class MagnetLink {
  final String? infoHash;
  final String? displayName;
  final int? fileSize;
  final List<String> trackers;
  final String rawMagnetLink;

  MagnetLink({
    required this.infoHash,
    this.displayName,
    this.fileSize,
    this.trackers = const [],
    required this.rawMagnetLink,
  });

  bool get isValid => infoHash != null && infoHash!.isNotEmpty;

  static MagnetLink? parse(String magnetLink) {
    try {
      if (!magnetLink.startsWith('magnet:')) {
        return null;
      }

      // Remove 'magnet:?' prefix
      final queryString = magnetLink.substring(8);
      final params = Uri.splitQueryString(queryString);

      // Extract info hash from xt parameter (e.g., urn:btih:HASH)
      String? infoHash;
      final xtParam = params['xt'];
      if (xtParam != null) {
        // Handle both urn:btih: and urn:btmh: formats
        if (xtParam.contains(':')) {
          infoHash = xtParam.split(':').last;
        } else {
          infoHash = xtParam;
        }
      }

      // Extract display name
      final displayName = params['dn'];

      // Extract file size
      int? fileSize;
      final xlParam = params['xl'];
      if (xlParam != null) {
        fileSize = int.tryParse(xlParam);
      }

      // Extract tracker URLs (can be multiple)
      final trackers = params.entries
          .where((e) => e.key == 'tr')
          .map((e) => Uri.decodeComponent(e.value))
          .toList();

      return MagnetLink(
        infoHash: infoHash,
        displayName: displayName,
        fileSize: fileSize,
        trackers: trackers,
        rawMagnetLink: magnetLink,
      );
    } catch (e) {
      print('Error parsing magnet link: $e');
      return null;
    }
  }

  String getDisplayString() {
    final parts = <String>[];

    if (displayName != null && displayName!.isNotEmpty) {
      parts.add('📄 ${displayName!}');
    }

    if (fileSize != null) {
      parts.add('📊 ${_formatFileSize(fileSize!)}');
    }

    if (infoHash != null) {
      final hashDisplay = infoHash!.length > 16
          ? '${infoHash!.substring(0, 16)}...'
          : infoHash!;
      parts.add('🔐 Hash: $hashDisplay');
    }

    if (trackers.isNotEmpty) {
      parts.add('🌐 ${trackers.length} tracker(s)');
    }

    return parts.isNotEmpty ? parts.join('\n') : 'Magnet link';
  }

  static String _formatFileSize(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int suffixIndex = 0;

    while (size >= 1024 && suffixIndex < suffixes.length - 1) {
      size /= 1024;
      suffixIndex++;
    }

    return '${size.toStringAsFixed(2)} ${suffixes[suffixIndex]}';
  }
}
