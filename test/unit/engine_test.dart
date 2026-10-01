import 'package:color_gravity/core/constants/game_constants.dart';
import 'package:color_gravity/core/models/game_color.dart';
import 'package:color_gravity/core/models/gravity_dir.dart';
import 'package:color_gravity/game/engine/game_engine.dart';
import 'package:color_gravity/game/entities/entity.dart';
import 'package:color_gravity/levels/generators/level_generator.dart';
import 'package:color_gravity/levels/models/level_config.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Entity finishAt(double track) => Entity(kind: EntityKind.finish, x: 180, w: 344, h: 24)..trackY = track;

GameEngine engineWith(List<Entity> ents,
    {GameColor start = GameColor.red,
    bool swipe = true,
    int hearts = 3,
    List<Objective>? objectives,
    List<Objective>? stars,
    double speed = 150}) {
  return GameEngine(
    level: testLevel([...ents, finishAt(5000)],
        start: start, swipe: swipe, hearts: hearts, objectives: objectives, stars: stars, speed: speed),
  );
}

List<GameEventType> events(GameEngine e) => e.drainEvents().map((x) => x.type).toList();

void main() {
  const f = Arena.field;
  const r = Arena.playerRadius;

  group('Game start & gravity', () {
    test('run starts playing with the player resting on the gravity side', () {
      final e = engineWith([]);
      run(e, 0.5);
      expect(e.phase, RunPhase.playing);
      expect(e.player.y, closeTo(f.bottom - r, 0.5));
      expect(e.hud.gravity.value, GravityDir.down);
      expect(e.hud.color.value, GameColor.red);
    });

    test('swipes move the player to all four sides', () {
      final e = engineWith([]);
      run(e, 0.3);
      e.onSwipe(GravityDir.left);
      run(e, 0.9);
      expect(e.player.x, closeTo(f.left + r, 0.5));
      e.onSwipe(GravityDir.up);
      run(e, 0.9);
      expect(e.player.y, closeTo(f.top + r, 0.5));
      e.onSwipe(GravityDir.right);
      run(e, 0.9);
      expect(e.player.x, closeTo(f.right - r, 0.5));
      e.onSwipe(GravityDir.down);
      run(e, 0.9);
      expect(e.player.y, closeTo(f.bottom - r, 0.5));
      expect(e.stats.gravityShifts, 4);
      expect(e.stats.shiftsByDir[GravityDir.up], 1);
      expect(events(e), contains(GameEventType.gravityShift));
    });

    test('dragging steers perpendicular to gravity', () {
      final e = engineWith([]);
      run(e, 0.2);
      e.onDrag(const Offset(40, 0));
      run(e, 0.3);
      expect(e.player.x, closeTo(180 + 40 * Physics.steerSensitivity, 1));
      // Vertical drag does nothing while gravity is vertical.
      final y = e.player.y;
      e.onDrag(const Offset(0, -40));
      run(e, 0.3);
      expect(e.player.y, closeTo(y, 0.5));
    });

    test('swipes are ignored when the level disables gravity control', () {
      final e = engineWith([], swipe: false);
      e.onSwipe(GravityDir.left);
      run(e, 0.3);
      expect(e.gravity.dir, GravityDir.down);
    });

    test('loose orbs fall with gravity', () {
      final o = at(Entity(kind: EntityKind.orb, r: 10, color: GameColor.blue), 100, 300);
      final e = engineWith([o]);
      e.onSwipe(GravityDir.left);
      run(e, 1.2);
      final live = e.entities.firstWhere((x) => x.kind == EntityKind.orb);
      expect(live.x, closeTo(Arena.wallLeft + live.r, 1));
    });
  });

  group('Color & matching', () {
    test('matching orb is collected and scores', () {
      final e = engineWith([at(Entity(kind: EntityKind.orb, r: 10, color: GameColor.red), 180, 590)]);
      e.update(1 / 60);
      expect(e.stats.orbsCollected, 1);
      expect(e.stats.colorMatches, 1);
      expect(e.stats.score, greaterThanOrEqualTo(10));
      expect(events(e), contains(GameEventType.collect));
    });

    test('wrong color orb is not collected and breaks the combo', () {
      final e = engineWith([at(Entity(kind: EntityKind.orb, r: 10, color: GameColor.blue), 180, 590)]);
      e.combo.combo = 3;
      e.update(1 / 60);
      expect(e.stats.orbsCollected, 0);
      expect(e.combo.combo, 0);
      expect(events(e), contains(GameEventType.mismatch));
    });

    test('color band changes the player color', () {
      final e =
          engineWith([at(Entity(kind: EntityKind.colorSwitch, w: 344, h: 14, color: GameColor.blue, fullWidth: true), 180, 590)]);
      e.update(1 / 60);
      expect(e.player.color, GameColor.blue);
      expect(e.stats.colorHistory, [GameColor.red, GameColor.blue]);
    });
  });

  group('Merging', () {
    test('touching same-color orbs combine into the next level', () {
      final e = engineWith([
        at(Entity(kind: EntityKind.orb, r: 10, color: GameColor.green), 100, 300),
        at(Entity(kind: EntityKind.orb, r: 10, color: GameColor.green), 116, 300),
      ]);
      e.update(1 / 60);
      final orbs = e.entities.where((x) => x.kind == EntityKind.orb).toList();
      expect(orbs.length, 1);
      expect(orbs.first.level, 2);
      expect(e.stats.merges, 1);
      expect(events(e), contains(GameEventType.merge));
    });

    test('chain merges cascade', () {
      final e = engineWith([
        at(Entity(kind: EntityKind.orb, r: 10, color: GameColor.green), 100, 300),
        at(Entity(kind: EntityKind.orb, r: 10, color: GameColor.green), 116, 300),
        at(Entity(kind: EntityKind.orb, r: Entity.orbRadius(2), color: GameColor.green, level: 2), 108, 318),
      ]);
      run(e, 0.1);
      expect(e.stats.merges, 2);
      expect(e.stats.maxMergeLevel, 3);
      expect(e.stats.chainMerges, 1);
    });

    test('different colors do not combine', () {
      final e = engineWith([
        at(Entity(kind: EntityKind.orb, r: 10, color: GameColor.green), 100, 300),
        at(Entity(kind: EntityKind.orb, r: 10, color: GameColor.blue), 116, 300),
      ]);
      e.update(1 / 60);
      expect(e.entities.where((x) => x.kind == EntityKind.orb).length, 2);
    });
  });

  group('Obstacles & gates', () {
    test('hazards cost a heart, last heart fails the run', () {
      final e = engineWith([at(Entity(kind: EntityKind.block, w: 60, h: 20), 180, 590)], hearts: 1);
      e.update(1 / 60);
      expect(e.phase, RunPhase.failed);
      expect(e.stats.failReason, 'Hit a barrier');
      expect(events(e), containsAll([GameEventType.hit, GameEventType.fail]));
    });

    test('shield absorbs a hit', () {
      final e = engineWith([at(Entity(kind: EntityKind.spikes, w: 60, h: 18), 180, 590)]);
      e.player.shield = true;
      e.update(1 / 60);
      expect(e.player.hearts, 3);
      expect(e.player.shield, isFalse);
    });

    test('colored spikes only hurt their color', () {
      final e = engineWith([at(Entity(kind: EntityKind.spikes, w: 60, h: 18, dangerColor: GameColor.blue), 180, 590)]);
      e.update(1 / 60);
      expect(e.player.hearts, 3);
    });

    test('matching color passes a gate', () {
      final e = engineWith([
        at(Entity(kind: EntityKind.gate, w: 344, h: 18, gateColors: [GameColor.red], fullWidth: true), 180, 580)
      ]);
      e.update(1 / 60);
      expect(e.stats.gatesPassed, 1);
      expect(e.player.hearts, 3);
    });

    test('wrong color at a gate is a hit', () {
      final e = engineWith([
        at(Entity(kind: EntityKind.gate, w: 344, h: 18, gateColors: [GameColor.blue], fullWidth: true), 180, 580)
      ], hearts: 1);
      e.update(1 / 60);
      expect(e.phase, RunPhase.failed);
      expect(e.stats.failReason, 'Wrong color at a gate');
    });

    test('color + gravity gate requires both', () {
      final gate =
          Entity(kind: EntityKind.gate, w: 344, h: 18, gateColors: [GameColor.red], gateDir: GravityDir.left, fullWidth: true);
      final e = engineWith([at(gate, 180, 400)], hearts: 1);
      e.onSwipe(GravityDir.left);
      run(e, 1.5);
      expect(e.stats.gatesPassed, 1);
      expect(e.phase, RunPhase.playing);
    });

    test('gravity gate effect and switch pad shift gravity', () {
      final e = engineWith([
        at(Entity(kind: EntityKind.gravitySwitch, r: 17, dir: GravityDir.right), 180, 590),
      ]);
      e.update(1 / 60);
      expect(e.gravity.dir, GravityDir.right);
      final e2 =
          engineWith([at(Entity(kind: EntityKind.gate, w: 344, h: 18, effectDir: GravityDir.left, fullWidth: true), 180, 580)]);
      e2.update(1 / 60);
      expect(e2.gravity.dir, GravityDir.left);
    });

    test('gravity zone holds gravity while inside and locks swipes', () {
      final zone = Entity(kind: EntityKind.gravityZone, w: 344, h: 300, dir: GravityDir.right);
      final e = engineWith([at(zone, 180, 500)]);
      e.update(1 / 60);
      expect(e.gravity.dir, GravityDir.right);
      e.onSwipe(GravityDir.left);
      expect(e.gravity.dir, GravityDir.right);
    });

    test('power-ups activate', () {
      final e = engineWith([
        at(Entity(kind: EntityKind.powerUp, r: 16, powerUp: PowerUpType.magnet), 180, 590),
      ]);
      e.update(1 / 60);
      expect(e.powerUps.containsKey(PowerUpType.magnet), isTrue);
      expect(e.stats.powerUpsUsed, 1);
      run(e, 9);
      expect(e.powerUps.containsKey(PowerUpType.magnet), isFalse);
    });
  });

  group('Completion, failure & rewards', () {
    test('reaching the finish completes the level with stars', () {
      final e = GameEngine(
        level: testLevel([
          at(Entity(kind: EntityKind.coin, r: 8), 180, 590),
          finishAt(trackAtY(560)),
        ], stars: [
          const Objective(ObjectiveType.collectCoins, target: 1),
          const Objective(ObjectiveType.noCollision)
        ]),
      );
      run(e, 1);
      expect(e.phase, RunPhase.completed);
      expect(e.stars, 3);
      expect(e.stats.coins, 1);
      expect(events(e), contains(GameEventType.complete));
    });

    test('unmet mission fails at the finish', () {
      final e = GameEngine(
        level: testLevel([
          finishAt(trackAtY(560))
        ], objectives: [
          const Objective(ObjectiveType.reachFinish),
          const Objective(ObjectiveType.collectCoins, target: 5),
        ]),
      );
      run(e, 1);
      expect(e.phase, RunPhase.failed);
      expect(e.stats.failReason, startsWith('Mission incomplete'));
    });

    test('revive continues a failed run once', () {
      final e = engineWith([at(Entity(kind: EntityKind.block, w: 60, h: 20), 180, 590)], hearts: 1);
      e.update(1 / 60);
      expect(e.phase, RunPhase.failed);
      e.revive();
      expect(e.phase, RunPhase.playing);
      expect(e.player.hearts, 1);
      expect(e.continued, isTrue);
    });

    test('endless mode keeps extending and speeds up', () {
      final e = GameEngine(level: LevelGenerator.endless(7));
      final startLen = e.level.plan.entities.length;
      run(e, 8, each: () => e.player.invuln = 5);
      expect(e.level.plan.entities.length, greaterThan(startLen));
      expect(e.speed, greaterThan(e.config.speed));
      expect(e.phase, RunPhase.playing);
    });
  });

  group('Full levels (headless, invulnerable bot)', () {
    test('sampled levels run start → finish without errors', () {
      for (final l in [1, 2, 3, 4, 6, 12, 33, 51, 77, 101, 150, 203, 333, 451, 601, 777, 999, 1000]) {
        final e = GameEngine(level: LevelGenerator.load(l));
        final maxSeconds = e.config.pathLength / e.config.speed + 20;
        var t = 0.0;
        while (e.phase == RunPhase.playing && t < maxSeconds) {
          e.player.invuln = 5; // bot never dies; we are testing flow, not skill
          if (e.hud.prompt.value != null) {
            final p = e.hud.prompt.value!;
            if (p.dir != null) {
              e.onSwipe(p.dir!);
            } else {
              e.onDrag(const Offset(60, 0));
            }
          }
          e.update(1 / 30);
          e.drainEvents();
          t += 1 / 30;
        }
        expect(e.phase, isNot(RunPhase.playing), reason: 'level $l did not finish in time');
        if (e.phase == RunPhase.failed) {
          expect(e.stats.failReason, startsWith('Mission incomplete'), reason: 'level $l');
        }
      }
    });
  });

  test('banners never overlap the tutorial prompt', () {
    final e = GameEngine(level: LevelGenerator.load(1));
    var sawPrompt = false, overlap = false, bannerAfterPrompt = false;
    for (var i = 0; i < 60 * 12; i++) {
      final p = e.hud.prompt.value;
      if (p != null) {
        sawPrompt = true;
        if (e.hud.banner.value != null) overlap = true;
        if (i % 30 == 0) e.onDrag(const Offset(30, 0)); // eventually completes the drag prompt
      } else if (sawPrompt && e.hud.banner.value != null) {
        bannerAfterPrompt = true;
      }
      e.player.invuln = 5;
      e.update(1 / 60);
    }
    expect(sawPrompt, isTrue);
    expect(overlap, isFalse);
    expect(bannerAfterPrompt, isTrue, reason: 'the deferred banner still shows afterwards');
  });
}
