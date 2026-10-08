import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/ui_components.dart';
import '../../providers/settings_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final narrow = MediaQuery.sizeOf(context).width < 880;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 400
                ? 16
                : MediaQuery.sizeOf(context).width < 700
                ? 20
                : 28,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(
                title: 'Settings',
                subtitle: 'Personalize the workspace and interface behavior.',
              ),
              const SizedBox(height: 24),
              if (narrow)
                _appearance(context, ref, mode)
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _appearance(context, ref, mode)),
                    const SizedBox(width: 20),
                    Expanded(child: _guidance(context)),
                  ],
                ),
              if (narrow) ...[const SizedBox(height: 18), _guidance(context)],
            ],
          ),
        ),
      ),
    );
  }

  Widget _appearance(BuildContext context, WidgetRef ref, ThemeMode mode) =>
      _section(context, 'Appearance', Icons.palette_outlined, [
        LayoutBuilder(
          builder: (context, constraints) {
            const choices = [
              (ThemeMode.light, 'Light', Icons.light_mode_outlined),
              (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
              (ThemeMode.system, 'System', Icons.settings_brightness_outlined),
            ];
            if (constraints.maxWidth < 440) {
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
      ]);

  Widget _guidance(BuildContext context) =>
      _section(context, 'Guidance', Icons.help_outline_rounded, [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.lightbulb_outline_rounded,
              color: AppColors.primaryBlue,
            ),
          ),
          title: const Text('Page guides'),
          subtitle: const Text(
            'Use the help button in the page header for contextual guidance.',
          ),
        ),
      ]);

  Widget _section(
    BuildContext context,
    String title,
    IconData icon,
    List<Widget> children,
  ) => Card(
    child: Padding(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 400 ? 18 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 22),
          ...children,
        ],
      ),
    ),
  );
}
