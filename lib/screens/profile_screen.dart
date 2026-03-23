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
