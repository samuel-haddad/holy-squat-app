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
  @override
  void initState() {
    super.initState();
  }


  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      UserState.avatarBytes.value = bytes;
      SupabaseService.upsertProfile().catchError((e) => debugPrint('Image save error: $e'));
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
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileFormScreen())).then((_) => setState(() {}));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildProfileHeader(),
            const SizedBox(height: 24),
            _buildExpandableSection(
              title: 'About',
              icon: Icons.person_outline,
              children: [
                _buildInfoRow('Birthdate', UserState.birthdate.value),
                _buildInfoRow('Weight', '${UserState.weight.value} ${UserState.weightUnit.value}'),
                _buildInfoRow('Sport', UserState.sport.value),
                _buildInfoRow('Goal', UserState.goal.value),
              ],
            ),
            const SizedBox(height: 12),
            _buildExpandableSection(
              title: 'Skills & Training',
              icon: Icons.fitness_center,
              children: [
                _buildInfoRow('Active hours per session', '${UserState.activeHoursValue.value} ${UserState.activeHoursUnit.value}'),
                _buildInfoRow('Sessions/Day', UserState.sessionsPerDay.value.toString()),
                _buildInfoRow('Where', UserState.whereTrain.value.join(', ')),
                const Divider(color: Colors.white10),
                _buildLongTextRow('Training Background', UserState.anamnesis.value),
                ValueListenableBuilder<String?>(
                  valueListenable: UserState.backgroundFileUrl,
                  builder: (context, url, _) => url != null ? _buildFileRow(url) : const SizedBox.shrink(),
                ),
                _buildLongTextRow('Additional Info', UserState.additionalInfo.value),
              ],
            ),
            const SizedBox(height: 12),
            _buildExpandableSection(
              title: 'Connections',
              icon: Icons.link,
              children: [
                _buildStravaRow(),
                const SizedBox(height: 12),
                _buildGarminRow(),
              ],
            ),
            const SizedBox(height: 32),
            _buildSignOutButton(),
            const SizedBox(height: 48),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(activeIndex: null),
    );
  }

  Widget _buildProfileHeader() {
    return Column(
      children: [
        ValueListenableBuilder<String?>(
          valueListenable: UserState.avatarUrl,
          builder: (context, avatarUrl, _) => ValueListenableBuilder<Uint8List?>(
            valueListenable: UserState.avatarBytes,
            builder: (context, avatarBytes, _) {
              ImageProvider? provider;
              if (avatarBytes != null) provider = MemoryImage(avatarBytes);
              else if (avatarUrl != null && avatarUrl.isNotEmpty) provider = NetworkImage(avatarUrl);
              return GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.transparent,
                      backgroundImage: provider,
                      child: provider == null ? SvgPicture.asset(
                        Theme.of(context).brightness == Brightness.dark ? 'assets/account_icons/account_icon_dark.svg' : 'assets/account_icons/account_icon_light.svg',
                        width: 100, height: 100, fit: BoxFit.cover,
                      ) : null,
                    ),
                    const CircleAvatar(backgroundColor: AppTheme.primaryTeal, radius: 16, child: Icon(Icons.camera_alt, size: 16, color: Colors.black)),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Text(UserState.name.value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(UserState.email.value, style: const TextStyle(color: AppTheme.secondaryTextColor)),
      ],
    );
  }

  Widget _buildExpandableSection({required String title, required IconData icon, required List<Widget> children}) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(12)),
        child: ExpansionTile(
          leading: Icon(icon, color: AppTheme.primaryTeal),
          title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          iconColor: AppTheme.primaryTeal,
          collapsedIconColor: Colors.white,
          childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          children: children,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.secondaryTextColor, fontSize: 15)),
          Text(value.isEmpty ? '-' : value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildLongTextRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.secondaryTextColor, fontSize: 14)),
          const SizedBox(height: 4),
          Text(value.isEmpty ? 'N/A' : value, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildFileRow(String url) {
    String fileName = url.split('/').last;
    if (fileName.contains('_')) {
      fileName = fileName.split('_').sublist(1).join('_'); // Remove timestamp prefix
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: InkWell(
        onTap: () => launchUrl(Uri.parse(url)),
        child: Row(
          children: [
            const Icon(Icons.description, color: AppTheme.primaryTeal, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '📄 $fileName',
                style: const TextStyle(color: AppTheme.primaryTeal, decoration: TextDecoration.underline),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStravaRow() {
    return ValueListenableBuilder<bool>(
      valueListenable: UserState.stravaConnected,
      builder: (context, isConnected, _) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: const [Icon(Icons.directions_run, color: Colors.orange), SizedBox(width: 12), Text('Strava', style: TextStyle(color: Colors.white))]),
            TextButton(
              onPressed: isConnected ? _confirmDisconnectStrava : _handleStravaConnect,
              child: Text(isConnected ? 'Disconnect' : 'Connect', style: TextStyle(color: isConnected ? Colors.red : AppTheme.primaryTeal, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGarminRow() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: const [Icon(Icons.watch, color: Colors.blueGrey), SizedBox(width: 12), Text('Garmin', style: TextStyle(color: Colors.white))]),
          TextButton(onPressed: () {}, child: const Text('Soon', style: TextStyle(color: Colors.white24))),
        ],
      ),
    );
  }

  Future<void> _handleStravaConnect() async {
    const stravaClientId = 216878;
    const redirectUri = 'https://samuel-haddad.github.io/holy-squat-app';
    final url = Uri.parse('https://www.strava.com/oauth/authorize?client_id=$stravaClientId&response_type=code&redirect_uri=$redirectUri&approval_prompt=auto&scope=read,activity:read_all');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
  }

  void _confirmDisconnectStrava() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardColor,
        title: const Text('Disconnect Strava?', style: TextStyle(color: Colors.white)),
        content: const Text('Your training data will no longer sync.', style: TextStyle(color: AppTheme.secondaryTextColor)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white))),
          TextButton(onPressed: () async { Navigator.pop(context); await SupabaseService.disconnectStrava(); setState(() {}); }, child: const Text('Disconnect', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Widget _buildSignOutButton() {
    return SizedBox(
      width: double.infinity, height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.1), foregroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        onPressed: () => Supabase.instance.client.auth.signOut(),
        child: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}
