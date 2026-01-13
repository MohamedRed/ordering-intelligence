import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class MenuHeader extends StatelessWidget {
  const MenuHeader({
    super.key,
    required this.storeName,
    required this.onChangeStore,
  });

  final String storeName;
  final VoidCallback onChangeStore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(storeName, style: ShadTheme.of(context).textTheme.h2),
            ],
          ),
        ),
        ShadButton.outline(
          onPressed: onChangeStore,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront, size: 16),
              SizedBox(width: 6),
              Text('Change store'),
            ],
          ),
        ),
      ],
    );
  }
}
