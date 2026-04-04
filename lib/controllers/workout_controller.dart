// lib/controllers/workout_controller.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/ai_workout_response.dart';
import '../repositories/workout_repository.dart';
import '../services/supabase_service.dart';

enum WorkoutState { initial, loading, success, error }

class WorkoutController extends ChangeNotifier {
  final WorkoutRepository _repository;

  WorkoutState _state = WorkoutState.initial;
  String _errorMessage = '';
  String _loadingMessage = '';
  AIWorkoutResponse? _planoGerado;
  Map<String, dynamic>? _athleteStats;

  WorkoutState get state => _state;
  bool get isLoading => _state == WorkoutState.loading;
  String get errorMessage => _errorMessage;
  String get loadingMessage => _loadingMessage;
  AIWorkoutResponse? get planoGerado => _planoGerado;
  Map<String, dynamic>? get athleteStats => _athleteStats;

  WorkoutController(this._repository);

  // =========================================================
  // Busca estatísticas para o dashboard (KPIs, Radar, Heatmap)
  // =========================================================
  Future<void> fetchPlanningStats(String email) async {
    try {
      _athleteStats = await _repository.fetchAthletePlanningStats(email);
      notifyListeners();
    } catch (e) {
      print('Erro ao buscar estatísticas do atleta: $e');
    }
  }

  // =========================================================
  // AÇÃO 1: Criar Novo Plano
  // =========================================================
  Future<void> criarNovoPlano({
    required String emailUtilizador,
    required String objetivoGeral,
    required String dataInicio,
    required String dataFim,
    required List<String> competicoes,
    String? notasAdicionais,
    int? aiCoachId,
    String? aiCoachName,
    double? activeHoursValue,
    String? activeHoursUnit,
    int? sessionsPerDay,
    List<String>? whereTrain,
  }) async {
    _state = WorkoutState.loading;
    _loadingMessage = '🧠 Analisando seu histórico e estruturando plano...';
    notifyListeners();

    try {
      // ── PASSO 0: Buscar estatísticas determinísticas ──
      await fetchPlanningStats(emailUtilizador);

      // ── FASE 1: estrutura + visaoSemanal ──
      final fase1 = await _repository.criarPlanoFase1(
        emailUtilizador: emailUtilizador,
        objetivoGeral: objetivoGeral,
        dataInicio: dataInicio,
        dataFim: dataFim,
        competicoes: competicoes,
        notasAdicionais: notasAdicionais,
        aiCoachName: aiCoachName,
        activeHoursValue: activeHoursValue,
        activeHoursUnit: activeHoursUnit,
        sessionsPerDay: sessionsPerDay,
        whereTrain: whereTrain,
      );
      _planoGerado = fase1;
      notifyListeners();

      // ── Extrair info do Meso 1 ──
      final blocos = (fase1.visaoGeralPlano['blocos'] as List<dynamic>?) ?? [];
      final meso1 = blocos.isNotEmpty ? (blocos.first as Map<String, dynamic>) : <String, dynamic>{};
      final meso1Nome = meso1['mesociclo']?.toString() ?? 'Mesociclo 1';
      final meso1Foco = meso1['foco']?.toString() ?? '';

      // ── Agrupar visaoSemanal por semana ──
      final Map<int, List<Map<String, dynamic>>> weekGroups = {};
      for (final dia in fase1.visaoSemanal) {
        if (!dia.isDescansoAtivo) {
          weekGroups.putIfAbsent(dia.week, () => []).add(dia.toJson());
        }
      }
      final weeksOrdered = weekGroups.keys.toList()..sort();
      final totalSemanas = weeksOrdered.length;

      // ── Gerar exercícios em PARALELO (Otimização para versões pagas) ──
      _loadingMessage = '⚡ Gerando exercícios em paralelo (Semanas 1 a $totalSemanas)...';
      notifyListeners();

      final List<ExercicioDetalhado> todosExercicios = [];
      
      final List<Future<List<ExercicioDetalhado>>> futureWeeks = weeksOrdered.map((weekNum) {
        return _repository.gerarExerciciosSemana(
          emailUtilizador: emailUtilizador,
          diasSemana: weekGroups[weekNum]!,
          mesoContext: {
            'nome': meso1Nome,
            'objetivo': objetivoGeral,
            'dataInicio': dataInicio,
            'dataFim': dataFim,
            'semanaNum': weekNum,
            'totalSemanas': totalSemanas,
            'focoSemana': meso1Foco,
            'contexto_atleta': _athleteStats?['kpis'], // Injeta KPIs no contexto da IA
          },
          aiCoachName: aiCoachName,
        );
      }).toList();

      // Aguarda todas as semanas concluírem em paralelo
      final results = await Future.wait(futureWeeks);
      for (final res in results) {
        todosExercicios.addAll(res);
      }

      // ── Montar resposta final ──
      final finalResponse = AIWorkoutResponse.fromJson({
        ...fase1.toJson(),
        'exerciciosDetalhados': todosExercicios.map((e) => e.toJson()).toList(),
      });
      _planoGerado = finalResponse;

      _loadingMessage = '💾 Salvando plano na base de dados...';
      notifyListeners();

      // ── Salvar metadados do plano ──
      final novoPlanoId = await SupabaseService.saveTrainingPlan({
        'start_date': dataInicio,
        'end_date': dataFim.isEmpty ? null : dataFim,
        'notes': notasAdicionais,
        'competitions': competicoes.map((c) => {'name': c, 'date': null}).toList(),
        'actual_plan_summary': jsonEncode(finalResponse.visaoGeralPlano),
        'workouts_plan_text': jsonEncode(finalResponse.analiseMacro),
        'workouts_plan_table': finalResponse.visaoSemanal.map((v) => v.toJson()).toList(),
      }, aiCoachName: aiCoachName);

      // ── Limpar sessões IA futuras antigas ──
      final hoje = DateTime.now();
      final hojeStr = '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}';
      try {
        await SupabaseService.client
            .from('sessions')
            .delete()
            .eq('user_email', emailUtilizador)
            .eq('ai_coach_name', aiCoachName ?? 'Human Coach')
            .not('plan_id', 'is', null)
            .gt('date', hojeStr);
      } catch (e) {
        print('Erro ao limpar sessões IA antigas: $e');
      }

      // ── Salvar exercícios ──
      if (finalResponse.exerciciosDetalhados.isNotEmpty) {
        _loadingMessage = '💾 Salvando ${finalResponse.exerciciosDetalhados.length} exercícios...';
        notifyListeners();
        await _repository.salvarExerciciosGerados(
          finalResponse.exerciciosDetalhados,
          emailUtilizador,
          planId: novoPlanoId,
          aiCoachName: aiCoachName,
        );
      }

      _state = WorkoutState.success;
      _loadingMessage = '';

    } catch (e) {
      _errorMessage = 'Falha ao gerar o plano: ${e.toString()}';
      _state = WorkoutState.error;
    } finally {
      notifyListeners();
    }
  }

  // =========================================================
  // AÇÃO 2: Gerar Próximo Ciclo
  // =========================================================
  Future<void> gerarProximoCiclo({
    required String emailUtilizador,
    required String planoId,
    required String actualPlanSummaryJson,
    required List currentWorkoutsTable,
    String? aiCoachName,
  }) async {
    _state = WorkoutState.loading;
    _loadingMessage = '🧠 Analisando progresso e estruturando próximo meso...';
    notifyListeners();

    try {
      // 1. Identificar o último mesociclo gerado no plano
      String? ultimoMeso;
      if (currentWorkoutsTable.isNotEmpty) {
        ultimoMeso = currentWorkoutsTable.last['mesocycle']?.toString();
      }

      // 2. Buscar estatísticas determinísticas do último ciclo
      Map<String, dynamic>? performanceStats;
      if (ultimoMeso != null) {
        performanceStats = await _repository.fetchMesocycleStats(planoId, ultimoMeso);
      }

      // ── FASE 1 ──
      final fase1 = await _repository.gerarProximoMesocicloFase1(
        emailUtilizador: emailUtilizador,
        planoId: planoId,
        actualPlanSummaryJson: actualPlanSummaryJson,
        mesosJaGerados: currentWorkoutsTable
            .map((e) => e['mesocycle']?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList(),
        aiCoachName: aiCoachName,
        performanceStats: performanceStats, // Injeta as estatísticas
      );
      _planoGerado = fase1;
      notifyListeners();

      final rawFase1 = fase1.toJson();
      final mesoCtxBase = (rawFase1['_mesoContext'] as Map<String, dynamic>?) ?? {};

      final Map<int, List<Map<String, dynamic>>> weekGroups = {};
      for (final dia in fase1.visaoSemanal) {
        if (!dia.isDescansoAtivo) {
          weekGroups.putIfAbsent(dia.week, () => []).add(dia.toJson());
        }
      }
      final weeksOrdered = weekGroups.keys.toList()..sort();
      final totalSemanas = weeksOrdered.length;

      // ── Gerar exercícios em PARALELO (Próximo Ciclo) ──
      _loadingMessage = '⚡ Gerando exercícios do novo ciclo em paralelo (1 a $totalSemanas)...';
      notifyListeners();

      final List<ExercicioDetalhado> todosExercicios = [];
      final List<Future<List<ExercicioDetalhado>>> futureWeeks = weeksOrdered.map((weekNum) {
        return _repository.gerarExerciciosSemana(
          emailUtilizador: emailUtilizador,
          diasSemana: weekGroups[weekNum]!,
          mesoContext: {
            ...mesoCtxBase,
            'semanaNum': weekNum,
            'totalSemanas': totalSemanas,
          },
          aiCoachName: aiCoachName,
        );
      }).toList();

      final results = await Future.wait(futureWeeks);
      for (final res in results) {
        todosExercicios.addAll(res);
      }

      final finalResponse = AIWorkoutResponse.fromJson({
        ...rawFase1,
        'exerciciosDetalhados': todosExercicios.map((e) => e.toJson()).toList(),
      });
      _planoGerado = finalResponse;

      _loadingMessage = '💾 Salvando novo ciclo...';
      notifyListeners();

      await SupabaseService.updateTrainingPlan(planoId, {
        'progress_analysis': jsonEncode(finalResponse.analiseMesocicloAnterior),
        'actual_plan_summary': jsonEncode(finalResponse.visaoGeralPlano),
        'workouts_plan_table': [
          ...currentWorkoutsTable,
          ...finalResponse.visaoSemanal.map((v) => v.toJson()).toList(),
        ],
      });

      if (finalResponse.exerciciosDetalhados.isNotEmpty) {
        _loadingMessage = '💾 Salvando ${finalResponse.exerciciosDetalhados.length} exercícios...';
        notifyListeners();
        await _repository.salvarExerciciosGerados(
          finalResponse.exerciciosDetalhados,
          emailUtilizador,
          planId: planoId,
          aiCoachName: aiCoachName,
        );
      }

      _state = WorkoutState.success;
      _loadingMessage = '';
    } catch (e) {
      _errorMessage = 'Falha ao gerar o próximo ciclo: ${e.toString()}';
      _state = WorkoutState.error;
    } finally {
      notifyListeners();
    }
  }

  void resetState() {
    _state = WorkoutState.initial;
    _errorMessage = '';
    _loadingMessage = '';
    _planoGerado = null;
    notifyListeners();
  }
}
