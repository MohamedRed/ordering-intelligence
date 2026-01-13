import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../providers/admin_providers.dart';

class AdminSignInScreen extends ConsumerStatefulWidget {
  const AdminSignInScreen({super.key});

  @override
  ConsumerState<AdminSignInScreen> createState() => _AdminSignInScreenState();
}

class _AdminSignInScreenState extends ConsumerState<AdminSignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Prefill to speed up testing; can be overridden via --dart-define.
    _emailCtrl.text =
        const String.fromEnvironment('ADMIN_PREFILL_EMAIL', defaultValue: 'admin-tester@example.com');
    _passCtrl.text =
        const String.fromEnvironment('ADMIN_PREFILL_PASSWORD', defaultValue: 'Temp#2025!');
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adminAuthProvider).signIn(
            email: _emailCtrl.text.trim(),
            password: _passCtrl.text,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(adminAuthProvider);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ShadCard(
              padding: const EdgeInsets.all(22),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Admin Console',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in to manage alerts, ingestion, and tenants',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 18),
                    ShadInputFormField(
                      controller: _emailCtrl,
                      label: const Text('Email'),
                      placeholder: const Text('admin@example.com'),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      validator: (v) => v.isEmpty ? 'Email required' : null,
                    ),
                    const SizedBox(height: 12),
                    ShadInputFormField(
                      controller: _passCtrl,
                      label: const Text('Password'),
                      placeholder: const Text('••••••••'),
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      validator: (v) => v.isEmpty ? 'Password required' : null,
                    ),
                    const SizedBox(height: 12),
                    if (_error != null || auth.error != null)
                      ShadAlert.destructive(
                        title: const Text('Sign-in failed'),
                        description: Text(_error ?? auth.error!),
                      ),
                    const SizedBox(height: 14),
                    ShadButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
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
