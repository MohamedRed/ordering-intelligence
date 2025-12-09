import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/app_providers.dart';

class BusinessDrawer extends ConsumerWidget {
  const BusinessDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider);
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Colors.deepOrange),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                auth.userName != null
                    ? 'Logged in as\n${auth.userName}'
                    : 'Ordering Intelligence',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_outlined),
            title: const Text('Orders'),
            onTap: () {
              Navigator.of(context).pop();
              context.go('/orders');
            },
          ),
          ListTile(
            leading: const Icon(Icons.restaurant_menu),
            title: const Text('Menu'),
            onTap: () {
              Navigator.of(context).pop();
              context.go('/menu');
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () {
              ref.read(authNotifierProvider).signOut();
              Navigator.of(context).pop();
              context.go('/sign-in');
            },
          ),
        ],
      ),
    );
  }
}
