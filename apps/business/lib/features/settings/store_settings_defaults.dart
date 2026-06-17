import 'store_settings_template_row.dart';

const orderCommsStatuses = [
  'pending',
  'confirmed',
  'ready',
  'completed',
  'cancelled',
  'delay',
];

const deliveryCommsStatuses = [
  'delivery_assigned',
  'picked_up',
  'out_for_delivery',
  'arriving_soon',
  'delivered',
  'delivery_failed',
];

const notificationChannels = ['none', 'sms', 'call'];

Map<String, dynamic> defaultOrderComms() {
  const defaults = {
    'pending': 'Your order was received.',
    'confirmed': 'Your order has been confirmed.',
    'ready': 'Your order is ready for pickup.',
    'completed': 'Thanks — your order is marked completed.',
    'cancelled':
        'Your order was cancelled. Please contact the store if you have questions.',
    'delay': 'Your order is running a bit late.',
  };
  return {
    'default_wait_minutes': 15,
    'statuses': _defaultStatuses(orderCommsStatuses, defaults),
    'ready_escalation_enabled': false,
    'ready_escalation_minutes': 5,
    'ready_escalation_channel': 'call',
  };
}

Map<String, dynamic> defaultDeliveryComms() {
  const defaults = {
    'delivery_assigned':
        'Your delivery is being prepared. A driver has been assigned.',
    'picked_up': 'Your order has been picked up and is on the way.',
    'out_for_delivery': 'Your order is out for delivery.',
    'arriving_soon': 'Your driver is nearby. Arriving soon.',
    'delivered': 'Delivered. Enjoy!',
    'delivery_failed':
        "We couldn't complete the delivery. Please contact the store.",
  };
  return {
    'rate_limit_per_hour': 3,
    'arriving_soon_enabled': false,
    'arriving_soon_eta_threshold_minutes': 3,
    'statuses': _defaultStatuses(deliveryCommsStatuses, defaults),
  };
}

Map<String, dynamic> _defaultStatuses(
  List<String> statuses,
  Map<String, String> defaults,
) {
  return {
    for (final status in statuses)
      status: {
        'default_channel': 'none',
        'default_template_id': 'default',
        'templates': [
          {
            'id': 'default',
            'label': 'Default',
            'body': defaults[status] ?? 'Status updated.',
          }
        ],
      }
  };
}

int readSettingsInt(dynamic value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}

List<TemplateRow> templateRowsFromConfig(
  dynamic rawTemplates, {
  required String fallbackBody,
}) {
  final rows = <TemplateRow>[];
  final templates = rawTemplates is Iterable ? rawTemplates : const [];
  for (final template in templates) {
    final map = (template as Map?)?.cast<String, dynamic>();
    if (map == null) continue;
    final id = (map['id'] as String?)?.trim() ?? '';
    if (id.isEmpty) continue;
    rows.add(
      TemplateRow(
        id: id,
        label: (map['label'] as String?)?.trim() ?? '',
        body: (map['body'] as String?)?.trim() ?? '',
      ),
    );
  }
  if (rows.isEmpty) {
    rows.add(TemplateRow(id: 'default', label: 'Default', body: fallbackBody));
  }
  return rows;
}

Map<String, dynamic> serializeCommsStatuses(
  List<String> statuses,
  Map<String, String> defaultChannelByStatus,
  Map<String, String> defaultTemplateIdByStatus,
  Map<String, List<TemplateRow>> templatesByStatus,
) {
  return {
    for (final status in statuses)
      status: {
        'default_channel': defaultChannelByStatus[status] ?? 'none',
        'default_template_id': defaultTemplateIdByStatus[status] ?? 'default',
        'templates':
            serializeTemplateRows(templatesByStatus[status] ?? const []),
      }
  };
}

List<Map<String, String>> serializeTemplateRows(List<TemplateRow> rows) {
  final templates = <Map<String, String>>[];
  for (final row in rows) {
    final id = row.id.text.trim();
    if (id.isEmpty) continue;
    templates.add({
      'id': id,
      'label': row.label.text.trim(),
      'body': row.body.text.trim(),
    });
  }
  return templates;
}
