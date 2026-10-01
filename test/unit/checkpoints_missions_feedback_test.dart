import 'package:color_gravity/core/models/game_color.dart';
import 'package:color_gravity/core/models/gravity_dir.dart';
import 'package:color_gravity/game/engine/game_engine.dart';
import 'package:color_gravity/game/entities/entity.dart';
import 'package:color_gravity/game/systems/scoring.dart';
import 'package:color_gravity/levels/generators/level_generator.dart';
import 'package:color_gravity/levels/models/level_config.dart';
import 'package:color_gravity/levels/validation/level_validator.dart';
import 'package:color_gravity/progression/daily_missions.dart';
import 'package:color_gravity/progression/progress_controller.dart';
import 'package:color_gravity/services/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Plays [e] with an invulnerable autopilot until it leaves the playing phase.
void autoplay(GameEngine e, {double maxSeconds = 120, bool Function()? stopWhen}) {
  var t = 0.0;
  while (e.phase == RunPhase.playing && t < maxSeconds) {
    if (stopWhen != null && stopWhen()) return;
    e.player.invuln = 5;
    e.update(1 / 30);
    e.drainEvents();
    t += 1 / 30;
  }
}

void main() {
  group('Checkpoints', () {
    test('only Hard and Very Hard levels get exactly one clean checkpoint', () {
      for (final l in [5, 60, 250, 399]) {
        expect(LevelGenerator.load(l).plan.ofKind(EntityKind.checkpoint), isEmpty, reason: 'level $l');
      }
      var withCp = 0;
      for (var l = 401; l <= 1000; l++) {
        final lv = LevelGenerator.load(l);
        final cps = lv.plan.ofKind(EntityKind.checkpoint).toList();
        expect(cps.length, lessThanOrEqualTo(1));
        if (cps.isNotEmpty) {
          withCp++;
          final cp = cps.first.trackY;
          expect(cp, greaterThan(lv.plan.length * 0.2));
          expect(cp, lessThan(lv.plan.length * 0.8));
        }
        expect(LevelValidator.validate(lv.config, lv.plan).ok, isTrue);
      }
      expect(withCp, greaterThanOrEqualTo(570), reason: 'nearly every hard level should have one ($withCp/600)');
    });

    test('passing a checkpoint records it; resuming starts there with saved stats', () {
      final level = LevelGenerator.load(450);
      final cpTrack = level.plan.ofKind(EntityKind.checkpoint).first.trackY;
      final first = GameEngine(level: level);
      autoplay(first, stopWhen: () => first.checkpoint != null);
      final cp = first.checkpoint;
      expect(cp, isNotNull);
      expect(cp!.track, cpTrack);
      first.stats.score += 999; // later progress must not leak into the snapshot
      expect(cp.stats.score, isNot(first.stats.score));

      final resumed = GameEngine(level: LevelGenerator.load(450), resume: cp);
      expect(resumed.resumed, isTrue);
      expect(resumed.stats.score, cp.stats.score);
      expect(resumed.player.color, cp.color);
      expect(resumed.gravity.dir, cp.gravity);
      resumed.update(1 / 60);
      // Nothing from before the checkpoint is spawned.
      final firstTrack = resumed.entities.map((e) => e.trackY).fold<double>(double.infinity, (a, b) => a < b ? a : b);
      expect(firstTrack, greaterThan(cpTrack));
      autoplay(resumed);
      expect(resumed.phase, isNot(RunPhase.playing));
    });
  });

  group('Gameplay feedback signals', () {
    test('lost hearts pulse the HUD; shields do not', () {
      final e = GameEngine(
          level: testLevel([
        at(Entity(kind: EntityKind.block, w: 60, h: 20), 180, 590),
      ]));
      e.update(1 / 60);
      expect(e.hud.hitPulse.value, 1);
      final s = GameEngine(level: testLevel([at(Entity(kind: EntityKind.block, w: 60, h: 20), 180, 590)]))..player.shield = true;
      s.update(1 / 60);
      expect(s.hud.hitPulse.value, 0);
    });

    test('coin events carry their arena position (for the fly-to-HUD effect)', () {
      final e = GameEngine(level: testLevel([at(Entity(kind: EntityKind.coin, r: 8), 180, 590)]));
      e.update(1 / 60);
      final coin = e.drainEvents().firstWhere((x) => x.type == GameEventType.coin);
      expect(coin.x, closeTo(180, 1));
      expect(coin.y, greaterThan(500));
    });

    test('combo timer drains between actions', () {
      final e = GameEngine(level: testLevel([]));
      e.combo
        ..hit()
        ..hit();
      e.update(1 / 60);
      final full = e.hud.comboTime.value;
      expect(full, greaterThan(0.9));
      run(e, 1.3);
      expect(e.hud.comboTime.value, lessThan(full));
      run(e, 2);
      expect(e.hud.comboTime.value, 0);
    });
  });

  group('Daily missions', () {
    RunStats stats({int merges = 0, int shifts = 0, int up = 0, int coins = 0, int combo = 0, double distance = 0}) {
      final s = RunStats()
        ..merges = merges
        ..gravityShifts = shifts
        ..coins = coins
        ..maxCombo = combo
        ..distance = distance
        ..colorMatches = 60
        ..gatesPassed = 20
        ..perfectDodges = 20;
      s.shiftsByDir[GravityDir.up] = up;
      return s;
    }

    test('three distinct missions per day, stable within a day', () {
      final a = DailyMissions.forDay(20261001);
      expect(a.length, 3);
      expect(a.map((m) => m.metric).toSet().length, 3);
      expect(DailyMissions.forDay(20261001).map((m) => m.id), a.map((m) => m.id));
      final week = {for (var d = 1; d <= 7; d++) DailyMissions.forDay(20261000 + d).map((m) => m.id).join()};
      expect(week.length, greaterThan(1));
    });

    test('progress accrues across runs, completes, claims once, resets next day', () {
      var now = DateTime(2026, 10, 1, 9);
      final p = ProgressController(MemoryStorage(), clock: () => now);
      final missions = p.todaysMissions;
      final big = stats(merges: 20, shifts: 50, up: 20, coins: 120, combo: 20, distance: 5000);
      // Two runs of every kind complete every possible mission type.
      final r1 = p.recordLevel(level: 1, completed: true, stars: 1, stats: big, baseReward: 0);
      p.recordLevel(level: 2, completed: true, stars: 1, stats: big, baseReward: 0);
      p.recordLevel(level: 3, completed: true, stars: 1, stats: big, baseReward: 0);
      p.recordLevel(level: 4, completed: true, stars: 1, stats: big, baseReward: 0);
      p.recordLevel(level: 5, completed: true, stars: 1, stats: big, baseReward: 0);
      p.recordDaily(completed: true, stats: big, now: now);
      p.recordEndless(big);
      expect(r1.missions, isNotEmpty);
      for (final m in missions) {
        expect(p.missionDone(m), isTrue, reason: m.title);
      }
      expect(p.claimableMissions, 4); // 3 missions + all-done bonus
      final coins = p.coins;
      final got = p.claimMission(missions.first);
      expect(got, missions.first.reward);
      expect(p.coins, coins + got);
      expect(p.claimMission(missions.first), 0, reason: 'claim only once');
      for (final m in missions.skip(1)) {
        p.claimMission(m);
      }
      expect(p.claimMissionBonus(), DailyMissions.allDoneBonus);
      expect(p.claimMissionBonus(), 0);
      expect(p.claimableMissions, 0);

      now = DateTime(2026, 10, 2, 9);
      final tomorrow = p.todaysMissions;
      expect(tomorrow.every((m) => p.missionProgress(m) == 0 && !p.missionClaimed(m)), isTrue);
      expect(p.data.missionBonusClaimed, isFalse);
    });

    test('"best run" missions use the max, not the sum', () {
      final p = ProgressController(MemoryStorage(), clock: () => DateTime(2026, 10, 1));
      const combo = DailyMission(metric: MissionMetric.combo, target: 10, reward: 45, title: 'x10');
      expect(DailyMissions.contribution(MissionMetric.combo, stats(combo: 6), kind: RunKind.level, completed: true), 6);
      expect(DailyMissions.contribution(MissionMetric.levels, stats(), kind: RunKind.level, completed: false), 0);
      expect(DailyMissions.contribution(MissionMetric.endlessDistance, stats(distance: 900), kind: RunKind.level, completed: true), 0);
      expect(p.missionProgress(combo), 0);
    });

    test('mission state survives a restart', () async {
      final store = MemoryStorage();
      final now = DateTime(2026, 10, 1);
      final p = ProgressController(store, clock: () => now);
      final m = p.todaysMissions.first;
      p.data.missionProgress[m.id] = m.target;
      p.claimMission(m);
      await p.flush();
      final q = ProgressController(store, clock: () => now);
      expect(q.missionClaimed(m), isTrue);
      expect(q.missionProgress(m), m.target);
    });
  });

  test('stat snapshots are independent copies', () {
    final s = RunStats()
      ..score = 10
      ..colorHistory.add(GameColor.red);
    final c = s.copy();
    s.score = 99;
    s.colorHistory.add(GameColor.blue);
    expect(c.score, 10);
    expect(c.colorHistory, [GameColor.red]);
  });
}
