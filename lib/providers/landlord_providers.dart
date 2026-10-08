import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/landlords/landlord_repository.dart';
import '../models/landlord_account.dart';
import 'activity_providers.dart';

import '../core/services/local_database_service.dart';

final landlordRepositoryProvider = Provider<LandlordRepository>(
  (ref) => FirestoreLandlordRepository(),
);

final landlordsProvider =
    AsyncNotifierProvider<LandlordsController, List<LandlordAccount>>(
      LandlordsController.new,
    );

class LandlordsController extends AsyncNotifier<List<LandlordAccount>> {
  LandlordRepository get _repository => ref.read(landlordRepositoryProvider);

  @override
  Future<List<LandlordAccount>> build() async {
    try {
      final items = await _repository.getLandlords();
      await LocalDatabaseService.instance.cacheLandlords(items);
      return items;
    } catch (e) {
      final cached = await LocalDatabaseService.instance.getCachedLandlords();
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<LandlordAccount?> get(String uid) async {
    final cached = state.value?.where((item) => item.uid == uid).firstOrNull;
    return cached ?? _repository.getLandlord(uid);
  }

  Future<LandlordAccount> create(LandlordAccount landlord) async {
    final created = await _repository.createLandlord(landlord);
    final currentList = state.value ?? [];
    final updatedList = [
      created,
      ...currentList.where((item) => item.uid != created.uid),
    ];
    state = AsyncData(updatedList);
    await LocalDatabaseService.instance.cacheLandlords(updatedList);
    _refreshActivity();
    return created;
  }

  Future<void> updateLandlord(LandlordAccount landlord) async {
    await _repository.updateLandlord(landlord);
    if (state.value != null) {
      final updatedList = state.value!.map((item) {
        return item.uid == landlord.uid ? landlord : item;
      }).toList();
      state = AsyncData(updatedList);
      await LocalDatabaseService.instance.cacheLandlords(updatedList);
    }
    _refreshActivity();
  }

  Future<void> suspend(String uid, String reason) async {
    await _repository.suspendLandlord(uid, reason);
    if (state.value != null) {
      final updatedList = state.value!.map((item) {
        if (item.uid == uid) {
          return item.copyWith(
            status: LandlordStatus.suspended,
            suspensionReason: reason,
            suspendedAt: DateTime.now(),
          );
        }
        return item;
      }).toList();
      state = AsyncData(updatedList);
      await LocalDatabaseService.instance.cacheLandlords(updatedList);
    }
    _refreshActivity();
  }

  Future<void> activate(String uid) async {
    await _repository.activateLandlord(uid);
    if (state.value != null) {
      final updatedList = state.value!.map((item) {
        if (item.uid == uid) {
          return item.copyWith(status: LandlordStatus.active);
        }
        return item;
      }).toList();
      state = AsyncData(updatedList);
      await LocalDatabaseService.instance.cacheLandlords(updatedList);
    }
    _refreshActivity();
  }

  Future<void> reactivate(String uid) async {
    await _repository.reactivateLandlord(uid);
    if (state.value != null) {
      final updatedList = state.value!.map((item) {
        if (item.uid == uid) {
          return item.copyWith(status: LandlordStatus.active);
        }
        return item;
      }).toList();
      state = AsyncData(updatedList);
      await LocalDatabaseService.instance.cacheLandlords(updatedList);
    }
    _refreshActivity();
  }

  Future<void> archive(String uid) async {
    await _repository.archiveLandlord(uid);
    if (state.value != null) {
      final updatedList = state.value!.map((item) {
        if (item.uid == uid) {
          return item.copyWith(
            status: LandlordStatus.archived,
            archivedAt: DateTime.now(),
          );
        }
        return item;
      }).toList();
      state = AsyncData(updatedList);
      await LocalDatabaseService.instance.cacheLandlords(updatedList);
    }
    _refreshActivity();
  }

  Future<void> sendPasswordReset(String uid) async {
    await _repository.sendPasswordReset(uid);
    _refreshActivity();
  }

  void _refreshActivity() {
    ref.invalidate(activityLogsProvider);
  }
}

class LandlordFilters {
  const LandlordFilters({
    this.query = '',
    this.status,
    this.sort = 'newest',
    this.page = 0,
    this.pageSize = 10,
  });
  final String query;
  final LandlordStatus? status;
  final String sort;
  final int page;
  final int pageSize;

  LandlordFilters copyWith({
    String? query,
    LandlordStatus? status,
    bool clearStatus = false,
    String? sort,
    int? page,
    int? pageSize,
  }) => LandlordFilters(
    query: query ?? this.query,
    status: clearStatus ? null : status ?? this.status,
    sort: sort ?? this.sort,
    page: page ?? this.page,
    pageSize: pageSize ?? this.pageSize,
  );
}

class LandlordFiltersNotifier extends Notifier<LandlordFilters> {
  @override
  LandlordFilters build() => const LandlordFilters();
  void set(LandlordFilters value) => state = value;
  void clear() => state = const LandlordFilters();
}

final landlordFiltersProvider =
    NotifierProvider<LandlordFiltersNotifier, LandlordFilters>(
      LandlordFiltersNotifier.new,
    );
