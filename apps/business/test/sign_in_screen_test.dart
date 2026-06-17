import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:business_app/features/auth/sign_in_screen.dart';
import 'package:business_app/providers/app_providers.dart';
import 'package:business_app/state/auth_notifier.dart';

import 'test_harness.dart';

void main() {
  testWidgets('signing in updates auth state', (tester) async {
    final notifier = AuthNotifier(
      authStateChanges: const Stream.empty(),
      signIn: ({required email, required password}) async {
        expect(email, 'staff@example.com');
        expect(password, 'secure-pass');
      },
    );

    await tester.pumpWidget(
      businessTestApp(
        const SignInScreen(),
        overrides: [authNotifierProvider.overrideWith((ref) => notifier)],
      ),
    );

    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'staff@example.com');
    await tester.enterText(fields.at(1), 'secure-pass');
    await tester.tap(find.text('Sign In'));
    await tester.pump();

    expect(notifier.isAuthenticated, isTrue);
    expect(notifier.userName, 'staff@example.com');
  });
}
