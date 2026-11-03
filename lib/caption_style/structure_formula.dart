import 'caption_template.dart';
import 'date_formula.dart';

/// Keys used by the structure formula editor (HTML-compatible).
class StructureFormulaKeys {
  StructureFormulaKeys._();

  static const dlCity = 'dl_city';
  static const dlState = 'dl_state';
  static const dlCountry = 'dl_country';
  static const dlCountryCode = 'dl_country_code';
  static const dlMonth = 'dl_month';
  static const dlDay = 'dl_day';
  static const dlWeekday = 'dl_weekday';
  static const caption = 'caption';
  static const league = 'league';
  /// Start-screen sport phrase ("in their NBA game", …). Not wire-master text.
  static const gameId = 'game_id';
  /// Structure variable for IPTC Location (SubLocation). Legacy alias: [venue].
  static const location = 'location';
  /// Legacy formula key; prefer [location].
  static const venue = 'venue';
  static const month = 'month';
  static const day = 'day';
  static const year = 'year';
  /// Weekday name derived from the photo / session date (not a separate IPTC field).
  static const weekday = 'weekday';
  static const city = 'city';
  static const state = 'state';
  /// Country from IPTC Country / CountryPrimaryLocationName.
  static const country = 'country';
  /// ISO country code from [GameInfo.resolvedCountryCode].
  static const countryCode = 'country_code';
  /// Photographer name (IPTC Creator).
  static const name = 'name';
  /// Agency / credit (IPTC Credit).
  static const credit = 'credit';
  /// Legacy full byline segment (Photo by …). Prefer [name] / [credit].
  static const byline = 'byline';

  /// Caps dateline fields (CITY / STATE / COUNTRY / COUNTRY CODE / MONTH / DAY / WEEKDAY).
  static const dateline = <String>[
    dlCity,
    dlState,
    dlCountry,
    dlCountryCode,
    dlMonth,
    dlDay,
    dlWeekday,
  ];

  /// Palette: date pieces.
  static const date = <String>[weekday, month, day, year];

  /// Palette: place pieces + IPTC Location.
  static const locationGroup = <String>[
    city,
    state,
    country,
    countryCode,
    location,
  ];

  /// Palette: byline pieces from IPTC Creator / Credit.
  /// Caption is always in the structure and is not offered as an insert chip.
  static const bylineGroup = <String>[name, credit];

  /// Palette: start-screen variations (sport fills these in).
  static const startScreenGroup = <String>[gameId];

  /// @Deprecated Use [bylineGroup].
  static const game = bylineGroup;

  static bool isDateline(String key) => dateline.contains(key);
  static bool isCaption(String key) => key == caption;
  static bool isGameId(String key) => key == gameId;

  /// Month variable (`{month}` / `{dl_month}`) — supports format optionIndex.
  static bool isMonth(String key) => key == month || key == dlMonth;

  /// Weekday variable (`{weekday}` / `{dl_weekday}`) — supports format optionIndex.
  static bool isWeekday(String key) => key == weekday || key == dlWeekday;

  /// Date part with Long/Short (etc.) format options on Structure chips.
  static DateFieldKind? formatKindFor(String key) {
    if (isMonth(key)) return DateFieldKind.month;
    if (isWeekday(key)) return DateFieldKind.weekday;
    return null;
  }

  /// Whether this variable can toggle ALL CAPS.
  static bool supportsCaps(String key) {
    switch (key) {
      case dlCity:
      case city:
      case dlState:
      case state:
      case dlCountry:
      case country:
      case dlCountryCode:
      case countryCode:
      case dlMonth:
      case month:
      case dlDay:
      case day:
      case dlWeekday:
      case weekday:
        return true;
      default:
        return false;
    }
  }

  static bool isCaps(String key) => isDateline(key);

  /// Map a caps-capable key to its caps / sentence-case twin.
  static String withCaps(String key, bool caps) {
    switch (key) {
      case dlCity:
      case city:
        return caps ? dlCity : city;
      case dlState:
      case state:
        return caps ? dlState : state;
      case dlCountry:
      case country:
        return caps ? dlCountry : country;
      case dlCountryCode:
      case countryCode:
        return caps ? dlCountryCode : countryCode;
      case dlMonth:
      case month:
        return caps ? dlMonth : month;
      case dlDay:
      case day:
        return caps ? dlDay : day;
      case dlWeekday:
      case weekday:
        return caps ? dlWeekday : weekday;
      default:
        return key;
    }
  }

  static String label(String key) {
    switch (key) {
      case dlCity:
        return 'CITY';
      case dlState:
        return 'STATE/PROVINCE';
      case dlCountry:
        return 'COUNTRY';
      case dlCountryCode:
        return 'COUNTRY CODE';
      case dlMonth:
        return 'MONTH';
      case dlDay:
        return 'DAY';
      case dlWeekday:
        return 'WEEKDAY';
      case caption:
        return 'App-Generated Caption';
      case gameId:
        return 'Game ID';
      case location:
      case venue:
        return 'Location';
      case month:
        return 'Month';
      case day:
        return 'Day';
      case year:
        return 'Year';
      case weekday:
        return 'Weekday';
      case city:
        return 'City';
      case state:
        return 'State/Province';
      case country:
        return 'Country';
      case countryCode:
        return 'Country code';
      case name:
        return 'Name';
      case credit:
        return 'Credit';
      case byline:
        return 'Byline';
      default:
        return key;
    }
  }

  /// IPTC panel storage key this structure chip reads from, if any.
  ///
  /// Date parts map to Camera time (EXIF / IPTC date). Caption is the IPTC
  /// Caption field (often app-generated). Returns null when there is no
  /// matching IPTC panel row.
  static String? iptcPanelKey(String key) {
    switch (key) {
      case dlCity:
      case city:
        return 'City';
      case dlState:
      case state:
        return 'Province/State';
      case dlCountry:
      case country:
        return 'Country';
      case dlCountryCode:
      case countryCode:
        return 'Country Code';
      case location:
      case venue:
        return 'Location';
      case name:
        return 'Creator';
      case credit:
        return 'Credit';
      case byline:
        return 'Credit';
      case caption:
        return 'Caption';
      case dlMonth:
      case month:
      case dlDay:
      case day:
      case year:
      case dlWeekday:
      case weekday:
        return 'Camera time';
      default:
        return null;
    }
  }

  static CaptionSegment? segmentFor(String key) {
    switch (key) {
      case dlCity:
      case city:
        return CaptionSegment.city;
      case dlState:
      case state:
        return CaptionSegment.state;
      case dlCountry:
      case country:
        return CaptionSegment.country;
      case dlCountryCode:
      case countryCode:
        return CaptionSegment.countryCode;
      case dlMonth:
      case month:
        return CaptionSegment.month;
      case dlDay:
      case day:
        return CaptionSegment.day;
      case year:
        return CaptionSegment.year;
      case dlWeekday:
      case weekday:
        return CaptionSegment.weekday;
      case caption:
        return CaptionSegment.caption;
      case location:
      case venue:
        return CaptionSegment.venue;
      case name:
        return CaptionSegment.creator;
      case credit:
        return CaptionSegment.agency;
      case byline:
        return CaptionSegment.credit;
      default:
        return null;
    }
  }
}

/// One node in a structure formula: literal text or a variable key.
sealed class StructureFormulaNode {
  const StructureFormulaNode();
}

class StructureLiteralNode extends StructureFormulaNode {
  const StructureLiteralNode(this.text);
  final String text;
}

class StructureVariableNode extends StructureFormulaNode {
  const StructureVariableNode(this.key);
  final String key;
}

/// Parse / serialize `{key}` formulas and map them to [CaptionTemplate].
class StructureFormula {
  StructureFormula._();

  static final RegExp _tokenRe = RegExp(r'\{([a-z_]+)\}');
  static final RegExp _captionTokenRe = RegExp(r'\{caption\}');

  /// Caption is permanent — re-insert at the start if the formula lost it.
  static String ensureCaption(String formula) {
    if (_captionTokenRe.hasMatch(formula)) return formula;
    final trimmed = formula.trimLeft();
    if (trimmed.isEmpty) return '{caption}';
    return '{caption} $trimmed';
  }

  static List<StructureFormulaNode> parse(String formula, {String? sport}) {
    final out = <StructureFormulaNode>[];
    var i = 0;
    for (final m in _tokenRe.allMatches(formula)) {
      if (m.start > i) {
        out.add(StructureLiteralNode(formula.substring(i, m.start)));
      }
      final key = m.group(1)!;
      if (key == StructureFormulaKeys.league) {
        // Legacy `{league}` → plain abbrev text (no longer a structure variable).
        out.add(StructureLiteralNode(leagueAbbrevForSport(sport)));
      } else if (key == StructureFormulaKeys.gameId ||
          StructureFormulaKeys.segmentFor(key) != null) {
        out.add(StructureVariableNode(key));
      } else {
        out.add(StructureLiteralNode(m.group(0)!));
      }
      i = m.end;
    }
    if (i < formula.length) {
      out.add(StructureLiteralNode(formula.substring(i)));
    }
    return out;
  }

  /// Expand any leftover `{league}` tokens to the sport abbrev as plain text.
  static String withoutLeagueTokens(String formula, {String? sport}) {
    if (!formula.contains('{league}')) return formula;
    return formula.replaceAll('{league}', leagueAbbrevForSport(sport));
  }

  static String serialize(List<StructureFormulaNode> nodes) {
    final buf = StringBuffer();
    for (final n in nodes) {
      switch (n) {
        case StructureLiteralNode(:final text):
          buf.write(text);
        case StructureVariableNode(:final key):
          buf.write('{$key}');
      }
    }
    return buf.toString();
  }

  /// League abbrev embedded in phrases like `in their NHL game`.
  static String leagueAbbrevForSport(String? sport) {
    final phrase = defaultGameIdentifierText(sport);
    final m = RegExp(r'in (?:their|an) (.+) game', caseSensitive: false)
        .firstMatch(phrase);
    return m?.group(1)?.trim() ?? phrase;
  }

  /// Build a formula string from a stored template.
  static String fromTemplate(CaptionTemplate template, {String? sport}) {
    final order = template.segmentOrder;
    if (order.isEmpty) return '';

    var punctI = 0;
    var sepI = 0;
    var freeI = 0;
    var cityI = 0;
    var stateI = 0;
    var countryI = 0;
    var countryCodeI = 0;
    var monthI = 0;
    var dayI = 0;
    var weekdayI = 0;
    final punct = template.punctuationSnippets ?? const <String>[];
    final seps = template.separatorSnippets ?? const <String>[];
    final frees = template.freeTextSnippets ?? const <String>[];
    final freeSuf = template.freeTextSuffixes ?? const <String>[];
    final monthTok = template.monthTokensByOccurrence ?? const <DateFieldToken>[];
    final dayTok = template.dayTokensByOccurrence ?? const <DateFieldToken>[];
    final weekdayTok =
        template.weekdayTokensByOccurrence ?? const <DateFieldToken>[];
    final locOpts = template.locationOptionsByOccurrence;

    final buf = StringBuffer();

    String? keyForGeo(CaptionSegment seg, int occ) {
      LocationChipKind? chipKind;
      if (seg == CaptionSegment.city) {
        chipKind = LocationChipKind.city;
      } else if (seg == CaptionSegment.state) {
        chipKind = LocationChipKind.region;
      } else if (seg == CaptionSegment.country) {
        chipKind = LocationChipKind.country;
      } else if (seg == CaptionSegment.countryCode) {
        chipKind = LocationChipKind.countryCode;
      }
      final caps = chipKind != null &&
          locOpts != null &&
          occ < locOpts.length &&
          locOpts[occ].chips.any((c) => c.kind == chipKind && c.caps);
      if (seg == CaptionSegment.city) {
        return caps
            ? StructureFormulaKeys.dlCity
            : StructureFormulaKeys.city;
      }
      if (seg == CaptionSegment.state) {
        return caps
            ? StructureFormulaKeys.dlState
            : StructureFormulaKeys.state;
      }
      if (seg == CaptionSegment.country) {
        return caps
            ? StructureFormulaKeys.dlCountry
            : StructureFormulaKeys.country;
      }
      if (seg == CaptionSegment.countryCode) {
        return caps
            ? StructureFormulaKeys.dlCountryCode
            : StructureFormulaKeys.countryCode;
      }
      return null;
    }

    String? keyForDate(CaptionSegment seg, int occ) {
      if (seg == CaptionSegment.month) {
        final caps = occ < monthTok.length && monthTok[occ].caps;
        return caps
            ? StructureFormulaKeys.dlMonth
            : StructureFormulaKeys.month;
      }
      if (seg == CaptionSegment.day) {
        final caps = occ < dayTok.length && dayTok[occ].caps;
        return caps
            ? StructureFormulaKeys.dlDay
            : StructureFormulaKeys.day;
      }
      if (seg == CaptionSegment.year) return StructureFormulaKeys.year;
      if (seg == CaptionSegment.weekday) {
        final caps = occ < weekdayTok.length && weekdayTok[occ].caps;
        return caps
            ? StructureFormulaKeys.dlWeekday
            : StructureFormulaKeys.weekday;
      }
      return null;
    }

    bool freeTextIsGameIdSlot(int segmentIndex) {
      for (var i = segmentIndex - 1; i >= 0; i--) {
        final prev = order[i];
        if (prev == CaptionSegment.caption) return true;
        if (prev == CaptionSegment.punctuation ||
            prev == CaptionSegment.separator) {
          continue;
        }
        return false;
      }
      return false;
    }

    for (var si = 0; si < order.length; si++) {
      final seg = order[si];
      switch (seg) {
        case CaptionSegment.punctuation:
          final t = punctI < punct.length ? punct[punctI] : '';
          punctI++;
          buf.write(t);
        case CaptionSegment.separator:
          final t = sepI < seps.length ? seps[sepI] : '';
          sepI++;
          buf.write(t);
        case CaptionSegment.freeText:
          var body = freeI < frees.length ? frees[freeI] : '';
          final suf = freeI < freeSuf.length ? freeSuf[freeI] : '';
          freeI++;
          // Sport Game ID phrases are start-screen only — omit from Structure.
          final asGameId = _isGameIdentifierPhrase(
                body,
                template.gameIdentifierText,
              ) ||
              (body.trim().isEmpty && freeTextIsGameIdSlot(si));
          if (asGameId) break;
          buf.write(body);
          buf.write(suf);
        case CaptionSegment.customText:
          // Legacy game-identifier segment — start screen owns this now.
          break;
        case CaptionSegment.caption:
          buf.write('{${StructureFormulaKeys.caption}}');
        case CaptionSegment.venue:
          buf.write('{${StructureFormulaKeys.location}}');
        case CaptionSegment.creator:
          buf.write('{${StructureFormulaKeys.name}}');
        case CaptionSegment.agency:
          buf.write('{${StructureFormulaKeys.credit}}');
        case CaptionSegment.credit:
          buf.write('{${StructureFormulaKeys.byline}}');
        case CaptionSegment.city:
          buf.write('{${keyForGeo(seg, cityI++)}}');
        case CaptionSegment.state:
          buf.write('{${keyForGeo(seg, stateI++)}}');
        case CaptionSegment.country:
          buf.write('{${keyForGeo(seg, countryI++)}}');
        case CaptionSegment.countryCode:
          buf.write('{${keyForGeo(seg, countryCodeI++)}}');
        case CaptionSegment.month:
          buf.write('{${keyForDate(seg, monthI++)}}');
        case CaptionSegment.day:
          buf.write('{${keyForDate(seg, dayI++)}}');
        case CaptionSegment.year:
          buf.write('{${StructureFormulaKeys.year}}');
        case CaptionSegment.weekday:
          buf.write('{${keyForDate(seg, weekdayI++)}}');
        case CaptionSegment.location:
        case CaptionSegment.date:
          // Omitted from the simplified editor formula; preserved via base copy.
          break;
      }
    }
    return ensureCaption(buf.toString());
  }

  /// True when [body] is the sport game-identifier phrase (not wire layout).
  static bool _isGameIdentifierPhrase(String body, String gameIdentifierText) {
    final t = body.trim();
    if (t.isEmpty) return false;
    final gid = gameIdentifierText.trim();
    if (gid.isNotEmpty && t == gid) return true;
    return kKnownGameIdentifierDefaults.contains(t);
  }

  /// Apply a formula onto [base], keeping wire/id/player-output settings.
  static CaptionTemplate applyToTemplate(
    CaptionTemplate base,
    String formula, {
    String? sport,
  }) {
    final nodes = parse(
      ensureCaption(withoutLeagueTokens(formula, sport: sport)),
      sport: sport,
    );
    final order = <CaptionSegment>[];
    final punct = <String>[];
    final seps = <String>[];
    final frees = <String>[];
    final freeSuf = <String>[];
    final monthTok = <DateFieldToken>[];
    final dayTok = <DateFieldToken>[];
    final yearTok = <DateFieldToken>[];
    final weekdayTok = <DateFieldToken>[];
    final locOpts = <LocationLineOptions>[];

    var cityOcc = 0;
    var stateOcc = 0;
    var countryOcc = 0;
    var countryCodeOcc = 0;

    void addLiteral(String text) {
      if (text.isEmpty) return;
      // Prefer punctuation for short joiners; freeText for long notes.
      if (text.trim().contains(' ') && text.trim().length > 24) {
        order.add(CaptionSegment.freeText);
        frees.add(text);
        freeSuf.add('');
      } else if (RegExp(r'^\s*(at|on|in)\s+$', caseSensitive: false)
          .hasMatch(text)) {
        order.add(CaptionSegment.separator);
        seps.add(text);
      } else {
        order.add(CaptionSegment.punctuation);
        punct.add(text);
      }
    }

    final isGettyWire = base.wireStyle == WireStyle.getty ||
        base.wireStyle == WireStyle.gettyInternational;
    final isApWire = base.wireStyle == WireStyle.ap ||
        base.wireStyle == WireStyle.cp;

    LocationRegionVariant _regionVariantFromBase() {
      LocationChip? region;
      final byOcc = base.locationOptionsByOccurrence;
      if (byOcc != null) {
        for (final o in byOcc) {
          for (final c in o.chips) {
            if (c.kind == LocationChipKind.region) {
              region = c;
              break;
            }
          }
          if (region != null) break;
        }
      }
      if (region == null) {
        for (final c in base.locationOptions.chips) {
          if (c.kind == LocationChipKind.region) {
            region = c;
            break;
          }
        }
      }
      if (region != null) {
        // Structure used to rebuild AP/CP with Imagn chips (fullName + country).
        // Restore AP Style when that pollution is detected.
        if (isApWire &&
            region.regionVariant == LocationRegionVariant.fullName &&
            base.locationOptions.chips
                .any((c) => c.kind == LocationChipKind.country)) {
          return LocationRegionVariant.apStyle;
        }
        return region.regionVariant;
      }
      return isApWire
          ? LocationRegionVariant.apStyle
          : LocationRegionVariant.fullName;
    }

    LocationLineOptions locFor({required bool caps}) {
      if (isGettyWire) {
        return caps
            ? LocationLineOptions.gettyDefault()
            : LocationLineOptions.gettyDefaultSentenceCase();
      }
      if (isApWire) {
        // AP/CP: keep State Format (AP Style by default) across Structure edits.
        final variant = _regionVariantFromBase();
        final chips = <LocationChip>[
          LocationChip(
            id: 'a_city',
            kind: LocationChipKind.city,
            caps: caps,
          ),
          const LocationChip(
            id: 'a_lit1',
            kind: LocationChipKind.literal,
            literal: ', ',
          ),
          LocationChip(
            id: 'a_reg',
            kind: LocationChipKind.region,
            caps: caps,
            regionVariant: variant,
          ),
          const LocationChip(
            id: 'a_lit2',
            kind: LocationChipKind.literal,
            literal: ', ',
          ),
          LocationChip(
            id: 'a_ctr',
            kind: LocationChipKind.country,
            caps: caps,
          ),
        ];
        return LocationLineOptions(
          uppercase: false,
          chips: chips,
          autoAdaptUsIntl: false,
        );
      }
      // Imagn: Structure owns geo commas; no US↔intl auto-adapt.
      final baseLoc = LocationLineOptions.imagnDefault();
      if (!caps) return baseLoc;
      return LocationLineOptions(
        uppercase: false,
        chips: [
          for (final c in baseLoc.chips)
            c.kind == LocationChipKind.literal
                ? c
                : c.copyWith(caps: true),
        ],
        autoSpacing: baseLoc.autoSpacing,
        autoAdaptUsIntl: false,
      );
    }

    /// Keep Structure `{country_code}` caps chips when city/state/country rewrite
    /// the shared [locOpts] slot.
    LocationLineOptions withPreservedCountryCode(
      LocationLineOptions next,
      LocationLineOptions? prev,
    ) {
      if (prev == null) return next;
      final extras = prev.chips
          .where((c) => c.kind == LocationChipKind.countryCode)
          .toList(growable: false);
      if (extras.isEmpty) return next;
      return LocationLineOptions(
        uppercase: next.uppercase,
        chips: [...next.chips, ...extras],
        autoSpacing: next.autoSpacing,
        autoAdaptUsIntl: next.autoAdaptUsIntl,
        usChips: next.usChips,
        intlChips: next.intlChips,
      );
    }

    void upsertCountryCodeChip(int occ, {required bool caps}) {
      while (locOpts.length <= occ) {
        locOpts.add(locFor(caps: false));
      }
      final cur = locOpts[occ];
      final chips = cur.chips
          .where((c) => c.kind != LocationChipKind.countryCode)
          .toList();
      chips.add(LocationChip(
        id: 'geo_country_code',
        kind: LocationChipKind.countryCode,
        caps: caps,
      ));
      locOpts[occ] = LocationLineOptions(
        uppercase: cur.uppercase,
        chips: chips,
        autoSpacing: cur.autoSpacing,
        autoAdaptUsIntl: cur.autoAdaptUsIntl,
        usChips: cur.usChips,
        intlChips: cur.intlChips,
      );
    }

    /// Keep wire date style (e.g. Imagn abbreviated month) across Structure edits.
    int optionIndexFor(DateFieldKind kind, int occ) {
      List<DateFieldToken>? byOcc;
      switch (kind) {
        case DateFieldKind.month:
          byOcc = base.monthTokensByOccurrence;
        case DateFieldKind.day:
          byOcc = base.dayTokensByOccurrence;
        case DateFieldKind.year:
          byOcc = base.yearTokensByOccurrence;
        case DateFieldKind.weekday:
          byOcc = base.weekdayTokensByOccurrence;
      }
      if (byOcc != null && occ < byOcc.length) return byOcc[occ].optionIndex;
      final df = base.dateFormula;
      if (df != null) {
        final matches =
            df.fields.where((f) => f.kind == kind).toList(growable: false);
        if (occ < matches.length) return matches[occ].optionIndex;
        if (matches.isNotEmpty) return matches.first.optionIndex;
      }
      return 0;
    }

    for (final node in nodes) {
      switch (node) {
        case StructureLiteralNode(:final text):
          addLiteral(text);
        case StructureVariableNode(:final key):
          // Legacy `{game_id}` chips are ignored — start screen owns the phrase.
          if (key == StructureFormulaKeys.gameId) {
            break;
          }
          final seg = StructureFormulaKeys.segmentFor(key);
          if (seg == null) break;
          order.add(seg);
          switch (key) {
            case StructureFormulaKeys.dlCity:
              while (locOpts.length <= cityOcc) {
                locOpts.add(locFor(caps: cityOcc == 0));
              }
              locOpts[cityOcc] = withPreservedCountryCode(
                locFor(caps: true),
                locOpts[cityOcc],
              );
              cityOcc++;
            case StructureFormulaKeys.city:
              while (locOpts.length <= cityOcc) {
                locOpts.add(locFor(caps: false));
              }
              locOpts[cityOcc] = withPreservedCountryCode(
                locFor(caps: false),
                locOpts[cityOcc],
              );
              cityOcc++;
            case StructureFormulaKeys.dlState:
              while (locOpts.length <= stateOcc) {
                locOpts.add(locFor(caps: stateOcc == 0));
              }
              locOpts[stateOcc] = withPreservedCountryCode(
                locFor(caps: true),
                locOpts[stateOcc],
              );
              stateOcc++;
            case StructureFormulaKeys.state:
              while (locOpts.length <= stateOcc) {
                locOpts.add(locFor(caps: false));
              }
              locOpts[stateOcc] = withPreservedCountryCode(
                locFor(caps: false),
                locOpts[stateOcc],
              );
              stateOcc++;
            case StructureFormulaKeys.dlCountry:
              while (locOpts.length <= countryOcc) {
                locOpts.add(locFor(caps: countryOcc == 0));
              }
              locOpts[countryOcc] = withPreservedCountryCode(
                locFor(caps: true),
                locOpts[countryOcc],
              );
              countryOcc++;
            case StructureFormulaKeys.country:
              while (locOpts.length <= countryOcc) {
                locOpts.add(locFor(caps: false));
              }
              locOpts[countryOcc] = withPreservedCountryCode(
                locFor(caps: false),
                locOpts[countryOcc],
              );
              countryOcc++;
            case StructureFormulaKeys.dlCountryCode:
              upsertCountryCodeChip(countryCodeOcc, caps: true);
              countryCodeOcc++;
            case StructureFormulaKeys.countryCode:
              upsertCountryCodeChip(countryCodeOcc, caps: false);
              countryCodeOcc++;
            case StructureFormulaKeys.dlMonth:
              monthTok.add(DateFieldToken(
                kind: DateFieldKind.month,
                optionIndex: optionIndexFor(
                    DateFieldKind.month, monthTok.length),
                caps: true,
              ));
            case StructureFormulaKeys.month:
              monthTok.add(DateFieldToken(
                kind: DateFieldKind.month,
                optionIndex: optionIndexFor(
                    DateFieldKind.month, monthTok.length),
              ));
            case StructureFormulaKeys.dlDay:
              dayTok.add(DateFieldToken(
                kind: DateFieldKind.day,
                optionIndex:
                    optionIndexFor(DateFieldKind.day, dayTok.length),
                caps: true,
              ));
            case StructureFormulaKeys.day:
              dayTok.add(DateFieldToken(
                kind: DateFieldKind.day,
                optionIndex:
                    optionIndexFor(DateFieldKind.day, dayTok.length),
              ));
            case StructureFormulaKeys.year:
              yearTok.add(DateFieldToken(
                kind: DateFieldKind.year,
                optionIndex:
                    optionIndexFor(DateFieldKind.year, yearTok.length),
              ));
            case StructureFormulaKeys.dlWeekday:
              weekdayTok.add(DateFieldToken(
                kind: DateFieldKind.weekday,
                optionIndex: optionIndexFor(
                    DateFieldKind.weekday, weekdayTok.length),
                caps: true,
              ));
            case StructureFormulaKeys.weekday:
              weekdayTok.add(DateFieldToken(
                kind: DateFieldKind.weekday,
                optionIndex: optionIndexFor(
                    DateFieldKind.weekday, weekdayTok.length),
              ));
            default:
              break;
          }
      }
    }

    // Ensure location options length covers max geo occurrence.
    var geoOcc = cityOcc > stateOcc ? cityOcc : stateOcc;
    if (countryOcc > geoOcc) geoOcc = countryOcc;
    if (countryCodeOcc > geoOcc) geoOcc = countryCodeOcc;
    while (locOpts.length < geoOcc) {
      locOpts.add(locFor(caps: locOpts.isEmpty));
    }

    return base
        .copyWith(
          segmentOrder: order,
          punctuationSnippets: punct.isEmpty ? null : punct,
          separatorSnippets: seps.isEmpty ? null : seps,
          freeTextSnippets: frees.isEmpty ? null : frees,
          freeTextSuffixes: freeSuf.isEmpty ? null : freeSuf,
          customSeparators: null,
          monthTokensByOccurrence: monthTok.isEmpty ? null : monthTok,
          dayTokensByOccurrence: dayTok.isEmpty ? null : dayTok,
          yearTokensByOccurrence: yearTok.isEmpty ? null : yearTok,
          weekdayTokensByOccurrence:
              weekdayTok.isEmpty ? null : weekdayTok,
          locationOptionsByOccurrence: locOpts.isEmpty ? null : locOpts,
          // Keep host/sport overlay; fall back to sport default for preview.
          gameIdentifierText: () {
            final existing = base.gameIdentifierText.trim();
            if (existing.isNotEmpty) return existing;
            return defaultGameIdentifierText(sport);
          }(),
        )
        .normalizePerOccurrenceLists();
  }
}
