import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/dispatch_api.dart';
import '../services/store_prefs.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storeCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _busy = false;
  String? _error;
  String? _verificationId;
  int? _forceResendToken;
  ConfirmationResult? _confirmationResult;

  @override
  void initState() {
    super.initState();
    final prefs = StorePrefs.instance;
    _storeCtrl.text = prefs.storeId();
    _phoneCtrl.text = prefs.phone();
  }

  @override
  void dispose() {
    _storeCtrl.dispose();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final phone = _phoneCtrl.text.trim();
    try {
      if (kIsWeb) {
        final result =
            await FirebaseAuth.instance.signInWithPhoneNumber(phone);
        setState(() {
          _confirmationResult = result;
          _verificationId = result.verificationId;
        });
        return;
      }
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        forceResendingToken: _forceResendToken,
        verificationCompleted: (credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          await _claimDriver();
        },
        verificationFailed: (e) {
          setState(() => _error = e.message ?? 'Verification failed');
        },
        codeSent: (verificationId, forceResendingToken) {
          setState(() {
            _verificationId = verificationId;
            _forceResendToken = forceResendingToken;
          });
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_verificationId == null && _confirmationResult == null) {
      setState(() => _error = 'Request a code first');
      return;
    }
    final code = _codeCtrl.text.trim();
    if (code.length < 4) {
      setState(() => _error = 'Enter the SMS code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (kIsWeb && _confirmationResult != null) {
        await _confirmationResult!.confirm(code);
      } else {
        final credential = PhoneAuthProvider.credential(
          verificationId: _verificationId!,
          smsCode: code,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
      await _claimDriver();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claimDriver() async {
    final storeId = _storeCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    await StorePrefs.instance.setStoreId(storeId);
    await StorePrefs.instance.setPhone(phone);
    final api = DispatchDriverApi(storeId: storeId);
    await api.claimDriver(phoneE164: phone);
  }

  @override
  Widget build(BuildContext context) {
    final codeSent = _verificationId != null || _confirmationResult != null;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Driver sign in',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _storeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Store ID',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter store id'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Phone (E.164)',
                      hintText: '+15551234567',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter phone number'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  if (codeSent) ...[
                    TextFormField(
                      controller: _codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'SMS Code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : codeSent
                        ? _verifyCode
                        : _sendCode,
                    child: _busy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(codeSent ? 'Verify code' : 'Send code'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
