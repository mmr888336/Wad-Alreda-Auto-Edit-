/// Cinematic world: one environment set and one main character for the whole
/// video.
///
/// Instead of rebuilding a different little world for every scene, the world
/// is planned once from the [StoryPlan]:
///  * ONE fixed main character, the same in every scene (not a small icon);
///  * each environment (office, room, library, ...) has ONE fixed layout, so
///    coming back to the office later rebuilds the very same office;
///  * the secondary objects of a scene are picked by the meaning of the
///    sentence and put in fixed slots of that layout, never on the face;
///  * one unified look (palette, key light, shadow, particles) for the whole
///    video, only its intensity follows the mood of a scene.
///
/// The output is renderer-neutral data ([WorldLayerSpec]); every layer has a
/// depth (0 far .. 1 near) so the depth camera and the person matte can put
/// things behind and in front of the speaker. Pure Dart, no I/O.
library;

import 'story_understanding.dart';

/// The one palette of the video (red / amber / teal), as `#RRGGBB`.
class WorldPalette {
  final String red;
  final String amber;
  final String teal;
  final String dark;
  final String light;

  const WorldPalette({
    this.red = '#D7263D',
    this.amber = '#F5A524',
    this.teal = '#1B998B',
    this.dark = '#14141A',
    this.light = '#F4EFE6',
  });
}

/// The main character, fixed for the whole video.
class WorldCharacter {
  final String id;
  final String assetKey;
  final String bodyColor;
  final String accentColor;

  /// Resting place (normalised) and size (share of the canvas width).
  final double x;
  final double y;
  final double scale;

  const WorldCharacter({
    this.id = 'hero',
    this.assetKey = 'sprite:hero',
    this.bodyColor = '#F5A524',
    this.accentColor = '#D7263D',
    this.x = 0.5,
    this.y = 0.62,
    this.scale = 0.42,
  });

  /// Depth of the character (matches the depth camera rule for sprites).
  static const double depth = 0.62;
}

/// Light and atmosphere of the video.
class WorldLook {
  final String tint;
  final double keyAngleDegrees;
  final double intensity;
  final double shadowOpacity;
  final double vignette;
  final String particleKind;
  final double particleDensity;

  const WorldLook({
    required this.tint,
    required this.keyAngleDegrees,
    required this.intensity,
    required this.shadowOpacity,
    required this.vignette,
    required this.particleKind,
    required this.particleDensity,
  });
}

/// One place of a layout where a secondary object can stand.
class WorldSlot {
  final double x;
  final double y;
  final double scale;

  /// 0 far .. 1 near. Slots above [WorldCharacter.depth] are in front of the
  /// speaker, the others behind.
  final double depth;

  const WorldSlot({
    required this.x,
    required this.y,
    required this.scale,
    required this.depth,
  });
}

/// The fixed layout of one environment.
class WorldLayout {
  final StoryEnvironment environment;
  final String backdropKey;
  final String backdropColor;
  final List<String> setPieces;
  final List<WorldSlot> slots;

  const WorldLayout({
    required this.environment,
    required this.backdropKey,
    required this.backdropColor,
    required this.setPieces,
    required this.slots,
  });
}

/// One layer of the world, ready to become a motion layer.
class WorldLayerSpec {
  final String id;
  final String assetKey;
  final double x;
  final double y;
  final double scale;
  final double depth;
  final int zIndex;

  const WorldLayerSpec({
    required this.id,
    required this.assetKey,
    required this.x,
    required this.y,
    required this.scale,
    required this.depth,
    required this.zIndex,
  });
}

/// The world of one beat.
class WorldScene {
  final int beatIndex;
  final StoryEnvironment environment;

  /// True when this beat stays in the same environment as the one before
  /// (the layout and the character are carried over untouched).
  final bool continuesPreviousScene;
  final WorldLook look;
  final List<WorldLayerSpec> layers;

  const WorldScene({
    required this.beatIndex,
    required this.environment,
    required this.continuesPreviousScene,
    required this.look,
    required this.layers,
  });
}

class WorldPlan {
  final WorldCharacter character;
  final WorldPalette palette;
  final List<WorldScene> scenes;

  const WorldPlan({
    required this.character,
    required this.palette,
    required this.scenes,
  });
}

class CinematicWorld {
  CinematicWorld._();

  // The speaker's face lives in this box (normalised): nothing of the world
  // is ever placed over it.
  static const double faceLeft = 0.3;
  static const double faceRight = 0.7;
  static const double faceTop = 0.14;
  static const double faceBottom = 0.5;

  /// The fixed layout of every environment. Slots are ordered by importance:
  /// the first prop of a beat takes the first slot.
  static const Map<StoryEnvironment, WorldLayout> layouts =
      <StoryEnvironment, WorldLayout>{
    StoryEnvironment.office: WorldLayout(
      environment: StoryEnvironment.office,
      backdropKey: 'bg:office',
      backdropColor: '#1E2230',
      setPieces: <String>['desk', 'window', 'wall_clock'],
      slots: <WorldSlot>[
        WorldSlot(x: 0.2, y: 0.74, scale: 0.2, depth: 0.38),
        WorldSlot(x: 0.8, y: 0.72, scale: 0.2, depth: 0.38),
        WorldSlot(x: 0.84, y: 0.9, scale: 0.22, depth: 0.85),
      ],
    ),
    StoryEnvironment.room: WorldLayout(
      environment: StoryEnvironment.room,
      backdropKey: 'bg:room',
      backdropColor: '#2A2024',
      setPieces: <String>['wall_shelf', 'rug', 'lamp_floor'],
      slots: <WorldSlot>[
        WorldSlot(x: 0.18, y: 0.7, scale: 0.2, depth: 0.36),
        WorldSlot(x: 0.82, y: 0.7, scale: 0.2, depth: 0.36),
        WorldSlot(x: 0.16, y: 0.9, scale: 0.22, depth: 0.85),
      ],
    ),
    StoryEnvironment.library: WorldLayout(
      environment: StoryEnvironment.library,
      backdropKey: 'bg:library',
      backdropColor: '#241B16',
      setPieces: <String>['bookshelf_left', 'bookshelf_right', 'ladder'],
      slots: <WorldSlot>[
        WorldSlot(x: 0.22, y: 0.76, scale: 0.2, depth: 0.4),
        WorldSlot(x: 0.78, y: 0.76, scale: 0.2, depth: 0.4),
        WorldSlot(x: 0.8, y: 0.9, scale: 0.22, depth: 0.85),
      ],
    ),
    StoryEnvironment.street: WorldLayout(
      environment: StoryEnvironment.street,
      backdropKey: 'bg:street',
      backdropColor: '#1B2A34',
      setPieces: <String>['building_row', 'street_lamp', 'kerb'],
      slots: <WorldSlot>[
        WorldSlot(x: 0.2, y: 0.78, scale: 0.22, depth: 0.34),
        WorldSlot(x: 0.8, y: 0.78, scale: 0.22, depth: 0.34),
        WorldSlot(x: 0.84, y: 0.92, scale: 0.24, depth: 0.85),
      ],
    ),
    StoryEnvironment.studio: WorldLayout(
      environment: StoryEnvironment.studio,
      backdropKey: 'bg:studio',
      backdropColor: '#16212B',
      setPieces: <String>['monitor_wall', 'light_panel', 'cable_tray'],
      slots: <WorldSlot>[
        WorldSlot(x: 0.2, y: 0.72, scale: 0.2, depth: 0.38),
        WorldSlot(x: 0.8, y: 0.72, scale: 0.2, depth: 0.38),
        WorldSlot(x: 0.82, y: 0.9, scale: 0.22, depth: 0.85),
      ],
    ),
    StoryEnvironment.outdoors: WorldLayout(
      environment: StoryEnvironment.outdoors,
      backdropKey: 'bg:outdoors',
      backdropColor: '#1F3340',
      setPieces: <String>['hills', 'sun', 'path'],
      slots: <WorldSlot>[
        WorldSlot(x: 0.2, y: 0.76, scale: 0.22, depth: 0.34),
        WorldSlot(x: 0.8, y: 0.76, scale: 0.22, depth: 0.34),
        WorldSlot(x: 0.16, y: 0.92, scale: 0.24, depth: 0.85),
      ],
    ),
  };

  static String _particleFor(StoryEnvironment environment) {
    switch (environment) {
      case StoryEnvironment.office:
        return 'dust';
      case StoryEnvironment.room:
        return 'dust';
      case StoryEnvironment.library:
        return 'dust';
      case StoryEnvironment.street:
        return 'sparks';
      case StoryEnvironment.studio:
        return 'sparks';
      case StoryEnvironment.outdoors:
        return 'pollen';
      case StoryEnvironment.bathroom:
        return 'dust';
      case StoryEnvironment.kitchen:
        return 'dust';
      case StoryEnvironment.bedroom:
        return 'dust';
      case StoryEnvironment.livingRoom:
        return 'dust';
      case StoryEnvironment.hallway:
        return 'dust';
    }
  }

  /// The look of a beat. Palette, light direction and shadow are the same
  /// for the whole video; only the intensity follows the mood.
  static WorldLook lookFor(
    StoryEnvironment environment,
    StoryMood mood,
    WorldPalette palette,
  ) {
    String tint;
    double intensity;
    double density;
    switch (mood) {
      case StoryMood.calm:
        tint = palette.amber;
        intensity = 0.7;
        density = 0.25;
        break;
      case StoryMood.energetic:
        tint = palette.red;
        intensity = 0.95;
        density = 0.5;
        break;
      case StoryMood.tense:
        tint = palette.teal;
        intensity = 0.6;
        density = 0.35;
        break;
    }
    return WorldLook(
      tint: tint,
      keyAngleDegrees: 35.0,
      intensity: intensity,
      shadowOpacity: 0.32,
      vignette: 0.35,
      particleKind: _particleFor(environment),
      particleDensity: density,
    );
  }

  /// True when the box of a slot touches the speaker's face area.
  static bool coversFace(WorldSlot slot) {
    final half = slot.scale / 2;
    final left = slot.x - half;
    final right = slot.x + half;
    final top = slot.y - half;
    final bottom = slot.y + half;
    return right > faceLeft &&
        left < faceRight &&
        bottom > faceTop &&
        top < faceBottom;
  }

  /// Plans the world of [story]. The character and the palette are the same
  /// in every scene.
  static WorldPlan plan(
    StoryPlan story, {
    WorldCharacter character = const WorldCharacter(),
    WorldPalette palette = const WorldPalette(),
  }) {
    final scenes = <WorldScene>[];
    StoryEnvironment? previous;

    for (final beat in story.beats) {
      final layout = layouts[beat.environment]!;
      final layers = <WorldLayerSpec>[];

      layers.add(
        WorldLayerSpec(
          id: 'w${beat.index}_backdrop',
          assetKey: layout.backdropKey,
          x: 0.5,
          y: 0.5,
          scale: 1.0,
          depth: 0.0,
          zIndex: 0,
        ),
      );

      // The set pieces keep the same keys and places in every scene of the
      // same environment: that is what makes the place feel continuous.
      for (var i = 0; i < layout.setPieces.length; i++) {
        layers.add(
          WorldLayerSpec(
            id: 'w${beat.index}_set$i',
            assetKey: 'decor:${layout.setPieces[i]}',
            x: 0.5,
            y: 0.5,
            scale: 1.0,
            depth: 0.12 + 0.06 * i,
            zIndex: 1 + i,
          ),
        );
      }

      layers.add(
        WorldLayerSpec(
          id: 'w${beat.index}_hero',
          assetKey: character.assetKey,
          x: character.x,
          y: character.y,
          scale: character.scale,
          depth: WorldCharacter.depth,
          zIndex: 20,
        ),
      );

      final slots = layout.slots;
      for (var i = 0; i < beat.props.length && i < slots.length; i++) {
        final slot = slots[i];
        layers.add(
          WorldLayerSpec(
            id: 'w${beat.index}_prop$i',
            assetKey: 'decor:${beat.props[i]}',
            x: slot.x,
            y: slot.y,
            scale: slot.scale,
            depth: slot.depth,
            // Behind the speaker below 20, in front of the speaker above.
            zIndex: slot.depth > WorldCharacter.depth ? 30 + i : 10 + i,
          ),
        );
      }

      scenes.add(
        WorldScene(
          beatIndex: beat.index,
          environment: beat.environment,
          continuesPreviousScene: previous == beat.environment,
          look: lookFor(beat.environment, beat.mood, palette),
          layers: layers,
        ),
      );
      previous = beat.environment;
    }

    return WorldPlan(character: character, palette: palette, scenes: scenes);
  }
}
