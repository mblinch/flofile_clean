import 'dart:math';

import 'package:intl/intl.dart';

import 'caption_template.dart';
import 'caption_text_normalize.dart';
import 'date_formula.dart';
import 'game_info.dart';

/// Drives the sample credit line dropdown (preview branding).
enum CreditSampleAgency { gettyImages, imagn, ap }

/// Renders static frame + sample dynamic caption for the layout dialog preview.
class CaptionFormulaRenderer {
  CaptionFormulaRenderer._();

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
    return uppercaseAll ? s.toUpperCase() : s;
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

  /// Builds the location line from [GameInfo] using ordered [LocationLineOptions.chips].
  ///
  /// - Per-chip `caps` uppercases just that chip's emitted text.
  /// - The legacy global [LocationLineOptions.uppercase] still force-caps the
  ///   whole line after assembly (kept for templates that haven't migrated).
  /// - When two geo chips render back-to-back with no literal between them,
  ///   a single space is inserted so fields never run together.
  static String formatLocationLine(GameInfo g, LocationLineOptions options) {
    final b = StringBuffer();
    var lastEmittedWasGeo = false;
    for (final c in options.chips) {
      switch (c.kind) {
        case LocationChipKind.city:
        case LocationChipKind.region:
        case LocationChipKind.country:
          String raw;
          if (c.kind == LocationChipKind.city) {
            raw = g.city.trim();
          } else if (c.kind == LocationChipKind.region) {
            final useShort = c.regionVariant == LocationRegionVariant.shortForm;
            raw = (useShort ? g.resolvedRegionShort : g.resolvedRegionName)
                .trim();
            if (raw.isEmpty) {
              raw = (useShort ? g.resolvedRegionName : g.resolvedRegionShort)
                  .trim();
            }
          } else {
            final useIso = c.countryVariant == LocationCountryVariant.isoCode;
            raw =
                (useIso ? g.resolvedCountryCode : g.resolvedCountryName).trim();
            if (raw.isEmpty) {
              raw = (useIso ? g.resolvedCountryName : g.resolvedCountryCode)
                  .trim();
            }
          }
          if (raw.isEmpty) {
            lastEmittedWasGeo = false;
            break;
          }
          if (lastEmittedWasGeo) b.write(' ');
          b.write(c.caps ? raw.toUpperCase() : raw);
          lastEmittedWasGeo = true;
          break;
        case LocationChipKind.literal:
          b.write(c.literal);
          if (c.literal.isNotEmpty) lastEmittedWasGeo = false;
          break;
      }
    }
    var s = b.toString();
    if (s.trim().isEmpty) return '—';
    if (options.uppercase) s = s.toUpperCase();
    return s;
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

  /// [occurrenceIndex] counts only [CaptionSegment.location] entries, left-to-right.
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

  static String formatCreditLine({
    required CreditFormat format,
    required BylineOptions bylineOptions,
    required String photographerName,
    required String agencyName,
    required Map<String, String> iptcMetadata,
    required CreditSampleAgency sampleAgency,
    bool apShortParen = false,
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

    if (apShortParen) {
      final short =
          credit.length > 20 || credit.contains('Associated') ? 'AP' : credit;
      return '($name/$short)';
    }
    String fieldValue(BylineFieldKind kind) {
      switch (kind) {
        case BylineFieldKind.name:
          return name;
        case BylineFieldKind.credit:
          return credit;
        case BylineFieldKind.copyright:
          return copyright;
      }
    }

    final fields = bylineOptions.fieldOrder
        .map(fieldValue)
        .where((v) => v.trim().isNotEmpty)
        .toList();
    if (fields.isEmpty) return '';
    return '${bylineOptions.prefix}${fields.join(bylineOptions.between)}${bylineOptions.suffix}';
  }

  static String sampleDynamicCaption(CaptionTemplate template) {
    return randomSinglePlayerCaption(template, seed: 0);
  }

  static String _numberToken(NumberFormatStyle nf, int number) {
    return nf == NumberFormatStyle.hash ? '#$number' : '($number)';
  }

  static String _possessiveTeam(String team) {
    final trimmed = team.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed.toLowerCase().endsWith('s') ? "$trimmed'" : "$trimmed's";
  }

  static String _singlePlayerLead(CaptionTemplate template, _SamplePlayer player) {
    var playerName = player.name;
    var teamName = player.team;
    if (template.removeDiacritics) {
      playerName = CaptionTextNormalize.stripDiacritics(playerName);
      teamName = CaptionTextNormalize.stripDiacritics(teamName);
    }
    final numText = _numberToken(template.numberFormat, player.number);
    final position = template.includePlayerPosition ? ' ${player.position}' : '';
    final teamPossessive = _possessiveTeam(teamName);
    switch (template.captionTeamOrder) {
      case CaptionTeamOrder.teamAfter:
        return '$playerName $numText of $teamName$position';
      case CaptionTeamOrder.teamBefore:
        if (template.includePlayerPosition) {
          return '$teamName$position $playerName $numText';
        }
        return '$teamPossessive $playerName $numText';
    }
  }

  /// Seeded player-only preview text (no action clause).
  static String randomSinglePlayerPreview(
    CaptionTemplate template, {
    int seed = 0,
  }) {
    final rand = Random(seed);
    final player = _samplePlayers[rand.nextInt(_samplePlayers.length)];
    return _singlePlayerLead(template, player);
  }

  /// Seeded preview caption featuring a single player from the mock game roster.
  /// Stable output per [seed] so the dialog can rebuild without flicker but still
  /// re-roll on demand.
  static String randomSinglePlayerCaption(
    CaptionTemplate template, {
    int seed = 0,
  }) {
    final rand = Random(seed);
    final player = _samplePlayers[rand.nextInt(_samplePlayers.length)];
    final lead = _singlePlayerLead(template, player);
    final actionTemplate =
        _sampleActions[rand.nextInt(_sampleActions.length)];
    var opp = player.opponent;
    if (template.removeDiacritics) {
      opp = CaptionTextNormalize.stripDiacritics(opp);
    }
    final action = actionTemplate.replaceAll('{opp}', opp);
    var line = '$lead $action';
    if (template.removeDiacritics) {
      line = CaptionTextNormalize.stripDiacritics(line);
    }
    return line;
  }

  static const List<_SamplePlayer> _samplePlayers = [
    _SamplePlayer(
        'Toronto FC', 'forward', 'Josh Sargent', 9, 'Colorado Rapids'),
    _SamplePlayer(
        'Toronto FC', 'forward', 'Dániel Sallói', 20, 'Colorado Rapids'),
    _SamplePlayer('Toronto FC', 'forward', 'Federico Bernardeschi', 10,
        'Colorado Rapids'),
    _SamplePlayer(
        'Toronto FC', 'midfielder', 'Jonathan Osorio', 21, 'Colorado Rapids'),
    _SamplePlayer(
        'Toronto FC', 'midfielder', 'Matty Longstaff', 16, 'Colorado Rapids'),
    _SamplePlayer(
        'Toronto FC', 'defender', 'Richie Laryea', 22, 'Colorado Rapids'),
    _SamplePlayer(
        'Toronto FC', 'goalkeeper', 'Sean Johnson', 1, 'Colorado Rapids'),
    _SamplePlayer(
        'Colorado Rapids', 'forward', 'Rafael Navarro', 10, 'Toronto FC'),
    _SamplePlayer('Colorado Rapids', 'midfielder', 'Djordje Mihailovic', 14,
        'Toronto FC'),
    _SamplePlayer(
        'Colorado Rapids', 'midfielder', 'Cole Bassett', 26, 'Toronto FC'),
    _SamplePlayer(
        'Colorado Rapids', 'defender', 'Moïse Bombito', 5, 'Toronto FC'),
    _SamplePlayer(
        'Colorado Rapids', 'goalkeeper', 'Zack Steffen', 1, 'Toronto FC'),
  ];

  static const List<String> _sampleActions = [
    'celebrates scoring against the {opp} during the second half',
    'takes a shot on goal against the {opp} during the first half',
    'controls the ball in the attacking third against the {opp} during the second half',
    'challenges for a header against the {opp} during the first half',
    'battles for possession at midfield against the {opp} during the match',
    'dribbles past defenders against the {opp} during the second half',
    'reacts after a missed chance against the {opp} during the first half',
    'directs teammates against the {opp} during a set piece',
    'makes a save against the {opp} during the second half',
    'clears the ball out of the defensive third against the {opp}',
  ];

  static String render({
    required CaptionTemplate template,
    required GameInfo game,
    required CreditSampleAgency sampleAgency,
    String? captionOverride,
  }) {
    final cap = captionOverride ?? sampleDynamicCaption(template);
    final venue = game.venue.trim().isEmpty ? 'Venue' : game.venue.trim();

    return _renderFromSegments(
      template: template,
      game: game,
      sampleAgency: sampleAgency,
      cap: cap,
      venue: venue,
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
  }) {
    String valueAt(int segmentIndex) {
      final s = template.segmentOrder[segmentIndex];
      switch (s) {
        case CaptionSegment.location:
          final occ = segmentOccurrenceIndex(
              template.segmentOrder, segmentIndex, CaptionSegment.location);
          return formatLocationLine(
            game,
            locationLineOptionsForOccurrence(template, occ),
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
        case CaptionSegment.caption:
          return cap;
        case CaptionSegment.venue:
          return venue;
        case CaptionSegment.credit:
          return formatCreditLine(
            format: template.creditFormat,
            bylineOptions: template.bylineOptions,
            photographerName: game.photographerName,
            agencyName: game.agencyName,
            iptcMetadata: game.iptcMetadata,
            sampleAgency: sampleAgency,
          );
      }
    }

    final order = template.segmentOrder;
    if (order.isEmpty) return '';

    final n = order.length;
    final gapList = effectiveSegmentGaps(template);
    final b = StringBuffer()..write(valueAt(0));
    for (var i = 1; i < n; i++) {
      b.write(gapList[i - 1]);
      b.write(valueAt(i));
    }
    return b.toString();
  }

  static bool _segmentPairEither(
    CaptionSegment a,
    CaptionSegment b,
    CaptionSegment x,
    CaptionSegment y,
  ) =>
      (a == x && b == y) || (a == y && b == x);

  /// Default joiner between [a] and [b] for this wire (any segment order).
  static String defaultGapBetweenSegments(
    CaptionTemplate preset,
    CaptionSegment a,
    CaptionSegment b,
  ) {
    switch (preset.wireStyle) {
      case WireStyle.getty:
      case WireStyle.gettyInternational:
        if (_segmentPairEither(
            a, b, CaptionSegment.location, CaptionSegment.date)) {
          return ' - ';
        }
        if (_segmentPairEither(
            a, b, CaptionSegment.date, CaptionSegment.caption)) {
          return ': ';
        }
        if (b == CaptionSegment.venue) return ' at ';
        if (b == CaptionSegment.credit) return '. ';
        return ' ';
      case WireStyle.imagn:
        if (b == CaptionSegment.credit) return '. ';
        if (b == CaptionSegment.venue) return ' at ';
        return '; ';
      case WireStyle.ap:
        if (_segmentPairEither(
            a, b, CaptionSegment.location, CaptionSegment.date)) {
          return ' (';
        }
        if (_segmentPairEither(
            a, b, CaptionSegment.date, CaptionSegment.caption)) {
          return ') — ';
        }
        if (b == CaptionSegment.venue) return ' at ';
        if (b == CaptionSegment.credit) return '. ';
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

class _SamplePlayer {
  const _SamplePlayer(
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
