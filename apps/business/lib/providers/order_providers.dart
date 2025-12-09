import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/order.dart';
import 'order_api.dart';

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return OrderRepository();
});

final ordersProvider = FutureProvider<List<Order>>((ref) async {
  final repo = ref.watch(orderRepositoryProvider);
  return repo.fetchOrders();
});
