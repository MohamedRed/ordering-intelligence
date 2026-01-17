class DeliveryPartnerComplianceDocument {
  DeliveryPartnerComplianceDocument({
    required this.status,
    required this.url,
    required this.key,
    required this.bucket,
    required this.uploadedAt,
  });

  final String status;
  final String url;
  final String key;
  final String bucket;
  final DateTime? uploadedAt;

  factory DeliveryPartnerComplianceDocument.fromJson(Map<String, dynamic> json) {
    return DeliveryPartnerComplianceDocument(
      status: (json['status'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      key: (json['key'] ?? '').toString(),
      bucket: (json['bucket'] ?? '').toString(),
      uploadedAt: _parseTimestamp(json['uploaded_at']),
    );
  }

  bool get isUploaded => status.isNotEmpty && status != 'rejected';

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is Map && value['seconds'] is int) {
      final seconds = value['seconds'] as int;
      final nanos = value['nanoseconds'] as int? ?? 0;
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000 + nanos ~/ 1000000, isUtc: true);
    }
    return null;
  }
}

class DeliveryPartnerCompliance {
  DeliveryPartnerCompliance({
    required this.status,
    required this.country,
    required this.vehicleType,
    required this.requiredDocs,
    required this.optionalDocs,
    required this.documents,
    required this.missingDocs,
    required this.updatedAt,
  });

  final String status;
  final String country;
  final String vehicleType;
  final List<String> requiredDocs;
  final List<String> optionalDocs;
  final Map<String, DeliveryPartnerComplianceDocument> documents;
  final List<String> missingDocs;
  final DateTime? updatedAt;

  factory DeliveryPartnerCompliance.fromJson(Map<String, dynamic> json) {
    final docsRaw =
        (json['documents'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final documents = <String, DeliveryPartnerComplianceDocument>{};
    for (final entry in docsRaw.entries) {
      final value = entry.value;
      if (value is Map) {
        documents[entry.key] =
            DeliveryPartnerComplianceDocument.fromJson(value.cast<String, dynamic>());
      }
    }

    return DeliveryPartnerCompliance(
      status: (json['status'] ?? '').toString(),
      country: (json['country'] ?? '').toString(),
      vehicleType: (json['vehicle_type'] ?? '').toString(),
      requiredDocs: _stringList(json['required_docs']),
      optionalDocs: _stringList(json['optional_docs']),
      documents: documents,
      missingDocs: _stringList(json['missing_docs']),
      updatedAt: DeliveryPartnerComplianceDocument._parseTimestamp(json['updated_at']),
    );
  }

  bool get isApproved => status == 'approved';

  List<String> missingRequiredDocs() {
    if (missingDocs.isNotEmpty) return missingDocs;
    final out = <String>[];
    for (final doc in requiredDocs) {
      final entry = documents[doc];
      if (entry == null || !entry.isUploaded) out.add(doc);
    }
    return out;
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList();
    }
    return const [];
  }
}
