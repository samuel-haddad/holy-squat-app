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

  Widget _buildActualPlanSection(String? content, String? textAnalysis) {
    if ((content == null || content.isEmpty) && (textAnalysis == null || textAnalysis.isEmpty)) {
      content = 'Nenhum plano ativo no momento.';
    }
    
    Widget bodyWidget = Text(content ?? '', style: const TextStyle(color: AppTheme.secondaryTextColor));
    String shareText = content ?? '';

    // Lógica para Visão Geral
    String analiseExtra = '';
    try {
      if (textAnalysis != null && textAnalysis.isNotEmpty) {
        final json = jsonDecode(textAnalysis);
        if (json is Map && json['analise'] != null) {
          analiseExtra = json['analise'].toString();
        } else {
          try {
            // Caso seja texto puro mas por algum motivo decode funcionou (números, etc)
            analiseExtra = textAnalysis; 
          } catch (_) {}
        }
      }
    } catch (_) {
      analiseExtra = textAnalysis ?? '';
    }

    try {
      if (content != null && content.isNotEmpty) {
        final json = jsonDecode(content);
        if (json is Map) {
          shareText = _formatActualPlanForShare(json, analiseExtra);
          bodyWidget = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (analiseExtra.isNotEmpty) ...[
                const Text('Visão Geral:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Text(analiseExtra, style: const TextStyle(color: AppTheme.secondaryTextColor)),
                const SizedBox(height: 16),
              ],
              if (json['objetivoPrincipal'] != null)
                _buildRichText('Objetivo Principal: ', json['objetivoPrincipal'].toString()),
              const SizedBox(height: 8),
              if (json['duracaoSemanas'] != null)
                _buildRichText('Duração: ', '${json['duracaoSemanas']} semanas'),
              const SizedBox(height: 16),
              const Text('Mesociclos:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              if (json['blocos'] is List)
                ...((json['blocos'] as List).map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 12.0, left: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ${b['mesociclo']} (${b['duracaoSemanas']} sem)', style: const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('${b['foco']}', style: const TextStyle(color: AppTheme.secondaryTextColor)),
                    ],
                  ),
                )).toList()),
            ],
          );
        }
      }
    } catch (_) {
      // Falha ao parsear
    }

    return _buildContainer(
      title: 'Actual Plan',
      shareText: shareText,
      children: [bodyWidget],
    );
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
        buffer.writeln('▪ *${b['mesociclo']}* (${b['duracaoSemanas']} sem): ${b['foco']}');
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
          currentMesoTitle = actualJson['blocos'][0]['mesociclo'].toString();
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
          Text(currentMesoTitle, style: const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold, fontSize: 16)),
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
