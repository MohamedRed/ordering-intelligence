class DeliveryLatLng {
  final double lat;
  final double lng;

  const DeliveryLatLng({required this.lat, required this.lng});

  factory DeliveryLatLng.fromJson(Map<String, dynamic> json) {
    return DeliveryLatLng(
      lat: _toDouble(json['lat']),
      lng: _toDouble(json['lng']),
    );
  }

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  static double _toDouble(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
}

class DeliveryAddress {
  final String line1;
  final String line2;
  final String city;
  final String state;
  final String postalCode;
  final String country;
  final String formatted;

  const DeliveryAddress({
    this.line1 = '',
    this.line2 = '',
    this.city = '',
    this.state = '',
    this.postalCode = '',
    this.country = '',
    this.formatted = '',
  });

  factory DeliveryAddress.fromJson(Map<String, dynamic> json) {
    return DeliveryAddress(
      line1: (json['line1'] ?? '').toString(),
      line2: (json['line2'] ?? '').toString(),
      city: (json['city'] ?? '').toString(),
      state: (json['state'] ?? '').toString(),
      postalCode: (json['postalCode'] ?? json['postal_code'] ?? '').toString(),
      country: (json['country'] ?? '').toString(),
      formatted: (json['formatted'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'line1': line1,
    'line2': line2,
    'city': city,
    'state': state,
    'postalCode': postalCode,
    'country': country,
    'formatted': formatted,
  };
}

class DeliveryDraft {
  final String fleetMode;
  final DeliveryLatLng? dropoffLatLng;
  final DeliveryAddress? dropoffAddress;
  final String instructions;
  final int offerCents;

  const DeliveryDraft({
    required this.fleetMode,
    this.dropoffLatLng,
    this.dropoffAddress,
    this.instructions = '',
    this.offerCents = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'fleetMode': fleetMode,
      if (dropoffLatLng != null) 'dropoffLatLng': dropoffLatLng!.toJson(),
      if (dropoffAddress != null) 'dropoffAddress': dropoffAddress!.toJson(),
      if (instructions.trim().isNotEmpty) 'instructions': instructions.trim(),
      if (offerCents > 0) 'offerCents': offerCents,
    };
  }
}

class DeliveryPrewarmResult {
  final int etaMinutes;
  final DeliveryLatLng? dropoffLatLng;
  final DeliveryAddress? dropoffAddress;
  final List<String> candidateIds;

  const DeliveryPrewarmResult({
    this.etaMinutes = 0,
    this.dropoffLatLng,
    this.dropoffAddress,
    this.candidateIds = const [],
  });

  factory DeliveryPrewarmResult.fromJson(Map<String, dynamic> json) {
    final candidateRaw = json['candidateIds'];
    final candidates = candidateRaw is List
        ? candidateRaw.map((e) => e.toString()).toList()
        : <String>[];
    return DeliveryPrewarmResult(
      etaMinutes: _toInt(json['etaMinutes']),
      dropoffLatLng: json['dropoffLatLng'] is Map
          ? DeliveryLatLng.fromJson(
              (json['dropoffLatLng'] as Map).cast<String, dynamic>(),
            )
          : null,
      dropoffAddress: json['dropoffAddress'] is Map
          ? DeliveryAddress.fromJson(
              (json['dropoffAddress'] as Map).cast<String, dynamic>(),
            )
          : null,
      candidateIds: candidates,
    );
  }

  static int _toInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}
