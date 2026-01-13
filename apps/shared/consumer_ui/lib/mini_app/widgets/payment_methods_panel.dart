import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'toggle_option_row.dart';
import 'package:consumer_core/consumer_core.dart';

class PaymentMethodsPanel extends StatelessWidget {
  const PaymentMethodsPanel({
    super.key,
    required this.defaultMethod,
    required this.methodCount,
    required this.oneTapEnabled,
    required this.onToggleOneTap,
    required this.onManage,
    this.loading = false,
    this.error,
  });

  final PaymentMethodSummary? defaultMethod;
  final int methodCount;
  final bool oneTapEnabled;
  final ValueChanged<bool> onToggleOneTap;
  final VoidCallback onManage;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final label = defaultMethod?.maskedLabel ?? 'No saved card';
    final expiry = defaultMethod?.expiryLabel ?? '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Payment methods', style: theme.textTheme.small),
              ),
              ShadButton.outline(
                onPressed: loading ? null : onManage,
                child: Text(methodCount == 0 ? 'Add card' : 'Manage'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(label, style: theme.textTheme.small),
          if (expiry.isNotEmpty)
            Text('Exp $expiry', style: theme.textTheme.muted),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error!,
                style: theme.textTheme.muted.copyWith(color: theme.colorScheme.destructive),
              ),
            ),
          if (defaultMethod != null) ...[
            const SizedBox(height: 8),
            ToggleOptionRow(
              title: 'One‑tap pay',
              value: oneTapEnabled,
              onChanged: onToggleOneTap,
              offLabel: 'Pay with the phone when needed',
              onLabel: 'Use saved card for faster checkout',
            ),
          ],
        ],
      ),
    );
  }
}
