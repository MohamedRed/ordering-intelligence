# Roku Channel (skeleton)

Goal: leanback experience that pairs to the mobile app for auth and payments.

Structure
- `manifest` – minimal Roku manifest.
- `source/main.brs` – boots the SceneGraph screen and injects a pairing URL.
- `components/MainScene.xml` – simple UI with title, subtitle, and QR code.
- `components/MainScene.brs` – sets background and dynamic QR based on `pairingUrl`.
- `images/` – add launcher/background assets (`icon_focus_hd.png`, `icon_side_hd.png`, `bg_placeholder.png`).

Pairing flow
1) Channel shows QR that points to `https://dev-channel-gateway.liive.dev/tv/pair` (replace per env).
2) Phone opens the link, authenticates, and writes a short-lived session token tied to the Roku device.
3) Channel polls channel-gateway for session state; once linked, it fetches menus/reorders and submits carts via existing APIs.

Build/test
- Zip the contents (or use Roku Dev Dashboard sideload) to test.
- Update the QR URL and icons before store submission.

Next steps (to productionize)
- Implement polling + state machine for pairing + orders.
- Add grids for reorders and store selection (SceneGraph RowList).
- Hook analytics/error reporting (e.g., Sentry via HTTPS).
- Add localization for FR/EN.
- Replace placeholder background and icons.
