import 'package:flutter/material.dart';
import 'package:holy_squat_app/widgets/theme_toggle_button.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'package:intl/intl.dart';

class PrFormScreen extends StatefulWidget {
  final String? exerciseName;
  final Map<String, dynamic>? existingPr;
  const PrFormScreen({super.key, this.exerciseName, this.existingPr});

  @override
  State<PrFormScreen> createState() => _PrFormScreenState();
}

class _PrFormScreenState extends State<PrFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final _exerciseController = TextEditingController();
  final _prController = TextEditingController();
  final _unitController = TextEditingController();
  final _dateController = TextEditingController();
  bool _isLoading = false;
  List<String> _exerciseSuggestions = [];

  @override
  void initState() {
    super.initState();
    _loadExerciseSuggestions();
    _exerciseController.text = widget.exerciseName ?? '';
    if (widget.existingPr != null) {
      if (widget.exerciseName == null) {
        _exerciseController.text = widget.existingPr!['exercise']?.toString() ?? '';
      }
      _prController.text = widget.existingPr!['pr']?.toString() ?? '';
      _unitController.text = widget.existingPr!['pr_unit']?.toString() ?? 'kg';
      
      String d = widget.existingPr!['date'] ?? '';
      try {
        final dt = DateTime.parse(d);
        _dateController.text = DateFormat('dd/MM/yyyy').format(dt);
      } catch (_) {
        _dateController.text = d;
      }
    } else {
      _unitController.text = 'kg';
      _dateController.text = DateFormat('dd/MM/yyyy').format(DateTime.now());
    }
  }

  Future<void> _loadExerciseSuggestions() async {
    final suggestions = await SupabaseService.getUniqueExercises();
    if (mounted) {
      setState(() {
        _exerciseSuggestions = suggestions;
      });
    }
  }

  @override
  void dispose() {
    _exerciseController.dispose();
    _prController.dispose();
    _unitController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.existingPr != null ? 'Edit PR' : 'Add PR';
    return Scaffold(
      appBar: AppBar(
        actions: const [ThemeToggleButton()],
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.exerciseName != null && widget.exerciseName!.isNotEmpty)
                Text(
                  widget.exerciseName!,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                )
              else
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: _exerciseController.text),
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return _exerciseSuggestions;
                    }
                    return _exerciseSuggestions.where((String option) {
                      return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                    });
                  },
                  onSelected: (String selection) {
                    _exerciseController.text = selection;
                  },
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    // Sincronizar o valor do campo de texto com o controlador principal
                    if (controller.text != _exerciseController.text && _exerciseController.text.isNotEmpty && controller.text.isEmpty) {
                       controller.text = _exerciseController.text;
                    }
                    
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      style: const TextStyle(color: Colors.white),
                      onChanged: (val) => _exerciseController.text = val,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Required';
                        return null;
                      },
                      decoration: InputDecoration(
                        labelText: 'Exercise Name',
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
                    );
                  },
                ),
              const SizedBox(height: 32),
              _buildTextField('New Record (PR)', _prController, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 16),
              
              DropdownButtonFormField<String>(
                value: _unitController.text.isEmpty ? 'kg' : _unitController.text,
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
                items: ['kg', 'lb'].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _unitController.text = newValue;
                    });
                  }
                },
              ),

              const SizedBox(height: 16),
              
              InkWell(
                onTap: () async {
                  DateTime initDate = DateTime.now();
                  try {
                    final parts = _dateController.text.trim().split('/');
                    if (parts.length == 3) {
                       initDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
                    }
                  } catch(_) {}

                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    setState(() {
                      _dateController.text = DateFormat('dd/MM/yyyy').format(picked);
                    });
                  }
                },
                child: AbsorbPointer(
                  child: _buildTextField('Date Achieved (dd/MM/yyyy)', _dateController),
                ),
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
                   onPressed: _isLoading ? null : () async {
                     if (_formKey.currentState!.validate()) {
                       setState(() => _isLoading = true);
                       try {
                         final prVal = double.tryParse(_prController.text.trim().replaceAll(',', '.')) ?? 0.0;
                         final unit = _unitController.text.trim();
                         
                         // parse back to YYYY-MM-DD
                         String isoDate = DateTime.now().toIso8601String().split('T')[0];
                         try {
                           final parts = _dateController.text.trim().split('/');
                           if (parts.length == 3) {
                             isoDate = '${parts[2]}-${parts[1]}-${parts[0]}';
                           }
                         } catch(_) {}
                         
                         if (widget.existingPr != null) {
                           await SupabaseService.updatePrLog(widget.existingPr!['id'], prVal, unit, isoDate);
                         } else {
                           await SupabaseService.insertPrLog(_exerciseController.text.trim(), prVal, unit, isoDate);
                         }
                         if (context.mounted) Navigator.pop(context, true);
                       } catch (e) {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                       } finally {
                         if (mounted) setState(() => _isLoading = false);
                       }
                     }
                   },
                   child: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text('Submit PR', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                 ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {TextInputType? keyboardType}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      validator: (val) {
        if (val == null || val.trim().isEmpty) return 'Required';
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
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
    );
  }
}
