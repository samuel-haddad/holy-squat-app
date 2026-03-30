// lib/controllers/workout_controller.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/ai_workout_response.dart';
import '../repositories/workout_repository.dart';
import '../services/supabase_service.dart';

// Criamos um Enum para representar exatamente em que fase o ecrã está
enum WorkoutState { initial, loading, success, error }

class WorkoutController extends ChangeNotifier {
  final WorkoutRepository _repository;

  // Variáveis de Estado (O que a UI vai observar)
  WorkoutState _state = WorkoutState.initial;
  String _errorMessage = '';
  String _loadingMessage = '';
  AIWorkoutResponse? _planoGerado;

  // Getters para a UI aceder aos dados com segurança
  WorkoutState get state => _state;
  bool get isLoading => _state == WorkoutState.loading;
  String get errorMessage => _errorMessage;
  String get loadingMessage => _loadingMessage;
  AIWorkoutResponse? get planoGerado => _planoGerado;

  // Injeção de dependência do Repositório
  WorkoutController(this._repository);

  /// =========================================================
  /// AÇÃO 1: Botão "Criar Novo Plano"
  /// =========================================================
  Future<void> criarNovoPlano({
    required String emailUtilizador,
    required String objetivoGeral,
    required String dataInicio,
    required String dataFim,
    required List<String> competicoes,
    String? notasAdicionais,
  }) async {
    _state = WorkoutState.loading;
    _loadingMessage = 'Analisando perfil e estruturando 1ª semana...';
    notifyListeners();

    try {
      // 2. Chama o Repositório (que vai à Nuvem)
      final resultado = await _repository.criarPlanoMacro(
        emailUtilizador: emailUtilizador,
        objetivoGeral: objetivoGeral,
        dataInicio: dataInicio,
        dataFim: dataFim,
        competicoes: competicoes,
        notasAdicionais: notasAdicionais,
      );

      // 3. Guarda o treino gerado e avisa a UI que foi um sucesso
      _planoGerado = resultado;
      
      // 4. Salva os metadados do plano gerado na tabela training_plans ANTES 
      // para conseguir o ID.
      final novoPlanoId = await SupabaseService.saveTrainingPlan({
        'start_date': dataInicio,
        'end_date': dataFim.isEmpty ? null : dataFim,
        'notes': notasAdicionais,
        'competitions': competicoes.map((c) => {'name': c, 'date': null}).toList(),
        'actual_plan_summary': jsonEncode(resultado.visaoGeralPlano),
        'workouts_plan_text': jsonEncode(resultado.analiseMacro),
        'workouts_plan_table': resultado.visaoSemanal.map((v) => {
          'day': v.day,
          'workout': v.focoPrincipal,
        }).toList(),
      });

      // --- PROTEÇÃO DE DADOS (Limpeza do Futuro) ---
      // Apagamos todas as sessões futuras (a partir de amanhã) que PERTENCEM A UM PLANO DE IA.
      // E protegemos completamente os treinos manuais!
      final hoje = DateTime.now();
      final hojeFormatado = "${hoje.year}-${hoje.month.toString().padLeft(2, '0')}-${hoje.day.toString().padLeft(2, '0')}";
      
      try {
        // Agora apagamos apenas sessões futuras que foram geradas pela IA (tem plan_id)
        await SupabaseService.client
            .from('sessions')
            .delete()
            .eq('user_email', emailUtilizador)
            .not('plan_id', 'is', null)
            .gt('date', hojeFormatado);
      } catch (e) {
        print('Erro ao limpar treinos futuros da IA: $e');
      }
      // ---------------------------------------------

      // 5. Salva os exercícios gerados passando o ID do plano
      if (resultado.exerciciosDetalhados.isNotEmpty) {
        await _repository.salvarExerciciosGerados(
          resultado.exerciciosDetalhados, 
          emailUtilizador,
          planId: novoPlanoId
        );
      }

      // --- GERAR O RESTO DO MESOCICLO EM BACKGROUND LOOP ---
      int totalSemanasMesociclo = 4; // fallback
      String nomeMesociclo = "Mesociclo Inicial";
      try {
        if (resultado.visaoGeralPlano['blocos'] is List) {
          final blocos = resultado.visaoGeralPlano['blocos'] as List;
          if (blocos.isNotEmpty) {
            totalSemanasMesociclo = (blocos[0]['duracaoSemanas'] as num).toInt();
            nomeMesociclo = blocos[0]['mesociclo'].toString();
          }
        }
      } catch (_) {}

      List currentTable = resultado.visaoSemanal.map((v) => {
        'day': v.day,
        'workout': v.focoPrincipal,
      }).toList();

      for (int week = 2; week <= totalSemanasMesociclo; week++) {
        _loadingMessage = 'Gerando exercícios aprofundados (Semana $week de $totalSemanasMesociclo)...';
        notifyListeners();
        
        try {
          final microResult = await _repository.gerarSemanaMicro(
            emailUtilizador: emailUtilizador,
            planoId: novoPlanoId,
            semanaAlvo: week,
            mesocicloAtual: nomeMesociclo,
            focoSemana: 'Continuação do $nomeMesociclo - Semana $week',
          );

          if (microResult.exerciciosDetalhados.isNotEmpty) {
            await _repository.salvarExerciciosGerados(microResult.exerciciosDetalhados, emailUtilizador, planId: novoPlanoId);
          }

          final newRows = microResult.visaoSemanal.map((v) => {
            'day': v.day,
            'workout': v.focoPrincipal,
          }).toList();
          currentTable.addAll(newRows);

          // Atualiza a tabela parcial para a UI
          await SupabaseService.updateTrainingPlan(novoPlanoId, {
            'workouts_plan_table': currentTable,
          });
        } catch (iteracaoErro) {
          print("Erro ao gerar a semana $week: $iteracaoErro");
          break; // Aborta geração do resto se der erro
        }
      }

      _state = WorkoutState.success;
      _loadingMessage = '';
      
    } catch (e) {
      // 4. Se a internet cair ou a API falhar, captura o erro e mostra ao utilizador
      _errorMessage = 'Falha ao gerar o plano: ${e.toString()}';
      _state = WorkoutState.error;
    } finally {
      // 5. Atualiza o ecrã independentemente de ter dado certo ou errado
      notifyListeners();
    }
  }

  /// =========================================================
  /// AÇÃO 2: Botão "Gerar Próximo Ciclo"
  /// =========================================================
  Future<void> gerarProximoCiclo({
    required String emailUtilizador,
    required String planoId,
    required String actualPlanSummaryJson,
    required List currentWorkoutsTable,
  }) async {
    _state = WorkoutState.loading;
    _loadingMessage = 'Analisando os blocos concluídos...';
    notifyListeners();

    try {
      int semanasGeradasNoPlano = (currentWorkoutsTable.length / 7).floor();
      int currentWeekToGenerate = semanasGeradasNoPlano + 1;

      int weeksPassed = 0;
      Map<String, dynamic>? targetBlock;
      final summary = jsonDecode(actualPlanSummaryJson);
      final blocos = summary['blocos'] as List;
      
      for (var bloco in blocos) {
        int duracao = (bloco['duracaoSemanas'] as num).toInt();
        if (currentWeekToGenerate <= weeksPassed + duracao) {
          targetBlock = bloco;
          break;
        }
        weeksPassed += duracao;
      }

      if (targetBlock == null) {
        throw Exception("Todas as semanas previstas no Plano atual já foram geradas!");
      }

      String mesocicloNome = targetBlock['mesociclo'] ?? 'Novo Ciclo';
      int semanasDesteBloco = (targetBlock['duracaoSemanas'] as num).toInt();
      
      List updatedTable = List.from(currentWorkoutsTable);

      for (int w = currentWeekToGenerate; w <= weeksPassed + semanasDesteBloco; w++) {
        _loadingMessage = 'Modelando Semana $w ($mesocicloNome)...';
        notifyListeners();
        
        final microResult = await _repository.gerarSemanaMicro(
          emailUtilizador: emailUtilizador,
          planoId: planoId,
          semanaAlvo: w,
          mesocicloAtual: mesocicloNome,
          focoSemana: 'Estruturação do $mesocicloNome - Semana $w',
        );

        if (microResult.exerciciosDetalhados.isNotEmpty) {
          await _repository.salvarExerciciosGerados(
            microResult.exerciciosDetalhados, 
            emailUtilizador, 
            planId: planoId
          );
        }

        updatedTable.addAll(microResult.visaoSemanal.map((v) => {
          'day': v.day,
          'workout': v.focoPrincipal,
        }).toList());

        await SupabaseService.updateTrainingPlan(planoId, {
          'workouts_plan_table': updatedTable,
        });
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

  /// Função para limpar o estado caso o utilizador feche o ecrã
  void resetState() {
    _state = WorkoutState.initial;
    _errorMessage = '';
    _loadingMessage = '';
    _planoGerado = null;
    notifyListeners();
  }
}
