import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'package:holy_squat_app/widgets/app_drawer.dart';
import 'package:holy_squat_app/widgets/app_bottom_nav.dart';
import 'package:holy_squat_app/screens/planning/create_plan_screen.dart';

class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  Map<String, dynamic>? _currentPlan;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    setState(() => _isLoading = true);
    final plan = await SupabaseService.fetchLatestTrainingPlan();
    setState(() {
      _currentPlan = plan;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Planning'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      drawer: const AppDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildExpandableSection(
                    title: 'Actual Plan',
                    content: _currentPlan?['actual_plan_summary'] ?? 'Nenhum plano ativo no momento.',
                  ),
                  const SizedBox(height: 16),
                  _buildExpandableSection(
                    title: 'Workouts Plan',
                    isWorkouts: true,
                    text: _currentPlan?['workouts_plan_text'] ?? 'Prescrições pendentes.',
                    tableData: _currentPlan?['workouts_plan_table'],
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CreatePlanScreen()),
                      );
                      if (result == true) {
                        _loadPlan();
                      }
                    },
                    child: const Text(
                      'Create a New Plan',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: const AppBottomNav(),
    );
  }

  Widget _buildExpandableSection({
    required String title,
    String? content,
    bool isWorkouts = false,
    String? text,
    dynamic tableData,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          childrenPadding: const EdgeInsets.all(16.0),
          iconColor: AppTheme.primaryTeal,
          collapsedIconColor: Colors.white,
          children: [
            if (!isWorkouts)
              Text(
                content ?? '',
                style: const TextStyle(color: AppTheme.secondaryTextColor),
              ),
            if (isWorkouts) ...[
              if (text != null)
                Text(
                  text,
                  style: const TextStyle(color: AppTheme.secondaryTextColor),
                ),
              if (tableData != null && tableData is List) ...[
                const SizedBox(height: 16),
                _buildWorkoutsTable(tableData),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWorkoutsTable(List data) {
    if (data.isEmpty) return const SizedBox.shrink();
    
    // Assume each item is a Map with 'day', 'workout', 'details'
    return Table(
      border: TableBorder.all(color: Colors.white.withOpacity(0.1), width: 1),
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05)),
          children: const [
            Padding(padding: EdgeInsets.all(8), child: Text('Dia', style: TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold))),
            Padding(padding: EdgeInsets.all(8), child: Text('Treino', style: TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold))),
          ],
        ),
        ...data.map((item) {
          final map = item as Map;
          return TableRow(
            children: [
              Padding(padding: const EdgeInsets.all(8), child: Text(map['day']?.toString() ?? '', style: const TextStyle(color: Colors.white))),
              Padding(padding: const EdgeInsets.all(8), child: Text(map['workout']?.toString() ?? '', style: const TextStyle(color: AppTheme.secondaryTextColor))),
            ],
          );
        }).toList(),
      ],
    );
  }
}
