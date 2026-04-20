import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/core/app_state.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'package:intl/intl.dart';

class WorkoutResultFormScreen extends StatefulWidget {
  final String title;
  final String wodExerciseId;
  
  const WorkoutResultFormScreen({super.key, required this.title, required this.wodExerciseId});

  @override
  State<WorkoutResultFormScreen> createState() => _WorkoutResultFormScreenState();
}

class _WorkoutResultFormScreenState extends State<WorkoutResultFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late DateTime _workoutDate;
  String _location = 'Academia';
  final _durationController = TextEditingController();
  final _pseController = TextEditingController();
  final _repsController = TextEditingController();
  final _weightController = TextEditingController();
  String _weightUnit = 'kg';
  final _cardioResultController = TextEditingController();
  String _cardioUnit = 'km';
  final _annotationsController = TextEditingController();
  
  bool _isLoading = false;
  bool _isFetching = true;

  @override
  void initState() {
    super.initState();
    _workoutDate = AppState.selectedWodDate.value;
    _loadExistingResult();
  }

  Future<void> _loadExistingResult() async {
    try {
      final data = await SupabaseService.getWorkoutResult(widget.wodExerciseId);
      if (data != null && mounted) {
        setState(() {
          if (data['workout_date'] != null) {
            _workoutDate = DateTime.tryParse(data['workout_date']) ?? _workoutDate;
          }
          if (data['location'] != null) _location = data['location'];
          if (data['duration_done'] != null) _durationController.text = data['duration_done'].toString();
          if (data['pse'] != null) _pseController.text = data['pse'].toString();
          if (data['reps_done'] != null) _repsController.text = data['reps_done'].toString();
          if (data['weight'] != null) _weightController.text = data['weight'].toString();
          if (data['weight_unit'] != null) _weightUnit = data['weight_unit'];
          if (data['cardio_result'] != null) _cardioResultController.text = data['cardio_result'].toString();
          if (data['cardio_unit'] != null) _cardioUnit = data['cardio_unit'];
          if (data['annotations'] != null) _annotationsController.text = data['annotations'];
        });
      }
    } catch (e) {
      debugPrint('Error loading existing result: $e');
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  @override
  void dispose() {
    _durationController.dispose();
    _pseController.dispose();
    _repsController.dispose();
    _weightController.dispose();
    _cardioResultController.dispose();
    _annotationsController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _workoutDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2050),
    );
    if (picked != null) {
      setState(() => _workoutDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        centerTitle: true,
        leading: const SizedBox.shrink(),
        actions: [
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ]
      ),
      body: _isFetching 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
        : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLabel('workout date', required: true),
              GestureDetector(
                onTap: _selectDate,
                child: Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.grey, size: 20),
                      const SizedBox(width: 12),
                      Text(DateFormat('dd/MM/yyyy').format(_workoutDate), style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              _buildLabel('exercise'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(widget.title, style: const TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 16),
              
              _buildLabel('location'),
              Wrap(
                spacing: 8,
                children: ['Academia', 'Box', 'Casa'].map((loc) {
                  final isSelected = _location == loc;
                  return ChoiceChip(
                    label: Text(loc),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setState(() => _location = loc);
                    },
                    backgroundColor: Colors.transparent,
                    selectedColor: Colors.transparent,
                    labelStyle: TextStyle(color: isSelected ? AppTheme.primaryTeal : Colors.white),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: isSelected ? AppTheme.primaryTeal : Colors.grey.withOpacity(0.5)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              
              _buildLabel('duration'),
              _buildTextInput(_durationController),
              const SizedBox(height: 16),
              
              _buildLabel('PSE'),
              _buildTextInput(_pseController),
              const SizedBox(height: 16),
              
              _buildLabel('reps'),
              _buildTextInput(_repsController),
              const SizedBox(height: 16),
              
              _buildLabel('weight'),
              _buildTextInput(_weightController, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 16),
              
              _buildLabel('weight_unit'),
              Wrap(
                spacing: 8,
                children: ['lb', 'kg'].map((unit) {
                  final isSelected = _weightUnit == unit;
                  return ChoiceChip(
                    label: Text(unit),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setState(() => _weightUnit = unit);
                    },
                    backgroundColor: Colors.transparent,
                    selectedColor: Colors.transparent,
                    labelStyle: TextStyle(color: isSelected ? AppTheme.primaryTeal : Colors.white),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: isSelected ? AppTheme.primaryTeal : Colors.grey.withOpacity(0.5)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              
              _buildLabel('cardio_result'),
              _buildTextInput(_cardioResultController, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 16),
              
              _buildLabel('cardio_unit'),
              Wrap(
                spacing: 8,
                children: ['km', 'miles', 'cal'].map((unit) {
                  final isSelected = _cardioUnit == unit;
                  return ChoiceChip(
                    label: Text(unit),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setState(() => _cardioUnit = unit);
                    },
                    backgroundColor: Colors.transparent,
                    selectedColor: Colors.transparent,
                    labelStyle: TextStyle(color: isSelected ? AppTheme.primaryTeal : Colors.white),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: isSelected ? AppTheme.primaryTeal : Colors.grey.withOpacity(0.5)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              
              _buildLabel('annotations'),
              _buildTextInput(_annotationsController, maxLines: 3),
              const SizedBox(height: 32),
              
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.grey),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar', style: TextStyle(color: Colors.white, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryTeal,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isLoading ? null : () async {
                        setState(() => _isLoading = true);
                        try {
                          await SupabaseService.saveWorkoutResult(
                            wodExerciseId: widget.wodExerciseId, 
                            workoutDate: _workoutDate,
                            location: _location,
                            duration: _durationController.text.trim(),
                            pse: _pseController.text.trim(),
                            reps: _repsController.text.trim(),
                            weight: double.tryParse(_weightController.text.trim().replaceAll(',', '.')),
                            weightUnit: _weightUnit,
                            cardioResult: double.tryParse(_cardioResultController.text.trim().replaceAll(',', '.')),
                            cardioUnit: _cardioUnit,
                            annotations: _annotationsController.text.trim(),
                          );
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                           if (context.mounted) {
                             ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                           }
                        } finally {
                          if (mounted) setState(() => _isLoading = false);
                        }
                      },
                      child: _isLoading 
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2)) 
                        : const Text('Enviar', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          if (required) Text('Necessário', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTextInput(TextEditingController controller, {int maxLines = 1, TextInputType keyboardType = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.transparent),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AppTheme.primaryTeal),
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: AppTheme.cardColor,
      ),
    );
  }
}
