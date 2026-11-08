import 'dart:math';

import 'package:intl/intl.dart';

import 'caption_template.dart';
import 'getty_note_variant.dart';
import 'caption_text_normalize.dart';
import 'date_formula.dart';
import 'game_info.dart';
import 'position_labels.dart';
import 'region_abbrev.dart';
import 'sport_verb_categories.dart';
import 'verb_caption_wording.dart';

/// Drives the sample credit line dropdown (preview branding).
enum CreditSampleAgency { gettyImages, imagn, ap }

/// [before] + inline editor + [after] matches a full [CaptionFormulaRenderer.render]
/// when the middle is [formatBylineCustomTextBlock] for a single byline custom slot.
class CaptionPreviewNarrativeSplit {
  const CaptionPreviewNarrativeSplit({
    required this.before,
    required this.after,
  });

  final String before;
  final String after;
}

class CaptionPreviewPlayer {
  const CaptionPreviewPlayer(
    this.team,
    this.position,
    this.name,
    this.number,
    this.opponent,
  );

  final String team;
  final String position;
  final String name;
  final int number;
  final String opponent;
}

/// Renders static frame + sample dynamic caption for the layout dialog preview.
class CaptionFormulaRenderer {
  CaptionFormulaRenderer._();

  /// Private-use placeholder; must not appear in real segment output.
  static const String _kCustomNarrativePreviewPlaceholder = '\uE000';

  /// IPTC panel labels needed by [template] that are empty on [game].
  ///
  /// IPTC fields still empty that the caption **structure** asks for.
  ///
  /// Flags every variable present in [CaptionTemplate.segmentOrder] / location
  /// chips — including both State and Country when the structure lists both
  /// (Getty auto-adapt does not hide either for this check).
  ///
  /// [includeCreator] is false on startup (Creator often comes from serial
  /// bylines per frame) and true in-session / IPTC dialog.
  /// IPTC panel labels the caption structure uses, whether filled or blank.
  static List<String> captionIptcLabels({
    required CaptionTemplate template,
    bool includeCreator = true,
  }) {
    // Structure UI expands legacy [location] into city/state/country tokens.
    final expanded = template.expandLocationSegments();
    final order = expanded.segmentOrder;
    final labels = <String>[];

    var needsCity = order.contains(CaptionSegment.city);
    var needsState = order.contains(CaptionSegment.state);
    var needsCountry = order.contains(CaptionSegment.country);
    var needsCountryCode = order.contains(CaptionSegment.countryCode);

    // Location chips in the structure (base + US/intl lists). Auto-adapt
    // styles still ask for city, state, and country across both formulas.
    var locOcc = 0;
    for (final seg in template.segmentOrder) {
      if (seg != CaptionSegment.location) continue;
      final opts = locationLineOptionsForOccurrence(template, locOcc++);
      if (opts.autoAdaptUsIntl) {
        needsCity = true;
        needsState = true;
        needsCountry = true;
      }
      for (final chip in _structureGeoChips(opts)) {
        switch (chip.kind) {
          case LocationChipKind.city:
            needsCity = true;
          case LocationChipKind.region:
            needsState = true;
          case LocationChipKind.country:
            if (chip.countryVariant == LocationCountryVariant.isoCode) {
              needsCountryCode = true;
            } else {
              needsCountry = true;
            }
          case LocationChipKind.countryCode:
            needsCountryCode = true;
          case LocationChipKind.literal:
            break;
        }
      }
    }

    // Expanded city/state/country tokens from an auto-adapt location line.
    final locOpts = locationLineOptionsForOccurrence(template, 0);
    if (locOpts.autoAdaptUsIntl &&
        (order.contains(CaptionSegment.city) ||
            order.contains(CaptionSegment.state) ||
            order.contains(CaptionSegment.country))) {
      needsCity = true;
      needsState = true;
      needsCountry = true;
    }

    if (needsCity) labels.add('City');
    if (needsState) labels.add('Province/State');
    if (needsCountry) labels.add('Country');
    if (needsCountryCode) labels.add('Country Code');
    if (order.contains(CaptionSegment.venue)) labels.add('Location');
    if (includeCreator &&
        (order.contains(CaptionSegment.credit) ||
            order.contains(CaptionSegment.creator))) {
      labels.add('Creator');
    }
    if (order.contains(CaptionSegment.agency) ||
        order.contains(CaptionSegment.credit)) {
      labels.add('Credit');
    }
    return labels;
  }

  static List<String> missingCaptionIptcLabels({
    required CaptionTemplate template,
    required GameInfo game,
    bool includeCreator = true,
  }) {
    final needed = captionIptcLabels(
      template: template,
      includeCreator: includeCreator,
    );
    final missing = <String>[];
    for (final label in needed) {
      switch (label) {
        case 'City':
          if (game.city.trim().isEmpty) missing.add(label);
        case 'Province/State':
          if (game.resolvedRegionName.isEmpty &&
              game.resolvedRegionShort.isEmpty) {
            missing.add(label);
          }
        case 'Country':
          // Country name is its own IPTC field — a filled Country Code must
          // not clear the Country highlight.
          if (game.resolvedCountryName.isEmpty) missing.add(label);
        case 'Country Code':
          if (game.resolvedCountryCode.isEmpty) missing.add('Country code');
        case 'Location':
          if (storedVenue(game).isEmpty) missing.add(label);
        case 'Creator':
          if (game.photographerName.trim().isEmpty) missing.add(label);
        case 'Credit':
          if (game.agencyName.trim().isEmpty &&
              _iptcLookup(game.iptcMetadata, const ['IPTC:Credit', 'Credit'])
                  .isEmpty) {
            missing.add(label);
          }
      }
    }
    return missing;
  }

  /// Enabled geo chips the structure defines (union of base + territory lists).
  static Iterable<LocationChip> _structureGeoChips(LocationLineOptions opts) {
    final seen = <LocationChipKind>{};
    final out = <LocationChip>[];
    void take(List<LocationChip>? list) {
      if (list == null) return;
      for (final chip in list) {
        if (chip.kind == LocationChipKind.literal) continue;
        if (!chip.enabled) continue;
        if (!seen.add(chip.kind)) continue;
        out.add(chip);
      }
    }

    take(opts.chips);
    take(opts.usChips);
    take(opts.intlChips);
    return out;
  }

  static String formatDate(
    DateTime? d,
    String pattern, {
    bool uppercaseAll = false,
  }) {
    if (d == null) return '—';
    try {
      final s = DateFormat(pattern).format(d);
      return uppercaseAll ? s.toUpperCase() : s;
    } catch (_) {
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
  }

  /// Date segment for the caption: legacy [CaptionTemplate.dateFormat] on [GameInfo.gameDate],
  /// or [CaptionTemplate.dateExpression] mixing literals with `{{game:ICU}}` and `{{iptc:Field:ICU?}}`.
  ///
  /// [dateFormulaOverride] — when set (e.g. duplicate Date chips), used instead of
  /// [CaptionTemplate.dateFormula] for the structured-formula branch.
  ///
  /// [uppercaseAll] applies only to the legacy [CaptionTemplate.dateFormat] /
  /// [CaptionTemplate.dateExpression] paths. Structured [DateFormula] output
  /// uses each token’s own `caps` flag only.
  static String formatTemplateDateLine(
    GameInfo game,
    CaptionTemplate template, {
    bool uppercaseAll = false,
    DateFormula? dateFormulaOverride,
  }) {
    final formula = dateFormulaOverride ?? template.dateFormula;
    if (formula != null && formula.fields.isNotEmpty) {
      final date = _resolveFormulaDate(game);
      final s = date != null ? formula.render(date) : '—';
      // Per-field caps live on each [DateFieldToken]; do not apply [uppercaseAll]
      // here or Getty (and similar) would defeat the month/weekday Aa toggles.
      return s;
    }
    final expr = template.dateExpression.trim();
    if (expr.isEmpty) {
      return formatDate(game.gameDate, template.dateFormat,
          uppercaseAll: uppercaseAll);
    }
    final s = _formatDateExpressionString(game, template, expr);
    final out = uppercaseAll ? s.toUpperCase() : s;
    return out;
  }

  /// Resolves the [DateTime] for structured [DateFormula] rendering.
  ///
  /// Uses embedded photo EXIF/IPTC [DateTimeOriginal] when the current image
  /// provides it; otherwise the game / session date from metadata or the
  /// template flow at import time ([GameInfo.gameDate]).
  static DateTime? _resolveFormulaDate(GameInfo game) {
    final raw = _lookupIptcDateRaw(game, 'DateTimeOriginal');
    if (raw != null && raw.isNotEmpty) {
      final dt = parseMetadataDate(raw);
      if (dt != null) return dt;
    }
    return game.gameDate;
  }

  static final RegExp _dateVarRe = RegExp(r'\{\{([^}]*)\}\}');

  static String _formatDateExpressionString(
    GameInfo game,
    CaptionTemplate template,
    String expr,
  ) {
    final buf = StringBuffer();
    var start = 0;
    for (final m in _dateVarRe.allMatches(expr)) {
      buf.write(expr.substring(start, m.start));
      buf.write(_evalDateVarToken(m.group(1) ?? '', game, template));
      start = m.end;
    }
    buf.write(expr.substring(start));
    return buf.toString();
  }

  static String _evalDateVarToken(
      String inner, GameInfo game, CaptionTemplate template) {
    final t = inner.trim();
    if (t.isEmpty) return '';
    if (t == 'game' || t.startsWith('game:')) {
      String pattern;
      if (t == 'game') {
        pattern = template.dateFormat;
      } else {
        pattern = t.substring(5);
      }
      if (pattern.isEmpty) pattern = template.dateFormat;
      return formatDate(game.gameDate, pattern, uppercaseAll: false);
    }
    if (t.startsWith('iptc:')) {
      final rest = t.substring(5).trim();
      final parts = rest.split(':');
      if (parts.isEmpty) return '—';
      final field = parts.first.trim();
      var pattern = parts.length > 1 ? parts.sublist(1).join(':').trim() : '';
      if (pattern.isEmpty) pattern = 'MMM d, yyyy';
      final raw = _lookupIptcDateRaw(game, field);
      if (raw == null || raw.isEmpty) return '—';
      final dt = parseMetadataDate(raw);
      if (dt == null) return raw;
      return formatDate(dt, pattern, uppercaseAll: false);
    }
    return '—';
  }

  static String? _lookupIptcDateRaw(GameInfo g, String field) {
    final m = g.iptcMetadata;
    if (m.isEmpty) return null;
    final k = field.trim();
    return m[k] ??
        m['EXIF:$k'] ??
        m['IPTC:$k'] ??
        m['XMP-exif:$k'] ??
        m['XMP:DateTimeOriginal'];
  }

  /// Parses common EXIF/IPTC date strings (e.g. `2026:04:04 14:30:00`, ISO, `yyyyMMdd`).
  static DateTime? parseMetadataDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final exifStyle = RegExp(
      r'^(\d{4}):(\d{2}):(\d{2})(?:\s+(\d{2}):(\d{2}):(\d{2}))?$',
    ).firstMatch(s);
    if (exifStyle != null) {
      final y = int.parse(exifStyle[1]!);
      final mo = int.parse(exifStyle[2]!);
      final d = int.parse(exifStyle[3]!);
      final hh = exifStyle[4] != null ? int.parse(exifStyle[4]!) : 0;
      final mm = exifStyle[5] != null ? int.parse(exifStyle[5]!) : 0;
      final ss = exifStyle[6] != null ? int.parse(exifStyle[6]!) : 0;
      return DateTime(y, mo, d, hh, mm, ss);
    }
    final iso = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (iso != null) return iso;
    final compact = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(s);
    if (compact != null) {
      return DateTime(
        int.parse(compact[1]!),
        int.parse(compact[2]!),
        int.parse(compact[3]!),
      );
    }
    return null;
  }

  /// Returns [chips] with disabled geo chips removed. Drops the literal that
  /// immediately follows each disabled chip (so its trailing separator doesn't
  /// orphan), and trims any leading/trailing literals left at the edges of the
  /// list after removal so the rendered line never starts or ends with a
  /// stranded separator.
  static List<LocationChip> _activeLocationChips(List<LocationChip> chips) {
    final out = <LocationChip>[];
    var skipNextLiteral = false;
    for (final c in chips) {
      if (c.kind != LocationChipKind.literal && !c.enabled) {
        skipNextLiteral = true;
        continue;
      }
      if (c.kind == LocationChipKind.literal && skipNextLiteral) {
        skipNextLiteral = false;
        continue;
      }
      skipNextLiteral = false;
      out.add(c);
    }
    return out;
  }

  /// Applies a location chip's Aa (ALL CAPS) toggle to geo text.
  ///
  /// IPTC Country / City / Province are often stored already uppercased. When
  /// [caps] is false, an ALL-CAPS full name is title-cased so the toggle is
  /// visible (CANADA → Canada). ISO codes (CAN, USA) are left as stored when
  /// Aa is off.
  static String applyLocationChipCaps(
    String raw, {
    required bool caps,
    bool isIsoCode = false,
  }) {
    final value = raw.trim();
    if (value.isEmpty) return value;
    if (caps) return value.toUpperCase();
    if (isIsoCode) return value;
    if (value == value.toUpperCase() &&
        value.contains(RegExp(r'[A-Za-z]')) &&
        value.contains(RegExp(r'\s|[A-Za-z]{4,}'))) {
      return value
          .toLowerCase()
          .split(RegExp(r'(\s+)'))
          .map((part) {
            if (part.trim().isEmpty) return part;
            if (part.length == 1) return part.toUpperCase();
            return '${part[0].toUpperCase()}${part.substring(1)}';
          })
          .join();
    }
    // Single ALL-CAPS token without spaces (e.g. CANADA): still title-case.
    if (value == value.toUpperCase() &&
        RegExp(r'^[A-Z]+$').hasMatch(value) &&
        value.length > 3) {
      return '${value[0]}${value.substring(1).toLowerCase()}';
    }
    return value;
  }

  /// Builds the location line from [GameInfo] using ordered [LocationLineOptions.chips].
  ///
  /// - Per-chip `caps` uppercases just that chip's emitted text.
  /// - Per-chip `enabled` toggles whether the chip (and the literal that
  ///   immediately follows it) contributes to the rendered line.
  /// - The legacy global [LocationLineOptions.uppercase] still force-caps the
  ///   whole line after assembly (kept for templates that haven't migrated).
  /// - When two geo chips render back-to-back with no literal between them,
  ///   a single space is inserted so fields never run together.
  /// - When [LocationLineOptions.autoAdaptUsIntl] or [forceAutoAdaptUsIntl] is
  ///   true: United States → City+State; everywhere else → City+Country.
  static String formatLocationLine(
    GameInfo g,
    LocationLineOptions options, {
    bool apStyleCaption = false,
    bool cpStyleCaption = false,
    bool forceAutoAdaptUsIntl = false,
    int locationOccurrenceIndex = 0,
  }) {
    if (options.autoAdaptUsIntl || forceAutoAdaptUsIntl) {
      final branch = options.chipsForTerritory(
        unitedStates: isUnitedStatesGame(g),
      );
      final rendered = formatLocationLine(
        g,
        LocationLineOptions(
          uppercase: options.uppercase,
          chips: branch,
          autoSpacing: false,
        ),
        apStyleCaption: apStyleCaption,
        cpStyleCaption: cpStyleCaption,
      );
      return rendered;
    }

    final b = StringBuffer();
    final countryName = g.resolvedCountryName.trim().toLowerCase();
    final countryCode = g.resolvedCountryCode.trim().toLowerCase();
    final isCanada = countryName == 'canada' || countryCode == 'can';
    final chips = _activeLocationChips(options.chips);
    // Hold literals until the next non-empty geo so suppressed / empty State
    // does not leave a dangling ", " (AP standalone cities, empty province).
    String? pendingLiteral;
    for (final c in chips) {
      switch (c.kind) {
        case LocationChipKind.city:
        case LocationChipKind.region:
        case LocationChipKind.country:
        case LocationChipKind.countryCode:
          String raw;
          var isIsoCode = false;
          if (c.kind == LocationChipKind.city) {
            raw = g.city.trim();
          } else if (c.kind == LocationChipKind.region) {
            if (cpStyleCaption) {
              // CP: Canadian provinces (standalone cities omit); US uses AP.
              raw = isCanada
                  ? formatCpStyleProvince(
                      city: g.city,
                      region: g.resolvedRegionName,
                      regionCode: g.resolvedRegionShort,
                    )
                  : formatApStyleState(
                      city: g.city,
                      region: g.resolvedRegionName,
                      regionCode: g.resolvedRegionShort,
                    );
            } else if (apStyleCaption && isCanada) {
              raw = '';
            } else if (apStyleCaption &&
                c.regionVariant == LocationRegionVariant.apStyle) {
              // AP — standalone cities + AP abbrevs.
              raw = formatApStyleState(
                city: g.city,
                region: g.resolvedRegionName,
                regionCode: g.resolvedRegionShort,
              );
            } else {
              final useShort = c.regionVariant == LocationRegionVariant.shortForm;
              isIsoCode = useShort;
              raw = (useShort ? g.resolvedRegionShort : g.resolvedRegionName)
                  .trim();
              if (raw.isEmpty) {
                raw = (useShort ? g.resolvedRegionName : g.resolvedRegionShort)
                    .trim();
                isIsoCode = !useShort && raw == g.resolvedRegionShort.trim();
              }
            }
          } else if (c.kind == LocationChipKind.countryCode) {
            raw = g.resolvedCountryCode.trim();
            isIsoCode = true;
          } else {
            final useIso = c.countryVariant == LocationCountryVariant.isoCode;
            isIsoCode = useIso;
            raw =
                (useIso ? g.resolvedCountryCode : g.resolvedCountryName).trim();
            if (raw.isEmpty) {
              raw = (useIso ? g.resolvedCountryName : g.resolvedCountryCode)
                  .trim();
              isIsoCode = !useIso && raw == g.resolvedCountryCode.trim();
            }
          }
          if (raw.isEmpty) break;
          if (pendingLiteral != null) {
            b.write(pendingLiteral);
            pendingLiteral = null;
          }
          b.write(applyLocationChipCaps(
            raw,
            caps: c.caps,
            isIsoCode: isIsoCode,
          ));
          break;
        case LocationChipKind.literal:
          pendingLiteral = c.literal;
          break;
      }
    }
    var s = b.toString();
    // AP: drop a dangling comma when State was omitted. CP province short
    // forms already include a trailing comma ("Que.,") — leave it alone.
    if (apStyleCaption) {
      s = s.replaceFirst(RegExp(r'[,\s]+$'), '');
    }
    if (s.trim().isEmpty) return '—';
    if (options.uppercase) s = s.toUpperCase();
    return s;
  }

  /// True when [GameInfo] resolves to the United States.
  ///
  /// Prefer explicit Country / Country Code. When those are missing, a known
  /// US state/territory in Province/State (or region code) implies US mode.
  static bool isUnitedStatesGame(GameInfo g) {
    final name = g.resolvedCountryName.trim().toLowerCase();
    final code = g.resolvedCountryCode.trim().toLowerCase();
    if (code == 'usa' || code == 'us' || code == '840') return true;
    if (name == 'united states' ||
        name == 'united states of america' ||
        name == 'usa' ||
        name == 'u.s.' ||
        name == 'u.s.a.' ||
        name == 'us') {
      return true;
    }
    // Explicit other country → not US (even if a state-like region is present).
    if (name.isNotEmpty || code.isNotEmpty) return false;
    return isKnownUsStateOrTerritory(g.resolvedRegionName) ||
        isKnownUsStateOrTerritory(g.regionCode);
  }

  /// How many times [kind] appears in [order] strictly before [segmentIndex].
  static int segmentOccurrenceIndex(
    List<CaptionSegment> order,
    int segmentIndex,
    CaptionSegment kind,
  ) {
    var n = 0;
    for (var j = 0; j < segmentIndex && j < order.length; j++) {
      if (order[j] == kind) n++;
    }
    return n;
  }

  /// [occurrenceIndex] counts geo-field (or legacy location) entries of a kind.
  static LocationLineOptions locationLineOptionsForOccurrence(
    CaptionTemplate template,
    int occurrenceIndex,
  ) {
    final by = template.locationOptionsByOccurrence;
    if (by != null &&
        occurrenceIndex >= 0 &&
        occurrenceIndex < by.length) {
      return by[occurrenceIndex];
    }
    return template.locationOptions;
  }

  /// True for city / state / country / country-code structure tokens.
  static bool isGeoFieldSegment(CaptionSegment s) =>
      s == CaptionSegment.city ||
      s == CaptionSegment.state ||
      s == CaptionSegment.country ||
      s == CaptionSegment.countryCode;

  /// True for month / day / year / weekday structure tokens.
  static bool isDatePartSegment(CaptionSegment s) =>
      CaptionTemplate.isDatePartSegment(s);

  static DateFieldKind? dateFieldKindForSegment(CaptionSegment s) {
    switch (s) {
      case CaptionSegment.month:
        return DateFieldKind.month;
      case CaptionSegment.day:
        return DateFieldKind.day;
      case CaptionSegment.year:
        return DateFieldKind.year;
      case CaptionSegment.weekday:
        return DateFieldKind.weekday;
      default:
        return null;
    }
  }

  /// Formats a single date part (month / day / year / weekday) from the same
  /// date source used by [formatTemplateDateLine].
  static String formatDatePart({
    required GameInfo game,
    required CaptionTemplate template,
    required DateFieldKind kind,
    required int occurrenceIndex,
  }) {
    final token = template.datePartTokenFor(
      kind: kind,
      occurrenceIndex: occurrenceIndex,
    );
    final date = _resolveFormulaDate(game);
    if (date == null) return '—';
    return token.render(date);
  }

  /// Renders a single geo field using the matching chip in [options].
  ///
  /// When [options.autoAdaptUsIntl] or [forceAutoAdaptUsIntl] is set (Getty),
  /// State is omitted outside the US and Country is omitted inside the US
  /// (empty string) so surrounding punctuation can collapse via pending-glue
  /// joins. Imagn keeps both province and country when present.
  ///
  /// When auto-adapt is on, outside the US, and the formula has no Country
  /// segment ([formulaIncludesCountry] is false), the State slot renders
  /// Country instead so City+State-only Getty structures still show Canada.
  /// [LocationChipKind.countryCode] is never auto-blanked.
  static String formatGeoField({
    required GameInfo game,
    required LocationLineOptions options,
    required LocationChipKind kind,
    bool apStyleCaption = false,
    bool cpStyleCaption = false,
    bool forceAutoAdaptUsIntl = false,
    bool formulaIncludesCountry = true,
  }) {
    assert(kind != LocationChipKind.literal);
    final autoAdapt = options.autoAdaptUsIntl || forceAutoAdaptUsIntl;
    if (autoAdapt) {
      final us = isUnitedStatesGame(game);
      if (kind == LocationChipKind.country && us) return '';
      if (kind == LocationChipKind.region && !us) {
        if (!formulaIncludesCountry) {
          // State-only Getty structure: put Country in the State slot.
          return formatGeoField(
            game: game,
            options: options,
            kind: LocationChipKind.country,
            apStyleCaption: apStyleCaption,
            cpStyleCaption: cpStyleCaption,
            forceAutoAdaptUsIntl: false,
            formulaIncludesCountry: true,
          );
        }
        return '';
      }
    }

    LocationChip chip = LocationChip(
      id: 'geo_${kind.name}',
      kind: kind,
      caps: options.uppercase,
    );
    for (final c in options.chips) {
      if (c.kind == kind) {
        chip = c;
        break;
      }
    }
    // Prefer territory-specific chip metadata when auto-adapt lists exist.
    if (autoAdapt && kind != LocationChipKind.countryCode) {
      final branch = options.chipsForTerritory(
        unitedStates: isUnitedStatesGame(game),
      );
      for (final c in branch) {
        if (c.kind == kind) {
          chip = c;
          break;
        }
      }
    }
    if (!chip.enabled && !autoAdapt) return '';

    final countryName = game.resolvedCountryName.trim().toLowerCase();
    final countryCode = game.resolvedCountryCode.trim().toLowerCase();
    final isCanada = countryName == 'canada' || countryCode == 'can';

    String raw;
    var isIsoCode = false;
    switch (kind) {
      case LocationChipKind.city:
        raw = game.city.trim();
        break;
      case LocationChipKind.region:
        if (cpStyleCaption) {
          raw = isCanada
              ? formatCpStyleProvince(
                  city: game.city,
                  region: game.resolvedRegionName,
                  regionCode: game.resolvedRegionShort,
                )
              : formatApStyleState(
                  city: game.city,
                  region: game.resolvedRegionName,
                  regionCode: game.resolvedRegionShort,
                );
        } else if (apStyleCaption && isCanada) {
          return '';
        } else if (apStyleCaption &&
            chip.regionVariant == LocationRegionVariant.apStyle) {
          // AP — standalone cities + AP abbrevs.
          raw = formatApStyleState(
            city: game.city,
            region: game.resolvedRegionName,
            regionCode: game.resolvedRegionShort,
          );
        } else {
          final useShort = chip.regionVariant == LocationRegionVariant.shortForm;
          isIsoCode = useShort;
          raw = (useShort ? game.resolvedRegionShort : game.resolvedRegionName)
              .trim();
          if (raw.isEmpty) {
            raw = (useShort
                    ? game.resolvedRegionName
                    : game.resolvedRegionShort)
                .trim();
            isIsoCode = !useShort && raw == game.resolvedRegionShort.trim();
          }
        }
        break;
      case LocationChipKind.country:
        final useIso = chip.countryVariant == LocationCountryVariant.isoCode;
        isIsoCode = useIso;
        raw = (useIso ? game.resolvedCountryCode : game.resolvedCountryName)
            .trim();
        if (raw.isEmpty) {
          raw = (useIso ? game.resolvedCountryName : game.resolvedCountryCode)
              .trim();
          isIsoCode = !useIso && raw == game.resolvedCountryCode.trim();
        }
        break;
      case LocationChipKind.countryCode:
        raw = game.resolvedCountryCode.trim();
        isIsoCode = true;
        break;
      case LocationChipKind.literal:
        return '';
    }
    if (raw.isEmpty) return '';
    var out = applyLocationChipCaps(
      raw,
      caps: chip.caps || options.uppercase,
      isIsoCode: isIsoCode,
    );
    return out;
  }

  /// [occurrenceIndex] counts only [CaptionSegment.separator] entries, left-to-right.
  static String separatorSnippetFor(
    CaptionTemplate template,
    int segmentIndex,
  ) {
    final occ = segmentOccurrenceIndex(
        template.segmentOrder, segmentIndex, CaptionSegment.separator);
    final list = template.separatorSnippets;
    if (list != null && occ >= 0 && occ < list.length) return list[occ];
    return ' ';
  }

  /// [occurrenceIndex] counts only [CaptionSegment.punctuation] entries, left-to-right.
  static String punctuationSnippetFor(
    CaptionTemplate template,
    int segmentIndex,
  ) {
    final occ = segmentOccurrenceIndex(
        template.segmentOrder, segmentIndex, CaptionSegment.punctuation);
    final list = template.punctuationSnippets;
    if (list != null && occ >= 0 && occ < list.length) return list[occ];
    return '';
  }

  /// [occurrenceIndex] counts only [CaptionSegment.freeText] entries, left-to-right.
  static String freeTextSnippetFor(
    CaptionTemplate template,
    int segmentIndex,
  ) {
    final occ = segmentOccurrenceIndex(
        template.segmentOrder, segmentIndex, CaptionSegment.freeText);
    final list = template.freeTextSnippets;
    final body =
        (list != null && occ >= 0 && occ < list.length) ? list[occ] : '';
    final suffixes = template.freeTextSuffixes;
    final suffix = (suffixes != null && occ >= 0 && occ < suffixes.length)
        ? suffixes[occ]
        : '';
    // Do not auto-inject gameIdentifierText — start screen owns that phrase.
    return '$body$suffix';
  }

  /// Body-only free text (no trailing suffix) for the editor field.
  static String freeTextBodyFor(
    CaptionTemplate template,
    int segmentIndex,
  ) {
    final occ = segmentOccurrenceIndex(
        template.segmentOrder, segmentIndex, CaptionSegment.freeText);
    final list = template.freeTextSnippets;
    if (list != null && occ >= 0 && occ < list.length) return list[occ];
    return '';
  }

  static String freeTextSuffixFor(
    CaptionTemplate template,
    int segmentIndex,
  ) {
    final occ = segmentOccurrenceIndex(
        template.segmentOrder, segmentIndex, CaptionSegment.freeText);
    final list = template.freeTextSuffixes;
    if (list != null && occ >= 0 && occ < list.length) return list[occ];
    return '';
  }

  /// [occurrenceIndex] counts only [CaptionSegment.date] entries, left-to-right.
  static DateFormula? dateFormulaForOccurrence(
    CaptionTemplate template,
    int occurrenceIndex,
  ) {
    final by = template.dateFormulasByOccurrence;
    if (by != null &&
        occurrenceIndex >= 0 &&
        occurrenceIndex < by.length) {
      return by[occurrenceIndex];
    }
    return template.dateFormula;
  }

  static String defaultAgencyLabel(CreditSampleAgency sample) {
    switch (sample) {
      case CreditSampleAgency.gettyImages:
        return 'Getty Images';
      case CreditSampleAgency.imagn:
        return 'Imagn Images';
      case CreditSampleAgency.ap:
        return 'AP';
    }
  }

  static String _iptcLookup(Map<String, String> iptcMetadata, List<String> keys) {
    for (final k in keys) {
      final v = iptcMetadata[k]?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }

  /// IPTC Creator / By-line → [GameInfo.photographerName], with sample fallback.
  static String formatCreatorName({
    required GameInfo game,
    required BylineOptions bylineOptions,
  }) {
    var name = game.photographerName.trim();
    if (name.isEmpty) {
      name = _iptcLookup(game.iptcMetadata, const [
        'IPTC:By-line',
        'By-line',
        'Creator',
        'XMP-dc:Creator',
        'XMP:Creator',
      ]);
    }
    if (name.isEmpty) name = 'Photographer';
    if (bylineOptions.nameCaps) name = name.toUpperCase();
    return name;
  }

  /// IPTC Credit → [GameInfo.agencyName], with wire sample fallback.
  static String formatAgencyCredit({
    required GameInfo game,
    required BylineOptions bylineOptions,
    required CreditSampleAgency sampleAgency,
  }) {
    var credit = game.agencyName.trim();
    if (credit.isEmpty) {
      credit = _iptcLookup(game.iptcMetadata, const [
        'IPTC:Credit',
        'Credit',
      ]);
    }
    if (credit.isEmpty) credit = defaultAgencyLabel(sampleAgency);
    if (bylineOptions.creditCaps || bylineOptions.organizationCaps) {
      credit = credit.toUpperCase();
    }
    return credit;
  }

  /// Narrative line built only from [BylineFieldKind.custom] slots (joined with
  /// a single space). Used when [CaptionSegment.customText] is in
  /// [CaptionTemplate.segmentOrder] so that text appears after the caption body.
  static String formatBylineCustomTextBlock({
    required BylineOptions bylineOptions,
    List<String> customTexts = const [],
  }) {
    var customOccurrence = 0;
    final parts = <String>[];
    for (final kind in bylineOptions.fieldOrder) {
      if (kind != BylineFieldKind.custom) continue;
      final idx = customOccurrence++;
      if (idx >= customTexts.length) continue;
      final t = customTexts[idx].trim();
      if (t.isNotEmpty) parts.add(t);
    }
    return parts.join(' ');
  }

  static String formatCreditLine({
    required CreditFormat format,
    required BylineOptions bylineOptions,
    required String photographerName,
    required String agencyName,
    required Map<String, String> iptcMetadata,
    required CreditSampleAgency sampleAgency,
    bool apShortParen = false,
    List<String> customTexts = const [],
    /// When false, custom slots still consume [customTexts] indices but render
    /// empty so customs can be emitted from [formatBylineCustomTextBlock] in
    /// an earlier caption segment instead.
    bool includeCustomInCredit = true,
  }) {
    var name = photographerName.trim().isEmpty
        ? 'Photographer'
        : photographerName.trim();
    String fromIptc(List<String> keys) {
      for (final k in keys) {
        final v = iptcMetadata[k]?.trim();
        if (v != null && v.isNotEmpty) return v;
      }
      return '';
    }

    var credit = agencyName.trim();
    if (credit.isEmpty) {
      credit = fromIptc(const [
        'IPTC:Credit',
        'Credit',
      ]);
    }
    if (credit.isEmpty) {
      credit = defaultAgencyLabel(sampleAgency);
    }
    var copyright = fromIptc(const [
      'IPTC:CopyrightNotice',
      'CopyrightNotice',
      'Copyright',
      'XMP:Copyright',
    ]);
    if (copyright.isEmpty) {
      copyright = credit;
    }
    if (bylineOptions.nameCaps) name = name.toUpperCase();
    if (bylineOptions.creditCaps || bylineOptions.organizationCaps) {
      credit = credit.toUpperCase();
    }
    if (bylineOptions.copyrightCaps) copyright = copyright.toUpperCase();

    // apShortParen only applies when no custom text has been typed.
    final hasCustomText =
        (bylineOptions.fieldOrder.contains(BylineFieldKind.custom) &&
            customTexts.any((t) => t.trim().isNotEmpty)) ||
        bylineOptions.customCreatorText.trim().isNotEmpty ||
        bylineOptions.customCreditText.trim().isNotEmpty;
    if (apShortParen && !hasCustomText) {
      final short =
          credit.length > 20 || credit.contains('Associated') ? 'AP' : credit;
      return '($name/$short)';
    }

    // Each custom occurrence in fieldOrder maps to customTexts[i] in order.
    var customOccurrence = 0;
    String fieldValue(BylineFieldKind kind) {
      switch (kind) {
        case BylineFieldKind.name:
          return name;
        case BylineFieldKind.credit:
          return credit;
        case BylineFieldKind.copyright:
          return copyright;
        case BylineFieldKind.custom:
          final idx = customOccurrence++;
          if (!includeCustomInCredit) return '';
          return idx < customTexts.length ? customTexts[idx].trim() : '';
        case BylineFieldKind.customCreator:
          var v = bylineOptions.customCreatorText.trim();
          if (bylineOptions.nameCaps) v = v.toUpperCase();
          return v;
        case BylineFieldKind.customCredit:
          var v = bylineOptions.customCreditText.trim();
          if (bylineOptions.creditCaps || bylineOptions.organizationCaps) {
            v = v.toUpperCase();
          }
          return v;
      }
    }

    // Toggled-off kinds keep their slot in fieldOrder (so re-enabling restores
    // position) but render as empty so the join-with-`between` step skips them.
    // Custom occurrences still advance the customOccurrence counter so disabled
    // non-custom kinds don't shift custom text mappings.
    // customCreator / customCredit are always removable (no disabled toggle).
    final fields = bylineOptions.fieldOrder
        .map((kind) {
          if (kind != BylineFieldKind.custom &&
              kind != BylineFieldKind.customCreator &&
              kind != BylineFieldKind.customCredit &&
              bylineOptions.disabledKinds.contains(kind)) {
            return '';
          }
          return fieldValue(kind);
        })
        .where((v) => v.trim().isNotEmpty)
        .toList();
    if (fields.isEmpty) return '';
    final out =
        '${bylineOptions.prefix}${fields.join(bylineOptions.between)}${bylineOptions.suffix}';
    return out;
  }

  /// Time phrase for layout/startup previews (matches live caption fields).
  static String previewTimePhraseForSport(
    String? sport, {
    bool caps = false,
  }) {
    String phrase;
    switch ((sport ?? 'baseball').toLowerCase().trim()) {
      case 'hockey':
        phrase = 'during the third period';
        break;
      case 'basketball':
      case 'wnba':
      case 'football':
        phrase = 'during the fourth quarter';
        break;
      case 'soccer':
        phrase = 'during the second half';
        break;
      case 'baseball':
      default:
        phrase = 'during the third inning';
        break;
    }
    return caps ? phrase.toUpperCase() : phrase;
  }

  static String defaultPreviewActionForSport(String? sport) {
    final s = (sport ?? 'baseball').toLowerCase().trim();
    final key = SportVerbCategories.defaultPreviewVerb[s] ??
        SportVerbCategories.defaultPreviewVerb['baseball']!;
    final verb = VerbCaptionWording.defaultWording(key, sport: s).trim();
    final phrase = previewTimePhraseForSport(sport);
    return '$verb against the {opp} $phrase';
  }

  static String sampleDynamicCaption(
    CaptionTemplate template, {
    List<CaptionPreviewPlayer>? previewPlayers,
    List<String>? previewActions,
    String? sport,
  }) {
    return randomSinglePlayerCaption(
      template,
      seed: 0,
      previewPlayers: previewPlayers,
      previewActions: previewActions,
      sport: sport,
    );
  }

  static String _numberToken(NumberFormatStyle nf, int number) {
    return nf == NumberFormatStyle.hash ? '#$number' : '($number)';
  }

  static String _possessiveTeam(String team) {
    final trimmed = team.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed.toLowerCase().endsWith('s') ? "$trimmed'" : "$trimmed's";
  }

  static String _singlePlayerLead(
    CaptionTemplate template,
    CaptionPreviewPlayer player, {
    String? sport,
  }) {
    return singlePlayerPreviewParts(
      template,
      player,
      sport: sport,
      includeTiming: false,
    ).map((e) => e.$2).join();
  }

  /// Ordered (flashKey, text) parts for the Player Output sample.
  ///
  /// Flash keys match toggle ids: `team`, `num`, `pos`, `poss`, `per`, `dia`.
  /// Literal spacers use a null key. Joining `$2` matches
  /// [randomSinglePlayerPreview] / [_singlePlayerLead].
  static List<(String? key, String text)> singlePlayerPreviewParts(
    CaptionTemplate template,
    CaptionPreviewPlayer player, {
    String? sport,
    bool includeTiming = true,
  }) {
    var playerName = player.name;
    var teamName = player.team;
    if (template.removeDiacritics) {
      playerName = CaptionTextNormalize.stripDiacritics(playerName);
      teamName = CaptionTextNormalize.stripDiacritics(teamName);
    }
    final numText = _numberToken(template.numberFormat, player.number);
    final posLabel = template.effectiveIncludePlayerPosition
        ? formatPositionLabelForCaption(
            player.position,
            apStyle: template.wireStyle == WireStyle.ap ||
                template.wireStyle == WireStyle.cp,
            imagnStyle: template.wireStyle == WireStyle.imagn,
            americanEnglish: template.americanEnglish,
            sport: sport ?? 'baseball',
          )
        : '';
    final parts = <(String? key, String text)>[];
    switch (template.captionTeamOrder) {
      case CaptionTeamOrder.teamAfter:
        parts.add(('dia', playerName));
        parts.add((null, ' '));
        parts.add(('num', numText));
        parts.add(('team', ' of the $teamName'));
        if (posLabel.isNotEmpty) {
          parts.add(('pos', ' $posLabel'));
        }
      case CaptionTeamOrder.teamBefore:
        // Possessive: "Maple Leafs' Auston Matthews (34)"
        // With position: "Maple Leafs' defenseman Auston Matthews (34)"
        if (template.useTeamPossessive ?? false) {
          parts.add(('poss', _possessiveTeam(teamName)));
        } else {
          parts.add(('team', teamName));
        }
        if (posLabel.isNotEmpty) {
          parts.add(('pos', ' $posLabel'));
        }
        parts.add((null, ' '));
        parts.add(('dia', playerName));
        parts.add((null, ' '));
        parts.add(('num', numText));
    }
    if (includeTiming && template.includeTimingPhrase) {
      parts.add((null, ' '));
      parts.add((
        'per',
        previewTimePhraseForSport(sport, caps: template.timingPhraseCaps),
      ));
    }
    return parts;
  }

  /// Seeded player-only preview parts (no action clause).
  ///
  /// Timing is omitted here — Player Output is for name / number / team /
  /// position. Period / quarter still affects the Structure preview caption
  /// and live captions via [includeTimingPhrase].
  static List<(String? key, String text)> randomSinglePlayerPreviewParts(
    CaptionTemplate template, {
    int seed = 0,
    List<CaptionPreviewPlayer>? previewPlayers,
    String? sport,
  }) {
    final rand = Random(seed);
    final players = (previewPlayers != null && previewPlayers.isNotEmpty)
        ? previewPlayers
        : _samplePlayers;
    final player = players[rand.nextInt(players.length)];
    return singlePlayerPreviewParts(
      template,
      player,
      sport: sport,
      includeTiming: false,
    );
  }

  /// Seeded player-only preview text (no action clause / no timing phrase).
  static String randomSinglePlayerPreview(
    CaptionTemplate template, {
    int seed = 0,
    List<CaptionPreviewPlayer>? previewPlayers,
    String? sport,
  }) {
    return randomSinglePlayerPreviewParts(
      template,
      seed: seed,
      previewPlayers: previewPlayers,
      sport: sport,
    ).map((e) => e.$2).join();
  }

  /// Seeded preview caption featuring a single player from the mock game roster.
  /// Stable output per [seed] so the dialog can rebuild without flicker but still
  /// re-roll on demand.
  static String randomSinglePlayerCaption(
    CaptionTemplate template, {
    int seed = 0,
    List<CaptionPreviewPlayer>? previewPlayers,
    List<String>? previewActions,
    String? sport,
  }) {
    final rand = Random(seed);
    final players = (previewPlayers != null && previewPlayers.isNotEmpty)
        ? previewPlayers
        : _samplePlayers;
    final actions = (previewActions != null && previewActions.isNotEmpty)
        ? previewActions
        : _previewActionsForSport(sport);
    final player = players[rand.nextInt(players.length)];
    final lead = _singlePlayerLead(template, player, sport: sport);
    final actionTemplate = actions[rand.nextInt(actions.length)];
    var opp = player.opponent;
    if (template.removeDiacritics) {
      opp = CaptionTextNormalize.stripDiacritics(opp);
    }
    var action = _normalizePreviewInningPhrase(
      actionTemplate.replaceAll('{opp}', opp),
    );
    var line = '$lead $action';
    // Preview should always read with a game segment (inning, half-inning,
    // quarter, or half) — append if an action template ever omits one.
    final hasGameSegment = RegExp(
      r'\b(inning|innings|quarter|quarters|period|periods|halftime)\b|'
      r'\b(first|second)\s+half\b|'
      r'\b(top|bottom)\s+of\s+the\b|'
      r'\b(before|following)\s+the\s+game\b|'
      r'\b(ahead of|following)\s+their\b|'
      r'\bahead of\s+(?:the\s+game|playing)\b',
      caseSensitive: false,
    ).hasMatch(line);
    if (!hasGameSegment) {
      if (template.includeTimingPhrase) {
        line = '$line ${previewTimePhraseForSport(
          sport,
          caps: template.timingPhraseCaps,
        )}';
      }
    } else if (!template.includeTimingPhrase) {
      line = _stripTimingPhraseFromCaption(line);
    } else if (template.timingPhraseCaps) {
      line = _uppercaseTimingPhraseInCaption(line);
    }
    if (template.removeDiacritics) {
      line = CaptionTextNormalize.stripDiacritics(line);
    }
    return line;
  }

  static const List<CaptionPreviewPlayer> _samplePlayers = [
    CaptionPreviewPlayer(
        'Los Angeles Boulevards', 'CF', 'Heater Ace', 24, 'New York Avenues'),
    CaptionPreviewPlayer(
        'New York Avenues', 'SS', 'Clutch Buckets', 7, 'Los Angeles Boulevards'),
    CaptionPreviewPlayer(
        'Los Angeles Boulevards', 'P', 'Jordan Lee', 12, 'New York Avenues'),
    CaptionPreviewPlayer(
        'New York Avenues', 'C', 'Riley Quinn', 9, 'Los Angeles Boulevards'),
    CaptionPreviewPlayer(
        'Los Angeles Boulevards', '1B', 'Morgan Blake', 33, 'New York Avenues'),
    CaptionPreviewPlayer(
        'New York Avenues', 'LF', 'Casey Storm', 18, 'Los Angeles Boulevards'),
  ];

  /// Rewrites preview-only inning phrasing (top/bottom half, bare "in the Nth").
  static String _normalizePreviewInningPhrase(String text) {
    var s = text;
    s = s.replaceAllMapped(
      RegExp(
        r'\bin the (?:top|bottom) of the ([a-z]+) inning\b',
        caseSensitive: false,
      ),
      (m) => 'during the ${m.group(1)} inning',
    );
    s = s.replaceAllMapped(
      RegExp(r'\bin the ([a-z]+) inning\b', caseSensitive: false),
      (m) => 'during the ${m.group(1)} inning',
    );
    return s;
  }

  /// Timing phrases shuffled into layout/startup sample captions.
  static List<String> _previewTimePhrasesForSport(String? sport) {
    switch ((sport ?? 'baseball').toLowerCase().trim()) {
      case 'hockey':
        return const [
          'during the first period',
          'during the second period',
          'during the third period',
        ];
      case 'basketball':
      case 'wnba':
      case 'football':
        return const [
          'during the first quarter',
          'during the second quarter',
          'during the third quarter',
          'during the fourth quarter',
        ];
      case 'soccer':
        return const [
          'during the first half',
          'during the second half',
        ];
      case 'baseball':
      default:
        return const [
          'during the first inning',
          'during the third inning',
          'during the fifth inning',
          'during the seventh inning',
          'during the ninth inning',
        ];
    }
  }

  /// Singular verb phrases from the sport's real verb list (never invented).
  static List<String> _catalogVerbPhrases(String? sport) {
    final s = (sport ?? 'baseball').toLowerCase().trim();
    final out = <String>[];
    final seen = <String>{};
    for (final entry in SportVerbCategories.forSport(s).entries) {
      for (final key in entry.value) {
        final label = key.trim();
        if (label.isEmpty) continue;
        final phrase =
            VerbCaptionWording.defaultWording(label, sport: s).trim();
        if (phrase.isEmpty) continue;
        if (!seen.add(phrase.toLowerCase())) continue;
        out.add(phrase);
      }
    }
    return out;
  }

  /// Layout/startup previews when no session verbs are loaded — verbs come
  /// only from [SportVerbCategories], not made-up sample wording.
  static List<String> _previewActionsForSport(String? sport) {
    final phrases = _previewTimePhrasesForSport(sport);
    final verbs = _catalogVerbPhrases(sport);
    if (verbs.isEmpty) {
      return [
        for (final phrase in phrases) 'against the {opp} $phrase',
      ];
    }
    return [
      for (final verb in verbs)
        for (final phrase in phrases)
          '$verb against the {opp} $phrase',
    ];
  }

  /// Uppercases the inning / period / quarter / half clause inside a caption.
  static String _uppercaseTimingPhraseInCaption(String text) {
    return text.replaceAllMapped(
      RegExp(
        r'\b((?:during|in|before|following|ahead of)\s+(?:the\s+)?'
        r'(?:(?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|'
        r'tenth|eleventh|twelfth|[\w-]+)\s+)?'
        r'(?:inning|innings|period|periods|quarter|quarters|half|overtime|'
        r'extra time|game|national anthem prior to play))\b',
        caseSensitive: false,
      ),
      (m) => m.group(0)!.toUpperCase(),
    );
  }

  /// Removes the inning / period / quarter / half clause from a caption body.
  static String _stripTimingPhraseFromCaption(String text) {
    var s = text.replaceAllMapped(
      RegExp(
        r'\s*\b((?:during|in|before|following|ahead of)\s+(?:the\s+)?'
        r'(?:(?:first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|'
        r'tenth|eleventh|twelfth|[\w-]+)\s+)?'
        r'(?:inning|innings|period|periods|quarter|quarters|half|overtime|'
        r'extra time|game|national anthem prior to play))\b',
        caseSensitive: false,
      ),
      (_) => '',
    );
    return s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  /// IPTC / XMP keys for Location (IPTC SubLocation — stadium / place name).
  static const stadiumMetadataKeys = <String>[
    'IPTC:SubLocation',
    'IPTC:Sub-location',
    'SubLocation',
    'Sub-location',
    'Location',
    'IPTC:Location',
    'XMP:Location',
    'XMP-iptcCore:Location',
    'LocationShownSublocation',
    'LocationCreatedSublocation',
  ];

  /// True when [game.iptcMetadata] has an IPTC Location / SubLocation value.
  static bool hasIptcLocation(GameInfo game) {
    for (final key in stadiumMetadataKeys) {
      final value = game.iptcMetadata[key]?.trim() ?? '';
      if (value.isNotEmpty) return true;
    }
    return false;
  }

  /// Location name from IPTC first, then [GameInfo.venue]. Empty when unknown.
  static String storedVenue(GameInfo game) {
    for (final key in stadiumMetadataKeys) {
      final value = game.iptcMetadata[key]?.trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return game.venue.trim();
  }

  /// Copies [location] into the IPTC Location / SubLocation metadata aliases.
  static Map<String, String> iptcLocationMetadata(
    String location, [
    Map<String, String>? base,
  ]) {
    final out = Map<String, String>.from(base ?? const {});
    final v = location.trim();
    if (v.isEmpty) return out;
    for (final key in stadiumMetadataKeys) {
      out[key] = v;
    }
    return out;
  }

  /// Location for captions / previews. Falls back to "Location" when unset.
  static String venueLabel(GameInfo game) {
    final stored = storedVenue(game);
    return stored.isEmpty ? 'Location' : stored;
  }

  static String render({
    required CaptionTemplate template,
    required GameInfo game,
    required CreditSampleAgency sampleAgency,
    String? captionOverride,
    String? creditOverride,
    List<CaptionPreviewPlayer>? previewPlayers,
    List<String>? previewActions,
    String? sport,
    bool applyGettyNoteVariant = false,
    bool gettyNbaeNote = false,
  }) {
    final cap = captionOverride ??
        sampleDynamicCaption(
          template,
          previewPlayers: previewPlayers,
          previewActions: previewActions,
          sport: sport,
        );
    final venue = venueLabel(game);

    final joined = _renderFromSegments(
      template: template,
      game: game,
      sampleAgency: sampleAgency,
      cap: cap,
      venue: venue,
      creditOverride: creditOverride,
      customSegmentPlaceholderIndex: null,
    );
    final gettyWire = template.wireStyle == WireStyle.getty ||
        template.wireStyle == WireStyle.gettyInternational;
    if (!applyGettyNoteVariant || !gettyWire) return joined;
    return GettyNoteVariant.apply(joined, nbae: gettyNbaeNote);
  }

  /// When the layout includes a [CaptionSegment.customText] segment, splits
  /// the preview around that slot so the game identifier can be edited inline.
  /// Returns `null` when no such segment exists.
  static CaptionPreviewNarrativeSplit? previewCaptionNarrativeSplit({
    required CaptionTemplate template,
    required GameInfo game,
    required CreditSampleAgency sampleAgency,
    String? captionOverride,
    String? creditOverride,
    List<CaptionPreviewPlayer>? previewPlayers,
    List<String>? previewActions,
  }) {
    final order = template.segmentOrder;
    final cut = order.indexWhere((s) => s == CaptionSegment.customText);
    if (cut < 0) return null;

    final cap = captionOverride ??
        sampleDynamicCaption(
          template,
          previewPlayers: previewPlayers,
          previewActions: previewActions,
        );
    final venue = venueLabel(game);
    final merged = _renderFromSegments(
      template: template,
      game: game,
      sampleAgency: sampleAgency,
      cap: cap,
      venue: venue,
      creditOverride: creditOverride,
      customSegmentPlaceholderIndex: cut,
    );
    final i = merged.indexOf(_kCustomNarrativePreviewPlaceholder);
    if (i < 0) return null;
    return CaptionPreviewNarrativeSplit(
      before: merged.substring(0, i),
      after: merged.substring(
        i + _kCustomNarrativePreviewPlaceholder.length,
      ),
    );
  }

  /// Joins [CaptionTemplate.segmentOrder] with per-gap strings for every wire
  /// style (Getty / Imagn / AP / Custom).
  ///
  /// When [CaptionTemplate.customSeparators] is null, uses [defaultCustomGaps]
  /// for presets or [CaptionTemplate.separator] for Custom.
  ///
  /// When length does not match `segmentOrder.length - 1` (e.g. after a prefs
  /// migration or an older bug), **merges** without discarding: uses each
  /// stored string in order, then pads with defaults so inline editors and the
  /// preview never disagree.
  static List<String> effectiveSegmentGaps(CaptionTemplate template) {
    final order = template.segmentOrder;
    final n = order.length;
    if (n < 2) return [];
    final expected = n - 1;
    final List<String> defaults;
    if (template.wireStyle == WireStyle.custom) {
      defaults = List.filled(expected, template.separator);
    } else {
      defaults = defaultCustomGaps(template);
    }
    final custom = template.customSeparators;
    if (custom == null) {
      return defaults;
    }
    if (custom.length == expected) {
      return List<String>.from(custom);
    }
    final merged = <String>[];
    for (var i = 0; i < expected; i++) {
      if (i < custom.length) {
        merged.add(custom[i]);
      } else {
        merged.add(defaults[i]);
      }
    }
    return merged;
  }

  static String _renderFromSegments({
    required CaptionTemplate template,
    required GameInfo game,
    required CreditSampleAgency sampleAgency,
    required String cap,
    required String venue,
    String? creditOverride,
    /// When set, that [CaptionSegment.customText] index is emitted as
    /// [_kCustomNarrativePreviewPlaceholder] and empty custom text is not
    /// dropped (so gaps match an empty slot).
    int? customSegmentPlaceholderIndex,
  }) {
    String valueAt(int segmentIndex) {
      final s = template.segmentOrder[segmentIndex];
      switch (s) {
        case CaptionSegment.location:
          final occ = segmentOccurrenceIndex(
              template.segmentOrder, segmentIndex, CaptionSegment.location);
          final locOpts = locationLineOptionsForOccurrence(template, occ);
          final gettyWire = template.wireStyle == WireStyle.getty ||
              template.wireStyle == WireStyle.gettyInternational;
          return formatLocationLine(
            game,
            locOpts,
            apStyleCaption: template.wireStyle == WireStyle.ap,
            cpStyleCaption: template.wireStyle == WireStyle.cp,
            forceAutoAdaptUsIntl: gettyWire,
            locationOccurrenceIndex: occ,
          );
        case CaptionSegment.city:
        case CaptionSegment.state:
        case CaptionSegment.country:
        case CaptionSegment.countryCode:
          final kind = s == CaptionSegment.city
              ? LocationChipKind.city
              : s == CaptionSegment.state
                  ? LocationChipKind.region
                  : s == CaptionSegment.countryCode
                      ? LocationChipKind.countryCode
                      : LocationChipKind.country;
          final occ = segmentOccurrenceIndex(
              template.segmentOrder, segmentIndex, s);
          final locOpts = locationLineOptionsForOccurrence(template, occ);
          // Getty only auto-adapts State↔Country; Imagn keeps both when present.
          final gettyWire = template.wireStyle == WireStyle.getty ||
              template.wireStyle == WireStyle.gettyInternational;
          return formatGeoField(
            game: game,
            options: locOpts,
            kind: kind,
            apStyleCaption: template.wireStyle == WireStyle.ap,
            cpStyleCaption: template.wireStyle == WireStyle.cp,
            forceAutoAdaptUsIntl: gettyWire,
            formulaIncludesCountry:
                template.segmentOrder.contains(CaptionSegment.country),
          );
        case CaptionSegment.date:
          final occ = segmentOccurrenceIndex(
              template.segmentOrder, segmentIndex, CaptionSegment.date);
          final f = dateFormulaForOccurrence(template, occ);
          return formatTemplateDateLine(
            game,
            template,
            uppercaseAll: template.wireStyle == WireStyle.getty ||
                template.wireStyle == WireStyle.gettyInternational,
            dateFormulaOverride: f,
          );
        case CaptionSegment.month:
        case CaptionSegment.day:
        case CaptionSegment.year:
        case CaptionSegment.weekday:
          final kind = dateFieldKindForSegment(s)!;
          final occ = segmentOccurrenceIndex(
              template.segmentOrder, segmentIndex, s);
          return formatDatePart(
            game: game,
            template: template,
            kind: kind,
            occurrenceIndex: occ,
          );
        case CaptionSegment.caption:
          return '${template.captionPrefix}$cap${template.captionSuffix}';
        case CaptionSegment.customText:
          if (customSegmentPlaceholderIndex != null &&
              segmentIndex == customSegmentPlaceholderIndex) {
            return '${template.gameIdentifierPrefix}'
                '$_kCustomNarrativePreviewPlaceholder'
                '${template.gameIdentifierSuffix}';
          }
          final gameIdentifier = template.gameIdentifierText.trim();
          return '${template.gameIdentifierPrefix}'
              '$gameIdentifier'
              '${template.gameIdentifierSuffix}';
        case CaptionSegment.freeText:
          return freeTextSnippetFor(template, segmentIndex);
        case CaptionSegment.separator:
          return separatorSnippetFor(template, segmentIndex);
        case CaptionSegment.punctuation:
          return punctuationSnippetFor(template, segmentIndex);
        case CaptionSegment.venue:
          return '${template.venuePrefix}$venue${template.venueSuffix}';
        case CaptionSegment.creator:
          return formatCreatorName(
            game: game,
            bylineOptions: template.bylineOptions,
          );
        case CaptionSegment.agency:
          return formatAgencyCredit(
            game: game,
            bylineOptions: template.bylineOptions,
            sampleAgency: sampleAgency,
          );
        case CaptionSegment.credit:
          final manualCredit = creditOverride?.trim() ?? '';
          if (manualCredit.isNotEmpty) return manualCredit;
          return formatCreditLine(
            format: template.creditFormat,
            bylineOptions: template.bylineOptions,
            photographerName: game.photographerName,
            agencyName: game.agencyName,
            iptcMetadata: game.iptcMetadata,
            sampleAgency: sampleAgency,
            apShortParen: template.wireStyle == WireStyle.ap || template.wireStyle == WireStyle.cp,
            customTexts: template.bylineOptions.customTexts,
          );
      }
    }

    final order = template.segmentOrder;
    if (order.isEmpty) return '';

    final n = order.length;
    final hasGlueSegments = order.any(
      (s) =>
          s == CaptionSegment.punctuation || s == CaptionSegment.separator,
    );

    // Build incrementally: join each new piece, removing duplicated punctuation
    // at the boundary so we never get "- -", ": :", ". .", "atat", etc.
    String joined = '';

    if (hasGlueSegments) {
      // Hold only geo-style Structure glue ("," ";" "/" "-") across empty
      // City/State/Country so "Toronto, , Canada" does not appear. Literals
      // like "(Photo by " / ")" must emit immediately — otherwise a trailing
      // ")" chip is held forever and never written to IPTC.
      final deferEmptyGeoGlue = _shouldDeferGlueForEmptyGeo(template);
      String? pendingGlue;
      for (var i = 0; i < n; i++) {
        final s = order[i];
        if (customSegmentPlaceholderIndex == null &&
            (s == CaptionSegment.customText || s == CaptionSegment.freeText) &&
            valueAt(i).trim().isEmpty) {
          continue;
        }
        final part = valueAt(i);
        final isGlue = s == CaptionSegment.punctuation ||
            s == CaptionSegment.separator;
        if (isGlue) {
          if (part.isEmpty) continue;
          if (deferEmptyGeoGlue && _isDeferableGeoGlue(part)) {
            // Keep the latest geo glue before the next content piece so an
            // empty geo field (auto-adapt) does not stack ", ," separators.
            pendingGlue = part;
            continue;
          }
          if (deferEmptyGeoGlue &&
              pendingGlue != null &&
              pendingGlue.isNotEmpty) {
            joined = joined.isEmpty
                ? pendingGlue
                : _joinWithoutDuplicateOverlap(joined, pendingGlue);
            pendingGlue = null;
          }
          joined = joined.isEmpty
              ? part
              : _joinWithoutDuplicateOverlap(joined, part);
          continue;
        }
        if (part.isEmpty) continue;
        if (deferEmptyGeoGlue) {
          if (pendingGlue != null && pendingGlue.isNotEmpty) {
            joined = joined.isEmpty
                ? pendingGlue
                : _joinWithoutDuplicateOverlap(joined, pendingGlue);
            pendingGlue = null;
          } else {
            pendingGlue = null;
          }
        }
        joined =
            joined.isEmpty ? part : _joinWithoutDuplicateOverlap(joined, part);
      }
      // Drop leftover geo glue after a trailing empty field (e.g. empty
      // Country). Non-geo literals were already emitted above.
      pendingGlue = null;
    } else {
      final gaps = effectiveSegmentGaps(template);
      for (var i = 0; i < n; i++) {
        final s = order[i];
        if (customSegmentPlaceholderIndex == null &&
            (s == CaptionSegment.customText || s == CaptionSegment.freeText) &&
            valueAt(i).trim().isEmpty) {
          continue;
        }
        final part = valueAt(i);
        if (part.isNotEmpty) {
          joined = joined.isEmpty ? part : _joinWithoutDuplicateOverlap(joined, part);
        }
        if (i < n - 1 && i < gaps.length) {
          final gap = gaps[i];
          if (gap.isNotEmpty) {
            joined = joined.isEmpty ? gap : _joinWithoutDuplicateOverlap(joined, gap);
          }
        }
      }
    }

    // Prepend/append the whole-layout prefix and suffix. These are always
    // visible as editable text boxes in the layout builder so nothing is hidden.
    final prefix = template.layoutPrefix;
    final suffix = template.layoutSuffix;
    if (prefix.isNotEmpty) {
      joined = joined.isEmpty ? prefix : _joinWithoutDuplicateOverlap(prefix, joined);
    }
    if (suffix.isNotEmpty) {
      joined = joined.isEmpty ? suffix : _joinWithoutDuplicateOverlap(joined, suffix);
    }
    joined = _cleanDuplicatePunctuation(joined);
    if (_shouldApplyGettyCaptionCleanup(template) ||
        joined.contains('(Photo by')) {
      joined = _cleanGettyCaptionPunctuation(joined);
    }
    // Default captionSuffix / trailing glue literals / layoutSuffix can leave a
    // dangling space after the last content segment — strip only the end.
    return joined.trimRight();
  }

  /// True when [text] is only field glue that should drop with an empty
  /// auto-adapted State/Country slot. Matches Structure PREVIEW's
  /// `_isStructureGeoGlue` so credit literals like `)` are never deferred.
  static bool _isDeferableGeoGlue(String text) {
    final t = text.trim();
    if (t.isEmpty) return true;
    return RegExp(r'^[,;|/–—\-]+$').hasMatch(t);
  }

  /// Whether empty content should swallow adjacent Structure glue so
  /// `{city}, {state}` does not leave a dangling comma when State is empty
  /// (Getty/Imagn auto-adapt, AP/CP standalone-city omit).
  static bool _shouldDeferGlueForEmptyGeo(CaptionTemplate template) {
    if (template.wireStyle == WireStyle.getty ||
        template.wireStyle == WireStyle.gettyInternational ||
        template.wireStyle == WireStyle.imagn ||
        template.wireStyle == WireStyle.ap ||
        template.wireStyle == WireStyle.cp) {
      return true;
    }
    if (template.locationOptions.autoAdaptUsIntl) return true;
    final byOcc = template.locationOptionsByOccurrence;
    return byOcc != null && byOcc.any((o) => o.autoAdaptUsIntl);
  }

  /// Getty (and Getty-like custom) captions need the same glue cleanup.
  /// Kept independent of [_shouldDeferGlueForEmptyGeo] so Imagn gets empty-geo
  /// hold without Getty-specific `, -` / `, .` rewrites.
  static bool _shouldApplyGettyCaptionCleanup(CaptionTemplate template) {
    if (template.wireStyle == WireStyle.getty ||
        template.wireStyle == WireStyle.gettyInternational) {
      return true;
    }
    if (template.locationOptions.autoAdaptUsIntl) return true;
    final byOcc = template.locationOptionsByOccurrence;
    if (byOcc != null && byOcc.any((o) => o.autoAdaptUsIntl)) return true;
    final prefix = template.bylineOptions.prefix.toLowerCase();
    return template.creditFormat == CreditFormat.photo_by &&
        prefix.contains('photo by');
  }

  /// Getty wire cleanup for common formula glue mistakes around location lines.
  static String _cleanGettyCaptionPunctuation(String s) {
    var r = s;
    // "TORONTO, CANADA, -" → "TORONTO, CANADA -"
    r = r.replaceAll(RegExp(r',\s+-'), ' -');
    // "in Toronto, Canada, ." → "in Toronto, Canada."
    r = r.replaceAll(RegExp(r',\s+\.'), '.');
    r = r.replaceAll(RegExp(r'  +'), ' ');
    return r;
  }

  /// Joins two adjacent caption parts, removing any duplicate punctuation at
  /// the boundary so the rendered preview never shows `- -`, `: :`, `. .`, etc.
  static String _joinWithoutDuplicateOverlap(String left, String right) {
    if (left.isEmpty) return right;
    if (right.isEmpty) return left;

    // Phase 1 — exact suffix / prefix overlap (handles most cases).
    final max = left.length < right.length ? left.length : right.length;
    for (var len = max; len > 0; len--) {
      if (left.endsWith(right.substring(0, len))) {
        return left + right.substring(len);
      }
    }

    // Phase 2 — whitespace-normalised overlap.
    // e.g. left = "…game at " · right = "at the…"  → leftT = "…game at", rightT = "at the…"
    //      leftT ends with "at" which matches rightT[0..2] "at" → keep one copy.
    final leftT = left.trimRight();
    final rightT = right.trimLeft();
    if ((leftT.length < left.length || rightT.length < right.length) &&
        leftT.isNotEmpty &&
        rightT.isNotEmpty) {
      final maxT =
          leftT.length < rightT.length ? leftT.length : rightT.length;
      for (var len = maxT; len > 0; len--) {
        if (leftT.endsWith(rightT.substring(0, len))) {
          // Preserve left's original trailing whitespace; any resulting double
          // space is collapsed by _cleanDuplicatePunctuation below.
          return left + rightT.substring(len);
        }
      }
    }

    return left + right;
  }

  /// Final-pass cleanup: collapse any duplicate punctuation that slipped
  /// through the join algorithm (e.g. when the location formula itself
  /// embeds a trailing dash that matches the following glue snippet).
  static String _cleanDuplicatePunctuation(String s) {
    var r = s;
    // Two or more dashes (with optional surrounding spaces) → single " - "
    // Handles: "- -", " - -", "- - ", " - - ", "--", etc.
    r = r.replaceAll(RegExp(r'\s*-\s+-\s*'), ' - ');
    // Two colons (with optional space between) → single ": "
    // Handles: ": :", "::", ": : "
    r = r.replaceAll(RegExp(r':\s*:'), ': ');
    // Two periods (with optional space between) → single ". "
    // Handles: ". .", "..", ". . "
    r = r.replaceAll(RegExp(r'\.\s+\.'), '. ');
    // Soften stacked commas from an empty Structure slot: "Toronto, , Canada"
    // → "Toronto, Canada" (space after the kept comma comes from the next token).
    r = r.replaceAll(RegExp(r',\s+,'), ',');
    // Collapse multiple spaces down to one
    r = r.replaceAll(RegExp(r'  +'), ' ');
    return r;
  }

  static bool _segmentPairEither(
    CaptionSegment a,
    CaptionSegment b,
    CaptionSegment x,
    CaptionSegment y,
  ) =>
      (a == x && b == y) || (a == y && b == x);

  /// Date (legacy or any date part) adjacent to any geo field.
  static bool _geoDatePair(CaptionSegment a, CaptionSegment b) {
    bool isDateish(CaptionSegment s) =>
        s == CaptionSegment.date || isDatePartSegment(s);
    return (isGeoFieldSegment(a) && isDateish(b)) ||
        (isGeoFieldSegment(b) && isDateish(a));
  }

  static bool _dateCaptionPair(CaptionSegment a, CaptionSegment b) {
    bool isDateish(CaptionSegment s) =>
        s == CaptionSegment.date || isDatePartSegment(s);
    return (isDateish(a) && b == CaptionSegment.caption) ||
        (isDateish(b) && a == CaptionSegment.caption);
  }

  /// Default joiner between [a] and [b] for this wire (any segment order).
  static String defaultGapBetweenSegments(
    CaptionTemplate preset,
    CaptionSegment a,
    CaptionSegment b,
  ) {
    if (a == CaptionSegment.separator ||
        b == CaptionSegment.separator ||
        a == CaptionSegment.punctuation ||
        b == CaptionSegment.punctuation) {
      return '';
    }
    switch (preset.wireStyle) {
      case WireStyle.getty:
      case WireStyle.gettyInternational:
        if (_segmentPairEither(
                a, b, CaptionSegment.location, CaptionSegment.date) ||
            _geoDatePair(a, b)) {
          return ' - ';
        }
        if (_dateCaptionPair(a, b)) {
          return ': ';
        }
        if (a == CaptionSegment.caption && b == CaptionSegment.customText) {
          return ' ';
        }
        if (a == CaptionSegment.customText && b == CaptionSegment.venue) {
          return ' at ';
        }
        if (a == CaptionSegment.customText &&
            (b == CaptionSegment.credit ||
                b == CaptionSegment.creator ||
                b == CaptionSegment.agency)) {
          return '. ';
        }
        if (a == CaptionSegment.creator && b == CaptionSegment.agency) {
          return preset.bylineOptions.between;
        }
        if (isGeoFieldSegment(a) && isGeoFieldSegment(b)) return ', ';
        if (isDatePartSegment(a) && isDatePartSegment(b)) return ' ';
        if (b == CaptionSegment.venue) return ' at ';
        if (b == CaptionSegment.credit ||
            b == CaptionSegment.creator ||
            b == CaptionSegment.agency) {
          return '. ';
        }
        return ' ';
      case WireStyle.imagn:
        // Structure owns all joiners via punctuation/separator snippets.
        // Never inject `; `, `, `, ` at `, `. ` here — that stacks with Structure.
        if (a == CaptionSegment.creator && b == CaptionSegment.agency) {
          return preset.bylineOptions.between;
        }
        return '';
      case WireStyle.ap:
      case WireStyle.cp:
        if (_segmentPairEither(
                a, b, CaptionSegment.location, CaptionSegment.date) ||
            _geoDatePair(a, b)) {
          return ' (';
        }
        if (_dateCaptionPair(a, b)) {
          return ') — ';
        }
        if (a == CaptionSegment.caption && b == CaptionSegment.customText) {
          return ' ';
        }
        if (a == CaptionSegment.customText && b == CaptionSegment.venue) {
          return ' at ';
        }
        if (a == CaptionSegment.customText &&
            (b == CaptionSegment.credit ||
                b == CaptionSegment.creator ||
                b == CaptionSegment.agency)) {
          return '. ';
        }
        if (a == CaptionSegment.creator && b == CaptionSegment.agency) {
          return preset.bylineOptions.between;
        }
        if (isGeoFieldSegment(a) && isGeoFieldSegment(b)) return ', ';
        if (isDatePartSegment(a) && isDatePartSegment(b)) return ' ';
        if (b == CaptionSegment.venue) return ' at ';
        if (b == CaptionSegment.credit ||
            b == CaptionSegment.creator ||
            b == CaptionSegment.agency) {
          return '. ';
        }
        return ' ';
      case WireStyle.custom:
        return preset.separator;
    }
  }

  /// Default gaps when switching to Custom from a wire preset (between consecutive segments in [order]).
  static List<String> defaultCustomGaps(CaptionTemplate preset) {
    final order = preset.segmentOrder;
    if (order.length < 2) return [];

    final gaps = <String>[];
    for (var i = 0; i < order.length - 1; i++) {
      gaps.add(defaultGapBetweenSegments(preset, order[i], order[i + 1]));
    }
    return gaps;
  }
}

