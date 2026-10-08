import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/admin_routes.dart';
import '../../core/config/app_config.dart';
import '../../core/services/firebase_error_mapper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/ui_components.dart';
import '../../models/admin_audit_log.dart';
import '../../models/dashboard_summary.dart';
import '../../models/landlord_account.dart';
import '../../providers/activity_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/dashboard_providers.dart';
import '../../providers/landlord_providers.dart';
import '../../providers/operational_data_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final landlords = ref.watch(landlordsProvider);
    final activity = ref.watch(activityLogsProvider);
    final dashboard = ref.watch(dashboardMockDataProvider);
    final summary = ref.watch(dashboardSummaryProvider);
    final currentUser = ref.watch(currentAdminUserProvider);
    final adminName = currentUser?.displayName?.trim().isNotEmpty == true
        ? currentUser!.displayName!
        : currentUser?.email?.split('@').first ?? 'Administrator';
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 700 ? 20 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Dashboard',
            subtitle:
                'Good morning, $adminName · Here’s a summary of landlord accounts and platform activity.',
            badge: Tooltip(
              message: AppConfig.useMockData
                  ? 'Showing sample data; no live records are being changed.'
                  : 'Showing data from the live Firebase project.',
              child: Chip(
                avatar: Icon(
                  AppConfig.useMockData
                      ? Icons.science_outlined
                      : Icons.cloud_done,
                  size: 16,
                ),
                label: Text(
                  AppConfig.useMockData ? 'Sample Data' : 'Live Database',
                ),
              ),
            ),
            actions: [
              OutlinedButton.icon(
                onPressed: () {
                  ref.invalidate(landlordsProvider);
                  ref.invalidate(activityLogsProvider);
                  ref.invalidate(dashboardMockDataProvider);
                  ref.invalidate(operationalRecordsProvider);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              ElevatedButton.icon(
                onPressed: () => context.go(AdminRoutes.landlordNew),
                icon: const Icon(Icons.add),
                label: const Text('Add landlord'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          summary.when(
            loading: () => const LoadingSkeleton(rows: 1),
            error: (error, _) => ErrorView(
              message: FirebaseErrorMapper.message(error),
              onRetry: () => ref.invalidate(landlordsProvider),
            ),
            data: (summary) => LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 1200
                    ? (constraints.maxWidth - 60) / 4
                    : constraints.maxWidth >= 650
                    ? (constraints.maxWidth - 20) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 20,
                  runSpacing: 20,
                  children: [
                    SizedBox(
                      width: width,
                      child: DashboardKpiCard(
                        label: 'Total Landlords',
                        value: '${summary.totalLandlords}',
                        caption: 'All registered accounts',
                        icon: Icons.apartment,
                        color: AppColors.primaryBlue,
                        tint: AppColors.primaryTint,
                        onTap: () => _filter(context, ref, null),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: DashboardKpiCard(
                        label: 'Active Accounts',
                        value: '${summary.activeLandlords}',
                        caption:
                            '${summary.totalLandlords > 0 ? ((summary.activeLandlords / summary.totalLandlords) * 100).round() : 0}% of all landlords',
                        icon: Icons.verified_user_outlined,
                        color: AppColors.success,
                        tint: AppColors.successBg,
                        onTap: () =>
                            _filter(context, ref, LandlordStatus.active),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: DashboardKpiCard(
                        label: 'Pending Activation',
                        value: '${summary.invitedLandlords}',
                        caption: 'Awaiting activation',
                        icon: Icons.outgoing_mail,
                        color: AppColors.warning,
                        tint: AppColors.warningBg,
                        onTap: () =>
                            _filter(context, ref, LandlordStatus.invited),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: DashboardKpiCard(
                        label: 'Suspended Accounts',
                        value: '${summary.suspendedLandlords}',
                        caption: 'Compliance / review status',
                        icon: Icons.block,
                        color: AppColors.error,
                        tint: AppColors.errorBg,
                        onTap: () =>
                            _filter(context, ref, LandlordStatus.suspended),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          dashboard.when(
            loading: () => const LoadingSkeleton(rows: 4),
            error: (_, _) => ErrorView(
              message: 'The dashboard summary could not be loaded.',
              onRetry: () => ref.invalidate(dashboardMockDataProvider),
            ),
            data: (data) => Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final growth = _growthChart(context, data.growth);
                    final status = summary.when(
                      loading: () => const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: LoadingSkeleton(rows: 2),
                        ),
                      ),
                      error: (_, _) => const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Account status could not be loaded.'),
                        ),
                      ),
                      data: (landlordSummary) =>
                          _statusChart(context, landlordSummary),
                    );
                    return constraints.maxWidth >= 980
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 2, child: growth),
                              const SizedBox(width: 20),
                              Expanded(child: status),
                            ],
                          )
                        : Column(
                            children: [
                              growth,
                              const SizedBox(height: 20),
                              status,
                            ],
                          );
                  },
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Platform Snapshot',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth >= 800
                        ? (constraints.maxWidth - 40) / 3
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 20,
                      runSpacing: 16,
                      children: [
                        _snapshot(
                          width,
                          'Managed Units',
                          '${data.managedUnits}',
                          'Across all landlord accounts',
                          Icons.domain,
                          onTap: () => context.go(AdminRoutes.operations),
                        ),
                        _snapshot(
                          width,
                          'Registered Tenants',
                          '${data.registeredTenants}',
                          'Currently listed in RAMP',
                          Icons.groups_outlined,
                          onTap: () => context.go(AdminRoutes.operations),
                        ),
                        _snapshot(
                          width,
                          'Open Maintenance',
                          '${data.openMaintenance}',
                          '${data.highPriorityMaintenance} marked high priority',
                          Icons.build_outlined,
                          onTap: () => context.go(AdminRoutes.operations),
                        ),
                      ],
                    );
                  },
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      AppConfig.useMockData
                          ? 'Sample operational totals for preview only.'
                          : 'Global operational totals include legacy records without a landlord owner tag.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _revenueOverview(context, landlords),
              ],
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final recent = _recentLandlords(context, landlords);
              final timeline = _activityTimeline(context, activity);
              return constraints.maxWidth >= 1100
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: recent),
                        const SizedBox(width: 20),
                        Expanded(child: timeline),
                      ],
                    )
                  : Column(
                      children: [recent, const SizedBox(height: 20), timeline],
                    );
            },
          ),
        ],
      ),
    );
  }

  void _filter(BuildContext context, WidgetRef ref, LandlordStatus? status) {
    ref
        .read(landlordFiltersProvider.notifier)
        .set(LandlordFilters(status: status));
    context.go(AdminRoutes.landlords);
  }

  Widget _growthChart(BuildContext context, Map<String, double> values) {
    final maxValue = values.values.fold<double>(
      0,
      (current, value) => value > current ? value : current,
    );
    final chartMax = maxValue < 10 ? 10.0 : maxValue.ceilToDouble() + 2;
    final interval = chartMax / 5;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Landlord Growth',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Text(
                        'New landlord accounts added during the last six months',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Chip(label: Text('6 months')),
              ],
            ),
            const SizedBox(height: 24),
            if (values.isEmpty || values.values.every((value) => value == 0))
              const EmptyState(
                title: 'No growth data',
                message: 'Growth data will appear here.',
              )
            else
              SizedBox(
                height: 250,
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: chartMax,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: interval,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: Theme.of(context).dividerColor,
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: interval,
                          reservedSize: 28,
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt().clamp(
                              0,
                              values.length - 1,
                            );
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                values.keys.elementAt(index),
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineTouchData: const LineTouchData(enabled: true),
                    lineBarsData: [
                      LineChartBarData(
                        spots: values.values.indexed
                            .map(
                              (entry) => FlSpot(entry.$1.toDouble(), entry.$2),
                            )
                            .toList(),
                        isCurved: true,
                        color: AppColors.primaryBlue,
                        barWidth: 3,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.primaryBlue.withAlpha(70),
                              AppColors.primaryBlue.withAlpha(0),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusChart(BuildContext context, DashboardSummary summary) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account Status',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),
          if (summary.totalLandlords == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: EmptyState(
                title: 'No landlord accounts',
                message: 'Status totals will appear once accounts are added.',
              ),
            )
          else ...[
            SizedBox(
              height: 190,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      centerSpaceRadius: 55,
                      sectionsSpace: 3,
                      sections: [
                        if (summary.activeLandlords > 0)
                          PieChartSectionData(
                            value: summary.activeLandlords.toDouble(),
                            color: AppColors.success,
                            radius: 24,
                            showTitle: false,
                          ),
                        if (summary.invitedLandlords > 0)
                          PieChartSectionData(
                            value: summary.invitedLandlords.toDouble(),
                            color: AppColors.warning,
                            radius: 24,
                            showTitle: false,
                          ),
                        if (summary.suspendedLandlords > 0)
                          PieChartSectionData(
                            value: summary.suspendedLandlords.toDouble(),
                            color: AppColors.error,
                            radius: 24,
                            showTitle: false,
                          ),
                        if (summary.archivedLandlords > 0)
                          PieChartSectionData(
                            value: summary.archivedLandlords.toDouble(),
                            color: AppColors.textSecondary,
                            radius: 24,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${summary.totalLandlords}',
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Text(
                        'Accounts',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _legend('Active', summary.activeLandlords, AppColors.success),
                _legend('Pending', summary.invitedLandlords, AppColors.warning),
                _legend(
                  'Suspended',
                  summary.suspendedLandlords,
                  AppColors.error,
                ),
                _legend(
                  'Archived',
                  summary.archivedLandlords,
                  AppColors.textSecondary,
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  Widget _legend(String label, int value, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text('$label $value', style: const TextStyle(fontSize: 12)),
    ],
  );

  Widget _revenueOverview(
    BuildContext context,
    AsyncValue<List<LandlordAccount>> landlords,
  ) => landlords.when(
    loading: () => const LoadingSkeleton(rows: 2),
    error: (_, _) => const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Text('Monthly paid revenue could not be loaded.'),
      ),
    ),
    data: (accounts) {
      final totals = <String, double>{};
      for (final account in accounts) {
        for (final entry in account.monthlyRevenue.entries) {
          totals.update(
            entry.key,
            (value) => value + entry.value,
            ifAbsent: () => entry.value,
          );
        }
      }
      final months = totals.keys.toList()..sort();
      final values = months.map((month) => totals[month] ?? 0).toList();
      final now = DateTime.now();
      final currentKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final currentRevenue = totals[currentKey] ?? 0;
      final maxRevenue = values.fold<double>(0, (max, v) => v > max ? v : max);
      final maxY = maxRevenue == 0 ? 10000.0 : (maxRevenue * 1.25);
      final interval = maxY / 4;

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paid Revenue',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '${_currency(currentRevenue)} received this month · account status is managed separately',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              if (values.isEmpty)
                const Text(
                  'No linked paid-payment history for the last six months.',
                )
              else
                SizedBox(
                  height: 220,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxY,
                      barGroups: [
                        for (var i = 0; i < values.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: values[i],
                                color: AppColors.primaryBlue,
                                width: 22,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ],
                          ),
                      ],
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(),
                        rightTitles: const AxisTitles(),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 64,
                            interval: interval,
                            getTitlesWidget: (value, _) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text(
                                NumberFormat.compactCurrency(
                                  locale: 'en_PH',
                                  symbol: '₱',
                                  decimalDigits: 0,
                                ).format(value),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, _) {
                              final index = value.toInt();
                              if (index < 0 || index >= months.length) {
                                return const SizedBox.shrink();
                              }
                              final parts = months[index].split('-');
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  DateFormat.MMM().format(
                                    DateTime(
                                      int.parse(parts[0]),
                                      int.parse(parts[1]),
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: interval,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: Theme.of(context).dividerColor,
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Widget _snapshot(
    double width,
    String label,
    String value,
    String caption,
    IconData icon, {
    VoidCallback? onTap,
  }) => SizedBox(
    width: width,
    child: HoverCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: AppColors.primaryBlue),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    caption,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _recentLandlords(
    BuildContext context,
    AsyncValue<List<LandlordAccount>> value,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recent Landlords',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
              TextButton(
                onPressed: () => context.go(AdminRoutes.landlords),
                child: const Text('View all'),
              ),
            ],
          ),
          const Divider(),
          value.when(
            loading: () => const LoadingSkeleton(rows: 5),
            error: (_, _) => const ErrorView(
              message: 'Recent landlords could not be loaded.',
            ),
            data: (items) {
              final recent = items.toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
              final latest = recent.take(5).toList();
              return LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 760) {
                    return Column(
                      children: latest
                          .map(
                            (item) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: LandlordAvatar(name: item.displayName),
                              title: Text(item.displayName),
                              subtitle: Text(
                                '${item.companyName}\n${item.unitCount} units · ${item.status == LandlordStatus.invited ? 'Pending activation' : item.status.name}',
                              ),
                              onTap: () =>
                                  context.go(AdminRoutes.landlord(item.uid)),
                            ),
                          )
                          .toList(),
                    );
                  }
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('LANDLORD')),
                        DataColumn(label: Text('COMPANY')),
                        DataColumn(label: Text('STATUS')),
                        DataColumn(label: Text('UNIT USAGE')),
                        DataColumn(label: Text('PAID THIS MONTH')),
                        DataColumn(label: Text('JOINED')),
                        DataColumn(label: Text('ACTIONS')),
                      ],
                      rows: latest
                          .map(
                            (item) => DataRow(
                              cells: [
                                DataCell(
                                  Row(
                                    children: [
                                      LandlordAvatar(name: item.displayName),
                                      const SizedBox(width: 8),
                                      Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(item.displayName),
                                          Text(
                                            item.email,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(Text(item.companyName)),
                                DataCell(StatusBadge(status: item.status)),
                                DataCell(Text('${item.unitCount}')),
                                DataCell(Text(_currency(item.paidThisMonth))),
                                DataCell(
                                  Text(
                                    '${item.createdAt.month}/${item.createdAt.day}/${item.createdAt.year}',
                                  ),
                                ),
                                DataCell(
                                  PopupMenuButton<String>(
                                    tooltip: 'Landlord actions',
                                    onSelected: (value) {
                                      if (value == 'view') {
                                        context.go(
                                          AdminRoutes.landlord(item.uid),
                                        );
                                      }
                                      if (value == 'edit') {
                                        context.go(
                                          AdminRoutes.landlordEdit(item.uid),
                                        );
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'view',
                                        child: Text('View details'),
                                      ),
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit account'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    ),
  );

  Widget _activityTimeline(
    BuildContext context,
    AsyncValue<List<AdminAuditLog>> value,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Activity',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const Divider(),
          value.when(
            loading: () => const LoadingSkeleton(rows: 6),
            error: (_, _) =>
                const ErrorView(message: 'Activity could not be loaded.'),
            data: (items) => Column(
              children: items
                  .take(6)
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: AppColors.primaryTint,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.history,
                              color: AppColors.primaryBlue,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _actionTitle(item.action),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  item.description,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  _relative(item.timestamp),
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          TextButton(
            onPressed: () => context.go(AdminRoutes.activity),
            child: const Text('View full activity'),
          ),
        ],
      ),
    ),
  );

  String _actionTitle(String action) => action
      .split('_')
      .map((part) => '${part[0]}${part.substring(1).toLowerCase()}')
      .join(' ');
  String _relative(DateTime time) {
    final difference = DateTime.now().difference(time);
    if (difference.inMinutes < 60) return '${difference.inMinutes} minutes ago';
    if (difference.inHours < 24) return '${difference.inHours} hours ago';
    if (difference.inDays == 1) return 'Yesterday';
    return '${difference.inDays} days ago';
  }

  String _currency(double value) => NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 0,
  ).format(value);
}
