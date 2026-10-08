import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rampadmin/core/theme/admin_theme.dart';
import 'package:rampadmin/features/operations/operational_data_repository.dart';
import 'package:rampadmin/features/operations/operational_data_screen.dart';
import 'package:rampadmin/providers/operational_data_providers.dart';

void main() {
  test('operational record resolves both current and legacy owner fields', () {
    const current = OperationalRecord(
      collection: 'units',
      id: 'unit-1',
      data: {'landlordId': 'landlord-current', 'status': 'Occupied'},
    );
    const legacy = OperationalRecord(
      collection: 'payments',
      id: 'payment-1',
      data: {'landlord_id': 'landlord-legacy', 'status': 'Paid'},
    );
    const unassigned = OperationalRecord(
      collection: 'maintenanceTickets',
      id: 'ticket-1',
      data: {'status': 'Open'},
    );

    expect(current.ownerId, 'landlord-current');
    expect(current.status, 'Occupied');
    expect(legacy.ownerId, 'landlord-legacy');
    expect(unassigned.ownerId, isEmpty);

    const inconsistent = OperationalRecord(
      collection: 'units',
      id: 'unit-inconsistent',
      data: {
        'landlordId': 'landlord-current',
        'landlord_id': 'landlord-legacy',
      },
    );
    expect(inconsistent.hasConflictingOwnerIds, isTrue);
    expect(inconsistent.ownerId, isEmpty);
    expect(
      inconsistent.ownerIds,
      containsAll(['landlord-current', 'landlord-legacy']),
    );
    expect(inconsistent.ownerDescription, contains('Inconsistent owners'));
  });

  testWidgets('operational data list opens a record detail view', (
    tester,
  ) async {
    const record = OperationalRecord(
      collection: 'payments',
      id: 'payment-1',
      data: {
        'tenantName': 'Maria Santos',
        'amount': 12000,
        'status': 'Paid',
        'landlordId': 'landlord-1',
        'referenceNumber': 'GC-123',
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operationalDataRepositoryProvider.overrideWithValue(
            MockOperationalDataRepository([record]),
          ),
        ],
        child: MaterialApp(
          theme: AdminTheme.lightTheme,
          home: const Scaffold(body: OperationalDataScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add Record'), findsNothing);
    expect(find.text('Edit Record'), findsNothing);
    expect(find.text('Delete Record'), findsNothing);
    expect(find.text('Maria Santos'), findsOneWidget);
    await tester.ensureVisible(find.text('Maria Santos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maria Santos'));
    await tester.pumpAndSettle();

    expect(find.text('Reference Number'), findsOneWidget);
    expect(find.text('GC-123'), findsOneWidget);
    expect(find.text('12000'), findsOneWidget);
  });
}
