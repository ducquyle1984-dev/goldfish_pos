import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and exposes the active theme choice.
/// [useWaterTheme] = true  → dark deep-water theme (default)
/// [useWaterTheme] = false → light standard Material theme
class ThemeProvider extends ChangeNotifier {
  static const _key = 'use_water_theme';

  bool _useWaterTheme = true;

  bool get useWaterTheme => _useWaterTheme;

  ThemeProvider(bool initial) : _useWaterTheme = initial;

  /// Toggle between water and light theme, then persist.
  void toggle() => _set(!_useWaterTheme);

  void _set(bool value) async {
    _useWaterTheme = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  /// Load saved preference (call once at startup before runApp).
  static Future<ThemeProvider> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_key) ?? true; // default = water theme ON
    return ThemeProvider(saved);
  }
}
