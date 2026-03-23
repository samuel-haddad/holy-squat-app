import 'package:flutter/material.dart';
import 'package:holy_squat_app/widgets/theme_toggle_button.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/services/supabase_service.dart';

class BenchmarkFormScreen extends StatefulWidget {
  final String exerciseName;
  final String initialUnit;
  const BenchmarkFormScreen({super.key, required this.exerciseName, required this.initialUnit});

  @override
  State<BenchmarkFormScreen> createState() => _BenchmarkFormScreenState();
}

class _BenchmarkFormScreenState extends State<BenchmarkFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _resultController = TextEditingController();
  final _dateController = TextEditingController();
  late String _selectedUnit;
  bool _isLoading = true;
  bool _isSaving = false;
  
  final List<String> _unitOptions = ['cal', 'lb', 'kg', 'km', 'reps', 'time'];

  @override
  void initState() {
    super.initState();
    _selectedUnit = _unitOptions.contains(widget.initialUnit) ? widget.initialUnit : 'reps';
    _loadBenchmark();
  }

  Future<void> _loadBenchmark() async {
    try {
      final log = await SupabaseService.getBenchmarkLog(widget.exerciseName);
      if (log != null) {
        if (log['result'] != null) {
          _resultController.text = log['result'].toString().replaceAll('.0', '');
        }
        if (log['date'] != null) {
          _dateController.text = log['date'].toString();
        }
      }
    } catch (e) {
      // ignore
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveBenchmark() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    
    final resultStr = _resultController.text.trim();
    final dateStr = _dateController.text.trim();
    if (resultStr.isEmpty) {
      if (mounted) setState(() => _isSaving = false);
       return;
    }
    
    final resultVal = double.tryParse(resultStr.replaceAll(',', '.'));
    if (resultVal == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Valor numérico inválido', style: TextStyle(color: Colors.white))));
      if (mounted) setState(() => _isSaving = false);
      return;
    }

    try {
      await SupabaseService.upsertBenchmarkLog(widget.exerciseName, resultVal, dateStr.isEmpty ? null : dateStr);
      // We also update the global Unit definition mapped to the Benchmark row
      await SupabaseService.updateBenchmarkUnit(widget.exerciseName, _selectedUnit);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Benchmark salvo com sucesso!', style: TextStyle(color: Colors.white)), backgroundColor: AppTheme.primaryTeal));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red));
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: const [ThemeToggleButton()],
        title: const Text('Edit Benchmark', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.exerciseName,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _resultController,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: 'Result (Record)',
                            labelStyle: const TextStyle(color: AppTheme.secondaryTextColor),
                            enabledBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: AppTheme.cardColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: AppTheme.primaryTeal),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: AppTheme.cardColor,
                          ),
                          validator: (val) => (val == null || val.isEmpty) ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 1,
                        child: DropdownButtonFormField<String>(
                          value: _selectedUnit,
                          dropdownColor: AppTheme.cardColor,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Unit',
                            labelStyle: const TextStyle(color: AppTheme.secondaryTextColor),
                            enabledBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: AppTheme.cardColor),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: AppTheme.primaryTeal),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: AppTheme.cardColor,
                          ),
                          items: _unitOptions.map((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                          onChanged: (newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedUnit = newValue;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _dateController,
                    readOnly: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Data (DD/MM/YYYY)',
                      labelStyle: const TextStyle(color: AppTheme.secondaryTextColor),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppTheme.cardColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: AppTheme.primaryTeal),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      filled: true,
                      fillColor: AppTheme.cardColor,
                      suffixIcon: const Icon(Icons.calendar_today, color: AppTheme.primaryTeal),
                    ),
                    onTap: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() {
                          _dateController.text = "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                        });
                      }
                    },
                    validator: (val) => (val == null || val.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryTeal,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isSaving ? null : _saveBenchmark,
                      child: _isSaving 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : const Text('Save Benchmark', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}
