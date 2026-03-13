# Sparkle release and Apple signing

## One-time setup (Keychain signing)

1. **Sparkle signing tools** – If you don’t have `tools/bin/sign_update` yet:
   ```bash
   mkdir -p tools
   curl -L -o /tmp/Sparkle-2.9.0.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.9.0/Sparkle-2.9.0.tar.xz
   tar -xf /tmp/Sparkle-2.9.0.tar.xz -C tools --strip-components=1
   ```
2. **Signing**: The script uses **Keychain only** (`sign_update -p`). The private key that matches `SUPublicEDKey` in `macos/Runner/Info.plist` must be in your Keychain (e.g. run Sparkle’s `generate_keys`, add to Keychain, put the public key in Info.plist). If you have multiple keys, set `SPARKLE_KEYCHAIN_ACCOUNT` to the Keychain account name.
3. When you run a release, the script signs the zip and puts `sparkle:edSignature` in the appcast so the app accepts the update.

---

## 1. Version values Sparkle uses

| Source | Key | Example |
|--------|-----|--------|
| App (Info.plist) | `CFBundleShortVersionString` | From `$(FLUTTER_BUILD_NAME)` → e.g. `1.0.1` |
| App (Info.plist) | `CFBundleVersion` | From `$(FLUTTER_BUILD_NUMBER)` → e.g. `101` |
| Flutter build | Set via | `flutter build macos --build-name=1.0.1 --build-number=101` |
| pubspec.yaml | `version:` | `1.0.1` (script reads this if no arg) |
| Appcast item | `sparkle:shortVersionString` | `1.0.1` (must match app’s display version) |
| Appcast item | `sparkle:version` | `101` (integer; Sparkle compares to `CFBundleVersion`) |

Sparkle offers an update when the appcast has an item with **strictly greater** `sparkle:version` than the app’s `CFBundleVersion` (and matching `sparkle:shortVersionString` semantics). So a build with version 1.0.0 / build 1 will **not** see an update for an appcast item that is also 1.0.0 / 1; it **will** see an update for 1.0.1 / 101.

---

## 2. Should the current (1.0.0) app see an update?

- **No** for an appcast item that is **1.0.0** (same version).
- **Yes** for an appcast item that is **1.0.1** (or any higher version).

So with the current appcast containing both 1.0.0 and 1.0.1, a running **1.0.0** app should see **1.0.1** as an update. The zip URL for 1.0.1 must be the public Pages URL and the zip must be the 1.0.1 build.

---

## 3. One-command Sparkle release

From repo root:

```bash
./sparkle_release.sh [VERSION]
```

Example:

```bash
./sparkle_release.sh 1.0.1
```

If you omit `VERSION`, the script uses `version:` from `pubspec.yaml`.

What it does:

1. Build macOS app: `flutter build macos --release --build-name=VERSION --build-number=SPARKLE_VERSION`
2. Bundle ExifTool libs into the app.
3. Zip the `.app`: `ditto -c -k --sequesterRsrc --keepParent "FloFile Beta.app" build/release/FloFileBeta.zip`
4. Run `sign_update -p` on the zip (reads private key from Keychain); it prints the EdDSA signature. The script puts that in the appcast as `sparkle:edSignature` (required when the app has `SUPublicEDKey` set).
5. Insert a new item into `docs/appcast.xml` (after `</language>`) with the versioned Pages URL, `length`, and optional `edSignature`.
6. Copy the zip to `docs/releases/vVERSION/FloFileBeta.zip` for GitHub Pages.
7. If `gh` is available and release doesn’t exist: `gh release create vVERSION ...` (tag + notes; zip is still served from Pages).

Then you commit and push so Pages and appcast update:

```bash
git add docs/appcast.xml docs/releases/
git commit -m "Release 1.0.1"
git push origin main
```

---

## 4. Exact commands for the next release cycle (by hand)

If you don’t use the script, use these in order.

**1) Set version in pubspec (e.g. 1.0.2):**

```bash
# Edit pubspec.yaml: version: 1.0.2
```

**2) Build:**

```bash
cd /Users/markblinch/Developer/caption_writer_flutter
flutter build macos --release --build-name=1.0.2 --build-number=102
```

**3) Bundle ExifTool (same as script):**

```bash
APP_PATH="build/macos/Build/Products/Release/FloFile Beta.app"
EXIF_PREFIX=$(brew --prefix exiftool 2>/dev/null || true)
[ -z "$EXIF_PREFIX" ] && EXIF_PREFIX=$(ls -d /opt/homebrew/Cellar/exiftool/* 2>/dev/null | sort -V | tail -1)
rsync -a "${EXIF_PREFIX}/libexec/lib/perl5/" "$APP_PATH/Contents/Resources/exiftool_lib/"
```

**4) Zip:**

```bash
ditto -c -k --sequesterRsrc --keepParent "build/macos/Build/Products/Release/FloFile Beta.app" build/release/FloFileBeta.zip
```

**5) Sign for Sparkle (optional but recommended):**

```bash
# Keychain only. Optional: SPARKLE_KEYCHAIN_ACCOUNT if you have multiple keys.
tools/bin/sign_update -p build/release/FloFileBeta.zip
# Use the printed signature in appcast as sparkle:edSignature
```

**6) Update docs/appcast.xml**

Add a new `<item>` after `</language>` (newest first), e.g. for 1.0.2:

- `sparkle:version`: `102`
- `sparkle:shortVersionString`: `1.0.2`
- `enclosure url`: `https://mblinch.github.io/flofile_clean/releases/v1.0.2/FloFileBeta.zip`
- `length`: byte size of `build/release/FloFileBeta.zip` (e.g. `stat -f%z build/release/FloFileBeta.zip`)
- `sparkle:edSignature`: output from `sign_update` (if you signed)

**7) Put zip on Pages:**

```bash
mkdir -p docs/releases/v1.0.2
cp build/release/FloFileBeta.zip docs/releases/v1.0.2/
```

**8) Optional – create GitHub release:**

```bash
gh release create v1.0.2 build/release/FloFileBeta.zip \
  --repo mblinch/flofile_clean \
  --title "FloFile Beta 1.0.2" \
  --notes "Release 1.0.2"
```

**9) Commit and push:**

```bash
git add docs/appcast.xml docs/releases/
git commit -m "Release 1.0.2"
git push origin main
```

---

## 5. App menu / AppDelegate / Sparkle

- **AppDelegate.swift**: Uses `SPUStandardUpdaterController` and exposes `checkForUpdates:`.
- **MainMenu.xib**: “Check for Updates…” menu item is connected to `checkForUpdates:` on the app delegate (target `Voe-Tx-rLC`).
- **Info.plist**: `SUFeedURL` = `https://mblinch.github.io/flofile_clean/appcast.xml`, `SUPublicEDKey` set.

No code changes needed for the update flow; Sparkle is wired correctly.

---

## 6. Apple code signing and notarization (still to do)

Do these **after** building the Release app and **before** zipping for Sparkle (so the `.app` inside the zip is signed and notarized).

**1) Sign the app with “Developer ID Application”:**

```bash
APP="build/macos/Build/Products/Release/FloFile Beta.app"
codesign --force --options runtime --sign "Developer ID Application: Your Name (TEAM_ID)" "$APP"
# Or use the full cert name from Keychain
```

**2) Notarize the zip (Sparkle ships a zip):**

```bash
ZIP="build/release/FloFileBeta.zip"
# Create zip if needed (ditto as above), then:
xcrun notarytool submit "$ZIP" \
  --apple-id "your@apple.id" \
  --team-id "TEAM_ID" \
  --password "app-specific-password" \
  --wait
```

**3) Staple the notarization ticket to the app (so it works offline):**

```bash
xcrun stapler staple "build/macos/Build/Products/Release/FloFile Beta.app"
```

**4) Re-zip the app** (so the zip contains the stapled app) and use that zip for Sparkle and Pages.

Summary: sign → notarize zip → staple app → re-zip → then run `sparkle_release.sh` (or the manual steps) using that zip. For automation, add a “sign + notarize + staple” step before the “zip” step in your script and use Apple ID + app-specific password (e.g. from env or keychain).
