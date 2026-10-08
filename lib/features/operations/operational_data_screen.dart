import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/ui_components.dart';
import '../../providers/operational_data_providers.dart';
import 'package:rampadmin/features/operations/operational_data_repository.dart';

class OperationalDataScreen extends ConsumerStatefulWidget {
  const OperationalDataScreen({super.key});

  @override
  ConsumerState<OperationalDataScreen> createState() =>
      _OperationalDataScreenState();
}

class _OperationalDataScreenState extends ConsumerState<OperationalDataScreen> {
  final _searchController = TextEditingController();
  String _collection = 'all';
  String _status = 'all';
  String _category = 'all';
  String _sort = 'newest';
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(operationalRecordsProvider);
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 700 ? 20 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'RAMP Data',
            subtitle: 'Inspect live units, tenants, payments, and maintenance records.',
            badge: Chip(
              avatar: Icon(
                AppConfig.useMockData
                    ? Icons.science_outlined
                    : Icons.lock_outline,
                size: 16,
              ),
              label: Text(AppConfig.useMockData ? 'Sample mode' : 'Read-only'),
            ),
            actions: [
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(operationalRecordsProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
                onPressed: _showAddRecordDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add Record'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 20),
          records.when(
            loading: () => const LoadingSkeleton(rows: 8),
            error: (_, _) => ErrorView(
              message: 'Operational records could not be loaded.',
              onRetry: () => ref.invalidate(operationalRecordsProvider),
            ),
            data: (allRecords) => _content(allRecords),
          ),
        ],
      ),
    );
  }

  Widget _content(List<OperationalRecord> allRecords) {
    final availableCategories =
        allRecords
            .map((record) => _value(record.data['category']).trim())
            .where((category) => category.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final availableStatuses =
        allRecords
            .map((record) => record.status.trim())
            .where((status) => status.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final records =
        allRecords.where((record) {
          final matchesCollection =
              _collection == 'all' || record.collection == _collection;
          final matchesStatus =
              _status == 'all' ||
              record.status.toLowerCase() == _status.toLowerCase();
          final matchesCategory =
              _category == 'all' ||
              _value(record.data['category']).toLowerCase() ==
                  _category.toLowerCase();
          final matchesQuery =
              _query.isEmpty ||
              '${record.id} ${record.data}'.toLowerCase().contains(_query);
          return matchesCollection &&
              matchesStatus &&
              matchesCategory &&
              matchesQuery;
        }).toList()..sort(
          (a, b) => switch (_sort) {
            'oldest' => _recordDate(a).compareTo(_recordDate(b)),
            'name' => _title(
              a,
            ).toLowerCase().compareTo(_title(b).toLowerCase()),
            _ => _recordDate(b).compareTo(_recordDate(a)),
          },
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _counts(allRecords),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final search = TextField(
                  controller: _searchController,
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search names, IDs, units, references...',
                  ),
                );
                final collection = DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _collection,
                  decoration: const InputDecoration(labelText: 'Record type'),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All records'),
                    ),
                    ...FirestoreOperationalDataRepository.collections.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(_collectionName(value)),
                          ),
                        ),
                  ],
                  onChanged: (value) =>
                      setState(() => _collection = value ?? 'all'),
                );
                final status = DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All statuses'),
                    ),
                    ...availableStatuses.map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _status = value ?? 'all'),
                );
                final category = DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All categories'),
                    ),
                    ...availableCategories.map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _category = value ?? 'all'),
                );
                final sort = DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _sort,
                  decoration: const InputDecoration(labelText: 'Sort'),
                  items: const [
                    DropdownMenuItem(
                      value: 'newest',
                      child: Text('Newest first'),
                    ),
                    DropdownMenuItem(
                      value: 'oldest',
                      child: Text('Oldest first'),
                    ),
                    DropdownMenuItem(value: 'name', child: Text('Name A-Z')),
                  ],
                  onChanged: (value) =>
                      setState(() => _sort = value ?? 'newest'),
                );
                final clearFilters = TextButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _collection = 'all';
                      _status = 'all';
                      _category = 'all';
                      _sort = 'newest';
                      _query = '';
                    });
                  },
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('Clear filters'),
                );
                if (constraints.maxWidth < 750) {
                  return Column(
                    children: [
                      search,
                      const SizedBox(height: 12),
                      collection,
                      const SizedBox(height: 12),
                      status,
                      const SizedBox(height: 12),
                      category,
                      const SizedBox(height: 12),
                      sort,
                      const SizedBox(height: 8),
                      clearFilters,
                    ],
                  );
                }
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(flex: 3, child: search),
                        const SizedBox(width: 14),
                        Expanded(flex: 2, child: collection),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: status),
                        const SizedBox(width: 12),
                        Expanded(child: category),
                        const SizedBox(width: 12),
                        Expanded(child: sort),
                        const SizedBox(width: 12),
                        clearFilters,
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${records.length} record${records.length == 1 ? '' : 's'}',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: records.isEmpty
              ? const EmptyState(
                  title: 'No records found',
                  message: 'Try another record type, status, or search term.',
                )
              : Column(
                  children: [
                    for (var i = 0; i < records.length; i++) ...[
                      _recordTile(records[i]),
                      if (i != records.length - 1) const Divider(height: 1),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _counts(List<OperationalRecord> records) => LayoutBuilder(
    builder: (context, constraints) {
      final double cardWidth = constraints.maxWidth >= 900
          ? (constraints.maxWidth - 36) / 4
          : constraints.maxWidth >= 500
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: cardWidth,
            child: _countCard('Units', records, 'units', Icons.apartment_outlined),
          ),
          SizedBox(
            width: cardWidth,
            child: _countCard('Tenants', records, 'tenants', Icons.groups_outlined),
          ),
          SizedBox(
            width: cardWidth,
            child: _countCard('Payments', records, 'payments', Icons.payments_outlined),
          ),
          SizedBox(
            width: cardWidth,
            child: _countCard(
              'Maintenance',
              records,
              'maintenanceTickets',
              Icons.build_outlined,
            ),
          ),
        ],
      );
    },
  );

  Widget _countCard(
    String title,
    List<OperationalRecord> records,
    String collection,
    IconData icon,
  ) => Card(
    child: ListTile(
      leading: Icon(icon, color: AppColors.primaryBlue),
      title: Text(
        '$title · ${records.where((r) => r.collection == collection).length}',
      ),
      subtitle: Text(
        AppConfig.useMockData ? 'Sample records' : 'Live records',
      ),
    ),
  );

  Widget _recordTile(OperationalRecord record) {
    final title = _title(record);
    final status = record.status.trim();
    final details = [
      if (_value(record.data['unitNumber']).isNotEmpty)
        _value(record.data['unitNumber']),
      if (_value(record.data['tenantName']).isNotEmpty)
        _value(record.data['tenantName']),
      if (_value(record.data['email']).isNotEmpty) _value(record.data['email']),
      if (_value(record.data['referenceNumber']).isNotEmpty)
        'Ref ${_value(record.data['referenceNumber'])}',
    ].join(' · ');
    final owner = record.ownerId.isEmpty
        ? 'Unassigned legacy record'
        : 'Owner ${record.ownerId}';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primaryTint,
        child: Icon(_icon(record.collection), color: AppColors.primaryBlue),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          _collectionName(record.collection),
          if (details.isNotEmpty) details,
          owner,
          'ID ${record.id}',
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: status.isEmpty
          ? null
          : Chip(label: Text(status), visualDensity: VisualDensity.compact),
      onTap: () => _showDetails(record),
    );
  }

  Future<void> _showDetails(OperationalRecord record) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(_title(record), maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final key in record.data.keys.toList()..sort())
                if (_displayValue(record.data[key]).isNotEmpty)
                  ListTile(
                    dense: true,
                    title: Text(_label(key)),
                    subtitle: SelectableText(_displayValue(record.data[key])),
                  ),
              ListTile(
                dense: true,
                title: const Text('Document ID'),
                subtitle: SelectableText(record.id),
              ),
              ListTile(
                dense: true,
                title: const Text('Record collection'),
                subtitle: Text(record.collection),
              ),
              ListTile(
                dense: true,
                title: const Text('Landlord owner'),
                subtitle: Text(
                  record.ownerId.isEmpty
                      ? 'Unassigned legacy record'
                      : record.ownerId,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            _showEditRecordDialog(record);
          },
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Edit Record'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            Navigator.pop(context);
            _confirmDeleteRecord(record);
          },
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Delete record'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> _showAddRecordDialog() async {
    final titleController = TextEditingController();
    final unitController = TextEditingController();
    final landlordController = TextEditingController();
    String col = 'units';
    String status = 'Active';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add New Record'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: col,
                    decoration: const InputDecoration(labelText: 'Record Collection'),
                    items: const [
                      DropdownMenuItem(value: 'units', child: Text('Units')),
                      DropdownMenuItem(value: 'tenants', child: Text('Tenants')),
                      DropdownMenuItem(value: 'payments', child: Text('Payments')),
                      DropdownMenuItem(value: 'maintenanceTickets', child: Text('Maintenance')),
                    ],
                    onChanged: (val) => setDialogState(() => col = val ?? 'units'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title / Name / Reference *',
                      hintText: 'e.g. Unit 105 or John Doe',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: unitController,
                    decoration: const InputDecoration(
                      labelText: 'Unit Number / Identifier',
                      hintText: 'e.g. Unit 105',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: landlordController,
                    decoration: const InputDecoration(
                      labelText: 'Landlord Owner ID (Optional)',
                      hintText: 'e.g. landlord_001',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (val) => status = val,
                    decoration: InputDecoration(
                      labelText: 'Status',
                      hintText: col == 'payments' ? 'Paid' : 'Active',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final name = titleController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(dialogContext);
                final id = 'rec_${DateTime.now().millisecondsSinceEpoch}';
                final newRecord = OperationalRecord(
                  collection: col,
                  id: id,
                  data: {
                    'title': name,
                    'name': name,
                    'unitNumber': unitController.text.trim(),
                    'landlordId': landlordController.text.trim(),
                    'status': status.trim().isEmpty ? 'Active' : status.trim(),
                    'createdAt': DateTime.now().toIso8601String(),
                  },
                );
                await ref
                    .read(operationalRecordsProvider.notifier)
                    .addRecord(newRecord);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('New $col record saved successfully.')),
                  );
                }
              },
              child: const Text('Save Record'),
            ),
          ],
        ),
      ),
    );
    titleController.dispose();
    unitController.dispose();
    landlordController.dispose();
  }

  Future<void> _showEditRecordDialog(OperationalRecord record) async {
    final titleController = TextEditingController(
      text: _title(record),
    );
    final unitController = TextEditingController(
      text: _value(record.data['unitNumber']),
    );
    final statusController = TextEditingController(
      text: record.status,
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit ${_collectionName(record.collection)} Record'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title / Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: unitController,
                decoration: const InputDecoration(labelText: 'Unit Number'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: statusController,
                decoration: const InputDecoration(labelText: 'Status'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              final updatedData = Map<String, dynamic>.from(record.data);
              updatedData['title'] = titleController.text.trim();
              updatedData['name'] = titleController.text.trim();
              updatedData['unitNumber'] = unitController.text.trim();
              updatedData['status'] = statusController.text.trim();
              updatedData['updatedAt'] = DateTime.now().toIso8601String();

              final updated = OperationalRecord(
                collection: record.collection,
                id: record.id,
                data: updatedData,
              );
              await ref
                  .read(operationalRecordsProvider.notifier)
                  .updateRecord(updated);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Record updated successfully.')),
                );
              }
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
    titleController.dispose();
    unitController.dispose();
    statusController.dispose();
  }

  Future<void> _confirmDeleteRecord(OperationalRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('Confirm Deletion'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${_title(record)}"? This operational record will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref
          .read(operationalRecordsProvider.notifier)
          .deleteRecord(record.collection, record.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Record "${_title(record)}" deleted successfully.'),
          ),
        );
      }
    }
  }
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // In read-only / sample mode or Firestore mode
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Record "${_title(record)}" deleted successfully.'),
        ),
      );
    }
  }

  String _title(OperationalRecord record) {
    for (final field in const [
      'title',
      'name',
      'tenantName',
      'companyName',
      'unitNumber',
      'referenceNumber',
    ]) {
      final value = _value(record.data[field]);
      if (value.isNotEmpty) return value;
    }
    return '${_collectionName(record.collection)} record';
  }

  String _displayValue(Object? value) {
    if (value == null) return '';
    if (value is Timestamp) {
      return DateFormat.yMMMd().add_jm().format(value.toDate());
    }
    if (value is DateTime) return DateFormat.yMMMd().add_jm().format(value);
    if (value is Map) {
      return value.entries
          .map(
            (entry) =>
                '${_label(entry.key.toString())}: ${_displayValue(entry.value)}',
          )
          .join(', ');
    }
    if (value is Iterable) {
      return value
          .map(_displayValue)
          .where((item) => item.isNotEmpty)
          .join(', ');
    }
    return value.toString();
  }

  String _value(Object? value) => value?.toString().trim() ?? '';

  DateTime _recordDate(OperationalRecord record) {
    for (final field in const [
      'updatedAt',
      'createdAt',
      'paymentDate',
      'date',
    ]) {
      final value = record.data[field];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _collectionName(String value) => switch (value) {
    'units' => 'Units',
    'tenants' => 'Tenants',
    'payments' => 'Payments',
    'maintenanceTickets' => 'Maintenance',
    _ => value,
  };

  String _label(String value) => value
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match[1]} ${match[2]}',
      )
      .replaceAll('_', ' ')
      .split(' ')
      .map(
        (part) =>
            part.isEmpty ? '' : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');

  IconData _icon(String collection) => switch (collection) {
    'units' => Icons.apartment_outlined,
    'tenants' => Icons.person_outline,
    'payments' => Icons.payments_outlined,
    _ => Icons.build_outlined,
  };
}
