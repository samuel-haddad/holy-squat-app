// lib/controllers/workout_controller.dart

import 'package:flutter/material.dart';
import '../models/ai_workout_response.dart';
import '../repositories/workout_repository.dart';

// Criamos um Enum para representar exatamente em que fase o ecrã está
enum WorkoutState { initial, loading, success, error }

class WorkoutController extends ChangeNotifier {
  final WorkoutRepository _repository;

  // Variáveis de Estado (O que a UI vai observar)
  WorkoutState _state = WorkoutState.initial;
  String _errorMessage = '';
  AIWorkoutResponse? _planoGerado;

  // Getters para a UI aceder aos dados com segurança
  WorkoutState get state => _state;
  bool get isLoading => _state == WorkoutState.loading;
  String get errorMessage => _errorMessage;
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
    // 1. Avisa a UI para mostrar o ícone de carregamento
    _state = WorkoutState.loading;
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
      
      // Opcional: Já salva os exercícios gerados no banco automaticamente
      if (resultado.exerciciosDetalhados.isNotEmpty) {
        await _repository.salvarExerciciosGerados(resultado.exerciciosDetalhados);
      }

      _state = WorkoutState.success;
      
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
  /// AÇÃO 2: Botão "Gerar Próxima Semana"
  /// =========================================================
  Future<void> gerarProximaSemana({
    required String emailUtilizador,
    required String planoId,
    required int semanaAlvo,
    required String mesocicloAtual,
    required String focoSemana,
  }) async {
    
    _state = WorkoutState.loading;
    notifyListeners();

    try {
      final resultado = await _repository.gerarSemanaMicro(
        emailUtilizador: emailUtilizador,
        planoId: planoId,
        semanaAlvo: semanaAlvo,
        mesocicloAtual: mesocicloAtual,
        focoSemana: focoSemana,
      );

      _planoGerado = resultado;
      
      if (resultado.exerciciosDetalhados.isNotEmpty) {
        await _repository.salvarExerciciosGerados(resultado.exerciciosDetalhados);
      }

      _state = WorkoutState.success;
      
    } catch (e) {
      _errorMessage = 'Falha ao gerar a semana: ${e.toString()}';
      _state = WorkoutState.error;
    } finally {
      notifyListeners();
    }
  }

  /// Função para limpar o estado caso o utilizador feche o ecrã
  void resetState() {
    _state = WorkoutState.initial;
    _errorMessage = '';
    _planoGerado = null;
    notifyListeners();
  }
}