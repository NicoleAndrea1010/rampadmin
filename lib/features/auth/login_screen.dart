import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/admin_auth_service.dart';
import '../../core/services/firebase_error_mapper.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, required this.onSuccess});

  final VoidCallback onSuccess;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  // Rate limiting / lockout timer
  int _failedAttempts = 0;
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  static const int _maxAllowedAttempts = 5;
  static const int _lockoutDurationSeconds = 60;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _lockoutTimer?.cancel();
    super.dispose();
  }

  void _startLockoutTimer(int seconds) {
    setState(() {
      _lockoutSeconds = seconds;
      _errorMessage =
          'Too many failed attempts. Login locked for $_lockoutSeconds seconds.';
    });

    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_lockoutSeconds > 1) {
          _lockoutSeconds--;
          _errorMessage =
              'Too many failed attempts. Login locked for $_lockoutSeconds seconds.';
        } else {
          _lockoutSeconds = 0;
          _failedAttempts = 0;
          _errorMessage = null;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _handleLogin() async {
    if (_lockoutSeconds > 0) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = ref.read(adminAuthServiceProvider);
      await authService.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
      _failedAttempts = 0;
      widget.onSuccess();
    } on AdminAccessException catch (e) {
      _registerFailedAttempt();
      setState(() {
        _errorMessage = e.message;
      });
    } catch (error) {
      _registerFailedAttempt();
      setState(() {
        _errorMessage = FirebaseErrorMapper.message(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _registerFailedAttempt() {
    _failedAttempts++;
    if (_failedAttempts >= _maxAllowedAttempts) {
      _startLockoutTimer(_lockoutDurationSeconds);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a valid email address to reset password.',
          ),
        ),
      );
      return;
    }

    try {
      await ref.read(adminAuthServiceProvider).sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password reset link sent to $email.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FirebaseErrorMapper.message(error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isLockedOut = _lockoutSeconds > 0;

    return Scaffold(
      backgroundColor: AppColors.primaryNavy,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              color: AppColors.cardLight,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.rocket_launch_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'RAMP',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              Text(
                                'Super Admin Portal',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isLockedOut
                                ? AppColors.warningBg
                                : AppColors.errorBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isLockedOut
                                  ? AppColors.warning.withAlpha(80)
                                  : AppColors.error.withAlpha(50),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isLockedOut
                                    ? Icons.timer_outlined
                                    : Icons.error_outline,
                                color: isLockedOut
                                    ? AppColors.warning
                                    : AppColors.error,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: isLockedOut
                                        ? AppColors.warning
                                        : AppColors.error,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.start,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      TextFormField(
                        controller: _emailController,
                        enabled: !isLockedOut && !_isLoading,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Super Admin Email',
                          prefixIcon: Icon(Icons.email_outlined, size: 18),
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                  .hasMatch(email)
                              ? null
                              : 'Enter a valid email';
                        },
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _passwordController,
                        enabled: !isLockedOut && !_isLoading,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(
                            Icons.lock_outline_rounded,
                            size: 18,
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) {
                            return 'Enter password';
                          }
                          if (val.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),

                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: isLockedOut || _isLoading
                              ? null
                              : _handleForgotPassword,
                          child: const Text(
                            'Forgot password?',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      ElevatedButton(
                        onPressed: isLockedOut || _isLoading
                            ? null
                            : _handleLogin,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                isLockedOut
                                    ? 'Locked ($_lockoutSeconds s)'
                                    : 'Sign In as Super Admin',
                              ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: AppColors.primaryBlue),
                        ),
                        onPressed: isLockedOut || _isLoading
                            ? null
                            : () {
                                _emailController.text =
                                    'nicoleandrearparedes@gmail.com';
                                _passwordController.text = 'superadmin123';
                                _handleLogin();
                              },
                        icon: const Icon(
                          Icons.flash_on_rounded,
                          color: AppColors.primaryBlue,
                          size: 18,
                        ),
                        label: const Text(
                          'demoadmin',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryBlue,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
