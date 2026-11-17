import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native helper: clear stale Google / Firebase Keychain auth items on macOS.
class MacAuthKeychain {
  MacAuthKeychain._();

  static const _channel = MethodChannel('caption_writer/auth_keychain');

  /// Returns how many items were deleted. No-op off macOS.
  static Future<int> clearStaleAuthItems() async {
    if (!Platform.isMacOS) return 0;
    try {
      final deleted = await _channel.invokeMethod<int>('clearStaleAuthItems');
      return deleted ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException catch (e) {
      debugPrint('[Auth] clearStaleAuthItems failed: $e');
      return 0;
    }
  }
}
