import 'dart:convert';

import 'date_formula.dart';

/// Wire service preset or fully custom formula.
///
/// Enum order doubles as the display order in the Caption Style dropdown.
/// [getty] is the North America / city–state–country preset (“Getty USA” in UI).
/// [gettyInternational] matches the same caption formula with a City · Region ·
/// Country location line. Added values are appended at the end so
/// previously-serialised templates — which round-trip via `.name` — still
/// decode correctly.
enum WireStyle { getty, imagn, ap, custom, gettyInternational }

/// Legacy enum — migrated into [LocationLineOptions] when reading old JSON.
enum LocationFormat {
  city_region,
  city_region_country,
  city_state_country,
}

/// One draggable token in the location line (place field or punctuation / spacing).
enum LocationChipKind { city, region, country, literal }

/// For [LocationChipKind.country] only: full name vs ISO code from [GameInfo].
enum LocationCountryVariant {
  fullName,
  isoCode,
}

String locationCountryVariantLabel(LocationCountryVariant v) {
  switch (v) {
    case LocationCountryVariant.fullName:
      return 'Full Country Name';
    case LocationCountryVariant.isoCode:
      return 'Short Form';
  }
}

LocationCountryVariant locationCountryVariantFromJson(String? s) {
  if (s == LocationCountryVariant.isoCode.name) {
    return LocationCountryVariant.isoCode;
  }
  return LocationCountryVariant.fullName;
}

/// For [LocationChipKind.region] only: full name vs derived / explicit short form.
enum LocationRegionVariant {
  fullName,
  shortForm,
  apStyle,
}

String locationRegionVariantLabel(LocationRegionVariant v) {
  switch (v) {
    case LocationRegionVariant.fullName:
      return 'Full State/Province Name';
    case LocationRegionVariant.shortForm:
      return 'Short Form';
    case LocationRegionVariant.apStyle:
      return 'AP Style';
  }
}

LocationRegionVariant locationRegionVariantFromJson(String? s) {
  if (s == LocationRegionVariant.shortForm.name) {
    return LocationRegionVariant.shortForm;
  }
  if (s == LocationRegionVariant.apStyle.name) {
    return LocationRegionVariant.apStyle;
  }
  return LocationRegionVariant.fullName;
}

class LocationChip {
  const LocationChip({
    required this.id,
    required this.kind,
    this.literal = '',
    this.caps = false,
    this.enabled = true,
    this.countryVariant = LocationCountryVariant.fullName,
    this.regionVariant = LocationRegionVariant.fullName,
  });

  final String id;
  final LocationChipKind kind;

  /// When [kind] is [LocationChipKind.literal], text inserted as-is (e.g. `", "`, `" - "`).
  final String literal;

  /// Per-chip ALL CAPS toggle. Applies only to geo chips during rendering; the
  /// legacy global [LocationLineOptions.uppercase] still forces caps on every
  /// chip for backward compatibility with old templates.
  final bool caps;

  /// Whether this geo chip contributes to the rendered location line. When
  /// `false`, both the chip and the literal that immediately follows it are
  /// skipped during rendering, but the chip is preserved in [LocationLineOptions.chips]
  /// so its position / variant / caps state is remembered. Always `true` for
  /// [LocationChipKind.literal] chips (toggling is a geo-chip-only concept).
  final bool enabled;

  /// When [kind] is [LocationChipKind.country]: use [GameInfo.country] vs [GameInfo.countryCode].
  final LocationCountryVariant countryVariant;

  /// When [kind] is [LocationChipKind.region]: full name vs short ([GameInfo.resolvedRegionShort]).
  final LocationRegionVariant regionVariant;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        if (kind == LocationChipKind.literal) 'literal': literal,
        if (caps) 'caps': true,
        if (!enabled && kind != LocationChipKind.literal) 'enabled': false,
        if (kind == LocationChipKind.country &&
            countryVariant != LocationCountryVariant.fullName)
          'countryVariant': countryVariant.name,
        if (kind == LocationChipKind.region &&
            regionVariant != LocationRegionVariant.fullName)
          'regionVariant': regionVariant.name,
      };

  factory LocationChip.fromJson(Map<String, dynamic> j) {
    LocationChipKind kind = LocationChipKind.literal;
    final raw = j['kind']?.toString();
    for (final e in LocationChipKind.values) {
      if (e.name == raw) {
        kind = e;
        break;
      }
    }
    return LocationChip(
      id: j['id'] as String? ?? 'chip',
      kind: kind,
      literal: kind == LocationChipKind.literal
          ? (j['literal'] as String? ?? '')
          : '',
      caps: j['caps'] as bool? ?? false,
      enabled: kind == LocationChipKind.literal
          ? true
          : (j['enabled'] as bool? ?? true),
      countryVariant: kind == LocationChipKind.country
          ? locationCountryVariantFromJson(j['countryVariant']?.toString())
          : LocationCountryVariant.fullName,
      regionVariant: kind == LocationChipKind.region
          ? locationRegionVariantFromJson(j['regionVariant']?.toString())
          : LocationRegionVariant.fullName,
    );
  }

  LocationChip copyWith({
    String? id,
    LocationChipKind? kind,
    String? literal,
    bool? caps,
    bool? enabled,
    LocationCountryVariant? countryVariant,
    LocationRegionVariant? regionVariant,
  }) =>
      LocationChip(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        literal: literal ?? this.literal,
        caps: caps ?? this.caps,
        enabled: enabled ?? this.enabled,
        countryVariant: countryVariant ?? this.countryVariant,
        regionVariant: regionVariant ?? this.regionVariant,
      );
}

/// Ordered draggable chips for the static location line + ALL CAPS flag.
class LocationLineOptions {
  const LocationLineOptions({
    required this.uppercase,
    required this.chips,
    this.autoSpacing = true,
  });

  final bool uppercase;
  final List<LocationChip> chips;
  final bool autoSpacing;

  LocationLineOptions copyWith({
    bool? uppercase,
    List<LocationChip>? chips,
    bool? autoSpacing,
  }) =>
      LocationLineOptions(
        uppercase: uppercase ?? this.uppercase,
        chips: chips ?? List<LocationChip>.from(this.chips),
        autoSpacing: autoSpacing ?? this.autoSpacing,
      );

  /// Deep copy for per–geo-chip templates (duplicate Geographical segments).
  LocationLineOptions clone() => LocationLineOptions(
        uppercase: uppercase,
        chips: chips.map((c) => c.copyWith()).toList(),
        autoSpacing: autoSpacing,
      );

  Map<String, dynamic> toJson() => {
        'uppercase': uppercase,
        'locationChips': chips.map((e) => e.toJson()).toList(),
        if (!autoSpacing) 'autoSpacing': false,
      };

  factory LocationLineOptions.fromJson(Map<String, dynamic> j) {
    if (j['locationChips'] is List) {
      final raw = j['locationChips'] as List<dynamic>;
      final parsed = raw
          .map(
              (e) => LocationChip.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final uppercase = j['uppercase'] as bool? ?? false;
      if (parsed.isEmpty) {
        return LocationLineOptions(
          uppercase: uppercase,
          chips: LocationLineOptions.imagnDefault().chips,
          autoSpacing: j['autoSpacing'] as bool? ?? true,
        );
      }
      // Migrate legacy global uppercase → per-chip caps, so once migrated the
      // per-chip toggles remain the source of truth.
      final anyChipCaps = parsed.any((c) => c.caps);
      if (uppercase && !anyChipCaps) {
        final migrated = parsed
            .map((c) =>
                c.kind == LocationChipKind.literal ? c : c.copyWith(caps: true))
            .toList();
        return LocationLineOptions(
          uppercase: false,
          chips: migrated,
          autoSpacing: j['autoSpacing'] as bool? ?? true,
        );
      }
      // Legacy: uppercase + per-chip caps meant whole-line upper still ran and
      // ignored Aa toggles; per-chip caps are the only source of truth now.
      if (uppercase && anyChipCaps) {
        return LocationLineOptions(
          uppercase: false,
          chips: parsed,
          autoSpacing: j['autoSpacing'] as bool? ?? true,
        );
      }
      return LocationLineOptions(
        uppercase: uppercase,
        chips: parsed,
        autoSpacing: j['autoSpacing'] as bool? ?? true,
      );
    }
    return LocationLineOptions._fromLegacyFlatJson(j);
  }

  factory LocationLineOptions._fromLegacyFlatJson(Map<String, dynamic> j) {
    final includeCity = j['includeCity'] as bool? ?? true;
    final includeRegion = j['includeRegion'] as bool? ?? true;
    final includeCountry = j['includeCountry'] as bool? ?? false;
    final uppercase = j['uppercase'] as bool? ?? false;
    final j1 = j['joinBetweenFirstSecond'] as String? ?? ', ';
    final j2 = j['joinBetweenSecondThird'] as String? ?? ', ';
    final geo = <LocationChipKind>[];
    if (includeCity) geo.add(LocationChipKind.city);
    if (includeRegion) geo.add(LocationChipKind.region);
    if (includeCountry) geo.add(LocationChipKind.country);
    final chips = <LocationChip>[];
    var n = 0;
    String nid(String p) => '${p}_${n++}';
    for (var i = 0; i < geo.length; i++) {
      if (i > 0) {
        final sep = i == 1 ? j1 : j2;
        chips.add(LocationChip(
            id: nid('lit'), kind: LocationChipKind.literal, literal: sep));
      }
      chips.add(LocationChip(id: nid(geo[i].name), kind: geo[i], literal: ''));
    }
    if (chips.isEmpty) {
      chips.add(LocationChip(
          id: nid('city'), kind: LocationChipKind.city, literal: ''));
    }
    return LocationLineOptions(
      uppercase: uppercase,
      chips: chips,
      autoSpacing: j['autoSpacing'] as bool? ?? true,
    );
  }

  /// Preset strips matching former [LocationFormat] defaults.
  factory LocationLineOptions.fromLegacyFormat(LocationFormat f) {
    switch (f) {
      case LocationFormat.city_region:
        return LocationLineOptions.apDefault();
      case LocationFormat.city_region_country:
        return LocationLineOptions.imagnDefault();
      case LocationFormat.city_state_country:
        return LocationLineOptions.gettyDefault();
    }
  }

  static LocationLineOptions gettyDefault() => LocationLineOptions(
        uppercase: false,
        chips: [
          const LocationChip(
              id: 'g_city', kind: LocationChipKind.city, caps: true),
          const LocationChip(
              id: 'g_lit1', kind: LocationChipKind.literal, literal: ', '),
          const LocationChip(
              id: 'g_reg', kind: LocationChipKind.region, caps: true),
        ],
      );

  static LocationLineOptions imagnDefault() => LocationLineOptions(
        uppercase: false,
        chips: [
          const LocationChip(id: 'i_city', kind: LocationChipKind.city),
          const LocationChip(
              id: 'i_lit1', kind: LocationChipKind.literal, literal: ', '),
          const LocationChip(id: 'i_reg', kind: LocationChipKind.region),
          const LocationChip(
              id: 'i_lit2', kind: LocationChipKind.literal, literal: ', '),
          const LocationChip(id: 'i_ctr', kind: LocationChipKind.country),
        ],
      );

  static LocationLineOptions apDefault() => LocationLineOptions(
        uppercase: false,
        chips: [
          const LocationChip(id: 'a_city', kind: LocationChipKind.city),
          const LocationChip(
              id: 'a_lit1', kind: LocationChipKind.literal, literal: ', '),
          const LocationChip(
            id: 'a_reg',
            kind: LocationChipKind.region,
            regionVariant: LocationRegionVariant.apStyle,
          ),
        ],
      );
}

/// Jersey / roster number style in the dynamic caption sample.
enum NumberFormatStyle { hash, parens }

/// Built-in game-identifier phrases per league (see [defaultGameIdentifierText]).
const Set<String> kKnownGameIdentifierDefaults = {
  'in their MLB game',
  'in their NHL game',
  'in their NBA game',
  'in their MLS match',
};

/// Default [CaptionTemplate.gameIdentifierText] for the active sport.
String defaultGameIdentifierText(String? sport) {
  switch ((sport ?? 'baseball').toLowerCase()) {
    case 'baseball':
    case 'mlb':
      return 'in their MLB game';
    case 'hockey':
    case 'nhl':
      return 'in their NHL game';
    case 'basketball':
    case 'nba':
      return 'in their NBA game';
    case 'soccer':
    case 'mls':
      return 'in their MLS match';
    default:
      return '';
  }
}

/// Whether the club appears before or after the player in the dynamic caption
/// sentence (preview + default caption slot when no override is supplied).
enum CaptionTeamOrder {
  /// `Team position Name …` with number from [NumberFormatStyle].
  teamBefore,
  /// `Name … of Team position` with number from [NumberFormatStyle].
  teamAfter,
}

/// How the closing credit is phrased.
enum CreditFormat { photo_by, mandatory_credit }

/// Which IPTC field drives the byline organization segment.
enum BylineOrganizationSource { credit, copyright }

enum BylineFieldKind {
  name,
  credit,
  copyright,
  custom,
  /// User-typed photographer name override (shown in credit line like [name]).
  customCreator,
  /// User-typed agency/credit override (shown in credit line like [credit]).
  customCredit,
}

class BylineOptions {
  const BylineOptions({
    required this.prefix,
    required this.between,
    required this.suffix,
    required this.organizationSource,
    this.nameCaps = false,
    this.organizationCaps = false,
    this.creditCaps = false,
    this.copyrightCaps = false,
    this.fieldOrder = const [BylineFieldKind.name, BylineFieldKind.credit],
    this.customTexts = const [],
    this.disabledKinds = const <BylineFieldKind>{},
    this.customCreatorText = '',
    this.customCreditText = '',
    this.autoSpacing = true,
  });

  final String prefix;
  final String between;
  final String suffix;
  final BylineOrganizationSource organizationSource;
  final bool nameCaps;
  final bool organizationCaps;
  final bool creditCaps;
  final bool copyrightCaps;
  final List<BylineFieldKind> fieldOrder;
  /// One entry per `BylineFieldKind.custom` occurrence in [fieldOrder], in order.
  final List<String> customTexts;

  /// Kinds present in [fieldOrder] that the user has toggled "off" — they
  /// keep their position so re-enabling drops them right back in place,
  /// but the renderer skips them. Only meaningful for non-custom kinds
  /// (custom occurrences are removed entirely instead).
  final Set<BylineFieldKind> disabledKinds;

  /// Typed override for [BylineFieldKind.customCreator] (photographer name).
  final String customCreatorText;

  /// Typed override for [BylineFieldKind.customCredit] (agency / credit).
  final String customCreditText;
  final bool autoSpacing;

  BylineOptions copyWith({
    String? prefix,
    String? between,
    String? suffix,
    BylineOrganizationSource? organizationSource,
    bool? nameCaps,
    bool? organizationCaps,
    bool? creditCaps,
    bool? copyrightCaps,
    List<BylineFieldKind>? fieldOrder,
    List<String>? customTexts,
    Set<BylineFieldKind>? disabledKinds,
    String? customCreatorText,
    String? customCreditText,
    bool? autoSpacing,
  }) =>
      BylineOptions(
        prefix: prefix ?? this.prefix,
        between: between ?? this.between,
        suffix: suffix ?? this.suffix,
        organizationSource: organizationSource ?? this.organizationSource,
        nameCaps: nameCaps ?? this.nameCaps,
        organizationCaps: organizationCaps ?? this.organizationCaps,
        creditCaps: creditCaps ?? this.creditCaps,
        copyrightCaps: copyrightCaps ?? this.copyrightCaps,
        fieldOrder: fieldOrder ?? List<BylineFieldKind>.from(this.fieldOrder),
        customTexts: customTexts ?? List<String>.from(this.customTexts),
        disabledKinds:
            disabledKinds ?? Set<BylineFieldKind>.from(this.disabledKinds),
        customCreatorText: customCreatorText ?? this.customCreatorText,
        customCreditText: customCreditText ?? this.customCreditText,
        autoSpacing: autoSpacing ?? this.autoSpacing,
      );

  Map<String, dynamic> toJson() => {
        'prefix': prefix,
        'between': between,
        'suffix': suffix,
        'organizationSource': organizationSource.name,
        if (nameCaps) 'nameCaps': true,
        if (organizationCaps) 'organizationCaps': true,
        if (creditCaps) 'creditCaps': true,
        if (copyrightCaps) 'copyrightCaps': true,
        'fieldOrder': fieldOrder.map((e) => e.name).toList(),
        if (customTexts.any((t) => t.trim().isNotEmpty))
          'customTexts': customTexts,
        if (disabledKinds.isNotEmpty)
          'disabledKinds': disabledKinds.map((e) => e.name).toList(),
        if (customCreatorText.isNotEmpty) 'customCreatorText': customCreatorText,
        if (customCreditText.isNotEmpty) 'customCreditText': customCreditText,
        if (!autoSpacing) 'autoSpacing': false,
      };

  factory BylineOptions.fromJson(Map<String, dynamic> j) {
    final sourceRaw = j['organizationSource']?.toString();
    final source = BylineOrganizationSource.values.firstWhere(
      (e) => e.name == sourceRaw,
      orElse: () => BylineOrganizationSource.credit,
    );
    List<BylineFieldKind> orderFromRaw(dynamic raw) {
      if (raw is List) {
        final out = <BylineFieldKind>[];
        for (final v in raw) {
          final s = v.toString();
          for (final k in BylineFieldKind.values) {
            if (k.name == s) out.add(k);
          }
        }
        if (out.isNotEmpty) return out;
      }
      return source == BylineOrganizationSource.copyright
          ? const [BylineFieldKind.name, BylineFieldKind.copyright]
          : const [BylineFieldKind.name, BylineFieldKind.credit];
    }

    List<String> customTextsFromRaw(dynamic raw, String legacyCustomText) {
      if (raw is List) return raw.map((e) => e.toString()).toList();
      // Migrate from old single customText field
      if (legacyCustomText.isNotEmpty) return [legacyCustomText];
      return [];
    }

    final fieldOrder = orderFromRaw(j['fieldOrder']);
    final legacyCustomText = j['customText'] as String? ?? '';
    final customTexts =
        customTextsFromRaw(j['customTexts'], legacyCustomText);

    Set<BylineFieldKind> disabledFromRaw(dynamic raw) {
      if (raw is List) {
        final out = <BylineFieldKind>{};
        for (final v in raw) {
          final s = v.toString();
          for (final k in BylineFieldKind.values) {
            if (k.name == s) out.add(k);
          }
        }
        return out;
      }
      return const <BylineFieldKind>{};
    }

    return BylineOptions(
      prefix: j['prefix'] as String? ?? '',
      between: j['between'] as String? ?? '/',
      suffix: j['suffix'] as String? ?? '',
      organizationSource: source,
      nameCaps: j['nameCaps'] as bool? ?? false,
      organizationCaps: j['organizationCaps'] as bool? ?? false,
      creditCaps:
          j['creditCaps'] as bool? ?? (j['organizationCaps'] as bool? ?? false),
      copyrightCaps: j['copyrightCaps'] as bool? ?? false,
      fieldOrder: fieldOrder,
      disabledKinds: disabledFromRaw(j['disabledKinds']),
      customTexts: customTexts,
      customCreatorText: j['customCreatorText'] as String? ?? '',
      customCreditText: j['customCreditText'] as String? ?? '',
      autoSpacing: j['autoSpacing'] as bool? ?? true,
    );
  }

  static BylineOptions getty() => const BylineOptions(
        prefix: '(Photo by ',
        between: '/',
        suffix: ')',
        organizationSource: BylineOrganizationSource.credit,
        fieldOrder: [
          BylineFieldKind.name,
          BylineFieldKind.credit,
          BylineFieldKind.custom,
        ],
        customTexts: [''],
      );

  static BylineOptions imagn() => const BylineOptions(
        prefix: 'Mandatory Credit: ',
        between: '-',
        suffix: '',
        organizationSource: BylineOrganizationSource.credit,
      );

  static BylineOptions ap() => const BylineOptions(
        prefix: '(',
        between: '/',
        suffix: ')',
        organizationSource: BylineOrganizationSource.credit,
      );

  static BylineOptions fromLegacyFormat(CreditFormat format) {
    switch (format) {
      case CreditFormat.photo_by:
        return const BylineOptions(
          prefix: '(Photo by ',
          between: '/',
          suffix: ')',
          organizationSource: BylineOrganizationSource.credit,
        );
      case CreditFormat.mandatory_credit:
        return const BylineOptions(
          prefix: 'Mandatory Credit: ',
          between: '-',
          suffix: '',
          organizationSource: BylineOrganizationSource.credit,
        );
    }
  }
}

/// Ordered segments: static frame + dynamic caption slot + static tail.
///
/// [customText] is optional freeform narrative (e.g. game situation) sourced
/// from [BylineFieldKind.custom] entries; when present in [segmentOrder],
/// [CaptionFormulaRenderer] renders those customs in-place and omits them
/// from the [credit] segment so they are not duplicated.
enum CaptionSegment {
  location,
  date,
  caption,
  customText,
  /// Join word before venue etc.: ` at `, ` in `, ` on ` (editable per slot).
  separator,
  /// Any literal text between snippets — punctuation, dashes, spaces, etc.
  /// Displayed as "Custom" in the UI; editable per slot.
  punctuation,
  venue,
  credit,
}

/// Sentinel to distinguish "not passed" from "explicitly null" in copyWith.
const Object _unset = Object();

class CaptionTemplate {
  const CaptionTemplate({
    required this.id,
    required this.name,
    required this.wireStyle,
    required this.dateFormat,
    this.dateExpression = '',
    this.dateFormula,
    this.dateFormulaSource = DateFormulaSource.photo,
    required this.locationOptions,
    required this.numberFormat,
    required this.captionTeamOrder,
    this.includePlayerPosition = true,
    this.americanEnglish = true,
    this.removeDiacritics = true,
    this.showPersonalityField = true,
    this.showKeywordsField = false,
    required this.separator,
    required this.creditFormat,
    required this.bylineOptions,
    required this.segmentOrder,
    this.gameIdentifierText = '',
    this.captionPrefix = '',
    this.captionSuffix = ' ',
    this.gameIdentifierPrefix = '',
    this.gameIdentifierSuffix = ' ',
    this.customSeparators,
    this.separatorSnippets,
    this.punctuationSnippets,
    this.venuePrefix = '',
    this.venueSuffix = '',
    this.locationOptionsByOccurrence,
    this.dateFormulasByOccurrence,
  });

  final String id;
  final String name;
  final WireStyle wireStyle;

  /// ICU-style pattern for [intl.DateFormat], e.g. `MMMM d, yyyy`, `MMM d, yyyy`.
  /// Used when [dateExpression] is empty (legacy) and as the default game pattern in the UI.
  final String dateFormat;

  /// Optional template mixing literals and `{{game:…}}` / `{{iptc:…}}` variables (IPTC from file metadata).
  /// When empty, [dateFormat] is applied to the game date only.
  final String dateExpression;

  /// Structured date formula (built by [DateFormulaEditor]). When non-null it
  /// takes precedence over [dateExpression] during rendering.
  final DateFormula? dateFormula;

  /// Legacy JSON field; structured [dateFormula] rendering no longer uses this
  /// toggle. Dates resolve from photo EXIF when available, else [GameInfo.gameDate].
  final DateFormulaSource dateFormulaSource;

  /// Which location fields appear and whether the line is uppercased.
  final LocationLineOptions locationOptions;
  final NumberFormatStyle numberFormat;

  /// Club vs player order in the dynamic caption (player) segment.
  final CaptionTeamOrder captionTeamOrder;

  /// Whether the player's position label (e.g. `forward`, `guard`) appears in
  /// the dynamic caption segment.
  final bool includePlayerPosition;

  /// Controls US vs international spelling for expanded position labels
  /// (e.g. `center` vs `centre`) when AP / Imagn write positions out.
  final bool americanEnglish;

  /// When true, Latin accents in generated captions are folded to ASCII
  /// (player names, opponent names, etc.).
  final bool removeDiacritics;

  /// Optional Personality field beside the main caption (per caption style).
  final bool showPersonalityField;

  /// Optional Keywords field beside the main caption (per caption style).
  final bool showKeywordsField;

  /// Primary joiner used in [WireStyle.custom] between segments.
  final String separator;
  final CreditFormat creditFormat;
  final BylineOptions bylineOptions;
  final List<CaptionSegment> segmentOrder;

  /// Free-form narrative for the [CaptionSegment.customText] slot (e.g. game
  /// situation text). Stored separately from [BylineOptions.customTexts] so
  /// the caption body "Game identifier" and the credit-line "Custom text"
  /// fields are independent of each other.
  final String gameIdentifierText;
  final String captionPrefix;
  final String captionSuffix;
  final String gameIdentifierPrefix;
  final String gameIdentifierSuffix;

  /// Text between consecutive [segmentOrder] entries. When set, length must be
  /// [segmentOrder.length - 1]. When null or wrong length, rendering falls
  /// back to [CaptionFormulaRenderer.defaultCustomGaps] for presets (Getty /
  /// Imagn / AP) or [separator] between each pair for [WireStyle.custom].
  ///
  /// When [segmentOrder] includes [CaptionSegment.separator] or
  /// [CaptionSegment.punctuation], gaps are usually empty strings and these
  /// snippets carry the join / punctuation text instead.
  final List<String>? customSeparators;

  /// One string per [CaptionSegment.separator] in [segmentOrder] (left-to-right),
  /// e.g. ` at `, ` in `, ` on `.
  final List<String>? separatorSnippets;

  /// One string per [CaptionSegment.punctuation] ("Custom" in UI) in [segmentOrder],
  /// e.g. ` - `, `: `, `. `. Any literal text is valid.
  final List<String>? punctuationSnippets;

  final String venuePrefix;
  final String venueSuffix;

  /// One [LocationLineOptions] per [CaptionSegment.location] in [segmentOrder]
  /// (left-to-right). When null, every location segment uses [locationOptions].
  final List<LocationLineOptions>? locationOptionsByOccurrence;

  /// One [DateFormula] per [CaptionSegment.date] in [segmentOrder] (left-to-right).
  /// When null, every date segment uses [dateFormula].
  final List<DateFormula>? dateFormulasByOccurrence;

  /// Matches [CaptionTemplate.getty] / [CaptionTemplate.gettyInternational]
  /// snippet layout (Custom literal chips + optional narrative + separator before venue).
  static const List<CaptionSegment> defaultSegmentOrder = [
    CaptionSegment.location,
    CaptionSegment.punctuation,
    CaptionSegment.date,
    CaptionSegment.punctuation,
    CaptionSegment.caption,
    CaptionSegment.punctuation,
    CaptionSegment.customText,
    CaptionSegment.separator,
    CaptionSegment.venue,
    CaptionSegment.punctuation,
    CaptionSegment.credit,
  ];

  factory CaptionTemplate.getty() => CaptionTemplate(
        id: 'preset_getty',
        name: 'Getty USA',
        wireStyle: WireStyle.getty,
        dateFormat: 'MMMM d, yyyy',
        dateExpression: '',
        locationOptions: LocationLineOptions.fromLegacyFormat(
            LocationFormat.city_state_country),
        numberFormat: NumberFormatStyle.hash,
        captionTeamOrder: CaptionTeamOrder.teamAfter,
        includePlayerPosition: true,
        americanEnglish: true,
        removeDiacritics: true,
        separator: ' - ',
        creditFormat: CreditFormat.photo_by,
        bylineOptions: BylineOptions.getty(),
        segmentOrder: const [
          CaptionSegment.location,
          CaptionSegment.punctuation,
          CaptionSegment.date,
          CaptionSegment.punctuation,
          CaptionSegment.caption,
          CaptionSegment.punctuation,
          CaptionSegment.customText,
          CaptionSegment.separator,
          CaptionSegment.venue,
          CaptionSegment.punctuation,
          CaptionSegment.credit,
        ],
        customSeparators: const [
          '', '', '', '', '', '', '', '', '', '',
        ],
        separatorSnippets: const [' at '],
        punctuationSnippets: const [' - ', ': ', ' ', '. '],
        locationOptionsByOccurrence: null,
        dateFormulasByOccurrence: null,
      );

  factory CaptionTemplate.imagn() => CaptionTemplate(
        id: 'preset_imagn',
        name: 'Imagn',
        wireStyle: WireStyle.imagn,
        dateFormat: 'MMM d, yyyy',
        dateExpression: '',
        locationOptions: LocationLineOptions.fromLegacyFormat(
            LocationFormat.city_region_country),
        numberFormat: NumberFormatStyle.parens,
        captionTeamOrder: CaptionTeamOrder.teamBefore,
        includePlayerPosition: true,
        americanEnglish: true,
        removeDiacritics: true,
        separator: '; ',
        creditFormat: CreditFormat.mandatory_credit,
        bylineOptions: BylineOptions.imagn(),
        segmentOrder: const [
          CaptionSegment.date,
          CaptionSegment.punctuation,
          CaptionSegment.location,
          CaptionSegment.punctuation,
          CaptionSegment.caption,
          CaptionSegment.separator,
          CaptionSegment.venue,
          CaptionSegment.punctuation,
          CaptionSegment.credit,
        ],
        customSeparators: const ['', '', '', '', '', '', '', ''],
        separatorSnippets: const [' at '],
        punctuationSnippets: const ['; ', '; ', '. '],
        locationOptionsByOccurrence: null,
        dateFormulasByOccurrence: null,
      );

  /// Same caption structure and Custom literal chips as [CaptionTemplate.getty]
  /// ([WireStyle.getty] / Getty USA), with [LocationFormat.city_region_country]
  /// so the default location line is City · Region · Country.
  factory CaptionTemplate.gettyInternational() => CaptionTemplate(
        id: 'preset_getty_international',
        name: 'Getty International',
        wireStyle: WireStyle.gettyInternational,
        dateFormat: 'MMMM d, yyyy',
        dateExpression: '',
        locationOptions: LocationLineOptions.fromLegacyFormat(
            LocationFormat.city_region_country),
        numberFormat: NumberFormatStyle.hash,
        captionTeamOrder: CaptionTeamOrder.teamAfter,
        includePlayerPosition: true,
        americanEnglish: true,
        removeDiacritics: true,
        separator: ' - ',
        creditFormat: CreditFormat.photo_by,
        bylineOptions: BylineOptions.getty(),
        segmentOrder: const [
          CaptionSegment.location,
          CaptionSegment.punctuation,
          CaptionSegment.date,
          CaptionSegment.punctuation,
          CaptionSegment.caption,
          CaptionSegment.punctuation,
          CaptionSegment.customText,
          CaptionSegment.separator,
          CaptionSegment.venue,
          CaptionSegment.punctuation,
          CaptionSegment.credit,
        ],
        customSeparators: const [
          '', '', '', '', '', '', '', '', '', '',
        ],
        separatorSnippets: const [' at '],
        punctuationSnippets: const [' - ', ': ', ' ', '. '],
        locationOptionsByOccurrence: null,
        dateFormulasByOccurrence: null,
      );

  factory CaptionTemplate.ap() => CaptionTemplate(
        id: 'preset_ap',
        name: 'Associated Press',
        wireStyle: WireStyle.ap,
        dateFormat: 'MMM d, yyyy',
        dateExpression: '',
        locationOptions:
            LocationLineOptions.fromLegacyFormat(LocationFormat.city_region),
        numberFormat: NumberFormatStyle.parens,
        captionTeamOrder: CaptionTeamOrder.teamBefore,
        includePlayerPosition: true,
        americanEnglish: true,
        removeDiacritics: true,
        separator: ' — ',
        creditFormat: CreditFormat.photo_by,
        bylineOptions: BylineOptions.ap(),
        segmentOrder: const [
          CaptionSegment.location,
          CaptionSegment.punctuation,
          CaptionSegment.date,
          CaptionSegment.punctuation,
          CaptionSegment.caption,
          CaptionSegment.separator,
          CaptionSegment.venue,
          CaptionSegment.punctuation,
          CaptionSegment.credit,
        ],
        customSeparators: const ['', '', '', '', '', '', '', ''],
        separatorSnippets: const [' at '],
        punctuationSnippets: const [' (', ') — ', '. '],
        locationOptionsByOccurrence: null,
        dateFormulasByOccurrence: null,
      );

  factory CaptionTemplate.custom({
    String id = 'custom',
    String name = 'Custom',
    String dateFormat = 'MMMM d, yyyy',
    String dateExpression = '',
    LocationLineOptions? locationOptions,
    NumberFormatStyle numberFormat = NumberFormatStyle.parens,
    CaptionTeamOrder captionTeamOrder = CaptionTeamOrder.teamBefore,
    bool includePlayerPosition = true,
    bool americanEnglish = true,
    bool removeDiacritics = true,
    bool showPersonalityField = true,
    bool showKeywordsField = false,
    String separator = '; ',
    CreditFormat creditFormat = CreditFormat.mandatory_credit,
    BylineOptions? bylineOptions,
    List<CaptionSegment>? segmentOrder,
    List<String>? customSeparators,
    List<String>? separatorSnippets,
    List<String>? punctuationSnippets,
    String captionPrefix = '',
    String captionSuffix = ' ',
    String gameIdentifierText = '',
    String gameIdentifierPrefix = '',
    String gameIdentifierSuffix = ' ',
    String venuePrefix = '',
    String venueSuffix = '',
    DateFormula? dateFormula,
    List<DateFormula>? dateFormulasByOccurrence,
    List<LocationLineOptions>? locationOptionsByOccurrence,
  }) {
    final resolvedOrder =
        segmentOrder ?? List<CaptionSegment>.from(defaultSegmentOrder);
    final useFactorySnippetDefaults = segmentOrder == null;
    final gapCount = resolvedOrder.length - 1;
    final resolvedCustomSeparators = customSeparators ??
        (useFactorySnippetDefaults && gapCount > 0
            ? List<String>.filled(gapCount, '')
            : null);
    final resolvedSepSnippets = separatorSnippets ??
        (useFactorySnippetDefaults ? <String>[separator] : null);
    final resolvedPunSnippets = punctuationSnippets ??
        (useFactorySnippetDefaults
            ? <String>[separator, separator, separator, separator]
            : null);
    return CaptionTemplate(
      id: id,
      name: name,
      wireStyle: WireStyle.custom,
      dateFormat: dateFormat,
      dateExpression: dateExpression,
      dateFormula: dateFormula,
      locationOptions: locationOptions ??
          LocationLineOptions.fromLegacyFormat(
              LocationFormat.city_region_country),
      numberFormat: numberFormat,
      captionTeamOrder: captionTeamOrder,
      includePlayerPosition: includePlayerPosition,
      americanEnglish: americanEnglish,
      removeDiacritics: removeDiacritics,
      showPersonalityField: showPersonalityField,
      showKeywordsField: showKeywordsField,
      separator: separator,
      creditFormat: creditFormat,
      bylineOptions:
          bylineOptions ?? BylineOptions.fromLegacyFormat(creditFormat),
      segmentOrder: resolvedOrder,
      captionPrefix: captionPrefix,
      captionSuffix: captionSuffix,
      gameIdentifierText: gameIdentifierText,
      gameIdentifierPrefix: gameIdentifierPrefix,
      gameIdentifierSuffix: gameIdentifierSuffix,
      customSeparators: resolvedCustomSeparators,
      separatorSnippets: resolvedSepSnippets,
      punctuationSnippets: resolvedPunSnippets,
      venuePrefix: venuePrefix,
      venueSuffix: venueSuffix,
      locationOptionsByOccurrence: locationOptionsByOccurrence,
      dateFormulasByOccurrence: dateFormulasByOccurrence,
    ).normalizePerOccurrenceLists();
  }

  CaptionTemplate copyWith({
    String? id,
    String? name,
    WireStyle? wireStyle,
    String? dateFormat,
    String? dateExpression,
    Object? dateFormula = _unset,
    DateFormulaSource? dateFormulaSource,
    LocationLineOptions? locationOptions,
    NumberFormatStyle? numberFormat,
    CaptionTeamOrder? captionTeamOrder,
    bool? includePlayerPosition,
    bool? americanEnglish,
    bool? removeDiacritics,
    bool? showPersonalityField,
    bool? showKeywordsField,
    String? separator,
    CreditFormat? creditFormat,
    BylineOptions? bylineOptions,
    List<CaptionSegment>? segmentOrder,
    String? gameIdentifierText,
    String? captionPrefix,
    String? captionSuffix,
    String? gameIdentifierPrefix,
    String? gameIdentifierSuffix,
    List<String>? customSeparators,
    Object? separatorSnippets = _unset,
    Object? punctuationSnippets = _unset,
    String? venuePrefix,
    String? venueSuffix,
    Object? locationOptionsByOccurrence = _unset,
    Object? dateFormulasByOccurrence = _unset,
  }) =>
      CaptionTemplate(
        id: id ?? this.id,
        name: name ?? this.name,
        wireStyle: wireStyle ?? this.wireStyle,
        dateFormat: dateFormat ?? this.dateFormat,
        dateExpression: dateExpression ?? this.dateExpression,
        dateFormula: identical(dateFormula, _unset)
            ? this.dateFormula
            : dateFormula as DateFormula?,
        dateFormulaSource: dateFormulaSource ?? this.dateFormulaSource,
        locationOptions: locationOptions ?? this.locationOptions,
        numberFormat: numberFormat ?? this.numberFormat,
        captionTeamOrder: captionTeamOrder ?? this.captionTeamOrder,
        includePlayerPosition: includePlayerPosition ?? this.includePlayerPosition,
        americanEnglish: americanEnglish ?? this.americanEnglish,
        removeDiacritics: removeDiacritics ?? this.removeDiacritics,
        showPersonalityField:
            showPersonalityField ?? this.showPersonalityField,
        showKeywordsField: showKeywordsField ?? this.showKeywordsField,
        separator: separator ?? this.separator,
        creditFormat: creditFormat ?? this.creditFormat,
        bylineOptions: bylineOptions ?? this.bylineOptions,
        segmentOrder:
            segmentOrder ?? List<CaptionSegment>.from(this.segmentOrder),
        gameIdentifierText: gameIdentifierText ?? this.gameIdentifierText,
        captionPrefix: captionPrefix ?? this.captionPrefix,
        captionSuffix: captionSuffix ?? this.captionSuffix,
        gameIdentifierPrefix: gameIdentifierPrefix ?? this.gameIdentifierPrefix,
        gameIdentifierSuffix: gameIdentifierSuffix ?? this.gameIdentifierSuffix,
        customSeparators: customSeparators ?? this.customSeparators,
        separatorSnippets: identical(separatorSnippets, _unset)
            ? this.separatorSnippets
            : separatorSnippets as List<String>?,
        punctuationSnippets: identical(punctuationSnippets, _unset)
            ? this.punctuationSnippets
            : punctuationSnippets as List<String>?,
        venuePrefix: venuePrefix ?? this.venuePrefix,
        venueSuffix: venueSuffix ?? this.venueSuffix,
        locationOptionsByOccurrence: identical(locationOptionsByOccurrence, _unset)
            ? this.locationOptionsByOccurrence
            : locationOptionsByOccurrence as List<LocationLineOptions>?,
        dateFormulasByOccurrence: identical(dateFormulasByOccurrence, _unset)
            ? this.dateFormulasByOccurrence
            : dateFormulasByOccurrence as List<DateFormula>?,
      );

  /// Ensures [locationOptionsByOccurrence] / [dateFormulasByOccurrence] have one
  /// entry per [CaptionSegment.location] / [CaptionSegment.date] when duplicates
  /// exist. Otherwise the renderer falls back to [locationOptions] / [dateFormula]
  /// for every occurrence and in-place editor edits are shared across chips.
  CaptionTemplate normalizePerOccurrenceLists() {
    final locCount =
        segmentOrder.where((s) => s == CaptionSegment.location).length;
    final dateCount = segmentOrder.where((s) => s == CaptionSegment.date).length;

    var r = this;

    if (locCount > 1) {
      final by = r.locationOptionsByOccurrence;
      if (by == null || by.length < locCount) {
        final list = <LocationLineOptions>[];
        for (var i = 0; i < locCount; i++) {
          if (by != null && i < by.length) {
            list.add(by[i]);
          } else if (list.isEmpty) {
            list.add(r.locationOptions);
          } else {
            list.add(list.last.clone());
          }
        }
        r = r.copyWith(
          locationOptions: list[0],
          locationOptionsByOccurrence: list,
        );
      }
    }

    if (dateCount > 1) {
      final by = r.dateFormulasByOccurrence;
      if (by == null || by.length < dateCount) {
        final seed = r.dateFormula ??
            (by != null && by.isNotEmpty ? by.first : null);
        if (seed != null) {
          final list = <DateFormula>[];
          for (var i = 0; i < dateCount; i++) {
            if (by != null && i < by.length) {
              list.add(by[i]);
            } else if (list.isEmpty) {
              list.add(seed);
            } else {
              list.add(list.last.clone());
            }
          }
          r = r.copyWith(
            dateFormula: list[0],
            dateFormulasByOccurrence: list,
          );
        }
      }
    }

    final sepCount =
        r.segmentOrder.where((s) => s == CaptionSegment.separator).length;
    final punCount =
        r.segmentOrder.where((s) => s == CaptionSegment.punctuation).length;

    String defaultSeparatorPad() {
      if (r.wireStyle == WireStyle.getty ||
          r.wireStyle == WireStyle.gettyInternational) {
        return ' at ';
      }
      if (r.wireStyle == WireStyle.custom) {
        return r.separator;
      }
      return ' ';
    }

    String defaultPunctuationPad() {
      if (r.wireStyle == WireStyle.custom) {
        return r.separator;
      }
      return ' ';
    }

    if (sepCount > 0) {
      final by = r.separatorSnippets;
      if (by == null || by.length != sepCount) {
        final list = <String>[];
        for (var i = 0; i < sepCount; i++) {
          if (by != null && i < by.length) {
            list.add(by[i]);
          } else {
            list.add(defaultSeparatorPad());
          }
        }
        r = r.copyWith(separatorSnippets: list);
      }
    } else if (r.separatorSnippets != null) {
      r = r.copyWith(separatorSnippets: null);
    }

    if (punCount > 0) {
      final by = r.punctuationSnippets;
      if (by == null || by.length != punCount) {
        final list = <String>[];
        for (var i = 0; i < punCount; i++) {
          if (by != null && i < by.length) {
            list.add(by[i]);
          } else {
            list.add(defaultPunctuationPad());
          }
        }
        r = r.copyWith(punctuationSnippets: list);
      }
    } else if (r.punctuationSnippets != null) {
      r = r.copyWith(punctuationSnippets: null);
    }

    return r;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'wireStyle': wireStyle.name,
        'dateFormat': dateFormat,
        if (dateExpression.isNotEmpty) 'dateExpression': dateExpression,
        if (dateFormula != null) 'dateFormula': dateFormula!.toJson(),
        'dateFormulaSource': dateFormulaSourceToString(dateFormulaSource),
        'locationOptions': locationOptions.toJson(),
        'numberFormat': numberFormat.name,
        'captionTeamOrder': captionTeamOrder.name,
        if (!includePlayerPosition) 'includePlayerPosition': false,
        if (!americanEnglish) 'americanEnglish': false,
        if (!removeDiacritics) 'removeDiacritics': false,
        'showPersonalityField': showPersonalityField,
        'showKeywordsField': showKeywordsField,
        'separator': separator,
        'creditFormat': creditFormat.name,
        'bylineOptions': bylineOptions.toJson(),
        'segmentOrder': segmentOrder.map((e) => e.name).toList(),
        if (gameIdentifierText.isNotEmpty) 'gameIdentifierText': gameIdentifierText,
        if (captionPrefix.isNotEmpty) 'captionPrefix': captionPrefix,
        if (captionSuffix != ' ') 'captionSuffix': captionSuffix,
        if (gameIdentifierPrefix.isNotEmpty)
          'gameIdentifierPrefix': gameIdentifierPrefix,
        if (gameIdentifierSuffix != ' ')
          'gameIdentifierSuffix': gameIdentifierSuffix,
        if (customSeparators != null) 'customSeparators': customSeparators,
        if (separatorSnippets != null) 'separatorSnippets': separatorSnippets,
        if (punctuationSnippets != null) 'punctuationSnippets': punctuationSnippets,
        if (venuePrefix.isNotEmpty) 'venuePrefix': venuePrefix,
        if (venueSuffix.isNotEmpty) 'venueSuffix': venueSuffix,
        if (locationOptionsByOccurrence != null)
          'locationOptionsByOccurrence': locationOptionsByOccurrence!
              .map((e) => e.toJson())
              .toList(),
        if (dateFormulasByOccurrence != null)
          'dateFormulasByOccurrence': dateFormulasByOccurrence!
              .map((e) => e.toJson())
              .toList(),
      };

  static CaptionTeamOrder _parseCaptionTeamOrder(Map<String, dynamic> json) {
    final co = json['captionTeamOrder']?.toString();
    if (co != null) {
      for (final e in CaptionTeamOrder.values) {
        if (e.name == co) return e;
      }
    }
    // Migrate from older `rosterCaptionStyle` (removed).
    final legacy = json['rosterCaptionStyle']?.toString();
    switch (legacy) {
      case 'gettyNameNumberOfTeam':
        return CaptionTeamOrder.teamAfter;
      case 'teamFirst':
      case 'apExtended':
        return CaptionTeamOrder.teamBefore;
    }
    final w = json['wireStyle']?.toString();
    if (w == 'getty') return CaptionTeamOrder.teamAfter;
    return CaptionTeamOrder.teamBefore;
  }

  static CaptionTemplate fromJson(Map<String, dynamic> json) {
    return CaptionTemplate(
      id: json['id'] as String? ?? 'custom',
      name: json['name'] as String? ?? 'Custom',
      wireStyle: WireStyle.values.firstWhere(
        (e) => e.name == json['wireStyle'],
        orElse: () => WireStyle.custom,
      ),
      dateFormat: json['dateFormat'] as String? ?? 'MMMM d, yyyy',
      dateExpression: json['dateExpression'] as String? ?? '',
      dateFormula: json['dateFormula'] is Map<String, dynamic>
          ? DateFormula.fromJson(
              Map<String, dynamic>.from(json['dateFormula'] as Map))
          : null,
      dateFormulaSource:
          dateFormulaSourceFromString(json['dateFormulaSource'] as String?),
      locationOptions: _parseLocationOptions(json),
      numberFormat: NumberFormatStyle.values.firstWhere(
        (e) => e.name == json['numberFormat'],
        orElse: () => NumberFormatStyle.parens,
      ),
      captionTeamOrder: _parseCaptionTeamOrder(json),
      includePlayerPosition: json['includePlayerPosition'] as bool? ?? true,
      americanEnglish: json['americanEnglish'] as bool? ?? true,
      removeDiacritics: json['removeDiacritics'] as bool? ?? true,
      showPersonalityField: json['showPersonalityField'] as bool? ?? true,
      showKeywordsField: json['showKeywordsField'] as bool? ?? false,
      separator: json['separator'] as String? ?? '; ',
      creditFormat: CreditFormat.values.firstWhere(
        (e) => e.name == json['creditFormat'],
        orElse: () => CreditFormat.mandatory_credit,
      ),
      bylineOptions: json['bylineOptions'] is Map<String, dynamic>
          ? BylineOptions.fromJson(
              Map<String, dynamic>.from(json['bylineOptions'] as Map))
          : BylineOptions.fromLegacyFormat(
              CreditFormat.values.firstWhere(
                (e) => e.name == json['creditFormat'],
                orElse: () => CreditFormat.mandatory_credit,
              ),
            ),
      segmentOrder: _parseSegmentOrder(json['segmentOrder']),
      gameIdentifierText: json['gameIdentifierText'] as String? ?? '',
      captionPrefix: json['captionPrefix'] as String? ?? '',
      captionSuffix: json['captionSuffix'] as String? ?? ' ',
      gameIdentifierPrefix: json['gameIdentifierPrefix'] as String? ?? '',
      gameIdentifierSuffix: json['gameIdentifierSuffix'] as String? ?? ' ',
      customSeparators: (json['customSeparators'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      separatorSnippets: (json['separatorSnippets'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      punctuationSnippets: (json['punctuationSnippets'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      venuePrefix: json['venuePrefix'] as String? ?? '',
      venueSuffix: json['venueSuffix'] as String? ?? '',
      locationOptionsByOccurrence:
          (json['locationOptionsByOccurrence'] as List<dynamic>?)
              ?.map((e) => LocationLineOptions.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList(),
      dateFormulasByOccurrence: (json['dateFormulasByOccurrence'] as List<dynamic>?)
          ?.map((e) => DateFormula.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
    ).normalizePerOccurrenceLists();
  }

  static LocationLineOptions _parseLocationOptions(Map<String, dynamic> json) {
    final o = json['locationOptions'];
    if (o is Map<String, dynamic>) {
      return LocationLineOptions.fromJson(o);
    }
    final legacy = json['locationFormat'] as String?;
    if (legacy != null) {
      final f = LocationFormat.values.firstWhere(
        (e) => e.name == legacy,
        orElse: () => LocationFormat.city_region_country,
      );
      return LocationLineOptions.fromLegacyFormat(f);
    }
    return LocationLineOptions.fromLegacyFormat(
        LocationFormat.city_region_country);
  }

  static List<CaptionSegment> _parseSegmentOrder(dynamic raw) {
    if (raw is! List) return List<CaptionSegment>.from(defaultSegmentOrder);
    CaptionSegment? parseSeg(String s) {
      if (s == 'game_date') return CaptionSegment.date;
      if (s == 'body') return CaptionSegment.caption;
      for (final v in CaptionSegment.values) {
        if (v.name == s) return v;
      }
      return null;
    }

    final out = <CaptionSegment>[];
    for (final e in raw) {
      final seg = parseSeg(e.toString());
      if (seg != null) out.add(seg);
    }
    if (out.isEmpty) {
      return List<CaptionSegment>.from(defaultSegmentOrder);
    }
    return out;
  }

  static CaptionTemplate? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = json.decode(raw) as Map<String, dynamic>;
      return CaptionTemplate.fromJson(m);
    } catch (_) {
      return null;
    }
  }

  String encode() => json.encode(toJson());

  /// Fills [gameIdentifierText] from [defaultGameIdentifierText] when empty, or
  /// when [replaceKnownDefaults] and the current text is another sport’s default.
  static CaptionTemplate withSportGameIdentifierDefault(
    CaptionTemplate template,
    String? sport, {
    bool replaceKnownDefaults = true,
  }) {
    final next = defaultGameIdentifierText(sport);
    if (next.isEmpty) return template;
    final current = template.gameIdentifierText.trim();
    final shouldSet = current.isEmpty ||
        (replaceKnownDefaults && kKnownGameIdentifierDefaults.contains(current));
    if (!shouldSet) return template;
    return template.copyWith(gameIdentifierText: next);
  }

  /// Migrates from legacy prefs (`game_date`, `body`, …) + `getty` / `imagn` flavor.
  static CaptionTemplate fromLegacySegmentOrder(
    List<String> legacyIds,
    String flavor,
  ) {
    final segments = _parseSegmentOrder(legacyIds);
    if (flavor == 'imagn') {
      return CaptionTemplate.imagn()
          .copyWith(
            segmentOrder: segments,
            customSeparators: null,
            separatorSnippets: null,
            punctuationSnippets: null,
          )
          .normalizePerOccurrenceLists();
    }
    return CaptionTemplate.getty()
        .copyWith(
          segmentOrder: segments,
          customSeparators: null,
          separatorSnippets: null,
          punctuationSnippets: null,
        )
        .normalizePerOccurrenceLists();
  }
}
