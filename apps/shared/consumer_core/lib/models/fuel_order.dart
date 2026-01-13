const String fuelUnitLiter = 'liter';
const String fuelCurrency = 'eur';

enum FuelPaymentFlow { prepay, preauth }

enum FuelPrepayMode { amount, liters }

extension FuelPaymentFlowValue on FuelPaymentFlow {
  String get value => this == FuelPaymentFlow.preauth ? 'preauth' : 'prepay';
  String get label => this == FuelPaymentFlow.preauth ? 'Pre-auth' : 'Prepay';
}

extension FuelPrepayModeValue on FuelPrepayMode {
  String get label => this == FuelPrepayMode.liters ? 'By liters' : 'By amount';
}

class FuelOrderDraft {
  final String fuelGradeId;
  final String fuelGradeName;
  final int unitPriceCents;
  final String unit;
  final double requestedLiters;
  final int requestedAmountCents;
  final int preauthAmountCents;
  final String paymentFlow;
  final String pumpNumber;

  const FuelOrderDraft({
    required this.fuelGradeId,
    required this.fuelGradeName,
    required this.unitPriceCents,
    required this.unit,
    required this.requestedLiters,
    required this.requestedAmountCents,
    required this.preauthAmountCents,
    required this.paymentFlow,
    required this.pumpNumber,
  });

  factory FuelOrderDraft.fromJson(Map<String, dynamic> json) {
    return FuelOrderDraft(
      fuelGradeId: (json['fuelGradeId'] ?? '').toString(),
      fuelGradeName: (json['fuelGradeName'] ?? '').toString(),
      unitPriceCents: _toInt(json['unitPriceCents']),
      unit: (json['unit'] ?? fuelUnitLiter).toString(),
      requestedLiters: _toDouble(json['requestedLiters']),
      requestedAmountCents: _toInt(json['requestedAmountCents']),
      preauthAmountCents: _toInt(json['preauthAmountCents']),
      paymentFlow: (json['paymentFlow'] ?? FuelPaymentFlow.prepay.value).toString(),
      pumpNumber: (json['pumpNumber'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'fuelGradeId': fuelGradeId,
        'fuelGradeName': fuelGradeName,
        'unitPriceCents': unitPriceCents,
        'unit': unit,
        'requestedLiters': requestedLiters,
        'requestedAmountCents': requestedAmountCents,
        'preauthAmountCents': preauthAmountCents,
        'paymentFlow': paymentFlow,
        'pumpNumber': pumpNumber,
      };

  static int _toInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

  static double _toDouble(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0.0;
}
