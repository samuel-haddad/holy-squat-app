/// Represents a single training session slot configured by the athlete.
class TrainingSession {
  final String? id;
  int sessionNumber;
  List<String> locations;
  int durationMinutes;
  List<String> schedule;
  String timeOfDay;
  String notes;

  TrainingSession({
    this.id,
    required this.sessionNumber,
    List<String>? locations,
    this.durationMinutes = 60,
    List<String>? schedule,
    this.timeOfDay = 'morning',
    this.notes = '',
  })  : this.locations = List<String>.from(locations ?? []),
        this.schedule = List<String>.from(schedule ?? []);

  factory TrainingSession.fromJson(Map<String, dynamic> json) {
    return TrainingSession(
      id: json['id'] as String?,
      sessionNumber: json['session_number'] as int? ?? 1,
      locations: List<String>.from(json['locations'] ?? []),
      durationMinutes: json['duration_minutes'] as int? ?? 60,
      schedule: List<String>.from(json['schedule'] ?? []),
      timeOfDay: json['time_of_day'] as String? ?? 'morning',
      notes: json['notes'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'session_number': sessionNumber,
      'locations': locations,
      'duration_minutes': durationMinutes,
      'schedule': schedule,
      'time_of_day': timeOfDay,
      'notes': notes,
    };
  }

  /// Human-readable summary for display in read-only views.
  String get summary {
    final loc = locations.isNotEmpty ? locations.join(', ') : '-';
    final sched = schedule.isNotEmpty ? schedule.join(', ') : '-';
    return 'Session $sessionNumber: $loc | ${durationMinutes}min | $sched | $timeOfDay';
  }

  TrainingSession copyWith({
    String? id,
    int? sessionNumber,
    List<String>? locations,
    int? durationMinutes,
    List<String>? schedule,
    String? timeOfDay,
    String? notes,
  }) {
    return TrainingSession(
      id: id ?? this.id,
      sessionNumber: sessionNumber ?? this.sessionNumber,
      locations: locations ?? List.from(this.locations),
      durationMinutes: durationMinutes ?? this.durationMinutes,
      schedule: schedule ?? List.from(this.schedule),
      timeOfDay: timeOfDay ?? this.timeOfDay,
      notes: notes ?? this.notes,
    );
  }
}
