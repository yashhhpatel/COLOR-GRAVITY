import 'package:flutter/foundation.dart';

import 'ads/ad_service.dart';
import 'purchases/purchase_service.dart';
import 'storage/storage_service.dart';

/// Owns the Ads-Free entitlement (monthly subscription or lifetime) and
/// mediates ads/purchases. Ads-Free only affects advertising — never gameplay.
class MonetizationController extends ChangeNotifier {
  MonetizationController(this._storage, this.ads, this.purchases, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    final m = _storage.readJson(key) ?? const {};
    // `removeAds` is the v1 field name for the lifetime unlock.
    _lifetime = Json.b(m, 'lifetime', Json.b(m, 'removeAds', false));
    _monthlyUntil = Json.i(m, 'monthlyUntil', 0);
    purchases.onEntitlement = grant;
  }

  static const String key = 'cg_monetization_v1';

  /// A month of Ads-Free from purchase; renewals are re-confirmed by the
  /// silent restore on every launch (which extends the window).
  static const Duration monthlyPeriod = Duration(days: 30);
  static const Duration renewalGrace = Duration(days: 3);

  final StorageService _storage;
  final AdService ads;
  final PurchaseService purchases;
  final DateTime Function() _clock;
  late bool _lifetime;
  late int _monthlyUntil; // epoch ms

  bool get lifetimeOwned => _lifetime;
  DateTime? get monthlyUntil => _monthlyUntil == 0 ? null : DateTime.fromMillisecondsSinceEpoch(_monthlyUntil);
  bool get monthlyActive => _monthlyUntil > _clock().millisecondsSinceEpoch;
  bool get adsRemoved => _lifetime || monthlyActive;

  void grant(AdFreePlan plan) {
    switch (plan) {
      case AdFreePlan.lifetime:
        if (_lifetime) return;
        _lifetime = true;
      case AdFreePlan.monthly:
        final now = _clock();
        final candidate = now.add(monthlyPeriod).millisecondsSinceEpoch;
        // A confirmed active subscription keeps the window at least `grace` ahead.
        final refreshed = now.add(renewalGrace).millisecondsSinceEpoch;
        final next = _monthlyUntil > refreshed ? _monthlyUntil : (monthlyActive ? refreshed : candidate);
        if (next == _monthlyUntil) return;
        _monthlyUntil = next;
    }
    _save();
    notifyListeners();
  }

  void _save() => _storage.writeJson(key, {'v': 2, 'lifetime': _lifetime, 'monthlyUntil': _monthlyUntil});

  Future<void> naturalBreak() => ads.showInterstitialIfDue(adsRemoved: adsRemoved);

  /// Shows a rewarded ad; [grantReward] runs at most once, only if earned.
  Future<bool> rewarded(VoidCallback grantReward) async {
    final earned = await ads.showRewarded();
    if (earned) grantReward();
    return earned;
  }

  /// Price label: Google Play's localized price, else the listed INR price.
  String priceOf(AdFreePlan plan) => purchases.priceOf(plan) ?? plan.listedPrice;

  Future<PurchaseOutcome> buy(AdFreePlan plan) async {
    if (_lifetime) return PurchaseOutcome.alreadyOwned;
    if (plan == AdFreePlan.monthly && monthlyActive) return PurchaseOutcome.alreadyOwned;
    final o = await purchases.buy(plan);
    if (o == PurchaseOutcome.success || o == PurchaseOutcome.alreadyOwned) grant(plan);
    notifyListeners();
    return o;
  }

  /// Returns the plans Google Play reports as owned / active.
  Future<Set<AdFreePlan>> restore() async {
    final found = await purchases.restore();
    for (final p in found) {
      grant(p);
    }
    notifyListeners();
    return found;
  }
}
