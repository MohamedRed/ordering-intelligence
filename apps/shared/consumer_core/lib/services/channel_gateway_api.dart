import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../adapters/auth_adapter.dart';
import '../models/cart_models.dart';
import '../models/chat_models.dart';
import '../models/customer_profile.dart';
import '../models/delivery_models.dart';
import '../models/draft_order.dart';
import '../models/group_order_checkout_response.dart';
import '../models/group_order_invite.dart';
import '../models/group_order_session.dart';
import '../models/fuel_order.dart';
import '../models/menu_models.dart';
import '../models/off_session_payment.dart';
import '../models/order_updates_link.dart';
import '../models/payment_intent.dart';
import '../models/payment_method.dart';
import '../models/recommended_order.dart';
import '../models/setup_intent.dart';
import '../models/store_models.dart';

part 'channel_gateway_api_session.dart';
part 'channel_gateway_api_stores.dart';
part 'channel_gateway_api_menu.dart';
part 'channel_gateway_api_orders.dart';
part 'channel_gateway_api_payments.dart';
part 'channel_gateway_api_recommendations.dart';
part 'channel_gateway_api_order_updates.dart';
part 'channel_gateway_api_chat.dart';
part 'channel_gateway_api_chat_decode.dart';
part 'channel_gateway_api_drafts.dart';
part 'channel_gateway_api_group_orders_read.dart';
part 'channel_gateway_api_group_orders_utils.dart';
part 'channel_gateway_api_group_orders_write.dart';
part 'channel_gateway_api_group_orders_checkout.dart';
part 'channel_gateway_api_identity.dart';
part 'channel_gateway_api_notifications.dart';

abstract class ChannelGatewayApiBase {
  ChannelGatewayApiBase({
    required this.baseUrl,
    this.webappPathPrefix = '/telegram/webapp',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String webappPathPrefix;
  final http.Client _client;

  Uri _buildUri(String path, [Map<String, String>? query]) {
    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final full = '$normalized$path';
    return Uri.parse(full).replace(queryParameters: query);
  }

  Uri _buildWebAppUri(String path, [Map<String, String>? query]) {
    final prefix = webappPathPrefix.isEmpty
        ? ''
        : webappPathPrefix.startsWith('/')
        ? webappPathPrefix
        : '/$webappPathPrefix';
    return _buildUri('$prefix$path', query);
  }
}

class ChannelGatewayApi extends ChannelGatewayApiBase
    with
        ChannelGatewaySessionApi,
        ChannelGatewayStoreApi,
        ChannelGatewayMenuApi,
        ChannelGatewayOrdersApi,
        ChannelGatewayPaymentsApi,
        ChannelGatewayRecommendationsApi,
        ChannelGatewayOrderUpdatesApi,
        ChannelGatewayChatApi,
        ChannelGatewayDraftsApi,
        ChannelGatewayIdentityApi,
        ChannelGatewayNotificationsApi,
        ChannelGatewayGroupOrdersReadApi,
        ChannelGatewayGroupOrdersWriteApi,
        ChannelGatewayGroupOrdersCheckoutApi {
  ChannelGatewayApi({
    required super.baseUrl,
    super.webappPathPrefix,
    super.client,
  });
}
