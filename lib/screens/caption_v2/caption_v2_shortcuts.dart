import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OpenSearchIntent extends Intent {
  const OpenSearchIntent();
}

class CloseSearchIntent extends Intent {
  const CloseSearchIntent();
}

class SaveNextIntent extends Intent {
  const SaveNextIntent();
}

class SaveTransmitNextIntent extends Intent {
  const SaveTransmitNextIntent();
}

class PastePreviousIntent extends Intent {
  const PastePreviousIntent();
}

class TransmitIntent extends Intent {
  const TransmitIntent();
}

class ApplyLastComboIntent extends Intent {
  const ApplyLastComboIntent();
}

class SearchHitIntent extends Intent {
  const SearchHitIntent(this.digit);

  final int digit;
}

class NavigateFrameIntent extends Intent {
  const NavigateFrameIntent(this.delta);

  final int delta;
}

class CycleColumnIntent extends Intent {
  const CycleColumnIntent(this.delta);

  final int delta;
}

class ShiftNumberIntent extends Intent {
  const ShiftNumberIntent(this.number);

  final int number;
}

class JerseyDigitIntent extends Intent {
  const JerseyDigitIntent(this.digit, {required this.isHome});

  final int digit;
  final bool isHome;
}

/// An action which leaves the key available to an [EditableText].
///
/// Local roster, verb, and thumbnail focus handlers run before this ancestor
/// action. Returning false from [consumesKey] also prevents the global shortcut
/// layer from swallowing cursor movement, Tab, or printable input in editors.
class CaptionV2GuardedAction<T extends Intent> extends CallbackAction<T> {
  CaptionV2GuardedAction({
    required super.onInvoke,
    this.enabledWhen,
  });

  final bool Function()? enabledWhen;

  @override
  bool isEnabled(T intent) =>
      !captionV2FocusIsEditable() && (enabledWhen?.call() ?? true);

  @override
  bool consumesKey(T intent) => isEnabled(intent);
}

bool captionV2FocusIsEditable([FocusNode? focus]) {
  final context = (focus ?? FocusManager.instance.primaryFocus)?.context;
  if (context == null) return false;
  if (context.widget is EditableText) return true;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}

Map<ShortcutActivator, Intent> buildCaptionV2Shortcuts() {
  final shortcuts = <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
        const OpenSearchIntent(),
    const SingleActivator(LogicalKeyboardKey.keyK, control: true):
        const OpenSearchIntent(),
    const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
        const SaveNextIntent(),
    const SingleActivator(LogicalKeyboardKey.keyS, control: true):
        const SaveNextIntent(),
    const SingleActivator(LogicalKeyboardKey.enter, shift: true):
        const SaveNextIntent(),
    const SingleActivator(LogicalKeyboardKey.numpadEnter, shift: true):
        const SaveNextIntent(),
    const SingleActivator(
      LogicalKeyboardKey.enter,
      meta: true,
      shift: true,
    ): const SaveTransmitNextIntent(),
    const SingleActivator(
      LogicalKeyboardKey.enter,
      control: true,
      shift: true,
    ): const SaveTransmitNextIntent(),
    const SingleActivator(
      LogicalKeyboardKey.numpadEnter,
      meta: true,
      shift: true,
    ): const SaveTransmitNextIntent(),
    const SingleActivator(
      LogicalKeyboardKey.numpadEnter,
      control: true,
      shift: true,
    ): const SaveTransmitNextIntent(),
    const SingleActivator(
      LogicalKeyboardKey.keyV,
      meta: true,
      shift: true,
    ): const PastePreviousIntent(),
    const SingleActivator(
      LogicalKeyboardKey.keyV,
      control: true,
      shift: true,
    ): const PastePreviousIntent(),
    const SingleActivator(LogicalKeyboardKey.keyF, shift: true):
        const TransmitIntent(),
    const SingleActivator(LogicalKeyboardKey.enter):
        const ApplyLastComboIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowLeft):
        const NavigateFrameIntent(-1),
    const SingleActivator(LogicalKeyboardKey.arrowUp):
        const NavigateFrameIntent(-1),
    const SingleActivator(LogicalKeyboardKey.arrowRight):
        const NavigateFrameIntent(1),
    const SingleActivator(LogicalKeyboardKey.arrowDown):
        const NavigateFrameIntent(1),
    const SingleActivator(LogicalKeyboardKey.tab): const CycleColumnIntent(1),
    const SingleActivator(LogicalKeyboardKey.tab, shift: true):
        const CycleColumnIntent(-1),
    const SingleActivator(LogicalKeyboardKey.escape): const CloseSearchIntent(),
  };

  for (var digit = 0; digit <= 9; digit++) {
    final key = _digitKeys[digit];
    final numpadKey = _numpadDigitKeys[digit];
    if (digit > 0) {
      shortcuts[SingleActivator(key)] = SearchHitIntent(digit);
      shortcuts[SingleActivator(numpadKey)] = SearchHitIntent(digit);
    }
    final assignedNumber = digit == 0 ? 10 : digit;
    shortcuts[SingleActivator(key, shift: true)] =
        ShiftNumberIntent(assignedNumber);
    shortcuts[SingleActivator(numpadKey, shift: true)] =
        ShiftNumberIntent(assignedNumber);

    for (final digitKey in [key, numpadKey]) {
      shortcuts[SingleActivator(digitKey, control: true)] =
          JerseyDigitIntent(digit, isHome: true);
      shortcuts[SingleActivator(digitKey, meta: true)] =
          JerseyDigitIntent(digit, isHome: false);
      shortcuts[SingleActivator(digitKey, alt: true)] =
          JerseyDigitIntent(digit, isHome: false);
    }
  }
  return shortcuts;
}

const _digitKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit0,
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

const _numpadDigitKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.numpad0,
  LogicalKeyboardKey.numpad1,
  LogicalKeyboardKey.numpad2,
  LogicalKeyboardKey.numpad3,
  LogicalKeyboardKey.numpad4,
  LogicalKeyboardKey.numpad5,
  LogicalKeyboardKey.numpad6,
  LogicalKeyboardKey.numpad7,
  LogicalKeyboardKey.numpad8,
  LogicalKeyboardKey.numpad9,
];
