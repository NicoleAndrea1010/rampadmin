import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_providers.dart';
import '../constants/admin_routes.dart';
import 'ui_components.dart';

class AdminProfileButton extends ConsumerWidget {
  const AdminProfileButton({super.key, this.radius = 19});
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentAdminUserProvider);
    final email = user?.email ?? 'Administrator';
    final displayName = user?.displayName?.trim();
    final name = displayName?.isNotEmpty == true
        ? displayName!
        : email.split('@').first;

    return IconButton(
      tooltip: 'View administrator profile',
      onPressed: () => context.go(AdminRoutes.profile),
      padding: const EdgeInsets.all(3),
      icon: LandlordAvatar(name: name, radius: radius),
    );
  }
}

class AdminIdentity extends ConsumerWidget {
  const AdminIdentity({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentAdminUserProvider);
    final email = user?.email ?? 'Administrator';
    final displayName = user?.displayName?.trim();
    final name = displayName?.isNotEmpty == true
        ? displayName!
        : email.split('@').first;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 10, vertical: 8),
      child: Row(
        mainAxisAlignment: compact
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          LandlordAvatar(name: name, radius: 17),
          if (!compact) ...[
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Super Administrator',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
