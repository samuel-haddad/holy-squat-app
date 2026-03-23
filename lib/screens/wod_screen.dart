import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/widgets/app_drawer.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'package:holy_squat_app/screens/sessions/session_detail.dart';
import 'package:holy_squat_app/widgets/theme_toggle_button.dart';
import 'package:holy_squat_app/core/app_state.dart';
import 'package:intl/intl.dart';

class WodScreen extends StatefulWidget {
  const WodScreen({super.key});

  @override
  State<WodScreen> createState() => _WodScreenState();
}

class _WodScreenState extends State<WodScreen> {
  late Future<List<Map<String, dynamic>>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _sessionsFuture = SupabaseService.getSessions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 40),
              Center(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: AppState.selectedWodDate.value,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      builder: (context, child) {
                        return Theme(
                          data: ThemeData.dark().copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: AppTheme.primaryTeal,
                              onPrimary: Colors.black,
                              surface: AppTheme.cardColor,
                              onSurface: Colors.white,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      AppState.selectedWodDate.value = picked;
                    }
                  },
                  child: ValueListenableBuilder<DateTime>(
                    valueListenable: AppState.selectedWodDate,
                    builder: (context, date, _) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'WOD - ${DateFormat('dd MMM yyyy').format(date)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.keyboard_arrow_down),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ValueListenableBuilder<DateTime>(
                  valueListenable: AppState.selectedWodDate,
                  builder: (context, selectedDate, _) {
                    return FutureBuilder<List<Map<String, dynamic>>>(
                      future: _sessionsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal));
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                        }
                        
                        final sessions = snapshot.data ?? [];
                        if (sessions.isEmpty) {
                          return const Center(child: Text('No WOD available', style: TextStyle(color: AppTheme.secondaryTextColor)));
                        }

                        // Get matching session
                        final targetDate = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
                        Map<String, dynamic>? matchingSession;
                        for (var s in sessions) {
                          try {
                            final d = DateTime.parse(s['date']);
                            final sessionDate = DateTime(d.year, d.month, d.day);
                            if (sessionDate.isAtSameMomentAs(targetDate)) {
                              matchingSession = s;
                              break;
                            }
                          } catch (_) {}
                        }
                        
                        if (matchingSession == null) {
                           return const Center(child: Padding(
                             padding: EdgeInsets.all(32.0),
                             child: Text('Nenhum WOD cadastrado para esta data.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.secondaryTextColor)),
                           ));
                        }

                        return _buildWodCard(context, matchingSession);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Stack(
      children: [
        Theme.of(context).brightness == Brightness.dark
            ? Image.asset(
                'assets/header_imgs/wod_blue_dark_light_mode.png',
                width: double.infinity,
                fit: BoxFit.fitWidth,
                errorBuilder: (context, error, stackTrace) => Container(color: AppTheme.primaryTeal, width: double.infinity, height: 120, child: const Center(child: Text('WOD', style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)))),
              )
            : Image.asset(
                'assets/header_imgs/wod_black_bg_transparent.png',
                width: double.infinity,
                fit: BoxFit.fitWidth,
                errorBuilder: (context, error, stackTrace) => Container(color: Colors.black, width: double.infinity, height: 120, child: const Center(child: Text('WOD', style: TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)))),
              ),
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.cardColor.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {
                  Scaffold.of(context).openDrawer();
                },
              ),
            ),
          ),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: const ThemeToggleButton(),
        ),
      ],
    );
  }

  Widget _buildWodCard(BuildContext context, Map<String, dynamic> session) {
    // Parse Supabase data fields
    final dayName = session['day'] ?? 'DAY';
    final dateStr = session['date'] ?? '1970-01-01';
    final sessionType = session['session_type'] ?? 'Session';
    final sessionNum = session['session']?.toString() ?? '1';
    final sessionKey = session['date_session_sessiontype_key'] ?? '';
    
    // Parse Date for display formatting
    String formattedDate = dateStr;
    try {
      final parsedDate = DateTime.parse(dateStr);
      formattedDate = DateFormat('yyyy-MM-dd').format(parsedDate);
    } catch (_) {}

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
       if (t.contains('relax')) return 'assets/sessions_icons/relax_session_icon.png';
       if (t.contains('swimming') || t.contains('natação') || t.contains('nataçao')) return 'assets/sessions_icons/swimming_session_icon.png';
       return 'assets/sessions_icons/crossfit_session_icon.png';
    }

    final imgSrc = getSessionIcon(sessionType);

    return InkWell(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => SessionDetailScreen(sessionData: session, sessionKey: sessionKey),
        ));
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                        imgSrc,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.fitness_center, size: 100, color: Colors.grey),
                      ),
                ),
              ),
              const SizedBox(height: 16),
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  children: [
                    TextSpan(
                      text: '$dayName ',
                      style: const TextStyle(color: AppTheme.primaryTeal),
                    ),
                    TextSpan(
                      text: '| $formattedDate',
                      style: const TextStyle(color: AppTheme.primaryTeal),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sessionType,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Session: $sessionNum',
                style: const TextStyle(
                  fontSize: 16,
                  color: AppTheme.secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
