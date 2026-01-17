part of 'marketplace_home_screen.dart';

mixin MarketplaceHomeLogic<T extends StatefulWidget> on State<T> {
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
  DeliveryPartnerCompliance? _compliance;
  String _selectedVehicleType = '';
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
    _loadCompliance();
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _accuracyCtrl.dispose();
    _locationService.stop();
    super.dispose();
  }

  Future<void> _initFcm() async {
    final token = await fetchFcmToken();
    if (token != null && token.trim().isNotEmpty) {
      await registerTokenWithBackend(token: token, storeId: 'marketplace');
    }
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

  Future<void> _loadCompliance() async {
    try {
      final compliance = await _onboardingApi.fetchComplianceStatus();
      if (!mounted) return;
      setState(() => _compliance = compliance);
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
      final url = await _onboardingApi.createEmbeddedSessionUrl();
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

  Future<void> _startCompliance() async {
    if (_selectedVehicleType.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final compliance = await _onboardingApi.startCompliance(
        vehicleType: _selectedVehicleType,
        country: 'FR',
      );
      if (!mounted) return;
      setState(() => _compliance = compliance);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadComplianceDoc(String docType) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      );
      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final file = result.files.single;
      final path = file.path;
      if (path == null || path.isEmpty) {
        throw Exception('Selected file is unavailable');
      }
      final compliance = await _onboardingApi.uploadComplianceDocument(
        docType: docType,
        filePath: path,
        fileName: file.name,
      );
      if (!mounted) return;
      setState(() => _compliance = compliance);
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

  bool get _stripeReady =>
      _stripeStatus != null &&
      _stripeStatus!.payoutsEnabled &&
      _stripeStatus!.detailsSubmitted;

  bool get _complianceReady => _compliance?.isApproved == true;

  bool get _eligibleForOffers => _stripeReady && _complianceReady;
}
