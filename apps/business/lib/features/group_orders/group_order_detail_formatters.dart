import '../../models/group_order.dart';

String formatGroupOrderCents(int cents) {
  if (cents == 0) return '—';
  final value = (cents / 100).toStringAsFixed(2);
  return '\$$value';
}

String formatGroupOrderDate(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$mm-$dd $hh:$min';
}

String joinCodeForGroupOrder(GroupOrder order) {
  return order.joinCode.isNotEmpty ? order.joinCode : order.id;
}
