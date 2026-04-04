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
      print('Aviso: refresh de sessão falhou: $e');
    }
  }

  // =========================================================
  // Busca coaches disponíveis na tabela ai_coach
  // =========================================================
  Future<List<Map<String, dynamic>>> fetchAiCoaches() async {
    final response = await _supabase
        .from('ai_coach')
        .select('*')
        .order('id');
    return List<Map<String, dynamic>>.from(response as List);
  }

  // =========================================================
  // Busca estatísticas para o dashboard de planejamento
  // =========================================================
  Future<Map<String, dynamic>?> fetchAthletePlanningStats(String email) async {
    try {
      await _refreshSessionIfNeeded();
      final response = await _supabase.rpc(
        'get_athlete_planning_stats',
        params: {'p_email': email},
      );
      return response as Map<String, dynamic>?;
    } catch (e) {
      print('Erro ao buscar athlete planning stats: $e');
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
      print('Erro ao buscar mesocycle stats: $e');
      return null;
    }
  }

  // =========================================================
  // Migração: Atribui "Human Coach" a sessões sem coach
  // =========================================================
  Future<void> migrateLegacySessions() async {
    try {
      await _supabase
          .from('sessions')
          .update({'ai_coach_name': 'Human Coach'})
          .isFilter('ai_coach_name', null);
      print('✅ Migração de sessões legadas concluída.');
    } catch (e) {
      print('❌ Erro na migração: $e');
    }
  }

  // =========================================================
  // Limpeza: Remove dados de um coach específico para evitar fantasmas
  // =========================================================
  Future<void> cleanupCoachData(String email, String aiCoachName) async {
    await _refreshSessionIfNeeded();
    
    // Remove sessões (workouts são vinculados pela key e devem ser limpos se houver cascata ou manualmente)
    // Para garantir, limpamos workouts primeiro se não houver cascata no banco
    await _supabase
        .from('workouts')
        .delete()
        .eq('user_email', email)
        .eq('mesocycle', 'Histórico'); // Opcional, mas por segurança limpamos tudo do coach
        
    // Como a tabela workouts não tem ai_coach_name, limpamos via subquerie ou apenas as sessões
    // Na verdade, a melhor forma é limpar as sessões do coach, e os workouts associados.
    
    // 1. Buscar as chaves das sessões desse coach
    final sessions = await _supabase
        .from('sessions')
        .select('date_session_sessiontype_key')
        .eq('user_email', email)
        .eq('ai_coach_name', aiCoachName);
    
    final List<String> keys = (sessions as List).map((s) => s['date_session_sessiontype_key'] as String).toList();
    
    if (keys.isNotEmpty) {
      // 2. Limpar workouts vinculados a essas sessões
      await _supabase.from('workouts').delete().inFilter('date_session_sessiontype_key', keys);
      
      // 3. Limpar as sessões
      await _supabase.from('sessions').delete().inFilter('date_session_sessiontype_key', keys);
    }
    
    print('🧹 Limpeza de dados para $aiCoachName concluída.');
  }

  // =========================================================
  // FASE 1: Criar Plano — estrutura + visaoSemanal
  // =========================================================
  Future<AIWorkoutResponse> criarPlanoFase1({
    required String emailUtilizador,
    required String objetivoGeral,
    required String dataInicio,
    required String dataFim,
    required List<String> competicoes,
    String? notasAdicionais,
    String? aiCoachName,
    double? activeHoursValue,
    String? activeHoursUnit,
    int? sessionsPerDay,
    List<String>? whereTrain,
  }) async {
    await _refreshSessionIfNeeded();
    final response = await _supabase.functions.invoke(
      'gerar-treino',
      body: {
        'acao': 'criar_plano_fase1',
        'email_utilizador': emailUtilizador,
        'ai_coach_name': aiCoachName,
        'diretrizes_plano': {
          'objetivo': objetivoGeral,
          'data_inicio': dataInicio,
          'data_fim': dataFim,
          'competicoes': competicoes,
          'notas': notasAdicionais ?? '',
          'contexto_atleta': {
            'horas_ativas_sessao': activeHoursValue,
            'unidade_tempo': activeHoursUnit,
            'sessoes_dia': sessionsPerDay,
            'locais_treino': whereTrain,
          },
        },
      },
    );
    if (response.status != 200) {
      throw Exception('Fase 1 falhou: ${response.status} - ${response.data}');
    }
    return AIWorkoutResponse.fromJson(response.data as Map<String, dynamic>);
  }

  // =========================================================
  // FASE 1: Próximo Meso — estrutura + visaoSemanal
  // =========================================================
  Future<AIWorkoutResponse> gerarProximoMesocicloFase1({
    required String emailUtilizador,
    required String planoId,
    required String actualPlanSummaryJson,
    required List<String> mesosJaGerados,
    String? aiCoachName,
    Map<String, dynamic>? performanceStats,
  }) async {
    await _refreshSessionIfNeeded();
    final response = await _supabase.functions.invoke(
      'gerar-treino',
      body: {
        'acao': 'gerar_proximo_meso_fase1',
        'email_utilizador': emailUtilizador,
        'plano_id': planoId,
        'actual_plan_summary_json': actualPlanSummaryJson,
        'mesos_ja_gerados': mesosJaGerados,
        'ai_coach_name': aiCoachName,
        'performance_stats': performanceStats,
      },
    );
    if (response.status != 200) {
      throw Exception('Próximo Meso Fase 1 falhou: ${response.status} - ${response.data}');
    }
    return AIWorkoutResponse.fromJson(response.data as Map<String, dynamic>);
  }

  // =========================================================
  // SEMANA: Exercícios de UMA semana (loop no controller)
  // =========================================================
  Future<List<ExercicioDetalhado>> gerarExerciciosSemana({
    required String emailUtilizador,
    required List<Map<String, dynamic>> diasSemana,
    required Map<String, dynamic> mesoContext,
    String? aiCoachName,
  }) async {
    await _refreshSessionIfNeeded();
    final response = await _supabase.functions.invoke(
      'gerar-treino',
      body: {
        'acao': 'gerar_exercicios_semana',
        'email_utilizador': emailUtilizador,
        'dias_semana': diasSemana,
        'meso_context': mesoContext,
        'ai_coach_name': aiCoachName,
      },
    );
    if (response.status != 200) {
      throw Exception('Semana ${mesoContext['semanaNum']} falhou: ${response.status} - ${response.data}');
    }
    final jsonData = response.data as Map<String, dynamic>;
    final rawList = jsonData['exerciciosDetalhados'] as List<dynamic>? ?? [];
    return rawList.map((e) => ExercicioDetalhado.fromJson(e as Map<String, dynamic>)).toList();
  }

  // =========================================================
  // Salvar exercícios + sessões na base de dados
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
          print('⚠️ session_type inválido: "$safeSessionType" → usando "Crossfit"');
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
            if (aiCoachName != null) 'ai_coach_name': aiCoachName,  // ← NEW
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
      print('Erro ao salvar exercícios: $e');
      rethrow;
    }
  }
}