import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../constants/admin_routes.dart';
import '../theme/app_colors.dart';
import 'ui_components.dart';

class AdminSidebar extends ConsumerWidget {
  const AdminSidebar({
    super.key,
    required this.currentRoute,
    required this.onNavigate,
    this.isCompact = false,
  });
  final String currentRoute;
  final ValueChanged<String> onNavigate;
  final bool isCompact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentAdminUserProvider);
    final name = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!
        : user?.email?.split('@').first ?? 'Administrator';
    return Container(
      width: isCompact ? 84 : 248,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 18 : 22,
                vertical: 24,
              ),
              child: Row(
                mainAxisAlignment: isCompact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.apartment_rounded,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  if (!isCompact) ...[
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RAMP',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          'SUPER ADMIN',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            letterSpacing: .8,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _group('OVERVIEW', [
                    _Item(
                      'Dashboard',
                      Icons.dashboard_outlined,
                      AdminRoutes.dashboard,
                    ),
                  ]),
                  _group('MANAGEMENT', [
                    _Item(
                      'Landlords',
                      Icons.apartment_outlined,
                      AdminRoutes.landlords,
                    ),
                    _Item(
                      'RAMP Data',
                      Icons.storage_outlined,
                      AdminRoutes.operations,
                    ),
                  ]),
                  _group('MONITORING', [
                    _Item(
                      'Admin Activity',
                      Icons.history_rounded,
                      AdminRoutes.activity,
                    ),
                  ]),
                  _group('SYSTEM', [
                    _Item(
                      'Settings',
                      Icons.settings_outlined,
                      AdminRoutes.settings,
                    ),
                  ]),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                padding: EdgeInsets.all(isCompact ? 10 : 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    LandlordAvatar(name: name, radius: 18),
                    if (!isCompact) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Text(
                              'Super Administrator',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Tooltip(
                        message: 'Sign out',
                        child: IconButton(
                          onPressed: () =>
                              ref.read(adminAuthServiceProvider).signOut(),
                          icon: const Icon(Icons.logout, size: 20),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _group(String label, List<_Item> items) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isCompact)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 7),
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: .7,
              ),
            ),
          ),
        ...items.map(_nav),
      ],
    ),
  );

  Widget _nav(_Item item) {
    final selected = item.route == AdminRoutes.landlords
        ? currentRoute.startsWith('/landlords')
        : item.route == AdminRoutes.operations
        ? currentRoute.startsWith(AdminRoutes.operations)
        : currentRoute == item.route;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Tooltip(
        message: isCompact ? item.label : '',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: () => onNavigate(item.route),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 18 : 13,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: selected ? AppColors.primaryTint : Colors.transparent,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                mainAxisAlignment: isCompact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Icon(
                    item.icon,
                    size: 21,
                    color: selected
                        ? AppColors.primaryBlue
                        : AppColors.textSecondary,
                  ),
                  if (!isCompact) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selected ? AppColors.primaryBlue : null,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Item {
  const _Item(this.label, this.icon, this.route);
  final String label;
  final IconData icon;
  final String route;
}
