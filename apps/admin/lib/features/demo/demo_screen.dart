import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tenant.dart';
import '../../providers/tenant_providers.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/shad_snackbar.dart';
import 'demo_config.dart';
import 'demo_controls.dart';
import 'demo_split_view.dart';

class DemoScreen extends ConsumerStatefulWidget {
  const DemoScreen({super.key});

  @override
  ConsumerState<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends ConsumerState<DemoScreen> {
  Tenant? _selectedTenant;
  late final TextEditingController _businessBaseCtrl;
  late final TextEditingController _driverBaseCtrl;
  late final TextEditingController _agentIdCtrl;
  String _agentId = demoFastFoodAgentId;
  bool _settingRoute = false;
  bool _loadingStatus = false;
  Map<String, dynamic>? _demoStatus;
  bool _splitFullView = false;
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    _businessBaseCtrl = TextEditingController(text: demoBusinessAppBaseUrl);
    _driverBaseCtrl = TextEditingController(text: demoDriverAppBaseUrl);
    _agentIdCtrl = TextEditingController(text: _agentId);
  }

  @override
  void dispose() {
    _businessBaseCtrl.dispose();
    _driverBaseCtrl.dispose();
    _agentIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectTenant(Tenant tenant) async {
    setState(() {
      _selectedTenant = tenant;
      _agentId = pickDemoAgentIdForTenant(tenant);
      _agentIdCtrl.text = _agentId;
      _rev++;
    });
    await _applyDemoRoute();
  }

  Future<void> _submitAgentId(String value) async {
    final next = value.trim();
    if (next.isEmpty) return;
    setState(() {
      _agentId = next;
      _rev++;
    });
    await _applyDemoRoute();
  }

  Future<void> _applyDemoRoute() async {
    final tenant = _selectedTenant;
    if (tenant == null) return;
    setState(() => _settingRoute = true);
    try {
      final demoTopReorders = await _loadDemoTopReorders(tenant.storeId);
      await ref.read(tenantApiProvider).setDemoAgentRoute(
            agentId: _agentId,
            tenantId: tenant.id,
            storeId: tenant.storeId,
            businessType: tenant.businessType,
            environment: const String.fromEnvironment(
              'ENVIRONMENT',
              defaultValue: 'dev',
            ),
            demoSessionId: jsonEncode({
              'ts': DateTime.now().toIso8601String(),
            }),
            demoCallerId: demoCallerId,
            demoCallSid: demoCallSid,
            demoCustomerName: demoCustomerName,
            demoIsReturningCustomer:
                demoTopReorders.isEmpty ? false : demoIsReturningCustomer,
            demoTopReorders: demoTopReorders,
            demoEtaMinutes: demoEtaMinutes,
          );
      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Demo routing set',
        message:
            'Agent $_agentId will inject context for ${tenant.name} (${tenant.storeId}).',
        type: ShadSnackType.success,
      );
      await _refreshDemoStatus();
    } catch (error) {
      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Failed to set demo routing',
        message: '$error',
        type: ShadSnackType.error,
      );
    } finally {
      if (mounted) setState(() => _settingRoute = false);
    }
  }

  Future<List<String>> _loadDemoTopReorders(String storeId) async {
    try {
      final snapshot = await ref
          .read(tenantApiProvider)
          .getOrderServiceMenuSnapshot(storeId: storeId);
      return extractDemoTopReorders(snapshot);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _refreshDemoStatus() async {
    final agentId = _agentId.trim();
    if (agentId.isEmpty) return;
    setState(() => _loadingStatus = true);
    try {
      final status = await ref
          .read(tenantApiProvider)
          .getDemoAgentRouteStatus(agentId: agentId);
      if (!mounted) return;
      setState(() {
        _demoStatus = status;
        _rev++;
      });
    } catch (error) {
      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Failed to refresh webhook status',
        message: '$error',
        type: ShadSnackType.error,
      );
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantsAsync = ref.watch(tenantsProvider);

    return AdminScaffold(
      title: const Text('Live Demo'),
      body: Padding(
        padding: EdgeInsets.all(_splitFullView ? 0 : 16),
        child: Column(
          children: [
            if (!_splitFullView) ...[
              DemoRouteControls(
                tenants: tenantsAsync,
                selectedTenant: _selectedTenant,
                businessBaseController: _businessBaseCtrl,
                driverBaseController: _driverBaseCtrl,
                agentIdController: _agentIdCtrl,
                settingRoute: _settingRoute,
                onTenantChanged: _selectTenant,
                onAgentSubmitted: _submitAgentId,
                onApplyRouting: _applyDemoRoute,
                onBaseUrlSubmitted: () => setState(() => _rev++),
              ),
              const SizedBox(height: 16),
              DemoStatusControls(
                selectedTenant: _selectedTenant,
                splitFullView: _splitFullView,
                loadingStatus: _loadingStatus,
                onSplitFullViewChanged: (value) =>
                    setState(() => _splitFullView = value),
                onRefreshStatus: _refreshDemoStatus,
              ),
              const SizedBox(height: 16),
            ],
            Expanded(
              child: DemoSplitView(
                tenants: tenantsAsync,
                selectedTenant: _selectedTenant,
                businessBaseUrl: _businessBaseCtrl.text,
                driverBaseUrl: _driverBaseCtrl.text,
                agentId: _agentId,
                revision: _rev,
                demoStatus: _demoStatus,
                splitFullView: _splitFullView,
                onExitFullView: () => setState(() => _splitFullView = false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
