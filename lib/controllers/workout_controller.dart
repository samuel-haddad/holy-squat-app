// lib/controllers/workout_controller.dart

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  // Background job tracking
  RealtimeChannel? _jobChannel;
  Completer<void>? _jobCompleter;

  WorkoutState get state => _state;
  bool get isLoading => _state == WorkoutState.loading;
  String get errorMessage => _errorMessage;
  String get loadingMessage => _loadingMessage;
  AIWorkoutResponse? get planoGerado => _planoGerado;
  Map<String, dynamic>? get athleteStats => _athleteStats;

  WorkoutController(this._repository);

  // Step-specific loading messages
  static const _newPlanStepMessages = {
    1: '🧠 Ação 1/4 — Analisando histórico esportivo...',
    2: '📋 Ação 2/4 — Projetando blocos do macrociclo...',
    3: '📆 Ação 3/4 — Gerando calendário semanal...',
    4: '⚡ Ação 4/4 — Gerando exercícios detalhados...',
  };

  static const _nextCycleStepMessages = {
    1: '🧠 Ação 1/2 — Analisando progresso e gerando calendário...',
    2: '⚡ Ação 2/2 — Gerando exercícios detalhados...',
  };

  // =========================================================
  // Fetches statistics for the dashboard (KPIs, Radar, Heatmap)
  // =========================================================
  Future<void> fetchPlanningStats(String email) async {
    try {
      _athleteStats = await _repository.fetchAthletePlanningStats(email);
      notifyListeners();
    } catch (e) {
      print('Error fetching athlete statistics: $e');
    }
  }

  // =========================================================
  // CREATE NEW PLAN — Background orchestration via webhooks
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
    _loadingMessage = '🚀 Iniciando geração do plano em background...';
    notifyListeners();

    try {
      await fetchPlanningStats(emailUtilizador);

      // 1. Create background job
      final jobId = await _repository.criarJobGeracao(
        jobType: 'new_plan',
        totalSteps: 4,
        aiCoachName: aiCoachName,
        inputParams: {
          'email_utilizador': emailUtilizador,
          'ai_coach_name': aiCoachName,
          'diretrizes_plano': {
            'objetivo': objetivoGeral,
            'data_inicio': dataInicio,
            'data_fim': dataFim,
            'competicoes': competicoes,
            'notas': notasAdicionais ?? '',
          },
          'perfil_atleta': {
            'sessions_per_day': sessionsPerDay,
            'where_train': whereTrain,
            'active_hours_value': activeHoursValue,
            'active_hours_unit': activeHoursUnit,
          },
        },
      );

      _loadingMessage = _newPlanStepMessages[1]!;
      notifyListeners();

      // 2. Subscribe to Realtime and wait for completion
      await _subscribeAndWait(jobId, _newPlanStepMessages);

      // 3. Fetch final result and build response
      final job = await _repository.fetchJobResult(jobId);
      if (job == null) throw Exception('Job result not found');

      if (job['status'] == 'error') {
        throw Exception(job['error_message'] ?? 'Unknown server error');
      }

      _planoGerado = _buildResponseFromNewPlanJob(job);
      _state = WorkoutState.success;
      _loadingMessage = '';

    } catch (e) {
      _errorMessage = 'Falha ao gerar o plano: ${e.toString()}';
      _state = WorkoutState.error;
    } finally {
      _cleanupJobChannel();
      notifyListeners();
    }
  }

  // =========================================================
  // GENERATE NEXT CYCLE — Background orchestration via webhooks
  // =========================================================
  Future<void> gerarProximoCiclo({
    required String emailUtilizador,
    required String planoId,
    required String actualPlanSummaryJson,
    required List currentWorkoutsTable,
    String? aiCoachName,
  }) async {
    _state = WorkoutState.loading;
    _loadingMessage = '🚀 Iniciando geração do próximo ciclo em background...';
    notifyListeners();

    try {
      // Identify mesos already generated
      final mesosJaGerados = currentWorkoutsTable
          .map((e) => e['mesocycle']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      // 1. Create background job
      final jobId = await _repository.criarJobGeracao(
        jobType: 'next_cycle',
        totalSteps: 2,
        aiCoachName: aiCoachName,
        inputParams: {
          'email_utilizador': emailUtilizador,
          'ai_coach_name': aiCoachName,
          'plano_id': planoId,
          'actual_plan_summary_json': actualPlanSummaryJson,
          'mesos_ja_gerados': mesosJaGerados,
          'current_workouts_table': currentWorkoutsTable,
        },
      );

      _loadingMessage = _nextCycleStepMessages[1]!;
      notifyListeners();

      // 2. Subscribe and wait
      await _subscribeAndWait(jobId, _nextCycleStepMessages);

      // 3. Fetch final result
      final job = await _repository.fetchJobResult(jobId);
      if (job == null) throw Exception('Job result not found');

      if (job['status'] == 'error') {
        throw Exception(job['error_message'] ?? 'Unknown server error');
      }

      _planoGerado = _buildResponseFromNextCycleJob(job);
      _state = WorkoutState.success;
      _loadingMessage = '';

    } catch (e) {
      _errorMessage = 'Falha ao gerar o próximo ciclo: ${e.toString()}';
      _state = WorkoutState.error;
    } finally {
      _cleanupJobChannel();
      notifyListeners();
    }
  }

  // =========================================================
  // Realtime subscription for job progress
  // =========================================================
  Future<void> _subscribeAndWait(
    String jobId,
    Map<int, String> stepMessages,
  ) async {
    _jobCompleter = Completer<void>();
    final supabase = Supabase.instance.client;

    _jobChannel = supabase
        .channel('job:$jobId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ai_generation_jobs',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: jobId,
          ),
          callback: (PostgresChangePayload payload) {
            final newData = payload.newRecord;
            final step = newData['current_step'] as int? ?? 1;
            final status = newData['status'] as String? ?? 'processing';

            // Update loading message based on step
            if (stepMessages.containsKey(step)) {
              _loadingMessage = stepMessages[step]!;
              notifyListeners();
            }

            // Check for completion
            if (status == 'completed') {
              _loadingMessage = '💾 Dados salvos pelo servidor. Finalizando...';
              notifyListeners();
              if (!_jobCompleter!.isCompleted) {
                _jobCompleter!.complete();
              }
            } else if (status == 'error') {
              if (!_jobCompleter!.isCompleted) {
                _jobCompleter!.complete();
              }
            }
          },
        )
        .subscribe();

    // Safety timeout: 10 minutes max wait
    await _jobCompleter!.future.timeout(
      const Duration(minutes: 10),
      onTimeout: () {
        throw Exception('Timeout: a geração excedeu 10 minutos.');
      },
    );
  }

  void _cleanupJobChannel() {
    if (_jobChannel != null) {
      Supabase.instance.client.removeChannel(_jobChannel!);
      _jobChannel = null;
    }
    _jobCompleter = null;
  }

  // =========================================================
  // Build AIWorkoutResponse from job results
  // =========================================================
  AIWorkoutResponse _buildResponseFromNewPlanJob(Map<String, dynamic> job) {
    final step1 = job['step_1_result'] as Map<String, dynamic>? ?? {};
    final step2 = job['step_2_result'] as Map<String, dynamic>? ?? {};
    final step3 = job['step_3_result'] as Map<String, dynamic>? ?? {};
    final step4 = job['step_4_result'] as Map<String, dynamic>? ?? {};

    return AIWorkoutResponse.fromJson({
      'analiseMacro': step1['analiseMacro'],
      'visaoGeralPlano': step2['visaoGeralPlano'] ?? {},
      'analiseCicloAnterior': step3['analiseCicloAnterior'],
      'visaoGeralCiclo': step3['visaoGeralCiclo'],
      'visaoSemanal': step3['visaoSemanal'] ?? [],
      'exerciciosDetalhados': step4['exerciciosDetalhados'] ?? [],
    });
  }

  AIWorkoutResponse _buildResponseFromNextCycleJob(Map<String, dynamic> job) {
    final step1 = job['step_1_result'] as Map<String, dynamic>? ?? {};
    final step2 = job['step_2_result'] as Map<String, dynamic>? ?? {};
    final inputParams = job['input_params'] as Map<String, dynamic>? ?? {};

    Map<String, dynamic> planSummary = {};
    try {
      planSummary = jsonDecode(inputParams['actual_plan_summary_json'] ?? '{}');
    } catch (_) {}

    return AIWorkoutResponse.fromJson({
      'analiseCicloAnterior': step1['analiseCicloAnterior'],
      'visaoGeralCiclo': step1['visaoGeralCiclo'],
      'visaoGeralPlano': planSummary,
      'visaoSemanal': step1['visaoSemanal'] ?? [],
      'exerciciosDetalhados': step2['exerciciosDetalhados'] ?? [],
    });
  }

  // =========================================================
  // Reset
  // =========================================================
  void resetState() {
    _cleanupJobChannel();
    _state = WorkoutState.initial;
    _errorMessage = '';
    _loadingMessage = '';
    _planoGerado = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _cleanupJobChannel();
    super.dispose();
  }
}
