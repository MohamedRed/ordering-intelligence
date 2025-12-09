import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/admin_auth_notifier.dart';

final adminAuthProvider = ChangeNotifierProvider<AdminAuthNotifier>((ref) {
  return AdminAuthNotifier();
});
