import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/core/user_state.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'package:holy_squat_app/screens/main_screen.dart';
import 'package:holy_squat_app/models/training_session.dart';
import 'package:holy_squat_app/widgets/training_sessions_editor.dart';
import 'package:file_picker/file_picker.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final _formKey1 = GlobalKey<FormState>();
  final _formKey2 = GlobalKey<FormState>();

  // Page 1 Controllers (About)
  late TextEditingController _nameController;
  late TextEditingController _birthdateController;
  late TextEditingController _weightController;
  late String _weightUnit;
  late TextEditingController _goalController;

  // Page 2 Controllers (Skills & Training)
  late TextEditingController _anamnesisController;
  late TextEditingController _activeHoursController;
  late String _activeHoursUnit;
  late TextEditingController _sessionsPerDayController;
  List<String> _selectedWhere = [];
  late TextEditingController _additionalInfoController;
  PlatformFile? _backgroundFile;
  List<TrainingSession> _trainingSessions = [];

  final List<String> _whereOptions = ['box', 'academia', 'corrida de rua'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: UserState.name.value);
    _birthdateController = TextEditingController(text: UserState.birthdate.value);
    _weightController = TextEditingController(text: UserState.weight.value);
    _weightUnit = UserState.weightUnit.value;
    _goalController = TextEditingController(text: UserState.goal.value);

    _anamnesisController = TextEditingController(text: UserState.anamnesis.value);
    _activeHoursController = TextEditingController(text: UserState.activeHoursValue.value.toString());
    _activeHoursUnit = UserState.activeHoursUnit.value;
    _sessionsPerDayController = TextEditingController(text: UserState.sessionsPerDay.value.toString());
    _selectedWhere = List<String>.from(UserState.whereTrain.value);
    _additionalInfoController = TextEditingController(text: UserState.additionalInfo.value);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _birthdateController.dispose();
    _weightController.dispose();
    _goalController.dispose();
    _anamnesisController.dispose();
    _activeHoursController.dispose();
    _sessionsPerDayController.dispose();
    _additionalInfoController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage == 0) {
      if (_formKey1.currentState!.validate()) {
        _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      }
    } else if (_currentPage == 1) {
      if (_formKey2.currentState!.validate()) {
        _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      }
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt', 'doc', 'docx'],
      withData: true, // Important for web and some native cases
    );
    if (result != null) {
      setState(() => _backgroundFile = result.files.first);
    }
  }

  Future<void> _finish() async {
    // Save everything to UserState
    UserState.name.value = _nameController.text;
    UserState.birthdate.value = _birthdateController.text;
    UserState.weight.value = _weightController.text;
    UserState.weightUnit.value = _weightUnit;
    UserState.goal.value = _goalController.text;

    UserState.anamnesis.value = _anamnesisController.text;
    UserState.activeHoursValue.value = double.tryParse(_activeHoursController.text) ?? 1.0;
    UserState.activeHoursUnit.value = _activeHoursUnit;
    UserState.sessionsPerDay.value = int.tryParse(_sessionsPerDayController.text) ?? 1;
    UserState.whereTrain.value = _selectedWhere;
    UserState.additionalInfo.value = _additionalInfoController.text;

    try {
      if (_backgroundFile != null) {
        final url = await SupabaseService.uploadTrainingBackground(_backgroundFile!);
        if (url == null) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to upload file. Please check your storage settings.')));
          return; // Stop if upload fails to avoid inconsistent state
        }
      }
      
      await SupabaseService.upsertProfile();
      await SupabaseService.upsertAllTrainingSessions(_trainingSessions);
      if (mounted) {
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainScreen()), (route) => false);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressBar(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _buildPage1(),
                  _buildPage2(),
                  _buildPage3(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: List.generate(3, (index) {
          return Expanded(
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: index <= _currentPage ? AppTheme.primaryTeal : Colors.grey[800],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPage1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Form(
        key: _formKey1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('About You', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            const Text('Let\'s start with the basics.', style: TextStyle(color: AppTheme.secondaryTextColor)),
            const SizedBox(height: 32),
            _buildTextField('Full Name', _nameController),
            const SizedBox(height: 16),
            _buildBirthdateField('Birthdate'),
            const SizedBox(height: 16),
            _buildWeightField(),
            const SizedBox(height: 16),
            _buildTextField('Training Goal', _goalController),
            const SizedBox(height: 48),
            _buildNextButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildPage2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Form(
        key: _formKey2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Skills & Training', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            const Text('Help us personalize your journey.', style: TextStyle(color: AppTheme.secondaryTextColor)),
            const SizedBox(height: 32),
            const SizedBox(height: 16),
            _buildTrainingBackgroundField(),
            const SizedBox(height: 16),
            _buildActiveHoursField(),
            const SizedBox(height: 16),
            _buildTextField('Sessions per day', _sessionsPerDayController, keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            const Text('Where do you train?', style: TextStyle(color: AppTheme.secondaryTextColor, fontSize: 14)),
            const SizedBox(height: 8),
            _buildWhereCheckboxes(),
            const SizedBox(height: 16),
            _buildTextField('Additional Info (Optional)', _additionalInfoController, maxLines: 2, required: false),
            const SizedBox(height: 24),
            TrainingSessionsEditor(
              sessions: _trainingSessions,
              onChanged: (sessions) => _trainingSessions = sessions,
            ),
            const SizedBox(height: 48),
            _buildNextButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildPage3() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline, color: AppTheme.primaryTeal, size: 100),
          const SizedBox(height: 32),
          const Text('All Set!', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 16),
          const Text(
            'Your profile is ready. You can now access your customized WODs and track your progress.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.secondaryTextColor, fontSize: 16),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryTeal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _finish,
              child: const Text('Start Training', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildTrainingBackgroundField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTextField('Training Background (Optional)', _anamnesisController, maxLines: 3, required: false),
        const SizedBox(height: 8),
        InkWell(
          onTap: _pickFile,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryTeal.withOpacity(0.3), width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.attach_file, color: AppTheme.primaryTeal, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _backgroundFile != null ? _backgroundFile!.name : 'Upload PDF or Text file',
                    style: TextStyle(color: _backgroundFile != null ? Colors.white : AppTheme.secondaryTextColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_backgroundFile != null)
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red, size: 18),
                    onPressed: () => setState(() => _backgroundFile = null),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWhereCheckboxes() {
    return Wrap(
      spacing: 8,
      children: _whereOptions.map((option) {
        final isSelected = _selectedWhere.contains(option);
        return FilterChip(
          label: Text(option),
          selected: isSelected,
          onSelected: (selected) {
            setState(() {
              if (selected) {
                _selectedWhere.add(option);
              } else {
                _selectedWhere.remove(option);
              }
            });
          },
          selectedColor: AppTheme.primaryTeal.withOpacity(0.3),
          checkmarkColor: AppTheme.primaryTeal,
          labelStyle: TextStyle(color: isSelected ? AppTheme.primaryTeal : Colors.white),
          backgroundColor: AppTheme.cardColor,
        );
      }).toList(),
    );
  }

  Widget _buildActiveHoursField() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: _buildTextField('Active hours per session', _activeHoursController, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _activeHoursUnit,
            dropdownColor: AppTheme.cardColor,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration('Unit'),
            items: ['hour', 'min'].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
            onChanged: (val) => setState(() => _activeHoursUnit = val!),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {int maxLines = 1, TextInputType? keyboardType, bool required = true}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(label),
      validator: required ? (v) => v == null || v.isEmpty ? 'Required' : null : null,
    );
  }

  Widget _buildBirthdateField(String label) {
    return TextFormField(
      controller: _birthdateController,
      readOnly: true,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(label).copyWith(suffixIcon: const Icon(Icons.calendar_today, color: AppTheme.primaryTeal)),
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime(1990, 1, 1),
          firstDate: DateTime(1900),
          lastDate: DateTime.now(),
        );
        if (date != null) {
          setState(() => _birthdateController.text = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}');
        }
      },
    );
  }

  Widget _buildWeightField() {
    return Row(
      children: [
        Expanded(flex: 2, child: _buildTextField('Weight', _weightController, keyboardType: TextInputType.number)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _weightUnit,
            dropdownColor: AppTheme.cardColor,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration('Unit'),
            items: ['Kg', 'Lb'].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
            onChanged: (val) => setState(() => _weightUnit = val!),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppTheme.secondaryTextColor),
      filled: true,
      fillColor: AppTheme.cardColor,
      enabledBorder: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppTheme.primaryTeal), borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildNextButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryTeal,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: _nextPage,
        child: const Text('Next Step', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
