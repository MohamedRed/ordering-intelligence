import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';

import '../../models/reorder_handoff.dart';
import '../home/payment_method_dialog.dart';
import '../home/reorder_flow.dart';

class HandoffReorderScreen extends StatefulWidget {
  const HandoffReorderScreen({
    super.key,
    required this.session,
    required this.api,
    required this.handoff,
  });

  final SessionInfo session;
  final ChannelGatewayApi api;
  final ReorderHandoff handoff;

  @override
  State<HandoffReorderScreen> createState() => _HandoffReorderScreenState();
}

class _HandoffReorderScreenState extends State<HandoffReorderScreen> {
  StoreChoice? _store;
  bool _loadingStore = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStore();
  }

  Future<void> _loadStore() async {
    if (widget.handoff.storeId.isEmpty) return;
    setState(() => _loadingStore = true);
    try {
      final store = await widget.api.fetchStoreDetails(widget.handoff.storeId);
      if (!mounted) return;
      setState(() => _store = store);
    } catch (_) {
      // Store details are optional for handoff; continue without them.
    } finally {
      if (mounted) setState(() => _loadingStore = false);
    }
  }

  Future<void> _confirmReorder() async {
    final paymentMethod = await showPaymentMethodDialog(
      context,
      allowCash: true,
    );
    if (paymentMethod == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final flow = ReorderFlow(api: widget.api, session: widget.session);
      final order = widget.handoff.toRecommendedOrder(store: _store);
      await flow.placeReorder(order: order, paymentMethod: paymentMethod);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order placed.')),
      );
      Navigator.of(context).pop();
    } catch (err) {
      if (!mounted) return;
      setState(() => _error = err.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeName = _store?.name ?? widget.handoff.storeId;
    final title = widget.handoff.title.isNotEmpty
        ? widget.handoff.title
        : 'Reorder from watch';
    return Scaffold(
      appBar: AppBar(title: const Text('Watch reorder')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(storeName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_loadingStore) const LinearProgressIndicator(),
            Text(
              '${widget.handoff.itemCount} item(s)',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _confirmReorder,
                child: Text(_submitting ? 'Placing order...' : 'Continue'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
