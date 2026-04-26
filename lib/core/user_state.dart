import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class UserState {
  static final ValueNotifier<Uint8List?> avatarBytes = ValueNotifier(null);
  static final ValueNotifier<String?> avatarUrl = ValueNotifier(null);
  static final ValueNotifier<String> name = ValueNotifier('Samuel Haddad');
  static final ValueNotifier<String> email = ValueNotifier('samuelhsm@gmail.com');
  static final ValueNotifier<String> birthdate = ValueNotifier('01/01/1990');
  static final ValueNotifier<String> weight = ValueNotifier('80');
  static final ValueNotifier<String> weightUnit = ValueNotifier('Kg');
  static final ValueNotifier<String> sport = ValueNotifier('Crossfit');
  static final ValueNotifier<String> goal = ValueNotifier('Hypertrophy');
  static final ValueNotifier<bool> stravaConnected = ValueNotifier(false);

  // Preserved field (now part of About section)
  static final ValueNotifier<String> anamnesis = ValueNotifier('');
  
  static final ValueNotifier<bool> isProfileComplete = ValueNotifier(true); // Default to true to avoid flicker
}
