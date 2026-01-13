import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../providers/tenant_providers.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/shad_snackbar.dart';

class TenantListScreen extends ConsumerWidget {
  const TenantListScreen({super.key});

  static const _demoSkipStripeFlag = 'demo_skip_stripe';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantsAsync = ref.watch(tenantsProvider);
    return AdminScaffold(
        title: const Text('Tenants'),
        actions: [
          IconButton(
            tooltip: 'Create tenant',
            icon: const Icon(Icons.add_business_outlined),
            onPressed: () => _createTenant(context, ref),
          ),
        ],
      body: tenantsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
            child: ShadAlert.destructive(
          title: const Text('Failed to load tenants'),
          description: Text('$err'),
        )),
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
                return ShadCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Theme(
                    // ExpansionTile draws top/bottom dividers using dividerColor
                    // when expanded; shad theme makes these very prominent on web.
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      shape: const RoundedRectangleBorder(side: BorderSide.none),
                      collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
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
                                .map((e) => ShadBadge.secondary(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      child: Text(
                                          '${e.key}: ${e.value ? 'on' : 'off'}'),
                                    ))
                                .toList(),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Demo: skip Stripe',
                                      style: TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Allows progressing past Stripe during dev demos.',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ShadSwitch(
                                value: tenant.featureFlags[_demoSkipStripeFlag] ?? false,
                                onChanged: (v) async {
                                  try {
                                    final next = {...tenant.featureFlags, _demoSkipStripeFlag: v};
                                    await ref.read(tenantApiProvider).updateFlags(tenant.id, next);
                                    ref.invalidate(tenantsProvider);
                                    if (context.mounted) {
                                      showShadSnack(
                                        context,
                                        title: 'Tenant updated',
                                        message: v ? 'Stripe demo skip enabled.' : 'Stripe demo skip disabled.',
                                        type: ShadSnackType.success,
                                      );
                                    }
                                  } catch (err) {
                                    if (context.mounted) {
                                      showShadSnack(
                                        context,
                                        title: 'Failed to update tenant',
                                        message: '$err',
                                        type: ShadSnackType.error,
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 8,
                            children: [
                              ShadButton(
                                onPressed: () => context.go(
                                  '/tenants/${tenant.id}/onboarding',
                                  extra: tenant,
                                ),
                                child: const Text('Onboarding'),
                              ),
                              ShadButton.outline(
                                onPressed: () => _editFlags(
                                    context, ref, tenant.id, tenant.featureFlags),
                                child: const Text('Edit flags'),
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
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
        showShadSnack(context,
            title: 'Flags updated', type: ShadSnackType.success);
      }
    } catch (err) {
      if (context.mounted) {
        showShadSnack(context,
            title: 'Failed to update flags',
            message: '$err',
            type: ShadSnackType.error);
      }
    }
  }

  Future<void> _createTenant(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final storeCtrl = TextEditingController();
    final primaryCtrl = TextEditingController();
    String businessType = 'fast_food';

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Create tenant'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tenant name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: storeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Store ID (slug)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: primaryCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Primary user (email)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: businessType,
                    decoration: const InputDecoration(
                      labelText: 'Business type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'fast_food',
                        child: Text('Fast Food'),
                      ),
                      DropdownMenuItem(
                        value: 'auto_parts',
                        child: Text('Auto Parts'),
                      ),
                      DropdownMenuItem(
                        value: 'gas_station',
                        child: Text('Gas Station'),
                      ),
                    ],
                    onChanged: (v) => businessType = v ?? 'fast_food',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Create'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) return;
      if (!context.mounted) return;

      final name = nameCtrl.text.trim();
      final storeId = storeCtrl.text.trim();
      final primaryUser = primaryCtrl.text.trim();

      if (name.isEmpty || storeId.isEmpty || primaryUser.isEmpty) {
        showShadSnack(
          context,
          title: 'Missing fields',
          message: 'Name, Store ID, and Primary user are required.',
          type: ShadSnackType.error,
        );
        return;
      }

      try {
        final tenant = await ref.read(tenantApiProvider).createTenant(
              name: name,
              primaryUser: primaryUser,
              storeId: storeId,
              businessType: businessType,
            );
        ref.invalidate(tenantsProvider);
        if (!context.mounted) return;
        showShadSnack(
          context,
          title: 'Tenant created',
          message: tenant.name,
          type: ShadSnackType.success,
        );
        context.go('/tenants/${tenant.id}/onboarding', extra: tenant);
      } catch (err) {
        if (!context.mounted) return;
        showShadSnack(
          context,
          title: 'Failed to create tenant',
          message: '$err',
          type: ShadSnackType.error,
        );
      }
    } finally {
      nameCtrl.dispose();
      storeCtrl.dispose();
      primaryCtrl.dispose();
    }
  }
}
