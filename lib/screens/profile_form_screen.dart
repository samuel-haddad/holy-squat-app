import 'package:flutter/material.dart';
import 'package:holy_squat_app/theme/app_theme.dart';
import 'package:holy_squat_app/core/user_state.dart';
import 'package:holy_squat_app/services/supabase_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:typed_data';

class ProfileFormScreen extends StatefulWidget {
  const ProfileFormScreen({super.key});

  @override
  State<ProfileFormScreen> createState() => _ProfileFormScreenState();
}

class _ProfileFormScreenState extends State<ProfileFormScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _birthdateController;
  late TextEditingController _weightController;
  late TextEditingController _sportController;
  late TextEditingController _goalController;
  late String _weightUnit;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: UserState.name.value);
    _emailController = TextEditingController(text: UserState.email.value);
    _birthdateController = TextEditingController(text: UserState.birthdate.value);
    _weightController = TextEditingController(text: UserState.weight.value);
    _sportController = TextEditingController(text: UserState.sport.value);
    _goalController = TextEditingController(text: UserState.goal.value);
    _weightUnit = UserState.weightUnit.value;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _birthdateController.dispose();
    _weightController.dispose();
    _sportController.dispose();
    _goalController.dispose();
    super.dispose();
  }
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      final bytes = await image.readAsBytes();
      UserState.avatarBytes.value = bytes;
      
      // Auto-save silently in the background
      SupabaseService.upsertProfile().catchError((e) {
        debugPrint('Auto-save profile image failed: $e');
      });
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
              Center(
                child: ValueListenableBuilder<String?>(
                  valueListenable: UserState.avatarUrl,
                  builder: (context, avatarUrl, _) {
                    return ValueListenableBuilder<Uint8List?>(
                      valueListenable: UserState.avatarBytes,
                      builder: (context, avatarBytes, child) {
                        ImageProvider? provider;
                        if (avatarBytes != null) {
                          provider = MemoryImage(avatarBytes);
                        } else if (avatarUrl != null && avatarUrl.isNotEmpty) {
                          provider = NetworkImage(avatarUrl);
                        }

                        return GestureDetector(
                          onTap: _pickImage,
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundColor: Colors.transparent,
                                backgroundImage: provider,
                                child: provider == null
                                    ? SvgPicture.asset(
                                        Theme.of(context).brightness == Brightness.dark
                                            ? 'assets/account_icons/account_icon_dark.svg'
                                            : 'assets/account_icons/account_icon_light.svg',
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              const CircleAvatar(
                                backgroundColor: AppTheme.primaryTeal,
                                radius: 18,
                                child: Icon(Icons.camera_alt, size: 18, color: Colors.black),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              _buildTextField('Name', _nameController),
              const SizedBox(height: 16),
              _buildTextField('Email', _emailController),
              const SizedBox(height: 16),
              _buildBirthdateField('Birthdate'),
              const SizedBox(height: 16),
              _buildWeightField(),
              const SizedBox(height: 16),
              _buildTextField('Favorite Sport', _sportController),
              const SizedBox(height: 16),
              _buildTextField('Training goal', _goalController),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryTeal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    // Save action
                    if (_formKey.currentState!.validate()) {
                      UserState.name.value = _nameController.text;
                      UserState.email.value = _emailController.text;
                      UserState.birthdate.value = _birthdateController.text;
                      UserState.weight.value = _weightController.text;
                      UserState.sport.value = _sportController.text;
                      UserState.goal.value = _goalController.text;
                      UserState.weightUnit.value = _weightUnit;
                      
                      try {
                        await SupabaseService.upsertProfile();
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save profile: $e')));
                      }
                    }
                  },
                  child: const Text('Save Changes', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
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

  Widget _buildBirthdateField(String label) {
    return TextFormField(
      controller: _birthdateController,
      keyboardType: TextInputType.datetime,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.secondaryTextColor),
        enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppTheme.cardColor), borderRadius: BorderRadius.circular(8)),
        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppTheme.primaryTeal), borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: AppTheme.cardColor,
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today, color: AppTheme.primaryTeal),
          onPressed: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: DateTime(1990, 1, 1),
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
              builder: (context, child) {
                return Theme(
                  data: ThemeData.dark().copyWith(
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
            if (date != null) {
              setState(() {
                _birthdateController.text = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildWeightField() {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: _weightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: false),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Weight',
              labelStyle: const TextStyle(color: AppTheme.secondaryTextColor),
              enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppTheme.cardColor), borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppTheme.primaryTeal), borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: AppTheme.cardColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 1,
          child: DropdownButtonFormField<String>(
            value: _weightUnit,
            dropdownColor: AppTheme.cardColor,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppTheme.cardColor), borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppTheme.primaryTeal), borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: AppTheme.cardColor,
            ),
            items: ['Kg', 'Lb'].map((unit) {
              return DropdownMenuItem(value: unit, child: Text(unit));
            }).toList(),
            onChanged: (val) {
              setState(() {
                if (val != null) _weightUnit = val;
              });
            },
          ),
        ),
      ],
    );
  }
}
