import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/tenant.dart';

class DemoRouteControls extends StatelessWidget {
  const DemoRouteControls({
    super.key,
    required this.tenants,
    required this.selectedTenant,
    required this.businessBaseController,
    required this.driverBaseController,
    required this.agentIdController,
    required this.settingRoute,
    required this.onTenantChanged,
    required this.onAgentSubmitted,
    required this.onApplyRouting,
    required this.onBaseUrlSubmitted,
  });

  final AsyncValue<List<Tenant>> tenants;
  final Tenant? selectedTenant;
  final TextEditingController businessBaseController;
  final TextEditingController driverBaseController;
  final TextEditingController agentIdController;
  final bool settingRoute;
  final Future<void> Function(Tenant tenant) onTenantChanged;
  final Future<void> Function(String agentId) onAgentSubmitted;
  final Future<void> Function() onApplyRouting;
  final VoidCallback onBaseUrlSubmitted;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: tenants.when(
              loading: () => const Text('Loading tenants...'),
              error: (error, _) => Text('Failed to load tenants: $error'),
              data: (items) {
                return DropdownButtonFormField<Tenant>(
                  initialValue: selectedTenant,
                  decoration: const InputDecoration(
                    labelText: 'Tenant',
                    border: OutlineInputBorder(),
                  ),
                  items: items
                      .map(
                        (tenant) => DropdownMenuItem(
                          value: tenant,
                          child: Text('${tenant.name} - ${tenant.storeId}'),
                        ),
                      )
                      .toList(),
                  onChanged: (tenant) async {
                    if (tenant == null) return;
                    await onTenantChanged(tenant);
                  },
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: TextField(
              controller: businessBaseController,
              decoration: const InputDecoration(
                labelText: 'Business app base URL',
                border: OutlineInputBorder(),
                hintText: 'https://liive-dev-business.web.app',
              ),
              onSubmitted: (_) => onBaseUrlSubmitted(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: TextField(
              controller: driverBaseController,
              decoration: const InputDecoration(
                labelText: 'Driver app base URL',
                border: OutlineInputBorder(),
                hintText: 'https://liive-dev-driver.web.app',
              ),
              onSubmitted: (_) => onBaseUrlSubmitted(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'ElevenLabs agent ID',
                border: OutlineInputBorder(),
              ),
              controller: agentIdController,
              onSubmitted: onAgentSubmitted,
            ),
          ),
          const SizedBox(width: 12),
          ShadButton(
            onPressed: settingRoute ? null : onApplyRouting,
            child: Text(settingRoute ? 'Setting...' : 'Apply routing'),
          ),
        ],
      ),
    );
  }
}

class DemoStatusControls extends StatelessWidget {
  const DemoStatusControls({
    super.key,
    required this.selectedTenant,
    required this.splitFullView,
    required this.loadingStatus,
    required this.onSplitFullViewChanged,
    required this.onRefreshStatus,
  });

  final Tenant? selectedTenant;
  final bool splitFullView;
  final bool loadingStatus;
  final ValueChanged<bool> onSplitFullViewChanged;
  final Future<void> Function() onRefreshStatus;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              selectedTenant == null
                  ? 'Select a tenant to see expected variables.'
                  : 'Expected: tenantId=${selectedTenant!.id} - storeId=${selectedTenant!.storeId} - businessType=${selectedTenant!.businessType}',
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Full view'),
              const SizedBox(width: 8),
              ShadSwitch(
                value: splitFullView,
                onChanged: onSplitFullViewChanged,
              ),
            ],
          ),
          const SizedBox(width: 12),
          ShadButton(
            onPressed: loadingStatus ? null : onRefreshStatus,
            child:
                Text(loadingStatus ? 'Refreshing...' : 'Refresh last webhook'),
          ),
        ],
      ),
    );
  }
}
