import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// macOS [NSSpellChecker] via platform channel. No-op on other platforms.
class MacSpellCheckService implements SpellCheckService {
  MacSpellCheckService();

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
    } catch (_) {
      return null;
    }
  }
}

/// FloFile spell-check config: macOS system checker, disabled elsewhere.
SpellCheckConfiguration floSpellCheckConfiguration() {
  if (!MacSpellCheckService.isSupported) {
    return const SpellCheckConfiguration.disabled();
  }
  return SpellCheckConfiguration(
    spellCheckService: MacSpellCheckService(),
    misspelledTextStyle: const TextStyle(
      decoration: TextDecoration.underline,
      decorationColor: Color(0xFFE53935),
      decorationStyle: TextDecorationStyle.wavy,
    ),
    misspelledSelectionColor: const Color(0x66E53935),
    spellCheckSuggestionsToolbarBuilder: (context, editableTextState) {
      return SpellCheckSuggestionsToolbar.editableText(
        editableTextState: editableTextState,
      );
    },
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
