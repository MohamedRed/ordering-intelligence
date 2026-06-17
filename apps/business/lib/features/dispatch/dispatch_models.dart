class DriverShiftInfo {
  const DriverShiftInfo({required this.status, required this.updatedAt});

  final String status;
  final DateTime? updatedAt;
}

class DriverLocationInfo {
  const DriverLocationInfo({
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.recordedAt,
  });

  final double lat;
  final double lng;
  final double accuracyM;
  final DateTime? recordedAt;
}

class DispatchAssignment {
  const DispatchAssignment({
    required this.id,
    required this.orderId,
    required this.driverId,
    required this.status,
    required this.expiresAt,
    required this.updatedAt,
    required this.candidates,
  });

  final String id;
  final String orderId;
  final String driverId;
  final String status;
  final DateTime? expiresAt;
  final DateTime? updatedAt;
  final List<Map<String, dynamic>> candidates;
}

class DispatchRoute {
  const DispatchRoute({
    required this.id,
    required this.driverId,
    required this.status,
    required this.deliveryIds,
    required this.updatedAt,
  });

  final String id;
  final String driverId;
  final String status;
  final List<String> deliveryIds;
  final DateTime? updatedAt;
}
