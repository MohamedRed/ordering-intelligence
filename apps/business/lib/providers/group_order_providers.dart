import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group_order.dart';
import 'group_order_api.dart';

final groupOrderRepositoryProvider = Provider<GroupOrderRepository>((ref) {
  return GroupOrderRepository();
});

final groupOrdersProvider = FutureProvider<List<GroupOrder>>((ref) async {
  final repo = ref.watch(groupOrderRepositoryProvider);
  return repo.fetchGroupOrders();
});

final groupOrderDetailProvider =
    FutureProvider.family<GroupOrder, String>((ref, groupOrderId) async {
  final repo = ref.watch(groupOrderRepositoryProvider);
  return repo.fetchGroupOrder(groupOrderId);
});

class GroupOrderRepository {
  final GroupOrderApi _api;
  GroupOrderRepository({GroupOrderApi? api}) : _api = api ?? GroupOrderApi();

  Future<List<GroupOrder>> fetchGroupOrders() =>
      _api.listGroupOrders(status: 'submitted');

  Future<GroupOrder> fetchGroupOrder(String groupOrderId) =>
      _api.fetchGroupOrder(groupOrderId);

  Future<GroupOrderRefundResult> refundGroupOrder(
    String groupOrderId, {
    int? amountCents,
    String? reason,
    String? note,
    String? participantId,
    String? paymentId,
  }) {
    return _api.refundGroupOrder(
      groupOrderId,
      amountCents: amountCents,
      reason: reason,
      note: note,
      participantId: participantId,
      paymentId: paymentId,
    );
  }
}
