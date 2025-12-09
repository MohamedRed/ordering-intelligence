import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/auth_notifier.dart';

final authNotifierProvider = ChangeNotifierProvider<AuthNotifier>((ref) {
  return AuthNotifier();
});
