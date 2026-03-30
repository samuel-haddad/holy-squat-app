// lib/repositories/workout_repository.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ai_workout_response.dart';

class WorkoutRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// =========================================================
  /// AÇÃO 1: Criar um Plano Macro/Meso do Zero
  /// =========================================================
  Future<AIWorkoutResponse> criarPlanoMacro({
    required String emailUtilizador,
    required String objetivoGeral, // O que o atleta escreveu no app
    required String dataInicio,    // Formato 'YYYY-MM-DD'
    required String dataFim,       // Formato 'YYYY-MM-DD'
    required List<String> competicoes,
    String? notasAdicionais,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'gerar-treino',
        body: {
          'acao': 'criar_plano_macro',
          'email_utilizador': emailUtilizador,
          'diretrizes_plano': {
            'objetivo': objetivoGeral,
            'data_inicio': dataInicio,
            'data_fim': dataFim,
            'competicoes': competicoes,
            'notas': notasAdicionais ?? '',
          }
        },
      );

      if (response.status == 200) {
        final jsonData = response.data as Map<String, dynamic>;
        return AIWorkoutResponse.fromJson(jsonData);
      } else {
        throw Exception('Erro na API ao criar plano: ${response.status} - ${response.data}');
      }
    } catch (e) {
      print('Erro no Repositório (Criar Plano): $e');
      rethrow;
    }
  }

  /// =========================================================
  /// AÇÃO 2: Gerar novas semanas (Microciclos) de um plano atual
  /// =========================================================
  Future<AIWorkoutResponse> gerarSemanaMicro({
    required String emailUtilizador,
    required String planoId, // O ID do plano na tabela 'training_plans'
    required int semanaAlvo, // Ex: 2 (Semana 2 do mesociclo)
    required String mesocicloAtual,
    required String focoSemana,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'gerar-treino',
        body: {
          'acao': 'gerar_semana_micro',
          'email_utilizador': emailUtilizador,
          'plano_id': planoId,
          'semana_alvo': semanaAlvo,
          'mesociclo_atual': mesocicloAtual,
          'foco_semana': focoSemana,
        },
      );

      if (response.status == 200) {
        final jsonData = response.data as Map<String, dynamic>;
        return AIWorkoutResponse.fromJson(jsonData);
      } else {
        throw Exception('Erro na API ao gerar semana: ${response.status} - ${response.data}');
      }
    } catch (e) {
      print('Erro no Repositório (Gerar Semana): $e');
      rethrow;
    }
  }

  /// =========================================================
  /// FUNÇÃO AUXILIAR: Guardar na Base de Dados
  /// =========================================================
  Future<void> salvarExerciciosGerados(List<ExercicioDetalhado> exercicios, String emailUtilizador, {String? planId}) async {
    try {
      // Usamos o método toJson() e injetamos o email para o RLS do Supabase
      final Map<String, Map<String, dynamic>> uniqueSessions = {};

      final List<Map<String, dynamic>> recordsToInsert = exercicios.map((ex) {
        final json = ex.toJson();
        json['user_email'] = emailUtilizador;
        
        // --- PROTEÇÃO CONTRA ALUCINAÇÃO DA IA ---
        final validIcons = [
          'Acessório', 'Acessórios/Blindagem', 'Calistenia', 'Cardio', 'Cardio-Mobilidade',
          'Core Strength', 'Core/Prep', 'Crossfit', 'Descanso', 'Endurance', 'Força/Heavy',
          'Força/Metcon', 'Força/Skill', 'Full Body Pump', 'Full Session', 'Ginástica/Metcon',
          'Hipertrofia/Blindagem', 'LPO', 'LPO/Força/Metcon', 'LPO/Metcon', 'LPO/Potência',
          'Mobilidade', 'Mobilidade Flow', 'Mobilidade-Cardio', 'Mobilidade-Core',
          'Mobilidade-Inferiores', 'Mobilidade/Prep', 'Multi', 'Musculação', 'Musculação-Cardio',
          'Musculação-Funcional', 'Musculação/Força', 'Natação', 'Prehab/Força',
          'Prehab/Mobilidade', 'Recuperação Ativa', 'Reintrodução/FBB', 'Skill', 'Skill/Metcon'
        ];
        var safeSessionType = ex.sessionType.trim();
        if (!validIcons.contains(safeSessionType)) {
          print('⚠️ IA retornou um tipo inválido ($safeSessionType). Usando fallback "Crossfit"');
          safeSessionType = 'Crossfit'; // O mais genérico
        }
        json['session_type'] = safeSessionType;
        // ----------------------------------------

        // Geramos as chaves obrigatórias exigidas pelo esquema do banco
        final dateStr = ex.date;
        final sessionNum = ex.session;
        final workoutIdx = ex.workoutIdx;
        
        // date_session_sessiontype_key é a chave de ligação com a tabela sessions
        final sessionKey = '${dateStr}_${sessionNum}_$safeSessionType';
        json['date_session_sessiontype_key'] = sessionKey;

        // Registramos a sessão para garantir que ela exista na tabela 'sessions'
        if (!uniqueSessions.containsKey(sessionKey)) {
          uniqueSessions[sessionKey] = {
            'date_session_sessiontype_key': sessionKey,
            'date': dateStr,
            'session': sessionNum,
            'session_type': safeSessionType,
            'user_email': emailUtilizador,
            if (planId != null) 'plan_id': planId,
          };
        }

        // wod_exercise_id é a Primary Key e precisa ser única e não-nula
        json['wod_exercise_id'] = '${dateStr}_${sessionNum}_${workoutIdx}_${DateTime.now().millisecondsSinceEpoch % 10000}';

        return json;
      }).toList();

      // Upsert das sessões antes de inserir os exercícios, para evitar violação de Foreign Key
      if (uniqueSessions.isNotEmpty) {
        await _supabase.from('sessions').upsert(
          uniqueSessions.values.toList(),
          onConflict: 'date_session_sessiontype_key',
        );
      }

      await _supabase.from('workouts').insert(recordsToInsert);
    } catch (e) {
      print('Erro ao salvar os exercícios no banco: $e');
      rethrow;
    }
  }
}