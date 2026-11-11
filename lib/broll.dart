import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'settings.dart';

/// Downloads topic-related B-roll from Pexels or Pixabay.
///
/// Quality policy:
/// - Prefer the largest usable MP4 available from Pexels.
/// - Try the next smaller file if a larger file is unavailable or exceeds the
///   download-size ceiling.
/// - Prefer Pixabay's largest rendition first, then fall back to smaller ones.
/// - Keep the existing 20 MB per-clip ceiling to protect mobile data/storage.
class BrollFetcher {
  static const int maxClipBytes = 20 * 1024 * 1024;

  static const List<String> _blocked = <String>[
    'woman',
    'women',
    'girl',
    'girls',
    'female',
    'lady',
    'ladies',
    'bikini',
    'mother',
    'bride',
    'actress',
  ];

  static bool _bad(String text) {
    final value = text.toLowerCase();
    for (final word in _blocked) {
      if (RegExp('(^|[^a-z])$word([^a-z]|\\$)').hasMatch(value)) {
        return true;
      }
    }
    return false;
  }

  static int _dimension(dynamic value) {
    if (value is num && value.isFinite) return value.toInt();
    return 0;
  }

  static int _area(dynamic file) {
    final width = _dimension(file['width']);
    final height = _dimension(file['height']);
    return width * height;
  }

  static int _shortEdge(dynamic file) {
    final width = _dimension(file['width']);
    final height = _dimension(file['height']);
    if (width <= 0 || height <= 0) return 0;
    return math.min(width, height);
  }

  /// Returns valid Pexels MP4 renditions, best quality first.
  ///
  /// Exposed separately so the quality ordering can be covered by unit tests.
  static List<Map<String, dynamic>> rankPexelsFiles(Iterable<dynamic> files) {
    final result = <Map<String, dynamic>>[];

    for (final item in files) {
      if (item is! Map) continue;
      final file = Map<String, dynamic>.from(item);
      final link = file['link'];
      final width = _dimension(file['width']);
      final height = _dimension(file['height']);
      final type = file['file_type'];

      if (type != 'video/mp4' ||
          link is! String ||
          link.trim().isEmpty ||
          width <= 0 ||
          height <= 0) {
        continue;
      }
      result.add(file);
    }

    result.sort((a, b) {
      final areaOrder = _area(b).compareTo(_area(a));
      if (areaOrder != 0) return areaOrder;
      return _shortEdge(b).compareTo(_shortEdge(a));
    });

    return result;
  }

  static List<String> _pixabayUrls(dynamic video) {
    if (video is! Map) return <String>[];
    final urls = <String>[];
    // Pixabay's large rendition is preferred. Smaller versions are fallbacks.
    for (final key in <String>['large', 'medium', 'small', 'tiny']) {
      final rendition = video[key];
      if (rendition is! Map) continue;
      final url = rendition['url'];
      if (url is String && url.trim().isNotEmpty && !urls.contains(url)) {
        urls.add(url);
      }
    }
    return urls;
  }

  /// animation=true requests a 2D animation from Pixabay (requires Pixabay key).
  static Future<String?> fetch(
    AppSettings settings,
    String query,
    bool portrait,
    String outPath,
    int pick, {
    bool animation = false,
  }) async {
    try {
      final encodedQuery = Uri.encodeQueryComponent(query.trim());
      if (encodedQuery.isEmpty) return null;

      List<String> candidates = <String>[];

      if (animation || settings.brollProvider == 'pixabay') {
        final key = settings.pixabayKey.trim();
        if (key.isEmpty) return null;

        final type = animation ? '&video_type=animation' : '';
        final response = await http
            .get(
              Uri.parse(
                'https://pixabay.com/api/videos/?key='
                '${Uri.encodeQueryComponent(key)}&q=$encodedQuery'
                '&per_page=20&safesearch=true$type',
              ),
            )
            .timeout(const Duration(seconds: 20));

        if (response.statusCode != 200) return null;
        final decoded = jsonDecode(response.body);
        if (decoded is! Map || decoded['hits'] is! List) return null;

        final hits = (decoded['hits'] as List)
            .where((item) =>
                item is Map && !_bad('${item['tags']} ${item['pageURL']}'))
            .toList();
        if (hits.isEmpty) return null;

        final selected = hits[pick.abs() % hits.length];
        candidates = _pixabayUrls(selected['videos']);
      } else {
        final key = settings.pexelsKey.trim();
        if (key.isEmpty) return null;

        final response = await http
            .get(
              Uri.parse(
                'https://api.pexels.com/videos/search?query=$encodedQuery'
                '&per_page=15&orientation=${portrait ? 'portrait' : 'landscape'}',
              ),
              headers: <String, String>{'Authorization': key},
            )
            .timeout(const Duration(seconds: 20));

        if (response.statusCode != 200) return null;
        final decoded = jsonDecode(response.body);
        if (decoded is! Map || decoded['videos'] is! List) return null;

        final videos = (decoded['videos'] as List)
            .where((item) => item is Map && !_bad('${item['url']}'))
            .toList();
        if (videos.isEmpty) return null;

        final selected = videos[pick.abs() % videos.length];
        final rawFiles = selected['video_files'];
        if (rawFiles is! List) return null;

        final ranked = rankPexelsFiles(rawFiles);
        if (ranked.isEmpty) return null;

        // Try up to five renditions, highest resolution first. This prevents
        // one oversized HD file from cancelling an otherwise usable B-roll.
        candidates = ranked
            .take(5)
            .map((file) => file['link'] as String)
            .toList();
      }

      for (final url in candidates) {
        try {
          final download = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 90));

          if (download.statusCode != 200 ||
              download.bodyBytes.isEmpty ||
              download.bodyBytes.length > maxClipBytes) {
            continue;
          }

          final output = File(outPath);
          await output.parent.create(recursive: true);
          await output.writeAsBytes(download.bodyBytes, flush: true);
          if (await output.exists() && await output.length() > 0) {
            return outPath;
          }
        } catch (_) {
          // Try the next rendition instead of abandoning the B-roll search.
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }
}