import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rampadmin/core/theme/admin_theme.dart';
import 'package:rampadmin/features/landlords/landlord_list_screen.dart';
import 'package:rampadmin/features/landlords/landlord_repository.dart';
import 'package:rampadmin/providers/landlord_providers.dart';
import 'package:rampadmin/models/landlord_account.dart';

void main() {
  testWidgets('landlord directory preserves selected status filter', (
    tester,
  ) async {
    final now = DateTime.now();
    final container = ProviderContainer(
      overrides: [
        landlordRepositoryProvider.overrideWithValue(
          MockLandlordRepository([
            LandlordAccount(
              uid: 'filter-test-landlord',
              email: 'invited@example.test',
              displayName: 'Invited landlord',
              companyName: 'Test company',
              phone: '',
              status: LandlordStatus.invited,
              createdAt: now,
              updatedAt: now,
              createdBy: 'test',
              updatedBy: 'test',
            ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(landlordFiltersProvider.notifier)
        .set(const LandlordFilters(status: LandlordStatus.invited));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AdminTheme.lightTheme,
          home: const Scaffold(body: LandlordListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Pending / Invitations'), findsOneWidget);
    expect(find.textContaining('Active'), findsOneWidget);
    expect(find.textContaining('Suspended'), findsOneWidget);
    expect(find.textContaining('Archived'), findsOneWidget);
    expect(find.text('Status'), findsNothing);
    expect(find.text('No landlords found'), findsNothing);
    expect(
      container.read(landlordFiltersProvider).status,
      LandlordStatus.invited,
    );
  });

  testWidgets('mobile landlord toolbar places sort in the filter sheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          landlordRepositoryProvider.overrideWithValue(
            MockLandlordRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AdminTheme.lightTheme,
          home: const Scaffold(body: LandlordListScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('Sort'), findsNothing);
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    expect(find.text('Sort'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });
}
