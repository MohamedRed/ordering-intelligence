import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/channel_route.dart';
import '../../providers/channel_route_providers.dart';
import '../../widgets/admin_scaffold.dart';
import '../../widgets/shad_snackbar.dart';

class ChannelRoutesScreen extends ConsumerStatefulWidget {
  const ChannelRoutesScreen({super.key});

  @override
  ConsumerState<ChannelRoutesScreen> createState() =>
      _ChannelRoutesScreenState();
}

class _ChannelRoutesScreenState extends ConsumerState<ChannelRoutesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accountIdCtrl = TextEditingController();
  final _tenantIdCtrl = TextEditingController();
  final _storeIdCtrl = TextEditingController();
  final _businessTypeCtrl = TextEditingController(text: 'fast_food');
  final _agentIdCtrl = TextEditingController();
  String _channel = 'telegram';
  ChannelRoute? _editing;

  @override
  void dispose() {
    _accountIdCtrl.dispose();
    _tenantIdCtrl.dispose();
    _storeIdCtrl.dispose();
    _businessTypeCtrl.dispose();
    _agentIdCtrl.dispose();
    super.dispose();
  }

  void _resetForm() {
    setState(() {
      _editing = null;
      _channel = 'telegram';
    });
    _accountIdCtrl.clear();
    _tenantIdCtrl.clear();
    _storeIdCtrl.clear();
    _businessTypeCtrl.text = 'fast_food';
    _agentIdCtrl.clear();
  }

  void _prefill(ChannelRoute route) {
    setState(() {
      _editing = route;
      _channel = route.channel.isNotEmpty ? route.channel : 'telegram';
    });
    _accountIdCtrl.text = route.accountId;
    _tenantIdCtrl.text = route.tenantId;
    _storeIdCtrl.text = route.storeId;
    _businessTypeCtrl.text = route.businessType;
    _agentIdCtrl.text = route.agentId;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final route = ChannelRoute(
      id: _editing?.id ?? '',
      channel: _channel,
      accountId: _accountIdCtrl.text.trim(),
      tenantId: _tenantIdCtrl.text.trim(),
      storeId: _storeIdCtrl.text.trim(),
      businessType: _businessTypeCtrl.text.trim(),
      agentId: _agentIdCtrl.text.trim(),
    );
    try {
      await ref.read(channelRouteApiProvider).upsert(route);
      ref.invalidate(channelRoutesProvider);
      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Channel route saved',
        message: 'Routing updated for ${route.channel} / ${route.accountId}.',
        type: ShadSnackType.success,
      );
      _resetForm();
    } catch (err) {
      if (!mounted) return;
      showShadSnack(
        context,
        title: 'Failed to save route',
        message: '$err',
        type: ShadSnackType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final routesAsync = ref.watch(channelRoutesProvider);
    return AdminScaffold(
      title: const Text('Channels'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(channelRoutesProvider),
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShadCard(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _editing == null
                          ? 'Create channel route'
                          : 'Update channel route',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _channel,
                      decoration: const InputDecoration(
                        labelText: 'Channel',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'telegram',
                          child: Text('Telegram'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _channel = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    ShadInputFormField(
                      controller: _accountIdCtrl,
                      label: const Text('Account ID'),
                      placeholder: const Text('e.g. 8522756388'),
                      validator: (v) =>
                          v.trim().isEmpty ? 'Account ID is required' : null,
                    ),
                    const SizedBox(height: 12),
                    ShadInputFormField(
                      controller: _tenantIdCtrl,
                      label: const Text('Tenant ID (optional)'),
                      placeholder: const Text('e.g. dev'),
                    ),
                    const SizedBox(height: 12),
                    ShadInputFormField(
                      controller: _storeIdCtrl,
                      label: const Text('Store ID (optional)'),
                      placeholder: const Text('e.g. fwencheese-demo-...'),
                    ),
                    const SizedBox(height: 12),
                    ShadInputFormField(
                      controller: _businessTypeCtrl,
                      label: const Text('Business type'),
                      placeholder: const Text('fast_food'),
                    ),
                    const SizedBox(height: 12),
                    ShadInputFormField(
                      controller: _agentIdCtrl,
                      label: const Text('ElevenLabs Agent ID'),
                      placeholder: const Text('agent_...'),
                      validator: (v) =>
                          v.trim().isEmpty ? 'Agent ID is required' : null,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        ShadButton.outline(
                          onPressed: _editing == null ? null : _resetForm,
                          child: const Text('Clear'),
                        ),
                        ShadButton(
                          onPressed: _submit,
                          child: Text(
                              _editing == null ? 'Save route' : 'Update route'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: routesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(
                  child: ShadAlert.destructive(
                    title: const Text('Failed to load routes'),
                    description: Text('$err'),
                  ),
                ),
                data: (routes) {
                  if (routes.isEmpty) {
                    return const Center(child: Text('No channel routes yet.'));
                  }
                  return ListView.separated(
                    itemCount: routes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final route = routes[index];
                      return ShadCard(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${route.channel} • ${route.accountId}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('Tenant: ${route.tenantId}'),
                                  Text('Store: ${route.storeId}'),
                                  Text('Business: ${route.businessType}'),
                                  Text('Agent: ${route.agentId}'),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            ShadButton.outline(
                              onPressed: () => _prefill(route),
                              child: const Text('Edit'),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
