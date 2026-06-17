import 'package:cloud_firestore/cloud_firestore.dart';

import 'dispatch_helpers.dart';
import 'dispatch_models.dart';

Future<List<DispatchAssignment>> fetchDispatchAssignments(
    String storeId) async {
  final snap = await FirebaseFirestore.instance
      .collection('stores')
      .doc(storeId)
      .collection('driver_assignments')
      .orderBy('updatedAt', descending: true)
      .limit(25)
      .get();
  return snap.docs.map((doc) {
    final data = doc.data();
    final candidatesRaw = data['candidates'];
    final candidates = candidatesRaw is List
        ? candidatesRaw
            .whereType<Map>()
            .map((entry) => entry.cast<String, dynamic>())
            .toList()
        : <Map<String, dynamic>>[];
    return DispatchAssignment(
      id: doc.id,
      orderId: (data['orderId'] as String?)?.trim() ?? '',
      driverId: (data['driverId'] as String?)?.trim() ?? '',
      status: (data['status'] as String?)?.trim() ?? '',
      expiresAt: readDispatchTime(data['expiresAt']),
      updatedAt: readDispatchTime(data['updatedAt']),
      candidates: candidates,
    );
  }).toList(growable: false);
}

Future<List<DispatchRoute>> fetchDispatchRoutes(String storeId) async {
  final snap = await FirebaseFirestore.instance
      .collection('stores')
      .doc(storeId)
      .collection('driver_routes')
      .orderBy('updatedAt', descending: true)
      .limit(25)
      .get();
  return snap.docs.map((doc) {
    final data = doc.data();
    final deliveriesRaw = data['deliveryIds'];
    final deliveries = deliveriesRaw is List
        ? deliveriesRaw.map((entry) => entry.toString()).toList()
        : const <String>[];
    return DispatchRoute(
      id: doc.id,
      driverId: (data['driverId'] as String?)?.trim() ?? '',
      status: (data['status'] as String?)?.trim() ?? '',
      deliveryIds: deliveries,
      updatedAt: readDispatchTime(data['updatedAt']),
    );
  }).toList(growable: false);
}

Future<Map<String, DriverShiftInfo>> fetchDriverShifts(String storeId) async {
  final snap = await FirebaseFirestore.instance
      .collection('stores')
      .doc(storeId)
      .collection('driver_shifts')
      .get();
  final out = <String, DriverShiftInfo>{};
  for (final doc in snap.docs) {
    final data = doc.data();
    out[doc.id] = DriverShiftInfo(
      status: (data['status'] as String?)?.trim() ?? '',
      updatedAt: readDispatchTime(data['updatedAt']),
    );
  }
  return out;
}

Future<Map<String, DriverLocationInfo>> fetchDriverLocations(
    String storeId) async {
  final snap = await FirebaseFirestore.instance
      .collection('stores')
      .doc(storeId)
      .collection('driver_locations')
      .get();
  final out = <String, DriverLocationInfo>{};
  for (final doc in snap.docs) {
    final data = doc.data();
    out[doc.id] = DriverLocationInfo(
      lat: readDispatchNum(data['lat']),
      lng: readDispatchNum(data['lng']),
      accuracyM: readDispatchNum(data['accuracyM']),
      recordedAt: readDispatchTime(data['recordedAt']),
    );
  }
  return out;
}
