import '../../core/models/game_color.dart';
import '../../levels/models/level_config.dart';
import 'scoring.dart';

/// Evaluates objectives and star rules against a run's stats.
class ObjectiveSystem {
  static (int current, int target) progress(Objective o, RunStats s, {GameColor? finalColor, bool finished = false}) {
    return switch (o.type) {
      ObjectiveType.reachFinish => (finished ? 1 : 0, 1),
      ObjectiveType.collectOrbs => (s.orbsCollected, o.target),
      ObjectiveType.colorMatches => (s.colorMatches, o.target),
      ObjectiveType.merges => (s.merges, o.target),
      ObjectiveType.targetScore => (s.score, o.target),
      ObjectiveType.gravityShifts => (s.gravityShifts, o.target),
      ObjectiveType.useGravity => (s.shiftsByDir[o.dir] ?? 0, o.target),
      ObjectiveType.noCollision => (s.hits == 0 ? 1 : 0, 1),
      ObjectiveType.finishWithColor => (finished && finalColor == o.color ? 1 : 0, 1),
      ObjectiveType.colorSequence => (_sequenceProgress(o.sequence ?? const [], s.colorHistory), (o.sequence ?? const []).length),
      ObjectiveType.perfectShifts => (s.perfectShifts, o.target),
      ObjectiveType.noPowerUps => (s.powerUpsUsed == 0 ? 1 : 0, 1),
      ObjectiveType.collectCoins => (s.coins, o.target),
      ObjectiveType.perfectActions => (s.perfectActions, o.target),
      ObjectiveType.maxCombo => (s.maxCombo, o.target),
    };
  }

  static bool met(Objective o, RunStats s, {GameColor? finalColor, bool finished = true}) {
    final (cur, target) = progress(o, s, finalColor: finalColor, finished: finished);
    return cur >= target;
  }

  /// Longest prefix of [seq] found as a subsequence of [history].
  static int _sequenceProgress(List<GameColor> seq, List<GameColor> history) {
    var i = 0;
    for (final c in history) {
      if (i < seq.length && seq[i] == c) i++;
    }
    return i;
  }

  /// Required objectives other than reaching the finish that are not met.
  static List<Objective> unmetRequired(LevelConfig c, RunStats s, GameColor finalColor) =>
      c.objectives.where((o) => o.type != ObjectiveType.reachFinish && !met(o, s, finalColor: finalColor)).toList();

  /// 1 star for completing, +1 per star objective met.
  static int stars(LevelConfig c, RunStats s, GameColor finalColor) {
    var stars = 1;
    for (final o in c.starObjectives) {
      if (met(o, s, finalColor: finalColor)) stars++;
    }
    return stars.clamp(1, 3);
  }
}
