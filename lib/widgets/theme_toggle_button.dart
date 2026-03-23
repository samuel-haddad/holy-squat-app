import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:holy_squat_app/core/app_state.dart';

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppState.themeMode,
      builder: (context, mode, child) {
        final isDark = mode == ThemeMode.dark;
        
        // Show light button if in dark mode, dark button if in light mode
        final iconAsset = isDark 
            ? 'assets/mode_icons/light_mode.svg' 
            : 'assets/mode_icons/dark_mode.svg';
        
        return IconButton(
          icon: SvgPicture.asset(iconAsset, width: 24, height: 24),
          onPressed: () => AppState.toggleTheme(),
        );
      },
    );
  }
}
