import 'package:flutter/widgets.dart';

import '../progression/progress_controller.dart';
import 'ads/ad_service.dart';
import 'audio/audio_service.dart';
import 'haptics/haptics_service.dart';
import 'monetization_controller.dart';
import 'purchases/purchase_service.dart';
import 'settings/settings_controller.dart';
import 'storage/storage_service.dart';

/// Service container. Each concern keeps its own controller/state so
/// gameplay, UI, progression, settings and monetization stay decoupled.
class AppServices {
  AppServices({
    required this.storage,
    required this.settings,
    required this.progress,
    required this.monetization,
    required this.audio,
    required this.haptics,
  });

  final StorageService storage;
  final SettingsController settings;
  final ProgressController progress;
  final MonetizationController monetization;
  final AudioService audio;
  final HapticsService haptics;

  static Future<AppServices> createReal() async {
    StorageService storage;
    try {
      storage = await PrefsStorage.create();
    } catch (_) {
      storage = MemoryStorage();
    }
    final settings = SettingsController(storage);
    final audio = GameAudioService(settings);
    final ads = AdMobService();
    final purchases = PlayPurchaseService();
    final services = AppServices(
      storage: storage,
      settings: settings,
      progress: ProgressController(storage),
      monetization: MonetizationController(storage, ads, purchases),
      audio: audio,
      haptics: HapticsService(settings),
    );
    // Fire-and-forget: the game is fully playable while these warm up.
    audio.init();
    ads.init();
    purchases.init();
    return services;
  }

  /// Offline, plugin-free services (tests / previews).
  factory AppServices.offline({StorageService? storage}) {
    final s = storage ?? MemoryStorage();
    final settings = SettingsController(s);
    return AppServices(
      storage: s,
      settings: settings,
      progress: ProgressController(s),
      monetization: MonetizationController(s, NoAdService(), NoPurchaseService()),
      audio: SilentAudioService(),
      haptics: HapticsService(settings),
    );
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});
  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
