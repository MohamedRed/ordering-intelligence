import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:go_router/go_router.dart';

import '../../models/order.dart';
import '../../models/group_order.dart';
import '../../providers/order_providers.dart';
import '../../providers/group_order_providers.dart';
import '../../providers/highlight_provider.dart';
import '../../providers/offline_badge_provider.dart';
import '../../providers/wait_time_providers.dart';
import '../../widgets/business_scaffold.dart';
import '../../fcm_token_manager.dart';
import '../../notification_service.dart';
import 'inbox/order_inbox_body.dart';
import 'inbox/order_inbox_filters.dart';
import 'inbox/order_inbox_utils.dart';
import 'inbox/order_list_states.dart';

class OrderListScreen extends ConsumerStatefulWidget {
  const OrderListScreen({
    super.key,
    this.title,
    this.fulfillmentFilter,
  });

  final String? title;
  final String? fulfillmentFilter;

  @override
  ConsumerState<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends ConsumerState<OrderListScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  final ScrollController _scrollController = ScrollController();
  late final ProviderSubscription<String?> _navSub;
  late final ProviderSubscription<AsyncValue<String?>> _tokenSub;
  String _deliveryStatusFilter = 'all';
  late OrderInboxFilter _filter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _filter = _defaultFilter();

    _navSub = ref.listenManual<String?>(
      pendingOrderNavigationProvider,
      (prev, next) {
        if (next != null && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _goToOrderDetail(next);
            ref.read(pendingOrderNavigationProvider.notifier).state = null;
          });
        }
      },
    );
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _handleDeeplink(message);
      }
    });
    final tappedPayload = NotificationService.instance.takePayload();
    if (tappedPayload != null) {
      ref.read(pendingOrderNavigationProvider.notifier).state = tappedPayload;
      ref.read(highlightedOrderIdProvider.notifier).state = tappedPayload;
    }
    FirebaseMessaging.onMessage.listen((message) {
      ref.invalidate(ordersProvider);
      final orderId = message.data['orderId'];
      if (orderId != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order $orderId updated')),
        );
        ref.read(highlightedOrderIdProvider.notifier).state = orderId;
      }
    });
    FirebaseMessaging.onMessageOpenedApp.listen(_handleDeeplink);
    _tokenSub = ref.listenManual<AsyncValue<String?>>(
      fcmTokenProvider,
      (prev, next) {
        final token = next.asData?.value;
        if (token != null) {
          registerTokenWithBackend(token);
        }
      },
      fireImmediately: true,
    );
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _flushPending());
  }

  @override
  void didUpdateWidget(covariant OrderListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fulfillmentFilter != widget.fulfillmentFilter) {
      setState(() => _filter = _defaultFilter());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navSub.close();
    _tokenSub.close();
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _flushPending();
    }
  }

  OrderInboxFilter _defaultFilter() {
    final fulfillment = widget.fulfillmentFilter?.toLowerCase().trim();
    if (fulfillment == 'delivery') {
      return OrderInboxFilter.delivery;
    }
    return OrderInboxFilter.all;
  }

  bool get _lockFilter =>
      widget.fulfillmentFilter?.toLowerCase().trim() == 'delivery';

  List<OrderInboxFilter> get _availableFilters {
    if (_lockFilter) return [OrderInboxFilter.delivery];
    return const [
      OrderInboxFilter.all,
      OrderInboxFilter.orders,
      OrderInboxFilter.groupOrders,
      OrderInboxFilter.delivery,
    ];
  }

  void _handleDeeplink(RemoteMessage message) {
    final orderId = message.data['orderId'];
    if (orderId != null) {
      ref.read(highlightedOrderIdProvider.notifier).state = orderId;
      ref.read(pendingOrderNavigationProvider.notifier).state = orderId;
      ref.invalidate(ordersProvider);
    }
  }

  Future<void> _flushPending() async {
    final repo = ref.read(orderRepositoryProvider);
    try {
      await repo.flushPending();
      ref.invalidate(ordersProvider);
    } catch (_) {
      // swallow; badge will still show pending
    }
  }

  Future<void> _refreshAll() async {
    ref.invalidate(waitTimeSummaryProvider);
    ref.invalidate(ordersProvider);
    ref.invalidate(groupOrdersProvider);
  }

  void _goToOrderDetail(String orderId) {
    if (!mounted) return;
    context.push('/orders/$orderId');
  }

  void _scrollToHighlight(List<Order> orders, String orderId) {
    final index = orders.indexWhere((o) => o.id == orderId);
    if (index >= 0 && _scrollController.hasClients) {
      _scrollController.animateTo(
        index * 120.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Map<OrderInboxFilter, int> _buildFilterCounts({
    required List<Order> orders,
    required List<GroupOrder> groupOrders,
  }) {
    final deliveryCount = orders
        .where((order) =>
            order.fulfillmentType.toLowerCase().trim() == 'delivery')
        .length;
    final submittedGroupOrders =
        groupOrders.where(isGroupOrderSubmitted).toList();
    return {
      OrderInboxFilter.all: orders.length + submittedGroupOrders.length,
      OrderInboxFilter.orders: orders.length,
      OrderInboxFilter.groupOrders: submittedGroupOrders.length,
      OrderInboxFilter.delivery: deliveryCount,
    };
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersProvider);
    final groupOrdersAsync = ref.watch(groupOrdersProvider);
    final highlight = ref.watch(highlightedOrderIdProvider);
    final filter = _lockFilter ? OrderInboxFilter.delivery : _filter;

    final orders = ordersAsync.value ?? const <Order>[];
    final groupOrders = groupOrdersAsync.value ?? const <GroupOrder>[];
    final ordersError = ordersAsync.hasError ? ordersAsync.error : null;
    final groupOrdersError =
        groupOrdersAsync.hasError ? groupOrdersAsync.error : null;

    final isLoading = (ordersAsync.isLoading && ordersAsync.value == null) &&
        (groupOrdersAsync.isLoading && groupOrdersAsync.value == null);
    if (isLoading) {
      return BusinessScaffold(
        title: Text(widget.title ?? 'Order Inbox'),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (ordersError != null &&
        groupOrdersError != null &&
        orders.isEmpty &&
        groupOrders.isEmpty) {
      return BusinessScaffold(
        title: Text(widget.title ?? 'Order Inbox'),
        body: OrderListErrorState(
          message: 'Failed to load inbox',
          detail: '$ordersError\n$groupOrdersError',
          onRetry: () => _refreshAll(),
        ),
      );
    }

    final filteredOrders =
        filterOrdersForInbox(orders, filter, _deliveryStatusFilter);
    if (highlight != null &&
        (filter == OrderInboxFilter.orders ||
            filter == OrderInboxFilter.delivery)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToHighlight(filteredOrders, highlight);
      });
    }

    return BusinessScaffold(
      title: Text(widget.title ?? 'Order Inbox'),
      actions: [
        Consumer(builder: (context, ref, _) {
          final pending = ref.watch(pendingStatusCountProvider).maybeWhen(
                data: (count) => count,
                orElse: () => 0,
              );
          if (pending == 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: ShadBadge(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              backgroundColor: Colors.orange,
              child: Text('$pending pending'),
            ),
          );
        }),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _refreshAll(),
        )
      ],
      body: OrderInboxBody(
        orders: orders,
        groupOrders: groupOrders,
        ordersError: ordersError,
        groupOrdersError: groupOrdersError,
        filter: filter,
        availableFilters: _availableFilters,
        filterCounts: _buildFilterCounts(
          orders: orders,
          groupOrders: groupOrders,
        ),
        showFilters: !_lockFilter,
        onFilterChanged: (next) => setState(() => _filter = next),
        deliveryStatusFilter: _deliveryStatusFilter,
        onDeliveryStatusChanged: (value) =>
            setState(() => _deliveryStatusFilter = value),
        scrollController: _scrollController,
        highlightedOrderId: highlight,
        onRefresh: _refreshAll,
      ),
    );
  }
}
