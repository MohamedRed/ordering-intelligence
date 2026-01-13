import 'gas_order_handoff.dart';
import 'order_payment_handoff.dart';
import 'reorder_handoff.dart';
import 'tv_pairing_handoff.dart';

enum HandoffKind { fuelOrder, reorder, orderPayment, tvPairing }

class HandoffPayload {
  const HandoffPayload._({
    required this.kind,
    this.fuel,
    this.reorder,
    this.orderPayment,
    this.tvPairing,
  });

  final HandoffKind kind;
  final GasOrderHandoff? fuel;
  final ReorderHandoff? reorder;
  final OrderPaymentHandoff? orderPayment;
  final TvPairingHandoff? tvPairing;

  factory HandoffPayload.fuel(GasOrderHandoff handoff) {
    return HandoffPayload._(kind: HandoffKind.fuelOrder, fuel: handoff);
  }

  factory HandoffPayload.reorder(ReorderHandoff handoff) {
    return HandoffPayload._(kind: HandoffKind.reorder, reorder: handoff);
  }

  factory HandoffPayload.orderPayment(OrderPaymentHandoff handoff) {
    return HandoffPayload._(
      kind: HandoffKind.orderPayment,
      orderPayment: handoff,
    );
  }

  factory HandoffPayload.tvPairing(TvPairingHandoff handoff) {
    return HandoffPayload._(
      kind: HandoffKind.tvPairing,
      tvPairing: handoff,
    );
  }
}
