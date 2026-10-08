import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rampadmin/core/theme/admin_theme.dart';
import 'package:rampadmin/core/widgets/admin_shell.dart';
import 'package:rampadmin/features/activity/admin_activity_screen.dart';
import 'package:rampadmin/features/activity/admin_activity_repository.dart';
import 'package:rampadmin/features/dashboard/dashboard_screen.dart';
import 'package:rampadmin/features/dashboard/dashboard_repository.dart';
import 'package:rampadmin/features/landlords/landlord_details_screen.dart';
import 'package:rampadmin/features/landlords/landlord_form_screen.dart';
import 'package:rampadmin/features/landlords/landlord_list_screen.dart';
import 'package:rampadmin/features/landlords/landlord_repository.dart';
import 'package:rampadmin/features/operations/operational_data_screen.dart';
import 'package:rampadmin/features/settings/settings_screen.dart';
import 'package:rampadmin/providers/activity_providers.dart';
import 'package:rampadmin/providers/dashboard_providers.dart';
import 'package:rampadmin/providers/landlord_providers.dart';
import 'package:rampadmin/providers/operational_data_providers.dart';

void main() {
  final screens = <String, Widget>{
    'dashboard': const DashboardScreen(),
    'landlords': const LandlordListScreen(),
    'add landlord': const LandlordFormScreen(),
    'edit landlord': const LandlordFormScreen(landlordUid: 'landlord_001'),
    'landlord details': const LandlordDetailsScreen(
      landlordUid: 'landlord_001',
    ),
    'RAMP data': const OperationalDataScreen(),
    'activity': const AdminActivityScreen(),
    'settings': const SettingsScreen(),
  };
  for (final size in [
    const Size(320, 700),
    const Size(390, 844),
    const Size(768, 900),
  ]) {
    for (final entry in screens.entries) {
      testWidgets('${entry.key} has no layout exception at ${size.width}px', (
        tester,
      ) async {
        final reported = <FlutterErrorDetails>[];
        final previousOnError = FlutterError.onError;
        FlutterError.onError = reported.add;
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) =>
                  AdminShell(currentRoute: '/', child: entry.value),
            ),
            GoRoute(path: '/landlords', builder: (_, _) => const Scaffold()),
            GoRoute(
              path: '/landlords/new',
              builder: (_, _) => const Scaffold(),
            ),
            GoRoute(
              path: '/landlords/:uid',
              builder: (_, _) => const Scaffold(),
            ),
            GoRoute(
              path: '/landlords/:uid/edit',
              builder: (_, _) => const Scaffold(),
            ),
            GoRoute(path: '/activity', builder: (_, _) => const Scaffold()),
            GoRoute(path: '/operations', builder: (_, _) => const Scaffold()),
            GoRoute(path: '/settings', builder: (_, _) => const Scaffold()),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              landlordRepositoryProvider.overrideWithValue(
              ),
              dashboardRepositoryProvider.overrideWithValue(
                MockDashboardRepository(),
              ),
              activityRepositoryProvider.overrideWithValue(
              ),
              operationalDataRepositoryProvider.overrideWithValue(
              ),
            ],
            child: MaterialApp.router(
              theme: AdminTheme.lightTheme,
              routerConfig: router,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump(const Duration(milliseconds: 300));
        FlutterError.onError = previousOnError;
        tester.takeException();
        if (reported.isNotEmpty) {
          fail(reported.map((error) => error.toString()).join('\n'));
        }
      });
    }
  }
}
