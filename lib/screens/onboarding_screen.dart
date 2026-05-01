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
  late TextEditingController _anamnesisController;

  // Page 2 Controllers (Training Sessions)
  List<TrainingSession> _trainingSessions = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: UserState.name.value);
    _birthdateController = TextEditingController(text: UserState.birthdate.value);
    _weightController = TextEditingController(text: UserState.weight.value);
    _weightUnit = UserState.weightUnit.value;
    _goalController = TextEditingController(text: UserState.goal.value);

    _anamnesisController = TextEditingController(text: UserState.anamnesis.value);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _birthdateController.dispose();
    _weightController.dispose();
    _goalController.dispose();
    _anamnesisController.dispose();
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

  Future<void> _finish() async {
    UserState.goal.value = _goalController.text;
    UserState.anamnesis.value = _anamnesisController.text;

    try {
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
      body: SelectionArea(
        child: SafeArea(
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
            const SizedBox(height: 16),
            _buildTextField('Anamnesis', _anamnesisController, maxLines: 3, required: false, maxLength: 1500),
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
            const Text('Training Sessions', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            const Text('When and where do you usually train?', style: TextStyle(color: AppTheme.secondaryTextColor)),
            const SizedBox(height: 32),
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

  Widget _buildTextField(String label, TextEditingController controller, {int maxLines = 1, TextInputType? keyboardType, bool required = true, int? maxLength}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(label).copyWith(
        counterStyle: const TextStyle(color: AppTheme.secondaryTextColor),
      ),
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
