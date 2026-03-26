import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/screens/profile_form_screen.dart';
import 'package:holy_squat_app/widgets/app_bottom_nav.dart';
import 'package:holy_squat_app/core/user_state.dart';
import 'package:holy_squat_app/widgets/theme_toggle_button.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:typed_data';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      UserState.avatarBytes.value = bytes;
      
      // Auto-save silently in the background
      SupabaseService.upsertProfile().catchError((e) {
        debugPrint('Auto-save profile image failed: $e');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          const ThemeToggleButton(),
          IconButton(
            icon: const Icon(Icons.edit, color: AppTheme.primaryTeal),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileFormScreen())).then((_) => setState((){}));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Center(
              child: ValueListenableBuilder<String?>(
                valueListenable: UserState.avatarUrl,
                builder: (context, avatarUrl, _) {
                  return ValueListenableBuilder<Uint8List?>(
                    valueListenable: UserState.avatarBytes,
                    builder: (context, avatarBytes, child) {
                      ImageProvider? provider;
                      if (avatarBytes != null) {
                        provider = MemoryImage(avatarBytes);
                      } else if (avatarUrl != null && avatarUrl.isNotEmpty) {
                        provider = NetworkImage(avatarUrl);
                      }
                      
                      return GestureDetector(
                        onTap: _pickImage,
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 50,
                              backgroundColor: Colors.transparent,
                              backgroundImage: provider,
                              child: provider == null
                                  ? SvgPicture.asset(
                                      Theme.of(context).brightness == Brightness.dark
                                          ? 'assets/account_icons/account_icon_dark.svg'
                                          : 'assets/account_icons/account_icon_light.svg',
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            const CircleAvatar(
                              backgroundColor: AppTheme.primaryTeal,
                              radius: 16,
                              child: Icon(Icons.camera_alt, size: 16, color: Colors.black),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(
              UserState.name.value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              UserState.email.value,
              style: const TextStyle(fontSize: 16, color: AppTheme.secondaryTextColor),
            ),
            const SizedBox(height: 32),
            _buildStatCard('Birthdate', UserState.birthdate.value),
            _buildStatCard('Weight', '${UserState.weight.value} ${UserState.weightUnit.value}'),
            _buildStatCard('Favorite Sport', UserState.sport.value),
            _buildStatCard('Training goal', UserState.goal.value),
            const SizedBox(height: 24),
            _buildConnectedAccountsSection(),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileFormScreen())).then((_) => setState((){}));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.cardColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Edit Profile', style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.1),
                  foregroundColor: Colors.red,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(activeIndex: null),
    );
  }

  Widget _buildConnectedAccountsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4.0, bottom: 12.0),
          child: Text(
            'Connected Accounts',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: UserState.stravaConnected,
          builder: (context, isConnected, _) {
            return _buildAccountRow(
              'Strava',
              isConnected,
              'assets/logo/strava_logo.png', // Fallback to icon if missing
              isConnected ? _confirmDisconnectStrava : _handleStravaConnect,
            );
          },
        ),
        const SizedBox(height: 12),
        _buildAccountRow(
          'Garmin',
          false,
          null, // Placeholder
          () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Garmin import coming soon!'))
            );
          },
        ),
      ],
    );
  }

  Widget _buildAccountRow(String name, bool isConnected, String? assetPath, VoidCallback onTap) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                name == 'Strava' ? Icons.directions_run : Icons.watch,
                color: name == 'Strava' ? Colors.orange : Colors.blueGrey,
              ),
              const SizedBox(width: 12),
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          TextButton(
            onPressed: onTap,
            child: Text(
              isConnected ? 'Disconnect' : 'Connect',
              style: TextStyle(
                color: isConnected ? Colors.red : AppTheme.primaryTeal,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleStravaConnect() async {
    const stravaClientId = 216878;
    const redirectUri = 'https://samuel-haddad.github.io/holy-squat-app';
    final url = Uri.parse(
      'https://www.strava.com/oauth/authorize'
      '?client_id=$stravaClientId'
      '&response_type=code'
      '&redirect_uri=$redirectUri'
      '&approval_prompt=auto'
      '&scope=read,activity:read_all',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
    }
  }

  void _confirmDisconnectStrava() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Disconnect Strava?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Your training data will no longer sync from Strava.',
          style: TextStyle(color: AppTheme.secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await SupabaseService.disconnectStrava();
              setState(() {});
            },
            child: const Text('Disconnect', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.secondaryTextColor, fontSize: 16)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
