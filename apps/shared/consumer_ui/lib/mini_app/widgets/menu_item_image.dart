import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class MenuItemImage extends StatelessWidget {
  const MenuItemImage({super.key, required this.url, this.size = 64});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ShadTheme.of(context).colorScheme.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.fastfood, size: size * 0.45),
    );
    if (url.isEmpty) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}
