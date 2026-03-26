import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/widgets/theme_toggle_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleEmailAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('E-mail and password required.')));
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      if (_isSignUp) {
        await Supabase.instance.client.auth.signUp(email: email, password: password);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registration successful! Please sign in.')));
          setState(() => _isSignUp = false);
        }
      } else {
        await Supabase.instance.client.auth.signInWithPassword(email: email, password: password);
        // Main.dart StreamBuilder handles navigation automatically!
      }
    } on AuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unexpected error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleOAuth(OAuthProvider provider) async {
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        provider,
        redirectTo: kIsWeb
            ? 'https://samuel-haddad.github.io/holy-squat-app/'
            : 'holysquat://login-callback',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OAuth Error: $e')));
      }
    }
  }

  Future<void> _handleStravaLogin() async {
    // Strava is not a native Supabase provider — we launch the OAuth URL manually.
    // A Supabase Edge Function will handle the token exchange and session creation.
    const stravaClientId = 216878; // Replace after Strava app registration
    const redirectUri = 'https://samuel-haddad.github.io/holy-squat-app/';
    final url = Uri.parse(
      'https://www.strava.com/oauth/authorize'
      '?client_id=$stravaClientId'
      '&response_type=code'
      '&redirect_uri=$redirectUri'
      '&approval_prompt=auto'
      '&scope=read,activity:read_all',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Strava login.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Holy Squat', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryTeal)),
        centerTitle: true,
        actions: const [ThemeToggleButton()],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.fitness_center, size: 80, color: AppTheme.primaryTeal),
                const SizedBox(height: 32),
                Text(
                  _isSignUp ? 'Create an Account' : 'Welcome Back',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Email',
                    hintStyle: const TextStyle(color: AppTheme.secondaryTextColor),
                    filled: true,
                    fillColor: AppTheme.cardColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Password',
                    hintStyle: const TextStyle(color: AppTheme.secondaryTextColor),
                    filled: true,
                    fillColor: AppTheme.cardColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 24),
                
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleEmailAuth,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.black)
                        : Text(
                            _isSignUp ? 'Sign Up' : 'Log In',
                            style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isSignUp = !_isSignUp;
                    });
                  },
                  child: Text(
                    _isSignUp ? 'Already have an account? Log In' : 'Need an account? Sign Up',
                    style: const TextStyle(color: AppTheme.secondaryTextColor),
                  ),
                ),
                
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Row(
                    children: [
                      Expanded(child: Divider(color: AppTheme.cardColor)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text('OR', style: TextStyle(color: AppTheme.secondaryTextColor)),
                      ),
                      Expanded(child: Divider(color: AppTheme.cardColor)),
                    ],
                  ),
                ),
                
                _buildSocialButton(Icons.g_mobiledata, 'Continue with Google', Colors.white, Colors.black, () => _handleOAuth(OAuthProvider.google)),
                const SizedBox(height: 12),
                _buildSocialButton(Icons.directions_run, 'Continue with Strava', Colors.orange, Colors.white, _handleStravaLogin),
                const SizedBox(height: 12),
                _buildSocialButton(Icons.watch, 'Continue with Garmin', Colors.blueGrey, Colors.white, () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Garmin OAuth integration pending API keys.')));
                }),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSocialButton(IconData icon, String label, Color bgColor, Color textColor, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: textColor, size: 28),
        label: Text(label, style: TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
