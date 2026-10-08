import 'package:cloud_firestore/cloud_firestore.dart';

enum LandlordStatus { invited, active, suspended, archived, unknown }

class LandlordAccount {
  const LandlordAccount({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.companyName,
    required this.phone,
    required this.status,
    this.unitCount = 0,
    this.tenantCount = 0,
    this.paidThisMonth = 0,
    this.monthlyRevenue = const {},
    this.openTicketCount = 0,
    this.metricsAvailable = true,
    this.paymentMetricsAvailable = true,
    this.rawStatus,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    this.suspensionReason,
    this.suspendedAt,
    this.archivedAt,
    this.lastSignInAt,
    this.canManageAllUnits = true,
    this.assignedUnitIds = const [],
    this.assignedEmployeeEmails = const [],
    this.permissions = const [
      'manage_units',
      'manage_tenants',
      'manage_payments',
      'manage_tickets',
    ],
  });

  final String uid;
  final String email;
  final String displayName;
  final String companyName;
  final String phone;
  final LandlordStatus status;
  final int unitCount;
  final int tenantCount;
  final double paidThisMonth;
  final Map<String, double> monthlyRevenue;
  final int openTicketCount;
  final bool metricsAvailable;
  final bool paymentMetricsAvailable;
  final String? rawStatus;

  String get statusLabel => switch (status) {
    LandlordStatus.invited => 'Pending activation',
    LandlordStatus.unknown =>
      'Unknown / ${rawStatus?.isNotEmpty == true ? rawStatus : 'missing'}',
    _ => status.name,
  };
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final String updatedBy;
  final String? suspensionReason;
  final DateTime? suspendedAt;
  final DateTime? archivedAt;
  final DateTime? lastSignInAt;

  // Granular Unit Assignment & Employee Delegation
  final bool canManageAllUnits;
  final List<String> assignedUnitIds;
  final List<String> assignedEmployeeEmails;
  final List<String> permissions;

  factory LandlordAccount.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();

    if (data == null) {
      throw StateError('Landlord ${document.id} has no data.');
    }

    final rawStatus = data['status'] as String?;
    final status = LandlordStatus.values
        .where(
          (value) =>
              value != LandlordStatus.unknown &&
              value.name.toLowerCase() == rawStatus?.trim().toLowerCase(),
        )
        .firstOrNull;
    return LandlordAccount(
      uid: document.id,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      companyName: data['companyName'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      status: status ?? LandlordStatus.unknown,
      rawStatus: status == null ? rawStatus : null,
      unitCount: (data['unitCount'] as num?)?.toInt() ?? 0,
      tenantCount: (data['tenantCount'] as num?)?.toInt() ?? 0,
      paidThisMonth: (data['paidThisMonth'] as num?)?.toDouble() ?? 0,
      openTicketCount: (data['openTicketCount'] as num?)?.toInt() ?? 0,
      metricsAvailable: true,
      paymentMetricsAvailable: false,
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          (data['updatedAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      createdBy: data['createdBy'] as String? ?? '',
      updatedBy: data['updatedBy'] as String? ?? '',
      suspensionReason: data['suspensionReason'] as String?,
      suspendedAt: (data['suspendedAt'] as Timestamp?)?.toDate(),
      archivedAt: (data['archivedAt'] as Timestamp?)?.toDate(),
      lastSignInAt: (data['lastSignInAt'] as Timestamp?)?.toDate(),
      canManageAllUnits: data['canManageAllUnits'] as bool? ?? true,
      assignedUnitIds:
          (data['assignedUnitIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      assignedEmployeeEmails:
          (data['assignedEmployeeEmails'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      permissions:
          (data['permissions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [
            'manage_units',
            'manage_tenants',
            'manage_payments',
            'manage_tickets',
          ],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'companyName': companyName,
      'phone': phone,
      'status': status == LandlordStatus.unknown
          ? rawStatus ?? 'unknown'
          : status.name,
      'unitCount': unitCount,
      'tenantCount': tenantCount,
      'paidThisMonth': paidThisMonth,
      'openTicketCount': openTicketCount,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'createdBy': createdBy,
      'updatedBy': updatedBy,
      'canManageAllUnits': canManageAllUnits,
      'assignedUnitIds': assignedUnitIds,
      'assignedEmployeeEmails': assignedEmployeeEmails,
      'permissions': permissions,
      if (suspensionReason != null) 'suspensionReason': suspensionReason,
      if (suspendedAt != null) 'suspendedAt': Timestamp.fromDate(suspendedAt!),
      if (archivedAt != null) 'archivedAt': Timestamp.fromDate(archivedAt!),
      if (lastSignInAt != null)
        'lastSignInAt': Timestamp.fromDate(lastSignInAt!),
    };
  }

  LandlordAccount copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? companyName,
    String? phone,
    LandlordStatus? status,
    int? unitCount,
    int? tenantCount,
    double? paidThisMonth,
    int? openTicketCount,
    bool? metricsAvailable,
    bool? paymentMetricsAvailable,
    String? rawStatus,
    DateTime? updatedAt,
    String? updatedBy,
    String? suspensionReason,
    DateTime? suspendedAt,
    DateTime? archivedAt,
    Map<String, double>? monthlyRevenue,
    bool? canManageAllUnits,
    List<String>? assignedUnitIds,
    List<String>? assignedEmployeeEmails,
    List<String>? permissions,
  }) => LandlordAccount(
    uid: uid ?? this.uid,
    email: email ?? this.email,
    displayName: displayName ?? this.displayName,
    companyName: companyName ?? this.companyName,
    phone: phone ?? this.phone,
    status: status ?? this.status,
    unitCount: unitCount ?? this.unitCount,
    tenantCount: tenantCount ?? this.tenantCount,
    paidThisMonth: paidThisMonth ?? this.paidThisMonth,
    monthlyRevenue: monthlyRevenue ?? this.monthlyRevenue,
    openTicketCount: openTicketCount ?? this.openTicketCount,
    metricsAvailable: metricsAvailable ?? this.metricsAvailable,
    paymentMetricsAvailable:
        paymentMetricsAvailable ?? this.paymentMetricsAvailable,
    rawStatus: rawStatus ?? this.rawStatus,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    createdBy: createdBy,
    updatedBy: updatedBy ?? this.updatedBy,
    suspensionReason: suspensionReason ?? this.suspensionReason,
    suspendedAt: suspendedAt ?? this.suspendedAt,
    archivedAt: archivedAt ?? this.archivedAt,
    lastSignInAt: lastSignInAt,
    canManageAllUnits: canManageAllUnits ?? this.canManageAllUnits,
    assignedUnitIds: assignedUnitIds ?? this.assignedUnitIds,
    assignedEmployeeEmails:
        assignedEmployeeEmails ?? this.assignedEmployeeEmails,
    permissions: permissions ?? this.permissions,
  );
}
