String effectiveStoreId() {
  // For web demos, allow overriding the store context via query param so the app can be embedded and switched.
  final base = Uri.base;
  final qp =
      base.queryParameters['storeId'] ?? base.queryParameters['store_id'];
  if (qp != null && qp.trim().isNotEmpty) return qp.trim();
  // If using hash routing, query params can live inside the fragment: "#/orders?storeId=..."
  final frag = base.fragment;
  final qIndex = frag.indexOf('?');
  if (qIndex >= 0 && qIndex + 1 < frag.length) {
    try {
      final qs = frag.substring(qIndex + 1);
      final qp2 = Uri.splitQueryString(qs);
      final v = qp2['storeId'] ?? qp2['store_id'];
      if (v != null && v.trim().isNotEmpty) return v.trim();
    } catch (_) {
      // ignore
    }
  }
  return const String.fromEnvironment('STORE_ID', defaultValue: 'demo-store');
}
