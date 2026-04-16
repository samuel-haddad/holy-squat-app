import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:image_picker/image_picker.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'dart:io';
import 'technique_analysis_screen.dart';

class TechniqueUploadScreen extends StatefulWidget {
  const TechniqueUploadScreen({super.key});

  @override
  State<TechniqueUploadScreen> createState() => _TechniqueUploadScreenState();
}

class _TechniqueUploadScreenState extends State<TechniqueUploadScreen> {
  String? selectedExercise;
  bool isUploading = false;
  final ImagePicker _picker = ImagePicker();
  
  // Lista Mock de exercícios (em prod, virá do bank/library)
  final List<String> exercises = ['Back Squat', 'Front Squat', 'Clean', 'Snatch', 'Deadlift'];

  Future<void> _processFile(File file) async {
    if (selectedExercise == null) return;

    setState(() { isUploading = true; });

    try {
      final String extension = file.path.split('.').last.toLowerCase();
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}_technique.$extension';
      
      // 1. Upload para o bucket 'technique_videos/raw'
      final String? rawPath = await SupabaseService.uploadTechniqueVideo(file, fileName);
      
      if (rawPath != null) {
        // 2. Cria o registro que dispara o Webhook/IA
        await SupabaseService.requestTechniqueAnalysis(
          exerciseName: selectedExercise!,
          rawVideoPath: rawPath,
        );

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => TechniqueAnalysisScreen(
              exerciseName: selectedExercise!,
            )),
          );
        }
      } else {
        throw Exception("Upload failed");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() { isUploading = false; });
    }
  }

  Future<void> _recordVideo() async {
    final XFile? video = await _picker.pickVideo(source: ImageSource.camera);
    if (video != null) {
      await _processFile(File(video.path));
    }
  }

  Future<void> _pickVideo() async {
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video != null) {
      await _processFile(File(video.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('New Analysis', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select Exercise',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              dropdownColor: AppTheme.cardColor,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.cardColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              hint: const Text('Choose what you performed', style: TextStyle(color: Colors.grey)),
              value: selectedExercise,
              items: exercises.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (val) {
                setState(() { selectedExercise = val; });
              },
            ),
            const SizedBox(height: 48),
            if (isUploading)
              const Column(
                children: [
                  CircularProgressIndicator(color: AppTheme.primaryTeal),
                  SizedBox(height: 16),
                  Text('Uploading technique for analysis...', style: TextStyle(color: Colors.white)),
                ],
              )
            else ...[
              ElevatedButton.icon(
                onPressed: selectedExercise != null ? _recordVideo : null,
                icon: const Icon(Icons.camera_alt, color: Colors.black),
                label: const Text('Record Video', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryTeal,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: selectedExercise != null ? _pickVideo : null,
                icon: const Icon(Icons.upload_file, color: AppTheme.primaryTeal),
                label: const Text('Upload Video', style: TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  side: const BorderSide(color: AppTheme.primaryTeal),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
