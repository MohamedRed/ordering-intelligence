# Telegram Mini App

Flutter Web mini app that powers the in-chat ordering experience.

## Run locally

```bash
flutter pub get
flutter run -d chrome --dart-define=CHANNEL_GATEWAY_BASE_URL=http://localhost:8090
```

Optional: pass a store id and api base in the URL:

```
http://localhost:XXXX/?storeId=fwencheese-demo&apiBase=http://localhost:8090
```

## Telegram WebApp

Host the built web bundle and point your Telegram bot WebApp URL to it. The
client forwards Telegram `initData` to the channel-gateway `/telegram/webapp`
endpoints for verification and session setup.
