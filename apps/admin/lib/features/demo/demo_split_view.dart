import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/tenant.dart';
import '../../widgets/web_iframe.dart';
import 'demo_config.dart';

class DemoSplitView extends StatelessWidget {
  const DemoSplitView({
    super.key,
    required this.tenants,
    required this.selectedTenant,
    required this.businessBaseUrl,
    required this.driverBaseUrl,
    required this.agentId,
    required this.revision,
    required this.demoStatus,
    required this.splitFullView,
    required this.onExitFullView,
  });

  final AsyncValue<List<Tenant>> tenants;
  final Tenant? selectedTenant;
  final String businessBaseUrl;
  final String driverBaseUrl;
  final String agentId;
  final int revision;
  final Map<String, dynamic>? demoStatus;
  final bool splitFullView;
  final VoidCallback onExitFullView;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        tenants.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: ShadAlert.destructive(
              title: const Text('Failed to load'),
              description: Text('$error'),
            ),
          ),
          data: (_) {
            final tenant = selectedTenant;
            if (tenant == null) {
              return Center(
                child: ShadAlert(
                  title: const Text('Select a tenant'),
                  description: const Text(
                    'Pick a tenant to start the split-view demo.',
                  ),
                ),
              );
            }
            return _DemoPanels(
              tenant: tenant,
              agentId: agentId,
              revision: revision,
              businessUrl: buildBusinessOrdersUrl(
                baseUrl: businessBaseUrl,
                storeId: tenant.storeId,
              ),
              driverUrl: buildDriverAppUrl(baseUrl: driverBaseUrl),
              widgetDoc: buildElevenLabsWidgetSrcDoc(
                agentId: agentId,
                dynamicVariables: buildDemoWidgetDynamicVariables(
                  demoStatus: demoStatus,
                  selectedTenant: selectedTenant,
                ),
              ),
              demoStatus: demoStatus,
            );
          },
        ),
        if (splitFullView)
          Positioned(
            top: 16,
            right: 16,
            child: ShadButton.outline(
              onPressed: onExitFullView,
              child: const Text('Exit full view'),
            ),
          ),
      ],
    );
  }
}

class _DemoPanels extends StatelessWidget {
  const _DemoPanels({
    required this.tenant,
    required this.agentId,
    required this.revision,
    required this.businessUrl,
    required this.driverUrl,
    required this.widgetDoc,
    required this.demoStatus,
  });

  final Tenant tenant;
  final String agentId;
  final int revision;
  final String businessUrl;
  final String driverUrl;
  final String widgetDoc;
  final Map<String, dynamic>? demoStatus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DemoPanel(
            title: 'Agent view - ElevenLabs widget ($agentId)',
            footer: _LastInjectedVariables(demoStatus: demoStatus),
            child: WebIFrame(
              key: ValueKey('agent_${agentId}_$revision'),
              srcDoc: widgetDoc,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _DemoPanel(
            title: 'Business view - Orders (${tenant.storeId})',
            child: WebIFrame(
              key: ValueKey('biz_${tenant.storeId}_$revision'),
              url: businessUrl,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _DemoPanel(
            title: 'Driver view',
            child: WebIFrame(
              key: ValueKey('driver_${tenant.storeId}_$revision'),
              url: driverUrl,
            ),
          ),
        ),
      ],
    );
  }
}

class _DemoPanel extends StatelessWidget {
  const _DemoPanel({
    required this.title,
    required this.child,
    this.footer,
  });

  final String title;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ShadTheme.of(context).colorScheme;
    return ShadCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colorScheme.border)),
            ),
            child: Text(title),
          ),
          Expanded(child: child),
          if (footer != null) footer!,
        ],
      ),
    );
  }
}

class _LastInjectedVariables extends StatelessWidget {
  const _LastInjectedVariables({required this.demoStatus});

  final Map<String, dynamic>? demoStatus;

  @override
  Widget build(BuildContext context) {
    final lastEvent = demoStatus?['lastEvent'];
    if (lastEvent is! Map) return const SizedBox.shrink();

    final colorScheme = ShadTheme.of(context).colorScheme;
    final dynamicVariables =
        (lastEvent['dynamic_variables'] as Map?) ?? const {};
    final storeId = dynamicVariables['storeId'];
    final tenantId = dynamicVariables['tenantId'];
    final businessType = dynamicVariables['businessType'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colorScheme.border)),
      ),
      child: Text(
        'Last injected: tenantId=$tenantId - storeId=$storeId - businessType=$businessType',
        style: TextStyle(color: colorScheme.mutedForeground),
      ),
    );
  }
}
