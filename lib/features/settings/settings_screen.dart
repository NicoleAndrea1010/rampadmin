import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/firebase_error_mapper.dart';
import '../../core/widgets/ui_components.dart';
import '../../providers/auth_providers.dart';
import '../../providers/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final user = ref.watch(currentAdminUserProvider);
    final email = user?.email ?? 'Unavailable';
    final name = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!
        : email.split('@').first;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            title: 'Settings',
            subtitle: 'Manage your administrator profile, appearance, and session-only browser sign-in.',
          ),
          const SizedBox(height: 24),
          _section(context, 'Administrator profile', Icons.person_outline, [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Signed-in administrator'),
              subtitle: Text(name),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Email address'),
              subtitle: Text(email),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Role'),
              subtitle: Text('Super Administrator'),
            ),
          ]),
          const SizedBox(height: 18),
          _section(context, 'Appearance', Icons.palette_outlined, [
            LayoutBuilder(
              builder: (context, constraints) {
                const choices = [
                  (ThemeMode.light, 'Light', Icons.light_mode),
                  (ThemeMode.dark, 'Dark', Icons.dark_mode),
                  (
                    ThemeMode.system,
                    'System preference',
                    Icons.settings_brightness,
                  ),
                ];
                if (constraints.maxWidth < 430) {
                  return DropdownButtonFormField<ThemeMode>(
                    isExpanded: true,
                    initialValue: mode,
                    decoration: const InputDecoration(labelText: 'Color theme'),
                    items: choices
                        .map(
                          (choice) => DropdownMenuItem(
                            value: choice.$1,
                            child: Text(choice.$2),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(themeModeProvider.notifier).setMode(value);
                      }
                    },
                  );
                }
                return SegmentedButton<ThemeMode>(
                  segments: choices
                      .map(
                        (choice) => ButtonSegment(
                          value: choice.$1,
                          label: Text(choice.$2),
                          icon: Icon(choice.$3),
                        ),
                      )
                      .toList(),
                  selected: {mode},
                  onSelectionChanged: (value) =>
                      ref.read(themeModeProvider.notifier).setMode(value.first),
                );
              },
            ),
          ]),
          const SizedBox(height: 18),
          _section(context, 'Tutorial & Guidance', Icons.school_outlined, [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('System Tutorial Mode'),
              subtitle: const Text(
                'Relaunch the interactive page spotlight tour for system navigation and features.',
              ),
              trailing: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Tutorial Mode activated. Select "Tutorial Mode" in the top bar on any page.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start Tour'),
              ),
            ),
          ]),
          const SizedBox(height: 18),
          _section(context, 'Security', Icons.security_outlined, [
            LayoutBuilder(
              builder: (context, constraints) {
                final reset = constraints.maxWidth < 430
                    ? OutlinedButton(
                        onPressed: () =>
                            _sendPasswordReset(context, ref, email),
                        child: const Text('Send password reset'),
                      )
                    : OutlinedButton.icon(
                        onPressed: () =>
                            _sendPasswordReset(context, ref, email),
                        icon: const Icon(Icons.password),
                        label: const Text('Send password-reset email'),
                      );
                final signOut = constraints.maxWidth < 430
                    ? OutlinedButton(
                        onPressed: () =>
                            ref.read(adminAuthServiceProvider).signOut(),
                        child: const Text('Sign out'),
                      )
                    : OutlinedButton.icon(
                        onPressed: () =>
                            ref.read(adminAuthServiceProvider).signOut(),
                        icon: const Icon(Icons.logout, color: AppColors.error),
                        label: const Text('Sign out from this browser'),
                      );
                if (constraints.maxWidth < 430) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [reset, const SizedBox(height: 10), signOut],
                  );
                }
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [reset, signOut],
                );
              },
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _sendPasswordReset(
    BuildContext context,
    WidgetRef ref,
    String email,
  ) async {
    if (email == 'Unavailable') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The signed-in account has no email.')),
      );
      return;
    }
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

  Widget _section(
    BuildContext context,
    String title,
    IconData icon,
    List<Widget> children,
  ) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 760),
    child: Card(
      child: Padding(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 400 ? 16 : 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primaryBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    ),
  );
}
