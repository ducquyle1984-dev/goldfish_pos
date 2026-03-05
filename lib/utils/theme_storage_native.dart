// Native (non-web) implementation — uses shared_preferences as normal.
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'use_water_theme';

Future<bool?> loadThemePreference() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_key);
}

Future<void> saveThemePreference(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_key, value);
}
