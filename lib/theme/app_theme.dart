import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand Colors
  static const Color primaryTeal = Color(0xFF1AE5D3);
  static const Color backgroundColor = Color(0xFF141414);
  static const Color cardColor = Color(0xFF222222);
  static const Color textColor = Colors.white;
  static const Color secondaryTextColor = Color(0xFFAAAAAA);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: backgroundColor,
      primaryColor: primaryTeal,
      cardColor: cardColor,
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: primaryTeal),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: backgroundColor,
        selectedItemColor: primaryTeal,
        unselectedItemColor: secondaryTextColor,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.dark().textTheme.copyWith(
          displayLarge: const TextStyle(color: textColor, fontWeight: FontWeight.bold),
          bodyLarge: const TextStyle(color: textColor),
          bodyMedium: const TextStyle(color: secondaryTextColor),
        ),
      ),
      colorScheme: const ColorScheme.dark(
        primary: primaryTeal,
        surface: cardColor,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      primaryColor: primaryTeal,
      cardColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF5F5F5),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.black),
        titleTextStyle: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w600),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryTeal,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        showUnselectedLabels: true,
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData.light().textTheme.copyWith(
          displayLarge: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          bodyLarge: const TextStyle(color: Colors.black),
          bodyMedium: const TextStyle(color: Colors.grey),
        ),
      ),
      colorScheme: const ColorScheme.light(
        primary: primaryTeal,
        surface: Colors.white,
      ),
    );
  }
}
