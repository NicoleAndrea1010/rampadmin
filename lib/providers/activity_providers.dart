import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/activity/admin_activity_repository.dart';
import '../models/admin_audit_log.dart';

final activityRepositoryProvider = Provider<AdminActivityRepository>(
  (ref) => FirestoreAdminActivityRepository(),
);

final activityLogsProvider =
    AsyncNotifierProvider<ActivityController, List<AdminAuditLog>>(
      ActivityController.new,
    );

class ActivityController extends AsyncNotifier<List<AdminAuditLog>> {
  @override
  Future<List<AdminAuditLog>> build() =>
      ref.read(activityRepositoryProvider).getActivities();
}
