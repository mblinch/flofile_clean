import 'caption_template.dart';

/// Getty's legal note, with or without the NBAE copyright line.
///
/// Getty:
/// `NOTE TO USER: ... Getty Images License Agreement.`
///
/// NBAE adds `Mandatory Copyright Notice: Copyright <year> NBAE`.
class GettyNoteVariant {
  static final RegExp _copyrightLine = RegExp(
    r'\s*Mandatory Copyright Notice: Copyright \d{4} NBAE',
  );

  static String copyrightLine([DateTime? now]) =>
      'Mandatory Copyright Notice: Copyright ${(now ?? DateTime.now()).year} NBAE';

  /// The copyright line is only for Getty basketball.
  static bool applies({
    required bool enabled,
    required WireStyle wire,
    required String sport,
  }) {
    final getty =
        wire == WireStyle.getty || wire == WireStyle.gettyInternational;
    return enabled && getty && sport.trim().toLowerCase() == 'basketball';
  }

  /// Puts the copyright line on the note, immediately after the license
  /// agreement.
  ///
  /// A finished caption is left alone unless [insertIfMissing] is set. The
  /// line is only written into text the author already included, or when the
  /// NBAE control explicitly inserts it into the snippet.
  static String apply(
    String text, {
    required bool nbae,
    bool insertIfMissing = false,
  }) {
    if (!text.contains('NOTE TO USER:')) return text;
    if (!text.contains('Getty Images License Agreement')) return text;
    final stripped = text.replaceAll(_copyrightLine, '');
    if (!nbae) return stripped;
    if (!insertIfMissing && !_copyrightLine.hasMatch(text)) return text;
    const marker = 'Getty Images License Agreement.';
    final at = stripped.indexOf(marker);
    if (at < 0) return stripped;
    final end = at + marker.length;
    final rest = stripped.substring(end);
    return '${stripped.substring(0, end)} ${copyrightLine()}$rest';
  }

  static List<String>? _list(
    List<String>? values,
    bool nbae, {
    bool insertIfMissing = false,
  }) {
    if (values == null) return null;
    return [
      for (final value in values)
        apply(value, nbae: nbae, insertIfMissing: insertIfMissing),
    ];
  }

  static CaptionTemplate applyToTemplate(
    CaptionTemplate template, {
    required bool nbae,
    bool insertIfMissing = false,
  }) {
    return template.copyWith(
      layoutPrefix: apply(
        template.layoutPrefix,
        nbae: nbae,
        insertIfMissing: insertIfMissing,
      ),
      layoutSuffix: apply(
        template.layoutSuffix,
        nbae: nbae,
        insertIfMissing: insertIfMissing,
      ),
      captionPrefix: apply(
        template.captionPrefix,
        nbae: nbae,
        insertIfMissing: insertIfMissing,
      ),
      captionSuffix: apply(
        template.captionSuffix,
        nbae: nbae,
        insertIfMissing: insertIfMissing,
      ),
      separator: apply(
        template.separator,
        nbae: nbae,
        insertIfMissing: insertIfMissing,
      ),
      separatorSnippets: _list(
        template.separatorSnippets,
        nbae,
        insertIfMissing: insertIfMissing,
      ),
      punctuationSnippets: _list(
        template.punctuationSnippets,
        nbae,
        insertIfMissing: insertIfMissing,
      ),
      freeTextSnippets: _list(
        template.freeTextSnippets,
        nbae,
        insertIfMissing: insertIfMissing,
      ),
      customSeparators: _list(
        template.customSeparators,
        nbae,
        insertIfMissing: insertIfMissing,
      ),
      basketballUserNote: apply(
        template.basketballUserNote,
        nbae: nbae,
        insertIfMissing: insertIfMissing,
      ),
    );
  }
}
