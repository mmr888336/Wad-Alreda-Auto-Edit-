/// World 3D planner: turns the fixed story world into a real 3D scene.
///
/// [CinematicWorld] plans ONE world for the whole video (the same character,
/// one fixed layout per environment) as flat layers with a depth. This planner
/// reads that plan and builds the matching 3D scene for the Filament renderer:
///  * a back wall and a floor in the colour of the environment;
///  * the set pieces of the environment (desk, window, shelves, hills...) as
///    3D objects at their real depth;
///  * the recurring character as one 3D object;
///  * the props the story picked, as pictures standing in the world until each
///    one has a 3D model;
///  * a true 3D camera path chosen from the camera hint of the story.
///
/// The 2D layout is kept: with the camera at rest every object lands exactly
/// where its 2D layer was (see [World3DStage.pointAt]).
/// Pure Dart, no I/O.

import 'cinematic_world.dart';
import 'depth_camera_model.dart';
import 'story_understanding.dart' show StoryEnvironment;
import 'three_d_asset_resolver.dart';
import 'world3d_model.dart';

/// The 3D scene of one beat.
class World3DScene {
  final int beatIndex;
  final StoryEnvironment environment;

  /// Light and atmosphere (tint, key angle, intensity, particles).
  final WorldLook look;
  final World3DStage stage;
  final List<World3DObject> objects;
  final World3DCameraPath camera;

  const World3DScene({
    required this.beatIndex,
    required this.environment,
    required this.look,
    required this.stage,
    required this.objects,
    required this.camera,
  });

  /// The recurring character, or null when the scene has none.
  World3DObject? get character {
    for (final object in objects) {
      if (object.role == World3DRole.character) return object;
    }
    return null;
  }

  List<World3DObject> objectsOf(World3DRole role) =>
      <World3DObject>[for (final o in objects) if (o.role == role) o];
}

/// Shape and place of one set piece, in the normalised canvas of its own
/// plane: centre ([cx], [cy]), size ([w], [h]) as shares of the frame at that
/// depth, and its thickness in metres.
class _Piece {
  final World3DShape shape;
  final double cx;
  final double cy;
  final double w;
  final double h;
  final double thick;
  final String color;

  const _Piece(
    this.shape,
    this.cx,
    this.cy,
    this.w,
    this.h,
    this.thick,
    this.color,
  );
}

class World3DPlanner {
  World3DPlanner._();

  /// Stand-in geometry of the set pieces of [CinematicWorld.layouts]. A name
  /// that is not listed gets a neutral box.
  static const Map<String, _Piece> _pieces = <String, _Piece>{
    'desk': _Piece(World3DShape.box, 0.5, 0.86, 0.9, 0.12, 0.7, '#6B4A2F'),
    'window': _Piece(World3DShape.box, 0.8, 0.3, 0.26, 0.2, 0.1, '#8EC5E8'),
    'wall_clock':
        _Piece(World3DShape.box, 0.5, 0.1, 0.09, 0.05, 0.06, '#F4EFE6'),
    'wall_shelf':
        _Piece(World3DShape.box, 0.5, 0.32, 0.5, 0.03, 0.3, '#7A5634'),
    'rug': _Piece(World3DShape.box, 0.5, 0.93, 0.7, 0.015, 1.6, '#8C3B3B'),
    'lamp_floor':
        _Piece(World3DShape.cylinder, 0.12, 0.66, 0.05, 0.3, 0.05, '#F5A524'),
    'bookshelf_left':
        _Piece(World3DShape.box, 0.14, 0.5, 0.24, 0.6, 0.4, '#5B3A22'),
    'bookshelf_right':
        _Piece(World3DShape.box, 0.86, 0.5, 0.24, 0.6, 0.4, '#5B3A22'),
    'ladder': _Piece(World3DShape.box, 0.9, 0.62, 0.06, 0.5, 0.1, '#8B6B43'),
    'building_row':
        _Piece(World3DShape.box, 0.5, 0.55, 1.0, 0.5, 0.8, '#2C3E4C'),
    'street_lamp':
        _Piece(World3DShape.cylinder, 0.88, 0.5, 0.03, 0.5, 0.03, '#C9C9C9'),
    'kerb': _Piece(World3DShape.box, 0.5, 0.9, 1.0, 0.03, 0.4, '#4A4F55'),
    'monitor_wall':
        _Piece(World3DShape.box, 0.5, 0.3, 0.8, 0.3, 0.1, '#0F1A24'),
    'light_panel':
        _Piece(World3DShape.box, 0.82, 0.15, 0.2, 0.1, 0.06, '#F4EFE6'),
    'cable_tray':
        _Piece(World3DShape.box, 0.5, 0.93, 0.9, 0.02, 0.3, '#2B2F36'),
    'hills': _Piece(World3DShape.sphere, 0.5, 0.82, 1.4, 0.3, 2.0, '#2E5E4E'),
    'sun': _Piece(World3DShape.sphere, 0.78, 0.14, 0.14, 0.08, 0.14, '#F5A524'),
    'path': _Piece(World3DShape.box, 0.5, 0.95, 0.5, 0.015, 2.0, '#8A7456'),
  };

  static const _Piece _unknownPiece =
      _Piece(World3DShape.box, 0.5, 0.5, 0.3, 0.3, 0.3, '#555B66');

  /// True when [shapeName] has hand-made stand-in geometry.
  static bool hasPiece(String shapeName) => _pieces.containsKey(shapeName);

  /// A `decor:` layer of scale 0.9 or more is a set piece (a full-canvas
  /// picture in 2D); a smaller one is a prop that sits in a slot. Same rule as
  /// the story world bridge.
  static bool isSetPiece(String assetKey, double scale) =>
      assetKey.startsWith('decor:') && scale >= 0.9;

  static String _shade(String hex, double factor) {
    if (hex.length != 7 || !hex.startsWith('#')) return '#000000';
    final value = int.tryParse(hex.substring(1), radix: 16);
    if (value == null) return '#000000';
    int channel(int shift) =>
        (((value >> shift) & 0xFF) * factor).round().clamp(0, 255).toInt();
    final r = channel(16).toRadixString(16).padLeft(2, '0');
    final g = channel(8).toRadixString(16).padLeft(2, '0');
    final b = channel(0).toRadixString(16).padLeft(2, '0');
    return '#${r.toUpperCase()}${g.toUpperCase()}${b.toUpperCase()}';
  }

  /// The back wall and the floor. Both are wider than the frame, so an orbit
  /// never shows their edges.
  static List<World3DObject> _room(
    World3DStage stage,
    String wallColor,
    String idBase,
  ) {
    final far = stage.farDistance;
    final frameHeight = stage.frameHeightAt(far);
    final frameWidth = stage.frameWidthAt(far);
    final wallZ = stage.cameraZ - far;
    final floorLength = far - 1.0;
    return <World3DObject>[
      World3DObject(
        id: '${idBase}_wall',
        role: World3DRole.backWall,
        shape: World3DShape.box,
        assetKey: 'bg:wall',
        position: Vec3(0, stage.cameraHeight, wallZ - 0.025),
        size: Vec3(frameWidth * 1.6, frameHeight * 1.6, 0.05),
        color: wallColor,
      ),
      World3DObject(
        id: '${idBase}_floor',
        role: World3DRole.floor,
        shape: World3DShape.box,
        position: Vec3(0, -0.025, stage.cameraZ - 1.0 - floorLength / 2),
        size: Vec3(frameWidth * 1.6, 0.05, floorLength),
        color: _shade(wallColor, 0.65),
      ),
    ];
  }

  /// The 3D scene of [scene].
  ///
  /// [move] and [intensity] are the camera of the scene (usually from the
  /// camera hint of the story, see CameraHintBridge); the camera orbits and
  /// zooms on the character.
  static World3DScene plan(
    WorldScene scene, {
    World3DStage stage = const World3DStage(),
    WorldCharacter character = const WorldCharacter(),
    DepthCameraMove move = DepthCameraMove.none,
    double intensity = 0.8,
    Map<String, ResolvedAsset> resolved = const <String, ResolvedAsset>{},
  }) {
    final layout = CinematicWorld.layouts[scene.environment];
    final wallColor = layout?.backdropColor ?? '#1E2230';
    final idBase = 'w${scene.beatIndex}';

    final objects = <World3DObject>[..._room(stage, wallColor, idBase)];
    var subjectDepth = WorldCharacter.depth;

    for (final spec in scene.layers) {
      final key = spec.assetKey;

      if (key.startsWith('sprite:')) {
        subjectDepth = spec.depth;
        final distance = stage.distanceOf(spec.depth);
        final width = spec.scale * stage.frameWidthAt(distance);
        objects.add(
          World3DObject(
            id: spec.id,
            role: World3DRole.character,
            shape: World3DShape.character,
            assetKey: key,
            position: stage.pointAt(spec.x, spec.y, spec.depth),
            size: Vec3(width, width * 1.6, width * 0.5),
            color: character.bodyColor,
          ),
        );
        continue;
      }

      if (key.startsWith('decor:')) {
        final distance = stage.distanceOf(spec.depth);
        final frameHeight = stage.frameHeightAt(distance);
        final frameWidth = stage.frameWidthAt(distance);

        if (isSetPiece(key, spec.scale)) {
          final name = key.substring('decor:'.length);
          final piece = _pieces[name] ?? _unknownPiece;
          objects.add(
            World3DObject(
              id: spec.id,
              role: World3DRole.setPiece,
              shape: piece.shape,
              assetKey: key,
              position: stage.pointAt(piece.cx, piece.cy, spec.depth),
              size: Vec3(
                piece.w * frameWidth,
                piece.h * frameHeight,
                piece.thick,
              ),
              color: piece.color,
            ),
          );
        } else {
          final width = spec.scale * frameWidth;
          final resolvedAsset = resolved[key];
          final localPath = resolvedAsset?.localPath;
          if (localPath != null && localPath.isNotEmpty) {
            objects.add(
              World3DObject(
                id: spec.id,
                role: World3DRole.prop,
                shape: World3DShape.model,
                assetKey: key,
                position: stage.pointAt(spec.x, spec.y, spec.depth),
                size: Vec3(width, width, 0.02),
                color: '#FFFFFF',
                modelPath: localPath,
              ),
            );
          } else {
            objects.add(
              World3DObject(
                id: spec.id,
                role: World3DRole.prop,
                shape: World3DShape.billboard,
                assetKey: key,
                position: stage.pointAt(spec.x, spec.y, spec.depth),
                size: Vec3(width, width, 0.02),
                color: '#FFFFFF',
              ),
            );
          }
        }
      }
      // Backdrops (`bg:`), text and effects are not 3D objects: the room is
      // built from the environment, titles and effects stay in the 2.5D engine.
    }

    return World3DScene(
      beatIndex: scene.beatIndex,
      environment: scene.environment,
      look: scene.look,
      stage: stage,
      objects: objects,
      camera: World3DCameraPath(
        stage: stage,
        move: move,
        intensity: intensity,
        subjectDepth: subjectDepth,
      ),
    );
  }
}
