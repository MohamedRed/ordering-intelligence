class FuelOrder {
  final String fuelGradeId;
  final String fuelGradeName;
  final String unit;
  final int unitPriceCents;
  final double requestedLiters;
  final int requestedAmountCents;
  final int preauthAmountCents;
  final String paymentFlow;
  final String pumpNumber;
  final double finalLiters;
  final int finalAmountCents;

  const FuelOrder({
    required this.fuelGradeId,
    required this.fuelGradeName,
    required this.unit,
    required this.unitPriceCents,
    required this.requestedLiters,
    required this.requestedAmountCents,
    required this.preauthAmountCents,
    required this.paymentFlow,
    required this.pumpNumber,
    required this.finalLiters,
    required this.finalAmountCents,
  });

  factory FuelOrder.fromJson(Map<String, dynamic> json) {
    return FuelOrder(
      fuelGradeId: (json['fuelGradeId'] as String?)?.trim() ?? '',
      fuelGradeName: (json['fuelGradeName'] as String?)?.trim() ?? '',
      unit: (json['unit'] as String?)?.trim() ?? '',
      unitPriceCents: _toInt(json['unitPriceCents']),
      requestedLiters: _toDouble(json['requestedLiters']),
      requestedAmountCents: _toInt(json['requestedAmountCents']),
      preauthAmountCents: _toInt(json['preauthAmountCents']),
      paymentFlow: (json['paymentFlow'] as String?)?.trim() ?? '',
      pumpNumber: (json['pumpNumber'] as String?)?.trim() ?? '',
      finalLiters: _toDouble(json['finalLiters']),
      finalAmountCents: _toInt(json['finalAmountCents']),
    );
  }

  bool get isPreauth => paymentFlow == 'preauth';
  bool get isPrepay => paymentFlow == 'prepay';

  static int _toInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static double _toDouble(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
}
