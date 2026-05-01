import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ai_workout_response.dart';
import '../models/training_session.dart';
import '../repositories/workout_repository.dart';
import '../services/supabase_service.dart';
import '../core/user_state.dart';

enum WorkoutState { initial, loading, success, error }

class WorkoutController extends ChangeNotifier {
  final WorkoutRepository _repository;

  WorkoutState _state = WorkoutState.initial;
  String _errorMessage = '';
  String _loadingMessage = '';
  AIWorkoutResponse? _planoGerado;
  Map<String, dynamic>? _athleteStats;

  RealtimeChannel? _jobChannel;
  Completer<void>? _jobCompleter;
  String? _currentCycleJobId;

  WorkoutState get state => _state;
  bool get isLoading => _state == WorkoutState.loading;
  String get errorMessage => _errorMessage;
  String get loadingMessage => _loadingMessage;
  AIWorkoutResponse? get planoGerado => _planoGerado;
  Map<String, dynamic>? get athleteStats => _athleteStats;
  String? get currentCycleJobId => _currentCycleJobId;

  WorkoutController(this._repository);

  // Step messages for each job type
  static const _createPlanSteps = {
    1: '🧠 Ação 1/2 — Analisando histórico esportivo...',
    2: '📋 Ação 2/2 — Projetando blocos do macrociclo...',
  };

  static const _generateCycleSteps = {
    1: '🧠 Ação 1/2 — Analisando histórico e visão geral...',
    2: '📆 Ação 2/2 — Estruturando calendário semanal...',
  };

  static const _generateWorkoutsSteps = {
    1: '⚡ Gerando detalhamento dos treinos...',
  };

  // =========================================================
  // Stats
  // =========================================================
  Future<void> fetchPlanningStats(String email, double weight) async {
    try {
      _athleteStats = await _repository.fetchAthletePlanningStats(email, weight);
      notifyListeners();
    } catch (e) {
      print('Error fetching athlete statistics: $e');
    }
  }

  // =========================================================
  // CREATE PLAN (Ações 1+2) — "3, 2, 1... GO!" button
  // =========================================================
  Future<void> criarNovoPlano({
    required String emailUtilizador,
    required String objetivoGeral,
    required String dataInicio,
    required String dataFim,
    required List<Map<String, dynamic>> competicoes,
    List<Map<String, dynamic>>? ferias,
    List<String>? lesoes,
    String? notasAdicionais,
    int? aiCoachId,
    String? aiCoachName,
    List<TrainingSession>? trainingSessions,
  }) async {
    _state = WorkoutState.loading;
    _loadingMessage = '🚀 Iniciando análise e planejamento...';
    notifyListeners();

    try {
      final double rawWeight = double.tryParse(UserState.weight.value) ?? 0.0;
      final bool isLbs = UserState.weightUnit.value.toLowerCase().contains('lb');
      final double userWeight = isLbs ? rawWeight * 0.453592 : rawWeight;
      await fetchPlanningStats(emailUtilizador, userWeight);

      final jobId = await _repository.criarJobGeracao(
        jobType: 'create_plan',
        totalSteps: 2,
        aiCoachName: aiCoachName,
        inputParams: {
          'email_utilizador': emailUtilizador,
          'ai_coach_name': aiCoachName,
          'diretrizes_plano': {
            'objetivo': objetivoGeral,
            'data_inicio': dataInicio,
            'data_fim': dataFim,
            'competicoes': competicoes,
            'ferias': ferias ?? [],
            'lesoes': lesoes ?? [],
            'notas': notasAdicionais ?? '',
          },
          'training_sessions': (trainingSessions ?? []).map((s) => s.toJson()).toList(),
        },
      );

      _loadingMessage = _createPlanSteps[1]!;
      notifyListeners();

      await _subscribeAndWait(jobId, _createPlanSteps, isGenerateCycle: false);

      final job = await _repository.fetchJobResult(jobId);
      if (job == null) throw Exception('Job result not found');
      if (job['status'] == 'error') throw Exception(job['error_message'] ?? 'Unknown server error');

      _planoGerado = _buildResponseFromCreatePlanJob(job);
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
  // GENERATE ANALYSIS (Ações 3a+3b) — "Next Cycle" button
  // =========================================================
  Future<void> gerarAnaliseCiclo({
    required String emailUtilizador,
    required String planoId,
    required String actualPlanSummaryJson,
    required List currentWorkoutsTable,
    List<TrainingSession>? trainingSessions,
    String? aiCoachName,
  }) async {
    _state = WorkoutState.loading;
    _loadingMessage = '🚀 Iniciando análise e calendário do ciclo...';
    notifyListeners();

    try {
      final mesosJaGerados = currentWorkoutsTable
          .map((e) => e['mesocycle']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      final jobId = await _repository.criarJobGeracao(
        jobType: 'generate_cycle',
        totalSteps: 2,
        aiCoachName: aiCoachName,
        inputParams: {
          'email_utilizador': emailUtilizador,
          'ai_coach_name': aiCoachName,
          'plano_id': planoId,
          'actual_plan_summary_json': actualPlanSummaryJson,
          'mesos_ja_gerados': mesosJaGerados,
          'current_workouts_table': currentWorkoutsTable,
          'training_sessions': (trainingSessions ?? []).map((s) => s.toJson()).toList(),
        },
      );

      _loadingMessage = _generateCycleSteps[1]!;
      notifyListeners();

      await _subscribeAndWait(jobId, _generateCycleSteps, isGenerateCycle: true);

      final job = await _repository.fetchJobResult(jobId);
      if (job == null) throw Exception('Job result not found');
      if (job['status'] == 'error') throw Exception(job['error_message'] ?? 'Unknown server error');

      _planoGerado = _buildResponseFromGenerateCycleJob(job);
      _state = WorkoutState.success;
      _loadingMessage = '';

    } catch (e) {
      _errorMessage = 'Falha ao gerar a análise do ciclo: ${e.toString()}';
      _state = WorkoutState.error;
    } finally {
      _cleanupJobChannel();
      notifyListeners();
    }
  }

  // =========================================================
  // RESTORE CYCLE — "Restore" button
  // =========================================================
  Future<void> restaurarCiclo({
    required String emailUtilizador,
    required String planoId,
    required String actualPlanSummaryJson,
    required List currentWorkoutsTable,
    List<TrainingSession>? trainingSessions,
    String? aiCoachName,
  }) async {
    try {
      await _repository.removeLastMeso(planoId);
      
      // Remove the last mesocycle from the in-memory table so it gets regenerated
      String? lastMeso;
      if (currentWorkoutsTable.isNotEmpty) {
        lastMeso = currentWorkoutsTable.last['mesocycle']?.toString();
      }
      final newTable = List.from(currentWorkoutsTable);
      if (lastMeso != null) {
        newTable.removeWhere((row) => row['mesocycle']?.toString() == lastMeso);
      }

      await gerarAnaliseCiclo(
        emailUtilizador: emailUtilizador,
        planoId: planoId,
        actualPlanSummaryJson: actualPlanSummaryJson,
        currentWorkoutsTable: newTable,
        trainingSessions: trainingSessions,
        aiCoachName: aiCoachName,
      );
    } catch (e) {
      _errorMessage = 'Falha ao restaurar ciclo: ${e.toString()}';
      _state = WorkoutState.error;
      notifyListeners();
    }
  }

  // =========================================================
  // GENERATE WORKOUTS (Ação 4) — "Workouts" button
  // =========================================================
  Future<void> gerarExerciciosDetalhados({
    required String emailUtilizador,
    required String planoId,
    required List visaoSemanal,
    required Map blocoAtual,
    List<TrainingSession>? trainingSessions,
    String? aiCoachName,
  }) async {
    _state = WorkoutState.loading;
    _loadingMessage = '⚡ Iniciando detalhamento dos treinos...';
    notifyListeners();

    try {
      final plan = await SupabaseService.fetchLatestTrainingPlan(aiCoachName: aiCoachName);
      Map<String, dynamic> planSummary = {};
      try { planSummary = jsonDecode(plan?['actual_plan_summary'] ?? '{}'); } catch (_) {}

      final activeDaysCount = visaoSemanal.where((d) => d['isDescansoAtivo'] != true).length;

      final jobId = await _repository.criarJobGeracao(
        jobType: 'generate_workouts',
        totalSteps: activeDaysCount,
        aiCoachName: aiCoachName,
        inputParams: {
          'email_utilizador': emailUtilizador,
          'plano_id': planoId,
          'ai_coach_name': aiCoachName,
          'visao_semanal': visaoSemanal,
          'bloco_atual': blocoAtual,
          'plan_summary': planSummary,
          'training_sessions': (trainingSessions ?? []).map((s) => s.toJson()).toList(),
        },
      );

      _loadingMessage = '⚡ Gerando treino do dia 1/$activeDaysCount...';
      notifyListeners();

      await _subscribeAndWait(jobId, {}, isGenerateWorkouts: true);

      final job = await _repository.fetchJobResult(jobId);
      if (job == null) throw Exception('Job result not found');
      if (job['status'] == 'error') throw Exception(job['error_message'] ?? 'Unknown server error');

      _state = WorkoutState.success;
      _loadingMessage = '';

    } catch (e) {
      _errorMessage = 'Falha ao detalhar o ciclo: ${e.toString()}';
      _state = WorkoutState.error;
    } finally {
      _cleanupJobChannel();
      notifyListeners();
    }
  }

  // =========================================================
  // Resume the Job for Action 4
  // =========================================================
  Future<void> gerarDetalhamento() async {
    if (_currentCycleJobId == null) return;
    
    _state = WorkoutState.loading;
    _loadingMessage = '⚡ Iniciando detalhamento dos treinos...';
    notifyListeners();

    try {
      final supabase = Supabase.instance.client;
      await supabase.from('ai_generation_jobs').update({
        'status': 'processing'
      }).eq('id', _currentCycleJobId!);

      await _subscribeAndWait(_currentCycleJobId!, {}, isGenerateCycle: true);

      final job = await _repository.fetchJobResult(_currentCycleJobId!);
      if (job == null) throw Exception('Job result not found');
      if (job['status'] == 'error') throw Exception(job['error_message'] ?? 'Unknown server error');

      _planoGerado = _buildResponseFromGenerateCycleJob(job);
      _state = WorkoutState.success;
      _loadingMessage = '';
      _currentCycleJobId = null;

    } catch (e) {
      _errorMessage = 'Falha ao detalhar o ciclo: ${e.toString()}';
      _state = WorkoutState.error;
    } finally {
      _cleanupJobChannel();
      notifyListeners();
    }
  }

  // =========================================================
  // Realtime subscription
  // =========================================================
  Future<void> _subscribeAndWait(String jobId, Map<int, String> stepMessages, {bool isGenerateCycle = false, bool isGenerateWorkouts = false}) async {
    _jobCompleter = Completer<void>();
    final supabase = Supabase.instance.client;
    Timer? pollTimer;

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

            if (isGenerateWorkouts) {
              int totalDays = 1;
              try {
                final input = newData['input_params'] as Map<String, dynamic>? ?? {};
                final visaoSemanal = input['visao_semanal'] as List<dynamic>? ?? [];
                totalDays = visaoSemanal.where((d) => d['isDescansoAtivo'] != true).length;
                if (totalDays == 0) totalDays = 1;
              } catch (_) {}
              
              _loadingMessage = '⚡ Gerando treino do dia $step/$totalDays...';
              notifyListeners();
            } else if (stepMessages.containsKey(step)) {
              _loadingMessage = stepMessages[step]!;
              notifyListeners();
            }

            if (status == 'completed' || status == 'pending_approval') {
              _loadingMessage = '💾 Dados salvos. Finalizando...';
              notifyListeners();
              if (!_jobCompleter!.isCompleted) _jobCompleter!.complete();
            } else if (status == 'error') {
              if (!_jobCompleter!.isCompleted) _jobCompleter!.complete();
            }
          },
        )
        .subscribe();

    // Polling fallback: consulta o job a cada 30s caso o Realtime
    // WebSocket falhe ou o orquestrador seja encerrado silenciosamente.
    pollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_jobCompleter == null || _jobCompleter!.isCompleted) return;
      try {
        final job = await _repository.fetchJobResult(jobId);
        if (job == null) return;
        final status = job['status'] as String? ?? 'processing';
        final step   = job['current_step'] as int? ?? 1;

        if (isGenerateWorkouts) {
          int totalDays = 1;
          try {
            final input = job['input_params'] as Map<String, dynamic>? ?? {};
            final visaoSemanal = input['visao_semanal'] as List<dynamic>? ?? [];
            totalDays = visaoSemanal.where((d) => d['isDescansoAtivo'] != true).length;
            if (totalDays == 0) totalDays = 1;
          } catch (_) {}
          
          _loadingMessage = '⚡ Gerando treino do dia $step/$totalDays...';
          notifyListeners();
        } else if (stepMessages.containsKey(step)) {
          _loadingMessage = stepMessages[step]!;
          notifyListeners();
        }

        if (status == 'completed' || status == 'pending_approval') {
          _loadingMessage = '💾 Dados salvos. Finalizando (polling)...';
          notifyListeners();
          if (!_jobCompleter!.isCompleted) _jobCompleter!.complete();
        } else if (status == 'error') {
          if (!_jobCompleter!.isCompleted) _jobCompleter!.complete();
        }
      } catch (_) {
        // ignora erros de rede no polling
      }
    });

    try {
      await _jobCompleter!.future.timeout(
        const Duration(minutes: 15),
        onTimeout: () => throw Exception('Timeout: geração excedeu 15 minutos.'),
      );
    } finally {
      pollTimer.cancel();
    }
  }

  void _cleanupJobChannel() {
    if (_jobChannel != null) {
      Supabase.instance.client.removeChannel(_jobChannel!);
      _jobChannel = null;
    }
    _jobCompleter = null;
  }

  // =========================================================
  // Build responses from job results
  // =========================================================
  AIWorkoutResponse _buildResponseFromCreatePlanJob(Map<String, dynamic> job) {
    final step1 = job['step_1_result'] as Map<String, dynamic>? ?? {};
    final step2 = job['step_2_result'] as Map<String, dynamic>? ?? {};

    return AIWorkoutResponse.fromJson({
      'analiseMacro': step1['analiseMacro'],
      'visaoGeralPlano': step2['visaoGeralPlano'] ?? {},
      'visaoSemanal': [],
      'exerciciosDetalhados': [],
    });
  }

  AIWorkoutResponse _buildResponseFromGenerateCycleJob(Map<String, dynamic> job) {
    final step1 = job['step_1_result'] as Map<String, dynamic>? ?? {};
    final step2 = job['step_2_result'] as Map<String, dynamic>? ?? {};
    final inputParams = job['input_params'] as Map<String, dynamic>? ?? {};

    Map<String, dynamic> planSummary = {};
    try { planSummary = jsonDecode(inputParams['actual_plan_summary_json'] ?? '{}'); } catch (_) {}

    return AIWorkoutResponse.fromJson({
      'analiseCicloAnterior': step1['analiseCicloAnterior'],
      'visaoGeralCiclo': step1['visaoGeralCiclo'],
      'visaoGeralPlano': planSummary,
      'visaoSemanal': step1['visaoSemanal'] ?? [],
      'exerciciosDetalhados': step2['exerciciosDetalhados'] ?? [],
    });
  }

  // =========================================================
  // Reset / Dispose
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
