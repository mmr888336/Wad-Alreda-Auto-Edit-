import 'khronos_model_catalog.dart';
import 'settings.dart';
import 'three_d_asset_service.dart';
import 'three_d_query_planner.dart';

/// One 3D asset request for a single beat of the story.
class ThreeDAssetRequest {
  final String beat;
  final String? zone;
  final String? shot;
  final String? caption;
  final List<String> keywords;

  const ThreeDAssetRequest({
    required this.beat,
    this.zone,
    this.shot,
    this.caption,
    this.keywords = const <String>[],
  });

  /// The text used to derive keywords when none were supplied.
  String get text {
    final parts = <String>[
      if (caption != null && caption!.trim().isNotEmpty) caption!.trim(),
      if (shot != null && shot!.trim().isNotEmpty) shot!.trim(),
      if (zone != null && zone!.trim().isNotEmpty) zone!.trim(),
      if (beat.trim().isNotEmpty) beat.trim(),
    ];
    return parts.join(' ');
  }
}

/// A resolved 3D asset: the catalog/service entry, an optional local GLB path
/// and the keywords that produced it.
class ResolvedAsset {
  final ThreeDAsset asset;
  final String? localPath;
  final List<String> keywords;
  final bool fromCatalog;

  const ResolvedAsset({
    required this.asset,
    required this.keywords,
    this.localPath,
    this.fromCatalog = false,
  });

  ResolvedAsset copyWith({String? localPath}) => ResolvedAsset(
        asset: asset,
        keywords: keywords,
        localPath: localPath ?? this.localPath,
        fromCatalog: fromCatalog,
      );
}

/// Resolves 3D assets for story beats.
///
/// It reuses the existing [ThreeDAssetService] (no new HTTP client, no new
/// cache) and [ThreeDQueryPlanner] for keyword extraction. Resolution order:
///   1. [KhronosModelCatalog.match] on the keywords (offline, reliable).
///   2. [ThreeDAssetService.search] with the first keyword.
///   3. [KhronosModelCatalog.fallbackFor] as a last resort.
class ThreeDAssetResolver {
  ThreeDAssetResolver({required this.service, required this.settings});

  final ThreeDAssetService service;
  final AppSettings settings;

  /// Keywords for [request], best first. Never empty.
  Future<List<String>> keywordsFor(ThreeDAssetRequest request) async {
    if (request.keywords.isNotEmpty) {
      return List<String>.unmodifiable(request.keywords);
    }
    final text = request.text;
    if (text.trim().isEmpty) {
      return List<String>.unmodifiable(ThreeDQueryPlanner.fallbackKeywords);
    }
    return ThreeDQueryPlanner.keywords(settings, text);
  }

  /// Resolves [request] to a [ResolvedAsset] without downloading it.
  Future<ResolvedAsset> resolve(ThreeDAssetRequest request) async {
    final keywords = await keywordsFor(request);

    final catalogMatches = KhronosModelCatalog.match(keywords);
    if (catalogMatches.isNotEmpty) {
      return ResolvedAsset(
        asset: KhronosModelCatalog.asset(catalogMatches.first),
        keywords: keywords,
        fromCatalog: true,
      );
    }

    if (keywords.isNotEmpty) {
      try {
        final results = await service.search(keywords.first);
        if (results.isNotEmpty) {
          return ResolvedAsset(asset: results.first, keywords: keywords);
        }
      } catch (_) {
        // Fall through to the catalog fallback below.
      }
    }

    final fallback = KhronosModelCatalog.fallbackFor(0);
    return ResolvedAsset(
      asset: KhronosModelCatalog.asset(fallback),
      keywords: keywords,
      fromCatalog: true,
    );
  }

  /// Resolves [request] and downloads the GLB, returning the local path.
  ///
  /// [onInspecting] is forwarded to [ThreeDAssetService.download] so the
  /// caller can log the download and inspection as separate stages.
  Future<ResolvedAsset> resolveAndDownload(
    ThreeDAssetRequest request, {
    void Function()? onInspecting,
  }) async {
    final resolved = await resolve(request);
    final path = await service.download(
      resolved.asset,
      onInspecting: onInspecting,
    );
    return resolved.copyWith(localPath: path);
  }

  /// Resolves every prop of a beat with a single search.
  ///
  /// [props] maps an `assetKey` to the text describing that prop. The beat is
  /// searched once (using [beatText]); the returned assets are then assigned
  /// to props by keyword matching. The result is keyed by `assetKey`.
  Future<Map<String, ResolvedAsset>> resolveForBeat({
    required String beatText,
    required Map<String, String> props,
    String? zone,
    String? shot,
    String? caption,
  }) async {
    if (props.isEmpty) return <String, ResolvedAsset>{};

    final beatRequest = ThreeDAssetRequest(
      beat: beatText,
      zone: zone,
      shot: shot,
      caption: caption,
    );
    final beatKeywords = await keywordsFor(beatRequest);

    // One search for the whole beat.
    final pool = <ThreeDAsset>[];
    if (beatKeywords.isNotEmpty) {
      try {
        pool.addAll(await service.search(beatKeywords.first));
      } catch (_) {
        // The catalog fallback below still produces assets.
      }
    }

    final catalogPool = KhronosModelCatalog.match(beatKeywords);
    final result = <String, ResolvedAsset>{};

    for (final entry in props.entries) {
      final assetKey = entry.key;
      final propText = entry.value;
      final propKeywords = propText.trim().isEmpty
          ? beatKeywords
          : await keywordsFor(ThreeDAssetRequest(beat: propText));

      final matched = _pickFromPool(pool, propKeywords);
      if (matched != null) {
        result[assetKey] = ResolvedAsset(
          asset: matched,
          keywords: propKeywords,
        );
        continue;
      }

      final catalogMatch = _pickFromCatalog(catalogPool, propKeywords);
      if (catalogMatch != null) {
        result[assetKey] = ResolvedAsset(
          asset: KhronosModelCatalog.asset(catalogMatch),
          keywords: propKeywords,
          fromCatalog: true,
        );
        continue;
      }

      final fallback = KhronosModelCatalog.fallbackFor(result.length);
      result[assetKey] = ResolvedAsset(
        asset: KhronosModelCatalog.asset(fallback),
        keywords: propKeywords,
        fromCatalog: true,
      );
    }

    return result;
  }

  ThreeDAsset? _pickFromPool(List<ThreeDAsset> pool, List<String> keywords) {
    if (pool.isEmpty) return null;
    if (keywords.isEmpty) return pool.first;

    for (final keyword in keywords) {
      final lower = keyword.toLowerCase();
      for (final asset in pool) {
        final haystack = '${asset.title} ${asset.id}'.toLowerCase();
        if (haystack.contains(lower)) return asset;
      }
    }
    return pool.first;
  }

  KhronosModel? _pickFromCatalog(
    List<KhronosModel> pool,
    List<String> keywords,
  ) {
    if (pool.isEmpty) return null;
    if (keywords.isEmpty) return pool.first;

    for (final keyword in keywords) {
      final lower = keyword.toLowerCase();
      for (final model in pool) {
        final haystack = '${model.name} ${model.tags.join(' ')}'.toLowerCase();
        if (haystack.contains(lower)) return model;
      }
    }
    return pool.first;
  }
}
