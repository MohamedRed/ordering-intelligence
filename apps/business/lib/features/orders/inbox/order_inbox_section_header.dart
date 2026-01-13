import 'package:flutter/material.dart';

class OrderInboxSectionHeader extends StatelessWidget {
  const OrderInboxSectionHeader({
    super.key,
    required this.title,
    this.count,
  });

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final label =
        count == null ? title : '$title (${count!.toString()})';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
