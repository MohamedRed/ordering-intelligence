import 'package:consumer_core/consumer_core.dart';

class OrderPaymentHandoff {
  const OrderPaymentHandoff({
    required this.orderId,
    required this.intent,
  });

  final String orderId;
  final PaymentIntentInfo intent;
}
