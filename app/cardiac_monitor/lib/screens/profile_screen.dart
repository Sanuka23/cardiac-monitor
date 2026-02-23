import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../models/user.dart';
import '../config/theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _ageC = TextEditingController();
  final _heightC = TextEditingController();
  final _weightC = TextEditingController();
  String _sex = 'male';
  bool _diabetic = false;
  bool _hypertensive = false;
  bool _smoker = false;
  bool _familyHistory = false;
  final _conditionsC = TextEditingController();
  final _medicationsC = TextEditingController();
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final profile = context.read<AuthProvider>().user?.healthProfile;
      if (profile != null) {
        _ageC.text = profile.age?.toString() ?? '';
        _heightC.text = profile.heightCm?.toString() ?? '';
        _weightC.text = profile.weightKg?.toString() ?? '';
        _sex = profile.sex ?? 'male';
        _diabetic = profile.diabetic;
        _hypertensive = profile.hypertensive;
        _smoker = profile.smoker;
        _familyHistory = profile.familyHistory;
        _conditionsC.text = profile.knownConditions.join(', ');
        _medicationsC.text = profile.medications.join(', ');
      }
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _ageC.dispose();
    _heightC.dispose();
    _weightC.dispose();
    _conditionsC.dispose();
    _medicationsC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final profile = HealthProfile(
      age: int.tryParse(_ageC.text),
      sex: _sex,
      heightCm: double.tryParse(_heightC.text),
      weightKg: double.tryParse(_weightC.text),
      diabetic: _diabetic,
      hypertensive: _hypertensive,
      smoker: _smoker,
      familyHistory: _familyHistory,
      knownConditions: _conditionsC.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      medications: _medicationsC.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    );

    final ok = await context.read<ProfileProvider>().saveProfile(profile);
    if (!mounted) return;

    if (ok) {
      await context.read<AuthProvider>().refreshUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile saved'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF22C55E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to save profile'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileProv = context.watch<ProfileProvider>();
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Profile Header ──
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppGradients.primary,
                      ),
                      child: Center(
                        child: Text(
                          (auth.user?.name ?? 'U')[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      auth.user?.name ?? 'User',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Health data improves prediction accuracy',
                      style: TextStyle(
                        color: AppTheme.textSecondary(context),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms),
              const SizedBox(height: 24),

              // ── Personal Section ──
              _sectionHeader('Personal', PhosphorIconsLight.user, const Color(0xFF3B82F6)),
              const SizedBox(height: 10),
              _buildCard(
                child: Column(
                  children: [
                    _buildTextField(_ageC, 'Age', PhosphorIconsLight.calendar,
                        keyboardType: TextInputType.number),
                    const SizedBox(height: 12),
                    // Sex selector
                    _buildSegmentedControl(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(_heightC, 'Height (cm)',
                              PhosphorIconsLight.ruler,
                              keyboardType: TextInputType.number),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(_weightC, 'Weight (kg)',
                              PhosphorIconsLight.scales,
                              keyboardType: TextInputType.number),
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms, delay: 50.ms).slideY(begin: 0.05),

              const SizedBox(height: 20),

              // ── Medical History Section ──
              _sectionHeader('Medical History', PhosphorIconsLight.stethoscope, const Color(0xFFEF4444)),
              const SizedBox(height: 10),
              _buildCard(
                child: Column(
                  children: [
                    _buildToggle('Diabetic', PhosphorIconsLight.stethoscope,
                        _diabetic, (v) => setState(() => _diabetic = v)),
                    Divider(color: AppTheme.dividerColor(context), height: 1),
                    _buildToggle('Hypertensive', PhosphorIconsLight.heartbeat,
                        _hypertensive, (v) => setState(() => _hypertensive = v)),
                    Divider(color: AppTheme.dividerColor(context), height: 1),
                    _buildToggle('Smoker', PhosphorIconsLight.prohibit,
                        _smoker, (v) => setState(() => _smoker = v)),
                    Divider(color: AppTheme.dividerColor(context), height: 1),
                    _buildToggle('Family History', PhosphorIconsLight.users,
                        _familyHistory, (v) => setState(() => _familyHistory = v)),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms, delay: 100.ms).slideY(begin: 0.05),

              const SizedBox(height: 20),

              // ── Conditions Section ──
              _sectionHeader('Conditions & Medications', PhosphorIconsLight.pill, const Color(0xFF8B5CF6)),
              const SizedBox(height: 10),
              _buildCard(
                child: Column(
                  children: [
                    _buildTextField(_conditionsC, 'Known conditions (comma separated)',
                        PhosphorIconsLight.fileText, maxLines: 2),
                    const SizedBox(height: 12),
                    _buildTextField(_medicationsC, 'Medications (comma separated)',
                        PhosphorIconsLight.pill, maxLines: 2),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms, delay: 150.ms).slideY(begin: 0.05),

              const SizedBox(height: 28),

              // ── Save Button ──
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: profileProv.saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent(context),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: profileProv.saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Save Profile',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ).animate().fadeIn(duration: 300.ms, delay: 200.ms).slideY(begin: 0.05),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String text, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary(context),
          ),
        ),
      ],
    );
  }

  Widget _buildCard({required Widget child}) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dividerColor(context)),
        boxShadow: isLight
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: child,
    );
  }

  Widget _buildSegmentedControl() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _sexTab('Male', 'male'),
          _sexTab('Female', 'female'),
        ],
      ),
    );
  }

  Widget _sexTab(String label, String value) {
    final selected = _sex == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _sex = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppTheme.textSecondary(context),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(color: AppTheme.textPrimary(context), fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppTheme.textTertiary(context), fontSize: 14),
        prefixIcon: Icon(icon, size: 18, color: AppTheme.textSecondary(context)),
        filled: true,
        fillColor: AppTheme.surfaceVariant(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.dividerColor(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppTheme.accent(context), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _buildToggle(
      String label, IconData icon, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SwitchListTile(
        title: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.textSecondary(context)),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    fontSize: 14, color: AppTheme.textPrimary(context))),
          ],
        ),
        value: value,
        onChanged: onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        activeTrackColor: AppTheme.accent(context),
      ),
    );
  }
}
