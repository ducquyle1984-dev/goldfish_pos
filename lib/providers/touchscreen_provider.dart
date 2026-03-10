import 'package:flutter/material.dart';
import 'package:goldfish_pos/repositories/pos_repository.dart';

/// Exposes [enabled] — whether the current device is running in touchscreen
/// mode. When true, PIN-entry dialogs show an on-screen numpad.
///
/// Loaded once from Firestore on startup (via [load]); updated in-memory
/// whenever the user toggles the setting in Business Settings and calls
/// [setEnabled].
class TouchscreenProvider extends ChangeNotifier {
  bool _enabled;

  bool get enabled => _enabled;

  TouchscreenProvider(bool initial) : _enabled = initial;

  /// Update the in-memory flag and notify listeners.
  /// Call this after saving the new value to Firestore.
  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }

  /// Load the setting from Firestore at app startup.
  static Future<TouchscreenProvider> load() async {
    try {
      final settings = await PosRepository().getBusinessSettings();
      return TouchscreenProvider(settings.touchscreenEnabled);
    } catch (_) {
      return TouchscreenProvider(false);
    }
  }
}
