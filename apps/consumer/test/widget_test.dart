import 'package:flutter_test/flutter_test.dart';

import 'package:consumer_core/consumer_core.dart';

void main() {
  test('SessionInfo roundtrip preserves ids', () {
    const session = SessionInfo(
      sessionId: 'session-123',
      accountId: 'account-1',
      userId: 'user-1',
      displayName: 'Test User',
      storeId: 'store-1',
      storeName: 'Store',
      tenantId: 'tenant-1',
      customerId: 'customer-1',
      businessType: 'restaurant',
      startGroupOrder: false,
      telegramBotUsername: '',
    );
    final json = session.toJson();
    final parsed = SessionInfo.fromJson(json);
    expect(parsed.sessionId, session.sessionId);
    expect(parsed.customerId, session.customerId);
    expect(parsed.tenantId, session.tenantId);
  });
}
