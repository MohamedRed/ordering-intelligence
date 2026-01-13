import 'package:flutter/material.dart';

import '../../../models/group_order.dart';
import '../../../models/order.dart';
import '../../../widgets/push_banner.dart';
import '../../group_orders/group_order_card.dart';
import 'order_delivery_summary.dart';
import 'order_inbox_filters.dart';
import 'order_inbox_section_header.dart';
import 'order_inbox_utils.dart';
import 'order_list_card.dart';
import 'order_list_states.dart';
import 'order_wait_time_card.dart';

class OrderInboxBody extends StatelessWidget {
  const OrderInboxBody({
    super.key,
    required this.orders,
    required this.groupOrders,
    required this.ordersError,
    required this.groupOrdersError,
    required this.filter,
    required this.availableFilters,
    required this.filterCounts,
    required this.showFilters,
    required this.onFilterChanged,
    required this.deliveryStatusFilter,
    required this.onDeliveryStatusChanged,
    required this.scrollController,
    required this.highlightedOrderId,
    required this.onRefresh,
  });

  final List<Order> orders;
  final List<GroupOrder> groupOrders;
  final Object? ordersError;
  final Object? groupOrdersError;
  final OrderInboxFilter filter;
  final List<OrderInboxFilter> availableFilters;
  final Map<OrderInboxFilter, int> filterCounts;
  final bool showFilters;
  final ValueChanged<OrderInboxFilter> onFilterChanged;
  final String deliveryStatusFilter;
  final ValueChanged<String> onDeliveryStatusChanged;
  final ScrollController scrollController;
  final String? highlightedOrderId;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final showGroupOrders =
        filter == OrderInboxFilter.all || filter == OrderInboxFilter.groupOrders;
    final showOrders = filter == OrderInboxFilter.all ||
        filter == OrderInboxFilter.orders ||
        filter == OrderInboxFilter.delivery;

    final filteredOrders =
        filterOrdersForInbox(orders, filter, deliveryStatusFilter);
    final filteredGroupOrders = filterGroupOrdersForInbox(groupOrders, filter);
    final sortedGroupOrders = sortGroupOrdersForInbox(filteredGroupOrders);

    if (filter == OrderInboxFilter.orders ||
        filter == OrderInboxFilter.delivery) {
      if (ordersError != null && filteredOrders.isEmpty) {
        return OrderListErrorState(
          message: 'Failed to load orders',
          detail: '$ordersError',
          onRetry: () => onRefresh(),
        );
      }
      if (filteredOrders.isEmpty) {
        return OrderListEmptyState(
          title: filter == OrderInboxFilter.delivery
              ? 'No delivery orders'
              : 'No orders yet',
          message: filter == OrderInboxFilter.delivery
              ? 'There are no delivery orders yet for this store.'
              : 'New orders will appear here as soon as customers place them.',
          onRefresh: () => onRefresh(),
        );
      }
    }

    if (filter == OrderInboxFilter.groupOrders) {
      if (groupOrdersError != null && sortedGroupOrders.isEmpty) {
        return OrderListErrorState(
          message: 'Failed to load group orders',
          detail: '$groupOrdersError',
          onRetry: () => onRefresh(),
        );
      }
      if (sortedGroupOrders.isEmpty) {
        return OrderListEmptyState(
          title: 'No group orders yet',
          message: 'Group orders will appear here once customers submit them.',
          onRefresh: () => onRefresh(),
          icon: Icons.groups_outlined,
        );
      }
    }

    if (filter == OrderInboxFilter.all &&
        filteredOrders.isEmpty &&
        sortedGroupOrders.isEmpty &&
        ordersError == null &&
        groupOrdersError == null) {
      return OrderListEmptyState(
        title: 'No orders yet',
        message: 'New orders will appear here as soon as customers place them.',
        onRefresh: () => onRefresh(),
      );
    }

    final children = <Widget>[];

    if (showFilters) {
      if (filter == OrderInboxFilter.all ||
          filter == OrderInboxFilter.orders) {
        children.add(const PushBanner());
        children.add(const SizedBox(height: 12));
        children.add(const OrderWaitTimeDashboardCard());
        children.add(const SizedBox(height: 12));
      }
      children.add(OrderInboxFilterBar(
        filter: filter,
        onChanged: onFilterChanged,
        availableFilters: availableFilters,
        counts: filterCounts,
      ));
      children.add(const SizedBox(height: 12));
    }

    if (filter == OrderInboxFilter.delivery) {
      children.add(OrderDeliverySummary(orders: filteredOrders));
      children.add(const SizedBox(height: 10));
      children.add(DeliveryStatusChips(
        selected: deliveryStatusFilter,
        onSelected: onDeliveryStatusChanged,
      ));
      children.add(const SizedBox(height: 12));
    }

    if (showGroupOrders) {
      if (groupOrdersError != null && sortedGroupOrders.isEmpty) {
        children.add(_inlineErrorCard(
          title: 'Failed to load group orders',
          detail: '$groupOrdersError',
        ));
      } else if (sortedGroupOrders.isNotEmpty) {
        children.add(OrderInboxSectionHeader(
          title: 'Group orders',
          count: sortedGroupOrders.length,
        ));
        children.add(const SizedBox(height: 8));
        children.addAll(_buildGroupOrderCards(sortedGroupOrders));
        children.add(const SizedBox(height: 16));
      }
    }

    if (showOrders) {
      if (ordersError != null && filteredOrders.isEmpty) {
        children.add(_inlineErrorCard(
          title: 'Failed to load orders',
          detail: '$ordersError',
        ));
      } else if (filteredOrders.isNotEmpty) {
        children.add(OrderInboxSectionHeader(
          title: filter == OrderInboxFilter.delivery ? 'Delivery orders' : 'Orders',
          count: filteredOrders.length,
        ));
        children.add(const SizedBox(height: 8));
        children.addAll(
          _buildOrderCards(filteredOrders, highlightedOrderId),
        );
      }
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        controller: scrollController,
        children: children,
      ),
    );
  }

  List<Widget> _buildOrderCards(List<Order> orders, String? highlightedId) {
    return orders
        .map((order) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OrderCard(
                order: order,
                highlighted: highlightedId != null && order.id == highlightedId,
              ),
            ))
        .toList();
  }

  List<Widget> _buildGroupOrderCards(List<GroupOrder> orders) {
    return orders
        .map((order) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GroupOrderCard(groupOrder: order),
            ))
        .toList();
  }

  Widget _inlineErrorCard({required String title, required String detail}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            detail,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.red.shade700),
          ),
        ],
      ),
    );
  }

}
