import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../providers/app_providers.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController(text: 'demo@restaurant.com');
  final _passCtrl = TextEditingController(text: 'password123');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ShadCard(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Welcome back',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in to manage orders and menu',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 18),
                    ShadInputFormField(
                      controller: _emailCtrl,
                      label: const Text('Email'),
                      placeholder: const Text('demo@restaurant.com'),
                      validator: (value) => value.isEmpty
                          ? 'Enter your email'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    ShadInputFormField(
                      controller: _passCtrl,
                      label: const Text('Password'),
                      placeholder: const Text('••••••••'),
                      obscureText: true,
                      validator: (value) => value.isEmpty
                          ? 'Enter password'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    if (_error != null)
                      ShadAlert.destructive(
                        title: const Text('Sign-in failed'),
                        description: Text(_error!),
                      ),
                    const SizedBox(height: 14),
                    ShadButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              if (!_formKey.currentState!.validate()) return;
                              setState(() {
                                _busy = true;
                                _error = null;
                              });
                              try {
                                await ref
                                    .read(authNotifierProvider)
                                    .signInEmailPassword(
                                      email: _emailCtrl.text.trim(),
                                      password: _passCtrl.text,
                                    );
                              } catch (e) {
                                setState(() => _error = e.toString());
                              } finally {
                                if (mounted) {
                                  setState(() => _busy = false);
                                }
                              }
                            },
                      child: _busy
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign In'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
