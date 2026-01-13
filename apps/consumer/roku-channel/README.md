# Roku Channel (skeleton)

Goal: leanback experience that pairs to the mobile app for auth and payments.

Structure
- `manifest` – minimal Roku manifest.
- `source/main.brs` – boots the SceneGraph screen and starts `/tv/pair/start`.
- `components/MainScene.xml` – UI with title, subtitle, QR, and pairing code.
- `components/MainScene.brs` – sets background, QR, pairing code, and reacts to session link.
- `images/` – add launcher/background assets (`icon_focus_hd.png`, `icon_side_hd.png`, `bg_placeholder.png`).

Pairing flow
1) Channel calls `/tv/pair/start`, receives `pairUrl` + `code`, and renders both.
2) Phone opens the link, authenticates, and completes pairing.
3) Channel polls `/tv/pair/state?pairingId=...`; once linked, it stores the session token and fetches reorders.

Build/test
- Set `base_url` in the Roku registry section `ordering-intel` (or rely on the dev fallback).
- Zip the contents (or use Roku Dev Dashboard sideload) to test.
- Update icons/backgrounds before store submission.

Next steps (to productionize)
- Add a richer state machine for pairing retries and expired codes.
- Add grids for reorders and store selection (SceneGraph RowList).
- Hook analytics/error reporting (e.g., Sentry via HTTPS).
- Add localization for FR/EN.
- Replace placeholder background and icons.
