import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/screens/main_screen.dart';
import 'package:holy_squat_app/core/app_state.dart';
import 'package:holy_squat_app/screens/login_screen.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('pt_BR', null);

  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // Detect Strava OAuth connection callback on web (?code=...&scope=...activity...)
  if (kIsWeb) {
    final uri = Uri.base;
    final code = uri.queryParameters['code'];
    final scope = uri.queryParameters['scope'] ?? '';
    if (code != null && scope.contains('activity')) {
      await _handleStravaConnectCallback(code);
    }
  }

  runApp(const HolySquatApp());
}

/// Exchanges the Strava authorization code for tokens and saves them to the profile.
Future<void> _handleStravaConnectCallback(String code) async {
  try {
    // Invoke function to get tokens (Edge Function needs to return JSON, not redirect)
    final res = await Supabase.instance.client.functions.invoke(
      'strava-auth',
      body: {'code': code},
    );
    final data = res.data as Map<String, dynamic>?;
    
    // If we have tokens and no session token, it's a "Connect" flow
    if (data != null && data['strava_id'] != null && data['access_token'] != null) {
      await SupabaseService.saveStravaTokens(
        data['strava_id'].toString(),
        data['access_token'] as String,
        data['refresh_token'] as String,
      );
    }
  } catch (e) {
    debugPrint('Strava connection retry error: $e');
  }
}

class HolySquatApp extends StatelessWidget {
  const HolySquatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppState.themeMode,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'Holy Squat',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          home: const AuthGate(),
        );
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      SupabaseService.getProfile();
      return const MainScreen();
    }
    return const LoginScreen();
  }
}
