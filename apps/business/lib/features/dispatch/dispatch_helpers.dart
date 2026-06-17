import 'package:cloud_firestore/cloud_firestore.dart';

import '../../providers/dispatch_api.dart';
import 'dispatch_models.dart';

DateTime? readDispatchTime(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

double readDispatchNum(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

String formatDispatchTime(DateTime? time) {
  if (time == null) return '';
  final local = time.toLocal();
  final date =
      '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final clock =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$date $clock';
}

List<DispatchDriver> filteredDispatchDrivers({
  required List<DispatchDriver> drivers,
  required Map<String, DriverShiftInfo> shifts,
  required String shiftFilter,
  required bool activeOnly,
}) {
  return drivers.where((driver) {
    if (activeOnly && !driver.active) return false;
    if (shiftFilter == 'all') return true;
    final uid = driver.uid.trim();
    if (shiftFilter == 'unclaimed') return uid.isEmpty;
    if (uid.isEmpty) return false;
    return shifts[uid]?.status == shiftFilter;
  }).toList(growable: false);
}

List<DispatchAssignment> filteredDispatchAssignments(
  List<DispatchAssignment> assignments,
  String statusFilter,
) {
  if (statusFilter == 'all') return assignments;
  return assignments
      .where((assignment) => assignment.status == statusFilter)
      .toList(growable: false);
}

List<DispatchRoute> filteredDispatchRoutes(
  List<DispatchRoute> routes,
  String statusFilter,
) {
  if (statusFilter == 'all') return routes;
  return routes
      .where((route) => route.status == statusFilter)
      .toList(growable: false);
}

String dispatchDriverLabel(List<DispatchDriver> drivers, String uid) {
  if (uid.isEmpty) return 'unassigned';
  final matches = drivers.where((driver) => driver.uid == uid).toList();
  if (matches.isEmpty) return uid;
  final driver = matches.first;
  return driver.displayName.isNotEmpty ? driver.displayName : driver.id;
}

String dispatchAssignmentEta(DispatchAssignment assignment) {
  if (assignment.driverId.isEmpty || assignment.candidates.isEmpty) {
    return formatDispatchTime(assignment.expiresAt);
  }
  final match = assignment.candidates.firstWhere(
    (candidate) =>
        (candidate['driverId'] as String?)?.trim() == assignment.driverId,
    orElse: () => const <String, dynamic>{},
  );
  final etaSecs = readDispatchNum(match['etaToPickupSecs']).toInt();
  if (etaSecs <= 0) return formatDispatchTime(assignment.expiresAt);
  final mins = (etaSecs / 60).round();
  return '~$mins min';
}
