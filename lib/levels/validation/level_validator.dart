import 'dart:math' as math;

import '../../core/constants/game_constants.dart';
import '../../core/models/game_color.dart';
import '../../game/entities/entity.dart';
import '../models/level_config.dart';
import '../segments/segment_builder.dart';

class ValidationReport {
  ValidationReport(this.issues);
  final List<String> issues;
  bool get ok => issues.isEmpty;
  @override
  String toString() => ok ? 'OK' : issues.join('; ');
}

/// Static checks that every generated level is completable: start/finish
/// exist, color requirements are reachable, gravity requirements are
/// satisfiable, every hazard row leaves a gap, and objectives are achievable.
class LevelValidator {
  static final double _minPlayerX = Arena.field.left + Arena.playerRadius;
  static final double _maxPlayerX = Arena.field.right - Arena.playerRadius;
  static const double _lateralSpeed = 520; // conservative units/s

  static ValidationReport validate(LevelConfig c, LevelPlan plan) {
    final issues = <String>[];
    final ents = plan.entities;

    // 1. Structure
    if (c.segments.isEmpty || c.segments.first.type != SegmentType.start) issues.add('no start segment');
    if (c.kind != RunKind.endless) {
      if (c.segments.last.type != SegmentType.finish) issues.add('no finish segment');
      if (!ents.any((e) => e.kind == EntityKind.finish)) issues.add('no finish line');
    }

    // 2. Color reachability
    var possible = <GameColor>{c.startingColor};
    final lethalStartZone = ents.where((e) => _isStaticBlocker(e) && e.trackY < 280);
    if (lethalStartZone.isNotEmpty) issues.add('hazard in start zone');

    for (final e in ents) {
      switch (e.kind) {
        case EntityKind.colorSwitch:
          if (e.fullWidth) {
            possible = {e.color!};
          } else {
            possible = {...possible, e.color!};
          }
        case EntityKind.special when e.special == SpecialKind.colorCore && e.color != null:
          possible = {...possible, e.color!};
        case EntityKind.gate when e.gateColors != null:
          final colors = e.gateColors!.toSet();
          final next = e.gateMode == GateMode.allow ? possible.intersection(colors) : possible.difference(colors);
          if (next.isEmpty) issues.add('gate @${e.trackY.round()} needs unreachable color');
          possible = next.isEmpty ? possible : next;
        case EntityKind.spikes when e.dangerColor != null && e.w >= Arena.wallRight - Arena.wallLeft - 1:
          final next = possible.difference({e.dangerColor!});
          if (next.isEmpty) issues.add('color spikes @${e.trackY.round()} unavoidable');
        default:
          break;
      }
    }

    // 3. Gravity requirements
    final gravityGates = ents.where((e) => e.kind == EntityKind.gate && e.gateDir != null).toList();
    if (gravityGates.isNotEmpty && (!c.swipeEnabled || c.gravityMode == GravityMode.rotating)) {
      issues.add('gravity gate without player gravity control');
    }
    for (final g in gravityGates) {
      for (final z in ents.where((e) => e.kind == EntityKind.lockZone || e.kind == EntityKind.gravityZone)) {
        final inside = (g.trackY - z.trackY).abs() <= z.h / 2 + 30;
        if (inside && (z.kind == EntityKind.lockZone || z.dir != g.gateDir)) {
          issues.add('gravity gate inside conflicting zone');
        }
      }
    }

    // 4. Every blocker row leaves a gap the orb fits through, and the
    //    lateral move between consecutive rows is reachable in time.
    final blockers = ents.where(_isStaticBlocker).toList()..sort((a, b) => (a.trackY - a.h / 2).compareTo(b.trackY - b.h / 2));
    List<(double, double)>? prevFree;
    double prevY = -1e9;
    for (final b in blockers) {
      final y0 = b.trackY - b.h / 2;
      final y1 = b.trackY + b.h / 2;
      final row = blockers.where((o) => o.trackY + o.h / 2 >= y0 && o.trackY - o.h / 2 <= y1);
      final free = _freeIntervals(row);
      if (free.isEmpty) {
        issues.add('blocked row @${b.trackY.round()}');
        continue;
      }
      if (prevFree != null && y0 > prevY) {
        final need = _lateralDistance(prevFree, free);
        final timeAvail = (y0 - prevY) / c.speed;
        if (need / _lateralSpeed + 0.2 > timeAvail) issues.add('rows too close @${b.trackY.round()}');
      }
      prevFree = free;
      prevY = math.max(prevY, y1);
    }

    // 5. Mandatory barriers need reaction distance between them.
    final barriers = ents.where((e) => (e.kind == EntityKind.gate && e.fullWidth)).toList();
    for (var i = 1; i < barriers.length; i++) {
      if (barriers[i].trackY - barriers[i - 1].trackY < c.speed * 0.55) {
        issues.add('barriers too close @${barriers[i].trackY.round()}');
      }
    }

    // 6. Objectives achievable
    final coins = ents.where((e) => e.kind == EntityKind.coin).length;
    final orbs = ents.where((e) => e.kind == EntityKind.orb).length;
    for (final o in [...c.objectives, ...c.starObjectives]) {
      final ok = switch (o.type) {
        ObjectiveType.collectCoins => o.target <= coins,
        ObjectiveType.colorMatches || ObjectiveType.collectOrbs => o.target <= orbs,
        ObjectiveType.merges => orbs >= o.target * 2,
        ObjectiveType.useGravity ||
        ObjectiveType.gravityShifts ||
        ObjectiveType.perfectShifts =>
          c.swipeEnabled || c.gravityMode != GravityMode.manual,
        _ => true,
      };
      if (!ok) issues.add('objective not achievable: ${o.describe()}');
    }

    return ValidationReport(issues);
  }

  /// Lethal, non-moving, color-independent geometry.
  static bool _isStaticBlocker(Entity e) {
    if (e.kind == EntityKind.block) return e.motion == BlockMotion.none && e.dangerColor == null;
    if (e.kind == EntityKind.spikes) return e.dangerColor == null && e.w > 20;
    return false;
  }

  static List<(double, double)> _freeIntervals(Iterable<Entity> row) {
    const margin = Arena.playerRadius + 3;
    final blocked = row.map((e) => (e.x - e.w / 2 - margin, e.x + e.w / 2 + margin)).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final free = <(double, double)>[];
    var cursor = _minPlayerX;
    for (final (a, b) in blocked) {
      if (a > cursor + 4) free.add((cursor, math.min(a, _maxPlayerX)));
      cursor = math.max(cursor, b);
      if (cursor >= _maxPlayerX) break;
    }
    if (cursor < _maxPlayerX - 4) free.add((cursor, _maxPlayerX));
    return free.where((f) => f.$2 - f.$1 >= 4).toList();
  }

  static double _lateralDistance(List<(double, double)> a, List<(double, double)> b) {
    var best = double.infinity;
    for (final (a0, a1) in a) {
      for (final (b0, b1) in b) {
        if (a1 >= b0 && b1 >= a0) return 0;
        best = math.min(best, math.min((a0 - b1).abs(), (b0 - a1).abs()));
      }
    }
    return best;
  }
}
