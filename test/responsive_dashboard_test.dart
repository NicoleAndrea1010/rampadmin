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

import 'support/layout_test_data.dart';

void main() {
  for (final size in [
    const Size(320, 700),
    const Size(390, 844),
    const Size(480, 844),
    const Size(768, 900),
    const Size(1024, 900),
    const Size(1280, 900),
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
              MockLandlordRepository(layoutTestLandlords()),
            ),
            dashboardRepositoryProvider.overrideWithValue(
              MockDashboardRepository(),
            ),
            activityRepositoryProvider.overrideWithValue(
              MockAdminActivityRepository(layoutTestActivities()),
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
      expect(find.text('Live Data'), findsOneWidget);
    });
  }

  testWidgets('dashboard presents consolidated operational sections', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          landlordRepositoryProvider.overrideWithValue(
            MockLandlordRepository(layoutTestLandlords()),
          ),
          dashboardRepositoryProvider.overrideWithValue(
            _DashboardFixtureRepository(),
          ),
          activityRepositoryProvider.overrideWithValue(
            MockAdminActivityRepository(layoutTestActivities()),
          ),
        ],
        child: MaterialApp(
          theme: AdminTheme.lightTheme,
          home: const Scaffold(body: DashboardScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Landlords'), findsOneWidget);
    expect(find.text('Properties'), findsOneWidget);
    expect(find.text('Tenants'), findsOneWidget);
    expect(find.text('Collected This Month'), findsOneWidget);
    expect(find.text('Portfolio'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
    expect(find.text('Maintenance'), findsOneWidget);
    expect(find.text('Account Status'), findsOneWidget);
    expect(find.text('Attention Required'), findsOneWidget);
    expect(find.text('Archived Units'), findsNothing);
    expect(find.text('Orphan Tenants'), findsNothing);
    expect(find.text('No payment history yet'), findsOneWidget);
    expect(find.text('No revenue data'), findsNothing);
  });

  testWidgets('dashboard keeps exactly four primary KPI values', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          landlordRepositoryProvider.overrideWithValue(
            MockLandlordRepository(layoutTestLandlords()),
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
    await tester.pumpAndSettle();

    expect(find.text('Landlords'), findsOneWidget);
    expect(find.text('Properties'), findsOneWidget);
    expect(find.text('Tenants'), findsOneWidget);
    expect(find.text('Collected This Month'), findsOneWidget);
    expect(find.text('Active Accounts'), findsNothing);
    expect(find.text('No properties synced yet'), findsOneWidget);
    expect(find.text('Occupancy'), findsNothing);
    expect(find.text('Vacant'), findsNothing);
    expect(find.text('Reserved'), findsNothing);
    expect(find.text('Occupancy Rate'), findsNothing);
  });

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

class _DashboardFixtureRepository implements DashboardRepository {
  @override
  Future<DashboardData> getSummary() async => const DashboardData(
    growth: {},
    monthlyRevenue: {},
    managedUnits: 4,
    registeredTenants: 3,
    openMaintenance: 2,
    highPriorityMaintenance: 1,
    unitsByStatus: {'Occupied': 2, 'Vacant': 1, 'Reserved': 0},
    paymentsByStatus: {'Paid': 2, 'Overdue': 1},
    maintenanceByStatus: {'Pending': 2},
    outstandingPayments: 100,
    overduePayments: 200,
    paymentBalancesAvailable: true,
    maintenanceExpenses: 50,
    slaBreaches: null,
    missingLandlordId: 1,
    orphanRelationships: 2,
    paymentsMissingTenancy: 1,
    ownershipMismatches: 0,
    awaitingEstimate: 0,
    completedMaintenanceThisMonth: null,
    maintenanceMissingUnitId: 0,
    archivedUnits: 1,
    awaitingVisit: 1,
    scheduledRepair: 0,
    orphanTenants: 1,
    orphanUnits: 1,
    unknownUnitStatuses: 0,
  );
}
