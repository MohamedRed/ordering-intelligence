import 'package:flutter_test/flutter_test.dart';

import 'package:business_app/features/settings/store_settings_defaults.dart';
import 'package:business_app/features/settings/store_settings_payload.dart';
import 'package:business_app/features/settings/store_settings_template_cards.dart';
import 'package:business_app/features/settings/store_settings_template_row.dart';

void main() {
  test('default order and delivery comms include every supported status', () {
    final order = defaultOrderComms();
    final orderStatuses = order['statuses'] as Map<String, dynamic>;

    expect(orderStatuses.keys, containsAll(orderCommsStatuses));
    expect(order['default_wait_minutes'], 15);
    expect(order['ready_escalation_channel'], 'call');
    expect(_defaultTemplateBody(orderStatuses['ready']),
        'Your order is ready for pickup.');

    final delivery = defaultDeliveryComms();
    final deliveryStatuses = delivery['statuses'] as Map<String, dynamic>;

    expect(deliveryStatuses.keys, containsAll(deliveryCommsStatuses));
    expect(delivery['rate_limit_per_hour'], 3);
    expect(
      _defaultTemplateBody(deliveryStatuses['delivery_assigned']),
      'Your delivery is being prepared. A driver has been assigned.',
    );
  });

  test('settings integer parser handles persisted numeric shapes', () {
    expect(readSettingsInt(8, 1), 8);
    expect(readSettingsInt(8.9, 1), 8);
    expect(readSettingsInt(' 12 ', 1), 12);
    expect(readSettingsInt('bad', 4), 4);
    expect(readSettingsInt(null, 7), 7);
  });

  test('template rows parse, serialize, and pick safe dropdown values', () {
    final rows = templateRowsFromConfig(
      [
        {'id': ' first ', 'label': ' First ', 'body': ' Body '},
        {'id': ' ', 'label': 'ignored', 'body': 'ignored'},
      ],
      fallbackBody: 'Fallback',
    );

    addTearDown(() => _disposeRows(rows));

    expect(rows, hasLength(1));
    expect(rows.single.id.text, 'first');
    expect(rows.single.label.text, 'First');
    expect(rows.single.body.text, 'Body');
    expect(templateLabel(rows.single), 'First');
    expect(selectedTemplateValue(rows, 'missing'), 'first');

    rows.single.label.text = '';
    expect(templateLabel(rows.single), 'first');
    expect(serializeTemplateRows(rows), [
      {'id': 'first', 'label': '', 'body': 'Body'},
    ]);
  });

  test('template parser creates fallback row for invalid template payloads',
      () {
    final rows = templateRowsFromConfig('not-a-list', fallbackBody: 'Fallback');

    addTearDown(() => _disposeRows(rows));

    expect(rows, hasLength(1));
    expect(rows.single.id.text, 'default');
    expect(rows.single.body.text, 'Fallback');
  });

  test('store settings payload preserves comms and delivery configuration', () {
    final orderRows = [
      TemplateRow(id: 'ready_custom', label: 'Ready custom', body: 'Ready now'),
      TemplateRow(id: '', label: 'Ignored', body: 'No id'),
    ];
    final deliveryRows = [
      TemplateRow(id: 'delivered_custom', label: 'Delivered', body: 'Enjoy'),
    ];

    addTearDown(() {
      _disposeRows(orderRows);
      _disposeRows(deliveryRows);
    });

    final payload = buildStoreSettingsPayload(
      defaultWaitMinutes: 22,
      readyEscalationEnabled: true,
      readyEscalationMinutes: 9,
      readyEscalationChannel: 'sms',
      deliveryArrivingSoonEnabled: true,
      deliveryArrivingSoonMinutes: 4,
      deliveryRateLimitPerHour: 2,
      deliveryEnabled: true,
      deliveryFleetMode: 'marketplace',
      storeAddress: '  123 Main St  ',
      storeLat: '40.12',
      storeLng: '-73.45',
      marketplaceOffer: ' 450 ',
      marketplaceOfferCents: 300,
      defaultChannelByStatus: const {'ready': 'sms'},
      defaultTemplateIdByStatus: const {'ready': 'ready_custom'},
      templatesByStatus: {'ready': orderRows},
      deliveryDefaultChannelByStatus: const {'delivered': 'sms'},
      deliveryDefaultTemplateIdByStatus: const {
        'delivered': 'delivered_custom',
      },
      deliveryTemplatesByStatus: {'delivered': deliveryRows},
    );

    final orderComms = payload['order_comms'] as Map<String, dynamic>;
    final deliveryComms = payload['delivery_comms'] as Map<String, dynamic>;
    final deliverySettings =
        payload['delivery_settings'] as Map<String, dynamic>;
    final orderStatuses = orderComms['statuses'] as Map<String, dynamic>;
    final deliveryStatuses = deliveryComms['statuses'] as Map<String, dynamic>;

    expect(orderComms['default_wait_minutes'], 22);
    expect(orderComms['ready_escalation_enabled'], isTrue);
    expect(orderStatuses['ready']['default_channel'], 'sms');
    expect(orderStatuses['ready']['templates'], [
      {'id': 'ready_custom', 'label': 'Ready custom', 'body': 'Ready now'},
    ]);
    expect(deliveryComms['arriving_soon_enabled'], isTrue);
    expect(deliveryStatuses['delivered']['default_template_id'],
        'delivered_custom');
    expect(deliverySettings['marketplace_offer_cents'], 450);
    expect(deliverySettings['store_location'], {
      'formatted': '123 Main St',
      'lat': 40.12,
      'lng': -73.45,
    });
  });

  test('store location omits coordinates unless both values parse', () {
    expect(
      buildStoreLocation(address: 'HQ', lat: '1.2', lng: 'bad'),
      {'formatted': 'HQ'},
    );
  });
}

String _defaultTemplateBody(dynamic statusConfig) {
  final templates = (statusConfig as Map<String, dynamic>)['templates'] as List;
  return (templates.single as Map<String, dynamic>)['body'] as String;
}

void _disposeRows(List<TemplateRow> rows) {
  for (final row in rows) {
    row.dispose();
  }
}
