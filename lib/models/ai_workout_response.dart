class ExercicioDetalhado {
  final String date;
  final int week;
  final String mesocycle;
  final String day;
  final int session;
  final String sessionType;
  final int workoutIdx;
  final String exercise;
  final String exerciseTitle;
  final String exerciseGroup;
  final String exerciseType;
  final int sets;
  final String details;
  final num timeExercise;
  final String exUnit;
  final num rest;
  final String restUnit;
  final num totalTime;
  final String location;
  final String stage;
  final String adaptacaoLesao;

  ExercicioDetalhado({
    required this.date,
    required this.week,
    required this.mesocycle,
    required this.day,
    required this.session,
    required this.sessionType,
    required this.workoutIdx,
    required this.exercise,
    required this.exerciseTitle,
    required this.exerciseGroup,
    required this.exerciseType,
    required this.sets,
    required this.details,
    required this.timeExercise,
    required this.exUnit,
    required this.rest,
    required this.restUnit,
    required this.totalTime,
    required this.location,
    required this.stage,
    required this.adaptacaoLesao,
  });

  factory ExercicioDetalhado.fromJson(Map<String, dynamic> json) {
    return ExercicioDetalhado(
      date: json['date'] ?? '',
      week: json['week'] ?? 0,
      mesocycle: json['mesocycle'] ?? '',
      day: json['day'] ?? '',
      session: json['session'] ?? 1,
      sessionType: json['session_type'] ?? '',
      workoutIdx: json['workout_idx'] ?? 1,
      exercise: json['exercise'] ?? '',
      exerciseTitle: json['exercise_title'] ?? '',
      exerciseGroup: json['exercise_group'] ?? '',
      exerciseType: json['exercise_type'] ?? '',
      sets: json['sets'] ?? 0,
      details: json['details'] ?? '',
      timeExercise: json['time_exercise'] ?? 0,
      exUnit: json['ex_unit'] ?? 'min',
      rest: json['rest'] ?? 0,
      restUnit: json['rest_unit'] ?? 'seg',
      totalTime: json['total_time'] ?? 0,
      location: json['location'] ?? 'Academia',
      stage: json['stage'] ?? 'workout',
      adaptacaoLesao: json['adaptacaoLesao'] ?? '',
    );
  }
  
  // Optional, but very useful: A method to transform the object back into JSON
  // for when we INSERT into the Supabase database.
  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'week': week,
      'mesocycle': mesocycle,
      'day': day,
      'session': session,
      'session_type': sessionType,
      'workout_idx': workoutIdx,
      'exercise': exercise,
      'exercise_title': exerciseTitle,
      'exercise_group': exerciseGroup,
      'exercise_type': exerciseType,
      'sets': sets,
      'details': details,
      'time_exercise': timeExercise,
      'ex_unit': exUnit,
      'rest': rest,
      'rest_unit': restUnit,
      'total_time': totalTime,
      'location': location,
      'stage': stage,
      'adaptacaoLesao': adaptacaoLesao,
    };
  }
}

class VisaoSemanal {
  final String date;
  final String day;
  final String sessionType;
  final String focoPrincipal;
  final bool isDescansoAtivo;
  final String mesocycle; // NEW: Name of the mesocycle
  final int week;        // NEW: Week number

  VisaoSemanal({
    required this.date,
    required this.day,
    required this.sessionType,
    required this.focoPrincipal,
    required this.isDescansoAtivo,
    required this.mesocycle,
    required this.week,
  });

  factory VisaoSemanal.fromJson(Map<String, dynamic> json) {
    return VisaoSemanal(
      date: json['date'] ?? '',
      day: json['day'] ?? '',
      sessionType: json['session_type'] ?? '',
      focoPrincipal: json['focoPrincipal'] ?? '',
      isDescansoAtivo: json['isDescansoAtivo'] ?? false,
      mesocycle: json['mesocycle'] ?? '',
      week: json['week'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'day': day,
      'session_type': sessionType,
      'focoPrincipal': focoPrincipal,
      'isDescansoAtivo': isDescansoAtivo,
      'mesocycle': mesocycle,
      'week': week,
    };
  }
}

// The main class that encapsulates the entire AI response
class AIWorkoutResponse {
  final Map<String, dynamic>? analiseMacro;
  final Map<String, dynamic>? analiseMesocicloAnterior;
  final Map<String, dynamic>? analiseCicloAnterior; // NEW: Action 3 output
  final List<Map<String, dynamic>>? visaoGeralCiclo; // NEW: Action 3 weekly overview per meso
  final Map<String, dynamic> visaoGeralPlano;
  final List<VisaoSemanal> visaoSemanal;
  final List<ExercicioDetalhado> exerciciosDetalhados;

  AIWorkoutResponse({
    this.analiseMacro,
    this.analiseMesocicloAnterior,
    this.analiseCicloAnterior,
    this.visaoGeralCiclo,
    required this.visaoGeralPlano,
    required this.visaoSemanal,
    required this.exerciciosDetalhados,
  });

  factory AIWorkoutResponse.fromJson(Map<String, dynamic> json) {
    return AIWorkoutResponse(
      analiseMacro: json['analiseMacro'],
      analiseMesocicloAnterior: json['analiseMesocicloAnterior'],
      analiseCicloAnterior: json['analiseCicloAnterior'],
      visaoGeralCiclo: (json['visaoGeralCiclo'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
      visaoGeralPlano: json['visaoGeralPlano'] ?? {},
      visaoSemanal: (json['visaoSemanal'] as List<dynamic>?)
              ?.map((e) => VisaoSemanal.fromJson(e))
              .toList() ??
          [],
      exerciciosDetalhados: (json['exerciciosDetalhados'] as List<dynamic>?)
              ?.map((e) => ExercicioDetalhado.fromJson(e))
              .toList() ??
          [],
    );
  }

  // Domino effect! It calls the toJson() of the child lists.
  Map<String, dynamic> toJson() {
    return {
      if (analiseMacro != null) 'analiseMacro': analiseMacro,
      if (analiseMesocicloAnterior != null) 'analiseMesocicloAnterior': analiseMesocicloAnterior,
      if (analiseCicloAnterior != null) 'analiseCicloAnterior': analiseCicloAnterior,
      if (visaoGeralCiclo != null) 'visaoGeralCiclo': visaoGeralCiclo,
      'visaoGeralPlano': visaoGeralPlano,
      'visaoSemanal': visaoSemanal.map((e) => e.toJson()).toList(),
      'exerciciosDetalhados': exerciciosDetalhados.map((e) => e.toJson()).toList(),
    };
  }
}