import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/group_order.dart';

class GroupOrderRefundAction {
  const GroupOrderRefundAction({
    required this.participantId,
    required this.amountCents,
    this.reason,
    this.note,
  });

  final String participantId;
  final int amountCents;
  final String? reason;
  final String? note;
}

Future<GroupOrderRefundAction?> showGroupOrderRefundSheet({
  required BuildContext context,
  required GroupOrder groupOrder,
}) {
  return showModalBottomSheet<GroupOrderRefundAction>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _GroupOrderRefundSheet(groupOrder: groupOrder),
  );
}

class _ParticipantOption {
  const _ParticipantOption({
    required this.id,
    required this.label,
    required this.maxRefundCents,
  });

  final String id;
  final String label;
  final int maxRefundCents;
}

class _GroupOrderRefundSheet extends StatefulWidget {
  const _GroupOrderRefundSheet({required this.groupOrder});
  final GroupOrder groupOrder;

  @override
  State<_GroupOrderRefundSheet> createState() => _GroupOrderRefundSheetState();
}

class _GroupOrderRefundSheetState extends State<_GroupOrderRefundSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  bool _fullRefund = true;
  String _reason = 'requested_by_customer';
  String? _amountError;
  String? _participantError;
  late final List<_ParticipantOption> _participants;
  String? _selectedParticipantId;

  @override
  void initState() {
    super.initState();
    _participants = _buildParticipants();
    _selectedParticipantId =
        _participants.isNotEmpty ? _participants.first.id : null;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<_ParticipantOption> _buildParticipants() {
    final order = widget.groupOrder;
    final allocations = order.pricing?.allocations ?? [];
    if (allocations.isNotEmpty) {
      return allocations
          .map((allocation) => _ParticipantOption(
                id: allocation.participantId,
                label: order.participantLabel(allocation.participantId),
                maxRefundCents: allocation.totalCents > 0
                    ? allocation.totalCents
                    : order.totalCents,
              ))
          .toList();
    }
    return order.participants
        .map((participant) => _ParticipantOption(
              id: participant.participantId,
              label: participant.label,
              maxRefundCents: order.totalCents,
            ))
        .toList();
  }

  int get _maxRefundCents {
    final selected = _selectedParticipantId;
    if (selected == null) return widget.groupOrder.totalCents;
    final option = _participants.firstWhere(
      (p) => p.id == selected,
      orElse: () => _ParticipantOption(
        id: selected,
        label: selected,
        maxRefundCents: widget.groupOrder.totalCents,
      ),
    );
    return option.maxRefundCents;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxLabel = _formatCents(_maxRefundCents);
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
          Text('Issue group order refund',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Max refundable for selection: $maxLabel',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          if (_participants.isEmpty) ...[
            ShadAlert.destructive(
              title: const Text('No participants found'),
              description: const Text(
                  'Cannot issue a refund without a participant reference.'),
            ),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedParticipantId,
              decoration: InputDecoration(
                labelText: 'Refund participant',
                errorText: _participantError,
              ),
              items: _participants
                  .map((option) => DropdownMenuItem(
                        value: option.id,
                        child: Text(option.label),
                      ))
                  .toList(),
              onChanged: (value) => setState(() {
                _selectedParticipantId = value;
                _amountError = null;
                _participantError = null;
              }),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Full refund for participant'),
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
              initialValue: _reason,
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
          ],
          const SizedBox(height: 16),
          ShadButton(
            onPressed: _participants.isEmpty ? null : _confirm,
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
    final participantId = _selectedParticipantId;
    if (participantId == null || participantId.trim().isEmpty) {
      setState(() {
        _participantError = 'Select a participant';
      });
      return;
    }
    final maxCents = _maxRefundCents;
    final amount = _fullRefund
        ? maxCents
        : _parseAmountCents(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() {
        _amountError = 'Enter a valid amount';
      });
      return;
    }
    if (amount > maxCents) {
      setState(() {
        _amountError = 'Amount exceeds max refundable';
      });
      return;
    }
    final reason = _reason == 'other' ? null : _reason;
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();
    Navigator.of(context).pop(GroupOrderRefundAction(
      participantId: participantId,
      amountCents: amount,
      reason: reason,
      note: note,
    ));
  }

  int? _parseAmountCents(String value) {
    if (value.isEmpty) return null;
    final normalized =
        value.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), '');
    final amount = double.tryParse(normalized);
    if (amount == null || amount <= 0) return null;
    return (amount * 100).round();
  }

  String _formatCents(int cents) {
    if (cents <= 0) return '—';
    final value = (cents / 100).toStringAsFixed(2);
    return '\$$value';
  }
}
