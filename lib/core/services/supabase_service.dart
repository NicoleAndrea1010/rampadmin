import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const tableNames = {
    'units': 'units',
    'tenants': 'tenants',
    'payments': 'payments',
    'maintenanceTickets': 'maintenance_tickets',
  };

  String _tableName(String appTableName) {
    final tableName = tableNames[appTableName];
    if (tableName == null) {
      throw ArgumentError.value(
        appTableName,
        'appTableName',
        'No Supabase table mapping is defined.',
      );
    }
    return tableName;
  }

  Future<List<Map<String, dynamic>>> loadTable(String appTableName) async {
    final tableName = _tableName(appTableName);
    try {
      final rows = await _client.from(tableName).select();
      return rows.map(_toAppMap).toList();
    } catch (error, stackTrace) {
      debugPrint('Supabase load failed for $tableName: $error');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> upsertRecord(
    String appTableName,
    Map<String, dynamic> record,
  ) async {
    final tableName = _tableName(appTableName);
    try {
      final payload = _convertMapToDatabase(record);
      final id = payload['id'];
      if (id == null || id.toString().isEmpty) {
        throw ArgumentError('A record ID is required for Supabase upsert.');
      }
      await _client.from(tableName).upsert(payload);
    } catch (error, stackTrace) {
      debugPrint('Supabase upsert failed for $tableName: $error');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> deleteRecord(String appTableName, String id) async {
    final tableName = _tableName(appTableName);
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'A record ID is required.');
    }
    try {
      await _client.from(tableName).delete().eq('id', id);
    } catch (error, stackTrace) {
      debugPrint('Supabase delete failed for $tableName/$id: $error');
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Map<String, dynamic> _toAppMap(Map<String, dynamic> row) {
    final converted = <String, dynamic>{};
    for (final entry in row.entries) {
      final key = _toCamelCase(entry.key);
      final value = entry.value is Map<String, dynamic>
          ? _toAppMap(entry.value as Map<String, dynamic>)
          : entry.value;
      if (entry.key == 'landlord_id') {
        converted['landlord_id'] = value;
      }
      converted.putIfAbsent(key, () => value);
    }
    return converted;
  }

  Map<String, dynamic> _convertMapToDatabase(Map<String, dynamic> record) {
    final converted = <String, dynamic>{};
    for (final entry in record.entries) {
      final key = _toSnakeCase(entry.key);
      if (converted.containsKey(key) && converted[key] != entry.value) {
        throw StateError(
          'Conflicting values for Supabase column "$key"; refusing to '
          'overwrite a potentially inconsistent record.',
        );
      }
      final value = entry.value is Map<String, dynamic>
          ? _convertMapToDatabase(entry.value as Map<String, dynamic>)
          : entry.value;
      converted[key] = value;
    }
    return converted;
  }

  String _toCamelCase(String value) => value.replaceAllMapped(
    RegExp(r'_([a-zA-Z0-9])'),
    (match) => match.group(1)!.toUpperCase(),
  );

  String _toSnakeCase(String value) => value.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (match) => '${match.group(1)}_${match.group(2)!.toLowerCase()}',
  );
}
