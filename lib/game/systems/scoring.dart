import 'dart:math' as math;

import '../../core/constants/game_constants.dart';
import '../../core/models/game_color.dart';
import '../../core/models/gravity_dir.dart';

/// Combo chain: consecutive good actions inside a time window.
class ComboSystem {
  int combo = 0;
  int best = 0;
  double timer = 0;

  int get multiplier => 1 + math.min(combo ~/ 4, 4);

  /// Returns true when the combo just reached a milestone worth announcing.
  bool hit() {
    combo++;
    timer = GameTiming.comboWindow;
    best = math.max(best, combo);
    return combo >= 2 && (combo == 2 || combo % 5 == 0 || combo == 3);
  }

  void breakCombo() {
    combo = 0;
    timer = 0;
  }

  void update(double dt) {
    if (combo == 0) return;
    timer -= dt;
    if (timer <= 0) breakCombo();
  }
}

/// Everything measured during a run; feeds objectives, stars, achievements.
class RunStats {
  int score = 0;
  int coins = 0;
  int orbsCollected = 0;
  int colorMatches = 0;
  int merges = 0;
  int chainMerges = 0;
  int maxMergeLevel = 1;
  int gravityShifts = 0;
  final Map<GravityDir, int> shiftsByDir = {for (final d in GravityDir.values) d: 0};
  int perfectShifts = 0;
  int perfectDodges = 0;
  int perfectGates = 0;
  int perfectMerges = 0;
  int perfectMatches = 0;
  int gatesPassed = 0;
  int hits = 0;
  int powerUpsUsed = 0;
  int maxCombo = 0;
  int deliveries = 0;
  double distance = 0;
  double time = 0;
  final List<GameColor> colorHistory = [];
  String? failReason;

  int get perfectActions => perfectShifts + perfectDodges + perfectGates + perfectMerges + perfectMatches;

  /// Snapshot used for checkpoints.
  RunStats copy() {
    final c = RunStats()
      ..score = score
      ..coins = coins
      ..orbsCollected = orbsCollected
      ..colorMatches = colorMatches
      ..merges = merges
      ..chainMerges = chainMerges
      ..maxMergeLevel = maxMergeLevel
      ..gravityShifts = gravityShifts
      ..perfectShifts = perfectShifts
      ..perfectDodges = perfectDodges
      ..perfectGates = perfectGates
      ..perfectMerges = perfectMerges
      ..perfectMatches = perfectMatches
      ..gatesPassed = gatesPassed
      ..hits = hits
      ..powerUpsUsed = powerUpsUsed
      ..maxCombo = maxCombo
      ..deliveries = deliveries
      ..distance = distance
      ..time = time;
    c.shiftsByDir.addAll(shiftsByDir);
    c.colorHistory.addAll(colorHistory);
    return c;
  }
}
