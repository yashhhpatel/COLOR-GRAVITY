import 'package:color_gravity/core/models/game_color.dart';
import 'package:color_gravity/game/entities/entity.dart';
import 'package:color_gravity/levels/generators/level_generator.dart';
import 'package:color_gravity/levels/models/level_config.dart';
import 'package:color_gravity/levels/segments/segment_builder.dart';
import 'package:color_gravity/levels/validation/level_validator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  group('Level generation (1000 levels)', () {
    test('every level generates, validates and never needs the fallback', () {
      for (var l = 1; l <= 1000; l++) {
        final loaded = LevelGenerator.load(l);
        expect(loaded.config.fallback, isFalse, reason: 'level $l fell back');
        final report = LevelValidator.validate(loaded.config, loaded.plan);
        expect(report.ok, isTrue, reason: 'level $l: $report');
        expect(loaded.config.segments.first.type, SegmentType.start);
        expect(loaded.config.segments.last.type, SegmentType.finish);
        expect(loaded.plan.ofKind(EntityKind.finish).length, 1);
        expect(loaded.config.starObjectives.length, 2);
      }
    });

    test('generation is deterministic', () {
      for (final l in [1, 7, 120, 555, 1000]) {
        final a = LevelGenerator.load(l).plan.entities;
        final b = LevelGenerator.load(l).plan.entities;
        expect(a.length, b.length);
        for (var i = 0; i < a.length; i++) {
          expect(a[i].kind, b[i].kind);
          expect(a[i].trackY, b[i].trackY);
          expect(a[i].x, b[i].x);
        }
      }
    });

    test('mechanics are introduced progressively', () {
      final l1 = LevelGenerator.load(1);
      expect(l1.config.palette.length, 1);
      expect(l1.config.swipeEnabled, isFalse);
      expect(l1.plan.ofKind(EntityKind.gate), isEmpty);
      expect(l1.config.tutorial, isTrue);
      expect(l1.plan.ofKind(EntityKind.hint), isNotEmpty);

      final l3 = LevelGenerator.load(3);
      expect(l3.config.palette.length, 2);
      expect(l3.plan.ofKind(EntityKind.gate), isNotEmpty);

      expect(LevelGenerator.mechanicsFor(10).contains(Mechanic.gravityZone), isFalse);
      expect(LevelGenerator.mechanicsFor(31).contains(Mechanic.gravityZone), isTrue);
      expect(LevelGenerator.load(601).config.palette.contains(GameColor.cyan), isTrue);
      // Freshly unlocked mechanic shows up in its unlock level.
      expect(
          LevelGenerator.load(31).plan.ofKind(EntityKind.gravityZone).isNotEmpty ||
              LevelGenerator.load(31).config.segments.any((s) => s.type == SegmentType.gravity),
          isTrue);
    });

    test('difficulty ramps without only raising speed', () {
      expect(LevelGenerator.speedFor(1), lessThan(LevelGenerator.speedFor(500)));
      expect(LevelGenerator.difficultyFor(1), lessThan(LevelGenerator.difficultyFor(1000)));
      expect(LevelGenerator.mechanicsFor(500).length, greaterThan(LevelGenerator.mechanicsFor(50).length));
      final late = LevelGenerator.load(900).plan;
      final kinds = late.entities.map((e) => e.kind).toSet();
      expect(kinds.length, greaterThan(6));
    });

    test('daily challenge is stable per day and differs across days', () {
      final a = LevelGenerator.daily(DateTime(2026, 10, 1));
      final b = LevelGenerator.daily(DateTime(2026, 10, 1));
      final c = LevelGenerator.daily(DateTime(2026, 10, 2));
      expect(a.config.kind, RunKind.daily);
      expect(a.plan.entities.length, b.plan.entities.length);
      expect(a.config.seed == c.config.seed, isFalse);
    });

    test('endless plans extend on demand', () {
      final e = LevelGenerator.endless(42);
      final before = e.plan.entities.length;
      final cursor = e.builder.ctx.cursor;
      e.builder.buildMore(LevelGenerator.endlessBatch(80, e.builder.rng, null));
      expect(e.plan.entities.length, greaterThan(before));
      expect(e.builder.ctx.cursor, greaterThan(cursor));
      // still sorted for spawning
      final ys = e.plan.entities.map((x) => x.trackY).toList();
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i] >= ys[i - 1], isTrue);
      }
    });
  });

  group('LevelValidator', () {
    test('rejects a gate whose color is unreachable', () {
      final lvl = testLevel([
        at(Entity(kind: EntityKind.gate, w: 344, h: 18, gateColors: [GameColor.blue], fullWidth: true), 180, 100)..trackY = 900,
        Entity(kind: EntityKind.finish, x: 180, w: 344, h: 24)..trackY = 2000,
      ], start: GameColor.red);
      final r = LevelValidator.validate(lvl.config, lvl.plan);
      expect(r.issues.any((i) => i.contains('unreachable color')), isTrue);
    });

    test('accepts the same gate after a color band', () {
      final lvl = testLevel([
        Entity(kind: EntityKind.colorSwitch, x: 180, w: 344, h: 14, color: GameColor.blue, fullWidth: true)..trackY = 700,
        Entity(kind: EntityKind.gate, x: 180, w: 344, h: 18, gateColors: [GameColor.blue], fullWidth: true)..trackY = 900,
        Entity(kind: EntityKind.finish, x: 180, w: 344, h: 24)..trackY = 2000,
      ], start: GameColor.red);
      final r = LevelValidator.validate(lvl.config, lvl.plan);
      expect(r.issues.where((i) => i.contains('gate')), isEmpty);
    });

    test('rejects a fully blocked row', () {
      final lvl = testLevel([
        Entity(kind: EntityKind.block, x: 180, w: 344, h: 24)..trackY = 900,
        Entity(kind: EntityKind.finish, x: 180, w: 344, h: 24)..trackY = 2000,
      ]);
      final r = LevelValidator.validate(lvl.config, lvl.plan);
      expect(r.issues.any((i) => i.contains('blocked row')), isTrue);
    });

    test('rejects unachievable objectives', () {
      final lvl = testLevel(
        [Entity(kind: EntityKind.finish, x: 180, w: 344, h: 24)..trackY = 2000],
        stars: [const Objective(ObjectiveType.collectCoins, target: 10)],
      );
      expect(LevelValidator.validate(lvl.config, lvl.plan).ok, isFalse);
    });

    test('segment builder output is always sorted', () {
      final c = LevelGenerator.configFor(250);
      final plan = SegmentBuilder(c).build();
      for (var i = 1; i < plan.entities.length; i++) {
        expect(plan.entities[i].trackY >= plan.entities[i - 1].trackY, isTrue);
      }
    });
  });
}
