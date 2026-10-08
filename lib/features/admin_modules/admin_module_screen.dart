import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/config/supabase_config.dart';
import '../../core/constants/admin_routes.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/ui_components.dart';
import '../../models/landlord_account.dart';
import '../../providers/landlord_providers.dart';
import '../../providers/operational_data_providers.dart';
import '../operations/operational_data_repository.dart';

enum AdminModule {
  units,
  tenancies,
  tenants,
  payments,
  maintenance,
  utilityRates,
  documents,
  publicListings,
  listingReview,
  inquiries,
  applications,
  auditLogs,
  dataIntegrity,
  syncHealth,
  invitations,
  suspendedAccounts,
  adminUsers,
  security,
}

class AdminModuleScreen extends ConsumerStatefulWidget {
  const AdminModuleScreen({super.key, required this.module});

  final AdminModule module;

  @override
  ConsumerState<AdminModuleScreen> createState() => _AdminModuleScreenState();
}

class _AdminModuleScreenState extends ConsumerState<AdminModuleScreen> {
  String _query = '';
  String _status = 'All';
  String _landlord = 'All';
  DateTime? _lastSuccessfulRefresh;
  String _billingMonth = 'All';
  String _unit = 'All';
  String _tenant = 'All';
  String _priority = 'All';
  String _method = 'All';
  String _sortKey = 'id';
  bool _sortAscending = true;

  @override
  Widget build(BuildContext context) {
    final metadata = _metadata[widget.module]!;
    final unsupported = _requirements[widget.module];
    if (unsupported != null) {
      return _comingSoon(context, metadata, unsupported);
    }

    if (widget.module == AdminModule.invitations ||
        widget.module == AdminModule.suspendedAccounts) {
      return _accounts(context, metadata);
    }

    final records = ref.watch(operationalRecordsProvider);
    return records.when(
      loading: () =>
          _pageFrame(context, metadata, const LoadingSkeleton(rows: 6)),
      error: (error, _) => _pageFrame(
        context,
        metadata,
        widget.module == AdminModule.syncHealth
            ? _healthError(error)
            : ErrorView(
                message: 'Unable to load data.',
                onRetry: () => ref.invalidate(operationalRecordsProvider),
              ),
      ),
      data: (allRecords) {
        _lastSuccessfulRefresh = DateTime.now();
        if (widget.module == AdminModule.dataIntegrity) {
          return _pageFrame(context, metadata, _integrity(allRecords));
        }
        if (widget.module == AdminModule.syncHealth) {
          return _pageFrame(context, metadata, _health(allRecords));
        }
        return _operational(context, metadata, allRecords);
      },
    );
  }

  Widget _operational(
    BuildContext context,
    _ModuleMetadata metadata,
    List<OperationalRecord> allRecords,
  ) {
    final collection = metadata.collection!;
    final searchHint = switch (widget.module) {
      AdminModule.units => 'Search properties',
      AdminModule.tenants => 'Search tenants',
      AdminModule.payments => 'Search payment records',
      AdminModule.maintenance => 'Search tickets',
      _ => 'Search records',
    };
    final source = allRecords
        .where((record) => record.collection == collection)
        .toList();
    final landlordItems = ref.watch(landlordsProvider).value ?? const [];
    final units = allRecords
        .where((item) => item.collection == 'units')
        .toList();
    final tenantRecords = allRecords
        .where((item) => item.collection == 'tenants')
        .toList();
    final unitChoices = {
      for (final unit in units)
        unit.id: _value(unit.data['unitNumber']).isEmpty
            ? unit.id
            : _value(unit.data['unitNumber']),
    };
    final tenantChoices = {
      for (final tenant in tenantRecords)
        tenant.id: _value(tenant.data['name']).isEmpty
            ? tenant.id
            : _value(tenant.data['name']),
    };
    final billingMonths = widget.module == AdminModule.payments
        ? source
              .map(
                (record) => _firstValue(record.data, ['billingMonth', 'month']),
              )
              .where((month) => month.isNotEmpty)
              .toSet()
              .toList()
        : <String>[];
    final methods = widget.module == AdminModule.payments
        ? source
              .map(
                (record) =>
                    _firstValue(record.data, ['paymentMethod', 'method']),
              )
              .where((method) => method.isNotEmpty)
              .toSet()
              .toList()
        : <String>[];
    final statuses =
        source
            .map((record) => _value(record.data['status']))
            .where((status) => status.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final priorities =
        source
            .map((record) => _value(record.data['priority']))
            .where((priority) => priority.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final records = source.where((record) {
      final matchesStatus = _matchesStatus(record);
      final matchesLandlord =
          _landlord == 'All' || record.ownerIds.contains(_landlord);
      final matchesBillingMonth =
          _billingMonth == 'All' ||
          _firstValue(record.data, ['billingMonth', 'month']) == _billingMonth;
      final matchesMethod =
          _method == 'All' ||
          _firstValue(record.data, ['paymentMethod', 'method']) == _method;
      final matchesUnit =
          _unit == 'All' || _value(record.data['unitId']) == _unit;
      final matchesTenant =
          _tenant == 'All' || _value(record.data['tenantId']) == _tenant;
      final matchesPriority =
          _priority == 'All' || _value(record.data['priority']) == _priority;
      final searchable = '${record.id} ${record.data}'.toLowerCase();
      return matchesStatus &&
          matchesLandlord &&
          matchesBillingMonth &&
          matchesMethod &&
          matchesUnit &&
          matchesTenant &&
          matchesPriority &&
          searchable.contains(_query.toLowerCase());
    }).toList()..sort(_compareRecords);
    final statusFilters = widget.module == AdminModule.units
        ? [
            ...{
              'All',
              'Occupied',
              'Vacant',
              'Reserved',
              'Inactive',
              'Archived',
              ...statuses,
            },
          ]
        : widget.module == AdminModule.tenants
        ? [
            ...{'All', 'Current', 'Unassigned', 'Archived', ...statuses},
          ]
        : widget.module == AdminModule.maintenance
        ? [
            ...{
              'All',
              'Pending',
              'Schedule Visit',
              'Estimate',
              'Schedule Repair',
              'Completed',
              ...statuses,
            },
          ]
        : ['All', ...statuses];
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, _) {
            final search = TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: searchHint,
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            );
            final filters = <Widget>[
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: statusFilters
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(status, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _status = value ?? 'All'),
                ),
              ),
              if ({
                AdminModule.units,
                AdminModule.tenants,
                AdminModule.payments,
                AdminModule.maintenance,
              }.contains(widget.module))
                SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _landlord,
                    decoration: const InputDecoration(labelText: 'Landlord'),
                    items: [
                      const DropdownMenuItem(
                        value: 'All',
                        child: Text('All landlords'),
                      ),
                      ...landlordItems.map(
                        (landlord) => DropdownMenuItem(
                          value: landlord.uid,
                          child: Text(
                            landlord.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _landlord = value ?? 'All'),
                  ),
                ),
              if (widget.module == AdminModule.payments &&
                  billingMonths.isNotEmpty)
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _billingMonth,
                    decoration: const InputDecoration(
                      labelText: 'Billing month',
                    ),
                    items: [
                      const DropdownMenuItem(value: 'All', child: Text('All')),
                      ...billingMonths.map(
                        (month) => DropdownMenuItem(
                          value: month,
                          child: Text(month, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _billingMonth = value ?? 'All'),
                  ),
                ),
              if (widget.module == AdminModule.payments && methods.isNotEmpty)
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _method,
                    decoration: const InputDecoration(labelText: 'Method'),
                    items: [
                      const DropdownMenuItem(
                        value: 'All',
                        child: Text('All methods'),
                      ),
                      ...methods.map(
                        (method) => DropdownMenuItem(
                          value: method,
                          child: Text(method, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _method = value ?? 'All'),
                  ),
                ),
              if ({
                AdminModule.tenants,
                AdminModule.payments,
                AdminModule.maintenance,
              }.contains(widget.module))
                SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _unit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                    items: [
                      const DropdownMenuItem(
                        value: 'All',
                        child: Text('All units'),
                      ),
                      ...unitChoices.entries.map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(
                            entry.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _unit = value ?? 'All'),
                  ),
                ),
              if (widget.module == AdminModule.payments)
                SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _tenant,
                    decoration: const InputDecoration(labelText: 'Tenant'),
                    items: [
                      const DropdownMenuItem(
                        value: 'All',
                        child: Text('All tenants'),
                      ),
                      ...tenantChoices.entries.map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(
                            entry.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _tenant = value ?? 'All'),
                  ),
                ),
              if (widget.module == AdminModule.maintenance &&
                  priorities.isNotEmpty)
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: [
                      const DropdownMenuItem(value: 'All', child: Text('All')),
                      ...priorities.map(
                        (priority) => DropdownMenuItem(
                          value: priority,
                          child: Text(priority),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _priority = value ?? 'All'),
                  ),
                ),
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: widget.module == AdminModule.maintenance
                      ? const {
                              'newest',
                              'oldest',
                              'priority',
                            }.contains(_sortKey)
                            ? _sortKey
                            : 'newest'
                      : _sortKey,
                  decoration: const InputDecoration(labelText: 'Sort by'),
                  items: widget.module == AdminModule.maintenance
                      ? const [
                          DropdownMenuItem(
                            value: 'newest',
                            child: Text('Newest first'),
                          ),
                          DropdownMenuItem(
                            value: 'oldest',
                            child: Text('Oldest first'),
                          ),
                          DropdownMenuItem(
                            value: 'priority',
                            child: Text('Priority'),
                          ),
                        ]
                      : [
                          if (!metadata.keys.contains('id'))
                            const DropdownMenuItem(
                              value: 'id',
                              child: Text('Record ID'),
                            ),
                          for (final entry in metadata.keys.indexed)
                            DropdownMenuItem(
                              value: entry.$2,
                              child: Text(
                                metadata.columns[entry.$1],
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sortKey = value);
                  },
                ),
              ),
              IconButton(
                tooltip: _sortAscending ? 'Sort descending' : 'Sort ascending',
                onPressed: () =>
                    setState(() => _sortAscending = !_sortAscending),
                icon: Icon(
                  _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                ),
              ),
            ];
            final activeFilterCount = [
              _status != 'All',
              _landlord != 'All',
              _billingMonth != 'All',
              _unit != 'All',
              _tenant != 'All',
              _priority != 'All',
              _method != 'All',
            ].where((active) => active).length;
            return ResponsiveFilterToolbar(
              search: search,
              filters: filters,
              activeFilterCount: activeFilterCount,
            );
          },
        ),
        const SizedBox(height: 16),
        if (widget.module == AdminModule.payments)
          _paymentSummary(source, records),
        if (records.isEmpty)
          Card(
            child: EmptyState(
              compact: true,
              icon: _emptyIcon(),
              title: source.isEmpty
                  ? _emptyTitle()
                  : 'No records match the selected filters.',
              message: source.isEmpty
                  ? _emptyMessage()
                  : 'Clear or adjust the selected filters to see records.',
              action: source.isEmpty
                  ? null
                  : TextButton(
                      onPressed: () => setState(() {
                        _query = '';
                        _status = 'All';
                        _landlord = 'All';
                        _billingMonth = 'All';
                        _unit = 'All';
                        _tenant = 'All';
                        _priority = 'All';
                        _method = 'All';
                      }),
                      child: const Text('Clear filters'),
                    ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 700
                ? Column(
                    children: records
                        .map((record) => _recordCard(context, record))
                        .toList(),
                  )
                : Card(
                    clipBehavior: Clip.antiAlias,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        sortColumnIndex: metadata.keys.contains(_sortKey)
                            ? metadata.keys.indexOf(_sortKey)
                            : null,
                        sortAscending: _sortAscending,
                        columns: [
                          for (final entry in metadata.keys.indexed)
                            DataColumn(
                              label: Text(metadata.columns[entry.$1]),
                              onSort: widget.module == AdminModule.maintenance
                                  ? null
                                  : (_, ascending) => setState(() {
                                      _sortKey = entry.$2;
                                      _sortAscending = ascending;
                                    }),
                            ),
                        ],
                        rows: records
                            .map(
                              (record) => DataRow(
                                cells: [
                                  for (final key in metadata.keys)
                                    DataCell(
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 220,
                                        ),
                                        child:
                                            key == 'status' || key == 'priority'
                                            ? _statusChip(
                                                context,
                                                _field(record, key),
                                              )
                                            : Text(
                                                _field(record, key),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                      ),
                                    ),
                                ],
                                onSelectChanged: (_) =>
                                    _showRecord(context, record),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
          ),
      ],
    );
    return _pageFrame(context, metadata, body);
  }

  String _emptyTitle() => switch (widget.module) {
    AdminModule.units => 'No properties yet',
    AdminModule.tenants => 'No tenants yet',
    AdminModule.payments => 'No payment records yet',
    AdminModule.maintenance => 'No maintenance requests yet',
    _ => 'No records found',
  };

  String _emptyMessage() => switch (widget.module) {
    AdminModule.units => 'Properties registered by landlords will appear here once they sync with RAMP.',
    AdminModule.tenants => 'Tenant records will appear here once available.',
    AdminModule.payments => 'Payment records will appear here once available.',
    AdminModule.maintenance =>
      'Maintenance requests will appear here once submitted.',
    _ => 'No records are currently available.',
  };

  IconData _emptyIcon() => switch (widget.module) {
    AdminModule.units => Icons.domain_outlined,
    AdminModule.tenants => Icons.key_outlined,
    AdminModule.payments => Icons.receipt_long_outlined,
    AdminModule.maintenance => Icons.handyman_outlined,
    _ => Icons.inbox_outlined,
  };

  Widget _recordCard(BuildContext context, OperationalRecord record) => Card(
    child: ListTile(
      title: Text(
        _field(record, _metadata[widget.module]!.keys.first),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _metadata[widget.module]!.keys
            .skip(1)
            .map((key) => '${_label(key)}: ${_field(record, key)}')
            .join(' · '),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showRecord(context, record),
    ),
  );

  Widget _statusChip(BuildContext context, String label) {
    final normalized = label.toLowerCase();
    final color =
        normalized.contains('complete') ||
            normalized == 'paid' ||
            normalized == 'occupied' ||
            normalized == 'active'
        ? Theme.of(context).colorScheme.tertiary
        : normalized.contains('declin') ||
              normalized.contains('overdue') ||
              normalized.contains('high')
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      side: BorderSide(color: color.withAlpha(60)),
      backgroundColor: color.withAlpha(16),
      labelStyle: TextStyle(color: color, fontSize: 12),
    );
  }

  int _compareRecords(OperationalRecord left, OperationalRecord right) {
    int comparison;
    if (widget.module == AdminModule.maintenance) {
      if (_sortKey == 'priority') {
        comparison = _priorityRank(_value(left.data['priority']))
            .compareTo(_priorityRank(_value(right.data['priority'])));
      } else {
        final leftDate = _dateValue(left.data['createdAt']);
        final rightDate = _dateValue(right.data['createdAt']);
        comparison = _compareDates(
          leftDate,
          rightDate,
          descending: _sortKey != 'oldest',
        );
      }
    } else {
      comparison = _field(
        left,
        _sortKey,
      ).toLowerCase().compareTo(_field(right, _sortKey).toLowerCase());
    }
    return _sortAscending ? comparison : -comparison;
  }

  int _priorityRank(String priority) => switch (priority.toLowerCase()) {
    'urgent' => 0,
    'high' => 1,
    'medium' => 2,
    'low' => 3,
    _ => 4,
  };

  int _compareDates(
    DateTime? left,
    DateTime? right, {
    required bool descending,
  }) {
    if (left == null) return right == null ? 0 : 1;
    if (right == null) return -1;
    final comparison = left.compareTo(right);
    return descending ? -comparison : comparison;
  }

  DateTime? _dateValue(Object? value) => switch (value) {
    DateTime date => date,
    String date => DateTime.tryParse(date),
    _ => null,
  };

  Widget _paymentSummary(
    List<OperationalRecord> source,
    List<OperationalRecord> visible,
  ) {
    final currency = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );
    final rentPayments = source.where(
      (record) =>
          _value(record.data['transactionType']).trim().toLowerCase() == 'rent',
    );
    List<OperationalRecord> withStatus(String status) => rentPayments
        .where(
          (record) =>
              _value(record.data['status']).trim().toLowerCase() == status,
        )
        .toList();
    String totalFor(String status) {
      final selected = withStatus(status);
      if (selected.any((record) {
        final amount = record.data['amount'];
        return amount is! num || !amount.isFinite || amount < 0;
      })) {
        return 'Unavailable';
      }
      return currency.format(
        selected.fold<double>(
          0,
          (sum, record) => sum + _number(record.data['amount']),
        ),
      );
    }

    final actualMaintenanceCost =
        (ref.read(operationalRecordsProvider).value ??
                const <OperationalRecord>[])
            .where((record) => record.collection == 'maintenanceTickets')
            .where((record) => record.data['actualCost'] is num)
            .fold<double>(
              0,
              (sum, record) => sum + _number(record.data['actualCost']),
            );
    final counts = <String, int>{
      'Declined': withStatus('declined').length,
      'Reversed': withStatus('reversed').length,
    };
    final values = <(String, String)>[
      ('Collected', totalFor('paid')),
      ('Pending', totalFor('pending')),
      ('Overdue', totalFor('overdue')),
      ('Declined', '${counts['Declined']}'),
      ('Maintenance Costs', currency.format(actualMaintenanceCost)),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 850 ? values.length : 2;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                for (final value in values)
                  SizedBox(
                    width: width,
                    child: _summaryMetric(value.$1, value.$2),
                  ),
                Text(
                  '${visible.length} of ${source.length} shown',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _summaryMetric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 3),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );

  double _number(Object? value) =>
      value is num && value.isFinite ? value.toDouble() : 0;

  String _firstValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = _value(data[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Widget _integrity(List<OperationalRecord> records) {
    final issues = _findIssues(records);
    if (issues.isEmpty) {
      return const EmptyState(
        compact: true,
        icon: Icons.verified_user_outlined,
        title: 'No integrity issues detected',
        message: 'No issues were found in the loaded operational records.',
      );
    }
    return Column(
      children: issues
          .map(
            (issue) => Card(
              child: ListTile(
                leading: Icon(
                  issue.severity == 'High'
                      ? Icons.error_outline
                      : Icons.warning_amber_outlined,
                ),
                title: Text(issue.type),
                subtitle: Text(
                  '${issue.collection}/${issue.id} · ${issue.description}\nSuggested action: ${issue.action}',
                ),
                trailing: Chip(label: Text(issue.severity)),
              ),
            ),
          )
          .toList(),
    );
  }

  List<_IntegrityIssue> _findIssues(List<OperationalRecord> records) {
    final units = records.where((r) => r.collection == 'units').toList();
    final tenants = records.where((r) => r.collection == 'tenants').toList();
    final payments = records.where((r) => r.collection == 'payments').toList();
    final tickets = records
        .where((r) => r.collection == 'maintenanceTickets')
        .toList();
    final unitIds = units.map((r) => r.id).toSet();
    final tenantIds = tenants.map((r) => r.id).toSet();
    final unitsById = {for (final unit in units) unit.id: unit};
    final tenantsById = {for (final tenant in tenants) tenant.id: tenant};
    final issues = <_IntegrityIssue>[];

    void checkOwnerLink(
      OperationalRecord record,
      OperationalRecord? related,
      String relation,
    ) {
      final ownerId = record.ownerId;
      final relatedOwnerId = related?.ownerId ?? '';
      if (ownerId.isNotEmpty &&
          relatedOwnerId.isNotEmpty &&
          ownerId != relatedOwnerId) {
        issues.add(
          _IntegrityIssue(
            'Relationship crosses landlord ownership',
            record.collection,
            record.id,
            'High',
            '$relation references a record owned by a different landlord.',
            action: 'Verify the linked records and ownership assignments; do not reassign automatically.',
          ),
        );
      }
    }

    void inspect(OperationalRecord record) {
      if (record.hasConflictingOwnerIds) {
        issues.add(
          _IntegrityIssue(
            'Ownership fields disagree',
            record.collection,
            record.id,
            'High',
            'landlordId and landlord_id identify different accounts.',
          ),
        );
      } else if (record.ownerIds.isEmpty) {
        issues.add(
          _IntegrityIssue(
            'Missing landlordId',
            record.collection,
            record.id,
            'Medium',
            'Operational record has no explicit landlord owner.',
          ),
        );
      }
    }

    for (final record in [...units, ...tenants, ...payments, ...tickets]) {
      inspect(record);
    }
    for (final tenant in tenants) {
      final unitId = _value(tenant.data['unitId']);
      if (unitId.isNotEmpty && !unitIds.contains(unitId)) {
        issues.add(
          _IntegrityIssue(
            'Tenant references missing unit',
            tenant.collection,
            tenant.id,
            'High',
            'Referenced unit $unitId was not found.',
          ),
        );
      } else if (unitId.isNotEmpty) {
        checkOwnerLink(tenant, unitsById[unitId], 'Tenant unitId');
      }
    }
    for (final unit in units) {
      final tenantId = _value(unit.data['tenantId']);
      if (tenantId.isNotEmpty && !tenantIds.contains(tenantId)) {
        issues.add(
          _IntegrityIssue(
            'Unit references missing tenant',
            unit.collection,
            unit.id,
            'High',
            'Referenced tenant $tenantId was not found.',
          ),
        );
      } else if (tenantId.isNotEmpty) {
        checkOwnerLink(unit, tenantsById[tenantId], 'Unit tenantId');
      }
      if (_value(unit.data['currentTenancyId']).isNotEmpty) {
        issues.add(
          _IntegrityIssue(
            'Unit current tenancy cannot be verified',
            unit.collection,
            unit.id,
            'Low',
            'A currentTenancyId is present, but no confirmed tenancy source is configured.',
            action:
                'Configure a tenancy source before validating this reference.',
          ),
        );
      }
    }
    for (final payment in payments) {
      final tenantId = _value(payment.data['tenantId']);
      if (tenantId.isNotEmpty && !tenantIds.contains(tenantId)) {
        issues.add(
          _IntegrityIssue(
            'Payment references missing tenant',
            payment.collection,
            payment.id,
            'High',
            'Referenced tenant $tenantId was not found.',
          ),
        );
      } else if (tenantId.isNotEmpty) {
        checkOwnerLink(payment, tenantsById[tenantId], 'Payment tenantId');
      }
      final unitId = _value(payment.data['unitId']);
      if (unitId.isNotEmpty && !unitIds.contains(unitId)) {
        issues.add(
          _IntegrityIssue(
            'Payment references missing unit',
            payment.collection,
            payment.id,
            'High',
            'Referenced unit $unitId was not found.',
          ),
        );
      } else if (unitId.isNotEmpty) {
        checkOwnerLink(payment, unitsById[unitId], 'Payment unitId');
      }
      final tenancyId = _value(payment.data['tenancyId']);
      if (tenancyId.isEmpty) {
        issues.add(
          _IntegrityIssue(
            'Payment missing tenancyId',
            payment.collection,
            payment.id,
            'Medium',
            'Payment does not reference a tenancy.',
          ),
        );
      } else {
        issues.add(
          _IntegrityIssue(
            'Payment tenancy cannot be verified',
            payment.collection,
            payment.id,
            'Low',
            'A tenancyId is present, but no confirmed tenancy source is configured.',
            action:
                'Configure a tenancy source before validating this reference.',
          ),
        );
      }
    }
    for (final ticket in tickets) {
      final tenantId = _value(ticket.data['tenantId']);
      if (tenantId.isNotEmpty && !tenantIds.contains(tenantId)) {
        issues.add(
          _IntegrityIssue(
            'Maintenance ticket references missing tenant',
            ticket.collection,
            ticket.id,
            'High',
            'Referenced tenant $tenantId was not found.',
          ),
        );
      } else if (tenantId.isNotEmpty) {
        checkOwnerLink(ticket, tenantsById[tenantId], 'Maintenance tenantId');
      }
      if (_value(ticket.data['unitId']).isEmpty) {
        issues.add(
          _IntegrityIssue(
            'Maintenance ticket missing unitId',
            ticket.collection,
            ticket.id,
            'Medium',
            'Ticket does not reference a unit.',
          ),
        );
      } else if (!unitIds.contains(_value(ticket.data['unitId']))) {
        issues.add(
          _IntegrityIssue(
            'Maintenance ticket references missing unit',
            ticket.collection,
            ticket.id,
            'High',
            'Referenced unit ${ticket.data['unitId']} was not found.',
          ),
        );
      } else {
        checkOwnerLink(
          ticket,
          unitsById[_value(ticket.data['unitId'])],
          'Maintenance unitId',
        );
      }
    }
    final tenantIdsByCollection = <String, Map<String, int>>{};
    for (final record in records) {
      final ids = tenantIdsByCollection.putIfAbsent(
        record.collection,
        () => <String, int>{},
      );
      ids.update(record.id, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final entry in tenantIdsByCollection.entries) {
      for (final duplicate in entry.value.entries.where(
        (item) => item.value > 1,
      )) {
        issues.add(
          _IntegrityIssue(
            'Duplicate record ID',
            entry.key,
            duplicate.key,
            'High',
            'The loaded result contains this ID ${duplicate.value} times.',
            action: 'Review the source table and confirm its primary-key integrity.',
          ),
        );
      }
    }
    for (final tenant in tenants) {
      if (_value(tenant.data['currentTenancyId']).isNotEmpty) {
        issues.add(
          _IntegrityIssue(
            'Current tenancy reference cannot be verified',
            tenant.collection,
            tenant.id,
            'Low',
            'A currentTenancyId is present, but no confirmed tenancies source is configured.',
            action: 'Configure the tenancy source before validating this reference.',
          ),
        );
      }
    }
    return issues;
  }

  Widget _health(List<OperationalRecord> records) {
    final counts = <String, int>{
      for (final collection in const [
        'units',
        'tenants',
        'payments',
        'maintenanceTickets',
      ])
        collection: records.where((r) => r.collection == collection).length,
    };
    final firebaseAvailable = Firebase.apps.isNotEmpty;
    final user = firebaseAvailable ? FirebaseAuth.instance.currentUser : null;
    final configured =
        SupabaseConfig.url.isNotEmpty && SupabaseConfig.anonKey.isNotEmpty;
    return Column(
      children: [
        _healthRow(
          'Firebase Auth',
          !firebaseAvailable
              ? 'Firebase is not initialized'
              : user == null
              ? 'No signed-in user'
              : 'Signed-in session available',
        ),
        _healthRow(
          'Supabase configuration',
          configured
              ? 'Environment values present'
              : 'Missing environment configuration',
        ),
        _healthRow(
          'Supabase client',
          configured ? 'Initialized · operational data loaded' : 'Unavailable',
        ),
        _healthRow('Latest repository error', 'None reported in this refresh'),
        _healthRow(
          'Latest successful refresh',
          _lastSuccessfulRefresh?.toLocal().toString() ?? 'Not recorded',
        ),
        for (final entry in counts.entries)
          _healthRow(entry.key, '${entry.value} records · connected'),
        _developerTools(context),
      ],
    );
  }

  Widget _healthError(Object error) {
    final firebaseAvailable = Firebase.apps.isNotEmpty;
    final user = firebaseAvailable ? FirebaseAuth.instance.currentUser : null;
    final configured =
        SupabaseConfig.url.isNotEmpty && SupabaseConfig.anonKey.isNotEmpty;
    return Column(
      children: [
        _healthRow(
          'Firebase Auth',
          !firebaseAvailable
              ? 'Firebase is not initialized'
              : user == null
              ? 'No signed-in user'
              : 'Signed-in session available',
        ),
        _healthRow(
          'Supabase configuration',
          configured
              ? 'Environment values present'
              : 'Missing environment configuration',
        ),
        _healthRow(
          'Supabase client',
          configured ? 'Configured · operational query failed' : 'Unavailable',
        ),
        _healthRow(
          'Latest repository error',
          '${error.runtimeType}: Operational table load failed. Details are available in application logs.',
        ),
        _healthRow(
          'Latest successful refresh',
          _lastSuccessfulRefresh?.toLocal().toString() ?? 'Not recorded',
        ),
        _developerTools(context),
      ],
    );
  }

  Widget _developerTools(BuildContext context) => Card(
    child: ExpansionTile(
      title: const Text('Advanced / Developer Tools'),
      children: [
        ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: const Text('Raw Data Inspector'),
          subtitle: const Text('Read-only operational record diagnostics.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go(AdminRoutes.operations),
        ),
      ],
    ),
  );

  Widget _healthRow(String label, String value) => Card(
    child: ListTile(
      leading: Icon(
        value.toLowerCase().contains('failed') ||
                value.toLowerCase().contains('missing') ||
                value.toLowerCase().contains('unavailable')
            ? Icons.error_outline
            : Icons.check_circle_outline,
      ),
      title: Text(label),
      subtitle: Text(value),
    ),
  );

  Widget _accounts(BuildContext context, _ModuleMetadata metadata) {
    final accounts = ref.watch(landlordsProvider);
    return accounts.when(
      loading: () =>
          _pageFrame(context, metadata, const LoadingSkeleton(rows: 5)),
      error: (error, _) => _pageFrame(
        context,
        metadata,
        ErrorView(message: 'Landlord accounts could not be loaded: $error'),
      ),
      data: (items) {
        final status = widget.module == AdminModule.invitations
            ? LandlordStatus.invited
            : LandlordStatus.suspended;
        final selected = items.where((item) => item.status == status).toList();
        final body = selected.isEmpty
            ? EmptyState(
                title: widget.module == AdminModule.invitations
                    ? 'No pending invitations'
                    : 'No suspended accounts',
                message: 'No landlord accounts currently match this status.',
              )
            : Column(
                children: selected
                    .map(
                      (item) => Card(
                        child: ListTile(
                          title: Text(item.displayName),
                          subtitle: Text('${item.email} · ${item.companyName}'),
                          trailing: Chip(
                            label: Text(
                              items
                                  .firstWhere((item) => item.status == status)
                                  .statusLabel,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
        return _pageFrame(context, metadata, body);
      },
    );
  }

  Widget _comingSoon(
    BuildContext context,
    _ModuleMetadata metadata,
    String requirement,
  ) => _pageFrame(
    context,
    metadata,
    EmptyState(title: 'Backend support required', message: requirement),
  );

  Widget _pageFrame(
    BuildContext context,
    _ModuleMetadata metadata,
    Widget body,
  ) => SingleChildScrollView(
    padding: EdgeInsets.all(
      MediaQuery.sizeOf(context).width < 400
          ? 16
          : MediaQuery.sizeOf(context).width < 700
          ? 20
          : 28,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(title: metadata.title, subtitle: metadata.description),
        const SizedBox(height: 20),
        body,
      ],
    ),
  );

  void _showRecord(BuildContext context, OperationalRecord record) {
    final allRecords = ref.read(operationalRecordsProvider).value ?? const [];
    final tenantId = record.collection == 'tenants'
        ? record.id
        : _value(record.data['tenantId'] ?? record.data['currentTenantId']);
    final unitId = record.collection == 'units'
        ? record.id
        : _value(record.data['unitId']);
    final relatedPayments = allRecords.where((item) {
      return item.collection == 'payments' &&
          ((tenantId.isNotEmpty && _value(item.data['tenantId']) == tenantId) ||
              (unitId.isNotEmpty && _value(item.data['unitId']) == unitId));
    }).toList();
    final relatedMaintenance = allRecords.where((item) {
      return item.collection == 'maintenanceTickets' &&
          ((tenantId.isNotEmpty && _value(item.data['tenantId']) == tenantId) ||
              (unitId.isNotEmpty && _value(item.data['unitId']) == unitId));
    }).toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '${_metadata[widget.module]!.title} · ${record.id}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              for (final entry in record.data.entries)
                ListTile(
                  dense: true,
                  title: Text(_label(entry.key)),
                  subtitle: SelectableText(_value(entry.value)),
                ),
              ListTile(
                title: const Text('Record ID'),
                subtitle: SelectableText(record.id),
              ),
              ListTile(
                title: const Text('Ownership'),
                subtitle: Text(record.ownerDescription),
              ),
              if (record.collection == 'tenants' ||
                  record.collection == 'units') ...[
                const Divider(),
                const ListTile(title: Text('Linked payment history')),
                if (relatedPayments.isEmpty)
                  const ListTile(title: Text('No linked payment records')),
                for (final item in relatedPayments)
                  ListTile(
                    title: Text('Payment · ${item.id}'),
                    subtitle: Text(
                      '${_value(item.data['status'])} · ${_value(item.data['amount'])}',
                    ),
                  ),
                const ListTile(title: Text('Linked maintenance history')),
                if (relatedMaintenance.isEmpty)
                  const ListTile(title: Text('No linked maintenance records')),
                for (final item in relatedMaintenance)
                  ListTile(
                    title: Text('Ticket · ${item.id}'),
                    subtitle: Text(
                      '${_value(item.data['status'])} · ${_value(item.data['title'])} · ${_value(item.data['actualCost'])}',
                    ),
                  ),
                const ListTile(
                  title: Text('Tenancy history and documents'),
                  subtitle: Text(
                    'These records are unavailable because tenancy and document backend sources are not configured.',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _field(OperationalRecord record, String key) {
    if (key == 'id') return record.id;
    if (key == 'status') {
      final rawStatus = _value(record.data['status']);
      const knownStatuses = {
        AdminModule.units: {
          'occupied',
          'vacant',
          'reserved',
          'inactive',
          'archived',
        },
        AdminModule.tenants: {'active', 'former', 'archived'},
        AdminModule.payments: {
          'paid',
          'pending',
          'declined',
          'reversed',
          'recorded',
        },
        AdminModule.maintenance: {
          'pending',
          'schedule visit',
          'estimate',
          'schedule repair',
          'completed',
        },
      };
      final known = knownStatuses[widget.module];
      final normalized = _normalizedStatus(rawStatus);
      if (rawStatus.isEmpty) return 'Unknown / missing';
      return known == null || known.contains(normalized)
          ? rawStatus
          : 'Unknown / $rawStatus';
    }
    if (key == 'currentTenancyId' || key == 'tenancyId') {
      final tenancyId = _value(record.data[key]);
      return tenancyId.isEmpty
          ? 'Missing'
          : 'Unverified · $tenancyId (tenancy source not configured)';
    }
    if (key == 'isArchived') {
      final archived = record.data['isArchived'] ?? record.data['archived'];
      if (archived is bool) return archived ? 'Archived' : 'Not archived';
      if (_value(record.data['archivedAt']).isNotEmpty ||
          _value(record.data['status']).toLowerCase() == 'archived') {
        return 'Archived';
      }
      return 'Not recorded';
    }
    if (key == 'landlordId') {
      if (record.hasConflictingOwnerIds) {
        return 'Inconsistent: ${record.ownerIds.join(' / ')}';
      }
      final ownerId = record.ownerId;
      if (ownerId.isEmpty) return 'Unassigned';
      final landlords = ref.read(landlordsProvider).value ?? const [];
      return landlords
              .where((landlord) => landlord.uid == ownerId)
              .map((landlord) => landlord.displayName)
              .firstOrNull ??
          ownerId;
    }
    if (key == 'unitNumber') {
      final direct = _firstValue(record.data, ['unitNumber', 'unitName']);
      if (direct.isNotEmpty) return direct;
      final unitId = _value(record.data['unitId']);
      if (unitId.isEmpty) return '';
      final unit = _findRecord('units', unitId);
      if (unit == null) return unitId;
      final unitNumber = _firstValue(unit.data, ['unitNumber', 'unitName']);
      return unitNumber.isEmpty ? unitId : unitNumber;
    }
    if (key == 'tenantName') {
      final direct = _firstValue(
        record.data,
        record.collection == 'tenants'
            ? ['name', 'displayName']
            : ['tenantName'],
      );
      if (direct.isNotEmpty) return direct;
      final tenantId = _value(
        record.data['tenantId'] ?? record.data['currentTenantId'],
      );
      if (tenantId.isEmpty) return '';
      final tenant = _findRecord('tenants', tenantId);
      if (tenant == null) return tenantId;
      final name = _firstValue(tenant.data, ['name', 'displayName']);
      return name.isEmpty ? tenantId : name;
    }
    if (key == 'title') {
      return _firstValue(record.data, ['title', 'propertyName', 'name']);
    }
    if (key == 'month') {
      return _firstValue(record.data, ['billingMonth', 'month']);
    }
    if (key == 'paymentMethod') {
      return _firstValue(record.data, ['paymentMethod', 'method']);
    }
    if (key == 'paymentDate') {
      return _firstValue(record.data, [
        'paymentDate',
        'paidAt',
        'payment_date',
      ]);
    }
    if (key == 'waterCharge') {
      return _firstValue(record.data, [
        'waterBill',
        'waterCharge',
        'waterAmount',
      ]);
    }
    if (key == 'electricityCharge') {
      return _firstValue(record.data, [
        'electricBill',
        'electricityBill',
        'electricityCharge',
        'electricityAmount',
      ]);
    }
    if (key == 'otherCharge') {
      return _firstValue(record.data, ['otherCharges', 'otherCharge']);
    }
    if (key == 'floor') {
      return _firstValue(record.data, ['location', 'address', 'floor', 'city']);
    }
    if (key == 'visitDate') {
      return _firstValue(record.data, [
        'visitDate',
        'visitScheduledAt',
        'visitScheduledDate',
        'scheduledVisitAt',
        'scheduledVisitDate',
      ]);
    }
    if (key == 'repairDate') {
      return _firstValue(record.data, [
        'repairDate',
        'repairScheduledAt',
        'repairScheduledDate',
        'scheduledRepairAt',
        'scheduledRepairDate',
      ]);
    }
    if (key == 'assignedTo') {
      return _firstValue(record.data, [
        'assignedToName',
        'assignedTo',
        'assignedContractor',
        'contractorName',
        'contractor',
      ]);
    }
    if (key == 'leasePeriod') {
      final start = _value(record.data['leaseStart']);
      final end = _value(record.data['leaseEnd']);
      return [start, end].where((value) => value.isNotEmpty).join(' – ');
    }
    if (key == 'utilities') {
      return [
        if (record.data['waterBill'] != null)
          'Water ${_value(record.data['waterBill'])}',
        if (record.data['electricBill'] != null)
          'Electricity ${_value(record.data['electricBill'])}',
      ].join(' · ');
    }
    return _value(record.data[key]);
  }

  OperationalRecord? _findRecord(String collection, String id) =>
      (ref.read(operationalRecordsProvider).value ?? const [])
          .where((record) => record.collection == collection && record.id == id)
          .firstOrNull;

  bool _matchesStatus(OperationalRecord record) {
    if (_status == 'All') return true;
    if (widget.module == AdminModule.units) {
      if (_status == 'Archived') {
        return _isArchived(record);
      }
      if (_isArchived(record)) return false;
      if (_status == 'Inactive') {
        return _normalizedStatus(_value(record.data['status'])) == 'inactive';
      }
      return _normalizedStatus(_value(record.data['status'])) ==
          _normalizedStatus(_status);
    }
    if (widget.module == AdminModule.tenants) {
      if (_status == 'Archived') return _isArchived(record);
      if (_isArchived(record)) return false;
      if (_status == 'Unassigned') {
        return _value(record.data['unitId']).isEmpty;
      }
      if (_status == 'Current') {
        return record.data['isArchived'] != true &&
            _value(record.data['unitId']).isNotEmpty;
      }
    }
    return _normalizedStatus(_value(record.data['status'])) ==
        _normalizedStatus(_status);
  }

  bool _isArchived(OperationalRecord record) =>
      record.data['isArchived'] == true ||
      record.data['archived'] == true ||
      _value(record.data['archivedAt']).isNotEmpty ||
      _normalizedStatus(_value(record.data['status'])) == 'archived';

  String _normalizedStatus(String value) =>
      value.replaceAll('_', ' ').replaceAll('-', ' ').toLowerCase().trim();

  String _label(String key) => key
      .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]}')
      .replaceAll('_', ' ')
      .replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());

  String _value(Object? value) => value?.toString().trim() ?? '';
}

class _IntegrityIssue {
  const _IntegrityIssue(
    this.type,
    this.collection,
    this.id,
    this.severity,
    this.description, {
    this.action = 'Review the source record and confirm its relationships.',
  });

  final String type;
  final String collection;
  final String id;
  final String severity;
  final String description;
  final String action;
}

class _ModuleMetadata {
  const _ModuleMetadata(
    this.title,
    this.description, {
    this.collection,
    this.columns = const [],
    this.keys = const [],
  });

  final String title;
  final String description;
  final String? collection;
  final List<String> columns;
  final List<String> keys;
}

const _metadata = <AdminModule, _ModuleMetadata>{
  AdminModule.units: _ModuleMetadata(
    'Properties',
    'Manage units across landlord portfolios.',
    collection: 'units',
    columns: [
      'Unit ID',
      'Unit Number',
      'Property',
      'Location',
      'Status',
      'Monthly Rent',
      'Tenant',
      'Current Tenancy',
      'Landlord',
      'Archived',
    ],
    keys: [
      'id',
      'unitNumber',
      'title',
      'floor',
      'status',
      'monthlyRent',
      'tenantName',
      'currentTenancyId',
      'landlordId',
      'isArchived',
    ],
  ),
  AdminModule.tenants: _ModuleMetadata(
    'Tenants',
    'View tenants and their current property assignments.',
    collection: 'tenants',
    columns: [
      'Tenant',
      'Current Unit',
      'Landlord',
      'Current Tenancy',
      'Status',
      'Balance',
      'Lease Period',
      'Archived',
    ],
    keys: [
      'name',
      'unitNumber',
      'landlordId',
      'currentTenancyId',
      'status',
      'balance',
      'leasePeriod',
      'isArchived',
    ],
  ),
  AdminModule.payments: _ModuleMetadata(
    'Payments & Billing',
    'Review rent payments, balances, and transaction status.',
    collection: 'payments',
    columns: [
      'Reference',
      'Tenant',
      'Tenancy',
      'Unit',
      'Landlord',
      'Month',
      'Amount',
      'Status',
      'Method',
      'Date',
      'Base Rent',
      'Water',
      'Electricity',
      'Late Fee',
      'Other Charges',
    ],
    keys: [
      'referenceNumber',
      'tenantName',
      'tenancyId',
      'unitNumber',
      'landlordId',
      'month',
      'amount',
      'status',
      'paymentMethod',
      'paymentDate',
      'baseRent',
      'waterCharge',
      'electricityCharge',
      'lateFee',
      'otherCharge',
    ],
  ),
  AdminModule.maintenance: _ModuleMetadata(
    'Maintenance',
    'Track maintenance requests and repair progress.',
    collection: 'maintenanceTickets',
    columns: [
      'Ticket',
      'Unit',
      'Tenant',
      'Landlord',
      'Priority',
      'Category',
      'Stage',
      'Created',
      'Visit Date',
      'Repair Date',
      'Contractor',
      'Estimate',
      'Actual Cost',
    ],
    keys: [
      'id',
      'unitNumber',
      'tenantName',
      'landlordId',
      'priority',
      'category',
      'status',
      'createdAt',
      'visitDate',
      'repairDate',
      'assignedTo',
      'estimatedCost',
      'actualCost',
    ],
  ),
  AdminModule.tenancies: _ModuleMetadata(
    'Tenancies',
    'Tenancy records are not currently available from a confirmed Supabase table.',
  ),
  AdminModule.utilityRates: _ModuleMetadata(
    'Utility Rates',
    'Utility rate history',
  ),
  AdminModule.documents: _ModuleMetadata('Documents', 'Documents'),
  AdminModule.publicListings: _ModuleMetadata('Public Listings', 'Listings'),
  AdminModule.listingReview: _ModuleMetadata(
    'Listing Review',
    'Listing review',
  ),
  AdminModule.inquiries: _ModuleMetadata('Inquiries', 'Inquiries'),
  AdminModule.applications: _ModuleMetadata('Applications', 'Applications'),
  AdminModule.auditLogs: _ModuleMetadata(
    'Audit & Activity',
    'Administrator activity history.',
  ),
  AdminModule.dataIntegrity: _ModuleMetadata(
    'Data Health',
    'Review ownership and relationship issues in operational records.',
  ),
  AdminModule.syncHealth: _ModuleMetadata(
    'System Health',
    'Review service configuration and operational connectivity.',
  ),
  AdminModule.invitations: _ModuleMetadata(
    'Invitations',
    'Landlord accounts awaiting activation.',
  ),
  AdminModule.suspendedAccounts: _ModuleMetadata(
    'Suspended Accounts',
    'Landlord accounts currently suspended.',
  ),
  AdminModule.adminUsers: _ModuleMetadata('Admin Users', 'Admin identities'),
  AdminModule.security: _ModuleMetadata('Security', 'Security controls'),
};

const _requirements = <AdminModule, String>{
  AdminModule.tenancies: 'No confirmed Supabase tenancies table is configured. A table name and schema are required before tenancy records can be shown.',
  AdminModule.utilityRates: 'A confirmed utility-rate history table/schema and current-rate source are required. No historical entries are fabricated.',
  AdminModule.documents: 'A confirmed documents table and document metadata contract are required.',
  AdminModule.publicListings: 'A confirmed public-listings table and publication workflow are required.',
  AdminModule.listingReview: 'A confirmed listing-review workflow and backend operations are required.',
  AdminModule.inquiries:
      'A confirmed inquiries table and backend workflow are required.',
  AdminModule.applications:
      'A confirmed applications table and backend workflow are required.',
  AdminModule.adminUsers:
      'A supported admin-user listing and management API is required.',
  AdminModule.security:
      'Security policy management endpoints are not configured.',
};

const adminModuleRoutes = {
  AdminModule.units: AdminRoutes.units,
  AdminModule.tenancies: AdminRoutes.tenancies,
  AdminModule.tenants: AdminRoutes.tenants,
  AdminModule.payments: AdminRoutes.payments,
  AdminModule.maintenance: AdminRoutes.maintenance,
  AdminModule.utilityRates: AdminRoutes.utilityRates,
  AdminModule.documents: AdminRoutes.documents,
  AdminModule.publicListings: AdminRoutes.publicListings,
  AdminModule.listingReview: AdminRoutes.listingReview,
  AdminModule.inquiries: AdminRoutes.inquiries,
  AdminModule.applications: AdminRoutes.applications,
  AdminModule.auditLogs: AdminRoutes.auditLogs,
  AdminModule.dataIntegrity: AdminRoutes.dataIntegrity,
  AdminModule.syncHealth: AdminRoutes.syncHealth,
  AdminModule.invitations: AdminRoutes.invitations,
  AdminModule.suspendedAccounts: AdminRoutes.suspendedAccounts,
  AdminModule.adminUsers: AdminRoutes.adminUsers,
  AdminModule.security: AdminRoutes.security,
};

String adminModuleTitle(String route) {
  for (final entry in adminModuleRoutes.entries) {
    if (entry.value == route) return _metadata[entry.key]!.title;
  }
  return 'Overview';
}
