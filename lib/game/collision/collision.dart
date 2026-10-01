import 'dart:math' as math;
import 'dart:ui';

import '../../core/constants/game_constants.dart';
import '../../core/models/gravity_dir.dart';
import '../entities/entity.dart';

/// Lightweight geometric tests (circles vs rects / segments / circles).
class Collision {
  static bool circleCircle(double ax, double ay, double ar, double bx, double by, double br) {
    final dx = ax - bx, dy = ay - by, r = ar + br;
    return dx * dx + dy * dy < r * r;
  }

  static double rectDistance(double px, double py, Rect r) {
    final dx = math.max(math.max(r.left - px, 0.0), px - r.right);
    final dy = math.max(math.max(r.top - py, 0.0), py - r.bottom);
    return math.sqrt(dx * dx + dy * dy);
  }

  static bool circleRect(double cx, double cy, double cr, Rect r) => rectDistance(cx, cy, r) < cr;

  static double segmentDistance(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  /// Gravity laser beam: from the emitter to the arena edge along gravity.
  static (Offset, Offset) gravityBeam(Entity e, GravityDir g) {
    final start = Offset(e.x, e.y);
    final end = switch (g) {
      GravityDir.down => Offset(e.x, Arena.height + 20),
      GravityDir.up => Offset(e.x, -20),
      GravityDir.left => Offset(Arena.wallLeft, e.y),
      GravityDir.right => Offset(Arena.wallRight, e.y),
    };
    return (start, end);
  }

  /// Distance from a point to a hazard's lethal geometry (negative = inside).
  static double hazardDistance(Entity e, double px, double py, GravityDir g) {
    switch (e.kind) {
      case EntityKind.rotor:
        final (a, b) = e.rotorEnds;
        return segmentDistance(Offset(px, py), a, b) - e.h / 2;
      case EntityKind.laser:
        if (e.followsGravity) {
          final (a, b) = gravityBeam(e, g);
          return math.min(segmentDistance(Offset(px, py), a, b) - 4, rectDistance(px, py, e.rect));
        }
        return e.laserOn ? rectDistance(px, py, e.rect.inflate(-1)) : 999;
      case EntityKind.meteor:
        return math.sqrt((px - e.x) * (px - e.x) + (py - e.y) * (py - e.y)) - e.r;
      case EntityKind.spikes:
        return rectDistance(px, py, e.rect.deflate(2));
      default:
        return rectDistance(px, py, e.rect);
    }
  }
}
