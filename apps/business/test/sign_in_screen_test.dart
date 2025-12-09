import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:business_app/features/auth/sign_in_screen.dart';
import 'package:business_app/providers/app_providers.dart';
import 'package:business_app/state/auth_notifier.dart';

void main() {
  testWidgets('signing in updates auth state', (tester) async {
    final notifier = AuthNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authNotifierProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(home: SignInScreen()),
      ),
    );

    await tester.enterText(find.byType(TextFormField), 'staff@example.com');
    await tester.tap(find.text('Sign In'));
    await tester.pump();

    expect(notifier.isAuthenticated, isTrue);
    expect(notifier.userName, 'staff@example.com');
  });
}
