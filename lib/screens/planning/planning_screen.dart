import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'package:holy_squat_app/widgets/app_drawer.dart';
import 'package:holy_squat_app/widgets/app_bottom_nav.dart';
import 'package:holy_squat_app/screens/planning/create_plan_screen.dart';
import 'package:holy_squat_app/controllers/workout_controller.dart';
import 'package:holy_squat_app/repositories/workout_repository.dart';
import 'package:holy_squat_app/core/user_state.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:math' as math;

class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  Map<String, Map<String, dynamic>?> _coachPlans = {};
  bool _isLoading = true;
  List<Map<String, dynamic>> _aiCoaches = [];
  // Snapshot stats are now retrieved from each individual plan record

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final repo = WorkoutRepository();
      // Get dynamic email
      final String userEmail = SupabaseService.client.auth.currentUser?.email ?? UserState.email.value;

      // 1. Load Coaches
      _aiCoaches = await repo.fetchAiCoaches();

      // 2. Load the latest plan for each coach and statistics
      final Map<String, Map<String, dynamic>?> plans = {};
      for (var coach in _aiCoaches) {
        final name = coach['ai_coach_name'] as String;
        final plan = await SupabaseService.fetchLatestTrainingPlan(aiCoachName: name);
        plans[name] = plan;
      }

      // 3. (Legacy) _athleteStats is now static per plan. No need for global dynamic fetch.
      
      if (mounted) {
        setState(() {
          _coachPlans = plans;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados: $e');
      if (mounted) setState(() => _isLoading = false);
    }
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
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: _aiCoaches.length,
                itemBuilder: (context, index) {
                  final coach = _aiCoaches[index];
                  return _buildCoachSection(coach);
                },
              ),
            ),
      bottomNavigationBar: const AppBottomNav(),
    );
  }

  Widget _buildCoachSection(Map<String, dynamic> coach) {
    final String name = coach['ai_coach_name'] as String;
    final plan = _coachPlans[name];
    final color = _parseColor(coach['color_hex']);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Text(coach['icon_emoji'] ?? '🤖', style: const TextStyle(fontSize: 20)),
          ),
          title: Text(
            coach['ai_coach_name'] ?? 'Coach',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          subtitle: Text(
            coach['description'] ?? '',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          childrenPadding: const EdgeInsets.all(16),
          children: [
            if (plan == null) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('Nenhum plano ativo com este Coach.', style: TextStyle(color: AppTheme.secondaryTextColor)),
                ),
              ),
              _buildCreatePlanButton(coach),
            ] else ...[
              _buildActualPlanSection(
                plan['actual_plan_summary'],
                plan['workouts_plan_text'],
                plan,
                plan['snapshot_stats'],
              ),
              const SizedBox(height: 16),
              ..._buildWorkoutsPlanSections(plan['workouts_plan_table']),
              const SizedBox(height: 16),
              _buildProgressSection(plan['progress_analysis'], plan, coach),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _buildCreatePlanButton(coach)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildGenerateNextButton(coach, plan)),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return AppTheme.primaryTeal;
    try {
      return Color(int.parse(hex.replaceAll('#', '0xFF')));
    } catch (_) {
      return AppTheme.primaryTeal;
    }
  }

  Widget _buildCreatePlanButton(Map<String, dynamic> coach) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primaryTeal,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider(
              create: (_) => WorkoutController(WorkoutRepository()),
              child: CreatePlanScreen(initialCoach: coach),
            ),
          ),
        );
        if (result == true) _loadData();
      },
      child: const Text('Create a New Plan', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildGenerateNextButton(Map<String, dynamic> coach, Map<String, dynamic> plan) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.05),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppTheme.primaryTeal, width: 0.5)),
      ),
      onPressed: () => _generateNextMeso(coach, plan),
      child: const Text('Next Cycle', style: TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildActualPlanSection(String? actualPlanSummary, String? workoutsPlanText, Map<String, dynamic> plan, dynamic snapshotStats) {
    if ((actualPlanSummary == null || actualPlanSummary.isEmpty) && (workoutsPlanText == null || workoutsPlanText.isEmpty)) {
      return _buildContainer(
        title: 'Actual Planning',
        shareText: '',
        children: [const Text('Nenhum plano ativo no momento.', style: TextStyle(color: AppTheme.secondaryTextColor))],
      );
    }

    Map<String, dynamic>? macroJson;
    Map<String, dynamic>? summaryJson;

    try {
      if (workoutsPlanText != null) macroJson = jsonDecode(workoutsPlanText);
    } catch (_) {}
    try {
      if (actualPlanSummary != null) summaryJson = jsonDecode(actualPlanSummary);
    } catch (_) {}

    // Parse snapshotStats if it's a string (though Supabase usually returns Map)
    Map<String, dynamic>? stats;
    if (snapshotStats is Map<String, dynamic>) {
      stats = snapshotStats;
    } else if (snapshotStats is String) {
      try {
        stats = jsonDecode(snapshotStats);
      } catch (_) {}
    }

    return Column(
      children: [
        _buildContainer(
          title: 'Histórico',
          shareText: _formatHistoricoForShare(macroJson),
          children: [_buildHistoricoContent(macroJson)],
        ),
        const SizedBox(height: 16),
        _buildContainer(
          title: 'Visão Geral',
          shareText: _formatActualPlanForShare(summaryJson ?? {}, ""),
          children: [
            if (stats == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Estatísticas estáticas do plano indisponíveis.\n(Recurso disponível para novos planos/ciclos)',
                    style: TextStyle(color: AppTheme.secondaryTextColor, fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              _buildBigNumbersGrid(stats['kpis']),
              const SizedBox(height: 24),
              _buildCapabilitiesRadar(stats['radar']),
              const SizedBox(height: 24),
              _buildActivityHeatmap(stats['heatmap']),
            ],
            const SizedBox(height: 24),
            _buildVisaoGeralContent(summaryJson),
          ],
        ),
        const SizedBox(height: 16),
        _buildPDFExportButton(macroJson, summaryJson, plan['progress_analysis']),
      ],
    );
  }

  Widget _buildProgressSection(String? progressJson, Map<String, dynamic> plan, Map<String, dynamic> coach) {
    if (progressJson == null || progressJson.isEmpty) {
       return _buildContainer(
        title: 'Progress',
        shareText: '',
        children: [
          const Text(
            'Inicie seu primeiro ciclo para ver sua análise de progresso aqui.',
            style: TextStyle(color: AppTheme.secondaryTextColor),
          ),
          const SizedBox(height: 16),
          _buildGenerateNextButton(coach, plan),
        ],
      );
    }

    Map<String, dynamic>? data;
    try {
      data = jsonDecode(progressJson);
    } catch (_) {}

    if (data == null) return const SizedBox.shrink();

    final kpis = data['kpis'] as Map<String, dynamic>?;
    final charts = data['charts'] as Map<String, dynamic>?;
    final cycleSnapshot = data['cycle_snapshot'] as Map<String, dynamic>?;
    final hasData = kpis != null && (kpis['completion_rate'] as num? ?? 0) > 0;

    return _buildContainer(
      title: 'Progress (Último Mesociclo)',
      shareText: "📈 *Análise de Progresso*\n\n${data['texto'] ?? ''}",
      children: [
        if (data['texto'] != null)
          Text(data['texto'], style: const TextStyle(color: AppTheme.secondaryTextColor)),
        
        const SizedBox(height: 24),
        
        if (cycleSnapshot != null) ...[
          const Text('Estado do Atleta ao Iniciar Ciclo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 12),
          _buildBigNumbersGrid(cycleSnapshot['kpis']),
          const SizedBox(height: 16),
          _buildCapabilitiesRadar(cycleSnapshot['radar']),
          const SizedBox(height: 16),
          _buildActivityHeatmap(cycleSnapshot['heatmap']),
          const SizedBox(height: 24),
          const Divider(color: Colors.white10),
          const SizedBox(height: 24),
        ],

        if (!hasData)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Nenhum treino realizado foi detectado para análise neste ciclo.',
                style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else ...[
          _buildProgressKpisGrid(kpis),
          
          const SizedBox(height: 32),
          
          if (charts != null) ...[
            _buildPlannedVsRealizedChart(charts['planned_vs_realized']),
            const SizedBox(height: 24),
            _buildLoadVsPseChart(charts['load_vs_pse']),
            const SizedBox(height: 24),
            _buildVolumeByGroupChart(charts['volume_by_group']),
          ],
        ],
      ],
    );
  }

  Widget _buildProgressKpisGrid(Map<String, dynamic>? kpis) {
    if (kpis == null) return const SizedBox.shrink();

    final items = [
      {'l': 'Conclusão', 'v': '${kpis['completion_rate']}%', 'i': Icons.check_circle_outline},
      {'l': 'Freq. Sem.', 'v': '${kpis['weekly_freq']} sv', 'i': Icons.calendar_today},
      {'l': 'Negligenciados', 'v': kpis['neglected_type'] ?? '-', 'i': Icons.warning_amber, 'c': Colors.orange},
      {'l': 'Delta Carga', 'v': '${kpis['load_delta']}%', 'i': Icons.trending_up},
      {'l': 'Recuperação PR', 'v': '${kpis['pr_recovery']}%', 'i': Icons.history},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.1,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final it = items[index];
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: (it['c'] as Color?) ?? Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(it['i'] as IconData, size: 16, color: (it['c'] as Color?) ?? AppTheme.primaryTeal),
              const SizedBox(height: 6),
              Text(it['v'] as String, 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(it['l'] as String, style: const TextStyle(color: Colors.grey, fontSize: 8), textAlign: TextAlign.center),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlannedVsRealizedChart(List<dynamic>? data) {
    if (data == null || data.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Prescrito vs Realizado (Semana)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 16),
        SizedBox(
          height: 150,
          child: data.isEmpty 
            ? const Center(child: Text('Sem dados para comparar', style: TextStyle(color: Colors.grey, fontSize: 10)))
            : BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: data.isEmpty ? 10 : data.map((e) => (e['planned'] as num? ?? 0).toDouble()).reduce((a, b) => a > b ? a : b) + 2,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, meta) => Text('S${val.toInt()+1}', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                      ),
                    ),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  barGroups: data.asMap().entries.map((e) => BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(toY: (e.value['planned'] as num? ?? 0).toDouble(), color: Colors.white.withOpacity(0.1), width: 8),
                      BarChartRodData(toY: (e.value['realized'] as num? ?? 0).toDouble(), color: AppTheme.primaryTeal, width: 8),
                    ],
                  )).toList(),
                ),
              ),
        ),
      ],
    );
  }

  Widget _buildLoadVsPseChart(List<dynamic>? data) {
    if (data == null || data.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Eficiência: Carga vs PSE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 16),
        SizedBox(
          height: 150,
          child: LineChart(
            LineChartData(
              lineBarsData: [
                LineChartBarData(
                  spots: data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value['avg_load'] as num? ?? 0).toDouble())).toList(),
                  color: AppTheme.primaryTeal,
                  barWidth: 3,
                  isCurved: true,
                  dotData: const FlDotData(show: true),
                ),
                LineChartBarData(
                  spots: data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value['avg_pse'] as num? ?? 0).toDouble() * 10)).toList(),
                  color: Colors.orange,
                  barWidth: 2,
                  dashArray: [5, 5],
                  isCurved: true,
                  dotData: const FlDotData(show: false),
                ),
              ],
              titlesData: const FlTitlesData(show: false),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVolumeByGroupChart(List<dynamic>? data) {
    if (data == null || data.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Volume por Grupo (Sets Realizados)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 16),
        SizedBox(
          height: 150,
          child: data.isEmpty
            ? const Center(child: Text('Sem volume registrado', style: TextStyle(color: Colors.grey, fontSize: 10)))
            : BarChart(
                BarChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, meta) {
                          if (val.toInt() < data.length) {
                            String label = data[val.toInt()]['exercise_group']?.toString() ?? '';
                            if (label.length > 3) label = label.substring(0, 3);
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 8)),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: data.asMap().entries.map((e) => BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: (e.value['volume'] as num? ?? 0).toDouble(),
                        color: AppTheme.primaryTeal,
                        width: 16,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ],
                  )).toList(),
                ),
              ),
        ),
      ],
    );
  }


  Widget _buildBigNumbersGrid(Map<String, dynamic>? kpis) {
    if (kpis == null) return const SizedBox.shrink();
    
    final items = [
      {'label': 'Aderência', 'value': '${kpis['adherence']}%', 'icon': Icons.bolt},
      {'label': 'PSE Médio', 'value': '${kpis['avg_pse']}', 'icon': Icons.speed},
      {'label': 'Power Index', 'value': '${kpis['power_index']}', 'icon': Icons.fitness_center},
      {'label': 'Evolução', 'value': '+${kpis['best_evolution']?['percent']}%', 'icon': Icons.trending_up, 'sub': kpis['best_evolution']?['exercise']},
      {'label': 'Streak', 'value': '${kpis['streak']} d', 'icon': Icons.fireplace},
      {'label': 'Freq. Sem.', 'value': '${kpis['weekly_freq']}/w', 'icon': Icons.calendar_view_week},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.1,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item['icon'] as IconData, size: 16, color: AppTheme.primaryTeal),
              const SizedBox(height: 4),
              Text(item['value'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 2),
              Text(item['label'] as String, style: const TextStyle(color: Colors.grey, fontSize: 9), textAlign: TextAlign.center),
              if (item['sub'] != null)
                Text(item['sub'] as String, style: const TextStyle(color: AppTheme.primaryTeal, fontSize: 7), overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCapabilitiesRadar(List<dynamic>? radarData) {
    if (radarData == null || radarData.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Aderência por tipo de exercício', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: (radarData.length < 3)
            ? const Center(child: Text('Necessário ao menos 3 categorias para o radar', style: TextStyle(color: Colors.grey, fontSize: 10)))
            : RadarChart(
                RadarChartData(
                  radarShape: RadarShape.polygon,
                  dataSets: [
                    RadarDataSet(
                      fillColor: AppTheme.primaryTeal.withOpacity(0.3),
                      borderColor: AppTheme.primaryTeal,
                      entryRadius: 3,
                      dataEntries: radarData.map((e) => RadarEntry(value: (e['count'] as num? ?? 0).toDouble())).toList(),
                    ),
                  ],
                  getTitle: (index, angle) {
                    if (index < radarData.length) {
                      return RadarChartTitle(text: radarData[index]['category']?.toString() ?? '', angle: angle);
                    }
                    return const RadarChartTitle(text: '');
                  },
                  radarBackgroundColor: Colors.transparent,
                  borderData: FlBorderData(show: false),
                ),
              ),
        ),
      ],
    );
  }

  Widget _buildActivityHeatmap(List<dynamic>? heatmapData) {
    if (heatmapData == null || heatmapData.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Constância (Últimos 6 meses)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Eixo Vertical
            RotatedBox(
              quarterTurns: 3,
              child: Container(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Dias da semana',
                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10, letterSpacing: 0.5),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: 3,
                    child: LayoutBuilder(builder: (context, constraints) {
                       return GridView.builder(
                         scrollDirection: Axis.horizontal,
                         gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                           crossAxisCount: 7,
                           mainAxisSpacing: 2,
                           crossAxisSpacing: 2,
                         ),
                         itemCount: heatmapData.length,
                         itemBuilder: (context, index) {
                           final item = heatmapData[index];
                           final intensity = (item['intensity'] as num?)?.toDouble() ?? 0.0;
                           return Container(
                             decoration: BoxDecoration(
                               color: intensity == 0 
                                  ? Colors.white.withOpacity(0.05) 
                                  : AppTheme.primaryTeal.withOpacity(0.2 + (intensity / 10).clamp(0.0, 0.8)),
                               borderRadius: BorderRadius.circular(1),
                             ),
                           );
                         },
                       );
                    }),
                  ),
                  const SizedBox(height: 12),
                  // Eixo Horizontal
                  Text(
                    'Semanas',
                    style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10, letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        // Legenda de Intensidade
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Intensidade (PSE): ',
              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 9, fontWeight: FontWeight.w300),
            ),
            const SizedBox(width: 8),
            Text('0', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9)),
            const SizedBox(width: 6),
            ...List.generate(6, (index) {
              final double intensity = index * 2.0; // Amostragem da escala de 0 a 10
              return Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: intensity == 0 
                    ? Colors.white.withOpacity(0.05) 
                    : AppTheme.primaryTeal.withOpacity(0.2 + (intensity / 10).clamp(0.0, 0.8)),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
            const SizedBox(width: 6),
            Text('10', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 9)),
          ],
        ),
      ],
    );
  }

  Widget _buildHistoricoContent(Map<String, dynamic>? json) {
    if (json == null) return const Text('Dados de histórico não disponíveis.', style: TextStyle(color: AppTheme.secondaryTextColor));
    
    final historico = json['historico'];
    if (historico == null) return Text(json['analise'] ?? '', style: const TextStyle(color: AppTheme.secondaryTextColor));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(historico['texto'] ?? '', style: const TextStyle(color: AppTheme.secondaryTextColor)),
        const SizedBox(height: 20),
        if (historico['graficos'] is List)
          ...((historico['graficos'] as List).map((g) => _buildChartSection(g)).toList()),
      ],
    );
  }

  Widget _buildChartSection(Map<String, dynamic> chart) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(chart['titulo'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: _renderChart(chart),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _renderChart(Map<String, dynamic> chart) {
    final List dados = chart['dados'] ?? [];
    if (dados.isEmpty) return const Center(child: Text('Sem dados', style: TextStyle(color: Colors.grey)));

    if (chart['tipo'] == 'linha') {
      return LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(dados.length, (i) => FlSpot(i.toDouble(), (dados[i]['y'] as num).toDouble())),
              isCurved: true,
              color: AppTheme.primaryTeal,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: AppTheme.primaryTeal.withOpacity(0.1)),
            ),
          ],
        ),
      );
    }
    
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(dados.length, (i) => BarChartGroupData(
          x: i,
          barRods: [BarChartRodData(toY: (dados[i]['y'] as num).toDouble(), color: AppTheme.primaryTeal, width: 12)],
        )),
      ),
    );
  }

  Widget _buildVisaoGeralContent(Map<String, dynamic>? json) {
    if (json == null) return const Text('Plano não disponível.', style: TextStyle(color: AppTheme.secondaryTextColor));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (json['objetivoPrincipal'] != null)
          _buildRichText('Objetivo Principal: ', json['objetivoPrincipal'].toString()),
        const SizedBox(height: 8),
        if (json['duracaoSemanas'] != null)
          _buildRichText('Duração: ', '${json['duracaoSemanas']} semanas'),
        
        if (json['fases'] is List) ...[
          const SizedBox(height: 16),
          const Text('Fases do Macro:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ...((json['fases'] as List).map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text('• ${f['nome']} (${f['duracao']}): ${f['foco']}', style: const TextStyle(color: AppTheme.secondaryTextColor, fontSize: 13)),
          ))),
        ],

        const SizedBox(height: 16),
        const Text('Mesociclos:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        if (json['blocos'] is List)
          ...((json['blocos'] as List).map((b) {
            if (b is! Map) return Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(b.toString(), style: const TextStyle(color: AppTheme.secondaryTextColor)));
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0, left: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ${b['mesociclo'] ?? 'Mesociclo'} (${b['duracaoSemanas'] ?? '?'} sem)', style: const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('${b['foco'] ?? ''}', style: const TextStyle(color: AppTheme.secondaryTextColor)),
                ],
              ),
            );
          }).toList()),
      ],
    );
  }

  Widget _buildPDFExportButton(Map<String, dynamic>? macroJson, Map<String, dynamic>? summaryJson, String? progressJson) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.05),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppTheme.primaryTeal)),
      ),
      onPressed: () => _generateAndSharePDF(macroJson, summaryJson, progressJson),
      icon: const Icon(Icons.picture_as_pdf, color: AppTheme.primaryTeal),
      label: const Text('Exportar Plano (PDF)', style: TextStyle(color: Colors.white)),
    );
  }

  String _formatHistoricoForShare(Map<String, dynamic>? json) {
    if (json == null) return "";
    final hist = json['historico'];
    if (hist == null) return json['analise'] ?? "";
    return "📈 *Análise de Histórico*\n\n${hist['texto']}";
  }

  String _sanitizePdfText(String? text) {
    if (text == null) return "";
    return text
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('•', '*')
        .replaceAll('✅', '[OK]')
        .replaceAll('❌', '[X]')
        .replaceAll('📈', '[HIST]')
        .replaceAll('🎯', '[OBJ]')
        .replaceAll('🧠', '[AI]')
        .replaceAll('’', "'")
        .replaceAll('“', '"')
        .replaceAll('”', '"');
  }

  Future<void> _generateAndSharePDF(Map<String, dynamic>? macro, Map<String, dynamic>? summary, String? progressJson) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    Map<String, dynamic>? progressData;
    try { if (progressJson != null) progressData = jsonDecode(progressJson); } catch (_) {}

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(level: 0, child: pw.Text("Relatorio de Planejamento - Holy Squat", style: pw.TextStyle(font: fontBold, fontSize: 18, color: PdfColors.teal))),
            pw.SizedBox(height: 10),
            
            pw.Text("1. Visao Geral do Atleta (KPIs)", style: pw.TextStyle(font: fontBold, fontSize: 14)),
            pw.SizedBox(height: 8),
            _buildPdfBigNumbers(_athleteStats?['kpis'], font, fontBold),
            pw.SizedBox(height: 15),

            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 1,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("Equilibrio de Capacidades", style: pw.TextStyle(font: fontBold, fontSize: 10)),
                      pw.SizedBox(height: 5),
                      _buildPdfRadarChart(_athleteStats?['radar'], 120, font),
                    ],
                  ),
                ),
                pw.SizedBox(width: 20),
                pw.Expanded(
                  flex: 1,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("Heatmap de Constancia", style: pw.TextStyle(font: fontBold, fontSize: 10)),
                      pw.SizedBox(height: 5),
                      _buildPdfHeatmap(_athleteStats?['heatmap']),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            if (progressData != null) ...[
              pw.Header(level: 1, child: pw.Text('2. Analise de Progresso (Mesociclo Anterior)')),
              pw.Text(_sanitizePdfText(progressData['texto'] ?? ''), style: pw.TextStyle(font: font, fontSize: 9)),
              pw.SizedBox(height: 12),
              
              if (progressData['kpis'] != null) ...[
                pw.Text("Metricas de Performance:", style: pw.TextStyle(font: fontBold, fontSize: 10)),
                pw.SizedBox(height: 6),
                _buildPdfBigNumbers(progressData['kpis'], font, fontBold, isProgress: true),
              ],
              
              pw.SizedBox(height: 20),
            ],

            pw.Header(level: 1, child: pw.Text('3. Planejamento Macro')),
            pw.Bullet(text: 'Objetivo: ${summary?['objetivoPrincipal'] ?? 'N/A'}', style: pw.TextStyle(font: font, fontSize: 9)),
            pw.Bullet(text: 'Duracao: ${summary?['duracaoSemanas'] ?? 'N/A'} semanas', style: pw.TextStyle(font: font, fontSize: 9)),
            pw.SizedBox(height: 10),
            pw.Text('Mesociclos:', style: pw.TextStyle(font: fontBold, fontSize: 10)),
            if (summary?['blocos'] is List)
              ...((summary?['blocos'] as List).map((b) => pw.Padding(
                padding: const pw.EdgeInsets.only(left: 10, top: 4),
                child: pw.Text('- ${_sanitizePdfText(b['mesociclo'])}: ${_sanitizePdfText(b['foco'])}', style: const pw.TextStyle(fontSize: 9)),
              ))),
            
            pw.SizedBox(height: 20),
            pw.Header(level: 1, child: pw.Text('3. Planejamento Consolidado')),
            if (summary?['mesociclo1_consolidado'] is List)
              pw.Table.fromTextArray(
                context: context,
                data: [
                  ['Sem', 'Foco', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sab', 'Dom'],
                  ...((summary?['mesociclo1_consolidado'] as List).map((s) => [
                    s['semana'].toString(),
                    _sanitizePdfText(s['foco']?.toString()),
                    _sanitizePdfText(s['seg']?.toString()),
                    _sanitizePdfText(s['ter']?.toString()),
                    _sanitizePdfText(s['qua']?.toString()),
                    _sanitizePdfText(s['qui']?.toString()),
                    _sanitizePdfText(s['sex']?.toString()),
                    _sanitizePdfText(s['sab']?.toString()),
                    _sanitizePdfText(s['dom']?.toString()),
                  ])),
                ],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.teal),
                cellStyle: const pw.TextStyle(fontSize: 7),
                columnWidths: {
                  0: const pw.FixedColumnWidth(25),
                  1: const pw.FlexColumnWidth(2.5),
                  2: const pw.FlexColumnWidth(2),
                  3: const pw.FlexColumnWidth(2),
                  4: const pw.FlexColumnWidth(2),
                  5: const pw.FlexColumnWidth(2),
                  6: const pw.FlexColumnWidth(2),
                  7: const pw.FlexColumnWidth(2),
                  8: const pw.FlexColumnWidth(2),
                },
                cellAlignment: pw.Alignment.topLeft,
                cellPadding: const pw.EdgeInsets.all(3),
              ),
          ];
        },
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(bytes: bytes, filename: 'plano_holy_squat.pdf');
  }

  String _formatActualPlanForShare(Map json, String analiseExtra) {
    final buffer = StringBuffer();
    buffer.writeln('🎯 *Plano de Treino*');
    if (analiseExtra.isNotEmpty) {
      buffer.writeln('\n*Visão Geral*:\n$analiseExtra\n');
    }
    if (json['objetivoPrincipal'] != null) buffer.writeln('*Objetivo*: ${json['objetivoPrincipal']}');
    if (json['duracaoSemanas'] != null) buffer.writeln('*Duração Total*: ${json['duracaoSemanas']} semanas\n');
    if (json['blocos'] is List) {
      buffer.writeln('*Mesociclos:*');
      for (var b in json['blocos']) {
        if (b is Map) {
          buffer.writeln('▪ *${b['mesociclo'] ?? ''}* (${b['duracaoSemanas'] ?? ''} sem): ${b['foco'] ?? ''}');
        } else {
          buffer.writeln('▪ $b');
        }
      }
    }
    return buffer.toString();
  }

  List<Widget> _buildWorkoutsPlanSections(dynamic tableData) {
    if (tableData == null || tableData is! List || tableData.isEmpty) {
      return [_buildContainer(
        title: 'Workouts Plan',
        shareText: 'Nenhum plano pendente.',
        children: [const Text('Prescrições pendentes.', style: TextStyle(color: AppTheme.secondaryTextColor))],
      )];
    }

    final data = tableData as List;

    final Map<String, List<Map<String, dynamic>>> byMeso = {};
    for (var row in data) {
      if (row is Map) {
        final meso = row['mesocycle']?.toString() ?? 'Histórico';
        byMeso.putIfAbsent(meso, () => []);
        byMeso[meso]!.add(Map<String, dynamic>.from(row));
      }
    }

    final List<Widget> sections = [];

    for (final mesoEntry in byMeso.entries) {
      final mesoName = mesoEntry.key;
      final mesoRows = mesoEntry.value;

      final bool hasWeekField = mesoRows.any((r) {
        final w = r['week'];
        return w != null && (w is int ? w > 0 : int.tryParse(w.toString(), radix: 10) != null && int.parse(w.toString()) > 0);
      });

      final Map<int, Map<String, Map<String, dynamic>>> byWeekByDate = {};

      if (hasWeekField) {
        for (final row in mesoRows) {
          final week = (row['week'] as num?)?.toInt() ?? 1;
          final dateKey = row['date']?.toString() ?? '';
          byWeekByDate.putIfAbsent(week, () => {});
          if (byWeekByDate[week]!.containsKey(dateKey)) {
            final existing = byWeekByDate[week]![dateKey]!;
            final existingFoco = existing['focoPrincipal']?.toString() ?? existing['workout']?.toString() ?? '';
            final newFoco = (row['focoPrincipal'] ?? row['workout'])?.toString() ?? '';
            if (newFoco.isNotEmpty && !existingFoco.contains(newFoco)) {
              existing['focoPrincipal'] = '$existingFoco / $newFoco';
            }
          } else {
            byWeekByDate[week]![dateKey] = Map<String, dynamic>.from(row);
          }
        }
      } else {
        DateTime? firstDate;
        for (final row in mesoRows) {
          final ds = row['date']?.toString() ?? '';
          if (ds.isNotEmpty) {
            try {
              final d = DateTime.parse(ds);
              if (firstDate == null || d.isBefore(firstDate)) firstDate = d;
            } catch (_) {}
          }
        }
        firstDate ??= DateTime.now();

        for (final row in mesoRows) {
          final ds = row['date']?.toString() ?? '';
          if (ds.isEmpty) continue;
          try {
            final d = DateTime.parse(ds);
            final week = (d.difference(firstDate).inDays ~/ 7) + 1;
            byWeekByDate.putIfAbsent(week, () => {});
            if (byWeekByDate[week]!.containsKey(ds)) {
              final existing = byWeekByDate[week]![ds]!;
              final existingFoco = existing['focoPrincipal']?.toString() ?? existing['workout']?.toString() ?? '';
              final newFoco = (row['focoPrincipal'] ?? row['workout'])?.toString() ?? '';
              if (newFoco.isNotEmpty && !existingFoco.contains(newFoco)) {
                existing['focoPrincipal'] = '$existingFoco / $newFoco';
              }
            } else {
              byWeekByDate[week]![ds] = Map<String, dynamic>.from(row);
            }
          } catch (_) {}
        }
      }

      final buffer = StringBuffer();
      buffer.writeln('🏋️‍♂️ *Planejamento - $mesoName*');

      final List<Widget> mesoChildren = [
        Text(mesoName, style: const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
      ];

      final sortedWeeks = byWeekByDate.keys.toList()..sort();
      for (final weekNum in sortedWeeks) {
        final dateMap = byWeekByDate[weekNum]!;

        final sortedDates = dateMap.keys.toList()..sort();
        List<Map<String, dynamic>> weekRows = [];

        if (sortedDates.isNotEmpty) {
          DateTime? firstOfWeek;
          try {
            firstOfWeek = DateTime.parse(sortedDates.first);
            while (firstOfWeek!.weekday != DateTime.monday) {
              firstOfWeek = firstOfWeek.subtract(const Duration(days: 1));
            }
          } catch (_) {}

          if (firstOfWeek != null) {
            const dayNames = ['Segunda-feira', 'Terça-feira', 'Quarta-feira', 'Quinta-feira', 'Sexta-feira', 'Sábado', 'Domingo'];
            for (int i = 0; i < 7; i++) {
              final dayDate = firstOfWeek.add(Duration(days: i));
              final dateStr = '${dayDate.year}-${dayDate.month.toString().padLeft(2, '0')}-${dayDate.day.toString().padLeft(2, '0')}';
              if (dateMap.containsKey(dateStr)) {
                weekRows.add(dateMap[dateStr]!);
              } else {
                weekRows.add({
                  'date': dateStr,
                  'day': dayNames[i],
                  'focoPrincipal': 'Descanso',
                  'isDescansoAtivo': true,
                  'mesocycle': mesoName,
                  'week': weekNum,
                });
              }
            }
          } else {
            weekRows = dateMap.values.toList();
          }
        }

        buffer.writeln('\n*Semana $weekNum*');
        for (var row in weekRows) {
          buffer.writeln('${row['day']}: ${row['focoPrincipal'] ?? row['workout'] ?? ''}');
        }

        mesoChildren.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0, top: 12.0),
            child: Text('Semana $weekNum', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          )
        );
        mesoChildren.add(_buildWorkoutsTable(weekRows));
      }

      sections.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildContainer(
            title: mesoName,
            shareText: buffer.toString(),
            children: mesoChildren,
          ),
        )
      );
    }

    return sections;
  }


  Widget _buildContainer({required String title, required String shareText, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.share, size: 20, color: AppTheme.primaryTeal),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  Share.share(shareText);
                },
              )
            ],
          ),
          childrenPadding: const EdgeInsets.all(16.0),
          iconColor: AppTheme.primaryTeal,
          collapsedIconColor: Colors.white,
          children: children,
        ),
      ),
    );
  }

  Widget _buildRichText(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 14, color: AppTheme.secondaryTextColor),
        children: [
          TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          TextSpan(text: value),
        ],
      ),
    );
  }

  Future<void> _generateNextMeso(Map<String, dynamic> coach, Map<String, dynamic> plan) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final controller = WorkoutController(WorkoutRepository());
      
      await controller.gerarProximoCiclo(
        planoId: plan['id'],
        actualPlanSummaryJson: plan['actual_plan_summary'] ?? '{}',
        currentWorkoutsTable: (plan['workouts_plan_table'] is List) ? plan['workouts_plan_table'] : [],
        aiCoachName: coach['ai_coach_name'],
        emailUtilizador: SupabaseService.client.auth.currentUser?.email ?? UserState.email.value,
      );

      if (controller.state == WorkoutState.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ciclo gerado com sucesso!'), backgroundColor: Colors.green),
          );
        }
      } else if (controller.state == WorkoutState.error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(controller.errorMessage), backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Erro inesperado: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      await _loadData(); 
    }
  }

  Widget _buildWorkoutsTable(List weekData) {
    if (weekData.isEmpty) return const SizedBox.shrink();
    
    // 1. Group by Day to handle multiple sessions on the same day
    Map<String, List<String>> sessionsByDay = {};
    for (var row in weekData) {
      if (row is Map) {
        String day = row['day']?.toString() ?? 'N/A';
        // Supports both the new 'focoPrincipal' field and the old 'workout' field
        String workout = (row['focoPrincipal'] ?? row['workout'])?.toString() ?? '';
        if (!sessionsByDay.containsKey(day)) sessionsByDay[day] = [];
        sessionsByDay[day]!.add(workout);
      }
    }

    // 2. Find the maximum number of sessions in a single day to build the columns
    int maxSessions = 0;
    for (var sessions in sessionsByDay.values) {
      if (sessions.length > maxSessions) maxSessions = sessions.length;
    }
    if (maxSessions == 0) maxSessions = 1;

    // Headers (Day, Workout 1, Workout 2...)
    List<Widget> headerCells = [
      const Padding(padding: EdgeInsets.all(8), child: Text('Dia', style: TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold))),
    ];
    for (int s = 1; s <= maxSessions; s++) {
      headerCells.add(Padding(
        padding: const EdgeInsets.all(8), 
        child: Text(maxSessions > 1 ? 'Treino $s' : 'Treino', style: const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold))
      ));
    }

    return Table(
      border: TableBorder.all(color: Colors.white.withOpacity(0.1), width: 1),
      columnWidths: {
        0: const IntrinsicColumnWidth(),
        for (int s = 1; s <= maxSessions; s++) s: const FlexColumnWidth(),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05)),
          children: headerCells,
        ),
        ...sessionsByDay.entries.map((entry) {
          final day = entry.key;
          final workouts = entry.value;

          List<Widget> rowCells = [
            Padding(padding: const EdgeInsets.all(8), child: Text(day, style: const TextStyle(color: Colors.white))),
          ];

          for (int s = 0; s < maxSessions; s++) {
            String text = s < workouts.length ? workouts[s] : '-';
            rowCells.add(Padding(padding: const EdgeInsets.all(8), child: Text(text, style: const TextStyle(color: AppTheme.secondaryTextColor))));
          }

          return TableRow(children: rowCells);
        }).toList(),
      ],
    );
  }

  pw.Widget _buildPdfBigNumbers(Map<String, dynamic>? kpis, pw.Font font, pw.Font fontBold, {bool isProgress = false}) {
    if (kpis == null) return pw.SizedBox();
    
    final items = isProgress ? [
      {'l': 'Conclusao', 'v': '${kpis['completion_rate']}%'},
      {'l': 'Freq. Sem.', 'v': '${kpis['weekly_freq']} sv'},
      {'l': 'Negligencia', 'v': '${kpis['neglected_type']}'},
      {'l': 'Delta Carga', 'v': '${kpis['load_delta']}%'},
      {'l': 'Recup. PR', 'v': '${kpis['pr_recovery']}%'},
    ] : [
      {'l': 'Aderencia', 'v': '${kpis['adherence']}%'},
      {'l': 'PSE Medio', 'v': '${kpis['avg_pse']}'},
      {'l': 'Power Idx', 'v': '${kpis['power_index']}'},
      {'l': 'Evolucao', 'v': '+${kpis['best_evolution']?['percent']}%'},
      {'l': 'Streak', 'v': '${kpis['streak']} d'},
      {'l': 'Freq/Sem', 'v': '${kpis['weekly_freq']}/w'},
    ];

    return pw.GridView(
      crossAxisCount: isProgress ? 5 : 3,
      childAspectRatio: isProgress ? 2.0 : 2.5,
      children: items.map((it) => pw.Container(
        margin: const pw.EdgeInsets.all(2),
        padding: const pw.EdgeInsets.all(5),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(it['v']!.toString(), style: pw.TextStyle(font: fontBold, fontSize: isProgress ? 8 : 10)),
            pw.Text(it['l']!.toString(), style: pw.TextStyle(font: font, fontSize: 6, color: PdfColors.grey700)),
          ],
        ),
      )).toList(),
    );
  }

  pw.Widget _buildPdfHeatmap(List<dynamic>? data) {
    if (data == null || data.isEmpty) return pw.SizedBox();
    
    return pw.Wrap(
      spacing: 1,
      runSpacing: 1,
      children: data.take(120).map((it) {
        final intensity = (it['intensity'] as num?)?.toDouble() ?? 0.0;
        final baseColor = PdfColor.fromHex('#2CC1BC');
        final color = intensity == 0 
            ? PdfColors.grey100 
            : PdfColor(baseColor.red, baseColor.green, baseColor.blue, 0.2 + (intensity / 10).clamp(0.0, 0.8));
        return pw.Container(
          width: 5,
          height: 5,
          color: color,
        );
      }).toList(),
    );
  }

  pw.Widget _buildPdfRadarChart(List<dynamic>? data, double size, pw.Font font) {
    if (data == null || data.isEmpty) return pw.SizedBox();

    return pw.Container(
      width: size,
      height: size,
      child: pw.CustomPaint(
        size: PdfPoint(size, size),
        painter: (PdfGraphics canvas, PdfPoint size) {
          final count = data.length;
          final center = PdfPoint(size.x / 2, size.y / 2);
          final radius = (size.x / 2) * 0.8;
          final angleStep = (2 * math.pi) / count;

          canvas.setLineWidth(0.2);
          canvas.setStrokeColor(PdfColors.grey300);
          for (int level = 1; level <= 3; level++) {
            final r = radius * (level / 3);
            for (int i = 0; i < count; i++) {
              final x1 = center.x + r * math.cos(angleStep * i);
              final y1 = center.y + r * math.sin(angleStep * i);
              final x2 = center.x + r * math.cos(angleStep * (i + 1));
              final y2 = center.y + r * math.sin(angleStep * (i + 1));
              canvas.moveTo(x1, y1);
              canvas.lineTo(x2, y2);
              canvas.strokePath();
            }
          }

          final baseColor = PdfColor.fromHex('#2CC1BC');
          canvas.setLineWidth(1);
          canvas.setStrokeColor(baseColor);
          canvas.setFillColor(PdfColor(baseColor.red, baseColor.green, baseColor.blue, 0.3));
          
          if (data.isEmpty) {
            _drawPdfNoDataPlaceholder(canvas, size, font);
            return;
          }
          final values = data.map((e) => (e['count'] as num? ?? 0).toDouble()).toList();
          final maxVal = values.isNotEmpty ? values.reduce(math.max) : 0.0;
          if (maxVal == 0) {
            _drawPdfNoDataPlaceholder(canvas, size, font);
            return;
          }

          for (int i = 0; i < count; i++) {
            final val = (data[i]['count'] as num).toDouble();
            final r = radius * (val / maxVal);
            final x = center.x + r * math.cos(angleStep * i);
            final y = center.y + r * math.sin(angleStep * i);
            if (i == 0) canvas.moveTo(x, y);
            else canvas.lineTo(x, y);
          }
          canvas.closePath();
          canvas.fillPath();
          canvas.strokePath();
        },
      ),
    );
  }

  void _drawPdfNoDataPlaceholder(PdfGraphics canvas, PdfPoint center, pw.Font font) {
    canvas.setStrokeColor(PdfColors.grey400);
    canvas.setFillColor(PdfColors.grey400);
    // Draw a simple box as placeholder since string drawing is complex without easy access to PdfFont here
    canvas.drawRect(center.x - 25, center.y - 25, 50, 50);
    canvas.strokePath();
  }
}
