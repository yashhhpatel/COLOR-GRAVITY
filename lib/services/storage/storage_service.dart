import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin JSON-document store over SharedPreferences. Every read is defensive:
/// corrupt data yields `null` so callers fall back to defaults.
abstract class StorageService {
  Map<String, dynamic>? readJson(String key);
  Future<void> writeJson(String key, Map<String, dynamic> value);
}

class PrefsStorage implements StorageService {
  PrefsStorage(this._prefs);
  final SharedPreferences _prefs;

  static Future<PrefsStorage> create() async => PrefsStorage(await SharedPreferences.getInstance());

  @override
  Map<String, dynamic>? readJson(String key) {
    try {
      final raw = _prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      debugPrint('Storage: corrupt "$key" ignored ($e)');
      return null;
    }
  }

  @override
  Future<void> writeJson(String key, Map<String, dynamic> value) async {
    try {
      await _prefs.setString(key, jsonEncode(value));
    } catch (e) {
      debugPrint('Storage: failed to write "$key" ($e)');
    }
  }
}

/// In-memory store for tests and as an emergency fallback.
class MemoryStorage implements StorageService {
  final Map<String, String> data = {};

  @override
  Map<String, dynamic>? readJson(String key) {
    final raw = data[key];
    if (raw == null) return null;
    try {
      final d = jsonDecode(raw);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeJson(String key, Map<String, dynamic> value) async => data[key] = jsonEncode(value);
}

/// Safe field readers for versioned save documents.
class Json {
  static int i(Map<String, dynamic> m, String k, int d) {
    final v = m[k];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return d;
  }

  static double n(Map<String, dynamic> m, String k, double d) {
    final v = m[k];
    return v is num ? v.toDouble() : d;
  }

  static bool b(Map<String, dynamic> m, String k, bool d) {
    final v = m[k];
    return v is bool ? v : d;
  }

  static String? s(Map<String, dynamic> m, String k) {
    final v = m[k];
    return v is String ? v : null;
  }

  static List<int> intList(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v is! List) return [];
    return [for (final x in v) x is num ? x.toInt() : 0];
  }

  static Set<String> strSet(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v is! List) return {};
    return {
      for (final x in v)
        if (x is String) x
    };
  }

  static Map<String, int> intMap(Map<String, dynamic> m, String k) {
    final v = m[k];
    if (v is! Map) return {};
    return {
      for (final e in v.entries)
        if (e.key is String && e.value is num) e.key as String: (e.value as num).toInt()
    };
  }
}
