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
    final container = ProviderContainer(
      overrides: [
        landlordRepositoryProvider.overrideWithValue(MockLandlordRepository()),
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

    expect(find.text('No landlords found'), findsNothing);
    expect(
      container.read(landlordFiltersProvider).status,
      LandlordStatus.invited,
    );
  });
}
