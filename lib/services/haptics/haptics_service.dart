import 'package:flutter/services.dart';

import '../settings/settings_controller.dart';

enum Haptic { light, medium, heavy, selection }

/// Subtle haptics via the platform haptic channel (no VIBRATE permission).
class HapticsService {
  HapticsService(this.settings);
  final SettingsController settings;
  int _last = 0;

  void fire(Haptic h) {
    if (!settings.vibration) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _last < 40) return;
    _last = now;
    switch (h) {
      case Haptic.light:
        HapticFeedback.lightImpact();
      case Haptic.medium:
        HapticFeedback.mediumImpact();
      case Haptic.heavy:
        HapticFeedback.heavyImpact();
      case Haptic.selection:
        HapticFeedback.selectionClick();
    }
  }
}
