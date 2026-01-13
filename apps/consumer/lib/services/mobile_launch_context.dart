import 'package:consumer_core/consumer_core.dart';
import 'package:consumer_ui/consumer_ui.dart';

class MobileLaunchContextResolver {
  const MobileLaunchContextResolver();

  static MiniAppLaunchContext resolve({SessionInfo? session}) {
    return MiniAppLaunchContext(
      baseUri: _resolveBaseUri(),
      storeId: session?.storeId,
    );
  }

  static Uri _resolveBaseUri() {
    const fromEnv = String.fromEnvironment('MOBILE_SHARE_BASE_URL');
    if (fromEnv.isNotEmpty) {
      return Uri.parse(fromEnv);
    }
    return Uri.parse('https://ordering-intelligence.app');
  }
}
