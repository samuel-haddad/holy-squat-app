import 'package:flutter/material.dart';
import 'package:holy_squat_app/models/training_session.dart';
import 'package:holy_squat_app/theme/app_theme.dart';

/// Reusable widget for managing a list of training sessions.
/// Used in Onboarding, Profile Form, and Create Plan screens.
class TrainingSessionsEditor extends StatefulWidget {
  final List<TrainingSession> sessions;
  final ValueChanged<List<TrainingSession>> onChanged;

  const TrainingSessionsEditor({
    super.key,
    required this.sessions,
    required this.onChanged,
  });

  @override
  State<TrainingSessionsEditor> createState() => _TrainingSessionsEditorState();
}

class _TrainingSessionsEditorState extends State<TrainingSessionsEditor> {
  static const List<String> _locationOptions = ['academia', 'box', 'casa', 'corrida de rua'];
  static const List<String> _scheduleOptions = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
  static const List<String> _timeOfDayOptions = ['morning', 'afternoon', 'evening'];

  static const Map<String, IconData> _timeOfDayIcons = {
    'morning': Icons.wb_sunny,
    'afternoon': Icons.wb_twilight,
    'evening': Icons.nightlight_round,
  };

  late List<TrainingSession> _sessions;
  final Map<int, TextEditingController> _durationControllers = {};
  final Map<int, TextEditingController> _notesControllers = {};

  @override
  void initState() {
    super.initState();
    _sessions = widget.sessions.map((s) => s.copyWith()).toList();
    _initControllers();
  }

  @override
  void didUpdateWidget(TrainingSessionsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessions != widget.sessions) {
      _disposeControllers();
      _sessions = widget.sessions.map((s) => s.copyWith()).toList();
      _initControllers();
    }
  }

  void _initControllers() {
    for (int i = 0; i < _sessions.length; i++) {
      _durationControllers[i] = TextEditingController(text: _sessions[i].durationMinutes.toString());
      _notesControllers[i] = TextEditingController(text: _sessions[i].notes);
    }
  }

  void _disposeControllers() {
    for (var c in _durationControllers.values) { c.dispose(); }
    for (var c in _notesControllers.values) { c.dispose(); }
    _durationControllers.clear();
    _notesControllers.clear();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _notifyChanged() {
    widget.onChanged(List.from(_sessions));
  }

  void _addSession() {
    setState(() {
      final nextNumber = _sessions.isEmpty ? 1 : _sessions.last.sessionNumber + 1;
      final session = TrainingSession(sessionNumber: nextNumber);
      _sessions.add(session);
      final idx = _sessions.length - 1;
      _durationControllers[idx] = TextEditingController(text: '60');
      _notesControllers[idx] = TextEditingController();
    });
    _notifyChanged();
  }

  void _removeSession(int index) {
    setState(() {
      _durationControllers[index]?.dispose();
      _notesControllers[index]?.dispose();
      _sessions.removeAt(index);
      // Rebuild controllers map with correct indices
      _durationControllers.clear();
      _notesControllers.clear();
      for (int i = 0; i < _sessions.length; i++) {
        _sessions[i].sessionNumber = i + 1;
        _durationControllers[i] = TextEditingController(text: _sessions[i].durationMinutes.toString());
        _notesControllers[i] = TextEditingController(text: _sessions[i].notes);
      }
    });
    _notifyChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Sessões de Treino',
              style: TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: AppTheme.primaryTeal, size: 30),
              tooltip: 'Adicionar Sessão',
              onPressed: _addSession,
            ),
          ],
        ),
        if (_sessions.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              children: [
                Icon(Icons.event_note, color: Colors.white.withOpacity(0.2), size: 40),
                const SizedBox(height: 8),
                Text(
                  'Nenhuma sessão adicionada ainda.\nToque no + para adicionar sua primeira sessão.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 14),
                ),
              ],
            ),
          ),
        ..._sessions.asMap().entries.map((entry) => _buildSessionCard(entry.key)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _addSession,
            icon: const Icon(Icons.add, color: AppTheme.primaryTeal),
            label: const Text(
              'Adicionar Nova Sessão',
              style: TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.primaryTeal, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionCard(int index) {
    final session = _sessions[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryTeal.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Session number + delete
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryTeal.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Sessão ${session.sessionNumber}',
                      style: const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                onPressed: () => _removeSession(index),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Location chips
          const Text('Local', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _locationOptions.map((loc) {
              final selected = session.locations.contains(loc);
              return FilterChip(
                label: Text(loc, style: TextStyle(fontSize: 12, color: selected ? AppTheme.primaryTeal : Colors.white70)),
                selected: selected,
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      session.locations.add(loc);
                    } else {
                      session.locations.remove(loc);
                    }
                  });
                  _notifyChanged();
                },
                selectedColor: AppTheme.primaryTeal.withOpacity(0.2),
                checkmarkColor: AppTheme.primaryTeal,
                backgroundColor: Colors.white.withOpacity(0.05),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Duration
          Row(
            children: [
              const Text('Duração (min)', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: TextFormField(
                  controller: _durationControllers[index],
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    fillColor: Colors.white.withOpacity(0.05),
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                  onChanged: (val) {
                    session.durationMinutes = int.tryParse(val) ?? 60;
                    _notifyChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Schedule chips
          const Text('Dias da Semana', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: _scheduleOptions.map((day) {
              final selected = session.schedule.contains(day);
              return FilterChip(
                label: Text(day, style: TextStyle(fontSize: 11, color: selected ? AppTheme.primaryTeal : Colors.white70)),
                selected: selected,
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      session.schedule.add(day);
                    } else {
                      session.schedule.remove(day);
                    }
                  });
                  _notifyChanged();
                },
                selectedColor: AppTheme.primaryTeal.withOpacity(0.2),
                checkmarkColor: AppTheme.primaryTeal,
                backgroundColor: Colors.white.withOpacity(0.05),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Time of Day
          const Text('Turno', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            children: _timeOfDayOptions.map((tod) {
              final selected = session.timeOfDay == tod;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(_timeOfDayIcons[tod], size: 16, color: selected ? AppTheme.primaryTeal : Colors.white54),
                  label: Text(tod, style: TextStyle(fontSize: 12, color: selected ? AppTheme.primaryTeal : Colors.white70)),
                  selected: selected,
                  onSelected: (val) {
                    if (val) {
                      setState(() => session.timeOfDay = tod);
                      _notifyChanged();
                    }
                  },
                  selectedColor: AppTheme.primaryTeal.withOpacity(0.2),
                  backgroundColor: Colors.white.withOpacity(0.05),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Notes
          TextFormField(
            controller: _notesControllers[index],
            maxLines: 2,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Escreva aqui as limitações de equipamentos ou preferências de exercícios para esta sessão',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 12),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              fillColor: Colors.white.withOpacity(0.05),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
            onChanged: (val) {
              session.notes = val;
              _notifyChanged();
            },
          ),
        ],
      ),
    );
  }
}
