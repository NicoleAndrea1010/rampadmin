import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/admin_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/firebase_error_mapper.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/ui_components.dart';
import '../../models/landlord_account.dart';
import '../../providers/activity_providers.dart';
import '../../providers/landlord_providers.dart';
import '../../providers/operational_data_providers.dart';

class LandlordDetailsScreen extends ConsumerWidget {
  const LandlordDetailsScreen({super.key, required this.landlordUid});
  final String landlordUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final landlords = ref.watch(landlordsProvider);
    return landlords.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: LoadingSkeleton(rows: 7),
      ),
      error: (_, _) =>
          const ErrorView(message: 'The landlord details could not be loaded.'),
      data: (items) {
        final landlord = items
            .where((item) => item.uid == landlordUid)
            .firstOrNull;
        if (landlord == null) {
          return const ErrorView(message: 'Landlord record not found.');
        }
        return DefaultTabController(
          length: 9,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 700 ? 20 : 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, ref, landlord),
                const SizedBox(height: 22),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth >= 900
                        ? (constraints.maxWidth - 60) / 4
                        : constraints.maxWidth >= 500
                        ? (constraints.maxWidth - 20) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 20,
                      runSpacing: 16,
                      children: [
                        _metric(
                          width,
                          'Units',
                          '${landlord.unitCount}',
                          Icons.apartment_outlined,
                          AppColors.primaryBlue,
                        ),
                        _metric(
                          width,
                          'Tenants',
                          '${landlord.tenantCount}',
                          Icons.groups_outlined,
                          AppColors.purple,
                        ),
                        _metric(
                          width,
                          'Paid This Month',
                          landlord.paymentMetricsAvailable
                              ? NumberFormat.currency(
                                  locale: 'en_PH',
                                  symbol: '₱',
                                  decimalDigits: 0,
                                ).format(landlord.paidThisMonth)
                              : 'Unavailable',
                          Icons.payments_outlined,
                          AppColors.success,
                        ),
                        _metric(
                          width,
                          'Open Tickets',
                          '${landlord.openTicketCount}',
                          Icons.build_outlined,
                          AppColors.warning,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                _accountInfo(context, landlord),
                const SizedBox(height: 20),
                const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Overview'),
                    Tab(text: 'Properties'),
                    Tab(text: 'Tenants'),
                    Tab(text: 'Tenancies'),
                    Tab(text: 'Payments'),
                    Tab(text: 'Maintenance'),
                    Tab(text: 'Documents'),
                    Tab(text: 'Activity'),
                    Tab(text: 'Settings'),
                  ],
                ),
                SizedBox(
                  height: 460,
                  child: TabBarView(
                    children: [
                      _overview(context, ref, landlord),
                      _units(context, ref, landlord.uid),
                      _tenants(context, ref, landlord.uid),
                      _unsupportedTab(
                        'Tenancies',
                        'A confirmed Supabase tenancies table and schema are required. Current tenant fields are not converted into tenancy history.',
                      ),
                      _payments(context, ref, landlord.uid),
                      _maintenance(context, ref, landlord.uid),
                      _unsupportedTab(
                        'Documents',
                        'A confirmed Supabase documents table and storage metadata contract are required.',
                      ),
                      _history(ref, landlord),
                      _preview('Account settings', [
                        ListTile(
                          title: const Text('Account status'),
                          subtitle: Text(landlord.statusLabel),
                        ),
                        ListTile(
                          title: const Text('Joined'),
                          subtitle: Text(
                            DateFormat.yMMMd().format(landlord.createdAt),
                          ),
                        ),
                        ListTile(
                          title: const Text('Management scope'),
                          subtitle: Text(
                            landlord.canManageAllUnits
                                ? 'All portfolio units'
                                : '${landlord.assignedUnitIds.length} assigned units',
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, WidgetRef ref, LandlordAccount item) =>
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 18,
        runSpacing: 14,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Back to landlords',
                onPressed: () => context.go(AdminRoutes.landlords),
                icon: const Icon(Icons.arrow_back),
              ),
              LandlordAvatar(name: item.displayName, radius: 28),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      item.companyName,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    Text(
                      item.email,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    LandlordStatusChip(landlord: item),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _showAssignUnitsDialog(context, ref, item),
                icon: const Icon(Icons.apartment, size: 18),
                label: const Text('Assign Units & Employees'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go(AdminRoutes.landlordEdit(item.uid)),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit profile'),
              ),
              PopupMenuButton<String>(
                tooltip: 'More account actions',
                onSelected: (action) => _action(context, ref, item, action),
                itemBuilder: (_) => [
                  if (item.status == LandlordStatus.active) ...[
                    const PopupMenuItem(
                      value: 'reset',
                      child: Text('Send password reset'),
                    ),
                    const PopupMenuItem(
                      value: 'suspend',
                      child: Text('Suspend account'),
                    ),
                  ],
                  if (item.status == LandlordStatus.invited)
                    const PopupMenuItem(
                      value: 'activate',
                      child: Text('Activate account'),
                    ),
                  if (item.status == LandlordStatus.suspended) ...[
                    const PopupMenuItem(
                      value: 'reactivate',
                      child: Text('Reactivate account'),
                    ),
                    const PopupMenuItem(
                      value: 'archive',
                      child: Text('Archive account'),
                    ),
                  ],
                  if (item.status == LandlordStatus.invited)
                    const PopupMenuItem(
                      enabled: false,
                      value: 'archive',
                      child: Text('Suspend before archiving'),
                    ),
                ],
                child: const Chip(
                  avatar: Icon(Icons.more_horiz),
                  label: Text('More actions'),
                ),
              ),
            ],
          ),
        ],
      );

  Widget _metric(
    double width,
    String label,
    String value,
    IconData icon,
    Color color,
  ) => SizedBox(
    width: width,
    child: HoverCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withAlpha(22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
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

  Widget _accountInfo(BuildContext context, LandlordAccount item) {
    final entries = {
      'Email': item.email,
      'Phone': item.phone,
      'Company': item.companyName,
      'Units': '${item.unitCount}',
      'Account status': item.statusLabel,
      'Created date': DateFormat.yMMMd().format(item.createdAt),
      'Last updated': DateFormat.yMMMd().add_jm().format(item.updatedAt),
      'Last sign-in': item.lastSignInAt == null
          ? 'Never'
          : DateFormat.yMMMd().add_jm().format(item.lastSignInAt!),
      'Created by': item.createdBy,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Account information',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 900
                    ? (constraints.maxWidth - 48) / 3
                    : constraints.maxWidth >= 500
                    ? (constraints.maxWidth - 24) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 24,
                  runSpacing: 18,
                  children: entries.entries
                      .map(
                        (entry) => SizedBox(
                          width: width,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.key,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                entry.value,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _overview(BuildContext context, WidgetRef ref, LandlordAccount item) {
    final operational = ref.watch(operationalRecordsProvider);
    final liveOverview = operational.when(
      loading: () => const [ListTile(title: Text('Loading portfolio data…'))],
      error: (_, _) => const [
        ListTile(
          title: Text('Portfolio occupancy unavailable'),
          subtitle: Text('Supabase operational data could not be loaded.'),
        ),
      ],
      data: (records) {
        final units = records.where(
          (record) =>
              record.collection == 'units' &&
              record.ownerId == item.uid &&
              record.data['isArchived'] != true &&
              record.data['archived'] != true &&
              _stringValue(record.data['archivedAt']).isEmpty &&
              (record.data['status'] as String? ?? '').toLowerCase() !=
                  'archived',
        );
        final ownedUnits = units.toList();
        final occupied = ownedUnits
            .where(
              (unit) =>
                  unit.status.toLowerCase() == 'occupied' ||
                  _stringValue(
                    unit.data['tenantId'] ?? unit.data['currentTenantId'],
                  ).isNotEmpty,
            )
            .length;
        final conflicting = records
            .where(
              (record) =>
                  record.hasConflictingOwnerIds &&
                  record.ownerIds.contains(item.uid),
            )
            .length;
        final pendingAmount = records
            .where(
              (record) =>
                  record.collection == 'payments' &&
                  record.ownerId == item.uid &&
                  (record.status.toLowerCase() == 'pending'),
            )
            .fold<double>(0, (total, record) {
              final amount = record.data['amount'];
              return total + (amount is num && amount.isFinite ? amount : 0);
            });
        return [
          ListTile(
            title: const Text('Portfolio occupancy'),
            subtitle: Text(
              ownedUnits.isEmpty
                  ? 'No linked units'
                  : '$occupied of ${ownedUnits.length} units occupied · ${(occupied * 100 / ownedUnits.length).round()}%',
            ),
            leading: const Icon(Icons.pie_chart_outline),
          ),
          ListTile(
            title: const Text('Pending payment balance'),
            subtitle: Text(_currency(pendingAmount)),
            leading: const Icon(Icons.account_balance_outlined),
          ),
          ListTile(
            title: const Text('Ownership integrity warnings'),
            subtitle: Text(
              '$conflicting records with conflicting landlord IDs',
            ),
            leading: const Icon(Icons.warning_amber_outlined),
          ),
        ];
      },
    );
    return _preview('Account overview & Unit Delegation', [
      ListTile(
        title: const Text('Joined'),
        subtitle: Text(DateFormat.yMMMd().format(item.createdAt)),
        leading: const Icon(Icons.calendar_today_outlined),
      ),
      ListTile(
        title: const Text('Account status'),
        subtitle: Text(item.statusLabel),
        leading: const Icon(Icons.verified_user_outlined),
      ),
      ...liveOverview,
      ListTile(
        title: const Text('Portfolio records'),
        subtitle: Text('${item.unitCount} units · ${item.tenantCount} tenants'),
        leading: const Icon(Icons.apartment_outlined),
      ),
      ListTile(
        title: const Text('Paid this month'),
        subtitle: Text(
          item.paymentMetricsAvailable
              ? _currency(item.paidThisMonth)
              : 'Unavailable',
        ),
        leading: const Icon(Icons.payments_outlined),
      ),
      ListTile(
        title: const Text('Unit Management Scope'),
        subtitle: Text(
          item.canManageAllUnits
              ? 'All Portfolio Units'
              : (item.assignedUnitIds.isEmpty
                    ? 'No specific units assigned'
                    : 'Assigned: ${item.assignedUnitIds.join(", ")}'),
        ),
        leading: const Icon(Icons.apartment_outlined),
      ),
      ListTile(
        title: const Text('Delegated Employees (While Away)'),
        subtitle: item.assignedEmployeeEmails.isEmpty
            ? const Text('No temporary employee managers delegated.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    'Currently delegated to: ${item.assignedEmployeeEmails.join(", ")}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      final controller = ref.read(landlordsProvider.notifier);
                      await controller.updateLandlord(
                        item.copyWith(assignedEmployeeEmails: []),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Unit management returned back exclusively to primary landlord account!',
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('Return Management Back to Me'),
                  ),
                ],
              ),
        leading: const Icon(Icons.badge_outlined),
      ),
      ListTile(
        title: const Text('Management Permissions'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: item.permissions
                .map(
                  (p) => Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.check_circle_outline, size: 14),
                    label: Text(
                      p.replaceAll('manage_', '').replaceAll('_', ' '),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        leading: const Icon(Icons.security_outlined),
      ),
      if (item.suspensionReason != null)
        ListTile(
          title: const Text('Suspension reason'),
          subtitle: Text(item.suspensionReason!),
          leading: const Icon(Icons.warning_amber, color: AppColors.error),
        ),
    ]);
  }

  Widget _unsupportedTab(String title, String requirement) => _preview(title, [
    ListTile(
      leading: const Icon(Icons.storage_outlined),
      title: const Text('Backend support required'),
      subtitle: Text(requirement),
    ),
  ]);
  Widget _units(BuildContext context, WidgetRef ref, String landlordId) =>
      _operationalPreview(context, ref, 'Units', 'units', landlordId);
  Widget _tenants(BuildContext context, WidgetRef ref, String landlordId) =>
      _operationalPreview(context, ref, 'Tenants', 'tenants', landlordId);
  Widget _payments(
    BuildContext context,
    WidgetRef ref,
    String landlordId,
  ) => ref
      .watch(landlordsProvider)
      .when(
        loading: () => _preview('Payments', [
          const ListTile(title: Text('Loading payment history…')),
        ]),
        error: (_, _) => _operationalPreview(
          context,
          ref,
          'Payments',
          'payments',
          landlordId,
        ),
        data: (accounts) {
          final account = accounts
              .where((item) => item.uid == landlordId)
              .firstOrNull;
          final revenue = account?.monthlyRevenue.entries.toList() ?? [];
          revenue.sort((a, b) => b.key.compareTo(a.key));
          return Column(
            children: [
              _preview(
                'Paid revenue by month',
                revenue.isEmpty || revenue.every((entry) => entry.value == 0)
                    ? [
                        const ListTile(
                          title: Text(
                            'No linked paid revenue in the last six months.',
                          ),
                        ),
                      ]
                    : revenue.take(6).map((entry) {
                        final parts = entry.key.split('-');
                        final month = DateFormat.MMMM().format(
                          DateTime(int.parse(parts[0]), int.parse(parts[1])),
                        );
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.payments_outlined),
                          title: Text(month),
                          trailing: Text(_currency(entry.value)),
                        );
                      }).toList(),
              ),
              Expanded(
                child: _operationalPreview(
                  context,
                  ref,
                  'Payment records',
                  'payments',
                  landlordId,
                ),
              ),
            ],
          );
        },
      );
  Widget _maintenance(BuildContext context, WidgetRef ref, String landlordId) =>
      _operationalPreview(
        context,
        ref,
        'Maintenance',
        'maintenanceTickets',
        landlordId,
      );
  Widget _history(WidgetRef ref, LandlordAccount item) {
    return ref
        .watch(activityLogsProvider)
        .when(
          loading: () =>
              _preview('Audit history', [const LoadingSkeleton(rows: 3)]),
          error: (_, _) => _preview('Audit history', [
            const ListTile(
              title: Text('Unable to load audit history.'),
              subtitle: Text('Refresh the audit log and try again.'),
            ),
          ]),
          data: (items) {
            final logs = items
                .where((log) => log.targetId == item.uid)
                .toList();
            return _preview(
              'Audit history',
              logs.isEmpty
                  ? [
                      const ListTile(
                        title: Text(
                          'No audit records found for this landlord.',
                        ),
                      ),
                    ]
                  : logs
                        .map(
                          (log) => ListTile(
                            leading: const Icon(Icons.history),
                            title: Text(
                              log.action.isEmpty
                                  ? 'Unknown action'
                                  : _title(
                                      log.action
                                          .replaceAll('_', ' ')
                                          .toLowerCase(),
                                    ),
                            ),
                            subtitle: Text(
                              '${log.description.isEmpty ? 'Details not recorded' : log.description}\n'
                              '${log.actorEmail.isNotEmpty
                                  ? log.actorEmail
                                  : log.actorId.isNotEmpty
                                  ? log.actorId
                                  : 'Actor not recorded'} · '
                              '${log.timestampAvailable ? DateFormat.yMMMd().add_jm().format(log.timestamp) : 'Time not recorded'}',
                            ),
                          ),
                        )
                        .toList(),
            );
          },
        );
  }

  Widget _preview(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(top: 18),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
          const Divider(),
          ...children,
        ],
      ),
    ),
  );

  Widget _operationalPreview(
    BuildContext context,
    WidgetRef ref,
    String title,
    String collection,
    String landlordId,
  ) => ref
      .watch(operationalRecordsProvider)
      .when(
        loading: () =>
            _preview(title, [const ListTile(title: Text('Loading records…'))]),
        error: (_, _) => _preview(title, [
          const ListTile(title: Text('Records could not be loaded.')),
          TextButton(
            onPressed: () => ref.invalidate(operationalRecordsProvider),
            child: const Text('Retry'),
          ),
        ]),
        data: (records) {
          final owned = records
              .where(
                (record) =>
                    record.collection == collection &&
                    record.ownerIds.contains(landlordId),
              )
              .toList();
          if (owned.isEmpty) {
            return _preview(title, [
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('No records linked to this landlord.'),
                subtitle: Text(
                  'Records need a matching landlordId or landlord_id to appear here.',
                ),
              ),
            ]);
          }
          return _preview(
            '$title · Supabase records',
            owned.map((record) {
              final data = record.data;
              final name =
                  [
                    data['title'],
                    data['name'],
                    data['tenantName'],
                    data['unitNumber'],
                    data['referenceNumber'],
                  ].whereType<String>().firstWhere(
                    (value) => value.trim().isNotEmpty,
                    orElse: () => record.id,
                  );
              final status = data['status'];
              final details = [
                if (status is String && status.isNotEmpty) status,
                if (data['unitNumber'] is String) data['unitNumber'] as String,
                if (data['tenantName'] is String) data['tenantName'] as String,
                if (record.hasConflictingOwnerIds)
                  'OWNERSHIP CONFLICT · ${record.ownerIds.join(' / ')}',
              ].join(' · ');
              return ListTile(
                leading: Icon(switch (collection) {
                  'units' => Icons.meeting_room_outlined,
                  'tenants' => Icons.person_outline,
                  'payments' => Icons.payments_outlined,
                  _ => Icons.build_outlined,
                }),
                title: Text(name),
                subtitle: Text(details.isEmpty ? 'ID ${record.id}' : details),
              );
            }).toList(),
          );
        },
      );

  Future<void> _action(
    BuildContext context,
    WidgetRef ref,
    LandlordAccount item,
    String action,
  ) async {
    final controller = ref.read(landlordsProvider.notifier);
    if (action == 'activate') {
      final confirmed = await _confirm(
        context,
        'Activate this landlord?',
        'The landlord will be able to sign in to RAMP.',
      );
      if (!context.mounted || !confirmed) return;
      await _runMutation(
        context,
        () => controller.activate(item.uid),
        'Landlord account activated.',
      );
      return;
    }
    if (action == 'reset') {
      await _runMutation(
        context,
        () => controller.sendPasswordReset(item.uid),
        'Password reset email sent.',
      );
      return;
    }
    if (action == 'archive' && item.status != LandlordStatus.suspended) {
      _snack(context, 'Suspend this landlord before archiving the account.');
      return;
    }
    if (action == 'suspend') {
      final reason = await _reason(context);
      if (!context.mounted) return;
      if (reason != null) {
        await _runMutation(
          context,
          () => controller.suspend(item.uid, reason),
          'Account suspended.',
        );
      }
      return;
    }
    if (action == 'reactivate') {
      final confirmed = await _confirm(
        context,
        'Reactivate this landlord?',
        'The account will regain access to RAMP.',
      );
      if (!context.mounted) return;
      if (confirmed) {
        await _runMutation(
          context,
          () => controller.reactivate(item.uid),
          'Account reactivated.',
        );
      }
      return;
    }
    if (action == 'archive') {
      final confirmed = await _confirm(
        context,
        'Archive landlord account?',
        'The account will be removed from active lists. Historical records will remain available.',
      );
      if (!context.mounted || !confirmed) return;
      await _runMutation(
        context,
        () => controller.archive(item.uid),
        'Account archived.',
      );
      return;
    }
  }

  Future<void> _runMutation(
    BuildContext context,
    Future<void> Function() mutation,
    String successMessage,
  ) async {
    try {
      await mutation();
      if (!context.mounted) return;
      _snack(context, successMessage);
    } on FirebaseFunctionsException catch (error) {
      if (!context.mounted) return;
      _snack(context, FirebaseErrorMapper.message(error));
    } on FirebaseException catch (error) {
      if (!context.mounted) return;
      _snack(context, FirebaseErrorMapper.message(error));
    } on StateError catch (error) {
      if (!context.mounted) return;
      _snack(context, error.message.toString());
    } on ArgumentError catch (error) {
      if (!context.mounted) return;
      _snack(
        context,
        error.message?.toString() ?? 'The action could not be completed.',
      );
    }
  }

  Future<void> _showAssignUnitsDialog(
    BuildContext context,
    WidgetRef ref,
    LandlordAccount item,
  ) async {
    final unitInput = TextEditingController();
    final empInput = TextEditingController();
    bool canManageAll = item.canManageAllUnits;
    List<String> units = List<String>.from(item.assignedUnitIds);
    List<String> emps = List<String>.from(item.assignedEmployeeEmails);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Assign Units & Delegate Employees'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Manage All Portfolio Units'),
                    subtitle: const Text(
                      'When active, account manages all units. Turn off to restrict to specific unit IDs.',
                    ),
                    value: canManageAll,
                    onChanged: (val) =>
                        setDialogState(() => canManageAll = val),
                  ),
                  if (!canManageAll) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: unitInput,
                            decoration: const InputDecoration(
                              labelText: 'Add Unit Number / ID',
                              hintText: 'e.g., Unit 101, B2-204',
                            ),
                            onSubmitted: (val) {
                              if (val.trim().isNotEmpty &&
                                  !units.contains(val.trim())) {
                                setDialogState(() {
                                  units.add(val.trim());
                                  unitInput.clear();
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            if (unitInput.text.trim().isNotEmpty &&
                                !units.contains(unitInput.text.trim())) {
                              setDialogState(() {
                                units.add(unitInput.text.trim());
                                unitInput.clear();
                              });
                            }
                          },
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: units
                          .map(
                            (u) => Chip(
                              avatar: const Icon(Icons.apartment, size: 14),
                              label: Text(u),
                              onDeleted: () =>
                                  setDialogState(() => units.remove(u)),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  const Divider(height: 32),
                  const Text(
                    'Delegated Employee Managers (While Away)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sub-account emails authorized to access and manage these units:',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: empInput,
                          decoration: const InputDecoration(
                            labelText: 'Employee Email',
                            hintText: 'assistant@ramp.local',
                          ),
                          onSubmitted: (val) {
                            final email = val.trim().toLowerCase();
                            if (email.contains('@') && !emps.contains(email)) {
                              setDialogState(() {
                                emps.add(email);
                                empInput.clear();
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final email = empInput.text.trim().toLowerCase();
                          if (email.contains('@') && !emps.contains(email)) {
                            setDialogState(() {
                              emps.add(email);
                              empInput.clear();
                            });
                          }
                        },
                        child: const Text('Delegate'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: emps
                        .map(
                          (e) => Chip(
                            avatar: const Icon(Icons.person, size: 14),
                            label: Text(e),
                            onDeleted: () =>
                                setDialogState(() => emps.remove(e)),
                          ),
                        )
                        .toList(),
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
                Navigator.pop(dialogContext);
                final controller = ref.read(landlordsProvider.notifier);
                await controller.updateLandlord(
                  item.copyWith(
                    canManageAllUnits: canManageAll,
                    assignedUnitIds: units,
                    assignedEmployeeEmails: emps,
                  ),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Unit assignments and employee delegations saved.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Save Assignments'),
            ),
          ],
        ),
      ),
    );
    unitInput.dispose();
    empInput.dispose();
  }

  Future<String?> _reason(BuildContext context) async {
    final value = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: const Text('Suspend landlord account?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The landlord will be prevented from accessing RAMP. Existing property and financial records will be retained.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: value,
                autofocus: true,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Reason for suspension *',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (value.text.trim().length < 5) {
                  setState(
                    () => error = 'Enter at least five meaningful characters.',
                  );
                } else {
                  Navigator.pop(dialogContext, value.text.trim());
                }
              },
              child: const Text('Suspend account'),
            ),
          ],
        ),
      ),
    );
    value.dispose();
    return result;
  }

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String message,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;
  void _snack(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  String _title(String value) => value
      .split(' ')
      .map(
        (part) =>
            part.isEmpty ? '' : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');

  String _currency(double value) => NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 0,
  ).format(value);

  String _stringValue(Object? value) => value?.toString().trim() ?? '';
}
