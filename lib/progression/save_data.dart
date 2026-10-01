import '../services/storage/storage_service.dart';
import 'cosmetics.dart';

/// Versioned player progress. Unknown / corrupt fields fall back to defaults.
class SaveData {
  static const int version = 1;

  bool onboardingDone = false;
  int unlockedLevel = 1;
  List<int> stars = []; // index = level - 1
  List<int> bestScores = [];
  int coins = 0;

  Set<String> ownedCosmetics = Cosmetics.defaults;
  String skin = Cosmetics.classic.id;
  String trail = Cosmetics.trailLight.id;
  String gravityFx = Cosmetics.gfxEnergy.id;
  String mergeFx = Cosmetics.mfxBurst.id;

  Set<String> achievements = {};

  // Daily challenge
  int dailyLastCompleted = 0; // yyyymmdd
  int dailyStreak = 0;
  int dailyBest = 0;
  int dailyBestDay = 0;
  int dailyTodayBest = 0;

  // Endless
  int endlessBestScore = 0;
  int endlessBestDistance = 0;
  int endlessBestCombo = 0;
  int endlessRuns = 0;

  // Lifetime stats
  Map<String, int> totals = {};

  // Daily missions (reset when the day changes)
  int missionDay = 0; // yyyymmdd
  Map<String, int> missionProgress = {};
  Set<String> missionClaimed = {};
  bool missionBonusClaimed = false;

  int total(String k) => totals[k] ?? 0;
  void addTotal(String k, int v) => totals[k] = total(k) + v;
  void maxTotal(String k, int v) {
    if (v > total(k)) totals[k] = v;
  }

  int starsFor(int level) => level - 1 < stars.length && level >= 1 ? stars[level - 1] : 0;
  int bestScoreFor(int level) => level - 1 < bestScores.length && level >= 1 ? bestScores[level - 1] : 0;

  void setStars(int level, int s) {
    while (stars.length < level) {
      stars.add(0);
    }
    if (s > stars[level - 1]) stars[level - 1] = s;
  }

  void setBestScore(int level, int s) {
    while (bestScores.length < level) {
      bestScores.add(0);
    }
    if (s > bestScores[level - 1]) bestScores[level - 1] = s;
  }

  int get totalStars => stars.fold(0, (a, b) => a + b);
  int get levelsCompleted => stars.where((s) => s > 0).length;
  int get threeStarLevels => stars.where((s) => s >= 3).length;

  Map<String, dynamic> toJson() => {
        'v': version,
        'onboardingDone': onboardingDone,
        'unlockedLevel': unlockedLevel,
        'stars': stars,
        'bestScores': bestScores,
        'coins': coins,
        'owned': ownedCosmetics.toList(),
        'skin': skin,
        'trail': trail,
        'gravityFx': gravityFx,
        'mergeFx': mergeFx,
        'achievements': achievements.toList(),
        'dailyLastCompleted': dailyLastCompleted,
        'dailyStreak': dailyStreak,
        'dailyBest': dailyBest,
        'dailyBestDay': dailyBestDay,
        'dailyTodayBest': dailyTodayBest,
        'endlessBestScore': endlessBestScore,
        'endlessBestDistance': endlessBestDistance,
        'endlessBestCombo': endlessBestCombo,
        'endlessRuns': endlessRuns,
        'totals': totals,
        'missionDay': missionDay,
        'missionProgress': missionProgress,
        'missionClaimed': missionClaimed.toList(),
        'missionBonusClaimed': missionBonusClaimed,
      };

  static SaveData fromJson(Map<String, dynamic>? m) {
    final d = SaveData();
    if (m == null) return d;
    // Future migrations: switch on Json.i(m, 'v', 1).
    d.onboardingDone = Json.b(m, 'onboardingDone', false);
    d.unlockedLevel = Json.i(m, 'unlockedLevel', 1).clamp(1, 1000);
    d.stars = Json.intList(m, 'stars').map((s) => s.clamp(0, 3)).toList();
    d.bestScores = Json.intList(m, 'bestScores').map((s) => s < 0 ? 0 : s).toList();
    d.coins = Json.i(m, 'coins', 0).clamp(0, 1 << 30);
    final owned = Json.strSet(m, 'owned');
    d.ownedCosmetics = {...Cosmetics.defaults, ...owned.where((id) => Cosmetics.all.any((c) => c.id == id))};
    String pick(String key, String fallback) {
      final v = Json.s(m, key);
      return v != null && d.ownedCosmetics.contains(v) ? v : fallback;
    }

    d.skin = pick('skin', Cosmetics.classic.id);
    d.trail = pick('trail', Cosmetics.trailLight.id);
    d.gravityFx = pick('gravityFx', Cosmetics.gfxEnergy.id);
    d.mergeFx = pick('mergeFx', Cosmetics.mfxBurst.id);
    d.achievements = Json.strSet(m, 'achievements');
    d.dailyLastCompleted = Json.i(m, 'dailyLastCompleted', 0);
    d.dailyStreak = Json.i(m, 'dailyStreak', 0);
    d.dailyBest = Json.i(m, 'dailyBest', 0);
    d.dailyBestDay = Json.i(m, 'dailyBestDay', 0);
    d.dailyTodayBest = Json.i(m, 'dailyTodayBest', 0);
    d.endlessBestScore = Json.i(m, 'endlessBestScore', 0);
    d.endlessBestDistance = Json.i(m, 'endlessBestDistance', 0);
    d.endlessBestCombo = Json.i(m, 'endlessBestCombo', 0);
    d.endlessRuns = Json.i(m, 'endlessRuns', 0);
    d.totals = Json.intMap(m, 'totals');
    d.missionDay = Json.i(m, 'missionDay', 0);
    d.missionProgress = Json.intMap(m, 'missionProgress');
    d.missionClaimed = Json.strSet(m, 'missionClaimed');
    d.missionBonusClaimed = Json.b(m, 'missionBonusClaimed', false);
    // Consistency: unlocked level is at least one past the furthest cleared.
    final furthest = d.stars.lastIndexWhere((s) => s > 0) + 1;
    if (furthest + 1 > d.unlockedLevel) d.unlockedLevel = (furthest + 1).clamp(1, 1000);
    return d;
  }
}
