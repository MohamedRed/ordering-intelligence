import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../providers/order_detail_provider.dart';
import '../../widgets/business_scaffold.dart';
import 'order_detail_body.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderDetailProvider(orderId));
    return BusinessScaffold(
      title: Text('Order $orderId'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.refresh(orderDetailProvider(orderId)),
        ),
      ],
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ShadAlert.destructive(
          title: const Text('Failed to load order'),
          description: Text('$err'),
        ),
        data: (order) => OrderDetailBody(order: order),
      ),
    );
  }
}
