import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/ui_components.dart';
import '../../models/admin_audit_log.dart';
import '../../providers/activity_providers.dart';

class AdminActivityScreen extends ConsumerStatefulWidget {
  const AdminActivityScreen({super.key});
  @override
  ConsumerState<AdminActivityScreen> createState() =>
      _AdminActivityScreenState();
}

String _actor(AdminAuditLog log) => log.actorEmail.isNotEmpty
    ? log.actorEmail
    : log.actorId.isNotEmpty
    ? log.actorId
    : 'Not recorded';

class _AdminActivityScreenState extends ConsumerState<AdminActivityScreen> {
  String query = '';
  String? action;
  String? admin;
  String? entity;
  String target = '';
  DateTimeRange? dates;
  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(activityLogsProvider);
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 700 ? 20 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Audit & Activity',
            subtitle: 'Review administrator actions recorded in the platform audit log.',
          ),
          const SizedBox(height: 22),
          logs.when(
            loading: () => const LoadingSkeleton(rows: 8),
            error: (_, _) => ErrorView(
              message: 'Administrative activity could not be loaded.',
              onRetry: () => ref.invalidate(activityLogsProvider),
            ),
            data: (items) {
              final actions =
                  items
                      .map((log) => log.action)
                      .where((value) => value.isNotEmpty)
                      .toSet()
                      .toList()
                    ..sort();
              final administrators =
                  items
                      .map((log) => log.actorEmail)
                      .where((email) => email.isNotEmpty)
                      .toSet()
                      .toList()
                    ..sort();
              final entities =
                  items
                      .map((log) => log.targetType)
                      .where((type) => type.isNotEmpty)
                      .toSet()
                      .toList()
                    ..sort();
              if (admin != null && !administrators.contains(admin)) {
                admin = null;
              }
              if (entity != null && !entities.contains(entity)) entity = null;
              final filtered = items.where(_matches).toList();
              return Column(
                children: [
                  _filters(administrators, entities, actions),
                  const SizedBox(height: 16),
                  if (filtered.isEmpty)
                    Card(
                      child: EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: items.isEmpty
                            ? 'No audit records found'
                            : 'No records match filters',
                        message: items.isEmpty
                            ? 'The audit log contains no records.'
                            : 'Try changing your audit filters.',
                      ),
                    )
                  else
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            constraints.maxWidth < 780
                            ? Column(children: filtered.map(_card).toList())
                            : _table(filtered),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _filters(
    List<String> administrators,
    List<String> entities,
    List<String> actions,
  ) => ResponsiveFilterToolbar(
    search: TextField(
      onChanged: (value) => setState(() => query = value.toLowerCase()),
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText: 'Search activity',
      ),
    ),
    filters: [
      SizedBox(
        width: 200,
        child: DropdownButtonFormField<String?>(
          isExpanded: true,
          initialValue: action,
          decoration: const InputDecoration(labelText: 'Action type'),
          items: [
            const DropdownMenuItem(value: null, child: Text('All actions')),
            ...actions.map(
              (value) =>
                  DropdownMenuItem(value: value, child: Text(_title(value))),
            ),
          ],
          onChanged: (value) => setState(() => action = value),
        ),
      ),
      SizedBox(
        width: 220,
        child: DropdownButtonFormField<String?>(
          isExpanded: true,
          initialValue: admin,
          decoration: const InputDecoration(labelText: 'Administrator'),
          items: [
            const DropdownMenuItem(
              value: null,
              child: Text('All administrators'),
            ),
            ...administrators.map(
              (email) => DropdownMenuItem(value: email, child: Text(email)),
            ),
          ],
          onChanged: (value) => setState(() => admin = value),
        ),
      ),
      SizedBox(
        width: 200,
        child: TextField(
          onChanged: (value) => setState(() => target = value.toLowerCase()),
          decoration: const InputDecoration(labelText: 'Entity ID'),
        ),
      ),
      SizedBox(
        width: 200,
        child: DropdownButtonFormField<String?>(
          isExpanded: true,
          initialValue: entity,
          decoration: const InputDecoration(labelText: 'Entity'),
          items: [
            const DropdownMenuItem(value: null, child: Text('All entities')),
            ...entities.map(
              (value) => DropdownMenuItem(value: value, child: Text(value)),
            ),
          ],
          onChanged: (value) => setState(() => entity = value),
        ),
      ),
      OutlinedButton.icon(
        onPressed: _pickDates,
        icon: const Icon(Icons.date_range),
        label: Text(
          dates == null
              ? 'Date range'
              : '${DateFormat.MMMd().format(dates!.start)} – ${DateFormat.MMMd().format(dates!.end)}',
        ),
      ),
    ],
    activeFilterCount:
        (query.isNotEmpty ? 1 : 0) +
        (action == null ? 0 : 1) +
        (admin == null ? 0 : 1) +
        (target.isNotEmpty ? 1 : 0) +
        (entity == null ? 0 : 1) +
        (dates == null ? 0 : 1),
  );

  Widget _table(List<AdminAuditLog> logs) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      columns: const [
        DataColumn(label: Text('TIME')),
        DataColumn(label: Text('ADMINISTRATOR')),
        DataColumn(label: Text('ACTION')),
        DataColumn(label: Text('TARGET')),
        DataColumn(label: Text('DESCRIPTION')),
        DataColumn(label: Text('REASON')),
      ],
      rows: logs
          .map(
            (log) => DataRow(
              cells: [
                DataCell(
                  Text(
                    log.timestampAvailable
                        ? DateFormat.yMMMd().add_jm().format(log.timestamp)
                        : 'Not recorded',
                  ),
                ),
                DataCell(Text(_actor(log))),
                DataCell(_badge(log.action)),
                DataCell(
                  Text(
                    '${log.targetType.isEmpty ? 'Unknown' : log.targetType} · ${log.targetId.isEmpty ? 'Not recorded' : log.targetId}',
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 240,
                    child: Text(
                      log.description.isEmpty
                          ? 'Details not recorded'
                          : log.description,
                    ),
                  ),
                ),
                DataCell(Text(log.reason ?? '—')),
              ],
            ),
          )
          .toList(),
    ),
  );
  Widget _card(AdminAuditLog log) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            _badge(log.action),
            Text(
              log.timestampAvailable
                  ? DateFormat.MMMd().add_jm().format(log.timestamp)
                  : 'Not recorded',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          log.description.isEmpty ? 'Details not recorded' : log.description,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          '${_actor(log)} · ${log.targetType.isEmpty ? 'Unknown entity' : log.targetType} · ${log.targetId.isEmpty ? 'ID not recorded' : log.targetId}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        if (log.reason != null)
          Text('Reason: ${log.reason}', style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
  Widget _badge(String actionValue) {
    final color = actionValue.contains('SUSPENDED')
        ? AppColors.error
        : actionValue.contains('ARCHIVED')
        ? AppColors.textSecondary
        : actionValue.contains('REACTIVATED') ||
              actionValue.contains('ACTIVATED')
        ? AppColors.success
        : actionValue.contains('UPDATED') || actionValue.contains('PLAN')
        ? AppColors.purple
        : actionValue.contains('PASSWORD') || actionValue.contains('INVITATION')
        ? AppColors.warning
        : AppColors.primaryBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        _title(actionValue),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  bool _matches(AdminAuditLog log) {
    final text =
        '${log.action} ${log.description} ${log.targetId} ${log.reason ?? ''}'
            .toLowerCase();
    return (query.isEmpty || text.contains(query)) &&
        (action == null || log.action == action) &&
        (admin == null || log.actorEmail == admin) &&
        (entity == null || log.targetType == entity) &&
        (target.isEmpty || log.targetId.toLowerCase().contains(target)) &&
        (dates == null ||
            (!log.timestamp.isBefore(dates!.start) &&
                log.timestamp.isBefore(
                  dates!.end.add(const Duration(days: 1)),
                )));
  }

  Future<void> _pickDates() async {
    final value = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: dates,
    );
    if (value != null) setState(() => dates = value);
  }

  String _title(String value) => value
      .split('_')
      .map((part) => '${part[0]}${part.substring(1).toLowerCase()}')
      .join(' ');
}
