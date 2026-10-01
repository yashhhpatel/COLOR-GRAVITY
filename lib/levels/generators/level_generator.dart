import 'dart:math' as math;

import '../../core/constants/app_config.dart';
import '../../core/models/game_color.dart';
import '../../core/models/gravity_dir.dart';
import '../../game/entities/entity.dart';
import '../models/level_config.dart';
import '../segments/segment_builder.dart';
import '../validation/level_validator.dart';

/// A level ready to play: validated config + laid-out plan.
class LoadedLevel {
  LoadedLevel(this.config, this.plan, this.builder);
  final LevelConfig config;
  final LevelPlan plan;

  /// Kept so endless mode can keep extending the same track.
  final SegmentBuilder builder;
}

/// Deterministically generates configs for 1000+ levels, the daily challenge
/// and endless mode from a seed. No level is hard-coded.
class LevelGenerator {
  static int _levelSeed(int level, int attempt) => level * 7919 + attempt * 104729 + 17;

  static List<Mechanic> mechanicsFor(int level) => Mechanic.values.where((m) => m.unlockLevel <= level).toList();

  /// Mechanics that unlock exactly at this level (for "NEW" callouts).
  static List<Mechanic> newMechanicsAt(int level) => Mechanic.values.where((m) => m.unlockLevel == level).toList();

  /// Difficulty bands (0..1) for Easy → Medium → Hard → Very Hard.
  static const Map<DifficultyTier, (double, double)> _bands = {
    DifficultyTier.easy: (0.0, 0.18),
    DifficultyTier.medium: (0.22, 0.48),
    DifficultyTier.hard: (0.52, 0.78),
    DifficultyTier.veryHard: (0.82, 1.0),
  };

  static const Map<DifficultyTier, (double, double)> _speeds = {
    DifficultyTier.easy: (140, 162),
    DifficultyTier.medium: (166, 196),
    DifficultyTier.hard: (200, 232),
    DifficultyTier.veryHard: (236, 268),
  };

  /// Rises steadily through each tier, with pacing: every 10th level is a
  /// harder challenge and the level after it is a short breather.
  static double difficultyFor(int level) {
    final tier = DifficultyTier.forLevel(level);
    final (lo, hi) = _bands[tier]!;
    var d = lo + (hi - lo) * tier.progressOf(level);
    if (level > 4 && level % 10 == 0) d += 0.06;
    if (level > 4 && level % 10 == 1) d -= 0.03;
    return d.clamp(0.0, 1.0);
  }

  static double speedFor(int level) {
    final tier = DifficultyTier.forLevel(level);
    final (lo, hi) = _speeds[tier]!;
    final bump = level % 10 == 0 ? 6.0 : 0.0;
    return lo + (hi - lo) * tier.progressOf(level) + bump;
  }

  /// Hearts per run: Very Hard levels allow one mistake fewer.
  static int heartsFor(int level) => DifficultyTier.forLevel(level) == DifficultyTier.veryHard ? 2 : 3;

  static List<GameColor> paletteFor(int level, int worldId, math.Random rng) {
    final n = level <= 2
        ? 1
        : level <= 10
            ? 2
            : level <= 50
                ? 3
                : level <= 200
                    ? 4
                    : 5;
    const base = GameColor.base;
    final start = (worldId + level ~/ 25) % base.length;
    final list = [for (var i = 0; i < n; i++) base[(start + i * 2) % base.length]];
    if (level >= Mechanic.sixColors.unlockLevel) list.add(GameColor.cyan);
    return list;
  }

  static LevelConfig configFor(int level,
      {int attempt = 0, RunKind kind = RunKind.level, DailyModifier modifier = DailyModifier.none, int? seedOverride}) {
    final seed = seedOverride ?? _levelSeed(level, attempt);
    final rng = math.Random(seed);
    final worldId = ((level - 1) ~/ AppConfig.levelsPerWorld).clamp(0, 9);
    final mechanics = mechanicsFor(level).toSet();
    final tutorial = kind == RunKind.level && level <= 4;
    var palette = paletteFor(level, worldId, rng);
    if (modifier == DailyModifier.mono && palette.length > 2) palette = palette.sublist(0, 2);
    var difficulty = difficultyFor(level);
    var speed = speedFor(level);
    if (modifier == DailyModifier.fast) speed *= 1.25;

    // Gravity mode progression.
    var mode = GravityMode.manual;
    var interval = 6.0;
    if (modifier == DailyModifier.rotating) {
      mode = GravityMode.rotating;
      interval = 5.5;
    } else if (level >= Mechanic.rotatingGravity.unlockLevel && level % 7 == 3) {
      mode = GravityMode.rotating;
      interval = level >= Mechanic.rapidGravity.unlockLevel ? 4.2 : 5.5;
    } else if (level >= Mechanic.reversingGravity.unlockLevel && level % 5 == 1) {
      mode = GravityMode.reversing;
      interval = level >= Mechanic.rapidGravity.unlockLevel ? 3.2 : 4.6;
    }

    final pathLength = tutorial
        ? 1900.0
        : kind == RunKind.endless
            ? double.infinity
            : 2000.0 + math.min(level, 450) * 5.5 + rng.nextInt(200);

    final objectPatterns = <String>['line', 'zigzag', 'coins'];
    if (mechanics.contains(Mechanic.swipeSide)) objectPatterns.add('sides');
    if (level >= 15) objectPatterns.add('arc');

    final obstaclePatterns = <String>['spikeRow'];
    void addIf(Mechanic m, String p) {
      if (mechanics.contains(m)) obstaclePatterns.add(p);
    }

    addIf(Mechanic.movingBlock, 'sway');
    addIf(Mechanic.rotor, 'rotor');
    addIf(Mechanic.laser, 'laser');
    addIf(Mechanic.crusher, 'crusher');
    addIf(Mechanic.gravitySpikes, 'gravitySpikes');
    addIf(Mechanic.meteors, 'meteors');
    if (palette.length > 1) addIf(Mechanic.colorSpikes, 'colorSpikes');
    if (palette.length > 1) addIf(Mechanic.colorCrusher, 'colorCrusher');
    if (mode != GravityMode.rotating) addIf(Mechanic.gravityLaser, 'gravityLaser');

    final gatePatterns = <String>['plain'];
    if (mechanics.contains(Mechanic.multiColorGate)) gatePatterns.add('multi');
    if (mechanics.contains(Mechanic.colorGravityGate)) gatePatterns.add('colorGravity');
    if (mechanics.contains(Mechanic.colorBarrier)) gatePatterns.add('barrier');

    final powerUps = <String>[];
    if (level >= 10) powerUps.addAll(['shield', 'magnet', 'slowMotion']);
    if (level >= 20) powerUps.addAll(['doubleCoins', 'colorShift']);
    if (level >= 30) powerUps.addAll(['gravityFreeze', 'megaMerge']);
    if (level >= 45) powerUps.add('gravityControl');
    if (level >= 60) powerUps.addAll(['colorFreeze', 'perfectGravity']);

    final segments =
        tutorial ? _tutorialSegments(level, seed) : _segmentsFor(level, mechanics, palette, difficulty, pathLength, rng, kind);

    final startColor = palette[rng.nextInt(palette.length)];
    return LevelConfig(
      levelId: level,
      worldId: worldId,
      seed: seed,
      speed: tutorial ? 135 : speed,
      pathLength: pathLength,
      startingColor: startColor,
      startingGravity: GravityDir.down,
      palette: palette,
      gravityMode: mode,
      gravityInterval: interval,
      smoothGravity: level < 300 || level.isEven,
      swipeEnabled: level != 1 && mode != GravityMode.rotating,
      segments: segments,
      objectives: [const Objective(ObjectiveType.reachFinish)],
      starObjectives: [],
      baseReward: 20 + level ~/ 10,
      difficulty: difficulty,
      mechanics: mechanics,
      objectPatterns: objectPatterns,
      obstaclePatterns: obstaclePatterns,
      gatePatterns: gatePatterns,
      powerUpPatterns: powerUps,
      hearts: modifier == DailyModifier.glass ? 1 : (kind == RunKind.level ? heartsFor(level) : 3),
      kind: kind,
      modifier: modifier,
      tutorial: tutorial,
    );
  }

  static List<SegmentSpec> _tutorialSegments(int level, int seed) {
    var s = seed;
    SegmentSpec seg(SegmentType t, double len) => SegmentSpec(t, length: len, seed: s++);
    return switch (level) {
      1 => [
          seg(SegmentType.start, 420),
          seg(SegmentType.collection, 460),
          seg(SegmentType.obstacle, 380),
          seg(SegmentType.collection, 420),
          seg(SegmentType.finish, 300),
        ],
      2 => [
          seg(SegmentType.start, 380),
          seg(SegmentType.gravityShift, 620),
          seg(SegmentType.collection, 420),
          seg(SegmentType.obstacle, 380),
          seg(SegmentType.finish, 300),
        ],
      3 => [
          seg(SegmentType.start, 340),
          seg(SegmentType.collection, 440),
          seg(SegmentType.color, 440),
          seg(SegmentType.colorGate, 420),
          seg(SegmentType.finish, 300),
        ],
      _ => [
          seg(SegmentType.start, 340),
          seg(SegmentType.merge, 480),
          seg(SegmentType.gravityShift, 520),
          seg(SegmentType.merge, 480),
          seg(SegmentType.finish, 300),
        ],
    };
  }

  static double segmentLength(SegmentType t, double d, math.Random rng) => switch (t) {
        SegmentType.start => 360,
        SegmentType.finish => 300,
        SegmentType.collection => 440 + rng.nextInt(80).toDouble(),
        SegmentType.obstacle => 380 + d * 260 + (d >= 0.5 ? 140 : 0),
        SegmentType.gravityShift => 520 + rng.nextInt(180).toDouble(),
        SegmentType.colorGate => 400,
        SegmentType.color => 440,
        SegmentType.merge => 460,
        SegmentType.gravity => 480,
        SegmentType.powerUp => 400,
        SegmentType.riskReward => 780,
        SegmentType.challenge => 560 + d * 120,
        SegmentType.reward => 380,
      };

  static Map<SegmentType, double> segmentWeights(int level, Set<Mechanic> m, List<GameColor> palette, double d) {
    return {
      SegmentType.collection: 3,
      SegmentType.obstacle: 3 + d * 2,
      if (m.contains(Mechanic.swipeSide)) SegmentType.gravityShift: 2.5,
      if (m.contains(Mechanic.colorGate) && palette.length > 1) SegmentType.colorGate: 2,
      if (m.contains(Mechanic.colorSwitch) && palette.length > 1) SegmentType.color: 1.4,
      if (m.contains(Mechanic.merge)) SegmentType.merge: 1.5,
      if (m.contains(Mechanic.gravitySwitch)) SegmentType.gravity: 2,
      if (m.contains(Mechanic.powerUps)) SegmentType.powerUp: 1,
      if (m.contains(Mechanic.riskReward)) SegmentType.riskReward: 0.8,
      if (level > DifficultyTier.easy.last && palette.length > 1) SegmentType.challenge: 0.4 + d * 2.4,
      SegmentType.reward: 0.15 + 0.4 * (1 - d),
    };
  }

  static SegmentType pickSegment(Map<SegmentType, double> weights, SegmentType? last, math.Random rng) {
    final entries = weights.entries.where((e) => e.key != last).toList();
    final total = entries.fold<double>(0, (a, e) => a + e.value);
    var roll = rng.nextDouble() * total;
    for (final e in entries) {
      roll -= e.value;
      if (roll <= 0) return e.key;
    }
    return entries.last.key;
  }

  static List<SegmentSpec> _segmentsFor(
      int level, Set<Mechanic> m, List<GameColor> palette, double d, double pathLength, math.Random rng, RunKind kind) {
    final segs = <SegmentSpec>[SegmentSpec(SegmentType.start, length: 360, seed: rng.nextInt(1 << 30))];
    final weights = segmentWeights(level, m, palette, d);
    var total = 360.0;
    final limit = kind == RunKind.endless ? 3000.0 : pathLength - 300;
    SegmentType? last = SegmentType.start;
    // Make sure a newly unlocked mechanic actually shows up in its first level.
    final fresh = newMechanicsAt(level);
    final forced = <SegmentType>[
      for (final f in fresh)
        if (_segmentFor(f) case final t?) t,
    ];
    while (total < limit) {
      final t = forced.isNotEmpty ? forced.removeAt(0) : pickSegment(weights, last, rng);
      final len = segmentLength(t, d, rng);
      segs.add(SegmentSpec(t, length: len, seed: rng.nextInt(1 << 30)));
      total += len;
      last = t;
    }
    if (kind != RunKind.endless) segs.add(SegmentSpec(SegmentType.finish, length: 300, seed: rng.nextInt(1 << 30)));
    return segs;
  }

  static SegmentType? _segmentFor(Mechanic m) => switch (m) {
        Mechanic.gravitySwitch || Mechanic.gravityGate || Mechanic.gravityZone || Mechanic.gravityLock => SegmentType.gravity,
        Mechanic.gravityWall => SegmentType.gravityShift,
        Mechanic.colorGravityGate || Mechanic.multiColorGate || Mechanic.colorBarrier => SegmentType.colorGate,
        Mechanic.basin || Mechanic.colorTrigger => SegmentType.color,
        Mechanic.mergeZone => SegmentType.merge,
        Mechanic.riskReward => SegmentType.riskReward,
        Mechanic.powerUps ||
        Mechanic.bomb ||
        Mechanic.gravityCore ||
        Mechanic.colorCore ||
        Mechanic.gravityBomb =>
          SegmentType.powerUp,
        Mechanic.rotor ||
        Mechanic.movingBlock ||
        Mechanic.laser ||
        Mechanic.crusher ||
        Mechanic.gravitySpikes ||
        Mechanic.meteors ||
        Mechanic.colorSpikes ||
        Mechanic.gravityLaser ||
        Mechanic.colorCrusher =>
          SegmentType.obstacle,
        Mechanic.wildcard || Mechanic.anchor || Mechanic.reverse || Mechanic.rainbow => SegmentType.collection,
        _ => null,
      };

  /// More endless segments; difficulty rises with distance.
  static List<SegmentSpec> endlessBatch(int virtualLevel, math.Random rng, SegmentType? last) {
    final m = mechanicsFor(virtualLevel).toSet();
    final palette = paletteFor(virtualLevel, 0, rng);
    final d = difficultyFor(virtualLevel);
    final weights = segmentWeights(virtualLevel, m, palette, d);
    final out = <SegmentSpec>[];
    for (var i = 0; i < 4; i++) {
      final t = pickSegment(weights, last, rng);
      out.add(SegmentSpec(t, length: segmentLength(t, d, rng), seed: rng.nextInt(1 << 30)));
      last = t;
    }
    return out;
  }

  // ------------------------------------------------------------ objectives
  static void assignObjectives(LevelConfig c, LevelPlan plan) {
    final coins = plan.ofKind(EntityKind.coin).length;
    final orbs = plan.ofKind(EntityKind.orb).length;
    final gates = plan.ofKind(EntityKind.gate).length;
    final mergeSegs = c.segments.where((s) => s.type == SegmentType.merge).length;
    final rng = math.Random(c.seed ^ 0x5eed);
    final level = c.levelId;

    if (c.kind == RunKind.endless) {
      c.objectives
        ..clear()
        ..add(const Objective(ObjectiveType.reachFinish));
      return;
    }

    // Mission levels add a required objective on top of reaching the finish.
    if (!c.tutorial && level % 5 == 0) {
      final options = <Objective>[
        Objective(ObjectiveType.collectCoins, target: math.max(5, (coins * 0.5).floor())),
        Objective(ObjectiveType.gravityShifts, target: math.min(12, 4 + level ~/ 60)),
        if (orbs >= 8) Objective(ObjectiveType.colorMatches, target: math.max(3, (orbs * 0.3).floor())),
        if (mergeSegs > 0 && c.has(Mechanic.merge)) Objective(ObjectiveType.merges, target: math.min(2, mergeSegs)),
        if (c.swipeEnabled && c.has(Mechanic.swipeVertical))
          const Objective(ObjectiveType.useGravity, target: 2, dir: GravityDir.up),
      ];
      c.objectives.add(options[rng.nextInt(options.length)]);
    }

    final star2Options = <Objective>[
      Objective(ObjectiveType.collectCoins, target: math.max(4, (coins * (0.5 + 0.3 * c.difficulty)).floor())),
      if (orbs >= 6) Objective(ObjectiveType.colorMatches, target: math.max(3, (orbs * 0.4).floor())),
      if (level >= 8) Objective(ObjectiveType.maxCombo, target: math.min(8, 3 + level ~/ 80)),
    ];
    final star3Options = <Objective>[
      const Objective(ObjectiveType.noCollision),
      if (level >= 12) Objective(ObjectiveType.perfectActions, target: math.min(10, 2 + (c.difficulty * 8).round())),
      if (gates >= 2 && level >= 20 && c.swipeEnabled)
        Objective(ObjectiveType.perfectShifts, target: math.min(4, 1 + level ~/ 200)),
      if (plan.ofKind(EntityKind.powerUp).isNotEmpty && level >= 25) const Objective(ObjectiveType.noPowerUps),
    ];
    c.starObjectives
      ..clear()
      ..add(c.tutorial
          ? Objective(ObjectiveType.collectCoins, target: math.max(3, (coins * 0.5).floor()))
          : star2Options[rng.nextInt(star2Options.length)])
      ..add(c.tutorial ? const Objective(ObjectiveType.noCollision) : star3Options[rng.nextInt(star3Options.length)]);
  }

  // --------------------------------------------------------------- loading
  static LoadedLevel load(int level) {
    for (var attempt = 0; attempt < 6; attempt++) {
      final c = configFor(level, attempt: attempt);
      final result = _buildAndValidate(c);
      if (result != null) return result;
    }
    return _fallback(level);
  }

  static LoadedLevel daily(DateTime date) {
    final key = date.year * 10000 + date.month * 100 + date.day;
    final rng = math.Random(key);
    final virtualLevel = 30 + rng.nextInt(170);
    final modifier = DailyModifier.values[rng.nextInt(DailyModifier.values.length)];
    for (var attempt = 0; attempt < 6; attempt++) {
      final c = configFor(virtualLevel, kind: RunKind.daily, modifier: modifier, seedOverride: key * 31 + attempt);
      final result = _buildAndValidate(c);
      if (result != null) {
        if (modifier == DailyModifier.coinRush) _doubleCoins(result);
        return result;
      }
    }
    return _fallback(virtualLevel, kind: RunKind.daily);
  }

  static void _doubleCoins(LoadedLevel l) {
    final extra = <Entity>[];
    for (final e in l.plan.entities.where((e) => e.kind == EntityKind.coin)) {
      final c = Entity(kind: EntityKind.coin, x: (e.x + 40).clamp(40, 320), r: 8, value: 1)..trackY = e.trackY + 16;
      extra.add(c);
    }
    l.plan.entities
      ..addAll(extra)
      ..sort((a, b) => a.trackY.compareTo(b.trackY));
  }

  static LoadedLevel endless(int seed) {
    final c = configFor(25, kind: RunKind.endless, seedOverride: seed);
    final b = SegmentBuilder(c);
    final plan = b.build();
    assignObjectives(c, plan);
    return LoadedLevel(c, plan, b);
  }

  static LoadedLevel? _buildAndValidate(LevelConfig c) {
    final b = SegmentBuilder(c);
    final plan = b.build();
    assignObjectives(c, plan);
    final report = LevelValidator.validate(c, plan);
    if (!report.ok) return null;
    return LoadedLevel(c, plan, b);
  }

  /// Guaranteed-safe configuration used if generation keeps failing validation.
  static LoadedLevel _fallback(int level, {RunKind kind = RunKind.level}) {
    final base = configFor(level, kind: kind);
    final c = LevelConfig(
      levelId: level,
      worldId: base.worldId,
      seed: base.seed,
      speed: base.speed,
      pathLength: 2000,
      startingColor: base.palette.first,
      startingGravity: GravityDir.down,
      palette: [base.palette.first],
      gravityMode: GravityMode.manual,
      gravityInterval: 6,
      smoothGravity: true,
      swipeEnabled: level > 1,
      segments: [
        SegmentSpec(SegmentType.start, length: 360, seed: base.seed),
        SegmentSpec(SegmentType.collection, length: 480, seed: base.seed + 1),
        SegmentSpec(SegmentType.reward, length: 380, seed: base.seed + 2),
        SegmentSpec(SegmentType.collection, length: 480, seed: base.seed + 3),
        SegmentSpec(SegmentType.finish, length: 300, seed: base.seed + 4),
      ],
      objectives: [const Objective(ObjectiveType.reachFinish)],
      starObjectives: [],
      baseReward: base.baseReward,
      difficulty: 0,
      mechanics: {Mechanic.drag, Mechanic.coins},
      objectPatterns: const ['line'],
      obstaclePatterns: const ['spikeRow'],
      gatePatterns: const [],
      powerUpPatterns: const [],
      kind: kind,
      fallback: true,
    );
    final b = SegmentBuilder(c);
    final plan = b.build();
    assignObjectives(c, plan);
    return LoadedLevel(c, plan, b);
  }
}
