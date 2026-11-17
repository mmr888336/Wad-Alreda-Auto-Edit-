import 'three_d_asset_service.dart';

/// A small, reliable model from the Khronos glTF sample library (direct GLB
/// files on GitHub). It is the safety net used when the online libraries
/// return nothing relevant for a scene.
class KhronosModel {
  final String name;
  final List<String> tags;

  const KhronosModel(this.name, this.tags);

  String get url =>
      'https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/main/Models/$name/glTF-Binary/$name.glb';
}

class KhronosModelCatalog {
  KhronosModelCatalog._();

  // Tags are matched with "contains" in both directions, so very short tags
  // (for example "ai" or "gem") would match unrelated words such as "train"
  // or "management". Keep tags at four letters or more.
  static const List<KhronosModel> models = <KhronosModel>[
    KhronosModel('Lantern', <String>['lantern', 'lamp', 'light', 'candle', 'crescent', 'hope', 'idea', 'guide', 'night']),
    KhronosModel('Avocado', <String>['avocado', 'fruit', 'food']),
    KhronosModel('AntiqueCamera', <String>['camera', 'photo', 'video', 'film', 'antique', 'cinema', 'movie', 'memory', 'story']),
    KhronosModel('BoomBox', <String>['radio', 'speaker', 'music', 'boombox', 'sound', 'audio', 'microphone']),
    KhronosModel('BarramundiFish', <String>['fish', 'sea', 'ocean', 'animal']),
    KhronosModel('DamagedHelmet', <String>['helmet', 'robot', 'space', 'technology', 'shield', 'future', 'innovation', 'cyber']),
    KhronosModel('Duck', <String>['duck', 'bird', 'toy', 'animal']),
    KhronosModel('Fox', <String>['fox', 'animal', 'nature', 'wildlife']),
    KhronosModel('WaterBottle', <String>['bottle', 'water', 'drink']),
    KhronosModel('SheenChair', <String>['chair', 'furniture', 'seat', 'room', 'house']),
    KhronosModel('ToyCar', <String>['car', 'toy', 'vehicle']),
    KhronosModel('CesiumMilkTruck', <String>['truck', 'vehicle', 'delivery', 'transport']),
    KhronosModel('Buggy', <String>['buggy', 'car', 'vehicle', 'road']),
    KhronosModel('BrainStem', <String>['robot', 'machine', 'technology', 'brain']),
    KhronosModel('ABeautifulGame', <String>['chess', 'game', 'strategy', 'board', 'scale', 'balance']),
    KhronosModel('GlamVelvetSofa', <String>['sofa', 'couch', 'furniture', 'house']),
    KhronosModel('MosquitoInAmber', <String>['amber', 'mosquito', 'insect', 'time', 'hourglass', 'clock', 'crystal', 'gold', 'coins', 'luxury', 'premium', 'diamond', 'jewel', 'wealth', 'money', 'rich', 'value', 'treasure', 'abstract']),
  ];

  /// Models used when no keyword matches. Only warm, metallic, cinematic
  /// models belong here: they look like motion graphics when blended over a
  /// video. Toys, animals and furniture are never used as a blind fallback.
  static const List<String> fallbackNames = <String>[
    'MosquitoInAmber',
    'Lantern',
    'AntiqueCamera',
    'DamagedHelmet',
  ];

  /// Models whose tags match the keywords, best match first.
  static List<KhronosModel> match(List<String> keywords) {
    final wanted = keywords.map((k) => k.toLowerCase().trim()).where((k) => k.isNotEmpty).toList();
    if (wanted.isEmpty) return const <KhronosModel>[];

    final scored = <MapEntry<KhronosModel, int>>[];
    for (final model in models) {
      var score = 0;
      for (var i = 0; i < wanted.length; i++) {
        final keyword = wanted[i];
        final hit = model.tags.any((tag) => tag == keyword || keyword.contains(tag) || tag.contains(keyword));
        // Earlier keywords are more relevant.
        if (hit) score += wanted.length - i;
      }
      if (score > 0) scored.add(MapEntry<KhronosModel, int>(model, score));
    }

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((entry) => entry.key).toList();
  }

  static KhronosModel fallbackFor(int index) {
    final name = fallbackNames[index.abs() % fallbackNames.length];
    return models.firstWhere((model) => model.name == name);
  }

  static ThreeDAsset asset(KhronosModel model) {
    return ThreeDAsset(
      id: 'khronos_${model.name}',
      title: 'Khronos ${model.name}',
      provider: ThreeDAssetProvider.polyHaven,
      license: 'Khronos sample asset',
      downloadUrl: model.url,
    );
  }
}
