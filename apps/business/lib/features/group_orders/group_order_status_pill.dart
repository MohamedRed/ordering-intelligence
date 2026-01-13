import 'package:flutter/material.dart';

class GroupOrderStatusPill extends StatelessWidget {
  const GroupOrderStatusPill({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(_statusLabel(status), style: TextStyle(color: color)),
    );
  }
}

String _statusLabel(String raw) {
  final status = raw.trim().toLowerCase();
  switch (status) {
    case 'open':
      return 'Open';
    case 'locked':
      return 'Locked';
    case 'payment_pending':
      return 'Payment pending';
    case 'paid':
      return 'Paid';
    case 'submitted':
      return 'Submitted';
    case 'cancelled':
      return 'Cancelled';
    case 'expired':
      return 'Expired';
    default:
      return status.isEmpty ? 'Unknown' : status.replaceAll('_', ' ');
  }
}

Color _statusColor(String raw) {
  final status = raw.trim().toLowerCase();
  switch (status) {
    case 'open':
      return Colors.blue;
    case 'locked':
      return Colors.orange;
    case 'payment_pending':
      return Colors.amber;
    case 'paid':
      return Colors.green;
    case 'submitted':
      return Colors.deepPurple;
    case 'cancelled':
      return Colors.red;
    case 'expired':
      return Colors.grey;
    default:
      return Colors.blueGrey;
  }
}
