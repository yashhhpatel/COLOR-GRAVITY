import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/systems/scoring.dart';
import '../levels/models/level_config.dart';

/// What a daily mission measures. "Max" metrics track the best single run;
/// the others add up across all of today's runs.
enum MissionMetric {
  merges(Icons.merge_type_rounded),
  shifts(Icons.swap_vert_rounded),
  shiftsUp(Icons.north_rounded),
  matches(Icons.palette_rounded),
  gates(Icons.door_sliding_rounded),
  perfect(Icons.auto_awesome_rounded),
  coins(Icons.monetization_on_rounded),
  levels(Icons.flag_rounded),
  combo(Icons.bolt_rounded, isMax: true),
  endlessDistance(Icons.all_inclusive_rounded, isMax: true),
  daily(Icons.today_rounded);

  const MissionMetric(this.icon, {this.isMax = false});
  final IconData icon;
  final bool isMax;
}

class _Template {
  const _Template(this.metric, this.title, this.targets, this.reward);
  final MissionMetric metric;
  final String title; // `{n}` is replaced by the target
  final List<int> targets;
  final int reward;
}

class DailyMission {
  const DailyMission({required this.metric, required this.target, required this.reward, required this.title});
  final MissionMetric metric;
  final int target;
  final int reward;
  final String title;

  /// Stable id for today's save data.
  String get id => '${metric.name}_$target';
}

/// Three fresh, deterministic missions per day, built from what a run
/// already measures (no new mechanics needed).
class DailyMissions {
  static const int perDay = 3;
  static const int allDoneBonus = 50;

  static const List<_Template> _pool = [
    _Template(MissionMetric.merges, 'Combine orbs {n} times', [5, 8, 12], 40),
    _Template(MissionMetric.shifts, 'Shift gravity {n} times', [15, 25, 40], 30),
    _Template(MissionMetric.shiftsUp, 'Shift gravity ↑ {n} times', [5, 10], 35),
    _Template(MissionMetric.matches, 'Make {n} color matches', [20, 35, 50], 35),
    _Template(MissionMetric.gates, 'Pass {n} gates', [5, 10, 15], 35),
    _Template(MissionMetric.perfect, 'Get {n} perfect actions', [5, 10, 15], 45),
    _Template(MissionMetric.coins, 'Collect {n} coins', [30, 60, 100], 30),
    _Template(MissionMetric.levels, 'Clear {n} levels', [2, 3, 5], 50),
    _Template(MissionMetric.combo, 'Reach a x{n} combo in one run', [6, 10, 15], 45),
    _Template(MissionMetric.endlessDistance, 'Travel {n} m in one Endless run', [1500, 3000], 50),
    _Template(MissionMetric.daily, 'Finish the Daily Challenge', [1], 40),
  ];

  static List<DailyMission> forDay(int dayKey) {
    final rng = math.Random(dayKey * 7349 + 11);
    final pool = List.of(_pool)..shuffle(rng);
    return [
      for (final t in pool.take(perDay))
        () {
          final i = rng.nextInt(t.targets.length);
          final n = t.targets[i];
          return DailyMission(metric: t.metric, target: n, reward: t.reward + i * 15, title: t.title.replaceAll('{n}', '$n'));
        }(),
    ];
  }

  /// How much one finished run contributes to [m].
  static int contribution(MissionMetric m, RunStats s, {required RunKind kind, required bool completed}) => switch (m) {
        MissionMetric.merges => s.merges,
        MissionMetric.shifts => s.gravityShifts,
        MissionMetric.shiftsUp => s.shiftsByDir.entries.where((e) => e.key.name == 'up').fold(0, (a, e) => a + e.value),
        MissionMetric.matches => s.colorMatches,
        MissionMetric.gates => s.gatesPassed,
        MissionMetric.perfect => s.perfectActions,
        MissionMetric.coins => s.coins,
        MissionMetric.levels => kind == RunKind.level && completed ? 1 : 0,
        MissionMetric.combo => s.maxCombo,
        MissionMetric.endlessDistance => kind == RunKind.endless ? s.distance.round() : 0,
        MissionMetric.daily => kind == RunKind.daily && completed ? 1 : 0,
      };
}
