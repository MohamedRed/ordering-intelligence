import 'package:flutter_test/flutter_test.dart';

import 'package:admin_app/features/auth/admin_sign_in_screen.dart';
import 'package:admin_app/providers/admin_providers.dart';
import 'package:admin_app/state/admin_auth_notifier.dart';

import 'test_harness.dart';

void main() {
  testWidgets('admin sign in toggles auth state', (tester) async {
    final notifier = AdminAuthNotifier.testing();

    await tester.pumpWidget(
      adminTestApp(
        const AdminSignInScreen(),
        overrides: [adminAuthProvider.overrideWith((ref) => notifier)],
      ),
    );

    await tester.tap(find.text('Sign in'));
    await tester.pump();

    expect(notifier.isAuthenticated, isTrue);
  });
}
