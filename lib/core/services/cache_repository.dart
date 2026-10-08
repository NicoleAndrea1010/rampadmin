import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/landlord_account.dart';
import '../../features/operations/operational_data_repository.dart';
import 'local_database_service.dart';

final localDatabaseServiceProvider = Provider<LocalDatabaseService>((ref) {
  return LocalDatabaseService.instance;
});

class CacheRepository {
  CacheRepository(this._localDb);

  final LocalDatabaseService _localDb;

  Future<List<LandlordAccount>> syncLandlords(
    Future<List<LandlordAccount>> Function() fetchFromCloud,
  ) async {
    try {
      final freshData = await fetchFromCloud();
      await _localDb.cacheLandlords(freshData);
      return freshData;
    } catch (e) {
      final cached = await _localDb.getCachedLandlords();
      if (cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }

  Future<List<OperationalRecord>> syncOperationalRecords(
    Future<List<OperationalRecord>> Function() fetchFromCloud,
  ) async {
    try {
      final freshData = await fetchFromCloud();
      await _localDb.cacheOperationalRecords(freshData);
      return freshData;
    } catch (e) {
      final cached = await _localDb.getCachedOperationalRecords();
      if (cached.isNotEmpty) {
        return cached;
      }
      rethrow;
    }
  }
}

final cacheRepositoryProvider = Provider<CacheRepository>((ref) {
  return CacheRepository(ref.watch(localDatabaseServiceProvider));
});
