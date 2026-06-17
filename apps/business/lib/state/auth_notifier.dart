import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

typedef AuthSignIn = Future<void> Function({
  required String email,
  required String password,
});

typedef AuthSignOut = Future<void> Function();

class AuthNotifier extends ChangeNotifier {
  AuthNotifier({
    FirebaseAuth? firebaseAuth,
    Stream<User?>? authStateChanges,
    AuthSignIn? signIn,
    AuthSignOut? signOut,
  })  : _firebaseAuth = firebaseAuth ??
            (authStateChanges == null ? FirebaseAuth.instance : null),
        _signIn = signIn,
        _signOut = signOut {
    final auth = _firebaseAuth;
    _sub = (authStateChanges ?? auth!.authStateChanges()).listen((user) {
      _setAuthState(isAuthenticated: user != null, userName: user?.email);
    });
  }

  late final StreamSubscription<User?> _sub;
  final FirebaseAuth? _firebaseAuth;
  final AuthSignIn? _signIn;
  final AuthSignOut? _signOut;
  bool _isAuthenticated = false;
  String? _userName;

  bool get isAuthenticated => _isAuthenticated;
  String? get userName => _userName;

  Future<void> signInEmailPassword(
      {required String email, required String password}) async {
    final handler = _signIn;
    if (handler != null) {
      await handler(email: email, password: password);
      _setAuthState(isAuthenticated: true, userName: email);
      return;
    }
    await _firebaseAuth!
        .signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    final handler = _signOut;
    if (handler != null) {
      await handler();
      _setAuthState(isAuthenticated: false, userName: null);
      return;
    }
    await _firebaseAuth!.signOut();
  }

  void _setAuthState(
      {required bool isAuthenticated, required String? userName}) {
    _isAuthenticated = isAuthenticated;
    _userName = userName;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
