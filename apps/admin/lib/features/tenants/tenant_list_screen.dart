import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/tenant_providers.dart';
import '../../widgets/admin_navigation_drawer.dart';

class TenantListScreen extends ConsumerWidget {
  const TenantListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantsAsync = ref.watch(tenantsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tenants')),
      drawer: const AdminNavigationDrawer(),
      body: tenantsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load tenants: $err')),
        data: (tenants) {
          if (tenants.isEmpty) {
            return const Center(child: Text('No tenants yet'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(tenantsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: tenants.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final tenant = tenants[index];
                return Card(
                  child: ExpansionTile(
                    title: Text(tenant.name),
                    subtitle: Text(
                        'Owner: ${tenant.primaryUser} • Status: ${tenant.status}'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Wrap(
                          spacing: 8,
                          children: tenant.featureFlags.entries
                              .map((e) => Chip(
                                    label: Text(
                                        '${e.key}: ${e.value ? 'on' : 'off'}'),
                                  ))
                              .toList(),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _editFlags(
                              context, ref, tenant.id, tenant.featureFlags),
                          icon: const Icon(Icons.toggle_on_outlined),
                          label: const Text('Edit flags'),
                        ),
                      )
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _editFlags(BuildContext context, WidgetRef ref, String tenantId,
      Map<String, bool> flags) async {
    final controller = TextEditingController(
        text: flags.entries.map((e) => '${e.key}=${e.value}').join('\n'));
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Feature flags (key=true/false per line)'),
          content: SizedBox(
            width: 400,
            child: TextField(
              controller: controller,
              maxLines: 6,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Save')),
          ],
        );
      },
    );
    if (result != true) return;

    final parsed = <String, bool>{};
    for (final line in controller.text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split('=');
      if (parts.length == 2) {
        parsed[parts[0]] = parts[1].toLowerCase() == 'true';
      }
    }
    try {
      await ref.read(tenantApiProvider).updateFlags(tenantId, parsed);
      ref.invalidate(tenantsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Flags updated')));
      }
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $err')));
      }
    }
  }
}
