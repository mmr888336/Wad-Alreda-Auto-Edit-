import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'settings.dart';

enum ThreeDAssetProvider { sketchfab, polyHaven, huggingFace }

class ThreeDAsset {
  final String id;
  final String title;
  final ThreeDAssetProvider provider;
  final String? previewUrl;
  final String? license;
  final String? downloadUrl;
  final String? filePath;

  const ThreeDAsset({
    required this.id,
    required this.title,
    required this.provider,
    this.previewUrl,
    this.license,
    this.downloadUrl,
    this.filePath,
  });

  ThreeDAsset copyWith({String? downloadUrl, String? filePath}) => ThreeDAsset(
        id: id,
        title: title,
        provider: provider,
        previewUrl: previewUrl,
        license: license,
        downloadUrl: downloadUrl ?? this.downloadUrl,
        filePath: filePath ?? this.filePath,
      );

  String get providerLabel {
    switch (provider) {
      case ThreeDAssetProvider.sketchfab:
        return 'Sketchfab';
      case ThreeDAssetProvider.polyHaven:
        return 'Poly Haven';
      case ThreeDAssetProvider.huggingFace:
        return 'Hugging Face';
    }
  }
}

/// Connects the credentials already stored by AppSettings to real 3D asset APIs.
/// Only self-contained GLB downloads are accepted in this phase; loose glTF/ZIP
/// packages are rejected instead of being passed to Filament as broken files.
class ThreeDAssetService {
  ThreeDAssetService({required this.settings, http.Client? client})
      : _client = client ?? http.Client();

  final AppSettings settings;
  final http.Client _client;
  final List<String> warnings = <String>[];

  static const int maxModelBytes = 80 * 1024 * 1024;

  static bool isValidGlb(Uint8List bytes) {
    if (bytes.length < 20) return false;
    if (bytes[0] != 0x67 || bytes[1] != 0x6c ||
        bytes[2] != 0x54 || bytes[3] != 0x46) return false;
    final data = ByteData.sublistView(bytes);
    return data.getUint32(4, Endian.little) == 2 &&
        data.getUint32(8, Endian.little) == bytes.length;
  }

  Future<List<ThreeDAsset>> search(String query) async {
    final text = query.trim();
    if (text.length < 2) {
      throw ArgumentError('اكتب اسم المجسم أو المشهد بصورة أوضح.');
    }
    if (!settings.online3DAssetsEnabled) {
      throw StateError('فعّل Prefer online 3D assets من الإعدادات أولاً.');
    }

    warnings.clear();
    final results = await Future.wait<List<ThreeDAsset>>([
      _safeSearch('Sketchfab', () => _searchSketchfab(text)),
      _safeSearch('Poly Haven', () => _searchPolyHaven(text)),
      _safeSearch('Hugging Face', () => _searchHuggingFace(text)),
    ]);

    final all = results.expand((items) => items).toList();
    final seen = <String>{};
    return all.where((asset) => seen.add('${asset.provider.name}:${asset.id}')).toList();
  }

  Future<List<ThreeDAsset>> _safeSearch(
    String provider,
    Future<List<ThreeDAsset>> Function() action,
  ) async {
    try {
      return await action();
    } catch (error) {
      warnings.add('$provider: $error');
      return <ThreeDAsset>[];
    }
  }

  Future<List<ThreeDAsset>> _searchSketchfab(String query) async {
    final token = settings.sketchfabToken.trim();
    if (token.isEmpty) {
      warnings.add('Sketchfab: أضف API Token من الإعدادات.');
      return <ThreeDAsset>[];
    }

    final uri = Uri.https('api.sketchfab.com', '/v3/search', {
      'type': 'models',
      'downloadable': 'true',
      'q': query,
      'count': '8',
    });
    final response = await _client.get(uri, headers: {
      'Authorization': 'Token $token',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 25));
    _checkResponse('Sketchfab search', response);

    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final rows = (json['results'] as List? ?? const <dynamic>[]).whereType<Map>();
    return rows.map((row) {
      final thumbnail = row['thumbnails'];
      String? preview;
      if (thumbnail is Map) {
        final images = thumbnail['images'];
        if (images is List && images.isNotEmpty && images.first is Map) {
          preview = (images.first as Map)['url']?.toString();
        }
      }
      final license = row['license'];
      return ThreeDAsset(
        id: '${row['uid'] ?? ''}',
        title: '${row['name'] ?? 'Sketchfab model'}',
        provider: ThreeDAssetProvider.sketchfab,
        previewUrl: preview,
        license: license is Map ? license['label']?.toString() : null,
      );
    }).where((asset) => asset.id.isNotEmpty).toList();
  }

  Future<List<ThreeDAsset>> _searchPolyHaven(String query) async {
    final uri = Uri.https('api.polyhaven.com', '/assets', {'t': 'models'});
    final response = await _client.get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 25));
    _checkResponse('Poly Haven assets', response);

    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map) return <ThreeDAsset>[];
    final terms = query.toLowerCase().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final matches = <MapEntry<String, dynamic>>[];
    for (final entry in json.entries) {
      final id = entry.key.toLowerCase();
      final label = entry.value is Map ? '${entry.value['name'] ?? id}'.toLowerCase() : id;
      final score = terms.where((term) => id.contains(term) || label.contains(term)).length;
      if (score > 0) matches.add(MapEntry(entry.key, entry.value));
    }
    matches.sort((a, b) => b.key.length.compareTo(a.key.length));

    final assets = <ThreeDAsset>[];
    for (final item in matches.take(8)) {
      String? preview;
      if (item.value is Map) {
        preview = (item.value as Map)['thumbnail_url']?.toString() ??
            (item.value as Map)['thumbnail']?.toString();
      }
      final fileUrl = await _polyHavenGlbUrl(item.key);
      if (fileUrl == null) continue;
      assets.add(ThreeDAsset(
        id: item.key,
        title: item.value is Map
            ? '${(item.value as Map)['name'] ?? item.key}'
            : item.key,
        provider: ThreeDAssetProvider.polyHaven,
        previewUrl: preview,
        license: 'CC0 — راجع صفحة الأصل',
        downloadUrl: fileUrl,
      ));
    }
    return assets;
  }

  Future<String?> _polyHavenGlbUrl(String id) async {
    final uri = Uri.https('api.polyhaven.com', '/files/$id');
    final headers = <String, String>{'Accept': 'application/json'};
    if (settings.polyHavenApiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${settings.polyHavenApiKey.trim()}';
    }
    final response = await _client.get(uri, headers: headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return null;
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    return _findGlbUrl(json);
  }

  Future<List<ThreeDAsset>> _searchHuggingFace(String query) async {
    final token = settings.objaverseToken.trim();
    if (token.isEmpty) {
      warnings.add('Hugging Face: أضف Token في خانة Hugging Face / Objaverse.');
      return <ThreeDAsset>[];
    }
    final uri = Uri.https('huggingface.co', '/api/models', {
      'search': query,
      'limit': '12',
      'full': 'true',
    });
    final response = await _client.get(uri, headers: {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 25));
    _checkResponse('Hugging Face model search', response);

    final modelRows = (jsonDecode(utf8.decode(response.bodyBytes)) as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((row) => <String, dynamic>{'id': row['id'], 'kind': 'model', 'cardData': row['cardData']})
        .toList();

    // Objaverse files are often published as datasets rather than model repos.
    final datasetUri = Uri.https('huggingface.co', '/api/datasets', {
      'search': query,
      'limit': '8',
      'full': 'true',
    });
    final datasetResponse = await _client.get(datasetUri, headers: {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 25));
    final datasetRows = <Map<String, dynamic>>[];
    if (datasetResponse.statusCode == 200) {
      final rawDatasets = jsonDecode(utf8.decode(datasetResponse.bodyBytes));
      if (rawDatasets is List) {
        for (final row in rawDatasets.whereType<Map>().take(8)) {
          datasetRows.add(<String, dynamic>{'id': row['id'], 'kind': 'dataset', 'cardData': row['cardData']});
        }
      }
    } else {
      warnings.add('Hugging Face datasets: HTTP ${datasetResponse.statusCode}');
    }

    final assets = <ThreeDAsset>[];
    for (final row in [...modelRows.take(8), ...datasetRows.take(8)]) {
      final id = '${row['id'] ?? ''}';
      if (id.isEmpty) continue;
      final kind = '${row['kind']}';
      final route = kind == 'dataset' ? '/api/datasets/$id/tree/main' : '/api/models/$id/tree/main';
      final treeUri = Uri.https('huggingface.co', route, {
        'recursive': 'true',
        'expand': 'false',
      });
      final treeResponse = await _client.get(treeUri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 20));
      if (treeResponse.statusCode != 200) continue;
      final files = jsonDecode(utf8.decode(treeResponse.bodyBytes));
      if (files is! List) continue;
      final glb = files.whereType<Map>().firstWhere(
        (file) => '${file['path'] ?? ''}'.toLowerCase().endsWith('.glb'),
        orElse: () => <String, dynamic>{},
      );
      final path = '${glb['path'] ?? ''}';
      if (path.isEmpty) continue;
      final encodedPath = path.split('/').map(Uri.encodeComponent).join('/');
      final prefix = kind == 'dataset' ? '/datasets/' : '/';
      final download = 'https://huggingface.co$prefix$id/resolve/main/$encodedPath';
      assets.add(ThreeDAsset(
        id: '$kind|$id::$path',
        title: '$id — ${path.split('/').last}',
        provider: ThreeDAssetProvider.huggingFace,
        previewUrl: null,
        license: (row['cardData'] is Map)
            ? (row['cardData'] as Map)['license']?.toString()
            : null,
        downloadUrl: download,
      ));
    }
    return assets;
  }

  String? _findGlbUrl(Object? node) {
    if (node is Map) {
      for (final entry in node.entries) {
        final key = '${entry.key}'.toLowerCase();
        final value = entry.value;
        if (key.contains('glb')) {
          if (value is String && value.startsWith('http')) return value;
          if (value is Map) {
            final url = value['url'] ?? value['download'] ?? value['href'];
            if (url is String && url.startsWith('http')) return url;
          }
        }
        final nested = _findGlbUrl(value);
        if (nested != null) return nested;
      }
      final url = node['url'] ?? node['download'] ?? node['href'];
      if (url is String && url.toLowerCase().contains('.glb')) return url;
    } else if (node is List) {
      for (final value in node) {
        final nested = _findGlbUrl(value);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  Future<String> download(ThreeDAsset asset) async {
    String url = asset.downloadUrl ?? '';
    final headers = <String, String>{'Accept': '*/*'};

    if (asset.provider == ThreeDAssetProvider.sketchfab) {
      final token = settings.sketchfabToken.trim();
      if (token.isEmpty) throw StateError('Sketchfab API Token غير موجود.');
      final response = await _client.get(
        Uri.https('api.sketchfab.com', '/v3/models/${asset.id}/download'),
        headers: {'Authorization': 'Token $token', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));
      _checkResponse('Sketchfab model download request', response);
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final glb = json['glb'];
      if (glb is Map && glb['url'] is String) {
        url = glb['url'] as String;
      } else {
        throw StateError(
          'Sketchfab أعاد حزمة glTF/ZIP وليس ملف GLB مستقل. لن نمرر ملفاً غير مدعوم للمحرك.',
        );
      }
    } else if (asset.provider == ThreeDAssetProvider.huggingFace) {
      final token = settings.objaverseToken.trim();
      if (token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    }

    if (url.isEmpty) throw StateError('رابط تحميل GLB غير متوفر لهذا الأصل.');
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw StateError('رابط تنزيل المجسم غير صالح.');
    }

    final request = http.Request('GET', uri)..headers.addAll(headers);
    final streamed = await _client.send(request).timeout(const Duration(seconds: 90));
    if (streamed.statusCode != 200) {
      throw HttpException('فشل تنزيل ${asset.providerLabel}: HTTP ${streamed.statusCode}');
    }
    final directory = await getApplicationSupportDirectory();
    final modelDirectory = Directory('${directory.path}/WadAlredaStudio/3DModels');
    await modelDirectory.create(recursive: true);
    final safeName = asset.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final output = File('${modelDirectory.path}/${asset.provider.name}_$safeName.glb');
    final sink = output.openWrite();
    var total = 0;
    try {
      await for (final chunk in streamed.stream) {
        total += chunk.length;
        if (total > maxModelBytes) {
          throw StateError('حجم المجسم تجاوز الحد الآمن (${maxModelBytes ~/ (1024 * 1024)} MB).');
        }
        sink.add(chunk);
      }
      await sink.flush();
    } catch (_) {
      await sink.close();
      if (await output.exists()) await output.delete();
      rethrow;
    }
    await sink.close();

    final handle = await output.open();
    final head = await handle.read(12);
    await handle.close();
    if (total < 20 || head.length < 12 ||
        head[0] != 0x67 || head[1] != 0x6c || head[2] != 0x54 || head[3] != 0x46 ||
        ByteData.sublistView(head).getUint32(4, Endian.little) != 2 ||
        ByteData.sublistView(head).getUint32(8, Endian.little) != total) {
      await output.delete();
      throw FormatException('الملف المنزّل ليس GLB صالحاً بإصدار 2.');
    }
    return output.path;
  }

  static void _checkResponse(String operation, http.Response response) {
    if (response.statusCode != 200) {
      final body = response.body.length > 240
          ? response.body.substring(0, 240)
          : response.body;
      throw HttpException('$operation: HTTP ${response.statusCode} $body');
    }
  }

  void dispose() => _client.close();
}
