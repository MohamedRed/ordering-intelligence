class DeliveryLatLng {
  final double lat;
  final double lng;

  const DeliveryLatLng({required this.lat, required this.lng});

  factory DeliveryLatLng.fromJson(Map<String, dynamic> json) {
    return DeliveryLatLng(
      lat: (json['lat'] is num) ? (json['lat'] as num).toDouble() : 0,
      lng: (json['lng'] is num) ? (json['lng'] as num).toDouble() : 0,
    );
  }
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
    required this.line1,
    required this.line2,
    required this.city,
    required this.state,
    required this.postalCode,
    required this.country,
    required this.formatted,
  });

  factory DeliveryAddress.fromJson(Map<String, dynamic> json) {
    return DeliveryAddress(
      line1: (json['line1'] as String?)?.trim() ?? '',
      line2: (json['line2'] as String?)?.trim() ?? '',
      city: (json['city'] as String?)?.trim() ?? '',
      state: (json['state'] as String?)?.trim() ?? '',
      postalCode: (json['postalCode'] as String?)?.trim() ?? '',
      country: (json['country'] as String?)?.trim() ?? '',
      formatted: (json['formatted'] as String?)?.trim() ?? '',
    );
  }

  String display() {
    if (formatted.isNotEmpty) return formatted;
    final parts = [
      line1,
      line2,
      city,
      state,
      postalCode,
      country,
    ].where((p) => p.trim().isNotEmpty).toList();
    return parts.join(', ');
  }
}

class DeliveryQuote {
  final String provider;
  final int providerFeeCents;
  final int dropoffEtaMinutes;
  final String currency;
  final DateTime? quoteExpiresAt;

  const DeliveryQuote({
    required this.provider,
    required this.providerFeeCents,
    required this.dropoffEtaMinutes,
    required this.currency,
    required this.quoteExpiresAt,
  });

  factory DeliveryQuote.fromJson(Map<String, dynamic> json) {
    final expiresRaw = json['quoteExpiresAt'];
    DateTime? expires;
    if (expiresRaw is String) {
      expires = DateTime.tryParse(expiresRaw);
    }
    return DeliveryQuote(
      provider: (json['provider'] as String?)?.trim() ?? '',
      providerFeeCents: (json['providerFeeCents'] is num)
          ? (json['providerFeeCents'] as num).toInt()
          : 0,
      dropoffEtaMinutes: (json['dropoffEtaMinutes'] is num)
          ? (json['dropoffEtaMinutes'] as num).toInt()
          : 0,
      currency: (json['currency'] as String?)?.trim() ?? '',
      quoteExpiresAt: expires,
    );
  }
}
