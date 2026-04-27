import 'dart:math';

import 'package:intl/intl.dart';

import 'caption_template.dart';
import 'caption_text_normalize.dart';
import 'date_formula.dart';
import 'game_info.dart';
import 'position_labels.dart';
import 'region_abbrev.dart';

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

/// Renders static frame + sample dynamic caption for the layout dialog preview.
class CaptionFormulaRenderer {
  CaptionFormulaRenderer._();

  /// Private-use placeholder; must not appear in real segment output.
  static const String _kCustomNarrativePreviewPlaceholder = '\uE000';

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
    while (out.isNotEmpty && out.first.kind == LocationChipKind.literal) {
      out.removeAt(0);
    }
    while (out.isNotEmpty && out.last.kind == LocationChipKind.literal) {
      out.removeLast();
    }
    return out;
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
  static String formatLocationLine(
    GameInfo g,
    LocationLineOptions options, {
    bool apStyleCaption = false,
  }) {
    final b = StringBuffer();
    var lastEmittedWasGeo = false;
    final countryName = g.resolvedCountryName.trim().toLowerCase();
    final countryCode = g.resolvedCountryCode.trim().toLowerCase();
    final isCanada = countryName == 'canada' || countryCode == 'can';
    final chips = _activeLocationChips(options.chips);
    for (final c in chips) {
      switch (c.kind) {
        case LocationChipKind.city:
        case LocationChipKind.region:
        case LocationChipKind.country:
          String raw;
          if (c.kind == LocationChipKind.city) {
            raw = g.city.trim();
          } else if (c.kind == LocationChipKind.region) {
            if (apStyleCaption && isCanada) {
              lastEmittedWasGeo = false;
              break;
            }
            if (c.regionVariant == LocationRegionVariant.apStyle) {
              final full = g.resolvedRegionName.trim();
              raw = abbreviateUsStateApStyle(full);
              if (raw.isEmpty) raw = full;
            } else {
              final useShort = c.regionVariant == LocationRegionVariant.shortForm;
              raw = (useShort ? g.resolvedRegionShort : g.resolvedRegionName)
                  .trim();
              if (raw.isEmpty) {
                raw = (useShort ? g.resolvedRegionName : g.resolvedRegionShort)
                    .trim();
              }
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
    if (apStyleCaption) {
      s = s.replaceFirst(RegExp(r'[,\s]+$'), '');
    }
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
    final position = template.includePlayerPosition
        ? ' ${formatPositionLabelForCaption(
            player.position,
            apStyle: template.wireStyle == WireStyle.ap,
            americanEnglish: template.americanEnglish,
            sport: 'baseball',
          )}'
        : '';
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
    // Preview should always read with a game segment (inning, half-inning,
    // quarter, or half) — append if an action template ever omits one.
    final hasGameSegment = RegExp(
      r'\b(inning|innings|quarter|quarters|halftime)\b|'
      r'\b(first|second)\s+half\b|'
      r'\b(top|bottom)\s+of\s+the\b',
      caseSensitive: false,
    ).hasMatch(line);
    if (!hasGameSegment) {
      line = '$line in the third inning';
    }
    if (template.removeDiacritics) {
      line = CaptionTextNormalize.stripDiacritics(line);
    }
    return line;
  }

  static const List<_SamplePlayer> _samplePlayers = [
    _SamplePlayer('Toronto Blue Jays', 'SP', 'Vladimir Guerrero Jr.', 27,
        'Atlanta Braves'),
    _SamplePlayer(
        'Toronto Blue Jays', 'CF', 'George Springer', 4, 'Atlanta Braves'),
    _SamplePlayer(
        'Toronto Blue Jays', 'SS', 'Bo Bichette', 11, 'Atlanta Braves'),
    _SamplePlayer(
        'Toronto Blue Jays', 'C', 'Danny Jansen', 9, 'Atlanta Braves'),
    _SamplePlayer(
        'Toronto Blue Jays', 'RF', 'Teoscar Hernández', 37, 'Atlanta Braves'),
    _SamplePlayer(
        'Atlanta Braves', 'SP', 'Max Fried', 54, 'Toronto Blue Jays'),
    _SamplePlayer(
        'Atlanta Braves', '3B', 'Austin Riley', 27, 'Toronto Blue Jays'),
    _SamplePlayer(
        'Atlanta Braves', 'RF', 'Ronald Acuña Jr.', 13, 'Toronto Blue Jays'),
    _SamplePlayer(
        'Atlanta Braves', 'C', 'Travis d\'Arnaud', 16, 'Toronto Blue Jays'),
    _SamplePlayer(
        'Atlanta Braves', 'SS', 'Dansby Swanson', 7, 'Toronto Blue Jays'),
  ];

  static const List<String> _sampleActions = [
    'celebrates after hitting a home run against the {opp} in the bottom of the eighth inning',
    'pitches during the third inning against the {opp}',
    'fields a ground ball against the {opp} during the fifth inning',
    'rounds third base against the {opp} during the seventh inning',
    'reacts after striking out against the {opp} in the ninth inning',
    'slides into second base against the {opp} during the fourth inning',
    'warms up in the bullpen during the second inning before facing the {opp}',
    'celebrates with teammates after scoring against the {opp} in the top of the sixth inning',
    'takes a swing against the {opp} in the bottom of the third inning',
    'throws to first base against the {opp} during the first inning',
    'checks the runner at first against the {opp} in the top of the fifth inning',
    'reaches on an error against the {opp} in the bottom of the second inning',
    // Non-baseball time phrases (still paired with MLB sample names for layout preview).
    'works against the {opp} during the third quarter',
    'battles for space against the {opp} in the second half',
  ];

  static String render({
    required CaptionTemplate template,
    required GameInfo game,
    required CreditSampleAgency sampleAgency,
    String? captionOverride,
    String? creditOverride,
  }) {
    final cap = captionOverride ?? sampleDynamicCaption(template);
    final venue = game.venue.trim().isEmpty ? 'Venue' : game.venue.trim();

    return _renderFromSegments(
      template: template,
      game: game,
      sampleAgency: sampleAgency,
      cap: cap,
      venue: venue,
      creditOverride: creditOverride,
      customSegmentPlaceholderIndex: null,
    );
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
  }) {
    final order = template.segmentOrder;
    final cut = order.indexWhere((s) => s == CaptionSegment.customText);
    if (cut < 0) return null;

    final cap = captionOverride ?? sampleDynamicCaption(template);
    final venue = game.venue.trim().isEmpty ? 'Venue' : game.venue.trim();
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
          return formatLocationLine(
            game,
            locationLineOptionsForOccurrence(template, occ),
            apStyleCaption: template.wireStyle == WireStyle.ap,
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
        case CaptionSegment.customText:
          if (customSegmentPlaceholderIndex != null &&
              segmentIndex == customSegmentPlaceholderIndex) {
            return _kCustomNarrativePreviewPlaceholder;
          }
          return template.gameIdentifierText.trim();
        case CaptionSegment.separator:
          return separatorSnippetFor(template, segmentIndex);
        case CaptionSegment.punctuation:
          return punctuationSnippetFor(template, segmentIndex);
        case CaptionSegment.venue:
          return venue;
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
            apShortParen: template.wireStyle == WireStyle.ap,
            customTexts: template.bylineOptions.customTexts,
          );
      }
    }

    final order = template.segmentOrder;
    if (order.isEmpty) return '';

    final n = order.length;
    final gapList = effectiveSegmentGaps(template);

    // Drop an empty [CaptionSegment.customText] slot so the join between
    // caption and venue still uses the correct " at " (not a stray space).
    // Placeholder mode keeps the slot so split preview gaps stay correct.
    final List<int> indices;
    if (customSegmentPlaceholderIndex != null) {
      indices = List<int>.generate(n, (i) => i);
    } else {
      indices = <int>[];
      for (var i = 0; i < n; i++) {
        if (order[i] == CaptionSegment.customText &&
            valueAt(i).trim().isEmpty) {
          continue;
        }
        indices.add(i);
      }
    }
    if (indices.isEmpty) return '';

    final b = StringBuffer()..write(valueAt(indices[0]));
    for (var j = 1; j < indices.length; j++) {
      final prev = indices[j - 1];
      final cur = indices[j];
      final gap = cur == prev + 1
          ? gapList[prev]
          : defaultGapBetweenSegments(template, order[prev], order[cur]);
      b.write(gap);
      b.write(valueAt(cur));
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
            a, b, CaptionSegment.location, CaptionSegment.date)) {
          return ' - ';
        }
        if (_segmentPairEither(
            a, b, CaptionSegment.date, CaptionSegment.caption)) {
          return ': ';
        }
        if (a == CaptionSegment.caption && b == CaptionSegment.customText) {
          return ' ';
        }
        if (a == CaptionSegment.customText && b == CaptionSegment.venue) {
          return ' at ';
        }
        if (a == CaptionSegment.customText && b == CaptionSegment.credit) {
          return '. ';
        }
        if (b == CaptionSegment.venue) return ' at ';
        if (b == CaptionSegment.credit) return '. ';
        return ' ';
      case WireStyle.imagn:
        if (b == CaptionSegment.credit) return '. ';
        if (b == CaptionSegment.venue) return ' at ';
        if (a == CaptionSegment.caption && b == CaptionSegment.customText) {
          return '; ';
        }
        if (a == CaptionSegment.customText && b == CaptionSegment.credit) {
          return '. ';
        }
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
        if (a == CaptionSegment.caption && b == CaptionSegment.customText) {
          return ' ';
        }
        if (a == CaptionSegment.customText && b == CaptionSegment.venue) {
          return ' at ';
        }
        if (a == CaptionSegment.customText && b == CaptionSegment.credit) {
          return '. ';
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
