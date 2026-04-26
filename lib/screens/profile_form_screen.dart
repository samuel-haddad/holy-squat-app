import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/core/user_state.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'package:holy_squat_app/models/training_session.dart';
import 'package:holy_squat_app/widgets/training_sessions_editor.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({super.key});

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // About Section
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _birthdateController;
  late TextEditingController _weightController;
  late String _weightUnit;
  late TextEditingController _goalController;
  late TextEditingController _sportController;

  // Skills & Training Section
  late TextEditingController _anamnesisController;
  List<TrainingSession> _trainingSessions = [];
  bool _loadingSessions = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: UserState.name.value);
    _emailController = TextEditingController(text: UserState.email.value);
    _birthdateController = TextEditingController(text: UserState.birthdate.value);
    _weightController = TextEditingController(text: UserState.weight.value);
    _weightUnit = UserState.weightUnit.value;
    _goalController = TextEditingController(text: UserState.goal.value);
    _sportController = TextEditingController(text: UserState.sport.value);

    _anamnesisController = TextEditingController(text: UserState.anamnesis.value);
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    final sessions = await SupabaseService.fetchTrainingSessions();
    if (mounted) {
      setState(() {
        _trainingSessions = sessions;
        _loadingSessions = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _birthdateController.dispose();
    _weightController.dispose();
    _goalController.dispose();
    _sportController.dispose();
    _anamnesisController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      UserState.avatarBytes.value = bytes;
      SupabaseService.upsertProfile().catchError((e) => debugPrint('Auto-save failed: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile', style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvatarSection(),
              const SizedBox(height: 24),
              
              _buildSectionHeader('About'),
              _buildTextField('Full Name', _nameController),
              const SizedBox(height: 16),
              _buildBirthdateField('Birthdate'),
              const SizedBox(height: 16),
              _buildWeightField(),
              const SizedBox(height: 16),
              _buildTextField('Favorite Sport', _sportController),
              const SizedBox(height: 16),
              _buildTextField('Training Goal', _goalController),
              const SizedBox(height: 16),
              _buildTextField('Anamnesis', _anamnesisController, maxLines: 3, required: false, maxLength: 1500),
              
              const SizedBox(height: 32),
              _buildSectionHeader('Training Sessions'),
              const SizedBox(height: 16),
              _loadingSessions
                  ? const Center(child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(color: AppTheme.primaryTeal),
                    ))
                  : TrainingSessionsEditor(
                      sessions: _trainingSessions,
                      onChanged: (sessions) => _trainingSessions = sessions,
                    ),

              const SizedBox(height: 48),
              _buildSaveButton(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryTeal)),
    );
  }

  Widget _buildAvatarSection() {
    return Center(
      child: ValueListenableBuilder<String?>(
        valueListenable: UserState.avatarUrl,
        builder: (context, avatarUrl, _) => ValueListenableBuilder<Uint8List?>(
          valueListenable: UserState.avatarBytes,
          builder: (context, avatarBytes, _) {
            ImageProvider? provider;
            if (avatarBytes != null) provider = MemoryImage(avatarBytes);
            else if (avatarUrl != null && avatarUrl.isNotEmpty) provider = NetworkImage(avatarUrl);
            return GestureDetector(
              onTap: _pickImage,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.transparent,
                    backgroundImage: provider,
                    child: provider == null ? SvgPicture.asset(
                      Theme.of(context).brightness == Brightness.dark ? 'assets/account_icons/account_icon_dark.svg' : 'assets/account_icons/account_icon_light.svg',
                      width: 100, height: 100, fit: BoxFit.cover,
                    ) : null,
                  ),
                  const CircleAvatar(backgroundColor: AppTheme.primaryTeal, radius: 18, child: Icon(Icons.camera_alt, size: 18, color: Colors.black)),
                ],
              ),
            );
          },
        ),
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

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity, height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryTeal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        onPressed: () async {
          if (_formKey.currentState!.validate()) {
            UserState.name.value = _nameController.text;
            UserState.birthdate.value = _birthdateController.text;
            UserState.weight.value = _weightController.text;
            UserState.weightUnit.value = _weightUnit;
            UserState.goal.value = _goalController.text;
            UserState.sport.value = _sportController.text;
            UserState.anamnesis.value = _anamnesisController.text;

            try {
              await SupabaseService.upsertProfile();
              await SupabaseService.upsertAllTrainingSessions(_trainingSessions);
              if (mounted) Navigator.pop(context);
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
            }
          }
        },
        child: const Text('Save Changes', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
