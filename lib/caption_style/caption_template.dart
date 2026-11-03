import 'dart:convert';

import 'date_formula.dart';

/// Wire service preset or fully custom formula.
///
/// Enum order doubles as the display order in the Caption Style dropdown.
/// [getty] is the unified Getty preset (“Getty” in UI): location auto-adapts
/// to City+State in the US and City+Country elsewhere.
/// [gettyInternational] is kept for saved templates and uses the same
/// auto-adapt location behavior. Added values are appended at the end so
/// previously-serialised templates — which round-trip via `.name` — still
/// decode correctly.
enum WireStyle { getty, imagn, ap, custom, gettyInternational, cp }

/// Legacy enum — migrated into [LocationLineOptions] when reading old JSON.
enum LocationFormat {
  city_region,
  city_region_country,
  city_state_country,
}

/// One draggable token in the location line (place field or punctuation / spacing).
///
/// [countryCode] is used by Structure `{country_code}` for independent caps
/// storage; location-line editors still offer City / State / Country only.
enum LocationChipKind { city, region, country, countryCode, literal }

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
    this.autoAdaptUsIntl = false,
    this.usChips,
    this.intlChips,
  });

  final bool uppercase;
  final List<LocationChip> chips;
  final bool autoSpacing;

  /// When true, render [usChips] for a United States game and [intlChips]
  /// everywhere else. Getty only. When a side is null, it is derived by
  /// dropping country (US) or state (international) from [chips].
  final bool autoAdaptUsIntl;

  /// American formula (city, state, …). Used when [autoAdaptUsIntl] is set.
  final List<LocationChip>? usChips;

  /// International formula (city, country, …). Used when [autoAdaptUsIntl] is set.
  final List<LocationChip>? intlChips;

  LocationLineOptions copyWith({
    bool? uppercase,
    List<LocationChip>? chips,
    bool? autoSpacing,
    bool? autoAdaptUsIntl,
    List<LocationChip>? usChips,
    List<LocationChip>? intlChips,
  }) =>
      LocationLineOptions(
        uppercase: uppercase ?? this.uppercase,
        chips: chips ?? List<LocationChip>.from(this.chips),
        autoSpacing: autoSpacing ?? this.autoSpacing,
        autoAdaptUsIntl: autoAdaptUsIntl ?? this.autoAdaptUsIntl,
        usChips: usChips != null
            ? List<LocationChip>.from(usChips)
            : (this.usChips == null
                ? null
                : List<LocationChip>.from(this.usChips!)),
        intlChips: intlChips != null
            ? List<LocationChip>.from(intlChips)
            : (this.intlChips == null
                ? null
                : List<LocationChip>.from(this.intlChips!)),
      );

  /// Deep copy for per–geo-chip templates (duplicate City/State/Country groups).
  LocationLineOptions clone() => LocationLineOptions(
        uppercase: uppercase,
        chips: chips.map((c) => c.copyWith()).toList(),
        autoSpacing: autoSpacing,
        autoAdaptUsIntl: autoAdaptUsIntl,
        usChips: usChips?.map((c) => c.copyWith()).toList(),
        intlChips: intlChips?.map((c) => c.copyWith()).toList(),
      );

  /// Chip list for a United States game, or for everywhere else.
  ///
  /// State is always on for the American list and country is always on for the
  /// international list. Older Getty formulas left that chip disabled and the
  /// caption still printed it.
  List<LocationChip> chipsForTerritory({required bool unitedStates}) {
    final kind =
        unitedStates ? LocationChipKind.region : LocationChipKind.country;
    final stored = unitedStates ? usChips : intlChips;
    final base = stored ??
        withoutGeoKind(
          chips,
          unitedStates ? LocationChipKind.country : LocationChipKind.region,
        );
    return ensureGeoKindEnabled(base, kind);
  }

  /// Returns [chips] with [kind] present and enabled. A missing chip is added
  /// after a comma-space. An existing disabled chip is switched on.
  static List<LocationChip> ensureGeoKindEnabled(
    List<LocationChip> chips,
    LocationChipKind kind,
  ) {
    final idx = chips.indexWhere((c) => c.kind == kind);
    if (idx < 0) {
      final out = List<LocationChip>.from(chips);
      final hasGeo = out.any((c) => c.kind != LocationChipKind.literal);
      if (hasGeo) {
        out.add(LocationChip(
          id: 'sep_${kind.name}',
          kind: LocationChipKind.literal,
          literal: ', ',
        ));
      }
      out.add(LocationChip(
        id: 'geo_${kind.name}',
        kind: kind,
        caps: true,
      ));
      return out;
    }
    if (chips[idx].enabled) return chips;
    final out = List<LocationChip>.from(chips);
    out[idx] = chips[idx].copyWith(enabled: true);
    return out;
  }

  /// Drops [drop] plus the separator that belongs to it.
  ///
  /// A chip in the middle gives its following separator up. A chip at the end
  /// also gives up the separator that introduced it, so the other territory
  /// does not inherit a trailing comma.
  static List<LocationChip> withoutGeoKind(
    List<LocationChip> chips,
    LocationChipKind drop,
  ) {
    final idx = chips.indexWhere((c) => c.kind == drop);
    if (idx < 0) return List<LocationChip>.from(chips);
    var end = idx + 1;
    while (end < chips.length &&
        chips[end].kind == LocationChipKind.literal) {
      end++;
    }
    final hasGeoAfter = end < chips.length;
    var start = idx;
    if (!hasGeoAfter) {
      while (start > 0 && chips[start - 1].kind == LocationChipKind.literal) {
        start--;
      }
    }
    return [...chips.sublist(0, start), ...chips.sublist(end)];
  }

  Map<String, dynamic> toJson() => {
        'uppercase': uppercase,
        'locationChips': chips.map((e) => e.toJson()).toList(),
        if (!autoSpacing) 'autoSpacing': false,
        if (autoAdaptUsIntl) 'autoAdaptUsIntl': true,
        if (usChips != null)
          'usChips': usChips!.map((e) => e.toJson()).toList(),
        if (intlChips != null)
          'intlChips': intlChips!.map((e) => e.toJson()).toList(),
      };

  static List<LocationChip>? _chipsFromJson(Object? raw) {
    if (raw is! List) return null;
    return raw
        .map((e) => LocationChip.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  factory LocationLineOptions.fromJson(Map<String, dynamic> j) {
    final autoAdaptUsIntl = j['autoAdaptUsIntl'] as bool? ?? false;
    final usChips = _chipsFromJson(j['usChips']);
    final intlChips = _chipsFromJson(j['intlChips']);
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
          autoAdaptUsIntl: autoAdaptUsIntl,
          usChips: usChips,
          intlChips: intlChips,
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
          autoAdaptUsIntl: autoAdaptUsIntl,
          usChips: usChips,
          intlChips: intlChips,
        );
      }
      // Legacy: uppercase + per-chip caps meant whole-line upper still ran and
      // ignored Aa toggles; per-chip caps are the only source of truth now.
      if (uppercase && anyChipCaps) {
        return LocationLineOptions(
          uppercase: false,
          chips: parsed,
          autoSpacing: j['autoSpacing'] as bool? ?? true,
          autoAdaptUsIntl: autoAdaptUsIntl,
          usChips: usChips,
          intlChips: intlChips,
        );
      }
      return LocationLineOptions(
        uppercase: uppercase,
        chips: parsed,
        autoSpacing: j['autoSpacing'] as bool? ?? true,
        autoAdaptUsIntl: autoAdaptUsIntl,
        usChips: usChips,
        intlChips: intlChips,
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
      autoAdaptUsIntl: j['autoAdaptUsIntl'] as bool? ?? false,
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

  /// Getty stores two formulas. American is city + state. International is
  /// city + country. [chips] keeps the combined list for older readers.
  static LocationLineOptions _gettySplit(List<LocationChip> chips) =>
      LocationLineOptions(
        uppercase: false,
        autoAdaptUsIntl: true,
        chips: chips,
        usChips: withoutGeoKind(chips, LocationChipKind.country),
        intlChips: withoutGeoKind(chips, LocationChipKind.region),
      );

  /// Getty: American city + state, international city + country.
  static LocationLineOptions gettyDefault() => _gettySplit(const [
        LocationChip(id: 'g_city', kind: LocationChipKind.city, caps: true),
        LocationChip(id: 'g_lit1', kind: LocationChipKind.literal, literal: ', '),
        LocationChip(id: 'g_reg', kind: LocationChipKind.region, caps: true),
        LocationChip(id: 'g_lit2', kind: LocationChipKind.literal, literal: ', '),
        LocationChip(id: 'g_ctr', kind: LocationChipKind.country, caps: true),
      ]);

  /// Sentence-case Getty location (second occurrence / “in City, …” line).
  static LocationLineOptions gettyDefaultSentenceCase() => _gettySplit(const [
        LocationChip(id: 'g2_in', kind: LocationChipKind.literal, literal: 'in '),
        LocationChip(id: 'g2_city', kind: LocationChipKind.city),
        LocationChip(id: 'g2_lit1', kind: LocationChipKind.literal, literal: ', '),
        LocationChip(id: 'g2_reg', kind: LocationChipKind.region),
        LocationChip(id: 'g2_lit2', kind: LocationChipKind.literal, literal: ', '),
        LocationChip(id: 'g2_ctr', kind: LocationChipKind.country),
      ]);

  /// Imagn writes city + province + country when present (no US↔intl blanking).
  static LocationLineOptions imagnDefault() => LocationLineOptions(
        uppercase: false,
        autoAdaptUsIntl: false,
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
  'in their WNBA game',
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
    case 'wnba':
      return 'in their WNBA game';
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
///
/// [location] is legacy: saved templates still decode it, then
/// [CaptionTemplate.expandLocationSegments] rewrites each occurrence into
/// [city] / [state] / [country] (plus [punctuation] for in-line separators).
///
/// [date] is legacy: saved templates still decode it, then
/// [CaptionTemplate.expandDateSegments] rewrites each occurrence into
/// [month] / [day] / [year] (and [weekday] when present), plus [punctuation]
/// for in-formula separators.
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
  /// Freeform custom text the user types (e.g. Getty NOTE TO USER). Multiple
  /// allowed; each occurrence has its own string in [CaptionTemplate.freeTextSnippets].
  freeText,
  venue,
  credit,
  /// Photographer name from IPTC Creator ([GameInfo.photographerName]).
  creator,
  /// Agency / credit from IPTC Credit ([GameInfo.agencyName]).
  agency,
  /// City from game / IPTC location.
  city,
  /// State or province from game / IPTC location.
  state,
  /// Country (full name) from game / IPTC location.
  country,
  /// ISO country code from [GameInfo.resolvedCountryCode].
  countryCode,
  /// Month part of the caption date (from photo EXIF or game date).
  month,
  /// Day-of-month part of the caption date.
  day,
  /// Year part of the caption date.
  year,
  /// Optional weekday part (migrated from structured [DateFormula] only).
  weekday,
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
    this.useTeamPossessive = false,
    this.americanEnglish = true,
    this.removeDiacritics = true,
    this.showPersonalityField = true,
    this.showKeywordsField = false,
    this.timingPhraseCaps = false,
    this.includeTimingPhrase = true,
    required this.separator,
    required this.creditFormat,
    required this.bylineOptions,
    required this.segmentOrder,
    this.gameIdentifierText = '',
    this.captionPrefix = '',
    this.captionSuffix = '',
    this.gameIdentifierPrefix = '',
    this.gameIdentifierSuffix = ' ',
    this.customSeparators,
    this.separatorSnippets,
    this.punctuationSnippets,
    this.freeTextSnippets,
    this.freeTextSuffixes,
    this.venuePrefix = '',
    this.venueSuffix = '',
    this.locationOptionsByOccurrence,
    this.dateFormulasByOccurrence,
    this.monthTokensByOccurrence,
    this.dayTokensByOccurrence,
    this.yearTokensByOccurrence,
    this.weekdayTokensByOccurrence,
    this.layoutPrefix = '',
    this.layoutSuffix = '',
    this.basketballUserNote = '',
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

  /// When true and [captionTeamOrder] is [CaptionTeamOrder.teamBefore], the
  /// team name is possessive (`Maple Leafs' Auston Matthews`).
  ///
  /// Nullable so instances that survive a hot reload (when this field was
  /// first added) do not throw on read; treat null as false.
  final bool? useTeamPossessive;

  /// Getty wire captions never include roster positions (abbreviated or expanded).
  bool get effectiveIncludePlayerPosition {
    if (wireStyle == WireStyle.getty ||
        wireStyle == WireStyle.gettyInternational) {
      return false;
    }
    return includePlayerPosition;
  }

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

  /// When true, the period / inning / quarter / half timing clause is emitted
  /// in ALL CAPS (e.g. `DURING THE THIRD INNING`). Defaults to off.
  final bool timingPhraseCaps;

  /// When false, captions omit the time-of-game clause (inning / period /
  /// quarter / half / before / following the game). Defaults to on.
  final bool includeTimingPhrase;

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

  /// Text prepended/appended to the entire rendered caption output (outside all
  /// segment blocks). Editable as the leftmost/rightmost text boxes in the
  /// caption layout builder so there is never hidden punctuation at the edges.
  final String layoutPrefix;
  final String layoutSuffix;

  /// Sentence typed after the byline for basketball and WNBA. Empty means
  /// nothing is added. Not inserted by the renderer on its own.
  final String basketballUserNote;

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

  /// One string per [CaptionSegment.freeText] ("Custom text" in UI) in
  /// [segmentOrder] (left-to-right). Freeform user text (e.g. Getty NOTE TO USER).
  final List<String>? freeTextSnippets;

  /// Trailing literal after each [freeTextSnippets] body (period, space, etc.).
  final List<String>? freeTextSuffixes;

  final String venuePrefix;
  final String venueSuffix;

  /// Format options for geo field segments ([CaptionSegment.city] /
  /// [CaptionSegment.state] / [CaptionSegment.country] /
  /// [CaptionSegment.countryCode]). Indexed by occurrence of that field kind
  /// (left-to-right). Also used when migrating legacy
  /// [CaptionSegment.location] chips. When null, every geo field uses
  /// [locationOptions].
  final List<LocationLineOptions>? locationOptionsByOccurrence;

  /// One [DateFormula] per legacy [CaptionSegment.date] in [segmentOrder]
  /// (left-to-right). When null, every date segment uses [dateFormula].
  /// After [expandDateSegments], date chips are gone and per-part token lists
  /// below drive formatting instead.
  final List<DateFormula>? dateFormulasByOccurrence;

  /// Format options per [CaptionSegment.month] occurrence (left-to-right).
  /// When null or short, falls back to the month field in [dateFormula].
  final List<DateFieldToken>? monthTokensByOccurrence;

  /// Format options per [CaptionSegment.day] occurrence (left-to-right).
  final List<DateFieldToken>? dayTokensByOccurrence;

  /// Format options per [CaptionSegment.year] occurrence (left-to-right).
  final List<DateFieldToken>? yearTokensByOccurrence;

  /// Format options per [CaptionSegment.weekday] occurrence (left-to-right).
  final List<DateFieldToken>? weekdayTokensByOccurrence;

  /// Matches [CaptionTemplate.getty] / [CaptionTemplate.gettyInternational]
  /// snippet layout (Custom literal chips + optional narrative + separator before venue).
  static const List<CaptionSegment> defaultSegmentOrder = [
    CaptionSegment.city,
    CaptionSegment.punctuation,
    CaptionSegment.state,
    CaptionSegment.punctuation,
    CaptionSegment.country,
    CaptionSegment.punctuation,
    CaptionSegment.month,
    CaptionSegment.punctuation,
    CaptionSegment.day,
    CaptionSegment.punctuation,
    CaptionSegment.year,
    CaptionSegment.punctuation,
    CaptionSegment.caption,
    CaptionSegment.punctuation,
    CaptionSegment.freeText,
    CaptionSegment.separator,
    CaptionSegment.venue,
    CaptionSegment.punctuation,
    CaptionSegment.credit,
  ];

  factory CaptionTemplate.getty() => CaptionTemplate(
        id: 'preset_getty',
        name: 'Getty',
        wireStyle: WireStyle.getty,
        dateFormat: 'MMMM d, yyyy',
        dateExpression: '',
        dateFormula: DateFormula.gettyOpening(),
        locationOptions: LocationLineOptions.gettyDefault(),
        numberFormat: NumberFormatStyle.hash,
        captionTeamOrder: CaptionTeamOrder.teamAfter,
        includePlayerPosition: false,
        americanEnglish: true,
        removeDiacritics: true,
        separator: ' - ',
        creditFormat: CreditFormat.photo_by,
        bylineOptions: BylineOptions.getty(),
        // CITY, STATE - MONTH DAY: CAPTION GAMEID at VENUE on MONTH DAY, YEAR in CITY, STATE.
        // Country is included so auto-adapt can swap State↔Country by territory.
        segmentOrder: const [
          CaptionSegment.city,
          CaptionSegment.punctuation,
          CaptionSegment.state,
          CaptionSegment.punctuation,
          CaptionSegment.country,
          CaptionSegment.punctuation,
          CaptionSegment.month,
          CaptionSegment.punctuation,
          CaptionSegment.day,
          CaptionSegment.punctuation,
          CaptionSegment.caption,
          CaptionSegment.punctuation,
          CaptionSegment.freeText,
          CaptionSegment.separator,
          CaptionSegment.venue,
          CaptionSegment.separator,
          CaptionSegment.month,
          CaptionSegment.punctuation,
          CaptionSegment.day,
          CaptionSegment.punctuation,
          CaptionSegment.year,
          CaptionSegment.punctuation,
          CaptionSegment.city,
          CaptionSegment.punctuation,
          CaptionSegment.state,
          CaptionSegment.punctuation,
          CaptionSegment.country,
          CaptionSegment.punctuation,
          CaptionSegment.credit,
        ],
        customSeparators: const [
          '', '', '', '', '', '', '', '', '', '', '', '', '',
          '', '', '', '', '', '', '', '', '', '', '', '', '', '', '',
        ],
        separatorSnippets: const [' at ', ' on '],
        punctuationSnippets: const [
          ', ',
          ', ',
          ' - ',
          ' ',
          ': ',
          ' ',
          ' ',
          ', ',
          'in ',
          ', ',
          ', ',
          '. ',
        ],
        // Filled per sport via [applyGameIdentifierText] ("in their NHL game", …).
        freeTextSnippets: const [''],
        freeTextSuffixes: const [''],
        locationOptionsByOccurrence: [
          LocationLineOptions.gettyDefault(),
          LocationLineOptions.gettyDefaultSentenceCase(),
        ],
        dateFormulasByOccurrence: [
          DateFormula.gettyOpening(),
          DateFormula.gettyClosing(),
        ],
        monthTokensByOccurrence: [
          DateFieldToken(kind: DateFieldKind.month, optionIndex: 0, caps: true),
          DateFieldToken(kind: DateFieldKind.month, optionIndex: 0),
        ],
        dayTokensByOccurrence: [
          DateFieldToken(kind: DateFieldKind.day, optionIndex: 0),
          DateFieldToken(kind: DateFieldKind.day, optionIndex: 0),
        ],
        yearTokensByOccurrence: [
          DateFieldToken(kind: DateFieldKind.year, optionIndex: 0),
        ],
      );

  /// Imagn joiners live only in Structure (punctuation / separator snippets).
  /// Same layout for every sport — position / period wording lives in
  /// `{caption}`. Country uses the ISO code (`USA` / `CAN`), matching wire copy:
  /// `{month} {day}, {year}; {city}, {state}, {country_code}; {caption} at {location}. {byline}`
  /// Wired gaps stay empty so the renderer never stacks a second `; `, `, `, etc.
  /// (`Mandatory Credit: …` stays in [BylineOptions.imagn] prefix, not Structure).
  factory CaptionTemplate.imagn() => CaptionTemplate(
        id: 'preset_imagn',
        name: 'Imagn',
        wireStyle: WireStyle.imagn,
        dateFormat: 'MMM d, yyyy',
        dateExpression: '',
        dateFormula: DateFormula.imagn(),
        locationOptions: LocationLineOptions.fromLegacyFormat(
            LocationFormat.city_region_country),
        numberFormat: NumberFormatStyle.parens,
        captionTeamOrder: CaptionTeamOrder.teamBefore,
        includePlayerPosition: true,
        americanEnglish: true,
        removeDiacritics: true,
        // Structure owns `; ` / `, ` / ` at ` / `. ` — not this fallback.
        separator: '',
        creditFormat: CreditFormat.mandatory_credit,
        bylineOptions: BylineOptions.imagn(),
        segmentOrder: const [
          CaptionSegment.month,
          CaptionSegment.punctuation,
          CaptionSegment.day,
          CaptionSegment.punctuation,
          CaptionSegment.year,
          CaptionSegment.punctuation,
          CaptionSegment.city,
          CaptionSegment.punctuation,
          CaptionSegment.state,
          CaptionSegment.punctuation,
          CaptionSegment.countryCode,
          CaptionSegment.punctuation,
          CaptionSegment.caption,
          CaptionSegment.separator,
          CaptionSegment.venue,
          CaptionSegment.punctuation,
          CaptionSegment.credit,
        ],
        customSeparators: const [
          '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '',
        ],
        separatorSnippets: const [' at '],
        punctuationSnippets: const [' ', ', ', '; ', ', ', ', ', '; ', '. '],
        locationOptionsByOccurrence: null,
        dateFormulasByOccurrence: null,
        monthTokensByOccurrence: [
          DateFieldToken(kind: DateFieldKind.month, optionIndex: 1),
        ],
        dayTokensByOccurrence: [
          DateFieldToken(kind: DateFieldKind.day, optionIndex: 0),
        ],
        yearTokensByOccurrence: [
          DateFieldToken(kind: DateFieldKind.year, optionIndex: 0),
        ],
      );

  /// Same formula as [CaptionTemplate.getty] with Getty International wire id.
  /// Location lines use the same US City+State / world City+Country auto-adapt.
  factory CaptionTemplate.gettyInternational() {
    final base = CaptionTemplate.getty();
    return base.copyWith(
      id: 'preset_getty_international',
      name: 'Getty International',
      wireStyle: WireStyle.gettyInternational,
      americanEnglish: false,
    );
  }

  factory CaptionTemplate.ap() => CaptionTemplate(
        id: 'preset_ap',
        name: 'Associated Press',
        wireStyle: WireStyle.ap,
        dateFormat: 'MMM d, yyyy',
        dateExpression: '',
        dateFormula: DateFormula.imagn(),
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
          CaptionSegment.city,
          CaptionSegment.punctuation,
          CaptionSegment.state,
          CaptionSegment.punctuation,
          CaptionSegment.month,
          CaptionSegment.punctuation,
          CaptionSegment.day,
          CaptionSegment.punctuation,
          CaptionSegment.year,
          CaptionSegment.punctuation,
          CaptionSegment.caption,
          CaptionSegment.separator,
          CaptionSegment.venue,
          CaptionSegment.punctuation,
          CaptionSegment.credit,
        ],
        customSeparators: const [
          '', '', '', '', '', '', '', '', '', '', '', '', '',
        ],
        separatorSnippets: const [' at '],
        punctuationSnippets: const [', ', ' (', ' ', ', ', ') — ', '. '],
        locationOptionsByOccurrence: null,
        dateFormulasByOccurrence: null,
        monthTokensByOccurrence: [
          DateFieldToken(kind: DateFieldKind.month, optionIndex: 1),
        ],
        dayTokensByOccurrence: [
          DateFieldToken(kind: DateFieldKind.day, optionIndex: 0),
        ],
        yearTokensByOccurrence: [
          DateFieldToken(kind: DateFieldKind.year, optionIndex: 0),
        ],
      );

  factory CaptionTemplate.cp() => CaptionTemplate(
        id: 'preset_cp',
        name: 'Canadian Press',
        wireStyle: WireStyle.cp,
        dateFormat: 'MMM d, yyyy',
        dateExpression: '',
        dateFormula: DateFormula.imagn(),
        // City + province with CP Style (standalone cities omit province).
        locationOptions: LocationLineOptions.apDefault(),
        numberFormat: NumberFormatStyle.parens,
        captionTeamOrder: CaptionTeamOrder.teamBefore,
        includePlayerPosition: false,
        useTeamPossessive: true,
        americanEnglish: true,
        removeDiacritics: true,
        separator: ' — ',
        creditFormat: CreditFormat.photo_by,
        bylineOptions: BylineOptions.ap(),
        // Dateline: City[, Prov.,] Month Day, Year — Caption …
        // Trailing ", " after province yields "Que., on …" when Structure
        // continues; empty province drops the comma (standalone cities).
        segmentOrder: const [
          CaptionSegment.city,
          CaptionSegment.punctuation,
          CaptionSegment.state,
          CaptionSegment.punctuation,
          CaptionSegment.month,
          CaptionSegment.punctuation,
          CaptionSegment.day,
          CaptionSegment.punctuation,
          CaptionSegment.year,
          CaptionSegment.punctuation,
          CaptionSegment.caption,
          CaptionSegment.separator,
          CaptionSegment.venue,
          CaptionSegment.punctuation,
          CaptionSegment.credit,
        ],
        customSeparators: const [
          '', '', '', '', '', '', '', '', '', '', '', '', '',
        ],
        separatorSnippets: const [' at '],
        punctuationSnippets: const [', ', ', ', ' ', ', ', ' — ', '. '],
        locationOptionsByOccurrence: null,
        dateFormulasByOccurrence: null,
        monthTokensByOccurrence: [
          DateFieldToken(kind: DateFieldKind.month, optionIndex: 1),
        ],
        dayTokensByOccurrence: [
          DateFieldToken(kind: DateFieldKind.day, optionIndex: 0),
        ],
        yearTokensByOccurrence: [
          DateFieldToken(kind: DateFieldKind.year, optionIndex: 0),
        ],
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
    bool useTeamPossessive = false,
    bool americanEnglish = true,
    bool removeDiacritics = true,
    bool showPersonalityField = true,
    bool showKeywordsField = false,
    bool timingPhraseCaps = false,
    bool includeTimingPhrase = true,
    String separator = '; ',
    CreditFormat creditFormat = CreditFormat.mandatory_credit,
    BylineOptions? bylineOptions,
    List<CaptionSegment>? segmentOrder,
    List<String>? customSeparators,
    List<String>? separatorSnippets,
    List<String>? punctuationSnippets,
    List<String>? freeTextSnippets,
    List<String>? freeTextSuffixes,
    String captionPrefix = '',
    String captionSuffix = '',
    String gameIdentifierText = '',
    String gameIdentifierPrefix = '',
    String gameIdentifierSuffix = ' ',
    String venuePrefix = '',
    String venueSuffix = '',
    DateFormula? dateFormula,
    List<DateFormula>? dateFormulasByOccurrence,
    List<LocationLineOptions>? locationOptionsByOccurrence,
    List<DateFieldToken>? monthTokensByOccurrence,
    List<DateFieldToken>? dayTokensByOccurrence,
    List<DateFieldToken>? yearTokensByOccurrence,
    List<DateFieldToken>? weekdayTokensByOccurrence,
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
    final punctCount =
        resolvedOrder.where((s) => s == CaptionSegment.punctuation).length;
    final resolvedPunSnippets = punctuationSnippets ??
        (useFactorySnippetDefaults
            ? List<String>.filled(punctCount, separator)
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
      useTeamPossessive: useTeamPossessive,
      americanEnglish: americanEnglish,
      removeDiacritics: removeDiacritics,
      showPersonalityField: showPersonalityField,
      showKeywordsField: showKeywordsField,
      timingPhraseCaps: timingPhraseCaps,
      includeTimingPhrase: includeTimingPhrase,
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
      freeTextSnippets: freeTextSnippets,
      freeTextSuffixes: freeTextSuffixes,
      venuePrefix: venuePrefix,
      venueSuffix: venueSuffix,
      locationOptionsByOccurrence: locationOptionsByOccurrence,
      dateFormulasByOccurrence: dateFormulasByOccurrence,
      monthTokensByOccurrence: monthTokensByOccurrence,
      dayTokensByOccurrence: dayTokensByOccurrence,
      yearTokensByOccurrence: yearTokensByOccurrence,
      weekdayTokensByOccurrence: weekdayTokensByOccurrence,
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
    bool? useTeamPossessive,
    bool? americanEnglish,
    bool? removeDiacritics,
    bool? showPersonalityField,
    bool? showKeywordsField,
    bool? timingPhraseCaps,
    bool? includeTimingPhrase,
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
    Object? freeTextSnippets = _unset,
    Object? freeTextSuffixes = _unset,
    String? venuePrefix,
    String? venueSuffix,
    Object? locationOptionsByOccurrence = _unset,
    Object? dateFormulasByOccurrence = _unset,
    Object? monthTokensByOccurrence = _unset,
    Object? dayTokensByOccurrence = _unset,
    Object? yearTokensByOccurrence = _unset,
    Object? weekdayTokensByOccurrence = _unset,
    String? layoutPrefix,
    String? layoutSuffix,
    String? basketballUserNote,
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
        includePlayerPosition:
            includePlayerPosition ?? this.includePlayerPosition,
        useTeamPossessive:
            useTeamPossessive ?? this.useTeamPossessive ?? false,
        americanEnglish: americanEnglish ?? this.americanEnglish,
        removeDiacritics: removeDiacritics ?? this.removeDiacritics,
        showPersonalityField:
            showPersonalityField ?? this.showPersonalityField,
        showKeywordsField: showKeywordsField ?? this.showKeywordsField,
        timingPhraseCaps: timingPhraseCaps ?? this.timingPhraseCaps,
        includeTimingPhrase: includeTimingPhrase ?? this.includeTimingPhrase,
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
        freeTextSnippets: identical(freeTextSnippets, _unset)
            ? this.freeTextSnippets
            : freeTextSnippets as List<String>?,
        freeTextSuffixes: identical(freeTextSuffixes, _unset)
            ? this.freeTextSuffixes
            : freeTextSuffixes as List<String>?,
        venuePrefix: venuePrefix ?? this.venuePrefix,
        venueSuffix: venueSuffix ?? this.venueSuffix,
        locationOptionsByOccurrence: identical(locationOptionsByOccurrence, _unset)
            ? this.locationOptionsByOccurrence
            : locationOptionsByOccurrence as List<LocationLineOptions>?,
        dateFormulasByOccurrence: identical(dateFormulasByOccurrence, _unset)
            ? this.dateFormulasByOccurrence
            : dateFormulasByOccurrence as List<DateFormula>?,
        monthTokensByOccurrence: identical(monthTokensByOccurrence, _unset)
            ? this.monthTokensByOccurrence
            : monthTokensByOccurrence as List<DateFieldToken>?,
        dayTokensByOccurrence: identical(dayTokensByOccurrence, _unset)
            ? this.dayTokensByOccurrence
            : dayTokensByOccurrence as List<DateFieldToken>?,
        yearTokensByOccurrence: identical(yearTokensByOccurrence, _unset)
            ? this.yearTokensByOccurrence
            : yearTokensByOccurrence as List<DateFieldToken>?,
        weekdayTokensByOccurrence: identical(weekdayTokensByOccurrence, _unset)
            ? this.weekdayTokensByOccurrence
            : weekdayTokensByOccurrence as List<DateFieldToken>?,
        layoutPrefix: layoutPrefix ?? this.layoutPrefix,
        layoutSuffix: layoutSuffix ?? this.layoutSuffix,
        basketballUserNote: basketballUserNote ?? this.basketballUserNote,
      );

  /// Older Getty prefs only had one date + one location (ending `at VENUE.`).
  /// Current Getty needs `at VENUE on MONTH DAY, YEAR in CITY…. (Photo…)`.
  static CaptionTemplate migrateGettyClosingFormulaIfNeeded(CaptionTemplate t) {
    if (t.wireStyle != WireStyle.getty &&
        t.wireStyle != WireStyle.gettyInternational) {
      return t;
    }
    final dates = t.segmentOrder.where((s) => s == CaptionSegment.date).length;
    final months = t.segmentOrder.where((s) => s == CaptionSegment.month).length;
    final cities = t.segmentOrder.where((s) => s == CaptionSegment.city).length;
    final locs =
        t.segmentOrder.where((s) => s == CaptionSegment.location).length;
    // Two city groups (or two legacy location chips) plus two date/month
    // groups means the closing formula is already present.
    final dateGroups = dates >= 2 || months >= 2;
    if (dateGroups && (cities >= 2 || locs >= 2)) return t;

    final factory = t.wireStyle == WireStyle.gettyInternational
        ? CaptionTemplate.gettyInternational()
        : CaptionTemplate.getty();
    return t
        .copyWith(
          segmentOrder: List<CaptionSegment>.from(factory.segmentOrder),
          customSeparators: factory.customSeparators != null
              ? List<String>.from(factory.customSeparators!)
              : null,
          separatorSnippets: factory.separatorSnippets != null
              ? List<String>.from(factory.separatorSnippets!)
              : null,
          punctuationSnippets: factory.punctuationSnippets != null
              ? List<String>.from(factory.punctuationSnippets!)
              : null,
          locationOptions: factory.locationOptions.clone(),
          locationOptionsByOccurrence: factory.locationOptionsByOccurrence
              ?.map((e) => e.clone())
              .toList(),
          dateFormula: factory.dateFormula?.clone(),
          dateFormulasByOccurrence:
              factory.dateFormulasByOccurrence?.map((e) => e.clone()).toList(),
          monthTokensByOccurrence: factory.monthTokensByOccurrence
              ?.map((e) => e.copy())
              .toList(),
          dayTokensByOccurrence:
              factory.dayTokensByOccurrence?.map((e) => e.copy()).toList(),
          yearTokensByOccurrence:
              factory.yearTokensByOccurrence?.map((e) => e.copy()).toList(),
          weekdayTokensByOccurrence: factory.weekdayTokensByOccurrence
              ?.map((e) => e.copy())
              .toList(),
        )
        .normalizePerOccurrenceLists();
  }

  /// Rewrites each legacy [CaptionSegment.location] into city / state / country
  /// tokens (plus [CaptionSegment.punctuation] for chip literals), preserving
  /// separators from [LocationLineOptions.chips].
  ///
  /// No-op when [segmentOrder] has no [CaptionSegment.location].
  CaptionTemplate expandLocationSegments() {
    if (!segmentOrder.contains(CaptionSegment.location)) return this;

    final newOrder = <CaptionSegment>[];
    final newPuncts = <String>[];
    final newSeps = <String>[];
    final newGaps = <String>[];

    final oldPuncts = punctuationSnippets;
    final oldSeps = separatorSnippets;
    final oldGaps = customSeparators;
    var punctOcc = 0;
    var sepOcc = 0;
    var locOcc = 0;

    String nextOldPunct() {
      if (oldPuncts != null && punctOcc < oldPuncts.length) {
        return oldPuncts[punctOcc++];
      }
      punctOcc++;
      return '';
    }

    String nextOldSep() {
      if (oldSeps != null && sepOcc < oldSeps.length) {
        return oldSeps[sepOcc++];
      }
      sepOcc++;
      return ' ';
    }

    for (var i = 0; i < segmentOrder.length; i++) {
      final s = segmentOrder[i];
      if (s != CaptionSegment.location) {
        if (newOrder.isNotEmpty) {
          final oldGapIdx = i - 1;
          if (oldGaps != null &&
              oldGapIdx >= 0 &&
              oldGapIdx < oldGaps.length &&
              // Only reuse the old gap when the previous original segment was
              // not expanded (single→many would mis-align indices).
              segmentOrder[i - 1] != CaptionSegment.location) {
            newGaps.add(oldGaps[oldGapIdx]);
          } else {
            newGaps.add('');
          }
        }
        newOrder.add(s);
        if (s == CaptionSegment.punctuation) {
          newPuncts.add(nextOldPunct());
        } else if (s == CaptionSegment.separator) {
          newSeps.add(nextOldSep());
        }
        continue;
      }

      final by = locationOptionsByOccurrence;
      final opts = (by != null && locOcc < by.length)
          ? by[locOcc]
          : locationOptions;
      locOcc++;

      // Auto-adapt templates keep city+state+country so territory can hide one.
      // Other templates drop disabled chips (and their trailing literals).
      final chips = opts.autoAdaptUsIntl
          ? List<LocationChip>.from(opts.chips)
          : _activeChipsForExpansion(opts.chips);

      for (final c in chips) {
        late final CaptionSegment seg;
        String? punct;
        switch (c.kind) {
          case LocationChipKind.city:
            seg = CaptionSegment.city;
            break;
          case LocationChipKind.region:
            seg = CaptionSegment.state;
            break;
          case LocationChipKind.country:
            seg = CaptionSegment.country;
            break;
          case LocationChipKind.countryCode:
            seg = CaptionSegment.countryCode;
            break;
          case LocationChipKind.literal:
            seg = CaptionSegment.punctuation;
            punct = c.literal;
            break;
        }
        if (newOrder.isNotEmpty) newGaps.add('');
        newOrder.add(seg);
        if (seg == CaptionSegment.punctuation) {
          newPuncts.add(punct ?? '');
        }
      }
    }

    // Consume the gap after a trailing expanded location (between location and
    // whatever followed it in the original order).
    // Already handled in the non-location branch via the "previous was location"
    // empty-gap path when the next segment is added.

    return copyWith(
      segmentOrder: newOrder,
      punctuationSnippets: newPuncts.isEmpty ? null : newPuncts,
      separatorSnippets: newSeps.isEmpty && oldSeps == null ? null : newSeps,
      customSeparators: newGaps.isEmpty ? null : newGaps,
    );
  }

  static List<LocationChip> _activeChipsForExpansion(List<LocationChip> chips) {
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

  /// True for month / day / year / weekday structure tokens.
  static bool isDatePartSegment(CaptionSegment s) =>
      s == CaptionSegment.month ||
      s == CaptionSegment.day ||
      s == CaptionSegment.year ||
      s == CaptionSegment.weekday;

  /// Builds a [DateFormula] that mirrors common ICU [dateFormat] patterns when
  /// no structured formula was saved (older Imagn / AP / CP prefs).
  static DateFormula dateFormulaFromLegacyPattern(String pattern) {
    final p = pattern.trim();
    if (p == 'MMMM d, yyyy' || p == 'MMMM d, y') {
      return DateFormula(
        fields: [
          DateFieldToken(kind: DateFieldKind.month, optionIndex: 0),
          DateFieldToken(kind: DateFieldKind.day, optionIndex: 0),
          DateFieldToken(kind: DateFieldKind.year, optionIndex: 0),
        ],
        separators: const ['', ' ', ', ', ''],
      );
    }
    if (p == 'MMM d, yyyy' || p == 'MMM d, y') {
      return DateFormula.imagn();
    }
    if (p == 'M/d/yy' || p == 'M/d/yyyy' || p == 'MM/dd/yy' || p == 'MM/dd/yyyy') {
      final padMonth = p.startsWith('MM');
      final padDay = p.contains('/dd');
      final twoYear = p.endsWith('yy') && !p.endsWith('yyyy');
      return DateFormula(
        fields: [
          DateFieldToken(
              kind: DateFieldKind.month, optionIndex: padMonth ? 3 : 2),
          DateFieldToken(kind: DateFieldKind.day, optionIndex: padDay ? 1 : 0),
          DateFieldToken(
              kind: DateFieldKind.year, optionIndex: twoYear ? 1 : 0),
        ],
        separators: const ['', '/', '/', ''],
      );
    }
    return DateFormula.ap();
  }

  DateFormula _formulaForDateOccurrence(int occ) {
    final by = dateFormulasByOccurrence;
    if (by != null && occ >= 0 && occ < by.length) return by[occ];
    if (dateFormula != null && dateFormula!.fields.isNotEmpty) {
      return dateFormula!;
    }
    return dateFormulaFromLegacyPattern(dateFormat);
  }

  static CaptionSegment _segmentForDateFieldKind(DateFieldKind kind) {
    switch (kind) {
      case DateFieldKind.weekday:
        return CaptionSegment.weekday;
      case DateFieldKind.month:
        return CaptionSegment.month;
      case DateFieldKind.day:
        return CaptionSegment.day;
      case DateFieldKind.year:
        return CaptionSegment.year;
    }
  }

  /// Rewrites each legacy [CaptionSegment.date] into month / day / year
  /// (and weekday when present) plus [CaptionSegment.punctuation] for the
  /// separators that lived inside the structured [DateFormula].
  ///
  /// Disabled formula fields are dropped (and the separator that followed
  /// them). Leading / trailing empty formula separators are omitted.
  ///
  /// No-op when [segmentOrder] has no [CaptionSegment.date].
  CaptionTemplate expandDateSegments() {
    if (!segmentOrder.contains(CaptionSegment.date)) return this;

    final newOrder = <CaptionSegment>[];
    final newPuncts = <String>[];
    final newSeps = <String>[];
    final newGaps = <String>[];
    final months = <DateFieldToken>[];
    final days = <DateFieldToken>[];
    final years = <DateFieldToken>[];
    final weekdays = <DateFieldToken>[];

    final oldPuncts = punctuationSnippets;
    final oldSeps = separatorSnippets;
    final oldGaps = customSeparators;
    var punctOcc = 0;
    var sepOcc = 0;
    var dateOcc = 0;

    String nextOldPunct() {
      if (oldPuncts != null && punctOcc < oldPuncts.length) {
        return oldPuncts[punctOcc++];
      }
      punctOcc++;
      return '';
    }

    String nextOldSep() {
      if (oldSeps != null && sepOcc < oldSeps.length) {
        return oldSeps[sepOcc++];
      }
      sepOcc++;
      return ' ';
    }

    for (var i = 0; i < segmentOrder.length; i++) {
      final s = segmentOrder[i];
      if (s != CaptionSegment.date) {
        if (newOrder.isNotEmpty) {
          final oldGapIdx = i - 1;
          if (oldGaps != null &&
              oldGapIdx >= 0 &&
              oldGapIdx < oldGaps.length &&
              segmentOrder[i - 1] != CaptionSegment.date) {
            newGaps.add(oldGaps[oldGapIdx]);
          } else {
            newGaps.add('');
          }
        }
        newOrder.add(s);
        if (s == CaptionSegment.punctuation) {
          newPuncts.add(nextOldPunct());
        } else if (s == CaptionSegment.separator) {
          newSeps.add(nextOldSep());
        }
        continue;
      }

      final formula = _formulaForDateOccurrence(dateOcc);
      dateOcc++;

      final kept = <({DateFieldToken token, int origIdx})>[];
      for (var fi = 0; fi < formula.fields.length; fi++) {
        final f = formula.fields[fi];
        if (!f.enabled) continue;
        kept.add((token: f.copy(), origIdx: fi));
      }

      for (var k = 0; k < kept.length; k++) {
        final entry = kept[k];
        final token = entry.token;
        final seg = _segmentForDateFieldKind(token.kind);

        // Separator between kept fields (skip empty leading / trailing).
        if (k > 0) {
          final sepIdx = kept[k - 1].origIdx + 1;
          final sep = sepIdx < formula.separators.length
              ? formula.separators[sepIdx]
              : ' ';
          final punctText = sep.isEmpty ? ' ' : sep;
          if (newOrder.isNotEmpty) newGaps.add('');
          newOrder.add(CaptionSegment.punctuation);
          newPuncts.add(punctText);
        }

        if (newOrder.isNotEmpty) newGaps.add('');
        newOrder.add(seg);
        switch (token.kind) {
          case DateFieldKind.month:
            months.add(token);
            break;
          case DateFieldKind.day:
            days.add(token);
            break;
          case DateFieldKind.year:
            years.add(token);
            break;
          case DateFieldKind.weekday:
            weekdays.add(token);
            break;
        }
      }
    }

    // Preserve any existing per-part tokens that already lived alongside
    // legacy date chips (unusual, but keep them ahead of migrated ones).
    List<DateFieldToken>? mergeTokens(
      List<DateFieldToken>? existing,
      List<DateFieldToken> migrated,
    ) {
      if (migrated.isEmpty && (existing == null || existing.isEmpty)) {
        return existing;
      }
      if (existing == null || existing.isEmpty) {
        return migrated.isEmpty ? null : migrated;
      }
      return [...existing, ...migrated];
    }

    return copyWith(
      segmentOrder: newOrder,
      punctuationSnippets: newPuncts.isEmpty ? null : newPuncts,
      separatorSnippets: newSeps.isEmpty && oldSeps == null ? null : newSeps,
      customSeparators: newGaps.isEmpty ? null : newGaps,
      monthTokensByOccurrence:
          mergeTokens(monthTokensByOccurrence, months),
      dayTokensByOccurrence: mergeTokens(dayTokensByOccurrence, days),
      yearTokensByOccurrence: mergeTokens(yearTokensByOccurrence, years),
      weekdayTokensByOccurrence:
          mergeTokens(weekdayTokensByOccurrence, weekdays),
    );
  }

  /// Ensures [locationOptionsByOccurrence] / [dateFormulasByOccurrence] /
  /// date-part token lists have one entry per occurrence when duplicates exist.
  /// Otherwise the renderer falls back to shared defaults and in-place editor
  /// edits are shared across chips.
  CaptionTemplate normalizePerOccurrenceLists() {
    var r = migrateGameIdentifierToFreeText();

    final geoOcc = [
      r.segmentOrder.where((s) => s == CaptionSegment.city).length,
      r.segmentOrder.where((s) => s == CaptionSegment.state).length,
      r.segmentOrder.where((s) => s == CaptionSegment.country).length,
      r.segmentOrder.where((s) => s == CaptionSegment.countryCode).length,
      r.segmentOrder.where((s) => s == CaptionSegment.location).length,
    ].fold<int>(0, (a, b) => a > b ? a : b);
    final dateCount =
        r.segmentOrder.where((s) => s == CaptionSegment.date).length;
    final monthCount =
        r.segmentOrder.where((s) => s == CaptionSegment.month).length;
    final dayCount =
        r.segmentOrder.where((s) => s == CaptionSegment.day).length;
    final yearCount =
        r.segmentOrder.where((s) => s == CaptionSegment.year).length;
    final weekdayCount =
        r.segmentOrder.where((s) => s == CaptionSegment.weekday).length;

    if (geoOcc > 1) {
      final by = r.locationOptionsByOccurrence;
      if (by == null || by.length < geoOcc) {
        final list = <LocationLineOptions>[];
        for (var i = 0; i < geoOcc; i++) {
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

    DateFieldToken seedToken(DateFieldKind kind) {
      final formula = r.dateFormula ??
          dateFormulaFromLegacyPattern(r.dateFormat);
      for (final f in formula.fields) {
        if (f.kind == kind) return f.copy();
      }
      return DateFieldToken(kind: kind);
    }

    List<DateFieldToken>? normalizeKind(
      int count,
      List<DateFieldToken>? by,
      DateFieldKind kind,
    ) {
      if (count <= 0) return by;
      if (by != null && by.length >= count) return by;
      final list = <DateFieldToken>[];
      for (var i = 0; i < count; i++) {
        if (by != null && i < by.length) {
          list.add(by[i].copy());
        } else if (list.isEmpty) {
          list.add(seedToken(kind));
        } else {
          list.add(list.last.copy());
        }
      }
      return list;
    }

    final nextMonths =
        normalizeKind(monthCount, r.monthTokensByOccurrence, DateFieldKind.month);
    final nextDays =
        normalizeKind(dayCount, r.dayTokensByOccurrence, DateFieldKind.day);
    final nextYears =
        normalizeKind(yearCount, r.yearTokensByOccurrence, DateFieldKind.year);
    final nextWeekdays = normalizeKind(
        weekdayCount, r.weekdayTokensByOccurrence, DateFieldKind.weekday);

    if (!identical(nextMonths, r.monthTokensByOccurrence) ||
        !identical(nextDays, r.dayTokensByOccurrence) ||
        !identical(nextYears, r.yearTokensByOccurrence) ||
        !identical(nextWeekdays, r.weekdayTokensByOccurrence)) {
      r = r.copyWith(
        monthTokensByOccurrence: nextMonths,
        dayTokensByOccurrence: nextDays,
        yearTokensByOccurrence: nextYears,
        weekdayTokensByOccurrence: nextWeekdays,
      );
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

    final freeCount =
        r.segmentOrder.where((s) => s == CaptionSegment.freeText).length;
    if (freeCount > 0) {
      final by = r.freeTextSnippets;
      if (by == null || by.length != freeCount) {
        final list = <String>[];
        for (var i = 0; i < freeCount; i++) {
          if (by != null && i < by.length) {
            list.add(by[i]);
          } else {
            list.add('');
          }
        }
        r = r.copyWith(freeTextSnippets: list);
      }
      final suf = r.freeTextSuffixes;
      if (suf == null || suf.length != freeCount) {
        final list = <String>[];
        for (var i = 0; i < freeCount; i++) {
          if (suf != null && i < suf.length) {
            list.add(suf[i]);
          } else {
            list.add('');
          }
        }
        r = r.copyWith(freeTextSuffixes: list);
      }
    } else if (r.freeTextSnippets != null || r.freeTextSuffixes != null) {
      r = r.copyWith(freeTextSnippets: null, freeTextSuffixes: null);
    }

    return r;
  }

  /// Turns legacy [CaptionSegment.customText] ("Game identifier") slots into
  /// typed [CaptionSegment.freeText] with [gameIdentifierText] filled in.
  CaptionTemplate migrateGameIdentifierToFreeText() {
    if (!segmentOrder.contains(CaptionSegment.customText)) return this;

    final order = List<CaptionSegment>.from(segmentOrder);
    final snippets = List<String>.from(freeTextSnippets ?? const <String>[]);
    final suffixes = List<String>.from(freeTextSuffixes ?? const <String>[]);
    final gid = gameIdentifierText.trim();

    var freeOcc = 0;
    for (var i = 0; i < order.length; i++) {
      if (order[i] == CaptionSegment.freeText) {
        freeOcc++;
        continue;
      }
      if (order[i] != CaptionSegment.customText) continue;
      order[i] = CaptionSegment.freeText;
      while (snippets.length < freeOcc) {
        snippets.add('');
      }
      while (suffixes.length < freeOcc) {
        suffixes.add('');
      }
      snippets.insert(freeOcc, gid);
      suffixes.insert(freeOcc, '');
      freeOcc++;
    }

    return copyWith(
      segmentOrder: order,
      freeTextSnippets: snippets,
      freeTextSuffixes: suffixes,
    );
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
        if (useTeamPossessive == true) 'useTeamPossessive': true,
        if (!americanEnglish) 'americanEnglish': false,
        if (!removeDiacritics) 'removeDiacritics': false,
        'showPersonalityField': showPersonalityField,
        'showKeywordsField': showKeywordsField,
        if (timingPhraseCaps) 'timingPhraseCaps': true,
        if (!includeTimingPhrase) 'includeTimingPhrase': false,
        'separator': separator,
        'creditFormat': creditFormat.name,
        'bylineOptions': bylineOptions.toJson(),
        'segmentOrder': segmentOrder.map((e) => e.name).toList(),
        if (gameIdentifierText.isNotEmpty) 'gameIdentifierText': gameIdentifierText,
        if (captionPrefix.isNotEmpty) 'captionPrefix': captionPrefix,
        if (captionSuffix.isNotEmpty) 'captionSuffix': captionSuffix,
        if (gameIdentifierPrefix.isNotEmpty)
          'gameIdentifierPrefix': gameIdentifierPrefix,
        if (gameIdentifierSuffix != ' ')
          'gameIdentifierSuffix': gameIdentifierSuffix,
        if (customSeparators != null) 'customSeparators': customSeparators,
        if (separatorSnippets != null) 'separatorSnippets': separatorSnippets,
        if (punctuationSnippets != null) 'punctuationSnippets': punctuationSnippets,
        if (freeTextSnippets != null) 'freeTextSnippets': freeTextSnippets,
        if (freeTextSuffixes != null) 'freeTextSuffixes': freeTextSuffixes,
        if (venuePrefix.isNotEmpty) 'venuePrefix': venuePrefix,
        if (venueSuffix.isNotEmpty) 'venueSuffix': venueSuffix,
        if (layoutPrefix.isNotEmpty) 'layoutPrefix': layoutPrefix,
        if (layoutSuffix.isNotEmpty) 'layoutSuffix': layoutSuffix,
        if (basketballUserNote.isNotEmpty)
          'basketballUserNote': basketballUserNote,
        if (locationOptionsByOccurrence != null)
          'locationOptionsByOccurrence': locationOptionsByOccurrence!
              .map((e) => e.toJson())
              .toList(),
        if (dateFormulasByOccurrence != null)
          'dateFormulasByOccurrence': dateFormulasByOccurrence!
              .map((e) => e.toJson())
              .toList(),
        if (monthTokensByOccurrence != null)
          'monthTokensByOccurrence':
              monthTokensByOccurrence!.map((e) => e.toJson()).toList(),
        if (dayTokensByOccurrence != null)
          'dayTokensByOccurrence':
              dayTokensByOccurrence!.map((e) => e.toJson()).toList(),
        if (yearTokensByOccurrence != null)
          'yearTokensByOccurrence':
              yearTokensByOccurrence!.map((e) => e.toJson()).toList(),
        if (weekdayTokensByOccurrence != null)
          'weekdayTokensByOccurrence':
              weekdayTokensByOccurrence!.map((e) => e.toJson()).toList(),
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
      useTeamPossessive: json['useTeamPossessive'] as bool? ??
          (json['wireStyle']?.toString() == 'cp'),
      americanEnglish: json['americanEnglish'] as bool? ?? true,
      removeDiacritics: json['removeDiacritics'] as bool? ?? true,
      showPersonalityField: json['showPersonalityField'] as bool? ?? true,
      showKeywordsField: json['showKeywordsField'] as bool? ?? false,
      timingPhraseCaps: json['timingPhraseCaps'] as bool? ?? false,
      includeTimingPhrase: json['includeTimingPhrase'] as bool? ?? true,
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
      // Legacy default was a single trailing space; treat missing / ' ' as none.
      captionSuffix: () {
        final raw = json['captionSuffix'] as String?;
        if (raw == null || raw == ' ') return '';
        return raw;
      }(),
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
      freeTextSnippets: (json['freeTextSnippets'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      freeTextSuffixes: (json['freeTextSuffixes'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      venuePrefix: json['venuePrefix'] as String? ?? '',
      venueSuffix: json['venueSuffix'] as String? ?? '',
      layoutPrefix: json['layoutPrefix'] as String? ?? '',
      layoutSuffix: json['layoutSuffix'] as String? ?? '',
      basketballUserNote: json['basketballUserNote'] as String? ?? '',
      locationOptionsByOccurrence:
          (json['locationOptionsByOccurrence'] as List<dynamic>?)
              ?.map((e) => LocationLineOptions.fromJson(
                  Map<String, dynamic>.from(e as Map)))
              .toList(),
      dateFormulasByOccurrence: (json['dateFormulasByOccurrence'] as List<dynamic>?)
          ?.map((e) => DateFormula.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
      monthTokensByOccurrence: (json['monthTokensByOccurrence'] as List<dynamic>?)
          ?.map((e) =>
              DateFieldToken.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      dayTokensByOccurrence: (json['dayTokensByOccurrence'] as List<dynamic>?)
          ?.map((e) =>
              DateFieldToken.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      yearTokensByOccurrence: (json['yearTokensByOccurrence'] as List<dynamic>?)
          ?.map((e) =>
              DateFieldToken.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      weekdayTokensByOccurrence:
          (json['weekdayTokensByOccurrence'] as List<dynamic>?)
              ?.map((e) =>
                  DateFieldToken.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList(),
    )
        .expandLocationSegments()
        .expandDateSegments()
        .normalizePerOccurrenceLists();
  }

  /// Resolves the [DateFieldToken] for a date-part occurrence.
  DateFieldToken datePartTokenFor({
    required DateFieldKind kind,
    required int occurrenceIndex,
  }) {
    List<DateFieldToken>? by;
    switch (kind) {
      case DateFieldKind.month:
        by = monthTokensByOccurrence;
        break;
      case DateFieldKind.day:
        by = dayTokensByOccurrence;
        break;
      case DateFieldKind.year:
        by = yearTokensByOccurrence;
        break;
      case DateFieldKind.weekday:
        by = weekdayTokensByOccurrence;
        break;
    }
    if (by != null &&
        occurrenceIndex >= 0 &&
        occurrenceIndex < by.length) {
      return by[occurrenceIndex];
    }
    final formula = dateFormula ?? dateFormulaFromLegacyPattern(dateFormat);
    for (final f in formula.fields) {
      if (f.kind == kind) return f;
    }
    return DateFieldToken(kind: kind);
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

  /// True for user-authored Custom or named library styles — their
  /// [gameIdentifierText] / free-text must not be overwritten by the
  /// per-wire sport overlay used for Getty / Imagn / AP / CP masters.
  bool get isUserAuthoredCaptionStyle =>
      wireStyle == WireStyle.custom ||
      id.startsWith('saved_') ||
      id.startsWith('saved:');

  /// Fills game-id typed free text from [defaultGameIdentifierText] when empty,
  /// or when [replaceKnownDefaults] and the current text is another sport’s default.
  static CaptionTemplate withSportGameIdentifierDefault(
    CaptionTemplate template,
    String? sport, {
    bool replaceKnownDefaults = true,
  }) {
    final next = defaultGameIdentifierText(sport);
    if (next.isEmpty) return template;
    final t = template.migrateGameIdentifierToFreeText();
    final current = t.gameIdentifierText.trim();
    final snippets = t.freeTextSnippets ?? const <String>[];
    final hasReplaceableFree = snippets.any((s) {
      final cur = s.trim();
      return cur.isEmpty || kKnownGameIdentifierDefaults.contains(cur);
    });
    final shouldSet = current.isEmpty ||
        (replaceKnownDefaults &&
            kKnownGameIdentifierDefaults.contains(current)) ||
        (replaceKnownDefaults && hasReplaceableFree);
    if (!shouldSet) return t;
    return applyGameIdentifierText(t, next);
  }

  /// Applies an explicit per-wire-per-sport game identifier into typed free text
  /// (and keeps [gameIdentifierText] in sync for older readers).
  static CaptionTemplate applyGameIdentifierText(
    CaptionTemplate template,
    String gameIdentifierText,
  ) {
    final trimmed = gameIdentifierText.trim();
    if (trimmed.isEmpty) return template;
    var t = template.migrateGameIdentifierToFreeText();
    t = t.copyWith(gameIdentifierText: trimmed);

    final freeCount =
        t.segmentOrder.where((s) => s == CaptionSegment.freeText).length;
    if (freeCount <= 0) return t;

    final snippets = List<String>.from(
      t.freeTextSnippets ?? List<String>.filled(freeCount, ''),
    );
    while (snippets.length < freeCount) {
      snippets.add('');
    }

    var replaced = false;
    for (var i = 0; i < snippets.length; i++) {
      final cur = snippets[i].trim();
      if (cur.isEmpty || kKnownGameIdentifierDefaults.contains(cur)) {
        snippets[i] = trimmed;
        replaced = true;
      }
    }

    if (!replaced) {
      // Prefer the free-text slot right after Caption (typical game-id place).
      final order = t.segmentOrder;
      var freeOcc = 0;
      var target = -1;
      for (var i = 0; i < order.length; i++) {
        if (order[i] != CaptionSegment.freeText) continue;
        final prev = i > 0 ? order[i - 1] : null;
        final prev2 = i > 1 ? order[i - 2] : null;
        if (prev == CaptionSegment.caption ||
            (prev == CaptionSegment.punctuation &&
                prev2 == CaptionSegment.caption)) {
          target = freeOcc;
          break;
        }
        freeOcc++;
      }
      if (target >= 0 && target < snippets.length) {
        snippets[target] = trimmed;
      }
    }

    return t.copyWith(freeTextSnippets: snippets);
  }

  /// Wire layout masters should not store sport-specific game ID text.
  CaptionTemplate stripGameIdentifierForWireMaster() {
    var t = copyWith(gameIdentifierText: '');
    final snippets = t.freeTextSnippets;
    if (snippets == null || snippets.isEmpty) return t;
    final next = <String>[
      for (final s in snippets)
        kKnownGameIdentifierDefaults.contains(s.trim()) ? '' : s,
    ];
    return t.copyWith(freeTextSnippets: next);
  }

  static Map<String, dynamic> wireMasterJsonFromTemplate(CaptionTemplate t) =>
      t.copyWith(wireStyle: t.wireStyle).stripGameIdentifierForWireMaster().toJson();

  /// Migrates from legacy prefs (`game_date`, `body`, …) + `getty` / `imagn` flavor.
  static CaptionTemplate fromLegacySegmentOrder(
    List<String> legacyIds,
    String flavor,
  ) {
    final segments = _parseSegmentOrder(legacyIds);
    final base = flavor == 'imagn' ? CaptionTemplate.imagn() : CaptionTemplate.getty();
    return base
        .copyWith(
          segmentOrder: segments,
          customSeparators: null,
          separatorSnippets: null,
          punctuationSnippets: null,
        )
        .expandLocationSegments()
        .expandDateSegments()
        .normalizePerOccurrenceLists();
  }
}
