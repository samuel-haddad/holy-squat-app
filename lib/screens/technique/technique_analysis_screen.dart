import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:video_player/video_player.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'dart:async';

class TechniqueAnalysisScreen extends StatefulWidget {
  final String exerciseName;
  const TechniqueAnalysisScreen({super.key, required this.exerciseName});

  @override
  State<TechniqueAnalysisScreen> createState() => _TechniqueAnalysisScreenState();
}

class _TechniqueAnalysisScreenState extends State<TechniqueAnalysisScreen> {
  Map<String, dynamic>? feedbackData;
  bool isProcessing = true;
  VideoPlayerController? _controller;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchFeedback();
    // Inicia polling para checar se a IA terminou
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (isProcessing) {
        _fetchFeedback();
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _fetchFeedback() async {
    final data = await SupabaseService.getTechniqueFeedback(widget.exerciseName);
    if (data != null) {
      setState(() {
        feedbackData = data;
        isProcessing = data['status'] == 'pending' || data['status'] == 'processing';
      });

      // Se terminou de processar e o controller ainda não foi criado
      if (!isProcessing && data['status'] == 'completed' && _controller == null && data['processed_video_path'] != null) {
        _initializeVideo(data['processed_video_path']);
      }
    }
  }

  Future<void> _initializeVideo(String path) async {
    final url = SupabaseService.client.storage.from('technique_videos').getPublicUrl(path);
    _controller = VideoPlayerController.networkUrl(Uri.parse(url))
      ..initialize().then((_) {
        setState(() {});
        _controller?.setLooping(true);
        _controller?.play();
      });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Analysis Results', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Downloading video backup...')));
              // Integar package `gal` aqui
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // CV Player Render
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primaryTeal),
              ),
              clipBehavior: Clip.hardEdge,
              child: _controller != null && _controller!.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    )
                  : Container(
                      height: 250, 
                      alignment: Alignment.center, 
                      child: feedbackData?['status'] == 'failed'
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, size: 60, color: Colors.red[300]),
                              const SizedBox(height: 16),
                              const Text("Analysis failed.", style: TextStyle(color: Colors.white, fontSize: 18)),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircularProgressIndicator(color: AppTheme.primaryTeal),
                              const SizedBox(height: 16),
                              Text(
                                isProcessing ? 'AI is analyzing your movement...' : 'Loading video...',
                                style: const TextStyle(color: Colors.white)
                              ),
                            ],
                          )
                    ),
            ),
            const SizedBox(height: 24),
            
            if (feedbackData != null && !isProcessing) ...[
              // Resume Section
              const Text(
                "Technical Resume",
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(12)
                ),
                child: Text(
                  feedbackData?['resume_text'] ?? 'No analysis available.',
                  style: const TextStyle(color: Colors.white, height: 1.5),
                ),
              ),
              const SizedBox(height: 24),
              
              // Improve Section
              const Text(
                "How to Improve",
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (feedbackData?['improve_exercises'] != null)
                ...(feedbackData!['improve_exercises'] as List).map((ex) {
                  return Card(
                    color: AppTheme.cardColor,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ExpansionTile(
                      iconColor: AppTheme.primaryTeal,
                      collapsedIconColor: Colors.white,
                      title: Text(ex["name"] ?? 'Exercise', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.lightbulb, color: AppTheme.primaryTeal, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(ex["reason"] ?? '', style: const TextStyle(color: AppTheme.secondaryTextColor)),
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  );
                }),
            ] else if (feedbackData?['status'] == 'failed')
              const Center(
                child: Text('Analysis failed. Please try again.', style: TextStyle(color: Colors.red)),
              ),
          ]
        ),
      ),
    );
  }
}
