import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Holds the user's light / dark / system choice and writes it to device
// storage, so the app reopens in the theme they picked.
//
// This is the personalisation the spec asks for: the app icon and splash are
// fixed brand assets, but the theme is something the user controls.
final AsyncNotifierProvider<ThemeController, ThemeMode> themeModeProvider =
    AsyncNotifierProvider<ThemeController, ThemeMode>(ThemeController.new);

class ThemeController extends AsyncNotifier<ThemeMode> {
  static const String _key = 'theme_mode';

  @override
  Future<ThemeMode> build() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return _decode(prefs.getString(_key));
  }

  Future<void> setMode(ThemeMode mode) async {
    // Update the UI first so the switch feels instant, then persist.
    state = AsyncData<ThemeMode>(mode);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  // Unknown or missing values fall back to following the device setting.
  ThemeMode _decode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
