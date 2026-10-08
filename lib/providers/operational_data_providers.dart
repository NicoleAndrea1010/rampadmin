import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import 'package:rampadmin/features/operations/operational_data_repository.dart';

final operationalDataRepositoryProvider = Provider<OperationalDataRepository>(
  (ref) => AppConfig.useMockData
      ? MockOperationalDataRepository()
      : FirestoreOperationalDataRepository(),
);

final operationalRecordsProvider =
    AsyncNotifierProvider<OperationalRecordsController, List<OperationalRecord>>(
      OperationalRecordsController.new,
    );

class OperationalRecordsController extends AsyncNotifier<List<OperationalRecord>> {
  OperationalDataRepository get _repository =>
      ref.read(operationalDataRepositoryProvider);

  @override
  Future<List<OperationalRecord>> build() async {
    return _repository.getRecords();
  }

  Future<void> addRecord(OperationalRecord record) async {
    await _repository.addRecord(record);
    final current = state.value ?? [];
    state = AsyncData([record, ...current]);
  }

  Future<void> updateRecord(OperationalRecord record) async {
    await _repository.updateRecord(record);
    if (state.value != null) {
      final updated = state.value!.map((item) {
        if (item.collection == record.collection && item.id == record.id) {
          return record;
        }
        return item;
      }).toList();
      state = AsyncData(updated);
    }
  }

  Future<void> deleteRecord(String collection, String id) async {
    await _repository.deleteRecord(collection, id);
    if (state.value != null) {
      final updated = state.value!.where((item) {
        return !(item.collection == collection && item.id == id);
      }).toList();
      state = AsyncData(updated);
    }
  }
}

class MockOperationalDataRepository implements OperationalDataRepository {
  MockOperationalDataRepository([List<OperationalRecord>? initialItems])
      : _items = List.from(initialItems ?? _initialItems);
  final List<OperationalRecord> _items;

  @override
  Future<List<OperationalRecord>> getRecords() async => List.unmodifiable(_items);

  @override
  Future<void> addRecord(OperationalRecord record) async {
    _items.insert(0, record);
  }

  @override
  Future<void> updateRecord(OperationalRecord record) async {
    final idx = _items.indexWhere(
      (r) => r.collection == record.collection && r.id == record.id,
    );
    if (idx >= 0) {
      _items[idx] = record;
    }
  }

  @override
  Future<void> deleteRecord(String collection, String id) async {
    _items.removeWhere((r) => r.collection == collection && r.id == id);
  }

  static const List<OperationalRecord> _initialItems = [
    OperationalRecord(
      collection: 'units',
      id: 'sample_unit_2',
      data: {
        'landlordId': 'landlord_001',
        'unitNumber': 'Unit 2',
        'status': 'Occupied',
        'rent': 12000,
        'tenantName': 'Maria Santos',
      },
    ),
    OperationalRecord(
      collection: 'tenants',
      id: 'sample_tenant_2',
      data: {
        'landlordId': 'landlord_001',
        'name': 'Maria Santos',
        'email': 'maria@example.test',
        'unitNumber': 'Unit 2',
        'status': 'Active',
      },
    ),
    OperationalRecord(
      collection: 'payments',
      id: 'sample_payment_2',
      data: {
        'landlordId': 'landlord_001',
        'tenantName': 'Maria Santos',
        'unitNumber': 'Unit 2',
        'amount': 12000,
        'paymentDate': '2026-09-21T04:10:06Z',
        'status': 'Paid',
        'referenceNumber': 'SAMPLE-GC-902182910',
      },
    ),
    OperationalRecord(
      collection: 'maintenanceTickets',
      id: 'sample_ticket_2',
      data: {
        'landlordId': 'landlord_001',
        'title': 'Bathroom Sink Leakage',
        'unitNumber': 'Unit 2',
        'priority': 'High',
        'status': 'In Progress',
        'createdAt': '2026-09-25T06:58:38Z',
      },
    ),
  ];
}
