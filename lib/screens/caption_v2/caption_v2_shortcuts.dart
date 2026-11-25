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

/// What [CaptionV2Screen]'s hardware save handler should do for one key-down.
enum CaptionV2SaveChord { none, save, savePrevious, transmit, burst }

/// Maps a key-down to save, save-previous, FTP, or Save to Burst.
///
/// ⌘Enter / Ctrl+Enter is the primary save (& next). ⌘S / Ctrl+S and
/// Shift+Enter stay as aliases (Shift may still be down on ⌘S after a
/// range select). ⌘⇧Enter / Ctrl⇧Enter saves & previous. FTP is ⌘U /
/// Ctrl+U (upload). ⌘B / Ctrl+B saves the current caption to the forward
/// burst. Plain Enter is not a save chord, so Firebar can apply the
/// shorthand line.
CaptionV2SaveChord captionV2SaveChord({
  required LogicalKeyboardKey key,
  required bool shift,
  required bool meta,
  required bool control,
  required bool alt,
  required bool ftpMode,
}) {
  final isEnter = key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter;
  final isS = key == LogicalKeyboardKey.keyS;
  final isB = key == LogicalKeyboardKey.keyB;
  final isU = key == LogicalKeyboardKey.keyU;
  final metaOrControl = meta || control;

  // ⌘⇧Enter / Ctrl⇧Enter → save & previous.
  if (isEnter && shift && metaOrControl) {
    return CaptionV2SaveChord.savePrevious;
  }
  // ⌘Enter / Ctrl+Enter → save & next.
  if (isEnter && metaOrControl && !shift && !alt) {
    return CaptionV2SaveChord.save;
  }
  // Shift+Enter → save (same as ⌘Enter).
  if (isEnter && shift && !metaOrControl && !alt) {
    return CaptionV2SaveChord.save;
  }
  // Ignore Shift so ⌘S still works right after Shift-click multi-select.
  if (isS && metaOrControl && !alt) {
    return CaptionV2SaveChord.save;
  }
  // ⌘U / Ctrl+U → FTP / upload (or save when FTP mode is off).
  if (isU && metaOrControl && !alt && !shift) {
    return ftpMode ? CaptionV2SaveChord.transmit : CaptionV2SaveChord.save;
  }
  // ⌘B / Ctrl+B → Save to Burst (when a multi-frame burst is available).
  if (isB && metaOrControl && !alt && !shift) {
    return CaptionV2SaveChord.burst;
  }
  return CaptionV2SaveChord.none;
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
    // ⌘↵ / ⌘S / Shift+Enter (save), ⌘⇧↵ (save & prev), ⌘U (FTP) are
    // handled by CaptionV2Screen's hardware key handler so they still work
    // when focus is outside the Shortcuts tree.
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
