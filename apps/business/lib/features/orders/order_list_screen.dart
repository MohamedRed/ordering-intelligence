import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';

import '../../models/order.dart';
import '../../providers/order_providers.dart';
import '../../providers/order_api.dart';
import '../../widgets/business_drawer.dart';
import '../../fcm_token_manager.dart';
import '../../providers/offline_badge_provider.dart';
import '../../widgets/push_banner.dart';
import '../../providers/highlight_provider.dart';
import '../../notification_service.dart';
import 'order_detail_screen.dart';

class OrderListScreen extends ConsumerStatefulWidget {
  const OrderListScreen({super.key});

  @override
  ConsumerState<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends ConsumerState<OrderListScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listen<String?>(pendingOrderNavigationProvider, (_, next) {
      if (next != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _goToOrderDetail(next);
          ref.read(pendingOrderNavigationProvider.notifier).state = null;
        });
      }
    });
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
    // Listen for foreground push updates to refresh orders.
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
    // When app opened from background/tap.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleDeeplink);
    // Ensure device token is registered once per session.
    ref.listen(fcmTokenProvider, (_, next) async {
      final token = next.asData?.value;
      if (token != null) {
        await registerTokenWithBackend(token);
      }
    });
    // periodic flush of offline queue
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _flushPending());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersProvider);
    final highlight = ref.watch(highlightedOrderIdProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Inbox'),
        actions: [
          Consumer(builder: (context, ref, _) {
            final pending = ref.watch(pendingStatusCountProvider).maybeWhen(
                  data: (count) => count,
                  orElse: () => 0,
                );
            if (pending == 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Chip(
                label: Text('$pending pending'),
                backgroundColor: Colors.orange.shade100,
                labelStyle: const TextStyle(color: Colors.orange),
              ),
            );
          }),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(ordersProvider),
          )
        ],
      ),
      drawer: const BusinessDrawer(),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load orders: $err')),
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No orders yet'));
          }
          if (highlight != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToHighlight(orders, highlight);
            });
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(ordersProvider);
            },
            child: Column(
              children: [
                const PushBanner(),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    controller: _scrollController,
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      final isHighlighted =
                          highlight != null && order.id == highlight;
                      return _OrderCard(
                          order: order, highlighted: isHighlighted);
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _scrollToHighlight(List<Order> orders, String orderId) {
    final index = orders.indexWhere((o) => o.id == orderId);
    if (index >= 0 && _scrollController.hasClients) {
      _scrollController.animateTo(
        index * 120.0, // approximate card height
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToOrderDetail(String orderId) {
    if (!mounted) return;
    context.push('/orders/$orderId');
  }
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order, this.highlighted = false});
  final Order order;
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: highlighted ? Colors.yellow.shade50 : null,
      child: InkWell(
        onTap: () => context.push('/orders/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(order.title,
                      style: Theme.of(context).textTheme.titleMedium),
                  Chip(
                    label: Text(_statusLabel(order.status)),
                    backgroundColor:
                        _statusColor(order.status).withOpacity(0.12),
                    labelStyle: TextStyle(color: _statusColor(order.status)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(order.itemsSummary()),
              if (order.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(order.notes,
                    style: const TextStyle(fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(order.formattedTotal,
                      style: Theme.of(context).textTheme.titleMedium),
                  _ActionButtons(order: order, ref: ref),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.order, required this.ref});
  final Order order;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final actions = _nextActions(order.status);
    if (actions.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      children: actions
          .map((status) => OutlinedButton(
                onPressed: () => _handleStatus(context, ref, order.id, status),
                child: Text(_statusLabel(status)),
              ))
          .toList(),
    );
  }

  Future<void> _handleStatus(BuildContext context, WidgetRef ref,
      String orderId, OrderStatus status) async {
    final repo = ref.read(orderRepositoryProvider);
    try {
      await repo.setStatus(orderId, status);
      ref.invalidate(ordersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Order $orderId updated to ${_statusLabel(status)}')));
      }
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to update: $err')));
      }
    }
  }
}

Color _statusColor(OrderStatus status) {
  switch (status) {
    case OrderStatus.pending:
      return Colors.orange;
    case OrderStatus.confirmed:
      return Colors.blue;
    case OrderStatus.ready:
      return Colors.teal;
    case OrderStatus.completed:
      return Colors.green;
    case OrderStatus.cancelled:
      return Colors.grey;
  }
}

String _statusLabel(OrderStatus status) {
  switch (status) {
    case OrderStatus.pending:
      return 'Pending';
    case OrderStatus.confirmed:
      return 'Confirmed';
    case OrderStatus.ready:
      return 'Ready';
    case OrderStatus.completed:
      return 'Completed';
    case OrderStatus.cancelled:
      return 'Cancelled';
  }
}

List<OrderStatus> _nextActions(OrderStatus current) {
  switch (current) {
    case OrderStatus.pending:
      return [OrderStatus.confirmed, OrderStatus.cancelled];
    case OrderStatus.confirmed:
      return [OrderStatus.ready, OrderStatus.cancelled];
    case OrderStatus.ready:
      return [OrderStatus.completed, OrderStatus.cancelled];
    case OrderStatus.completed:
    case OrderStatus.cancelled:
      return [];
  }
}
