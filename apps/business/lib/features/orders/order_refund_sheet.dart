import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/order.dart';

class OrderRefundAction {
  const OrderRefundAction({
    required this.amountCents,
    this.reason,
    this.note,
  });

  final int amountCents;
  final String? reason;
  final String? note;
}

Future<OrderRefundAction?> showOrderRefundSheet({
  required BuildContext context,
  required Order order,
}) {
  return showModalBottomSheet<OrderRefundAction>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _OrderRefundSheet(order: order),
  );
}

class _OrderRefundSheet extends StatefulWidget {
  const _OrderRefundSheet({required this.order});
  final Order order;

  @override
  State<_OrderRefundSheet> createState() => _OrderRefundSheetState();
}

class _OrderRefundSheetState extends State<_OrderRefundSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _fullRefund = true;
  String _reason = 'requested_by_customer';
  String? _amountError;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 16 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Issue refund', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Total: ${widget.order.formattedTotal}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Full refund'),
            value: _fullRefund,
            onChanged: (value) => setState(() {
              _fullRefund = value;
              _amountError = null;
            }),
          ),
          if (!_fullRefund) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount',
                hintText: 'e.g. 12.50',
                errorText: _amountError,
              ),
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _reason,
            decoration: const InputDecoration(labelText: 'Reason'),
            items: const [
              DropdownMenuItem(
                value: 'requested_by_customer',
                child: Text('Requested by customer'),
              ),
              DropdownMenuItem(
                value: 'duplicate',
                child: Text('Duplicate'),
              ),
              DropdownMenuItem(
                value: 'fraudulent',
                child: Text('Fraudulent'),
              ),
              DropdownMenuItem(
                value: 'other',
                child: Text('Other'),
              ),
            ],
            onChanged: (value) => setState(() {
              _reason = value ?? 'requested_by_customer';
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
            ),
          ),
          const SizedBox(height: 16),
          ShadButton(
            onPressed: _confirm,
            child: const Text('Confirm refund'),
          ),
          const SizedBox(height: 8),
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _confirm() {
    final amount = _fullRefund
        ? widget.order.totalCents
        : _parseAmountCents(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() {
        _amountError = 'Enter a valid amount';
      });
      return;
    }
    if (amount > widget.order.totalCents) {
      setState(() {
        _amountError = 'Amount exceeds order total';
      });
      return;
    }
    final reason = _reason == 'other' ? null : _reason;
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();
    Navigator.of(context).pop(OrderRefundAction(
      amountCents: amount,
      reason: reason,
      note: note,
    ));
  }

  int? _parseAmountCents(String value) {
    if (value.isEmpty) return null;
    final normalized = value.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
    final amount = double.tryParse(normalized);
    if (amount == null || amount <= 0) return null;
    return (amount * 100).round();
  }
}
