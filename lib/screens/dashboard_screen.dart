import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/widgets/app_drawer.dart';
import 'package:holy_squat_app/widgets/theme_toggle_button.dart';
import 'package:intl/intl.dart';
import 'package:holy_squat_app/repositories/workout_repository.dart';
import 'package:holy_squat_app/core/user_state.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  List<DateTime> _activeDates = [];

  // Metrics
  int _currentMonthCount = 0;
  int _streakWeeks = 0;
  List<int> _weeklyCounts = List.filled(12, 0);
  List<int> _monthlyCounts = List.filled(12, 0);
  Map<String, dynamic>? _athleteStats;

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  Future<void> _fetchAnalytics() async {
    try {
      final repo = WorkoutRepository();
      final String userEmail = SupabaseService.client.auth.currentUser?.email ?? UserState.email.value;
      final double rawWeight = double.tryParse(UserState.weight.value) ?? 0.0;
      final bool isLbs = UserState.weightUnit.value.toLowerCase().contains('lb');
      final double userWeight = isLbs ? rawWeight * 0.453592 : rawWeight;

      // Fetch dynamic stats in parallel
      final statsFuture = repo.fetchAthletePlanningStats(userEmail, userWeight);
      final activeDatesFuture = SupabaseService.getActiveWorkoutDates();

      final results = await Future.wait([statsFuture, activeDatesFuture]);
      
      _athleteStats = results[0] as Map<String, dynamic>?;
      final datesStr = results[1] as List<dynamic>;

      final List<DateTime> dates = [];
      for (var d in datesStr) {
        try {
          String cleanD = d.toString().split(',').first.split(' ').first.split('T').first;
          if (cleanD.contains('/')) {
             final parts = cleanD.split('/');
             if (parts.length >= 3) {
                int p0 = int.parse(parts[0]);
                int p1 = int.parse(parts[1]);
                int p2 = int.parse(parts[2]);
                int day = p1, month = p0;
                if (p0 > 12) { day = p0; month = p1; }
                else if (p1 > 12) { month = p0; day = p1; }
                dates.add(DateTime(p2, month, day));
             }
          } else {
             final parsed = DateTime.tryParse(cleanD);
             if (parsed != null) dates.add(parsed);
          }
        } catch (_) {
          // Skip securely row by row
        }
      }
      dates.sort();
      
      _activeDates = dates;
      _calculateMetrics();
    } catch (e) {
      debugPrint('Error fetching dashboard analytics: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _calculateMetrics() {
    final now = DateTime.now();
    
    // 1. Current Month Active Days
    _currentMonthCount = _activeDates.where((d) => d.year == now.year && d.month == now.month).length;

    // 2. 12-Week Weekly Counts (ending this week)
    // Find the start of the current week (Monday)
    int daysFromMonday = now.weekday - 1;
    DateTime startOfThisWeek = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysFromMonday));

    List<int> weekly = List.filled(12, 0);
    for (int i = 0; i < 12; i++) {
      DateTime weekStart = startOfThisWeek.subtract(Duration(days: (11 - i) * 7));
      DateTime weekEnd = weekStart.add(const Duration(days: 6, hours: 23, minutes: 59));
      
      weekly[i] = _activeDates.where((d) => d.isAfter(weekStart.subtract(const Duration(seconds: 1))) && d.isBefore(weekEnd.add(const Duration(seconds: 1)))).length;
    }
    _weeklyCounts = weekly;

    // 3. Weekly Streak
    int streak = 0;
    for (int i = 11; i >= 0; i--) {
      // Start from this week. If it's 0, and we haven't reached end of week, it's fine.
      // But rigorously, check consecutive > 0
      if (_weeklyCounts[i] > 0) {
        streak++;
      } else if (i < 11) {
        // If it's 0 and it's a past week, the streak breaks
        break;
      }
    }
    _streakWeeks = streak;

    // 4. 12-Month Bar Counts (ending this month)
    List<int> monthly = List.filled(12, 0);
    for (int i = 0; i < 12; i++) {
      int targetMonth = now.month - (11 - i);
      int targetYear = now.year;
      while (targetMonth <= 0) {
        targetMonth += 12;
        targetYear -= 1;
      }
      monthly[i] = _activeDates.where((d) => d.year == targetYear && d.month == targetMonth).length;
    }
    _monthlyCounts = monthly;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: const [ThemeToggleButton()],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
        : SelectionArea(
            child: RefreshIndicator(
                onRefresh: _fetchAnalytics,
                color: AppTheme.primaryTeal,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBigNumbersGrid(_athleteStats?['kpis']),
                      const SizedBox(height: 32),
                      _buildCapabilitiesRadar(_athleteStats?['radar']),
                      const SizedBox(height: 32),
                      _buildActivityHeatmap(_athleteStats?['heatmap']),
                      const SizedBox(height: 32),
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 32),
                      _buildBigNumbers(),
                      const SizedBox(height: 32),
                      _buildWeeklyLineChart(),
                      const SizedBox(height: 32),
                      _buildFrequencyMatrix(),
                      const SizedBox(height: 32),
                      _buildMonthlyBarChart(),
                      const SizedBox(height: 48), // Padding bottom
                    ],
                  ),
                ),
              ),
          ),
    );
  }

  Widget _buildBigNumbers() {
    final monthName = DateFormat('MMMM', 'pt_BR').format(DateTime.now());
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "${monthName[0].toUpperCase()}${monthName.substring(1)} ${DateTime.now().year}",
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile("Sua Sequência", "$_streakWeeks Semanas", Icons.local_fire_department, Colors.orange),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricTile("Dias Ativos no Mês", "$_currentMonthCount", Icons.calendar_month, AppTheme.primaryTeal),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildMetricTile(String title, String value, IconData icon, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title, 
                  style: const TextStyle(color: AppTheme.secondaryTextColor, fontSize: 13, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildBigNumbersGrid(Map<String, dynamic>? kpis) {
    if (kpis == null) return const SizedBox.shrink();
    
    final items = [
      {'label': 'Aderência', 'value': '${kpis['adherence']}%', 'icon': Icons.bolt},
      {'label': 'PSE Médio', 'value': '${kpis['avg_pse']}', 'icon': Icons.speed},
      {'label': 'IFR', 'value': '${kpis['ifr']}', 'icon': Icons.fitness_center},
      {'label': 'Evolução', 'value': '+${kpis['best_evolution']?['percent']}%', 'icon': Icons.trending_up, 'sub': kpis['best_evolution']?['exercise']},
      {'label': 'Streak', 'value': '${kpis['streak']} w', 'icon': Icons.fireplace},
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

  Widget _buildWeeklyLineChart() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Últimas 12 Semanas", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 7, // Max 7 days a week
                gridData: FlGridData(
                  show: true, 
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (val) => const FlLine(color: Colors.white12, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: const TextStyle(color: AppTheme.secondaryTextColor, fontSize: 12)),
                    )
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (val, meta) {
                        if (val.toInt() == 0 || val.toInt() == 11 || val.toInt() == 5) {
                          return Text("Sem ${val.toInt()+1}", style: const TextStyle(color: AppTheme.secondaryTextColor, fontSize: 10));
                        }
                        return const Text("");
                      }
                    )
                  )
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) => const Color(0xFF111111),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) => LineTooltipItem(
                        "${spot.y.toInt()} treinos",
                        const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold),
                      )).toList();
                    }
                  )
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: _weeklyCounts.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.toDouble())).toList(),
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: AppTheme.primaryTeal,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                        radius: 4, color: const Color(0xFF111111),
                        strokeWidth: 2, strokeColor: AppTheme.primaryTeal,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppTheme.primaryTeal.withOpacity(0.15),
                    )
                  )
                ]
              )
            ),
          )
        ],
      )
    );
  }

  Widget _buildMonthlyBarChart() {
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Resumo Mensal (12 Meses)", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                minY: 0,
                maxY: 31,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (val) => const FlLine(color: Colors.white12, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        int index = val.toInt();
                        if (index < 0 || index > 11) return const Text("");
                        int targetMonth = now.month - (11 - index);
                        while (targetMonth <= 0) targetMonth += 12;
                        
                        final ptMonths = ['JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN', 'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ'];
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            ptMonths[targetMonth - 1], 
                            style: TextStyle(
                              color: index == 11 ? AppTheme.primaryTeal : AppTheme.secondaryTextColor, 
                              fontSize: 9,
                              fontWeight: index == 11 ? FontWeight.bold : FontWeight.normal
                            )
                          ),
                        );
                      }
                    )
                  )
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => const Color(0xFF111111),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        "${rod.toY.toInt()} treinos",
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                      );
                    }
                  )
                ),
                barGroups: _monthlyCounts.asMap().entries.map((e) {
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.toDouble(),
                        width: 4,
                        color: e.key == 11 ? AppTheme.primaryTeal : Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      )
                    ]
                  );
                }).toList(),
              )
            )
          )
        ],
      )
    );
  }

  Widget _buildFrequencyMatrix() {
    // Generate a quick matrix for current month's weeks
    // Inspired by GitHub / Strava intensity map
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);
    
    // Calculate days shifted from Monday (1)
    int shift = firstDayOfMonth.weekday - 1; 
    
    // We will build a grid of 5 weeks x 7 days
    List<Widget> gridItems = [];
    final labels = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];
    
    // Add header
    for (var l in labels) {
      gridItems.add(Center(child: Text(l, style: const TextStyle(color: AppTheme.secondaryTextColor, fontSize: 12))));
    }
    
    // Add blank days before the 1st
    for (int i = 0; i < shift; i++) {
        gridItems.add(const SizedBox());
    }
    
    // Add the days
    int daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    for (int day = 1; day <= daysInMonth; day++) {
      DateTime currentDate = DateTime(now.year, now.month, day);
      bool isActive = _activeDates.any((d) => d.year == currentDate.year && d.month == currentDate.month && d.day == currentDate.day);
      bool isToday = currentDate.day == now.day;
      
      gridItems.add(
        Center(
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? AppTheme.primaryTeal : Colors.transparent,
              border: Border.all(
                color: isActive ? AppTheme.primaryTeal : (isToday ? Colors.white54 : AppTheme.cardColor),
                width: isActive ? 0 : 1,
              )
            ),
            child: isActive ? null : Center(child: Text("$day", style: const TextStyle(color: Colors.white30, fontSize: 10))),
          ),
        )
      );
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Dias Ativos este Mês", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: gridItems,
          )
        ],
      )
    );
  }
}
