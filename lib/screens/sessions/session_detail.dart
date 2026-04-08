import 'package:flutter/material.dart';
import 'package:holy_squat_app/widgets/theme_toggle_button.dart';
import 'package:intl/intl.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/screens/workout_result_form_screen.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:holy_squat_app/widgets/app_bottom_nav.dart';
import 'package:holy_squat_app/services/supabase_service.dart';

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
    final DateTime date = widget.sessionData['date'] != null
        ? DateTime.parse(widget.sessionData['date'])
        : DateTime.now();
    final String dayName = DateFormat('EEEE').format(date).toUpperCase();
    final String title = widget.sessionData['session_type'] ?? 'Session';
    final String sessionNum =
        widget.sessionData['session_num']?.toString() ?? '1';
    final String formattedDate = DateFormat('dd/MM/yyyy').format(date);
    final String? aiCoachName = widget.sessionData['ai_coach_name'] as String?;

    Color coachColor(String? name) {
      if (name == null) return Colors.grey;
      if (name.toLowerCase().contains('gemini')) return const Color(0xFF1565C0);
      if (name.toLowerCase().contains('claude')) return const Color(0xFF6A1B9A);
      return Colors.grey.shade600;
    }

    String getSessionIcon(String? type) {
      if (type == null) return 'assets/sessions_icons/crossfit_session_icon.png';
      String t = type.toLowerCase();
      if (t.contains('lpo')) return 'assets/sessions_icons/lpo_session_icon.png';
      if (t.contains('força') || t.contains('strength')) return 'assets/sessions_icons/strengh_session_icon.png';
      if (t.contains('mobilidade') || t.contains('prehab')) return 'assets/sessions_icons/mobility_session_icon.png';
      if (t.contains('ginástica') || t.contains('calistenia')) return 'assets/sessions_icons/calistenia_session_icon.png';
      if (t.contains('recuperação') || t.contains('recovery')) return 'assets/sessions_icons/recovery_session_icon.png';
      if (t.contains('corrida') || t.contains('run')) return 'assets/sessions_icons/run_session_icon.png';
      if (t.contains('core')) return 'assets/sessions_icons/core_session_icon.png';
      if (t.contains('relax') || t.contains('descanso')) return 'assets/sessions_icons/relax_session_icon.png';
      if (t.contains('swimming') || t.contains('natação') || t.contains('nataçao')) return 'assets/sessions_icons/swimming_session_icon.png';
      return 'assets/sessions_icons/crossfit_session_icon.png';
    }

    final String imgSrc = getSessionIcon(title);

    return Scaffold(
      appBar: AppBar(
        actions: const [ThemeToggleButton()],
        title: const Text(
          'Full Session',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
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
                        child: Image.asset(
                            imgSrc,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.fitness_center, size: 40),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SESSION $sessionNum',
                          style: const TextStyle(
                            color: AppTheme.primaryTeal,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$dayName | $formattedDate',
                          style: const TextStyle(
                            color: AppTheme.secondaryTextColor,
                            fontSize: 14,
                          ),
                        ),
                        if (aiCoachName != null && aiCoachName.isNotEmpty) ...[  
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: coachColor(aiCoachName).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: coachColor(aiCoachName).withOpacity(0.45), width: 1),
                            ),
                            child: Text(
                              aiCoachName.contains('Gemini') ? '🔵 $aiCoachName' : aiCoachName.contains('Claude') ? '🟣 $aiCoachName' : '🤖 $aiCoachName',
                              style: TextStyle(
                                color: coachColor(aiCoachName),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const Text(
                'Resume',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),

              // FutureBuilder for fetching workouts
              FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
                future: _workoutsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.primaryTeal,
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    );
                  }

                  final stages = snapshot.data ?? {};
                  if (stages.isEmpty) {
                    return const Text(
                      'No workouts found for this session.',
                      style: TextStyle(color: AppTheme.secondaryTextColor),
                    );
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
                              Text(
                                entry.key,
                                style: const TextStyle(
                                  color: AppTheme.primaryTeal,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check, color: AppTheme.backgroundColor),
                            SizedBox(width: 8),
                            Text(
                              'All session done',
                              style: TextStyle(
                                color: AppTheme.backgroundColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'WOD',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Detailed views
                      ...stages.entries.expand((entry) {
                        return entry.value.map((w) {
                          final dur = w['time_exercise'] != null
                              ? '${w['time_exercise']} min'
                              : '-';
                          final link = w['workout_link'];

                          final actualId = w['wod_exercise_id'].toString();

                          List<dynamic> logs = w['filtered_logs'] ?? [];
                          
                          final bool isCompleted = logs.isNotEmpty;
                          String? resultText;
                          if (isCompleted) {
                            final log = logs.first;
                            resultText =
                                log['duration_done'] ??
                                log['weight']?.toString() ??
                                log['cardio_result']?.toString() ??
                                'Feito';
                          }

                          final timeEx = w['time_exercise']?.toString() ?? '-';
                          final rest = w['rest']?.toString() ?? '-';
                          final restRound = w['rest_round']?.toString() ?? '-';

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
                              w['adaptacaoLesao'],
                              timeEx: timeEx,
                              rest: rest,
                              restRound: restRound,
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
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
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

  Widget _buildDetailedExercise(
    String category,
    String title,
    String sets,
    String reps,
    String duration,
    bool hasVideo,
    String? videoLink,
    String wodExerciseId,
    bool isCompleted,
    String? resultText,
    String? adaptacaoLesao, {
    String timeEx = '-',
    String rest = '-',
    String restRound = '-',
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            category,
            style: const TextStyle(
              color: AppTheme.primaryTeal,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          const SizedBox(height: 12),
          Text(
            'Sets: $sets',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          Text(
            'Reps/Details: $reps',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          if (adaptacaoLesao != null && adaptacaoLesao.toString().trim().isNotEmpty && adaptacaoLesao.toString().toLowerCase() != 'string (opcional)') ...[
            const SizedBox(height: 8),
            Text(
              'Adaptação/Lesão: $adaptacaoLesao',
              style: const TextStyle(
                color: Colors.orangeAccent, 
                fontSize: 16, 
                fontWeight: FontWeight.bold
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Time: $timeEx',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          Text(
            'Rest: $rest',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          Text(
            'Round rest: $restRound',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          Text(
            'Duração: $duration',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
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
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WorkoutResultFormScreen(
                    title: title,
                    wodExerciseId: wodExerciseId,
                  ),
                ),
              );
              setState(() {
                _workoutsFuture = SupabaseService.getWorkoutsForSession(
                  widget.sessionKey,
                );
              });
            },
            icon: Icon(
              isCompleted ? Icons.check_circle : Icons.edit,
              color: AppTheme.backgroundColor,
              size: 18,
            ),
            label: Text(
              isCompleted ? 'Resultado: $resultText' : 'Lance seu resultado',
              style: const TextStyle(
                color: AppTheme.backgroundColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryTeal,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
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
  YoutubePlayerController? _youtubeController;
  
  String? _driveImageUrl;
  String? _youtubeVideoId;
  bool _isYoutube = false;
  bool _isDrive = false;
  bool _isWindows = false;

  @override
  void initState() {
    super.initState();
    try {
      if (!kIsWeb) {
        _isWindows = Platform.isWindows;
      }
    } catch (_) {}
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    final String url = widget.videoLink.trim();

    // Usar o método oficial do pacote para extrair o ID do YouTube
    final String? videoId = YoutubePlayerController.convertUrlToId(url);

    if (videoId != null) {
      _isYoutube = true;
      _youtubeVideoId = videoId;
      
      if (!_isWindows) {
        try {
          _youtubeController = YoutubePlayerController.fromVideoId(
            videoId: videoId,
            autoPlay: false,
            params: const YoutubePlayerParams(
              showFullscreenButton: true,
              mute: false,
              showControls: true,
            ),
          );
        } catch (_) {}
        if (mounted) setState(() {});
      }
    } else if (url.contains('drive.google.com')) {
      _isDrive = true;
      try {
        final idMatch = RegExp(r'\/d\/([a-zA-Z0-9_-]+)').firstMatch(url);
        if (idMatch != null) {
          final id = idMatch.group(1);
          _driveImageUrl = 'https://drive.google.com/uc?id=$id';
        }
      } catch (_) {}
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _youtubeController?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_isYoutube) {
      if (_isWindows && _youtubeVideoId != null) {
        final thumbUrl = 'https://img.youtube.com/vi/$_youtubeVideoId/hqdefault.jpg';
        return GestureDetector(
          onTap: () async {
            final Uri url = Uri.parse(widget.videoLink);
            if (await canLaunchUrl(url)) {
              await launchUrl(url);
            }
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.network(
                thumbUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.grey[800],
                  child: const Center(
                    child: Text(
                      'Thumbnail indisponível',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
              const Icon(Icons.play_circle_fill, color: Colors.red, size: 60),
            ],
          ),
        );
      } else if (_youtubeController != null) {
        return YoutubePlayer(
          controller: _youtubeController!,
          aspectRatio: 16 / 9,
        );
      }
    }

    if (_isDrive && _driveImageUrl != null) {
      return Image.network(
        _driveImageUrl!,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _buildFallback('Erro ao carregar imagem do Drive'),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(
            child: CircularProgressIndicator(color: Colors.white24),
          );
        },
      );
    }

    return _buildFallback('Link não suportado: ${widget.videoLink}');
  }

  Widget _buildFallback(String message) {
    return Container(
      color: Colors.grey[900],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image, color: Colors.white24, size: 40),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
