import 'dart:math' as math;
import 'dart:ui';

/// The four gravity directions. Screen space: +y is down.
enum GravityDir {
  down(0, 1, '↓'),
  up(0, -1, '↑'),
  left(-1, 0, '←'),
  right(1, 0, '→');

  const GravityDir(this.dx, this.dy, this.arrow);

  final int dx;
  final int dy;
  final String arrow;

  Offset get vector => Offset(dx.toDouble(), dy.toDouble());

  bool get isVertical => dx == 0;
  bool get isHorizontal => dy == 0;

  GravityDir get opposite => switch (this) {
        GravityDir.down => GravityDir.up,
        GravityDir.up => GravityDir.down,
        GravityDir.left => GravityDir.right,
        GravityDir.right => GravityDir.left,
      };

  /// Next direction clockwise (down → left → up → right → down).
  GravityDir get clockwise => switch (this) {
        GravityDir.down => GravityDir.left,
        GravityDir.left => GravityDir.up,
        GravityDir.up => GravityDir.right,
        GravityDir.right => GravityDir.down,
      };

  /// Rotation angle (radians) of an arrow that points "down" at 0.
  double get angle => switch (this) {
        GravityDir.down => 0,
        GravityDir.left => math.pi / 2,
        GravityDir.up => math.pi,
        GravityDir.right => -math.pi / 2,
      };

  String get label => name.toUpperCase();

  static GravityDir fromName(String? n, [GravityDir fallback = GravityDir.down]) {
    for (final d in GravityDir.values) {
      if (d.name == n) return d;
    }
    return fallback;
  }

  /// Dominant direction of a swipe vector.
  static GravityDir fromVector(Offset v) {
    if (v.dx.abs() > v.dy.abs()) {
      return v.dx > 0 ? GravityDir.right : GravityDir.left;
    }
    return v.dy > 0 ? GravityDir.down : GravityDir.up;
  }
}
