import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../models/user.dart';
import '../config/theme.dart';
import '../widgets/glass_card.dart';

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
          backgroundColor: const Color(0xFF4CAF50),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to save profile'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  InputDecoration _fieldDecor(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppTheme.textSecondary),
      prefixIcon: Icon(icon, size: 20, color: AppTheme.textSecondary),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileProv = context.watch<ProfileProvider>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Health Profile',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ).animate().fadeIn(duration: 400.ms),
                const SizedBox(height: 6),
                const Text(
                  'Your health data improves prediction accuracy',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 24),

                // Personal section
                _sectionLabel('PERSONAL'),
                const SizedBox(height: 10),
                GlassCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _ageC,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary),
                              decoration:
                                  _fieldDecor('Age', Iconsax.calendar),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Sex selector
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: [
                            _sexTab('Male', 'male'),
                            _sexTab('Female', 'female'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _heightC,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary),
                              decoration:
                                  _fieldDecor('Height (cm)', Iconsax.ruler),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _weightC,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary),
                              decoration:
                                  _fieldDecor('Weight (kg)', Iconsax.weight),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 100.ms)
                    .slideY(begin: 0.1),

                const SizedBox(height: 20),
                _sectionLabel('MEDICAL HISTORY'),
                const SizedBox(height: 10),
                GlassCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: Column(
                    children: [
                      _toggle('Diabetic', Iconsax.health, _diabetic,
                          (v) => setState(() => _diabetic = v)),
                      _divider(),
                      _toggle('Hypertensive', Iconsax.heart, _hypertensive,
                          (v) => setState(() => _hypertensive = v)),
                      _divider(),
                      _toggle('Smoker', Iconsax.forbidden_2, _smoker,
                          (v) => setState(() => _smoker = v)),
                      _divider(),
                      _toggle(
                          'Family History',
                          Iconsax.people,
                          _familyHistory,
                          (v) => setState(() => _familyHistory = v)),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 200.ms)
                    .slideY(begin: 0.1),

                const SizedBox(height: 20),
                _sectionLabel('CONDITIONS & MEDICATIONS'),
                const SizedBox(height: 10),
                GlassCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      TextField(
                        controller: _conditionsC,
                        style:
                            const TextStyle(color: AppTheme.textPrimary),
                        decoration: _fieldDecor(
                            'Known conditions (comma separated)',
                            Iconsax.document_text),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _medicationsC,
                        style:
                            const TextStyle(color: AppTheme.textPrimary),
                        decoration: _fieldDecor(
                            'Medications (comma separated)',
                            Iconsax.firstline),
                        maxLines: 2,
                      ),
                    ],
                  ),
                )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 300.ms)
                    .slideY(begin: 0.1),

                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppGradients.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ElevatedButton(
                      onPressed: profileProv.saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
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
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 500.ms, delay: 400.ms)
                    .slideY(begin: 0.1),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppTheme.accent,
        letterSpacing: 1.2,
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
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: selected ? AppGradients.primary : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    return Divider(
      height: 1,
      color: Colors.white.withValues(alpha: 0.06),
      indent: 16,
      endIndent: 16,
    );
  }

  Widget _toggle(
      String label, IconData icon, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(
                  fontSize: 14, color: AppTheme.textPrimary)),
        ],
      ),
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      activeThumbColor: AppTheme.accent,
    );
  }
}
