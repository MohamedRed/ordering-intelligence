import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/admin_providers.dart';
import '../providers/ingestion_badge_provider.dart';

class AdminNavigationDrawer extends ConsumerWidget {
  const AdminNavigationDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(adminAuthProvider);
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Colors.blueGrey),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                auth.isAuthenticated ? 'Platform Operator' : 'Admin Console',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_outlined),
            title: const Text('Dashboard'),
            onTap: () {
              Navigator.of(context).pop();
              context.go('/dashboard');
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Alerts'),
            onTap: () {
              Navigator.of(context).pop();
              context.go('/alerts');
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('Onboard Store'),
            onTap: () {
              Navigator.of(context).pop();
              context.go('/onboarding');
            },
          ),
          ListTile(
            leading: const Icon(Icons.restaurant_menu_outlined),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Menu Ingestion'),
                Consumer(builder: (context, ref, _) {
                  final counts = ref.watch(ingestionBadgeProvider);
                  return counts.maybeWhen(
                    data: (c) {
                      final total = c.backlog + c.dlq;
                      if (total == 0) return const SizedBox.shrink();
                      return Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.dlq > 0 ? Colors.red.shade100 : Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          total.toString(),
                          style: TextStyle(
                            color: c.dlq > 0 ? Colors.red.shade800 : Colors.orange.shade800,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  );
                }),
              ],
            ),
            onTap: () {
              Navigator.of(context).pop();
              context.go('/menu-ingestion');
            },
          ),
          ListTile(
            leading: const Icon(Icons.business_outlined),
            title: const Text('Tenants'),
            onTap: () {
              Navigator.of(context).pop();
              context.go('/tenants');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () {
              ref.read(adminAuthProvider).signOut();
              Navigator.of(context).pop();
              context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}
