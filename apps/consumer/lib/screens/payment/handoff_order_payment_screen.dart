import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';

import '../../adapters/mobile_payments_adapter.dart';
import '../../models/order_payment_handoff.dart';

class HandoffOrderPaymentScreen extends StatefulWidget {
  const HandoffOrderPaymentScreen({
    super.key,
    required this.api,
    required this.handoff,
  });

  final ChannelGatewayApi api;
  final OrderPaymentHandoff handoff;

  @override
  State<HandoffOrderPaymentScreen> createState() =>
      _HandoffOrderPaymentScreenState();
}

class _HandoffOrderPaymentScreenState extends State<HandoffOrderPaymentScreen> {
  late final MobilePaymentsAdapter _payments;
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _payments = MobilePaymentsAdapter(api: widget.api);
    WidgetsBinding.instance.addPostFrameCallback((_) => _confirmPayment());
  }

  Future<void> _confirmPayment() async {
    if (_processing) return;
    final intent = widget.handoff.intent;
    if (intent.clientSecret.isEmpty) {
      setState(() => _error = 'Missing payment details.');
      return;
    }
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      await _payments.confirmPaymentIntent(intent);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment complete.')),
      );
      Navigator.of(context).pop();
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = err.toString());
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  String? _amountLabel(PaymentIntentInfo intent) {
    if (intent.amountCents <= 0) return null;
    final amount = (intent.amountCents / 100).toStringAsFixed(2);
    final currency = intent.currency.toUpperCase();
    if (currency.isEmpty) {
      return '\$$amount';
    }
    return '$currency $amount';
  }

  @override
  Widget build(BuildContext context) {
    final intent = widget.handoff.intent;
    final amountLabel = _amountLabel(intent);
    return Scaffold(
      appBar: AppBar(title: const Text('Complete payment')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order ${widget.handoff.orderId}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              amountLabel == null
                  ? 'Finish payment to place this order.'
                  : 'Amount due: $amountLabel',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _processing ? null : _confirmPayment,
                child: Text(_processing ? 'Processing...' : 'Pay now'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed:
                    _processing ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
