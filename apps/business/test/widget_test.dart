import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:business_app/models/group_order.dart';
import 'package:business_app/models/order.dart';
import 'package:business_app/providers/offline_queue.dart';

void main() {
  test('Order parses delivery, modifiers, fuel, and display totals', () {
    final order = Order.fromJson({
      'id': 'order-1',
      'storeId': 'store-1',
      'customerName': '',
      'status': 'ready',
      'fulfillmentType': 'delivery',
      'businessType': 'gas_station',
      'paymentMethod': 'card',
      'items': [
        {
          'itemId': 'burger',
          'name': 'Burger',
          'quantity': 2,
          'priceCents': 900,
          'modifierSelections': [
            {'name': 'Cheese'},
          ],
        },
      ],
      'delivery': {
        'fleetMode': 'owned',
        'trackingUrl': 'https://tracking.example/order-1',
        'assignmentStatus': 'assigned',
        'dropoffAddress': {
          'line1': '1 Main St',
          'city': 'Paris',
          'country': 'FR',
        },
        'dropoffLatLng': {'lat': 48.8566, 'lng': 2.3522},
        'quote': {
          'provider': 'owned',
          'providerFeeCents': 350,
          'dropoffEtaMinutes': 18,
          'currency': 'EUR',
          'quoteExpiresAt': '2026-01-01T10:05:00Z',
        },
      },
      'fuel': {
        'fuelGradeId': 'diesel',
        'fuelGradeName': 'Diesel',
        'unit': 'liter',
        'unitPriceCents': '190',
        'requestedLiters': '20.5',
        'requestedAmountCents': '3895',
        'preauthAmountCents': '5000',
        'paymentFlow': 'preauth',
      },
      'totalCents': 3895,
      'createdAt': '2026-01-01T10:00:00Z',
    });

    expect(order.title, 'order-1');
    expect(order.status, OrderStatus.ready);
    expect(order.isGasOrder, isTrue);
    expect(order.isCardPayment, isTrue);
    expect(order.formattedTotal, 'EUR 38.95');
    expect(order.items.first.modifierLabels, ['Cheese']);
    expect(order.delivery!.dropoffAddress!.display(), '1 Main St, Paris, FR');
    expect(order.delivery!.dropoffLatLng!.lat, 48.8566);
    expect(order.delivery!.quote!.dropoffEtaMinutes, 18);
    expect(order.fuel!.isPreauth, isTrue);
    expect(order.itemsSummary(), '2x Burger');
  });

  test('GroupOrder parses pricing, participants, and summary labels', () {
    final groupOrder = GroupOrder.fromJson({
      'id': 'group-1',
      'joinCode': 'ABC123',
      'storeId': 'store-1',
      'status': 'submitted',
      'host': {'displayName': 'Host User'},
      'paymentMode': 'split_by_participant',
      'paymentMethod': 'card',
      'participants': [
        {
          'participantId': 'p1',
          'displayName': '',
          'channelContact': {'displayName': 'Ana'},
        },
      ],
      'items': [
        {'name': 'Taco', 'quantity': 1, 'priceCents': 700},
        {'name': 'Soda', 'quantity': 2, 'priceCents': 250},
        {'name': 'Cake', 'quantity': 1, 'priceCents': 500},
        {'name': 'Coffee', 'quantity': 1, 'priceCents': 300},
      ],
      'pricing': {
        'subtotalCents': '2000',
        'taxCents': 100,
        'feeCents': 50,
        'discountCents': 0,
        'totalCents': 2150,
        'allocations': [
          {'participantId': 'p1', 'totalCents': 1250},
        ],
      },
    });

    expect(groupOrder.formattedTotal, r'$21.50');
    expect(groupOrder.hostLabel, 'Host User');
    expect(groupOrder.isCardPayment, isTrue);
    expect(groupOrder.isSplitPayment, isTrue);
    expect(groupOrder.paymentModeLabel, 'Split by participant');
    expect(groupOrder.paymentMethodLabel, 'Card');
    expect(groupOrder.itemsSummary(), '1x Taco, 2x Soda, 1x Cake, +1 more');
    expect(groupOrder.participantLabel('p1'), 'Ana');
    expect(groupOrder.allocationFor('p1')!.participantId, 'p1');
  });

  test('StatusUpdateQueue keeps failed updates and removes successful ones',
      () async {
    SharedPreferences.setMockInitialValues({});
    final queue = StatusUpdateQueue();

    await queue.add(QueuedStatus(orderId: 'ok', status: 'ready'));
    await queue.add(QueuedStatus(orderId: 'retry', status: 'confirmed'));

    await queue.flush((item) async {
      if (item.orderId == 'retry') {
        throw StateError('temporary failure');
      }
    });

    final remaining = await queue.load();
    expect(remaining, hasLength(1));
    expect(remaining.single.orderId, 'retry');

    await queue.flushIfAny((item) async {});
    expect(await queue.load(), isEmpty);
  });
}
