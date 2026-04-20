// lib/repositories/workout_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ai_workout_response.dart';

class WorkoutRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> _refreshSessionIfNeeded() async {
    try {
      final session = _supabase.auth.currentSession;
      if (session == null) return;
      final expiresAt = session.expiresAt;
      if (expiresAt != null) {
        final expiry = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
        if (expiry.isBefore(DateTime.now().add(const Duration(seconds: 60)))) {
          await _supabase.auth.refreshSession();
        }
      }
    } catch (e) {
      print('Warning: session refresh failed: $e');
    }
  }

  // =========================================================
  // Fetches available coaches from the ai_coach table
  // =========================================================
  Future<List<Map<String, dynamic>>> fetchAiCoaches() async {
    final response = await _supabase
        .from('ai_coach')
        .select('*')
        .order('id');
    return List<Map<String, dynamic>>.from(response as List);
  }

  // =========================================================
  // Fetches statistics for the planning dashboard
  // =========================================================
  Future<Map<String, dynamic>?> fetchAthletePlanningStats(String email, double weight) async {
    try {
      await _refreshSessionIfNeeded();
      final response = await _supabase.rpc(
        'get_athlete_planning_stats',
        params: {
          'p_email': email,
          'p_user_weight': weight,
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e) {
      print('Error fetching athlete planning stats: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchMesocycleStats(String planId, String mesocycleName) async {
    try {
      await _refreshSessionIfNeeded();
      final response = await _supabase.rpc(
        'get_mesocycle_performance_stats',
        params: {
          'p_plan_id': planId,
          'p_mesocycle_name': mesocycleName,
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e) {
      print('Error fetching mesocycle stats: $e');
      return null;
    }
  }

  // =========================================================
  // Migration: Assigns "Human Coach" to sessions without a coach
  // =========================================================
  Future<void> migrateLegacySessions() async {
    try {
      await _supabase
          .from('sessions')
          .update({'ai_coach_name': 'Human Coach'})
          .isFilter('ai_coach_name', null);
      print('✅ Legacy sessions migration complete.');
    } catch (e) {
      print('❌ Migration error: $e');
    }
  }

  // =========================================================
  // Cleanup: Removes data from a specific coach to avoid ghosts
  // =========================================================
  Future<void> cleanupCoachData(String email, String aiCoachName) async {
    await _refreshSessionIfNeeded();
    
    // Remove sessions (workouts are linked by key and should be cleaned if cascading or manually)
    // To ensure safety, we clean workouts first if there's no DB cascade
    await _supabase
        .from('workouts')
        .delete()
        .eq('user_email', email)
        .eq('mesocycle', 'Histórico'); // Optional, but for safety we clean everything from the coach
        
    // Since the workouts table doesn't have an ai_coach_name, we clean via subqueries or just the sessions
    // Actually, the best way is to clean the coach's sessions, and the associated workouts.
    
    // 1. Fetch the keys of the sessions for this coach
    final sessions = await _supabase
        .from('sessions')
        .select('date_session_sessiontype_key')
        .eq('user_email', email)
        .eq('ai_coach_name', aiCoachName);
    
    final List<String> keys = (sessions as List).map((s) => s['date_session_sessiontype_key'] as String).toList();
    
    if (keys.isNotEmpty) {
      // 2. Clean workouts linked to these sessions
      await _supabase.from('workouts').delete().inFilter('date_session_sessiontype_key', keys);
      
      // 3. Clean the sessions
      await _supabase.from('sessions').delete().inFilter('date_session_sessiontype_key', keys);
    }
    
    print('🧹 Data cleanup for $aiCoachName complete.');
  }

  // =========================================================
  // BACKGROUND JOBS: Create and monitor orchestrated generation
  // =========================================================

  /// Creates a background generation job. The server-side orchestrator
  /// (orchestrate-treino) will process it step by step via pg_net triggers.
  /// Returns the job UUID.
  Future<String> criarJobGeracao({
    required String jobType,
    required Map<String, dynamic> inputParams,
    required int totalSteps,
    String? aiCoachName,
  }) async {
    await _refreshSessionIfNeeded();
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final response = await _supabase.from('ai_generation_jobs').insert({
      'user_id': user.id,
      'user_email': user.email,
      'ai_coach_name': aiCoachName,
      'job_type': jobType,
      'total_steps': totalSteps,
      'input_params': inputParams,
    }).select('id').single();

    return response['id'] as String;
  }

  /// Fetches the full job record (used after completion to extract results).
  Future<Map<String, dynamic>?> fetchJobResult(String jobId) async {
    await _refreshSessionIfNeeded();
    final response = await _supabase
        .from('ai_generation_jobs')
        .select('*')
        .eq('id', jobId)
        .maybeSingle();
    return response;
  }

  // =========================================================
  // ACTION 1: gerar_analise_historica (DIRECT CALL FALLBACK)
  // Analyzes the athlete's sports history (heavy DB queries).
  // =========================================================
  Future<Map<String, dynamic>> gerarAnaliseHistorica({
    required String emailUtilizador,
    String? aiCoachName,
  }) async {
    await _refreshSessionIfNeeded();
    final response = await _supabase.functions.invoke(
      'gerar-treino',
      body: {
        'acao': 'gerar_analise_historica',
        'email_utilizador': emailUtilizador,
        'ai_coach_name': aiCoachName,
      },
    );
    if (response.status != 200) {
      throw Exception('Action gerar_analise_historica failed: ${response.status} - ${response.data}');
    }
    return response.data as Map<String, dynamic>;
  }

  // =========================================================
  // ACTION 2: criar_plano
  // Projects the macrocycle blocks. Receives analysis from Action 1.
  // =========================================================
  Future<Map<String, dynamic>> criarPlano({
    required String emailUtilizador,
    required Map<String, dynamic> analiseHistorica,
    required Map<String, dynamic> diretrizesPlano,
    Map<String, dynamic>? perfilAtleta,
    String? aiCoachName,
  }) async {
    await _refreshSessionIfNeeded();
    final response = await _supabase.functions.invoke(
      'gerar-treino',
      body: {
        'acao': 'criar_plano',
        'email_utilizador': emailUtilizador,
        'analise_historica': analiseHistorica,
        'diretrizes_plano': diretrizesPlano,
        'perfil_atleta': perfilAtleta,
        'ai_coach_name': aiCoachName,
      },
    );
    if (response.status != 200) {
      throw Exception('Action criar_plano failed: ${response.status} - ${response.data}');
    }
    return response.data as Map<String, dynamic>;
  }

  // =========================================================
  // ACTION 3: gerar_proximo_ciclo
  // Generates the weekly calendar for a specific mesocycle.
  // =========================================================
  Future<AIWorkoutResponse> gerarProximoCiclo({
    required String emailUtilizador,
    required Map<String, dynamic> blocoAtual,
    Map<String, dynamic>? performanceStats,
    Map<String, dynamic>? diasTreino,
    String? dataInicioMeso,
    String? aiCoachName,
  }) async {
    await _refreshSessionIfNeeded();
    final response = await _supabase.functions.invoke(
      'gerar-treino',
      body: {
        'acao': 'gerar_proximo_ciclo',
        'email_utilizador': emailUtilizador,
        'bloco_atual': blocoAtual,
        'performance_stats': performanceStats,
        'dias_treino': diasTreino,
        'data_inicio_meso': dataInicioMeso,
        'ai_coach_name': aiCoachName,
      },
    );
    if (response.status != 200) {
      throw Exception('Action gerar_proximo_ciclo failed: ${response.status} - ${response.data}');
    }
    return AIWorkoutResponse.fromJson(response.data as Map<String, dynamic>);
  }

  // =========================================================
  // ACTION 4: gerar_detalhamento
  // Fills the exercise matrix for one week using short keys.
  // =========================================================
  Future<List<ExercicioDetalhado>> gerarDetalhamento({
    required String emailUtilizador,
    required List<Map<String, dynamic>> visaoSemanal,
    required Map<String, dynamic> mesoContext,
    String? aiCoachName,
  }) async {
    await _refreshSessionIfNeeded();
    final response = await _supabase.functions.invoke(
      'gerar-treino',
      body: {
        'acao': 'gerar_detalhamento',
        'email_utilizador': emailUtilizador,
        'visao_semanal': visaoSemanal,
        'meso_context': mesoContext,
        'ai_coach_name': aiCoachName,
      },
    );
    if (response.status != 200) {
      throw Exception('Action gerar_detalhamento failed: ${response.status} - ${response.data}');
    }
    final jsonData = response.data as Map<String, dynamic>;
    final rawList = jsonData['exerciciosDetalhados'] as List<dynamic>? ?? [];
    return rawList.map((e) => ExercicioDetalhado.fromJson(e as Map<String, dynamic>)).toList();
  }

  // =========================================================
  // Save exercises + sessions to the database
  // =========================================================
  Future<void> salvarExerciciosGerados(
    List<ExercicioDetalhado> exercicios,
    String emailUtilizador, {
    String? planId,
    String? aiCoachName,
  }) async {
    try {
      final Map<String, Map<String, dynamic>> uniqueSessions = {};

      final validSessionTypes = {
        'Acessório', 'Acessórios/Blindagem', 'Calistenia', 'Cardio', 'Cardio-Mobilidade',
        'Core Strength', 'Core/Prep', 'Crossfit', 'Descanso', 'Endurance', 'Força/Heavy',
        'Força/Metcon', 'Força/Skill', 'Full Body Pump', 'Full Session', 'Ginástica/Metcon',
        'Hipertrofia/Blindagem', 'LPO', 'LPO/Força/Metcon', 'LPO/Metcon', 'LPO/Potência',
        'Mobilidade', 'Mobilidade Flow', 'Mobilidade-Cardio', 'Mobilidade-Core',
        'Mobilidade-Inferiores', 'Mobilidade/Prep', 'Multi', 'Musculação', 'Musculação-Cardio',
        'Musculação-Funcional', 'Musculação/Força', 'Natação', 'Prehab/Força',
        'Prehab/Mobilidade', 'Recuperação Ativa', 'Reintrodução/FBB', 'Skill', 'Skill/Metcon',
      };

      final List<Map<String, dynamic>> recordsToInsert = [];

      for (int i = 0; i < exercicios.length; i++) {
        final ex = exercicios[i];
        var safeSessionType = ex.sessionType.trim();
        if (!validSessionTypes.contains(safeSessionType)) {
          print('⚠️ invalid session_type: "$safeSessionType" → using "Crossfit"');
          safeSessionType = 'Crossfit';
        }

        final sessionKey = '${ex.date}_${ex.session}_$safeSessionType';
        if (!uniqueSessions.containsKey(sessionKey)) {
          uniqueSessions[sessionKey] = {
            'date_session_sessiontype_key': sessionKey,
            'date': ex.date,
            'session': ex.session,
            'session_type': safeSessionType,
            'user_email': emailUtilizador,
            if (planId != null) 'plan_id': planId,
            if (aiCoachName != null) 'ai_coach_name': aiCoachName,
          };
        }

        final record = ex.toJson();
        record['user_email'] = emailUtilizador;
        record['session_type'] = safeSessionType;
        record['date_session_sessiontype_key'] = sessionKey;
        record['wod_exercise_id'] = '${ex.date}_${ex.session}_${ex.workoutIdx}_${DateTime.now().millisecondsSinceEpoch % 100000}_$i';
        recordsToInsert.add(record);
      }

      if (uniqueSessions.isNotEmpty) {
        await _supabase.from('sessions').upsert(
          uniqueSessions.values.toList(),
          onConflict: 'date_session_sessiontype_key',
        );
      }

      if (recordsToInsert.isNotEmpty) {
        await _supabase.from('workouts').insert(recordsToInsert);
      }
    } catch (e) {
      print('Error saving exercises: $e');
      rethrow;
    }
  }
}