/// App-level configuration. Replace placeholders before publishing.
class AppConfig {
  static const String appName = 'Color Gravity';
  static const String androidPackage = 'com.colorgravity.app';

  // Monetization -----------------------------------------------------------
  /// Google Play product ids for the two Ads-Free plans. Create them in Play
  /// Console with these exact ids:
  ///  * `ads_free_monthly`  — auto-renewing subscription, 1 month, ₹299
  ///  * `ads_free_lifetime` — one-time (non-consumable) product, ₹2,999
  static const String adsFreeMonthlyProductId = 'ads_free_monthly';
  static const String adsFreeLifetimeProductId = 'ads_free_lifetime';

  /// Listed prices, shown until Google Play returns the localized price.
  static const String adsFreeMonthlyPrice = '₹299';
  static const String adsFreeLifetimePrice = '₹2,999';

  /// AdMob unit ids. These are Google's public TEST ids; swap them for real
  /// ids (and the APPLICATION_ID in AndroidManifest.xml) before release.
  static const String admobBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const String admobInterstitialId = 'ca-app-pub-3940256099942544/1033173712';
  static const String admobRewardedId = 'ca-app-pub-3940256099942544/5224354917';

  /// Show an interstitial at most every N completed runs (natural breaks only).
  static const int interstitialEveryRuns = 3;

  // Links -------------------------------------------------------------------
  static const String privacyPolicyUrl = 'https://api.buildprivacypolicy.com/policy/5e19d9a2-9943-4f01-a8ee-ff62e3d67f1f';
  static const String contactEmail = 'aakashmangukiya10@gmail.com';
  static const String storeUrl = 'https://play.google.com/store/apps/details?id=$androidPackage';

  // Game --------------------------------------------------------------------
  static const int totalLevels = 1000;
  static const int levelsPerWorld = 100;
}
