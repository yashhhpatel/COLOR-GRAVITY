import 'dart:math' as math;
import 'dart:ui';

import '../../core/constants/game_constants.dart';
import '../../core/models/gravity_dir.dart';
import '../../game/entities/entity.dart';
import '../../levels/models/level_config.dart';

enum GravitySource { player, scripted, switchPad, zone, gate, core, bomb }

class GravityChange {
  const GravityChange(this.from, this.to, this.source);
  final GravityDir from;
  final GravityDir to;
  final GravitySource source;
}

/// Single source of truth for gravity: direction, smooth/instant transitions,
/// scripted (reversing / rotating) gravity, zones, locks and freezes. Player,
/// loose objects, crushers, lasers and particles all read from here.
class GravitySystem {
  GravitySystem({
    GravityDir initial = GravityDir.down,
    this.smooth = true,
    this.mode = GravityMode.manual,
    this.interval = 6,
  })  : dir = initial,
        _from = initial.vector,
        _vector = initial.vector,
        _scriptTimer = interval;

  GravityDir dir;
  bool smooth;
  GravityMode mode;
  double interval;

  Offset _from;
  Offset _vector;
  double _blend = 1; // 0 → 1 during a smooth transition
  double _scriptTimer;

  /// Upcoming scripted direction while the warning is showing.
  GravityDir? warning;

  /// Inside a gravity-lock zone: the player cannot shift.
  bool zoneLocked = false;

  /// Gravity Freeze power-up: external changes are ignored.
  bool frozen = false;

  /// Gravity zone currently overriding gravity (and what to restore).
  Entity? activeZone;
  GravityDir? _restoreDir;

  /// Gravity bomb: temporary reversal.
  double _tempTimer = 0;
  GravityDir? _tempRestore;

  /// Visual pulse 1 → 0 after each change (indicator, camera, particles).
  double pulse = 0;
  double sinceChange = 99;

  /// Smoothed unit-ish gravity vector.
  Offset get vector => _vector;

  bool get transitioning => _blend < 1;

  bool canPlayerShift({bool override = false}) {
    if (override) return true;
    if (mode == GravityMode.rotating) return false;
    if (zoneLocked || activeZone != null) return false;
    return true;
  }

  /// Requests a change. Returns the change if gravity actually changed.
  GravityChange? request(GravityDir to, GravitySource source, {bool override = false}) {
    if (source == GravitySource.player) {
      if (!canPlayerShift(override: override)) return null;
    } else if (frozen && source != GravitySource.zone) {
      return null;
    }
    if (to == dir) return null;
    final from = dir;
    _from = _vector;
    dir = to;
    _blend = smooth ? 0 : 1;
    if (!smooth) _vector = to.vector;
    pulse = 1;
    sinceChange = 0;
    if (mode != GravityMode.manual) _scriptTimer = interval;
    return GravityChange(from, to, source);
  }

  GravityChange? enterZone(Entity zone) {
    if (frozen || activeZone == zone) return null;
    activeZone = zone;
    _restoreDir = dir;
    return request(zone.dir!, GravitySource.zone);
  }

  GravityChange? exitZone() {
    if (activeZone == null) return null;
    activeZone = null;
    final r = _restoreDir;
    _restoreDir = null;
    return r == null ? null : request(r, GravitySource.zone);
  }

  GravityChange? temporaryReverse(double seconds) {
    _tempRestore ??= dir;
    _tempTimer = seconds;
    return request(dir.opposite, GravitySource.bomb);
  }

  /// Advances transitions and scripted gravity. Returns a scripted change.
  GravityChange? update(double dt) {
    sinceChange += dt;
    pulse = math.max(0, pulse - dt * 2.2);
    if (_blend < 1) {
      _blend = math.min(1, _blend + dt / Physics.smoothTransition);
      final t = GravityEase.outCubic(_blend);
      _vector = Offset.lerp(_from, dir.vector, t)!;
    } else {
      _vector = dir.vector;
    }

    if (_tempTimer > 0) {
      _tempTimer -= dt;
      if (_tempTimer <= 0 && _tempRestore != null) {
        final r = _tempRestore!;
        _tempRestore = null;
        return request(r, GravitySource.bomb);
      }
    }

    if (mode == GravityMode.manual || frozen || activeZone != null) {
      warning = null;
      return null;
    }
    _scriptTimer -= dt;
    final next = mode == GravityMode.rotating ? dir.clockwise : dir.opposite;
    warning = _scriptTimer <= GameTiming.scriptedWarning ? next : null;
    if (_scriptTimer <= 0) {
      _scriptTimer = interval;
      warning = null;
      return request(next, GravitySource.scripted);
    }
    return null;
  }

  /// Seconds until the next scripted change (for the HUD).
  double get timeToScripted => mode == GravityMode.manual ? double.infinity : _scriptTimer;
}

/// Minimal cubic ease to avoid a Flutter dependency in pure logic.
class GravityEase {
  static double outCubic(double t) {
    final p = 1 - t;
    return 1 - p * p * p;
  }
}
