part of 'mini_app_screen.dart';

mixin MiniAppStateLifecycle
    on
        State<MiniAppScreen>,
        MiniAppStateFields,
        MiniAppStateSearch,
        MiniAppStateGroupOrdersEntry,
        MiniAppStateMenu,
        MiniAppStateChatState,
        MiniAppStateDelivery {
  @override
  void initState() {
    super.initState();
    _platform = widget.platform;
    _api = _platform.api;
    _launchContext = _platform.resolveLaunchContext();
    _locale = _launchContext.locale;
    _pendingInviteId = _launchContext.inviteId;
    _pendingGroupOrderId = _launchContext.groupOrderId;
    _pendingJoinCode = _launchContext.joinCode;
    _pendingLinkToken = _launchContext.linkToken;
    _pendingStartGroupOrder = _launchContext.startGroupOrder;
    _searchController.addListener(_onSearchChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loadingSession = true;
      _sessionError = null;
      _sessionStage = null;
    });
    try {
      _setSessionStage('session_start');
      final session = await _platform.startSession(_launchContext);
      if (!mounted) {
        return;
      }
      if (session == null) {
        setState(() {
          _sessionError = 'Session start canceled.';
          _loadingSession = false;
        });
        return;
      }
      _setSessionStage('session_ready');
      setState(() {
        _session = session;
        _orderUpdatesLabel = _platform.orderUpdatesLabel(session);
        _loadingSession = false;
      });
      await _platform.onSessionReady(session);
      await _loadPaymentMethods(silent: true);
      _maybeSeedChat();
      if (session.startGroupOrder) {
        _pendingStartGroupOrder = true;
      }
      if (_pendingLinkToken != null && _pendingLinkToken!.isNotEmpty) {
        final token = _pendingLinkToken!;
        _pendingLinkToken = null;
        await _completeIdentityLink(token);
      }
      _setSessionStage('load_identity');
      await _loadIdentity();
      _setSessionStage('load_recommendations');
      await _loadRecommendedOrders();
      _setSessionStage('resolve_group_order');
      final joined = await _maybeJoinGroupOrderFromUrl();
      if (!joined) {
        await _maybeStartGroupOrderFromUrl();
      }
      if (!joined && session.storeId.isNotEmpty) {
        _setSessionStage('load_menu');
        await _loadMenu(session.storeId);
        _setSessionStage('load_delivery_settings');
        await _refreshDeliverySettings(session.storeId);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        final stage = _sessionStage;
        _sessionError = stage == null || stage.isEmpty
            ? e.toString()
            : '[$stage] ${e.toString()}';
        _loadingSession = false;
      });
    }
  }

  void _setSessionStage(String stage) {
    _sessionStage = stage;
    debugPrint('session_stage=$stage');
  }
}
