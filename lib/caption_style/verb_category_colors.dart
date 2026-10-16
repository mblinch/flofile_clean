import 'dart:ui' show Color;

/// Soft fill behind a player name in the caption. Distinct from verb colors.
const Color captionPlayerHighlight = Color(0xFF8FB4D4);

/// Soft warm fill behind a verb phrase in the caption.
const Color captionVerbHighlight = Color(0xFFC4A06A);

/// Colour for a verb phrase highlighted in the caption.
Color verbCategoryColor(String category) {
  final key = category.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  switch (key) {
    case 'favorites':
      return const Color(0xFFE0B15A);
    case 'offense':
      return const Color(0xFFE07A3D);
    case 'defense':
      return const Color(0xFF4C8DFF);
    case 'pitching':
      return const Color(0xFFB07CFF);
    case 'running':
      return const Color(0xFF3DBE8B);
    case 'reactions':
      return const Color(0xFFE25B8A);
    case 'nongameaction':
    case 'nongame':
      return const Color(0xFF3DB8C9);
    case 'all':
      return const Color(0xFF8A93A0);
    default:
      var hash = 0;
      for (final unit in key.codeUnits) {
        hash = (hash * 31 + unit) & 0xFFFFFF;
      }
      const palette = <Color>[
        Color(0xFFE07A3D),
        Color(0xFF4C8DFF),
        Color(0xFFB07CFF),
        Color(0xFF3DBE8B),
        Color(0xFFE25B8A),
        Color(0xFF3DB8C9),
        Color(0xFFD4A017),
        Color(0xFF7AA2FF),
      ];
      return palette[hash % palette.length];
  }
}
