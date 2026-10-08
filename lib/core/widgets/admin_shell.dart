import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/admin_routes.dart';
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
    if (currentRoute == AdminRoutes.settings) return 'Settings';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, constraints) {
      final mobile = constraints.maxWidth < 700;
      final compact =
          constraints.maxWidth >= 700 && constraints.maxWidth < 1200;
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
                  currentRoute: currentRoute,
                  onNavigate: navigate,
              ),
            Expanded(
              child: Column(
                children: [
                  AdminTopBar(
                    title: title,
                    mobile: mobile,
                    onMenu: () => scaffoldKey.currentState?.openDrawer(),
                  ),
                  Expanded(
                            color: Theme.of(context).scaffoldBackgroundColor,
                          child: ConstrainedBox(
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
      );
    },
  );
}
