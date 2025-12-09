import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:admin_app/features/auth/admin_sign_in_screen.dart';
import 'package:admin_app/providers/admin_providers.dart';
import 'package:admin_app/state/admin_auth_notifier.dart';

void main() {
  testWidgets('admin sign in toggles auth state', (tester) async {
    final notifier = AdminAuthNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [adminAuthProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(home: AdminSignInScreen()),
      ),
    );

    await tester.tap(find.text('Enter Admin Console'));
    await tester.pump();

    expect(notifier.isAuthenticated, isTrue);
  });
}
