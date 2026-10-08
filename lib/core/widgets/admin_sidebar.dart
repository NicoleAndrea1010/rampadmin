import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/admin_routes.dart';
import '../theme/app_colors.dart';
import '../../providers/settings_providers.dart';
import 'admin_account_menu.dart';

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
    final reduceMotion =
        ref.watch(reducedMotionProvider) ||
        MediaQuery.disableAnimationsOf(context);
    return Container(
      width: isCompact ? 82 : 260,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.light
            ? const Color(0xFFF8FAFE)
            : Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).dividerColor.withAlpha(180),
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(isCompact ? 12 : 18, 18, 12, 20),
              child: Row(
                mainAxisAlignment: isCompact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primaryBlue, Color(0xFF4C8CFF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryBlue.withAlpha(28),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.apartment_rounded,
                      color: Colors.white,
                    ),
                  ),
                  if (!isCompact) ...[
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
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
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              letterSpacing: .8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _group(context, 'OVERVIEW', reduceMotion, [
                    _Item(
                      'Dashboard',
                      Icons.dashboard_outlined,
                      AdminRoutes.dashboard,
                    ),
                  ]),
                  _group(context, 'MANAGEMENT', reduceMotion, [
                    _Item(
                      'Landlords',
                      Icons.apartment_outlined,
                      AdminRoutes.landlords,
                    ),
                    _Item(
                      'Properties',
                      Icons.domain_outlined,
                      AdminRoutes.units,
                    ),
                    _Item('Tenants', Icons.people_outline, AdminRoutes.tenants),
                    _Item(
                      'Payments',
                      Icons.payments_outlined,
                      AdminRoutes.payments,
                    ),
                    _Item(
                      'Maintenance',
                      Icons.build_outlined,
                      AdminRoutes.maintenance,
                    ),
                  ]),
                  _group(context, 'ADMINISTRATION', reduceMotion, [
                    _Item(
                      'Audit & Activity',
                      Icons.receipt_long_outlined,
                      AdminRoutes.activity,
                    ),
                    _Item(
                      'Data Health',
                      Icons.rule_outlined,
                      AdminRoutes.dataIntegrity,
                    ),
                    _Item(
                      'System Health',
                      Icons.monitor_heart_outlined,
                      AdminRoutes.syncHealth,
                    ),
                  ]),
                  _group(context, 'SYSTEM', reduceMotion, [
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
              padding: EdgeInsets.fromLTRB(isCompact ? 12 : 14, 8, 12, 12),
              child: AdminIdentity(compact: isCompact),
            ),
          ],
        ),
      ),
    );
  }

  Widget _group(
    BuildContext context,
    String label,
    bool reduceMotion,
    List<_Item> items,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isCompact)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: .7,
              ),
            ),
          ),
        ...items.map((item) => _nav(context, item, reduceMotion)),
      ],
    ),
  );

  Widget _nav(BuildContext context, _Item item, bool reduceMotion) {
    final selected =
        currentRoute == item.route ||
        (item.route == AdminRoutes.landlords &&
            currentRoute.startsWith('/landlords'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: _SidebarNavigationTile(
        item: item,
        selected: selected,
        compact: isCompact,
        reduceMotion: reduceMotion,
        onTap: () => onNavigate(item.route),
      ),
    );
  }
}

class _SidebarNavigationTile extends StatefulWidget {
  const _SidebarNavigationTile({
    required this.item,
    required this.selected,
    required this.compact,
    required this.reduceMotion,
    required this.onTap,
  });
  final _Item item;
  final bool selected;
  final bool compact;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  State<_SidebarNavigationTile> createState() => _SidebarNavigationTileState();
}

class _SidebarNavigationTileState extends State<_SidebarNavigationTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).colorScheme.primary;
    final background = widget.selected
        ? selectedColor.withAlpha(
            Theme.of(context).brightness == Brightness.dark ? 35 : 16,
          )
        : _hovered
        ? Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(110)
        : Colors.transparent;
    return Tooltip(
      message: widget.compact ? widget.item.label : '',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: widget.reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              constraints: const BoxConstraints(minHeight: 42),
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 14 : 13,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: widget.compact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  AnimatedScale(
                    scale: widget.selected || _hovered ? 1.05 : 1,
                    duration: widget.reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 150),
                    child: Icon(
                      widget.item.icon,
                      size: 20,
                      color: widget.selected
                          ? selectedColor
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (!widget.compact) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: widget.selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: widget.selected ? selectedColor : null,
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
