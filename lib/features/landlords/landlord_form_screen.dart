import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/admin_routes.dart';
import '../../core/services/firebase_error_mapper.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/error_view.dart';
import '../../core/widgets/ui_components.dart';
import '../../models/landlord_account.dart';
import '../../providers/auth_providers.dart';
import '../../providers/landlord_providers.dart';

class LandlordFormScreen extends ConsumerStatefulWidget {
  const LandlordFormScreen({super.key, this.landlordUid});
  final String? landlordUid;
  @override
  ConsumerState<LandlordFormScreen> createState() => _LandlordFormScreenState();
}

class _LandlordFormScreenState extends ConsumerState<LandlordFormScreen> {
  final key = GlobalKey<FormState>();
  final email = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();
  final company = TextEditingController();
  final unitInputController = TextEditingController();
  final employeeInputController = TextEditingController();

  LandlordStatus status = LandlordStatus.invited;
  bool canManageAllUnits = true;
  List<String> assignedUnitIds = [];
  List<String> assignedEmployeeEmails = [];
  List<String> permissions = [
    'manage_units',
    'manage_tenants',
    'manage_payments',
    'manage_tickets',
  ];

  LandlordAccount? existing;
  bool busy = false;
  bool loaded = false;
  bool canRetryLoad = false;
  String? loadError;
  bool get editing => widget.landlordUid != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded) {
      loaded = true;
      if (editing) _load();
    }
  }

  Future<void> _load() async {
    setState(() => busy = true);
    loadError = null;
    canRetryLoad = false;
    try {
      final item = await ref
          .read(landlordsProvider.notifier)
          .get(widget.landlordUid!);
      if (!mounted) return;
      existing = item;
      if (item == null) {
        loadError = 'Landlord record not found.';
      } else {
        email.text = item.email;
        name.text = item.displayName;
        phone.text = item.phone;
        company.text = item.companyName;
        status = item.status;
        canManageAllUnits = item.canManageAllUnits;
        assignedUnitIds = List<String>.from(item.assignedUnitIds);
        assignedEmployeeEmails = List<String>.from(item.assignedEmployeeEmails);
        permissions = List<String>.from(item.permissions);
      }
    } on FirebaseException catch (error) {
      if (!mounted) return;
      loadError = FirebaseErrorMapper.message(error);
      canRetryLoad = true;
    } on StateError catch (error) {
      if (!mounted) return;
      loadError = error.message.toString();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    for (final item in [
      email,
      name,
      phone,
      company,
      unitInputController,
      employeeInputController,
    ]) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!key.currentState!.validate()) return;
    if (editing) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Save landlord changes?'),
          content: Text(
            'Update ${name.text.trim()} with the details, assigned units, and permissions entered in this form?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save changes'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    setState(() => busy = true);
    try {
      final now = DateTime.now();
      final controller = ref.read(landlordsProvider.notifier);
      final admin = ref.read(currentAdminUserProvider);
      if (admin == null) {
        throw StateError('An authenticated administrator is required.');
      }
      if (editing && existing != null) {
        await controller.updateLandlord(
          existing!.copyWith(
            displayName: name.text.trim(),
            companyName: company.text.trim(),
            phone: phone.text.trim(),
            status: status,
            canManageAllUnits: canManageAllUnits,
            assignedUnitIds: assignedUnitIds,
            assignedEmployeeEmails: assignedEmployeeEmails,
            permissions: permissions,
          ),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Landlord profile and permissions updated.'),
            ),
          );
          context.go(AdminRoutes.landlord(existing!.uid));
        }
      } else {
        final created = await controller.create(
          LandlordAccount(
            uid: '',
            email: email.text.trim().toLowerCase(),
            displayName: name.text.trim(),
            companyName: company.text.trim(),
            phone: phone.text.trim(),
            status: status,
            canManageAllUnits: canManageAllUnits,
            assignedUnitIds: assignedUnitIds,
            assignedEmployeeEmails: assignedEmployeeEmails,
            permissions: permissions,
            createdAt: now,
            updatedAt: now,
            createdBy: admin.uid,
            updatedBy: admin.uid,
          ),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Landlord created successfully.')),
          );
          context.go(AdminRoutes.landlord(created.uid));
        }
      }
    } on StateError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.message == 'duplicate-email'
                  ? 'An account with this email already exists.'
                  : error.message.toString(),
            ),
          ),
        );
      }
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FirebaseErrorMapper.message(error))),
        );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(FirebaseErrorMapper.message(error))),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _addUnit() {
    final text = unitInputController.text.trim();
    if (text.isNotEmpty && !assignedUnitIds.contains(text)) {
      setState(() {
        assignedUnitIds.add(text);
        unitInputController.clear();
      });
    }
  }

  void _addEmployee() {
    final text = employeeInputController.text.trim().toLowerCase();
    if (text.isNotEmpty &&
        text.contains('@') &&
        !assignedEmployeeEmails.contains(text)) {
      setState(() {
        assignedEmployeeEmails.add(text);
        employeeInputController.clear();
      });
    }
  }

  void _togglePermission(String perm) {
    setState(() {
      if (permissions.contains(perm)) {
        permissions.remove(perm);
      } else {
        permissions.add(perm);
      }
    });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 700 ? 20 : 32),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: editing ? 'Edit Landlord' : 'Add Landlord',
              subtitle: editing
                  ? 'Update profile details, unit assignments, and management permissions.'
                  : 'Create a landlord or employee management account.',
            ),
            const SizedBox(height: 20),
            if (busy && editing && existing == null)
              const LoadingSkeleton(rows: 6)
            else if (editing && existing == null)
              ErrorView(
                message: loadError ?? 'Landlord record not found.',
                onRetry: canRetryLoad ? _load : null,
                actionLabel: 'Retry',
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: key,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _section('Account information'),
                        TextFormField(
                          controller: email,
                          readOnly: editing,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Email address *',
                            helperText: editing
                                ? 'Email changes require a separate secure workflow.'
                                : null,
                            suffixIcon: editing
                                ? const Icon(Icons.lock_outline)
                                : null,
                          ),
                          validator: (value) {
                            if (editing) return null;
                            final text = value?.trim() ?? '';
                            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(text)) {
                              return 'Enter a valid email address';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: name,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Display name *',
                          ),
                          validator: (value) =>
                              _required(value, 'Display name'),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: phone,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Phone number',
                          ),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.isEmpty) return null;
                            final digits = text.replaceAll(
                              RegExp(r'[^0-9]'),
                              '',
                            );
                            return digits.length < 7 ||
                                    digits.length > 15 ||
                                    !RegExp(r'^[+()\d .-]+$').hasMatch(text)
                                ? 'Enter a phone number with 7 to 15 digits'
                                : null;
                          },
                        ),
                        const SizedBox(height: 24),
                        _section('Organization'),
                        TextFormField(
                          controller: company,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Company / property business name *',
                          ),
                          validator: (value) =>
                              _required(value, 'Company name'),
                        ),
                        const SizedBox(height: 24),
                        _section('Account Access & Status'),
                        DropdownButtonFormField<LandlordStatus>(
                          isExpanded: true,
                          initialValue: status,
                          decoration: const InputDecoration(
                            labelText: 'Account Status',
                            helperText: 'Use account actions to change landlord access status.',
                          ),
                          items: LandlordStatus.values
                              .where(
                                (value) =>
                                    value != LandlordStatus.unknown ||
                                    status == LandlordStatus.unknown,
                              )
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    s == LandlordStatus.unknown
                                        ? existing?.statusLabel ?? 'Unknown'
                                        : _statusTitle(s),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: null,
                        ),
                        const SizedBox(height: 24),
                        _section('Unit Assignments & Employee Delegation'),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Manage All Portfolio Units'),
                          subtitle: const Text(
                            'When enabled, this account can manage all units under the company. Disable to assign specific units.',
                          ),
                          value: canManageAllUnits,
                          onChanged: (val) =>
                              setState(() => canManageAllUnits = val),
                        ),
                        if (!canManageAllUnits) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: unitInputController,
                                  decoration: const InputDecoration(
                                    labelText: 'Assign Specific Unit Number',
                                    hintText: 'e.g., Unit 101, Building A-202',
                                  ),
                                  onSubmitted: (_) => _addUnit(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _addUnit,
                                child: const Text('Add Unit'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: assignedUnitIds
                                .map(
                                  (unit) => Chip(
                                    avatar: const Icon(
                                      Icons.apartment,
                                      size: 16,
                                    ),
                                    label: Text(unit),
                                    onDeleted: () => setState(
                                      () => assignedUnitIds.remove(unit),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: 20),
                        const Text(
                          'Delegated Employees / Co-Managers (While Away)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Assign employee email accounts so they are permitted to manage these units while the landlord is away.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: employeeInputController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Employee / Co-Manager Email',
                                  hintText: 'e.g., assistant@ramp.local',
                                ),
                                onSubmitted: (_) => _addEmployee(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _addEmployee,
                              child: const Text('Delegate'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: assignedEmployeeEmails
                              .map(
                                (emp) => Chip(
                                  avatar: const Icon(Icons.person, size: 16),
                                  label: Text(emp),
                                  onDeleted: () => setState(
                                    () => assignedEmployeeEmails.remove(emp),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 24),
                        _section('Granular Permissions'),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _permChip(
                              'manage_units',
                              'Units & Listings',
                              Icons.apartment,
                            ),
                            _permChip(
                              'manage_tenants',
                              'Tenants & Agreements',
                              Icons.groups,
                            ),
                            _permChip(
                              'manage_payments',
                              'Collect Payments',
                              Icons.payments,
                            ),
                            _permChip(
                              'manage_tickets',
                              'Maintenance Tickets',
                              Icons.build,
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 10,
                          children: [
                            OutlinedButton(
                              onPressed: () => context.pop(),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: busy ? null : _submit,
                              child: Text(
                                editing ? 'Save changes' : 'Create landlord',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _permChip(String key, String label, IconData icon) {
    final selected = permissions.contains(key);
    return FilterChip(
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? Colors.white : AppColors.primaryBlue,
      ),
      label: Text(label),
      selected: selected,
      onSelected: (_) => _togglePermission(key),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  );

  String? _required(String? value, String label) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '$label is required';
    if (text.length < 2) return '$label must contain at least 2 characters';
    final maxLength = label == 'Display name' ? 100 : 120;
    if (text.length > maxLength) {
      return '$label must be $maxLength characters or fewer';
    }
    return null;
  }

  String _statusTitle(LandlordStatus value) => value == LandlordStatus.invited
      ? 'Pending activation'
      : '${value.name[0].toUpperCase()}${value.name.substring(1)}';
}
