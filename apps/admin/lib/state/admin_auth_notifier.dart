import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AdminAuthNotifier extends ChangeNotifier {
  final FirebaseAuth _auth;
  StreamSubscription<User?>? _sub;

  bool _isAuthenticated = false;
  String? _email;
  String? _error;
  bool _loading = true;

  bool get isAuthenticated => _isAuthenticated;
  String? get email => _email;
  String? get error => _error;
  bool get loading => _loading;

  AdminAuthNotifier({FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance {
    _sub = _auth.authStateChanges().listen((user) {
      _isAuthenticated = user != null;
      _email = user?.email;
      _loading = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> signIn({required String email, required String password}) async {
    _error = null;
    notifyListeners();
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        _error = 'No admin user found for that email.';
      } else if (e.code == 'wrong-password') {
        _error = 'Incorrect password.';
      } else {
        _error = e.message ?? e.code;
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _error = null;
    _email = null;
    _isAuthenticated = false;
    notifyListeners();
  }
}
