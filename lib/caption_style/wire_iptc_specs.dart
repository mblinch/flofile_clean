import 'caption_template.dart';

/// How strongly a wire expects an IPTC field at ingest.
enum IptcFieldLevel { required, recommended, optional }

/// One IPTC field row in the startup wire template checklist.
class WireIptcFieldSpec {
  const WireIptcFieldSpec({
    required this.label,
    required this.iptcTag,
    required this.level,
    this.valueKey,
    this.example,
    this.notes,
  });

  /// Display label in the startup IPTC panel.
  final String label;
  final String iptcTag;
  final IptcFieldLevel level;

  /// Key in the values map (defaults to [label]).
  final String? valueKey;
  final String? example;
  final String? notes;

  String get storageKey => valueKey ?? label;
}

/// Required and recommended IPTC fields per built-in caption wire.
class WireIptcSpecs {
  WireIptcSpecs._();

  static const List<WireStyle> builtInWires = [
    WireStyle.getty,
    WireStyle.gettyInternational,
    WireStyle.imagn,
    WireStyle.ap,
    WireStyle.cp,
  ];

  static String factoryWireLabel(WireStyle wire) {
    switch (wire) {
      case WireStyle.getty:
        return 'Getty USA';
      case WireStyle.gettyInternational:
        return 'Getty International';
      case WireStyle.imagn:
        return 'Imagn';
      case WireStyle.ap:
        return 'AP';
      case WireStyle.cp:
        return 'CP';
      case WireStyle.custom:
        return 'Custom';
    }
  }

  static String displayWireLabel(WireStyle wire, String? customLabel) {
    final trimmed = customLabel?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    return factoryWireLabel(wire);
  }

  static List<WireIptcFieldSpec> fieldsFor(WireStyle wire) {
    switch (wire) {
      case WireStyle.getty:
      case WireStyle.gettyInternational:
        return _gettyFields;
      case WireStyle.imagn:
        return _imagnFields;
      case WireStyle.ap:
        return _apFields;
      case WireStyle.cp:
        return _cpFields;
      case WireStyle.custom:
        return _gettyFields;
    }
  }

  /// Photo Mechanic IPTC panel order (display labels).
  static const List<String> iptcPanelFieldOrder = [
    'Caption',
    'Personality',
    'Description Writers',
    'Headline',
    'MEID',
    'Keywords',
    'Creator',
    "Creator's Identity",
    'Job Title',
    'Copyright',
    'Credit',
    'Source',
    'Time and Date',
    'City',
    'Location',
    'Province/State',
    'Country',
    'Country Code',
    'Object Name',
    'Special Instructions',
    'Category',
    'Supp Cat 1',
    'Supp Cat 2',
    'Supp Cat 3',
    'Urgency',
  ];

  /// Wire fields in [iptcPanelFieldOrder], with levels from the active wire.
  static List<WireIptcFieldSpec> fieldsForPanel(WireStyle wire) {
    final byLabel = {for (final f in fieldsFor(wire)) f.label: f};
    final out = <WireIptcFieldSpec>[];
    for (final panelLabel in iptcPanelFieldOrder) {
      final storageKey =
          panelLabel == 'Location' ? 'Stadium' : panelLabel;
      final wireSpec = byLabel[storageKey];
      if (wireSpec != null) {
        out.add(WireIptcFieldSpec(
          label: panelLabel,
          valueKey: storageKey,
          iptcTag: wireSpec.iptcTag,
          level: wireSpec.level,
          example: wireSpec.example,
          notes: wireSpec.notes,
        ));
      } else {
        out.add(_fallbackPanelSpec(panelLabel, storageKey));
      }
    }
    return out;
  }

  static WireIptcFieldSpec _fallbackPanelSpec(String label, String storageKey) {
    const tags = <String, String>{
      'Caption': 'IPTC:Description',
      'Personality': 'XMP-getty:Personality',
      'Description Writers': 'CaptionWriter',
      'Headline': 'IPTC:Headline',
      'MEID': 'IPTC:OriginalTransmissionReference',
      'Keywords': 'IPTC:Keywords',
      'Creator': 'IPTC:By-line',
      "Creator's Identity": 'XMP:CreatorIdentity',
      'Job Title': 'IPTC:By-lineTitle',
      'Copyright': 'IPTC:CopyrightNotice',
      'Credit': 'IPTC:Credit',
      'Source': 'IPTC:Source',
      'Time and Date': 'DateTimeOriginal',
      'City': 'IPTC:City',
      'Location': 'IPTC:SubLocation',
      'Province/State': 'IPTC:ProvinceState',
      'Country': 'IPTC:CountryPrimaryLocationName',
      'Country Code': 'IPTC:CountryPrimaryLocationCode',
      'Object Name': 'IPTC:ObjectName',
      'Special Instructions': 'IPTC:SpecialInstructions',
      'Category': 'IPTC:Category',
      'Supp Cat 1': 'IPTC:SupplementalCategories',
      'Supp Cat 2': 'IPTC:SupplementalCategories',
      'Supp Cat 3': 'IPTC:SupplementalCategories',
      'Urgency': 'IPTC:Urgency',
    };
    return WireIptcFieldSpec(
      label: label,
      valueKey: storageKey,
      iptcTag: tags[label] ?? label,
      level: IptcFieldLevel.optional,
    );
  }

  static const List<WireIptcFieldSpec> _gettyFields = [
    WireIptcFieldSpec(
      label: 'Creator',
      iptcTag: 'IPTC:By-line',
      level: IptcFieldLevel.required,
      example: 'Mark Blinch',
    ),
    WireIptcFieldSpec(
      label: 'Description Writers',
      iptcTag: 'CaptionWriter',
      level: IptcFieldLevel.required,
      example: 'MB',
      notes: 'Getty / Photo Mechanic caption writer initials',
    ),
    WireIptcFieldSpec(
      label: 'Job Title',
      iptcTag: 'IPTC:By-lineTitle',
      level: IptcFieldLevel.required,
      example: 'Contributor',
    ),
    WireIptcFieldSpec(
      label: 'Copyright',
      iptcTag: 'IPTC:CopyrightNotice',
      level: IptcFieldLevel.required,
      example: '2025 Mark Blinch',
    ),
    WireIptcFieldSpec(
      label: 'Credit',
      iptcTag: 'IPTC:Credit',
      level: IptcFieldLevel.required,
      example: 'Getty Images',
    ),
    WireIptcFieldSpec(
      label: 'Source',
      iptcTag: 'IPTC:Source',
      level: IptcFieldLevel.required,
      example: 'Getty Images North America',
    ),
    WireIptcFieldSpec(
      label: 'MEID',
      iptcTag: 'IPTC:OriginalTransmissionReference',
      level: IptcFieldLevel.required,
      notes: 'Getty job / transmission reference',
    ),
    WireIptcFieldSpec(
      label: 'Category',
      iptcTag: 'IPTC:Category',
      level: IptcFieldLevel.required,
      example: 'SPO',
      notes: 'Sports = SPO',
    ),
    WireIptcFieldSpec(
      label: 'Supp Cat 1',
      iptcTag: 'IPTC:SupplementalCategories',
      level: IptcFieldLevel.required,
      example: 'SPO',
      notes: 'Sport code (slot 1)',
    ),
    WireIptcFieldSpec(
      label: 'Supp Cat 2',
      iptcTag: 'IPTC:SupplementalCategories',
      level: IptcFieldLevel.required,
      example: 'BBN',
      notes: 'League / event code (slot 2)',
    ),
    WireIptcFieldSpec(
      label: 'Supp Cat 3',
      iptcTag: 'IPTC:SupplementalCategories',
      level: IptcFieldLevel.required,
      example: 'BBA',
      notes: 'Assignment code (slot 3)',
    ),
    WireIptcFieldSpec(
      label: 'Stadium',
      iptcTag: 'IPTC:SubLocation',
      level: IptcFieldLevel.required,
      example: 'Rogers Centre',
    ),
    WireIptcFieldSpec(
      label: 'City',
      iptcTag: 'IPTC:City',
      level: IptcFieldLevel.required,
      example: 'Toronto',
    ),
    WireIptcFieldSpec(
      label: 'Province/State',
      iptcTag: 'IPTC:ProvinceState',
      level: IptcFieldLevel.required,
      example: 'Ontario',
    ),
    WireIptcFieldSpec(
      label: 'Country',
      iptcTag: 'IPTC:CountryPrimaryLocationName',
      level: IptcFieldLevel.required,
      example: 'Canada',
    ),
    WireIptcFieldSpec(
      label: 'Country Code',
      iptcTag: 'IPTC:CountryPrimaryLocationCode',
      level: IptcFieldLevel.required,
      example: 'CAN',
    ),
    WireIptcFieldSpec(
      label: 'Headline',
      iptcTag: 'IPTC:Headline',
      level: IptcFieldLevel.recommended,
    ),
    WireIptcFieldSpec(
      label: 'Keywords',
      iptcTag: 'IPTC:Keywords',
      level: IptcFieldLevel.recommended,
      notes: 'Player names, team, event',
    ),
    WireIptcFieldSpec(
      label: 'Personality',
      iptcTag: 'XMP-getty:Personality',
      level: IptcFieldLevel.recommended,
      notes: 'Getty personality / who is in frame',
    ),
    WireIptcFieldSpec(
      label: 'Object Name',
      iptcTag: 'IPTC:ObjectName',
      level: IptcFieldLevel.optional,
    ),
    WireIptcFieldSpec(
      label: 'Special Instructions',
      iptcTag: 'IPTC:SpecialInstructions',
      level: IptcFieldLevel.optional,
    ),
    WireIptcFieldSpec(
      label: 'Caption',
      iptcTag: 'IPTC:Description',
      level: IptcFieldLevel.recommended,
      notes: 'Written in FloFile; saved on export',
    ),
  ];

  static final List<WireIptcFieldSpec> _imagnFields = [
    ..._gettyFields.map((f) {
      if (f.label == 'MEID') {
        return const WireIptcFieldSpec(
          label: 'MEID',
          iptcTag: 'IPTC:OriginalTransmissionReference',
          level: IptcFieldLevel.recommended,
          notes: 'Job reference when supplied by desk',
        );
      }
      if (f.label == 'Source') {
        return const WireIptcFieldSpec(
          label: 'Source',
          iptcTag: 'IPTC:Source',
          level: IptcFieldLevel.required,
          example: 'Imagn Images',
        );
      }
      if (f.label == 'Credit') {
        return const WireIptcFieldSpec(
          label: 'Credit',
          iptcTag: 'IPTC:Credit',
          level: IptcFieldLevel.required,
          example: 'Imagn Images',
        );
      }
      if (f.label == 'Personality') {
        return const WireIptcFieldSpec(
          label: 'Personality',
          iptcTag: 'XMP:Personality',
          level: IptcFieldLevel.optional,
        );
      }
      return f;
    }),
  ];

  static const List<WireIptcFieldSpec> _apFields = [
    WireIptcFieldSpec(
      label: 'Creator',
      iptcTag: 'IPTC:By-line',
      level: IptcFieldLevel.required,
      example: 'Mark Blinch',
      notes: 'Photographer name',
    ),
    WireIptcFieldSpec(
      label: 'Credit',
      iptcTag: 'IPTC:Credit',
      level: IptcFieldLevel.required,
      example: 'The Canadian Press',
      notes: 'Credit line as transmitted',
    ),
    WireIptcFieldSpec(
      label: 'Source',
      iptcTag: 'IPTC:Source',
      level: IptcFieldLevel.required,
      example: 'AP',
    ),
    WireIptcFieldSpec(
      label: 'Headline',
      iptcTag: 'IPTC:Headline',
      level: IptcFieldLevel.required,
    ),
    WireIptcFieldSpec(
      label: 'Caption',
      iptcTag: 'IPTC:Description',
      level: IptcFieldLevel.required,
      notes: 'AP-style caption body',
    ),
    WireIptcFieldSpec(
      label: 'Category',
      iptcTag: 'IPTC:Category',
      level: IptcFieldLevel.required,
      example: 'SPT',
    ),
    WireIptcFieldSpec(
      label: 'Supp Cat 1',
      iptcTag: 'IPTC:SupplementalCategories',
      level: IptcFieldLevel.recommended,
      notes: 'Sport / desk codes',
    ),
    WireIptcFieldSpec(
      label: 'Supp Cat 2',
      iptcTag: 'IPTC:SupplementalCategories',
      level: IptcFieldLevel.recommended,
    ),
    WireIptcFieldSpec(
      label: 'Supp Cat 3',
      iptcTag: 'IPTC:SupplementalCategories',
      level: IptcFieldLevel.recommended,
    ),
    WireIptcFieldSpec(
      label: 'City',
      iptcTag: 'IPTC:City',
      level: IptcFieldLevel.required,
    ),
    WireIptcFieldSpec(
      label: 'Province/State',
      iptcTag: 'IPTC:ProvinceState',
      level: IptcFieldLevel.required,
      notes: 'AP state abbreviation when US',
    ),
    WireIptcFieldSpec(
      label: 'Country',
      iptcTag: 'IPTC:CountryPrimaryLocationName',
      level: IptcFieldLevel.required,
    ),
    WireIptcFieldSpec(
      label: 'Country Code',
      iptcTag: 'IPTC:CountryPrimaryLocationCode',
      level: IptcFieldLevel.required,
      example: 'USA',
    ),
    WireIptcFieldSpec(
      label: 'Stadium',
      iptcTag: 'IPTC:SubLocation',
      level: IptcFieldLevel.recommended,
    ),
    WireIptcFieldSpec(
      label: 'Keywords',
      iptcTag: 'IPTC:Keywords',
      level: IptcFieldLevel.recommended,
    ),
    WireIptcFieldSpec(
      label: 'Copyright',
      iptcTag: 'IPTC:CopyrightNotice',
      level: IptcFieldLevel.optional,
    ),
    WireIptcFieldSpec(
      label: 'Special Instructions',
      iptcTag: 'IPTC:SpecialInstructions',
      level: IptcFieldLevel.optional,
    ),
  ];

  static final List<WireIptcFieldSpec> _cpFields = [
    ..._apFields.map((f) {
      if (f.label == 'Source') {
        return const WireIptcFieldSpec(
          label: 'Source',
          iptcTag: 'IPTC:Source',
          level: IptcFieldLevel.required,
          example: 'The Canadian Press',
        );
      }
      if (f.label == 'Credit') {
        return const WireIptcFieldSpec(
          label: 'Credit',
          iptcTag: 'IPTC:Credit',
          level: IptcFieldLevel.required,
          example: 'The Canadian Press',
        );
      }
      if (f.label == 'Country') {
        return const WireIptcFieldSpec(
          label: 'Country',
          iptcTag: 'IPTC:CountryPrimaryLocationName',
          level: IptcFieldLevel.required,
          example: 'Canada',
        );
      }
      if (f.label == 'Country Code') {
        return const WireIptcFieldSpec(
          label: 'Country Code',
          iptcTag: 'IPTC:CountryPrimaryLocationCode',
          level: IptcFieldLevel.required,
          example: 'CAN',
        );
      }
      return f;
    }),
  ];
}
