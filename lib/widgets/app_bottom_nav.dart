import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/screens/main_screen.dart';

class AppBottomNav extends StatelessWidget {
  final int? activeIndex;
  
  const AppBottomNav({super.key, this.activeIndex});

  @override
  Widget build(BuildContext context) {
    final int safeIndex = activeIndex ?? 0;

    return BottomNavigationBar(
      currentIndex: safeIndex,
      type: BottomNavigationBarType.fixed,
      backgroundColor: AppTheme.backgroundColor,
      selectedItemColor: activeIndex == null ? AppTheme.secondaryTextColor : AppTheme.primaryTeal,
      unselectedItemColor: AppTheme.secondaryTextColor,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      onTap: (index) {
        if (index != activeIndex) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => MainScreen(initialIndex: index)),
            (route) => false,
          );
        }
      },
      items: [
        _buildNavItem('WOD', 'wod', activeIndex == 0),
        _buildNavItem('Sessions', 'sessions', activeIndex == 1),
        _buildNavItem('PRs', 'prs', activeIndex == 2),
        _buildNavItem('Benchmark', 'benchmark', activeIndex == 3),
        _buildNavItem('Dashboard', 'dashboard', activeIndex == 4),
      ],
    );
  }

  BottomNavigationBarItem _buildNavItem(String label, String iconPrefix, bool isActive) {
    return BottomNavigationBarItem(
      icon: SvgPicture.asset(
        'assets/menu_icons/${iconPrefix}_menu_icon_white.svg',
        width: 24,
        height: 24,
      ),
      activeIcon: SvgPicture.asset(
        isActive 
            ? 'assets/menu_icons/${iconPrefix}_menu_icon_blue.svg'
            : 'assets/menu_icons/${iconPrefix}_menu_icon_white.svg',
        width: 24,
        height: 24,
      ),
      label: label,
    );
  }
}
