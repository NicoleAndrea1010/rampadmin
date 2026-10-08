import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/admin_routes.dart';
import '../theme/app_colors.dart';

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
    return Container(
      decoration: BoxDecoration(
        border: Border(
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              child: Row(
                mainAxisAlignment: isCompact
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                    ),
                    child: const Icon(
                      Icons.apartment_rounded,
                    ),
                  ),
                  if (!isCompact) ...[
                    const SizedBox(width: 12),
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
                    _Item(
                      'Dashboard',
                      Icons.dashboard_outlined,
                      AdminRoutes.dashboard,
                    ),
                  ]),
                    _Item(
                      'Landlords',
                      Icons.apartment_outlined,
                      AdminRoutes.landlords,
                    ),
                    _Item(
                    ),
                    _Item(
                      AdminRoutes.activity,
                    ),
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
            ),
          ],
        ),
      ),
    );
  }

    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isCompact)
          Padding(
            child: Text(
              label,
                fontWeight: FontWeight.w600,
                letterSpacing: .7,
              ),
            ),
          ),
      ],
    ),
  );

    return Padding(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            child: AnimatedContainer(
              padding: EdgeInsets.symmetric(
              ),
              decoration: BoxDecoration(
              ),
              child: Row(
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                              ? FontWeight.w600
                              : FontWeight.w400,
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
