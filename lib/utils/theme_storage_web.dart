// Web implementation — reads/writes window.localStorage directly,
// bypassing the shared_preferences plugin channel entirely.
// This avoids MissingPluginException on browsers where the plugin
// fails to register (stale cache, cold load, etc.).
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

const _key = 'use_water_theme';

Future<bool?> loadThemePreference() async {
  final val = html.window.localStorage[_key];
  if (val == null) return null;
  return val == 'true';
}

Future<void> saveThemePreference(bool value) async {
  html.window.localStorage[_key] = value.toString();
}
