import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/game_color.dart';
import '../../core/models/gravity_dir.dart';
import '../../core/theme/app_theme.dart';
import '../../game/engine/game_engine.dart';
import '../../game/entities/entity.dart';
import '../../game/render/game_painter.dart';
import '../../levels/segments/segment_builder.dart';
import '../../widgets/common/ui.dart';

/// Minimal gameplay HUD. Each piece listens to its own notifier.
class GameHud extends StatelessWidget {
  const GameHud({
    super.key,
    required this.engine,
    required this.title,
    required this.onPause,
    this.coinKey,
    this.coinBump,
  });
  final GameEngine engine;
  final String title;
  final VoidCallback onPause;

  /// Target of coins flying into the HUD, and a counter that pops on arrival.
  final GlobalKey? coinKey;
  final ValueNotifier<int>? coinBump;

  @override
  Widget build(BuildContext context) {
    final hud = engine.hud;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              IconCircleButton(icon: Icons.pause_rounded, size: 42, tooltip: 'Pause', onTap: onPause),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: AppText.label.copyWith(color: AppColors.text, fontSize: 12)),
                  const SizedBox(height: 6),
                  if (!engine.isEndless)
                    ValueListenableBuilder<double>(
                      valueListenable: hud.progress,
                      builder: (_, v, __) => ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: v,
                          minHeight: 5,
                          backgroundColor: Colors.white.withOpacity(0.10),
                          valueColor: const AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                    )
                  else
                    AnimatedBuilder(
                      animation: engine,
                      builder: (_, __) =>
                          Text('${engine.traveled.round()} m', style: AppText.label.copyWith(color: AppColors.textDim)),
                    ),
                ]),
              ),
              const SizedBox(width: 14),
              ValueListenableBuilder<int>(
                valueListenable: hud.score,
                builder: (_, v, __) => Text('$v', style: AppText.number.copyWith(fontSize: 26)),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _Hearts(engine: engine),
              const SizedBox(width: 10),
              ValueListenableBuilder<int>(
                valueListenable: hud.coins,
                builder: (_, v, __) => ValueListenableBuilder<int>(
                  valueListenable: coinBump ?? ValueNotifier(0),
                  builder: (_, bump, __) => TweenAnimationBuilder<double>(
                    key: ValueKey(bump),
                    tween: Tween(begin: bump == 0 ? 1 : 1.35, end: 1),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutBack,
                    builder: (_, s, child) => Transform.scale(scale: s, child: child),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      CoinIcon(key: coinKey, size: 15),
                      const SizedBox(width: 4),
                      Text('$v', style: AppText.number.copyWith(fontSize: 14)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ValueListenableBuilder<int>(
                valueListenable: hud.combo,
                builder: (_, c, __) => AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
                  child: c >= 2
                      ? Container(
                          key: ValueKey(c),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration:
                              BoxDecoration(color: AppColors.star.withOpacity(0.18), borderRadius: BorderRadius.circular(10)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            // Remaining combo window: keep chaining before it empties.
                            ValueListenableBuilder<double>(
                              valueListenable: hud.comboTime,
                              builder: (_, f, __) => SizedBox(
                                width: 12,
                                height: 12,
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(end: f),
                                  duration: const Duration(milliseconds: 160),
                                  builder: (_, v, __) => CircularProgressIndicator(
                                    value: v,
                                    strokeWidth: 2.2,
                                    color: AppColors.star,
                                    backgroundColor: AppColors.star.withOpacity(0.2),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text('x$c', style: AppText.number.copyWith(fontSize: 13, color: AppColors.star)),
                          ]),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              const Spacer(),
              _ColorIndicator(hud: hud),
              const SizedBox(width: 8),
              _GravityIndicator(hud: hud),
            ]),
            _PowerUpRow(hud: hud),
            ValueListenableBuilder<String?>(
              valueListenable: hud.mission,
              builder: (_, m, __) => m == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(m, style: AppText.label.copyWith(color: AppColors.textDim, letterSpacing: 0.4)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hearts extends StatelessWidget {
  const _Hearts({required this.engine});
  final GameEngine engine;
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([engine.hud.hearts, engine.hud.shield, engine.hud.hitPulse]),
      builder: (_, __) {
        final h = engine.hud.hearts.value;
        final max = engine.config.hearts;
        final pulse = engine.hud.hitPulse.value;
        // Shake the hearts each time one is lost.
        return TweenAnimationBuilder<double>(
          key: ValueKey(pulse),
          tween: Tween(begin: pulse == 0 ? 1 : 0, end: 1),
          duration: const Duration(milliseconds: 480),
          builder: (_, t, child) => Transform.translate(offset: Offset(math.sin(t * math.pi * 6) * (1 - t) * 7, 0), child: child),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < max; i++)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: AnimatedScale(
                  scale: i < h ? 1 : 0.8,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.favorite_rounded, size: 17, color: i < h ? AppColors.danger : AppColors.locked),
                ),
              ),
            if (engine.hud.shield.value) const Icon(Icons.shield_rounded, size: 17, color: Color(0xFF9FD8FF)),
          ]),
        );
      },
    );
  }
}

class _GravityIndicator extends StatelessWidget {
  const _GravityIndicator({required this.hud});
  final HudState hud;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([hud.gravity, hud.warning, hud.locked]),
      builder: (_, __) {
        final d = hud.gravity.value;
        final w = hud.warning.value;
        return Semantics(
          label: 'Gravity ${d.label}',
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.surface.withOpacity(0.9),
              shape: BoxShape.circle,
              border: Border.all(color: w != null ? Colors.white : AppColors.strokeStrong, width: w != null ? 2 : 1),
            ),
            child: Stack(alignment: Alignment.center, children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: d.angle),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                builder: (_, a, __) => Transform.rotate(
                  angle: a,
                  child: const GravityArrowIcon(dir: GravityDir.down, size: 24),
                ),
              ),
              if (w != null)
                Positioned(
                  right: 2,
                  top: 2,
                  child: _Blink(child: GravityArrowIcon(dir: w, size: 13, color: AppColors.star)),
                ),
              if (hud.locked.value)
                const Positioned(right: 0, bottom: 0, child: Icon(Icons.lock_rounded, size: 14, color: AppColors.textDim)),
            ]),
          ),
        );
      },
    );
  }
}

class _Blink extends StatefulWidget {
  const _Blink({required this.child});
  final Widget child;
  @override
  State<_Blink> createState() => _BlinkState();
}

class _BlinkState extends State<_Blink> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))
    ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _c, child: widget.child);
}

class _ColorIndicator extends StatelessWidget {
  const _ColorIndicator({required this.hud});
  final HudState hud;
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GameColor>(
      valueListenable: hud.color,
      builder: (_, c, __) => Semantics(
        label: 'Your color ${c.label}',
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: c.color.withOpacity(0.18),
            shape: BoxShape.circle,
            border: Border.all(color: c.color, width: 2),
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
              child: ColorGlyph(key: ValueKey(c), color: c, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

class _PowerUpRow extends StatelessWidget {
  const _PowerUpRow({required this.hud});
  final HudState hud;
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<(PowerUpType, double)>>(
      valueListenable: hud.powerUps,
      builder: (_, list, __) => list.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 6, children: [
                for (final (t, f) in list)
                  Container(
                    padding: const EdgeInsets.fromLTRB(4, 3, 9, 3),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.stroke),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: Stack(alignment: Alignment.center, children: [
                          CircularProgressIndicator(
                              value: f, strokeWidth: 2, color: const Color(0xFF9FD8FF), backgroundColor: Colors.white12),
                          Icon(GamePainter.powerIcons[t], size: 12, color: Colors.white),
                        ]),
                      ),
                      const SizedBox(width: 5),
                      Text(t.title, style: AppText.label.copyWith(color: AppColors.text, fontSize: 10, letterSpacing: 0.3)),
                    ]),
                  ),
              ]),
            ),
    );
  }
}

/// Center-screen banner for mechanic intros.
class HintBanner extends StatelessWidget {
  const HintBanner({super.key, required this.hud});
  final HudState hud;
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: hud.banner,
      builder: (_, text, __) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (w, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: const Offset(0, -0.3), end: Offset.zero).animate(a), child: w),
        ),
        child: text == null
            ? const SizedBox.shrink()
            : Container(
                key: ValueKey(text),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bgDeep.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.strokeStrong),
                ),
                child: Text(text, textAlign: TextAlign.center, style: AppText.body.copyWith(fontWeight: FontWeight.w600)),
              ),
      ),
    );
  }
}

/// Interactive tutorial coach mark with an animated gesture hint.
class TutorialPromptView extends StatefulWidget {
  const TutorialPromptView({super.key, required this.hud});
  final HudState hud;
  @override
  State<TutorialPromptView> createState() => _TutorialPromptViewState();
}

class _TutorialPromptViewState extends State<TutorialPromptView> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TutorialPrompt?>(
      valueListenable: widget.hud.prompt,
      builder: (_, p, __) {
        if (p == null) return const SizedBox.shrink();
        return IgnorePointer(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.bgDeep.withOpacity(0.88),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.4)),
              ),
              child: Text(p.text, textAlign: TextAlign.center, style: AppText.heading.copyWith(fontSize: 20)),
            ),
            const SizedBox(height: 18),
            AnimatedBuilder(
              animation: _c,
              builder: (_, __) {
                final t = Curves.easeInOut.transform(_c.value);
                Offset off;
                if (p.action == HintAction.drag) {
                  off = Offset(math.sin(_c.value * math.pi * 2) * 60, 0);
                } else {
                  final d = p.dir ?? GravityDir.down;
                  off = Offset(d.dx * (t * 90 - 45), d.dy * (t * 90 - 45));
                }
                return Transform.translate(
                  offset: off,
                  child: Opacity(
                    opacity: p.action == HintAction.swipe ? (1 - (t - 0.5).abs() * 1.6).clamp(0.0, 1.0) : 1,
                    child: const Icon(Icons.touch_app_rounded, size: 54, color: Colors.white),
                  ),
                );
              },
            ),
          ]),
        );
      },
    );
  }
}

/// Optional on-screen gravity buttons (Settings → Gravity Buttons).
class GravityPad extends StatelessWidget {
  const GravityPad({super.key, required this.onDir});
  final void Function(GravityDir) onDir;

  Widget _btn(GravityDir d) => Pressable(
        silent: true,
        onTap: () => onDir(d),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: AppColors.surface.withOpacity(0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.strokeStrong),
          ),
          child: Center(child: GravityArrowIcon(dir: d, size: 22)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      height: 156,
      child: Stack(children: [
        Positioned(top: 0, left: 53, child: _btn(GravityDir.up)),
        Positioned(bottom: 0, left: 53, child: _btn(GravityDir.down)),
        Positioned(left: 0, top: 53, child: _btn(GravityDir.left)),
        Positioned(right: 0, top: 53, child: _btn(GravityDir.right)),
      ]),
    );
  }
}

/// Brief red edge flash whenever a heart is lost.
class HitVignette extends StatefulWidget {
  const HitVignette({super.key, required this.hud});
  final HudState hud;
  @override
  State<HitVignette> createState() => _HitVignetteState();
}

class _HitVignetteState extends State<HitVignette> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520), value: 1);
    widget.hud.hitPulse.addListener(_flash);
  }

  void _flash() => _c.forward(from: 0);

  @override
  void dispose() {
    widget.hud.hitPulse.removeListener(_flash);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final a = (1 - _c.value) * 0.55;
          if (a <= 0.01) return const SizedBox.shrink();
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 0.95,
                colors: [Colors.transparent, AppColors.danger.withOpacity(a)],
                stops: const [0.6, 1],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A collected coin arcing from the track into the HUD counter.
class FlyingCoin extends StatefulWidget {
  const FlyingCoin({super.key, required this.from, required this.to, required this.onDone});
  final Offset from;
  final Offset to;
  final VoidCallback onDone;
  @override
  State<FlyingCoin> createState() => _FlyingCoinState();
}

class _FlyingCoinState extends State<FlyingCoin> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 560))
      ..forward().whenComplete(() {
        if (mounted) widget.onDone();
      });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeInCubic.transform(_c.value);
        final a = widget.from, b = widget.to;
        // Quadratic arc: swing out sideways, then into the counter.
        final ctrl = Offset(a.dx + (a.dx < b.dx ? -60 : 60), (a.dy + b.dy) / 2);
        final p = a * ((1 - t) * (1 - t)) + ctrl * (2 * (1 - t) * t) + b * (t * t);
        final size = 20 - 6 * t;
        return Positioned(
          left: p.dx - size / 2,
          top: p.dy - size / 2,
          child: IgnorePointer(child: CoinIcon(size: size)),
        );
      },
    );
  }
}
