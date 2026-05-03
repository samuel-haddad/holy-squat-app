import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/services/supabase_service.dart';

class EditPlanDetailScreen extends StatefulWidget {
  final String mode;
  final Map<String, dynamic> group;
  final DateTime startDate;
  final DateTime? endDate;
  final String coach;

  const EditPlanDetailScreen({
    super.key,
    required this.mode,
    required this.group,
    required this.startDate,
    this.endDate,
    required this.coach,
  });

  @override
  State<EditPlanDetailScreen> createState() => _EditPlanDetailScreenState();
}

class _EditPlanDetailScreenState extends State<EditPlanDetailScreen> {
  late Map<String, dynamic> _fields;
  List<Map<String, dynamic>> _icons = [];
  bool _isLoadingIcons = true;
  bool _isSaving = false;

  final TextEditingController _sessionController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final Map<String, TextEditingController> _wodControllers = {};

  @override
  void dispose() {
    _sessionController.dispose();
    _durationController.dispose();
    for (var controller in _wodControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fields = Map.from(widget.group);
    if (widget.mode == 'Sessions') {
      _sessionController.text = _fields['session']?.toString() ?? '1';
      _durationController.text = _fields['duration']?.toString() ?? '60';
      _loadIcons();
    } else {
      _isLoadingIcons = false;
      _initWodControllers();
    }
  }

  void _initWodControllers() {
    final textFields = [
      'sets', 'details', 'time_exercise', 
      'rest', 'total_time'
    ];
    for (var field in textFields) {
      _wodControllers[field] = TextEditingController(text: _fields[field]?.toString() ?? '');
    }
  }

  Future<void> _loadIcons() async {
    final icons = await SupabaseService.getIcons();
    setState(() {
      _icons = icons;
      _isLoadingIcons = false;
    });
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      if (widget.mode == 'Sessions') {
        final updates = {
          'session_type': _fields['session_type'],
          'session': int.tryParse(_sessionController.text) ?? _fields['session'],
          'duration': int.tryParse(_durationController.text) ?? _fields['duration'],
        };
        await SupabaseService.updateSessionsBatch(
          originalAttributes: widget.group['original_attributes'],
          updates: updates,
          start: widget.startDate,
          end: widget.endDate,
          coach: widget.coach,
        );
      } else {
        final updates = {
          'day': _fields['day'],
          'ex_unit': _fields['ex_unit'],
          'rest_unit': _fields['rest_unit'],
          'sets': int.tryParse(_wodControllers['sets']!.text) ?? 0,
          'details': _wodControllers['details']!.text,
          'time_exercise': double.tryParse(_wodControllers['time_exercise']!.text) ?? 0,
          'rest': double.tryParse(_wodControllers['rest']!.text) ?? 0,
          'total_time': double.tryParse(_wodControllers['total_time']!.text) ?? 0,
          'stage': _fields['stage'],
        };
        await SupabaseService.updateWorkoutsBatch(
          originalAttributes: widget.group['original_attributes'],
          updates: updates,
          start: widget.startDate,
          end: widget.endDate,
          coach: widget.coach,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error saving: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text('Edit ${widget.mode == 'Sessions' ? 'Session' : 'WOD'} Group'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.primaryTeal),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoadingIcons
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.mode == 'Sessions') ..._buildSessionFields() else ..._buildWodFields(),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryTeal,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.black)
                        : const Text('Save Changes', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
    );
  }

  List<Widget> _buildSessionFields() {
    return [
      const Text('Session Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 8),
      _buildDropdown(
        value: _fields['session_type'],
        items: _icons.map((e) => e['session_type'] as String).toList(),
        onChanged: (val) => setState(() => _fields['session_type'] = val),
      ),
      const SizedBox(height: 16),
      const Text('Session Number', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 8),
      TextField(
        controller: _sessionController,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          filled: true,
          fillColor: AppTheme.cardColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 16),
      const Text('Duration (min)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 8),
      TextField(
        controller: _durationController,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          filled: true,
          fillColor: AppTheme.cardColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        ),
      ),
    ];
  }

  List<Widget> _buildWodFields() {
    final days = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo'];
    final stages = ['WARMUP', 'SKILL', 'STRENGTH', 'WORKOUT', 'COOLDOWN'];
    
    return [
      // 1. mesocycle
      _buildReadOnlyField('Mesocycle', _fields['mesocycle']?.toString() ?? '-'),
      const SizedBox(height: 16),
      
      // 2. day
      const Text('Day', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 8),
      _buildDropdown(
        value: _fields['day'],
        items: days,
        onChanged: (val) => setState(() => _fields['day'] = val),
      ),
      const SizedBox(height: 16),
      
      // 3. exercise
      _buildReadOnlyField('Exercise', _fields['exercise']?.toString() ?? '-'),
      const SizedBox(height: 16),
      
      // 5. stage
      const Text('Stage', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 8),
      _buildDropdown(
        value: _fields['stage'],
        items: stages,
        onChanged: (val) => setState(() => _fields['stage'] = val),
      ),
      const SizedBox(height: 16),
      
      // 6. details
      _buildTextField('Details', 'details', maxLines: 3),
      const SizedBox(height: 16),
      
      // 7. sets
      _buildTextField('Sets', 'sets', isNumber: true),
      const SizedBox(height: 16),
      
      // 8. time_exercise
      _buildTextField('Time Exercise', 'time_exercise', isNumber: true),
      const SizedBox(height: 16),
      
      // 9. ex_unit
      _buildChoiceSection('Exercise Unit (ex_unit)', 'ex_unit', ['kg', 'lb', 'reps', 'sec', 'min']),
      const SizedBox(height: 16),
      
      // 10. rest
      _buildTextField('Rest', 'rest', isNumber: true),
      const SizedBox(height: 16),
      
      // 11. rest_unit
      _buildChoiceSection('Rest Unit (rest_unit)', 'rest_unit', ['sec', 'min']),
      const SizedBox(height: 16),
      
      // 12. total_time
      _buildTextField('Total Time', 'total_time', isNumber: true),
    ];
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.secondaryTextColor)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.cardColor.withOpacity(0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        ),
      ],
    );
  }

  Widget _buildTextField(String label, String field, {bool isNumber = false, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        TextField(
          controller: _wodControllers[field],
          keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppTheme.cardColor,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({required String? value, required List<String> items, required Function(String) onChanged}) {
    return InkWell(
      onTap: () => _showPicker(value ?? '', items, onChanged),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(value ?? 'Select...', style: const TextStyle(color: Colors.white, fontSize: 14)),
            const Icon(Icons.keyboard_arrow_down, color: AppTheme.secondaryTextColor),
          ],
        ),
      ),
    );
  }

  void _showPicker(String current, List<String> items, Function(String) onChanged) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.backgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ...items.map((it) => ListTile(
              title: Text(it, style: const TextStyle(color: Colors.white)),
              onTap: () {
                onChanged(it);
                Navigator.pop(context);
              },
              trailing: current == it ? const Icon(Icons.check, color: AppTheme.primaryTeal) : null,
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceSection(String label, String field, List<String> options) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: options.map((opt) {
            bool isSelected = _fields[field] == opt;
            return ChoiceChip(
              label: Text(opt),
              selected: isSelected,
              onSelected: (val) {
                if (val) setState(() => _fields[field] = opt);
              },
              selectedColor: AppTheme.primaryTeal,
              backgroundColor: AppTheme.cardColor,
              labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
            );
          }).toList(),
        ),
      ],
    );
  }
}
