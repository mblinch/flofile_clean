import FlutterMacOS
import Foundation
import Security

/// Clears stale Google / Firebase auth Keychain items so Sign-In can recover
/// without asking the user to open Keychain Access.
class MacAuthKeychainPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "caption_writer/auth_keychain",
      binaryMessenger: registrar.messenger
    )
    let instance = MacAuthKeychainPlugin()
    channel.setMethodCallHandler(instance.handle)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "clearStaleAuthItems":
      result(clearStaleAuthItems())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Deletes generic-password items that look like FloFile / Google / Firebase
  /// auth leftovers, plus the file-backed Firebase Auth store. Returns how many
  /// Keychain items were removed.
  private func clearStaleAuthItems() -> Int {
    clearFileBackedAuthStore()
    return clearKeychainAuthItems()
  }

  private func clearFileBackedAuthStore() {
    let base = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first
    guard let base else { return }
    let dir = base.appendingPathComponent("FloFile/FirebaseAuthStore", isDirectory: true)
    try? FileManager.default.removeItem(at: dir)
  }

  private func clearKeychainAuthItems() -> Int {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecMatchLimit as String: kSecMatchLimitAll,
      kSecReturnAttributes as String: true,
    ]

    var raw: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &raw)
    guard status == errSecSuccess, let items = raw as? [[String: Any]] else {
      return 0
    }

    let bundleId = Bundle.main.bundleIdentifier?.lowercased() ?? ""
    var deleted = 0
    for item in items {
      guard shouldDelete(item, bundleId: bundleId) else { continue }
      var deleteQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
      ]
      if let service = item[kSecAttrService as String] {
        deleteQuery[kSecAttrService as String] = service
      }
      if let account = item[kSecAttrAccount as String] {
        deleteQuery[kSecAttrAccount as String] = account
      }
      if let accessGroup = item[kSecAttrAccessGroup as String] {
        deleteQuery[kSecAttrAccessGroup as String] = accessGroup
      }
      let del = SecItemDelete(deleteQuery as CFDictionary)
      if del == errSecSuccess || del == errSecItemNotFound {
        deleted += 1
      }
    }
    return deleted
  }

  private func shouldDelete(_ item: [String: Any], bundleId: String) -> Bool {
    let service = stringAttr(item[kSecAttrService as String]).lowercased()
    let account = stringAttr(item[kSecAttrAccount as String]).lowercased()
    let label = stringAttr(item[kSecAttrLabel as String]).lowercased()
    let accessGroup = stringAttr(item[kSecAttrAccessGroup as String]).lowercased()
    let haystack = "\(service) \(account) \(label) \(accessGroup)"

    let markers = [
      "gtmappauth",
      "gidsignin",
      "google.gidsignin",
      "firebase_auth",
      "firebaseauth",
      "flofile",
      "quick_cap",
      "quickcap",
      "com.flofilecaptions.app",
    ]
    if markers.contains(where: { haystack.contains($0) }) {
      return true
    }
    if !bundleId.isEmpty &&
      (service.contains(bundleId) || accessGroup.contains(bundleId)) {
      return true
    }
    // Stale single-word "auth" items tied to our access group / label.
    if (service == "auth" || account == "auth" || label.contains("auth")) &&
      (accessGroup.contains("flofile") ||
        label.contains("flofile") ||
        (!bundleId.isEmpty && accessGroup.contains(bundleId))) {
      return true
    }
    return false
  }

  private func stringAttr(_ value: Any?) -> String {
    if let s = value as? String { return s }
    if let data = value as? Data {
      return String(data: data, encoding: .utf8) ?? ""
    }
    return ""
  }
}
