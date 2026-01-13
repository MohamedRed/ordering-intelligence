import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';

import '../../models/tv_pairing_handoff.dart';
import '../../services/tv_pairing_service.dart';

class TvPairingLinkScreen extends StatefulWidget {
  const TvPairingLinkScreen({
    super.key,
    required this.session,
    required this.handoff,
    required this.service,
    this.onLinked,
  });

  final SessionInfo session;
  final TvPairingHandoff handoff;
  final TvPairingService service;
  final VoidCallback? onLinked;

  @override
  State<TvPairingLinkScreen> createState() => _TvPairingLinkScreenState();
}

class _TvPairingLinkScreenState extends State<TvPairingLinkScreen> {
  late final TextEditingController _codeController;
  late final TextEditingController _pairingIdController;
  bool _submitting = false;
  bool _linked = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.handoff.code);
    _pairingIdController = TextEditingController(
      text: widget.handoff.pairingId ?? '',
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    _pairingIdController.dispose();
    super.dispose();
  }

  Future<void> _linkTv() async {
    final code = _codeController.text.trim();
    final pairingId = _pairingIdController.text.trim();
    if (code.isEmpty && pairingId.isEmpty) {
      setState(() {
        _error = 'Enter the pairing code or pairing ID shown on the TV.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final response = await widget.service.completePairing(
        pairingId: pairingId.isEmpty ? null : pairingId,
        code: code.isEmpty ? null : code,
        sessionId: widget.session.sessionId,
      );
      if (!mounted) return;
      if (!response.isLinked) {
        setState(() {
          _error = 'Pairing is not complete yet. Please try again.';
          _submitting = false;
        });
        return;
      }
      setState(() {
        _linked = true;
        _submitting = false;
      });
      widget.onLinked?.call();
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Link your TV')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _linked ? _successState() : _formState(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Enter the code shown on your TV screen to link this device.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Pairing code',
            hintText: '6-digit code',
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pairingIdController,
          decoration: const InputDecoration(
            labelText: 'Pairing ID (optional)',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitting ? null : _linkTv,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Link TV'),
          ),
        ),
      ],
    );
  }

  Widget _successState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 48),
        const SizedBox(height: 12),
        const Text(
          'TV linked successfully.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        const Text(
          'You can continue on your TV now.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
