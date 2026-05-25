import 'dart:convert';

import 'caption_formula_renderer.dart';
import 'caption_template.dart';
import '../services/preferences_service.dart';

/// One entry in the caption-style picker (built-in wire or saved library row).
class CaptionStyleOption {
  const CaptionStyleOption({required this.token, required this.label});

  final String token;
  final String label;
}

/// Loads caption-style menu options and resolves a menu token to a template.
class CaptionStyleCatalog {
  CaptionStyleCatalog._({
    required this.options,
    required this.activeToken,
    required this.sport,
    required this.gettyWireDefault,
    required this.imagnWireDefault,
    required this.apWireDefault,
    required this.gettyIntlWireDefault,
    required this.library,
    required this.wireLabelGetty,
    required this.wireLabelImagn,
    required this.wireLabelAp,
    required this.wireLabelGettyIntl,
  });

  static const String tokGetty = 'wire:getty';
  static const String tokImagn = 'wire:imagn';
  static const String tokAp = 'wire:ap';
  static const String tokGettyIntl = 'wire:getty_international';
  static const String tokCustom = 'wire:custom';

  final List<CaptionStyleOption> options;
  final String activeToken;
  final String sport;
  final CaptionTemplate? gettyWireDefault;
  final CaptionTemplate? imagnWireDefault;
  final CaptionTemplate? apWireDefault;
  final CaptionTemplate? gettyIntlWireDefault;
  final List<CaptionStyleLibraryEntry> library;
  final String? wireLabelGetty;
  final String? wireLabelImagn;
  final String? wireLabelAp;
  final String? wireLabelGettyIntl;

  String labelFor(String token) {
    for (final o in options) {
      if (o.token == token) return o.label;
    }
    return token;
  }

  static Future<CaptionStyleCatalog> load(
    PreferencesService prefs, {
    String? sport,
  }) async {
    final resolvedSport =
        (sport ?? await prefs.getCurrentSport()).toLowerCase().trim();
    if (resolvedSport.isNotEmpty) {
      await prefs.saveCurrentSport(resolvedSport);
    }

    final gettyDef = await prefs.getCaptionTemplateWireDefault(WireStyle.getty);
    final imagnDef = await prefs.getCaptionTemplateWireDefault(WireStyle.imagn);
    final apDef = await prefs.getCaptionTemplateWireDefault(WireStyle.ap);
    final gettyIntlDef =
        await prefs.getCaptionTemplateWireDefault(WireStyle.gettyInternational);
    final lib = await prefs.getCaptionStyleLibrary();
    final active = await prefs.getCaptionTemplate();

    final gettyLabel = await prefs.getCaptionWireLabel(WireStyle.getty);
    final imagnLabel = await prefs.getCaptionWireLabel(WireStyle.imagn);
    final apLabel = await prefs.getCaptionWireLabel(WireStyle.ap);
    final gettyIntlLabel =
        await prefs.getCaptionWireLabel(WireStyle.gettyInternational);

    final catalog = CaptionStyleCatalog._(
      options: const [],
      activeToken: tokGetty,
      sport: resolvedSport.isEmpty ? 'baseball' : resolvedSport,
      gettyWireDefault: gettyDef,
      imagnWireDefault: imagnDef,
      apWireDefault: apDef,
      gettyIntlWireDefault: gettyIntlDef,
      library: lib,
      wireLabelGetty: gettyLabel,
      wireLabelImagn: imagnLabel,
      wireLabelAp: apLabel,
      wireLabelGettyIntl: gettyIntlLabel,
    );

    final tokens = <String>[
      tokGetty,
      tokImagn,
      tokAp,
      tokGettyIntl,
      tokCustom,
      ...lib.map((e) => 'saved:${e.id}'),
    ];
    final options = tokens
        .map((t) => CaptionStyleOption(token: t, label: catalog._menuLabel(t)))
        .toList()
      ..sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
    final activeToken = catalog._tokenForTemplate(active, lib);

    return CaptionStyleCatalog._(
      options: options,
      activeToken: activeToken,
      sport: catalog.sport,
      gettyWireDefault: gettyDef,
      imagnWireDefault: imagnDef,
      apWireDefault: apDef,
      gettyIntlWireDefault: gettyIntlDef,
      library: lib,
      wireLabelGetty: gettyLabel,
      wireLabelImagn: imagnLabel,
      wireLabelAp: apLabel,
      wireLabelGettyIntl: gettyIntlLabel,
    );
  }

  /// Resolves [token] to a full template (sport game-identifier defaults applied).
  CaptionTemplate resolve(
    String token, {
    CaptionTemplate? refForCustom,
  }) {
    if (token.startsWith('saved:')) {
      final id = token.substring(6);
      for (final e in library) {
        if (e.id == id) {
          return _withSport(_deepCopy(e.template));
        }
      }
      return _withSport(CaptionTemplate.getty());
    }

    final wire = _wireFromToken(token);
    switch (wire) {
      case WireStyle.getty:
      case WireStyle.gettyInternational:
      case WireStyle.imagn:
      case WireStyle.ap:
        return _withSport(_wiredBaseline(wire));
      case WireStyle.custom:
        final ref = refForCustom ?? CaptionTemplate.getty();
        return _withSport(
          CaptionTemplate.custom(
            dateFormat: ref.dateFormat,
            dateExpression: ref.dateExpression,
            dateFormula: ref.dateFormula?.clone(),
            dateFormulasByOccurrence:
                ref.dateFormulasByOccurrence?.map((e) => e.clone()).toList(),
            locationOptions: ref.locationOptions,
            locationOptionsByOccurrence: ref.locationOptionsByOccurrence
                ?.map((e) => e.clone())
                .toList(),
            numberFormat: ref.numberFormat,
            captionTeamOrder: ref.captionTeamOrder,
            includePlayerPosition: ref.includePlayerPosition,
            americanEnglish: ref.americanEnglish,
            removeDiacritics: ref.removeDiacritics,
            showPersonalityField: ref.showPersonalityField,
            showKeywordsField: ref.showKeywordsField,
            separator: ref.separator,
            creditFormat: ref.creditFormat,
            bylineOptions: ref.bylineOptions,
            segmentOrder: List<CaptionSegment>.from(ref.segmentOrder),
            customSeparators: List<String>.from(
              CaptionFormulaRenderer.defaultCustomGaps(ref),
            ),
            separatorSnippets: ref.separatorSnippets != null
                ? List<String>.from(ref.separatorSnippets!)
                : null,
            punctuationSnippets: ref.punctuationSnippets != null
                ? List<String>.from(ref.punctuationSnippets!)
                : null,
            gameIdentifierText: ref.gameIdentifierText,
          ),
        );
    }
  }

  CaptionTemplate _withSport(CaptionTemplate t) =>
      CaptionTemplate.withSportGameIdentifierDefault(t, sport);

  CaptionTemplate _wiredBaseline(WireStyle wire) {
    CaptionTemplate apply(CaptionTemplate? saved, CaptionTemplate factory) {
      final base = saved == null
          ? factory
          : (!_hasSnippetLayout(saved)
              ? _migrateSnippetLayout(saved, factory)
              : saved);
      return _withSport(base);
    }

    switch (wire) {
      case WireStyle.getty:
        return apply(gettyWireDefault, CaptionTemplate.getty());
      case WireStyle.imagn:
        return apply(imagnWireDefault, CaptionTemplate.imagn());
      case WireStyle.ap:
        return apply(apWireDefault, CaptionTemplate.ap());
      case WireStyle.gettyInternational:
        return apply(gettyIntlWireDefault, CaptionTemplate.gettyInternational());
      case WireStyle.custom:
        return apply(gettyWireDefault, CaptionTemplate.getty());
    }
  }

  static bool _hasSnippetLayout(CaptionTemplate t) =>
      t.segmentOrder.contains(CaptionSegment.punctuation) ||
      t.segmentOrder.contains(CaptionSegment.separator);

  static CaptionTemplate _migrateSnippetLayout(
    CaptionTemplate saved,
    CaptionTemplate factory,
  ) {
    return saved
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
        )
        .normalizePerOccurrenceLists();
  }

  static CaptionTemplate _deepCopy(CaptionTemplate t) {
    final raw = json.decode(json.encode(t.toJson())) as Map<String, dynamic>;
    return CaptionTemplate.fromJson(raw);
  }

  String _menuLabel(String token) {
    if (token.startsWith('saved:')) {
      final id = token.substring(6);
      for (final e in library) {
        if (e.id == id) return e.displayName;
      }
      return 'Saved style';
    }
    switch (token) {
      case tokGetty:
        return _wireLabel(WireStyle.getty, 'Getty USA');
      case tokImagn:
        return _wireLabel(WireStyle.imagn, 'Imagn');
      case tokAp:
        return _wireLabel(WireStyle.ap, 'AP');
      case tokGettyIntl:
        return _wireLabel(WireStyle.gettyInternational, 'Getty International');
      case tokCustom:
        return 'Custom';
      default:
        return token;
    }
  }

  String _wireLabel(WireStyle wire, String factoryName) {
    String? override;
    switch (wire) {
      case WireStyle.getty:
        override = wireLabelGetty;
        break;
      case WireStyle.imagn:
        override = wireLabelImagn;
        break;
      case WireStyle.ap:
        override = wireLabelAp;
        break;
      case WireStyle.gettyInternational:
        override = wireLabelGettyIntl;
        break;
      case WireStyle.custom:
        override = null;
        break;
    }
    if (override != null && override.trim().isNotEmpty) return override.trim();
    return factoryName;
  }

  String _tokenForTemplate(
    CaptionTemplate template,
    List<CaptionStyleLibraryEntry> lib,
  ) {
    for (final e in lib) {
      if (e.id == template.id) return 'saved:${e.id}';
      if (e.template.id == template.id) return 'saved:${e.id}';
    }
    final norm = template.normalizePerOccurrenceLists();
    final snap = jsonEncode(norm.toJson());
    for (final e in lib) {
      final eNorm = e.template.normalizePerOccurrenceLists();
      if (jsonEncode(eNorm.toJson()) == snap) return 'saved:${e.id}';
    }
    return _wireToken(template.wireStyle);
  }

  static String _wireToken(WireStyle w) {
    switch (w) {
      case WireStyle.getty:
        return tokGetty;
      case WireStyle.imagn:
        return tokImagn;
      case WireStyle.ap:
        return tokAp;
      case WireStyle.gettyInternational:
        return tokGettyIntl;
      case WireStyle.custom:
        return tokCustom;
    }
  }

  static WireStyle _wireFromToken(String token) {
    switch (token) {
      case tokImagn:
        return WireStyle.imagn;
      case tokAp:
        return WireStyle.ap;
      case tokGettyIntl:
        return WireStyle.gettyInternational;
      case tokCustom:
        return WireStyle.custom;
      case tokGetty:
      default:
        return WireStyle.getty;
    }
  }
}
