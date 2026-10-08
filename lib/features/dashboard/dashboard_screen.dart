import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/admin_routes.dart';
import '../../core/services/firebase_error_mapper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/ui_components.dart';
import '../../models/admin_audit_log.dart';
import '../../models/dashboard_summary.dart';
import '../../models/landlord_account.dart';
import '../../providers/activity_providers.dart';
import '../../providers/auth_providers.dart';
import '../../providers/dashboard_providers.dart';
import '../../providers/landlord_providers.dart';
import '../../providers/operational_data_providers.dart';
import '../../providers/settings_providers.dart';
import 'dashboard_repository.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final landlords = ref.watch(landlordsProvider);
    final activity = ref.watch(activityLogsProvider);
    final dashboard = ref.watch(dashboardDataProvider);
    final summary = ref.watch(dashboardSummaryProvider);
    final admin = ref.watch(currentAdminUserProvider);
    final refreshedAt = dashboard.value?.refreshedAt;
    final adminName = admin?.displayName?.trim().isNotEmpty == true
        ? admin!.displayName!
        : admin?.email?.split('@').first ?? 'Administrator';
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';

    return SingleChildScrollView(
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
          _DashboardHero(
            greeting: greeting,
            name: adminName,
            dataState: dashboard,
            refreshedAt: refreshedAt,
            onRefresh: () {
              ref.invalidate(landlordsProvider);
              ref.invalidate(activityLogsProvider);
              ref.invalidate(dashboardDataProvider);
              ref.invalidate(operationalRecordsProvider);
            },
          ),
          const SizedBox(height: 18),
          summary.when(
            loading: () => _dashboardSkeleton(context),
            error: (error, _) => ErrorView(
              message: FirebaseErrorMapper.message(error),
              onRetry: () => ref.invalidate(landlordsProvider),
            ),
            data: (accountSummary) => dashboard.when(
              loading: () => _dashboardSkeleton(context),
              error: (_, _) => ErrorView(
                message: 'Operational summary could not be loaded.',
                onRetry: () => ref.invalidate(dashboardDataProvider),
              ),
              data: (data) => _dashboardContent(
                context,
                accountSummary,
                data,
                landlords,
                activity,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardContent(
    BuildContext context,
    DashboardSummary accounts,
    DashboardData data,
    AsyncValue<List<LandlordAccount>> landlords,
    AsyncValue<List<AdminAuditLog>> activity,
  ) {
    final currentMonth =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
    final collected = data.monthlyRevenue[currentMonth];
    final occupied = _statusCount(data.unitsByStatus, 'occupied');
    final vacant = _statusCount(data.unitsByStatus, 'vacant');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1000
                ? 4
                : constraints.maxWidth >= 540
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                RampEntrance(
                  delay: const Duration(milliseconds: 0),
                  child: _Kpi(
                    width: width,
                    title: 'Landlords',
                    value: '${accounts.totalLandlords}',
                    detail: '${accounts.activeLandlords} active',
                    icon: Icons.apartment_rounded,
                    color: AppColors.primaryBlue,
                    tint: AppColors.primaryTint,
                    onTap: () => context.go(AdminRoutes.landlords),
                  ),
                ),
                RampEntrance(
                  delay: const Duration(milliseconds: 50),
                  child: _Kpi(
                    width: width,
                    title: 'Properties',
                    value: '${data.managedUnits}',
                    detail:
                        '$occupied occupied · ${data.unknownUnitStatuses > 0 ? 'vacancy unavailable' : '$vacant vacant'}',
                    icon: Icons.domain_rounded,
                    color: AppColors.purple,
                    tint: AppColors.purpleBg,
                    onTap: () => context.go(AdminRoutes.units),
                  ),
                ),
                RampEntrance(
                  delay: const Duration(milliseconds: 100),
                  child: _Kpi(
                    width: width,
                    title: 'Tenants',
                    value: '${data.registeredTenants}',
                    detail: 'Registered tenants',
                    icon: Icons.people_alt_rounded,
                    color: AppColors.cyan,
                    tint: AppColors.cyanTint,
                    onTap: () => context.go(AdminRoutes.tenants),
                  ),
                ),
                RampEntrance(
                  delay: const Duration(milliseconds: 150),
                  child: _Kpi(
                    width: width,
                    title: 'Collected This Month',
                    value: collected == null
                        ? 'Unavailable'
                        : _currency(collected),
                    detail: 'Paid rent recorded this month',
                    icon: Icons.payments_rounded,
                    color: AppColors.mint,
                    tint: AppColors.mintTint,
                    onTap: () => context.go(AdminRoutes.payments),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 950;
            final gap = 16.0;
            final primaryWidth = wide
                ? (constraints.maxWidth - gap) * .61
                : constraints.maxWidth;
            final secondaryWidth = wide
                ? (constraints.maxWidth - gap) * .39
                : constraints.maxWidth;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                SizedBox(
                  width: primaryWidth,
                  child: RampEntrance(
                    delay: const Duration(milliseconds: 60),
                    child: _Panel(
                      title: 'Portfolio',
                      children: [
                        if (data.managedUnits == 0)
                          const EmptyState(
                            compact: true,
                            icon: Icons.domain_outlined,
                            title: 'No properties synced yet',
                            message: 'Portfolio occupancy will appear when properties are available.',
                          )
                        else ...[
                          _metric(
                            'Occupancy',
                            data.managedUnits <= data.archivedUnits ||
                                    data.unknownUnitStatuses > 0
                                ? 'Unavailable'
                                : '${(occupied * 100 / (data.managedUnits - data.archivedUnits)).round()}%',
                          ),
                          _metric('Occupied', '$occupied'),
                          _metric(
                            'Vacant',
                            data.unknownUnitStatuses > 0
                                ? 'Unavailable'
                                : '$vacant',
                          ),
                          _metric(
                            'Reserved',
                            '${_statusCount(data.unitsByStatus, 'reserved')}',
                          ),
                          if (data.archivedUnits > 0)
                            _metric('Archived', '${data.archivedUnits}'),
                        ],
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: secondaryWidth,
                  child: RampEntrance(
                    delay: const Duration(milliseconds: 100),
                    child: _Panel(
                      title: 'Payments',
                      children: [
                        _metric(
                          'Collected',
                          collected == null
                              ? 'Unavailable'
                              : _currency(collected),
                          valueColor: AppColors.mint,
                        ),
                        _metric(
                          'Pending',
                          data.paymentBalancesAvailable
                              ? _currency(data.outstandingPayments)
                              : 'Unavailable',
                          valueColor: AppColors.amber,
                        ),
                        _metric(
                          'Overdue',
                          data.paymentBalancesAvailable
                              ? _currency(data.overduePayments)
                              : 'Unavailable',
                          valueColor: AppColors.coral,
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: primaryWidth,
                  child: RampEntrance(
                    delay: const Duration(milliseconds: 140),
                    child: _revenue(context, data.growth),
                  ),
                ),
                SizedBox(
                  width: secondaryWidth,
                  child: Column(
                    children: [
                      RampEntrance(
                        delay: const Duration(milliseconds: 180),
                        child: _Panel(
                          title: 'Maintenance',
                          children: [
                            _metric('Open', '${data.openMaintenance}'),
                            _metric(
                              'High priority',
                              '${data.highPriorityMaintenance}',
                              valueColor: AppColors.coral,
                            ),
                            _metric(
                              'Awaiting estimate',
                              '${data.awaitingEstimate}',
                            ),
                            _metric(
                              'Scheduled repair',
                              '${data.scheduledRepair}',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      RampEntrance(
                        delay: const Duration(milliseconds: 210),
                        child: _Panel(
                          title: 'Account Status',
                          children: [
                            _metric(
                              'Active',
                              '${accounts.activeLandlords}',
                              valueColor: AppColors.mint,
                            ),
                            _metric(
                              'Pending',
                              '${accounts.invitedLandlords}',
                              valueColor: AppColors.amber,
                            ),
                            _metric(
                              'Suspended',
                              '${accounts.suspendedLandlords}',
                              valueColor: AppColors.coral,
                            ),
                            _metric(
                              'Archived',
                              '${accounts.archivedLandlords}',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 950;
            final width = wide
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: width,
                  child: RampEntrance(
                    delay: const Duration(milliseconds: 240),
                    child: _attention(context, data),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: RampEntrance(
                    delay: const Duration(milliseconds: 280),
                    child: _activityPanel(context, activity),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _dashboardSkeleton(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const RampMetricSkeleton(),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: constraints.maxWidth >= 950
                  ? (constraints.maxWidth - 16) * .61
                  : constraints.maxWidth,
              height: 220,
              child: const LoadingSkeleton(rows: 2),
            ),
            SizedBox(
              width: constraints.maxWidth >= 950
                  ? (constraints.maxWidth - 16) * .39
                  : constraints.maxWidth,
              height: 220,
              child: const LoadingSkeleton(rows: 2),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _attention(BuildContext context, DashboardData data) {
    final checks = <(String, int)>[
      ('Missing landlord ownership', data.missingLandlordId),
      ('Ownership conflicts', data.ownershipMismatches),
      ('Orphan tenant / property links', data.orphanRelationships),
      ('Payments missing tenancy', data.paymentsMissingTenancy),
      ('Maintenance missing property', data.maintenanceMissingUnitId),
    ];
    final flagged = checks.where((entry) => entry.$2 > 0).toList();
    return _Panel(
      title: 'Attention Required',
      trailing: TextButton(
        onPressed: () => context.go(AdminRoutes.dataIntegrity),
        child: const Text('View Data Health'),
      ),
      children: [
        if (flagged.isEmpty)
          Text(
            'No ownership conflicts, orphan tenant or property links, or missing required references.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else ...[
          Text('${flagged.length} data checks require attention.'),
          for (final entry in flagged) _metric(entry.$1, '${entry.$2}'),
        ],
      ],
    );
  }

  Widget _revenue(BuildContext context, Map<String, double> values) {
    final maxValue = values.values.fold<double>(
      0,
      (largest, value) => value > largest ? value : largest,
    );
    final chartMax = maxValue < 10 ? 10.0 : maxValue.ceilToDouble() + 2;
    final interval = chartMax / 5;
    return _Panel(
      title: 'Paid Revenue',
      subtitle: 'Last 6 months',
      children: [
        if (values.isEmpty || values.values.every((value) => value == 0))
          const EmptyState(
            compact: true,
            icon: Icons.receipt_long_outlined,
            title: 'No payment history yet',
            message: 'Revenue trends appear after paid rent is recorded.',
          )
        else
          SizedBox(
            height: 220,
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
                      reservedSize: 44,
                      getTitlesWidget: (value, _) => Text(
                        NumberFormat.compactCurrency(
                          locale: 'en_PH',
                          symbol: '₱',
                          decimalDigits: 0,
                        ).format(value),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, _) {
                        final index = value.toInt();
                        if (index < 0 || index >= values.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(values.keys.elementAt(index)),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: const LineTouchData(enabled: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: values.values.indexed
                        .map((entry) => FlSpot(entry.$1.toDouble(), entry.$2))
                        .toList(),
                    isCurved: true,
                    color: AppColors.primaryBlue,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primaryBlue.withAlpha(24),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _activityPanel(
    BuildContext context,
    AsyncValue<List<AdminAuditLog>> activity,
  ) => _Panel(
    title: 'Recent Activity',
    trailing: TextButton(
      onPressed: () => context.go(AdminRoutes.activity),
      child: const Text('View all'),
    ),
    children: [
      activity.when(
        loading: () => const LoadingSkeleton(rows: 3),
        error: (_, _) => const Text('Activity could not be loaded.'),
        data: (items) => items.isEmpty
            ? const EmptyState(
                compact: true,
                title: 'No recent activity',
                message: 'Recorded administrator actions will appear here.',
              )
            : Column(
                children: items.take(5).map((item) {
                  final title = item.action
                      .split('_')
                      .map(
                        (part) => part.isEmpty
                            ? part
                            : '${part[0]}${part.substring(1).toLowerCase()}',
                      )
                      .join(' ');
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.history, size: 20),
                    title: Text(title),
                    subtitle: Text(item.description),
                    trailing: Text(
                      DateFormat.MMMd().add_jm().format(item.timestamp),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                }).toList(),
              ),
      ),
    ],
  );

  int _statusCount(Map<String, int> statuses, String key) => statuses.entries
      .where((entry) => entry.key.trim().toLowerCase() == key)
      .fold(0, (total, entry) => total + entry.value);

  Widget _metric(String label, String value, {Color? valueColor}) => Builder(
    builder: (context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w600, color: valueColor),
          ),
        ],
      ),
    ),
  );

  String _currency(double value) => NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 0,
  ).format(value);
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.width,
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
    required this.tint,
    required this.onTap,
  });

  final double width;
  final String title;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: HoverCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? color.withAlpha(35)
                        : tint,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
                Icon(Icons.arrow_outward_rounded, size: 17, color: color),
              ],
            ),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 3),
            _AnimatedMetricValue(value: value),
            const SizedBox(height: 2),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _AnimatedMetricValue extends ConsumerWidget {
  const _AnimatedMetricValue({required this.value});
  final String value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final numberString = value.replaceAll(RegExp(r'[^0-9.-]'), '');
    final target = double.tryParse(numberString);
    final reduceMotion =
        ref.watch(reducedMotionProvider) ||
        MediaQuery.disableAnimationsOf(context);
    if (target == null) {
      return Text(
        value,
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      );
    }
    final currency = value.contains('₱');
    if (reduceMotion) {
      return Text(
        currency
            ? NumberFormat.currency(
                locale: 'en_PH',
                symbol: '₱',
                decimalDigits: 0,
              ).format(target)
            : target.round().toString(),
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, amount, _) => Text(
        currency
            ? NumberFormat.currency(
                locale: 'en_PH',
                symbol: '₱',
                decimalDigits: 0,
              ).format(amount)
            : amount.round().toString(),
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.greeting,
    required this.name,
    required this.dataState,
    required this.refreshedAt,
    required this.onRefresh,
  });

  final String greeting;
  final String name;
  final AsyncValue<DashboardData> dataState;
  final DateTime? refreshedAt;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 560;
    final status = dataState.when(
      loading: () => ('Refreshing', Icons.sync_rounded),
      error: (_, _) => ('Unavailable', Icons.cloud_off_rounded),
      data: (_) => ('Live Data', Icons.circle),
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 112),
      padding: EdgeInsets.all(mobile ? 18 : 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: Theme.of(context).brightness == Brightness.light
              ? const [Color(0xFFEAF2FF), Color(0xFFF4F7FF), Color(0xFFEEF8FB)]
              : [AppColors.darkElevated, AppColors.darkSurface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 18,
        runSpacing: 14,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dashboard',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primaryBlue,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$greeting, $name',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                'Here’s what’s happening across RAMP today.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _LiveStatus(label: status.$1, icon: status.$2),
              if (refreshedAt != null)
                Text(
                  'Updated ${DateFormat.jm().format(refreshedAt!.toLocal())}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              Tooltip(
                message: 'Refresh dashboard',
                child: AnimatedRotation(
                  turns: dataState.isLoading ? .5 : 0,
                  duration: const Duration(milliseconds: 350),
                  child: IconButton.filledTonal(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveStatus extends StatelessWidget {
  const _LiveStatus({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withAlpha(210),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: label == 'Live Data'
                ? AppColors.mint
                : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 7),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.children,
    this.trailing,
    this.subtitle,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              ?trailing,
            ],
          ),
          if (subtitle != null) ...[
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    ),
  );
}
