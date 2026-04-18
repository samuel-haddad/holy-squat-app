import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/widgets/app_drawer.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'package:holy_squat_app/widgets/theme_toggle_button.dart';
import 'package:holy_squat_app/screens/planning/edit_plan_detail_screen.dart';
import 'package:intl/intl.dart';

class EditPlanScreen extends StatefulWidget {
  const EditPlanScreen({super.key});

  @override
  State<EditPlanScreen> createState() => _EditPlanScreenState();
}

class _EditPlanScreenState extends State<EditPlanScreen> {
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  Map<String, dynamic>? _selectedCoach;
  String _workMode = 'Sessions'; // 'Sessions' or 'WODs'
  
  List<Map<String, dynamic>> _coaches = [];
  bool _isLoadingCoaches = true;
  bool _isSearching = false;
  List<Map<String, dynamic>> _groupedResults = [];

  @override
  void initState() {
    super.initState();
    _loadCoaches();
  }

  Future<void> _loadCoaches() async {
    final coaches = await SupabaseService.getAICoaches();
    setState(() {
      _coaches = coaches;
      _isLoadingCoaches = false;
      if (_coaches.isNotEmpty) {
        _selectedCoach = _coaches.first;
        _search(); // Initial search once coaches are loaded
      }
    });
  }

  Future<void> _search() async {
    if (_selectedCoach == null) return;
    
    setState(() {
      _isSearching = true;
      _groupedResults = [];
    });

    try {
      final coachName = _selectedCoach!['ai_coach_name'];
      if (_workMode == 'Sessions') {
        final sessions = await SupabaseService.getSessionsWithFilters(
          start: _startDate,
          end: _endDate,
          coach: coachName,
        );
        _groupedResults = _groupSessions(sessions);
      } else {
        final workouts = await SupabaseService.getWorkoutsWithFilters(
          start: _startDate,
          end: _endDate,
          coach: coachName,
        );
        _groupedResults = _groupWorkouts(workouts);
      }
    } catch (e) {
      debugPrint('Error searching: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isSearching = false);
    }
  }

  List<Map<String, dynamic>> _groupSessions(List<Map<String, dynamic>> sessions) {
    final Map<String, Map<String, dynamic>> groups = {};
    for (var s in sessions) {
      final key = '${s['session_type']}_${s['session']}';
      if (!groups.containsKey(key)) {
        groups[key] = {
          'session_type': s['session_type'],
          'session': s['session'],
          'icons': s['icons'], // needed for image
          'count': 0,
          'items': [], // can store all items if needed, but original attributes are enough
          'original_attributes': {
            'session_type': s['session_type'],
            'session': s['session'],
            'duration': s['duration'],
          }
        };
      }
      groups[key]!['count']++;
    }
    return groups.values.toList();
  }

  List<Map<String, dynamic>> _groupWorkouts(List<Map<String, dynamic>> workouts) {
    final Map<String, Map<String, dynamic>> groups = {};
    final groupKeys = [
      'mesocycle', 'day', 'exercise', 'sets', 'details', 
      'time_exercise', 'ex_unit', 'rest', 'rest_unit',
      'total_time', 'location', 'stage'
    ];
    final allFields = [...groupKeys, 'exercise_title'];

    for (var w in workouts) {
      final keyParts = groupKeys.map((f) => w[f]?.toString() ?? 'null').join('|');
      if (!groups.containsKey(keyParts)) {
        final original = <String, dynamic>{};
        for (var f in allFields) {
          original[f] = w[f];
        }
        groups[keyParts] = {
          ...original,
          'count': 0,
          'original_attributes': Map<String, dynamic>.from(original)..remove('exercise_title'), 
          // exercise_title is editable but not part of original grouping key
        };
      }
      groups[keyParts]!['count']++;
    }
    return groups.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Edit Plan', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: const [ThemeToggleButton()],
      ),
      body: Column(
        children: [
          _buildFilters(),
          const Divider(color: AppTheme.cardColor, height: 1),
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
                : _buildResultsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _buildDateField('Start Date', _startDate, (d) => setState(() => _startDate = d))),
              const SizedBox(width: 12),
              Expanded(child: _buildDateField('End Date', _endDate, (d) => setState(() => _endDate = d), isRequired: false)),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Coach', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.secondaryTextColor)),
          const SizedBox(height: 8),
          _buildCoachDropdown(),
          const SizedBox(height: 16),
          _buildWorkModeSelector(),
          // Section removed to enable automatic filtering
        ],
      ),
    );
  }

  Widget _buildDateField(String label, DateTime? value, Function(DateTime) onPicked, {bool isRequired = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.secondaryTextColor)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: isRequired ? DateTime.now() : DateTime(2020),
              lastDate: DateTime(2030),
              builder: (context, child) => Theme(
                data: ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppTheme.primaryTeal,
                    onPrimary: Colors.black,
                    surface: AppTheme.cardColor,
                    onSurface: Colors.white,
                  ),
                ),
                child: child!,
              ),
            );
            if (picked != null) {
              onPicked(picked);
              _search();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: AppTheme.secondaryTextColor, size: 16),
                const SizedBox(width: 8),
                Text(
                  value != null ? DateFormat('dd/MM/yyyy').format(value) : 'Select date',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCoachDropdown() {
    return InkWell(
      onTap: _isLoadingCoaches ? null : () => _showCoachPicker(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _selectedCoach?['ai_coach_name'] ?? 'Select Coach',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const Icon(Icons.keyboard_arrow_down, color: AppTheme.secondaryTextColor),
          ],
        ),
      ),
    );
  }

  void _showCoachPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.backgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Select Coach', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ..._coaches.map((c) => ListTile(
              title: Text(c['ai_coach_name'], style: const TextStyle(color: Colors.white)),
              onTap: () {
                setState(() => _selectedCoach = c);
                Navigator.pop(context);
                _search();
              },
              trailing: _selectedCoach == c ? const Icon(Icons.check, color: AppTheme.primaryTeal) : null,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkModeSelector() {
    return Row(
      children: [
        _buildModeButton('Sessions'),
        const SizedBox(width: 12),
        _buildModeButton('WODs'),
      ],
    );
  }

  Widget _buildModeButton(String mode) {
    bool isSelected = _workMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _workMode = mode);
          _search();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryTeal : AppTheme.cardColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              mode,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsList() {
    if (_groupedResults.isEmpty) {
      return const Center(child: Text('No results found.', style: TextStyle(color: AppTheme.secondaryTextColor)));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _groupedResults.length,
      separatorBuilder: (context, index) => const Divider(color: AppTheme.cardColor, height: 1),
      itemBuilder: (context, index) {
        final group = _groupedResults[index];
        return _workMode == 'Sessions' ? _buildSessionTile(group) : _buildWodTile(group);
      },
    );
  }

  Widget _buildSessionTile(Map<String, dynamic> group) {
    final type = group['session_type'] ?? 'Session';
    final sessionNum = group['session']?.toString() ?? '1';
    
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

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: AppTheme.cardColor),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(getSessionIcon(type), fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.fitness_center)),
        ),
      ),
      title: Text(type, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      subtitle: Text('Session: $sessionNum - ${group['original_attributes']['duration'] ?? 60} min (${group['count']} instances)', style: const TextStyle(color: AppTheme.secondaryTextColor, fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.secondaryTextColor),
      onTap: () => _goToDetail(group),
    );
  }

  Widget _buildWodTile(Map<String, dynamic> group) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      title: Text(group['exercise'] ?? 'Workout', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primaryTeal.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.primaryTeal.withOpacity(0.5)),
            ),
            child: Text(
              'Mesocycle: ${group['mesocycle'] ?? '-'}',
              style: const TextStyle(color: AppTheme.primaryTeal, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${group['day']} - ${group['sets']} sets (${group['count']} instances)',
            style: const TextStyle(color: AppTheme.secondaryTextColor, fontSize: 14),
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.secondaryTextColor),
      onTap: () => _goToDetail(group),
    );
  }

  void _goToDetail(Map<String, dynamic> group) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditPlanDetailScreen(
          mode: _workMode,
          group: group,
          startDate: _startDate,
          endDate: _endDate,
          coach: _selectedCoach!['ai_coach_name'],
        ),
      ),
    );
    if (result == true) {
      _search(); // Refresh results after save
    }
  }
}
