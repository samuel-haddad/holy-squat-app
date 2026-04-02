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
  // FASE 1: Criar Plano — estrutura + visaoSemanal
  // =========================================================
  Future<AIWorkoutResponse> criarPlanoFase1({
    required String emailUtilizador,
    required String objetivoGeral,
    required String dataInicio,
    required String dataFim,
    required List<String> competicoes,
    String? notasAdicionais,
  }) async {
    await _refreshSessionIfNeeded();
    final response = await _supabase.functions.invoke(
      'gerar-treino',
      body: {
        'acao': 'criar_plano_fase1',
        'email_utilizador': emailUtilizador,
        'diretrizes_plano': {
          'objetivo': objetivoGeral,
          'data_inicio': dataInicio,
          'data_fim': dataFim,
          'competicoes': competicoes,
          'notas': notasAdicionais ?? '',
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
      },
    );
    if (response.status != 200) {
      throw Exception('Próximo Meso Fase 1 falhou: ${response.status} - ${response.data}');
    }
    return AIWorkoutResponse.fromJson(response.data as Map<String, dynamic>);
  }

  // =========================================================
  // SEMANA: Gera exercícios de UMA semana
  // Chamada tantas vezes quantas forem as semanas do mesociclo
  // =========================================================
  Future<List<ExercicioDetalhado>> gerarExerciciosSemana({
    required String emailUtilizador,
    required List<Map<String, dynamic>> diasSemana, // apenas dias de TREINO desta semana
    required Map<String, dynamic> mesoContext,
    // mesoContext: { nome, objetivo, dataInicio, dataFim, semanaNum, totalSemanas, focoSemana, sessionsPerDay, whereTrain }
  }) async {
    await _refreshSessionIfNeeded();
    final response = await _supabase.functions.invoke(
      'gerar-treino',
      body: {
        'acao': 'gerar_exercicios_semana',
        'email_utilizador': emailUtilizador,
        'dias_semana': diasSemana,
        'meso_context': mesoContext,
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
  // Salvar exercícios na base de dados
  // =========================================================
  Future<void> salvarExerciciosGerados(
    List<ExercicioDetalhado> exercicios,
    String emailUtilizador, {
    String? planId,
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