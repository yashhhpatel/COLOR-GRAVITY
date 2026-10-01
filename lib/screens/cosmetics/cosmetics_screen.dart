import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/game_color.dart';
import '../../core/theme/app_theme.dart';
import '../../game/render/shapes.dart';
import '../../progression/cosmetics.dart';
import '../../services/app_services.dart';
import '../../services/audio/audio_service.dart';
import '../../widgets/common/ui.dart';

/// Skins, trails, gravity and merge effects. Purely visual — never gameplay.
class CosmeticsScreen extends StatefulWidget {
  const CosmeticsScreen({super.key});
  @override
  State<CosmeticsScreen> createState() => _CosmeticsScreenState();
}

class _CosmeticsScreenState extends State<CosmeticsScreen> {
  CosmeticCategory _cat = CosmeticCategory.skin;

  void _tap(Cosmetic c) {
    final s = AppScope.of(context);
    final p = s.progress;
    if (p.owns(c)) {
      p.equip(c);
      return;
    }
    if (p.coins < c.price) {
      showToast(context, 'Need ${c.price - p.coins} more coins', icon: Icons.savings_rounded);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Unlock ${c.name}?', style: AppText.title.copyWith(fontSize: 20)),
        content: Row(children: [
          const CoinIcon(),
          const SizedBox(width: 8),
          Text('${c.price}', style: AppText.number),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: AppText.body.copyWith(color: AppColors.textDim))),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (p.buy(c)) {
                s.audio.play(Sfx.reward);
                showToast(context, '${c.name} unlocked & equipped', icon: Icons.check_circle_rounded);
              }
            },
            child: Text('Unlock', style: AppText.body.copyWith(color: AppColors.brand2, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: MenuBackdrop(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: s.progress,
            builder: (context, _) {
              final p = s.progress;
              final items = Cosmetics.of(_cat);
              return Column(children: [
                ScreenHeader(title: 'Skins & Effects', trailing: CoinPill(coins: p.coins, compact: true)),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final c in CosmeticCategory.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Pressable(
                            onTap: () => setState(() => _cat = c),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _cat == c ? Colors.white : AppColors.surface,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(color: AppColors.stroke),
                              ),
                              child: Text(c.title,
                                  style: AppText.body
                                      .copyWith(color: _cat == c ? AppColors.bg : AppColors.text, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final c = items[i];
                      final owned = p.owns(c);
                      final equipped = p.isEquipped(c);
                      return FadeSlideIn(
                        key: ValueKey('${_cat.name}-$i'),
                        delay: FadeSlideIn.stagger(i, stepMs: 50),
                        child: Pressable(
                          onTap: () => _tap(c),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: equipped ? Colors.white : AppColors.stroke, width: equipped ? 2 : 1),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Column(children: [
                              Expanded(child: _Preview(cosmetic: c)),
                              const SizedBox(height: 8),
                              Text(c.name, style: AppText.heading.copyWith(fontSize: 16)),
                              const SizedBox(height: 6),
                              if (equipped)
                                Text('EQUIPPED', style: AppText.label.copyWith(color: AppColors.success))
                              else if (owned)
                                const Text('TAP TO EQUIP', style: AppText.label)
                              else
                                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  const CoinIcon(size: 15),
                                  const SizedBox(width: 5),
                                  Text('${c.price}',
                                      style: AppText.number.copyWith(
                                          fontSize: 14, color: p.coins >= c.price ? AppColors.coin : AppColors.textMute)),
                                ]),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

/// Live animated preview of a cosmetic.
class _Preview extends StatefulWidget {
  const _Preview({required this.cosmetic});
  final Cosmetic cosmetic;
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(painter: _PreviewPainter(widget.cosmetic, _c.value), size: Size.infinite),
      );
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.c, this.t);
  final Cosmetic c;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = math.min(size.width, size.height) * 0.2;
    final p = Paint();
    final s = Paint()..style = PaintingStyle.stroke;
    const col = GameColor.blue;
    switch (c.category) {
      case CosmeticCategory.skin:
        p.color = col.color.withOpacity(0.2);
        canvas.drawCircle(center, r * 1.8, p);
        _skin(canvas, center, r, p, s);
      case CosmeticCategory.trail:
        final pts = [
          for (var i = 0; i < 14; i++) center + Offset(math.sin(t * math.pi * 2 - i * 0.25) * r * 1.6, i * r * 0.18 - r)
        ];
        for (var i = 1; i < pts.length; i++) {
          final k = 1 - i / pts.length;
          switch (c.id) {
            case 'trail_spark':
              p.color = const Color(0xFFFFE08A).withOpacity(k);
              canvas.drawCircle(pts[i] + Offset(math.sin(i * 2.3) * 4, 0), 2.5 * k + 0.5, p);
            case 'trail_pulse':
              if (i % 3 == 0) {
                s
                  ..strokeWidth = 1.5
                  ..color = col.color.withOpacity(0.6 * k);
                canvas.drawCircle(pts[i], r * 0.6 * k + 2, s);
              }
            case 'trail_rainbow':
              s
                ..strokeWidth = r * 0.9 * k
                ..strokeCap = StrokeCap.round
                ..color = GameColor.base[i % 5].color.withOpacity(0.7 * k);
              canvas.drawLine(pts[i - 1], pts[i], s);
            default:
              s
                ..strokeWidth = r * 1.0 * k
                ..strokeCap = StrokeCap.round
                ..color = col.color.withOpacity(0.4 * k);
              canvas.drawLine(pts[i - 1], pts[i], s);
          }
        }
        p.color = col.color;
        canvas.drawCircle(pts.first, r * 0.6, p);
      case CosmeticCategory.gravityFx:
      case CosmeticCategory.mergeFx:
        final k = (t * 1.5) % 1.0;
        final fx = c.preview;
        if (c.id.contains('lightning')) {
          s
            ..strokeWidth = 2
            ..color = fx.withOpacity(1 - k);
          for (var i = 0; i < 6; i++) {
            final a = i * math.pi / 3;
            final path = Path()..moveTo(center.dx, center.dy);
            for (var j = 1; j <= 4; j++) {
              final d = r * 0.5 * j * (0.4 + k);
              path.lineTo(
                  center.dx + math.cos(a + (j.isEven ? 0.2 : -0.2)) * d, center.dy + math.sin(a + (j.isEven ? 0.2 : -0.2)) * d);
            }
            canvas.drawPath(path, s);
          }
        } else if (c.id.contains('ring') || c.id.contains('energy')) {
          s
            ..strokeWidth = 3 * (1 - k) + 0.5
            ..color = fx.withOpacity(1 - k);
          canvas.drawCircle(center, r * (0.5 + 1.6 * k), s);
          canvas.drawCircle(center, r * (0.2 + 1.1 * k), s..color = Colors.white.withOpacity(0.6 * (1 - k)));
        } else if (c.id.contains('spiral')) {
          for (var i = 0; i < 12; i++) {
            final a = i * 0.6 + k * 6;
            final d = r * (0.2 + i * 0.12) * (0.5 + k);
            p.color = fx.withOpacity(1 - k);
            canvas.drawCircle(center + Offset(math.cos(a), math.sin(a)) * d, 2.4, p);
          }
        } else if (c.id.contains('crystal')) {
          for (var i = 0; i < 8; i++) {
            final a = i * math.pi / 4;
            p.color = fx.withOpacity(1 - k);
            Shapes.draw(canvas, ColorShape.diamond, center + Offset(math.cos(a), math.sin(a)) * r * 1.6 * k, 5, p,
                rotation: a + k * 3);
          }
        } else {
          for (var i = 0; i < 12; i++) {
            final a = i * math.pi / 6;
            p.color = fx.withOpacity(1 - k);
            canvas.drawCircle(center + Offset(math.cos(a), math.sin(a)) * r * 1.8 * k, 3 * (1 - k) + 1, p);
          }
        }
        p.color = col.color;
        canvas.drawCircle(center, r * 0.55, p);
    }
  }

  void _skin(Canvas canvas, Offset c, double r, Paint p, Paint s) {
    const col = GameColor.blue;
    switch (this.c.id) {
      case 'skin_crystal':
        p.color = col.color.withOpacity(0.85);
        Shapes.draw(canvas, ColorShape.hexagon, c, r, p, rotation: t * 2);
        s
          ..strokeWidth = 1.5
          ..color = Colors.white70;
        Shapes.draw(canvas, ColorShape.hexagon, c, r, s, rotation: t * 2);
      case 'skin_neon':
        s
          ..strokeWidth = r * 0.28
          ..color = col.color;
        canvas.drawCircle(c, r * 0.85, s);
        s
          ..strokeWidth = 1.5
          ..color = Colors.white;
        canvas.drawCircle(c, r * 0.85, s);
      case 'skin_shadow':
        p.color = const Color(0xFF12152A);
        canvas.drawCircle(c, r, p);
        s
          ..strokeWidth = r * 0.2
          ..color = col.color;
        canvas.drawCircle(c, r * 0.9, s);
      case 'skin_gold':
        p.color = col.color;
        canvas.drawCircle(c, r, p);
        s
          ..strokeWidth = r * 0.25
          ..color = const Color(0xFFFFD45C);
        canvas.drawCircle(c, r * 0.88, s);
      case 'skin_galaxy':
        p.color = const Color(0xFF1B1440);
        canvas.drawCircle(c, r, p);
        p.color = Colors.white;
        for (var i = 0; i < 7; i++) {
          final a = i * 1.7 + t * 4;
          canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r * (0.2 + (i % 3) * 0.22), 1.2, p);
        }
        s
          ..strokeWidth = r * 0.16
          ..color = col.color;
        canvas.drawCircle(c, r * 0.92, s);
      case 'skin_cyber':
        p.color = col.color;
        canvas.drawCircle(c, r, p);
        s
          ..strokeWidth = 1
          ..color = Colors.black45;
        for (var k = -1; k <= 1; k++) {
          canvas.drawLine(c + Offset(k * r * 0.45, -r * 0.85), c + Offset(k * r * 0.45, r * 0.85), s);
          canvas.drawLine(c + Offset(-r * 0.85, k * r * 0.45), c + Offset(r * 0.85, k * r * 0.45), s);
        }
        s
          ..strokeWidth = 2
          ..color = const Color(0xFF4DFFB8);
        canvas.drawCircle(c, r * 0.95, s);
      default:
        p.color = col.color;
        canvas.drawCircle(c, r, p);
        s
          ..strokeWidth = r * 0.16
          ..color = Colors.white;
        canvas.drawCircle(c, r * 0.9, s);
    }
    p.color = Colors.white;
    Shapes.drawColor(canvas, col, c, r * 0.4, p);
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter old) => old.t != t || old.c != c;
}
