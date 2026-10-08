import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/admin_audit_log.dart';

abstract interface class AdminActivityRepository {
  Future<List<AdminAuditLog>> getActivities();
  Future<AdminAuditLog> addActivity(AdminAuditLog activity);
}

class FirestoreAdminActivityRepository implements AdminActivityRepository {
  FirestoreAdminActivityRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<List<AdminAuditLog>> getActivities() async {
    final snapshot = await _firestore
        .collection('adminAuditLogs')
        .orderBy('timestamp', descending: true)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data();
      return AdminAuditLog(
        id: doc.id,
        actorId: data['actorId'] as String? ?? '',
        actorEmail: data['actorEmail'] as String? ?? '',
        action: data['action'] as String? ?? '',
        targetType: data['targetType'] as String? ?? '',
        targetId: data['targetId'] as String? ?? '',
        description: data['description'] as String? ?? '',
        reason: data['reason'] as String?,
        timestamp:
            (data['timestamp'] as Timestamp?)?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        timestampAvailable: data['timestamp'] is Timestamp,
      );
    }).toList();
  }

  @override
  Future<AdminAuditLog> addActivity(AdminAuditLog activity) {
    throw UnsupportedError(
      'Audit records are written by trusted Cloud Functions in live mode.',
    );
  }
}

class MockAdminActivityRepository implements AdminActivityRepository {
  // TODO: Align admin operational source with canonical RAMP backend.
  MockAdminActivityRepository([List<AdminAuditLog>? initialItems])
    : _items = List.from(initialItems ?? const []);

  final List<AdminAuditLog> _items;

  @override
  Future<List<AdminAuditLog>> getActivities() async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    return List.unmodifiable(_items);
  }

  @override
  Future<AdminAuditLog> addActivity(AdminAuditLog activity) async {
    _items.insert(0, activity);
    return activity;
  }
}
