import 'package:rampadmin/features/operations/operational_data_repository.dart';
import 'package:rampadmin/models/admin_audit_log.dart';
import 'package:rampadmin/models/landlord_account.dart';

List<LandlordAccount> layoutTestLandlords() {
  final now = DateTime.now();
  return [
    LandlordAccount(
      uid: 'landlord_001',
      email: 'owner@example.test',
      displayName: 'Test Owner',
      companyName: 'Test Rentals',
      phone: '',
      status: LandlordStatus.active,
      createdAt: now,
      updatedAt: now,
      createdBy: 'test',
      updatedBy: 'test',
    ),
    LandlordAccount(
      uid: 'landlord_002',
      email: 'invited@example.test',
      displayName: 'Invited Owner',
      companyName: 'Test Rentals',
      phone: '',
      status: LandlordStatus.invited,
      createdAt: now,
      updatedAt: now,
      createdBy: 'test',
      updatedBy: 'test',
    ),
  ];
}

List<AdminAuditLog> layoutTestActivities() => [
  AdminAuditLog(
    id: 'test-activity',
    actorId: 'test-admin',
    actorEmail: 'test-admin@example.test',
    action: 'LANDLORD_CREATED',
    targetType: 'landlord',
    targetId: 'landlord_001',
    description: 'Test account created',
    timestamp: DateTime(2026),
  ),
];

List<OperationalRecord> layoutTestOperationalRecords() => const [
  OperationalRecord(
    collection: 'units',
    id: 'test-unit',
    data: {
      'landlordId': 'landlord_001',
      'unitNumber': 'Test unit',
      'status': 'Occupied',
    },
  ),
  OperationalRecord(
    collection: 'payments',
    id: 'test-payment',
    data: {
      'landlordId': 'landlord_001',
      'amount': 100,
      'status': 'Paid',
      'referenceNumber': 'TEST-001',
    },
  ),
];
