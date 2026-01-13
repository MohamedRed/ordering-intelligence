import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../providers/admin_providers.dart';
import '../providers/ingestion_badge_provider.dart';

class AdminNavigationDrawer extends ConsumerWidget {
  const AdminNavigationDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      child: const AdminNavigationSidebar(closeDrawerOnNav: true),
    );
  }
}

/// The navigation content rendered either inside a Drawer (mobile/narrow)
/// or as a persistent sidebar (wide screens).
class AdminNavigationSidebar extends ConsumerWidget {
  const AdminNavigationSidebar({
    super.key,
    this.closeDrawerOnNav = false,
    this.includeTopSafeArea = true,
    this.collapsed = false,
  });

  final bool closeDrawerOnNav;
  final bool includeTopSafeArea;
  final bool collapsed;

  void _maybeCloseDrawer(BuildContext context) {
    if (!closeDrawerOnNav) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(adminAuthProvider);
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: includeTopSafeArea,
        child: Padding(
          padding: EdgeInsets.only(
            top: includeTopSafeArea ? 8 : 0,
            bottom: 8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  includeTopSafeArea ? 12 : 0,
                  12,
                  12,
                ),
                child: ShadCard(
                  padding: const EdgeInsets.all(14),
                  child: collapsed
                      ? const Center(
                          child: CircleAvatar(
                            backgroundColor: Colors.blueGrey,
                            child: Icon(Icons.admin_panel_settings, color: Colors.white),
                          ),
                        )
                      : Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Colors.blueGrey,
                              child: Icon(Icons.admin_panel_settings, color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    auth.isAuthenticated ? 'Platform Operator' : 'Admin Console',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Manage ingestion, alerts, tenants',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              _NavItem(
                icon: Icons.dashboard_outlined,
                label: 'Dashboard',
                collapsed: collapsed,
                onTap: () {
                  _maybeCloseDrawer(context);
                  context.go('/dashboard');
                },
              ),
              _NavItem(
                icon: Icons.notifications_active_outlined,
                label: 'Alerts',
                collapsed: collapsed,
                onTap: () {
                  _maybeCloseDrawer(context);
                  context.go('/alerts');
                },
              ),
              _NavItem(
                icon: Icons.restaurant_menu_outlined,
                label: 'Menu Ingestion',
                trailing: Consumer(builder: (context, ref, _) {
                  final counts = ref.watch(ingestionBadgeProvider);
                  return counts.maybeWhen(
                    data: (c) {
                      final total = c.backlog + c.dlq;
                      if (total == 0) return const SizedBox.shrink();
                      final isDlq = c.dlq > 0;
                      return isDlq
                          ? ShadBadge.destructive(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Text(total.toString()),
                            )
                          : ShadBadge.secondary(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Text(total.toString()),
                            );
                    },
                    orElse: () => const SizedBox.shrink(),
                  );
                }),
                collapsed: collapsed,
                onTap: () {
                  _maybeCloseDrawer(context);
                  context.go('/menu-ingestion');
                },
              ),
              _NavItem(
                icon: Icons.play_circle_outline,
                label: 'Live Demo',
                collapsed: collapsed,
                onTap: () {
                  _maybeCloseDrawer(context);
                  context.go('/demo');
                },
              ),
              _NavItem(
                icon: Icons.chat_bubble_outline,
                label: 'Channels',
                collapsed: collapsed,
                onTap: () {
                  _maybeCloseDrawer(context);
                  context.go('/channels');
                },
              ),
              _NavItem(
                icon: Icons.business_outlined,
                label: 'Tenants',
                collapsed: collapsed,
                onTap: () {
                  _maybeCloseDrawer(context);
                  context.go('/tenants');
                },
              ),
              const Spacer(),
              const Divider(),
              _NavItem(
                icon: Icons.logout,
                label: 'Sign out',
                collapsed: collapsed,
                onTap: () {
                  ref.read(adminAuthProvider).signOut();
                  _maybeCloseDrawer(context);
                  context.go('/login');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.icon,
      required this.label,
      this.trailing,
      this.collapsed = false,
      required this.onTap});
  final IconData icon;
  final String label;
  final Widget? trailing;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = ShadTheme.of(context).colorScheme.primary;
    if (collapsed) {
      return Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Center(child: Icon(icon, color: color)),
          ),
        ),
      );
    }
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
