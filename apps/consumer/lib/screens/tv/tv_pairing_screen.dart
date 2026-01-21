import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/tv_pairing_service.dart';

class TvPairingScreen extends StatefulWidget {
  const TvPairingScreen({
    super.key,
    required this.service,
    required this.onLinked,
  });

  final TvPairingService service;
  final ValueChanged<String> onLinked;

  @override
  State<TvPairingScreen> createState() => _TvPairingScreenState();
}

class _TvPairingScreenState extends State<TvPairingScreen> {
  TvPairingStartResponse? _pairing;
  Timer? _pollTimer;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startPairing();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _startPairing() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pairing = await widget.service.startPairing(
        deviceType: _deviceType(),
        clientPlatform: _devicePlatform(),
      );
      if (!mounted) return;
      setState(() {
        _pairing = pairing;
        _loading = false;
      });
      _startPolling(pairing);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  void _startPolling(TvPairingStartResponse pairing) {
    _pollTimer?.cancel();
    final interval = pairing.pollIntervalSeconds > 0
        ? pairing.pollIntervalSeconds
        : 2;
    _pollTimer = Timer.periodic(Duration(seconds: interval), (_) async {
      await _poll(pairing.pairingId);
    });
  }

  Future<void> _poll(String pairingId) async {
    try {
      final state = await widget.service.fetchState(pairingId: pairingId);
      if (state.isLinked) {
        _pollTimer?.cancel();
        widget.onLinked(state.sessionToken);
        return;
      }
      if (state.status.toLowerCase() == 'expired') {
        _pollTimer?.cancel();
        if (!mounted) return;
        setState(() {
          _error = 'Pairing code expired. Generate a new one.';
        });
      }
    } catch (_) {
      // Ignore transient polling errors.
    }
  }

  String _deviceType() {
    if (kIsWeb) return 'tv';
    if (Platform.isAndroid) return 'android_tv';
    if (Platform.isIOS) return 'tvos';
    return 'tv';
  }

  String _devicePlatform() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'tv';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final pairing = _pairing;
    if (pairing == null) {
      return _errorState();
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Card(
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Link your TV',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Scan the QR code or enter this code in the mobile app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 24),
                if (pairing.pairUrl.isNotEmpty)
                  QrImageView(
                    data: pairing.pairUrl,
                    size: 220,
                    foregroundColor: Colors.black,
                  ),
                const SizedBox(height: 24),
                Text(
                  pairing.code,
                  style: const TextStyle(
                    fontSize: 40,
                    letterSpacing: 6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: _startPairing,
                      child: const Text('Generate new code'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _error ?? 'Unable to start pairing.',
            style: const TextStyle(color: Colors.redAccent),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _startPairing,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
