import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/tenant.dart';
import '../../providers/tenant_providers.dart';
import '../../widgets/shad_snackbar.dart';
import '../../widgets/web_iframe.dart';
import '../../widgets/admin_scaffold.dart';

const _businessAppBaseUrl = String.fromEnvironment(
  'BUSINESS_APP_URL',
  // For local dev, you can run the business app on another port and override:
  // --dart-define=BUSINESS_APP_URL=http://localhost:4001
  defaultValue: 'http://localhost:4001',
);

const _driverAppBaseUrl = String.fromEnvironment(
  'DRIVER_APP_URL',
  // For local dev, you can run the driver app on another port and override:
  // --dart-define=DRIVER_APP_URL=http://localhost:4002
  defaultValue: 'http://localhost:4002',
);

const _fastFoodAgentId = String.fromEnvironment(
  'ELEVENLABS_FAST_FOOD_AGENT_ID',
  defaultValue: 'agent_7201kbfs3pbpe1tsv4dmakk1207q',
);

const _autoPartsAgentId = String.fromEnvironment(
  'ELEVENLABS_AUTO_PARTS_AGENT_ID',
  defaultValue: 'agent_9201kbnjy570f0ysjk9mssmwewm3',
);

const _gasStationAgentId = String.fromEnvironment(
  'ELEVENLABS_GAS_STATION_AGENT_ID',
  defaultValue: 'agent_7201kbfs3pbpe1tsv4dmakk1207q',
);

const _demoCallerId = String.fromEnvironment(
  'DEMO_CALLER_ID',
  defaultValue: '00212633284619',
);

const _demoCallSid = String.fromEnvironment(
  'DEMO_CALL_SID',
  defaultValue: 'DEMO_CALL_001',
);

const _demoCustomerName = String.fromEnvironment(
  'DEMO_CUSTOMER_NAME',
  defaultValue: 'Demo Customer',
);

const _demoIsReturningCustomer = bool.fromEnvironment(
  'DEMO_IS_RETURNING_CUSTOMER',
  defaultValue: true,
);

const _demoEtaMinutes = int.fromEnvironment(
  'DEMO_ETA_MINUTES',
  defaultValue: 15,
);

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
  String _agentId = _fastFoodAgentId;
  bool _settingRoute = false;
  bool _loadingStatus = false;
  Map<String, dynamic>? _demoStatus;
  bool _splitFullView = false;

  // Used to force iframe recreation on selection change.
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    _businessBaseCtrl = TextEditingController(text: _businessAppBaseUrl);
    _driverBaseCtrl = TextEditingController(text: _driverAppBaseUrl);
    _agentIdCtrl = TextEditingController(text: _agentId);
  }

  @override
  void dispose() {
    _businessBaseCtrl.dispose();
    _driverBaseCtrl.dispose();
    _agentIdCtrl.dispose();
    super.dispose();
  }

  String _pickAgentIdForTenant(Tenant t) {
    final bt = (t.businessType).toLowerCase().trim();
    if (bt == 'auto_parts') return _autoPartsAgentId;
    if (bt == 'gas_station') return _gasStationAgentId;
    return _fastFoodAgentId;
  }

  String _businessOrdersUrl(
      {required String baseUrl, required String storeId}) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/*$'), '');
    // Flutter web typically uses hash routing unless path strategy is enabled.
    return '$trimmed/#/orders?storeId=${Uri.encodeComponent(storeId)}';
  }

  String _driverAppUrl({required String baseUrl}) {
    return baseUrl.trim().replaceAll(RegExp(r'/*$'), '');
  }

  String _elevenLabsWidgetSrcDoc({required String agentId}) {
    // Use srcdoc so we don't need to host a separate HTML page.
    // Note: we pass dynamic variables directly so the widget can start even if the webhook is delayed.
    final dynamicVars = _buildWidgetDynamicVariables();
    final dynamicVarsAttr = dynamicVars.isEmpty
        ? ''
        : ' dynamic-variables=\'${const HtmlEscape(HtmlEscapeMode.attribute).convert(jsonEncode(dynamicVars))}\'';
    final html = '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style>
      html, body { margin: 0; padding: 0; height: 100%; width: 100%; overflow: hidden; }
      elevenlabs-convai { display: block; height: 100%; width: 100%; }
    </style>
  </head>
  <body>
    <elevenlabs-convai agent-id="${agentId.replaceAll('"', '')}"$dynamicVarsAttr></elevenlabs-convai>
    <script src="https://unpkg.com/@elevenlabs/convai-widget-embed@beta" async type="text/javascript"></script>
  </body>
</html>
''';
    return html;
  }

  Map<String, String> _buildWidgetDynamicVariables() {
    final route = _demoStatus?['route'];
    final lastEvent = _demoStatus?['lastEvent'];
    final lastVars = (lastEvent is Map<String, dynamic>)
        ? (lastEvent['dynamic_variables'] as Map?)?.cast<String, dynamic>() ??
            const {}
        : const <String, dynamic>{};
    final routeMap =
        route is Map<String, dynamic> ? route : const <String, dynamic>{};

    String? pickString(List<String> keys) {
      for (final key in keys) {
        final v = routeMap[key] ?? lastVars[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    int? pickInt(List<String> keys) {
      for (final key in keys) {
        final v = routeMap[key] ?? lastVars[key];
        if (v is int) return v;
        if (v is num) return v.toInt();
        if (v is String) {
          final parsed = int.tryParse(v.trim());
          if (parsed != null) return parsed;
        }
      }
      return null;
    }

    bool? pickBool(List<String> keys) {
      for (final key in keys) {
        final v = routeMap[key] ?? lastVars[key];
        if (v is bool) return v;
        if (v is String) {
          final lowered = v.trim().toLowerCase();
          if (lowered == 'true') return true;
          if (lowered == 'false') return false;
        }
      }
      return null;
    }

    dynamic pickAny(List<String> keys) {
      for (final key in keys) {
        final v = routeMap[key] ?? lastVars[key];
        if (v != null) return v;
      }
      return null;
    }

    final storeId =
        pickString(['store_id', 'storeId']) ?? _selectedTenant?.storeId;
    final tenantId =
        pickString(['tenant_id', 'tenantId']) ?? _selectedTenant?.id;
    final businessType = pickString(['business_type', 'businessType']) ??
        _selectedTenant?.businessType;
    final etaMinutes =
        pickInt(['demo_eta_minutes', 'eta_minutes', 'etaMinutes']);
    final isReturning = pickBool([
      'demo_is_returning_customer',
      'isReturningCustomer',
      'is_returning_customer'
    ]);
    final customerName = pickString(['demo_customer_name', 'customerName']);
    final topReorders = pickAny(['demo_top_reorders', 'topReorders']);
    final callerId = pickString(['demo_caller_id', 'callerId']);
    final callSid = pickString(['demo_call_sid', 'callSid']);

    final out = <String, String>{};
    if (storeId != null) out['storeId'] = storeId;
    if (tenantId != null) out['tenantId'] = tenantId;
    if (businessType != null) out['businessType'] = businessType;
    if (etaMinutes != null) out['eta_minutes'] = etaMinutes.toString();
    if (isReturning != null) {
      out['isReturningCustomer'] = isReturning.toString();
    }
    if (customerName != null) out['customerName'] = customerName;
    if (topReorders != null) {
      if (topReorders is String) {
        out['topReorders'] = topReorders;
      } else {
        out['topReorders'] = jsonEncode(topReorders);
      }
    }
    if (callerId != null) out['callerId'] = callerId;
    if (callSid != null) out['callSid'] = callSid;
    return out;
  }

  List<String> _extractTopReorders(Map<String, dynamic>? snapshot) {
    if (snapshot == null) return const [];
    final items = snapshot['items'];
    if (items is List) {
      for (final raw in items) {
        if (raw is Map<String, dynamic>) {
          final name = (raw['name'] as String?)?.trim() ?? '';
          if (name.isNotEmpty) {
            return [name];
          }
        } else if (raw is Map) {
          final name = (raw['name'] as String?)?.trim() ?? '';
          if (name.isNotEmpty) {
            return [name];
          }
        }
      }
    }
    return const [];
  }

  Future<void> _applyDemoRoute() async {
    final t = _selectedTenant;
    if (t == null) return;
    setState(() => _settingRoute = true);
    try {
      List<String> demoTopReorders = const [];
      try {
        final snapshot = await ref
            .read(tenantApiProvider)
            .getOrderServiceMenuSnapshot(storeId: t.storeId);
        demoTopReorders = _extractTopReorders(snapshot);
      } catch (_) {
        demoTopReorders = const [];
      }
      await ref.read(tenantApiProvider).setDemoAgentRoute(
            agentId: _agentId,
            tenantId: t.id,
            storeId: t.storeId,
            businessType: t.businessType,
            environment: const String.fromEnvironment('ENVIRONMENT',
                defaultValue: 'dev'),
            demoSessionId: jsonEncode({
              'ts': DateTime.now().toIso8601String(),
            }),
            demoCallerId: _demoCallerId,
            demoCallSid: _demoCallSid,
            demoCustomerName: _demoCustomerName,
            demoIsReturningCustomer:
                demoTopReorders.isEmpty ? false : _demoIsReturningCustomer,
            demoTopReorders: demoTopReorders,
            demoEtaMinutes: _demoEtaMinutes,
          );
      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Demo routing set',
        message:
            'Agent $_agentId will inject context for ${t.name} (${t.storeId}).',
        type: ShadSnackType.success,
      );
      await _refreshDemoStatus();
    } catch (e) {
      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Failed to set demo routing',
        message: '$e',
        type: ShadSnackType.error,
      );
    } finally {
      if (mounted) setState(() => _settingRoute = false);
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
    } catch (e) {
      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Failed to refresh webhook status',
        message: '$e',
        type: ShadSnackType.error,
      );
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantsAsync = ref.watch(tenantsProvider);
    final cs = ShadTheme.of(context).colorScheme;

    return AdminScaffold(
      title: const Text('Live Demo'),
      body: Padding(
        padding: EdgeInsets.all(_splitFullView ? 0 : 16),
        child: Column(
          children: [
            if (!_splitFullView) ...[
              ShadCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: tenantsAsync.when(
                        loading: () => const Text('Loading tenants…'),
                        error: (e, _) => Text('Failed to load tenants: $e'),
                        data: (tenants) {
                          return DropdownButtonFormField<Tenant>(
                            initialValue: _selectedTenant,
                            decoration: const InputDecoration(
                              labelText: 'Tenant',
                              border: OutlineInputBorder(),
                            ),
                            items: tenants
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Text('${t.name} • ${t.storeId}'),
                                  ),
                                )
                                .toList(),
                            onChanged: (t) async {
                              if (t == null) return;
                              setState(() {
                                _selectedTenant = t;
                                _agentId = _pickAgentIdForTenant(t);
                                _agentIdCtrl.text = _agentId;
                                _rev++;
                              });
                              await _applyDemoRoute();
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _businessBaseCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Business app base URL',
                          border: OutlineInputBorder(),
                          hintText: 'http://localhost:4001',
                        ),
                        onSubmitted: (_) => setState(() => _rev++),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _driverBaseCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Driver app base URL',
                          border: OutlineInputBorder(),
                          hintText: 'http://localhost:4002',
                        ),
                        onSubmitted: (_) => setState(() => _rev++),
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
                        controller: _agentIdCtrl,
                        onSubmitted: (v) async {
                          final next = v.trim();
                          if (next.isEmpty) return;
                          setState(() {
                            _agentId = next;
                            _rev++;
                          });
                          await _applyDemoRoute();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    ShadButton(
                      onPressed: _settingRoute ? null : _applyDemoRoute,
                      child: Text(_settingRoute ? 'Setting…' : 'Apply routing'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ShadCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedTenant == null
                            ? 'Select a tenant to see expected variables.'
                            : 'Expected: tenantId=${_selectedTenant!.id} • storeId=${_selectedTenant!.storeId} • businessType=${_selectedTenant!.businessType}',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Full view'),
                        const SizedBox(width: 8),
                        ShadSwitch(
                          value: _splitFullView,
                          onChanged: (v) => setState(() => _splitFullView = v),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    ShadButton(
                      onPressed: _loadingStatus ? null : _refreshDemoStatus,
                      child: Text(_loadingStatus
                          ? 'Refreshing…'
                          : 'Refresh last webhook'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Expanded(
              child: Stack(
                children: [
                  tenantsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: ShadAlert.destructive(
                        title: const Text('Failed to load'),
                        description: Text('$e'),
                      ),
                    ),
                    data: (_) {
                      final t = _selectedTenant;
                      if (t == null) {
                        return Center(
                          child: ShadAlert(
                            title: const Text('Select a tenant'),
                            description: const Text(
                                'Pick a tenant to start the split-view demo.'),
                          ),
                        );
                      }
                      final businessUrl = _businessOrdersUrl(
                        baseUrl: _businessBaseCtrl.text,
                        storeId: t.storeId,
                      );
                      final driverUrl =
                          _driverAppUrl(baseUrl: _driverBaseCtrl.text);
                      final widgetDoc =
                          _elevenLabsWidgetSrcDoc(agentId: _agentId);

                      return Row(
                        children: [
                          Expanded(
                            child: ShadCard(
                              padding: const EdgeInsets.all(0),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      border: Border(
                                          bottom: BorderSide(color: cs.border)),
                                    ),
                                    child: Text(
                                        'Agent view • ElevenLabs widget ($_agentId)'),
                                  ),
                                  Expanded(
                                    child: WebIFrame(
                                      key: ValueKey('agent_${_agentId}_$_rev'),
                                      srcDoc: widgetDoc,
                                    ),
                                  ),
                                  if ((_demoStatus?['lastEvent'] as Map?) !=
                                      null)
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        border: Border(
                                            top: BorderSide(color: cs.border)),
                                      ),
                                      child: Builder(
                                        builder: (context) {
                                          final lastEvent =
                                              _demoStatus?['lastEvent'] as Map?;
                                          final dv =
                                              (lastEvent?['dynamic_variables']
                                                      as Map?) ??
                                                  const {};
                                          final storeId = dv['storeId'];
                                          final tenantId = dv['tenantId'];
                                          final businessType =
                                              dv['businessType'];
                                          return Text(
                                            'Last injected: tenantId=$tenantId • storeId=$storeId • businessType=$businessType',
                                            style: TextStyle(
                                                color: cs.mutedForeground),
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ShadCard(
                              padding: const EdgeInsets.all(0),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      border: Border(
                                          bottom: BorderSide(color: cs.border)),
                                    ),
                                    child: Text(
                                        'Business view • Orders (${t.storeId})'),
                                  ),
                                  Expanded(
                                    child: WebIFrame(
                                      key: ValueKey('biz_${t.storeId}_$_rev'),
                                      url: businessUrl,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ShadCard(
                              padding: const EdgeInsets.all(0),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      border: Border(
                                          bottom: BorderSide(color: cs.border)),
                                    ),
                                    child: const Text('Driver view'),
                                  ),
                                  Expanded(
                                    child: WebIFrame(
                                      key:
                                          ValueKey('driver_${t.storeId}_$_rev'),
                                      url: driverUrl,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  if (_splitFullView)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: ShadButton.outline(
                        onPressed: () => setState(() => _splitFullView = false),
                        child: const Text('Exit full view'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
