import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/driver_app.dart';
import 'bootstrap/ci_semantics.dart';
import 'firebase_options.dart';
import 'services/store_prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  enableCiSemantics();
  await Firebase.initializeApp(options: firebaseOptions);
  await StorePrefs.instance.load();
  runApp(const DriverApp());
}
