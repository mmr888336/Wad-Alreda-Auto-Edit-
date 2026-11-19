import 'package:auto_edit/cinematic_world.dart';
import 'package:auto_edit/world_set_pieces.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every set piece of every environment has art', () {
    for (final layout in CinematicWorld.layouts.values) {
      for (final piece in layout.setPieces) {
        expect(WorldSetPieces.has(piece), isTrue, reason: piece);
      }
    }
  });

  test('ids round trip and other ids are not set pieces', () {
    expect(WorldSetPieces.idOf('desk'), 'set:desk');
    expect(WorldSetPieces.nameOf('set:desk'), 'desk');
    expect(WorldSetPieces.nameOf('coins'), isNull);
  });

  test('an unknown piece or an invalid size is refused', () async {
    await expectLater(
      WorldSetPieces.renderPng('nope', width: 10, height: 10),
      throwsArgumentError,
    );
    await expectLater(
      WorldSetPieces.renderPng('desk', width: 0, height: 10),
      throwsArgumentError,
    );
  });

  testWidgets('every piece renders a PNG of the canvas size', (tester) async {
    await tester.runAsync(() async {
      for (final name in WorldSetPieces.names) {
        final bytes =
            await WorldSetPieces.renderPng(name, width: 180, height: 320);
        expect(bytes.length, greaterThan(100), reason: name);
        expect(bytes[0], 0x89, reason: name);
        expect(bytes[1], 0x50, reason: name);
        final width =
            (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
        final height =
            (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
        expect(width, 180, reason: name);
        expect(height, 320, reason: name);
      }
    });
  });
}
