import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';

class SignInScaffold extends StatelessWidget {
  const SignInScaffold({
    super.key,
    required this.providers,
    required this.loading,
    required this.error,
    required this.onProviderSelected,
  });

  final List<AuthProvider> providers;
  final bool loading;
  final String? error;
  final ValueChanged<AuthProvider> onProviderSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choose a social account to continue.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              for (final provider in providers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ElevatedButton(
                    onPressed: loading ? null : () => onProviderSelected(provider),
                    child: Text('Continue with ${provider.displayLabel}'),
                  ),
                ),
              const SizedBox(height: 8),
              if (loading) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
