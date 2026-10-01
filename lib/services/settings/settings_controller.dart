import 'package:flutter/foundation.dart';

import '../storage/storage_service.dart';

/// Player preferences (persisted separately from progression).
class SettingsController extends ChangeNotifier {
  SettingsController(this._storage) {
    final m = _storage.readJson(key) ?? const {};
    _music = Json.b(m, 'music', true);
    _sfx = Json.b(m, 'sfx', true);
    _vibration = Json.b(m, 'vibration', true);
    _gravityPad = Json.b(m, 'gravityPad', false);
  }

  static const String key = 'cg_settings_v1';
  final StorageService _storage;

  late bool _music, _sfx, _vibration, _gravityPad;

  bool get music => _music;
  bool get sfx => _sfx;
  bool get vibration => _vibration;

  /// Show on-screen gravity buttons in addition to swipes.
  bool get gravityPad => _gravityPad;

  set music(bool v) => _set(() => _music = v);
  set sfx(bool v) => _set(() => _sfx = v);
  set vibration(bool v) => _set(() => _vibration = v);
  set gravityPad(bool v) => _set(() => _gravityPad = v);

  void _set(VoidCallback f) {
    f();
    notifyListeners();
    _storage.writeJson(key, {
      'v': 1,
      'music': _music,
      'sfx': _sfx,
      'vibration': _vibration,
      'gravityPad': _gravityPad,
    });
  }
}
