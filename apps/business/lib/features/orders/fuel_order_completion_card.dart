import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/order.dart';
import '../../providers/order_api.dart';
import '../../providers/order_detail_provider.dart';
import '../../providers/order_providers.dart';
import '../../widgets/shad_snackbar.dart';
import 'fuel_order_completion_form.dart';
class FuelOrderCompletionCard extends ConsumerStatefulWidget {
  const FuelOrderCompletionCard({super.key, required this.order});
  final Order order;
  @override
  ConsumerState<FuelOrderCompletionCard> createState() =>
      _FuelOrderCompletionCardState();
}
class _FuelOrderCompletionCardState
    extends ConsumerState<FuelOrderCompletionCard> {
  final _litersController = TextEditingController();
  final _amountController = TextEditingController();
  bool _submitting = false;
  String? _error;
  @override
  void dispose() {
    _litersController.dispose();
    _amountController.dispose();
    super.dispose();
  }
  bool get _canComplete =>
      widget.order.status == OrderStatus.confirmed ||
      widget.order.status == OrderStatus.ready;
  @override
  Widget build(BuildContext context) {
    if (!_canComplete) {
      return Text(
        'Fuel order is ${orderStatusToString(widget.order.status)}.',
        style: const TextStyle(color: Colors.grey),
      );
    }
    return FuelOrderCompletionForm(
      litersController: _litersController,
      amountController: _amountController,
      isSubmitting: _submitting,
      errorMessage: _error,
      onSubmit: () => _submit(context),
    );
  }
  Future<void> _submit(BuildContext context) async {
    final liters = _parseDouble(_litersController.text);
    final amountCents = _parseCents(_amountController.text);
    if (liters <= 0 && amountCents <= 0) {
      setState(() => _error = 'Enter liters or final amount.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final repo = ref.read(orderRepositoryProvider);
      await repo.completeFuelOrder(
        widget.order.id,
        finalLiters: liters,
        finalAmountCents: amountCents,
      );
      ref
        ..invalidate(orderDetailProvider(widget.order.id))
        ..invalidate(ordersProvider);
      if (context.mounted) {
        showShadSnack(
          context,
          title: 'Fuel order completed',
          message: 'Order ${widget.order.id} captured successfully.',
          type: ShadSnackType.success,
        );
      }
    } catch (err) {
      if (context.mounted) {
        showShadSnack(
          context,
          title: 'Capture failed',
          message: '$err',
          type: ShadSnackType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
  double _parseDouble(String value) =>
      double.tryParse(value.replaceAll(',', '.')) ?? 0;
  int _parseCents(String value) =>
      ((_parseDouble(value)) * 100).round();
}
