import 'dart:math' as math;
import 'dart:ui';

import '../../core/models/game_color.dart';
import '../../core/models/gravity_dir.dart';

enum EntityKind {
  orb, // loose colored object: collect / merge / deliver
  coin,
  block, // solid hazard (static, moving, crusher)
  spikes, // spike strip (neutral or color-specific)
  laser, // timed beam (or gravity laser that follows gravity)
  rotor, // rotating bar
  meteor, // loose neutral hazard that falls with gravity
  gate, // color / gravity / color+gravity requirement barrier
  colorSwitch,
  gravitySwitch,
  gravityZone, // forces gravity while inside (gravity tunnel)
  lockZone, // gravity lock: no gravity changes while inside
  mergeZone, // gravity merge cup: holds loose orbs, merge bonus
  basin, // color target: deliver matching loose orbs
  powerUp,
  special, // bomb, gravity bomb, gravity core, color core
  finish,
  hint, // tutorial / mechanic intro text marker (invisible)
}

enum BlockMotion { none, sway, crusher }

enum OrbBehavior { normal, anchor, reverse }

enum GateMode { allow, block }

enum SpecialKind { bomb, gravityBomb, gravityCore, colorCore }

enum PowerUpType {
  gravityControl('Gravity Control', 'Swipe freely, even through locks'),
  colorShift('Color Shift', 'Become the next gate\'s color'),
  magnet('Magnet', 'Pulls in matching orbs and coins'),
  shield('Shield', 'Blocks one hit'),
  slowMotion('Slow Motion', 'Time slows down'),
  megaMerge('Mega Merge', 'Orbs merge from further away'),
  colorFreeze('Color Freeze', 'Color rules paused'),
  gravityFreeze('Gravity Freeze', 'Gravity locked as is'),
  doubleCoins('Double Coins', 'Coins count twice'),
  perfectGravity('Perfect Gravity', 'Every shift is perfect');

  const PowerUpType(this.title, this.description);
  final String title;
  final String description;

  double get duration => switch (this) {
        PowerUpType.shield => 0,
        PowerUpType.colorShift => 0,
        PowerUpType.slowMotion => 5,
        PowerUpType.colorFreeze => 5,
        PowerUpType.doubleCoins => 10,
        _ => 8,
      };
}

/// A gameplay object. The same class is used as an immutable-ish template in
/// a level plan (positioned by [trackY]) and as a live instance once spawned
/// (positioned by [x]/[y] in arena space). Kind-specific fields are nullable.
class Entity {
  Entity({
    required this.kind,
    this.trackY = 0,
    this.x = 0,
    this.y = 0,
    this.w = 0,
    this.h = 0,
    this.r = 0,
    this.color,
    this.level = 1,
    this.behavior = OrbBehavior.normal,
    this.wildcard = false,
    this.dir,
    this.gateColors,
    this.gateMode = GateMode.allow,
    this.gateDir,
    this.effectDir,
    this.dangerColor,
    this.motion = BlockMotion.none,
    this.amp = 0,
    this.period = 2,
    this.phase = 0,
    this.angle = 0,
    this.angSpeed = 0,
    this.duty = 0.5,
    this.followsGravity = false,
    this.powerUp,
    this.special,
    this.triggerColor,
    this.fullWidth = false,
    this.risk = false,
    this.text,
    this.value = 0,
  });

  final EntityKind kind;

  /// Distance along the track (template only).
  double trackY;

  // Live state ------------------------------------------------------------
  double x, y; // center in arena space
  double w, h; // full size for rect-like entities
  double r; // radius for round entities
  double vx = 0, vy = 0;
  double baseX = 0; // anchor for swaying blocks
  double age = 0;
  double flash = 0; // visual flash timer
  bool alive = true;
  bool passed = false; // player has passed it (dodge/gate scoring)
  bool triggered = false;
  bool nearMiss = false;

  // Kind data -------------------------------------------------------------
  GameColor? color;
  int level;
  OrbBehavior behavior;
  bool wildcard; // matches/merges with any color
  GravityDir? dir;
  List<GameColor>? gateColors;
  GateMode gateMode;
  GravityDir? gateDir;
  GravityDir? effectDir;
  GameColor? dangerColor;
  BlockMotion motion;
  double amp, period, phase, angle, angSpeed, duty;
  bool followsGravity;
  PowerUpType? powerUp;
  SpecialKind? special;
  GameColor? triggerColor;
  bool fullWidth;
  bool risk;
  String? text;
  int value;

  Entity spawnCopy(double atY) {
    final e = Entity(
      kind: kind,
      trackY: trackY,
      x: x,
      y: atY,
      w: w,
      h: h,
      r: r,
      color: color,
      level: level,
      behavior: behavior,
      wildcard: wildcard,
      dir: dir,
      gateColors: gateColors == null ? null : List.of(gateColors!),
      gateMode: gateMode,
      gateDir: gateDir,
      effectDir: effectDir,
      dangerColor: dangerColor,
      motion: motion,
      amp: amp,
      period: period,
      phase: phase,
      angle: angle,
      angSpeed: angSpeed,
      duty: duty,
      followsGravity: followsGravity,
      powerUp: powerUp,
      special: special,
      triggerColor: triggerColor,
      fullWidth: fullWidth,
      risk: risk,
      text: text,
      value: value,
    );
    e.baseX = x;
    return e;
  }

  // Geometry helpers --------------------------------------------------------
  bool get isRound =>
      kind == EntityKind.orb ||
      kind == EntityKind.coin ||
      kind == EntityKind.meteor ||
      kind == EntityKind.colorSwitch && !fullWidth ||
      kind == EntityKind.gravitySwitch ||
      kind == EntityKind.powerUp ||
      kind == EntityKind.special;

  bool get isLoose => kind == EntityKind.orb || kind == EntityKind.meteor;

  Rect get rect => Rect.fromCenter(center: Offset(x, y), width: w, height: h);

  /// Vertical extent (used for spawn / despawn).
  double get halfExtent {
    if (kind == EntityKind.rotor) return angSpeed == 0 ? w / 2 : w / 2 + 6;
    if (isRound) return r;
    return h / 2;
  }

  /// Orbs grow with merge level.
  static double orbRadius(int level) => 10 + 3.2 * (level - 1).clamp(0, 5);

  /// Laser is active (lethal) at this moment?
  bool get laserOn {
    if (kind != EntityKind.laser) return false;
    if (followsGravity) return true;
    final t = ((age + phase) / period) % 1.0;
    return t < duty;
  }

  /// Laser is about to switch on (warning flicker).
  bool get laserWarming {
    if (kind != EntityKind.laser || followsGravity) return false;
    final t = ((age + phase) / period) % 1.0;
    return t > 0.82 && !laserOn;
  }

  /// Rotor bar endpoints.
  (Offset, Offset) get rotorEnds {
    final half = w / 2;
    final c = math.cos(angle) * half, s = math.sin(angle) * half;
    return (Offset(x - c, y - s), Offset(x + c, y + s));
  }

  bool get isHazard =>
      kind == EntityKind.block ||
      kind == EntityKind.spikes ||
      kind == EntityKind.laser ||
      kind == EntityKind.rotor ||
      kind == EntityKind.meteor;
}
