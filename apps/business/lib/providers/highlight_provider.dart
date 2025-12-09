import 'package:flutter_riverpod/flutter_riverpod.dart';

// Tracks the orderId to highlight in list.
final highlightedOrderIdProvider = StateProvider<String?>((ref) => null);

// Tracks an orderId that should open the detail screen (e.g., from a push tap).
final pendingOrderNavigationProvider = StateProvider<String?>((ref) => null);
