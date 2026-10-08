import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rampadmin/features/operations/operational_data_repository.dart';

final operationalDataRepositoryProvider = Provider<OperationalDataRepository>(
  (ref) => SupabaseOperationalDataRepository(),
);

final operationalRecordsProvider =
    AsyncNotifierProvider<
      OperationalRecordsController,
      List<OperationalRecord>
    >(OperationalRecordsController.new);

class OperationalRecordsController
    extends AsyncNotifier<List<OperationalRecord>> {
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
  // TODO: Align admin operational source with canonical RAMP backend.
  MockOperationalDataRepository([List<OperationalRecord>? initialItems])
    : _items = List.from(initialItems ?? const []);
  final List<OperationalRecord> _items;

  @override
  Future<List<OperationalRecord>> getRecords() async =>
      List.unmodifiable(_items);

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
}
