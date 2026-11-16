import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'settings.dart';

/// Downloads topic-related B-roll from Pexels or Pixabay.
///
/// Selection policy:
/// - Rank search results by topic relevance, output orientation, resolution,
///   and useful clip duration before downloading anything.
/// - Prefer the strongest candidates, while allowing the caller's `pick`
///   value to rotate through the top results on a retry.
/// - Prefer the largest usable rendition of a selected result, then fall back
///   to smaller renditions if a download fails or exceeds the size ceiling.
/// - Keep the existing 20 MB per-clip ceiling to protect mobile data/storage.
///
/// Downloads are streamed: a rendition larger than the ceiling is abandoned
/// as soon as its size is known (or exceeded) instead of being downloaded in
/// full first, and one fetch has a total time budget, so a slow connection
/// can no longer freeze the export for minutes.
class BrollFetcher {
  static const int maxClipBytes = 20 * 1024 * 1024;
  static const int _candidatePoolSize = 3;

  /// Total time one [fetch] may spend downloading (all renditions together).
  static const Duration _downloadBudget = Duration(seconds: 75);

  /// A download that receives nothing for this long is given up.
  static const Duration _idleTimeout = Duration(seconds: 20);

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

  static int _dimension(dynamic value) {
    if (value is num && value.isFinite) return value.toInt();
    return 0;
  }

  static double _number(dynamic value) {
    if (value is num && value.isFinite) return value.toDouble();
    return double.tryParse('$value') ?? 0.0;
  }

  static int _area(dynamic file) {
    if (file is! Map) return 0;
    final width = _dimension(file['width']);
    final height = _dimension(file['height']);
    return width * height;
  }

  static int _shortEdge(dynamic file) {
    if (file is! Map) return 0;
    final width = _dimension(file['width']);
    final height = _dimension(file['height']);
    if (width <= 0 || height <= 0) return 0;
    return math.min(width, height);
  }

  /// Checks blocked words without a regex end-anchor. Using a padded token set
  /// also avoids treating substrings such as "human" as "woman".
  static bool _bad(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z]+'), ' ')
        .trim();
    if (normalized.isEmpty) return false;

    final words = normalized.split(RegExp(r'\s+')).toSet();
    return _blocked.any((word) => words.contains(word));
  }

  static Set<String> _words(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.length >= 2)
        .toSet();
  }

  static double _topicScore(String searchableText, String query) {
    final wanted = _words(query);
    if (wanted.isEmpty) return 0;
    final available = _words(searchableText);
    var matches = 0;
    for (final word in wanted) {
      if (available.contains(word)) matches++;
    }
    // A relevant subject is more valuable than a small resolution advantage.
    return matches * 3.0;
  }

  static double _orientationScore({
    required int width,
    required int height,
    required bool portrait,
  }) {
    if (width <= 0 || height <= 0) return -8;

    final matchesOrientation = portrait ? height >= width : width >= height;
    if (!matchesOrientation) return -8;

    final ratio = width / height;
    final targetRatio = portrait ? 9 / 16 : 16 / 9;
    final deviation = (ratio - targetRatio).abs();
    return 5.0 - math.min(2.5, deviation * 2.5);
  }

  static double _resolutionScore(int width, int height) {
    final short = math.min(width, height);
    if (short >= 1080) return 5.0;
    if (short >= 720) return 4.0;
    if (short >= 540) return 2.5;
    if (short >= 360) return 1.0;
    return 0;
  }

  static double _durationScore(dynamic rawDuration) {
    final duration = _number(rawDuration);
    if (duration <= 0) return 0.5; // Some providers omit duration metadata.
    if (duration >= 3 && duration <= 18) return 3.0;
    if (duration >= 2 && duration <= 30) return 2.0;
    if (duration <= 60) return 0.75;
    return -1.0;
  }

  static double _videoScore({
    required int width,
    required int height,
    required dynamic duration,
    required String searchableText,
    required String query,
    required bool portrait,
  }) {
    return _topicScore(searchableText, query) +
        _orientationScore(
          width: width,
          height: height,
          portrait: portrait,
        ) +
        _resolutionScore(width, height) +
        _durationScore(duration);
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

  /// Ranks Pexels video results before choosing a video file to download.
  /// Relevance and orientation are considered before raw resolution.
  static List<Map<String, dynamic>> rankPexelsVideos(
    Iterable<dynamic> videos, {
    required String query,
    required bool portrait,
  }) {
    final ranked = <_RankedVideo>[];
    var originalIndex = 0;

    for (final item in videos) {
      final index = originalIndex++;
      if (item is! Map) continue;
      final video = Map<String, dynamic>.from(item);
      final url = video['url'];
      if (url is! String ||
          url.trim().isEmpty ||
          _bad(url) ||
          video['video_files'] is! List) {
        continue;
      }

      var width = _dimension(video['width']);
      var height = _dimension(video['height']);
      if ((width <= 0 || height <= 0) && video['video_files'] is List) {
        final files = rankPexelsFiles(video['video_files'] as List);
        if (files.isNotEmpty) {
          width = _dimension(files.first['width']);
          height = _dimension(files.first['height']);
        }
      }
      if (width <= 0 || height <= 0) continue;
      if (rankPexelsFiles(video['video_files'] as List).isEmpty) continue;

      final score = _videoScore(
        width: width,
        height: height,
        duration: video['duration'],
        searchableText: '$url ${video['image'] ?? ''}',
        query: query,
        portrait: portrait,
      );
      ranked.add(
        _RankedVideo(
          video: video,
          score: score,
          area: width * height,
          originalIndex: index,
        ),
      );
    }

    ranked.sort(_compareRankedVideos);
    return ranked.map((candidate) => candidate.video).toList();
  }

  /// Ranks Pixabay search hits using tags, orientation, duration and size.
  /// Unsafe results and hits without a usable video rendition are discarded.
  static List<Map<String, dynamic>> rankPixabayHits(
    Iterable<dynamic> hits, {
    required String query,
    required bool portrait,
  }) {
    final ranked = <_RankedVideo>[];
    var originalIndex = 0;

    for (final item in hits) {
      final index = originalIndex++;
      if (item is! Map) continue;
      final hit = Map<String, dynamic>.from(item);
      final searchableText = '${hit['tags'] ?? ''} ${hit['pageURL'] ?? ''}';
      if (_bad(searchableText)) continue;

      final videos = hit['videos'];
      if (videos is! Map) continue;
      final rendition = _bestPixabayRendition(videos);
      if (rendition == null) continue;

      final width = _dimension(rendition['width']);
      final height = _dimension(rendition['height']);
      if (width <= 0 || height <= 0) continue;

      final score = _videoScore(
        width: width,
        height: height,
        duration: hit['duration'],
        searchableText: searchableText,
        query: query,
        portrait: portrait,
      );
      ranked.add(
        _RankedVideo(
          video: hit,
          score: score,
          area: width * height,
          originalIndex: index,
        ),
      );
    }

    ranked.sort(_compareRankedVideos);
    return ranked.map((candidate) => candidate.video).toList();
  }

  static int _compareRankedVideos(_RankedVideo a, _RankedVideo b) {
    final scoreOrder = b.score.compareTo(a.score);
    if (scoreOrder != 0) return scoreOrder;
    final areaOrder = b.area.compareTo(a.area);
    if (areaOrder != 0) return areaOrder;
    return a.originalIndex.compareTo(b.originalIndex);
  }

  static Map<String, dynamic>? _bestPixabayRendition(dynamic videos) {
    if (videos is! Map) return null;
    for (final key in <String>['large', 'medium', 'small', 'tiny']) {
      final rendition = videos[key];
      if (rendition is! Map) continue;
      final url = rendition['url'];
      if (url is String &&
          url.trim().isNotEmpty &&
          _dimension(rendition['width']) > 0 &&
          _dimension(rendition['height']) > 0) {
        return Map<String, dynamic>.from(rendition);
      }
    }
    return null;
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

  static T _pickFromTop<T>(List<T> ranked, int pick) {
    final poolLength = math.min(_candidatePoolSize, ranked.length);
    return ranked[pick.abs() % poolLength];
  }

  static Future<void> _discard(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Streams one rendition to [outPath].
  ///
  /// Returns false (and leaves no file behind) when the server answers with an
  /// error, when the clip is larger than [maxClipBytes] (known from the
  /// Content-Length header or reached while receiving), when the connection
  /// goes idle, or when [allowed] runs out.
  static Future<bool> _download(
    String url,
    String outPath,
    Duration allowed,
  ) async {
    final client = http.Client();
    final clock = Stopwatch()..start();
    final output = File(outPath);

    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(_idleTimeout);

      if (response.statusCode != 200) return false;

      // A clip that is too big is skipped at once, before any of it is read.
      final declared = response.contentLength;
      if (declared != null && declared > maxClipBytes) return false;

      await output.parent.create(recursive: true);

      final sink = output.openWrite();
      var received = 0;
      var aborted = false;

      try {
        await for (final chunk in response.stream.timeout(_idleTimeout)) {
          received += chunk.length;

          if (received > maxClipBytes || clock.elapsed > allowed) {
            aborted = true;
            break;
          }

          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }

      if (aborted || received == 0) {
        await _discard(output);
        return false;
      }

      if (await output.exists() && await output.length() > 0) return true;

      await _discard(output);
      return false;
    } catch (_) {
      await _discard(output);
      return false;
    } finally {
      client.close();
    }
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

        final ranked = rankPixabayHits(
          decoded['hits'] as List,
          query: query,
          portrait: portrait,
        );
        if (ranked.isEmpty) return null;

        final selected = _pickFromTop(ranked, pick);
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

        final ranked = rankPexelsVideos(
          decoded['videos'] as List,
          query: query,
          portrait: portrait,
        );
        if (ranked.isEmpty) return null;

        final selected = _pickFromTop(ranked, pick);
        final rawFiles = selected['video_files'];
        if (rawFiles is! List) return null;

        final rankedFiles = rankPexelsFiles(rawFiles);
        if (rankedFiles.isEmpty) return null;

        // Try up to five renditions, highest resolution first. This prevents
        // one oversized HD file from cancelling an otherwise usable B-roll.
        candidates = rankedFiles
            .take(5)
            .map((file) => file['link'] as String)
            .toList();
      }

      final budget = Stopwatch()..start();

      for (final url in candidates) {
        final remaining = _downloadBudget - budget.elapsed;
        if (remaining <= Duration.zero) break;

        // Try the next rendition instead of abandoning the B-roll search.
        if (await _download(url, outPath, remaining)) return outPath;
      }

      return null;
    } catch (_) {
      return null;
    }
  }
}

class _RankedVideo {
  final Map<String, dynamic> video;
  final double score;
  final int area;
  final int originalIndex;

  const _RankedVideo({
    required this.video,
    required this.score,
    required this.area,
    required this.originalIndex,
  });
}
