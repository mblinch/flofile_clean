import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Turns macOS Control-clicks into secondary clicks.
///
/// Flutter reports Control+primary click as a normal left click. macOS treats
/// that chord as a right-click, so context menus never open. This rewrites the
/// button on the pointer-down and keeps the same button for the rest of that
/// pointer so tap recognizers still see one consistent button.
///
/// Command-click is left as a primary click. This app uses it for pinning.
class MacControlClickPromoter {
  final Set<int> _pointers = <int>{};

  PointerEvent transform(
    PointerEvent event, {
    required bool macOS,
    required bool controlPressed,
    required bool metaPressed,
  }) {
    if (event is PointerRemovedEvent || event is PointerCancelEvent) {
      if (_pointers.remove(event.pointer)) {
        return event.copyWith(buttons: kSecondaryButton);
      }
      return event;
    }

    if (event is PointerDownEvent) {
      _pointers.remove(event.pointer);
      if (_isControlPrimaryClick(
        event,
        macOS: macOS,
        controlPressed: controlPressed,
        metaPressed: metaPressed,
      )) {
        _pointers.add(event.pointer);
        return event.copyWith(buttons: kSecondaryButton);
      }
      return event;
    }

    if (!_pointers.contains(event.pointer)) return event;

    if (event is PointerUpEvent) {
      _pointers.remove(event.pointer);
      return event.copyWith(buttons: kSecondaryButton);
    }
    if (event is PointerMoveEvent) {
      return event.copyWith(buttons: kSecondaryButton);
    }
    return event;
  }

  static bool _isControlPrimaryClick(
    PointerDownEvent event, {
    required bool macOS,
    required bool controlPressed,
    required bool metaPressed,
  }) {
    if (!macOS || metaPressed || !controlPressed) return false;
    if (event.buttons != kPrimaryButton) return false;
    return event.kind == PointerDeviceKind.mouse ||
        event.kind == PointerDeviceKind.trackpad;
  }
}

/// App binding that applies [MacControlClickPromoter] before gesture dispatch.
class FloWidgetsBinding extends WidgetsFlutterBinding {
  final MacControlClickPromoter _controlClick = MacControlClickPromoter();

  static WidgetsBinding ensureInitialized() => FloWidgetsBinding();

  @override
  void handlePointerEvent(PointerEvent event) {
    final keys = HardwareKeyboard.instance;
    super.handlePointerEvent(
      _controlClick.transform(
        event,
        macOS: defaultTargetPlatform == TargetPlatform.macOS,
        controlPressed: keys.isControlPressed,
        metaPressed: keys.isMetaPressed,
      ),
    );
  }
}
