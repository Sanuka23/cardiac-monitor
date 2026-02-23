import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/glass_card.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isRegister = false;
  final _formKey = GlobalKey<FormState>();
  final _emailC = TextEditingController();
  final _passwordC = TextEditingController();
  final _nameC = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailC.dispose();
    _passwordC.dispose();
    _nameC.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    bool success;

    if (_isRegister) {
      success =
          await auth.register(_emailC.text, _passwordC.text, _nameC.text);
    } else {
      success = await auth.login(_emailC.text, _passwordC.text);
    }

    if (!mounted) return;

    if (success) {
      if (auth.deviceIds.isEmpty) {
        Navigator.of(context).pushReplacementNamed('/device-setup');
      } else {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } else if (auth.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error!),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isLoading = auth.state == AuthState.loading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.accent(context).withValues(alpha: 0.2),
                        AppTheme.accent(context).withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(
                    PhosphorIconsLight.heartbeat,
                    size: 48,
                    color: AppTheme.accent(context),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 300.ms)
                    .scale(begin: const Offset(0.8, 0.8)),
                const SizedBox(height: 20),
                Text(
                  'Cardiac Monitor',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary(context),
                  ),
                )
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 50.ms)
                    .slideY(begin: 0.05),
                const SizedBox(height: 6),
                Text(
                  'Real-time heart health monitoring',
                  style: TextStyle(
                    color: AppTheme.textSecondary(context),
                    fontSize: 14,
                  ),
                )
                    .animate()
                    .fadeIn(duration: 300.ms, delay: 100.ms)
                    .slideY(begin: 0.05),
                const SizedBox(height: 36),

                // Form card
                GlassCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Toggle
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant(context),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: [
                            _tab('Login', !_isRegister),
                            _tab('Register', _isRegister),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            if (_isRegister)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _buildField(
                                  controller: _nameC,
                                  hint: 'Full name',
                                  icon: PhosphorIconsLight.user,
                                  validator: (v) =>
                                      (v == null || v.trim().isEmpty)
                                          ? 'Name required'
                                          : null,
                                ),
                              ),
                            _buildField(
                              controller: _emailC,
                              hint: 'Email address',
                              icon: PhosphorIconsLight.envelope,
                              keyboardType: TextInputType.emailAddress,
                              validator: (v) =>
                                  (v == null || !v.contains('@'))
                                      ? 'Valid email required'
                                      : null,
                            ),
                            const SizedBox(height: 14),
                            _buildField(
                              controller: _passwordC,
                              hint: 'Password',
                              icon: PhosphorIconsLight.lock,
                              obscure: _obscure,
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? PhosphorIconsLight.eyeSlash
                                      : PhosphorIconsLight.eye,
                                  size: 20,
                                  color: AppTheme.textSecondary(context),
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                              validator: (v) => (v == null || v.length < 6)
                                  ? 'Min 6 characters'
                                  : null,
                            ),
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
                                  onPressed: isLoading ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          _isRegister
                                              ? 'Create Account'
                                              : 'Sign In',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 300.ms, delay: 150.ms).slideY(begin: 0.05),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: TextStyle(color: AppTheme.textPrimary(context)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppTheme.textSecondary(context)),
        prefixIcon: Icon(icon, size: 20, color: AppTheme.textSecondary(context)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppTheme.surfaceVariant(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppTheme.dividerColor(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppTheme.accent(context), width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      validator: validator,
    );
  }

  Widget _tab(String label, bool selected) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _isRegister = label == 'Register'),
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
                color: selected ? Colors.white : AppTheme.textSecondary(context),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
