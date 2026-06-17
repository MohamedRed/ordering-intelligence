import 'dart:convert';

import '../../models/tenant.dart';

const demoBusinessAppBaseUrl = String.fromEnvironment(
  'BUSINESS_APP_URL',
  defaultValue: 'https://liive-dev-business.web.app',
);

const demoDriverAppBaseUrl = String.fromEnvironment(
  'DRIVER_APP_URL',
  defaultValue: 'https://liive-dev-driver.web.app',
);

const demoFastFoodAgentId = String.fromEnvironment(
  'ELEVENLABS_FAST_FOOD_AGENT_ID',
  defaultValue: 'agent_7201kbfs3pbpe1tsv4dmakk1207q',
);

const demoAutoPartsAgentId = String.fromEnvironment(
  'ELEVENLABS_AUTO_PARTS_AGENT_ID',
  defaultValue: 'agent_9201kbnjy570f0ysjk9mssmwewm3',
);

const demoGasStationAgentId = String.fromEnvironment(
  'ELEVENLABS_GAS_STATION_AGENT_ID',
  defaultValue: 'agent_7201kbfs3pbpe1tsv4dmakk1207q',
);

const demoCallerId = String.fromEnvironment(
  'DEMO_CALLER_ID',
  defaultValue: '00212633284619',
);

const demoCallSid = String.fromEnvironment(
  'DEMO_CALL_SID',
  defaultValue: 'DEMO_CALL_001',
);

const demoCustomerName = String.fromEnvironment(
  'DEMO_CUSTOMER_NAME',
  defaultValue: 'Demo Customer',
);

const demoIsReturningCustomer = bool.fromEnvironment(
  'DEMO_IS_RETURNING_CUSTOMER',
  defaultValue: true,
);

const demoEtaMinutes = int.fromEnvironment(
  'DEMO_ETA_MINUTES',
  defaultValue: 15,
);

String pickDemoAgentIdForTenant(Tenant tenant) {
  final businessType = tenant.businessType.toLowerCase().trim();
  if (businessType == 'auto_parts') return demoAutoPartsAgentId;
  if (businessType == 'gas_station') return demoGasStationAgentId;
  return demoFastFoodAgentId;
}

String buildBusinessOrdersUrl({
  required String baseUrl,
  required String storeId,
}) {
  final trimmed = baseUrl.trim().replaceAll(RegExp(r'/*$'), '');
  return '$trimmed/#/orders?storeId=${Uri.encodeComponent(storeId)}';
}

String buildDriverAppUrl({required String baseUrl}) {
  return baseUrl.trim().replaceAll(RegExp(r'/*$'), '');
}

String buildElevenLabsWidgetSrcDoc({
  required String agentId,
  required Map<String, String> dynamicVariables,
}) {
  final dynamicVarsAttr = dynamicVariables.isEmpty
      ? ''
      : ' dynamic-variables=\'${const HtmlEscape(HtmlEscapeMode.attribute).convert(jsonEncode(dynamicVariables))}\'';
  return '''
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
}

Map<String, String> buildDemoWidgetDynamicVariables({
  required Map<String, dynamic>? demoStatus,
  required Tenant? selectedTenant,
}) {
  final route = demoStatus?['route'];
  final lastEvent = demoStatus?['lastEvent'];
  final lastVars = lastEvent is Map
      ? (lastEvent['dynamic_variables'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{}
      : const <String, dynamic>{};
  final routeMap =
      route is Map ? route.cast<String, dynamic>() : const <String, dynamic>{};

  String? pickString(List<String> keys) {
    for (final key in keys) {
      final value = routeMap[key] ?? lastVars[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  int? pickInt(List<String> keys) {
    for (final key in keys) {
      final value = routeMap[key] ?? lastVars[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  bool? pickBool(List<String> keys) {
    for (final key in keys) {
      final value = routeMap[key] ?? lastVars[key];
      if (value is bool) return value;
      if (value is String) {
        final lowered = value.trim().toLowerCase();
        if (lowered == 'true') return true;
        if (lowered == 'false') return false;
      }
    }
    return null;
  }

  Object? pickAny(List<String> keys) {
    for (final key in keys) {
      final value = routeMap[key] ?? lastVars[key];
      if (value != null) return value;
    }
    return null;
  }

  final storeId =
      pickString(['store_id', 'storeId']) ?? selectedTenant?.storeId;
  final tenantId = pickString(['tenant_id', 'tenantId']) ?? selectedTenant?.id;
  final businessType = pickString(['business_type', 'businessType']) ??
      selectedTenant?.businessType;
  final etaMinutes = pickInt(['demo_eta_minutes', 'eta_minutes', 'etaMinutes']);
  final isReturning = pickBool([
    'demo_is_returning_customer',
    'isReturningCustomer',
    'is_returning_customer',
  ]);
  final customerName = pickString(['demo_customer_name', 'customerName']);
  final topReorders = pickAny(['demo_top_reorders', 'topReorders']);
  final callerId = pickString(['demo_caller_id', 'callerId']);
  final callSid = pickString(['demo_call_sid', 'callSid']);

  final output = <String, String>{};
  if (storeId != null) output['storeId'] = storeId;
  if (tenantId != null) output['tenantId'] = tenantId;
  if (businessType != null) output['businessType'] = businessType;
  if (etaMinutes != null) output['eta_minutes'] = etaMinutes.toString();
  if (isReturning != null) {
    output['isReturningCustomer'] = isReturning.toString();
  }
  if (customerName != null) output['customerName'] = customerName;
  if (topReorders != null) {
    output['topReorders'] =
        topReorders is String ? topReorders : jsonEncode(topReorders);
  }
  if (callerId != null) output['callerId'] = callerId;
  if (callSid != null) output['callSid'] = callSid;
  return output;
}

List<String> extractDemoTopReorders(Map<String, dynamic>? snapshot) {
  if (snapshot == null) return const [];
  final items = snapshot['items'];
  if (items is! List) return const [];
  for (final raw in items) {
    if (raw is Map<String, dynamic>) {
      final name = (raw['name'] as String?)?.trim() ?? '';
      if (name.isNotEmpty) return [name];
    } else if (raw is Map) {
      final name = (raw['name'] as String?)?.trim() ?? '';
      if (name.isNotEmpty) return [name];
    }
  }
  return const [];
}
