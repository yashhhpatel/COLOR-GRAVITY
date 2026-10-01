import 'package:color_gravity/core/models/game_color.dart';
import 'package:color_gravity/core/models/gravity_dir.dart';
import 'package:color_gravity/game/systems/objective_system.dart';
import 'package:color_gravity/game/systems/scoring.dart';
import 'package:color_gravity/levels/models/level_config.dart';
import 'package:color_gravity/progression/achievements.dart';
import 'package:color_gravity/progression/cosmetics.dart';
import 'package:color_gravity/progression/progress_controller.dart';
import 'package:color_gravity/progression/save_data.dart';
import 'package:color_gravity/services/ads/ad_service.dart';
import 'package:color_gravity/services/monetization_controller.dart';
import 'package:color_gravity/services/purchases/purchase_service.dart';
import 'package:color_gravity/services/settings/settings_controller.dart';
import 'package:color_gravity/services/storage/storage_service.dart';
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

RunStats statsWith({int coins = 0, int score = 100, int hits = 0, int shifts = 0, int matches = 0, int merges = 0}) => RunStats()
  ..coins = coins
  ..score = score
  ..hits = hits
  ..gravityShifts = shifts
  ..colorMatches = matches
  ..merges = merges;

class FakeAds implements AdService {
  bool earn = true;
  int shown = 0;
  @override
  Future<void> init() async {}
  @override
  Future<void> showInterstitialIfDue({required bool adsRemoved}) async {
    if (!adsRemoved) shown++;
  }

  @override
  Future<bool> showRewarded() async => earn;
  @override
  bool get rewardedReady => true;
  @override
  Widget? banner({required bool adsRemoved}) => null;
  @override
  bool get privacyOptionsRequired => false;
  @override
  Future<void> showPrivacyOptions() async {}
}

class FakeStore implements PurchaseService {
  PurchaseOutcome next = PurchaseOutcome.success;
  Set<AdFreePlan> owned = {};
  String? price;
  @override
  void Function(AdFreePlan plan)? onEntitlement;
  @override
  Future<void> init() async {}
  @override
  bool get storeAvailable => true;
  @override
  String? priceOf(AdFreePlan plan) => price;
  @override
  Future<PurchaseOutcome> buy(AdFreePlan plan) async => next;
  @override
  Future<Set<AdFreePlan>> restore({bool silent = false}) async {
    for (final p in owned) {
      onEntitlement?.call(p);
    }
    return Set.of(owned);
  }

  @override
  void dispose() {}
}

void main() {
  group('Objectives & stars', () {
    test('progress and evaluation', () {
      final s = statsWith(coins: 7, shifts: 3)..shiftsByDir[GravityDir.up] = 2;
      expect(ObjectiveSystem.met(const Objective(ObjectiveType.collectCoins, target: 7), s), isTrue);
      expect(ObjectiveSystem.met(const Objective(ObjectiveType.collectCoins, target: 8), s), isFalse);
      expect(ObjectiveSystem.met(const Objective(ObjectiveType.useGravity, target: 2, dir: GravityDir.up), s), isTrue);
      expect(ObjectiveSystem.met(const Objective(ObjectiveType.noCollision), s), isTrue);
      s.hits = 1;
      expect(ObjectiveSystem.met(const Objective(ObjectiveType.noCollision), s), isFalse);
      s.colorHistory.addAll([GameColor.red, GameColor.blue, GameColor.red, GameColor.green]);
      expect(ObjectiveSystem.met(const Objective(ObjectiveType.colorSequence, sequence: [GameColor.blue, GameColor.green]), s),
          isTrue);
      expect(
          ObjectiveSystem.met(const Objective(ObjectiveType.finishWithColor, color: GameColor.green), s,
              finalColor: GameColor.green),
          isTrue);
    });

    test('stars = 1 + star objectives met', () {
      final lvl = testLevel([], stars: [
        const Objective(ObjectiveType.collectCoins, target: 5),
        const Objective(ObjectiveType.noCollision),
      ]);
      expect(ObjectiveSystem.stars(lvl.config, statsWith(coins: 0, hits: 1), GameColor.red), 1);
      expect(ObjectiveSystem.stars(lvl.config, statsWith(coins: 5, hits: 1), GameColor.red), 2);
      expect(ObjectiveSystem.stars(lvl.config, statsWith(coins: 5), GameColor.red), 3);
    });

    test('combo multiplier grows and expires', () {
      final c = ComboSystem();
      for (var i = 0; i < 8; i++) {
        c.hit();
      }
      expect(c.multiplier, 3);
      c.update(5);
      expect(c.combo, 0);
      expect(c.best, 8);
    });
  });

  group('Progression', () {
    test('completing a level unlocks the next and pays out once', () {
      final p = ProgressController(MemoryStorage());
      final r1 = p.recordLevel(level: 1, completed: true, stars: 2, stats: statsWith(coins: 5), baseReward: 20);
      expect(p.unlockedLevel, 2);
      expect(r1.firstClear, isTrue);
      expect(r1.coins, 5 + 20 + 20);
      expect(p.data.starsFor(1), 2);
      final r2 = p.recordLevel(level: 1, completed: true, stars: 3, stats: statsWith(coins: 0), baseReward: 20);
      expect(r2.firstClear, isFalse);
      expect(r2.coins, 20 ~/ 3 + 10);
      expect(p.data.starsFor(1), 3);
      p.recordLevel(level: 1, completed: true, stars: 1, stats: statsWith(), baseReward: 20);
      expect(p.data.starsFor(1), 3, reason: 'stars never decrease');
    });

    test('failed runs do not unlock levels', () {
      final p = ProgressController(MemoryStorage());
      p.recordLevel(level: 1, completed: false, stars: 0, stats: statsWith(coins: 6), baseReward: 20);
      expect(p.unlockedLevel, 1);
      expect(p.coins, 3);
    });

    test('rewarded doubling applies once', () {
      final p = ProgressController(MemoryStorage());
      final r = p.recordLevel(level: 1, completed: true, stars: 1, stats: statsWith(coins: 10), baseReward: 20);
      final before = p.coins;
      final earned = r.coins;
      p.doubleReward(r);
      p.doubleReward(r);
      expect(p.coins, before + earned);
      expect(r.coins, earned * 2);
    });

    test('achievements unlock from lifetime stats and grant coins', () {
      final p = ProgressController(MemoryStorage());
      final r =
          p.recordLevel(level: 1, completed: true, stars: 3, stats: statsWith(shifts: 1, matches: 1, merges: 1), baseReward: 0);
      final ids = r.unlocked.map((a) => a.id).toSet();
      expect(ids, containsAll(['first_shift', 'first_match', 'first_merge', 'perfect_run']));
      expect(p.data.achievements, containsAll(ids));
      final again = p.recordLevel(level: 2, completed: true, stars: 3, stats: statsWith(shifts: 1), baseReward: 0);
      expect(again.unlocked.where((a) => a.id == 'first_shift'), isEmpty);
      expect(Achievements.all.length, greaterThanOrEqualTo(11));
    });

    test('cosmetics: buy, equip, insufficient coins', () {
      final p = ProgressController(MemoryStorage());
      expect(p.owns(Cosmetics.classic), isTrue);
      expect(p.buy(Cosmetics.gold), isFalse);
      p.addCoins(5000);
      final coins = p.coins;
      expect(p.buy(Cosmetics.gold), isTrue);
      expect(p.coins, coins - Cosmetics.gold.price);
      expect(p.loadout.skin, Cosmetics.gold.id);
      expect(p.buy(Cosmetics.gold), isTrue, reason: 'owned items just equip');
      expect(p.coins, coins - Cosmetics.gold.price);
      p.equip(Cosmetics.classic);
      expect(p.isEquipped(Cosmetics.classic), isTrue);
    });

    test('daily streak counts consecutive days only', () {
      final p = ProgressController(MemoryStorage());
      p.recordDaily(completed: true, stats: statsWith(score: 50), now: DateTime(2026, 10, 1));
      expect(p.data.dailyStreak, 1);
      p.recordDaily(completed: true, stats: statsWith(score: 70), now: DateTime(2026, 10, 2));
      expect(p.data.dailyStreak, 2);
      final again = p.recordDaily(completed: true, stats: statsWith(score: 10), now: DateTime(2026, 10, 2));
      expect(again.firstClear, isFalse, reason: 'daily reward only once per day');
      p.recordDaily(completed: true, stats: statsWith(score: 5), now: DateTime(2026, 10, 5));
      expect(p.data.dailyStreak, 1);
      expect(p.data.dailyBest, 70);
    });

    test('endless bests', () {
      final p = ProgressController(MemoryStorage());
      final s = statsWith(score: 900)
        ..distance = 2400
        ..maxCombo = 9;
      final r = p.recordEndless(s);
      expect(r.newBest, isTrue);
      expect(p.data.endlessBestDistance, 2400);
      expect(p.recordEndless(statsWith(score: 10)).newBest, isFalse);
    });
  });

  group('Persistence & save safety', () {
    test('progress round-trips through storage', () async {
      final store = MemoryStorage();
      final p = ProgressController(store);
      p.recordLevel(level: 1, completed: true, stars: 3, stats: statsWith(coins: 4), baseReward: 20);
      p.addCoins(2000);
      p.buy(Cosmetics.neon);
      await p.flush();
      final q = ProgressController(store);
      expect(q.unlockedLevel, 2);
      expect(q.data.starsFor(1), 3);
      expect(q.coins, p.coins);
      expect(q.loadout.skin, Cosmetics.neon.id);
      expect(q.data.achievements, p.data.achievements);
    });

    test('corrupt or hostile data falls back to safe defaults', () {
      final store = MemoryStorage()..data[ProgressController.key] = '{not json';
      final p = ProgressController(store);
      expect(p.unlockedLevel, 1);
      expect(p.coins, 0);

      final d = SaveData.fromJson({
        'unlockedLevel': 'abc',
        'stars': [5, -2, 'x', 1],
        'coins': -50,
        'owned': ['skin_gold', 'hacked_item', 42],
        'skin': 'hacked_item',
        'totals': {'shifts': 'many', 'merges': 3},
      });
      expect(d.unlockedLevel, 5, reason: 'derived from furthest cleared level');
      expect(d.stars, [3, 0, 0, 1]);
      expect(d.coins, 0);
      expect(d.ownedCosmetics.contains('hacked_item'), isFalse);
      expect(d.ownedCosmetics.contains('skin_gold'), isTrue);
      expect(d.skin, Cosmetics.classic.id);
      expect(d.totals, {'merges': 3});
    });

    test('settings persist', () {
      final store = MemoryStorage();
      final s = SettingsController(store);
      expect(s.music, isTrue);
      s.music = false;
      s.vibration = false;
      s.gravityPad = true;
      final t = SettingsController(store);
      expect(t.music, isFalse);
      expect(t.vibration, isFalse);
      expect(t.gravityPad, isTrue);
      expect(t.sfx, isTrue);
    });
  });

  group('Monetization', () {
    test('two Ads-Free plans with INR prices (Play price wins when loaded)', () {
      final store = FakeStore();
      final m = MonetizationController(MemoryStorage(), FakeAds(), store);
      expect(AdFreePlan.values.length, 2);
      expect(m.priceOf(AdFreePlan.monthly), '₹299');
      expect(m.priceOf(AdFreePlan.lifetime), '₹2,999');
      expect(AdFreePlan.values.any((p) => m.priceOf(p).contains(r'$')), isFalse);
      store.price = '₹299.00';
      expect(m.priceOf(AdFreePlan.monthly), '₹299.00');
    });

    test('lifetime purchase persists and stops interstitials', () async {
      final storage = MemoryStorage();
      final ads = FakeAds();
      final m = MonetizationController(storage, ads, FakeStore());
      await m.naturalBreak();
      expect(ads.shown, 1);
      expect(await m.buy(AdFreePlan.lifetime), PurchaseOutcome.success);
      expect(m.adsRemoved, isTrue);
      expect(m.lifetimeOwned, isTrue);
      await m.naturalBreak();
      expect(ads.shown, 1);
      expect(MonetizationController(storage, ads, FakeStore()).adsRemoved, isTrue);
      expect(await m.buy(AdFreePlan.monthly), PurchaseOutcome.alreadyOwned);
    });

    test('monthly plan lasts a month, then ads return unless renewed', () async {
      var now = DateTime(2026, 10, 1);
      final storage = MemoryStorage();
      final store = FakeStore();
      final m = MonetizationController(storage, FakeAds(), store, clock: () => now);
      expect(await m.buy(AdFreePlan.monthly), PurchaseOutcome.success);
      expect(m.monthlyActive, isTrue);
      expect(await m.buy(AdFreePlan.monthly), PurchaseOutcome.alreadyOwned);
      now = DateTime(2026, 10, 20);
      expect(MonetizationController(storage, FakeAds(), FakeStore(), clock: () => now).adsRemoved, isTrue);
      now = DateTime(2026, 11, 2);
      expect(m.adsRemoved, isFalse, reason: 'expired without a confirmed renewal');
      // Google Play still reports the subscription active (renewed) → re-granted.
      store.owned = {AdFreePlan.monthly};
      expect(await m.restore(), {AdFreePlan.monthly});
      expect(m.adsRemoved, isTrue);
    });

    test('cancelled, pending and failed purchases grant nothing', () async {
      final store = FakeStore()..next = PurchaseOutcome.cancelled;
      final m = MonetizationController(MemoryStorage(), FakeAds(), store);
      expect(await m.buy(AdFreePlan.lifetime), PurchaseOutcome.cancelled);
      store.next = PurchaseOutcome.pending;
      expect(await m.buy(AdFreePlan.monthly), PurchaseOutcome.pending);
      store.next = PurchaseOutcome.failed;
      expect(await m.buy(AdFreePlan.lifetime), PurchaseOutcome.failed);
      expect(m.adsRemoved, isFalse);
    });

    test('already-purchased and pending-then-confirmed grant the plan', () async {
      final store = FakeStore()..next = PurchaseOutcome.alreadyOwned;
      final m = MonetizationController(MemoryStorage(), FakeAds(), store);
      expect(await m.buy(AdFreePlan.lifetime), PurchaseOutcome.alreadyOwned);
      expect(m.lifetimeOwned, isTrue);

      final store2 = FakeStore()..next = PurchaseOutcome.pending;
      final m2 = MonetizationController(MemoryStorage(), FakeAds(), store2);
      await m2.buy(AdFreePlan.lifetime);
      expect(m2.adsRemoved, isFalse);
      store2.onEntitlement!(AdFreePlan.lifetime); // Play confirms later on the stream
      expect(m2.adsRemoved, isTrue);
    });

    test('restore grants previously owned plans', () async {
      final store = FakeStore()..owned = {AdFreePlan.lifetime};
      final m = MonetizationController(MemoryStorage(), FakeAds(), store);
      expect(await m.restore(), {AdFreePlan.lifetime});
      expect(m.lifetimeOwned, isTrue);
      final empty = MonetizationController(MemoryStorage(), FakeAds(), FakeStore());
      expect(await empty.restore(), isEmpty);
      expect(empty.adsRemoved, isFalse);
    });

    test('v1 save (removeAds) migrates to lifetime', () {
      final storage = MemoryStorage()..data[MonetizationController.key] = '{"v":1,"removeAds":true}';
      expect(MonetizationController(storage, FakeAds(), FakeStore()).lifetimeOwned, isTrue);
    });

    test('rewarded grant runs only when earned', () async {
      final ads = FakeAds();
      final m = MonetizationController(MemoryStorage(), ads, FakeStore());
      var grants = 0;
      await m.rewarded(() => grants++);
      ads.earn = false;
      await m.rewarded(() => grants++);
      expect(grants, 1);
    });
  });
}
