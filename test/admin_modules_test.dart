import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rampadmin/core/theme/admin_theme.dart';
import 'package:rampadmin/core/widgets/admin_sidebar.dart';
import 'package:rampadmin/features/admin_modules/admin_module_screen.dart';
import 'package:rampadmin/features/landlords/landlord_details_screen.dart';
import 'package:rampadmin/features/landlords/landlord_repository.dart';
import 'package:rampadmin/features/operations/operational_data_repository.dart';
import 'package:rampadmin/models/landlord_account.dart';
import 'package:rampadmin/providers/landlord_providers.dart';
import 'package:rampadmin/providers/operational_data_providers.dart';

import 'support/layout_test_data.dart';

void main() {
  final modules = <String, AdminModule>{
    'units': AdminModule.units,
    'tenants': AdminModule.tenants,
    'payments': AdminModule.payments,
    'maintenance': AdminModule.maintenance,
    'integrity': AdminModule.dataIntegrity,
    'health': AdminModule.syncHealth,
  };

  for (final size in [
    const Size(320, 700),
    const Size(390, 844),
    const Size(480, 844),
    const Size(768, 900),
    const Size(1024, 900),
    const Size(1280, 900),
    const Size(1440, 1000),
  ]) {
    for (final entry in modules.entries) {
      testWidgets('${entry.key} has no overflow at ${size.width}px', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_moduleApp(entry.value));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('operational modules use live records and show module columns', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_moduleApp(AdminModule.payments));
    await tester.pumpAndSettle();

    expect(find.text('Payments & Billing'), findsOneWidget);
    expect(find.text('Reference'), findsOneWidget);
    expect(find.text('PAY-1'), findsOneWidget);
    expect(find.text('No matching records'), findsNothing);
  });

  testWidgets('unsupported tenancy module explains required backend', (
    tester,
  ) async {
    await tester.pumpWidget(_moduleApp(AdminModule.tenancies));
    await tester.pumpAndSettle();

    expect(find.text('Backend support required'), findsOneWidget);
    expect(
      find.textContaining('No confirmed Supabase tenancies table'),
      findsOneWidget,
    );
  });

  testWidgets('integrity screen reports real missing tenancy references', (
    tester,
  ) async {
    await tester.pumpWidget(_moduleApp(AdminModule.dataIntegrity));
    await tester.pumpAndSettle();

    expect(find.text('Payment missing tenancyId'), findsWidgets);
    expect(find.textContaining('payments/PAY-1'), findsOneWidget);
    expect(find.textContaining('Suggested action:'), findsWidgets);
  });

  testWidgets('integrity flags ownership mismatch and orphan links', (
    tester,
  ) async {
    final records = [
      ..._records,
      const OperationalRecord(
        collection: 'units',
        id: 'UNIT-BROKEN',
        data: {
          'landlordId': 'landlord_001',
          'landlord_id': 'landlord_002',
          'tenantId': 'TEN-MISSING',
        },
      ),
    ];
    await tester.pumpWidget(
      _moduleApp(AdminModule.dataIntegrity, records: records),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ownership fields disagree'), findsOneWidget);
    expect(find.text('Unit references missing tenant'), findsOneWidget);
    expect(find.textContaining('UNIT-BROKEN'), findsWidgets);
  });

  testWidgets('unit detail links tenant, payment, and maintenance records', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_moduleApp(AdminModule.units));
    await tester.pumpAndSettle();

    await tester.tap(find.text('UNIT-1').first);
    await tester.pumpAndSettle();
    expect(find.text('Properties · UNIT-1'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.text('Linked payment history'), findsOneWidget);
    expect(find.text('Payment · PAY-1'), findsOneWidget);
    expect(find.text('Linked maintenance history'), findsOneWidget);
    expect(find.text('Ticket · TKT-1'), findsOneWidget);
  });

  testWidgets(
    'payment workspace exposes real financial summaries and filters',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(_moduleApp(AdminModule.payments));
      await tester.pumpAndSettle();

      expect(find.text('Collected'), findsOneWidget);
      expect(find.text('₱12,000.00'), findsOneWidget);
      expect(find.text('All methods'), findsOneWidget);
      expect(find.text('Maintenance Costs'), findsOneWidget);
    },
  );

  testWidgets(
    'health shows connectivity without secrets or primary inspector entry',
    (tester) async {
      await tester.pumpWidget(_moduleApp(AdminModule.syncHealth));
      await tester.pumpAndSettle();

      expect(find.text('Latest repository error'), findsOneWidget);
      expect(find.text('units'), findsOneWidget);
      expect(find.textContaining('records · connected'), findsWidgets);
      expect(find.textContaining('ANON_KEY'), findsNothing);
      expect(find.text('Raw Data Inspector'), findsNothing);
      await tester.ensureVisible(find.text('Advanced / Developer Tools'));
      await tester.tap(find.text('Advanced / Developer Tools'));
      await tester.pumpAndSettle();
      expect(find.text('Raw Data Inspector'), findsOneWidget);
    },
  );

  testWidgets('landlord detail center exposes the requested tabs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operationalDataRepositoryProvider.overrideWithValue(
            MockOperationalDataRepository(_records),
          ),
          landlordRepositoryProvider.overrideWithValue(
            _InstantLandlordRepository(layoutTestLandlords()),
          ),
        ],
        child: MaterialApp(
          theme: AdminTheme.lightTheme,
          home: const Scaffold(
            body: LandlordDetailsScreen(landlordUid: 'landlord_001'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final tab in [
      'Overview',
      'Properties',
      'Tenants',
      'Tenancies',
      'Payments',
      'Maintenance',
      'Documents',
      'Activity',
      'Settings',
    ]) {
      expect(
        find.descendant(of: find.byType(TabBar), matching: find.text(tab)),
        findsOneWidget,
      );
    }
  });

  testWidgets('sidebar shows only primary navigation destinations', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AdminTheme.lightTheme,
          home: Scaffold(
            body: AdminSidebar(currentRoute: '/dashboard', onNavigate: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OVERVIEW'), findsOneWidget);
    expect(find.text('MANAGEMENT'), findsOneWidget);
    expect(find.text('ADMINISTRATION'), findsOneWidget);
    expect(find.text('SYSTEM'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Landlords'), findsOneWidget);
    expect(find.text('Properties'), findsOneWidget);
    expect(find.text('Tenants'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
    expect(find.text('Maintenance'), findsOneWidget);
    expect(find.text('Audit & Activity'), findsOneWidget);
    expect(find.text('Data Health'), findsOneWidget);
    expect(find.text('System Health'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    for (final hidden in [
      'Tenancies',
      'Utility Rates',
      'Documents',
      'Public Listings',
      'Listing Review',
      'Inquiries',
      'Applications',
      'Admin Users',
      'Security',
      'Invitations',
      'Suspended Accounts',
      'Raw Data Inspector',
      'Audit Logs',
      'System Activity',
    ]) {
      expect(find.text(hidden), findsNothing);
    }
  });

  testWidgets('empty operational modules use compact product empty states', (
    tester,
  ) async {
    const emptyModules = {
      AdminModule.units: 'No properties yet',
      AdminModule.tenants: 'No tenants yet',
      AdminModule.payments: 'No payment records yet',
      AdminModule.maintenance: 'No maintenance requests yet',
    };
    for (final entry in emptyModules.entries) {
      await tester.pumpWidget(_moduleApp(entry.key, records: const []));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('No records match the selected filters.'), findsNothing);
    }
  });

  testWidgets('mobile operational filters open in a bottom sheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_moduleApp(AdminModule.units));
    await tester.pumpAndSettle();

    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('Sort by'), findsNothing);
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Sort by'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Sort by'), findsNothing);
  });
}

Widget _moduleApp(AdminModule module, {List<OperationalRecord>? records}) =>
    ProviderScope(
      overrides: [
        operationalDataRepositoryProvider.overrideWithValue(
          MockOperationalDataRepository(records ?? _records),
        ),
        landlordRepositoryProvider.overrideWithValue(
          _InstantLandlordRepository(layoutTestLandlords()),
        ),
      ],
      child: MaterialApp(
        theme: AdminTheme.lightTheme,
        home: Scaffold(body: AdminModuleScreen(module: module)),
      ),
    );

final _records = <OperationalRecord>[
  const OperationalRecord(
    collection: 'units',
    id: 'UNIT-1',
    data: {
      'landlordId': 'landlord_001',
      'unitNumber': '1A',
      'status': 'Occupied',
      'monthlyRent': 12000,
      'tenantId': 'TEN-1',
      'tenantName': 'A. Tenant',
    },
  ),
  const OperationalRecord(
    collection: 'tenants',
    id: 'TEN-1',
    data: {
      'landlordId': 'landlord_001',
      'unitId': 'UNIT-1',
      'name': 'A. Tenant',
      'status': 'Active',
      'balance': 0,
    },
  ),
  const OperationalRecord(
    collection: 'payments',
    id: 'PAY-1',
    data: {
      'landlordId': 'landlord_001',
      'tenantId': 'TEN-1',
      'unitId': 'UNIT-1',
      'referenceNumber': 'PAY-1',
      'amount': 12000,
      'transactionType': 'Rent',
      'status': 'Paid',
      'billingMonth': '2026-10',
      'paymentMethod': 'Bank Transfer',
    },
  ),
  const OperationalRecord(
    collection: 'payments',
    id: 'PAY-2',
    data: {
      'landlordId': 'landlord_001',
      'tenantId': 'TEN-1',
      'unitId': 'UNIT-1',
      'referenceNumber': 'PAY-2',
      'amount': 5000,
      'transactionType': 'Rent',
      'status': 'Pending',
      'billingMonth': '2026-10',
      'paymentMethod': 'Cash',
    },
  ),
  const OperationalRecord(
    collection: 'maintenanceTickets',
    id: 'TKT-1',
    data: {
      'landlordId': 'landlord_001',
      'tenantId': 'TEN-1',
      'unitId': 'UNIT-1',
      'title': 'Repair',
      'priority': 'High',
      'status': 'Pending',
    },
  ),
];

class _InstantLandlordRepository extends MockLandlordRepository {
  _InstantLandlordRepository([super.initialItems])
    : _items = initialItems ?? const [];

  final List<LandlordAccount> _items;

  @override
  Future<List<LandlordAccount>> getLandlords() async => _items;

  @override
  Future<LandlordAccount?> getLandlord(String uid) async =>
      _items.where((item) => item.uid == uid).firstOrNull;
}
