import 'package:flutter/material.dart';

import '../../core/models/game_color.dart';
import '../../core/theme/app_theme.dart';
import 'ui.dart';

/// Wordmark: a falling orb mark + "COLOR / GRAVITY" + the five color shapes.
class GameLogo extends StatelessWidget {
  const GameLogo({super.key, this.size = 1, this.animate = true});
  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _OrbMark(size: 64 * size, animate: animate),
      SizedBox(height: 14 * size),
      ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          colors: [Colors.white, Color(0xFFE4E1FF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(r),
        child: Text('COLOR', style: AppText.display.copyWith(fontSize: 48 * size, letterSpacing: 8 * size, height: 1)),
      ),
      SizedBox(height: 2 * size),
      Text('GRAVITY',
          style: AppText.heading
              .copyWith(fontSize: 20 * size, letterSpacing: 13 * size, color: AppColors.textDim, fontWeight: FontWeight.w600)),
      SizedBox(height: 12 * size),
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (final c in GameColor.base)
          Padding(
              padding: EdgeInsets.symmetric(horizontal: 4 * size), child: ColorGlyph(color: c, size: 14 * size, outline: false)),
      ]),
    ]);
  }
}

class _OrbMark extends StatefulWidget {
  const _OrbMark({required this.size, required this.animate});
  final double size;
  final bool animate;
  @override
  State<_OrbMark> createState() => _OrbMarkState();
}

class _OrbMarkState extends State<_OrbMark> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 1.3,
      height: s * 1.3,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          // The orb drops, lands with a squash and floats back.
          final t = _c.value;
          final drop = t < 0.5 ? Curves.easeInQuad.transform(t * 2) : 1 - Curves.easeOutCubic.transform((t - 0.5) * 2);
          final squash = (t > 0.45 && t < 0.6) ? (1 - ((t - 0.525).abs() / 0.075)).clamp(0.0, 1.0) * 0.18 : 0.0;
          return Stack(alignment: Alignment.center, children: [
            Container(
              width: s * 1.25,
              height: s * 1.25,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.12), width: 1.5),
              ),
            ),
            Transform.translate(
              offset: Offset(0, (drop - 0.5) * s * 0.28),
              child: Transform.scale(
                scaleX: 1 + squash,
                scaleY: 1 - squash,
                child: Container(
                  width: s * 0.62,
                  height: s * 0.62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF4D5E), Color(0xFFB45CFF), Color(0xFF3D8BFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: Colors.white, width: s * 0.045),
                    boxShadow: [BoxShadow(color: const Color(0xFF8B6BFF).withOpacity(0.6), blurRadius: s * 0.35)],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: s * 0.04,
              child: Container(
                  width: s * 0.5,
                  height: 3,
                  decoration: BoxDecoration(color: Colors.white54, borderRadius: BorderRadius.circular(2))),
            ),
          ]);
        },
      ),
    );
  }
}
