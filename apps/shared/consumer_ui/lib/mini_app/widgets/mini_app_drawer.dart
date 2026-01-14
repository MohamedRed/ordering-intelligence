import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class MiniAppDrawer extends StatelessWidget {
  const MiniAppDrawer({
    super.key,
    required this.signOutLabel,
    required this.onSignOut,
    this.signingOut = false,
    this.displayName,
    this.subtitle,
  });

  final String signOutLabel;
  final VoidCallback onSignOut;
  final bool signingOut;
  final String? displayName;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName?.trim().isNotEmpty == true
                        ? displayName!
                        : 'Menu',
                    style: theme.textTheme.h3,
                  ),
                  if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: theme.textTheme.muted),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(signOutLabel),
              trailing: signingOut
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: signingOut
                  ? null
                  : () {
                      Navigator.of(context).maybePop();
                      onSignOut();
                    },
            ),
          ],
        ),
      ),
    );
  }
}
