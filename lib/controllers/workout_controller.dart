import 'package:flutter/material.dart';
import 'package:holy_squat_app/repositories/workout_repository.dart';
import 'package:holy_squat_app/models/training_session.dart';

enum WorkoutState { idle, loading, success, error }

class WorkoutController extends ChangeNotifier {
  final WorkoutRepository _repository = WorkoutRepository();
  
  WorkoutState _state = WorkoutState.idle;
  WorkoutState get state => _state;
  
  String _errorMessage = '';
  String get errorMessage => _errorMessage;
  
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  String _loadingMessage = '';
  String get loadingMessage => _loadingMessage;

  void _setLoading(bool loading, {String message = ''}) {
    _isLoading = loading;
    _loadingMessage = message;
    if (loading) _state = WorkoutState.loading;
    notifyListeners();
  }

  void _setState(WorkoutState state) {
    _state = state;
    notifyListeners();
  }

  Future<void> criarNovoPlano({
    required String emailUtilizador,
    required String objetivoGeral,
    required String dataInicio,
    required String dataFim,
    required List<Map<String, dynamic>> competicoes,
    required List<Map<String, dynamic>> ferias,
    required List<String> lesoes,
    required String notasAdicionais,
    required int? aiCoachId,
    required String aiCoachName,
    required List<TrainingSession> trainingSessions,
  }) async {
    _setLoading(true, message: 'Iniciando geração do plano...');
    _errorMessage = '';

    try {
      // 1. Gerar análise histórica
      _setLoading(true, message: 'Analisando histórico esportivo...');
      final analise = await _repository.gerarAnaliseHistorica(
        emailUtilizador: emailUtilizador,
        aiCoachName: aiCoachName,
      );

      // 2. Criar diretrizes do plano
      _setLoading(true, message: 'Projetando macrociclo...');
      final diretrizes = {
        'objetivo': objetivoGeral,
        'data_inicio': dataInicio,
        'data_fim': dataFim,
        'competicoes': competicoes,
        'ferias': ferias,
        'lesoes': lesoes,
        'notas': notasAdicionais,
      };

      final plano = await _repository.criarPlano(
        emailUtilizador: emailUtilizador,
        analiseHistorica: analise,
        diretrizesPlano: diretrizes,
        aiCoachName: aiCoachName,
      );

      // 3. O plano foi criado. Dependendo da lógica do backend,
      // ele pode já ter gerado os exercícios ou precisar de um job.
      // Assumindo sucesso após Action 2 conforme fluxo básico.
      
      _setState(WorkoutState.success);
    } catch (e) {
      debugPrint('Error in criarNovoPlano: $e');
      _errorMessage = e.toString();
      _setState(WorkoutState.error);
    } finally {
      _setLoading(false);
    }
  }
}
