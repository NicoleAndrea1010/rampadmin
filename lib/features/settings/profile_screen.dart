import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/admin_routes.dart';
import '../../core/services/firebase_error_mapper.dart';
import '../../core/widgets/ui_components.dart';
import '../../providers/auth_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentAdminUserProvider);
    final email = user?.email ?? 'Unavailable';
    final name = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!
        : email == 'Unavailable'
        ? 'Administrator'
        : email.split('@').first;
    final providerNames = user?.providerData
        .map((provider) => provider.providerId)
        .where((provider) => provider.isNotEmpty)
        .toSet()
        .join(', ');
    final lastSignIn = user?.metadata.lastSignInTime;

    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 700 ? 20 : 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            title: 'Profile',
            subtitle: 'Your authenticated administrator account.',
          ),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(
                  MediaQuery.sizeOf(context).width < 400 ? 18 : 28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        LandlordAvatar(name: name, radius: 29),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                email,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'ACCOUNT',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ProfileRow(label: 'Email', value: email),
                    const _ProfileRow(
                      label: 'Role',
                      value: 'Super Administrator',
                    ),
                    _ProfileRow(
                      label: 'Authentication provider',
                      value: providerNames?.isNotEmpty == true
                          ? providerNames!
                          : 'Unavailable',
                    ),
                    _ProfileRow(
                      label: 'Last sign-in',
                      value: lastSignIn == null
                          ? 'Unavailable'
                          : DateFormat.yMMMd().add_jm().format(
                              lastSignIn.toLocal(),
                            ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'SESSION',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _ProfileRow(
                      label: 'Status',
                      value: user == null ? 'Signed out' : 'Signed in',
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () =>
                              ref.read(adminAuthServiceProvider).signOut(),
                          icon: const Icon(Icons.logout),
                          label: const Text('Sign Out'),
                        ),
                        TextButton.icon(
                          onPressed: () => context.go(AdminRoutes.settings),
                          icon: const Icon(Icons.palette_outlined),
                          label: const Text('Appearance settings'),
                        ),
                        TextButton.icon(
                          onPressed: email == 'Unavailable'
                              ? null
                              : () => _sendPasswordReset(context, ref, email),
                          icon: const Icon(Icons.password_rounded),
                          label: const Text('Reset password'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendPasswordReset(
    BuildContext context,
    WidgetRef ref,
    String email,
  ) async {
    try {
      await ref.read(adminAuthServiceProvider).sendPasswordReset(email);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password reset email sent to $email.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FirebaseErrorMapper.message(error))),
        );
      }
    }
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final labelText = Text(
      label,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
    final valueText = Text(value, softWrap: true);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth < 430
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelText, const SizedBox(height: 2), valueText],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 210, child: labelText),
                  Expanded(child: valueText),
                ],
              ),
      ),
    );
  }
}
