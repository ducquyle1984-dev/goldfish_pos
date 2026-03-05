import 'package:flutter/material.dart';

// On web, uses window.localStorage directly (no plugin channel → no
// MissingPluginException).  On native, uses shared_preferences as usual.
import '../utils/theme_storage_native.dart'
    if (dart.library.html) '../utils/theme_storage_web.dart';

/// Persists and exposes the active theme choice.
/// [useWaterTheme] = true  → dark deep-water theme (default)
/// [useWaterTheme] = false → light standard Material theme
class ThemeProvider extends ChangeNotifier {
  bool _useWaterTheme = true;

  bool get useWaterTheme => _useWaterTheme;

  ThemeProvider(bool initial) : _useWaterTheme = initial;

  /// Toggle between water and light theme, then persist.
  void toggle() => _set(!_useWaterTheme);

  void _set(bool value) async {
    _useWaterTheme = value;
    notifyListeners();
    try {
      await saveThemePreference(value);
    } catch (_) {
      // Persist failure is non-fatal — theme still switches for this session.
    }
  }

  /// Load saved preference (call once at startup before runApp).
  static Future<ThemeProvider> load() async {
    try {
      final saved = await loadThemePreference();
      return ThemeProvider(saved ?? true); // default = water theme ON
    } catch (_) {
      return ThemeProvider(true);
    }
  }
}
