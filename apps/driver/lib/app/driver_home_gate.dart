import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/driver_home_screen.dart';
import '../screens/marketplace_home_screen.dart';
import '../screens/sign_in_screen.dart';
import '../services/store_prefs.dart';

class DriverHomeGate extends StatelessWidget {
  const DriverHomeGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == null) {
          return const SignInScreen();
        }
        final mode = StorePrefs.instance.mode();
        if (mode == 'marketplace') {
          return const MarketplaceHomeScreen();
        }
        return const DriverHomeScreen();
      },
    );
  }
}
