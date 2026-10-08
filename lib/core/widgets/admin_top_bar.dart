import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_providers.dart';
import '../../providers/landlord_providers.dart';
import '../constants/admin_routes.dart';
import '../theme/app_colors.dart';
import 'ui_components.dart';

final _tourTitleKey = GlobalKey();
final _tourSearchKey = GlobalKey();
final _tourHelpKey = GlobalKey();

class AdminTopBar extends ConsumerWidget {
  const AdminTopBar({
    super.key,
    required this.title,
    required this.mobile,
    required this.onMenu,
  });
  final String title;
  final bool mobile;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    height: 76,
    padding: EdgeInsets.symmetric(horizontal: mobile ? 16 : 28),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Row(
      children: [
        if (mobile)
          Tooltip(
            message: 'Open navigation',
            child: IconButton(onPressed: onMenu, icon: const Icon(Icons.menu)),
          ),
        if (mobile) const SizedBox(width: 4),
        Expanded(
          child: Text(
            key: _tourTitleKey,
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
        ),
        if (!mobile)
          SizedBox(
            width: 260,
            height: 43,
            child: TextField(
              key: _tourSearchKey,
              onSubmitted: (value) {
                ref
                    .read(landlordFiltersProvider.notifier)
                    .set(LandlordFilters(query: value));
                context.go(AdminRoutes.landlords);
              },
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Search landlords',
                contentPadding: EdgeInsets.zero,
              ),
            ),
          )
        else
          Tooltip(
            message: 'Search landlords',
            child: IconButton(
              key: _tourSearchKey,
              onPressed: () => context.go(AdminRoutes.landlords),
              icon: const Icon(Icons.search),
            ),
          ),
        SizedBox(width: mobile ? 4 : 8),
        Tooltip(
          message: 'Help & Page Guide',
          child: IconButton(
            key: _tourHelpKey,
            onPressed: () => _showHelp(context),
            icon: const Icon(Icons.help_outline),
          ),
        ),
        SizedBox(width: mobile ? 4 : 8),
        Badge(
          smallSize: 8,
          child: Tooltip(
            message: 'Notifications',
            child: IconButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('You have no new notifications.')),
              ),
              icon: const Icon(Icons.notifications_none),
            ),
          ),
        ),
        SizedBox(width: mobile ? 4 : 8),
        PopupMenuButton<String>(
          tooltip: 'Administrator menu',
          onSelected: (value) async {
            if (value == 'settings') context.go(AdminRoutes.settings);
            if (value == 'signout') {
              await ref.read(adminAuthServiceProvider).signOut();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'settings', child: Text('Settings')),
            PopupMenuItem(value: 'signout', child: Text('Sign out')),
          ],
          child: LandlordAvatar(
            name:
                ref.watch(currentAdminUserProvider)?.displayName ??
                ref.watch(currentAdminUserProvider)?.email ??
                'Administrator',
            radius: 19,
          ),
        ),
      ],
    ),
  );

  void _showHelp(BuildContext context) {
    final steps = switch (title) {
      'Dashboard' => [
        _TourStep(
          _tourTitleKey,
          'Dashboard overview',
          'Start here for account totals, portfolio activity, and monthly paid revenue.',
        ),
        _TourStep(
          _tourSearchKey,
          'Find a landlord',
          'Search landlords by name, company, or email. Selecting search opens the landlord directory.',
        ),
        _TourStep(
          _tourHelpKey,
          'Page guide',
          'Use this guide whenever you need a quick tour of the current page.',
        ),
      ],
      'Landlords' => [
        _TourStep(
          _tourTitleKey,
          'Landlord directory',
          'Open a landlord to review their profile, linked units, tenants, payment history, and activity.',
        ),
        _TourStep(
          _tourSearchKey,
          'Search landlords',
          'Search by name, company, or email. Use the directory filters to narrow status or change sorting.',
        ),
        _TourStep(
          _tourHelpKey,
          'Manage accounts',
          'Use Add landlord or a row action to create, edit, activate, suspend, reset access, or archive an account.',
        ),
      ],
      'RAMP Data' => [
        _TourStep(
          _tourTitleKey,
          'Operational records',
          'This page shows current records from the property app. Record ownership is not guessed when a landlord link is absent.',
        ),
        _TourStep(
          _tourHelpKey,
          'Search and filter',
          'Use the page controls to search, filter by collection, status, or category, and sort records.',
        ),
        _TourStep(
          _tourTitleKey,
          'Inspect a record',
          'Select a record to see its saved fields. This monitor does not edit payment or tenant source records.',
        ),
      ],
      'Admin Activity' => [
        _TourStep(
          _tourTitleKey,
          'Audit history',
          'Review the administrator actions recorded for landlord account management.',
        ),
        _TourStep(
          _tourHelpKey,
          'Narrow the results',
          'Search and filter by action, administrator, landlord, and date range.',
        ),
        _TourStep(
          _tourTitleKey,
          'Review details',
          'Use the description and reason fields to understand each account action.',
        ),
      ],
      'Settings' => [
        _TourStep(
          _tourTitleKey,
          'Administrator settings',
          'Confirm which signed-in administrator is using this browser session.',
        ),
        _TourStep(
          _tourHelpKey,
          'Appearance and access',
          'Choose a theme, request a password reset, or sign out. Web authentication is session-scoped.',
        ),
        _TourStep(
          _tourTitleKey,
          'Security',
          'Never share account credentials. Sensitive landlord operations are authorized and rate-limited server-side.',
        ),
      ],
      _ => [
        _TourStep(
          _tourTitleKey,
          'Landlord profile',
          'Review profile information, account status, linked portfolio records, and payments.',
        ),
        _TourStep(
          _tourHelpKey,
          'Account actions',
          'Edit profile details or use account actions. Status changes and archiving require confirmation.',
        ),
        _TourStep(
          _tourTitleKey,
          'Portfolio tabs',
          'Units, incoming tenants, maintenance, and payments show saved records linked to this landlord.',
        ),
      ],
    };
    _AdminPageTour.show(context, title, steps);
  }
}

class _TourStep {
  const _TourStep(this.target, this.heading, this.description);

  final GlobalKey target;
  final String heading;
  final String description;
}

abstract final class _AdminPageTour {
  static void show(
    BuildContext context,
    String pageTitle,
    List<_TourStep> steps,
  ) {
    final overlay = Overlay.of(context, rootOverlay: true);
    var index = 0;
    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (overlayContext) {
        final targetContext = steps[index].target.currentContext;
        if (targetContext == null) return const SizedBox.shrink();
        final targetBox = targetContext.findRenderObject() as RenderBox?;
        final overlayBox =
            Overlay.of(
                  overlayContext,
                  rootOverlay: true,
                ).context.findRenderObject()
                as RenderBox?;
        if (targetBox == null || overlayBox == null || !targetBox.hasSize) {
          return const SizedBox.shrink();
        }
        final targetOrigin = targetBox.localToGlobal(
          Offset.zero,
          ancestor: overlayBox,
        );
        final targetRect = targetOrigin & targetBox.size;
        final screen = MediaQuery.sizeOf(overlayContext);
        final cardWidth = (screen.width - 32).clamp(240.0, 420.0);
        final left = (targetRect.center.dx - cardWidth / 2).clamp(
          16.0,
          screen.width - cardWidth - 16,
        );
        final top = (targetRect.bottom + 26).clamp(90.0, screen.height - 220);
        final step = steps[index];
        return Positioned.fill(
          child: Stack(
            children: [
              CustomPaint(
                size: screen,
                painter: _TourSpotlightPainter(targetRect),
              ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                ),
              ),
              Positioned(
                left: left,
                top: top,
                width: cardWidth,
                child: Material(
                  elevation: 16,
                  color: Theme.of(overlayContext).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.arrow_upward_rounded,
                              color: AppColors.primaryBlue,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$pageTitle · ${index + 1} of ${steps.length}',
                                style: Theme.of(overlayContext)
                                    .textTheme
                                    .labelMedium,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close guide',
                              onPressed: entry.remove,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        Text(
                          step.heading,
                          style: Theme.of(overlayContext).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(step.description),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (index > 0)
                              TextButton(
                                onPressed: () {
                                  index--;
                                  entry.markNeedsBuild();
                                },
                                child: const Text('Back'),
                              ),
                            ElevatedButton.icon(
                              onPressed: () {
                                if (index == steps.length - 1) {
                                  entry.remove();
                                } else {
                                  index++;
                                  entry.markNeedsBuild();
                                }
                              },
                              icon: Icon(
                                index == steps.length - 1
                                    ? Icons.check
                                    : Icons.arrow_forward,
                              ),
                              label: Text(
                                index == steps.length - 1 ? 'Done' : 'Next',
                              ),
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
      },
    );
    overlay.insert(entry);
  }
}

class _TourSpotlightPainter extends CustomPainter {
  const _TourSpotlightPainter(this.targetRect);

  final Rect targetRect;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    canvas.saveLayer(area, Paint());
    canvas.drawRect(area, Paint()..color = Colors.black.withAlpha(190));
    canvas.drawRRect(
      RRect.fromRectAndRadius(targetRect.inflate(8), const Radius.circular(12)),
      Paint()..blendMode = BlendMode.clear,
    );
    canvas.restore();

    final start = Offset(targetRect.center.dx, targetRect.bottom + 26);
    final end = Offset(targetRect.center.dx, targetRect.bottom + 6);
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawLine(start, end, paint);
    canvas.drawLine(end, end + const Offset(-6, 7), paint);
    canvas.drawLine(end, end + const Offset(6, 7), paint);
  }

  @override
  bool shouldRepaint(_TourSpotlightPainter oldDelegate) =>
      oldDelegate.targetRect != targetRect;
}
