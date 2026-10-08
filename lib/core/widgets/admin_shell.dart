import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/settings_providers.dart';
import '../constants/admin_routes.dart';
import '../theme/app_colors.dart';
import '../../features/admin_modules/admin_module_screen.dart';
import 'admin_sidebar.dart';
import 'admin_top_bar.dart';

class AdminShell extends ConsumerWidget {
  const AdminShell({
    super.key,
    required this.currentRoute,
    required this.child,
  });
  final String currentRoute;
  final Widget child;

  String get title {
    if (currentRoute == AdminRoutes.landlords) return 'Landlords';
    if (currentRoute == AdminRoutes.landlordNew) return 'Add Landlord';
    if (currentRoute.endsWith('/edit')) return 'Edit Landlord';
    if (currentRoute.startsWith('/landlords/')) return 'Landlord Details';
    if (currentRoute == AdminRoutes.operations) return 'Raw Data Inspector';
    if (currentRoute == AdminRoutes.activity ||
        currentRoute == AdminRoutes.auditLogs) {
      return 'Audit & Activity';
    }
    if (currentRoute == AdminRoutes.settings) return 'Settings';
    if (currentRoute == AdminRoutes.profile) return 'Profile';
    return adminModuleTitle(currentRoute);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, constraints) {
      final mobile = constraints.maxWidth < 700;
      final compact =
          constraints.maxWidth >= 700 && constraints.maxWidth < 1200;
      final collapsed = ref.watch(sidebarCollapsedProvider);
      final reduceMotion =
          ref.watch(reducedMotionProvider) ||
          MediaQuery.disableAnimationsOf(context);
      final scaffoldKey = GlobalKey<ScaffoldState>();
      void navigate(String route) => context.go(route);
      return Scaffold(
        key: scaffoldKey,
        drawer: mobile
            ? Drawer(
                child: AdminSidebar(
                  currentRoute: currentRoute,
                  onNavigate: (route) {
                    Navigator.pop(context);
                    navigate(route);
                  },
                ),
              )
            : null,
        body: Row(
          children: [
            if (!mobile)
              AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: compact || collapsed ? 82 : 260,
                child: AdminSidebar(
                  currentRoute: currentRoute,
                  onNavigate: navigate,
                  isCompact: compact || collapsed,
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  AdminTopBar(
                    title: title,
                    mobile: mobile,
                    onMenu: () => scaffoldKey.currentState?.openDrawer(),
                    onToggleSidebar: !mobile && !compact
                        ? () => ref
                              .read(sidebarCollapsedProvider.notifier)
                              .toggle()
                        : null,
                    sidebarCollapsed: collapsed,
                  ),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            gradient:
                                Theme.of(context).brightness == Brightness.light
                                ? const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFF5F8FD),
                                      Color(0xFFF2F5FA),
                                    ],
                                  )
                                : null,
                          ),
                        ),
                        const Positioned(
                          top: -150,
                          right: -120,
                          child: IgnorePointer(child: _AmbientGlow()),
                        ),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1450),
                            child: AnimatedSwitcher(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              transitionBuilder: (page, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, .015),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: page,
                                    ),
                                  ),
                              child: KeyedSubtree(
                                key: ValueKey(currentRoute),
                                child: child,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow();

  @override
  Widget build(BuildContext context) => Container(
    width: 360,
    height: 360,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [
          AppColors.primaryBlue.withAlpha(
            Theme.of(context).brightness == Brightness.light ? 12 : 8,
          ),
          Colors.transparent,
        ],
      ),
    ),
  );
}
