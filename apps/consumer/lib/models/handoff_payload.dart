import 'gas_order_handoff.dart';
import 'order_payment_handoff.dart';
import 'reorder_handoff.dart';

enum HandoffKind { fuelOrder, reorder, orderPayment }

class HandoffPayload {
  const HandoffPayload._({
    required this.kind,
    this.fuel,
    this.reorder,
    this.orderPayment,
  });

  final HandoffKind kind;
  final GasOrderHandoff? fuel;
  final ReorderHandoff? reorder;
  final OrderPaymentHandoff? orderPayment;

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
}
