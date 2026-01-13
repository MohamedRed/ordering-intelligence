import 'package:consumer_core/consumer_core.dart';

class ApiConfig {
  static const String _defaultBaseUrl =
      'https://channel-gateway-230152279015.us-central1.run.app';

  static String resolveBaseUrl() {
    const configured = String.fromEnvironment('CHANNEL_GATEWAY_BASE_URL');
    if (configured.isNotEmpty) {
      return configured;
    }
    return _defaultBaseUrl;
  }

  static ChannelGatewayApi createApi() {
    return ChannelGatewayApi(
      baseUrl: resolveBaseUrl(),
      webappPathPrefix: '/mobile',
    );
  }

  static ChannelGatewayApi createTvApi() {
    return ChannelGatewayApi(
      baseUrl: resolveBaseUrl(),
      webappPathPrefix: '/tv',
    );
  }
}
