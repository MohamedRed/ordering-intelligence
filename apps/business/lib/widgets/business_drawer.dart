import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../providers/app_providers.dart';

class BusinessDrawer extends ConsumerWidget {
  const BusinessDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Drawer(
      child: BusinessNavigationSidebar(closeDrawerOnNav: true),
    );
  }
}

/// The navigation content rendered either inside a Drawer (mobile/narrow)
/// or as a persistent sidebar (wide screens).
class BusinessNavigationSidebar extends ConsumerWidget {
  const BusinessNavigationSidebar({
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
    final auth = ref.watch(authNotifierProvider);
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
                            backgroundColor: Colors.deepOrange,
                            child: Icon(Icons.storefront, color: Colors.white),
                          ),
                        )
                      : Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Colors.deepOrange,
                              child: Icon(Icons.storefront, color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    auth.userName ?? 'Ordering Intelligence',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600, fontSize: 16),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    auth.userName != null
                                        ? 'Logged in'
                                        : 'Staff portal',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              _DrawerItem(
                icon: Icons.receipt_outlined,
                label: 'Orders',
                collapsed: collapsed,
                onTap: () {
                  _maybeCloseDrawer(context);
                  context.go('/orders');
                },
              ),
              _DrawerItem(
                icon: Icons.local_shipping_outlined,
                label: 'Deliveries',
                collapsed: collapsed,
                onTap: () {
                  _maybeCloseDrawer(context);
                  context.go('/deliveries');
                },
              ),
              _DrawerItem(
                icon: Icons.restaurant_menu,
                label: 'Menu',
                collapsed: collapsed,
                onTap: () {
                  _maybeCloseDrawer(context);
                  context.go('/menu');
                },
              ),
              _DrawerItem(
                icon: Icons.record_voice_over_outlined,
                label: 'Agent voice',
                collapsed: collapsed,
                onTap: () {
                  _maybeCloseDrawer(context);
                  context.go('/voice');
                },
              ),
              _DrawerItem(
                icon: Icons.chat_bubble_outline,
                label: 'Channels',
                collapsed: collapsed,
                onTap: () {
                  _maybeCloseDrawer(context);
                  context.go('/channels');
                },
              ),
              _DrawerItem(
                icon: Icons.query_stats,
                label: 'Wait time',
                collapsed: collapsed,
                onTap: () {
                  _maybeCloseDrawer(context);
                  context.go('/wait-time');
                },
              ),
              _DrawerItem(
                icon: Icons.local_shipping_outlined,
                label: 'Delivery & dispatch',
                collapsed: collapsed,
                onTap: () {
                  _maybeCloseDrawer(context);
                  context.go('/dispatch');
                },
              ),
              _DrawerItem(
                icon: Icons.settings_outlined,
                label: 'Store settings',
                collapsed: collapsed,
                onTap: () {
                  _maybeCloseDrawer(context);
                  context.go('/settings');
                },
              ),
              const Spacer(),
              const Divider(),
              _DrawerItem(
                icon: Icons.logout,
                label: 'Sign out',
                collapsed: collapsed,
                onTap: () {
                  ref.read(authNotifierProvider).signOut();
                  _maybeCloseDrawer(context);
                  context.go('/sign-in');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem(
      {required this.icon,
      required this.label,
      this.collapsed = false,
      required this.onTap});
  final IconData icon;
  final String label;
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
      onTap: onTap,
    );
  }
}
