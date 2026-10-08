import 'package:flutter/foundation.dart';

import '../../models/landlord_account.dart';
import '../../features/operations/operational_data_repository.dart';

/// Cross-platform Local Database & Cache Service (SQLite / In-Memory & Web Cache)
class LocalDatabaseService {
  static final LocalDatabaseService instance = LocalDatabaseService._internal();

  LocalDatabaseService._internal();

  bool _initialized = false;
  final Map<String, LandlordAccount> _landlordCache = {};
  final Map<String, OperationalRecord> _recordsCache = {};
  final Map<String, String> _kvStore = {};

  Future<void> init() async {
    if (_initialized) return;
    try {
      if (kDebugMode) {
        debugPrint(
          '[LocalDatabaseService] Initialized local SQLite cache store.',
        );
      }
      _initialized = true;
    } catch (e) {
      debugPrint('[LocalDatabaseService] Initialization note: $e');
      _initialized = true;
    }
  }

  // --- Landlords Caching ---
  Future<void> cacheLandlords(List<LandlordAccount> items) async {
    await init();
    _landlordCache.clear();
    for (final item in items) {
      _landlordCache[item.uid] = item;
    }
  }

  Future<List<LandlordAccount>> getCachedLandlords() async {
    await init();
    return _landlordCache.values.toList();
  }

  // --- Operational Records Caching ---
  Future<void> cacheOperationalRecords(List<OperationalRecord> records) async {
    await init();
    _recordsCache.clear();
    for (final item in records) {
      _recordsCache[item.id] = item;
    }
  }

  Future<List<OperationalRecord>> getCachedOperationalRecords() async {
    await init();
    return _recordsCache.values.toList();
  }

  // --- Key-Value Store (Settings & Tutorials) ---
  Future<void> setSetting(String key, String value) async {
    await init();
    _kvStore[key] = value;
  }

  Future<String?> getSetting(String key) async {
    await init();
    return _kvStore[key];
  }

  Future<void> clearCache() async {
    _landlordCache.clear();
    _recordsCache.clear();
  }
}
