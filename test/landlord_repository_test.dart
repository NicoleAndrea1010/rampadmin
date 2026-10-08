import 'package:flutter_test/flutter_test.dart';
import 'package:rampadmin/features/landlords/landlord_repository.dart';
import 'package:rampadmin/models/landlord_account.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  test('monthly landlord revenue counts only linked paid amounts', () {
    final now = DateTime(2026, 10, 8);
    final revenue = LandlordPaymentMetrics.sixMonthPaidRevenue([
      {
        'status': 'Paid',
        'transactionType': 'Rent',
        'amount': 8500,
        'paymentDate': Timestamp.fromDate(DateTime(2026, 10, 2)),
      },
      {
        'status': 'paid',
        'transactionType': 'Maintenance',
        'baseRent': 1000,
        'date': '2026-09-10T10:00:00Z',
      },
      {
        'status': 'Pending',
        'transactionType': 'Rent',
        'amount': 3000,
        'paymentDate': Timestamp.fromDate(DateTime(2026, 10, 4)),
      },
      {
        'status': 'Paid',
        'amount': -500,
        'paymentDate': Timestamp.fromDate(DateTime(2026, 10, 5)),
      },
      {
        'status': 'Paid',
        'amount': 5000,
        'paymentDate': Timestamp.fromDate(DateTime(2026, 3, 1)),
      },
    ], now);

    expect(revenue['2026-10'], 8500);
    expect(revenue['2026-09'], 0);
    expect(revenue['2026-03'], isNull);
    expect(revenue.length, 6);
  });

  test('incomplete paid rent records make revenue unavailable', () {
    final revenue = LandlordPaymentMetrics.sixMonthPaidRevenue([
      {'status': 'Paid', 'transactionType': 'Rent', 'amount': 8500},
    ], DateTime(2026, 10, 8));

    expect(revenue, isEmpty);
  });

  test('mock repository enforces suspend before archive', () async {
    final now = DateTime.now();
    LandlordAccount landlord(String uid, LandlordStatus status) =>
        LandlordAccount(
          uid: uid,
          email: '$uid@example.test',
          displayName: uid,
          companyName: 'Test company',
          phone: '',
          status: status,
          createdAt: now,
          updatedAt: now,
          createdBy: 'test',
          updatedBy: 'test',
        );
    final repository = MockLandlordRepository([
      landlord('landlord_001', LandlordStatus.active),
      landlord('landlord_007', LandlordStatus.invited),
    ]);
    await expectLater(
      repository.archiveLandlord('landlord_001'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.archiveLandlord('landlord_007'),
      throwsA(isA<StateError>()),
    );
    await repository.suspendLandlord('landlord_001', 'Compliance review');
    expect(
      (await repository.getLandlord('landlord_001'))?.status,
      LandlordStatus.suspended,
    );
    await repository.archiveLandlord('landlord_001');
    expect(
      (await repository.getLandlord('landlord_001'))?.status,
      LandlordStatus.archived,
    );
  });

  test('mock creation produces an invited landlord', () async {
    final repository = MockLandlordRepository();
    final now = DateTime.now();
    final created = await repository.createLandlord(
      LandlordAccount(
        uid: 'owner_001',
        email: 'owner@example.com',
        displayName: 'Owner Name',
        companyName: 'Owner Company',
        phone: '09170000000',
        status: LandlordStatus.invited,
        createdAt: now,
        updatedAt: now,
        createdBy: 'Nicole',
        updatedBy: 'Nicole',
      ),
    );
    final landlord = await repository.getLandlord(created.uid);
    expect(landlord?.status, LandlordStatus.invited);
    expect(landlord?.displayName, 'Owner Name');
  });
}
