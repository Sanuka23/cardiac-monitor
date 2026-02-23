import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/profile_provider.dart';
import '../models/user.dart';

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
        const SnackBar(content: Text('Profile saved')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to save profile'),
          backgroundColor: Colors.red[700],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileProv = context.watch<ProfileProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Health Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Basic info
            _sectionTitle('Basic Information'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ageC,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Age'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'male', label: Text('Male')),
                      ButtonSegment(value: 'female', label: Text('Female')),
                    ],
                    selected: {_sex},
                    onSelectionChanged: (s) =>
                        setState(() => _sex = s.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _heightC,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(hintText: 'Height (cm)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _weightC,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(hintText: 'Weight (kg)'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),
            _sectionTitle('Medical History'),
            const SizedBox(height: 12),
            _toggle('Diabetic', _diabetic,
                (v) => setState(() => _diabetic = v)),
            _toggle('Hypertensive', _hypertensive,
                (v) => setState(() => _hypertensive = v)),
            _toggle(
                'Smoker', _smoker, (v) => setState(() => _smoker = v)),
            _toggle('Family History of Heart Disease', _familyHistory,
                (v) => setState(() => _familyHistory = v)),

            const SizedBox(height: 28),
            _sectionTitle('Conditions & Medications'),
            const SizedBox(height: 12),
            TextField(
              controller: _conditionsC,
              decoration: const InputDecoration(
                hintText: 'Known conditions (comma separated)',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _medicationsC,
              decoration: const InputDecoration(
                hintText: 'Medications (comma separated)',
              ),
              maxLines: 2,
            ),

            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: profileProv.saving ? null : _save,
              child: profileProv.saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Profile'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Color(0xFF00BFA5),
        ),
      );

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      activeThumbColor: const Color(0xFF00BFA5),
    );
  }
}
