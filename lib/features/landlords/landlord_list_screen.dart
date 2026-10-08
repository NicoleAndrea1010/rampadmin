import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/admin_routes.dart';
import '../../core/services/firebase_error_mapper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/ui_components.dart';
import '../../models/landlord_account.dart';
import '../../providers/landlord_providers.dart';

class LandlordListScreen extends ConsumerStatefulWidget {
  const LandlordListScreen({super.key});
  @override
  ConsumerState<LandlordListScreen> createState() => _LandlordListScreenState();
}

class _LandlordListScreenState extends ConsumerState<LandlordListScreen> {
  late final TextEditingController search;
  String? _mutatingUid;

  @override
  void initState() {
    super.initState();
    final filters = ref.read(landlordFiltersProvider);
    search = TextEditingController(text: filters.query);
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncItems = ref.watch(landlordsProvider);
    final filters = ref.watch(landlordFiltersProvider);
    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 700 ? 20 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Landlords',
            subtitle: 'Manage landlord accounts and access.',
            actions: [
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(landlordsProvider),
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
          const SizedBox(height: 22),
          asyncItems.when(
            loading: () => const LoadingSkeleton(rows: 7),
            error: (error, _) => ErrorView(
              message: FirebaseErrorMapper.message(error),
              onRetry: () => ref.invalidate(landlordsProvider),
            ),
            data: (all) {
              final items = _apply(all, filters);
              final pageCount = (items.length / filters.pageSize).ceil().clamp(
                1,
                999,
              );
              final safePage = filters.page.clamp(0, pageCount - 1);
              final pageItems = items
                  .skip(safePage * filters.pageSize)
                  .take(filters.pageSize)
                  .toList();
              return Column(
                children: [
                  if (all.any(
                    (item) =>
                        !item.metricsAvailable || !item.paymentMetricsAvailable,
                  )) ...[
                    _metricsNotice(),
                    const SizedBox(height: 14),
                  ],
                  _summary(all, filters),
                  const SizedBox(height: 16),
                  _filterBar(filters),
                  const SizedBox(height: 16),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: pageItems.isEmpty
                        ? EmptyState(
                            icon: Icons.apartment_outlined,
                            title: all.isEmpty
                                ? 'No landlords yet'
                                : 'No landlords found',
                            message: all.isEmpty
                                ? 'Landlord accounts will appear here once registered.'
                                : 'Try clearing or changing your filters.',
                            action: all.isEmpty
                                ? null
                                : TextButton(
                                    onPressed: _clear,
                                    child: const Text('Clear filters'),
                                  ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) =>
                                constraints.maxWidth < 760
                                ? Column(
                                    children: pageItems
                                        .map(_mobileCard)
                                        .toList(),
                                  )
                                : _table(pageItems),
                          ),
                  ),
                  const SizedBox(height: 14),
                  _pagination(filters, items.length, safePage, pageCount),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _metricsNotice() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.warningBg,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, color: AppColors.warning),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Landlord accounts loaded, but some live portfolio totals are unavailable. Account details are still shown; check Firestore read permissions and retry.',
          ),
        ),
      ],
    ),
  );

  Widget _summary(List<LandlordAccount> all, LandlordFilters filters) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _countPill('All', all.length, filters.status == null, null),
            for (final status in LandlordStatus.values.where(
              (status) =>
                  status != LandlordStatus.unknown ||
                  all.any((item) => item.status == LandlordStatus.unknown),
            ))
              _countPill(
                status == LandlordStatus.unknown
                    ? 'Unknown'
                    : status == LandlordStatus.invited
                    ? 'Pending / Invitations'
                    : _title(status.name),
                all.where((item) => item.status == status).length,
                filters.status == status,
                status,
              ),
          ],
        ),
      );

  Widget _countPill(
    String label,
    int count,
    bool selectedFilter,
    LandlordStatus? status,
  ) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text('$label  $count'),
      selected: selectedFilter,
      onSelected: (_) {
        final current = ref.read(landlordFiltersProvider);
        ref
            .read(landlordFiltersProvider.notifier)
            .set(
              current.copyWith(
                status: status,
                clearStatus: status == null,
                page: 0,
              ),
            );
      },
    ),
  );

  Widget _filterBar(LandlordFilters filters) => ResponsiveFilterToolbar(
    search: TextField(
      controller: search,
      onChanged: (value) => _set(filters.copyWith(query: value, page: 0)),
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText: 'Search landlords',
      ),
    ),
    filters: [
      SizedBox(
        width: 220,
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: filters.sort,
          decoration: const InputDecoration(labelText: 'Sort'),
          items: const [
            DropdownMenuItem(value: 'newest', child: Text('Newest')),
            DropdownMenuItem(value: 'oldest', child: Text('Oldest')),
            DropdownMenuItem(value: 'az', child: Text('Name A–Z')),
            DropdownMenuItem(value: 'za', child: Text('Name Z–A')),
            DropdownMenuItem(value: 'units', child: Text('Most units')),
            DropdownMenuItem(
              value: 'revenue',
              child: Text('Highest paid this month'),
            ),
          ],
          onChanged: (value) => _set(filters.copyWith(sort: value, page: 0)),
        ),
      ),
      TextButton.icon(
        onPressed: _clear,
        icon: const Icon(Icons.filter_alt_off),
        label: const Text('Clear filters'),
      ),
    ],
    activeFilterCount:
        (filters.query.isNotEmpty ? 1 : 0) + (filters.sort == 'newest' ? 0 : 1),
  );

  Widget _table(List<LandlordAccount> items) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      columns: [
        const DataColumn(label: Text('LANDLORD')),
        const DataColumn(label: Text('COMPANY')),
        const DataColumn(label: Text('CONTACT')),
        const DataColumn(label: Text('STATUS')),
        const DataColumn(label: Text('UNITS')),
        const DataColumn(label: Text('PAID THIS MONTH')),
        const DataColumn(label: Text('JOINED')),
        DataColumn(label: const Text('LAST SIGN-IN')),
        const DataColumn(label: Text('ACTIONS')),
      ],
      rows: items
          .map(
            (item) => DataRow(
              cells: [
                DataCell(
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => context.go(AdminRoutes.landlord(item.uid)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 4,
                      ),
                      child: Row(
                        children: [
                          LandlordAvatar(name: item.displayName),
                          const SizedBox(width: 10),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryBlue,
                                ),
                              ),
                              Text(
                                item.email,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                DataCell(SizedBox(width: 145, child: Text(item.companyName))),
                DataCell(Text(item.phone)),
                DataCell(
                  StatusBadge(status: item.status, label: item.statusLabel),
                ),
                DataCell(
                  Text(
                    item.metricsAvailable ? '${item.unitCount}' : 'Unavailable',
                  ),
                ),
                DataCell(
                  Text(
                    item.paymentMetricsAvailable
                        ? _currency(item.paidThisMonth)
                        : 'Unavailable',
                  ),
                ),
                DataCell(Text(DateFormat.yMMMd().format(item.createdAt))),
                DataCell(
                  Text(
                    item.lastSignInAt == null
                        ? 'Never'
                        : DateFormat.yMMMd().format(item.lastSignInAt!),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: 'View Profile',
                        child: IconButton(
                          icon: const Icon(Icons.visibility_outlined, size: 20),
                          color: AppColors.primaryBlue,
                          onPressed: () =>
                              context.go(AdminRoutes.landlord(item.uid)),
                        ),
                      ),
                      Tooltip(
                        message: 'Edit Account & Assign Units',
                        child: IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          color: AppColors.textSecondary,
                          onPressed: () =>
                              context.go(AdminRoutes.landlordEdit(item.uid)),
                        ),
                      ),
                      _menu(item),
                    ],
                  ),
                ),
              ],
            ),
          )
          .toList(),
    ),
  );

  Widget _mobileCard(LandlordAccount item) => InkWell(
    onTap: () => context.go(AdminRoutes.landlord(item.uid)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LandlordAvatar(name: item.displayName),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      item.companyName,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              _menu(item),
            ],
          ),
          const SizedBox(height: 12),
          LandlordStatusChip(landlord: item),
          const SizedBox(height: 12),
          Text(item.email),
          Text(
            '${item.metricsAvailable ? '${item.unitCount} units' : 'Unit totals unavailable'} · ${item.paymentMetricsAvailable ? '${_currency(item.paidThisMonth)} paid this month' : 'Payment totals unavailable'} · Joined ${DateFormat.yMMMd().format(item.createdAt)}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _menu(LandlordAccount item) => PopupMenuButton<String>(
    tooltip: 'Account actions',
    enabled: _mutatingUid == null,
    onSelected: (action) => _action(item, action),
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'view', child: Text('View details')),
      if (item.status != LandlordStatus.archived)
        const PopupMenuItem(value: 'edit', child: Text('Edit account')),
      if (item.status == LandlordStatus.invited)
        const PopupMenuItem(value: 'activate', child: Text('Activate account')),
      if (item.status == LandlordStatus.active) ...[
        const PopupMenuItem(value: 'reset', child: Text('Send password reset')),
        const PopupMenuItem(value: 'suspend', child: Text('Suspend')),
      ],
      if (item.status == LandlordStatus.suspended) ...[
        if (item.status == LandlordStatus.suspended)
          const PopupMenuItem(value: 'reactivate', child: Text('Reactivate')),
        if (item.status == LandlordStatus.suspended)
          const PopupMenuItem(value: 'archive', child: Text('Archive')),
      ],
      if (item.status == LandlordStatus.invited)
        const PopupMenuItem(
          enabled: false,
          value: 'archive',
          child: Text('Suspend before archiving'),
        ),
    ],
  );

  Future<void> _action(LandlordAccount item, String action) async {
    if (action == 'view') {
      context.go(AdminRoutes.landlord(item.uid));
      return;
    }
    if (action == 'edit') {
      context.go(AdminRoutes.landlordEdit(item.uid));
      return;
    }
    final controller = ref.read(landlordsProvider.notifier);
    if (action == 'activate' &&
        await _confirm(
          'Activate this landlord?',
          'The landlord will be able to sign in to RAMP.',
          'Activate',
        )) {
      await _runMutation(
        item.uid,
        () => controller.activate(item.uid),
        'Landlord account activated.',
      );
      return;
    }
    if (action == 'reset') {
      await _runMutation(
        item.uid,
        () => controller.sendPasswordReset(item.uid),
        'Password reset email sent.',
      );
      return;
    }
    if (action == 'suspend') {
      final reason = await _suspendDialog();
      if (reason != null) {
        await _runMutation(
          item.uid,
          () => controller.suspend(item.uid, reason),
          'Account suspended.',
        );
      }
      return;
    }
    if (action == 'reactivate' &&
        await _confirm(
          'Reactivate this landlord?',
          'The account will regain access to RAMP.',
          'Reactivate',
        )) {
      await _runMutation(
        item.uid,
        () => controller.reactivate(item.uid),
        'Account reactivated.',
      );
      return;
    }
    if (action == 'archive' &&
        await _confirm(
          'Archive landlord account?',
          'The account will be removed from active lists. Historical records will remain available.',
          'Archive account',
        )) {
      await _runMutation(
        item.uid,
        () => controller.archive(item.uid),
        'Account archived.',
      );
      return;
    }
  }

  Future<void> _runMutation(
    String uid,
    Future<void> Function() mutation,
    String successMessage,
  ) async {
    if (_mutatingUid != null) return;
    setState(() => _mutatingUid = uid);
    try {
      await mutation();
      _snack(successMessage);
    } on FirebaseFunctionsException catch (error) {
      _snack(FirebaseErrorMapper.message(error));
    } on FirebaseException catch (error) {
      _snack(FirebaseErrorMapper.message(error));
    } on StateError catch (error) {
      _snack(error.message.toString());
    } on ArgumentError catch (error) {
      _snack(error.message?.toString() ?? 'The action could not be completed.');
    } finally {
      if (mounted) setState(() => _mutatingUid = null);
    }
  }

  Future<String?> _suspendDialog() async {
    final reason = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Suspend landlord account?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The landlord will be prevented from accessing RAMP. Existing property and financial records will be retained.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reason,
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
                if (reason.text.trim().length < 5) {
                  setDialogState(
                    () => error = 'Enter at least five meaningful characters.',
                  );
                } else {
                  Navigator.pop(dialogContext, reason.text.trim());
                }
              },
              child: const Text('Suspend account'),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
    return result;
  }

  Future<bool> _confirm(String title, String message, String action) async =>
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
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Widget _pagination(
    LandlordFilters filters,
    int total,
    int page,
    int pageCount,
  ) => Wrap(
    spacing: 10,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        '$total results',
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      const SizedBox(width: 16),
      DropdownButton<int>(
        value: filters.pageSize,
        items: const [
          DropdownMenuItem(value: 5, child: Text('5 per page')),
          DropdownMenuItem(value: 10, child: Text('10 per page')),
          DropdownMenuItem(value: 20, child: Text('20 per page')),
        ],
        onChanged: (value) => _set(filters.copyWith(pageSize: value, page: 0)),
      ),
      const SizedBox(width: 12),
      Text('${page + 1} of $pageCount'),
      IconButton(
        tooltip: 'Previous page',
        onPressed: page == 0
            ? null
            : () => _set(filters.copyWith(page: page - 1)),
        icon: const Icon(Icons.chevron_left),
      ),
      IconButton(
        tooltip: 'Next page',
        onPressed: page >= pageCount - 1
            ? null
            : () => _set(filters.copyWith(page: page + 1)),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );

  List<LandlordAccount> _apply(
    List<LandlordAccount> all,
    LandlordFilters filters,
  ) {
    final query = filters.query.trim().toLowerCase();
    final result = all
        .where(
          (item) =>
              (query.isEmpty ||
                  '${item.displayName} ${item.companyName} ${item.email}'
                      .toLowerCase()
                      .contains(query)) &&
              (filters.status == null || item.status == filters.status),
        )
        .toList();
    result.sort(
      (a, b) => switch (filters.sort) {
        'oldest' => a.createdAt.compareTo(b.createdAt),
        'az' => a.displayName.compareTo(b.displayName),
        'za' => b.displayName.compareTo(a.displayName),
        'units' => b.unitCount.compareTo(a.unitCount),
        'revenue' => b.paidThisMonth.compareTo(a.paidThisMonth),
        _ => b.createdAt.compareTo(a.createdAt),
      },
    );
    return result;
  }

  void _set(LandlordFilters value) =>
      ref.read(landlordFiltersProvider.notifier).set(value);
  void _clear() {
    search.clear();
    ref
        .read(landlordFiltersProvider.notifier)
        .set(LandlordFilters(status: null));
  }

  void _snack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _title(String value) => value == 'invited'
      ? 'Pending / Invitations'
      : '${value[0].toUpperCase()}${value.substring(1)}';

  String _currency(double value) => NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
    decimalDigits: 0,
  ).format(value);
}
