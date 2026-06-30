#!/bin/bash
# Patches Google Sign-In / GTMAppAuth for macOS Developer ID builds on macOS 26+.
#
# Problem: Google Sign-In saves OAuth tokens to the keychain after login. Developer ID
# apps cannot use keychain-access-groups without an embedded provisioning profile
# (launch fails with error 163). Without that entitlement, keychain save fails and
# Google Sign-In reports a generic keychain error even though OAuth succeeded.
#
# Fix:
# 1) GTMAppAuth uses the login keychain (not Data Protection Keychain).
# 2) GIDSignIn treats keychain save failure as non-fatal on macOS (Firebase Auth
#    persists the signed-in user separately).
# 3) Skip macOS data-protection keychain migration in GIDAuthStateMigration.
# 4) FirebaseAuth uses the file-based login keychain on macOS instead of the Data
#    Protection Keychain. This is the actual source of the "keychain error" dialog
#    after Google sign-in: Firebase Auth (not Google Sign-In) persists the signed-in
#    user, and on Developer ID builds without keychain-access-groups the Data
#    Protection Keychain is inaccessible (errSecMissingEntitlement / errSecParam).
#
# Run before `flutter build macos`. Also invoked from sparkle_release.sh.
#
# Usage: ./tool/patch_gtm_keychain.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

KEYCHAIN_DIR="$ROOT/build/macos/SourcePackages/checkouts/GTMAppAuth/GTMAppAuth/Sources/KeychainStore"
KEYCHAIN_HELPER="$KEYCHAIN_DIR/KeychainHelper.swift"
KEYCHAIN_STORE="$KEYCHAIN_DIR/KeychainStore.swift"
GID_SIGNIN="$ROOT/build/macos/SourcePackages/checkouts/GoogleSignIn-iOS/GoogleSignIn/Sources/GIDSignIn.m"
GID_MIGRATION="$ROOT/build/macos/SourcePackages/checkouts/GoogleSignIn-iOS/GoogleSignIn/Sources/GIDAuthStateMigration/Implementation/GIDAuthStateMigration.m"
FIREBASE_AUTH_KEYCHAIN="$ROOT/build/macos/SourcePackages/checkouts/firebase-ios-sdk/FirebaseAuth/Sources/Swift/Storage/AuthKeychainServices.swift"

if [ ! -f "$KEYCHAIN_HELPER" ] || [ ! -f "$KEYCHAIN_STORE" ]; then
  echo "Error: GTMAppAuth not found at expected path." >&2
  echo "Run 'flutter build macos --release' once to resolve SPM packages, then re-run." >&2
  exit 1
fi

if [ ! -f "$GID_SIGNIN" ] || [ ! -f "$GID_MIGRATION" ]; then
  echo "Error: GoogleSignIn-iOS not found at expected path." >&2
  echo "Run 'flutter build macos --release' once to resolve SPM packages, then re-run." >&2
  exit 1
fi

if [ ! -f "$FIREBASE_AUTH_KEYCHAIN" ]; then
  echo "Error: FirebaseAuth not found at expected path." >&2
  echo "Run 'flutter build macos --release' once to resolve SPM packages, then re-run." >&2
  exit 1
fi

chmod u+w "$KEYCHAIN_HELPER" "$KEYCHAIN_STORE" "$GID_SIGNIN" "$GID_MIGRATION" "$FIREBASE_AUTH_KEYCHAIN" 2>/dev/null || true

python3 - "$KEYCHAIN_HELPER" "$KEYCHAIN_STORE" "$GID_SIGNIN" "$GID_MIGRATION" "$FIREBASE_AUTH_KEYCHAIN" <<'PY'
from pathlib import Path
import sys

helper_path = Path(sys.argv[1])
store_path = Path(sys.argv[2])
gid_signin_path = Path(sys.argv[3])
gid_migration_path = Path(sys.argv[4])
firebase_auth_path = Path(sys.argv[5])

changed = False

old_flag = """    if #available(macOS 10.15, macCatalyst 13.1, iOS 13.0, tvOS 13.0, watchOS 6.0, *) {
      query[kSecUseDataProtectionKeychain as String] = kCFBooleanTrue
    }"""
new_flag = """    if #available(macOS 10.15, macCatalyst 13.1, iOS 13.0, tvOS 13.0, watchOS 6.0, *) {
      // FloFile patch: on macOS Developer ID builds, the Data Protection
      // Keychain requires keychain-access-groups + provisioning. Omit this flag
      // so GTMAppAuth uses the regular login keychain instead.
      #if !os(macOS) || targetEnvironment(macCatalyst)
      query[kSecUseDataProtectionKeychain as String] = kCFBooleanTrue
      #endif
    }"""

old_set = """  func setPassword(data: Data, forService service: String, accessibility: CFTypeRef?) throws {
    guard !service.isEmpty else { throw KeychainStore.Error.noService }
    do {
      try removePassword(forService: service)
    } catch KeychainStore.Error.failedToDeletePasswordBecauseItemNotFound {
      // Don't throw; password doesn't exist since the password is being saved for the first time
    } catch {
      // throw here since this is some other error
      throw error
    }
    guard !data.isEmpty else { return }
    var keychainQuery = keychainQuery(forService: service)
    keychainQuery[kSecValueData as String] = data

    if let accessibility = accessibility {
      keychainQuery[kSecAttrAccessible as String] = accessibility
    }

    let status = SecItemAdd(keychainQuery as CFDictionary, nil)
    guard status == noErr else {
      throw KeychainStore.Error.failedToSetPassword(forItemName: service)
    }
  }"""
new_set = """  func setPassword(data: Data, forService service: String, accessibility: CFTypeRef?) throws {
    guard !service.isEmpty else { throw KeychainStore.Error.noService }
    guard !data.isEmpty else { return }

    #if os(macOS) && !targetEnvironment(macCatalyst)
    let query = keychainQuery(forService: service)
    let updateAttributes = [kSecValueData as String: data]
    let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
    if updateStatus == errSecSuccess { return }

    var addQuery = query
    addQuery[kSecValueData as String] = data
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    if addStatus == errSecSuccess { return }

    if addStatus == errSecDuplicateItem {
      let retryStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
      if retryStatus == errSecSuccess { return }
    }

    throw KeychainStore.Error.failedToSetPassword(forItemName: service)
    #else
    do {
      try removePassword(forService: service)
    } catch KeychainStore.Error.failedToDeletePasswordBecauseItemNotFound {
      // Don't throw; password doesn't exist since the password is being saved for the first time
    } catch {
      // throw here since this is some other error
      throw error
    }
    var keychainQuery = keychainQuery(forService: service)
    keychainQuery[kSecValueData as String] = data

    if let accessibility = accessibility {
      keychainQuery[kSecAttrAccessible as String] = accessibility
    }

    let status = SecItemAdd(keychainQuery as CFDictionary, nil)
    guard status == noErr else {
      throw KeychainStore.Error.failedToSetPassword(forItemName: service)
    }
    #endif
  }"""

old_init = """  @objc public convenience init(itemName: String) {
    self.init(itemName: itemName, keychainHelper: KeychainWrapper())
  }"""
new_init = """  @objc public convenience init(itemName: String) {
    #if os(macOS)
    // FloFile patch: Developer ID apps on macOS 26+ cannot use the Data
    // Protection Keychain without provisioning-backed keychain-access-groups.
    // Use GTMAppAuth's built-in file-based keychain mode so Google Sign-In
    // stores tokens in the normal login keychain.
    self.init(
      itemName: itemName,
      keychainAttributes: [.useFileBasedKeychain]
    )
    #else
    self.init(itemName: itemName, keychainHelper: KeychainWrapper())
    #endif
  }"""

old_save = """- (BOOL)saveAuthState:(OIDAuthState *)authState {
  GTMAuthSession *authorization = [[GTMAuthSession alloc] initWithAuthState:authState];
  NSError *error;
  [_keychainStore saveAuthSession:authorization error:&error];
  return error == nil;
}"""
new_save = """- (BOOL)saveAuthState:(OIDAuthState *)authState {
#if TARGET_OS_OSX
  // FloFile patch: on macOS Developer ID builds the signed-in user is persisted by
  // Firebase Auth. Skip GTMAppAuth's own keychain write entirely so we don't create a
  // second login-keychain item (and a second macOS access prompt). OAuth already succeeded.
  return YES;
#else
  GTMAuthSession *authorization = [[GTMAuthSession alloc] initWithAuthState:authState];
  NSError *error;
  [_keychainStore saveAuthSession:authorization error:&error];
  return error == nil;
#endif
}"""

old_migration = """- (void)performDataProtectedMigrationIfNeeded {
  // See if we've performed the migration check previously.
  NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];"""
new_migration = """- (void)performDataProtectedMigrationIfNeeded {
  // FloFile patch: skip macOS data-protection keychain migration for Developer ID builds.
  return;
  // See if we've performed the migration check previously.
  NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];"""

helper_text = helper_path.read_text()
if "FloFile patch: on macOS Developer ID builds" not in helper_text:
    if old_flag not in helper_text:
        raise SystemExit("Could not find GTMAppAuth Data Protection block to patch")
    helper_text = helper_text.replace(old_flag, new_flag, 1)
    changed = True
if "SecItemUpdate(query as CFDictionary" not in helper_text:
    if old_set not in helper_text:
        raise SystemExit("Could not find GTMAppAuth setPassword implementation to patch")
    helper_text = helper_text.replace(old_set, new_set, 1)
    changed = True
if changed:
    helper_path.write_text(helper_text)

store_text = store_path.read_text()
if "FloFile patch: Developer ID apps" not in store_text:
    if old_init not in store_text:
        raise SystemExit("Could not find GTMAppAuth KeychainStore initializer to patch")
    store_text = store_text.replace(old_init, new_init, 1)
    store_path.write_text(store_text)
    changed = True

gid_text = gid_signin_path.read_text()
if "FloFile patch: on macOS Developer ID builds the signed-in user is persisted by" not in gid_text:
    if old_save not in gid_text:
        raise SystemExit("Could not find GIDSignIn saveAuthState to patch")
    gid_text = gid_text.replace(old_save, new_save, 1)
    gid_signin_path.write_text(gid_text)
    changed = True

migration_text = gid_migration_path.read_text()
if "FloFile patch: skip macOS data-protection keychain migration" not in migration_text:
    if old_migration not in migration_text:
        raise SystemExit("Could not find GIDAuthStateMigration performDataProtectedMigrationIfNeeded to patch")
    migration_text = migration_text.replace(old_migration, new_migration, 1)
    gid_migration_path.write_text(migration_text)
    changed = True

# --- FirebaseAuth keychain patch (the real fix) ---
old_fb_query = """    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: kAccountPrefix + key,
      kSecAttrService as String: service,
    ]
    query[kSecUseDataProtectionKeychain as String] = true
    return query"""
new_fb_query = """    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: kAccountPrefix + key,
      kSecAttrService as String: service,
    ]
    #if os(macOS)
    // FloFile patch: Developer ID macOS apps without a keychain-access-group
    // entitlement cannot use the data protection keychain (operations fail with
    // errSecMissingEntitlement / errSecParam). Use the classic file-based login
    // keychain instead so the Firebase Auth session persists.
    query[kSecUseDataProtectionKeychain as String] = false
    #else
    query[kSecUseDataProtectionKeychain as String] = true
    #endif
    return query"""

old_fb_legacy = """  func setItemLegacy(_ item: Data, withQuery query: [String: Any]) throws {
    let attributes: [String: Any] = [
      kSecValueData as String: item,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]"""
new_fb_legacy = """  func setItemLegacy(_ item: Data, withQuery query: [String: Any]) throws {
    #if os(macOS)
    // FloFile patch: kSecAttrAccessible is a data-protection-keychain attribute and is
    // rejected (errSecParam) by the file-based keychain used on macOS Developer ID builds.
    let attributes: [String: Any] = [
      kSecValueData as String: item,
    ]
    #else
    let attributes: [String: Any] = [
      kSecValueData as String: item,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    #endif"""

firebase_text = firebase_auth_path.read_text()
fb_changed = False
if "FloFile patch: Developer ID macOS apps without a keychain-access-group" not in firebase_text:
    if old_fb_query not in firebase_text:
        raise SystemExit("Could not find FirebaseAuth genericPasswordQuery to patch")
    firebase_text = firebase_text.replace(old_fb_query, new_fb_query, 1)
    fb_changed = True
if "FloFile patch: kSecAttrAccessible is a data-protection-keychain attribute" not in firebase_text:
    if old_fb_legacy not in firebase_text:
        raise SystemExit("Could not find FirebaseAuth setItemLegacy to patch")
    firebase_text = firebase_text.replace(old_fb_legacy, new_fb_legacy, 1)
    fb_changed = True
if fb_changed:
    firebase_auth_path.write_text(firebase_text)
    changed = True

if changed:
    print("Google Sign-In / GTMAppAuth macOS keychain patches applied.")
else:
    print("Google Sign-In / GTMAppAuth macOS keychain patches already applied.")
PY
