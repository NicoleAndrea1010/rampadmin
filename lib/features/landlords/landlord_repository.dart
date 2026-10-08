import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../core/services/firebase_functions_service.dart';
import '../../core/services/supabase_service.dart';
import '../../models/landlord_account.dart';
import '../operations/operational_data_repository.dart';

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
      if ((payment['transactionType'] as String? ?? '').trim().toLowerCase() !=
          'rent') {
        continue;
      }
      if ((payment['status'] as String? ?? '').trim().toLowerCase() != 'paid') {
        continue;
      }
      final paidAt = _paymentDate(payment);
      if (paidAt == null) return const {};
      if (paidAt.isAfter(now)) continue;
      final amount = (payment['amount'] as num?)?.toDouble();
      if (amount == null || !amount.isFinite || amount < 0) return const {};
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
        data['date'];
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
    SupabaseService? operationalDataService,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctionsService(FirebaseFunctions.instance),
       _supabase = operationalDataService;

  final FirebaseFirestore _firestore;
  final FirebaseFunctionsService _functions;
  SupabaseService? _supabase;
  SupabaseService get _operationalData => _supabase ??= SupabaseService();

  @override
  Future<List<LandlordAccount>> getLandlords() async {
    final snapshot = await _firestore
        .collection('landlords')
        .get()
        .timeout(const Duration(seconds: 15));
    final landlords = snapshot.docs.map(LandlordAccount.fromFirestore).toList();
    const collections = ['units', 'tenants', 'payments', 'maintenanceTickets'];
    final operational = await Future.wait(
      collections.map(_operationalData.loadTable),
    );
    final recordsByCollection = {
      for (var index = 0; index < operational.length; index++)
        collections[index]: operational[index],
    };
    for (final records in recordsByCollection.values) {
      for (final record in records) {
        final owners = operationalOwnerIds(record);
        if (owners.length > 1) {
          debugPrint(
            'Data-integrity issue: operational record has conflicting '
            'landlordId values: '
            '${owners.join(', ')}',
          );
        }
      }
    }
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
    Map<String, List<Map<String, dynamic>>> recordsByCollection,
  ) {
    final owned = {
      for (final collection in recordsByCollection.entries)
        collection.key: collection.value.where((record) {
          final owners = _ownerIds(record);
          return owners.length == 1 && owners.single == landlord.uid;
        }).toList(),
    };
    final now = DateTime.now();
    final monthlyRevenue = LandlordPaymentMetrics.sixMonthPaidRevenue(
      owned['payments'] ?? [],
      now,
    );
    final paidThisMonth =
        monthlyRevenue[LandlordPaymentMetrics.monthKey(
          DateTime(now.year, now.month),
        )] ??
        0;
    final openTickets = (owned['maintenanceTickets'] ?? []).where((ticket) {
      final status = (ticket['status'] as String? ?? '')
          .replaceAll('_', ' ')
          .replaceAll('-', ' ')
          .trim()
          .toLowerCase();
      return const {
        'pending',
        'schedule visit',
        'estimate',
        'schedule repair',
      }.contains(status);
    }).length;

    return landlord.copyWith(
      unitCount: (owned['units'] ?? []).length,
      tenantCount: (owned['tenants'] ?? []).length,
      paidThisMonth: paidThisMonth,
      monthlyRevenue: monthlyRevenue,
      paymentMetricsAvailable: monthlyRevenue.isNotEmpty,
      openTicketCount: openTickets,
    );
  }

  List<String> _ownerIds(Map<String, dynamic> data) =>
      operationalOwnerIds(data);

  @override
  Future<LandlordAccount> createLandlord(LandlordAccount landlord) async {
    final response = await _functions.call('createLandlord', {
      'email': landlord.email,
      'displayName': landlord.displayName,
      'companyName': landlord.companyName,
      'phone': landlord.phone,
    });
    final uid = response['uid'];
    if (uid is! String || uid.isEmpty) {
      throw StateError('The server did not return the created landlord ID.');
    }

    final createdAccount = landlord.copyWith(
      uid: uid,
      status: LandlordStatus.invited,
      updatedAt: DateTime.now(),
    );
    await _firestore.collection('landlords').doc(uid).set({
      'canManageAllUnits': createdAccount.canManageAllUnits,
      'assignedUnitIds': createdAccount.assignedUnitIds,
      'assignedEmployeeEmails': createdAccount.assignedEmployeeEmails,
      'permissions': createdAccount.permissions,
    }, SetOptions(merge: true));

    final snapshot = await _firestore.collection('landlords').doc(uid).get();
    if (!snapshot.exists) {
      throw StateError('The server-created landlord profile was not found.');
    }
    return LandlordAccount.fromFirestore(snapshot);
  }

  @override
  Future<void> updateLandlord(LandlordAccount landlord) async {
    await _functions.call('updateLandlord', {
      'uid': landlord.uid,
      'displayName': landlord.displayName,
      'companyName': landlord.companyName,
      'phone': landlord.phone,
    });
    await _firestore.collection('landlords').doc(landlord.uid).update({
      'canManageAllUnits': landlord.canManageAllUnits,
      'assignedUnitIds': landlord.assignedUnitIds,
      'assignedEmployeeEmails': landlord.assignedEmployeeEmails,
      'permissions': landlord.permissions,
    });
  }

  @override
  Future<void> activateLandlord(String uid) async {
    await _functions.call('activateLandlord', {'uid': uid});
  }

  @override
  Future<void> suspendLandlord(String uid, String reason) async {
    await _functions.call('suspendLandlord', {
      'uid': uid,
      'reason': reason.trim(),
    });
  }

  @override
  Future<void> reactivateLandlord(String uid) async {
    await _functions.call('reactivateLandlord', {'uid': uid});
  }

  @override
  Future<void> archiveLandlord(String uid) async {
    await _functions.call('archiveLandlord', {'uid': uid});
  }

  @override
  Future<void> sendPasswordReset(String uid) async {
    await _functions.call('sendLandlordPasswordReset', {'uid': uid});
  }
}

class MockLandlordRepository implements LandlordRepository {
  MockLandlordRepository([List<LandlordAccount>? initialItems])
    : _items = List.from(initialItems ?? const []);

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
      updatedBy: 'test',
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
      updatedBy: 'test',
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
}
