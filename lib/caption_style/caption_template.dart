import 'dart:convert';

import 'date_formula.dart';

/// Wire service preset or fully custom formula.
enum WireStyle { getty, imagn, ap, custom }

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
}

String locationRegionVariantLabel(LocationRegionVariant v) {
  switch (v) {
    case LocationRegionVariant.fullName:
      return 'Full State/Province Name';
    case LocationRegionVariant.shortForm:
      return 'Short Form';
  }
}

LocationRegionVariant locationRegionVariantFromJson(String? s) {
  if (s == LocationRegionVariant.shortForm.name) {
    return LocationRegionVariant.shortForm;
  }
  return LocationRegionVariant.fullName;
}

class LocationChip {
  const LocationChip({
    required this.id,
    required this.kind,
    this.literal = '',
    this.caps = false,
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
  /// When [kind] is [LocationChipKind.country]: use [GameInfo.country] vs [GameInfo.countryCode].
  final LocationCountryVariant countryVariant;
  /// When [kind] is [LocationChipKind.region]: full name vs short ([GameInfo.resolvedRegionShort]).
  final LocationRegionVariant regionVariant;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        if (kind == LocationChipKind.literal) 'literal': literal,
        if (caps) 'caps': true,
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
      literal: kind == LocationChipKind.literal ? (j['literal'] as String? ?? '') : '',
      caps: j['caps'] as bool? ?? false,
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
    LocationCountryVariant? countryVariant,
    LocationRegionVariant? regionVariant,
  }) =>
      LocationChip(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        literal: literal ?? this.literal,
        caps: caps ?? this.caps,
        countryVariant: countryVariant ?? this.countryVariant,
        regionVariant: regionVariant ?? this.regionVariant,
      );
}

/// Ordered draggable chips for the static location line + ALL CAPS flag.
class LocationLineOptions {
  const LocationLineOptions({
    required this.uppercase,
    required this.chips,
  });

  final bool uppercase;
  final List<LocationChip> chips;

  LocationLineOptions copyWith({
    bool? uppercase,
    List<LocationChip>? chips,
  }) =>
      LocationLineOptions(
        uppercase: uppercase ?? this.uppercase,
        chips: chips ?? List<LocationChip>.from(this.chips),
      );

  Map<String, dynamic> toJson() => {
        'uppercase': uppercase,
        'locationChips': chips.map((e) => e.toJson()).toList(),
      };

  factory LocationLineOptions.fromJson(Map<String, dynamic> j) {
    if (j['locationChips'] is List) {
      final raw = j['locationChips'] as List<dynamic>;
      final parsed = raw
          .map((e) => LocationChip.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final uppercase = j['uppercase'] as bool? ?? false;
      if (parsed.isEmpty) {
        return LocationLineOptions(
          uppercase: uppercase,
          chips: LocationLineOptions.imagnDefault().chips,
        );
      }
      // Migrate legacy global uppercase → per-chip caps, so once migrated the
      // per-chip toggles remain the source of truth.
      final anyChipCaps = parsed.any((c) => c.caps);
      if (uppercase && !anyChipCaps) {
        final migrated = parsed
            .map((c) => c.kind == LocationChipKind.literal
                ? c
                : c.copyWith(caps: true))
            .toList();
        return LocationLineOptions(uppercase: false, chips: migrated);
      }
      // Legacy: uppercase + per-chip caps meant whole-line upper still ran and
      // ignored Aa toggles; per-chip caps are the only source of truth now.
      if (uppercase && anyChipCaps) {
        return LocationLineOptions(uppercase: false, chips: parsed);
      }
      return LocationLineOptions(uppercase: uppercase, chips: parsed);
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
        chips.add(LocationChip(id: nid('lit'), kind: LocationChipKind.literal, literal: sep));
      }
      chips.add(LocationChip(id: nid(geo[i].name), kind: geo[i], literal: ''));
    }
    if (chips.isEmpty) {
      chips.add(LocationChip(id: nid('city'), kind: LocationChipKind.city, literal: ''));
    }
    return LocationLineOptions(uppercase: uppercase, chips: chips);
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
          const LocationChip(id: 'g_city', kind: LocationChipKind.city, caps: true),
          const LocationChip(id: 'g_lit1', kind: LocationChipKind.literal, literal: ', '),
          const LocationChip(id: 'g_reg', kind: LocationChipKind.region, caps: true),
        ],
      );

  static LocationLineOptions imagnDefault() => LocationLineOptions(
        uppercase: false,
        chips: [
          const LocationChip(id: 'i_city', kind: LocationChipKind.city),
          const LocationChip(id: 'i_lit1', kind: LocationChipKind.literal, literal: ', '),
          const LocationChip(id: 'i_reg', kind: LocationChipKind.region),
          const LocationChip(id: 'i_lit2', kind: LocationChipKind.literal, literal: ', '),
          const LocationChip(id: 'i_ctr', kind: LocationChipKind.country),
        ],
      );

  static LocationLineOptions apDefault() => LocationLineOptions(
        uppercase: false,
        chips: [
          const LocationChip(id: 'a_city', kind: LocationChipKind.city),
          const LocationChip(id: 'a_lit1', kind: LocationChipKind.literal, literal: ', '),
          const LocationChip(id: 'a_reg', kind: LocationChipKind.region),
        ],
      );
}

/// Jersey / roster number style in the dynamic caption sample.
enum NumberFormatStyle { hash, parens }

/// How the closing credit is phrased.
enum CreditFormat { photo_by, mandatory_credit }

/// Ordered segments: static frame + dynamic caption slot + static tail.
enum CaptionSegment { location, date, caption, venue, credit }

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
    required this.separator,
    required this.creditFormat,
    required this.segmentOrder,
    this.customSeparators,
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
  /// Which [DateTime] feeds [dateFormula]: embedded photo EXIF vs template date.
  final DateFormulaSource dateFormulaSource;
  /// Which location fields appear and whether the line is uppercased.
  final LocationLineOptions locationOptions;
  final NumberFormatStyle numberFormat;
  /// Primary joiner used in [WireStyle.custom] between segments.
  final String separator;
  final CreditFormat creditFormat;
  final List<CaptionSegment> segmentOrder;
  /// When [wireStyle] is [WireStyle.custom]: text between consecutive segments;
  /// length must be [segmentOrder.length - 1] when set.
  final List<String>? customSeparators;

  static const List<CaptionSegment> defaultSegmentOrder = [
    CaptionSegment.location,
    CaptionSegment.date,
    CaptionSegment.caption,
    CaptionSegment.venue,
    CaptionSegment.credit,
  ];

  factory CaptionTemplate.getty() => CaptionTemplate(
        id: 'preset_getty',
        name: 'Getty Images',
        wireStyle: WireStyle.getty,
        dateFormat: 'MMMM d, yyyy',
        dateExpression: '',
        locationOptions: LocationLineOptions.fromLegacyFormat(LocationFormat.city_state_country),
        numberFormat: NumberFormatStyle.hash,
        separator: ' - ',
        creditFormat: CreditFormat.photo_by,
        segmentOrder: const [
          CaptionSegment.location,
          CaptionSegment.date,
          CaptionSegment.caption,
          CaptionSegment.venue,
          CaptionSegment.credit,
        ],
      );

  factory CaptionTemplate.imagn() => CaptionTemplate(
        id: 'preset_imagn',
        name: 'Imagn',
        wireStyle: WireStyle.imagn,
        dateFormat: 'MMM d, yyyy',
        dateExpression: '',
        locationOptions: LocationLineOptions.fromLegacyFormat(LocationFormat.city_region_country),
        numberFormat: NumberFormatStyle.parens,
        separator: '; ',
        creditFormat: CreditFormat.mandatory_credit,
        segmentOrder: const [
          CaptionSegment.date,
          CaptionSegment.location,
          CaptionSegment.caption,
          CaptionSegment.venue,
          CaptionSegment.credit,
        ],
      );

  factory CaptionTemplate.ap() => CaptionTemplate(
        id: 'preset_ap',
        name: 'Associated Press',
        wireStyle: WireStyle.ap,
        dateFormat: 'MMM d, yyyy',
        dateExpression: '',
        locationOptions: LocationLineOptions.fromLegacyFormat(LocationFormat.city_region),
        numberFormat: NumberFormatStyle.parens,
        separator: ' — ',
        creditFormat: CreditFormat.photo_by,
        segmentOrder: const [
          CaptionSegment.location,
          CaptionSegment.date,
          CaptionSegment.caption,
          CaptionSegment.venue,
          CaptionSegment.credit,
        ],
      );

  factory CaptionTemplate.custom({
    String id = 'custom',
    String name = 'Custom',
    String dateFormat = 'MMMM d, yyyy',
    String dateExpression = '',
    LocationLineOptions? locationOptions,
    NumberFormatStyle numberFormat = NumberFormatStyle.parens,
    String separator = '; ',
    CreditFormat creditFormat = CreditFormat.mandatory_credit,
    List<CaptionSegment>? segmentOrder,
    List<String>? customSeparators,
  }) =>
      CaptionTemplate(
        id: id,
        name: name,
        wireStyle: WireStyle.custom,
        dateFormat: dateFormat,
        dateExpression: dateExpression,
        locationOptions: locationOptions ??
            LocationLineOptions.fromLegacyFormat(LocationFormat.city_region_country),
        numberFormat: numberFormat,
        separator: separator,
        creditFormat: creditFormat,
        segmentOrder: segmentOrder ?? List<CaptionSegment>.from(defaultSegmentOrder),
        customSeparators: customSeparators,
      );

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
    String? separator,
    CreditFormat? creditFormat,
    List<CaptionSegment>? segmentOrder,
    List<String>? customSeparators,
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
        separator: separator ?? this.separator,
        creditFormat: creditFormat ?? this.creditFormat,
        segmentOrder: segmentOrder ?? List<CaptionSegment>.from(this.segmentOrder),
        customSeparators: customSeparators ?? this.customSeparators,
      );

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
        'separator': separator,
        'creditFormat': creditFormat.name,
        'segmentOrder': segmentOrder.map((e) => e.name).toList(),
        if (customSeparators != null) 'customSeparators': customSeparators,
      };

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
          ? DateFormula.fromJson(Map<String, dynamic>.from(json['dateFormula'] as Map))
          : null,
      dateFormulaSource: dateFormulaSourceFromString(json['dateFormulaSource'] as String?),
      locationOptions: _parseLocationOptions(json),
      numberFormat: NumberFormatStyle.values.firstWhere(
        (e) => e.name == json['numberFormat'],
        orElse: () => NumberFormatStyle.parens,
      ),
      separator: json['separator'] as String? ?? '; ',
      creditFormat: CreditFormat.values.firstWhere(
        (e) => e.name == json['creditFormat'],
        orElse: () => CreditFormat.mandatory_credit,
      ),
      segmentOrder: _parseSegmentOrder(json['segmentOrder']),
      customSeparators: (json['customSeparators'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
    );
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
    return LocationLineOptions.fromLegacyFormat(LocationFormat.city_region_country);
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
    if (out.length != CaptionSegment.values.length) {
      return List<CaptionSegment>.from(defaultSegmentOrder);
    }
    if (out.toSet().length != CaptionSegment.values.length) {
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

  /// Migrates from legacy prefs (`game_date`, `body`, …) + `getty` / `imagn` flavor.
  static CaptionTemplate fromLegacySegmentOrder(
    List<String> legacyIds,
    String flavor,
  ) {
    final segments = _parseSegmentOrder(legacyIds);
    if (flavor == 'imagn') {
      return CaptionTemplate.imagn().copyWith(segmentOrder: segments);
    }
    return CaptionTemplate.getty().copyWith(segmentOrder: segments);
  }
}
