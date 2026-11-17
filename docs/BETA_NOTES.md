# FloFile Beta notes

Copy relevant bullets into Sparkle / GitHub release notes for each beta build.

## 2.0.51

- **Google Sign-In:** If macOS Keychain leftovers break sign-in, FloFile clears them and retries automatically — no Keychain Access steps for users.

## 2.0.50

- **Accessibility:** VoiceOver / UI-test Semantics labels on setup, caption controls, and dialogs (including Save & Next and player rows like “Home 34 Auston Matthews”).
- **Crash reports:** Settings → Application → **Send crash reports** (on by default in beta). Uses Sentry on macOS and Windows. Includes app version, OS, wire, IPTC mode, and league only — never captions, IPTC values, paths, photos, or email.
- **Player codes:** Type `h34` / `v88` (or `hh` / `vv`) on the caption screen to select home/visitor jersey numbers. Also works in the caption box and Firebar.

## Crash reports (Settings)

- **Send crash reports** is on by default in beta (Settings → Application → Modes).
- Reports go to Sentry (macOS and Windows). Firebase Crashlytics is not used — it does not support Flutter Windows.
- Included: app version, OS, selected wire, IPTC mode, league.
- Never included: caption text, IPTC field values, file names/paths, photos, or email.
- Turn the toggle off anytime to stop sending.

## Build with reporting

```bash
flutter run -d macos --dart-define=SENTRY_DSN=https://…@….ingest.sentry.io/…
# or for Sparkle release:
SENTRY_DSN='https://…' ./sparkle_release.sh
```

Without `SENTRY_DSN`, the app still runs; nothing is sent.
