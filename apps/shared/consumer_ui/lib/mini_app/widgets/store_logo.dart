import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class StoreLogo extends StatelessWidget {
  const StoreLogo({super.key, required this.name, required this.logoUrl});

  final String name;
  final String logoUrl;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initials = trimmed.isEmpty ? '?' : trimmed[0];
    final fallback = CircleAvatar(
      radius: 20,
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
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        logoUrl,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}
