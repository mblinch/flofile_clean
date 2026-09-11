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
# 2) GIDSignIn skips GTMAppAuth keychain read/write on macOS (Firebase Auth
#    persists the signed-in user separately).
# 3) Skip macOS data-protection keychain migration in GIDAuthStateMigration.
# 4) FirebaseAuth avoids Data Protection Keychain flags that fail on Developer ID.
# 5) FirebaseAuth storage on macOS is file-backed (Application Support) so users
#    never see the login-keychain password dialog for firebase_auth_* items.
#
# Run before `flutter build macos`. Also invoked from sparkle_release.sh.
#
# Usage: ./tool/patch_gtm_keychain.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Prefer CocoaPods checkouts (current Flutter macOS integration). Fall back to
# SPM SourcePackages used by older builds.
if [ -f "$ROOT/macos/Pods/GTMAppAuth/GTMAppAuth/Sources/KeychainStore/KeychainHelper.swift" ]; then
  KEYCHAIN_DIR="$ROOT/macos/Pods/GTMAppAuth/GTMAppAuth/Sources/KeychainStore"
  GID_SIGNIN="$ROOT/macos/Pods/GoogleSignIn/GoogleSignIn/Sources/GIDSignIn.m"
  GID_MIGRATION="$ROOT/macos/Pods/GoogleSignIn/GoogleSignIn/Sources/GIDAuthStateMigration/Implementation/GIDAuthStateMigration.m"
  FIREBASE_AUTH_KEYCHAIN="$ROOT/macos/Pods/FirebaseAuth/FirebaseAuth/Sources/Swift/Storage/AuthKeychainServices.swift"
  FIREBASE_AUTH_STORAGE="$ROOT/macos/Pods/FirebaseAuth/FirebaseAuth/Sources/Swift/Storage/AuthKeychainStorageReal.swift"
  PATCH_SOURCE="CocoaPods"
else
  KEYCHAIN_DIR="$ROOT/build/macos/SourcePackages/checkouts/GTMAppAuth/GTMAppAuth/Sources/KeychainStore"
  GID_SIGNIN="$ROOT/build/macos/SourcePackages/checkouts/GoogleSignIn-iOS/GoogleSignIn/Sources/GIDSignIn.m"
  GID_MIGRATION="$ROOT/build/macos/SourcePackages/checkouts/GoogleSignIn-iOS/GoogleSignIn/Sources/GIDAuthStateMigration/Implementation/GIDAuthStateMigration.m"
  FIREBASE_AUTH_KEYCHAIN="$ROOT/build/macos/SourcePackages/checkouts/firebase-ios-sdk/FirebaseAuth/Sources/Swift/Storage/AuthKeychainServices.swift"
  FIREBASE_AUTH_STORAGE="$ROOT/build/macos/SourcePackages/checkouts/firebase-ios-sdk/FirebaseAuth/Sources/Swift/Storage/AuthKeychainStorageReal.swift"
  PATCH_SOURCE="SPM SourcePackages"
fi
KEYCHAIN_HELPER="$KEYCHAIN_DIR/KeychainHelper.swift"
KEYCHAIN_STORE="$KEYCHAIN_DIR/KeychainStore.swift"

if [ ! -f "$KEYCHAIN_HELPER" ] || [ ! -f "$KEYCHAIN_STORE" ]; then
  echo "Error: GTMAppAuth not found at expected path." >&2
  echo "Run 'flutter build macos --release' once to resolve packages, then re-run." >&2
  exit 1
fi

if [ ! -f "$GID_SIGNIN" ] || [ ! -f "$GID_MIGRATION" ]; then
  echo "Error: GoogleSignIn not found at expected path." >&2
  echo "Run 'flutter build macos --release' once to resolve packages, then re-run." >&2
  exit 1
fi

if [ ! -f "$FIREBASE_AUTH_KEYCHAIN" ] || [ ! -f "$FIREBASE_AUTH_STORAGE" ]; then
  echo "Error: FirebaseAuth not found at expected path." >&2
  echo "Run 'flutter build macos --release' once to resolve packages, then re-run." >&2
  exit 1
fi

echo "Patching Google Sign-In keychain sources from $PATCH_SOURCE..."

chmod u+w "$KEYCHAIN_HELPER" "$KEYCHAIN_STORE" "$GID_SIGNIN" "$GID_MIGRATION" "$FIREBASE_AUTH_KEYCHAIN" "$FIREBASE_AUTH_STORAGE" 2>/dev/null || true

python3 - "$KEYCHAIN_HELPER" "$KEYCHAIN_STORE" "$GID_SIGNIN" "$GID_MIGRATION" "$FIREBASE_AUTH_KEYCHAIN" "$FIREBASE_AUTH_STORAGE" <<'PY'
from pathlib import Path
import sys

helper_path = Path(sys.argv[1])
store_path = Path(sys.argv[2])
gid_signin_path = Path(sys.argv[3])
gid_migration_path = Path(sys.argv[4])
firebase_auth_path = Path(sys.argv[5])
firebase_storage_path = Path(sys.argv[6])

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

old_load = """- (OIDAuthState *)loadAuthState {
  GTMAuthSession *authorization = [_keychainStore retrieveAuthSessionWithError:nil];
  return authorization.authState;
}"""
new_load = """- (OIDAuthState *)loadAuthState {
#if TARGET_OS_OSX
  // FloFile patch: Firebase Auth persists the session on macOS. Never read Google
  // tokens from the login keychain (avoids the separate "auth" keychain prompt).
  return nil;
#else
  GTMAuthSession *authorization = [_keychainStore retrieveAuthSessionWithError:nil];
  return authorization.authState;
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
if "FloFile patch: Firebase Auth persists the session on macOS. Never read Google" not in gid_text:
    if old_load not in gid_text:
        raise SystemExit("Could not find GIDSignIn loadAuthState to patch")
    gid_text = gid_text.replace(old_load, new_load, 1)
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

# --- Never call macOS SecItem* (eliminates login-keychain password prompts) ---
file_backed_storage = r'''// Copyright 2023 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Security

/// FloFile patch: file-backed Auth storage on macOS.
///
/// Developer ID builds cannot silently use the login keychain without prompting
/// the user for their password whenever the app signature changes. Persist
/// Firebase Auth sessions under Application Support instead of SecItem*.
final class AuthKeychainStorageReal: AuthKeychainStorage {
  static let shared: AuthKeychainStorageReal = .init()

  private let lock = NSLock()
  private init() {}

  #if os(macOS)
    private func storeURL() -> URL {
      let base = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first!
      let dir = base.appendingPathComponent("FloFile/FirebaseAuthStore", isDirectory: true)
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      return dir.appendingPathComponent("items.json")
    }

    private func storageKey(from query: [String: Any]) -> String {
      let account = query[kSecAttrAccount as String] as? String ?? ""
      let service = query[kSecAttrService as String] as? String ?? ""
      let group = query[kSecAttrAccessGroup as String] as? String ?? ""
      return "\(group)|\(service)|\(account)"
    }

    private func loadMap() -> [String: Data] {
      let url = storeURL()
      guard let raw = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: raw) as? [String: String]
      else { return [:] }
      var out: [String: Data] = [:]
      for (key, b64) in json {
        if let data = Data(base64Encoded: b64) {
          out[key] = data
        }
      }
      return out
    }

    private func saveMap(_ map: [String: Data]) {
      var json: [String: String] = [:]
      for (key, data) in map {
        json[key] = data.base64EncodedString()
      }
      guard let raw = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
      else { return }
      try? raw.write(to: storeURL(), options: [.atomic])
    }

    func get(query: [String: Any], result: inout AnyObject?) -> OSStatus {
      lock.lock()
      defer { lock.unlock() }
      let key = storageKey(from: query)
      guard let data = loadMap()[key] else {
        return errSecItemNotFound
      }
      let item: [String: Any] = [
        kSecValueData as String: data,
        kSecAttrAccount as String: (query[kSecAttrAccount as String] as? String) ?? "",
        kSecAttrService as String: (query[kSecAttrService as String] as? String) ?? "",
      ]
      result = [item] as AnyObject
      return noErr
    }

    func add(query: [String: Any]) -> OSStatus {
      lock.lock()
      defer { lock.unlock() }
      guard let data = query[kSecValueData as String] as? Data else {
        return errSecParam
      }
      let key = storageKey(from: query)
      var map = loadMap()
      if map[key] != nil {
        return errSecDuplicateItem
      }
      map[key] = data
      saveMap(map)
      return noErr
    }

    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
      lock.lock()
      defer { lock.unlock() }
      let key = storageKey(from: query)
      var map = loadMap()
      guard map[key] != nil else {
        return errSecItemNotFound
      }
      if let data = attributes[kSecValueData as String] as? Data {
        map[key] = data
      }
      saveMap(map)
      return noErr
    }

    @discardableResult func delete(query: [String: Any]) -> OSStatus {
      lock.lock()
      defer { lock.unlock() }
      let key = storageKey(from: query)
      var map = loadMap()
      guard map.removeValue(forKey: key) != nil else {
        return errSecItemNotFound
      }
      saveMap(map)
      return noErr
    }
  #else
    func get(query: [String: Any], result: inout AnyObject?) -> OSStatus {
      return SecItemCopyMatching(query as CFDictionary, &result)
    }

    func add(query: [String: Any]) -> OSStatus {
      return SecItemAdd(query as CFDictionary, nil)
    }

    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
      SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    @discardableResult func delete(query: [String: Any]) -> OSStatus {
      return SecItemDelete(query as CFDictionary)
    }
  #endif
}
'''

storage_text = firebase_storage_path.read_text()
if "FloFile patch: file-backed Auth storage on macOS" not in storage_text:
    firebase_storage_path.write_text(file_backed_storage)
    changed = True

if changed:
    print("Google Sign-In / GTMAppAuth macOS keychain patches applied.")
else:
    print("Google Sign-In / GTMAppAuth macOS keychain patches already applied.")
PY
