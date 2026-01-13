import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthNotifier extends ChangeNotifier {
  AuthNotifier() {
    _sub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _isAuthenticated = user != null;
      _userName = user?.email;
      notifyListeners();
    });
  }

  late final StreamSubscription<User?> _sub;
  bool _isAuthenticated = false;
  String? _userName;

  bool get isAuthenticated => _isAuthenticated;
  String? get userName => _userName;

  Future<void> signInEmailPassword(
      {required String email, required String password}) async {
    await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
