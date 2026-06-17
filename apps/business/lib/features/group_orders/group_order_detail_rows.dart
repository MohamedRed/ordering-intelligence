import 'package:flutter/material.dart';

class GroupOrderDetailValueRow extends StatelessWidget {
  const GroupOrderDetailValueRow({
    super.key,
    required this.label,
    required this.value,
    this.labelStyle,
    this.valueStyle,
    this.verticalPadding = 4,
  });

  final String label;
  final String value;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final valueText = value.trim();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: valueText.isEmpty ? 1 : 2,
            child: Text(
              label,
              style: labelStyle,
              softWrap: true,
            ),
          ),
          if (valueText.isNotEmpty) ...[
            const SizedBox(width: 12),
            Flexible(
              flex: 3,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  value,
                  style: valueStyle,
                  textAlign: TextAlign.right,
                  softWrap: true,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
