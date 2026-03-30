import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/controllers/workout_controller.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class CreatePlanScreen extends StatefulWidget {
  const CreatePlanScreen({super.key});

  @override
  State<CreatePlanScreen> createState() => _CreatePlanScreenState();
}

class _CreatePlanScreenState extends State<CreatePlanScreen> {
  final _formKey = GlobalKey<FormState>();
  DateTime? _startDate;
  DateTime? _endDate;
  final _objetivoController = TextEditingController();
  final _notesController = TextEditingController();
  final List<Map<String, dynamic>> _competitions = [];

  @override
  void dispose() {
    _objetivoController.dispose();
    _notesController.dispose();
    for (var comp in _competitions) {
      comp['nameController'].dispose();
    }
    super.dispose();
  }

  void _addCompetition() {
    setState(() {
      _competitions.add({
        'nameController': TextEditingController(),
        'date': null,
      });
    });
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryTeal,
              onPrimary: Colors.black,
              surface: AppTheme.cardColor,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _selectCompetitionDate(int index) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryTeal,
              onPrimary: Colors.black,
              surface: AppTheme.cardColor,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _competitions[index]['date'] = picked;
      });
    }
  }

  Future<void> _savePlan() async {
    if (!_formKey.currentState!.validate() || _startDate == null) {
      if (_startDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Start date is required')),
        );
      }
      return;
    }

    final controller = context.read<WorkoutController>();

    final List<String> competicoesFormatadas = _competitions
        .map((comp) => comp['nameController'].text as String)
        .where((name) => name.isNotEmpty)
        .toList();

    final startDateFormatted = DateFormat('yyyy-MM-dd').format(_startDate!);
    final endDateFormatted = _endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : '';

    await controller.criarNovoPlano(
      emailUtilizador: 'samuelhsm@gmail.com', // Mocked as requested
      objetivoGeral: _objetivoController.text,
      dataInicio: startDateFormatted,
      dataFim: endDateFormatted,
      competicoes: competicoesFormatadas,
      notasAdicionais: _notesController.text,
    );

    if (mounted) {
      if (controller.state == WorkoutState.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(controller.errorMessage),
            backgroundColor: Colors.redAccent,
          ),
        );
      } else if (controller.state == WorkoutState.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Plano gerado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Create a New Plan'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Objetivo do Macrociclo *',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _objetivoController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Ex: Ganho de força e condicionamento focado no Open...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  fillColor: AppTheme.cardColor,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                validator: (value) => value == null || value.isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 20),
              _buildDatePicker('Start date *', _startDate, () => _selectDate(context, true), true),
              const SizedBox(height: 20),
              _buildDatePicker('End date', _endDate, () => _selectDate(context, false), false),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Competitions',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: AppTheme.primaryTeal, size: 30),
                    onPressed: _addCompetition,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ..._competitions.asMap().entries.map((entry) => _buildCompetitionItem(entry.key)).toList(),
              const SizedBox(height: 32),
              const Text(
                'Notes',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                maxLines: 5,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Add some details about your plan...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  fillColor: AppTheme.cardColor,
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              Consumer<WorkoutController>(
                builder: (context, controller, child) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (controller.isLoading && controller.loadingMessage.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: Text(
                            controller.loadingMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppTheme.primaryTeal, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryTeal,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: controller.isLoading ? null : _savePlan,
                        child: controller.isLoading
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : const Text(
                                '3, 2, 1... GO!',
                                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDatePicker(String label, DateTime? date, VoidCallback onTap, bool isRequired) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  date == null ? 'Select date' : DateFormat('dd/MM/yyyy').format(date),
                  style: TextStyle(color: date == null ? Colors.white.withOpacity(0.3) : Colors.white),
                ),
                const Icon(Icons.calendar_today, color: AppTheme.primaryTeal, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompetitionItem(int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _competitions[index]['nameController'],
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Competition Name',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                    isDense: true,
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                onPressed: () {
                  setState(() {
                    _competitions[index]['nameController'].dispose();
                    _competitions.removeAt(index);
                  });
                },
              ),
            ],
          ),
          const Divider(color: Colors.white10),
          InkWell(
            onTap: () => _selectCompetitionDate(index),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _competitions[index]['date'] == null
                      ? 'Select Competition Date'
                      : DateFormat('dd/MM/yyyy').format(_competitions[index]['date']),
                  style: TextStyle(
                    color: _competitions[index]['date'] == null ? Colors.white.withOpacity(0.3) : Colors.white,
                    fontSize: 14,
                  ),
                ),
                const Icon(Icons.event, color: AppTheme.primaryTeal, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
