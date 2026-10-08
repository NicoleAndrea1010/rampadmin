import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rampadmin/core/theme/admin_theme.dart';
import 'package:rampadmin/features/activity/admin_activity_repository.dart';
import 'package:rampadmin/features/dashboard/dashboard_screen.dart';
import 'package:rampadmin/features/dashboard/dashboard_repository.dart';
import 'package:rampadmin/features/landlords/landlord_list_screen.dart';
import 'package:rampadmin/features/landlords/landlord_repository.dart';
import 'package:rampadmin/providers/activity_providers.dart';
import 'package:rampadmin/providers/dashboard_providers.dart';
import 'package:rampadmin/providers/landlord_providers.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(1024, 900),
    const Size(1440, 1000),
  ]) {
    testWidgets('dashboard renders without overflow at ${size.width}px', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            landlordRepositoryProvider.overrideWithValue(
              MockLandlordRepository(),
            ),
            dashboardRepositoryProvider.overrideWithValue(
              MockDashboardRepository(),
            ),
            activityRepositoryProvider.overrideWithValue(
              MockAdminActivityRepository(),
            ),
          ],
          child: MaterialApp(
            theme: AdminTheme.lightTheme,
            home: const Scaffold(body: DashboardScreen()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.takeException(), isNull);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Live Database'), findsOneWidget);
    });
  }

  testWidgets('landlord list uses a mobile-safe card layout', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          landlordRepositoryProvider.overrideWithValue(
            MockLandlordRepository(),
          ),
          dashboardRepositoryProvider.overrideWithValue(
            MockDashboardRepository(),
          ),
          activityRepositoryProvider.overrideWithValue(
            MockAdminActivityRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AdminTheme.lightTheme,
          home: const Scaffold(body: LandlordListScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
    expect(find.text('Landlords'), findsOneWidget);
  });
}
