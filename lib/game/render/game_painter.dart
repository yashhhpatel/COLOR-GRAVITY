import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/game_constants.dart';
import '../../core/models/game_color.dart';
import '../../core/models/gravity_dir.dart';
import '../../core/theme/world_themes.dart';
import '../collision/collision.dart';
import '../effects/particles.dart';
import '../engine/game_engine.dart';
import '../entities/entity.dart';
import 'shapes.dart';
import 'world_background.dart';

/// Maps the logical arena onto the screen (uniform scale, centered).
class ArenaTransform {
  ArenaTransform(this.size) : scale = math.min(size.width / Arena.width, size.height / Arena.height) {
    offset = Offset((size.width - Arena.width * scale) / 2, (size.height - Arena.height * scale) / 2);
  }
  final double scale;
  final Size size;
  late final Offset offset;

  Offset toArena(Offset screen) => (screen - offset) / scale;
}

/// Renders a [GameEngine] frame. Paints are cached; nothing heavy per frame.
class GamePainter extends CustomPainter {
  GamePainter(this.engine) : super(repaint: engine) {
    _bg = WorldBackground(WorldTheme.byId(engine.config.worldId));
  }

  final GameEngine engine;
  late final WorldBackground _bg;

  final Paint _fill = Paint();
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Expando<TextPainter> _textCache = Expando();
  final Map<String, TextPainter> _labelCache = {};
  Shader? _rainbow;

  static const _hazardBody = Color(0xFF262C48);
  static const _hazardEdge = Color(0xFFE9ECF8);
  static const _white = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final e = engine;
    final t = ArenaTransform(size);
    final time = e.camera.time;
    _bg.paint(canvas, size, unit: t.scale, scroll: e.traveled, time: time, gravity: e.gravity.vector);

    canvas.save();
    canvas.translate(t.offset.dx, t.offset.dy);
    canvas.scale(t.scale);
    // Camera: shake + zoom pulse around the arena center.
    final z = e.camera.zoom;
    final sh = e.camera.offset;
    canvas.translate(Arena.width / 2 + sh.dx, Arena.height / 2 + sh.dy);
    canvas.scale(z);
    canvas.translate(-Arena.width / 2, -Arena.height / 2);

    _paintArena(canvas, time);
    // Layers: zones → gates/switches → hazards → collectibles → player → fx.
    for (final en in e.entities) {
      switch (en.kind) {
        case EntityKind.gravityZone:
        case EntityKind.lockZone:
        case EntityKind.mergeZone:
        case EntityKind.basin:
          _paintZone(canvas, en, time);
        default:
          break;
      }
    }
    for (final en in e.entities) {
      switch (en.kind) {
        case EntityKind.gate:
          _paintGate(canvas, en, time);
        case EntityKind.colorSwitch:
          _paintColorSwitch(canvas, en, time);
        case EntityKind.gravitySwitch:
          _paintGravitySwitch(canvas, en, time);
        case EntityKind.finish:
          _paintFinish(canvas, en);
        case EntityKind.checkpoint:
          _paintCheckpoint(canvas, en, time);
        default:
          break;
      }
    }
    for (final en in e.entities) {
      if (en.isHazard) _paintHazard(canvas, en, time);
    }
    for (final en in e.entities) {
      switch (en.kind) {
        case EntityKind.orb:
          _paintOrb(canvas, en, time);
        case EntityKind.coin:
          _paintCoin(canvas, en, time);
        case EntityKind.powerUp:
          _paintPowerUp(canvas, en, time);
        case EntityKind.special:
          _paintSpecial(canvas, en, time);
        default:
          break;
      }
    }
    _paintPlayer(canvas, time);
    _paintParticles(canvas);
    _paintTexts(canvas);
    canvas.restore();

    // Letterbox fade outside the arena so gameplay edges stay crisp.
    _fill
      ..shader = null
      ..color = const Color(0x66000000);
    if (t.offset.dy > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, t.offset.dy), _fill);
      canvas.drawRect(Rect.fromLTWH(0, size.height - t.offset.dy, size.width, t.offset.dy), _fill);
    }
    if (t.offset.dx > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, t.offset.dx, size.height), _fill);
      canvas.drawRect(Rect.fromLTWH(size.width - t.offset.dx, 0, t.offset.dx, size.height), _fill);
    }
  }

  // ------------------------------------------------------------------ arena
  void _paintArena(Canvas canvas, double time) {
    final e = engine;
    // Side walls of the tunnel.
    _fill
      ..shader = null
      ..color = const Color(0x22000000);
    canvas.drawRect(const Rect.fromLTRB(0, 0, Arena.wallLeft, Arena.height), _fill);
    canvas.drawRect(const Rect.fromLTRB(Arena.wallRight, 0, Arena.width, Arena.height), _fill);
    _stroke
      ..strokeWidth = 1.2
      ..color = const Color(0x22FFFFFF);
    canvas.drawLine(const Offset(Arena.wallLeft, 0), const Offset(Arena.wallLeft, Arena.height), _stroke);
    canvas.drawLine(const Offset(Arena.wallRight, 0), const Offset(Arena.wallRight, Arena.height), _stroke);

    // Gravity field frame with the active side glowing.
    const f = Arena.field;
    final rr = RRect.fromRectAndRadius(f, const Radius.circular(18));
    _stroke
      ..strokeWidth = 1
      ..color = const Color(0x18FFFFFF);
    canvas.drawRRect(rr, _stroke);

    final g = e.gravity.dir;
    final pc = e.player.color.color;
    final pulse = e.gravity.pulse;
    final (a, b) = switch (g) {
      GravityDir.down => (f.bottomLeft + const Offset(18, 0), f.bottomRight - const Offset(18, 0)),
      GravityDir.up => (f.topLeft + const Offset(18, 0), f.topRight - const Offset(18, 0)),
      GravityDir.left => (f.topLeft + const Offset(0, 18), f.bottomLeft - const Offset(0, 18)),
      GravityDir.right => (f.topRight + const Offset(0, 18), f.bottomRight - const Offset(0, 18)),
    };
    _stroke
      ..strokeWidth = 7 + pulse * 6
      ..color = pc.withOpacity(0.10 + pulse * 0.2);
    canvas.drawLine(a, b, _stroke);
    _stroke
      ..strokeWidth = 2.2
      ..color = pc.withOpacity(0.55 + pulse * 0.45);
    canvas.drawLine(a, b, _stroke);

    // Moving chevrons along the field showing the pull direction.
    _fill.color = _white.withOpacity(0.06 + pulse * 0.12);
    final gv = g.vector;
    final angle = g.angle;
    for (var i = 0; i < 3; i++) {
      final phase = ((time * 0.8 + i / 3) % 1.0);
      final c = f.center + gv * ((phase - 0.5) * (g.isVertical ? f.height : f.width) * 0.8);
      Shapes.drawChevron(canvas, angle, c, 14, _fill);
    }

    // Scripted gravity warning.
    final w = e.gravity.warning;
    if (w != null) {
      final blink = (math.sin(time * 18) + 1) / 2;
      _fill.color = _white.withOpacity(0.25 + 0.5 * blink);
      Shapes.drawArrow(canvas, w, f.center, 34, _fill);
    }
  }

  // ------------------------------------------------------------------ zones
  void _paintZone(Canvas canvas, Entity z, double time) {
    final r = z.rect;
    switch (z.kind) {
      case EntityKind.gravityZone:
        final active = engine.gravity.activeZone == z;
        _fill
          ..shader = null
          ..color = const Color(0xFF6FB6FF).withOpacity(active ? 0.13 : 0.07);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)), _fill);
        _stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF6FB6FF).withOpacity(0.5);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)), _stroke);
        _fill.color = const Color(0xFF9FD0FF).withOpacity(0.35);
        final d = z.dir!;
        for (var row = 0; row < (r.height / 60).floor(); row++) {
          for (var col = 0; col < 4; col++) {
            final phase = (time * 0.9 + col * 0.25) % 1.0;
            final base = Offset(r.left + (col + 0.5) * r.width / 4, r.top + 30 + row * 60);
            final c = base + d.vector * (phase * 24 - 12);
            Shapes.drawChevron(canvas, d.angle, c, 9, _fill);
          }
        }
      case EntityKind.lockZone:
        _fill
          ..shader = null
          ..color = const Color(0x14FFFFFF);
        canvas.drawRect(r, _fill);
        _stroke
          ..strokeWidth = 1
          ..color = const Color(0x22FFFFFF);
        canvas.save();
        canvas.clipRect(r);
        for (var x = r.left - r.height; x < r.right; x += 22) {
          canvas.drawLine(Offset(x, r.bottom), Offset(x + r.height, r.top), _stroke);
        }
        canvas.restore();
        _paintLock(canvas, Offset(r.left + 20, r.top + 20), 9);
        _paintLock(canvas, Offset(r.right - 20, r.top + 20), 9);
        _label(canvas, 'GRAVITY LOCK', Offset(r.center.dx, r.top + 14), 10, const Color(0x99FFFFFF));
      case EntityKind.mergeZone:
        final glow = 0.4 + 0.2 * math.sin(time * 4);
        _fill
          ..shader = null
          ..color = const Color(0xFFFFD45C).withOpacity(0.06);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(16)), _fill);
        _stroke
          ..strokeWidth = 3
          ..color = const Color(0xFFFFD45C).withOpacity(glow);
        final cup = Path()
          ..moveTo(r.left, r.top + 10)
          ..lineTo(r.left, r.bottom - 16)
          ..quadraticBezierTo(r.left, r.bottom, r.left + 16, r.bottom)
          ..lineTo(r.right - 16, r.bottom)
          ..quadraticBezierTo(r.right, r.bottom, r.right, r.bottom - 16)
          ..lineTo(r.right, r.top + 10);
        canvas.drawPath(cup, _stroke);
        canvas.drawLine(
            r.topLeft + const Offset(0, 10),
            r.topRight + const Offset(0, 10),
            _stroke
              ..strokeWidth = 1
              ..color = const Color(0x33FFD45C));
        _label(canvas, 'MERGE ×2', Offset(r.center.dx, r.top - 8), 10, const Color(0xCCFFD45C));
      case EntityKind.basin:
        final c = z.color!;
        _fill
          ..shader = null
          ..color = c.color.withOpacity(0.12 + z.flash * 0.6);
        final rr = RRect.fromRectAndRadius(r, const Radius.circular(12));
        canvas.drawRRect(rr, _fill);
        _stroke
          ..strokeWidth = 2.5
          ..color = c.color.withOpacity(0.85);
        canvas.drawRRect(rr, _stroke);
        _fill.color = c.color.withOpacity(0.7);
        Shapes.drawColor(canvas, c, r.center, 14, _fill);
        _label(canvas, 'BASIN', Offset(r.center.dx, r.top - 8), 9, c.color);
      default:
        break;
    }
  }

  void _paintLock(Canvas canvas, Offset c, double s) {
    _stroke
      ..strokeWidth = 2
      ..color = const Color(0x88FFFFFF);
    canvas.drawArc(Rect.fromCircle(center: c - Offset(0, s * 0.4), radius: s * 0.55), math.pi, math.pi, false, _stroke);
    _fill.color = const Color(0x88FFFFFF);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: c + Offset(0, s * 0.35), width: s * 1.6, height: s * 1.2), const Radius.circular(2)),
        _fill);
  }

  // -------------------------------------------------------------- gates etc.
  void _paintGate(Canvas canvas, Entity g, double time) {
    final r = g.rect;
    final colors = g.gateColors;
    final base = colors == null ? const Color(0xFFDDE6FF) : colors.first.color;
    final fade = g.passed && !g.triggered ? 0.35 : 1.0;
    final failed = g.triggered;

    // Body with diagonal energy stripes.
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(6));
    _fill
      ..shader = null
      ..color = (failed ? const Color(0xFFFF5470) : base).withOpacity((0.22 + g.flash * 0.5) * fade);
    canvas.drawRRect(rr, _fill);
    canvas.save();
    canvas.clipRRect(rr);
    _stroke
      ..strokeWidth = 3
      ..color = base.withOpacity(0.25 * fade);
    final off = (time * 30) % 16;
    for (var x = r.left - 20 + off; x < r.right + 20; x += 16) {
      canvas.drawLine(Offset(x, r.bottom), Offset(x + r.height, r.top), _stroke);
    }
    canvas.restore();
    _stroke
      ..strokeWidth = 2
      ..color = base.withOpacity(0.9 * fade);
    canvas.drawRRect(rr, _stroke);
    if (colors != null && colors.length > 1) {
      // Multi-color gate: segmented top edge.
      final segW = r.width / colors.length;
      for (var i = 0; i < colors.length; i++) {
        _stroke
          ..strokeWidth = 3
          ..color = colors[i].color.withOpacity(fade);
        canvas.drawLine(Offset(r.left + i * segW + 4, r.top), Offset(r.left + (i + 1) * segW - 4, r.top), _stroke);
      }
    }

    // Requirement badges along the gate: shape(s) + arrow.
    final badges = <void Function(Offset)>[];
    if (colors != null) {
      for (final c in colors) {
        badges.add((o) {
          _fill.color = c.color.withOpacity(fade);
          Shapes.drawColor(canvas, c, o, 8, _fill);
          _stroke
            ..strokeWidth = 1.5
            ..color = _white.withOpacity(0.9 * fade);
          Shapes.drawColor(canvas, c, o, 8, _stroke);
          if (g.gateMode == GateMode.block) {
            _stroke
              ..strokeWidth = 2.5
              ..color = const Color(0xFFFF5470).withOpacity(fade);
            canvas.drawLine(o + const Offset(-10, 10), o + const Offset(10, -10), _stroke);
          }
        });
      }
    }
    if (g.gateDir != null) {
      badges.add((o) {
        _fill.color = _white.withOpacity(fade);
        Shapes.drawArrow(canvas, g.gateDir!, o, 9, _fill);
      });
    }
    if (g.effectDir != null) {
      badges.add((o) {
        _fill.color = const Color(0xFF9FD8FF).withOpacity(fade);
        Shapes.drawChevron(canvas, g.effectDir!.angle, o - g.effectDir!.vector * 4, 8, _fill);
        Shapes.drawChevron(canvas, g.effectDir!.angle, o + g.effectDir!.vector * 4, 8, _fill);
      });
    }
    if (badges.isEmpty) return;
    final reps = r.width > 200 ? 3 : 1;
    for (var k = 0; k < reps; k++) {
      final cx = r.left + r.width * (k + 0.5) / reps;
      final total = badges.length * 24.0;
      for (var i = 0; i < badges.length; i++) {
        final o = Offset(cx - total / 2 + 12 + i * 24, r.center.dy);
        _fill.color = const Color(0xCC0A0E1C);
        canvas.drawCircle(o, 11, _fill);
        badges[i](o);
      }
    }
  }

  void _paintColorSwitch(Canvas canvas, Entity s, double time) {
    final c = s.color!;
    if (s.fullWidth) {
      final r = s.rect;
      _fill
        ..shader = null
        ..color = c.color.withOpacity((0.55 + s.flash).clamp(0.0, 1.0));
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(7)), _fill);
      _fill.color = _white.withOpacity(0.85);
      for (var x = r.left + 22.0; x < r.right; x += 44) {
        Shapes.drawColor(canvas, c, Offset(x, r.center.dy), 4.5, _fill);
      }
      return;
    }
    final o = Offset(s.x, s.y);
    final pulse = 1 + 0.08 * math.sin(time * 6);
    _fill
      ..shader = null
      ..color = c.color.withOpacity(0.18);
    canvas.drawCircle(o, s.r * 1.5 * pulse, _fill);
    _stroke
      ..strokeWidth = 3.5
      ..color = c.color;
    // Rotating segmented ring.
    for (var i = 0; i < 4; i++) {
      final a = time * 2 + i * math.pi / 2;
      canvas.drawArc(Rect.fromCircle(center: o, radius: s.r * pulse), a, math.pi / 3, false, _stroke);
    }
    _fill.color = c.color;
    Shapes.drawColor(canvas, c, o, s.r * 0.5, _fill);
  }

  void _paintGravitySwitch(Canvas canvas, Entity s, double time) {
    final o = Offset(s.x, s.y);
    final used = s.triggered;
    final rect = Rect.fromCircle(center: o, radius: s.r);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    _fill
      ..shader = null
      ..color = used ? const Color(0x22FFFFFF) : const Color(0xFF1A2A4A);
    canvas.drawRRect(rr, _fill);
    _stroke
      ..strokeWidth = 2.5
      ..color = s.triggerColor?.color ?? const Color(0xFF9FD8FF).withOpacity(used ? 0.3 : 1);
    canvas.drawRRect(rr, _stroke);
    final bob = used ? 0.0 : math.sin(time * 5) * 2;
    _fill.color = _white.withOpacity(used ? 0.3 : 1);
    Shapes.drawArrow(canvas, s.dir!, o + s.dir!.vector * bob, s.r * 0.6, _fill);
    if (s.triggerColor != null) {
      _fill.color = s.triggerColor!.color;
      Shapes.drawColor(canvas, s.triggerColor!, o + Offset(s.r * 0.75, -s.r * 0.75), 5, _fill);
    }
  }

  void _paintCheckpoint(Canvas canvas, Entity c, double time) {
    const teal = Color(0xFF5CF2C2);
    final r = c.rect;
    final y = r.center.dy;
    if (c.passed) {
      _fill
        ..shader = null
        ..color = teal.withOpacity(0.10 + c.flash * 0.6);
      canvas.drawRect(r.inflate(4), _fill);
    }
    _stroke
      ..strokeWidth = 3
      ..color = teal.withOpacity(c.passed ? 0.45 : 0.9);
    final shift = (time * 24) % 18;
    for (var x = r.left - 18 + shift; x < r.right; x += 18) {
      canvas.drawLine(Offset(math.max(x, r.left), y), Offset(math.min(x + 10, r.right), y), _stroke);
    }
    // Flag on the left wall.
    _stroke
      ..strokeWidth = 2
      ..color = teal;
    canvas.drawLine(Offset(r.left + 14, y), Offset(r.left + 14, y - 26), _stroke);
    _fill.color = teal;
    canvas.drawPath(
        Path()
          ..moveTo(r.left + 15, y - 26)
          ..lineTo(r.left + 32 + math.sin(time * 6) * 2, y - 21)
          ..lineTo(r.left + 15, y - 16)
          ..close(),
        _fill);
    _label(canvas, 'CHECKPOINT', Offset(r.center.dx, y - 12), 10, teal);
  }

  void _paintFinish(Canvas canvas, Entity f) {
    final r = f.rect;
    const sq = 12.0;
    var row = 0;
    for (var y = r.top; y < r.bottom; y += sq, row++) {
      var col = 0;
      for (var x = r.left; x < r.right; x += sq, col++) {
        _fill
          ..shader = null
          ..color = (row + col).isEven ? const Color(0xEEFFFFFF) : const Color(0xEE1A1F36);
        canvas.drawRect(Rect.fromLTWH(x, y, math.min(sq, r.right - x), math.min(sq, r.bottom - y)), _fill);
      }
    }
    _label(canvas, 'FINISH', Offset(r.center.dx, r.top - 12), 13, _white);
  }

  // ---------------------------------------------------------------- hazards
  void _paintHazard(Canvas canvas, Entity h, double time) {
    final colored = h.dangerColor;
    final dangerNow = colored == null || colored == engine.player.color;
    final ghost = colored != null && !dangerNow;
    final alpha = ghost ? 0.35 : 1.0;
    switch (h.kind) {
      case EntityKind.block:
        final rr = RRect.fromRectAndRadius(h.rect, const Radius.circular(7));
        _fill
          ..shader = null
          ..color = (colored?.deep ?? _hazardBody).withOpacity(alpha);
        canvas.drawRRect(rr, _fill);
        // Warning stripes
        canvas.save();
        canvas.clipRRect(rr);
        _stroke
          ..strokeWidth = 4
          ..color = (colored?.color ?? const Color(0xFF3A4270)).withOpacity(0.55 * alpha);
        for (var x = h.rect.left - h.rect.height; x < h.rect.right; x += 14) {
          canvas.drawLine(Offset(x, h.rect.bottom), Offset(x + h.rect.height, h.rect.top), _stroke);
        }
        canvas.restore();
        _stroke
          ..strokeWidth = 2
          ..color = (colored?.color ?? _hazardEdge).withOpacity(((0.85 + h.flash) * alpha).clamp(0.0, 1.0));
        canvas.drawRRect(rr, _stroke);
        if (h.motion == BlockMotion.crusher) {
          final gv = engine.gravity.dir;
          _fill.color = _white.withOpacity(0.7 * alpha);
          Shapes.drawChevron(canvas, gv.angle, Offset(h.x, h.y), 7, _fill);
        }
        if (colored != null) {
          _fill.color = colored.color.withOpacity(alpha);
          Shapes.drawColor(canvas, colored, Offset(h.x, h.y), 7, _fill);
        }
      case EntityKind.spikes:
        _paintSpikes(canvas, h, alpha, time);
      case EntityKind.laser:
        _paintLaser(canvas, h, time);
      case EntityKind.rotor:
        final (a, b) = h.rotorEnds;
        _stroke
          ..strokeWidth = h.h + 4
          ..color = const Color(0x55000000);
        canvas.drawLine(a, b, _stroke);
        _stroke
          ..strokeWidth = h.h
          ..color = _hazardEdge;
        canvas.drawLine(a, b, _stroke);
        _stroke
          ..strokeWidth = h.h * 0.4
          ..color = const Color(0xFFFF5470);
        canvas.drawLine(Offset.lerp(a, b, 0.08)!, Offset.lerp(a, b, 0.92)!, _stroke);
        _fill.color = _hazardBody;
        canvas.drawCircle(Offset(h.x, h.y), 9, _fill);
        _stroke
          ..strokeWidth = 2
          ..color = _hazardEdge;
        canvas.drawCircle(Offset(h.x, h.y), 9, _stroke);
      case EntityKind.meteor:
        final o = Offset(h.x, h.y);
        _fill.color = const Color(0x33FF5470);
        canvas.drawCircle(o, h.r * 1.5, _fill);
        _fill.color = const Color(0xFF3A3550);
        canvas.drawCircle(o, h.r, _fill);
        _stroke
          ..strokeWidth = 2
          ..color = _hazardEdge;
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4 + h.age * 2;
          canvas.drawLine(o + Offset(math.cos(a), math.sin(a)) * h.r, o + Offset(math.cos(a), math.sin(a)) * (h.r + 5), _stroke);
        }
        canvas.drawCircle(o, h.r, _stroke);
      default:
        break;
    }
  }

  void _paintSpikes(Canvas canvas, Entity h, double alpha, double time) {
    final r = h.rect;
    final vertical = r.height > r.width;
    final colored = h.dangerColor;
    var tip = colored?.color ?? _hazardEdge;
    if (vertical) {
      // Gravity spikes on a field edge: glow when gravity pulls toward them.
      final left = h.x < Arena.width / 2;
      final armed = engine.gravity.dir == (left ? GravityDir.left : GravityDir.right);
      if (armed) {
        _fill.color = const Color(0xFFFF5470).withOpacity(0.18 + 0.1 * math.sin(time * 10));
        canvas.drawRect(r.inflate(6), _fill);
        tip = const Color(0xFFFF8A9A);
      }
    }
    final path = Path();
    if (!vertical) {
      final n = math.max(2, (r.width / 14).round());
      final w = r.width / n;
      for (var i = 0; i < n; i++) {
        final x = r.left + i * w;
        path
          ..moveTo(x, r.bottom)
          ..lineTo(x + w / 2, r.top)
          ..lineTo(x + w, r.bottom);
        // mirrored half for readability from both sides
        path
          ..moveTo(x, r.top + r.height * 0.5)
          ..lineTo(x + w / 2, r.bottom + 4)
          ..lineTo(x + w, r.top + r.height * 0.5);
      }
    } else {
      final left = h.x < Arena.width / 2;
      final n = math.max(2, (r.height / 14).round());
      final w = r.height / n;
      for (var i = 0; i < n; i++) {
        final y = r.top + i * w;
        if (left) {
          path
            ..moveTo(r.left, y)
            ..lineTo(r.right, y + w / 2)
            ..lineTo(r.left, y + w);
        } else {
          path
            ..moveTo(r.right, y)
            ..lineTo(r.left, y + w / 2)
            ..lineTo(r.right, y + w);
        }
      }
    }
    _fill
      ..shader = null
      ..color = tip.withOpacity(alpha);
    canvas.drawPath(path, _fill);
    _stroke
      ..strokeWidth = 1
      ..color = const Color(0x66000000);
    canvas.drawPath(path, _stroke);
    if (colored != null) {
      _fill.color = _white.withOpacity(alpha);
      final step = vertical ? r.height / 3 : r.width / 3;
      for (var i = 0; i < 3; i++) {
        final c = vertical ? Offset(r.center.dx, r.top + step * (i + 0.5)) : Offset(r.left + step * (i + 0.5), r.center.dy);
        _fill.color = const Color(0xDD0A0E1C);
        canvas.drawCircle(c, 7, _fill);
        _fill.color = colored.color.withOpacity(alpha);
        Shapes.drawColor(canvas, colored, c, 5, _fill);
      }
    }
  }

  void _paintLaser(Canvas canvas, Entity l, double time) {
    if (l.followsGravity) {
      final (a, b) = Collision.gravityBeam(l, engine.gravity.dir);
      _stroke
        ..strokeWidth = 10
        ..color = const Color(0x44FF5470);
      canvas.drawLine(a, b, _stroke);
      _stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFFFB3BE);
      canvas.drawLine(a, b, _stroke);
      _fill.color = _hazardBody;
      canvas.drawCircle(a, 10, _fill);
      _stroke
        ..strokeWidth = 2
        ..color = _hazardEdge;
      canvas.drawCircle(a, 10, _stroke);
      _fill.color = const Color(0xFFFF5470);
      Shapes.drawArrow(canvas, engine.gravity.dir, a, 6, _fill);
      return;
    }
    final r = l.rect;
    final y = r.center.dy;
    // Emitters
    _fill.color = _hazardBody;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(r.left + 6, y), width: 12, height: 20), const Radius.circular(3)),
        _fill);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(r.right - 6, y), width: 12, height: 20), const Radius.circular(3)),
        _fill);
    if (l.laserOn) {
      _stroke
        ..strokeWidth = 12
        ..color = const Color(0x55FF5470);
      canvas.drawLine(Offset(r.left + 12, y), Offset(r.right - 12, y), _stroke);
      _stroke
        ..strokeWidth = 3.5
        ..color = const Color(0xFFFFD6DC);
      canvas.drawLine(Offset(r.left + 12, y), Offset(r.right - 12, y), _stroke);
    } else if (l.laserWarming) {
      final blink = (math.sin(time * 40) + 1) / 2;
      _stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFFF5470).withOpacity(0.3 + 0.5 * blink);
      canvas.drawLine(Offset(r.left + 12, y), Offset(r.right - 12, y), _stroke);
    } else {
      _stroke
        ..strokeWidth = 1
        ..color = const Color(0x33FF5470);
      for (var x = r.left + 14; x < r.right - 14; x += 10) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), _stroke);
      }
    }
  }

  // ----------------------------------------------------------- collectibles
  void _paintOrb(Canvas canvas, Entity o, double time) {
    final c = Offset(o.x, o.y);
    final spawn = o.age < 0.25 ? Curves.easeOutBack.transform((o.age / 0.25).clamp(0, 1)) : 1.0;
    final r = o.r * (0.6 + 0.4 * spawn) * (1 + o.flash * 0.5);
    final matches = engine.colors.canCollect(engine.player.color, o);

    if (o.wildcard) {
      _rainbow ??= const SweepGradient(colors: [
        Color(0xFFFF4D5E),
        Color(0xFFFFC93D),
        Color(0xFF2EDB8A),
        Color(0xFF3D8BFF),
        Color(0xFFB45CFF),
        Color(0xFFFF4D5E),
      ]).createShader(Rect.fromCircle(center: Offset.zero, radius: 1));
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(time * 2);
      canvas.scale(r);
      _fill.shader = _rainbow;
      canvas.drawCircle(Offset.zero, 1, _fill);
      _fill.shader = null;
      canvas.restore();
      _fill.color = _white;
      Shapes.draw(canvas, ColorShape.star, c, r * 0.5, _fill);
      return;
    }
    final gc = o.color!;
    // Cheap two-step glow.
    _fill
      ..shader = null
      ..color = gc.color.withOpacity(matches ? 0.16 : 0.07);
    canvas.drawCircle(c, r * 1.6, _fill);
    _fill.color = gc.color.withOpacity(matches ? 0.22 : 0.10);
    canvas.drawCircle(c, r * 1.25, _fill);
    _fill.color = gc.color;
    Shapes.drawColor(canvas, gc, c, r, _fill);
    _stroke
      ..strokeWidth = 2
      ..color = gc.deep;
    Shapes.drawColor(canvas, gc, c, r, _stroke);
    // Highlight
    _fill.color = const Color(0x55FFFFFF);
    canvas.drawCircle(c + Offset(-r * 0.3, -r * 0.35), r * 0.28, _fill);
    // Merge level pips
    if (o.level > 1) {
      _fill.color = _white;
      final n = o.level - 1;
      for (var i = 0; i < n; i++) {
        final a = -math.pi / 2 + (i - (n - 1) / 2) * 0.55;
        canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r * 0.45 + Offset(0, r * 0.35), 1.8, _fill);
      }
    }
    if (o.behavior == OrbBehavior.anchor) {
      _stroke
        ..strokeWidth = 2
        ..color = _white;
      canvas.drawCircle(c, r + 4, _stroke);
      canvas.drawLine(c + Offset(0, r + 4), c + Offset(0, r + 9), _stroke);
    } else if (o.behavior == OrbBehavior.reverse) {
      _fill.color = _white;
      Shapes.drawArrow(canvas, engine.gravity.dir.opposite, c + engine.gravity.dir.opposite.vector * (r + 7), 5, _fill);
    }
    if (o.flash > 0) {
      _fill.color = _white.withOpacity((o.flash * 1.8).clamp(0, 1));
      Shapes.drawColor(canvas, gc, c, r, _fill);
    }
  }

  void _paintCoin(Canvas canvas, Entity e, double time) {
    final c = Offset(e.x, e.y);
    final sx = math.cos(time * 3 + e.trackY * 0.05).abs() * 0.7 + 0.3;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(sx, 1);
    _fill
      ..shader = null
      ..color = const Color(0x33FFC23D);
    canvas.drawCircle(Offset.zero, e.r * 1.5, _fill);
    _fill.color = const Color(0xFFFFC23D);
    canvas.drawCircle(Offset.zero, e.r, _fill);
    _stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFFB27A00);
    canvas.drawCircle(Offset.zero, e.r * 0.62, _stroke);
    canvas.restore();
  }

  static const Map<PowerUpType, IconData> powerIcons = {
    PowerUpType.gravityControl: Icons.open_with_rounded,
    PowerUpType.colorShift: Icons.palette_rounded,
    PowerUpType.magnet: Icons.track_changes_rounded,
    PowerUpType.shield: Icons.shield_rounded,
    PowerUpType.slowMotion: Icons.slow_motion_video_rounded,
    PowerUpType.megaMerge: Icons.auto_awesome_rounded,
    PowerUpType.colorFreeze: Icons.ac_unit_rounded,
    PowerUpType.gravityFreeze: Icons.lock_clock_rounded,
    PowerUpType.doubleCoins: Icons.monetization_on_rounded,
    PowerUpType.perfectGravity: Icons.gps_fixed_rounded,
  };

  void _paintPowerUp(Canvas canvas, Entity e, double time) {
    final c = Offset(e.x, e.y + math.sin(time * 4 + e.trackY) * 3);
    _fill
      ..shader = null
      ..color = const Color(0x339FD8FF);
    canvas.drawCircle(c, e.r * 1.6, _fill);
    _fill.color = const Color(0xFF1B2A4E);
    canvas.drawCircle(c, e.r, _fill);
    _stroke
      ..strokeWidth = 2.5
      ..color = const Color(0xFF9FD8FF);
    canvas.drawArc(Rect.fromCircle(center: c, radius: e.r), time * 3, math.pi * 1.5, false, _stroke);
    _icon(canvas, powerIcons[e.powerUp]!, c, e.r * 1.1, _white);
  }

  void _paintSpecial(Canvas canvas, Entity e, double time) {
    final c = Offset(e.x, e.y);
    switch (e.special!) {
      case SpecialKind.bomb:
        _fill.color = const Color(0x33FF9F5A);
        canvas.drawCircle(c, e.r * 1.6, _fill);
        _fill.color = const Color(0xFF2B2235);
        canvas.drawCircle(c, e.r, _fill);
        _stroke
          ..strokeWidth = 2
          ..color = const Color(0xFFFF9F5A);
        canvas.drawCircle(c, e.r, _stroke);
        _fill.color = Color.lerp(const Color(0xFFFFE07A), const Color(0xFFFF5470), (math.sin(time * 12) + 1) / 2)!;
        canvas.drawCircle(c + Offset(e.r * 0.6, -e.r * 0.9), 3.5, _fill);
        _icon(canvas, Icons.flare_rounded, c, e.r * 1.1, const Color(0xFFFF9F5A));
      case SpecialKind.gravityBomb:
      case SpecialKind.gravityCore:
        final isBomb = e.special == SpecialKind.gravityBomb;
        final col = isBomb ? const Color(0xFFB45CFF) : _white;
        _fill.color = col.withOpacity(0.2);
        canvas.drawCircle(c, e.r * 1.6 + math.sin(time * 6) * 2, _fill);
        _fill.color = const Color(0xFF1A1F36);
        canvas.drawCircle(c, e.r, _fill);
        _stroke
          ..strokeWidth = 2
          ..color = col;
        canvas.drawCircle(c, e.r, _stroke);
        _fill.color = col;
        Shapes.drawArrow(canvas, GravityDir.up, c + const Offset(-4, 0), 6, _fill);
        Shapes.drawArrow(canvas, GravityDir.down, c + const Offset(4, 0), 6, _fill);
      case SpecialKind.colorCore:
        final gc = e.color ?? GameColor.purple;
        _fill.color = gc.color.withOpacity(0.25);
        canvas.drawCircle(c, e.r * 1.6, _fill);
        _fill.color = gc.color;
        Shapes.draw(canvas, ColorShape.diamond, c, e.r, _fill, rotation: time);
        _stroke
          ..strokeWidth = 2
          ..color = _white;
        Shapes.draw(canvas, ColorShape.diamond, c, e.r, _stroke, rotation: time);
        _fill.color = _white;
        Shapes.drawColor(canvas, gc, c, e.r * 0.4, _fill);
    }
  }

  // ----------------------------------------------------------------- player
  void _paintPlayer(Canvas canvas, double time) {
    final p = engine.player;
    final gc = p.color;
    final col = gc.color;
    final c = Offset(p.x, p.y);
    final r = p.r;
    final blink = p.invuln > 0 && (time * 14).floor().isEven;

    _paintTrail(canvas, p, col);
    if (blink) return;

    // Glow
    _fill
      ..shader = null
      ..color = col.withOpacity(0.14 + p.colorPulse * 0.25);
    canvas.drawCircle(c, r * 2.0 + p.colorPulse * 8, _fill);
    _fill.color = col.withOpacity(0.25);
    canvas.drawCircle(c, r * 1.45, _fill);

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(p.angle);
    // Squash along gravity axis on landing.
    canvas.scale(1 + p.squash * 0.25, 1 - p.squash * 0.25);

    final skin = engine.loadout.skin;
    switch (skin) {
      case 'skin_crystal':
        _fill.color = col.withOpacity(0.85);
        Shapes.draw(canvas, ColorShape.hexagon, Offset.zero, r, _fill, rotation: time * 0.6);
        _stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xCCFFFFFF);
        Shapes.draw(canvas, ColorShape.hexagon, Offset.zero, r, _stroke, rotation: time * 0.6);
        for (var i = 0; i < 3; i++) {
          final a = time * 0.6 + i * math.pi / 3;
          canvas.drawLine(Offset(math.cos(a), math.sin(a)) * r * 0.95,
              Offset(math.cos(a + math.pi), math.sin(a + math.pi)) * r * 0.95, _stroke..strokeWidth = 0.8);
        }
      case 'skin_neon':
        _stroke
          ..strokeWidth = 4
          ..color = col;
        canvas.drawCircle(Offset.zero, r - 2, _stroke);
        _stroke
          ..strokeWidth = 1.5
          ..color = _white;
        canvas.drawCircle(Offset.zero, r - 2, _stroke);
      case 'skin_shadow':
        _fill.color = const Color(0xFF12152A);
        canvas.drawCircle(Offset.zero, r, _fill);
        _stroke
          ..strokeWidth = 3
          ..color = col;
        canvas.drawCircle(Offset.zero, r - 1.5, _stroke);
      case 'skin_gold':
        _fill.color = col;
        canvas.drawCircle(Offset.zero, r, _fill);
        _stroke
          ..strokeWidth = 3.5
          ..color = const Color(0xFFFFD45C);
        canvas.drawCircle(Offset.zero, r - 1.5, _stroke);
        _stroke
          ..strokeWidth = 1
          ..color = const Color(0xFFFFF4C2);
        canvas.drawCircle(Offset.zero, r - 3.5, _stroke);
      case 'skin_galaxy':
        _fill.color = const Color(0xFF1B1440);
        canvas.drawCircle(Offset.zero, r, _fill);
        _fill.color = _white;
        for (var i = 0; i < 6; i++) {
          final a = i * 1.7 + time * 0.8;
          final d = (0.25 + (i % 3) * 0.22) * r;
          canvas.drawCircle(Offset(math.cos(a) * d, math.sin(a) * d), 0.9 + (i % 2), _fill);
        }
        _stroke
          ..strokeWidth = 2.5
          ..color = col;
        canvas.drawCircle(Offset.zero, r - 1, _stroke);
      case 'skin_cyber':
        _fill.color = col.withOpacity(0.9);
        canvas.drawCircle(Offset.zero, r, _fill);
        _stroke
          ..strokeWidth = 1
          ..color = const Color(0x99000000);
        for (var k = -1; k <= 1; k++) {
          canvas.drawLine(Offset(k * r * 0.45, -r * 0.9), Offset(k * r * 0.45, r * 0.9), _stroke);
          canvas.drawLine(Offset(-r * 0.9, k * r * 0.45), Offset(r * 0.9, k * r * 0.45), _stroke);
        }
        _stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF4DFFB8);
        canvas.drawCircle(Offset.zero, r - 1, _stroke);
      default: // classic
        _fill.color = col;
        canvas.drawCircle(Offset.zero, r, _fill);
        _stroke
          ..strokeWidth = 2.5
          ..color = _white;
        canvas.drawCircle(Offset.zero, r - 1.2, _stroke);
    }

    // Accessibility glyph (shape of current color) + gravity notch.
    _fill.color = skin == 'skin_classic' || skin == 'skin_gold' || skin == 'skin_cyber' || skin == 'skin_crystal' ? _white : col;
    Shapes.drawColor(canvas, gc, const Offset(0, -1), r * 0.42, _fill, rotation: -p.angle);
    _fill.color = _white;
    final notch = Path()
      ..moveTo(-5, r + 2)
      ..lineTo(0, r + 8)
      ..lineTo(5, r + 2)
      ..close();
    canvas.drawPath(notch, _fill);
    canvas.restore();

    if (p.shield) {
      _stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF9FD8FF).withOpacity(0.7 + 0.3 * math.sin(time * 6));
      canvas.drawCircle(c, r + 8, _stroke);
      _fill.color = const Color(0x229FD8FF);
      canvas.drawCircle(c, r + 8, _fill);
    }
  }

  void _paintTrail(Canvas canvas, Player p, Color col) {
    final trail = p.trail;
    if (trail.length < 2) return;
    switch (engine.loadout.trail) {
      case 'trail_spark':
        for (var i = 1; i < trail.length; i += 2) {
          final t = 1 - i / trail.length;
          _fill.color = const Color(0xFFFFE08A).withOpacity(0.7 * t);
          canvas.drawCircle(trail[i] + Offset(math.sin(i * 2.3) * 4, math.cos(i * 1.7) * 4), 2.2 * t + 0.6, _fill);
        }
      case 'trail_pulse':
        for (var i = 2; i < trail.length; i += 3) {
          final t = 1 - i / trail.length;
          _stroke
            ..strokeWidth = 1.5
            ..color = col.withOpacity(0.5 * t);
          canvas.drawCircle(trail[i], p.r * (0.5 + 0.5 * t), _stroke);
        }
      case 'trail_rainbow':
        for (var i = 1; i < trail.length; i++) {
          final t = 1 - i / trail.length;
          _stroke
            ..strokeWidth = p.r * 1.2 * t
            ..color = GameColor.base[i % GameColor.base.length].color.withOpacity(0.55 * t);
          canvas.drawLine(trail[i - 1], trail[i], _stroke);
        }
      default:
        for (var i = 1; i < trail.length; i++) {
          final t = 1 - i / trail.length;
          _stroke
            ..strokeWidth = p.r * 1.4 * t
            ..color = col.withOpacity(0.28 * t);
          canvas.drawLine(trail[i - 1], trail[i], _stroke);
        }
    }
  }

  // --------------------------------------------------------------------- fx
  void _paintParticles(Canvas canvas) {
    for (final pt in engine.particles.active) {
      final t = pt.t;
      switch (pt.style) {
        case ParticleStyle.ring:
          _stroke
            ..strokeWidth = 2.5 * t + 0.5
            ..color = pt.color.withOpacity(t * 0.9);
          canvas.drawCircle(Offset(pt.x, pt.y), pt.size * (1.4 - t), _stroke);
        case ParticleStyle.spark:
          _stroke
            ..strokeWidth = pt.size * 0.6
            ..color = pt.color.withOpacity(t);
          canvas.drawLine(Offset(pt.x, pt.y), Offset(pt.x - pt.vx * 0.04, pt.y - pt.vy * 0.04), _stroke);
        case ParticleStyle.shard:
          _fill
            ..shader = null
            ..color = pt.color.withOpacity(t);
          Shapes.draw(canvas, ColorShape.diamond, Offset(pt.x, pt.y), pt.size * (0.5 + t * 0.5), _fill, rotation: pt.rot);
        case ParticleStyle.dot:
          _fill
            ..shader = null
            ..color = pt.color.withOpacity(t);
          canvas.drawCircle(Offset(pt.x, pt.y), pt.size * (0.4 + 0.6 * t), _fill);
      }
    }
  }

  void _paintTexts(Canvas canvas) {
    for (final ft in engine.texts) {
      var tp = _textCache[ft];
      if (tp == null) {
        tp = TextPainter(
          text: TextSpan(
            text: ft.text,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: ft.big ? 17 : 13,
              fontWeight: FontWeight.w700,
              color: ft.color,
              letterSpacing: 0.6,
              shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 6)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        _textCache[ft] = tp;
      }
      final t = (ft.life / ft.maxLife).clamp(0.0, 1.0);
      final scale = ft.big ? (t > 0.85 ? 1 + (t - 0.85) * 2 : 1.0) : 1.0;
      canvas.save();
      canvas.translate(ft.x, ft.y);
      canvas.scale(scale);
      final layer = Paint()..color = Color.fromRGBO(0, 0, 0, math.min(1, t * 2.5));
      canvas.saveLayer(Rect.fromCenter(center: Offset.zero, width: tp.width + 20, height: tp.height + 20), layer);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
      canvas.restore();
    }
  }

  void _label(Canvas canvas, String text, Offset c, double size, Color color) {
    final key = '$text|$size|${color.value}';
    final tp = _labelCache.putIfAbsent(
      key,
      () => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontFamily: 'Inter', fontSize: size, fontWeight: FontWeight.w700, color: color, letterSpacing: 1.2),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  void _icon(Canvas canvas, IconData icon, Offset c, double size, Color color) {
    final key = 'icon:${icon.codePoint}|$size|${color.value}';
    final tp = _labelCache.putIfAbsent(
      key,
      () => TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(fontFamily: icon.fontFamily, package: icon.fontPackage, fontSize: size, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => oldDelegate.engine != engine;
}
