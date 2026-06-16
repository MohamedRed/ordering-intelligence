import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver_app/screens/sign_in_screen.dart';

void main() {
  testWidgets('driver sign in screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));

    expect(find.text('Driver sign in'), findsOneWidget);
    expect(find.text('Store ID'), findsOneWidget);
    expect(find.text('Phone (E.164)'), findsOneWidget);
  });
}
