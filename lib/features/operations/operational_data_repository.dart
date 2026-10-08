import 'package:cloud_firestore/cloud_firestore.dart';

class OperationalRecord {
  const OperationalRecord({
    required this.collection,
    required this.id,
    required this.data,
  });

  final String collection;
  final String id;
  final Map<String, dynamic> data;

  String get ownerId {
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
        return snapshot.docs
            .map(
              (doc) => OperationalRecord(
                collection: entry.value,
                id: doc.id,
                data: doc.data(),
              ),
            )
            .toList();
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
