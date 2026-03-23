import 'package:flutter/material.dart';
import 'package:holy_squat_app/widgets/app_bottom_nav.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/screens/pr_form_screen.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'package:intl/intl.dart';

class PrDetailScreen extends StatefulWidget {
  final String exerciseName;
  const PrDetailScreen({super.key, required this.exerciseName});

  @override
  State<PrDetailScreen> createState() => _PrDetailScreenState();
}

class _PrDetailScreenState extends State<PrDetailScreen> {
  late Future<List<Map<String, dynamic>>> _logsFuture;

  @override
  void initState() {
    super.initState();
    _logsFuture = SupabaseService.getPrLogsForExercise(widget.exerciseName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _logsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          }

          final logs = snapshot.data ?? [];
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    widget.exerciseName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (logs.isNotEmpty) _buildChart(logs),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => PrFormScreen(exerciseName: widget.exerciseName)));
                        if (result == true) {
                          setState(() { _logsFuture = SupabaseService.getPrLogsForExercise(widget.exerciseName); });
                        }
                      },
                      icon: const Icon(Icons.add, color: AppTheme.backgroundColor),
                      label: const Text('Add', style: TextStyle(color: AppTheme.backgroundColor, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryTeal,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: Text('WORKOUT', style: TextStyle(color: AppTheme.secondaryTextColor, fontSize: 12, fontWeight: FontWeight.bold))),
                        Expanded(flex: 1, child: Text('PR', style: TextStyle(color: AppTheme.secondaryTextColor, fontSize: 12, fontWeight: FontWeight.bold))),
                        Expanded(flex: 1, child: Text('UNIT', style: TextStyle(color: AppTheme.secondaryTextColor, fontSize: 12, fontWeight: FontWeight.bold))),
                        Expanded(flex: 2, child: Text('DATE', style: TextStyle(color: AppTheme.secondaryTextColor, fontSize: 12, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                  const Divider(color: AppTheme.cardColor, height: 1),
                  
                  if (logs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('Nenhum histórico encontrado.', style: TextStyle(color: AppTheme.secondaryTextColor)),
                    )
                  else
                    ...logs.reversed.map((log) => _buildListEntry(log)),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: const AppBottomNav(activeIndex: 2),
    );
  }

  Widget _buildChart(List<Map<String, dynamic>> logs) {
    if (logs.length < 2) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(16)),
        child: const Text('Gráfico necessita de pelo menos 2 registros.', style: TextStyle(color: AppTheme.secondaryTextColor)),
      );
    }
    final spots = <FlSpot>[];
    final dates = <String>[];
    
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (int i = 0; i < logs.length; i++) {
      final prStr = logs[i]['pr']?.toString() ?? '0';
      final double prVal = double.tryParse(prStr) ?? 0.0;
      
      if (prVal < minY) minY = prVal;
      if (prVal > maxY) maxY = prVal;
      
      spots.add(FlSpot(i.toDouble(), prVal));
      dates.add(logs[i]['date'] ?? '');
    }

    final yRange = maxY - minY;
    minY = (minY - (yRange * 0.2)).clamp(0, double.infinity);
    if (yRange == 0) maxY = maxY + 10;
    else maxY = maxY + (yRange * 0.2);

    double minX = 0;
    double maxX = (logs.length - 1).toDouble();
    if (logs.length == 1) {
      minX = -1;
      maxX = 1;
    }

    return Container(
      decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Progress', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    tooltipBgColor: Colors.black87,
                    tooltipRoundedRadius: 8,
                    getTooltipItems: (List<LineBarSpot> touchedSpots) {
                      return touchedSpots.map((LineBarSpot touchedSpot) {
                        String d = dates[touchedSpot.x.toInt()];
                        try {
                           d = DateFormat('dd/MM/yyyy').format(DateTime.parse(d));
                        } catch (_) {}
                        String val = touchedSpot.y.toStringAsFixed(1).replaceAll('.0', '');
                        return LineTooltipItem(
                          '$val\n',
                          const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold, fontSize: 14),
                          children: [TextSpan(text: d, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.normal))],
                        );
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true, drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1, dashArray: [5, 5]),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true, reservedSize: 30, interval: 1,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= 0 && value.toInt() < dates.length) {
                          String d = dates[value.toInt()];
                          try { d = DateFormat('dd/MM').format(DateTime.parse(d)); } catch (_) { if (d.length > 5) d = d.substring(0, 5); }
                          return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(d, style: const TextStyle(color: AppTheme.secondaryTextColor, fontSize: 10)));
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true, reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(color: AppTheme.secondaryTextColor, fontSize: 12)),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: minX, maxX: maxX, minY: minY, maxY: maxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots, isCurved: true, curveSmoothness: 0.2, color: AppTheme.primaryTeal, barWidth: 3, isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: true, color: AppTheme.primaryTeal.withOpacity(0.15)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListEntry(Map<String, dynamic> log) {
    String workout = log['exercise'] ?? '';
    String pr = log['pr']?.toString() ?? '-';
    String unit = log['pr_unit'] ?? '';
    String dateStr = log['date'] ?? '-';
    try { dateStr = DateFormat('dd/MM/yyyy').format(DateTime.parse(dateStr)); } catch (_) {}

    return Dismissible(
      key: Key(log['id'].toString()),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) {
            return AlertDialog(
              backgroundColor: AppTheme.cardColor,
              title: const Text('Confirm delete?', style: TextStyle(color: Colors.white)),
              content: const Text('Are you sure you want to delete this PR?', style: TextStyle(color: AppTheme.secondaryTextColor)),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel', style: TextStyle(color: AppTheme.secondaryTextColor))),
                TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
              ],
            );
          },
        );
      },
      onDismissed: (direction) async {
        await SupabaseService.deletePrLog(log['id']);
        setState(() { _logsFuture = SupabaseService.getPrLogsForExercise(widget.exerciseName); });
      },
      background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 20), child: const Icon(Icons.delete, color: Colors.white)),
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => PrFormScreen(exerciseName: widget.exerciseName, existingPr: log)));
          if (result == true) setState(() { _logsFuture = SupabaseService.getPrLogsForExercise(widget.exerciseName); });
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 4.0),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(workout, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Expanded(flex: 1, child: Text(pr)),
                  Expanded(flex: 1, child: Text(unit)),
                  Expanded(flex: 2, child: Text(dateStr)),
                ],
              ),
            ),
            const Divider(color: AppTheme.cardColor, height: 1),
          ],
        ),
      ),
    );
  }
}
