#!/bin/bash
# Patches GTMAppAuth to use the legacy macOS file-based (login) keychain instead of
# the Data Protection Keychain. This avoids the need for a keychain-access-groups
# entitlement which requires a provisioning profile on macOS 26+.
#
# Run this ONCE after cloning the repo or after Xcode resets the SPM package cache
# (File → Packages → Reset Package Caches).
#
# The patch is also re-applied automatically during:
#   ./tool/macos_sign_and_notarize.sh (which calls this script)
#
# Usage: ./tool/patch_gtm_keychain.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

KEYCHAIN_DIR="$ROOT/build/macos/SourcePackages/checkouts/GTMAppAuth/GTMAppAuth/Sources/KeychainStore"
KEYCHAIN_HELPER="$KEYCHAIN_DIR/KeychainHelper.swift"
KEYCHAIN_STORE="$KEYCHAIN_DIR/KeychainStore.swift"

if [ ! -f "$KEYCHAIN_HELPER" ] || [ ! -f "$KEYCHAIN_STORE" ]; then
  echo "Error: GTMAppAuth not found at expected path." >&2
  echo "Run 'flutter build macos --release' first to resolve SPM packages, then re-run this script." >&2
  exit 1
fi

if grep -q "FloFile patch: on macOS Developer ID builds" "$KEYCHAIN_HELPER" 2>/dev/null \
    && grep -q "FloFile patch: Developer ID apps" "$KEYCHAIN_STORE" 2>/dev/null; then
  echo "GTMAppAuth keychain patch already applied — nothing to do."
  exit 0
fi

chmod u+w "$KEYCHAIN_HELPER"
chmod u+w "$KEYCHAIN_STORE"

python3 - "$KEYCHAIN_HELPER" "$KEYCHAIN_STORE" <<'PY'
from pathlib import Path
import sys

helper_path = Path(sys.argv[1])
store_path = Path(sys.argv[2])

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

helper_text = helper_path.read_text()
if "FloFile patch: on macOS Developer ID builds" not in helper_text:
    if old_flag not in helper_text:
        raise SystemExit("Could not find Data Protection Keychain block to patch")
    helper_text = helper_text.replace(old_flag, new_flag, 1)

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

if "SecItemUpdate(query as CFDictionary" not in helper_text:
    if old_set not in helper_text:
        raise SystemExit("Could not find setPassword implementation to patch")
    helper_text = helper_text.replace(old_set, new_set, 1)

helper_path.write_text(helper_text)

store_text = store_path.read_text()
if "FloFile patch: Developer ID apps" not in store_text:
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
    if old_init not in store_text:
        raise SystemExit("Could not find KeychainStore itemName initializer to patch")
    store_text = store_text.replace(old_init, new_init, 1)
    store_path.write_text(store_text)
PY

echo "GTMAppAuth keychain patch applied successfully."
