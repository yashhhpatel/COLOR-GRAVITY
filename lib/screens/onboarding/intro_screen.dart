import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/game_color.dart';
import '../../core/models/gravity_dir.dart';
import '../../core/theme/app_theme.dart';
import '../../game/render/shapes.dart';
import '../../services/app_services.dart';
import '../../widgets/common/ui.dart';
import '../gameplay/gameplay_screen.dart';

/// First launch: three quick visual beats, then straight into tutorial play.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});
  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
  int _beat = 0;
  static const _titles = ['COLOR decides WHAT', 'GRAVITY decides WHERE', 'Master both.'];
  static const _subs = [
    'Collect your color. Gates only open for it.',
    'Swipe to shift gravity in any of 4 directions.',
    'Read the color. Choose the pull. Survive.',
  ];

  @override
  void initState() {
    super.initState();
    _c.addListener(_autoAdvance);
  }

  double _lastV = 0;
  void _autoAdvance() {
    // Advance one beat per animation loop.
    if (_c.value < _lastV && _beat < 2) setState(() => _beat++);
    _lastV = _c.value;
  }

  void _start() {
    final s = AppScope.of(context);
    s.progress.completeOnboarding();
    Navigator.of(context).pushReplacement(fadeRoute(const GameplayScreen(request: RunRequest.level(1))));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: MenuBackdrop(
        child: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _beat < 2 ? setState(() => _beat++) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(children: [
                Align(
                  alignment: Alignment.centerRight,
                  child:
                      TextButton(onPressed: _start, child: Text('Skip', style: AppText.body.copyWith(color: AppColors.textDim))),
                ),
                const Spacer(),
                AspectRatio(
                  aspectRatio: 1,
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (_, __) => CustomPaint(painter: _IntroPainter(_beat, _c.value)),
                  ),
                ),
                const SizedBox(height: 28),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Column(key: ValueKey(_beat), children: [
                    Text(_titles[_beat], textAlign: TextAlign.center, style: AppText.title.copyWith(fontSize: 28)),
                    const SizedBox(height: 10),
                    Text(_subs[_beat], textAlign: TextAlign.center, style: AppText.bodyDim.copyWith(fontSize: 16)),
                  ]),
                ),
                const SizedBox(height: 22),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < 3; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _beat ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _beat ? Colors.white : AppColors.locked,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ]),
                const Spacer(),
                PrimaryButton(
                    label: _beat == 2 ? 'Start Playing' : 'Play Tutorial', icon: Icons.play_arrow_rounded, onTap: _start),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroPainter extends CustomPainter {
  _IntroPainter(this.beat, this.t);
  final int beat;
  final double t;
  final Paint _p = Paint();
  final Paint _s = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 100;
    final box = Rect.fromLTWH(8 * u, 8 * u, 84 * u, 84 * u);
    _s.color = Colors.white.withOpacity(0.15);
    canvas.drawRRect(RRect.fromRectAndRadius(box, Radius.circular(8 * u)), _s);
    switch (beat) {
      case 0:
        _colorBeat(canvas, box, u);
      case 1:
        _gravityBeat(canvas, box, u);
      default:
        _bothBeat(canvas, box, u);
    }
  }

  void _player(Canvas canvas, Offset c, GameColor col, double u) {
    _p.color = col.color.withOpacity(0.2);
    canvas.drawCircle(c, 9 * u, _p);
    _p.color = col.color;
    canvas.drawCircle(c, 6 * u, _p);
    _s
      ..color = Colors.white
      ..strokeWidth = 1.6 * u / 2;
    canvas.drawCircle(c, 5.5 * u, _s);
    _p.color = Colors.white;
    Shapes.drawColor(canvas, col, c, 2.4 * u, _p);
  }

  void _colorBeat(Canvas canvas, Rect box, double u) {
    final pc = Offset(box.center.dx, box.bottom - 12 * u);
    // Red orb falls and is absorbed; blue diamond bounces away.
    final f = (t * 1.6).clamp(0.0, 1.0);
    final red = Offset(box.center.dx, box.top + 8 * u + f * (pc.dy - box.top - 8 * u));
    if (f < 1) {
      _p.color = GameColor.red.color;
      Shapes.drawColor(canvas, GameColor.red, red, 4 * u, _p);
    } else {
      final k = ((t * 1.6) - 1).clamp(0.0, 0.6) / 0.6;
      _s
        ..color = GameColor.red.color.withOpacity(1 - k)
        ..strokeWidth = 1.5 * u;
      canvas.drawCircle(pc, (7 + 10 * k) * u, _s);
    }
    final g = ((t - 0.35) * 1.8).clamp(0.0, 1.0);
    final hitY = pc.dy - 10 * u;
    final blueX = box.center.dx + 2 * u + (g > 0.6 ? (g - 0.6) * 60 * u : 0);
    final blueY = box.top + 8 * u + math.min(g / 0.6, 1) * (hitY - box.top - 8 * u) - (g > 0.6 ? (g - 0.6) * 40 * u : 0);
    if (t > 0.35) {
      _p.color = GameColor.blue.color;
      Shapes.drawColor(canvas, GameColor.blue, Offset(blueX, blueY), 4 * u, _p);
    }
    _player(canvas, pc, GameColor.red, u);
  }

  void _gravityBeat(Canvas canvas, Rect box, double u) {
    const seq = [GravityDir.left, GravityDir.up, GravityDir.right, GravityDir.down];
    final step = (t * 4).floor().clamp(0, 3);
    final local = Curves.easeOutBack.transform(((t * 4) - step).clamp(0.0, 1.0));
    final inner = box.deflate(9 * u);
    Offset corner(GravityDir d, Offset from) => switch (d) {
          GravityDir.left => Offset(inner.left, from.dy),
          GravityDir.right => Offset(inner.right, from.dy),
          GravityDir.up => Offset(from.dx, inner.top),
          GravityDir.down => Offset(from.dx, inner.bottom),
        };
    var pos = Offset(inner.center.dx, inner.bottom);
    for (var i = 0; i < step; i++) {
      pos = corner(seq[i], pos);
    }
    final target = corner(seq[step], pos);
    final now = Offset.lerp(pos, target, local)!;
    _p.color = Colors.white.withOpacity(0.25);
    Shapes.drawArrow(canvas, seq[step], box.center, 12 * u, _p);
    _player(canvas, now, GameColor.blue, u);
  }

  void _bothBeat(Canvas canvas, Rect box, double u) {
    // A red gate scrolls down; the red player passes, gravity pulls it left first.
    final gateY = box.top + 6 * u + t * (box.height - 12 * u);
    final gate = Rect.fromLTWH(box.left + 4 * u, gateY - 2.5 * u, box.width - 8 * u, 5 * u);
    _p.color = GameColor.red.color.withOpacity(0.35);
    canvas.drawRRect(RRect.fromRectAndRadius(gate, Radius.circular(2 * u)), _p);
    _s
      ..color = GameColor.red.color
      ..strokeWidth = 1.2 * u / 2;
    canvas.drawRRect(RRect.fromRectAndRadius(gate, Radius.circular(2 * u)), _s);
    _p.color = Colors.white;
    Shapes.drawColor(canvas, GameColor.red, gate.center, 2.2 * u, _p);
    final px = box.left + 18 * u + (1 - Curves.easeOut.transform((t * 2).clamp(0.0, 1.0))) * 30 * u;
    _player(canvas, Offset(px, box.bottom - 14 * u), GameColor.red, u);
    _p.color = Colors.white.withOpacity(0.25);
    Shapes.drawArrow(canvas, GravityDir.left, Offset(box.right - 16 * u, box.top + 18 * u), 8 * u, _p);
  }

  @override
  bool shouldRepaint(covariant _IntroPainter old) => old.t != t || old.beat != beat;
}
