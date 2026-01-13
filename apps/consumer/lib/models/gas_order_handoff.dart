import 'package:consumer_core/consumer_core.dart';

class GasOrderHandoff {
  GasOrderHandoff({
    required this.storeId,
    required this.fuel,
    this.currency = '',
  });

  final String storeId;
  final FuelOrderDraft fuel;
  final String currency;

  FuelPaymentFlow get paymentFlow =>
      fuel.paymentFlow == FuelPaymentFlow.preauth.value
          ? FuelPaymentFlow.preauth
          : FuelPaymentFlow.prepay;

  FuelPrepayMode get prepayMode {
    if (fuel.requestedLiters > 0 && fuel.requestedAmountCents <= 0) {
      return FuelPrepayMode.liters;
    }
    return FuelPrepayMode.amount;
  }
}
