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

  WorkoutState get state => _state;
  bool get isLoading => _state == WorkoutState.loading;
  String get errorMessage => _errorMessage;
  String get loadingMessage => _loadingMessage;
  AIWorkoutResponse? get planoGerado => _planoGerado;

  WorkoutController(this._repository);

  // =========================================================
  // AÇÃO 1: Criar Novo Plano
  //
  // Fluxo (respeita 5 RPM do gemini-2.5-flash):
  //   [t=0s]    Fase 1: estrutura + visaoSemanal         (~25s)
  //   [t=25s]   delay 13s
  //   [t=38s]   Semana 1: exercícios                     (~20s)
  //   [t=58s]   delay 13s
  //   [t=71s]   Semana 2: exercícios                     (~20s)
  //   ...e assim por diante para cada semana do Meso 1
  // =========================================================
  Future<void> criarNovoPlano({
    required String emailUtilizador,
    required String objetivoGeral,
    required String dataInicio,
    required String dataFim,
    required List<String> competicoes,
    String? notasAdicionais,
  }) async {
    _state = WorkoutState.loading;
    _loadingMessage = '🧠 Estruturando plano e calendário...';
    notifyListeners();

    try {
      // ── FASE 1: estrutura + visaoSemanal ──────────────────────────
      final fase1 = await _repository.criarPlanoFase1(
        emailUtilizador: emailUtilizador,
        objetivoGeral: objetivoGeral,
        dataInicio: dataInicio,
        dataFim: dataFim,
        competicoes: competicoes,
        notasAdicionais: notasAdicionais,
      );
      _planoGerado = fase1;
      notifyListeners();

      // ── Extrair info do Meso 1 para o contexto das semanas ────────
      final blocos = (fase1.visaoGeralPlano['blocos'] as List<dynamic>?) ?? [];
      final meso1 = blocos.isNotEmpty ? (blocos.first as Map<String, dynamic>) : <String, dynamic>{};
      final meso1Nome = meso1['mesociclo']?.toString() ?? 'Mesociclo 1';
      final meso1Foco = meso1['foco']?.toString() ?? '';

      // ── Agrupar visaoSemanal por semana (apenas dias de treino) ───
      final Map<int, List<Map<String, dynamic>>> weekGroups = {};
      for (final dia in fase1.visaoSemanal) {
        if (!dia.isDescansoAtivo) {
          weekGroups.putIfAbsent(dia.week, () => []).add(dia.toJson());
        }
      }
      final weeksOrdered = weekGroups.keys.toList()..sort();
      final totalSemanas = weeksOrdered.length;

      // ── Gerar exercícios semana por semana ────────────────────────
      final List<ExercicioDetalhado> todosExercicios = [];

      for (int i = 0; i < weeksOrdered.length; i++) {
        final weekNum = weeksOrdered[i];

        // Delay de 13s entre chamadas (respeita 5 RPM)
        _loadingMessage = '⏳ Preparando semana ${weekNum}/$totalSemanas...';
        notifyListeners();
        await Future.delayed(const Duration(seconds: 13));

        _loadingMessage = '💪 Gerando exercícios — Semana $weekNum/$totalSemanas';
        notifyListeners();

        final exerciciosSemana = await _repository.gerarExerciciosSemana(
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
          },
        );
        todosExercicios.addAll(exerciciosSemana);
      }

      // ── Montar resposta final ─────────────────────────────────────
      final finalResponse = AIWorkoutResponse.fromJson({
        ...fase1.toJson(),
        'exerciciosDetalhados': todosExercicios.map((e) => e.toJson()).toList(),
      });
      _planoGerado = finalResponse;

      _loadingMessage = '💾 Salvando plano na base de dados...';
      notifyListeners();

      // ── Salvar metadados do plano ─────────────────────────────────
      final novoPlanoId = await SupabaseService.saveTrainingPlan({
        'start_date': dataInicio,
        'end_date': dataFim.isEmpty ? null : dataFim,
        'notes': notasAdicionais,
        'competitions': competicoes.map((c) => {'name': c, 'date': null}).toList(),
        'actual_plan_summary': jsonEncode(finalResponse.visaoGeralPlano),
        'workouts_plan_text': jsonEncode(finalResponse.analiseMacro),
        'workouts_plan_table': finalResponse.visaoSemanal.map((v) => v.toJson()).toList(),
      });

      // ── Limpar sessões futuras da IA anteriores (preservar manuais) ──
      final hoje = DateTime.now();
      final hojeStr = '${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}';
      try {
        await SupabaseService.client
            .from('sessions')
            .delete()
            .eq('user_email', emailUtilizador)
            .not('plan_id', 'is', null)
            .gt('date', hojeStr);
      } catch (e) {
        print('Erro ao limpar sessões IA antigas: $e');
      }

      // ── Salvar exercícios ─────────────────────────────────────────
      if (finalResponse.exerciciosDetalhados.isNotEmpty) {
        _loadingMessage = '💾 Salvando ${finalResponse.exerciciosDetalhados.length} exercícios...';
        notifyListeners();
        await _repository.salvarExerciciosGerados(
          finalResponse.exerciciosDetalhados,
          emailUtilizador,
          planId: novoPlanoId,
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
  }) async {
    _state = WorkoutState.loading;
    _loadingMessage = '🧠 Analisando progresso e estruturando próximo meso...';
    notifyListeners();

    try {
      // Deriva mesociclos já gerados
      final Set<String> mesosGeradosSet = {};
      for (final row in currentWorkoutsTable) {
        if (row is Map) {
          final meso = row['mesocycle']?.toString();
          if (meso != null && meso.isNotEmpty) mesosGeradosSet.add(meso);
        }
      }

      // ── FASE 1: estrutura do próximo meso ─────────────────────────
      final fase1 = await _repository.gerarProximoMesocicloFase1(
        emailUtilizador: emailUtilizador,
        planoId: planoId,
        actualPlanSummaryJson: actualPlanSummaryJson,
        mesosJaGerados: mesosGeradosSet.toList(),
      );
      _planoGerado = fase1;
      notifyListeners();

      // Extrai contexto que a Edge Function embutiu na resposta (_mesoContext)
      final rawFase1 = fase1.toJson();
      final mesoCtxBase = (rawFase1['_mesoContext'] as Map<String, dynamic>?) ?? {};

      // Agrupar visaoSemanal por semana
      final Map<int, List<Map<String, dynamic>>> weekGroups = {};
      for (final dia in fase1.visaoSemanal) {
        if (!dia.isDescansoAtivo) {
          weekGroups.putIfAbsent(dia.week, () => []).add(dia.toJson());
        }
      }
      final weeksOrdered = weekGroups.keys.toList()..sort();
      final totalSemanas = weeksOrdered.length;

      // ── Gerar exercícios semana por semana ────────────────────────
      final List<ExercicioDetalhado> todosExercicios = [];

      for (int i = 0; i < weeksOrdered.length; i++) {
        final weekNum = weeksOrdered[i];

        _loadingMessage = '⏳ Preparando semana $weekNum/$totalSemanas...';
        notifyListeners();
        await Future.delayed(const Duration(seconds: 13));

        _loadingMessage = '💪 Gerando exercícios — Semana $weekNum/$totalSemanas';
        notifyListeners();

        final exerciciosSemana = await _repository.gerarExerciciosSemana(
          emailUtilizador: emailUtilizador,
          diasSemana: weekGroups[weekNum]!,
          mesoContext: {
            ...mesoCtxBase,
            'semanaNum': weekNum,
            'totalSemanas': totalSemanas,
          },
        );
        todosExercicios.addAll(exerciciosSemana);
      }

      // ── Montar resposta final ─────────────────────────────────────
      final finalResponse = AIWorkoutResponse.fromJson({
        ...rawFase1,
        'exerciciosDetalhados': todosExercicios.map((e) => e.toJson()).toList(),
      });
      _planoGerado = finalResponse;

      _loadingMessage = '💾 Salvando novo ciclo...';
      notifyListeners();

      // ── Atualizar plano ───────────────────────────────────────────
      await SupabaseService.updateTrainingPlan(planoId, {
        'progress_analysis': jsonEncode(finalResponse.analiseMesocicloAnterior),
        'actual_plan_summary': jsonEncode(finalResponse.visaoGeralPlano),
        'workouts_plan_table': [
          ...currentWorkoutsTable,
          ...finalResponse.visaoSemanal.map((v) => v.toJson()).toList(),
        ],
      });

      // ── Salvar exercícios ─────────────────────────────────────────
      if (finalResponse.exerciciosDetalhados.isNotEmpty) {
        _loadingMessage = '💾 Salvando ${finalResponse.exerciciosDetalhados.length} exercícios...';
        notifyListeners();
        await _repository.salvarExerciciosGerados(
          finalResponse.exerciciosDetalhados,
          emailUtilizador,
          planId: planoId,
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
