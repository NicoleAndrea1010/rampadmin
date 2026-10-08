import 'package:intl/intl.dart';

import '../../core/services/supabase_service.dart';
import '../landlords/landlord_repository.dart';
import '../operations/operational_data_repository.dart';

class DashboardData {
  const DashboardData({
    required this.growth,
    required this.monthlyRevenue,
    required this.managedUnits,
    required this.registeredTenants,
    required this.openMaintenance,
    required this.highPriorityMaintenance,
    required this.unitsByStatus,
    required this.paymentsByStatus,
    required this.maintenanceByStatus,
    required this.outstandingPayments,
    required this.overduePayments,
    required this.paymentBalancesAvailable,
    required this.maintenanceExpenses,
    required this.slaBreaches,
    required this.missingLandlordId,
    required this.orphanRelationships,
    required this.paymentsMissingTenancy,
    required this.ownershipMismatches,
    required this.awaitingEstimate,
    required this.completedMaintenanceThisMonth,
    required this.maintenanceMissingUnitId,
    required this.archivedUnits,
    required this.awaitingVisit,
    required this.scheduledRepair,
    required this.orphanTenants,
    required this.orphanUnits,
    required this.unknownUnitStatuses,
    this.refreshedAt,
  });

  final Map<String, double> growth;
  final Map<String, double> monthlyRevenue;
  final int managedUnits;
  final int registeredTenants;
  final int openMaintenance;
  final int highPriorityMaintenance;
  final Map<String, int> unitsByStatus;
  final Map<String, int> paymentsByStatus;
  final Map<String, int> maintenanceByStatus;
  final double outstandingPayments;
  final double overduePayments;
  final bool paymentBalancesAvailable;
  final double? maintenanceExpenses;
  final int? slaBreaches;
  final int missingLandlordId;
  final int orphanRelationships;
  final int paymentsMissingTenancy;
  final int ownershipMismatches;
  final int awaitingEstimate;
  final int? completedMaintenanceThisMonth;
  final int maintenanceMissingUnitId;
  final int archivedUnits;
  final int awaitingVisit;
  final int scheduledRepair;
  final int orphanTenants;
  final int orphanUnits;
  final int unknownUnitStatuses;
  final DateTime? refreshedAt;
}

abstract interface class DashboardRepository {
  Future<DashboardData> getSummary();
}

class SupabaseDashboardRepository implements DashboardRepository {
  SupabaseDashboardRepository({SupabaseService? supabase})
    : _supabase = supabase ?? SupabaseService();

  final SupabaseService _supabase;

  @override
  Future<DashboardData> getSummary() async {
    const collections = ['units', 'tenants', 'payments', 'maintenanceTickets'];
    final loadedRecords = await Future.wait(
      collections.map(_supabase.loadTable),
    );
    final recordsByCollection = {
      for (var index = 0; index < collections.length; index++)
        collections[index]: loadedRecords[index],
    };
    final payments = recordsByCollection['payments']!;
    final units = recordsByCollection['units']!;
    final tickets = recordsByCollection['maintenanceTickets']!;
    final monthlyRevenue = LandlordPaymentMetrics.sixMonthPaidRevenue(
      payments,
      DateTime.now(),
    );
    final growth = {
      for (final entry in monthlyRevenue.entries)
        DateFormat.MMM().format(_monthDate(entry.key)): entry.value,
    };
    var openMaintenance = 0;
    var highPriorityMaintenance = 0;
    var slaBreaches = 0;
    var hasSlaDueDates = false;
    var awaitingEstimate = 0;
    var awaitingVisit = 0;
    var scheduledRepair = 0;
    var completedMaintenanceThisMonth = 0;
    var maintenanceExpenses = 0.0;
    var maintenanceExpensesAvailable = true;
    var completedMaintenanceDatesAvailable = true;
    var completedTicketCount = 0;
    final maintenanceByStatus = <String, int>{};
    for (final ticket in tickets) {
      final statusValue = ticket['status'] as String? ?? '';
      final status = _normalizedStatus(statusValue);
      if (status.isNotEmpty) {
        maintenanceByStatus.update(
          statusValue.trim(),
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      if (status == 'estimate') {
        awaitingEstimate++;
      }
      if (status == 'pending' || status == 'schedule visit') {
        awaitingVisit++;
      }
      if (status == 'schedule repair') {
        scheduledRepair++;
      }
      if (status == 'completed') {
        completedTicketCount++;
        final completedAt = _date(ticket['completedAt']);
        final now = DateTime.now();
        if (completedAt == null) {
          completedMaintenanceDatesAvailable = false;
        } else if (completedAt.year == now.year &&
            completedAt.month == now.month) {
          completedMaintenanceThisMonth++;
        }
        final actualCost = ticket['actualCost'] as num?;
        if (actualCost != null && actualCost.isFinite && actualCost >= 0) {
          maintenanceExpenses += actualCost.toDouble();
        } else {
          maintenanceExpensesAvailable = false;
        }
        continue;
      }
      if (const {
        'pending',
        'schedule visit',
        'estimate',
        'schedule repair',
      }.contains(status)) {
        openMaintenance++;
        if ((ticket['priority'] as String? ?? '').toLowerCase().trim() ==
            'high') {
          highPriorityMaintenance++;
        }
      }
      final due = _date(ticket['slaDueDate'] ?? ticket['slaDueAt']);
      if (due != null) {
        hasSlaDueDates = true;
        if (due.isBefore(DateTime.now())) slaBreaches++;
      }
    }
    final archivedUnits = units.where((unit) {
      return unit['isArchived'] == true ||
          unit['archived'] == true ||
          (unit['archivedAt'] != null &&
              unit['archivedAt'].toString().isNotEmpty) ||
          (unit['status'] as String? ?? '').toLowerCase() == 'archived';
    }).length;
    final activeUnits = units.where((unit) {
      return unit['isArchived'] != true &&
          unit['archived'] != true &&
          (unit['archivedAt'] == null ||
              unit['archivedAt'].toString().isEmpty) &&
          (unit['status'] as String? ?? '').toLowerCase() != 'archived';
    }).toList();
    final unitsByStatus = _countBy(activeUnits, 'status');
    const knownUnitStatuses = {'occupied', 'vacant', 'reserved', 'inactive'};
    final unknownUnitStatuses = activeUnits.where((unit) {
      final status = _normalizedStatus(unit['status'] as String? ?? '');
      return status.isNotEmpty && !knownUnitStatuses.contains(status);
    }).length;
    final paymentsByStatus = _countBy(payments, 'status');
    final tenants = recordsByCollection['tenants']!;
    final unitIds = units.map((unit) => unit['id']?.toString()).toSet();
    final tenantIds = tenants.map((tenant) => tenant['id']?.toString()).toSet();
    final operationalRecords = [...units, ...tenants, ...payments, ...tickets];
    var missingLandlordId = 0;
    var ownershipMismatches = 0;
    for (final record in operationalRecords) {
      final owners = operationalOwnerIds(record);
      if (owners.isEmpty) {
        missingLandlordId++;
      }
      if (owners.length > 1) {
        ownershipMismatches++;
      }
    }
    var orphanRelationships = 0;
    var orphanTenants = 0;
    var orphanUnits = 0;
    for (final tenant in tenants) {
      final unitId = tenant['unitId']?.toString() ?? '';
      if (unitId.isNotEmpty && !unitIds.contains(unitId)) {
        orphanRelationships++;
        orphanTenants++;
      }
    }
    for (final unit in units) {
      final tenantId = unit['tenantId']?.toString() ?? '';
      if (tenantId.isNotEmpty && !tenantIds.contains(tenantId)) {
        orphanRelationships++;
        orphanUnits++;
      }
    }
    for (final payment in payments) {
      final tenantId = payment['tenantId']?.toString() ?? '';
      if (tenantId.isNotEmpty && !tenantIds.contains(tenantId)) {
        orphanRelationships++;
      }
      final unitId = payment['unitId']?.toString() ?? '';
      if (unitId.isNotEmpty && !unitIds.contains(unitId)) {
        orphanRelationships++;
      }
    }
    for (final ticket in tickets) {
      final unitId = ticket['unitId']?.toString() ?? '';
      if (unitId.isNotEmpty && !unitIds.contains(unitId)) {
        orphanRelationships++;
      }
      final tenantId = ticket['tenantId']?.toString() ?? '';
      if (tenantId.isNotEmpty && !tenantIds.contains(tenantId)) {
        orphanRelationships++;
      }
    }
    var outstandingPayments = 0.0;
    var overduePayments = 0.0;
    var paymentBalancesAvailable = true;
    for (final payment in payments) {
      final status = (payment['status'] as String? ?? '').trim().toLowerCase();
      final isRent =
          (payment['transactionType'] as String? ?? '').trim().toLowerCase() ==
          'rent';
      if (isRent && (status == 'pending' || status == 'overdue')) {
        final amount = payment['amount'] as num?;
        if (amount != null && amount.isFinite && amount >= 0) {
          if (status == 'pending') outstandingPayments += amount.toDouble();
          if (status == 'overdue') overduePayments += amount.toDouble();
        } else {
          paymentBalancesAvailable = false;
        }
      }
    }

    return DashboardData(
      growth: growth,
      monthlyRevenue: monthlyRevenue,
      managedUnits: units.length,
      openMaintenance: openMaintenance,
      highPriorityMaintenance: highPriorityMaintenance,
      registeredTenants: tenants.length,
      unitsByStatus: unitsByStatus,
      paymentsByStatus: paymentsByStatus,
      maintenanceByStatus: maintenanceByStatus,
      outstandingPayments: outstandingPayments,
      overduePayments: overduePayments,
      paymentBalancesAvailable: paymentBalancesAvailable,
      maintenanceExpenses: maintenanceExpensesAvailable
          ? maintenanceExpenses
          : null,
      slaBreaches: hasSlaDueDates ? slaBreaches : null,
      missingLandlordId: missingLandlordId,
      orphanRelationships: orphanRelationships,
      paymentsMissingTenancy: payments
          .where((payment) => (payment['tenancyId']?.toString() ?? '').isEmpty)
          .length,
      ownershipMismatches: ownershipMismatches,
      awaitingEstimate: awaitingEstimate,
      completedMaintenanceThisMonth:
          completedTicketCount == 0 || completedMaintenanceDatesAvailable
          ? completedMaintenanceThisMonth
          : null,
      maintenanceMissingUnitId: tickets
          .where((ticket) => (ticket['unitId']?.toString() ?? '').isEmpty)
          .length,
      archivedUnits: archivedUnits,
      awaitingVisit: awaitingVisit,
      scheduledRepair: scheduledRepair,
      orphanTenants: orphanTenants,
      orphanUnits: orphanUnits,
      unknownUnitStatuses: unknownUnitStatuses,
      refreshedAt: DateTime.now(),
    );
  }

  Map<String, int> _countBy(List<Map<String, dynamic>> records, String field) {
    final counts = <String, int>{};
    for (final record in records) {
      final status = (record[field] as String? ?? '').trim();
      if (status.isEmpty) continue;
      counts.update(status, (count) => count + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  DateTime? _date(Object? value) => switch (value) {
    DateTime date => date,
    String date => DateTime.tryParse(date),
    _ => null,
  };

  String _normalizedStatus(String value) =>
      value.replaceAll('_', ' ').replaceAll('-', ' ').toLowerCase().trim();

  DateTime _monthDate(String key) {
    final parts = key.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]));
  }
}

class MockDashboardRepository implements DashboardRepository {
  @override
  Future<DashboardData> getSummary() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return const DashboardData(
      growth: {},
      monthlyRevenue: {},
      managedUnits: 0,
      registeredTenants: 0,
      openMaintenance: 0,
      highPriorityMaintenance: 0,
      unitsByStatus: {},
      paymentsByStatus: {},
      maintenanceByStatus: {},
      outstandingPayments: 0,
      overduePayments: 0,
      paymentBalancesAvailable: true,
      maintenanceExpenses: 0,
      slaBreaches: 0,
      missingLandlordId: 0,
      orphanRelationships: 0,
      paymentsMissingTenancy: 0,
      ownershipMismatches: 0,
      awaitingEstimate: 0,
      completedMaintenanceThisMonth: null,
      maintenanceMissingUnitId: 0,
      archivedUnits: 0,
      awaitingVisit: 0,
      scheduledRepair: 0,
      orphanTenants: 0,
      orphanUnits: 0,
      unknownUnitStatuses: 0,
    );
  }
}
