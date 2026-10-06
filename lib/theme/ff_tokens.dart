import 'package:flutter/material.dart';

/// FloFile caption V2 design tokens — **Nocturne**.
///
/// Soft cool slate ground (light blue cast), teal accent, warm orange labels.
/// Admin badge stays gold.
/// Source: design-system styles.css `:root` (FloFile Captions palette).
/// Access via `Theme.of(context).extension<FfTokens>()!`.
@immutable
class FfTokens extends ThemeExtension<FfTokens> {
  // ---------------------------------------------------------------------------
  // Nocturne palette (teal)
  // ---------------------------------------------------------------------------

  /// Firebar orange (--firebar). Sparingly: Firebar label + flame only.
  static const firebar = Color(0xFFFF5A1F);

  /// Surfaces — soft cool slate (blue kept, but less saturated than before).
  static const nocturneBg = Color(0xFF101315);
  static const nocturneEl = Color(0xFF181D22);
  static const nocturneSf = Color(0xFF1E242A);
  static const nocturneHv = Color(0xFF2A3035);
  /// Input / control fills — lighter than [nocturneEl] so fields read on panels
  /// instead of sinking into near-black wells.
  static const nocturneSunken = Color(0xFF262D35);

  /// Picture-preview chrome (headers + photo surround).
  static const photoHeader = Color(0xFF101418);

  /// Selected / soft accent fills
  static const nocturneAccentSoft = Color(0xFF20313C);
  static const nocturneAccentRow = Color(0xFF1D2832);
  static const nocturneAccentEdge = Color(0xFF3A6076);
  static const nocturneAccentDeep = Color(0xFF2A4858);

  /// Lines — rgba(232,238,244,…)
  static const nocturneLn = Color(0x1EE8EEF4); // .12
  static const nocturneLn2 = Color(0x2EE8EEF4); // .18

  /// Text
  static const nocturneTx = Color(0xFFE8EEF4);
  static const nocturneT2 = Color(0xFF959AA0); // text @ ~0.62 on bg
  static const nocturneT3 = Color(0xFF6A6E73); // text @ ~0.42 on bg

  /// Accents
  static const nocturneAc = Color(0xFF4A7A96);
  static const accentHover = Color(0xFF5A8EAB);
  static const accent2 = Color(0xFFE8763A); // warm orange — labels, emphasis
  static const gold = Color(0xFFE8C547); // admin / status badge
  static const inkOnGold = Color(0xFF1A1606);

  /// Soft heading spotlight (accent @ 0.18).
  static const glow = Color(0x2E4A7A96);

  /// Soft grey rim for player / caption panels (border + glow).
  static const panelOutline = Color(0xFF5A6570);

  /// Soft grey rim glow for outlined panels (players, caption).
  static List<BoxShadow> panelGlow([Color color = panelOutline]) => [
        BoxShadow(
          color: color.withValues(alpha: 0.28),
          blurRadius: 14,
          spreadRadius: 0,
        ),
        BoxShadow(
          color: color.withValues(alpha: 0.14),
          blurRadius: 28,
          spreadRadius: 1,
        ),
      ];

  /// Soft teal rim glow for action buttons.
  static List<BoxShadow> accentButtonGlow([Color color = nocturneAc]) => [
        BoxShadow(
          color: color.withValues(alpha: 0.24),
          blurRadius: 8,
          spreadRadius: 0,
        ),
        BoxShadow(
          color: color.withValues(alpha: 0.12),
          blurRadius: 14,
          spreadRadius: 0,
        ),
      ];

  /// Soft selection glow for selected verbs / open categories.
  static List<BoxShadow> selectionGlow([Color color = nocturneAc]) => [
        BoxShadow(
          color: color.withValues(alpha: 0.38),
          blurRadius: 12,
          spreadRadius: 0.5,
        ),
        BoxShadow(
          color: color.withValues(alpha: 0.20),
          blurRadius: 22,
          spreadRadius: 0,
        ),
      ];

  @Deprecated('Use panelGlow')
  static List<BoxShadow> accentPanelGlow([Color color = panelOutline]) =>
      panelGlow(color);

  /// Destructive
  static const danger = Color(0xFFF07167);
  static const dangerBg = Color(0x1AF07167); // .10
  static const dangerBorder = Color(0x59F07167); // .35

  /// Pinned header icon / label (--t3).
  static const pinned = nocturneT3;

  /// Empty pinned-slot hint text (--t3).
  static const pinnedHint = nocturneT3;

  /// Divider under a filled pinned slot (--ln).
  static const pinnedDivider = nocturneLn;

  /// Favorites gold (stars, Admin badge) (--badge / --gold).
  static const favorites = gold;

  /// Favorites header fill.
  static const favoritesFill = Color(0x12E8C547); // rgba(232,197,71,0.07)

  /// Favorites header bottom border.
  static const favoritesBorder = Color(0x2EE8C547); // rgba(232,197,71,0.18)

  /// Saved check on viewer / thumbnails (cool status, not warm).
  static const statusSaved = Color(0xFF7FB88A);

  /// Overlay chrome behind viewer toolbar / counter / thumb status.
  static const viewerChrome = Color(0xBF101315); // rgba(16,19,21,.75)
  static const thumbStatusChrome = Color(0xCC101315); // rgba(16,19,21,.8)

  /// Focus ring (--focus).
  static const focus = Color(0xFF7EB0CC);

  const FfTokens({
    required this.bg,
    required this.surface,
    required this.sunken,
    required this.hover,
    required this.selected,
    required this.text,
    required this.accent,
    required this.accentEdge,
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

  /// Elevated panel fill (--el).
  final Color surface;
  final Color sunken;

  /// Row / control hover fill (--hv).
  final Color hover;

  /// Selected row / raised card fill (--accent-soft).
  final Color selected;

  final Color text;

  /// Teal accent (--accent): focus bar, toggles on, selection.
  final Color accent;

  /// Border on soft-filled controls (--accent-edge).
  final Color accentEdge;

  /// Text on filled accent (ac) surfaces.
  final Color inkOnAccent;

  // ---------------------------------------------------------------------------
  // Colors (derived — never hard-coded at call sites)
  // ---------------------------------------------------------------------------

  Color get elevated => surface;

  Color get divider => nocturneLn;

  /// Input / button border (--divider-ish / ln2).
  Color get inputBorder => nocturneLn2;

  /// Selected row/tile fill (--accent-soft).
  Color get selectedFill => selected;

  /// Selection accent bar / focus border (--accent).
  Color get selectedBorder => accent;

  /// Number badge / inert chip fill: text @ 8%.
  Color get badgeFill => text.withValues(alpha: 0.08);

  /// Secondary label text (--t2).
  Color get textSecondary => nocturneT2;

  /// Tertiary / muted text (--t3).
  Color get textTertiary => nocturneT3;

  /// Neutral filled status (saved-but-not-sent).
  Color get statusNeutral => text.withValues(alpha: 0.45);

  /// Selected row: --accent-soft fill + 2px --accent left bar.
  BoxDecoration selectedRowDecoration({BorderRadius? borderRadius}) {
    return BoxDecoration(
      color: selected,
      borderRadius: borderRadius,
      border: Border(left: BorderSide(color: accent, width: 2)),
    );
  }

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
  static const double radiusRow = 5;
  static const double radiusTile = 11;
  /// Panel / card corner radius (caption, viewer, roster, verbs, thumbs).
  static const double radiusCard = 8;
  static const double radiusWindow = 14;

  // ---------------------------------------------------------------------------
  // Typography families / weights
  // ---------------------------------------------------------------------------

  static const String fontFamily = 'Inter';
  static const String labelFamily = 'Inter';
  static const String monoFamily = 'JetBrainsMono';
  static const FontWeight weightRegular = FontWeight.w400;
  static const FontWeight weightMedium = FontWeight.w500;
  static const FontWeight weightSemibold = FontWeight.w600;

  /// Thumbnail card fill inside elevated panels (--sf).
  static const card = nocturneSf;

  /// Panel titles + secondary chrome labels (CAPTION, PERIOD, SORT…).
  static TextStyle panelLabel({required Color color}) => TextStyle(
        fontFamily: fontFamily,
        fontWeight: weightSemibold,
        fontSize: 11,
        letterSpacing: 1.43, // .13em at 11px
        height: 1,
        color: color,
      );

  /// Team abbreviations in roster / drum column headers (TOR, NYR…).
  static TextStyle teamAbbrLabel({required Color color}) => TextStyle(
        fontFamily: fontFamily,
        fontWeight: weightSemibold,
        fontSize: 14,
        letterSpacing: 0.8,
        height: 1,
        color: color,
        shadows: [
          Shadow(
            color: color.withValues(alpha: 0.55),
            blurRadius: 7,
          ),
          Shadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 12,
          ),
        ],
      );

  /// Verb category rows share the small-label style.
  static TextStyle categoryLabel({required Color color}) => panelLabel(color: color);

  static const TextStyle captionTitle = TextStyle(
    fontFamily: labelFamily,
    fontWeight: FontWeight.w700,
    fontSize: 26,
    letterSpacing: 0,
    height: 1,
  );

  static const TextStyle railLabel = TextStyle(
    fontFamily: labelFamily,
    fontWeight: FontWeight.w600,
    fontSize: 11,
    letterSpacing: 1.43,
    height: 1,
  );

  static const TextStyle inningValue = TextStyle(
    fontFamily: labelFamily,
    fontWeight: FontWeight.w600,
    fontSize: 13,
    letterSpacing: 0,
    height: 1,
  );

  /// Player / verb list name.
  static TextStyle rosterName({
    required Color color,
    required bool selected,
  }) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: 13.5,
        fontWeight: selected ? weightSemibold : weightRegular,
        letterSpacing: 0,
        height: 1.2,
        color: color,
      );

  /// Jersey number column.
  static TextStyle rosterJersey({required Color color}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 11.5,
        fontWeight: weightRegular,
        letterSpacing: 0,
        height: 1.1,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
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
        letterSpacing: 0,
        color: text,
        height: 1.5,
      );

  TextStyle get bodyStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: textSizeBody,
        fontWeight: weightRegular,
        letterSpacing: 0,
        color: text,
        height: 1.35,
      );

  TextStyle get labelStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: textSizeLabel,
        fontWeight: weightMedium,
        letterSpacing: 0,
        color: text,
        height: 1.3,
      );

  TextStyle get secondaryLabelStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: textSizeLabel,
        fontWeight: weightRegular,
        letterSpacing: 0,
        color: textSecondary,
        height: 1.3,
      );

  TextStyle get metaStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: textSizeMeta,
        fontWeight: weightRegular,
        letterSpacing: 0,
        color: textSecondary,
        height: 1.3,
      );

  TextStyle get microStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: textSizeMicro,
        fontWeight: weightMedium,
        color: textSecondary,
        letterSpacing: 0,
        height: 1.2,
      );

  TextStyle get chipStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: textSizeChip,
        fontWeight: weightMedium,
        letterSpacing: 0,
        color: text,
        height: 1.2,
      );

  TextStyle get jerseyStyle => rosterJersey(color: textTertiary);

  TextStyle get keyHintStyle => TextStyle(
        fontFamily: fontFamily,
        fontSize: textSizeKeyHint,
        fontWeight: weightRegular,
        letterSpacing: 0,
        color: textSecondary,
        height: 1.1,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  TextStyle get monoMetaStyle => TextStyle(
        fontFamily: monoFamily,
        fontSize: textSizeMeta,
        fontWeight: weightRegular,
        letterSpacing: 0,
        color: textSecondary,
        height: 1.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  // ---------------------------------------------------------------------------
  // Presets — Nocturne
  // ---------------------------------------------------------------------------

  static const FfTokens dark = FfTokens(
    bg: nocturneBg, // --color-bg
    surface: nocturneEl, // --color-elevated
    sunken: nocturneSunken, // --color-sunken
    hover: nocturneHv, // --color-hover
    selected: nocturneAccentSoft, // --color-accent-soft
    text: nocturneTx, // --color-text
    accent: nocturneAc, // --color-accent
    accentEdge: nocturneAccentEdge, // --color-accent-edge
    inkOnAccent: nocturneBg, // --color-on-accent
    textSizeCaption: 15,
    textSizeBody: 14,
    textSizeLabel: 13,
    textSizeMeta: 12,
    textSizeMicro: 11,
    textSizeKeyHint: 11,
    textSizeJersey: 12,
    textSizeChip: 13,
  );

  /// Light companion; mirrors design-system `[data-theme="light"]`.
  static const FfTokens light = FfTokens(
    bg: Color(0xFFF4F7FA),
    surface: Color(0xFFFFFFFF),
    sunken: Color(0xFFE8EEF2),
    hover: Color(0xFFDCE2EA),
    selected: Color(0x1F3A5F78), // accent-soft @ ~12%
    text: Color(0xFF101315),
    accent: Color(0xFF3A5F78),
    accentEdge: Color(0xFF3A5F78),
    inkOnAccent: Color(0xFFFFFFFF),
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
    Color? hover,
    Color? selected,
    Color? text,
    Color? accent,
    Color? accentEdge,
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
      hover: hover ?? this.hover,
      selected: selected ?? this.selected,
      text: text ?? this.text,
      accent: accent ?? this.accent,
      accentEdge: accentEdge ?? this.accentEdge,
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
      hover: Color.lerp(hover, other.hover, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      text: Color.lerp(text, other.text, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentEdge: Color.lerp(accentEdge, other.accentEdge, t)!,
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
