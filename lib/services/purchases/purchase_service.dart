import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/constants/app_config.dart';

enum PurchaseOutcome { success, pending, cancelled, failed, unavailable, alreadyOwned }

/// The two Ads-Free plans sold through Google Play Billing.
enum AdFreePlan {
  /// Auto-renewing monthly subscription.
  monthly(AppConfig.adsFreeMonthlyProductId, '1 Month Ads-Free', AppConfig.adsFreeMonthlyPrice),

  /// One-time (non-consumable) lifetime purchase.
  lifetime(AppConfig.adsFreeLifetimeProductId, 'Lifetime Ads-Free', AppConfig.adsFreeLifetimePrice);

  const AdFreePlan(this.productId, this.title, this.listedPrice);
  final String productId;
  final String title;

  /// Price shown until Google Play returns the localized price.
  final String listedPrice;

  static AdFreePlan? byProductId(String id) {
    for (final p in AdFreePlan.values) {
      if (p.productId == id) return p;
    }
    return null;
  }
}

/// Google Play Billing for the Ads-Free plans.
abstract class PurchaseService {
  Future<void> init();

  bool get storeAvailable;

  /// Localized price from Google Play, or null when not loaded.
  String? priceOf(AdFreePlan plan);

  Future<PurchaseOutcome> buy(AdFreePlan plan);

  /// Re-queries owned purchases / active subscriptions. Returns the plans found.
  /// [silent] restores run at startup to refresh subscription status.
  Future<Set<AdFreePlan>> restore({bool silent = false});

  /// Called whenever ownership of a plan is confirmed by Google Play.
  void Function(AdFreePlan plan)? onEntitlement;

  void dispose();
}

class NoPurchaseService implements PurchaseService {
  @override
  void Function(AdFreePlan plan)? onEntitlement;
  @override
  Future<void> init() async {}
  @override
  bool get storeAvailable => false;
  @override
  String? priceOf(AdFreePlan plan) => null;
  @override
  Future<PurchaseOutcome> buy(AdFreePlan plan) async => PurchaseOutcome.unavailable;
  @override
  Future<Set<AdFreePlan>> restore({bool silent = false}) async => {};
  @override
  void dispose() {}
}

class PlayPurchaseService implements PurchaseService {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final Map<AdFreePlan, ProductDetails> _products = {};
  bool _available = false;
  final Map<AdFreePlan, Completer<PurchaseOutcome>> _buying = {};
  final Set<AdFreePlan> _restored = {};

  @override
  void Function(AdFreePlan plan)? onEntitlement;

  @override
  bool get storeAvailable => _available && _products.isNotEmpty;

  @override
  String? priceOf(AdFreePlan plan) => _products[plan]?.price;

  @override
  Future<void> init() async {
    try {
      _available = await _iap.isAvailable();
      if (!_available) return;
      _sub = _iap.purchaseStream.listen(_onPurchases, onError: (Object e) => debugPrint('IAP stream error: $e'));
      final resp = await _iap.queryProductDetails({for (final p in AdFreePlan.values) p.productId});
      for (final d in resp.productDetails) {
        final plan = AdFreePlan.byProductId(d.id);
        // Subscriptions can return one entry per offer; keep the first.
        if (plan != null) _products.putIfAbsent(plan, () => d);
      }
      if (resp.notFoundIDs.isNotEmpty) debugPrint('IAP products not found: ${resp.notFoundIDs}');
      // Refresh entitlements (active subscription / lifetime) without UI.
      await restore(silent: true);
    } catch (e) {
      _available = false;
      debugPrint('IAP unavailable: $e');
    }
  }

  @override
  Future<PurchaseOutcome> buy(AdFreePlan plan) async {
    final p = _products[plan];
    if (!_available || p == null) return PurchaseOutcome.unavailable;
    final existing = _buying[plan];
    if (existing != null && !existing.isCompleted) return existing.future;
    final c = Completer<PurchaseOutcome>();
    _buying[plan] = c;
    try {
      // Both the subscription and the lifetime unlock are non-consumables.
      final started = await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: p));
      if (!started && !c.isCompleted) c.complete(PurchaseOutcome.failed);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (!c.isCompleted) {
        if (msg.contains('owned')) {
          onEntitlement?.call(plan);
          c.complete(PurchaseOutcome.alreadyOwned);
        } else {
          c.complete(PurchaseOutcome.failed);
        }
      }
    }
    return c.future.timeout(const Duration(minutes: 5), onTimeout: () => PurchaseOutcome.pending);
  }

  @override
  Future<Set<AdFreePlan>> restore({bool silent = false}) async {
    if (!_available) return {};
    _restored.clear();
    try {
      await _iap.restorePurchases();
      // Restored purchases arrive asynchronously on the purchase stream.
      await Future<void>.delayed(Duration(seconds: silent ? 2 : 3));
    } catch (e) {
      debugPrint('Restore failed: $e');
    }
    return Set.of(_restored);
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      final plan = AdFreePlan.byProductId(p.productID);
      if (plan == null) continue;
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _restored.add(plan);
          onEntitlement?.call(plan);
          _finish(plan, PurchaseOutcome.success);
        case PurchaseStatus.pending:
          _finish(plan, PurchaseOutcome.pending);
        case PurchaseStatus.canceled:
          _finish(plan, PurchaseOutcome.cancelled);
        case PurchaseStatus.error:
          final already = (p.error?.message ?? '').toLowerCase().contains('owned');
          if (already) onEntitlement?.call(plan);
          _finish(plan, already ? PurchaseOutcome.alreadyOwned : PurchaseOutcome.failed);
      }
      if (p.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(p); // acknowledges the purchase on Play
        } catch (e) {
          debugPrint('completePurchase failed: $e');
        }
      }
    }
  }

  void _finish(AdFreePlan plan, PurchaseOutcome o) {
    final c = _buying[plan];
    if (c != null && !c.isCompleted) c.complete(o);
  }

  @override
  void dispose() => _sub?.cancel();
}
