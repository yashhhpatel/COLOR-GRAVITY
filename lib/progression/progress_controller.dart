import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/constants/app_config.dart';
import '../game/systems/scoring.dart';
import '../services/storage/storage_service.dart';
import 'achievements.dart';
import 'cosmetics.dart';
import 'save_data.dart';

/// Outcome of a finished run, shown on the result screen.
class RunReward {
  RunReward({
    required this.coins,
    required this.stars,
    required this.previousStars,
    required this.firstClear,
    required this.newBest,
    required this.unlocked,
  });
  int coins;
  final int stars;
  final int previousStars;
  final bool firstClear;
  final bool newBest;
  final List<Achievement> unlocked;
  bool doubled = false;
}

/// Owns progression: levels, stars, coins, cosmetics, achievements, daily
/// challenge and endless records. Persists with a short debounce.
class ProgressController extends ChangeNotifier {
  ProgressController(this._storage) : data = SaveData.fromJson(_storage.readJson(key));

  static const String key = 'cg_progress_v1';
  final StorageService _storage;
  SaveData data;
  Timer? _saveTimer;

  /// Achievements unlocked but not yet shown to the player.
  final List<Achievement> pendingToasts = [];

  int get coins => data.coins;
  int get unlockedLevel => data.unlockedLevel;
  Loadout get loadout => Loadout(skin: data.skin, trail: data.trail, gravityFx: data.gravityFx, mergeFx: data.mergeFx);

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), flush);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    await _storage.writeJson(key, data.toJson());
  }

  void completeOnboarding() {
    data.onboardingDone = true;
    _changed();
  }

  // --------------------------------------------------------------- runs
  void _accumulate(RunStats s) {
    data.addTotal(StatKeys.shifts, s.gravityShifts);
    data.addTotal(StatKeys.matches, s.colorMatches);
    data.addTotal(StatKeys.merges, s.merges);
    data.addTotal(StatKeys.perfect, s.perfectActions);
    data.addTotal(StatKeys.gates, s.gatesPassed);
    data.addTotal(StatKeys.runs, 1);
    data.maxTotal(StatKeys.bestCombo, s.maxCombo);
    data.maxTotal(StatKeys.maxMergeLevel, s.maxMergeLevel);
  }

  /// Records a level run. Failed runs still count toward lifetime stats.
  RunReward recordLevel(
      {required int level, required bool completed, required int stars, required RunStats stats, required int baseReward}) {
    _accumulate(stats);
    final prevStars = data.starsFor(level);
    final prevBest = data.bestScoreFor(level);
    var coins = 0;
    var firstClear = false;
    if (completed) {
      firstClear = prevStars == 0;
      data.setStars(level, stars);
      data.setBestScore(level, stats.score);
      if (stats.hits == 0) data.addTotal(StatKeys.perfectRuns, 1);
      final newStars = math.max(0, stars - prevStars);
      coins = stats.coins + (firstClear ? baseReward : baseReward ~/ 3) + newStars * 10;
      if (level >= data.unlockedLevel && level < AppConfig.totalLevels) data.unlockedLevel = level + 1;
    } else {
      coins = stats.coins ~/ 2; // keep half of what was collected
    }
    _earn(coins);
    final unlocked = _checkAchievements();
    _changed();
    return RunReward(
      coins: coins,
      stars: completed ? stars : 0,
      previousStars: prevStars,
      firstClear: firstClear,
      newBest: completed && stats.score > prevBest,
      unlocked: unlocked,
    );
  }

  static int dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  bool get dailyDoneToday => data.dailyLastCompleted == dayKey(DateTime.now());

  int get currentStreak {
    final today = DateTime.now();
    final yesterday = dayKey(today.subtract(const Duration(days: 1)));
    if (data.dailyLastCompleted == dayKey(today) || data.dailyLastCompleted == yesterday) return data.dailyStreak;
    return 0;
  }

  RunReward recordDaily({required bool completed, required RunStats stats, DateTime? now}) {
    _accumulate(stats);
    final today = dayKey(now ?? DateTime.now());
    final yesterday = dayKey((now ?? DateTime.now()).subtract(const Duration(days: 1)));
    var coins = stats.coins ~/ (completed ? 1 : 2);
    var firstClear = false;
    if (completed) {
      if (data.dailyLastCompleted != today) {
        firstClear = true;
        data.dailyStreak = data.dailyLastCompleted == yesterday ? data.dailyStreak + 1 : 1;
        data.dailyLastCompleted = today;
        coins += 100 + math.min(data.dailyStreak, 7) * 15;
      }
    }
    if (data.dailyBestDay != today) {
      data.dailyBestDay = today;
      data.dailyTodayBest = 0;
    }
    final newBest = stats.score > data.dailyTodayBest;
    data.dailyTodayBest = math.max(data.dailyTodayBest, stats.score);
    data.dailyBest = math.max(data.dailyBest, stats.score);
    _earn(coins);
    final unlocked = _checkAchievements();
    _changed();
    return RunReward(
        coins: coins, stars: completed ? 3 : 0, previousStars: 0, firstClear: firstClear, newBest: newBest, unlocked: unlocked);
  }

  RunReward recordEndless(RunStats stats) {
    _accumulate(stats);
    data.endlessRuns++;
    final newBest = stats.score > data.endlessBestScore;
    data.endlessBestScore = math.max(data.endlessBestScore, stats.score);
    data.endlessBestDistance = math.max(data.endlessBestDistance, stats.distance.round());
    data.endlessBestCombo = math.max(data.endlessBestCombo, stats.maxCombo);
    final coins = stats.coins + stats.distance ~/ 500;
    _earn(coins);
    final unlocked = _checkAchievements();
    _changed();
    return RunReward(coins: coins, stars: 0, previousStars: 0, firstClear: false, newBest: newBest, unlocked: unlocked);
  }

  /// Rewarded-ad doubling. Guarded so one reward can only be doubled once.
  void doubleReward(RunReward r) {
    if (r.doubled) return;
    r.doubled = true;
    _earn(r.coins);
    r.coins *= 2;
    _changed();
  }

  void _earn(int coins) {
    if (coins <= 0) return;
    data.coins += coins;
    data.addTotal(StatKeys.coinsEarned, coins);
  }

  void addCoins(int coins) {
    _earn(coins);
    _checkAchievements();
    _changed();
  }

  List<Achievement> _checkAchievements() {
    final out = <Achievement>[];
    for (final a in Achievements.all) {
      if (!data.achievements.contains(a.id) && a.done(data)) {
        data.achievements.add(a.id);
        data.coins += a.reward;
        out.add(a);
      }
    }
    pendingToasts.addAll(out);
    return out;
  }

  // ------------------------------------------------------------ cosmetics
  bool owns(Cosmetic c) => data.ownedCosmetics.contains(c.id);

  bool isEquipped(Cosmetic c) => switch (c.category) {
        CosmeticCategory.skin => data.skin == c.id,
        CosmeticCategory.trail => data.trail == c.id,
        CosmeticCategory.gravityFx => data.gravityFx == c.id,
        CosmeticCategory.mergeFx => data.mergeFx == c.id,
      };

  /// Buys (if affordable) and equips. Returns false when coins are short.
  bool buy(Cosmetic c) {
    if (owns(c)) {
      equip(c);
      return true;
    }
    if (data.coins < c.price) return false;
    data.coins -= c.price;
    data.ownedCosmetics = {...data.ownedCosmetics, c.id};
    equip(c);
    return true;
  }

  void equip(Cosmetic c) {
    if (!owns(c)) return;
    switch (c.category) {
      case CosmeticCategory.skin:
        data.skin = c.id;
      case CosmeticCategory.trail:
        data.trail = c.id;
      case CosmeticCategory.gravityFx:
        data.gravityFx = c.id;
      case CosmeticCategory.mergeFx:
        data.mergeFx = c.id;
    }
    _changed();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
