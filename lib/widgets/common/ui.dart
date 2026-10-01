import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/game_color.dart';
import '../../core/models/gravity_dir.dart';
import '../../core/theme/app_theme.dart';
import '../../game/render/shapes.dart';
import '../../services/app_services.dart';
import '../../services/audio/audio_service.dart';
import '../../services/haptics/haptics_service.dart';

/// Fade + slight rise transition used across the app.
Route<T> fadeRoute<T>(Widget page, {RouteSettings? settings}) => PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: c,
          child: SlideTransition(position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(c), child: child),
        );
      },
    );

void uiFeedback(BuildContext context) {
  final s = AppScope.of(context);
  s.audio.play(Sfx.button, volume: 0.7);
  s.haptics.fire(Haptic.selection);
}

/// Press-scale wrapper with sound + haptic.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.95, this.silent = false});
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool silent;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTap: enabled
          ? () {
              if (!widget.silent) uiFeedback(context);
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedOpacity(opacity: enabled ? 1 : 0.45, duration: const Duration(milliseconds: 150), child: widget.child),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(
      {super.key, required this.label, this.onTap, this.icon, this.height = 58, this.gradient, this.expand = true});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final double height;
  final Gradient? gradient;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: height,
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          gradient: gradient ?? AppColors.brandGradient,
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: [BoxShadow(color: AppColors.brand.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, color: Colors.white, size: 22), const SizedBox(width: 8)],
            Flexible(child: Text(label, style: AppText.button, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, this.onTap, this.icon, this.height = 54, this.expand = true});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: height,
        width: expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(color: AppColors.strokeStrong),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, color: AppColors.text, size: 20), const SizedBox(width: 8)],
            Flexible(child: Text(label, style: AppText.button.copyWith(fontSize: 16), overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

class IconCircleButton extends StatelessWidget {
  const IconCircleButton({super.key, required this.icon, this.onTap, this.size = 46, this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = Pressable(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.surface.withOpacity(0.85),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.stroke),
        ),
        child: Icon(icon, color: AppColors.text, size: size * 0.48),
      ),
    );
    return tooltip == null ? btn : Semantics(label: tooltip, button: true, child: btn);
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.color, this.border});
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface.withOpacity(0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: border ?? AppColors.stroke),
      ),
      child: child,
    );
  }
}

class CoinPill extends StatelessWidget {
  const CoinPill({super.key, required this.coins, this.compact = false});
  final int coins;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: compact ? 6 : 9),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const CoinIcon(size: 18),
        const SizedBox(width: 6),
        TweenAnimationBuilder<double>(
          tween: Tween(end: coins.toDouble()),
          duration: const Duration(milliseconds: 600),
          builder: (_, v, __) => Text('${v.round()}', style: AppText.number.copyWith(fontSize: compact ? 14 : 16)),
        ),
      ]),
    );
  }
}

class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 18});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.coin,
          border: Border.all(color: const Color(0xFFB27A00), width: size * 0.09),
        ),
        child: Center(
          child: Container(
            width: size * 0.45,
            height: size * 0.45,
            decoration:
                BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFB27A00), width: size * 0.07)),
          ),
        ),
      );
}

/// Shape + color glyph (accessibility: color is never the only cue).
class ColorGlyph extends StatelessWidget {
  const ColorGlyph({super.key, required this.color, this.size = 22, this.outline = true});
  final GameColor color;
  final double size;
  final bool outline;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: _GlyphPainter(color, outline)));
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.color, this.outline);
  final GameColor color;
  final bool outline;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 * 0.86;
    Shapes.drawColor(canvas, color, c, r, Paint()..color = color.color);
    if (outline) {
      Shapes.drawColor(
          canvas,
          color,
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.5, r * 0.14)
            ..color = Colors.white.withOpacity(0.9));
    }
  }

  @override
  bool shouldRepaint(covariant _GlyphPainter old) => old.color != color;
}

class GravityArrowIcon extends StatelessWidget {
  const GravityArrowIcon({super.key, required this.dir, this.size = 22, this.color = Colors.white});
  final GravityDir dir;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _ArrowPainter(dir, color)),
      );
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.dir, this.color);
  final GravityDir dir;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) =>
      Shapes.drawArrow(canvas, dir, size.center(Offset.zero), size.shortestSide / 2 * 0.9, Paint()..color = color);
  @override
  bool shouldRepaint(covariant _ArrowPainter old) => old.dir != dir || old.color != color;
}

class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.stars, this.size = 16, this.spacing = 2});
  final int stars;
  final double size;
  final double spacing;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing / 2),
              child: Icon(Icons.star_rounded, size: size, color: i < stars ? AppColors.star : AppColors.locked),
            ),
        ],
      );
}

class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.trailing, this.onBack});
  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        IconCircleButton(
            icon: Icons.arrow_back_rounded, tooltip: 'Back', onTap: onBack ?? () => Navigator.of(context).maybePop()),
        const SizedBox(width: 14),
        Expanded(child: Text(title, style: AppText.title, overflow: TextOverflow.ellipsis)),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(4, 18, 4, 10), child: Text(text.toUpperCase(), style: AppText.label));
}

/// Dark backdrop with a soft brand glow; used behind menu screens.
class MenuBackdrop extends StatelessWidget {
  const MenuBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -1.1),
          radius: 1.3,
          colors: [Color(0xFF1D2350), AppColors.bg, AppColors.bgDeep],
          stops: [0, 0.55, 1],
        ),
      ),
      child: child,
    );
  }
}

void showToast(BuildContext context, String text, {IconData icon = Icons.info_outline_rounded}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content:
          Row(children: [Icon(icon, color: AppColors.text, size: 20), const SizedBox(width: 10), Expanded(child: Text(text))]),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      duration: const Duration(milliseconds: 2200),
    ));
}

/// Entrance animation (fade + rise) with an optional stagger delay.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn(
      {super.key,
      required this.child,
      this.delay = Duration.zero,
      this.offset = 0.08,
      this.duration = const Duration(milliseconds: 420)});
  final Widget child;
  final Duration delay;
  final double offset;
  final Duration duration;

  /// Staggered delay for list item [i] (capped so long lists stay snappy).
  static Duration stagger(int i, {int stepMs = 45, int maxItems = 10}) =>
      Duration(milliseconds: stepMs * (i < maxItems ? i : maxItems));

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _a,
        child:
            SlideTransition(position: Tween(begin: Offset(0, widget.offset), end: Offset.zero).animate(_a), child: widget.child),
      );
}

/// Smoothly animated linear progress bar.
class AnimatedBar extends StatelessWidget {
  const AnimatedBar({super.key, required this.value, this.color = AppColors.brand2, this.height = 6});
  final double value;
  final Color color;
  final double height;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: LinearProgressIndicator(
            value: v,
            minHeight: height,
            backgroundColor: Colors.white10,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      );
}

/// Easy / Medium / Hard / Very Hard pill.
class TierBadge extends StatelessWidget {
  const TierBadge({super.key, required this.label, required this.color, this.small = false});
  final String label;
  final Color color;
  final bool small;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 7 : 10, vertical: small ? 2 : 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.speed_rounded, size: small ? 11 : 14, color: color),
          SizedBox(width: small ? 3 : 5),
          Text(label.toUpperCase(), style: AppText.label.copyWith(color: color, fontSize: small ? 9.5 : 11, letterSpacing: 0.8)),
        ]),
      );
}
