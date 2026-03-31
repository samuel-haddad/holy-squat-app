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
                  _buildWorkoutsPlanSection(
                    _currentPlan?['workouts_plan_table'],
                    _currentPlan != null ? _generateMicro : null,
                    _currentPlan?['actual_plan_summary'],
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
        _buildPDFExportButton(macroJson, summaryJson),
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

  Widget _buildPDFExportButton(Map<String, dynamic>? macroJson, Map<String, dynamic>? summaryJson) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.05),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppTheme.primaryTeal)),
      ),
      onPressed: () => _generateAndSharePDF(macroJson, summaryJson),
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

  Future<void> _generateAndSharePDF(Map<String, dynamic>? macro, Map<String, dynamic>? summary) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Header(level: 0, child: pw.Text('Holy Squat App - Planejamento', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.teal))),
            pw.SizedBox(height: 20),
            
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
            pw.Header(level: 1, child: pw.Text('3. Planejamento Consolidado (Meso 1)')),
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

  Widget _buildWorkoutsPlanSection(dynamic tableData, VoidCallback? onGenerateMicro, String? actualPlanJson) {
    String shareText = 'Prescrições pendentes.';

    String currentMesoTitle = "Mesociclo Atual";
    try {
      if (actualPlanJson != null) {
        final actualJson = jsonDecode(actualPlanJson);
        if (actualJson is Map && actualJson['blocos'] is List && (actualJson['blocos'] as List).isNotEmpty) {
          final firstBloco = actualJson['blocos'][0];
          if (firstBloco is Map) {
            currentMesoTitle = firstBloco['mesociclo'].toString();
          } else {
            currentMesoTitle = firstBloco.toString();
          }
        }
      }
    } catch (_) {}

    final buffer = StringBuffer();
    buffer.writeln('🏋️‍♂️ *Planejamento Semanal*');
    if (tableData is List && tableData.isNotEmpty) {
      buffer.writeln('\n*$currentMesoTitle*');
      
      int weekNum = 1;
      for (int i = 0; i < tableData.length; i += 7) {
        int end = (i + 7 < tableData.length) ? i + 7 : tableData.length;
        buffer.writeln('\n*Semana $weekNum*');
        for (var row in tableData.sublist(i, end)) {
          if (row is Map) {
            buffer.writeln('${row['day']}: ${row['workout']}');
          }
        }
        weekNum++;
      }
    } else {
      buffer.writeln('\nPrescrições pendentes.');
    }
    shareText = buffer.toString();

    return _buildContainer(
      title: 'Workouts Plan',
      shareText: shareText,
      children: [
        if (tableData != null && tableData is List && tableData.isNotEmpty) ...[
          const Text('Primeiro Mesociclo - Vista Semanal', style: TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ..._buildWeeklyTables(tableData),
        ] else ...[
          const Text('Prescrições pendentes.', style: TextStyle(color: AppTheme.secondaryTextColor)),
        ],
        if (onGenerateMicro != null) ...[
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: onGenerateMicro,
              icon: const Icon(Icons.autorenew, color: AppTheme.primaryTeal),
              label: const Text('Generate Next Cycle', style: TextStyle(color: AppTheme.primaryTeal)),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildWeeklyTables(List data) {
    List<Widget> tables = [];
    int weekNum = 1;
    for (int i = 0; i < data.length; i += 7) {
      int end = (i + 7 < data.length) ? i + 7 : data.length;
      final weekData = data.sublist(i, end);
      
      tables.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0, top: 12.0),
          child: Text('Semana $weekNum', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        )
      );
      tables.add(_buildWorkoutsTable(weekData));
      weekNum++;
    }
    return tables;
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

  Future<void> _generateMicro() async {
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
