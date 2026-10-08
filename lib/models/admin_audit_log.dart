import 'package:cloud_firestore/cloud_firestore.dart';

class AdminAuditLog {
  const AdminAuditLog({
    required this.id,
    required this.actorId,
    required this.actorEmail,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.description,
    this.reason,
    required this.timestamp,
    this.timestampAvailable = true,
  });

  final String id;
  final String actorId;
  final String actorEmail;
  final String action;
  final String targetType;
  final String targetId;
  final String description;
  final String? reason;
  final DateTime timestamp;
  final bool timestampAvailable;

  factory AdminAuditLog.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? {};
    final timestamp = data['timestamp'];
    return AdminAuditLog(
      id: document.id,
      actorId: data['actorId'] as String? ?? '',
      actorEmail: data['actorEmail'] as String? ?? '',
      action: data['action'] as String? ?? '',
      targetType: data['targetType'] as String? ?? '',
      targetId: data['targetId'] as String? ?? '',
      description: data['description'] as String? ?? '',
      reason: data['reason'] as String?,
      timestamp: timestamp is Timestamp
          ? timestamp.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0),
      timestampAvailable: timestamp is Timestamp,
    );
  }
}
