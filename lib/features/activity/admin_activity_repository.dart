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
        targetType: data['targetType'] as String? ?? 'landlord',
        targetId: data['targetId'] as String? ?? '',
        description: data['description'] as String? ?? '',
        reason: data['reason'] as String?,
        timestamp:
            (data['timestamp'] as Timestamp?)?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0),
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
  final List<AdminAuditLog> _items = _seed();

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

  static List<AdminAuditLog> _seed() {
    final now = DateTime.now();
    AdminAuditLog log(
      int id,
      String action,
      String target,
      String description,
      Duration age, {
      String? reason,
    }) => AdminAuditLog(
      id: 'activity_$id',
      actorId: 'nicole_admin',
      actorEmail: 'nicole@ramp.example',
      action: action,
      targetType: 'landlord',
      targetId: target,
      description: description,
      reason: reason,
      timestamp: now.subtract(age),
    );
    return [
      log(
        1,
        'LANDLORD_CREATED',
        'landlord_001',
        'QA Alpha Rentals was added',
        const Duration(minutes: 10),
      ),
      log(
        3,
        'LANDLORD_SUSPENDED',
        'landlord_009',
        'Maple Residences was suspended',
        const Duration(days: 1),
        reason: 'Account compliance review',
      ),
      log(
        4,
        'PASSWORD_RESET_SENT',
        'landlord_003',
        'Reset email sent to Riverstone Leasing',
        const Duration(days: 2),
      ),
      log(
        5,
        'LANDLORD_UPDATED',
        'landlord_004',
        'Northpoint Homes information was updated',
        const Duration(days: 3),
      ),
      log(
        6,
        'LANDLORD_REACTIVATED',
        'landlord_005',
        'Cedar Lane Properties was reactivated',
        const Duration(days: 5),
      ),
      log(
        8,
        'LANDLORD_ARCHIVED',
        'landlord_011',
        'Bluewater Suites was archived',
        const Duration(days: 8),
      ),
    ];
  }
}
