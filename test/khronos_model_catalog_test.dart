import 'package:auto_edit/khronos_model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KhronosModelCatalog', () {
    test('matches models by keyword, best first', () {
      final matches = KhronosModelCatalog.match(<String>['lantern', 'book']);

      expect(matches, isNotEmpty);
      expect(matches.first.name, 'Lantern');
    });

    test('earlier keywords weigh more', () {
      final matches = KhronosModelCatalog.match(<String>['robot', 'fish']);
      final robotIndex = matches.indexWhere((m) => m.tags.contains('robot'));
      final fishIndex = matches.indexWhere((m) => m.name == 'BarramundiFish');

      expect(robotIndex, greaterThanOrEqualTo(0));
      expect(fishIndex, greaterThanOrEqualTo(0));
      expect(robotIndex, lessThan(fishIndex));
    });

    test('unknown keywords match nothing', () {
      expect(KhronosModelCatalog.match(<String>['zzzzqq']), isEmpty);
      expect(KhronosModelCatalog.match(<String>[]), isEmpty);
    });

    test('builds a direct GLB download asset', () {
      final asset = KhronosModelCatalog.asset(KhronosModelCatalog.models.first);

      expect(asset.downloadUrl, startsWith('https://raw.githubusercontent.com/'));
      expect(asset.downloadUrl, endsWith('.glb'));
      expect(asset.id, startsWith('khronos_'));
    });

    test('every fallback name exists in the catalog', () {
      for (var i = 0; i < 10; i++) {
        expect(KhronosModelCatalog.fallbackFor(i).name, isNotEmpty);
      }
    });
  });
}
