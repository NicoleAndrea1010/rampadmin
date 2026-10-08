import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class DashboardMockData {
  const DashboardMockData({
    required this.growth,
    required this.managedUnits,
    required this.registeredTenants,
    required this.openMaintenance,
    required this.highPriorityMaintenance,
  });
  final Map<String, double> growth;
  final int managedUnits;
  final int registeredTenants;
  final int openMaintenance;
  final int highPriorityMaintenance;
}

abstract interface class DashboardRepository {
  Future<DashboardMockData> getSummary();
}

class FirestoreDashboardRepository implements DashboardRepository {
  FirestoreDashboardRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<DashboardMockData> getSummary() async {
    final units = await _firestore.collection('units').get();
    final tenants = await _firestore.collection('tenants').get();
    final tickets = await _firestore.collection('maintenanceTickets').get();
    final landlords = await _firestore.collection('landlords').get();
    var openMaintenance = 0;
    var highPriorityMaintenance = 0;
    for (final ticket in tickets.docs) {
      if (ticket.id.startsWith('tkt_00')) continue;
      final data = ticket.data();
      final status = (data['status'] as String? ?? '').toLowerCase();
      if (status != 'completed' && status != 'resolved') {
        openMaintenance++;
        if ((data['priority'] as String? ?? '').toLowerCase() == 'high') {
          highPriorityMaintenance++;
        }
      }
    }

    final now = DateTime.now();
    final growth = <String, double>{};
    final months = <DateTime>[
      for (var offset = 5; offset >= 0; offset--)
        DateTime(now.year, now.month - offset),
    ];
    for (final month in months) {
      growth[DateFormat('MMM').format(month)] = landlords.docs
          .where((doc) {
            final createdAt = (doc.data()['createdAt'] as Timestamp?)?.toDate();
            return createdAt != null &&
                createdAt.year == month.year &&
                createdAt.month == month.month;
          })
          .length
          .toDouble();
    }

    return DashboardMockData(
      growth: growth,
      managedUnits: units.docs.length,
      registeredTenants: tenants.docs.length,
      openMaintenance: openMaintenance,
      highPriorityMaintenance: highPriorityMaintenance,
    );
  }
}

class MockDashboardRepository implements DashboardRepository {
  @override
  Future<DashboardMockData> getSummary() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return const DashboardMockData(
      growth: {'Apr': 2, 'May': 3, 'Jun': 5, 'Jul': 4, 'Aug': 6, 'Sep': 8},
      managedUnits: 86,
      registeredTenants: 63,
      openMaintenance: 12,
      highPriorityMaintenance: 4,
    );
  }
}
