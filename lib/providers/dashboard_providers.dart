import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../features/dashboard/dashboard_repository.dart';
import '../models/dashboard_summary.dart';
import '../models/landlord_account.dart';
import 'landlord_providers.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => AppConfig.useMockData
      ? MockDashboardRepository()
      : FirestoreDashboardRepository(),
);

final dashboardMockDataProvider = FutureProvider<DashboardMockData>((ref) {
  ref.watch(landlordsProvider);
  return ref.read(dashboardRepositoryProvider).getSummary();
});

final dashboardSummaryProvider = Provider<AsyncValue<DashboardSummary>>((ref) {
  return ref.watch(landlordsProvider).whenData((landlords) {
    return DashboardSummary(
      totalLandlords: landlords.length,
      activeLandlords: landlords
          .where((item) => item.status == LandlordStatus.active)
          .length,
      invitedLandlords: landlords
          .where((item) => item.status == LandlordStatus.invited)
          .length,
      suspendedLandlords: landlords
          .where((item) => item.status == LandlordStatus.suspended)
          .length,
      archivedLandlords: landlords
          .where((item) => item.status == LandlordStatus.archived)
          .length,
    );
  });
});
