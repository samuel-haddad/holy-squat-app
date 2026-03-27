import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/screens/calendar_screen.dart';
import 'package:holy_squat_app/screens/main_screen.dart';
import 'package:holy_squat_app/screens/profile_screen.dart';
import 'package:holy_squat_app/screens/planning/planning_screen.dart';
import 'package:holy_squat_app/core/user_state.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppTheme.backgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              height: 120, // fixed height for header
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
              color: AppTheme.backgroundColor,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/logo/holysquat_logo.png',
                      height: 48,
                      errorBuilder: (context, error, stackTrace) => const Text('Holy Squat', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildDrawerItem('WOD', () {
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainScreen(initialIndex: 0)), (route) => false);
            }),
            _buildDrawerItem('Calendar', () {
              Navigator.pop(context); // close drawer
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CalendarScreen()));
            }),
            _buildDrawerItem('Planning', () {
              Navigator.pop(context); // close drawer
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PlanningScreen()));
            }),
            _buildDrawerItem('Sessions', () {
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainScreen(initialIndex: 1)), (route) => false);
            }),
            _buildDrawerItem('PRs', () {
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainScreen(initialIndex: 2)), (route) => false);
            }),
            _buildDrawerItem('Benchmark', () {
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainScreen(initialIndex: 3)), (route) => false);
            }),
            _buildDrawerItem('Dashboard', () {
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainScreen(initialIndex: 4)), (route) => false);
            }),
            const Spacer(),
            ValueListenableBuilder<String?>(
              valueListenable: UserState.avatarUrl,
              builder: (context, avatarUrl, _) {
                return ValueListenableBuilder<Uint8List?>(
                  valueListenable: UserState.avatarBytes,
                  builder: (context, avatarBytes, child) {
                    return ValueListenableBuilder<String>(
                      valueListenable: UserState.name,
                      builder: (context, name, child) {
                        return ValueListenableBuilder<String>(
                          valueListenable: UserState.email,
                          builder: (context, email, child) {
                            ImageProvider? provider;
                            if (avatarBytes != null) {
                              provider = MemoryImage(avatarBytes);
                            } else if (avatarUrl != null && avatarUrl.isNotEmpty) {
                              provider = NetworkImage(avatarUrl);
                            }
                            
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.transparent,
                                backgroundImage: provider,
                                child: provider == null
                                    ? SvgPicture.asset(
                                        Theme.of(context).brightness == Brightness.dark
                                            ? 'assets/account_icons/account_icon_dark.svg'
                                            : 'assets/account_icons/account_icon_light.svg',
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              title: Text(name, style: const TextStyle(color: Colors.white)),
                              subtitle: Text(email, style: const TextStyle(color: AppTheme.secondaryTextColor, fontSize: 12)),
                              trailing: const Icon(Icons.more_vert, color: Colors.white),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(String title, VoidCallback onTap) {
    return ListTile(
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
        ),
      ),
      onTap: onTap,
    );
  }
}
