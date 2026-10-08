import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../features/activity/admin_activity_repository.dart';
import '../models/admin_audit_log.dart';

final activityRepositoryProvider = Provider<AdminActivityRepository>(
  (ref) => AppConfig.useMockData
      ? MockAdminActivityRepository()
      : FirestoreAdminActivityRepository(),
);

final activityLogsProvider =
    AsyncNotifierProvider<ActivityController, List<AdminAuditLog>>(
      ActivityController.new,
    );

class ActivityController extends AsyncNotifier<List<AdminAuditLog>> {
  @override
  Future<List<AdminAuditLog>> build() =>
      ref.read(activityRepositoryProvider).getActivities();

  Future<void> record({
    required String action,
    required String targetId,
    required String description,
    String? reason,
  }) async {
    if (!AppConfig.useMockData) {
      ref.invalidateSelf();
      return;
    }
    final log = AdminAuditLog(
      id: 'activity_${DateTime.now().microsecondsSinceEpoch}',
      actorId: 'nicole_admin',
      actorEmail: 'nicole@ramp.example',
      action: action,
      targetType: 'landlord',
      targetId: targetId,
      description: description,
      reason: reason,
      timestamp: DateTime.now(),
    );
    await ref.read(activityRepositoryProvider).addActivity(log);
    state = AsyncData([log, ...?state.value]);
  }
}
