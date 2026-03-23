import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/widgets/app_drawer.dart';
import 'package:holy_squat_app/screens/sessions/session_detail.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'package:holy_squat_app/widgets/theme_toggle_button.dart';
import 'package:intl/intl.dart';

class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  late Future<List<Map<String, dynamic>>> _sessionsFuture;
  DateTime _selectedFilterDate = DateTime.now();
  String? _selectedObjective;

  @override
  void initState() {
    super.initState();
    _sessionsFuture = SupabaseService.getSessions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Sessions', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: const [ThemeToggleButton()],
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            const Text('date start', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildDateField(),
            const SizedBox(height: 16),
            const Text('Objective', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildDropdown(),
            const SizedBox(height: 24),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _sessionsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal));
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                  }
                  
                  final sessions = (snapshot.data ?? []).reversed.toList();
                  
                  final filteredSessions = sessions.where((s) {
                    try {
                      // Objective Filter
                      if (_selectedObjective != null) {
                        final type = s['session_type']?.toString().trim() ?? '';
                        if (type != _selectedObjective) return false;
                      }

                      // Date Filter
                      final d = DateTime.parse(s['date']);
                      final sessionDay = DateTime(d.year, d.month, d.day);
                      final filterDay = DateTime(_selectedFilterDate.year, _selectedFilterDate.month, _selectedFilterDate.day);
                      return sessionDay.compareTo(filterDay) >= 0;
                    } catch (_) { return false; }
                  }).toList();

                  if (filteredSessions.isEmpty) {
                    return const Center(child: Text('Nenhuma sessão encontrada após esta data.', style: TextStyle(color: AppTheme.secondaryTextColor)));
                  }

                  return ListView.separated(
                    itemCount: filteredSessions.length,
                    separatorBuilder: (context, index) => const Divider(color: AppTheme.cardColor, height: 1),
                    itemBuilder: (context, index) {
                      final session = filteredSessions[index];
                      return _buildSessionTile(session);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField() {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedFilterDate,
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
          setState(() {
            _selectedFilterDate = picked;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: AppTheme.secondaryTextColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(DateFormat('dd MMM yyyy').format(_selectedFilterDate), style: const TextStyle(color: Colors.white, fontSize: 16)),
            ),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown() {
    return InkWell(
      onTap: () async {
        final sessions = await _sessionsFuture;
        final Set<String> uniqueTypes = {};
        for (var s in sessions) {
          if (s['session_type'] != null && s['session_type'].toString().trim().isNotEmpty) {
            uniqueTypes.add(s['session_type'].toString().trim());
          }
        }
        final typesList = uniqueTypes.toList()..sort();
        
        if (!context.mounted) return;
        
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppTheme.backgroundColor,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          builder: (context) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  const Text('Select Objective', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('All Objectives', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      setState(() {
                        _selectedObjective = null;
                      });
                      Navigator.pop(context);
                    },
                    trailing: _selectedObjective == null ? const Icon(Icons.check, color: AppTheme.primaryTeal) : null,
                  ),
                  ...typesList.map((type) => ListTile(
                    title: Text(type, style: const TextStyle(color: Colors.white)),
                    onTap: () {
                      setState(() {
                        _selectedObjective = type;
                      });
                      Navigator.pop(context);
                    },
                    trailing: _selectedObjective == type ? const Icon(Icons.check, color: AppTheme.primaryTeal) : null,
                  )),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        );
      },
      );
    },
    child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_selectedObjective ?? 'All Objectives', style: const TextStyle(color: Colors.white, fontSize: 16)),
            const Icon(Icons.keyboard_arrow_down, color: AppTheme.secondaryTextColor),
          ],
        ),
      ),
    );
  }
  Widget _buildSessionTile(Map<String, dynamic> session) {
    // Parse Supabase data fields
    final dayName = session['day'] ?? 'DAY';
    final dateStr = session['date'] ?? '1970-01-01';
    final sessionType = session['session_type'] ?? 'Session';
    final sessionNum = session['session']?.toString() ?? '1';
    final sessionKey = session['date_session_sessiontype_key'] ?? '';
    
    // Parse Date for display formatting if valid date
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: AppTheme.cardColor,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                      imgSrc,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.fitness_center),
                    ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      children: [
                        TextSpan(text: '$dayName ', style: const TextStyle(color: AppTheme.primaryTeal)),
                        TextSpan(text: '| $formattedDate', style: const TextStyle(color: AppTheme.primaryTeal)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sessionType,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Session: $sessionNum',
                    style: const TextStyle(
                      color: AppTheme.secondaryTextColor,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.secondaryTextColor),
          ],
        ),
      ),
    );
  }
}

