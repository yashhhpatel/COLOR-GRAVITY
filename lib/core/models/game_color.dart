import 'package:flutter/material.dart';

/// Shapes paired with each gameplay color so color is never the only cue.
enum ColorShape { circle, diamond, triangle, square, hexagon, star }

/// Gameplay colors. Every color carries a distinct shape + glyph for
/// accessibility (color-vision deficiency, glare, small screens).
enum GameColor {
  red(Color(0xFFFF4D5E), Color(0xFFB31B2E), ColorShape.circle, 'Red'),
  blue(Color(0xFF3D8BFF), Color(0xFF1749A8), ColorShape.diamond, 'Blue'),
  green(Color(0xFF2EDB8A), Color(0xFF0E8A50), ColorShape.triangle, 'Green'),
  yellow(Color(0xFFFFC93D), Color(0xFFB0820A), ColorShape.square, 'Yellow'),
  purple(Color(0xFFB45CFF), Color(0xFF6C24B0), ColorShape.hexagon, 'Purple'),
  cyan(Color(0xFF2EE6F0), Color(0xFF0B8C96), ColorShape.star, 'Cyan');

  const GameColor(this.color, this.deep, this.shape, this.label);

  final Color color;
  final Color deep;
  final ColorShape shape;
  final String label;

  int get colorId => index;

  /// The five base colors; cyan is introduced in advanced worlds.
  static const List<GameColor> base = [
    GameColor.red,
    GameColor.blue,
    GameColor.green,
    GameColor.yellow,
    GameColor.purple,
  ];

  /// Optional "opposite" pairs used by special levels.
  GameColor get opposite => switch (this) {
        GameColor.red => GameColor.blue,
        GameColor.blue => GameColor.red,
        GameColor.green => GameColor.purple,
        GameColor.purple => GameColor.green,
        GameColor.yellow => GameColor.cyan,
        GameColor.cyan => GameColor.yellow,
      };

  static GameColor fromId(int? id, [GameColor fallback = GameColor.red]) {
    if (id == null || id < 0 || id >= GameColor.values.length) return fallback;
    return GameColor.values[id];
  }
}
