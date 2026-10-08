import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../core/services/firebase_functions_service.dart';
import '../../models/landlord_account.dart';

abstract final class LandlordPaymentMetrics {
  static Map<String, double> sixMonthPaidRevenue(
    Iterable<Map<String, dynamic>> payments,
    DateTime now,
  ) {
    final revenue = <String, double>{};
    for (var offset = 5; offset >= 0; offset--) {
      final month = DateTime(now.year, now.month - offset);
      revenue[monthKey(month)] = 0;
    }
    for (final payment in payments) {
      if ((payment['status'] as String? ?? '').toLowerCase() != 'paid') {
        continue;
      }
      final paidAt = _paymentDate(payment);
      if (paidAt == null || paidAt.isAfter(now)) continue;
      final amount =
          (payment['amount'] as num?)?.toDouble() ??
          (payment['baseRent'] as num?)?.toDouble() ??
          (payment['total_amount'] as num?)?.toDouble();
      if (amount == null || !amount.isFinite || amount < 0) continue;
      final key = monthKey(paidAt);
      if (revenue.containsKey(key)) revenue[key] = revenue[key]! + amount;
    }
    return revenue;
  }

  static DateTime? _paymentDate(Map<String, dynamic> data) {
    final value =
        data['paidAt'] ??
        data['paid_at'] ??
        data['paymentDate'] ??
        data['payment_date'] ??
        data['date'] ??
        data['timestamp'] ??
        data['createdAt'];
    return switch (value) {
      Timestamp timestamp => timestamp.toDate(),
      DateTime date => date,
      String date => DateTime.tryParse(date),
      _ => null,
    };
  }

  static String monthKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';
}

abstract interface class LandlordRepository {
  Future<List<LandlordAccount>> getLandlords();
  Future<LandlordAccount?> getLandlord(String uid);
  Future<LandlordAccount> createLandlord(LandlordAccount landlord);
  Future<void> updateLandlord(LandlordAccount landlord);
  Future<void> activateLandlord(String uid);
  Future<void> suspendLandlord(String uid, String reason);
  Future<void> reactivateLandlord(String uid);
  Future<void> archiveLandlord(String uid);
  Future<void> sendPasswordReset(String uid);
}

class FirestoreLandlordRepository implements LandlordRepository {
  FirestoreLandlordRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctionsService? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctionsService(FirebaseFunctions.instance);

  final FirebaseFirestore _firestore;
  final FirebaseFunctionsService _functions;

  @override
  Future<List<LandlordAccount>> getLandlords() async {
    final snapshot = await _firestore
        .collection('landlords')
        .get()
        .timeout(const Duration(seconds: 15));
    final landlords = snapshot.docs.map(LandlordAccount.fromFirestore).toList();
    final operational = await Future.wait(
      const ['units', 'tenants', 'payments', 'maintenanceTickets'].map(
        (collection) => _firestore
            .collection(collection)
            .get()
            .timeout(const Duration(seconds: 15)),
      ),
    );
    final recordsByCollection = {
      for (var index = 0; index < operational.length; index++)
        const ['units', 'tenants', 'payments', 'maintenanceTickets'][index]:
            operational[index].docs,
    };
    return landlords
        .map(
          (landlord) => _enrichWithLiveMetrics(landlord, recordsByCollection),
        )
        .toList();
  }

  @override
  Future<LandlordAccount?> getLandlord(String uid) async {
    final doc = await _firestore.collection('landlords').doc(uid).get();
    if (!doc.exists) return null;
    final fullList = await getLandlords();
    return fullList.where((item) => item.uid == uid).firstOrNull;
  }

  LandlordAccount _enrichWithLiveMetrics(
    LandlordAccount landlord,
    Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    recordsByCollection,
  ) {
    final owned = {
      for (final collection in recordsByCollection.entries)
        collection.key: collection.value
            .where((record) => _ownerId(record.data()) == landlord.uid)
            .toList(),
    };
    final now = DateTime.now();
    final monthlyRevenue = LandlordPaymentMetrics.sixMonthPaidRevenue(
      (owned['payments'] ?? []).map((payment) => payment.data()),
      now,
    );
    final paidThisMonth =
        monthlyRevenue[LandlordPaymentMetrics.monthKey(
          DateTime(now.year, now.month),
        )] ??
        0;
    final openTickets = (owned['maintenanceTickets'] ?? []).where((ticket) {
      final status = (ticket.data()['status'] as String? ?? '').toLowerCase();
      return status != 'completed' &&
          status != 'resolved' &&
          status != 'closed';
    }).length;

    return landlord.copyWith(
      unitCount: (owned['units'] ?? []).length,
      tenantCount: (owned['tenants'] ?? []).length,
      paidThisMonth: paidThisMonth,
      monthlyRevenue: monthlyRevenue,
      openTicketCount: openTickets,
    );
  }

  String _ownerId(Map<String, dynamic> data) {
    final current = data['landlordId'];
    final legacy = data['landlord_id'];
    if (current is String && current.isNotEmpty) {
      if (legacy is String && legacy.isNotEmpty && legacy != current) {
        return '';
      }
      return current;
    }
    return legacy is String ? legacy : '';
  }

  @override
  Future<LandlordAccount> createLandlord(LandlordAccount landlord) async {
    String uid = landlord.uid;
    try {
      final response = await _functions.call('createLandlord', {
        'email': landlord.email,
        'displayName': landlord.displayName,
        'companyName': landlord.companyName,
        'phone': landlord.phone,
      });
      if (response['uid'] is String && (response['uid'] as String).isNotEmpty) {
        uid = response['uid'];
      }
    } catch (_) {}

    final createdAccount = landlord.copyWith(
      uid: uid,
      updatedAt: DateTime.now(),
    );
    await _firestore
        .collection('landlords')
        .doc(uid)
        .set(createdAccount.toMap(), SetOptions(merge: true));

    return createdAccount;
  }

  @override
  Future<void> updateLandlord(LandlordAccount landlord) async {
    await _firestore
        .collection('landlords')
        .doc(landlord.uid)
        .set(landlord.toMap(), SetOptions(merge: true));

    try {
      await _functions.call('updateLandlord', {
        'uid': landlord.uid,
        'displayName': landlord.displayName,
        'companyName': landlord.companyName,
        'phone': landlord.phone,
      });
    } catch (_) {}
  }

  @override
  Future<void> activateLandlord(String uid) async {
    await _firestore.collection('landlords').doc(uid).set(
      {'status': LandlordStatus.active.name},
      SetOptions(merge: true),
    );
    try {
      await _functions.call('activateLandlord', {'uid': uid});
    } catch (_) {}
  }

  @override
  Future<void> suspendLandlord(String uid, String reason) async {
    await _firestore.collection('landlords').doc(uid).set({
      'status': LandlordStatus.suspended.name,
      'suspensionReason': reason.trim(),
      'suspendedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    try {
      await _functions.call('suspendLandlord', {
        'uid': uid,
        'reason': reason.trim(),
      });
    } catch (_) {}
  }

  @override
  Future<void> reactivateLandlord(String uid) async {
    await _firestore.collection('landlords').doc(uid).set(
      {'status': LandlordStatus.active.name},
      SetOptions(merge: true),
    );
    try {
      await _functions.call('reactivateLandlord', {'uid': uid});
    } catch (_) {}
  }

  @override
  Future<void> archiveLandlord(String uid) async {
    await _firestore.collection('landlords').doc(uid).set({
      'status': LandlordStatus.archived.name,
      'archivedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    try {
      await _functions.call('archiveLandlord', {'uid': uid});
    } catch (_) {}
  }

  @override
  Future<void> sendPasswordReset(String uid) async {
    try {
      await _functions.call('sendLandlordPasswordReset', {'uid': uid});
    } catch (_) {}
  }
}

class MockLandlordRepository implements LandlordRepository {
  MockLandlordRepository() : _items = _seedData();
  final List<LandlordAccount> _items;

  @override
  Future<List<LandlordAccount>> getLandlords() async {
    await Future<void>.delayed(const Duration(milliseconds: 260));
    return List.unmodifiable(_items);
  }

  @override
  Future<LandlordAccount?> getLandlord(String uid) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return _items.where((item) => item.uid == uid).firstOrNull;
  }

  @override
  Future<LandlordAccount> createLandlord(LandlordAccount landlord) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (_items.any(
      (item) => item.email.toLowerCase() == landlord.email.toLowerCase(),
    )) {
      throw StateError('duplicate-email');
    }
    final created = landlord.copyWith(
      updatedAt: DateTime.now(),
      updatedBy: 'Nicole',
    );
    _items.insert(0, created);
    return created;
  }

  @override
  Future<void> updateLandlord(LandlordAccount landlord) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final index = _items.indexWhere((item) => item.uid == landlord.uid);
    if (index < 0) throw StateError('not-found');
    _items[index] = landlord.copyWith(
      updatedAt: DateTime.now(),
      updatedBy: 'Nicole',
    );
  }

  @override
  Future<void> activateLandlord(String uid) async {
    final item = await getLandlord(uid);
    if (item == null) throw StateError('not-found');
    await updateLandlord(item.copyWith(status: LandlordStatus.active));
  }

  @override
  Future<void> suspendLandlord(String uid, String reason) async {
    if (reason.trim().length < 5) throw ArgumentError('reason-too-short');
    final item = await getLandlord(uid);
    if (item == null) throw StateError('not-found');
    await updateLandlord(
      item.copyWith(
        status: LandlordStatus.suspended,
        suspensionReason: reason.trim(),
        suspendedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> reactivateLandlord(String uid) async {
    final item = await getLandlord(uid);
    if (item == null) throw StateError('not-found');
    await updateLandlord(item.copyWith(status: LandlordStatus.active));
  }

  @override
  Future<void> archiveLandlord(String uid) async {
    final item = await getLandlord(uid);
    if (item == null) throw StateError('not-found');
    if (item.status != LandlordStatus.suspended) {
      throw StateError('suspend-first');
    }
    await updateLandlord(
      item.copyWith(
        status: LandlordStatus.archived,
        archivedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> sendPasswordReset(String uid) async {
    if (await getLandlord(uid) == null) throw StateError('not-found');
  }

  static List<LandlordAccount> _seedData() {
    final now = DateTime.now();
    LandlordAccount item(
      int number,
      String name,
      String company,
      LandlordStatus status,
      int used,
      int tenants,
      double paid,
      int tickets,
      int age,
    ) => LandlordAccount(
      uid: 'landlord_${number.toString().padLeft(3, '0')}',
      email:
          'admin${number.toString().padLeft(2, '0')}@${company.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')}.example',
      displayName: name,
      companyName: company,
      phone: '09${(1700000000 + number * 7919).toString().substring(0, 9)}',
      status: status,
      unitCount: used,
      tenantCount: tenants,
      paidThisMonth: paid,
      openTicketCount: tickets,
      createdAt: now.subtract(Duration(days: age)),
      updatedAt: now.subtract(Duration(days: number % 5)),
      lastSignInAt: status == LandlordStatus.invited
          ? null
          : now.subtract(Duration(hours: number * 7)),
      createdBy: 'Nicole',
      updatedBy: 'Nicole',
      suspensionReason: status == LandlordStatus.suspended
          ? 'Account compliance review'
          : null,
      suspendedAt: status == LandlordStatus.suspended
          ? now.subtract(Duration(days: number))
          : null,
      archivedAt: status == LandlordStatus.archived
          ? now.subtract(Duration(days: number))
          : null,
    );

    return [
      item(
        1,
        'Alyssa Mendoza',
        'QA Alpha Rentals',
        LandlordStatus.active,
        18,
        15,
        72500,
        3,
        8,
      ),
      item(
        2,
        'Marco Villanueva',
        'Sunrise Apartments',
        LandlordStatus.active,
        43,
        36,
        168400,
        2,
        22,
      ),
      item(
        3,
        'Bianca Santos',
        'Riverstone Leasing',
        LandlordStatus.active,
        8,
        6,
        38500,
        1,
        39,
      ),
      item(
        4,
        'Paolo Reyes',
        'Northpoint Homes',
        LandlordStatus.active,
        23,
        19,
        91600,
        4,
        51,
      ),
      item(
        5,
        'Camille Navarro',
        'Cedar Lane Properties',
        LandlordStatus.active,
        6,
        5,
        28400,
        0,
        68,
      ),
      item(
        6,
        'Joaquin Lim',
        'Harborview Residences',
        LandlordStatus.active,
        47,
        41,
        193000,
        2,
        86,
      ),
      item(
        7,
        'Sofia Castillo',
        'Magnolia Property Group',
        LandlordStatus.invited,
        0,
        0,
        0,
        0,
        3,
      ),
      item(
        8,
        'Nathan Garcia',
        'Greenfield Spaces',
        LandlordStatus.invited,
        0,
        0,
        0,
        0,
        6,
      ),
      item(
        9,
        'Isabel Aquino',
        'Maple Residences',
        LandlordStatus.suspended,
        20,
        17,
        0,
        5,
        105,
      ),
      item(
        10,
        'Luis Fernandez',
        'Parkside Rental Co.',
        LandlordStatus.suspended,
        9,
        7,
        0,
        2,
        132,
      ),
      item(
        11,
        'Patricia Ong',
        'Bluewater Suites',
        LandlordStatus.archived,
        31,
        25,
        0,
        0,
        190,
      ),
      item(
        12,
        'Gabriel Torres',
        'Westbridge Living',
        LandlordStatus.archived,
        7,
        5,
        0,
        0,
        240,
      ),
    ];
  }
}
