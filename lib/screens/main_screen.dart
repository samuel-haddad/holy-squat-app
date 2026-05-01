import 'package:flutter/material.dart';
import 'package:holy_squat_app/widgets/app_drawer.dart';
import 'package:holy_squat_app/widgets/app_bottom_nav.dart';

// Placeholder screens - will create these next
import 'package:holy_squat_app/screens/wod_screen.dart';
import 'package:holy_squat_app/screens/sessions/sessions_screen.dart';
import 'package:holy_squat_app/screens/prs_screen.dart';
import 'package:holy_squat_app/screens/benchmarks/benchmark_screen.dart';
import 'package:holy_squat_app/screens/dashboard_screen.dart';

class MainScreen extends StatefulWidget {
  final int initialIndex;
  const MainScreen({super.key, this.initialIndex = 0});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  final List<Widget> _screens = [
    const WodScreen(),
    const SessionsScreen(),
    const PrsScreen(),
    const BenchmarkScreen(),
    const DashboardScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      body: SelectionArea(child: _screens[_currentIndex]),
      bottomNavigationBar: AppBottomNav(activeIndex: _currentIndex),
    );
  }
}
