import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'package:holy_squat_app/widgets/app_drawer.dart';
import 'package:holy_squat_app/widgets/app_bottom_nav.dart';
import 'package:holy_squat_app/screens/planning/create_plan_screen.dart';
import 'package:holy_squat_app/controllers/workout_controller.dart';
import 'package:holy_squat_app/repositories/workout_repository.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PlanningScreen extends StatefulWidget {
  const PlanningScreen({super.key});

  @override
  State<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends State<PlanningScreen> {
  Map<String, dynamic>? _currentPlan;
  bool _isLoading = true;
  String _loadingText = '';

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
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: AppTheme.primaryTeal),
                    if (_loadingText.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        _loadingText, 
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold)
                      ),
                    ]
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildActualPlanSection(
                    _currentPlan?['actual_plan_summary'],
                    _currentPlan?['workouts_plan_text']
                  ),
                  const SizedBox(height: 16),
                  ..._buildWorkoutsPlanSections(
                    _currentPlan?['workouts_plan_table'],
                  ),
                  const SizedBox(height: 16),
                  _buildProgressSection(_currentPlan?['progress_analysis']),
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
                        MaterialPageRoute(
                          builder: (_) => ChangeNotifierProvider(
                            create: (_) => WorkoutController(WorkoutRepository()),
                            child: const CreatePlanScreen(),
                          ),
                        ),
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
                  const SizedBox(height: 12),
                  if (_currentPlan != null)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.cardColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppTheme.primaryTeal, width: 0.5)),
                      ),
                      onPressed: _generateNextMeso,
                      child: const Text(
                        'Generate Next Cycle',
                        style: TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                ],
              ),
            ),
      bottomNavigationBar: const AppBottomNav(),
    );
  }

  Widget _buildActualPlanSection(String? actualPlanSummary, String? workoutsPlanText) {
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
          children: [_buildVisaoGeralContent(summaryJson)],
        ),
        const SizedBox(height: 16),
        _buildPDFExportButton(macroJson, summaryJson, _currentPlan?['progress_analysis']),
      ],
    );
  }

  Widget _buildProgressSection(String? progressJson) {
    if (progressJson == null || progressJson.isEmpty) return const SizedBox.shrink();

    Map<String, dynamic>? data;
    try {
      data = jsonDecode(progressJson);
    } catch (_) {}

    if (data == null) return const SizedBox.shrink();

    return _buildContainer(
      title: 'Progress',
      shareText: "📈 *Análise de Progresso*\n\n${data['texto'] ?? ''}",
      children: [
        if (data['texto'] != null)
          Text(data['texto'], style: const TextStyle(color: AppTheme.secondaryTextColor)),
        const SizedBox(height: 16),
        if (data['aderencia'] != null)
          _buildRichText('Aderência: ', data['aderencia'].toString()),
        if (data['evolucao'] != null)
           Padding(
             padding: const EdgeInsets.only(top: 8),
             child: _buildRichText('Evolução: ', data['evolucao'].toString()),
           ),
        if (data['graficos'] is List) ...[
          const SizedBox(height: 20),
          ...((data['graficos'] as List).map((g) => _buildChartSection(g)).toList()),
        ]
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

  Future<void> _generateAndSharePDF(Map<String, dynamic>? macro, Map<String, dynamic>? summary, String? progressJson) async {
    final pdf = pw.Document();
    Map<String, dynamic>? progressData;
    try { if (progressJson != null) progressData = jsonDecode(progressJson); } catch (_) {}

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(level: 0, child: pw.Text('Holy Squat App - Planejamento', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.teal))),
            pw.SizedBox(height: 20),
            
            if (progressData != null) ...[
              pw.Header(level: 1, child: pw.Text('Análise de Progresso (Mesociclo Anterior)')),
              pw.Text(progressData['texto'] ?? ''),
              pw.Bullet(text: 'Aderencia: ${progressData['aderencia'] ?? 'N/A'}'),
              pw.Bullet(text: 'Evolucao: ${progressData['evolucao'] ?? 'N/A'}'),
              pw.SizedBox(height: 20),
            ],

            pw.Header(level: 1, child: pw.Text('1. Analise de Historico')),
            pw.Text(macro?['historico']?['texto'] ?? (macro?['analise'] ?? 'N/A')),
            pw.SizedBox(height: 20),

            pw.Header(level: 1, child: pw.Text('2. Visao Geral do Plano')),
            pw.Bullet(text: 'Objetivo: ${summary?['objetivoPrincipal'] ?? 'N/A'}'),
            pw.Bullet(text: 'Duracao: ${summary?['duracaoSemanas'] ?? 'N/A'} semanas'),
            pw.SizedBox(height: 10),
            pw.Text('Mesociclos:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            if (summary?['blocos'] is List)
              ...((summary?['blocos'] as List).map((b) => pw.Padding(
                padding: const pw.EdgeInsets.only(left: 10, top: 5),
                child: pw.Text('- ${b['mesociclo']}: ${b['foco']}', style: const pw.TextStyle(fontSize: 10)),
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
                    s['foco'].toString(),
                    s['seg'].toString(),
                    s['ter'].toString(),
                    s['qua'].toString(),
                    s['qui'].toString(),
                    s['sex'].toString(),
                    s['sab'].toString(),
                    s['dom'].toString(),
                  ])),
                ],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.teal),
                cellStyle: const pw.TextStyle(fontSize: 8),
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

    // 1. Agrupar por Mesociclo (mantendo a ordem original de inserção)
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

      // 2. Agrupar por semana intra-meso usando o campo 'week'.
      //    Fallback: se todos os registros tiverem week == 0 ou nulo, agrupa por
      //    semana calendária derivando da diferença de dias da primeira data.
      final bool hasWeekField = mesoRows.any((r) {
        final w = r['week'];
        return w != null && (w is int ? w > 0 : int.tryParse(w.toString(), radix: 10) != null && int.parse(w.toString()) > 0);
      });

      final Map<int, Map<String, Map<String, dynamic>>> byWeekByDate = {};
      // byWeekByDate[semana][date] → row com o maior/único focoPrincipal do dia

      if (hasWeekField) {
        // Caminho principal: usa campo 'week' como semana intra-meso
        for (final row in mesoRows) {
          final week = (row['week'] as num?)?.toInt() ?? 1;
          final dateKey = row['date']?.toString() ?? '';
          byWeekByDate.putIfAbsent(week, () => {});
          // Se já existe uma entrada para essa data, concatena os focos (dupla sessão)
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
        // Fallback calendário: calcula semana pela diferença de dias da primeira data
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

      // 3. Construir os widgets do mesociclo
      final buffer = StringBuffer();
      buffer.writeln('🏋️‍♂️ *Planejamento - $mesoName*');

      final List<Widget> mesoChildren = [
        Text(mesoName, style: const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
      ];

      final sortedWeeks = byWeekByDate.keys.toList()..sort();
      for (final weekNum in sortedWeeks) {
        final dateMap = byWeekByDate[weekNum]!;

        // 4. Ordenar as datas da semana e expandir para 7 dias (Seg–Dom)
        final sortedDates = dateMap.keys.toList()..sort();
        List<Map<String, dynamic>> weekRows = [];

        if (sortedDates.isNotEmpty) {
          // Encontra a segunda-feira da semana a partir da primeira data da semana
          DateTime? firstOfWeek;
          try {
            firstOfWeek = DateTime.parse(sortedDates.first);
            // Se não começa na segunda, volta até a segunda
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
                // Dia sem sessão → Descanso
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
            // Sem data parseável, usa os dados como estão
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

  Future<void> _generateNextMeso() async {
    if (_currentPlan == null) return;
    setState(() {
      _isLoading = true;
      _loadingText = 'Iniciando geração...';
    });

    try {
      final controller = WorkoutController(WorkoutRepository());
      
      // Listener para atualizar o texto na tela de forma reativa
      controller.addListener(() {
        if (mounted && controller.loadingMessage != _loadingText) {
          setState(() {
            _loadingText = controller.loadingMessage;
          });
        }
      });

      final table = _currentPlan!['workouts_plan_table'];
      List currentTable = (table is List) ? table : [];

      await controller.gerarProximoCiclo(
        emailUtilizador: 'samuelhsm@gmail.com', // Mocked user email
        planoId: _currentPlan!['id'],
        actualPlanSummaryJson: _currentPlan!['actual_plan_summary'] ?? '{}',
        currentWorkoutsTable: currentTable,
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
      if (mounted) {
        setState(() => _loadingText = '');
      }
      await _loadPlan(); 
    }
  }

  Widget _buildWorkoutsTable(List weekData) {
    if (weekData.isEmpty) return const SizedBox.shrink();
    
    // 1. Agrupar por Dia para lidar com múltiplas sessões no mesmo dia
    Map<String, List<String>> sessionsByDay = {};
    for (var row in weekData) {
      if (row is Map) {
        String day = row['day']?.toString() ?? 'N/A';
        // Suporta tanto o novo campo 'focoPrincipal' quanto o antigo 'workout'
        String workout = (row['focoPrincipal'] ?? row['workout'])?.toString() ?? '';
        if (!sessionsByDay.containsKey(day)) sessionsByDay[day] = [];
        sessionsByDay[day]!.add(workout);
      }
    }

    // 2. Descobrir o número máximo de sessões num único dia para montar as colunas
    int maxSessions = 0;
    for (var sessions in sessionsByDay.values) {
      if (sessions.length > maxSessions) maxSessions = sessions.length;
    }
    if (maxSessions == 0) maxSessions = 1;

    // Cabeçalhos (Dia, Treino 1, Treino 2...)
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
}
