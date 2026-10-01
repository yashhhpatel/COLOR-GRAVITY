import 'dart:math' as math;
import 'dart:ui';

import '../../core/theme/world_themes.dart';

/// Paints a world's animated background: gradient, parallax motif and
/// gravity streaks drifting in the gravity direction. Low contrast on purpose.
class WorldBackground {
  WorldBackground(this.theme);

  final WorldTheme theme;
  Shader? _shader;
  Size? _shaderSize;
  final Paint _fill = Paint();
  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _dot = Paint();

  static double _hash(int i) {
    final x = math.sin(i * 127.1 + 311.7) * 43758.5453;
    return x - x.floorToDouble();
  }

  /// [unit] = pixels per arena unit. [scroll] = distance traveled.
  void paint(Canvas canvas, Size size,
      {required double unit, required double scroll, required double time, Offset gravity = const Offset(0, 1)}) {
    if (_shader == null || _shaderSize != size) {
      _shader = Gradient.linear(Offset.zero, Offset(0, size.height), [theme.top, theme.bottom]);
      _shaderSize = size;
    }
    _fill.shader = _shader;
    canvas.drawRect(Offset.zero & size, _fill);

    final accent = theme.accent;
    final spacing = 150 * unit;
    final par = scroll * unit * 0.35;
    final first = ((-par) / spacing).floor() - 1;
    final count = (size.height / spacing).ceil() + 3;
    for (var k = 0; k < count; k++) {
      final i = first + k;
      _motif(canvas, size, i.abs(), i * spacing + par, unit, time, accent);
    }

    // Gravity streaks: the environment visibly drifts with gravity.
    _line
      ..strokeWidth = 1.2 * unit
      ..color = accent.withOpacity(0.10);
    for (var i = 0; i < 14; i++) {
      final hx = _hash(i * 7 + 1), hy = _hash(i * 13 + 5);
      final speed = 40 + _hash(i) * 60;
      final travel = (time * speed * unit) % (size.longestSide + 200);
      final base = Offset(hx * size.width, hy * size.height);
      final p = Offset(
        (base.dx + gravity.dx * travel) % (size.width + 100) - 50,
        (base.dy + gravity.dy * travel + scroll * unit * 0.6) % (size.height + 100) - 50,
      );
      final len = (14 + _hash(i + 3) * 24) * unit;
      canvas.drawLine(p, p - gravity * len, _line);
    }
  }

  void _motif(Canvas canvas, Size size, int i, double y, double unit, double time, Color accent) {
    final h = _hash(i);
    final x = (0.1 + 0.8 * _hash(i + 17)) * size.width;
    _line
      ..strokeWidth = 1.4 * unit
      ..color = accent.withOpacity(0.10 + 0.05 * h);
    _dot.color = accent.withOpacity(0.10 + 0.08 * h);
    switch (theme.pattern) {
      case WorldPattern.hills:
        final path = Path()..moveTo(0, y);
        for (var sx = 0.0; sx <= size.width; sx += 12 * unit) {
          path.lineTo(sx, y + math.sin(sx / (40 * unit) + i) * 10 * unit);
        }
        canvas.drawPath(path, _line);
        canvas.drawCircle(Offset(x, y - 30 * unit), 2 * unit, _dot);
      case WorldPattern.gears:
        final r = (16 + 22 * h) * unit;
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(time * (i.isEven ? 0.4 : -0.4));
        canvas.drawCircle(Offset.zero, r, _line);
        for (var t = 0; t < 8; t++) {
          final a = t * math.pi / 4;
          canvas.drawLine(Offset(math.cos(a) * r, math.sin(a) * r),
              Offset(math.cos(a) * (r + 6 * unit), math.sin(a) * (r + 6 * unit)), _line);
        }
        canvas.restore();
      case WorldPattern.orbits:
        final r = (30 + 40 * h) * unit;
        canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: r * 2.4, height: r), _line);
        final a = time * (0.6 + h);
        canvas.drawCircle(Offset(x + math.cos(a) * r * 1.2, y + math.sin(a) * r / 2), 3 * unit, _dot);
      case WorldPattern.crystals:
        final r = (10 + 18 * h) * unit;
        final p = Path()
          ..moveTo(x, y - r * 1.6)
          ..lineTo(x + r, y)
          ..lineTo(x, y + r * 1.2)
          ..lineTo(x - r, y)
          ..close();
        canvas.drawPath(p, _line);
      case WorldPattern.magnets:
        final r = (12 + 12 * h) * unit;
        canvas.drawArc(Rect.fromCircle(center: Offset(x, y), radius: r), 0, math.pi, false, _line);
        canvas.drawLine(Offset(x - r, y), Offset(x - r, y - r), _line);
        canvas.drawLine(Offset(x + r, y), Offset(x + r, y - r), _line);
      case WorldPattern.skyline:
        final w = (18 + 26 * h) * unit, bh = (40 + 70 * _hash(i + 9)) * unit;
        canvas.drawRect(Rect.fromLTWH(x - w / 2, y - bh / 2, w, bh), _line);
        for (var k = 0; k < 3; k++) {
          canvas.drawCircle(Offset(x - w / 4 + k * w / 4, y - bh / 4), 1.5 * unit, _dot);
        }
      case WorldPattern.energy:
        final path = Path()..moveTo(x, y - 60 * unit);
        for (var s = -60.0; s <= 60; s += 6) {
          path.lineTo(x + math.sin(s / 10 + time * 3 + i) * 6 * unit, y + s * unit);
        }
        canvas.drawPath(path, _line);
      case WorldPattern.quantum:
        for (var k = 0; k < 6; k++) {
          final px = (k + 0.5) / 6 * size.width;
          canvas.drawCircle(Offset(px, y + math.sin(time * 2 + k + i) * 8 * unit), (1.5 + h) * unit, _dot);
        }
      case WorldPattern.voidStars:
        for (var k = 0; k < 4; k++) {
          final sx = _hash(i * 5 + k) * size.width;
          final tw = 0.5 + 0.5 * math.sin(time * 2 + k * 1.7 + i);
          _dot.color = accent.withOpacity(0.06 + 0.16 * tw);
          canvas.drawCircle(Offset(sx, y + k * 30 * unit), (1 + h) * unit, _dot);
        }
      case WorldPattern.prism:
        final r = (14 + 20 * h) * unit;
        final p = Path()
          ..moveTo(x, y - r)
          ..lineTo(x + r * 0.9, y + r * 0.6)
          ..lineTo(x - r * 0.9, y + r * 0.6)
          ..close();
        canvas.drawPath(p, _line);
        canvas.drawLine(Offset(x + r * 0.45, y - r * 0.2), Offset(x + r * 2, y - r * 0.6), _line);
    }
  }
}
