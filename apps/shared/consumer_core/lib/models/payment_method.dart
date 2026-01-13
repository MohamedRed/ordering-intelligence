class PaymentMethodSummary {
  const PaymentMethodSummary({
    required this.id,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
    this.isDefault = false,
  });

  final String id;
  final String brand;
  final String last4;
  final int expMonth;
  final int expYear;
  final bool isDefault;

  factory PaymentMethodSummary.fromJson(Map<String, dynamic> json) {
    return PaymentMethodSummary(
      id: (json['id'] ?? '').toString(),
      brand: (json['brand'] ?? '').toString(),
      last4: (json['last4'] ?? '').toString(),
      expMonth: (json['expMonth'] ?? json['exp_month'] ?? 0) is num
          ? (json['expMonth'] ?? json['exp_month'] ?? 0).toInt()
          : int.tryParse((json['expMonth'] ?? json['exp_month'] ?? '').toString()) ?? 0,
      expYear: (json['expYear'] ?? json['exp_year'] ?? 0) is num
          ? (json['expYear'] ?? json['exp_year'] ?? 0).toInt()
          : int.tryParse((json['expYear'] ?? json['exp_year'] ?? '').toString()) ?? 0,
      isDefault: json['isDefault'] == true ||
          json['is_default'] == true ||
          (json['isDefault'] ?? '').toString().toLowerCase() == 'true',
    );
  }

  String get maskedLabel {
    final brandLabel = brand.isEmpty ? 'Card' : brand[0].toUpperCase() + brand.substring(1);
    if (last4.isEmpty) return brandLabel;
    return '$brandLabel •••• $last4';
  }

  String get expiryLabel {
    if (expMonth <= 0 || expYear <= 0) return '';
    final month = expMonth.toString().padLeft(2, '0');
    final year = expYear.toString().padLeft(2, '0');
    return '$month/$year';
  }
}
