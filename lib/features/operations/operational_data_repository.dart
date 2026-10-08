import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/services/supabase_service.dart';

List<String> operationalOwnerIds(Map<String, dynamic> data) {
  final current = data['landlordId'];
  final legacy = data['landlord_id'];
  final owners = <String>{
    if (current is String && current.trim().isNotEmpty) current.trim(),
    if (legacy is String && legacy.trim().isNotEmpty) legacy.trim(),
  };
  return owners.toList();
}

String? operationalOwnerId(Map<String, dynamic> data) {
  final owners = operationalOwnerIds(data);
  return owners.length == 1 ? owners.single : null;
}

class OperationalRecord {
  const OperationalRecord({
    required this.collection,
    required this.id,
    required this.data,
  });

  final String collection;
  final String id;
  final Map<String, dynamic> data;

  List<String> get ownerIds => operationalOwnerIds(data);

  bool get hasConflictingOwnerIds => ownerIds.length > 1;

  String get ownerId => operationalOwnerId(data) ?? '';

  String get ownerDescription => hasConflictingOwnerIds
      ? 'Inconsistent owners: ${ownerIds.join(', ')}'
      : ownerId.isEmpty
      ? 'Unassigned legacy record'
      : 'Owner $ownerId';

  String get status {
    final value = data['status'];
    return value is String ? value : '';
  }
}

abstract class OperationalDataRepository {
  Future<List<OperationalRecord>> getRecords();
  Future<void> addRecord(OperationalRecord record);
  Future<void> updateRecord(OperationalRecord record);
  Future<void> deleteRecord(String collection, String id);
}

class FirestoreOperationalDataRepository implements OperationalDataRepository {
  FirestoreOperationalDataRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const collections = {
    'Units': 'units',
    'Tenants': 'tenants',
    'Payments': 'payments',
    'Maintenance': 'maintenanceTickets',
  };

  @override
  Future<List<OperationalRecord>> getRecords() async {
    final entries = await Future.wait(
      collections.entries.map((entry) async {
        final snapshot = await _firestore.collection(entry.value).get();
        return snapshot.docs.map((doc) {
          final record = OperationalRecord(
            collection: entry.value,
            id: doc.id,
            data: doc.data(),
          );
          if (record.hasConflictingOwnerIds) {
            debugPrint(
              'Data-integrity issue: '
              '${record.collection}/${record.id} has conflicting landlordId '
              'values: ${record.ownerIds.join(', ')}',
            );
          }

          return record;
        }).toList();
      }),
    );
    return entries.expand((records) => records).toList();
  }

  @override
  Future<void> addRecord(OperationalRecord record) async {
    await _firestore
        .collection(record.collection)
        .doc(record.id)
        .set(record.data, SetOptions(merge: true));
  }

  @override
  Future<void> updateRecord(OperationalRecord record) async {
    await _firestore
        .collection(record.collection)
        .doc(record.id)
        .set(record.data, SetOptions(merge: true));
  }

  @override
  Future<void> deleteRecord(String collection, String id) async {
    await _firestore.collection(collection).doc(id).delete();
  }
}

class SupabaseOperationalDataRepository implements OperationalDataRepository {
  SupabaseOperationalDataRepository({SupabaseService? supabase})
    : _supabase = supabase ?? SupabaseService();

  final SupabaseService _supabase;

  static const collections = FirestoreOperationalDataRepository.collections;

  @override
  Future<List<OperationalRecord>> getRecords() async {
    final recordsByCollection = await Future.wait(
      collections.values.map((collection) async {
        final rows = await _supabase.loadTable(collection);
        return rows.map((row) {
          final id = row['id'];
          if (id == null || id.toString().isEmpty) {
            throw StateError(
              'Supabase returned a $collection record without an ID.',
            );
          }
          final data = Map<String, dynamic>.from(row)..remove('id');
          final record = OperationalRecord(
            collection: collection,
            id: id.toString(),
            data: data,
          );
          if (record.hasConflictingOwnerIds) {
            debugPrint(
              'Data-integrity issue: ${record.collection}/${record.id} has '
              'conflicting landlordId values: ${record.ownerIds.join(', ')}',
            );
          }
          return record;
        }).toList();
      }),
    );
    return recordsByCollection.expand((records) => records).toList();
  }

  @override
  Future<void> addRecord(OperationalRecord record) => _upsertRecord(record);

  @override
  Future<void> updateRecord(OperationalRecord record) => _upsertRecord(record);

  Future<void> _upsertRecord(OperationalRecord record) {
    return _supabase.upsertRecord(record.collection, {
      ...record.data,
      'id': record.id,
    });
  }

  @override
  Future<void> deleteRecord(String collection, String id) =>
      _supabase.deleteRecord(collection, id);
}
