import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class StoreLogo extends StatelessWidget {
  const StoreLogo({
    super.key,
    required this.name,
    required this.logoUrl,
    this.size = 40,
  });

  final String name;
  final String logoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initials = trimmed.isEmpty ? '?' : trimmed[0];
    final fallback = CircleAvatar(
      radius: size / 2,
      backgroundColor: ShadTheme.of(context).colorScheme.muted,
      child: Text(
        initials.toUpperCase(),
        style: ShadTheme.of(context).textTheme.small,
      ),
    );
    if (logoUrl.isEmpty) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 4),
      child: Image.network(
        logoUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}
