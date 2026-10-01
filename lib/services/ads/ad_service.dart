import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/constants/app_config.dart';

/// Advertising, isolated from gameplay. Ads are only ever requested from
/// menus / result screens — never while a run is active.
abstract class AdService {
  Future<void> init();

  /// Interstitial at a natural break (respects Remove Ads + frequency cap).
  Future<void> showInterstitialIfDue({required bool adsRemoved});

  /// Rewarded ad. Completes `true` exactly once if the user earned the reward.
  Future<bool> showRewarded();

  bool get rewardedReady;

  /// Banner for non-gameplay screens; null when unavailable or removed.
  Widget? banner({required bool adsRemoved});

  /// True when the user must be offered a way to change ad consent (EEA/UK).
  bool get privacyOptionsRequired;

  /// Re-opens Google's consent (UMP) privacy options form.
  Future<void> showPrivacyOptions();
}

class NoAdService implements AdService {
  @override
  Future<void> init() async {}
  @override
  Future<void> showInterstitialIfDue({required bool adsRemoved}) async {}
  @override
  Future<bool> showRewarded() async => false;
  @override
  bool get rewardedReady => false;
  @override
  Widget? banner({required bool adsRemoved}) => null;
  @override
  bool get privacyOptionsRequired => false;
  @override
  Future<void> showPrivacyOptions() async {}
}

class AdMobService implements AdService {
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _initialized = false;
  int _breaks = 0;
  bool _loadingRewarded = false;
  bool _privacyOptionsRequired = false;

  @override
  bool get privacyOptionsRequired => _privacyOptionsRequired;

  /// Google UMP: asks EEA/UK users for ad consent before any ad request.
  Future<void> _gatherConsent() async {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((FormError? e) {
          if (e != null) debugPrint('Consent form: ${e.message}');
          if (!done.isCompleted) done.complete();
        });
      },
      (FormError e) {
        debugPrint('Consent info update failed: ${e.message}');
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    _privacyOptionsRequired =
        await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() == PrivacyOptionsRequirementStatus.required;
  }

  @override
  Future<void> showPrivacyOptions() async {
    final done = Completer<void>();
    await ConsentForm.showPrivacyOptionsForm((FormError? e) {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
  }

  @override
  Future<void> init() async {
    try {
      await _gatherConsent();
      if (!await ConsentInformation.instance.canRequestAds()) {
        debugPrint('Ads: no consent to request ads');
        return;
      }
      await MobileAds.instance.initialize();
      _initialized = true;
      _loadInterstitial();
      _loadRewarded();
    } catch (e) {
      debugPrint('Ads unavailable: $e');
    }
  }

  void _loadInterstitial() {
    if (!_initialized) return;
    InterstitialAd.load(
      adUnitId: AppConfig.admobInterstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (err) {
          _interstitial = null;
          debugPrint('Interstitial failed: ${err.message}');
        },
      ),
    );
  }

  void _loadRewarded() {
    if (!_initialized || _loadingRewarded || _rewarded != null) return;
    _loadingRewarded = true;
    RewardedAd.load(
      adUnitId: AppConfig.admobRewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingRewarded = false;
          _rewarded = ad;
        },
        onAdFailedToLoad: (err) {
          _loadingRewarded = false;
          _rewarded = null;
          debugPrint('Rewarded failed: ${err.message}');
        },
      ),
    );
  }

  @override
  Future<void> showInterstitialIfDue({required bool adsRemoved}) async {
    if (adsRemoved) return;
    _breaks++;
    if (_breaks < AppConfig.interstitialEveryRuns) return;
    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return;
    }
    _breaks = 0;
    _interstitial = null;
    final done = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
        if (!done.isCompleted) done.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        _loadInterstitial();
        if (!done.isCompleted) done.complete();
      },
    );
    await ad.show();
    await done.future.timeout(const Duration(minutes: 2), onTimeout: () {});
  }

  @override
  bool get rewardedReady => _rewarded != null;

  @override
  Future<bool> showRewarded() async {
    final ad = _rewarded;
    if (ad == null) {
      _loadRewarded();
      return false;
    }
    _rewarded = null;
    var earned = false;
    final done = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
        if (!done.isCompleted) done.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        _loadRewarded();
        if (!done.isCompleted) done.complete(false);
      },
    );
    await ad.show(onUserEarnedReward: (_, __) => earned = true);
    return done.future.timeout(const Duration(minutes: 3), onTimeout: () => earned);
  }

  @override
  Widget? banner({required bool adsRemoved}) {
    if (adsRemoved || !_initialized) return null;
    return const _BannerSlot();
  }
}

class _BannerSlot extends StatefulWidget {
  const _BannerSlot();
  @override
  State<_BannerSlot> createState() => _BannerSlotState();
}

class _BannerSlotState extends State<_BannerSlot> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = BannerAd(
      adUnitId: AppConfig.admobBannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
          _ad = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: _ad!.size.width.toDouble(),
      height: _ad!.size.height.toDouble(),
      child: AdWidget(ad: _ad!),
    );
  }
}
