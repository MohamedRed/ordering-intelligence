part of 'mini_app_screen.dart';

mixin MiniAppStateFields on State<MiniAppScreen> {
  late final MiniAppPlatform _platform;
  late final ChannelGatewayApi _api;
  late MiniAppLaunchContext _launchContext;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final ScrollController _menuScrollController = ScrollController();
  final GlobalKey _menuItemsAnchorKey = GlobalKey();
  Timer? _searchDebounce;

  SessionInfo? _session;
  String? _sessionError;
  String? _sessionStage;
  bool _loadingSession = true;
  String? _locale;
  String? _orderUpdatesLabel;

  bool _searching = false;
  String? _searchError;
  List<StoreChoice> _searchResults = [];
  List<RecommendedOrder> _recommendedOrders = [];
  List<RecommendedOrder> _storeRecommendations = [];
  CustomerProfile? _customerProfile;
  bool _loadingIdentity = false;
  String? _identityError;
  String? _pendingLinkToken;
  bool _linkingIdentity = false;

  String? _pendingInviteId;
  String? _pendingGroupOrderId;
  String? _pendingJoinCode;
  bool _pendingStartGroupOrder = false;
  GroupOrderSession? _groupOrder;
  String? _groupOrderParticipantId;
  String? _groupOrderError;
  bool _groupOrderBusy = false;
  bool _groupOrderCollapsed = true;
  String _groupOrderPaymentMode = 'single_payer';
  String _groupOrderPaymentMethod = 'card';
  String? _latestInviteId;

  MenuSnapshot? _menu;
  bool _loadingMenu = false;
  String? _menuError;
  List<String> _categories = [];
  String _activeCategory = '';

  List<CartItem> _cart = [];
  StateSetter? _cartSheetSetState;
  String _orderPaymentMethod = 'cash';
  bool _placingOrder = false;
  String? _orderError;
  Map<String, dynamic>? _orderConfirmation;
}
