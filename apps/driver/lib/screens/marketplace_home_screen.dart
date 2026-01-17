import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/delivery_partner_compliance.dart';
import '../models/delivery_partner_stripe_status.dart';
import '../models/marketplace_offer.dart';
import '../services/delivery_partner_onboarding_api.dart';
import '../services/fcm_token_manager.dart';
import '../services/location_service.dart';
import '../services/marketplace_api.dart';
import '../services/store_prefs.dart';
import '../widgets/marketplace/marketplace_compliance_card.dart';
import '../widgets/marketplace/marketplace_offers_list.dart';
import '../widgets/marketplace/marketplace_section_title.dart';
import '../widgets/marketplace/marketplace_stripe_card.dart';

part 'marketplace_home_logic.dart';

class MarketplaceHomeScreen extends StatefulWidget {
  const MarketplaceHomeScreen({super.key});

  @override
  State<MarketplaceHomeScreen> createState() => _MarketplaceHomeScreenState();
}

class _MarketplaceHomeScreenState extends State<MarketplaceHomeScreen>
    with MarketplaceHomeLogic<MarketplaceHomeScreen> {
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
                    _loadCompliance();
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
          const MarketplaceSectionTitle('Availability'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ready for offers'),
            value: _available,
            onChanged: _busy || !_eligibleForOffers ? null : _setAvailability,
          ),
          if (!_eligibleForOffers)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Complete payout setup and compliance documents to go online.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          const MarketplaceSectionTitle('Location'),
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
          const MarketplaceSectionTitle('Payout setup'),
          MarketplaceStripeCard(
            status: _stripeStatus,
            busy: _busy,
            onStart: _startStripeOnboarding,
            onRefresh: _loadStripeStatus,
          ),
          const SizedBox(height: 16),
          const MarketplaceSectionTitle('Compliance'),
          MarketplaceComplianceCard(
            compliance: _compliance,
            busy: _busy,
            selectedVehicleType: _selectedVehicleType,
            onVehicleTypeChanged: (value) {
              setState(() => _selectedVehicleType = value);
            },
            onStart: _startCompliance,
            onUpload: _uploadComplianceDoc,
            onRefresh: _loadCompliance,
          ),
          const SizedBox(height: 16),
          const MarketplaceSectionTitle('Offers'),
          if (_lastRefreshAt != null)
            Text('Updated: ${_lastRefreshAt!.toIso8601String()}'),
          const SizedBox(height: 8),
          MarketplaceOffersList(
            offers: _offers,
            busy: _busy,
            currentUserId: uid,
            onAccept: _acceptOffer,
            onUpdateStatus: _updateOrderStatus,
          ),
        ],
      ),
    );
  }
}
