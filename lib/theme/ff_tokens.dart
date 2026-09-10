import 'package:flutter/material.dart';

/// FloFile caption V2 design tokens.
///
/// All caption_v2 colors and text sizes live here — nowhere else.
/// Access via `Theme.of(context).extension<FfTokens>()!`.
@immutable
class FfTokens extends ThemeExtension<FfTokens> {
  static const firebar = Color(0xFFE8763A);

  const FfTokens({
    required this.bg,
    required this.surface,
    required this.sunken,
    required this.text,
    required this.accent,
    required this.inkOnAccent,
    required this.textSizeCaption,
    required this.textSizeBody,
    required this.textSizeLabel,
    required this.textSizeMeta,
    required this.textSizeMicro,
    required this.textSizeKeyHint,
    required this.textSizeJersey,
    required this.textSizeChip,
  });

  // ---------------------------------------------------------------------------
  // Colors (base)
  // ---------------------------------------------------------------------------

  final Color bg;
  final Color surface;
  final Color sunken;
  final Color text;
  final Color accent;

  /// Text drawn on a filled accent surface (e.g. selected jersey badge).
  final Color inkOnAccent;

  // ---------------------------------------------------------------------------
  // Colors (derived — never hard-coded at call sites)
  // ---------------------------------------------------------------------------

  Color get divider => text.withValues(alpha: 0.16);

  /// Selected row/tile fill: accent @ 16%.
  Color get selectedFill => accent.withValues(alpha: 0.16);

  /// Selected row/tile border: accent @ 50%.
  Color get selectedBorder => accent.withValues(alpha: 0.50);

  /// Number badge / inert chip fill: text @ 8%.
  Color get badgeFill => text.withValues(alpha: 0.08);

  /// Secondary label text: text @ 55%.
  Color get textSecondary => text.withValues(alpha: 0.55);

  /// Neutral filled status (saved-but-not-sent).
  Color get statusNeutral => text.withValues(alpha: 0.45);

  // ---------------------------------------------------------------------------
  // Text sizes
  // ---------------------------------------------------------------------------

  final double textSizeCaption;
  final double textSizeBody;
  final double textSizeLabel;
  final double textSizeMeta;
  final double textSizeMicro;
  final double textSizeKeyHint;
  final double textSizeJersey;
  final double textSizeChip;

  // ---------------------------------------------------------------------------
  // Radii (shared constants — identical in light/dark)
  // ---------------------------------------------------------------------------

  static const double radiusChip = 8;
  static const double radiusRow = 10;
  static const double radiusTile = 11;
  static const double radiusCard = 12;
  static const double radiusWindow = 14;

  // ---------------------------------------------------------------------------
  // Typography families / weights
  // ---------------------------------------------------------------------------

  static const String fontFamily = 'Inter';
  static const String labelFamily = 'InterTight';
  static const String monoFamily = 'JetBrainsMono';
  static const FontWeight weightRegular = FontWeight.w400;
  static const FontWeight weightMedium = FontWeight.w500;

  static const TextStyle captionTitle = TextStyle(
    fontFamily: labelFamily,
    fontWeight: FontWeight.w700,
    fontSize: 26,
    letterSpacing: -0.78,
    height: 1,
  );

  static const TextStyle railLabel = TextStyle(
    fontFamily: labelFamily,
    fontWeight: FontWeight.w600,
    fontSize: 11,
    letterSpacing: 1.5,
    height: 1,
  );

  static const TextStyle inningValue = TextStyle(
    fontFamily: labelFamily,
    fontWeight: FontWeight.w600,
    fontSize: 15,
    letterSpacing: 0,
    height: 1,
  );

  // ---------------------------------------------------------------------------
  // Hit targets (mobile minimums)
  // ---------------------------------------------------------------------------

  static const double hitRowMobile = 54;
  static const double hitVerbTileMobile = 58;
  static const double hitDockButtonMobile = 44;

  // ---------------------------------------------------------------------------
  // Focus ring
  // ---------------------------------------------------------------------------

  static const double focusOutlineWidth = 2;
  static const double focusOutlineOffset = 2;

  // ---------------------------------------------------------------------------
  // Text style helpers
  // ---------------------------------------------------------------------------

  TextStyle get captionStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: textSizeCaption,
        fontWeight: weightRegular,
        color: text,
        height: 1.45,
      );

  TextStyle get bodyStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: textSizeBody,
        fontWeight: weightRegular,
        color: text,
        height: 1.35,
      );

  TextStyle get labelStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: textSizeLabel,
        fontWeight: weightMedium,
        color: text,
        height: 1.3,
      );

  TextStyle get secondaryLabelStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: textSizeLabel,
        fontWeight: weightRegular,
        color: textSecondary,
        height: 1.3,
      );

  TextStyle get metaStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: textSizeMeta,
        fontWeight: weightRegular,
        color: textSecondary,
        height: 1.3,
      );

  TextStyle get microStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: textSizeMicro,
        fontWeight: weightMedium,
        color: textSecondary,
        letterSpacing: 0.4,
        height: 1.2,
      );

  TextStyle get chipStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: textSizeChip,
        fontWeight: weightMedium,
        color: text,
        height: 1.2,
      );

  TextStyle get jerseyStyle => TextStyle(
        fontFamily: monoFamily,
        fontSize: textSizeJersey,
        fontWeight: weightMedium,
        color: text,
        height: 1.1,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  TextStyle get keyHintStyle => TextStyle(
        fontFamily: monoFamily,
        fontSize: textSizeKeyHint,
        fontWeight: weightRegular,
        color: textSecondary,
        height: 1.1,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  TextStyle get monoMetaStyle => TextStyle(
        fontFamily: monoFamily,
        fontSize: textSizeMeta,
        fontWeight: weightRegular,
        color: textSecondary,
        height: 1.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  // ---------------------------------------------------------------------------
  // Presets
  // ---------------------------------------------------------------------------

  static const FfTokens dark = FfTokens(
    bg: Color(0xFF161826),
    surface: Color(0xFF232532),
    sunken: Color(0xFF1C1E2C),
    text: Color(0xFFE9E9ED),
    accent: Color(0xFF8792AB),
    inkOnAccent: Color(0xFF3C434F),
    textSizeCaption: 15,
    textSizeBody: 14,
    textSizeLabel: 13,
    textSizeMeta: 12,
    textSizeMicro: 11,
    textSizeKeyHint: 11,
    textSizeJersey: 12,
    textSizeChip: 13,
  );

  static const FfTokens light = FfTokens(
    bg: Color(0xFFF3F5FE),
    surface: Color(0xFFFFFFFF),
    sunken: Color(0xFFE8EAF4),
    text: Color(0xFF292B31),
    accent: Color(0xFF5C6577),
    inkOnAccent: Color(0xFFF3F5FE),
    textSizeCaption: 15,
    textSizeBody: 14,
    textSizeLabel: 13,
    textSizeMeta: 12,
    textSizeMicro: 11,
    textSizeKeyHint: 11,
    textSizeJersey: 12,
    textSizeChip: 13,
  );

  // ---------------------------------------------------------------------------
  // ThemeExtension
  // ---------------------------------------------------------------------------

  @override
  FfTokens copyWith({
    Color? bg,
    Color? surface,
    Color? sunken,
    Color? text,
    Color? accent,
    Color? inkOnAccent,
    double? textSizeCaption,
    double? textSizeBody,
    double? textSizeLabel,
    double? textSizeMeta,
    double? textSizeMicro,
    double? textSizeKeyHint,
    double? textSizeJersey,
    double? textSizeChip,
  }) {
    return FfTokens(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      sunken: sunken ?? this.sunken,
      text: text ?? this.text,
      accent: accent ?? this.accent,
      inkOnAccent: inkOnAccent ?? this.inkOnAccent,
      textSizeCaption: textSizeCaption ?? this.textSizeCaption,
      textSizeBody: textSizeBody ?? this.textSizeBody,
      textSizeLabel: textSizeLabel ?? this.textSizeLabel,
      textSizeMeta: textSizeMeta ?? this.textSizeMeta,
      textSizeMicro: textSizeMicro ?? this.textSizeMicro,
      textSizeKeyHint: textSizeKeyHint ?? this.textSizeKeyHint,
      textSizeJersey: textSizeJersey ?? this.textSizeJersey,
      textSizeChip: textSizeChip ?? this.textSizeChip,
    );
  }

  @override
  FfTokens lerp(ThemeExtension<FfTokens>? other, double t) {
    if (other is! FfTokens) return this;
    return FfTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      sunken: Color.lerp(sunken, other.sunken, t)!,
      text: Color.lerp(text, other.text, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      inkOnAccent: Color.lerp(inkOnAccent, other.inkOnAccent, t)!,
      textSizeCaption: _lerpDouble(textSizeCaption, other.textSizeCaption, t),
      textSizeBody: _lerpDouble(textSizeBody, other.textSizeBody, t),
      textSizeLabel: _lerpDouble(textSizeLabel, other.textSizeLabel, t),
      textSizeMeta: _lerpDouble(textSizeMeta, other.textSizeMeta, t),
      textSizeMicro: _lerpDouble(textSizeMicro, other.textSizeMicro, t),
      textSizeKeyHint: _lerpDouble(textSizeKeyHint, other.textSizeKeyHint, t),
      textSizeJersey: _lerpDouble(textSizeJersey, other.textSizeJersey, t),
      textSizeChip: _lerpDouble(textSizeChip, other.textSizeChip, t),
    );
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
}
