import 'dart:math' as math;

import '../../core/constants/game_constants.dart';
import '../../core/models/game_color.dart';
import '../../core/models/gravity_dir.dart';
import '../../game/entities/entity.dart';
import '../models/level_config.dart';

/// A fully laid-out level: entity templates sorted by track position.
class LevelPlan {
  LevelPlan(this.entities, this.length);
  final List<Entity> entities;
  final double length;

  Iterable<Entity> ofKind(EntityKind k) => entities.where((e) => e.kind == k);
}

/// Hint actions used by the tutorial director.
class HintAction {
  static const int none = 0;
  static const int drag = 1;
  static const int swipe = 2;
}

/// Mutable state threaded through segment construction.
class SegmentContext {
  SegmentContext(this.config) : expected = config.startingColor {
    adopt(config);
  }
  final LevelConfig config;

  // Tunables copied from a config; endless mode re-adopts them as it ramps up.
  late double d;
  late Set<Mechanic> mechanics;
  late List<GameColor> palette;
  late List<String> objectPatterns;
  late List<String> obstaclePatterns;
  late List<String> powerUpPatterns;

  void adopt(LevelConfig c) {
    d = c.difficulty;
    mechanics = c.mechanics;
    palette = c.palette;
    objectPatterns = c.objectPatterns;
    obstaclePatterns = c.obstaclePatterns;
    powerUpPatterns = c.powerUpPatterns;
    if (!palette.contains(expected)) expected = palette.first;
  }

  /// The color the player is guaranteed to have at the current cursor.
  GameColor expected;
  final Set<Mechanic> introduced = {};
  double cursor = 0;
  final List<Entity> out = [];

  bool has(Mechanic m) => mechanics.contains(m);
  bool get gravityRequirementsAllowed => config.gravityMode != GravityMode.rotating;
}

/// Builds reusable segments (Start, Gravity, Color, Collection, Merge,
/// GravityShift, ColorGate, Obstacle, RiskReward, PowerUp, Challenge, Reward,
/// Finish) and stitches them into a [LevelPlan].
class SegmentBuilder {
  SegmentBuilder(this.config) : ctx = SegmentContext(config);

  final LevelConfig config;
  final SegmentContext ctx;
  late math.Random rng;
  double _segStart = 0;

  static const double cx = Arena.width / 2;
  static const double minX = 40, maxX = 320;
  static const double fullW = Arena.wallRight - Arena.wallLeft;

  LevelPlan build() {
    final starts = <double>[];
    for (final s in config.segments) {
      rng = math.Random(s.seed);
      _segStart = ctx.cursor;
      starts.add(_segStart);
      _buildSegment(s);
      ctx.cursor += s.length;
    }
    if (config.tutorial) _tutorialHints(starts);
    if (config.kind == RunKind.level && !config.tutorial && config.tier.index >= DifficultyTier.hard.index) {
      _placeCheckpoint(starts);
    }
    ctx.out.sort((a, b) => a.trackY.compareTo(b.trackY));
    return LevelPlan(ctx.out, ctx.cursor);
  }

  /// Extend an endless plan (used by endless mode).
  List<Entity> buildMore(List<SegmentSpec> specs) {
    final start = ctx.out.length;
    for (final s in specs) {
      rng = math.Random(s.seed);
      _segStart = ctx.cursor;
      _buildSegment(s);
      ctx.cursor += s.length;
    }
    // Keep the shared plan list sorted in place (the engine spawns in order).
    final added = ctx.out.sublist(start)..sort((a, b) => a.trackY.compareTo(b.trackY));
    ctx.out.setRange(start, ctx.out.length, added);
    return added;
  }

  void _buildSegment(SegmentSpec s) {
    switch (s.type) {
      case SegmentType.start:
        _start(s.length);
      case SegmentType.collection:
        _collection(s.length);
      case SegmentType.merge:
        _merge(s.length);
      case SegmentType.gravityShift:
        _gravityShift(s.length);
      case SegmentType.colorGate:
        _colorGate(s.length);
      case SegmentType.color:
        _color(s.length);
      case SegmentType.obstacle:
        _obstacle(s.length);
      case SegmentType.gravity:
        _gravity(s.length);
      case SegmentType.riskReward:
        _riskReward(s.length);
      case SegmentType.powerUp:
        _powerUp(s.length);
      case SegmentType.challenge:
        _challenge(s.length);
      case SegmentType.reward:
        _reward(s.length);
      case SegmentType.finish:
        _finish(s.length);
    }
  }

  // ------------------------------------------------------------ primitives
  T _add<T extends Entity>(T e, double o) {
    e.trackY = _segStart + o;
    ctx.out.add(e);
    return e;
  }

  double _rx([double lo = minX, double hi = maxX]) => lo + rng.nextDouble() * (hi - lo);
  T _pick<T>(List<T> l) => l[rng.nextInt(l.length)];
  bool _chance(double p) => rng.nextDouble() < p;

  GameColor _otherColor(GameColor c) {
    final others = ctx.palette.where((p) => p != c).toList();
    return others.isEmpty ? c : _pick(others);
  }

  GameColor _orbColor() => _chance(0.68) ? ctx.expected : _pick(ctx.palette);

  void orb(double x, double o, GameColor c, {int level = 1, OrbBehavior behavior = OrbBehavior.normal}) {
    _add(Entity(kind: EntityKind.orb, x: x, r: Entity.orbRadius(level), color: c, level: level, behavior: behavior), o);
  }

  void wildOrb(double x, double o) {
    _add(Entity(kind: EntityKind.orb, x: x, r: Entity.orbRadius(1), wildcard: true, color: null), o);
  }

  void coin(double x, double o, {bool risk = false}) => _add(Entity(kind: EntityKind.coin, x: x, r: 8, risk: risk, value: 1), o);

  void block(double x, double o, double w, double h,
      {BlockMotion motion = BlockMotion.none, double amp = 0, double period = 2.4, double phase = 0, GameColor? danger}) {
    _add(
        Entity(
            kind: EntityKind.block,
            x: x,
            w: w,
            h: h,
            motion: motion,
            amp: amp,
            period: period,
            phase: phase,
            dangerColor: danger),
        o);
  }

  /// Spike strip spanning [x0, x1].
  void spikes(double x0, double x1, double o, {double h = 18, GameColor? danger}) {
    _add(Entity(kind: EntityKind.spikes, x: (x0 + x1) / 2, w: x1 - x0, h: h, dangerColor: danger), o);
  }

  void laser(double o,
      {double period = 2.6, double duty = 0.45, double phase = 0, double x0 = Arena.wallLeft, double x1 = Arena.wallRight}) {
    _add(Entity(kind: EntityKind.laser, x: (x0 + x1) / 2, w: x1 - x0, h: 8, period: period, duty: duty, phase: phase), o);
  }

  void gravityLaser(double x, double o) => _add(Entity(kind: EntityKind.laser, x: x, w: 16, h: 16, followsGravity: true), o);

  void rotor(double x, double o, double len, double speed) =>
      _add(Entity(kind: EntityKind.rotor, x: x, w: len, h: 12, angSpeed: speed, angle: rng.nextDouble() * math.pi), o);

  void meteor(double x, double o) => _add(Entity(kind: EntityKind.meteor, x: x, r: 13), o);

  void gate(double o,
      {List<GameColor>? colors,
      GateMode mode = GateMode.allow,
      GravityDir? dir,
      GravityDir? effect,
      double x = cx,
      double w = fullW}) {
    _add(
        Entity(
            kind: EntityKind.gate,
            x: x,
            w: w,
            h: 18,
            gateColors: colors,
            gateMode: mode,
            gateDir: dir,
            effectDir: effect,
            fullWidth: w >= fullW - 1),
        o);
  }

  void colorBand(double o, GameColor c) {
    _add(Entity(kind: EntityKind.colorSwitch, x: cx, w: fullW, h: 14, color: c, fullWidth: true), o);
    ctx.expected = c;
  }

  void colorRing(double x, double o, GameColor c) => _add(Entity(kind: EntityKind.colorSwitch, x: x, r: 15, color: c), o);

  void gravitySwitch(double x, double o, GravityDir d, {GameColor? trigger}) =>
      _add(Entity(kind: EntityKind.gravitySwitch, x: x, r: 17, dir: d, triggerColor: trigger), o);

  void gravityZone(double o, double len, GravityDir d) =>
      _add(Entity(kind: EntityKind.gravityZone, x: cx, w: fullW, h: len, dir: d), o + len / 2);

  void lockZone(double o, double len) => _add(Entity(kind: EntityKind.lockZone, x: cx, w: fullW, h: len), o + len / 2);

  void mergeZone(double x, double o, double w, double h) => _add(Entity(kind: EntityKind.mergeZone, x: x, w: w, h: h), o);

  void basin(double x, double o, double w, double h, GameColor c) =>
      _add(Entity(kind: EntityKind.basin, x: x, w: w, h: h, color: c), o);

  void powerUp(double x, double o, PowerUpType t) => _add(Entity(kind: EntityKind.powerUp, x: x, r: 16, powerUp: t), o);

  void special(double x, double o, SpecialKind k, {GameColor? color}) =>
      _add(Entity(kind: EntityKind.special, x: x, r: 15, special: k, color: color), o);

  void hint(double o, String text, {int action = HintAction.none, GravityDir? dir}) =>
      _add(Entity(kind: EntityKind.hint, x: cx, text: text, value: action, dir: dir), o);

  /// Show a "NEW" banner the first time a mechanic appears in early levels.
  void intro(Mechanic m, double o, String text) {
    if (ctx.introduced.contains(m)) return;
    ctx.introduced.add(m);
    final lvl = config.levelId;
    if (config.kind == RunKind.level && lvl >= m.unlockLevel && lvl <= m.unlockLevel + 1) {
      hint(o, text);
    }
  }

  /// Hard / Very Hard levels get one checkpoint at a clean segment boundary
  /// near the middle (no object straddles it, nothing lethal right after it).
  void _placeCheckpoint(List<double> starts) {
    final mid = ctx.cursor / 2;
    final candidates = [
      for (var i = 2; i < starts.length - 1; i++)
        if (config.segments[i].type != SegmentType.finish) starts[i],
    ]..sort((a, b) => (a - mid).abs().compareTo((b - mid).abs()));
    for (final b in candidates) {
      final clean = ctx.out.every((e) {
        if (e.kind == EntityKind.hint) return true;
        final ext = e.kind == EntityKind.rotor ? e.w / 2 : e.halfExtent;
        if (e.trackY < b) return e.trackY + ext < b - 10;
        return e.trackY - ext > b + 30;
      });
      if (clean) {
        ctx.out.add(Entity(kind: EntityKind.checkpoint, x: cx, w: fullW, h: 10)..trackY = b);
        return;
      }
    }
  }

  /// Coach marks for the interactive tutorial (levels 1-4).
  void _tutorialHints(List<double> starts) {
    void at(int seg, double o, String text, {int action = HintAction.none, GravityDir? dir}) {
      _segStart = starts[seg];
      hint(o, text, action: action, dir: dir);
    }

    switch (config.levelId) {
      case 1:
        at(0, 70, 'DRAG anywhere to steer', action: HintAction.drag);
        at(1, 0, 'Collect orbs for points');
        at(2, 0, 'Avoid the spikes!');
        at(4, 0, 'Reach the finish line');
      case 2:
        at(0, 70, 'SWIPE ← to shift gravity', action: HintAction.swipe, dir: GravityDir.left);
        at(0, 230, 'SWIPE → to shift it back', action: HintAction.swipe, dir: GravityDir.right);
        at(1, 0, 'Gravity snaps you to a wall · use it to dodge');
        at(2, 0, 'SWIPE ↑ · gravity works 4 ways', action: HintAction.swipe, dir: GravityDir.up);
        at(2, 200, 'SWIPE ↓ to fall back down', action: HintAction.swipe, dir: GravityDir.down);
      case 3:
        at(0, 70, 'Your color + shape is on your orb');
        at(1, 0, 'Collect orbs that MATCH your color');
        at(2, 0, 'Touch a color ring to change color');
        at(3, 0, 'Gates only let YOUR color through');
      default:
        at(0, 70, 'Same colors COMBINE when they touch');
        at(1, 0, 'Swipe sideways · pile orbs on a wall');
        at(3, 0, 'Bigger orbs are worth more');
    }
  }

  // --------------------------------------------------------------- segments
  void _start(double len) {
    for (var o = 140.0; o < len - 40; o += 34) {
      coin(cx, o);
    }
  }

  void _finish(double len) {
    for (var i = 0; i < 4; i++) {
      coin(cx - 60 + i * 40, 60);
    }
    _add(Entity(kind: EntityKind.finish, x: cx, w: fullW, h: 24), len * 0.62);
  }

  void _collection(double len) {
    final pats = ctx.objectPatterns.isEmpty ? ['line'] : ctx.objectPatterns;
    final pat = _pick(pats);
    final count = 5 + (ctx.d * 4).round();
    switch (pat) {
      case 'zigzag':
        for (var i = 0; i < count; i++) {
          orb(i.isEven ? 90 : 270, 40 + i * (len - 80) / count, _orbColor());
        }
      case 'sides':
        // Orbs hugging the walls: shift gravity sideways to sweep them up.
        final side = _chance(0.5);
        for (var i = 0; i < count; i++) {
          orb(side ? 44 : 316, 40 + i * 46.0, ctx.expected);
        }
        for (var i = 0; i < 3; i++) {
          coin(side ? 316 : 44, 60 + i * 40.0);
        }
      case 'arc':
        for (var i = 0; i < count; i++) {
          final t = i / (count - 1);
          orb(cx + math.sin(t * math.pi * 1.5) * 120, 40 + t * (len - 100), _orbColor());
        }
      case 'coins':
        final x = _rx(80, 280);
        for (var i = 0; i < 8; i++) {
          coin(x + math.sin(i * 0.8) * 50, 30 + i * 34.0);
        }
        for (var i = 0; i < count ~/ 2; i++) {
          orb(_rx(), 320 + i * 40.0, _orbColor());
        }
      default: // line
        final x = _rx(70, 290);
        for (var i = 0; i < count; i++) {
          orb(x, 40 + i * 42.0, _orbColor());
        }
        for (var i = 0; i < 3; i++) {
          coin(_rx(), 60 + i * 120.0);
        }
    }
    _sprinkleSpecials(len);
    if (ctx.has(Mechanic.spikes) && ctx.d > 0.08 && _chance(0.3 + ctx.d * 0.6)) {
      final left = _chance(0.5);
      spikes(left ? Arena.wallLeft : 230, left ? 130 : Arena.wallRight, len - 50);
    }
  }

  void _sprinkleSpecials(double len) {
    if (ctx.has(Mechanic.wildcard) && _chance(0.25)) {
      intro(Mechanic.wildcard, 10, 'NEW · Wildcard orb matches any color');
      wildOrb(_rx(), len * 0.5);
    }
    if (ctx.has(Mechanic.rainbow) && _chance(0.15)) {
      intro(Mechanic.rainbow, 10, 'NEW · Rainbow orb merges with every color');
      wildOrb(_rx(), len * 0.7);
    }
    if (ctx.has(Mechanic.anchor) && _chance(0.25)) {
      intro(Mechanic.anchor, 10, 'NEW · Anchor orbs ignore gravity');
      orb(_rx(), len * 0.35, ctx.expected, behavior: OrbBehavior.anchor);
    }
    if (ctx.has(Mechanic.reverse) && _chance(0.25)) {
      intro(Mechanic.reverse, 10, 'NEW · Reverse orbs fall the other way');
      orb(_rx(), len * 0.6, ctx.expected, behavior: OrbBehavior.reverse);
    }
  }

  void _merge(double len) {
    final c = ctx.expected;
    if (ctx.has(Mechanic.mergeZone) && _chance(0.55)) {
      intro(Mechanic.mergeZone, 0, 'NEW · Merge Zone holds orbs so they combine');
      const zh = 120.0;
      mergeZone(cx, 200, 230, zh);
      final n = 3 + (ctx.d * 3).round();
      for (var i = 0; i < n; i++) {
        orb(cx - 80 + (i % 4) * 54, 160 + (i ~/ 4) * 30 + i * 6, c, level: i == n - 1 && n > 4 ? 2 : 1);
      }
      coin(cx, 320);
      coin(cx, 350);
    } else {
      intro(Mechanic.merge, 0, 'Shift gravity sideways · same colors combine');
      // Two staggered columns of the same color that collide on a side wall.
      final n = 4 + (ctx.d * 3).round();
      for (var i = 0; i < n; i++) {
        orb(i.isEven ? 120 : 240, 40 + i * 26.0, c);
      }
      if (ctx.palette.length > 1 && _chance(0.6)) {
        final o2 = _otherColor(c);
        orb(cx, 40 + n * 26.0 + 30, o2);
        orb(cx + 50, 40 + n * 26.0 + 40, o2);
      }
    }
    _sprinkleSpecials(len);
  }

  void _gravityShift(double len) {
    final pats = <String>['gap', 'tunnel'];
    if (ctx.has(Mechanic.gravityWall) && ctx.gravityRequirementsAllowed) pats.add('wall');
    if (ctx.d > 0.1) pats.add('corners');
    final pat = config.tutorial && config.levelId == 2 ? 'gap' : _pick(pats);
    switch (pat) {
      case 'wall':
        intro(Mechanic.gravityWall, 0, 'NEW · Gravity Wall · match its arrow to pass');
        const dirs = GravityDir.values;
        final a = _pick(dirs);
        gate(120, dir: a);
        final b = _pick(dirs.where((d) => d != a).toList());
        if (len > 420) gate(120 + math.max(260, len - 300), dir: b);
      case 'tunnel':
        // A lane hugging one wall: snap sideways with gravity.
        final left = _chance(0.5);
        const laneW = 74.0;
        final bx0 = left ? Arena.wallLeft + laneW : Arena.wallLeft;
        final bx1 = left ? Arena.wallRight : Arena.wallRight - laneW;
        block((bx0 + bx1) / 2, 160, bx1 - bx0, 26);
        coin(left ? 44 : 316, 110);
        coin(left ? 44 : 316, 160);
        coin(left ? 44 : 316, 210);
        if (len > 460) {
          final bx0b = left ? Arena.wallLeft : Arena.wallLeft + laneW;
          final bx1b = left ? Arena.wallRight - laneW : Arena.wallRight;
          block((bx0b + bx1b) / 2, 160 + math.max(220, 300 - ctx.d * 80), bx1b - bx0b, 26);
        }
      case 'corners':
        block(cx, 120, 150, 26);
        coin(50, 120);
        coin(310, 120);
        if (len > 440) {
          block(70, 330, 130, 26);
          block(290, 330, 130, 26);
        }
      default: // gap
        final first = _chance(0.5);
        final reach = math.max(230.0, 330 - ctx.d * 110);
        for (var i = 0, o = 110.0; o < len - 60; i++, o += reach) {
          final leftSide = (i.isEven) == first;
          final x0 = leftSide ? Arena.wallLeft : Arena.wallRight - 196;
          final x1 = leftSide ? Arena.wallLeft + 196 : Arena.wallRight;
          block((x0 + x1) / 2, o, x1 - x0, 24);
          coin(leftSide ? 300 : 60, o - 40);
        }
    }
  }

  void _color(double len) {
    final pats = <String>['ring'];
    if (ctx.has(Mechanic.basin)) pats.add('basin');
    if (ctx.has(Mechanic.colorTrigger)) pats.add('trigger');
    final pat = _pick(pats);
    switch (pat) {
      case 'basin':
        intro(Mechanic.basin, 0, 'NEW · Basin · use gravity to drop matching orbs in');
        final c = _pick(ctx.palette);
        final left = _chance(0.5);
        basin(left ? 50 : 310, 300, 72, 170, c);
        for (var i = 0; i < 4; i++) {
          orb(cx + (left ? -1 : 1) * (20 + i * 22.0), 120 + i * 30.0, c);
        }
        orb(cx, 260, _otherColor(c));
      case 'trigger':
        intro(Mechanic.colorTrigger, 0, 'NEW · Color-triggered switch · only its color flips gravity');
        final c = ctx.expected;
        final d = _pick([GravityDir.left, GravityDir.right]);
        gravitySwitch(cx, 260, d, trigger: c);
        orb(cx, 150, c);
        coin(d == GravityDir.left ? 50 : 310, 340);
        coin(d == GravityDir.left ? 50 : 310, 380);
      default: // ring
        final c = _otherColor(ctx.expected);
        final x = _rx(80, 280);
        colorRing(x, 70, c);
        // Orbs of the new color reward taking the ring; validator treats the
        // ring as optional, so expected color does not change.
        for (var i = 0; i < 4; i++) {
          orb(x + (i - 1.5) * 30, 170 + i * 34.0, c);
        }
    }
  }

  void _colorGate(double len) {
    intro(Mechanic.colorGate, 0, 'Only your color passes a gate');
    final c = (_chance(0.6) && ctx.palette.length > 1) ? _otherColor(ctx.expected) : ctx.expected;
    // Always announce the required color with an unavoidable band: optional
    // rings taken earlier can never leave the player stuck at this gate.
    colorBand(40, c);
    for (var i = 0; i < 3; i++) {
      orb(_rx(), 100 + i * 50.0, _chance(0.75) ? c : _otherColor(c));
    }
    final o = math.min(len - 40, 280.0);
    final variants = <String>['plain'];
    if (ctx.has(Mechanic.multiColorGate) && ctx.palette.length > 2) variants.add('multi');
    if (ctx.has(Mechanic.colorGravityGate) && ctx.gravityRequirementsAllowed) variants.add('colorGravity');
    if (ctx.has(Mechanic.colorBarrier) && ctx.palette.length > 1) variants.add('barrier');
    if (ctx.d > 0.15) variants.add('lock');
    switch (_pick(variants)) {
      case 'multi':
        intro(Mechanic.multiColorGate, 60, 'NEW · Multi-Color Gate · any listed color passes');
        gate(o, colors: [c, _otherColor(c)]);
      case 'colorGravity':
        intro(Mechanic.colorGravityGate, 60, 'NEW · Color + Gravity Gate · need both');
        gate(o, colors: [c], dir: _pick(GravityDir.values));
      case 'barrier':
        intro(Mechanic.colorBarrier, 60, 'NEW · Barrier blocks the color it shows');
        final blocked = _otherColor(c);
        colorRing(cx, o - 120, blocked);
        gate(o, colors: [blocked], mode: GateMode.block);
      case 'lock':
        // Color lock set in a wall: pass through the colored gap.
        final gx = _rx(110, 250);
        const gw = 110.0;
        block((Arena.wallLeft + gx - gw / 2) / 2, o, gx - gw / 2 - Arena.wallLeft, 22);
        block((gx + gw / 2 + Arena.wallRight) / 2, o, Arena.wallRight - gx - gw / 2, 22);
        gate(o, colors: [c], x: gx, w: gw);
      default:
        gate(o, colors: [c]);
    }
  }

  void _obstacle(double len) {
    final pats = ctx.obstaclePatterns.isEmpty ? ['spikeRow'] : ctx.obstaclePatterns;
    // Easy: one obstacle; Medium: one or two; Hard: two; Very Hard: three.
    final n = ctx.d >= 0.8 && len >= 640
        ? 3
        : ctx.d >= 0.5 || len > 520
            ? 2
            : 1;
    for (var i = 0; i < n; i++) {
      final o = 90 + i * (len - 120) / n;
      _obstaclePattern(_pick(pats), o);
    }
  }

  void _obstaclePattern(String pat, double o) {
    final d = ctx.d;
    switch (pat) {
      case 'sway':
        intro(Mechanic.movingBlock, o - 60, 'Moving blocks · time your path');
        block(cx, o, 120, 22, motion: BlockMotion.sway, amp: 90 + d * 30, period: 3.2 - d * 1.2, phase: rng.nextDouble() * 3);
      case 'rotor':
        intro(Mechanic.rotor, o - 60, 'Rotors spin · slip past the gap');
        rotor(_pick([110.0, 250.0]), o, 130 + d * 40, (_chance(0.5) ? 1 : -1) * (1.3 + d * 1.4));
      case 'laser':
        intro(Mechanic.laser, o - 80, 'Lasers pulse · pass while they are off');
        laser(o, period: 2.8 - d * 0.8, duty: 0.4 + d * 0.12, phase: rng.nextDouble() * 2);
      case 'crusher':
        intro(Mechanic.crusher, o - 80, 'NEW · Gravity Crusher slides with gravity');
        block(_pick([100.0, 260.0]), o, 110, 30, motion: BlockMotion.crusher);
      case 'gravitySpikes':
        intro(Mechanic.gravitySpikes, o - 80, 'NEW · Gravity Spikes · don\'t fall into them');
        final left = _chance(0.5);
        _add(Entity(kind: EntityKind.spikes, x: left ? Arena.field.left + 8 : Arena.field.right - 8, w: 16, h: 220), o + 60);
        coin(cx, o);
        coin(cx, o + 50);
      case 'meteors':
        intro(Mechanic.meteors, o - 80, 'Meteors fall with gravity');
        meteor(_rx(), o);
        if (d > 0.3) meteor(_rx(), o + 70);
      case 'colorSpikes':
        intro(Mechanic.colorSpikes, o - 80, 'NEW · Colored spikes only hurt that color');
        final hurt = ctx.expected;
        final safe = _otherColor(hurt);
        spikes(Arena.wallLeft, Arena.wallRight, o, danger: hurt);
        if (safe != hurt) colorBand(o - 110, safe);
        if (safe == hurt) {
          // single color palette fallback: plain spike row with a gap
          ctx.out.removeLast();
          spikes(Arena.wallLeft, 180, o);
        }
      case 'colorCrusher':
        intro(Mechanic.colorCrusher, o - 80, 'NEW · Color Crusher only hits its color');
        block(cx, o, 200, 30, motion: BlockMotion.crusher, danger: _otherColor(ctx.expected));
      case 'gravityLaser':
        intro(Mechanic.gravityLaser, o - 80, 'NEW · Gravity Laser fires along gravity');
        gravityLaser(_pick([90.0, 270.0]), o);
      default: // spikeRow
        final gapX = _rx(90, 270);
        final gap = 120 - d * 30;
        if (gapX - gap / 2 > Arena.wallLeft + 10) spikes(Arena.wallLeft, gapX - gap / 2, o);
        if (gapX + gap / 2 < Arena.wallRight - 10) spikes(gapX + gap / 2, Arena.wallRight, o);
        coin(gapX, o - 30);
        coin(gapX, o + 30);
    }
  }

  void _gravity(double len) {
    final pats = <String>[];
    if (ctx.has(Mechanic.gravitySwitch)) pats.add('switch');
    if (ctx.has(Mechanic.gravityGate)) pats.add('gate');
    if (ctx.has(Mechanic.gravityZone)) pats.add('zone');
    if (ctx.has(Mechanic.gravityLock)) pats.add('lock');
    if (pats.isEmpty) pats.add('switch');
    switch (_pick(pats)) {
      case 'gate':
        intro(Mechanic.gravityGate, 0, 'NEW · Gravity Gate · passing it shifts gravity');
        final d = _pick([GravityDir.left, GravityDir.right]);
        gate(80, effect: d);
        final x0 = d == GravityDir.left ? Arena.wallLeft + 100 : Arena.wallLeft;
        final x1 = d == GravityDir.left ? Arena.wallRight : Arena.wallRight - 100;
        block((x0 + x1) / 2, 260, x1 - x0, 24);
        coin(d == GravityDir.left ? 50 : 310, 200);
      case 'zone':
        intro(Mechanic.gravityZone, 0, 'NEW · Gravity Zone · it holds gravity while inside');
        final d = _pick([GravityDir.left, GravityDir.right]);
        final zl = math.min(len - 80, 340.0);
        gravityZone(60, zl, d);
        final x0 = d == GravityDir.left ? Arena.wallLeft + 110 : Arena.wallLeft;
        final x1 = d == GravityDir.left ? Arena.wallRight : Arena.wallRight - 110;
        block((x0 + x1) / 2, 60 + zl * 0.55, x1 - x0, 24);
        for (var i = 0; i < 4; i++) {
          coin(d == GravityDir.left ? 48 : 312, 110 + i * 45.0);
        }
      case 'lock':
        intro(Mechanic.gravityLock, 0, 'NEW · Gravity Lock · no shifting inside');
        final zl = math.min(len - 60, 300.0);
        lockZone(40, zl);
        final gx = _rx(100, 260);
        if (gx - 60 > Arena.wallLeft + 20) block((Arena.wallLeft + gx - 60) / 2, 40 + zl * 0.5, gx - 60 - Arena.wallLeft, 22);
        if (gx + 60 < Arena.wallRight - 20) block((gx + 60 + Arena.wallRight) / 2, 40 + zl * 0.5, Arena.wallRight - gx - 60, 22);
        coin(gx, 40 + zl * 0.5 - 40);
      default: // switch
        intro(Mechanic.gravitySwitch, 0, 'NEW · Gravity Switch · touch it to shift');
        final d = _pick([GravityDir.left, GravityDir.right, GravityDir.up, GravityDir.down]);
        gravitySwitch(cx, 90, d);
        if (d.isHorizontal) {
          for (var i = 0; i < 4; i++) {
            orb(d == GravityDir.left ? 48 : 312, 200 + i * 36.0, ctx.expected);
          }
        } else {
          for (var i = 0; i < 4; i++) {
            coin(cx - 60 + i * 40, 240);
          }
        }
    }
  }

  void _riskReward(double len) {
    intro(Mechanic.riskReward, 0, 'Choose a route · RISK pays more');
    final riskRight = _chance(0.5);
    const div = 14.0;
    const gw = (fullW - div) / 2;
    // Gravity choice gates: each half shifts gravity toward its side.
    gate(110, effect: GravityDir.left, x: Arena.wallLeft + gw / 2, w: gw);
    gate(110, effect: GravityDir.right, x: Arena.wallRight - gw / 2, w: gw);
    final corridorLen = len - 230;
    block(cx, 170 + corridorLen / 2, div, corridorLen);
    final riskX0 = riskRight ? cx + div / 2 : Arena.wallLeft;
    final riskX1 = riskRight ? Arena.wallRight : cx - div / 2;
    final safeMid = riskRight ? (Arena.wallLeft + cx) / 2 : (cx + Arena.wallRight) / 2;
    final riskMid = (riskX0 + riskX1) / 2;
    hint(60, riskRight ? '←  SAFE      RISK  →' : '←  RISK      SAFE  →');
    // safe: a few coins
    for (var i = 0; i < 3; i++) {
      coin(safeMid, 230 + i * 90.0);
    }
    // risk: hazards + lots of coins + a power-up
    for (var o = 210.0; o < 170 + corridorLen - 30; o += 36) {
      coin(riskMid + math.sin(o / 40) * 30, o, risk: true);
    }
    final hazardO = 170 + corridorLen * 0.45;
    if (_chance(0.5)) {
      block(riskMid, hazardO, 70, 20, motion: BlockMotion.sway, amp: 36, period: 2.2);
    } else {
      final edge = riskRight ? Arena.wallRight : Arena.wallLeft;
      spikes(math.min(edge, riskMid), math.max(edge, riskMid), hazardO);
    }
    if (ctx.has(Mechanic.powerUps)) {
      powerUp(riskMid, 170 + corridorLen * 0.8, _pick([PowerUpType.doubleCoins, PowerUpType.shield, PowerUpType.magnet]));
    }
  }

  PowerUpType _powerUpType() {
    final pool = ctx.powerUpPatterns.isEmpty ? ['shield'] : ctx.powerUpPatterns;
    final name = _pick(pool);
    return PowerUpType.values.firstWhere((p) => p.name == name, orElse: () => PowerUpType.shield);
  }

  void _powerUp(double len) {
    intro(Mechanic.powerUps, 0, 'Power-ups · grab them for an edge');
    final t = _powerUpType();
    powerUp(_rx(90, 270), 60, t);
    switch (t) {
      case PowerUpType.magnet:
      case PowerUpType.doubleCoins:
        for (var i = 0; i < 8; i++) {
          coin(_rx(), 140 + i * 26.0);
        }
      case PowerUpType.megaMerge:
        for (var i = 0; i < 5; i++) {
          orb(80 + i * 50.0, 170 + (i % 2) * 20, ctx.expected);
        }
      case PowerUpType.colorShift:
        gate(len - 60, colors: [_otherColor(ctx.expected)]);
        // a band right before guarantees passability without the power-up
        colorBand(len - 150, ctx.out.last.gateColors!.first);
      default:
        spikes(Arena.wallLeft, 150, 220);
        spikes(210, Arena.wallRight, 220);
    }
    if (_chance(0.4 + ctx.d * 0.3)) {
      final specials = <SpecialKind>[];
      if (ctx.has(Mechanic.bomb)) specials.add(SpecialKind.bomb);
      if (ctx.has(Mechanic.gravityCore)) specials.add(SpecialKind.gravityCore);
      if (ctx.has(Mechanic.colorCore)) specials.add(SpecialKind.colorCore);
      if (ctx.has(Mechanic.gravityBomb)) specials.add(SpecialKind.gravityBomb);
      if (specials.isNotEmpty) {
        final k = _pick(specials);
        switch (k) {
          case SpecialKind.bomb:
            intro(Mechanic.bomb, 100, 'NEW · Bomb clears nearby hazards');
          case SpecialKind.gravityCore:
            intro(Mechanic.gravityCore, 100, 'NEW · Gravity Core reverses gravity');
          case SpecialKind.colorCore:
            intro(Mechanic.colorCore, 100, 'NEW · Color Core changes your color');
          case SpecialKind.gravityBomb:
            intro(Mechanic.gravityBomb, 100, 'NEW · Gravity Bomb flips gravity briefly');
        }
        // Color cores are optional pickups; they never change the guaranteed color.
        special(_rx(), len - 30, k, color: k == SpecialKind.colorCore ? _otherColor(ctx.expected) : null);
      }
    }
  }

  void _challenge(double len) {
    // Dense mix of unlocked mechanics.
    final c = ctx.palette.length > 1 ? _otherColor(ctx.expected) : ctx.expected;
    colorBand(40, c);
    final dir = ctx.gravityRequirementsAllowed && ctx.has(Mechanic.colorGravityGate) ? _pick(GravityDir.values) : null;
    gate(190, colors: [c], dir: dir);
    final pats = ctx.obstaclePatterns.where((p) => p != 'colorSpikes').toList();
    _obstaclePattern(pats.isEmpty ? 'spikeRow' : _pick(pats), 330);
    for (var i = 0; i < 4; i++) {
      orb(_rx(), 240 + i * 22.0, c);
    }
    if (len > 560) _obstaclePattern(pats.isEmpty ? 'spikeRow' : _pick(pats), len - 90);
  }

  void _reward(double len) {
    for (var row = 0; row < 6; row++) {
      final n = row < 3 ? row + 2 : 7 - row;
      for (var i = 0; i < n; i++) {
        coin(cx + (i - (n - 1) / 2) * 34, 60 + row * 32.0);
      }
    }
    orb(cx, len - 80, ctx.expected, level: 2);
  }
}
