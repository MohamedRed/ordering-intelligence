import 'package:flutter/material.dart';

import '../../../models/order.dart';

String deliveryStatusKeyForOrder(Order order) {
  final delivery = order.delivery;
  if (delivery == null) return '';
  final summary = delivery.deliveryStatusSummary.trim().toLowerCase();
  final assignment = delivery.assignmentStatus.trim().toLowerCase();
  final raw = summary.isNotEmpty ? summary : assignment;
  if (raw.contains('out for') ||
      raw.contains('out_for') ||
      raw.contains('en route') ||
      raw.contains('en_route')) {
    return 'out_for_delivery';
  }
  if (raw.contains('delivered')) return 'delivered';
  if (raw.contains('assign')) return 'assigned';
  if (raw.contains('pickup') || raw.contains('picked')) return 'picked_up';
  if (raw.contains('fail') || raw.contains('cancel')) return 'failed';
  if (raw.isNotEmpty) {
    return raw.replaceAll(' ', '_');
  }
  return '';
}

String deliveryStatusLabelForOrder(Order order) {
  final key = deliveryStatusKeyForOrder(order);
  switch (key) {
    case 'assigned':
      return 'Assigned';
    case 'picked_up':
      return 'Picked up';
    case 'out_for_delivery':
      return 'Out for delivery';
    case 'delivered':
      return 'Delivered';
    case 'failed':
      return 'Failed';
    case '':
      return '';
    default:
      return key.replaceAll('_', ' ');
  }
}

Color deliveryStatusColor(String key) {
  switch (key) {
    case 'assigned':
      return Colors.indigo;
    case 'picked_up':
      return Colors.orange;
    case 'out_for_delivery':
      return Colors.deepOrange;
    case 'delivered':
      return Colors.green;
    case 'failed':
      return Colors.red;
    default:
      return Colors.blueGrey;
  }
}
