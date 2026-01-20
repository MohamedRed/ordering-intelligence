import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/admin_app.dart';
import 'bootstrap/ci_semantics.dart';
import 'bootstrap/https_pins.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  enableCiSemantics();
  enforcePinnedCertificates();
  await Firebase.initializeApp(options: firebaseOptions);
  runApp(const ProviderScope(child: AdminApp()));
}
