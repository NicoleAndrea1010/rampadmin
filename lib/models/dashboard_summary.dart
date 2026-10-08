class DashboardSummary {
  const DashboardSummary({
    required this.totalLandlords,
    required this.activeLandlords,
    required this.invitedLandlords,
    required this.suspendedLandlords,
    required this.archivedLandlords,
  });

  final int totalLandlords;
  final int activeLandlords;
  final int invitedLandlords;
  final int suspendedLandlords;
  final int archivedLandlords;
}

class OperationalSummary {
  const OperationalSummary({
    required this.totalUnits,
    required this.occupiedUnits,
    required this.vacantUnits,
    required this.totalTenants,
    required this.paidPaymentValue,
    required this.pendingPaymentValue,
    required this.openMaintenanceTickets,
  });
  final int totalUnits;
  final int occupiedUnits;
  final int vacantUnits;
  final int totalTenants;
  final double paidPaymentValue;
  final double pendingPaymentValue;
  final int openMaintenanceTickets;
}
