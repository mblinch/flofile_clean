# Firebase Auth — Google Sign-In (macOS)

The app uses **Firebase Authentication** with **Google Sign-In** on macOS. Project: `projectflo-e99c6`.

## 1. Enable Google in Firebase Console

1. Open [Firebase Console → Authentication → Sign-in method](https://console.firebase.google.com/project/projectflo-e99c6/authentication/providers).
2. Enable **Google** and save. Download a fresh `GoogleService-Info.plist` (it will include `CLIENT_ID` and `REVERSED_CLIENT_ID`).

Replace the plist:

```bash
# After downloading from Firebase → Project settings → Your apps → macOS/iOS app
cp ~/Downloads/GoogleService-Info.plist macos/Runner/GoogleService-Info.plist
```

## 2. Google Sign-In — OAuth client ID

Copy `CLIENT_ID` from `macos/Runner/GoogleService-Info.plist` into **one** of:

- `lib/config/google_sign_in_config.dart` → set `kGoogleSignInClientId`
- or run with:  
  `flutter run --dart-define=GOOGLE_OAUTH_CLIENT_ID=YOUR_CLIENT_ID.apps.googleusercontent.com`

### macOS `Info.plist` (required for Google callback)

In `macos/Runner/Info.plist`, inside `<dict>`:

```xml
<key>GIDClientID</key>
<string>YOUR_CLIENT_ID.apps.googleusercontent.com</string>
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <!-- REVERSED_CLIENT_ID from GoogleService-Info.plist -->
      <string>com.googleusercontent.apps.737938045380-xxxxxxxx</string>
    </array>
  </dict>
</array>
```

Use the exact `REVERSED_CLIENT_ID` value from the plist (not the `CLIENT_ID` string).

## 3. Xcode signing (required for Google Sign-In on macOS)

Google Sign-In stores tokens in the **Keychain**. macOS only allows that when the app is **signed** with a development certificate.

1. Open `macos/Runner.xcworkspace` in Xcode.
2. Select the **Runner** target → **Signing & Capabilities**.
3. Check **Automatically manage signing**.
4. Choose your **Team** (sign in with any Apple ID under Xcode → Settings → Accounts if needed).
5. Build/run from Xcode or `flutter run -d macos`.

Until a Team is selected, you may see: *"entitlements that require signing with a development certificate"*.

## 5. Keychain (Google)

`macos/Runner/DebugProfile.entitlements` and `Release.entitlements` include (app group **first**):

```xml
<key>keychain-access-groups</key>
<array>
  <string>$(AppIdentifierPrefix)$(CFBundleIdentifier)</string>
  <string>$(AppIdentifierPrefix)com.google.GIDSignIn</string>
</array>
```

Google Sign-In on macOS needs **both** groups; the app’s bundle group must be listed first. Without this, Google Sign-In can fail with a keychain `PlatformException`.

## 6. Run the app

```bash
dart pub get
flutter run -d macos
```

On launch you should see **Sign in to FloFile**. After sign-in, **Preferences → Application** shows your account and **Sign out**.

Sync account ID is set automatically to your Firebase **UID** for cloud sync and feature gates.

## App admins

`projectflofile@gmail.com` is configured as an in-app admin in `lib/services/admin_service.dart` (and in the `runRosterSyncNow` Cloud Function).

- **Fine for you as owner** — gates beta features (e.g. MLB inning-from-EXIF) and manual roster sync.
- **Not enough alone for production security** — anyone could patch the client. For sensitive data, add Firebase **custom claims** on your user:

```js
// One-time, Firebase Admin SDK (e.g. functions shell or script):
await admin.auth().setCustomUserClaims(uid, { admin: true });
```

After signing in with Google, copy your **User UID** from Firebase Console → Authentication if you want to add it to `AdminService.adminUids` as a backup to email.

For Firestore write rules that require the `admin` claim:

```bash
node functions/scripts/set-admin-claim.js YOUR_UID
```

## App originals (verbs + IPTC)

Global defaults live in Firestore at **`appDefaults/current`**:

- **Read:** any signed-in user (cached locally on sign-in).
- **Write:** admin only (`admin` custom claim or `projectflofile@gmail.com` per `firestore.rules`).

In the app:

- **Admin:** arrange verbs or IPTC, then **Publish** (Preferences → Team & Verb, or startup IPTC panel).
- **Users:** hide IPTC templates they do not want; **Restore app originals** in Preferences reloads the catalog from Firebase.

Deploy rules after changes:

```bash
firebase deploy --only firestore:rules
```

## Troubleshooting

| Issue | Fix |
|--------|-----|
| Google button disabled | Enable Google in Firebase; set `CLIENT_ID` in config + `Info.plist` |
| Keychain error (Google) | Select a Team in Xcode Signing & Capabilities; rebuild Debug. Entitlements need both `$(CFBundleIdentifier)` and `com.google.GIDSignIn` keychain groups. Delete stale `auth` in Keychain Access if needed. |
| `invalid_client` (Google) | `GIDClientID` / URL scheme must match Firebase plist |
