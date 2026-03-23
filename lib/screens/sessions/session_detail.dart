import 'package:flutter/material.dart';
import 'package:holy_squat_app/widgets/theme_toggle_button.dart';
import 'package:intl/intl.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/screens/workout_result_form_screen.dart';
import 'package:holy_squat_app/widgets/app_bottom_nav.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'package:url_launcher/url_launcher.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

class SessionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> sessionData;
  final String sessionKey;

  const SessionDetailScreen({
    super.key,
    required this.sessionData,
    required this.sessionKey,
  });

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  late Future<Map<String, List<Map<String, dynamic>>>> _workoutsFuture;

  @override
  void initState() {
    super.initState();
    _workoutsFuture = SupabaseService.getWorkoutsForSession(widget.sessionKey);
  }

  @override
  Widget build(BuildContext context) {
    // Parse header data
    final DateTime date = widget.sessionData['date'] != null ? DateTime.parse(widget.sessionData['date']) : DateTime.now();
    final String dayName = DateFormat('EEEE').format(date).toUpperCase();
    final String title = widget.sessionData['session_type'] ?? 'Session';
    final String sessionNum = widget.sessionData['session_num']?.toString() ?? '1';
    final String formattedDate = DateFormat('dd/MM/yyyy').format(date);
    
    final iconObj = widget.sessionData['icons'];
    final String imgSrc = (iconObj != null && iconObj['img'] != null)
        ? iconObj['img']
        : 'https://cdn-icons-png.flaticon.com/512/2964/2964514.png';

    return Scaffold(
      appBar: AppBar(
        actions: const [ThemeToggleButton()],
        title: const Text('Full Session', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.primaryTeal),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppTheme.cardColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: imgSrc.startsWith('http')
                          ? Image.network(
                              imgSrc,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.fitness_center, size: 40),
                            )
                          : Image.asset(
                              'assets/sessions_icons/$imgSrc',
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.fitness_center, size: 40),
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SESSION $sessionNum', style: const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
                        const SizedBox(height: 4),
                        Text('$dayName | $formattedDate', style: const TextStyle(color: AppTheme.secondaryTextColor, fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const Text('Resume', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 24),
              
              // FutureBuilder for fetching workouts
              FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
                future: _workoutsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal));
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                  }
                  
                  final stages = snapshot.data ?? {};
                  if (stages.isEmpty) {
                    return const Text('No workouts found for this session.', style: TextStyle(color: AppTheme.secondaryTextColor));
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Resume list view
                      ...stages.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(entry.key, style: const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold, fontSize: 12)),
                              const SizedBox(height: 8),
                              ...entry.value.map((w) {
                                return _buildResumeItem(
                                  w['exercise'] ?? 'Unknown Exercise',
                                  w['sets']?.toString() ?? '-',
                                  w['details'] ?? '',
                                );
                              }),
                            ],
                          ),
                        );
                      }),
                      
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryTeal,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check, color: AppTheme.backgroundColor),
                            SizedBox(width: 8),
                            Text('All session done', style: TextStyle(color: AppTheme.backgroundColor, fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text('WOD', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 16),
                      
                      // Detailed views
                      ...stages.entries.expand((entry) {
                        return entry.value.map((w) {
                          final dur = w['time_exercise'] != null ? '${w['time_exercise']} min' : '-';
                          final link = w['workout_link'];
                          
                          final actualId = w['wod_exercise_id'].toString();
                          
                          dynamic logsData = w['workouts_logs'];
                          List<dynamic> logs = [];
                          if (logsData is List) {
                            logs = logsData;
                          } else if (logsData is Map) {
                            logs = [logsData];
                          }
                          
                          final bool isCompleted = logs.isNotEmpty;
                          String? resultText;
                          if (isCompleted) {
                            final log = logs.first;
                            resultText = log['duration_done'] ?? log['weight']?.toString() ?? log['cardio_result']?.toString() ?? 'Feito';
                          }
                          
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: _buildDetailedExercise(
                              entry.key,
                              w['exercise'] ?? 'Unknown',
                              w['sets']?.toString() ?? '-',
                              w['details'] ?? '-',
                              dur,
                              link != null && link.toString().isNotEmpty,
                              link,
                              actualId,
                              isCompleted,
                              resultText,
                            ),
                          );
                        });
                      }),
                    ],
                  );
                },
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AppBottomNav(activeIndex: 0),
    );
  }

  Widget _buildResumeItem(String title, String sets, String details) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            'Sets: $sets | Details: $details',
            style: const TextStyle(color: AppTheme.secondaryTextColor),
          ),
          const SizedBox(height: 12),
          const Divider(color: AppTheme.cardColor, height: 1),
        ],
      ),
    );
  }

  Widget _buildDetailedExercise(String category, String title, String sets, String reps, String duration, bool hasVideo, String? videoLink, String wodExerciseId, bool isCompleted, String? resultText) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(category, style: const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 12),
          Text('Sets: $sets', style: const TextStyle(color: Colors.white, fontSize: 16)),
          Text('Reps/Details: $reps', style: const TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Time:', style: TextStyle(color: Colors.white, fontSize: 14)),
          const Text('Rest:', style: TextStyle(color: Colors.white, fontSize: 14)),
          const Text('Round rest:', style: TextStyle(color: Colors.white, fontSize: 14)),
          Text('Duração: $duration', style: const TextStyle(color: Colors.white, fontSize: 14)),
          if (hasVideo) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _VideoPlayerItem(videoLink: videoLink.toString()),
            ),
          ],
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => WorkoutResultFormScreen(title: title, wodExerciseId: wodExerciseId)));
              setState(() {
                _workoutsFuture = SupabaseService.getWorkoutsForSession(widget.sessionKey);
              });
            },
            icon: Icon(isCompleted ? Icons.check_circle : Icons.edit, color: AppTheme.backgroundColor, size: 18),
            label: Text(isCompleted ? 'Resultado: $resultText' : 'Lance seu resultado', style: const TextStyle(color: AppTheme.backgroundColor, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryTeal,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoPlayerItem extends StatefulWidget {
  final String videoLink;

  const _VideoPlayerItem({required this.videoLink});

  @override
  State<_VideoPlayerItem> createState() => _VideoPlayerItemState();
}

class _VideoPlayerItemState extends State<_VideoPlayerItem> {
  bool _isPlaying = false;
  String? _videoId;
  String? _uniqueViewId;
  String _thumbUrl = 'https://img.youtube.com/vi/placeholder/0.jpg';

  @override
  void initState() {
    super.initState();
    try {
      String url = widget.videoLink;
      if (url.contains('youtu.be/')) {
        _videoId = url.split('youtu.be/').last.split('?').first;
      } else if (url.contains('shorts/')) {
        _videoId = url.split('shorts/').last.split('?').first.split('/').first;
      } else if (url.contains('v=')) {
        _videoId = url.split('v=').last.split('&').first;
      }
      
      if (_videoId != null && _videoId!.length >= 11) {
        _videoId = _videoId!.substring(0, 11);
        _thumbUrl = 'https://img.youtube.com/vi/$_videoId/hqdefault.jpg';
      } else {
        _videoId = null;
      }
    } catch (_) {}
  }

  void _startVideo() {
    setState(() {
      _isPlaying = true;
      if (_videoId != null) {
        _uniqueViewId = 'yt_${_videoId!}_${DateTime.now().millisecondsSinceEpoch}';
        ui_web.platformViewRegistry.registerViewFactory(_uniqueViewId!, (int id) {
          return html.IFrameElement()
            ..src = 'https://www.youtube.com/embed/${_videoId!}?autoplay=1&playsinline=1'
            ..style.border = 'none'
            ..allowFullscreen = true
            ..allow = 'autoplay; fullscreen';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isPlaying) {
      if (_uniqueViewId != null) {
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: HtmlElementView(viewType: _uniqueViewId!),
        );
      } else {
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(color: Colors.red, child: Center(child: Text('URL Inválida: ${widget.videoLink}', style: const TextStyle(color: Colors.white)))),
        );
      }
    }

    return GestureDetector(
      onTap: _startVideo,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.network(
                _thumbUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey[800], child: const Center(child: Text('Video Link Available', style: TextStyle(color: Colors.white70)))),
              ),
              const Icon(Icons.play_circle_fill, color: Colors.red, size: 60),
            ],
          ),
        ),
      ),
    );
  }
}
