import '../../../models/group_order.dart';
import '../../../models/order.dart';
import 'order_delivery_helpers.dart';
import 'order_inbox_filters.dart';

List<Order> filterOrdersForInbox(
  List<Order> orders,
  OrderInboxFilter filter,
  String deliveryStatusFilter,
) {
  if (filter == OrderInboxFilter.delivery) {
    final deliveryOrders = orders
        .where((order) =>
            order.fulfillmentType.toLowerCase().trim() == 'delivery')
        .toList();
    if (deliveryStatusFilter == 'all') return deliveryOrders;
    return deliveryOrders
        .where(
            (order) => deliveryStatusKeyForOrder(order) == deliveryStatusFilter)
        .toList();
  }
  return orders;
}

List<GroupOrder> sortGroupOrdersForInbox(List<GroupOrder> orders) {
  final sorted = List<GroupOrder>.from(orders);
  sorted.sort((a, b) {
    final pa = _groupOrderPriority(a.status);
    final pb = _groupOrderPriority(b.status);
    if (pa != pb) return pa.compareTo(pb);
    final ta =
        a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final tb =
        b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return tb.compareTo(ta);
  });
  return sorted;
}

List<GroupOrder> filterGroupOrdersForInbox(
  List<GroupOrder> orders,
  OrderInboxFilter filter,
) {
  final submittedOnly = orders.where(isGroupOrderSubmitted).toList();
  switch (filter) {
    case OrderInboxFilter.groupOrders:
    case OrderInboxFilter.all:
      return submittedOnly;
    case OrderInboxFilter.orders:
    case OrderInboxFilter.delivery:
      return const [];
  }
}

bool isGroupOrderSubmitted(GroupOrder order) {
  return order.status.trim().toLowerCase() == 'submitted';
}

int _groupOrderPriority(String status) {
  switch (status.trim().toLowerCase()) {
    case 'payment_pending':
      return 0;
    case 'locked':
      return 1;
    case 'paid':
      return 2;
    case 'open':
      return 3;
    case 'submitted':
      return 4;
    case 'cancelled':
      return 5;
    case 'expired':
      return 6;
    default:
      return 7;
  }
}
