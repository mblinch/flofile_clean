import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// macOS [NSSpellChecker] via platform channel. No-op on other platforms.
class MacSpellCheckService implements SpellCheckService {
  MacSpellCheckService._();

  static final MacSpellCheckService instance = MacSpellCheckService._();

  static const _channel = MethodChannel('caption_writer/spell_check');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async {
    if (!isSupported || text.isEmpty) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('check', {
        'text': text,
        'locale': locale.toLanguageTag(),
      });
      if (raw == null || raw.isEmpty) return const [];
      return [
        for (final item in raw)
          if (item is Map)
            SuggestionSpan(
              TextRange(
                start: item['startIndex'] as int,
                end: item['endIndex'] as int,
              ),
              ((item['suggestions'] as List?) ?? const [])
                  .whereType<String>()
                  .toList(growable: false),
            ),
      ];
    } catch (e, st) {
      debugPrint('MacSpellCheckService failed: $e\n$st');
      // Empty list (not null) so Flutter clears stale underlines instead of
      // treating the request as cancelled.
      return const [];
    }
  }
}

SpellCheckConfiguration? _floSpellCheckConfig;

/// FloFile spell-check config: macOS system checker, disabled elsewhere.
SpellCheckConfiguration floSpellCheckConfiguration() {
  if (!MacSpellCheckService.isSupported) {
    return const SpellCheckConfiguration.disabled();
  }
  return _floSpellCheckConfig ??= SpellCheckConfiguration(
    spellCheckService: MacSpellCheckService.instance,
    misspelledTextStyle: const TextStyle(
      decoration: TextDecoration.underline,
      decorationColor: Color(0xFFE53935),
      decorationStyle: TextDecorationStyle.wavy,
      decorationThickness: 2.0,
    ),
    misspelledSelectionColor: const Color(0x66E53935),
    spellCheckSuggestionsToolbarBuilder: (context, editableTextState) {
      return CupertinoSpellCheckSuggestionsToolbar.editableText(
        editableTextState: editableTextState,
      );
    },
  );
}

/// Right-click menu with spelling replacements (desktop-friendly).
///
/// Flutter does not show the mobile-style spell toolbar on macOS mouse taps,
/// so suggestions live here instead.
Widget floSpellCheckContextMenuBuilder(
  BuildContext context,
  EditableTextState editableTextState,
) {
  final spellItems =
      SpellCheckSuggestionsToolbar.buildButtonItems(editableTextState) ??
          const <ContextMenuButtonItem>[];
  // Drop the "delete" action from the spell toolbar — keep replacements only.
  final replacements = spellItems
      .where((item) => item.type != ContextMenuButtonType.delete)
      .toList(growable: false);

  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: <ContextMenuButtonItem>[
      ...replacements,
      ...editableTextState.contextMenuButtonItems,
    ],
  );
}

/// True when running as a macOS desktop binary.
bool get floSpellCheckAvailable {
  if (kIsWeb) return false;
  try {
    return Platform.isMacOS;
  } catch (_) {
    return defaultTargetPlatform == TargetPlatform.macOS;
  }
}
