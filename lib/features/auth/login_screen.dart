import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/admin_auth_service.dart';
import '../../core/services/firebase_error_mapper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/ui_components.dart';
import '../../providers/auth_providers.dart';
import '../../providers/settings_providers.dart';

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
  bool _isWelcome = false;
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

  Future<void> _handleManualLogin() async {
    if (_lockoutSeconds > 0) return;
    if (!_formKey.currentState!.validate()) return;
    await _authenticate(
      email: _emailController.text,
      password: _passwordController.text,
    );
  }

  Future<void> _handleDemoLogin() async {
    final configuration = ref.read(demoLoginConfigurationProvider);
    if (!configuration.isAvailable) return;
    await _authenticate(
      email: configuration.email,
      password: configuration.password,
    );
  }

  Future<void> _authenticate({
    required String email,
    required String password,
  }) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isWelcome = false;
    });
    ref.read(loginTransitionProvider.notifier).setInProgress(true);

    try {
      await ref.read(adminSignInCallbackProvider)(
        email: email,
        password: password,
      );
      if (!mounted) return;
      _failedAttempts = 0;
      final reduceMotion =
          ref.read(reducedMotionProvider) ||
          MediaQuery.disableAnimationsOf(context);
      if (!reduceMotion) {
        setState(() => _isWelcome = true);
        await Future<void>.delayed(const Duration(milliseconds: 850));
      }
      if (!mounted) return;
      setState(() => _isWelcome = false);
      ref.read(loginTransitionProvider.notifier).setInProgress(false);
      widget.onSuccess();
    } on AdminAccessException catch (e) {
      ref.read(loginTransitionProvider.notifier).setInProgress(false);
      _registerFailedAttempt();
      setState(() {
        _errorMessage = e.message;
      });
    } catch (error) {
      ref.read(loginTransitionProvider.notifier).setInProgress(false);
      _registerFailedAttempt();
      setState(() {
        _errorMessage = FirebaseErrorMapper.message(error);
      });
    } finally {
      if (mounted) {
        ref.read(loginTransitionProvider.notifier).setInProgress(false);
        setState(() {
          _isLoading = false;
          _isWelcome = false;
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
    final demoAvailable = ref.watch(demoLoginConfigurationProvider).isAvailable;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 900;
          if (desktop) {
            return Row(
              children: [
                Expanded(
                  flex: 5,
                  child: RampEntrance(child: _brandPanel(context, false)),
                ),
                Expanded(
                  flex: 6,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(36),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 470),
                        child: RampEntrance(
                          delay: const Duration(milliseconds: 80),
                          child: _loginCard(
                            context,
                            isLockedOut,
                            demoAvailable,
                            false,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  children: [
                    RampEntrance(child: _brandPanel(context, true)),
                    const SizedBox(height: 16),
                    RampEntrance(
                      delay: const Duration(milliseconds: 80),
                      child: _loginCard(
                        context,
                        isLockedOut,
                        demoAvailable,
                        true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _brandPanel(BuildContext context, bool compact) => Container(
    constraints: BoxConstraints(minHeight: compact ? 150 : 500),
    padding: EdgeInsets.all(compact ? 20 : 56),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(compact ? 22 : 0),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF102C61), Color(0xFF1658B8), Color(0xFF1473B9)],
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          right: compact ? -6 : 0,
          bottom: compact ? -2 : 15,
          child: Opacity(
            opacity: compact ? .14 : .23,
            child: _BuildingMotif(compact: compact),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: compact
              ? MainAxisAlignment.center
              : MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(28),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.white.withAlpha(45)),
                  ),
                  child: const Icon(
                    Icons.apartment_rounded,
                    color: Colors.white,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'RAMP',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
            if (!compact) ...[
              const SizedBox(height: 54),
              const Text(
                'Rental Administration\nManagement Platform',
                style: TextStyle(
                  color: Colors.white,
                  height: 1.18,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'A clearer view of every portfolio, account, and operational detail.',
                style: TextStyle(
                  color: Colors.white.withAlpha(210),
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              const _PlatformStatus(),
            ],
          ],
        ),
      ],
    ),
  );

  Widget _loginCard(
    BuildContext context,
    bool isLockedOut,
    bool demoAvailable,
    bool compact,
  ) => Card(
    elevation: 3,
    shadowColor: AppColors.primaryNavy.withAlpha(18),
    child: Padding(
      padding: EdgeInsets.all(compact ? 22 : 34),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedOpacity(
            opacity: _isWelcome ? 0 : 1,
            duration: const Duration(milliseconds: 220),
            child: AbsorbPointer(
              absorbing: _isWelcome,
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _isWelcome
                          ? _WelcomeBack(
                              name: ref
                                  .watch(currentAdminUserProvider)
                                  ?.displayName,
                            )
                          : Column(
                              key: const ValueKey('login-form-heading'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Welcome back',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Sign in to your RAMP administrator workspace.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 24),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _errorMessage == null
                          ? const SizedBox.shrink(
                              key: ValueKey('no-login-error'),
                            )
                          : Container(
                              key: ValueKey(_errorMessage),
                              margin: const EdgeInsets.only(bottom: 18),
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: isLockedOut
                                    ? AppColors.warningBg
                                    : AppColors.errorBg,
                                borderRadius: BorderRadius.circular(12),
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
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(_errorMessage!)),
                                ],
                              ),
                            ),
                    ),
                    TextFormField(
                      controller: _emailController,
                      enabled: !isLockedOut && !_isLoading && !_isWelcome,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Administrator email',
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
                      enabled: !isLockedOut && !_isLoading && !_isWelcome,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: isLockedOut || _isLoading || _isWelcome
                            ? null
                            : _handleForgotPassword,
                        child: const Text('Forgot password?'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isLockedOut || _isLoading || _isWelcome
                            ? null
                            : _handleManualLogin,
                        child: _isLoading
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  SizedBox(width: 11),
                                  Text('Signing in...'),
                                ],
                              )
                            : Text(
                                isLockedOut
                                    ? 'Locked ($_lockoutSeconds s)'
                                    : 'Sign In',
                              ),
                      ),
                    ),
                    if (demoAvailable) ...[
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: _isLoading || _isWelcome
                            ? null
                            : _handleDemoLogin,
                        icon: const Icon(Icons.bolt_rounded),
                        label: const Text('Sign in as Demo Super Admin'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (_isWelcome)
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: .75, end: 1),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (context, scale, child) => Opacity(
                  opacity: scale,
                  child: Transform.scale(scale: scale, child: child),
                ),
                child: Center(
                  child: _WelcomeBack(
                    name:
                        ref.watch(currentAdminUserProvider)?.displayName ??
                        ref
                            .watch(currentAdminUserProvider)
                            ?.email
                            ?.split('@')
                            .first,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _WelcomeBack extends StatelessWidget {
  const _WelcomeBack({required this.name});
  final String? name;

  @override
  Widget build(BuildContext context) {
    final firstName = name?.trim().split(RegExp(r'\s+')).first;
    return Column(
      key: const ValueKey('login-welcome'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: const BoxDecoration(
            color: AppColors.mintTint,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            color: AppColors.mint,
            size: 32,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          firstName?.isNotEmpty == true
              ? 'Welcome back, $firstName'
              : 'Welcome back',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _BuildingMotif extends StatelessWidget {
  const _BuildingMotif({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      _building(96, 190),
      const SizedBox(width: 12),
      _building(124, 250),
      const SizedBox(width: 12),
      _building(88, 160),
    ],
  );

  Widget _building(double width, double height) => Container(
    width: compact ? width * .42 : width,
    height: compact ? height * .42 : height,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      border: Border.all(color: Colors.white.withAlpha(80)),
    ),
    child: GridView.count(
      padding: EdgeInsets.zero,
      crossAxisCount: 3,
      mainAxisSpacing: 9,
      crossAxisSpacing: 9,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(
        12,
        (_) => DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(100),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    ),
  );
}

class _PlatformStatus extends StatelessWidget {
  const _PlatformStatus();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      _StatusTag(icon: Icons.verified_user_outlined, label: 'Firebase Auth'),
      _StatusTag(icon: Icons.apartment_outlined, label: 'Supabase Data'),
    ],
  );
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withAlpha(20),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.white.withAlpha(36)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
