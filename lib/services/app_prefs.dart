import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Small key-value store for the viewer layout.
///
/// Only the *view* is persisted: panel side and size, chart mode, overlays and
/// the cursor lock. Everything that belongs to a specific log (channel picks,
/// names, units) stays in memory for now.
class AppPrefs {
  static late SharedPreferences _store;

  static Future<void> init() async {
    _store = await SharedPreferences.getInstance();
  }

  static Map<String, dynamic> loadView() {
    final raw = _store.getString('view');
    if (raw == null) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<void> saveView(Map<String, dynamic> value) async {
    await _store.setString('view', jsonEncode(value));
  }

  static bool? getBool(String key) => _store.getBool(key);
  static Future<void> setBool(String key, bool value) => _store.setBool(key, value);
  static double? getDouble(String key) => _store.getDouble(key);
  static Future<void> setDouble(String key, double value) =>
      _store.setDouble(key, value);
  static String? getString(String key) => _store.getString(key);
  static Future<void> setString(String key, String value) =>
      _store.setString(key, value);
}
