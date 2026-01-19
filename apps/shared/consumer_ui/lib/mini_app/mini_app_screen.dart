import 'dart:async';
import 'dart:typed_data';

import 'package:consumer_core/consumer_core.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../utils/audio_recorder.dart';
import 'chat/chat_header_card.dart';
import 'chat/chat_context_panel.dart';
import 'chat/chat_view.dart';
import 'chat/chat_context_bar.dart';
import 'gas/gas_order_confirmation.dart';
import 'gas/gas_order_view.dart';
import 'menu_view_mode.dart';
import 'mini_app_platform.dart';
import 'mini_app_scope.dart';
import 'widgets/account_link_panel.dart';
import 'widgets/action_icon_button.dart';
import 'widgets/cart_sheet.dart';
import 'widgets/centered_message.dart';
import 'widgets/delivery_options_section.dart';
import 'widgets/group_order_panel.dart';
import 'widgets/modifier_dialog.dart';
import 'widgets/order_confirmation.dart';
import 'widgets/payment_methods_panel.dart';
import 'widgets/mini_app_drawer.dart';
import 'widgets/menu_browse_filters.dart';
import 'widgets/menu_item_card.dart';
import 'widgets/menu_mode_bar.dart';
import 'widgets/menu_view_toggle.dart';
import 'widgets/minimal_card.dart';
import 'widgets/store_search_footer.dart';
import 'widgets/store_inline_suggestions.dart';
import 'widgets/store_logo.dart';
import 'widgets/recommended_order_card.dart';

part 'mini_app_state_fields.dart';
part 'mini_app_state_search.dart';
part 'mini_app_state_recommendations.dart';
part 'mini_app_state_store_search_chat.dart';
part 'mini_app_state_home_chat.dart';
part 'mini_app_state_store.dart';
part 'mini_app_state_menu.dart';
part 'mini_app_state_cart.dart';
part 'mini_app_state_cart_sheet.dart';
part 'mini_app_state_delivery.dart';
part 'mini_app_state_group_orders_actions.dart';
part 'mini_app_state_group_orders_hydrate.dart';
part 'mini_app_state_group_orders_entry.dart';
part 'mini_app_state_group_orders_items.dart';
part 'mini_app_state_group_orders_checkout.dart';
part 'mini_app_state_group_orders_share.dart';
part 'mini_app_state_group_orders_view.dart';
part 'mini_app_state_drafts.dart';
part 'mini_app_state_chat.dart';
part 'mini_app_state_chat_actions.dart';
part 'mini_app_state_chat_comms.dart';
part 'mini_app_state_chat_participants.dart';
part 'mini_app_state_chat_product_lookup.dart';
part 'mini_app_state_chat_products.dart';
part 'mini_app_state_chat_selection.dart';
part 'mini_app_state_chat_seed.dart';
part 'mini_app_state_chat_audio.dart';
part 'mini_app_state_gas.dart';
part 'mini_app_state_gas_actions.dart';
part 'mini_app_state_gas_pump_actions.dart';
part 'mini_app_state_payments.dart';
part 'mini_app_state_reorders.dart';
part 'mini_app_state_order.dart';
part 'mini_app_state_identity.dart';
part 'mini_app_state_identity_actions.dart';
part 'mini_app_state_identity_links.dart';
part 'mini_app_state_identity_targets.dart';
part 'mini_app_state_identity_ui.dart';
part 'mini_app_state_sign_out.dart';
part 'mini_app_state_lifecycle.dart';
part 'mini_app_state_build_menu_gas.dart';
part 'mini_app_state_build_home.dart';
part 'mini_app_state_build_menu_browse.dart';
part 'mini_app_state_build_menu_chat.dart';
part 'mini_app_state_build_menu.dart';
part 'mini_app_state_build.dart';

class MiniAppScreen extends StatefulWidget {
  const MiniAppScreen({super.key, required this.platform});

  final MiniAppPlatform platform;

  @override
  State<MiniAppScreen> createState() => _MiniAppScreenState();
}

class _MiniAppScreenState extends State<MiniAppScreen>
    with
        MiniAppStateFields,
        MiniAppStateRecommendations,
        MiniAppStateIdentity,
        MiniAppStateIdentityActions,
        MiniAppStateIdentityLinks,
        MiniAppStateIdentityUI,
        MiniAppStateSignOut,
        MiniAppStatePayments,
        MiniAppStateGas,
        MiniAppStateGasActions,
        MiniAppStateGasPumpActions,
        MiniAppStateDelivery,
        MiniAppStateDrafts,
        MiniAppStateMenu,
        MiniAppStateOrder,
        MiniAppStateGroupOrdersItems,
        MiniAppStateCart,
        MiniAppStateReorders,
        MiniAppStateCartSheet,
        MiniAppStateGroupOrdersCheckout,
        MiniAppStateGroupOrdersShare,
        MiniAppStateGroupOrdersActions,
        MiniAppStateGroupOrdersHydrate,
        MiniAppStateGroupOrdersEntry,
        MiniAppStateGroupOrdersView,
        MiniAppStateChatState,
        MiniAppStateStore,
        MiniAppStateSearch,
        MiniAppStateHomeChat,
        MiniAppStateStoreSearchChat,
        MiniAppStateChatProducts,
        MiniAppStateChatSelection,
        MiniAppStateChatSeed,
        MiniAppStateChatProductLookup,
        MiniAppStateChatComms,
        MiniAppStateChatParticipants,
        MiniAppStateChatActions,
        MiniAppStateChatAudio,
        MiniAppStateLifecycle,
        MiniAppStateBuildMenuGas,
        MiniAppStateBuildMenuChat,
        MiniAppStateBuildMenuBrowse,
        MiniAppStateBuildHome,
        MiniAppStateBuildMenu,
        MiniAppStateBuild {
  @override
  Widget build(BuildContext context) {
    return MiniAppScope(
      platform: widget.platform,
      child: buildMiniApp(context),
    );
  }
}
