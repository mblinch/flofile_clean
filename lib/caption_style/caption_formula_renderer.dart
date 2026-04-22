import 'dart:math';

import 'package:intl/intl.dart';

import 'caption_template.dart';
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
  static String formatTemplateDateLine(
    GameInfo game,
    CaptionTemplate template, {
    bool uppercaseAll = false,
  }) {
    final formula = template.dateFormula;
    if (formula != null && formula.fields.isNotEmpty) {
      final date = _resolveFormulaDate(game, template.dateFormulaSource);
      final s = date != null ? formula.render(date) : '—';
      return uppercaseAll ? s.toUpperCase() : s;
    }
    final expr = template.dateExpression.trim();
    if (expr.isEmpty) {
      return formatDate(game.gameDate, template.dateFormat, uppercaseAll: uppercaseAll);
    }
    final s = _formatDateExpressionString(game, template, expr);
    return uppercaseAll ? s.toUpperCase() : s;
  }

  /// Resolves the [DateTime] that a [DateFormula] should render against.
  static DateTime? _resolveFormulaDate(GameInfo game, DateFormulaSource source) {
    switch (source) {
      case DateFormulaSource.template:
        return game.gameDate;
      case DateFormulaSource.photo:
        final raw = _lookupIptcDateRaw(game, 'DateTimeOriginal');
        if (raw != null && raw.isNotEmpty) {
          final dt = parseMetadataDate(raw);
          if (dt != null) return dt;
        }
        return game.gameDate;
    }
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

  static String _evalDateVarToken(String inner, GameInfo game, CaptionTemplate template) {
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
            final useShort =
                c.regionVariant == LocationRegionVariant.shortForm;
            raw = (useShort ? g.resolvedRegionShort : g.resolvedRegionName)
                .trim();
            if (raw.isEmpty) {
              raw = (useShort ? g.resolvedRegionName : g.resolvedRegionShort)
                  .trim();
            }
          } else {
            final useIso =
                c.countryVariant == LocationCountryVariant.isoCode;
            raw = (useIso ? g.resolvedCountryCode : g.resolvedCountryName)
                .trim();
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
    required String photographerName,
    required String agencyName,
    required CreditSampleAgency sampleAgency,
    bool apShortParen = false,
  }) {
    final name =
        photographerName.trim().isEmpty ? 'Photographer' : photographerName.trim();
    var agency = agencyName.trim();
    if (agency.isEmpty) {
      agency = defaultAgencyLabel(sampleAgency);
    }
    if (apShortParen) {
      final short = agency.length > 20 || agency.contains('Associated')
          ? 'AP'
          : agency;
      return '($name/$short)';
    }
    switch (format) {
      case CreditFormat.photo_by:
        return '(Photo by $name/$agency)';
      case CreditFormat.mandatory_credit:
        return 'Mandatory Credit: $name-$agency';
    }
  }

  static String sampleDynamicCaption(NumberFormatStyle nf) {
    return randomSinglePlayerCaption(nf, seed: 0);
  }

  /// Seeded preview caption featuring a single player from the mock game roster.
  /// Stable output per [seed] so the dialog can rebuild without flicker but still
  /// re-roll on demand.
  static String randomSinglePlayerCaption(
    NumberFormatStyle nf, {
    int seed = 0,
  }) {
    final rand = Random(seed);
    final player = _samplePlayers[rand.nextInt(_samplePlayers.length)];
    final actionTemplate =
        _sampleActions[rand.nextInt(_sampleActions.length)];
    final numText = nf == NumberFormatStyle.hash
        ? '#${player.number}'
        : '(${player.number})';
    final action = actionTemplate.replaceAll('{opp}', player.opponent);
    return '${player.team} ${player.position} ${player.name} $numText $action';
  }

  static const List<_SamplePlayer> _samplePlayers = [
    _SamplePlayer('Toronto FC', 'forward', 'Josh Sargent', 9, 'Colorado Rapids'),
    _SamplePlayer('Toronto FC', 'forward', 'Dániel Sallói', 20, 'Colorado Rapids'),
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
    _SamplePlayer(
        'Colorado Rapids', 'midfielder', 'Djordje Mihailovic', 14, 'Toronto FC'),
    _SamplePlayer(
        'Colorado Rapids', 'midfielder', 'Cole Bassett', 26, 'Toronto FC'),
    _SamplePlayer(
        'Colorado Rapids', 'defender', 'Moïse Bombito', 5, 'Toronto FC'),
    _SamplePlayer(
        'Colorado Rapids', 'goalkeeper', 'Zack Steffen', 1, 'Toronto FC'),
  ];

  static const List<String> _sampleActions = [
    'celebrates scoring against the {opp} during the second half',
    'takes a shot on goal during the first half against the {opp}',
    'controls the ball in the attacking third during the second half against the {opp}',
    'challenges for a header during the first half against the {opp}',
    'battles for possession at midfield during the match against the {opp}',
    'dribbles past defenders during the second half against the {opp}',
    'reacts after a missed chance during the first half against the {opp}',
    'directs teammates during a set piece against the {opp}',
    'makes a save during the second half against the {opp}',
    'clears the ball out of the defensive third against the {opp}',
  ];

  static String render({
    required CaptionTemplate template,
    required GameInfo game,
    required CreditSampleAgency sampleAgency,
    String? captionOverride,
  }) {
    final cap = captionOverride ?? sampleDynamicCaption(template.numberFormat);
    final loc = formatLocationLine(game, template.locationOptions);
    final date = formatTemplateDateLine(game, template, uppercaseAll: false);
    final dateU = formatTemplateDateLine(game, template, uppercaseAll: true);
    final venue = game.venue.trim().isEmpty ? 'Venue' : game.venue.trim();
    final credit = formatCreditLine(
      format: template.creditFormat,
      photographerName: game.photographerName,
      agencyName: game.agencyName,
      sampleAgency: sampleAgency,
      apShortParen: template.wireStyle == WireStyle.ap,
    );

    switch (template.wireStyle) {
      case WireStyle.getty:
        return '$loc - $dateU: $cap at $venue. $credit';
      case WireStyle.imagn:
        return '$date; $loc; $cap at $venue. $credit';
      case WireStyle.ap:
        return '$loc ($date) — $cap at $venue. $credit';
      case WireStyle.custom:
        return _renderCustom(
          template: template,
          game: game,
          sampleAgency: sampleAgency,
          loc: loc,
          date: date,
          cap: cap,
          venue: venue,
        );
    }
  }

  static String _renderCustom({
    required CaptionTemplate template,
    required GameInfo game,
    required CreditSampleAgency sampleAgency,
    required String loc,
    required String date,
    required String cap,
    required String venue,
  }) {
    String value(CaptionSegment s) {
      switch (s) {
        case CaptionSegment.location:
          return loc;
        case CaptionSegment.date:
          return date;
        case CaptionSegment.caption:
          return cap;
        case CaptionSegment.venue:
          return venue;
        case CaptionSegment.credit:
          return formatCreditLine(
            format: template.creditFormat,
            photographerName: game.photographerName,
            agencyName: game.agencyName,
            sampleAgency: sampleAgency,
          );
      }
    }

    final order = template.segmentOrder;
    if (order.isEmpty) return '';

    final gaps = template.customSeparators;
    final n = order.length;
    if (gaps != null && gaps.length == n - 1) {
      final b = StringBuffer()..write(value(order.first));
      for (var i = 1; i < n; i++) {
        b.write(gaps[i - 1]);
        b.write(value(order[i]));
      }
      return b.toString();
    }

    final b = StringBuffer()..write(value(order.first));
    for (var i = 1; i < n; i++) {
      b.write(template.separator);
      b.write(value(order[i]));
    }
    return b.toString();
  }

  /// Default gaps when switching to Custom from a wire preset (between consecutive segments in [order]).
  static List<String> defaultCustomGaps(CaptionTemplate preset) {
    final order = preset.segmentOrder;
    if (order.length < 2) return [];

    String gapBetween(CaptionSegment a, CaptionSegment b) {
      switch (preset.wireStyle) {
        case WireStyle.getty:
          if (a == CaptionSegment.location && b == CaptionSegment.date) {
            return ' - ';
          }
          if (a == CaptionSegment.date && b == CaptionSegment.caption) return ': ';
          if (b == CaptionSegment.venue) return ' at ';
          if (b == CaptionSegment.credit) return '. ';
          return ' ';
        case WireStyle.imagn:
          if (b == CaptionSegment.credit) return '. ';
          if (b == CaptionSegment.venue) return ' at ';
          return '; ';
        case WireStyle.ap:
          if (a == CaptionSegment.location && b == CaptionSegment.date) {
            return ' (';
          }
          if (a == CaptionSegment.date && b == CaptionSegment.caption) {
            return ') — ';
          }
          if (b == CaptionSegment.venue) return ' at ';
          if (b == CaptionSegment.credit) return '. ';
          return ' ';
        case WireStyle.custom:
          return preset.separator;
      }
    }

    final gaps = <String>[];
    for (var i = 0; i < order.length - 1; i++) {
      gaps.add(gapBetween(order[i], order[i + 1]));
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
