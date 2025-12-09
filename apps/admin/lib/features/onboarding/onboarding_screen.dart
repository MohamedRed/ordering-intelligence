import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/tenant_providers.dart';
import '../../widgets/admin_navigation_drawer.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _primaryCtrl = TextEditingController();
  final _storeIdCtrl = TextEditingController();
  final _timezoneCtrl = TextEditingController(text: 'America/New_York');
  final _phoneCtrl = TextEditingController();
  String _businessType = 'fast_food';
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _primaryCtrl.dispose();
    _storeIdCtrl.dispose();
    _timezoneCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      final api = ref.read(tenantApiProvider);
      final tenant = await api.createTenant(
        name: _nameCtrl.text.trim(),
        primaryUser: _primaryCtrl.text.trim(),
        storeId: _storeIdCtrl.text.trim(),
        businessType: _businessType,
        timezone: _timezoneCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      );
      setState(() {
        _success = 'Created ${tenant.name} (${tenant.storeId})';
      });
      _formKey.currentState!.reset();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Onboard Business')),
      drawer: const AdminNavigationDrawer(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('New Store', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Business name'),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  TextFormField(
                    controller: _storeIdCtrl,
                    decoration: const InputDecoration(labelText: 'Store ID (slug)'),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _businessType,
                    items: const [
                      DropdownMenuItem(value: 'fast_food', child: Text('Fast Food')),
                      DropdownMenuItem(value: 'auto_parts', child: Text('Auto Parts')),
                    ],
                    onChanged: (v) => setState(() => _businessType = v ?? 'fast_food'),
                    decoration: const InputDecoration(labelText: 'Business type'),
                  ),
                  TextFormField(
                    controller: _timezoneCtrl,
                    decoration: const InputDecoration(labelText: 'Timezone (IANA, e.g., America/New_York)'),
                  ),
                    TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Store phone'),
                  ),
                  TextFormField(
                    controller: _primaryCtrl,
                    decoration: const InputDecoration(labelText: 'Primary admin email'),
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  if (_success != null)
                    Text(_success!, style: const TextStyle(color: Colors.green)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _submit,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: const Text('Create'),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
