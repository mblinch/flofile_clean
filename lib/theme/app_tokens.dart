import 'package:flutter/material.dart';

import '../flo_layout_constants.dart';

/// Design tokens for the app-wide visual refresh.
///
/// Accent values alias the existing constants in `flo_layout_constants.dart`
/// so there is exactly one source of truth; new neutrals/typography live here.
/// Nothing in this file changes rendering until a component adopts it.
abstract class AppTokens {
  AppTokens._();

  // ---------------------------------------------------------------------------
  // Color — accent (aliased from flo_layout_constants.dart)
  // ---------------------------------------------------------------------------

  /// Teal accent (--color-accent): focus, toggles, selection bar.
  static const Color accent = kFloTealLight;

  /// Selected chip/row fill (--color-accent-soft).
  static const Color accentTint = kFloTealSelectedFill;

  /// Mid muted (--color-text-muted).
  static const Color midSlate = kFloTealMid;

  /// Pressed/emphasis surface (--color-elevated).
  static const Color accentDeep = Color(0xFF181D22);

  /// Top chrome bar (flat elevated; gradient API retained).
  static const LinearGradient topBarGradient = kFloTealGradientHorizontal;

  /// Fixed elevated surface used by the compact top chrome.
  static const Color topBarSurface = Color(0xFF181D22);

  /// Hairline beneath the compact top chrome (--color-divider).
  static const Color topBarBorder = Color(0x1EE8EEF4);

  /// Primary content rendered over dark top chrome (--color-text).
  static const Color onAccent = Color(0xFFE8EEF4);

  /// Secondary content rendered over dark top chrome.
  static const Color onAccentMuted = Color(0xFF959AA0);

  /// Low-emphasis separators and outlines over dark top chrome.
  static const Color onAccentSubtle = Color(0xFF6A6E73);

  /// Hover/splash wash used by controls on dark top chrome.
  static const Color onAccentOverlay = Color(0x14E8EEF4);

  /// Translucent fill for badges rendered over dark top chrome.
  static const Color topBarBadgeFill = Color(0x26E8EEF4);

  /// Semantic admin badge colors (--gold).
  static const Color adminAccent = Color(0xFFE8C547);
  static const Color adminTint = Color(0x59E8C547);
  static const Color adminText = Color(0xFF1A1606);

  // ---------------------------------------------------------------------------
  // Color — neutrals
  // ---------------------------------------------------------------------------

  /// App background behind panels.
  static const Color canvas = Color(0xFFF6F7F9);

  /// Card/panel background.
  static const Color surface = Color(0xFFFFFFFF);

  /// 1px hairline border on cards/panels.
  static const Color cardBorder = Color(0xFFEEF0F3);

  /// Dark neutral surrounding photo previews.
  static const Color photoSurround = Color(0xFF2A2D31);

  /// Near-white neutral surrounding photo previews in the light treatment.
  static const Color photoCanvas = Color(0xFFFAFBFC);

  /// Primary text.
  static const Color ink = Color(0xFF1A1D21);

  /// Secondary text.
  static const Color inkSecondary = Color(0xFF5C6470);

  /// Muted/disabled text.
  static const Color inkMuted = Color(0xFF9AA1AB);

  // ---------------------------------------------------------------------------
  // Shape
  // ---------------------------------------------------------------------------

  static const double radiusCard = 14;
  static const double radiusControl = 8;
  static const double radiusKeycap = 4;

  // ---------------------------------------------------------------------------
  // Elevation
  // ---------------------------------------------------------------------------

  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x0A101828),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x0F101828),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  // ---------------------------------------------------------------------------
  // Motion
  // ---------------------------------------------------------------------------

  static const Duration motionFast = Duration(milliseconds: 130);
  static const Curve motionCurve = Curves.easeOut;

  // ---------------------------------------------------------------------------
  // Typography (body inherits Inter from ThemeData unless set explicitly)
  // ---------------------------------------------------------------------------

  /// Display/title face used on Sideline pricing headlines (SF Pro Display).
  /// Private Apple name first; falls back to Inter when SF Pro isn't available.
  static const String titleFontFamily = '.SF Pro Display';

  static const List<String> titleFontFallback = [
    'SF Pro Display',
    'Inter',
  ];

  /// Shared title style for dialog headers, panel titles, and chrome labels.
  static const TextStyle title = TextStyle(
    fontFamily: titleFontFamily,
    fontFamilyFallback: titleFontFallback,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: -0.2,
  );

  /// Main caption text.
  static const TextStyle captionBody = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.65,
  );

  /// Panel/card header row title.
  static const TextStyle panelHeading = TextStyle(
    fontFamily: titleFontFamily,
    fontFamilyFallback: titleFontFallback,
    fontSize: 14,
    fontWeight: FontWeight.w700,
  );

  /// Standard list rows.
  static const TextStyle listBody = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
  );

  /// Secondary labels next to controls.
  static const TextStyle secondaryLabel = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
  );

  /// Metadata / numeric readouts (timestamps, counts, dimensions).
  static const TextStyle meta = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Tiny uppercase section labels.
  static const TextStyle microLabel = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
  );

  /// Monospace (formulas, shortcodes, API output) — bundled JetBrains Mono
  /// so Windows/macOS/Linux render identically.
  static const TextStyle mono = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Small monospace (keycaps, inline tokens).
  static const TextStyle monoSmall = TextStyle(
    fontFamily: 'JetBrainsMono',
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
