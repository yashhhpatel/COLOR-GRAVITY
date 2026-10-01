import 'package:color_gravity/core/models/game_color.dart';
import 'package:color_gravity/core/models/gravity_dir.dart';
import 'package:color_gravity/game/engine/game_engine.dart';
import 'package:color_gravity/game/entities/entity.dart';
import 'package:color_gravity/levels/generators/level_generator.dart';
import 'package:color_gravity/levels/models/level_config.dart';
import 'package:color_gravity/levels/segments/segment_builder.dart';

/// Builds a hand-made level for deterministic gameplay tests.
LoadedLevel testLevel(
  List<Entity> entities, {
  List<GameColor> palette = const [GameColor.red, GameColor.blue],
  GameColor start = GameColor.red,
  bool swipe = true,
  double speed = 150,
  int hearts = 3,
  GravityMode mode = GravityMode.manual,
  double interval = 4,
  bool smooth = false,
  List<Objective>? objectives,
  List<Objective>? stars,
  RunKind kind = RunKind.level,
}) {
  final config = LevelConfig(
    levelId: 50,
    worldId: 0,
    seed: 1,
    speed: speed,
    pathLength: 4000,
    startingColor: start,
    startingGravity: GravityDir.down,
    palette: palette,
    gravityMode: mode,
    gravityInterval: interval,
    smoothGravity: smooth,
    swipeEnabled: swipe,
    segments: const [SegmentSpec(SegmentType.start, length: 360, seed: 1)],
    objectives: objectives ?? [const Objective(ObjectiveType.reachFinish)],
    starObjectives: stars ?? [],
    baseReward: 20,
    difficulty: 0.2,
    mechanics: Mechanic.values.toSet(),
    objectPatterns: const ['line'],
    obstaclePatterns: const ['spikeRow'],
    gatePatterns: const ['plain'],
    powerUpPatterns: const ['shield'],
    hearts: hearts,
    kind: kind,
  );
  entities.sort((a, b) => a.trackY.compareTo(b.trackY));
  return LoadedLevel(config, LevelPlan(entities, 4000), SegmentBuilder(config));
}

/// Track position whose screen y equals [y] when nothing has scrolled yet.
double trackAtY(double y) => 640 - y;

Entity at(Entity e, double x, double y) {
  e
    ..x = x
    ..trackY = trackAtY(y);
  return e;
}

/// Runs the engine for [seconds] at 60 fps.
void run(GameEngine e, double seconds, {void Function()? each}) {
  final frames = (seconds * 60).round();
  for (var i = 0; i < frames; i++) {
    each?.call();
    e.update(1 / 60);
  }
}
