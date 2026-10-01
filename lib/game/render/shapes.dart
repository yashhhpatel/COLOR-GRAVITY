import 'dart:math' as math;
import 'dart:ui';

import '../../core/models/game_color.dart';
import '../../core/models/gravity_dir.dart';

/// Unit-size (radius 1) paths for the accessibility shapes paired with each
/// color, plus arrows/chevrons. Built once and drawn via canvas transforms.
class Shapes {
  static final Map<ColorShape, Path> _unit = {
    ColorShape.circle: Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 1)),
    ColorShape.diamond: _poly(4, -math.pi / 2, 1.05),
    ColorShape.triangle: _poly(3, -math.pi / 2, 1.12, yShift: 0.18),
    ColorShape.square: Path()
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(-0.82, -0.82, 0.82, 0.82), const Radius.circular(0.18))),
    ColorShape.hexagon: _poly(6, 0, 1.0),
    ColorShape.star: _star(),
  };

  static Path _poly(int n, double start, double r, {double yShift = 0}) {
    final p = Path();
    for (var i = 0; i < n; i++) {
      final a = start + i * math.pi * 2 / n;
      final o = Offset(math.cos(a) * r, math.sin(a) * r + yShift);
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    return p..close();
  }

  static Path _star() {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final a = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? 1.08 : 0.48;
      final o = Offset(math.cos(a) * r, math.sin(a) * r + 0.05);
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    return p..close();
  }

  static final Path arrow = Path()
    ..moveTo(0, 1)
    ..lineTo(-0.8, 0.05)
    ..lineTo(-0.3, 0.05)
    ..lineTo(-0.3, -1)
    ..lineTo(0.3, -1)
    ..lineTo(0.3, 0.05)
    ..lineTo(0.8, 0.05)
    ..close();

  static final Path chevron = Path()
    ..moveTo(-1, -0.4)
    ..lineTo(0, 0.5)
    ..lineTo(1, -0.4)
    ..lineTo(1, -0.05)
    ..lineTo(0, 0.85)
    ..lineTo(-1, -0.05)
    ..close();

  static Path unit(ColorShape s) => _unit[s]!;

  static void draw(Canvas canvas, ColorShape s, Offset c, double r, Paint paint, {double rotation = 0}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    if (rotation != 0) canvas.rotate(rotation);
    canvas.scale(r, r);
    final sw = paint.strokeWidth;
    if (paint.style == PaintingStyle.stroke) paint.strokeWidth = sw / r;
    canvas.drawPath(_unit[s]!, paint);
    paint.strokeWidth = sw;
    canvas.restore();
  }

  static void drawColor(Canvas canvas, GameColor gc, Offset c, double r, Paint paint, {double rotation = 0}) =>
      draw(canvas, gc.shape, c, r, paint, rotation: rotation);

  /// Arrow pointing in gravity direction [d].
  static void drawArrow(Canvas canvas, GravityDir d, Offset c, double r, Paint paint) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(d.angle);
    canvas.scale(r, r);
    canvas.drawPath(arrow, paint);
    canvas.restore();
  }

  static void drawChevron(Canvas canvas, double angle, Offset c, double r, Paint paint) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    canvas.scale(r, r);
    canvas.drawPath(chevron, paint);
    canvas.restore();
  }
}
