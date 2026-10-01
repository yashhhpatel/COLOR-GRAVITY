import '../../core/models/game_color.dart';
import '../../core/models/gravity_dir.dart';

enum SegmentType {
  start,
  gravity,
  color,
  collection,
  merge,
  gravityShift,
  colorGate,
  obstacle,
  riskReward,
  powerUp,
  challenge,
  reward,
  finish,
}

/// Mechanics are unlocked progressively; the generator only uses unlocked ones.
enum Mechanic {
  drag(1, 'Drag to steer'),
  spikes(1, 'Spikes'),
  coins(1, 'Coins'),
  swipeSide(2, 'Swipe ← → to shift gravity'),
  swipeVertical(2, 'Swipe ↑ ↓ to shift gravity'),
  gravityGap(2, 'Gravity Gap'),
  colors(3, 'Colors'),
  colorSwitch(3, 'Color Switch'),
  colorGate(3, 'Color Gate'),
  merge(4, 'Combine'),
  movingBlock(6, 'Moving Blocks'),
  rotor(8, 'Gravity Rotor'),
  powerUps(10, 'Power-ups'),
  gravitySwitch(11, 'Gravity Switch'),
  gravityWall(12, 'Gravity Wall'),
  gravityGate(14, 'Gravity Gate'),
  colorSpikes(15, 'Color Hazard'),
  laser(18, 'Lasers'),
  basin(20, 'Color Basin'),
  mergeZone(22, 'Gravity Merge Zone'),
  gravitySpikes(25, 'Gravity Spikes'),
  gravityZone(31, 'Gravity Zone'),
  riskReward(35, 'Risk / Reward'),
  crusher(38, 'Gravity Crusher'),
  meteors(42, 'Falling Meteors'),
  gravityLock(45, 'Gravity Lock'),
  colorGravityGate(51, 'Color + Gravity Gate'),
  multiColorGate(55, 'Multi-Color Gate'),
  colorTrigger(60, 'Gravity Color Switch'),
  colorBarrier(65, 'Color Barrier'),
  gravityLaser(70, 'Gravity Laser'),
  colorCrusher(75, 'Color Crusher'),
  wildcard(101, 'Wildcard Orb'),
  bomb(105, 'Bomb'),
  anchor(110, 'Anchor Orb'),
  reverse(115, 'Reverse Orb'),
  gravityCore(120, 'Gravity Core'),
  colorCore(125, 'Color Core'),
  gravityBomb(130, 'Gravity Bomb'),
  rainbow(140, 'Rainbow Orb'),
  reversingGravity(150, 'Reversing Gravity'),
  rotatingGravity(200, 'Rotating Gravity'),
  rapidGravity(300, 'Rapid Gravity'),
  sixColors(601, 'Cyan joins the palette');

  const Mechanic(this.unlockLevel, this.title);
  final int unlockLevel;
  final String title;
}

enum ObjectiveType {
  reachFinish,
  collectOrbs,
  colorMatches,
  merges,
  targetScore,
  gravityShifts,
  useGravity,
  noCollision,
  finishWithColor,
  colorSequence,
  perfectShifts,
  noPowerUps,
  collectCoins,
  perfectActions,
  maxCombo,
}

class Objective {
  const Objective(this.type, {this.target = 0, this.color, this.dir, this.sequence});

  final ObjectiveType type;
  final int target;
  final GameColor? color;
  final GravityDir? dir;
  final List<GameColor>? sequence;

  String describe() => switch (type) {
        ObjectiveType.reachFinish => 'Reach the finish',
        ObjectiveType.collectOrbs => color == null ? 'Collect $target orbs' : 'Collect $target ${color!.label} orbs',
        ObjectiveType.colorMatches => 'Make $target color matches',
        ObjectiveType.merges => 'Combine $target times',
        ObjectiveType.targetScore => 'Score $target',
        ObjectiveType.gravityShifts => 'Shift gravity $target times',
        ObjectiveType.useGravity => 'Shift gravity ${dir!.arrow} $target times',
        ObjectiveType.noCollision => 'No collisions',
        ObjectiveType.finishWithColor => 'Finish as ${color!.label}',
        ObjectiveType.colorSequence => 'Become ${sequence!.map((c) => c.label).join(' → ')}',
        ObjectiveType.perfectShifts => '$target perfect gravity shifts',
        ObjectiveType.noPowerUps => 'Finish without power-ups',
        ObjectiveType.collectCoins => 'Collect $target coins',
        ObjectiveType.perfectActions => '$target perfect actions',
        ObjectiveType.maxCombo => 'Reach a x$target combo',
      };
}

enum GravityMode { manual, reversing, rotating }

/// Broad difficulty bands across the 1000 levels.
enum DifficultyTier {
  easy('Easy', 1, 120, 0xFF39E09B),
  medium('Medium', 121, 400, 0xFFFFC93D),
  hard('Hard', 401, 700, 0xFFFF8A4D),
  veryHard('Very Hard', 701, 1000, 0xFFFF5470);

  const DifficultyTier(this.label, this.first, this.last, this.argb);
  final String label;
  final int first;
  final int last;
  final int argb;

  /// 0..1 position of [level] inside this tier.
  double progressOf(int level) => ((level - first) / (last - first)).clamp(0.0, 1.0);

  static DifficultyTier forLevel(int level) {
    for (final t in DifficultyTier.values) {
      if (level <= t.last) return t;
    }
    return DifficultyTier.veryHard;
  }
}

enum RunKind { level, daily, endless }

enum DailyModifier {
  none('Classic', 'A fresh daily run'),
  fast('Overdrive', 'Everything moves 25% faster'),
  rotating('Spin Cycle', 'Gravity rotates on its own'),
  glass('Glass Orb', 'One heart only'),
  coinRush('Coin Rush', 'Twice the coins on the track'),
  mono('Mono', 'Only two colors');

  const DailyModifier(this.title, this.description);
  final String title;
  final String description;
}

class SegmentSpec {
  const SegmentSpec(this.type, {required this.length, required this.seed});
  final SegmentType type;
  final double length;
  final int seed;
}

/// Data-driven description of a level. 1000+ levels are produced by the
/// generator from this structure; nothing is hard-coded per level.
class LevelConfig {
  LevelConfig({
    required this.levelId,
    required this.worldId,
    required this.seed,
    required this.speed,
    required this.pathLength,
    required this.startingColor,
    required this.startingGravity,
    required this.palette,
    required this.gravityMode,
    required this.gravityInterval,
    required this.smoothGravity,
    required this.swipeEnabled,
    required this.segments,
    required this.objectives,
    required this.starObjectives,
    required this.baseReward,
    required this.difficulty,
    required this.mechanics,
    required this.objectPatterns,
    required this.obstaclePatterns,
    required this.gatePatterns,
    required this.powerUpPatterns,
    this.hearts = 3,
    this.kind = RunKind.level,
    this.modifier = DailyModifier.none,
    this.tutorial = false,
    this.fallback = false,
  });

  final int levelId;
  final int worldId;
  final int seed;
  final double speed;
  final double pathLength;
  final GameColor startingColor;
  final GravityDir startingGravity;
  final List<GameColor> palette;
  final GravityMode gravityMode;
  final double gravityInterval;
  final bool smoothGravity;
  final bool swipeEnabled;
  final List<SegmentSpec> segments;

  /// Required to complete the run (besides surviving).
  final List<Objective> objectives;

  /// [0] → 2nd star, [1] → 3rd star.
  final List<Objective> starObjectives;
  final int baseReward;
  final double difficulty; // 0..1
  final Set<Mechanic> mechanics;
  final List<String> objectPatterns;
  final List<String> obstaclePatterns;
  final List<String> gatePatterns;
  final List<String> powerUpPatterns;
  final int hearts;
  final RunKind kind;
  final DailyModifier modifier;
  final bool tutorial;
  final bool fallback;

  DifficultyTier get tier => DifficultyTier.forLevel(levelId);

  /// Every 10th level is a tougher "challenge" level.
  bool get isChallengeLevel => kind == RunKind.level && levelId % 10 == 0 && !tutorial;

  bool has(Mechanic m) => mechanics.contains(m);
}
