import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/models/game_color.dart';
import '../../core/models/gravity_dir.dart';
import '../../core/theme/world_themes.dart';
import '../../game/render/shapes.dart';
import '../../game/render/world_background.dart';

/// Ambient menu background: color shapes tumbling under slowly rotating
/// gravity. Shows the game's identity before the player even taps Play.
class GravityBackground extends StatefulWidget {
  const GravityBackground({super.key, this.world = 0, this.count = 16, this.dim = 0.55});
  final int world;
  final int count;
  final double dim;

  @override
  State<GravityBackground> createState() => _GravityBackgroundState();
}

class _Piece {
  _Piece(this.x, this.y, this.color, this.r);
  double x, y, vx = 0, vy = 0, rot = 0, spin = 0;
  final GameColor color;
  final double r;
}

class _GravityBackgroundState extends State<GravityBackground> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _repaint = ValueNotifier<int>(0);
  final _rng = math.Random(3);
  final List<_Piece> _pieces = [];
  Duration _last = Duration.zero;
  double _time = 0;
  GravityDir _dir = GravityDir.down;
  Offset _g = const Offset(0, 1);
  double _nextShift = 3.2;
  late WorldBackground _bg;

  @override
  void initState() {
    super.initState();
    _bg = WorldBackground(WorldTheme.byId(widget.world));
    for (var i = 0; i < widget.count; i++) {
      _pieces.add(_Piece(_rng.nextDouble(), _rng.nextDouble(), GameColor.base[i % 5], 7 + _rng.nextDouble() * 9)
        ..spin = (_rng.nextDouble() - 0.5) * 2);
    }
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration now) {
    final dt = math.min(0.05, (now - _last).inMicroseconds / 1e6);
    _last = now;
    _time += dt;
    _nextShift -= dt;
    if (_nextShift <= 0) {
      _dir = _dir.clockwise;
      _nextShift = 3.2;
    }
    _g = Offset.lerp(_g, _dir.vector, math.min(1, dt * 3))!;
    for (final p in _pieces) {
      p.vx += _g.dx * 0.35 * dt;
      p.vy += _g.dy * 0.35 * dt;
      p.vx *= 0.985;
      p.vy *= 0.985;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rot += p.spin * dt;
      if (p.x < 0.03) {
        p.x = 0.03;
        p.vx = p.vx.abs() * 0.4;
      } else if (p.x > 0.97) {
        p.x = 0.97;
        p.vx = -p.vx.abs() * 0.4;
      }
      if (p.y < 0.03) {
        p.y = 0.03;
        p.vy = p.vy.abs() * 0.4;
      } else if (p.y > 0.97) {
        p.y = 0.97;
        p.vy = -p.vy.abs() * 0.4;
      }
    }
    _repaint.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BgPainter(this),
        size: Size.infinite,
      ),
    );
  }
}

class _BgPainter extends CustomPainter {
  _BgPainter(this.s) : super(repaint: s._repaint);
  final _GravityBackgroundState s;
  final Paint _p = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 360;
    s._bg.paint(canvas, size, unit: unit, scroll: s._time * 30, time: s._time, gravity: s._g);
    for (final p in s._pieces) {
      final c = Offset(p.x * size.width, p.y * size.height);
      _p.color = p.color.color.withOpacity(0.10);
      canvas.drawCircle(c, p.r * unit * 2.2, _p);
      _p.color = p.color.color.withOpacity(0.55);
      Shapes.drawColor(canvas, p.color, c, p.r * unit, _p, rotation: p.rot);
    }
    _p.color = Colors.black.withOpacity(s.widget.dim);
    canvas.drawRect(Offset.zero & size, _p);
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) => false;
}
