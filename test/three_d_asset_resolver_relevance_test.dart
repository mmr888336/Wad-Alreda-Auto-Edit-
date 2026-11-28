import 'package:auto_edit/three_d_asset_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThreeDAssetResolver.relevanceScore', () {
    test('a good match clears the threshold', () {
      final score = ThreeDAssetResolver.relevanceScore(
        <String>['lantern', 'light'],
        title: 'Khronos Lantern',
        tags: <String>['lantern', 'lamp', 'light'],
      );

      expect(score, greaterThanOrEqualTo(ThreeDAssetResolver.minRelevance));
    });

    test('an unrelated asset scores below the threshold', () {
      final score = ThreeDAssetResolver.relevanceScore(
        <String>['lantern', 'light'],
        title: 'Khronos Duck',
        id: 'khronos_Duck',
        tags: <String>['duck', 'bird', 'toy'],
      );

      expect(score, lessThan(ThreeDAssetResolver.minRelevance));
    });

    test('an empty keyword list scores zero', () {
      final score = ThreeDAssetResolver.relevanceScore(
        const <String>[],
        title: 'Khronos Lantern',
        tags: <String>['lantern'],
      );

      expect(score, 0);
    });
  });
}
