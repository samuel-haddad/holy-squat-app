import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'technique_upload_screen.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';

class TechniqueListScreen extends StatefulWidget {
  const TechniqueListScreen({super.key});

  @override
  State<TechniqueListScreen> createState() => _TechniqueListScreenState();
}

class _TechniqueListScreenState extends State<TechniqueListScreen> {
  // O SupabaseClient será chamado aqui para pesquisar 'technique_feedbacks' dps.
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Technique History', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam, size: 64, color: AppTheme.primaryTeal),
            const SizedBox(height: 16),
            const Text(
              'Your technical analysis history will appear here.',
              style: TextStyle(color: AppTheme.secondaryTextColor),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryTeal,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TechniqueUploadScreen()),
                );
              },
              child: const Text('New Analysis', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }
}
