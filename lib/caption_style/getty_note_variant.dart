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
  /// agreement. It must not be appended to the finished caption, or it lands
  /// after the byline.
  static String apply(String text, {required bool nbae}) {
    if (!text.contains('NOTE TO USER:')) return text;
    if (!text.contains('Getty Images License Agreement')) return text;
    final stripped = text.replaceAll(_copyrightLine, '');
    if (!nbae) return stripped;
    const marker = 'Getty Images License Agreement.';
    final at = stripped.indexOf(marker);
    if (at < 0) return stripped;
    final end = at + marker.length;
    final rest = stripped.substring(end);
    return '${stripped.substring(0, end)} ${copyrightLine()}$rest';
  }

  static List<String>? _list(List<String>? values, bool nbae) {
    if (values == null) return null;
    return [for (final value in values) apply(value, nbae: nbae)];
  }

  static CaptionTemplate applyToTemplate(
    CaptionTemplate template, {
    required bool nbae,
  }) {
    return template.copyWith(
      layoutPrefix: apply(template.layoutPrefix, nbae: nbae),
      layoutSuffix: apply(template.layoutSuffix, nbae: nbae),
      captionPrefix: apply(template.captionPrefix, nbae: nbae),
      captionSuffix: apply(template.captionSuffix, nbae: nbae),
      separator: apply(template.separator, nbae: nbae),
      separatorSnippets: _list(template.separatorSnippets, nbae),
      punctuationSnippets: _list(template.punctuationSnippets, nbae),
      freeTextSnippets: _list(template.freeTextSnippets, nbae),
      customSeparators: _list(template.customSeparators, nbae),
      basketballUserNote: apply(template.basketballUserNote, nbae: nbae),
    );
  }
}
