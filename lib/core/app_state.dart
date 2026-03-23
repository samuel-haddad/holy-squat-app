import 'package:flutter/material.dart';

class AppState {
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.dark);
  static final ValueNotifier<DateTime> selectedWodDate = ValueNotifier(DateTime.now());

  static void toggleTheme() {
    if (themeMode.value == ThemeMode.light) {
      themeMode.value = ThemeMode.dark;
    } else {
      themeMode.value = ThemeMode.light;
    }
  }
}
