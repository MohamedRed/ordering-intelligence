import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/delivery_partner_stripe_status.dart';
import '../models/marketplace_offer.dart';
import '../services/delivery_partner_onboarding_api.dart';
import '../services/fcm_token_manager.dart';
import '../services/location_service.dart';
import '../services/marketplace_api.dart';
import '../services/store_prefs.dart';

class MarketplaceHomeScreen extends StatefulWidget {
  const MarketplaceHomeScreen({super.key});

  @override
  State<MarketplaceHomeScreen> createState() => _MarketplaceHomeScreenState();
}

class _MarketplaceHomeScreenState extends State<MarketplaceHomeScreen> {
  late MarketplaceDispatchApi _api;
  late DeliveryPartnerOnboardingApi _onboardingApi;
  late LocationService _locationService;
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _accuracyCtrl = TextEditingController(text: '10');

  bool _available = true;
  bool _autoLocation = false;
  bool _busy = false;
  String? _error;
  List<MarketplaceOffer> _offers = const [];
  DeliveryPartnerStripeStatus? _stripeStatus;
  DateTime? _lastRefreshAt;
  double? _lastLat;
  double? _lastLng;
  double? _lastAccuracy;
  DateTime? _lastSentAt;

  @override
  void initState() {
    super.initState();
    _api = MarketplaceDispatchApi();
    _onboardingApi = DeliveryPartnerOnboardingApi();
    _locationService = LocationService(
      api: _api,
      onPosition: (pos) {
        if (!mounted) return;
        setState(() {
          _lastLat = pos.latitude;
          _lastLng = pos.longitude;
          _lastAccuracy = pos.accuracy;
        });
      },
      onSent: (pos) {
        if (!mounted) return;
        setState(() => _lastSentAt = DateTime.now().toUtc());
      },
      onError: (msg) {
        if (!mounted) return;
        setState(() => _error = msg);
      },
    );
    _initFcm();
    _refreshOffers();
    _loadStripeStatus();
  }

  Future<void> _initFcm() async {
    final token = await fetchFcmToken();
    if (token != null && token.trim().isNotEmpty) {
      await registerTokenWithBackend(token: token, storeId: 'marketplace');
    }
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _accuracyCtrl.dispose();
    _locationService.stop();
    super.dispose();
  }

  Future<void> _refreshOffers() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final offers = await _api.listOffers();
      if (!mounted) return;
      setState(() {
        _offers = offers;
        _lastRefreshAt = DateTime.now().toUtc();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadStripeStatus() async {
    try {
      final status = await _onboardingApi.fetchStripeStatus();
      if (!mounted) return;
      setState(() => _stripeStatus = status);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _setAvailability(bool value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.setAvailability(value);
      if (!mounted) return;
      setState(() => _available = value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startStripeOnboarding() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final phone = StorePrefs.instance.phone();
      await _onboardingApi.ensureStripeAccount(
        phone: phone.isEmpty ? null : phone,
      );
      final returnUrl = kIsWeb ? Uri.base.toString() : null;
      final refreshUrl = kIsWeb ? Uri.base.toString() : null;
      final url = await _onboardingApi.createAccountLink(
        returnUrl: returnUrl,
        refreshUrl: refreshUrl,
      );
      final uri = Uri.parse(url);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('Unable to open Stripe onboarding');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendLocation() async {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    final acc = double.tryParse(_accuracyCtrl.text.trim()) ?? 0;
    if (lat == null || lng == null) {
      setState(() => _error = 'Enter valid lat/lng');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.postLocation(lat: lat, lng: lng, accuracyM: acc);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleAutoLocation(bool enabled) async {
    if (enabled) {
      final ok = await _locationService.start();
      if (!ok) {
        if (mounted) setState(() => _autoLocation = false);
        return;
      }
    } else {
      await _locationService.stop();
    }
    if (mounted) setState(() => _autoLocation = enabled);
  }

  Future<void> _acceptOffer(MarketplaceOffer offer) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.acceptOffer(offer.offerId);
      await _refreshOffers();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateOrderStatus(MarketplaceOffer offer, String status) async {
    if (offer.orderId.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.updateOrderStatus(
        orderId: offer.orderId,
        status: status,
        offerId: offer.offerId,
        storeId: offer.storeId,
      );
      await _refreshOffers();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildStripeCard() {
    final status = _stripeStatus;
    final ready = status != null && status.payoutsEnabled && status.detailsSubmitted;
    final missingCount = status == null
        ? 0
        : status.currentlyDue.length +
            status.pendingVerification.length +
            status.pastDue.length;
    final title = ready ? 'Payouts enabled' : 'Complete payout setup';
    final subtitle = status == null
        ? 'Connect a Stripe Express account to receive payouts.'
        : ready
            ? 'You can receive payouts for completed deliveries.'
            : 'Stripe needs more details to enable payouts.';
    final statusLine = status == null
        ? 'Status: not started'
        : 'Status: ${status.status.isEmpty ? 'pending' : status.status}';
    final actionLabel = ready ? 'Update details' : 'Start setup';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(subtitle),
            const SizedBox(height: 6),
            Text(statusLine),
            if (missingCount > 0)
              Text('Requirements due: $missingCount'),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _busy ? null : _startStripeOnboarding,
                  child: Text(actionLabel),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _busy ? null : _loadStripeStatus,
                  child: const Text('Refresh status'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace courier'),
        actions: [
          IconButton(
            onPressed: _busy
                ? null
                : () {
                    _refreshOffers();
                    _loadStripeStatus();
                  },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          _sectionTitle('Availability'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ready for offers'),
            value: _available,
            onChanged: _busy ? null : _setAvailability,
          ),
          const SizedBox(height: 12),
          _sectionTitle('Location'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto location updates'),
            value: _autoLocation,
            onChanged: _busy ? null : _toggleAutoLocation,
          ),
          if (!_autoLocation) ...[
            TextField(
              controller: _latCtrl,
              decoration: const InputDecoration(
                labelText: 'Latitude',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _lngCtrl,
              decoration: const InputDecoration(
                labelText: 'Longitude',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _accuracyCtrl,
              decoration: const InputDecoration(
                labelText: 'Accuracy (m)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _busy ? null : _sendLocation,
              child: const Text('Send location'),
            ),
          ],
          if (_lastLat != null && _lastLng != null) ...[
            const SizedBox(height: 6),
            Text('Last GPS: $_lastLat,$_lastLng (±${_lastAccuracy ?? 0}m)'),
          ],
          if (_lastSentAt != null)
            Text('Last sent: ${_lastSentAt!.toIso8601String()}'),
          const SizedBox(height: 16),
          _sectionTitle('Payout setup'),
          _buildStripeCard(),
          const SizedBox(height: 16),
          _sectionTitle('Offers'),
          if (_lastRefreshAt != null)
            Text('Updated: ${_lastRefreshAt!.toIso8601String()}'),
          const SizedBox(height: 8),
          if (_offers.isEmpty)
            const Text('No offers yet.')
          else
            ..._offers.map((offer) {
              final assignedToMe =
                  offer.selectedDelivererId.isNotEmpty &&
                  offer.selectedDelivererId == uid;
              final expires = offer.expiresAt == null
                  ? ''
                  : 'Expires ${offer.expiresAt!.toLocal()}';
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Store ${offer.storeId}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text('Status: ${offer.status}'),
                      if (offer.orderId.isNotEmpty)
                        Text('Order: ${offer.orderId}'),
                      Text('Payout: ${offer.payoutCents} ${offer.currency}'),
                      if (offer.dropoffAddress.isNotEmpty)
                        Text('Dropoff: ${offer.dropoffAddress}'),
                      if (offer.instructions.isNotEmpty)
                        Text('Notes: ${offer.instructions}'),
                      if (expires.isNotEmpty) Text(expires),
                      const SizedBox(height: 8),
                      if (offer.status == 'open')
                        ElevatedButton(
                          onPressed: _busy ? null : () => _acceptOffer(offer),
                          child: const Text('Accept offer'),
                        ),
                      if (offer.status == 'assigned' && assignedToMe) ...[
                        Wrap(
                          spacing: 8,
                          children: [
                            ElevatedButton(
                              onPressed: _busy
                                  ? null
                                  : () =>
                                        _updateOrderStatus(offer, 'picked_up'),
                              child: const Text('Picked up'),
                            ),
                            ElevatedButton(
                              onPressed: _busy
                                  ? null
                                  : () => _updateOrderStatus(
                                      offer,
                                      'out_for_delivery',
                                    ),
                              child: const Text('Out for delivery'),
                            ),
                            ElevatedButton(
                              onPressed: _busy
                                  ? null
                                  : () =>
                                        _updateOrderStatus(offer, 'delivered'),
                              child: const Text('Delivered'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
