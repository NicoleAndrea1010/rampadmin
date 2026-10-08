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

class _AdminActivityScreenState extends ConsumerState<AdminActivityScreen> {
  String query = '';
  String? action;
  String? admin;
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
          ),
          const SizedBox(height: 22),
          logs.when(
            loading: () => const LoadingSkeleton(rows: 8),
            error: (_, _) => ErrorView(
              message: 'Administrative activity could not be loaded.',
              onRetry: () => ref.invalidate(activityLogsProvider),
            ),
            data: (items) {
              final administrators =
                  items
                      .map((log) => log.actorEmail)
                      .where((email) => email.isNotEmpty)
                      .toSet()
                      .toList()
                    ..sort();
              if (admin != null && !administrators.contains(admin)) {
                admin = null;
              }
              final filtered = items.where(_matches).toList();
              return Column(
                children: [
                  const SizedBox(height: 16),
                  if (filtered.isEmpty)
                      child: EmptyState(
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

      onChanged: (value) => setState(() => query = value.toLowerCase()),
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText: 'Search activity',
      ),
    ),
          isExpanded: true,
          initialValue: action,
          decoration: const InputDecoration(labelText: 'Action type'),
            ),
          ],
          onChanged: (value) => setState(() => action = value),
        ),
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
                ),
                DataCell(
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
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
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
