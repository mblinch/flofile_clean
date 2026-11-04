import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../caption_style/caption_formula_renderer.dart';
import '../caption_style/getty_note_variant.dart';
import '../caption_style/caption_session_context.dart';
import '../caption_style/caption_style_catalog.dart';
import '../caption_style/caption_template.dart';
import '../caption_style/date_formula.dart';
import '../caption_style/game_info.dart';
import '../caption_style/region_abbrev.dart';
import '../caption_style/sport_verb_categories.dart';
import '../caption_style/structure_formula.dart';
import '../caption_style/team_home_place.dart';
import '../services/api_manager.dart';
import '../services/app_defaults_firestore_service.dart';
import '../services/current_user_service.dart';
import '../services/iptc_template_apply_service.dart';
import '../services/mlb_api_service.dart' show Player;
import '../services/preferences_service.dart';
import '../theme/ff_tokens.dart';
import 'app_styled_dialogs.dart';
import 'space_token_text.dart';
import 'ff_dropdown.dart';
import 'structure_formula_field.dart';
import 'structure_iptc_source_dialog.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

FfTokens _ffOf(BuildContext context) =>
    Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;

/// Caption layout: wire preset or custom formula; preview prefers live session
/// teams / folder dates when provided, else prefs / mock samples.
class CaptionLayoutBuilderDialog extends StatefulWidget {
  const CaptionLayoutBuilderDialog({
    super.key,
    this.embedded = false,
    this.adminMode = false,
    this.initialWire,
    this.initialTemplate,
    this.wireDraftsSeed,
    this.gameIdDraftsSeed,
    this.initialSport,
    this.previewHomeTeam,
    this.previewAwayTeam,
    this.previewGameInfo,
    this.previewPlayers,
    this.previewDateFromFolder,
    this.onDraftChanged,
    this.onWireChanged,
    this.onSportChanged,
    this.onRegisterFlush,
    this.onRegisterSetAllDefaults,
    this.onAdminSaveAsDefault,
    this.onAdminDiscard,
    this.onSessionStructureChipTap,
  });

  /// When true, renders without [Dialog] chrome (for embedding in admin).
  final bool embedded;

  /// Edits in-memory wire drafts instead of writing user preferences.
  final bool adminMode;
  final WireStyle? initialWire;
  final CaptionTemplate? initialTemplate;
  final Map<WireStyle, CaptionTemplate>? wireDraftsSeed;
  final Map<WireStyle, Map<String, String>>? gameIdDraftsSeed;
  final String? initialSport;

  /// Live home team for Structure / caption examples (session selection).
  final String? previewHomeTeam;

  /// Live away team for Structure / caption examples (session selection).
  final String? previewAwayTeam;

  /// Live game metadata for date / venue / IPTC preview (focused folder file).
  final GameInfo? previewGameInfo;

  /// Real roster players for Shuffle sample (from the selected teams).
  final List<CaptionPreviewPlayer>? previewPlayers;

  /// When non-null, preview date came from the images folder (`true`) or
  /// fell back to today because the folder had no photos (`false`).
  final bool? previewDateFromFolder;
  final void Function(WireStyle wire, CaptionTemplate template)? onDraftChanged;
  final ValueChanged<WireStyle>? onWireChanged;
  final ValueChanged<String>? onSportChanged;
  final void Function(Future<void> Function() flush)? onRegisterFlush;
  final void Function(Future<void> Function() setAll)? onRegisterSetAllDefaults;

  /// Admin host publishes the current structure (Firebase app originals).
  /// Returns `true` when the publish actually completed (not cancelled).
  final Future<bool> Function()? onAdminSaveAsDefault;

  /// Admin host restores catalog baselines and rebuilds the editor.
  final VoidCallback? onAdminDiscard;

  /// New-session embed only: structure chip tap opens the 4-quadrant IPTC
  /// screen via this callback instead of [showStructureIptcSourceDialog].
  /// Argument is the IPTC panel storage key to focus, or null when the chip
  /// has no matching editable quadrant field.
  final ValueChanged<String?>? onSessionStructureChipTap;

  /// Returns the applied [CaptionTemplate] when Done succeeds; `null` on Cancel.
  static Future<CaptionTemplate?> show(
    BuildContext context, {
    String? initialSport,
    String? previewHomeTeam,
    String? previewAwayTeam,
    GameInfo? previewGameInfo,
    List<CaptionPreviewPlayer>? previewPlayers,
    bool? previewDateFromFolder,
  }) {
    final tokens =
        Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return showDialog<CaptionTemplate>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) => Theme(
        data: Theme.of(context).copyWith(
          brightness: Brightness.dark,
          extensions: <ThemeExtension<dynamic>>[tokens],
        ),
        child: AppDialogFfStyle(
          enabled: true,
          child: CaptionLayoutBuilderDialog(
            initialSport: initialSport,
            previewHomeTeam: previewHomeTeam,
            previewAwayTeam: previewAwayTeam,
            previewGameInfo: previewGameInfo,
            previewPlayers: previewPlayers,
            previewDateFromFolder: previewDateFromFolder,
          ),
        ),
      ),
    );
  }

  @override
  State<CaptionLayoutBuilderDialog> createState() =>
      CaptionLayoutBuilderDialogState();
}

class CaptionLayoutBuilderDialogState extends State<CaptionLayoutBuilderDialog> {
  FfTokens get _t => _ffOf(context);

  /// Embedded on New session (not Admin): hide prefs footer, USA/intl, sport.
  bool get _isSessionStartupEmbed => widget.embedded && !widget.adminMode;

  /// Sample city / date / venue for preview only (matches sample sentence in renderer).
  /// Photographer is resolved from the signed-in user at build time via
  /// [CurrentUserService]; agency is left blank so the renderer falls back to
  /// the selected wire style's sample label (e.g. Getty USA → "Getty Images").
  /// TODO: wire credit to the IPTC byline/credit fields once available.
  static final GameInfo _baseMockGameInfo = GameInfo(
    gameDate: DateTime(2026, 4, 4),
    city: 'Los Angeles',
    region: 'California',
    regionCode: 'CA',
    country: 'United States',
    countryCode: 'USA',
    venue: 'Los Angeles Sports Stadium',
  );

  /// Fallback IPTC date samples when no folder import has populated prefs yet.
  static const Map<String, String> _mockIptcDates = {
    'DateTimeOriginal': '2026:04:04 14:30:00',
    'CreateDate': '2026:04:04 15:00:00',
    'DateCreated': '20260404',
  };

  /// Session [GameInfo] from prefs (updated when images are imported — EXIF date).
  GameInfo? _loadedGameInfo;

  /// Preview row: constructor override → session → prefs-loaded → mock.
  GameInfo get _previewGameInfo {
    GameInfo withPhotographer(GameInfo info) => info.copyWith(
          photographerName: info.photographerName.trim().isNotEmpty
              ? info.photographerName
              : CurrentUserService.displayNameOrPlaceholder(),
        );

    final override = widget.previewGameInfo;
    if (override != null) {
      final fromOverride = CaptionFormulaRenderer.storedVenue(override);
      final fromSession = CaptionSessionContext.gameInfo;
      final fromLoaded = _loadedGameInfo?.venue.trim() ?? '';
      final sessionVenue = fromSession == null
          ? ''
          : CaptionFormulaRenderer.storedVenue(fromSession);
      final venue = fromOverride.isNotEmpty
          ? fromOverride
          : (sessionVenue.isNotEmpty
              ? sessionVenue
              : (fromLoaded.isNotEmpty ? fromLoaded : override.venue));
      return withPhotographer(override.copyWith(venue: venue));
    }

    // If the user has already generated a caption this session, use that data.
    final session = CaptionSessionContext.gameInfo;
    if (session != null) {
      final fromSession = CaptionFormulaRenderer.storedVenue(session);
      final fromLoaded = _loadedGameInfo?.venue.trim() ?? '';
      final venue = fromSession.isNotEmpty
          ? fromSession
          : (fromLoaded.isNotEmpty ? fromLoaded : session.venue);
      return withPhotographer(session.copyWith(venue: venue));
    }
    final snap = _loadedGameInfo;
    String pick(String a, String b) => b.trim().isNotEmpty ? b : a;
    return _baseMockGameInfo.copyWith(
      gameDate: snap?.gameDate ?? _baseMockGameInfo.gameDate,
      city: snap != null
          ? pick(_baseMockGameInfo.city, snap.city)
          : _baseMockGameInfo.city,
      region: snap != null
          ? pick(_baseMockGameInfo.region, snap.region)
          : _baseMockGameInfo.region,
      regionCode: snap != null
          ? pick(_baseMockGameInfo.regionCode, snap.regionCode)
          : _baseMockGameInfo.regionCode,
      country: snap != null
          ? pick(_baseMockGameInfo.country, snap.country)
          : _baseMockGameInfo.country,
      countryCode: snap != null
          ? pick(_baseMockGameInfo.countryCode, snap.countryCode)
          : _baseMockGameInfo.countryCode,
      iptcMetadata: (snap != null && snap.iptcMetadata.isNotEmpty)
          ? snap.iptcMetadata
          : _mockIptcDates,
      photographerName: CurrentUserService.displayNameOrPlaceholder(),
      agencyName: '',
    );
  }

  bool get _isGettyWire =>
      _template.wireStyle == WireStyle.getty ||
      _template.wireStyle == WireStyle.gettyInternational;

  bool get _isImagnWire => _template.wireStyle == WireStyle.imagn;

  bool get _isApWire =>
      _template.wireStyle == WireStyle.ap ||
      _template.wireStyle == WireStyle.cp;

  /// Hold Structure commas/spaces across empty City/State/Country so
  /// `{city}, {state}` → `Philadelphia` when AP omits a standalone city's state.
  bool get _holdsEmptyStructureGeoGlue =>
      _isGettyWire || _isImagnWire || _isApWire;

  /// Caption preview game — city/state from the selected **home** team.
  /// Location (stadium) comes from IPTC SubLocation when present.
  GameInfo get _captionPreviewGame {
    var info = _previewGameInfo;
    final names = _exampleTeamNames;
    final homeName = names.$1;
    final awayName = names.$2;

    // Always prefer the home club's place for dateline / city / state.
    final place = (homeName != null ? teamHomePlace(homeName) : null) ??
        (awayName != null ? teamHomePlace(awayName) : null);

    if (place != null) {
      final session = CaptionSessionContext.gameInfo;
      final sessionMatches = session != null &&
          session.city.trim().isNotEmpty &&
          session.city.trim().toLowerCase() ==
              place.city.trim().toLowerCase();
      if (!sessionMatches ||
          widget.previewGameInfo != null ||
          _hasLiveTeamOverrides) {
        info = place.applyTo(info);
      }
    }

    final hasIptcLocation = CaptionFormulaRenderer.hasIptcLocation(info);
    final apiVenue = (_previewHomeVenue ?? '').trim();
    if (!hasIptcLocation) {
      if (apiVenue.isNotEmpty) {
        info = info.copyWith(venue: apiVenue);
      } else if (info.venue.trim().isEmpty && place != null) {
        final stored = CaptionFormulaRenderer.storedVenue(_previewGameInfo);
        if (stored.isNotEmpty &&
            !stored.toLowerCase().contains('sports stadium')) {
          info = info.copyWith(venue: stored);
        }
      }
    }

    // Strip the generic mock stadium if location is no longer LA.
    if (info.venue.trim().toLowerCase() == 'los angeles sports stadium' &&
        info.city.trim().toLowerCase() != 'los angeles' &&
        !hasIptcLocation) {
      info = info.copyWith(venue: '');
    }

    return info;
  }

  /// Structure-editor preview game. For Getty, city/region/country follow the
  /// USA / International toggle when no live teams are selected. Getty
  /// Structure preview auto-adapts: State in the US, Country elsewhere.
  GameInfo get _structurePreviewGame {
    final base = _captionPreviewGame;
    // New session / live team overrides: always use team-derived geo (and
    // venue). Never replace Toronto with Chicago just because Getty USA mode
    // is the default when the USA/International toggle is hidden.
    if (_isSessionStartupEmbed || _hasLiveTeamOverrides) {
      return base;
    }
    if (_isGettyWire) {
      if (_gettyPreviewUnitedStates) {
        // Prefer the selected teams' US home place so State is a distinct name
        // (e.g. Chicago, Illinois) — not "New York, New York".
        if (CaptionFormulaRenderer.isUnitedStatesGame(base) &&
            base.region.trim().isNotEmpty) {
          return base;
        }
        return base.copyWith(
          city: 'Chicago',
          region: 'Illinois',
          regionCode: 'IL',
          country: 'United States',
          countryCode: 'USA',
        );
      }
      return base.copyWith(
        city: 'Toronto',
        region: 'Ontario',
        regionCode: 'ON',
        country: 'Canada',
        countryCode: 'CAN',
      );
    }
    return base;
  }

  /// Geo chip options for Structure preview values. Getty auto-adapts
  /// State↔Country by territory (same as live export). Imagn keeps
  /// province+country; AP/CP use the State Format (AP Style standalone cities
  /// + abbrevs).
  LocationLineOptions _structurePreviewGeoOptions({required bool caps}) {
    if (_isGettyWire) {
      return caps
          ? LocationLineOptions.gettyDefault()
          : LocationLineOptions.gettyDefaultSentenceCase();
    }
    if (_isImagnWire) {
      final base = LocationLineOptions.imagnDefault();
      return caps ? base.copyWith(uppercase: true) : base;
    }
    if (_isApWire) {
      final byOcc = _template.locationOptionsByOccurrence;
      final fromTemplate =
          (byOcc != null && byOcc.isNotEmpty) ? byOcc.first : _template.locationOptions;
      var regionVariant = LocationRegionVariant.apStyle;
      for (final c in fromTemplate.chips) {
        if (c.kind == LocationChipKind.region) {
          regionVariant = c.regionVariant;
          break;
        }
      }
      // Older drafts wiped AP Style via Structure apply — treat plain fullName
      // Imagn-shaped chips as AP Style on AP/CP wires.
      final looksImagnShaped = fromTemplate.chips.any(
            (c) => c.kind == LocationChipKind.country,
          ) &&
          regionVariant == LocationRegionVariant.fullName;
      if (looksImagnShaped) {
        regionVariant = LocationRegionVariant.apStyle;
      }
      final base = LocationLineOptions(
        uppercase: false,
        autoAdaptUsIntl: false,
        chips: [
          LocationChip(
            id: 'ap_city',
            kind: LocationChipKind.city,
            caps: caps,
          ),
          const LocationChip(
            id: 'ap_lit1',
            kind: LocationChipKind.literal,
            literal: ', ',
          ),
          LocationChip(
            id: 'ap_reg',
            kind: LocationChipKind.region,
            caps: caps,
            regionVariant: regionVariant,
          ),
          const LocationChip(
            id: 'ap_lit2',
            kind: LocationChipKind.literal,
            literal: ', ',
          ),
          LocationChip(
            id: 'ap_ctr',
            kind: LocationChipKind.country,
            caps: caps,
          ),
          LocationChip(
            id: 'ap_cc',
            kind: LocationChipKind.countryCode,
            caps: caps,
          ),
        ],
      );
      return caps ? base.copyWith(uppercase: true) : base;
    }
    // Custom — no US↔intl blanking for Structure token preview.
    final base = LocationLineOptions(
      uppercase: false,
      autoAdaptUsIntl: false,
      chips: LocationLineOptions.imagnDefault().chips,
    );
    return caps ? base.copyWith(uppercase: true) : base;
  }

  bool get _hasLiveTeamOverrides {
    final home = widget.previewHomeTeam?.trim() ?? '';
    final away = widget.previewAwayTeam?.trim() ?? '';
    return home.isNotEmpty || away.isNotEmpty;
  }

  (String?, String?) get _exampleTeamNames {
    // Constructor overrides (caption_v2 session) win over prior caption samples.
    if (_hasLiveTeamOverrides) {
      final home = widget.previewHomeTeam?.trim() ?? '';
      final away = widget.previewAwayTeam?.trim() ?? '';
      return (
        home.isEmpty ? null : home,
        away.isEmpty ? null : away,
      );
    }
    // Prefer last startup / admin-picked home/away.
    final savedHome = _savedExampleHome?.trim();
    final savedAway = _savedExampleAway?.trim();
    final hasHome = savedHome != null && savedHome.isNotEmpty;
    final hasAway = savedAway != null && savedAway.isNotEmpty;
    if (hasHome || hasAway) {
      return (
        hasHome ? savedHome : null,
        hasAway ? savedAway : null,
      );
    }
    if (widget.adminMode) return (null, null);
    final live = CaptionSessionContext.previewPlayers;
    if (live.isNotEmpty) {
      final home = live.first.team.trim();
      final away = live.first.opponent.trim();
      if (home.isNotEmpty || away.isNotEmpty) {
        return (
          home.isEmpty ? null : home,
          away.isEmpty ? null : away,
        );
      }
    }
    return (null, null);
  }

  bool get _hasSelectedExampleTeams {
    final names = _exampleTeamNames;
    return (names.$1 != null && names.$1!.isNotEmpty) ||
        (names.$2 != null && names.$2!.isNotEmpty);
  }

  /// True when [players] belong to the currently selected example teams.
  bool _rosterMatchesSelectedTeams(List<CaptionPreviewPlayer> players) {
    if (players.isEmpty) return false;
    final names = _exampleTeamNames;
    final home = names.$1?.trim().toLowerCase() ?? '';
    final away = names.$2?.trim().toLowerCase() ?? '';
    if (home.isEmpty && away.isEmpty) return false;
    final allowed = <String>{
      if (home.isNotEmpty) home,
      if (away.isNotEmpty) away,
    };
    for (final p in players) {
      final team = p.team.trim().toLowerCase();
      if (team.isEmpty || !allowed.contains(team)) return false;
    }
    return true;
  }

  /// Real roster players for the selected clubs. Never invents fake names.
  List<CaptionPreviewPlayer>? _realPreviewPlayers() {
    final roster = _rosterPreviewPlayers;
    if (roster != null &&
        roster.isNotEmpty &&
        (!_hasSelectedExampleTeams || _rosterMatchesSelectedTeams(roster))) {
      return roster;
    }
    // Admin team pickers own the sample — don't fall back to session/seeded
    // players from a different matchup.
    if (widget.adminMode && _hasSelectedExampleTeams) return null;
    final seeded = widget.previewPlayers;
    if (seeded != null &&
        seeded.isNotEmpty &&
        (!_hasSelectedExampleTeams || _rosterMatchesSelectedTeams(seeded))) {
      return seeded;
    }
    // Live session roster only when we are not overriding teams from startup.
    if (!_hasLiveTeamOverrides &&
        CaptionSessionContext.previewPlayers.isNotEmpty) {
      return CaptionSessionContext.previewPlayers;
    }
    return null;
  }

  Future<void> _refreshRosterPreviewPlayers({bool clearFirst = false}) async {
    final names = _exampleTeamNames;
    final home = names.$1?.trim();
    final away = names.$2?.trim();
    final homeName =
        (home != null && home.isNotEmpty) ? home : null;
    final awayName =
        (away != null && away.isNotEmpty) ? away : null;
    if (homeName == null && awayName == null) {
      if (!mounted) return;
      setState(() {
        _rosterPreviewPlayers = null;
        _rosterPreviewLoading = false;
        _previewHomeVenue = null;
      });
      return;
    }

    final gen = ++_rosterPreviewGen;
    if (mounted) {
      setState(() {
        if (clearFirst ||
            _rosterPreviewPlayers == null ||
            !_rosterMatchesSelectedTeams(_rosterPreviewPlayers!)) {
          _rosterPreviewPlayers = null;
        }
        _rosterPreviewLoading = true;
      });
    }

    // Prefer already-fetched roster from the caller (startup) only when it
    // matches the selected clubs.
    final seeded = widget.previewPlayers;
    if (!clearFirst &&
        seeded != null &&
        seeded.isNotEmpty &&
        _rosterPreviewPlayers == null &&
        _rosterMatchesSelectedTeams(seeded)) {
      if (!mounted || gen != _rosterPreviewGen) return;
      setState(() {
        _rosterPreviewPlayers = List<CaptionPreviewPlayer>.from(seeded);
        _rosterPreviewLoading = false;
      });
    }

    final api = ApiManager()..setSport(_sessionSport);
    final out = <CaptionPreviewPlayer>[];
    String? homeVenue;

    Future<void> addSide(String team, String? opponent) async {
      try {
        final roster = await api.fetchTeamRoster(team);
        for (final player in roster) {
          final preview =
              _previewPlayerFromRoster(player, team, opponent ?? '');
          if (preview == null) continue;
          out.add(preview);
        }
      } catch (e) {
        debugPrint('Caption preview roster failed for $team: $e');
      }
    }

    if (homeName != null) {
      await addSide(homeName, awayName);
      try {
        final team = await api.findTeamByName(homeName);
        final venue = team?.venueName?.trim();
        if (venue != null && venue.isNotEmpty) homeVenue = venue;
        if (homeVenue == null || homeVenue.isEmpty) {
          homeVenue = await api.fetchVenueForTeam(homeName);
        }
      } catch (e) {
        debugPrint('Caption preview venue failed for $homeName: $e');
      }
    }
    if (awayName != null && awayName != homeName) {
      await addSide(awayName, homeName);
    }

    if (!mounted || gen != _rosterPreviewGen) return;
    setState(() {
      _rosterPreviewLoading = false;
      if (homeVenue != null && homeVenue.trim().isNotEmpty) {
        _previewHomeVenue = homeVenue.trim();
      }
      if (out.isNotEmpty) {
        _rosterPreviewPlayers = out;
        // New club(s) loaded — reshuffle so the preview shows their players.
        _captionSampleSeed =
            DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
      } else {
        _rosterPreviewPlayers = null;
      }
    });
  }

  /// Null when the roster entry has no usable person name.
  static CaptionPreviewPlayer? _previewPlayerFromRoster(
    Player player,
    String team,
    String opponent,
  ) {
    final rawNum = (player.jerseyNumber ?? '').trim();
    final number = int.tryParse(rawNum.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final position = (player.position ?? '').trim();
    var name = player.fullName.trim();
    if (name.isEmpty) {
      // displayName is often "Name #12" — strip jersey for the caption lead.
      name = player.displayName.trim().replaceAll(RegExp(r'\s*#\d+\s*$'), '');
    }
    if (name.isEmpty) return null;
    // Reject placeholders that are just the club name.
    if (name.toLowerCase() == team.trim().toLowerCase()) return null;
    return CaptionPreviewPlayer(
      team,
      position.isEmpty ? 'P' : position,
      name,
      number,
      opponent,
    );
  }

  /// Caption body used by Structure preview and ADD-menu field samples.
  ///
  /// Always includes a sport timing sample (quarter / period / inning / half)
  /// so PREVIEW shows game time even when Player Output Period is Hide.
  String _resolvedSampleCaption() {
    final realPlayers = _realPreviewPlayers();
    final previewActions = CaptionSessionContext.previewActions;
    final useSessionActions = !widget.adminMode &&
        !_hasLiveTeamOverrides &&
        previewActions.isNotEmpty;
    // Structure PREVIEW always shows timing; Period Hide only affects live
    // captions and the Player Output sample line.
    final previewTemplate =
        _template.copyWith(includeTimingPhrase: true);

    // Selected teams → only real roster names. Never Heater Ace / Boulevards.
    if (_hasSelectedExampleTeams) {
      if (realPlayers != null && realPlayers.isNotEmpty) {
        return CaptionFormulaRenderer.randomSinglePlayerCaption(
          previewTemplate,
          seed: _captionSampleSeed,
          previewPlayers: realPlayers,
          previewActions: useSessionActions ? previewActions : null,
          sport: _sessionSport,
        );
      }
      final names = _exampleTeamNames;
      final home = names.$1 ?? 'Home';
      final away = names.$2 ?? 'Away';
      return _rosterPreviewLoading
          ? 'Loading $home / $away roster…'
          : 'Waiting for $home / $away roster…';
    }

    if (realPlayers != null && realPlayers.isNotEmpty) {
      return CaptionFormulaRenderer.randomSinglePlayerCaption(
        previewTemplate,
        seed: _captionSampleSeed,
        previewPlayers: realPlayers,
        previewActions: useSessionActions ? previewActions : null,
        sport: _sessionSport,
      );
    }
    final sessionBody = CaptionSessionContext.captionBody;
    if (sessionBody != null && sessionBody.isNotEmpty) {
      // Session body may omit timing when Period is Hide — append sample.
      final hasGameSegment = RegExp(
        r'\b(inning|innings|quarter|quarters|period|periods|halftime)\b|'
        r'\b(first|second)\s+half\b|'
        r'\b(top|bottom)\s+of\s+the\b',
        caseSensitive: false,
      ).hasMatch(sessionBody);
      if (hasGameSegment) return sessionBody;
      return '$sessionBody ${CaptionFormulaRenderer.previewTimePhraseForSport(
        _sessionSport,
        caps: _template.timingPhraseCaps,
      )}';
    }
    // No teams chosen — built-in sample is fine for empty state only.
    return CaptionFormulaRenderer.randomSinglePlayerCaption(
      previewTemplate,
      seed: _captionSampleSeed,
      sport: _sessionSport,
    );
  }

  late Future<void> _load;
  CaptionTemplate _template = CaptionTemplate.getty();
  CaptionTemplate _lastPreset = CaptionTemplate.getty();

  /// User-saved baselines when switching wires (see [PreferencesService] wire defaults).
  CaptionTemplate? _gettyWireDefault;
  CaptionTemplate? _imagnWireDefault;
  CaptionTemplate? _apWireDefault;
  CaptionTemplate? _cpWireDefault;
  CaptionTemplate? _gettyIntlWireDefault;
  final Map<WireStyle, CaptionTemplate> _wireDrafts = {};

  /// Custom labels shown in the Caption Style dropdown for built-in wires.
  /// `null` means “use factory name (Getty USA / Imagn / AP / Getty International)”.
  String? _gettyWireLabel;
  String? _imagnWireLabel;
  String? _apWireLabel;
  String? _cpWireLabel;
  String? _gettyIntlWireLabel;
  WireStyle _selectedWire = WireStyle.getty;
  bool _locationEditorOpen = false;
  bool _dateEditorOpen = false;
  bool _captionPreviewSelected = false;
  bool _venuePreviewSelected = false;
  bool _bylinePreviewSelected = false;

  /// True when the user opened the [CaptionSegment.customText] snippet — show
  /// a plain text field only, not the full IPTC byline chip row.
  bool _customTextSnippetEditorOpen = false;
  bool _freeTextSnippetEditorOpen = false;
  bool _separatorSnippetEditorOpen = false;
  bool _punctuationSnippetEditorOpen = false;
  final TextEditingController _snippetLiteralCtrl = TextEditingController();
  bool _syncingSnippetLiteralCtrl = false;
  final TextEditingController _freeTextCtrl = TextEditingController();
  bool _syncingFreeTextCtrl = false;
  int? _activeFormulaIndex;

  /// Which formula separator field (index in [customSeparators]) has focus.
  int? _focusedGapIndex;

  /// Controllers for visible punctuation / separator fields in the preview row.
  final Map<int, TextEditingController> _glueSnippetControllers = {};
  bool _syncingGlueSnippetCtrls = false;
  final Map<int, FocusNode> _glueFocusNodes = {};
  late final FocusNode _layoutPrefixFocus = FocusNode(
    onKeyEvent: (node, event) => _handleStructureSepArrow(0, event),
  );
  late final FocusNode _layoutSuffixFocus = FocusNode(
    onKeyEvent: (node, event) {
      final slots = _structureSepSlots();
      if (slots.isEmpty) return KeyEventResult.ignored;
      return _handleStructureSepArrow(slots.length - 1, event);
    },
  );

  final List<TapGestureRecognizer> _structureFlowTaps = [];

  /// [segmentOrder] index of the inline glue field that currently has focus.
  int? _focusedGlueSegmentIndex;
  bool _layoutPrefixFocused = false;
  bool _layoutSuffixFocused = false;
  int _captionSampleSeed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
  bool _prefsLoaded = false;
  String _lastSavedTemplateSnapshot = '';
  /// Formula string at last save — dirty also compares this so lossy
  /// formula→template round-trips still enable Save as default.
  String _lastSavedStructureFormula = '';
  /// Set by [_done] so [dispose] does not race a second prefs write.
  bool _appliedOnDone = false;
  bool _closeConfirmed = false;
  Timer? _autosaveDebounce;
  bool _renameCaptionStylePromptOpen = false;
  /// When true, a successful Save as template from the footer closes the dialog.
  bool _closeDialogAfterSaveAs = false;
  /// When set, overrides [_currentRenameMode] (used by Save as template).
  _RenamePromptMode? _forcedRenameMode;
  TextEditingController? _renameCaptionStyleNameCtrl;
  List<CaptionStyleLibraryEntry> _captionStyleLibrary = const [];

  /// Caption screen: Personality / Keywords visibility (same prefs as Preferences dialog).

  /// When set, the dropdown shows this library entry; cleared for wire presets.
  String? _selectedSavedStyleId;

  /// Application sport (baseball / hockey / basketball / soccer) for defaults.
  String _sessionSport = 'baseball';

  /// Resolved game identifier per built-in wire for [_sessionSport].
  final Map<WireStyle, String> _gameIdByWire = {};

  /// Favorite caption-style menu token (per sport), shown with a star in the dropdown.
  String? _favoriteCaptionStyleToken;

  /// Scroll target for "edit snippets below" when tapping Caption Preview.
  final GlobalKey _structureSectionKey = GlobalKey();
  bool _structureHintFlash = false;

  /// Getty caption preview: American is City, State. International is City, Country.
  bool _gettyPreviewUnitedStates = true;

  /// Structure PREVIEW: colour-code slots like Structure chips.
  bool _structurePreviewColorCode = false;

  /// Getty note to user includes the NBAE copyright line.
  bool _gettyNoteIsNbae = false;

  /// Chip and preview span share this index while the pointer is over either.
  int? _linkedHoverIndex;

  /// Formula-editor ↔ preview hover (key + occurrence index).
  StructureHoverRef? _structureHoverRef;
  final GlobalKey<StructureFormulaFieldState> _structureFormulaFieldKey =
      GlobalKey<StructureFormulaFieldState>();

  /// Live formula text while the structure field is being edited (avoids
  /// cursor loss from apply→fromTemplate round-trips).
  String? _liveStructureFormula;

  String? _editingSepKey;
  final TextEditingController _sepEditCtrl = TextEditingController();

  /// Last home/away saved for the current sport, used when no teams are open.
  String? _savedExampleHome;
  String? _savedExampleAway;
  bool _exampleTeamsLoaded = false;
  /// League team names for the admin Structure team pickers.
  List<String> _adminTeamNames = const [];
  bool _adminTeamsLoading = false;
  String? _adminTeamsLoadedForSport;
  /// Live roster names for Shuffle sample (from selected / last teams).
  List<CaptionPreviewPlayer>? _rosterPreviewPlayers;
  bool _rosterPreviewLoading = false;
  int _rosterPreviewGen = 0;
  /// Home venue from the league API when available (e.g. MLB park name).
  String? _previewHomeVenue;
  Timer? _structureHintFlashTimer;

  /// Last Player Output toggle that changed — drives sample `.ch` flash (~900ms).
  String? _playerOutputFlashKey;
  Timer? _playerOutputFlashTimer;

  static const String _menuTokGetty = 'wire:getty';
  static const String _menuTokImagn = 'wire:imagn';
  static const String _menuTokAp = 'wire:ap';
  static const String _menuTokCp = 'wire:cp';
  static const String _menuTokGettyIntl = 'wire:getty_international';
  static const String _menuTokCustom = 'wire:custom';

  final List<TextEditingController> _gapControllers = [];
  final TextEditingController _layoutPrefixCtrl = TextEditingController();
  final TextEditingController _layoutSuffixCtrl = TextEditingController();
  final TextEditingController _bylinePrefixCtrl = TextEditingController();
  final TextEditingController _bylineBetweenCtrl = TextEditingController();
  final TextEditingController _bylineSuffixCtrl = TextEditingController();

  /// One controller per `BylineFieldKind.custom` occurrence in fieldOrder.
  final List<TextEditingController> _customChipCtrls = [];

  /// Controller for the [CaptionSegment.customText] ("Game identifier") field.
  /// Separate from [_customChipCtrls] which drive [BylineFieldKind.custom] in
  /// the credit line only.
  final TextEditingController _gameIdentifierCtrl = TextEditingController();

  /// Controllers for the typed-override byline fields.
  final TextEditingController _customCreatorCtrl = TextEditingController();
  final TextEditingController _customCreditCtrl = TextEditingController();

  /// Focus for the game identifier inline field inside the full-caption preview.
  final FocusNode _customNarrativeInlineFocus = FocusNode();

  /// Occurrence index of the custom chip whose text field is currently open.
  int? _editingCustomOccurrence;
  bool _syncingBylineCtrls = false;

  /// Structured date formula — kept for legacy decode / migration only.
  /// Live chips are Month / Day / Year (see [CaptionTemplate.expandDateSegments]).
  /// Seeded from [_template.dateFormula] on load, or [DateFormula.ap] as fallback.
  DateFormula _dateFormula = DateFormula.ap();

  @override
  void initState() {
    super.initState();
    final seeded = widget.previewPlayers;
    if (seeded != null && seeded.isNotEmpty) {
      _rosterPreviewPlayers = List<CaptionPreviewPlayer>.from(seeded);
    }
    _layoutPrefixCtrl.addListener(_onLayoutPrefixEdited);
    _layoutSuffixCtrl.addListener(_onLayoutSuffixEdited);
    _bylinePrefixCtrl.addListener(_onBylineTextEdited);
    _bylineBetweenCtrl.addListener(_onBylineTextEdited);
    _bylineSuffixCtrl.addListener(_onBylineTextEdited);
    _gameIdentifierCtrl.addListener(_onGameIdentifierEdited);
    _customCreatorCtrl.addListener(_onCustomCreatorEdited);
    _customCreditCtrl.addListener(_onCustomCreditEdited);
    _snippetLiteralCtrl.addListener(_onSnippetLiteralEdited);
    _freeTextCtrl.addListener(_onFreeTextEdited);
    _load = widget.adminMode ? _loadForAdmin() : _loadFromPrefs();
  }

  /// Latest wire / template after editors are flushed (for host publish).
  WireStyle get currentWire => _selectedWire;
  CaptionTemplate get currentTemplate => _template;

  /// Host wire/style picker (startup Caption style step) changed the active
  /// template. GlobalKey keeps this State alive across KeyedSubtree remounts,
  /// so we must apply [template] into live Structure + PREVIEW here.
  void applyHostCaptionTemplate(CaptionTemplate template) {
    var applied = CaptionTemplate.withSportGameIdentifierDefault(
      _deepCopyCaptionTemplate(template),
      _sessionSport,
      replaceKnownDefaults: false,
    ).normalizePerOccurrenceLists();
    applied = GettyNoteVariant.applyToTemplate(
      applied,
      nbae: GettyNoteVariant.applies(
        enabled: _gettyNoteIsNbae,
        wire: applied.wireStyle,
        sport: _sessionSport,
      ),
    );
    if (_prefsLoaded &&
        applied.wireStyle == _selectedWire &&
        _templateSnapshot(applied) == _templateSnapshot(_template) &&
        _liveStructureFormula == null) {
      return;
    }
    setState(() {
      _liveStructureFormula = null;
      _locationEditorOpen = false;
      _dateEditorOpen = false;
      _captionPreviewSelected = false;
      _venuePreviewSelected = false;
      _bylinePreviewSelected = false;
      _customTextSnippetEditorOpen = false;
      _freeTextSnippetEditorOpen = false;
      _separatorSnippetEditorOpen = false;
      _punctuationSnippetEditorOpen = false;
      _activeFormulaIndex = null;
      _focusedGapIndex = null;
      _disposeGapControllers();
      _selectedSavedStyleId = null;
      _template = applied;
      _selectedWire = applied.wireStyle;
      _gettyPreviewUnitedStates =
          applied.wireStyle != WireStyle.gettyInternational;
      if (applied.wireStyle == WireStyle.custom) {
        _lastPreset = _wiredBaseline(WireStyle.getty);
      } else {
        _lastPreset = _clonePreset(applied);
      }
      _initGapControllers(_template);
      _syncBylineControllersFromTemplate();
      _markStructureSaved(_template);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDateUiFromTemplate();
    });
  }

  /// Flushes pending edits (used before admin publish).
  Future<void> flushDraft() async {
    _flushAllEditorsIntoTemplate();
    await _persistCaptionLayoutToPreferences(
      syncBuiltInWireDefault: true,
      allowSkipIfUnchanged: false,
    );
    // Non-admin persist does not always notify; hosts that publish to Firebase
    // still need the latest template (notes, free-text, structure).
    widget.onDraftChanged?.call(_selectedWire, _template);
  }

  void _seedWireDefaultFromDraft(WireStyle wire, CaptionTemplate template) {
    final copy = _deepCopyCaptionTemplate(template).copyWith(wireStyle: wire);
    switch (wire) {
      case WireStyle.getty:
        _gettyWireDefault = copy;
        break;
      case WireStyle.imagn:
        _imagnWireDefault = copy;
        break;
      case WireStyle.ap:
        _apWireDefault = copy;
        break;
      case WireStyle.cp:
        _cpWireDefault = copy;
        break;
      case WireStyle.gettyInternational:
        _gettyIntlWireDefault = copy;
        break;
      case WireStyle.custom:
        break;
    }
  }

  Future<void> _loadGameIdByWire() async {
    _gameIdByWire.clear();
    if (widget.adminMode && widget.gameIdDraftsSeed != null) {
      for (final wire in AppDefaultsFirestoreService.captionWireStyles) {
        final fromDraft = widget.gameIdDraftsSeed![wire]?[_sessionSport]?.trim();
        _gameIdByWire[wire] = (fromDraft != null && fromDraft.isNotEmpty)
            ? fromDraft
            : defaultGameIdentifierText(_sessionSport);
      }
      return;
    }
    final prefs = await PreferencesService.getInstance();
    for (final wire in AppDefaultsFirestoreService.captionWireStyles) {
      _gameIdByWire[wire] =
          await prefs.resolveGameIdentifierText(wire, _sessionSport);
    }
  }

  Future<void> _loadForAdmin() async {
    _sessionSport = widget.initialSport ?? 'baseball';
    await _loadGameIdByWire();
    final wire = widget.initialWire ?? WireStyle.getty;
    _wireDrafts.clear();
    if (widget.wireDraftsSeed != null) {
      for (final entry in widget.wireDraftsSeed!.entries) {
        final copy =
            _deepCopyCaptionTemplate(entry.value).copyWith(wireStyle: entry.key);
        _wireDrafts[entry.key] = copy;
        _seedWireDefaultFromDraft(entry.key, copy);
      }
    }
    var template = widget.initialTemplate != null
        ? _deepCopyCaptionTemplate(widget.initialTemplate!)
        : _draftOrBaseline(wire);
    template = _withSessionSportGameId(template.copyWith(wireStyle: wire));
    final mergedGaps = CaptionFormulaRenderer.effectiveSegmentGaps(template);
    if (template.customSeparators == null ||
        template.customSeparators!.length != mergedGaps.length) {
      template = template.copyWith(customSeparators: mergedGaps);
    }
    template = template.normalizePerOccurrenceLists();
    final prefs = await PreferencesService.getInstance();
    _gettyNoteIsNbae = await prefs.getGettyNoteIsNbae();
    template = GettyNoteVariant.applyToTemplate(
      template,
      nbae: GettyNoteVariant.applies(
        enabled: _gettyNoteIsNbae,
        wire: wire,
        sport: _sessionSport,
      ),
    );
    if (!mounted) return;
    setState(() {
      _template = template;
      _selectedWire = wire;
      _gettyPreviewUnitedStates = wire != WireStyle.gettyInternational;
      _selectedSavedStyleId = null;
      _lastPreset = _clonePreset(template);
      _initGapControllers(_template);
      _syncBylineControllersFromTemplate();
      _prefsLoaded = true;
      _markStructureSaved(_template);
    });
    widget.onRegisterFlush?.call(flushDraft);
    widget.onRegisterSetAllDefaults?.call(_setAllStylesAsDefaults);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDateUiFromTemplate();
    });
    await _refreshRosterPreviewPlayers();
  }

  /// Rebuilds local editor state from [_template]. Called after prefs load and
  /// after a wire-style swap. Any legacy [CaptionTemplate.dateExpression] is
  /// discarded in favour of the structured formula (which is the only editor
  /// surface now).
  void _syncDateUiFromTemplate() {
    setState(() {
      DateFormula? src;
      if (_dateEditorOpen &&
          _activeFormulaIndex != null &&
          _activeFormulaIndex! < _template.segmentOrder.length &&
          _template.segmentOrder[_activeFormulaIndex!] == CaptionSegment.date) {
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            _template.segmentOrder, _activeFormulaIndex!, CaptionSegment.date);
        src = CaptionFormulaRenderer.dateFormulaForOccurrence(_template, occ);
      } else {
        src = _template.dateFormula;
      }
      if (src != null && src.fields.isNotEmpty) {
        _dateFormula = src.clone();
        if (_template.dateExpression.isNotEmpty) {
          _template = _template.copyWith(dateExpression: '');
        }
        return;
      }
      _dateFormula = DateFormula.ap();
      _template = _template.copyWith(
        dateFormula: _dateFormula.clone(),
        dateExpression: '',
      );
    });
  }

  @override
  void didUpdateWidget(covariant CaptionLayoutBuilderDialog oldWidget) {
    super.didUpdateWidget(oldWidget);

    final teamsChanged =
        widget.previewHomeTeam != oldWidget.previewHomeTeam ||
            widget.previewAwayTeam != oldWidget.previewAwayTeam;
    if (teamsChanged) {
      unawaited(_refreshRosterPreviewPlayers());
    }

    // Startup host wire picker updates initialTemplate; GlobalKey preserves
    // this State, so apply when the wire actually changes (not every draft).
    if (_isSessionStartupEmbed && _prefsLoaded) {
      final incoming = widget.initialTemplate;
      if (incoming != null && incoming.wireStyle != _selectedWire) {
        applyHostCaptionTemplate(incoming);
      }
    }

    if (!widget.adminMode) return;

    final sportChanged = widget.initialSport != null &&
        widget.initialSport != oldWidget.initialSport;
    if (sportChanged) {
      unawaited(_applyAdminSportChange());
    }
  }

  /// Parent sport changed — load that sport’s Structure draft + preview sample.
  Future<void> _applyAdminSportChange() async {
    _sessionSport = widget.initialSport ?? _sessionSport;
    await _loadGameIdByWire();
    if (!mounted) return;
    final seeded = widget.wireDraftsSeed?[_selectedWire] ??
        widget.initialTemplate;
    final gid = _gameIdByWire[_selectedWire] ??
        seeded?.gameIdentifierText ??
        defaultGameIdentifierText(_sessionSport);
    setState(() {
      if (seeded != null) {
        _template = seeded.copyWith(
          wireStyle: _selectedWire,
          gameIdentifierText: gid,
        );
        _wireDrafts[_selectedWire] = _template;
      } else {
        _template = _template.copyWith(gameIdentifierText: gid);
      }
      if (_gameIdentifierCtrl.text != gid) {
        _gameIdentifierCtrl.text = gid;
      }
      _captionSampleSeed =
          DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
      _exampleTeamsLoaded = false;
      _adminTeamsLoadedForSport = null;
      _rosterPreviewPlayers = null;
      _rosterPreviewLoading = false;
      _previewHomeVenue = null;
    });
    _syncBylineControllersFromTemplate();
    _ensureExampleTeams();
    unawaited(_loadAdminPreviewTeamList(force: true));
    unawaited(_refreshRosterPreviewPlayers(clearFirst: true));
  }

  void _syncBylineControllersFromTemplate() {
    _syncingBylineCtrls = true;
    _bylinePrefixCtrl.text = _template.bylineOptions.prefix;
    _bylineBetweenCtrl.text = _template.bylineOptions.between;
    _bylineSuffixCtrl.text = _template.bylineOptions.suffix;
    // Sync the standalone game identifier controller.
    if (_gameIdentifierCtrl.text != _template.gameIdentifierText) {
      _gameIdentifierCtrl.text = _template.gameIdentifierText;
    }
    // Sync custom creator / credit controllers.
    if (_customCreatorCtrl.text != _template.bylineOptions.customCreatorText) {
      _customCreatorCtrl.text = _template.bylineOptions.customCreatorText;
    }
    if (_customCreditCtrl.text != _template.bylineOptions.customCreditText) {
      _customCreditCtrl.text = _template.bylineOptions.customCreditText;
    }

    final customCount = _template.bylineOptions.fieldOrder
        .where((k) => k == BylineFieldKind.custom)
        .length;
    final texts = _template.bylineOptions.customTexts;

    // Grow controller list if needed
    while (_customChipCtrls.length < customCount) {
      final ctrl = TextEditingController();
      ctrl.addListener(_onBylineTextEdited);
      _customChipCtrls.add(ctrl);
    }
    // Shrink controller list if needed
    while (_customChipCtrls.length > customCount) {
      final ctrl = _customChipCtrls.removeLast();
      ctrl.removeListener(_onBylineTextEdited);
      ctrl.dispose();
    }
    for (var i = 0; i < _customChipCtrls.length; i++) {
      _customChipCtrls[i].text = i < texts.length ? texts[i] : '';
    }
    _syncingBylineCtrls = false;
  }

  void _onBylineTextEdited() {
    if (_syncingBylineCtrls) return;
    setState(() {
      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(
          prefix: _bylinePrefixCtrl.text,
          between: _bylineBetweenCtrl.text,
          suffix: _bylineSuffixCtrl.text,
          customTexts: _customChipCtrls.map((c) => c.text).toList(),
        ),
      );
    });
  }

  void _onGameIdentifierEdited() {
    if (_syncingBylineCtrls) return;
    setState(() {
      _template = _template.copyWith(
        gameIdentifierText: _gameIdentifierCtrl.text,
      );
    });
    if (widget.adminMode) {
      widget.onDraftChanged?.call(
        _selectedWire,
        _template.normalizePerOccurrenceLists(),
      );
    } else {
      _scheduleAutosave();
    }
  }

  void _onCustomCreatorEdited() {
    if (_syncingBylineCtrls) return;
    setState(() {
      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(
          customCreatorText: _customCreatorCtrl.text,
        ),
      );
    });
  }

  void _onCustomCreditEdited() {
    if (_syncingBylineCtrls) return;
    setState(() {
      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(
          customCreditText: _customCreditCtrl.text,
        ),
      );
    });
  }

  void _closeAllInlineEdits() {
    setState(() {
      _locationEditorOpen = false;
      _dateEditorOpen = false;
      _captionPreviewSelected = false;
      _venuePreviewSelected = false;
      _bylinePreviewSelected = false;
      _customTextSnippetEditorOpen = false;
      _freeTextSnippetEditorOpen = false;
      _separatorSnippetEditorOpen = false;
      _punctuationSnippetEditorOpen = false;
      _activeFormulaIndex = null;
      _focusedGapIndex = null;
      _focusedGlueSegmentIndex = null;
    });
  }

  void _activateFormulaEditor({
    required int index,
    required CaptionSegment segment,
  }) {
    if (_coreStyleLocked) return;
    // Combined Date chips are never edited as one block — expand first.
    if (segment == CaptionSegment.date) {
      _initGapControllers(_template);
      final mi = _template.segmentOrder.indexWhere(_isDatePartSegment);
      if (mi < 0) return;
      _activateFormulaEditor(
        index: mi,
        segment: _template.segmentOrder[mi],
      );
      return;
    }
    // Legacy "Game identifier" → typed free text in the same slot.
    if (segment == CaptionSegment.customText) {
      final migrated =
          _template.migrateGameIdentifierToFreeText().normalizePerOccurrenceLists();
      if (!identical(migrated, _template)) {
        setState(() {
          _template = migrated;
          _initGapControllers(_template);
        });
      }
      if (index < 0 || index >= _template.segmentOrder.length) return;
      _activateFormulaEditor(
        index: index,
        segment: _template.segmentOrder[index],
      );
      return;
    }
    // Typed text is edited inline in the structure strip — no options panel.
    if (_isInlineTypedSegment(segment)) {
      _initGapControllers(_template);
      final focus = _glueFocusNodes[index];
      setState(() {
        _focusedGlueSegmentIndex = index;
        _activeFormulaIndex = null;
        _locationEditorOpen = false;
        _dateEditorOpen = false;
        _captionPreviewSelected = false;
        _venuePreviewSelected = false;
        _bylinePreviewSelected = false;
        _customTextSnippetEditorOpen = false;
        _freeTextSnippetEditorOpen = false;
        _separatorSnippetEditorOpen = false;
        _punctuationSnippetEditorOpen = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focus?.requestFocus();
      });
      return;
    }
    setState(() {
      final currentlyActive = _activeFormulaIndex == index;
      final sameModeActive =
          (_isGeoFieldSegment(segment) && _locationEditorOpen) ||
              (_isDatePartSegment(segment) && _dateEditorOpen) ||
              (segment == CaptionSegment.caption && _captionPreviewSelected) ||
              (segment == CaptionSegment.venue && _venuePreviewSelected) ||
              (segment == CaptionSegment.credit && _bylinePreviewSelected) ||
              (segment == CaptionSegment.customText &&
                  (_customTextSnippetEditorOpen ||
                      (_singleCustomNarrativeInlineEligible &&
                          _activeFormulaIndex == index))) ||
              (segment == CaptionSegment.freeText &&
                  _freeTextSnippetEditorOpen) ||
              (segment == CaptionSegment.separator &&
                  _separatorSnippetEditorOpen) ||
              (segment == CaptionSegment.punctuation &&
                  _punctuationSnippetEditorOpen);
      if (currentlyActive && sameModeActive) {
        _locationEditorOpen = false;
        _dateEditorOpen = false;
        _captionPreviewSelected = false;
        _venuePreviewSelected = false;
        _bylinePreviewSelected = false;
        _customTextSnippetEditorOpen = false;
        _freeTextSnippetEditorOpen = false;
        _separatorSnippetEditorOpen = false;
        _punctuationSnippetEditorOpen = false;
        _activeFormulaIndex = null;
        _focusedGapIndex = null;
        _focusedGlueSegmentIndex = null;
        _layoutPrefixFocused = false;
        _layoutSuffixFocused = false;
        return;
      }
      _activeFormulaIndex = index;
      _focusedGapIndex = null;
      _focusedGlueSegmentIndex = null;
      _layoutPrefixFocused = false;
      _layoutSuffixFocused = false;
      _locationEditorOpen = _isGeoFieldSegment(segment);
      _dateEditorOpen = _isDatePartSegment(segment);
      _captionPreviewSelected = segment == CaptionSegment.caption;
      _venuePreviewSelected = segment == CaptionSegment.venue;
      _bylinePreviewSelected = segment == CaptionSegment.credit;
      // Multi–custom narrative still uses the panel editor; single custom is inline in preview.
      _customTextSnippetEditorOpen = segment == CaptionSegment.customText &&
          !_singleCustomNarrativeInlineEligible;
      _freeTextSnippetEditorOpen = segment == CaptionSegment.freeText;
      _separatorSnippetEditorOpen = segment == CaptionSegment.separator;
      _punctuationSnippetEditorOpen = segment == CaptionSegment.punctuation;
      if (_separatorSnippetEditorOpen || _punctuationSnippetEditorOpen) {
        _syncingSnippetLiteralCtrl = true;
        if (segment == CaptionSegment.separator) {
          _snippetLiteralCtrl.text =
              CaptionFormulaRenderer.separatorSnippetFor(_template, index);
        } else {
          _snippetLiteralCtrl.text =
              CaptionFormulaRenderer.punctuationSnippetFor(_template, index);
        }
        _syncingSnippetLiteralCtrl = false;
      }
      if (_freeTextSnippetEditorOpen) {
        _syncingFreeTextCtrl = true;
        _freeTextCtrl.text =
            CaptionFormulaRenderer.freeTextBodyFor(_template, index);
        _syncingFreeTextCtrl = false;
      }
    });
    if (segment == CaptionSegment.customText &&
        _singleCustomNarrativeInlineEligible &&
        _activeFormulaIndex == index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _customNarrativeInlineFocus.requestFocus();
      });
    }
  }

  void _toggleBylineFieldCaps(BylineFieldKind kind) {
    setState(() {
      final o = _template.bylineOptions;
      switch (kind) {
        case BylineFieldKind.name:
          _template = _template.copyWith(
            bylineOptions: o.copyWith(nameCaps: !o.nameCaps),
          );
          break;
        case BylineFieldKind.credit:
          _template = _template.copyWith(
            bylineOptions: o.copyWith(
              creditCaps: !o.creditCaps,
              organizationCaps: !o.creditCaps,
            ),
          );
          break;
        case BylineFieldKind.copyright:
          _template = _template.copyWith(
            bylineOptions: o.copyWith(copyrightCaps: !o.copyrightCaps),
          );
          break;
        case BylineFieldKind.customCreator:
          _template = _template.copyWith(
            bylineOptions: o.copyWith(nameCaps: !o.nameCaps),
          );
          break;
        case BylineFieldKind.customCredit:
          _template = _template.copyWith(
            bylineOptions: o.copyWith(
              creditCaps: !o.creditCaps,
              organizationCaps: !o.creditCaps,
            ),
          );
          break;
        case BylineFieldKind.custom:
          break;
      }
    });
  }

  /// View-order for the byline editor: the persisted [fieldOrder], with any
  /// canonical kinds (name / credit) that aren't already present appended at
  /// the end. The editor always shows these two so users can toggle them
  /// on/off without needing an "Add field" picker.
  /// [customCreator] and [customCredit] are optional — only shown when added.
  List<BylineFieldKind> _bylineViewOrder() {
    final saved = _template.bylineOptions.fieldOrder;
    final result = List<BylineFieldKind>.from(saved);
    for (final k in const [
      BylineFieldKind.name,
      BylineFieldKind.credit,
    ]) {
      if (!result.contains(k)) result.add(k);
    }
    return result;
  }

  /// Toggle whether [kind] renders in the byline. Always promotes [kind] into
  /// the persisted [fieldOrder] (at the position implied by the editor's
  /// view-order) so its slot survives toggling, exactly like the location
  /// editor's per-chip switch.
  void _setBylineKindEnabled(BylineFieldKind kind, bool enabled) {
    if (kind == BylineFieldKind.custom) return;
    setState(() {
      final view = _bylineViewOrder();
      final order = List<BylineFieldKind>.from(view);
      final disabled = Set<BylineFieldKind>.from(
        _template.bylineOptions.disabledKinds,
      );
      if (enabled) {
        disabled.remove(kind);
      } else {
        disabled.add(kind);
      }
      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(
          fieldOrder: order,
          disabledKinds: disabled,
        ),
      );
    });
  }

  /// Drag-reorder operating on view-order indices. On first reorder, this
  /// also promotes any canonical kinds that were only in the view (not yet
  /// persisted) into [fieldOrder] so the position survives saves.
  void _reorderBylineFromView(int viewFrom, int viewTo) {
    if (viewFrom == viewTo) return;
    setState(() {
      final view = _bylineViewOrder();
      if (viewFrom < 0 || viewFrom >= view.length) return;
      // "Drop chip X onto chip Y" semantic: X lands AT Y's slot in the
      // post-removal list. See location_formula_editor._reorder for why we
      // do NOT subtract 1 when moving right (that's why dragging chips to
      // the right used to look like a no-op).
      final moved = view.removeAt(viewFrom);
      var insert = viewTo;
      if (insert < 0) insert = 0;
      if (insert > view.length) insert = view.length;
      view.insert(insert, moved);

      // Map custom occurrences across the move so each custom chip's text
      // travels with it (mirrors the existing _reorderBylineField logic).
      final savedOrder = _template.bylineOptions.fieldOrder;
      var customTexts = List<String>.from(_template.bylineOptions.customTexts);
      if (moved == BylineFieldKind.custom) {
        // Original occurrence index in the saved order. The editor view is
        // saved + appended-canonical-missing, and customs only live in
        // saved, so the from-occurrence is just "how many customs precede
        // viewFrom in the original saved order". Walk the original saved
        // order until we've seen viewFrom-many chips that match positions
        // in the view.
        final fromOcc = _customOccurrenceAt(
            savedOrder, viewFrom.clamp(0, savedOrder.length));
        // Compute target occurrence: count customs that appear before
        // `insert` in the new view-order, excluding the moved chip itself.
        var toOcc = 0;
        for (var i = 0; i < insert; i++) {
          if (view[i] == BylineFieldKind.custom) toOcc++;
        }
        if (fromOcc < customTexts.length && fromOcc != toOcc) {
          final text = customTexts.removeAt(fromOcc);
          customTexts.insert(toOcc.clamp(0, customTexts.length), text);
          if (fromOcc < _customChipCtrls.length) {
            final ctrl = _customChipCtrls.removeAt(fromOcc);
            _customChipCtrls.insert(
                toOcc.clamp(0, _customChipCtrls.length), ctrl);
          }
          if (_editingCustomOccurrence == fromOcc) {
            _editingCustomOccurrence = toOcc;
          }
        }
      }

      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(
          fieldOrder: view,
          customTexts: customTexts,
        ),
      );
    });
  }

  /// Ensures the byline has at least one custom field so the caption-layout
  /// custom-text snippet editor can show a [TextField] immediately (no extra
  /// "add field" step). Call only from within an existing [setState].
  void _ensureAtLeastOneBylineCustomField() {
    if (_customChipCtrls.isNotEmpty) return;
    final order =
        List<BylineFieldKind>.from(_template.bylineOptions.fieldOrder);
    var customTexts = List<String>.from(_template.bylineOptions.customTexts);
    customTexts.add('');
    final ctrl = TextEditingController();
    ctrl.addListener(_onBylineTextEdited);
    _customChipCtrls.add(ctrl);
    _editingCustomOccurrence = 0;
    order.add(BylineFieldKind.custom);
    _template = _template.copyWith(
      bylineOptions: _template.bylineOptions.copyWith(
        fieldOrder: order,
        customTexts: customTexts,
      ),
    );
  }

  void _addBylineField(BylineFieldKind kind) {
    final order =
        List<BylineFieldKind>.from(_template.bylineOptions.fieldOrder);
    // Non-custom fields are unique; custom chips can appear multiple times.
    if (kind != BylineFieldKind.custom && order.contains(kind)) return;
    setState(() {
      order.add(kind);
      var customTexts = List<String>.from(_template.bylineOptions.customTexts);
      if (kind == BylineFieldKind.custom) {
        customTexts.add('');
        final ctrl = TextEditingController();
        ctrl.addListener(_onBylineTextEdited);
        _customChipCtrls.add(ctrl);
        // Auto-expand the new chip for editing
        _editingCustomOccurrence = _customChipCtrls.length - 1;
      }
      // customCreator / customCredit store text in their own fields — no
      // customTexts entry needed.
      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(
          fieldOrder: order,
          customTexts: customTexts,
        ),
      );
    });
  }

  /// Returns the occurrence index (0-based) of [fieldOrder[chipIndex]] among
  /// chips of the same kind that appear before [chipIndex].
  int _customOccurrenceAt(List<BylineFieldKind> order, int chipIndex) {
    int occ = 0;
    for (var i = 0; i < chipIndex; i++) {
      if (order[i] == BylineFieldKind.custom) occ++;
    }
    return occ;
  }

  void _removeBylineFieldAt(int chipIndex) {
    final order =
        List<BylineFieldKind>.from(_template.bylineOptions.fieldOrder);
    if (chipIndex < 0 || chipIndex >= order.length) return;
    final kind = order[chipIndex];
    if (kind == BylineFieldKind.name) return;
    setState(() {
      order.removeAt(chipIndex);
      var customTexts = List<String>.from(_template.bylineOptions.customTexts);
      if (kind == BylineFieldKind.custom) {
        final occ =
            _customOccurrenceAt(_template.bylineOptions.fieldOrder, chipIndex);
        if (occ < customTexts.length) customTexts.removeAt(occ);
        if (occ < _customChipCtrls.length) {
          _customChipCtrls[occ].removeListener(_onBylineTextEdited);
          _customChipCtrls[occ].dispose();
          _customChipCtrls.removeAt(occ);
        }
        if (_editingCustomOccurrence != null) {
          if (_editingCustomOccurrence == occ) {
            _editingCustomOccurrence = null;
          } else if (_editingCustomOccurrence! > occ) {
            _editingCustomOccurrence = _editingCustomOccurrence! - 1;
          }
        }
      }
      _template = _template.copyWith(
        bylineOptions: _template.bylineOptions.copyWith(
          fieldOrder: order,
          customTexts: customTexts,
        ),
      );
    });
  }

  CaptionTemplate _withSessionSportGameId(CaptionTemplate t) {
    // Named library styles and Custom keep authored game-ID / free-text.
    if (_selectedSavedStyleId != null || t.isUserAuthoredCaptionStyle) {
      return CaptionTemplate.withSportGameIdentifierDefault(
        t,
        _sessionSport,
        replaceKnownDefaults: false,
      );
    }
    // Wire masters stay bare — Game ID is added on the start screen later.
    return t.stripGameIdentifierForWireMaster();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await PreferencesService.getInstance();
    final initial = widget.initialSport?.trim() ?? '';
    _sessionSport = initial.isNotEmpty
        ? initial
        : await prefs.getCurrentSport();
    final lastTeams = await prefs.getStartupLastTeams(sport: _sessionSport);
    _savedExampleHome = lastTeams.key;
    _savedExampleAway = lastTeams.value;
    _exampleTeamsLoaded = true;
    await _loadGameIdByWire();
    _favoriteCaptionStyleToken =
        await prefs.getFavoriteCaptionStyleToken(sport: _sessionSport);
    _gettyNoteIsNbae = await prefs.getGettyNoteIsNbae();
    // Promote any legacy "Getty International" library entry before we read
    // the library so it doesn't show up alongside the new built-in wire.
    await prefs.migrateGettyInternationalLibraryEntry();
    await prefs.cementGettyFactoryDefaultsIfNeeded();
    var template = _withSessionSportGameId(await prefs.getCaptionTemplate());
    final mergedGaps = CaptionFormulaRenderer.effectiveSegmentGaps(template);
    if (template.customSeparators == null ||
        template.customSeparators!.length != mergedGaps.length) {
      template = template.copyWith(customSeparators: mergedGaps);
    }
    template = template.normalizePerOccurrenceLists();
    template = GettyNoteVariant.applyToTemplate(
      template,
      nbae: GettyNoteVariant.applies(
        enabled: _gettyNoteIsNbae,
        wire: template.wireStyle,
        sport: _sessionSport,
      ),
    );
    var gameInfo = await prefs.getCaptionGameInfo();
    // Fold IPTC Location from the active wire preset into preview GameInfo so
    // the Location structure chip resolves even without a live photo.
    try {
      final preset = await prefs.getIptcWirePreset(template.wireStyle);
      if (preset.isNotEmpty) {
        final fromPanel =
            IptcTemplateApplyService.gameInfoFromPanelValues(
          IptcTemplateApplyService.denormalizeForPanel(preset),
        );
        final loc = fromPanel.venue.trim();
        if (loc.isNotEmpty) {
          final base = gameInfo ?? _baseMockGameInfo;
          if (!CaptionFormulaRenderer.hasIptcLocation(base)) {
            gameInfo = base.copyWith(
              venue: base.venue.trim().isNotEmpty ? base.venue : loc,
              iptcMetadata: CaptionFormulaRenderer.iptcLocationMetadata(
                loc,
                base.iptcMetadata,
              ),
            );
          }
        }
      }
    } catch (_) {}
    final adminWires = AppDefaultsFirestoreService.mergedCaptionWireDefaults(
      sport: _sessionSport.isEmpty ? 'baseball' : _sessionSport,
    );
    final gettyDef = adminWires[WireStyle.getty];
    final imagnDef = adminWires[WireStyle.imagn];
    final apDef = adminWires[WireStyle.ap];
    final cpDef = adminWires[WireStyle.cp];
    final gettyIntlDef = adminWires[WireStyle.gettyInternational];
    final styleLib = await prefs.getCaptionStyleLibrary();
    final gettyLabel = await prefs.getCaptionWireLabel(WireStyle.getty);
    final imagnLabel = await prefs.getCaptionWireLabel(WireStyle.imagn);
    final apLabel = await prefs.getCaptionWireLabel(WireStyle.ap);
    final cpLabel = await prefs.getCaptionWireLabel(WireStyle.cp);
    final gettyIntlLabel =
        await prefs.getCaptionWireLabel(WireStyle.gettyInternational);
    if (!mounted) return;
    setState(() {
      _loadedGameInfo = gameInfo;
      _gettyWireDefault = gettyDef;
      _imagnWireDefault = imagnDef;
      _apWireDefault = apDef;
      _cpWireDefault = cpDef;
      _gettyIntlWireDefault = gettyIntlDef;
      _gettyWireLabel = gettyLabel;
      _imagnWireLabel = imagnLabel;
      _apWireLabel = apLabel;
      _cpWireLabel = cpLabel;
      _gettyIntlWireLabel = gettyIntlLabel;
      _captionStyleLibrary = styleLib;
      _template = template;
      _selectedWire = template.wireStyle;
      _gettyPreviewUnitedStates =
          template.wireStyle != WireStyle.gettyInternational;
      _selectedSavedStyleId =
          _libraryEntryIdMatchingActiveTemplate(template, styleLib);
      if (template.wireStyle == WireStyle.custom) {
        _lastPreset = _wiredBaseline(WireStyle.getty);
      } else {
        _lastPreset = _clonePreset(template);
      }
      _initGapControllers(_template);
      _syncBylineControllersFromTemplate();
      _prefsLoaded = true;
      _markStructureSaved(_template);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDateUiFromTemplate();
    });
    await _refreshRosterPreviewPlayers();
  }

  Future<void> _toggleFavoriteCaptionStyle(String token) async {
    if (widget.adminMode) return;
    final prefs = await PreferencesService.getInstance();
    setState(() {
      if (_favoriteCaptionStyleToken == token) {
        _favoriteCaptionStyleToken = null;
      } else {
        _favoriteCaptionStyleToken = token;
      }
    });
    await prefs.saveFavoriteCaptionStyleToken(
      _favoriteCaptionStyleToken,
      sport: _sessionSport,
    );
  }

  String _templateSnapshot([CaptionTemplate? t]) {
    final source = t ?? _template;
    return jsonEncode(source.toJson());
  }

  String _structureFormulaOf(CaptionTemplate t) {
    return StructureFormula.ensureCaption(
      StructureFormula.withoutLeagueTokens(
        StructureFormula.fromTemplate(t, sport: _sessionSport),
        sport: _sessionSport,
      ),
    );
  }

  void _markStructureSaved([CaptionTemplate? t]) {
    final source = t ?? _template;
    _lastSavedTemplateSnapshot = _templateSnapshot(source);
    _lastSavedStructureFormula = _structureFormulaOf(source);
  }

  /// Ensures [customSeparators] matches the live gap text fields before encoding.
  void _flushGapControllersIntoTemplate() {
    if (_gapControllers.isEmpty) return;
    _template = _template.copyWith(
      customSeparators: _gapControllers.map((c) => c.text).toList(),
    );
  }

  /// Writes the current layout to preferences (active template, optional library row,
  /// field visibility). [syncBuiltInWireDefault] updates the per-wire baseline when
  /// editing a built-in wire (not a named library style).
  Future<void> _persistCaptionLayoutToPreferences({
    bool syncBuiltInWireDefault = false,
    bool allowSkipIfUnchanged = true,
  }) async {
    _autosaveDebounce?.cancel();
    _flushGapControllersIntoTemplate();
    final normalized = _template.normalizePerOccurrenceLists();
    final saveSnapshot = _templateSnapshot(normalized);
    if (allowSkipIfUnchanged &&
        saveSnapshot == _lastSavedTemplateSnapshot &&
        !syncBuiltInWireDefault) {
      return;
    }
    if (widget.adminMode) {
      if (syncBuiltInWireDefault &&
          _isBuiltInWire(_selectedWire) &&
          _selectedSavedStyleId == null) {
        _wireDrafts[_selectedWire] = _deepCopyCaptionTemplate(normalized);
        _seedWireDefaultFromDraft(_selectedWire, normalized);
      }
      widget.onDraftChanged?.call(_selectedWire, normalized);
      _template = normalized;
      _markStructureSaved(normalized);
      if (mounted) {
        setState(() {});
      }
      return;
    }
    final prefs = await PreferencesService.getInstance();
    await prefs.saveCaptionTemplate(normalized);
    if (syncBuiltInWireDefault &&
        _isBuiltInWire(_selectedWire) &&
        _selectedSavedStyleId == null) {
      await prefs.saveCaptionTemplateWireDefault(_selectedWire, normalized);
      _seedWireDefaultFromDraft(_selectedWire, normalized);
    }

    final libId = _selectedSavedStyleId;
    if (libId != null) {
      await prefs.updateCaptionStyleTemplateInLibrary(
        id: libId,
        template: normalized,
      );
    }

    _template = normalized;
    _markStructureSaved(normalized);

    List<CaptionStyleLibraryEntry>? refreshedLib;
    if (libId != null) {
      refreshedLib = await prefs.getCaptionStyleLibrary();
    }
    if (!mounted) return;
    final lib = refreshedLib;
    if (lib != null) {
      setState(() => _captionStyleLibrary = lib);
    }
  }

  /// Writes the open layout into the working caption template. Used when this
  /// editor is embedded in Preferences, so leaving the section keeps the edit.
  Future<void> persistEmbeddedEdits() async {
    if (!widget.embedded || widget.adminMode || !_prefsLoaded) return;
    if (_requiresSaveAsNewStyle) return;
    _autosaveDebounce?.cancel();
    _flushAllEditorsIntoTemplate();
    await _persistCaptionLayoutToPreferences(
      syncBuiltInWireDefault: false,
      allowSkipIfUnchanged: true,
    );
  }

  void _scheduleAutosave() {
    // Nocturne editor (admin + user) uses explicit Save as default / Discard.
  }

  CreditSampleAgency _sampleAgencyForWire(WireStyle w) {
    switch (w) {
      case WireStyle.getty:
      case WireStyle.gettyInternational:
        return CreditSampleAgency.gettyImages;
      case WireStyle.imagn:
        return CreditSampleAgency.imagn;
      case WireStyle.ap:
      case WireStyle.cp:
        return CreditSampleAgency.ap;
      case WireStyle.custom:
        return CreditSampleAgency.gettyImages;
    }
  }

  String _factoryWireLabel(WireStyle w) {
    switch (w) {
      case WireStyle.getty:
      case WireStyle.gettyInternational:
        return 'Getty';
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

  String? _wireLabelOverride(WireStyle w) {
    switch (w) {
      case WireStyle.getty:
        return _gettyWireLabel;
      case WireStyle.imagn:
        return _imagnWireLabel;
      case WireStyle.ap:
        return _apWireLabel;
      case WireStyle.cp:
        return _cpWireLabel;
      case WireStyle.gettyInternational:
        return _gettyIntlWireLabel ?? _gettyWireLabel;
      case WireStyle.custom:
        return null;
    }
  }

  String _wireStyleDropdownLabel(WireStyle w) {
    final override = _wireLabelOverride(w);
    if (override != null && override.isNotEmpty) {
      final lower = override.trim().toLowerCase();
      if (lower == 'getty usa' ||
          lower == 'getty international' ||
          lower == 'getty images') {
        return _factoryWireLabel(w);
      }
      return override.trim();
    }
    return _factoryWireLabel(w);
  }

  String _wireMenuToken(WireStyle w) {
    switch (w) {
      case WireStyle.getty:
      case WireStyle.gettyInternational:
        return _menuTokGetty;
      case WireStyle.imagn:
        return _menuTokImagn;
      case WireStyle.ap:
        return _menuTokAp;
      case WireStyle.cp:
        return _menuTokCp;
      case WireStyle.custom:
        return _menuTokCustom;
    }
  }

  WireStyle _wireStyleFromMenuToken(String token) {
    switch (token) {
      case _menuTokImagn:
        return WireStyle.imagn;
      case _menuTokAp:
        return WireStyle.ap;
      case _menuTokCp:
        return WireStyle.cp;
      case _menuTokGettyIntl:
        // Legacy token → unified Getty.
        return WireStyle.getty;
      case _menuTokCustom:
        return WireStyle.custom;
      case _menuTokGetty:
      default:
        return WireStyle.getty;
    }
  }

  List<String> _captionStyleDropdownTokens() {
    if (widget.adminMode) {
      return const [
        _menuTokGetty,
        _menuTokImagn,
        _menuTokAp,
        _menuTokCp,
      ];
    }
    final saved = _captionStyleLibrary
        .map((e) => 'saved:${e.id}')
        .toList()
      ..sort(
        (a, b) => _captionStyleMenuLabel(a)
            .toLowerCase()
            .compareTo(_captionStyleMenuLabel(b).toLowerCase()),
      );
    return [
      _menuTokGetty,
      _menuTokImagn,
      _menuTokAp,
      _menuTokCp,
      _menuTokCustom,
      ...saved,
    ];
  }

  /// Built-in Getty / Imagn / AP / CP match the published admin originals.
  /// User edits are kept only as a new saved style. Admin can still publish
  /// the wire defaults.
  bool get _requiresSaveAsNewStyle =>
      !widget.adminMode &&
      _selectedSavedStyleId == null &&
      _isBuiltInWire(_selectedWire);

  /// Legacy name kept for call sites that gated editing. Built-ins are no longer
  /// read-only; use [_requiresSaveAsNewStyle] for autosave / discard rules.
  bool get _coreStyleLocked => false;

  /// Built-ins are editable; no longer shown as locked in the menu.
  bool _tokenIsLockedCore(String token) => false;

  /// No-op wrapper (built-ins are editable). Kept so call sites stay stable.
  Widget _lockableEditorSurface({required Widget child}) => child;

  CaptionStyleLibraryEntry? _entryForSavedStyleToken(String token) {
    if (!token.startsWith('saved:')) return null;
    final id = token.substring(6);
    for (final e in _captionStyleLibrary) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// When the active caption template was saved from a library row, [CaptionTemplate.id]
  /// matches that row — set [_selectedSavedStyleId] so Rename / Delete apply.
  ///
  /// Do not match nested [CaptionTemplate.id] values like `preset_getty` or
  /// full JSON equality — those false positives made Done update a library
  /// row instead of promoting the live style to Custom.
  String? _libraryEntryIdMatchingActiveTemplate(
    CaptionTemplate template,
    List<CaptionStyleLibraryEntry> lib,
  ) {
    for (final e in lib) {
      if (e.id == template.id) return e.id;
    }
    return null;
  }

  String _captionStyleMenuLabel(String token) {
    final saved = _entryForSavedStyleToken(token);
    if (saved != null) return saved.displayName;
    switch (token) {
      case _menuTokGetty:
        return _wireStyleDropdownLabel(WireStyle.getty);
      case _menuTokImagn:
        return _wireStyleDropdownLabel(WireStyle.imagn);
      case _menuTokAp:
        return _wireStyleDropdownLabel(WireStyle.ap);
      case _menuTokCp:
        return _wireStyleDropdownLabel(WireStyle.cp);
      case _menuTokGettyIntl:
        return _wireStyleDropdownLabel(WireStyle.gettyInternational);
      case _menuTokCustom:
        return _wireStyleDropdownLabel(WireStyle.custom);
      default:
        return token;
    }
  }

  String _captionStyleDropdownInitialToken() {
    // USA / International share the Getty menu row; the pills pick the wire.
    if (_selectedSavedStyleId == null &&
        (_selectedWire == WireStyle.getty ||
            _selectedWire == WireStyle.gettyInternational)) {
      return _menuTokGetty;
    }
    if (_selectedSavedStyleId != null) {
      final t = 'saved:$_selectedSavedStyleId';
      if (_captionStyleDropdownTokens().contains(t)) return t;
    }
    return _wireMenuToken(_selectedWire);
  }

  void _applyCaptionStyleMenuToken(String? token) {
    if (token == null) return;
    if (token.startsWith('saved:')) {
      final entry = _entryForSavedStyleToken(token);
      if (entry == null) return;
      // Keep the authored game-ID / custom text; only fill when empty.
      final applied = CaptionTemplate.withSportGameIdentifierDefault(
        _deepCopyCaptionTemplate(entry.template),
        _sessionSport,
        replaceKnownDefaults: false,
      );
      setState(() {
        _locationEditorOpen = false;
        _dateEditorOpen = false;
        _captionPreviewSelected = false;
        _venuePreviewSelected = false;
        _bylinePreviewSelected = false;
        _customTextSnippetEditorOpen = false;
        _freeTextSnippetEditorOpen = false;
        _separatorSnippetEditorOpen = false;
        _punctuationSnippetEditorOpen = false;
        _activeFormulaIndex = null;
        _focusedGapIndex = null;
        _disposeGapControllers();
        _selectedSavedStyleId = entry.id;
        _template = applied;
        _selectedWire = _template.wireStyle;
        if (_template.wireStyle == WireStyle.custom) {
          _lastPreset = _wiredBaseline(WireStyle.getty);
        } else {
          _lastPreset = _clonePreset(_template);
        }
        _initGapControllers(_template);
        _syncBylineControllersFromTemplate();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncDateUiFromTemplate();
      });
      // Selecting a named style should become the live caption style.
      if (!widget.adminMode) {
        unawaited(_persistCaptionLayoutToPreferences(
          syncBuiltInWireDefault: false,
          allowSkipIfUnchanged: false,
        ));
      } else {
        unawaited(PreferencesService.getInstance().then((prefs) async {
          await prefs.saveCaptionTemplate(applied);
        }));
      }
      return;
    }
    _applyWireStyle(_wireStyleFromMenuToken(token));
  }

  /// True when [t] already has the snippet chip layout (punctuation / separator
  /// segments in segmentOrder). Templates saved before this feature was added
  /// won't have them.
  bool _hasSnippetLayout(CaptionTemplate t) =>
      t.segmentOrder.contains(CaptionSegment.punctuation) ||
      t.segmentOrder.contains(CaptionSegment.separator);

  /// Migrates a legacy template (no snippet chips) to the current factory
  /// segment order while preserving all other user settings (byline, date
  /// format, location options, etc.).
  CaptionTemplate _migrateSnippetLayout(
      CaptionTemplate saved, CaptionTemplate factory) {
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
          freeTextSnippets: factory.freeTextSnippets != null
              ? List<String>.from(factory.freeTextSnippets!)
              : null,
          freeTextSuffixes: factory.freeTextSuffixes != null
              ? List<String>.from(factory.freeTextSuffixes!)
              : null,
        )
        .normalizePerOccurrenceLists();
  }

  /// Factory Getty USA / Imagn / AP / Getty International, or the user's saved
  /// default for that wire. Legacy templates missing snippet chips are silently
  /// migrated to the current factory segment layout on first load.
  CaptionTemplate _wiredBaseline(WireStyle wire) {
    CaptionTemplate apply(CaptionTemplate? saved, CaptionTemplate factory) {
      var base = saved == null
          ? factory
          : (!_hasSnippetLayout(saved)
              ? _migrateSnippetLayout(saved, factory)
              : saved);
      if (wire == WireStyle.getty || wire == WireStyle.gettyInternational) {
        base = CaptionTemplate.migrateGettyClosingFormulaIfNeeded(base);
      }
      return _withSessionSportGameId(base);
    }

    switch (wire) {
      case WireStyle.getty:
        return apply(_gettyWireDefault, CaptionTemplate.getty())
            .copyWith(includePlayerPosition: false);
      case WireStyle.imagn:
        return apply(_imagnWireDefault, CaptionTemplate.imagn());
      case WireStyle.ap:
        return apply(_apWireDefault, CaptionTemplate.ap());
      case WireStyle.cp:
        return apply(_cpWireDefault, CaptionTemplate.cp());
      case WireStyle.gettyInternational:
        return apply(
                _gettyIntlWireDefault, CaptionTemplate.gettyInternational())
            .copyWith(includePlayerPosition: false);
      case WireStyle.custom:
        return apply(_gettyWireDefault, CaptionTemplate.getty());
    }
  }

  CaptionTemplate _clonePreset(CaptionTemplate t) {
    switch (t.wireStyle) {
      case WireStyle.getty:
      case WireStyle.gettyInternational:
        return _wiredBaseline(t.wireStyle).copyWith(
          segmentOrder: List<CaptionSegment>.from(t.segmentOrder),
          dateFormat: t.dateFormat,
          dateExpression: t.dateExpression,
          dateFormula: t.dateFormula?.clone(),
          dateFormulasByOccurrence:
              t.dateFormulasByOccurrence?.map((e) => e.clone()).toList(),
          monthTokensByOccurrence:
              t.monthTokensByOccurrence?.map((e) => e.copy()).toList(),
          dayTokensByOccurrence:
              t.dayTokensByOccurrence?.map((e) => e.copy()).toList(),
          yearTokensByOccurrence:
              t.yearTokensByOccurrence?.map((e) => e.copy()).toList(),
          weekdayTokensByOccurrence:
              t.weekdayTokensByOccurrence?.map((e) => e.copy()).toList(),
          locationOptions: t.locationOptions,
          locationOptionsByOccurrence:
              t.locationOptionsByOccurrence?.map((e) => e.clone()).toList(),
          numberFormat: t.numberFormat,
          captionTeamOrder: t.captionTeamOrder,
          includePlayerPosition: t.includePlayerPosition,
          americanEnglish: t.americanEnglish,
          removeDiacritics: t.removeDiacritics,
          showPersonalityField: t.showPersonalityField,
          showKeywordsField: t.showKeywordsField,
          timingPhraseCaps: t.timingPhraseCaps,
          includeTimingPhrase: t.includeTimingPhrase,
          separator: t.separator,
          creditFormat: t.creditFormat,
          bylineOptions: t.bylineOptions,
          customSeparators: t.customSeparators != null
              ? List<String>.from(t.customSeparators!)
              : null,
          separatorSnippets: t.separatorSnippets != null
              ? List<String>.from(t.separatorSnippets!)
              : null,
          punctuationSnippets: t.punctuationSnippets != null
              ? List<String>.from(t.punctuationSnippets!)
              : null,
          freeTextSnippets: t.freeTextSnippets != null
              ? List<String>.from(t.freeTextSnippets!)
              : null,
          freeTextSuffixes: t.freeTextSuffixes != null
              ? List<String>.from(t.freeTextSuffixes!)
              : null,
        );
      case WireStyle.imagn:
        return _wiredBaseline(WireStyle.imagn).copyWith(
          segmentOrder: List<CaptionSegment>.from(t.segmentOrder),
          dateFormat: t.dateFormat,
          dateExpression: t.dateExpression,
          dateFormula: t.dateFormula?.clone(),
          dateFormulasByOccurrence:
              t.dateFormulasByOccurrence?.map((e) => e.clone()).toList(),
          monthTokensByOccurrence:
              t.monthTokensByOccurrence?.map((e) => e.copy()).toList(),
          dayTokensByOccurrence:
              t.dayTokensByOccurrence?.map((e) => e.copy()).toList(),
          yearTokensByOccurrence:
              t.yearTokensByOccurrence?.map((e) => e.copy()).toList(),
          weekdayTokensByOccurrence:
              t.weekdayTokensByOccurrence?.map((e) => e.copy()).toList(),
          locationOptions: t.locationOptions,
          locationOptionsByOccurrence:
              t.locationOptionsByOccurrence?.map((e) => e.clone()).toList(),
          numberFormat: t.numberFormat,
          captionTeamOrder: t.captionTeamOrder,
          includePlayerPosition: t.includePlayerPosition,
          americanEnglish: t.americanEnglish,
          removeDiacritics: t.removeDiacritics,
          showPersonalityField: t.showPersonalityField,
          showKeywordsField: t.showKeywordsField,
          timingPhraseCaps: t.timingPhraseCaps,
          includeTimingPhrase: t.includeTimingPhrase,
          separator: t.separator,
          creditFormat: t.creditFormat,
          bylineOptions: t.bylineOptions,
          customSeparators: t.customSeparators != null
              ? List<String>.from(t.customSeparators!)
              : null,
          separatorSnippets: t.separatorSnippets != null
              ? List<String>.from(t.separatorSnippets!)
              : null,
          punctuationSnippets: t.punctuationSnippets != null
              ? List<String>.from(t.punctuationSnippets!)
              : null,
          freeTextSnippets: t.freeTextSnippets != null
              ? List<String>.from(t.freeTextSnippets!)
              : null,
          freeTextSuffixes: t.freeTextSuffixes != null
              ? List<String>.from(t.freeTextSuffixes!)
              : null,
        );
      case WireStyle.ap:
      case WireStyle.cp:
        return _wiredBaseline(t.wireStyle).copyWith(
          segmentOrder: List<CaptionSegment>.from(t.segmentOrder),
          dateFormat: t.dateFormat,
          dateExpression: t.dateExpression,
          dateFormula: t.dateFormula?.clone(),
          dateFormulasByOccurrence:
              t.dateFormulasByOccurrence?.map((e) => e.clone()).toList(),
          monthTokensByOccurrence:
              t.monthTokensByOccurrence?.map((e) => e.copy()).toList(),
          dayTokensByOccurrence:
              t.dayTokensByOccurrence?.map((e) => e.copy()).toList(),
          yearTokensByOccurrence:
              t.yearTokensByOccurrence?.map((e) => e.copy()).toList(),
          weekdayTokensByOccurrence:
              t.weekdayTokensByOccurrence?.map((e) => e.copy()).toList(),
          locationOptions: t.locationOptions,
          locationOptionsByOccurrence:
              t.locationOptionsByOccurrence?.map((e) => e.clone()).toList(),
          numberFormat: t.numberFormat,
          captionTeamOrder: t.captionTeamOrder,
          includePlayerPosition: t.includePlayerPosition,
          americanEnglish: t.americanEnglish,
          removeDiacritics: t.removeDiacritics,
          showPersonalityField: t.showPersonalityField,
          showKeywordsField: t.showKeywordsField,
          timingPhraseCaps: t.timingPhraseCaps,
          includeTimingPhrase: t.includeTimingPhrase,
          separator: t.separator,
          creditFormat: t.creditFormat,
          bylineOptions: t.bylineOptions,
          customSeparators: t.customSeparators != null
              ? List<String>.from(t.customSeparators!)
              : null,
          separatorSnippets: t.separatorSnippets != null
              ? List<String>.from(t.separatorSnippets!)
              : null,
          punctuationSnippets: t.punctuationSnippets != null
              ? List<String>.from(t.punctuationSnippets!)
              : null,
          freeTextSnippets: t.freeTextSnippets != null
              ? List<String>.from(t.freeTextSnippets!)
              : null,
          freeTextSuffixes: t.freeTextSuffixes != null
              ? List<String>.from(t.freeTextSuffixes!)
              : null,
        );
      case WireStyle.custom:
        return _wiredBaseline(WireStyle.getty);
    }
  }

  bool _isBuiltInWire(WireStyle wire) => wire != WireStyle.custom;

  void _rememberCurrentWireDraft() {
    if (!widget.adminMode) return;
    if (_coreStyleLocked) return;
    if (!_isBuiltInWire(_selectedWire) || _selectedSavedStyleId != null) return;
    _flushGapControllersIntoTemplate();
    final normalized = _template.normalizePerOccurrenceLists();
    _wireDrafts[_selectedWire] = _deepCopyCaptionTemplate(normalized);
    _seedWireDefaultFromDraft(_selectedWire, normalized);
    widget.onDraftChanged?.call(_selectedWire, normalized);
  }

  CaptionTemplate _draftOrBaseline(WireStyle wire) {
    final draft = _wireDrafts[wire];
    if (draft != null) {
      return _deepCopyCaptionTemplate(draft).copyWith(wireStyle: wire);
    }
    return _wiredBaseline(wire);
  }

  /// Full JSON round-trip so nested lists (per–date-chip formulas, etc.) stay independent.
  CaptionTemplate _deepCopyCaptionTemplate(CaptionTemplate t) {
    final raw = json.decode(json.encode(t.toJson())) as Map<String, dynamic>;
    return CaptionTemplate.fromJson(raw);
  }

  /// Copies the working layout as [WireStyle.custom] for editing without replacing
  /// the Getty / Imagn / AP / CP built-in defaults.
  void _duplicateCaptionStyle() {
    _rememberCurrentWireDraft();
    final previousWire = _selectedWire;
    final duplicatedCore = _selectedSavedStyleId == null &&
        _isBuiltInWire(previousWire);
    final sourceLabel = _selectedSavedStyleId != null
        ? _captionStyleMenuLabel('saved:$_selectedSavedStyleId')
        : _wireStyleDropdownLabel(previousWire);
    final copy = _deepCopyCaptionTemplate(_template);
    setState(() {
      _locationEditorOpen = false;
      _dateEditorOpen = false;
      _captionPreviewSelected = false;
      _venuePreviewSelected = false;
      _bylinePreviewSelected = false;
      _customTextSnippetEditorOpen = false;
      _freeTextSnippetEditorOpen = false;
      _separatorSnippetEditorOpen = false;
      _punctuationSnippetEditorOpen = false;
      _activeFormulaIndex = null;
      _focusedGapIndex = null;
      _disposeGapControllers();
      _selectedSavedStyleId = null;
      _selectedWire = WireStyle.custom;
      _template = copy.copyWith(
        wireStyle: WireStyle.custom,
        id: 'custom',
        name: 'Custom',
      );
      if (previousWire != WireStyle.custom) {
        _lastPreset = _clonePreset(_wiredBaseline(previousWire));
      }
      _initGapControllers(_template);
      _syncBylineControllersFromTemplate();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDateUiFromTemplate();
    });
    // Persist as the live active style immediately so edits apply without
    // requiring a named caption profile.
    if (!widget.adminMode) {
      unawaited(_persistCaptionLayoutToPreferences(
        syncBuiltInWireDefault: false,
        allowSkipIfUnchanged: false,
      ));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          duplicatedCore
              ? 'Editing a copy of "$sourceLabel". Done applies it now — '
                  'use Save as new caption profile only if you want a named style.'
              : previousWire == WireStyle.custom
                  ? 'Layout duplicated as Custom. Done keeps your caption style.'
                  : 'Copied $sourceLabel layout as Custom. Done keeps it.',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _deleteSelectedCaptionStyle() async {
    final id = _selectedSavedStyleId;
    if (id == null) return;
    String? removedName;
    for (final e in _captionStyleLibrary) {
      if (e.id == id) {
        removedName = e.displayName;
        break;
      }
    }
    try {
      final prefs = await PreferencesService.getInstance();
      await prefs.removeCaptionStyleFromLibrary(id);
      final lib = await prefs.getCaptionStyleLibrary();
      if (!mounted) return;
      setState(() {
        _captionStyleLibrary = lib;
        _selectedSavedStyleId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            removedName != null
                ? 'Removed "$removedName" from saved caption styles.'
                : 'Removed saved caption style.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete caption style: $e'),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _setAllStylesAsDefaults() async {
    _rememberCurrentWireDraft();
    final prefs = await PreferencesService.getInstance();
    const wires = <WireStyle>[
      WireStyle.getty,
      WireStyle.imagn,
      WireStyle.ap,
      WireStyle.cp,
      WireStyle.gettyInternational,
    ];

    final nextDefaults = <WireStyle, CaptionTemplate>{};
    for (final wire in wires) {
      final draft = _wireDrafts[wire];
      final source = draft ?? _wiredBaseline(wire);
      final normalized =
          _deepCopyCaptionTemplate(source).copyWith(wireStyle: wire);
      await prefs.saveCaptionTemplateWireDefault(wire, normalized);
      nextDefaults[wire] = normalized;
    }
    if (!mounted) return;
    setState(() {
      _gettyWireDefault = nextDefaults[WireStyle.getty];
      _imagnWireDefault = nextDefaults[WireStyle.imagn];
      _apWireDefault = nextDefaults[WireStyle.ap];
      _cpWireDefault = nextDefaults[WireStyle.cp];
      _gettyIntlWireDefault = nextDefaults[WireStyle.gettyInternational];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saved all caption styles as defaults.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _disposeGapControllers() {
    for (final c in _gapControllers) {
      c.dispose();
    }
    _gapControllers.clear();
  }

  void _disposeGlueSnippetControllers() {
    for (final c in _glueSnippetControllers.values) {
      c.dispose();
    }
    _glueSnippetControllers.clear();
    for (final f in _glueFocusNodes.values) {
      f.dispose();
    }
    _glueFocusNodes.clear();
  }

  bool _separatorEnsureScheduled = false;

  void _scheduleSeparatorEnsure() {
    final ensured = _withSeparatorsAroundSnippets(_template);
    if (identical(ensured, _template) || _separatorEnsureScheduled) return;
    _separatorEnsureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _separatorEnsureScheduled = false;
      if (!mounted) return;
      final next = _withSeparatorsAroundSnippets(_template);
      if (identical(next, _template)) return;
      setState(() {
        _initGapControllers(next);
      });
      widget.onDraftChanged?.call(_selectedWire, _template);
      _scheduleAutosave();
    });
  }

  bool _isGlueSegment(CaptionSegment seg) =>
      seg == CaptionSegment.punctuation || seg == CaptionSegment.separator;

  /// Typed caption body (game-id phrases, notes) — shown as real text, not a chip.
  bool _isInlineTypedSegment(CaptionSegment seg) =>
      seg == CaptionSegment.freeText || seg == CaptionSegment.customText;

  bool _isStructureTextField(CaptionSegment seg) =>
      _isGlueSegment(seg) || _isInlineTypedSegment(seg);

  /// Long notes (NOTE TO USER, etc.) that don't fit on one line — these must
  /// sit on their own full-width row so reading order stays left-to-right.
  bool _structureTextNeedsOwnRow(String raw, double maxWidth) {
    final text = raw.trim();
    if (!text.contains(' ')) return false;
    if (_structureTextIsTrailingPunct(raw)) return false;
    final style = _structurePatternTextStyle.copyWith(
      color: FfTokens.sessionTx,
      height: 1.35,
    );
    final painter = TextPainter(
      text: TextSpan(text: raw, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);
    return painter.width > math.max(32.0, maxWidth - 8);
  }

  /// Comma, colon, period, etc. — always stay on the same line as the chip
  /// they follow (`{City},` `{Day}:`).
  bool _structureTextIsTrailingPunct(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;
    return RegExp(r'^[.,:;!?]+$').hasMatch(trimmed);
  }

  /// Short joiners (`at`, `on`, `in`, `-`) stick to the next chip.
  bool _structureTextIsLeadingJoiner(String raw) {
    if (_structureTextIsTrailingPunct(raw)) return false;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return true;
    return !trimmed.contains(' ');
  }

  Widget _structureInlineGroup(List<Widget> parts) {
    if (parts.isEmpty) return const SizedBox.shrink();
    if (parts.length == 1) return parts.first;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: parts,
    );
  }

  TapGestureRecognizer _structureFlowTap(VoidCallback onTap) {
    final tap = TapGestureRecognizer()..onTap = onTap;
    _structureFlowTaps.add(tap);
    return tap;
  }

  InlineSpan _structureWidgetSpan(Widget child) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: child,
    );
  }

  /// Chips stay widgets; long notes are real text so they continue after the
  /// previous chip (`{State 2}. NOTE TO USER…`) instead of jumping to a new row.
  Widget _structureReadingFlow({
    required double maxWidth,
    required List<
            ({
              Widget child,
              bool ownRow,
              bool isChip,
              bool leadingJoiner,
              bool trailingPunct,
              String? flowText,
              bool flowFocused,
              VoidCallback? onEditFlow,
            })>
        items,
  }) {
    for (final tap in _structureFlowTaps) {
      tap.dispose();
    }
    _structureFlowTaps.clear();

    final spans = <InlineSpan>[];
    final flowStyle = _structurePatternTextStyle.copyWith(
      color: FfTokens.sessionTx,
    );

    void addWidget(Widget child) {
      spans.add(_structureWidgetSpan(child));
    }

    var i = 0;
    while (i < items.length) {
      final item = items[i];
      if (item.ownRow) {
        if (!item.flowFocused &&
            item.flowText != null &&
            item.flowText!.isNotEmpty) {
          spans.add(
            TextSpan(
              text: item.flowText,
              style: flowStyle,
              recognizer: item.onEditFlow == null
                  ? null
                  : _structureFlowTap(item.onEditFlow!),
            ),
          );
        } else {
          addWidget(item.child);
        }
        i++;
        continue;
      }

      final leading = <Widget>[];
      while (i < items.length &&
          !items[i].ownRow &&
          items[i].leadingJoiner &&
          !items[i].isChip) {
        leading.add(items[i].child);
        i++;
      }
      if (i < items.length && !items[i].ownRow && items[i].isChip) {
        final chip = items[i].child;
        i++;
        final trailing = <Widget>[];
        while (i < items.length &&
            !items[i].ownRow &&
            items[i].trailingPunct &&
            !items[i].isChip) {
          trailing.add(items[i].child);
          i++;
        }
        addWidget(_structureInlineGroup([...leading, chip, ...trailing]));
        continue;
      }
      if (leading.isNotEmpty) {
        addWidget(_structureInlineGroup(leading));
      }
      if (i < items.length && !items[i].ownRow) {
        addWidget(items[i].child);
        i++;
      }
    }

    return SizedBox(
      width: maxWidth,
      child: Text.rich(
        TextSpan(style: flowStyle, children: spans),
      ),
    );
  }

  /// One separator box between snippets. The box before the first snippet is
  /// the layout prefix, and the box after the last snippet is the layout
  /// suffix. Extra empty boxes that were inserted between a pair are dropped.
  /// When several boxes sit between a pair, the one that already has text is
  /// kept.
  CaptionTemplate _withSeparatorsAroundSnippets(CaptionTemplate t) {
    final order = t.segmentOrder;
    if (order.isEmpty) return t;
    final punct = List<String>.from(t.punctuationSnippets ?? const []);
    final seps = List<String>.from(t.separatorSnippets ?? const []);
    var punctI = 0;
    var sepI = 0;

    String glueText(CaptionSegment seg) {
      if (seg == CaptionSegment.punctuation) {
        final value = punctI < punct.length ? punct[punctI] : '';
        punctI++;
        return value;
      }
      final value = sepI < seps.length ? seps[sepI] : '';
      sepI++;
      return value;
    }

    // Typed freeText is content (keeps joiners like "at" beside it). Only
    // punctuation/separator segments are collapsed by this pass.
    final tokens = <({CaptionSegment seg, String text, bool glue})>[];
    for (final seg in order) {
      if (_isGlueSegment(seg)) {
        tokens.add((seg: seg, text: glueText(seg), glue: true));
      } else {
        tokens.add((seg: seg, text: '', glue: false));
      }
    }

    final firstContent = tokens.indexWhere((token) => !token.glue);
    final lastContent = tokens.lastIndexWhere((token) => !token.glue);
    if (firstContent < 0) return t;

    final kept = <({CaptionSegment seg, String text, bool glue})>[];
    // Keep non-empty literals before the first chip (e.g. leading spaces).
    for (var i = 0; i < firstContent; i++) {
      if (tokens[i].glue && tokens[i].text.isNotEmpty) {
        kept.add(tokens[i]);
      }
    }
    var i = firstContent;
    while (i <= lastContent) {
      kept.add(tokens[i]);
      i++;
      if (i > lastContent) break;
      final gap = <int>[];
      while (i < lastContent && tokens[i].glue) {
        gap.add(i);
        i++;
      }
      if (gap.isEmpty) {
        kept.add((seg: CaptionSegment.punctuation, text: '', glue: true));
      } else {
        var pick = gap.last;
        for (final g in gap.reversed) {
          if (tokens[g].text.isNotEmpty) {
            pick = g;
            break;
          }
        }
        kept.add(tokens[pick]);
      }
    }
    // Keep non-empty literals after the last chip (e.g. trailing ".").
    for (var j = lastContent + 1; j < tokens.length; j++) {
      if (tokens[j].glue && tokens[j].text.isNotEmpty) {
        kept.add(tokens[j]);
      }
    }

    final newOrder = kept.map((token) => token.seg).toList();
    final newPunct = <String>[];
    final newSeps = <String>[];
    for (final token in kept) {
      if (token.seg == CaptionSegment.punctuation) newPunct.add(token.text);
      if (token.seg == CaptionSegment.separator) newSeps.add(token.text);
    }

    final sameOrder = newOrder.length == order.length &&
        _listEqualsSeg(newOrder, order);
    final samePunct = _listEqualsStr(newPunct, punct);
    final sameSeps = _listEqualsStr(newSeps, seps);
    if (sameOrder && samePunct && sameSeps) return t;

    return t
        .copyWith(
          segmentOrder: newOrder,
          punctuationSnippets: newPunct.isEmpty ? null : newPunct,
          separatorSnippets: newSeps.isEmpty ? null : newSeps,
        )
        .normalizePerOccurrenceLists();
  }

  bool _listEqualsSeg(List<CaptionSegment> a, List<CaptionSegment> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _listEqualsStr(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _initGlueSnippetControllers(CaptionTemplate t) {
    final order = t.segmentOrder;
    final needed = <int>{};
    for (var i = 0; i < order.length; i++) {
      if (!_isStructureTextField(order[i])) continue;
      needed.add(i);
      final String raw;
      if (order[i] == CaptionSegment.separator) {
        raw = CaptionFormulaRenderer.separatorSnippetFor(t, i);
      } else if (order[i] == CaptionSegment.punctuation) {
        raw = CaptionFormulaRenderer.punctuationSnippetFor(t, i);
      } else {
        raw = CaptionFormulaRenderer.freeTextBodyFor(t, i);
      }
      final value = _normalizeSep(raw);
      final existing = _glueSnippetControllers[i];
      if (existing == null) {
        final c = TextEditingController(text: value);
        final index = i;
        c.addListener(() => _onGlueSnippetEdited(index));
        _glueSnippetControllers[i] = c;
      } else if (existing.text != value) {
        _syncingGlueSnippetCtrls = true;
        existing.text = value;
        existing.selection = TextSelection.collapsed(offset: value.length);
        _syncingGlueSnippetCtrls = false;
      }
    }
    for (final key in _glueSnippetControllers.keys.toList()) {
      if (!needed.contains(key)) {
        _glueSnippetControllers.remove(key)?.dispose();
        _glueFocusNodes.remove(key)?.dispose();
      }
    }
    for (final i in needed) {
      _glueFocusNodes.putIfAbsent(
        i,
        () => FocusNode(
          onKeyEvent: (node, event) {
            final slots = _structureSepSlots();
            final idx = slots.indexWhere((s) => identical(s.focus, node));
            if (idx < 0) return KeyEventResult.ignored;
            return _handleStructureSepArrow(idx, event);
          },
        ),
      );
    }
  }

  /// Ordered typeable fields in the structure / preview strip:
  /// prefix → separators / typed text → suffix.
  List<({TextEditingController controller, FocusNode focus})>
      _structureSepSlots() {
    final slots = <({TextEditingController controller, FocusNode focus})>[
      (controller: _layoutPrefixCtrl, focus: _layoutPrefixFocus),
    ];
    final order = _template.segmentOrder;
    for (var i = 0; i < order.length; i++) {
      if (!_isStructureTextField(order[i])) continue;
      final c = _glueSnippetControllers[i];
      final f = _glueFocusNodes[i];
      if (c == null || f == null) continue;
      slots.add((controller: c, focus: f));
    }
    slots.add((controller: _layoutSuffixCtrl, focus: _layoutSuffixFocus));
    return slots;
  }

  KeyEventResult _handleStructureSepArrow(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final slots = _structureSepSlots();
    if (index < 0 || index >= slots.length) return KeyEventResult.ignored;
    final c = slots[index].controller;
    final text = c.text;
    final sel = c.selection;
    final pos = sel.isValid ? sel.extentOffset : text.length;
    final collapsed = !sel.isValid || sel.isCollapsed;

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (collapsed && pos >= text.length && index < slots.length - 1) {
        final next = slots[index + 1];
        next.focus.requestFocus();
        next.controller.selection = const TextSelection.collapsed(offset: 0);
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (collapsed && pos <= 0 && index > 0) {
        final prev = slots[index - 1];
        prev.focus.requestFocus();
        prev.controller.selection = TextSelection.collapsed(
          offset: prev.controller.text.length,
        );
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onGlueSnippetEdited(int segmentIndex) {
    if (_syncingGlueSnippetCtrls) return;
    if (segmentIndex < 0 || segmentIndex >= _template.segmentOrder.length) {
      return;
    }
    final seg = _template.segmentOrder[segmentIndex];
    if (!_isStructureTextField(seg)) return;
    final controller = _glueSnippetControllers[segmentIndex];
    if (controller == null) return;
    setState(() {
      if (seg == CaptionSegment.separator) {
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            _template.segmentOrder, segmentIndex, CaptionSegment.separator);
        _template = _templateWithSeparatorAtOccurrence(
            _template, occ, controller.text);
      } else if (seg == CaptionSegment.punctuation) {
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            _template.segmentOrder, segmentIndex, CaptionSegment.punctuation);
        _template = _templateWithPunctuationAtOccurrence(
            _template, occ, controller.text);
      } else {
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            _template.segmentOrder, segmentIndex, CaptionSegment.freeText);
        _template = _templateWithFreeTextAtOccurrence(
            _template, occ, controller.text);
        // Keep legacy gameIdentifierText in sync when this is a known phrase.
        final trimmed = controller.text.trim();
        if (trimmed.isEmpty ||
            kKnownGameIdentifierDefaults.contains(trimmed) ||
            _template.gameIdentifierText.trim().isNotEmpty) {
          _template = _template.copyWith(gameIdentifierText: trimmed);
          if (_gameIdentifierCtrl.text != trimmed) {
            _gameIdentifierCtrl.text = trimmed;
          }
        }
      }
    });
  }

  String _glueFieldTooltip(int segmentIndex) {
    final order = _template.segmentOrder;
    if (_isInlineTypedSegment(order[segmentIndex])) {
      return 'Typed text in the caption';
    }
    String? before;
    String? after;
    for (var j = segmentIndex - 1; j >= 0; j--) {
      if (!_isStructureTextField(order[j])) {
        before = _segmentDisplayLabel(order[j], j);
        break;
      }
    }
    for (var j = segmentIndex + 1; j < order.length; j++) {
      if (!_isStructureTextField(order[j])) {
        after = _segmentDisplayLabel(order[j], j);
        break;
      }
    }
    if (before != null && after != null) {
      return 'Separator between $before and $after';
    }
    return order[segmentIndex] == CaptionSegment.separator
        ? 'Separator'
        : 'Punctuation';
  }

  void _onGlueSnippetFocusChanged(int segmentIndex, bool focused) {
    setState(() {
      if (focused) {
        _focusedGlueSegmentIndex = segmentIndex;
        _layoutPrefixFocused = false;
        _layoutSuffixFocused = false;
        _locationEditorOpen = false;
        _dateEditorOpen = false;
        _captionPreviewSelected = false;
        _venuePreviewSelected = false;
        _bylinePreviewSelected = false;
        _customTextSnippetEditorOpen = false;
        _freeTextSnippetEditorOpen = false;
        _separatorSnippetEditorOpen = false;
        _punctuationSnippetEditorOpen = false;
        _activeFormulaIndex = null;
        _focusedGapIndex = null;
      } else if (_focusedGlueSegmentIndex == segmentIndex) {
        _focusedGlueSegmentIndex = null;
      }
    });
  }

  /// Separators keep every character the user typed, including spaces.
  static String _normalizeSep(String raw) => raw;

  /// Rewrites any leftover combined [CaptionSegment.date] into Month/Day/Year
  /// before the structure strip is built. No-op when already expanded.
  CaptionTemplate _ensureDatePartsExpanded(CaptionTemplate t) {
    if (!t.segmentOrder.contains(CaptionSegment.date)) {
      return t.normalizePerOccurrenceLists();
    }
    return t.expandDateSegments().normalizePerOccurrenceLists();
  }

  void _initGapControllers(CaptionTemplate t) {
    final ensured = _withSeparatorsAroundSnippets(_ensureDatePartsExpanded(t));
    t = ensured;
    _template = t;
    _focusedGapIndex = null;
    _disposeGapControllers();
    // Always match [CaptionFormulaRenderer.effectiveSegmentGaps] so preview and
    // inline fields stay aligned (handles null or wrong-length custom lists).
    final gaps = CaptionFormulaRenderer.effectiveSegmentGaps(t);
    final normalizedGaps = gaps.map(_normalizeSep).toList();
    for (final g in normalizedGaps) {
      final c = TextEditingController(text: g);
      c.addListener(_onGapEdited);
      _gapControllers.add(c);
    }
    // Apply normalized values back to the template so the preview is correct
    // immediately — even for old saved templates with bad punctuation spacing.
    _template = _template.copyWith(customSeparators: normalizedGaps);
    // Sync layout prefix/suffix controllers.
    _layoutPrefixCtrl.text = t.layoutPrefix;
    _layoutSuffixCtrl.text = t.layoutSuffix;
    _initGlueSnippetControllers(t);
  }

  void _onLayoutPrefixEdited() {
    setState(() {
      _template = _template.copyWith(layoutPrefix: _layoutPrefixCtrl.text);
    });
    _scheduleAutosave();
  }

  void _onLayoutSuffixEdited() {
    setState(() {
      _template = _template.copyWith(layoutSuffix: _layoutSuffixCtrl.text);
    });
    _scheduleAutosave();
  }

  /// Inserts [kind] into [segmentOrder] immediately after the snippet at
  /// [_activeFormulaIndex], or at the end when no snippet is selected.
  void _addSegmentSnippet(CaptionSegment kind) {
    late final int insertedAt;
    setState(() {
      final order = List<CaptionSegment>.from(_template.segmentOrder);
      final idx = _activeFormulaIndex;
      final insert = (idx != null && idx >= 0 && idx < order.length)
          ? idx + 1
          : order.length;
      insertedAt = insert.clamp(0, order.length);
      order.insert(insertedAt, kind);
      var next = _template.copyWith(
        segmentOrder: order,
        customSeparators: null,
      );
      next = next.copyWith(
        customSeparators: List<String>.from(
          CaptionFormulaRenderer.effectiveSegmentGaps(next),
        ),
      );
      _template = next.normalizePerOccurrenceLists();
      _initGapControllers(_template);
    });
    _scheduleAutosave();
    if (kind == CaptionSegment.freeText ||
        kind == CaptionSegment.customText ||
        kind == CaptionSegment.caption ||
        _isGeoFieldSegment(kind) ||
        _isDatePartSegment(kind) ||
        kind == CaptionSegment.date ||
        kind == CaptionSegment.venue ||
        kind == CaptionSegment.credit) {
      _activateFormulaEditor(index: insertedAt, segment: kind);
    }
  }

  // Note: freeText / customText activate focuses the inline typed field.

  static bool _isGeoFieldSegment(CaptionSegment s) =>
      s == CaptionSegment.city ||
      s == CaptionSegment.state ||
      s == CaptionSegment.country ||
      s == CaptionSegment.countryCode ||
      s == CaptionSegment.location;

  static bool _isDatePartSegment(CaptionSegment s) =>
      CaptionTemplate.isDatePartSegment(s);

  /// Removes the snippet at [index] from [segmentOrder].
  void _removeSegmentSnippet(int index) {
    setState(() {
      final order = List<CaptionSegment>.from(_template.segmentOrder);
      if (index < 0 || index >= order.length) return;
      order.removeAt(index);
      var next = _template.copyWith(
        segmentOrder: order,
        customSeparators: null,
      );
      next = next.copyWith(
        customSeparators: List<String>.from(
          CaptionFormulaRenderer.effectiveSegmentGaps(next),
        ),
      );
      _template = next.normalizePerOccurrenceLists();
      _initGapControllers(_template);
      if (_activeFormulaIndex == index) {
        _activeFormulaIndex = null;
        _locationEditorOpen = false;
        _dateEditorOpen = false;
        _captionPreviewSelected = false;
        _venuePreviewSelected = false;
        _bylinePreviewSelected = false;
        _customTextSnippetEditorOpen = false;
        _freeTextSnippetEditorOpen = false;
        _separatorSnippetEditorOpen = false;
        _punctuationSnippetEditorOpen = false;
      } else if (_activeFormulaIndex != null && _activeFormulaIndex! > index) {
        _activeFormulaIndex = _activeFormulaIndex! - 1;
      }
    });
    _scheduleAutosave();
  }

  /// Reorders [CaptionTemplate.segmentOrder] when the user drags one preview
  /// snippet onto another ("drop at target index" semantics, same as byline).
  void _reorderPreviewSegment(int fromSegmentIndex, int toSegmentIndex) {
    if (fromSegmentIndex == toSegmentIndex) return;
    setState(() {
      final order = List<CaptionSegment>.from(_template.segmentOrder);
      if (fromSegmentIndex < 0 || fromSegmentIndex >= order.length) return;
      if (toSegmentIndex < 0 || toSegmentIndex >= order.length) return;
      if (_isStructureTextField(order[fromSegmentIndex])) return;

      final moved = order.removeAt(fromSegmentIndex);
      var insert = toSegmentIndex;
      if (fromSegmentIndex < insert) insert--;
      if (insert < 0) insert = 0;
      if (insert > order.length) insert = order.length;
      order.insert(insert, moved);

      final oldActive = _activeFormulaIndex;
      if (oldActive != null) {
        int newActive;
        if (oldActive == fromSegmentIndex) {
          newActive = insert;
        } else {
          final j =
              oldActive > fromSegmentIndex ? oldActive - 1 : oldActive;
          newActive = j >= insert ? j + 1 : j;
        }
        _activeFormulaIndex =
            newActive.clamp(0, order.length > 0 ? order.length - 1 : 0);
      }

      var next = _template.copyWith(
        segmentOrder: order,
        customSeparators: null,
      );
      next = next.copyWith(
        customSeparators: List<String>.from(
          CaptionFormulaRenderer.effectiveSegmentGaps(next),
        ),
      );
      _template = next.normalizePerOccurrenceLists();
      _initGapControllers(_template);
    });
    _scheduleAutosave();
  }

  void _onGapEdited() {
    setState(() {
      _template = _template.copyWith(
        customSeparators: _gapControllers.map((c) => c.text).toList(),
      );
    });
  }

  CaptionTemplate _templateWithLocationAtOccurrence(
    CaptionTemplate t,
    int occurrenceIndex,
    LocationLineOptions o,
  ) {
    final n = [
      t.segmentOrder.where((s) => s == CaptionSegment.city).length,
      t.segmentOrder.where((s) => s == CaptionSegment.state).length,
      t.segmentOrder.where((s) => s == CaptionSegment.country).length,
      t.segmentOrder.where((s) => s == CaptionSegment.countryCode).length,
      t.segmentOrder.where((s) => s == CaptionSegment.location).length,
    ].fold<int>(0, (a, b) => a > b ? a : b);
    if (n <= 1) {
      return t.copyWith(
        locationOptions: o,
        locationOptionsByOccurrence: null,
      );
    }
    final list = List<LocationLineOptions>.generate(
      n,
      (i) => (t.locationOptionsByOccurrence != null &&
              i < t.locationOptionsByOccurrence!.length)
          ? t.locationOptionsByOccurrence![i].clone()
          : t.locationOptions.clone(),
    );
    list[occurrenceIndex.clamp(0, n - 1)] = o;
    return t.copyWith(
      locationOptions: list[0],
      locationOptionsByOccurrence: list,
    );
  }

  CaptionTemplate _templateWithDatePartAtOccurrence(
    CaptionTemplate t,
    DateFieldKind kind,
    int occurrenceIndex,
    DateFieldToken next,
  ) {
    List<DateFieldToken>? current;
    int count;
    switch (kind) {
      case DateFieldKind.month:
        count = t.segmentOrder.where((s) => s == CaptionSegment.month).length;
        current = t.monthTokensByOccurrence;
        break;
      case DateFieldKind.day:
        count = t.segmentOrder.where((s) => s == CaptionSegment.day).length;
        current = t.dayTokensByOccurrence;
        break;
      case DateFieldKind.year:
        count = t.segmentOrder.where((s) => s == CaptionSegment.year).length;
        current = t.yearTokensByOccurrence;
        break;
      case DateFieldKind.weekday:
        count = t.segmentOrder.where((s) => s == CaptionSegment.weekday).length;
        current = t.weekdayTokensByOccurrence;
        break;
    }
    // Structure formula may have a Month/Weekday chip before segmentOrder has
    // caught up — grow the list so chip format clicks are never a no-op.
    final need = occurrenceIndex + 1;
    if (count < need) count = need;
    if (current != null && current.length > count) count = current.length;
    if (count <= 0) return t;
    final list = List<DateFieldToken>.generate(
      count,
      (i) {
        if (current != null && i < current.length) return current[i].copy();
        return t.datePartTokenFor(kind: kind, occurrenceIndex: i).copy();
      },
    );
    list[occurrenceIndex.clamp(0, count - 1)] = next.copy();
    switch (kind) {
      case DateFieldKind.month:
        return t.copyWith(monthTokensByOccurrence: list);
      case DateFieldKind.day:
        return t.copyWith(dayTokensByOccurrence: list);
      case DateFieldKind.year:
        return t.copyWith(yearTokensByOccurrence: list);
      case DateFieldKind.weekday:
        return t.copyWith(weekdayTokensByOccurrence: list);
    }
  }

  CaptionTemplate _templateWithSeparatorAtOccurrence(
    CaptionTemplate t,
    int occurrenceIndex,
    String value,
  ) {
    final normalized = t.normalizePerOccurrenceLists();
    final n = normalized.segmentOrder
        .where((s) => s == CaptionSegment.separator)
        .length;
    if (n == 0) return normalized;
    final list = List<String>.from(normalized.separatorSnippets!);
    list[occurrenceIndex.clamp(0, n - 1)] = value;
    return normalized.copyWith(separatorSnippets: list);
  }

  CaptionTemplate _templateWithPunctuationAtOccurrence(
    CaptionTemplate t,
    int occurrenceIndex,
    String value,
  ) {
    final normalized = t.normalizePerOccurrenceLists();
    final n = normalized.segmentOrder
        .where((s) => s == CaptionSegment.punctuation)
        .length;
    if (n == 0) return normalized;
    final list = List<String>.from(normalized.punctuationSnippets!);
    list[occurrenceIndex.clamp(0, n - 1)] = value;
    return normalized.copyWith(punctuationSnippets: list);
  }

  CaptionTemplate _templateWithFreeTextAtOccurrence(
    CaptionTemplate t,
    int occurrenceIndex,
    String value,
  ) {
    final normalized = t.normalizePerOccurrenceLists();
    final n = normalized.segmentOrder
        .where((s) => s == CaptionSegment.freeText)
        .length;
    if (n == 0) return normalized;
    final list = List<String>.from(normalized.freeTextSnippets!);
    list[occurrenceIndex.clamp(0, n - 1)] = value;
    return normalized.copyWith(freeTextSnippets: list);
  }

  CaptionTemplate _templateWithFreeTextSuffixAtOccurrence(
    CaptionTemplate t,
    int occurrenceIndex,
    String value,
  ) {
    final normalized = t.normalizePerOccurrenceLists();
    final n = normalized.segmentOrder
        .where((s) => s == CaptionSegment.freeText)
        .length;
    if (n == 0) return normalized;
    final list = List<String>.from(normalized.freeTextSuffixes!);
    list[occurrenceIndex.clamp(0, n - 1)] = value;
    return normalized.copyWith(freeTextSuffixes: list);
  }

  void _setFreeTextSuffix(String value) {
    final idx = _activeFormulaIndex;
    if (idx == null || idx < 0 || idx >= _template.segmentOrder.length) {
      return;
    }
    if (_template.segmentOrder[idx] != CaptionSegment.freeText) return;
    setState(() {
      final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
          _template.segmentOrder, idx, CaptionSegment.freeText);
      _template =
          _templateWithFreeTextSuffixAtOccurrence(_template, occ, value);
    });
    _scheduleAutosave();
  }

  void _onFreeTextEdited() {
    if (_syncingFreeTextCtrl) return;
    final idx = _activeFormulaIndex;
    if (idx == null || idx < 0 || idx >= _template.segmentOrder.length) {
      return;
    }
    if (_template.segmentOrder[idx] != CaptionSegment.freeText) return;
    setState(() {
      final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
          _template.segmentOrder, idx, CaptionSegment.freeText);
      _template =
          _templateWithFreeTextAtOccurrence(_template, occ, _freeTextCtrl.text);
    });
    _scheduleAutosave();
  }

  void _onSnippetLiteralEdited() {
    if (_syncingSnippetLiteralCtrl) return;
    final idx = _activeFormulaIndex;
    if (idx == null || idx < 0 || idx >= _template.segmentOrder.length) {
      return;
    }
    final seg = _template.segmentOrder[idx];
    if (seg != CaptionSegment.separator && seg != CaptionSegment.punctuation) {
      return;
    }
    setState(() {
      if (seg == CaptionSegment.separator) {
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            _template.segmentOrder, idx, CaptionSegment.separator);
        _template = _templateWithSeparatorAtOccurrence(
            _template, occ, _snippetLiteralCtrl.text);
      } else {
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            _template.segmentOrder, idx, CaptionSegment.punctuation);
        _template = _templateWithPunctuationAtOccurrence(
            _template, occ, _snippetLiteralCtrl.text);
      }
    });
  }

  void _commitLocationOptions(LocationLineOptions o) {
    final idx = _activeFormulaIndex;
    if (idx == null ||
        idx < 0 ||
        idx >= _template.segmentOrder.length ||
        !_isGeoFieldSegment(_template.segmentOrder[idx])) {
      return;
    }
    final seg = _template.segmentOrder[idx];
    final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
        _template.segmentOrder, idx, seg);
    setState(() {
      _template = _templateWithLocationAtOccurrence(_template, occ, o);
    });
  }

  /// AP/CP drafts that passed through Structure used to lose AP Style on State
  /// (Imagn-shaped fullName chips). Restore AP Style for those.
  CaptionTemplate _healApRegionStyleIfNeeded(CaptionTemplate t) {
    if (t.wireStyle != WireStyle.ap && t.wireStyle != WireStyle.cp) {
      return t;
    }

    LocationLineOptions heal(LocationLineOptions o) {
      var changed = false;
      var sawRegion = false;
      final chips = <LocationChip>[];
      final imagnShaped = o.chips.any((c) => c.kind == LocationChipKind.country);
      for (final c in o.chips) {
        if (c.kind == LocationChipKind.region) {
          sawRegion = true;
          if (c.regionVariant == LocationRegionVariant.fullName &&
              imagnShaped) {
            chips.add(
              c.copyWith(regionVariant: LocationRegionVariant.apStyle),
            );
            changed = true;
            continue;
          }
        }
        chips.add(c);
      }
      if (!sawRegion) {
        return LocationLineOptions.apDefault();
      }
      if (!changed) return o;
      return o.copyWith(chips: chips, autoAdaptUsIntl: false);
    }

    final loc = heal(t.locationOptions);
    final by = t.locationOptionsByOccurrence;
    final nextBy = by?.map(heal).toList();
    final locChanged = !identical(loc, t.locationOptions);
    final byChanged = nextBy != null &&
        by != null &&
        (nextBy.length != by.length ||
            !identical(nextBy.first, by.first));
    if (!locChanged && !byChanged) return t;
    return t.copyWith(
      locationOptions: loc,
      locationOptionsByOccurrence: nextBy ?? by,
    );
  }

  void _applyWireStyle(WireStyle w) {
    // Re-applying the same wire (e.g. Caption Style dropdown fires again) must not
    // replace [_template] with [_wiredBaseline], or in-progress Getty edits vanish.
    // Leaving a saved library entry for this wire still reloads the baseline below.
    if (w == _selectedWire && _selectedSavedStyleId == null) {
      return;
    }
    _rememberCurrentWireDraft();
    setState(() {
      _liveStructureFormula = null;
      _selectedSavedStyleId = null;
      _locationEditorOpen = false;
      _dateEditorOpen = false;
      _captionPreviewSelected = false;
      _venuePreviewSelected = false;
      _bylinePreviewSelected = false;
      _customTextSnippetEditorOpen = false;
      _freeTextSnippetEditorOpen = false;
      _separatorSnippetEditorOpen = false;
      _punctuationSnippetEditorOpen = false;
      _disposeGapControllers();
      _selectedWire = w;
      if (w == WireStyle.getty) {
        _gettyPreviewUnitedStates = true;
      } else if (w == WireStyle.gettyInternational) {
        _gettyPreviewUnitedStates = false;
      }
      widget.onWireChanged?.call(w);
      switch (w) {
        case WireStyle.getty:
        case WireStyle.gettyInternational:
        case WireStyle.imagn:
        case WireStyle.ap:
        case WireStyle.cp:
          final b = _healApRegionStyleIfNeeded(_withSessionSportGameId(_draftOrBaseline(w)));
          _template = b;
          _lastPreset = b;
          break;
        case WireStyle.custom:
          final ref = _lastPreset;
          _template = _withSessionSportGameId(CaptionTemplate.custom(
            dateFormat: ref.dateFormat,
            dateExpression: ref.dateExpression,
            dateFormula: ref.dateFormula?.clone(),
            dateFormulasByOccurrence:
                ref.dateFormulasByOccurrence?.map((e) => e.clone()).toList(),
            monthTokensByOccurrence:
                ref.monthTokensByOccurrence?.map((e) => e.copy()).toList(),
            dayTokensByOccurrence:
                ref.dayTokensByOccurrence?.map((e) => e.copy()).toList(),
            yearTokensByOccurrence:
                ref.yearTokensByOccurrence?.map((e) => e.copy()).toList(),
            weekdayTokensByOccurrence:
                ref.weekdayTokensByOccurrence?.map((e) => e.copy()).toList(),
            locationOptions: ref.locationOptions,
            locationOptionsByOccurrence:
                ref.locationOptionsByOccurrence?.map((e) => e.clone()).toList(),
            numberFormat: ref.numberFormat,
            captionTeamOrder: ref.captionTeamOrder,
            includePlayerPosition: ref.includePlayerPosition,
            americanEnglish: ref.americanEnglish,
            removeDiacritics: ref.removeDiacritics,
            showPersonalityField: ref.showPersonalityField,
            showKeywordsField: ref.showKeywordsField,
            timingPhraseCaps: ref.timingPhraseCaps,
            includeTimingPhrase: ref.includeTimingPhrase,
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
            freeTextSnippets: ref.freeTextSnippets != null
                ? List<String>.from(ref.freeTextSnippets!)
                : null,
            freeTextSuffixes: ref.freeTextSuffixes != null
                ? List<String>.from(ref.freeTextSuffixes!)
                : null,
            gameIdentifierText: ref.gameIdentifierText,
          ));
          break;
      }
      if (w == WireStyle.getty || w == WireStyle.gettyInternational) {
        _template = GettyNoteVariant.applyToTemplate(
          _template,
          nbae: GettyNoteVariant.applies(
            enabled: _gettyNoteIsNbae,
            wire: w,
            sport: _sessionSport,
          ),
        );
      }
      _initGapControllers(_template);
      _syncBylineControllersFromTemplate();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncDateUiFromTemplate();
    });
    // Selecting a wire (or Custom) should become the live caption style, same as
    // picking a named library entry — otherwise only the dialog preview changes
    // until the user happens to hit Save.
    if (!widget.adminMode) {
      unawaited(_persistCaptionLayoutToPreferences(
        syncBuiltInWireDefault: false,
        allowSkipIfUnchanged: false,
      ));
    }
  }

  /// Ensures live text fields are copied into [_template] before persist/Done.
  void _flushAllEditorsIntoTemplate() {
    _flushGapControllersIntoTemplate();
    if (!_syncingGlueSnippetCtrls) {
      for (final entry in _glueSnippetControllers.entries) {
        final segmentIndex = entry.key;
        if (segmentIndex < 0 ||
            segmentIndex >= _template.segmentOrder.length) {
          continue;
        }
        final seg = _template.segmentOrder[segmentIndex];
        if (!_isGlueSegment(seg)) continue;
        if (seg == CaptionSegment.separator) {
          final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
              _template.segmentOrder, segmentIndex, CaptionSegment.separator);
          _template = _templateWithSeparatorAtOccurrence(
              _template, occ, entry.value.text);
        } else {
          final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
              _template.segmentOrder,
              segmentIndex,
              CaptionSegment.punctuation);
          _template = _templateWithPunctuationAtOccurrence(
              _template, occ, entry.value.text);
        }
      }
    }
    _template = _template.copyWith(
      gameIdentifierText: _gameIdentifierCtrl.text,
      layoutPrefix: _layoutPrefixCtrl.text,
      layoutSuffix: _layoutSuffixCtrl.text,
    );
  }

  bool _closingWouldDiscard() {
    if (!_prefsLoaded || widget.adminMode || !_requiresSaveAsNewStyle) {
      return false;
    }
    _flushAllEditorsIntoTemplate();
    return _templateSnapshot() != _lastSavedTemplateSnapshot;
  }

  Future<void> _requestClose() async {
    if (_closeConfirmed) return;
    if (_closingWouldDiscard()) {
      final ok = await showAppConfirmDialog(
        context: context,
        title: 'Close without saving?',
        message:
            'This layout has changes that are not saved yet. Close and discard them?',
        cancelLabel: 'Stay',
        confirmLabel: 'Discard',
      );
      if (ok != true || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _closeConfirmed = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  /// Applies the current layout as the active caption style and closes.
  /// Built-in wire edits become [WireStyle.custom] so the style menu shows
  /// Custom. The personal wire baseline is updated too. Named library rows
  /// stay named. Use [_saveAsTemplate] to create a new named style.
  Future<void> _done() async {
    if (!_prefsLoaded) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Caption layout is still loading — try Done again.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    try {
      _autosaveDebounce?.cancel();
      _flushAllEditorsIntoTemplate();

      // Unchanged built-in wire: keep the published style. Dirty built-ins
      // fall through and promote to Custom — do not force Save as new profile.
      if (!widget.adminMode &&
          _requiresSaveAsNewStyle &&
          _templateSnapshot() == _lastSavedTemplateSnapshot) {
        final prefs = await PreferencesService.getInstance();
        final baseline = _wiredBaseline(_selectedWire);
        await prefs.saveCaptionTemplate(baseline);
        _appliedOnDone = true;
        if (!mounted) return;
        if (widget.embedded) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Using the published ${_wireStyleDropdownLabel(_selectedWire)} caption.',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
        Navigator.of(context).pop(baseline);
        return;
      }

      final prefs = await PreferencesService.getInstance();
      var toSave = _template.normalizePerOccurrenceLists();
      // Only treat as a named library edit when the user actually selected a
      // saved: menu row (template.id == library entry id). Built-in wires
      // always promote to Custom on Done.
      final libId = _selectedSavedStyleId;
      final editingNamedLibrary = libId != null && toSave.id == libId;
      final sourceWire = _selectedWire;
      final promoteToCustom = !widget.adminMode &&
          !editingNamedLibrary &&
          _isBuiltInWire(sourceWire);

      if (widget.adminMode) {
        await _persistCaptionLayoutToPreferences(
          syncBuiltInWireDefault: true,
          allowSkipIfUnchanged: false,
        );
        toSave = _template.normalizePerOccurrenceLists();
      } else {
        if (promoteToCustom) {
          toSave = _deepCopyCaptionTemplate(toSave).copyWith(
            wireStyle: WireStyle.custom,
            id: 'custom',
            name: 'Custom',
          );
        }

        await prefs.saveCaptionTemplate(toSave);

        if (editingNamedLibrary) {
          await prefs.updateCaptionStyleTemplateInLibrary(
            id: libId,
            template: toSave,
          );
        }

        // Hard verify — do not close if prefs still hold the old style.
        final verify = await prefs.getCaptionTemplateRaw();
        if (verify.wireStyle != toSave.wireStyle ||
            verify.includeTimingPhrase != toSave.includeTimingPhrase ||
            verify.showPersonalityField != toSave.showPersonalityField ||
            verify.showKeywordsField != toSave.showKeywordsField ||
            jsonEncode(verify.segmentOrder.map((e) => e.name).toList()) !=
                jsonEncode(toSave.segmentOrder.map((e) => e.name).toList())) {
          await prefs.saveCaptionTemplate(toSave);
          final retry = await prefs.getCaptionTemplateRaw();
          if (retry.wireStyle != toSave.wireStyle) {
            throw StateError(
              'Caption layout did not save (still ${retry.wireStyle.name}).',
            );
          }
        }

        _appliedOnDone = true;
        if (mounted) {
          setState(() {
            _template = toSave;
            _selectedWire = toSave.wireStyle;
            if (promoteToCustom) {
              _selectedSavedStyleId = null;
              _lastPreset = _clonePreset(_wiredBaseline(sourceWire));
            }
            _markStructureSaved(toSave);
          });
        }
      }

      if (!mounted) return;
      if (widget.embedded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Caption layout applied.'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
      Navigator.of(context).pop(toSave);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not apply caption layout: $e'),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Opens the name prompt to add the current layout as a named caption profile.
  void _saveAsTemplate() {
    if (!_prefsLoaded) return;
    _forcedRenameMode = _RenamePromptMode.saveAsNewLibrary;
    _closeDialogAfterSaveAs = !widget.embedded;
    _openRenameCaptionStylePrompt();
  }

  /// Three modes for the Rename / Save-as dialog:
  ///  * `libraryEntry` — selected style is a saved library entry → rename it.
  ///  * `wireLabel` — admin renaming a built-in wire's dropdown label.
  ///  * `saveAsNewLibrary` — save the current layout as a new caption profile.
  _RenamePromptMode _currentRenameMode() {
    if (_forcedRenameMode != null) return _forcedRenameMode!;
    if (_selectedSavedStyleId != null) return _RenamePromptMode.libraryEntry;
    if (_selectedWire == WireStyle.custom || _requiresSaveAsNewStyle) {
      return _RenamePromptMode.saveAsNewLibrary;
    }
    return _RenamePromptMode.wireLabel;
  }

  void _openRenameCaptionStylePrompt() {
    final mode = _currentRenameMode();
    // Inline rename / Save as template link keeps the dialog open unless the
    // footer Save as template button set [_closeDialogAfterSaveAs].
    if (mode != _RenamePromptMode.saveAsNewLibrary) {
      _closeDialogAfterSaveAs = false;
    }
    String? currentName;
    switch (mode) {
      case _RenamePromptMode.libraryEntry:
        for (final e in _captionStyleLibrary) {
          if (e.id == _selectedSavedStyleId) {
            currentName = e.displayName;
            break;
          }
        }
        break;
      case _RenamePromptMode.wireLabel:
        currentName = _wireStyleDropdownLabel(_selectedWire);
        break;
      case _RenamePromptMode.saveAsNewLibrary:
        currentName = 'My caption style';
        break;
    }
    _renameCaptionStyleNameCtrl?.dispose();
    _renameCaptionStyleNameCtrl =
        TextEditingController(text: currentName ?? '');
    setState(() => _renameCaptionStylePromptOpen = true);
  }

  void _closeRenameCaptionStylePrompt() {
    if (!_renameCaptionStylePromptOpen) return;
    _renameCaptionStyleNameCtrl?.dispose();
    _renameCaptionStyleNameCtrl = null;
    _closeDialogAfterSaveAs = false;
    _forcedRenameMode = null;
    setState(() => _renameCaptionStylePromptOpen = false);
  }

  Future<void> _submitRenameCaptionStyleName() async {
    final ctrl = _renameCaptionStyleNameCtrl;
    if (ctrl == null || !mounted) return;
    final trimmed = ctrl.text.trim();
    if (trimmed.isEmpty) return;
    final mode = _currentRenameMode();
    try {
      final prefs = await PreferencesService.getInstance();
      String snackMessage;
      switch (mode) {
        case _RenamePromptMode.libraryEntry:
          final existingId = _selectedSavedStyleId!;
          await prefs.renameCaptionStyleInLibrary(
              id: existingId, newDisplayName: trimmed);
          final lib = await prefs.getCaptionStyleLibrary();
          if (!mounted) return;
          _closeRenameCaptionStylePrompt();
          setState(() {
            _captionStyleLibrary = lib;
            _selectedSavedStyleId = existingId;
          });
          snackMessage = 'Renamed saved style to "$trimmed".';
          break;
        case _RenamePromptMode.wireLabel:
          final wire = _selectedWire;
          await prefs.saveCaptionWireLabel(wire, trimmed);
          if (!mounted) return;
          _closeRenameCaptionStylePrompt();
          setState(() {
            switch (wire) {
              case WireStyle.getty:
                _gettyWireLabel = trimmed;
                break;
              case WireStyle.imagn:
                _imagnWireLabel = trimmed;
                break;
              case WireStyle.ap:
                _apWireLabel = trimmed;
                break;
              case WireStyle.cp:
                _cpWireLabel = trimmed;
                break;
              case WireStyle.gettyInternational:
                _gettyIntlWireLabel = trimmed;
                break;
              case WireStyle.custom:
                break;
            }
          });
          snackMessage =
              'Renamed ${_factoryWireLabel(wire)} to "$trimmed" in the menu.';
          break;
        case _RenamePromptMode.saveAsNewLibrary:
          _flushGapControllersIntoTemplate();
          final normalized = _template.normalizePerOccurrenceLists();
          final savedId = await prefs.addCaptionStyleToLibrary(
            displayName: trimmed,
            template: normalized,
          );
          // Apply immediately — naming alone used to only add a library row,
          // so Caption V2 kept rendering the previous active template.
          CaptionTemplate? applied;
          final lib = await prefs.getCaptionStyleLibrary();
          for (final e in lib) {
            if (e.id == savedId) {
              applied = _deepCopyCaptionTemplate(e.template);
              break;
            }
          }
          applied ??= normalized.copyWith(id: savedId, name: trimmed);
          await prefs.saveCaptionTemplate(applied);
          if (!mounted) return;
          _closeRenameCaptionStylePrompt();
          setState(() {
            _captionStyleLibrary = lib;
            _selectedSavedStyleId = savedId;
            _template = applied!;
            _selectedWire = _template.wireStyle;
            _markStructureSaved(applied);
          });
          snackMessage = 'Saved "$trimmed" and applied it as the active caption style.';
          final shouldClose = _closeDialogAfterSaveAs;
          _closeDialogAfterSaveAs = false;
          if (shouldClose && mounted && !widget.embedded) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(snackMessage),
                duration: const Duration(seconds: 2),
              ),
            );
            Navigator.of(context).pop();
            return;
          }
          break;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(snackMessage),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: Colors.red.shade800,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _renameCaptionStyleNameOverlay() {
    final ctrl = _renameCaptionStyleNameCtrl;
    if (ctrl == null) return const SizedBox.shrink();
    final ok = ctrl.text.trim().isNotEmpty;
    final mode = _currentRenameMode();
    String title;
    String submitLabel;
    switch (mode) {
      case _RenamePromptMode.libraryEntry:
        title = 'Rename caption style';
        submitLabel = 'Rename';
        break;
      case _RenamePromptMode.wireLabel:
        title = 'Rename ${_factoryWireLabel(_selectedWire)} in menu';
        submitLabel = 'Rename';
        break;
      case _RenamePromptMode.saveAsNewLibrary:
        title = 'Save as new caption profile';
        submitLabel = 'Save';
        break;
    }
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Material(
            color: _t.surface,
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
              side: BorderSide(color: _t.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: _t.surface,
                    border: Border(bottom: BorderSide(color: _t.divider)),
                  ),
                  child: Text(
                    title.toUpperCase(),
                    style: FfTokens.railLabel.copyWith(
                      color: _t.text.withValues(alpha: 0.70),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Name',
                        style: TextStyle(
                          fontFamily: FfTokens.labelFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          height: 1.2,
                          color: FfTokens.nocturneTx.withValues(alpha: 0.72),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Material(
                        color: FfTokens.nocturneSunken,
                        borderRadius:
                            BorderRadius.circular(FfTokens.radiusChip),
                        child: Container(
                          height: kAppDialogControlHeight,
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(FfTokens.radiusChip),
                            border: Border.all(color: _t.divider),
                          ),
                          child: TextField(
                            controller: ctrl,
                            autofocus: true,
                            cursorColor: FfTokens.nocturneAc,
                            style: const TextStyle(
                              fontFamily: FfTokens.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: FfTokens.nocturneTx,
                              height: 1.25,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              filled: false,
                            ),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (value) {
                              if (value.trim().isNotEmpty) {
                                _submitRenameCaptionStyleName();
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedGreyButton(
                        label: 'Cancel',
                        fontSize: 11,
                        onPressed: _closeRenameCaptionStylePrompt,
                      ),
                      const SizedBox(width: 8),
                      ElevatedGreyButton(
                        label: submitLabel,
                        fontSize: 11,
                        isPrimary: true,
                        onPressed: ok ? _submitRenameCaptionStyleName : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _autosaveDebounce?.cancel();
    _structureHintFlashTimer?.cancel();
    _playerOutputFlashTimer?.cancel();
    // Flush pending edits for Custom / named styles only. Built-in edits are
    // applied via Done (or Save as template); Cancel discards them.
    // Skip after Done — that path already wrote prefs and must not be raced.
    final snapshot = _templateSnapshot();
    if (_prefsLoaded &&
        !_appliedOnDone &&
        !_requiresSaveAsNewStyle &&
        !widget.adminMode &&
        snapshot != _lastSavedTemplateSnapshot) {
      _flushGapControllersIntoTemplate();
      final normalized = _template.normalizePerOccurrenceLists();
      final libId = _selectedSavedStyleId;
      PreferencesService.getInstance().then((prefs) async {
        try {
          await prefs.saveCaptionTemplate(normalized);
          if (libId != null && normalized.id == libId) {
            await prefs.updateCaptionStyleTemplateInLibrary(
              id: libId,
              template: normalized,
            );
          }
        } catch (_) {}
      });
    }
    _disposeGapControllers();
    _disposeGlueSnippetControllers();
    for (final tap in _structureFlowTaps) {
      tap.dispose();
    }
    _structureFlowTaps.clear();
    _layoutPrefixFocus.dispose();
    _layoutSuffixFocus.dispose();
    _layoutPrefixCtrl.removeListener(_onLayoutPrefixEdited);
    _layoutSuffixCtrl.removeListener(_onLayoutSuffixEdited);
    _layoutPrefixCtrl.dispose();
    _layoutSuffixCtrl.dispose();
    _bylinePrefixCtrl.removeListener(_onBylineTextEdited);
    _bylineBetweenCtrl.removeListener(_onBylineTextEdited);
    _bylineSuffixCtrl.removeListener(_onBylineTextEdited);
    _snippetLiteralCtrl.removeListener(_onSnippetLiteralEdited);
    _freeTextCtrl.removeListener(_onFreeTextEdited);
    _bylinePrefixCtrl.dispose();
    _bylineBetweenCtrl.dispose();
    _bylineSuffixCtrl.dispose();
    _snippetLiteralCtrl.dispose();
    _freeTextCtrl.dispose();
    for (final ctrl in _customChipCtrls) {
      ctrl.removeListener(_onBylineTextEdited);
      ctrl.dispose();
    }
    _customChipCtrls.clear();
    _gameIdentifierCtrl.removeListener(_onGameIdentifierEdited);
    _gameIdentifierCtrl.dispose();
    _sepEditCtrl.dispose();
    _customCreatorCtrl.removeListener(_onCustomCreatorEdited);
    _customCreatorCtrl.dispose();
    _customCreditCtrl.removeListener(_onCustomCreditEdited);
    _customCreditCtrl.dispose();
    _customNarrativeInlineFocus.dispose();
    _renameCaptionStyleNameCtrl?.dispose();
    super.dispose();
  }

  static String _pillShortLabel(CaptionSegment s) {
    switch (s) {
      case CaptionSegment.location:
        return 'Geographical';
      case CaptionSegment.city:
        return 'City';
      case CaptionSegment.state:
        return 'State';
      case CaptionSegment.country:
        return 'Country';
      case CaptionSegment.countryCode:
        return 'Country code';
      case CaptionSegment.date:
        // Legacy combined chip — expanded to Month/Day/Year before display.
        return 'Month';
      case CaptionSegment.month:
        return 'Month';
      case CaptionSegment.day:
        return 'Day';
      case CaptionSegment.year:
        return 'Year';
      case CaptionSegment.weekday:
        return 'Weekday';
      case CaptionSegment.caption:
        return 'Caption';
      case CaptionSegment.customText:
      case CaptionSegment.freeText:
        // Shown as the typed words in the strip; menu label is just "Text".
        return 'Text';
      case CaptionSegment.venue:
        return 'IPTC:Location';
      case CaptionSegment.creator:
        return 'Name';
      case CaptionSegment.agency:
        return 'Credit';
      case CaptionSegment.credit:
        return 'IPTC:Byline';
      case CaptionSegment.separator:
        return 'Separator';
      case CaptionSegment.punctuation:
        return 'Custom';
    }
  }

  String _segmentDisplayLabel(CaptionSegment segment, int atIndex) {
    final base = _pillShortLabel(segment);
    if (!_isGeoFieldSegment(segment) &&
        !_isDatePartSegment(segment) &&
        segment != CaptionSegment.date &&
        segment != CaptionSegment.separator &&
        segment != CaptionSegment.punctuation &&
        segment != CaptionSegment.freeText) {
      return base;
    }
    var seen = 0;
    for (var i = 0; i <= atIndex && i < _template.segmentOrder.length; i++) {
      if (_template.segmentOrder[i] == segment) seen++;
    }
    return seen <= 1 ? base : '$base $seen';
  }

  Widget _activeEditIndicator() {
    if (!_locationEditorOpen &&
        !_dateEditorOpen &&
        !_captionPreviewSelected &&
        !_venuePreviewSelected &&
        !_bylinePreviewSelected &&
        !_customTextSnippetEditorOpen &&
        !_freeTextSnippetEditorOpen &&
        !_separatorSnippetEditorOpen &&
        !_punctuationSnippetEditorOpen &&
        _focusedGapIndex == null) {
      return const SizedBox.shrink();
    }
    String label;
    if (_focusedGapIndex != null) {
      label = 'Separator';
    } else if (_activeFormulaIndex != null &&
        _activeFormulaIndex! >= 0 &&
        _activeFormulaIndex! < _template.segmentOrder.length) {
      final activeSegment = _template.segmentOrder[_activeFormulaIndex!];
      label = _segmentDisplayLabel(activeSegment, _activeFormulaIndex!);
    } else {
      label = _locationEditorOpen
          ? 'Location'
          : _dateEditorOpen
              ? 'Month'
              : _captionPreviewSelected
                  ? 'Caption'
                  : _venuePreviewSelected
                      ? 'Venue'
                      : _separatorSnippetEditorOpen
                          ? 'Separator'
                          : _punctuationSnippetEditorOpen
                              ? 'Custom'
                              : 'Byline';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: _sectionTitleStyle,
        ),
      ],
    );
  }

  Widget _bylineEditor() {
    final saved = _template.bylineOptions;
    final view = _bylineViewOrder();

    // Map view-index -> custom occurrence index. We walk the *view* (which is
    // saved + missing-canonical-appended) but custom occurrences only live in
    // saved order. Since canonical kinds are appended at the end and customs
    // are interleaved with saved-only chips, customs in the view appear in
    // the same relative order as in saved — so a simple running counter on
    // view positions is correct.
    var customOcc = 0;
    final occByIndex = <int, int>{};
    final included = <int>[];
    for (var i = 0; i < view.length; i++) {
      final kind = view[i];
      final occ = kind == BylineFieldKind.custom ? customOcc++ : 0;
      occByIndex[i] = occ;
      final isCustomKind = kind == BylineFieldKind.custom ||
          kind == BylineFieldKind.customCreator ||
          kind == BylineFieldKind.customCredit;
      final disabled = !isCustomKind &&
          (saved.disabledKinds.contains(kind) ||
              !saved.fieldOrder.contains(kind));
      if (!disabled) included.add(i);
    }
    final chips = <Widget>[];
    for (var n = 0; n < included.length; n++) {
      final i = included[n];
      chips.add(_bylineFieldChip(
        view[i],
        viewIndex: i,
        customOccurrence: occByIndex[i] ?? 0,
      ));
      if (n < included.length - 1) {
        chips.add(_BylineSeparatorInput(
          key: ValueKey('byline-sep-$i'),
          value: saved.between,
          onChanged: _setBylineBetween,
        ));
      }
    }

    final editingOcc = _editingCustomOccurrence;
    final editingCtrl =
        (editingOcc != null && editingOcc < _customChipCtrls.length)
            ? _customChipCtrls[editingOcc]
            : null;

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bylinePreviewLine(),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _BylineWideInput(
                label: 'Prefix',
                controller: _bylinePrefixCtrl,
              ),
              ...chips,
              _BylineWideInput(
                label: 'Suffix',
                controller: _bylineSuffixCtrl,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _bylineAddFieldButton(),
          // Text inputs for custom-typed fields when they are active.
          if (saved.fieldOrder.contains(BylineFieldKind.customCreator)) ...[
            const SizedBox(height: 6),
            _BylineLabeledInput(
              label: 'Custom Creator:',
              controller: _customCreatorCtrl,
            ),
          ],
          if (saved.fieldOrder.contains(BylineFieldKind.customCredit)) ...[
            const SizedBox(height: 6),
            _BylineLabeledInput(
              label: 'Custom Credit:',
              controller: _customCreditCtrl,
            ),
          ],
          if (editingCtrl != null) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Custom text:',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _ffOf(context).textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: 28,
                    child: _GapSeparatorField(controller: editingCtrl),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _fieldPreviewLine(String rendered) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            'Preview:',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _ffOf(context).textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              rendered,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _ffOf(context).text,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Live preview line at the bottom of the byline editor — same pattern as
  /// the location editor's [Preview:] strip. Renders the current
  /// [BylineOptions] against the dialog's preview [GameInfo] so the user can
  /// see exactly what their byline will look like as they toggle / drag /
  /// type.
  Widget _bylinePreviewLine() {
    final g = _previewGameInfo;
    final rendered = CaptionFormulaRenderer.formatCreditLine(
      format: _template.creditFormat,
      bylineOptions: _template.bylineOptions,
      photographerName: g.photographerName,
      agencyName: g.agencyName,
      iptcMetadata: g.iptcMetadata,
      sampleAgency: _sampleAgencyForWire(_selectedWire),
      customTexts: _template.bylineOptions.customTexts,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text(
            'Preview:',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _ffOf(context).textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              rendered.isEmpty ? '(empty byline)' : rendered,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: rendered.isEmpty
                    ? _ffOf(context).text.withValues(alpha: 0.45)
                    : _ffOf(context).text,
                fontStyle:
                    rendered.isEmpty ? FontStyle.italic : FontStyle.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _setBylineBetween(String value) {
    if (_bylineBetweenCtrl.text == value) return;
    _bylineBetweenCtrl.text = value;
    _bylineBetweenCtrl.selection =
        TextSelection.collapsed(offset: value.length);
  }

  void _setVenuePrefix(String value) {
    setState(() {
      _template = _template.copyWith(venuePrefix: value);
    });
  }

  void _setVenueSuffix(String value) {
    setState(() {
      _template = _template.copyWith(venueSuffix: value);
    });
  }

  void _setCaptionPrefix(String value) {
    setState(() {
      _template = _template.copyWith(captionPrefix: value);
    });
  }

  void _setCaptionSuffix(String value) {
    setState(() {
      _template = _template.copyWith(captionSuffix: value);
    });
  }

  void _setGameIdentifierPrefix(String value) {
    setState(() {
      _template = _template.copyWith(gameIdentifierPrefix: value);
    });
  }

  void _setGameIdentifierSuffix(String value) {
    setState(() {
      _template = _template.copyWith(gameIdentifierSuffix: value);
    });
  }

  Widget _captionSegmentEditor() {
    final sampleCaption = _resolvedSampleCaption();
    return _simpleSegmentSeparatorEditor(
      label: 'Caption',
      body: sampleCaption,
      prefix: _template.captionPrefix,
      suffix: _template.captionSuffix,
      onPrefixChanged: _setCaptionPrefix,
      onSuffixChanged: _setCaptionSuffix,
    );
  }

  Widget _simpleSegmentSeparatorEditor({
    required String label,
    required String body,
    required String prefix,
    required String suffix,
    required ValueChanged<String> onPrefixChanged,
    required ValueChanged<String> onSuffixChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
          decoration: BoxDecoration(
            color: _ffOf(context).sunken,
            borderRadius: BorderRadius.circular(FfTokens.radiusChip),
            border: Border.all(color: _ffOf(context).divider),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _BylineSeparatorInput(
                key: ValueKey('$label-prefix'),
                value: prefix,
                onChanged: onPrefixChanged,
              ),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 32),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _ffOf(context).sunken,
                    border: Border.all(
                      color: _ffOf(context).text.withValues(alpha: 0.16),
                      width: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$label $body',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _ffOf(context).text,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
              _BylineSeparatorInput(
                key: ValueKey('$label-suffix'),
                value: suffix,
                onChanged: onSuffixChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Edited in place, beside the token it belongs to — not in a panel at the bottom of the dialog.',
            style: TextStyle(
              fontSize: 10,
              height: 1.35,
              color: _ffOf(context).text.withValues(alpha: 0.45),
            ),
          ),
        ),
      ],
    );
  }

  Widget _venueEditor() {
    final venue = CaptionFormulaRenderer.venueLabel(_previewGameInfo);
    final rendered = '${_template.venuePrefix}$venue${_template.venueSuffix}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldPreviewLine(rendered),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
          decoration: BoxDecoration(
            color: _ffOf(context).sunken,
            borderRadius: BorderRadius.circular(FfTokens.radiusChip),
            border: Border.all(color: _ffOf(context).divider),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _BylineSeparatorInput(
                key: const ValueKey('venue-prefix'),
                value: _template.venuePrefix,
                onChanged: _setVenuePrefix,
              ),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 32),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _ffOf(context).sunken,
                    border: Border.all(
                      color: _ffOf(context).text.withValues(alpha: 0.16),
                      width: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'IPTC:Location $venue',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _ffOf(context).text,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
              _BylineSeparatorInput(
                key: const ValueKey('venue-suffix'),
                value: _template.venueSuffix,
                onChanged: _setVenueSuffix,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bylineFieldChip(
    BylineFieldKind kind, {
    required int viewIndex,
    int customOccurrence = 0,
  }) {
    final saved = _template.bylineOptions;
    final isCustomKind = kind == BylineFieldKind.custom ||
        kind == BylineFieldKind.customCreator ||
        kind == BylineFieldKind.customCredit;
    final inSaved = saved.fieldOrder.contains(kind);
    final disabled =
        !isCustomKind && (saved.disabledKinds.contains(kind) || !inSaved);
    final enabled = !disabled;

    String label;
    bool caps;
    switch (kind) {
      case BylineFieldKind.name:
        label = 'IPTC Creator';
        caps = saved.nameCaps;
        break;
      case BylineFieldKind.credit:
        label = 'IPTC Credit';
        caps = saved.creditCaps;
        break;
      case BylineFieldKind.copyright:
        label = 'IPTC Copyright';
        caps = saved.copyrightCaps;
        break;
      case BylineFieldKind.custom:
        label = 'Custom text';
        caps = false;
        break;
      case BylineFieldKind.customCreator:
        label = 'Custom Creator';
        caps = saved.nameCaps;
        break;
      case BylineFieldKind.customCredit:
        label = 'Custom Credit';
        caps = saved.creditCaps;
        break;
    }

    final sample = _bylineSampleValue(kind, customOccurrence: customOccurrence);
    final isEditingThis = kind == BylineFieldKind.custom
        ? _editingCustomOccurrence == customOccurrence
        : false;

    Widget buildChipBody({required Widget handle}) {
      return Opacity(
        opacity: enabled || isCustomKind ? 1.0 : 0.55,
        child: Container(
          height: 32,
          padding: const EdgeInsets.only(left: 6, right: 4),
          decoration: BoxDecoration(
            color: _ffOf(context).sunken,
            border: Border.all(
              color: isEditingThis
                  ? _ffOf(context).accent.withValues(alpha: 0.85)
                  : _ffOf(context).text.withValues(alpha: 0.16),
              width: isEditingThis ? 1 : 0.5,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              handle,
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _ffOf(context).text,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  sample,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: _ffOf(context).textSecondary,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (isCustomKind) ...[
                if (kind == BylineFieldKind.custom) ...[
                  _BylineChipIconButton(
                    tooltip: 'Edit text',
                    onTap: () => setState(() {
                      _editingCustomOccurrence =
                          _editingCustomOccurrence == customOccurrence
                              ? null
                              : customOccurrence;
                    }),
                    background:
                        isEditingThis ? _ffOf(context).selectedFill : _ffOf(context).sunken,
                    child: PhosphorIcon(PhosphorIconsRegular.pencilSimple,
                      size: 11,
                      color: _ffOf(context).textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                _BylineChipIconButton(
                  tooltip: 'Remove',
                  onTap: () => _removeBylineFieldAtView(viewIndex),
                  background: _ffOf(context).sunken,
                  child: PhosphorIcon(PhosphorIconsRegular.x,
                    size: 11,
                    color: _ffOf(context).textSecondary,
                  ),
                ),
              ] else ...[
                _BylineChipIconButton(
                  tooltip: 'ALL CAPS',
                  onTap: () => _toggleBylineFieldCaps(kind),
                  background: caps ? _ffOf(context).selectedFill : _ffOf(context).sunken,
                  child: Text(
                    'Aa',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _ffOf(context).text,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _BylineChipIconButton(
                  tooltip: 'Remove',
                  onTap: () => _removeBylineFieldAtView(viewIndex),
                  background: _ffOf(context).sunken,
                  child: PhosphorIcon(PhosphorIconsRegular.x,
                    size: 11,
                    color: _ffOf(context).textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    Widget staticHandle() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: PhosphorIcon(PhosphorIconsRegular.dotsSixVertical,
            size: 14,
            color: _ffOf(context).text.withValues(alpha: 0.45),
          ),
        );

    final feedbackChip = buildChipBody(handle: staticHandle());

    final draggableHandle = Draggable<int>(
      data: viewIndex,
      feedback: Material(
        color: Colors.transparent,
        elevation: 4,
        borderRadius: BorderRadius.circular(6),
        child: Opacity(opacity: 0.92, child: feedbackChip),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Tooltip(
          message: 'Drag to reorder',
          child: staticHandle(),
        ),
      ),
    );

    final chipCore = buildChipBody(handle: draggableHandle);

    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != viewIndex,
      onAcceptWithDetails: (d) => _reorderBylineFromView(d.data, viewIndex),
      builder: (context, candidate, _) {
        final hot = candidate.isNotEmpty;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: hot ? _ffOf(context).accent : Colors.transparent,
                width: 2,
              ),
              right: BorderSide(
                color: hot ? _ffOf(context).accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: chipCore,
        );
      },
    );
  }

  /// View-index aware variant of [_removeBylineFieldAt]. The view contains
  /// chips that aren't in the persisted [fieldOrder] yet (canonical kinds
  /// appended for display only). Removing those is a no-op since they're
  /// already absent from saved. For chips that are in saved, find the saved
  /// index and delegate.
  void _removeBylineFieldAtView(int viewIndex) {
    final view = _bylineViewOrder();
    if (viewIndex < 0 || viewIndex >= view.length) return;
    final kind = view[viewIndex];
    final saved = _template.bylineOptions.fieldOrder;
    if (kind == BylineFieldKind.custom) {
      // Customs only live in saved, and saved-customs preserve the same
      // relative order as view-customs, so the saved index for this view
      // chip is the count of saved chips up to viewIndex (clamped).
      final customsBefore =
          view.take(viewIndex).where((k) => k == BylineFieldKind.custom).length;
      var savedIdx = -1;
      var seen = 0;
      for (var i = 0; i < saved.length; i++) {
        if (saved[i] == BylineFieldKind.custom) {
          if (seen == customsBefore) {
            savedIdx = i;
            break;
          }
          seen++;
        }
      }
      if (savedIdx == -1) return;
      _removeBylineFieldAt(savedIdx);
      return;
    }
    // Non-custom kinds appear at most once in saved.
    final savedIdx = saved.indexOf(kind);
    if (savedIdx == -1) return;
    _removeBylineFieldAt(savedIdx);
  }

  /// Sample value rendered in each chip's body (so users can see what the
  /// chip will produce without checking the live preview line below).
  /// Non-custom samples come from the dialog's [_previewGameInfo] / wire
  /// fallback, so they automatically reflect imported IPTC data when
  /// available; custom returns the user's typed text (or "<custom text>" when
  /// empty).
  String _bylineSampleValue(
    BylineFieldKind kind, {
    int customOccurrence = 0,
  }) {
    String sample;
    String fromIptc(List<String> keys) {
      for (final k in keys) {
        final v = _previewGameInfo.iptcMetadata[k]?.trim();
        if (v != null && v.isNotEmpty) return v;
      }
      return '';
    }

    final agency = _sampleAgencyForWire(_selectedWire);
    switch (kind) {
      case BylineFieldKind.name:
        sample = _previewGameInfo.photographerName.trim();
        if (sample.isEmpty) sample = 'Photographer';
        if (_template.bylineOptions.nameCaps) sample = sample.toUpperCase();
        return sample;
      case BylineFieldKind.credit:
        sample = _previewGameInfo.agencyName.trim();
        if (sample.isEmpty) sample = fromIptc(const ['IPTC:Credit', 'Credit']);
        if (sample.isEmpty) {
          sample = CaptionFormulaRenderer.defaultAgencyLabel(agency);
        }
        if (_template.bylineOptions.creditCaps ||
            _template.bylineOptions.organizationCaps) {
          sample = sample.toUpperCase();
        }
        return sample;
      case BylineFieldKind.copyright:
        sample = fromIptc(const [
          'IPTC:CopyrightNotice',
          'CopyrightNotice',
          'Copyright',
          'XMP:Copyright',
        ]);
        if (sample.isEmpty) {
          sample = CaptionFormulaRenderer.defaultAgencyLabel(agency);
        }
        if (_template.bylineOptions.copyrightCaps)
          sample = sample.toUpperCase();
        return sample;
      case BylineFieldKind.custom:
        final txt = customOccurrence < _customChipCtrls.length
            ? _customChipCtrls[customOccurrence].text.trim()
            : '';
        return txt.isEmpty ? '<custom text>' : txt;
      case BylineFieldKind.customCreator:
        final txt = _customCreatorCtrl.text.trim();
        return txt.isEmpty ? '<type name>' : txt;
      case BylineFieldKind.customCredit:
        final txt = _customCreditCtrl.text.trim();
        return txt.isEmpty ? '<type credit>' : txt;
    }
  }

  Widget _sourceOptionChip({
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? _ffOf(context).selectedFill : _ffOf(context).sunken,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? _ffOf(context).accent : _ffOf(context).divider,
          width: selected ? 1.2 : 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: selected ? _ffOf(context).accent : _ffOf(context).text.withValues(alpha: 0.88),
            ),
          ),
        ),
      ),
    );
  }

  /// Separate pills: the selected choice is filled, the others stay outlined.
  Widget _optionSegmentedControl({
    required List<_SegOption> options,
  }) {
    final t = _ffOf(context);
    final outline = t.divider;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        border: Border.all(color: outline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FfTokens.radiusChip - 0.5),
        child: Row(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0)
                Container(width: 0.5, height: 28, color: outline),
              Expanded(
                child: Material(
                  color: options[i].selected ? t.sunken : Colors.transparent,
                  child: InkWell(
                    onTap: _coreStyleLocked ? null : options[i].onTap,
                    child: Container(
                      height: 28,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        options[i].label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.0,
                          fontWeight: FontWeight.w500,
                          color: options[i].selected
                              ? t.text
                              : t.text.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _teamOrderSegments() {
    return _optionSegmentedControl(
      options: [
        _SegOption(
          label: 'Before',
          selected: _template.captionTeamOrder == CaptionTeamOrder.teamBefore,
          onTap: () => setState(() {
            _template = _template.copyWith(
                captionTeamOrder: CaptionTeamOrder.teamBefore);
          }),
        ),
        _SegOption(
          label: 'After',
          selected: _template.captionTeamOrder == CaptionTeamOrder.teamAfter,
          onTap: () => setState(() {
            _template = _template.copyWith(
              captionTeamOrder: CaptionTeamOrder.teamAfter,
              useTeamPossessive: false,
            );
          }),
        ),
      ],
    );
  }

  Widget _englishSegments() {
    return _optionSegmentedControl(
      options: [
        _SegOption(
          label: 'American',
          selected: _template.americanEnglish,
          onTap: () => setState(() {
            _template = _template.copyWith(americanEnglish: true);
          }),
        ),
        _SegOption(
          label: 'International',
          selected: !_template.americanEnglish,
          onTap: () => setState(() {
            _template = _template.copyWith(americanEnglish: false);
          }),
        ),
      ],
    );
  }

  Widget _numberFormatSegments() {
    return _optionSegmentedControl(
      options: [
        _SegOption(
          label: '#99',
          selected: _template.numberFormat == NumberFormatStyle.hash,
          onTap: () => setState(() {
            _template =
                _template.copyWith(numberFormat: NumberFormatStyle.hash);
          }),
        ),
        _SegOption(
          label: '(99)',
          selected: _template.numberFormat == NumberFormatStyle.parens,
          onTap: () => setState(() {
            _template =
                _template.copyWith(numberFormat: NumberFormatStyle.parens);
          }),
        ),
      ],
    );
  }

  Widget _positionSegments() {
    final gettyLocked = _selectedWire == WireStyle.getty ||
        _selectedWire == WireStyle.gettyInternational;
    final include = gettyLocked ? false : _template.includePlayerPosition;
    return _optionSegmentedControl(
      options: [
        _SegOption(
          label: 'On',
          selected: include,
          onTap: () {
            if (gettyLocked || _coreStyleLocked) return;
            setState(() {
              _template = _template.copyWith(includePlayerPosition: true);
            });
          },
        ),
        _SegOption(
          label: 'Off',
          selected: !include,
          onTap: () {
            if (gettyLocked || _coreStyleLocked) return;
            setState(() {
              _template = _template.copyWith(includePlayerPosition: false);
            });
          },
        ),
      ],
    );
  }

  Widget _diacriticsSegments() {
    return _optionSegmentedControl(
      options: [
        _SegOption(
          label: 'Keep',
          selected: !_template.removeDiacritics,
          onTap: () => setState(() {
            _template = _template.copyWith(removeDiacritics: false);
          }),
        ),
        _SegOption(
          label: 'Remove',
          selected: _template.removeDiacritics,
          onTap: () => setState(() {
            _template = _template.copyWith(removeDiacritics: true);
          }),
        ),
      ],
    );
  }

  Widget _timingPhraseSegments() {
    final include = _template.includeTimingPhrase;
    return Tooltip(
      message: include
          ? 'Include the $_timingUnitNoun in the caption'
          : 'Omit the $_timingUnitNoun from the caption',
      waitDuration: const Duration(milliseconds: 400),
      child: _optionSegmentedControl(
        options: [
          _SegOption(
            label: 'Show',
            selected: include,
            onTap: () {
              if (_coreStyleLocked) return;
              setState(() {
                _template = _template.copyWith(includeTimingPhrase: true);
              });
            },
          ),
          _SegOption(
            label: 'Hide',
            selected: !include,
            onTap: () {
              if (_coreStyleLocked) return;
              setState(() {
                _template = _template.copyWith(includeTimingPhrase: false);
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> _setShowKeywordsField(bool show) async {
    if (_coreStyleLocked) return;
    setState(() => _template = _template.copyWith(showKeywordsField: show));
  }

  Future<void> _setShowPersonalityField(bool show) async {
    if (_coreStyleLocked) return;
    setState(() => _template = _template.copyWith(showPersonalityField: show));
  }

  Widget _layoutOptionalFieldRow({
    required String label,
    required bool value,
    required Future<void> Function(bool) onSave,
  }) {
    return Row(
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _layoutOptionTextStyle,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          height: 22,
          child: FittedBox(
            child: Switch.adaptive(
              value: value,
              activeTrackColor: _ffOf(context).accent,
              inactiveTrackColor: _ffOf(context).hover,
              thumbColor: const WidgetStatePropertyAll(Colors.white),
              onChanged: _coreStyleLocked ? null : (next) => onSave(next),
            ),
          ),
        ),
      ],
    );
  }

  LocationLineOptions _activeLocationLineOptions() {
    final idx = _activeFormulaIndex;
    if (idx == null ||
        idx < 0 ||
        idx >= _template.segmentOrder.length ||
        !_isGeoFieldSegment(_template.segmentOrder[idx])) {
      return _template.locationOptions;
    }
    final seg = _template.segmentOrder[idx];
    final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
        _template.segmentOrder, idx, seg);
    return CaptionFormulaRenderer.locationLineOptionsForOccurrence(
        _template, occ);
  }

  LocationChipKind? _activeGeoChipKind() {
    final idx = _activeFormulaIndex;
    if (idx == null ||
        idx < 0 ||
        idx >= _template.segmentOrder.length) {
      return null;
    }
    switch (_template.segmentOrder[idx]) {
      case CaptionSegment.city:
        return LocationChipKind.city;
      case CaptionSegment.state:
        return LocationChipKind.region;
      case CaptionSegment.country:
        return LocationChipKind.country;
      case CaptionSegment.countryCode:
        return LocationChipKind.countryCode;
      case CaptionSegment.location:
        return null;
      default:
        return null;
    }
  }

  /// Minimal per-field editor for {City} / {State} / {Country}.
  Widget _locationOptionsEditor() {
    final kind = _activeGeoChipKind();
    if (kind == null) {
      return const SizedBox.shrink();
    }
    final opts = _activeLocationLineOptions();
    LocationChip chip = LocationChip(id: 'geo_${kind.name}', kind: kind);
    for (final c in opts.chips) {
      if (c.kind == kind) {
        chip = c;
        break;
      }
    }
    final sample = CaptionFormulaRenderer.formatGeoField(
      game: _captionPreviewGame,
      options: opts,
      kind: kind,
      apStyleCaption: _template.wireStyle == WireStyle.ap,
          cpStyleCaption: _template.wireStyle == WireStyle.cp,
      forceAutoAdaptUsIntl: _isGettyWire,
    );
    final label = kind == LocationChipKind.city
        ? 'City'
        : kind == LocationChipKind.region
            ? 'State'
            : kind == LocationChipKind.countryCode
                ? 'Country code'
                : 'Country';

    void upsertChip(LocationChip next) {
      final chips = List<LocationChip>.from(opts.chips);
      final i = chips.indexWhere((c) => c.kind == kind);
      if (i >= 0) {
        chips[i] = next;
      } else {
        chips.add(next);
      }
      _commitLocationOptions(opts.copyWith(chips: chips));
    }

    final t = _ffOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: t.text,
          ),
        ),
        const SizedBox(height: 8),
        if (sample.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              sample,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: t.textSecondary,
              ),
            ),
          ),
        Row(
          children: [
            Text(
              'ALL CAPS',
              style: TextStyle(fontSize: 12, color: t.textSecondary),
            ),
            const Spacer(),
            _allCapsButton(
              active: chip.caps,
              onTap: _coreStyleLocked
                  ? null
                  : () => upsertChip(chip.copyWith(caps: !chip.caps)),
            ),
          ],
        ),
        if (kind == LocationChipKind.region) ...[
          const SizedBox(height: 8),
          Text(
            'Format',
            style: TextStyle(fontSize: 12, color: t.textSecondary),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in LocationRegionVariant.values)
                if (v != LocationRegionVariant.apStyle || _isApWire)
                  ChoiceChip(
                    label: Text(locationRegionVariantLabel(v)),
                    selected: chip.regionVariant == v,
                    onSelected: _coreStyleLocked
                        ? null
                        : (_) => upsertChip(chip.copyWith(regionVariant: v)),
                  ),
            ],
          ),
          if (_isApWire &&
              chip.regionVariant == LocationRegionVariant.apStyle) ...[
            const SizedBox(height: 8),
            Text(
              'Hide state for standalone cities; abbreviate others '
              '(Calif., N.Y., Ohio). Accepts full name, AP abbrev, or postal.',
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
                color: t.textSecondary,
              ),
            ),
          ],
        ],
        if (kind == LocationChipKind.country) ...[
          const SizedBox(height: 8),
          Text(
            'Format',
            style: TextStyle(fontSize: 12, color: t.textSecondary),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final v in LocationCountryVariant.values)
                ChoiceChip(
                  label: Text(locationCountryVariantLabel(v)),
                  selected: chip.countryVariant == v,
                  onSelected: _coreStyleLocked
                      ? null
                      : (_) => upsertChip(chip.copyWith(countryVariant: v)),
                ),
            ],
          ),
        ],
        if (_isGettyWire &&
            (kind == LocationChipKind.region ||
                kind == LocationChipKind.country)) ...[
          const SizedBox(height: 10),
          Text(
            kind == LocationChipKind.region
                ? 'Shown for games in the United States; hidden elsewhere.'
                : 'Shown outside the United States; hidden for US games.',
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: t.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  DateFieldKind? _activeDatePartKind() {
    final idx = _activeFormulaIndex;
    if (idx == null ||
        idx < 0 ||
        idx >= _template.segmentOrder.length) {
      return null;
    }
    return CaptionFormulaRenderer.dateFieldKindForSegment(
        _template.segmentOrder[idx]);
  }

  /// Minimal per-field editor for {Month} / {Day} / {Year} (and weekday).
  /// Combined [CaptionSegment.date] chips are expanded before this opens.
  Widget _dateLineEditor() {
    final kind = _activeDatePartKind();
    if (kind == null) {
      // Leftover combined date chip — expand into Month/Day/Year and reopen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_template.segmentOrder.contains(CaptionSegment.date)) return;
        setState(() {
          _initGapControllers(_template);
          final mi = _template.segmentOrder.indexWhere(_isDatePartSegment);
          if (mi >= 0) {
            _activeFormulaIndex = mi;
            _dateEditorOpen = true;
          } else {
            _dateEditorOpen = false;
            _activeFormulaIndex = null;
          }
        });
      });
      return const SizedBox.shrink();
    }

    final idx = _activeFormulaIndex!;
    final seg = _template.segmentOrder[idx];
    final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
        _template.segmentOrder, idx, seg);
    final token = _template.datePartTokenFor(kind: kind, occurrenceIndex: occ);
    final sample = CaptionFormulaRenderer.formatDatePart(
      game: _previewGameInfo,
      template: _template,
      kind: kind,
      occurrenceIndex: occ,
    );
    final options = kDateFieldOptions[kind]!;
    final optionIndex = token.optionIndex.clamp(0, options.length - 1);
    final showCaps =
        kind == DateFieldKind.month || kind == DateFieldKind.weekday;
    final t = _ffOf(context);

    void commit(DateFieldToken next) {
      setState(() {
        _template =
            _templateWithDatePartAtOccurrence(_template, kind, occ, next);
      });
      _scheduleAutosave();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _pillShortLabel(seg),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: t.text,
          ),
        ),
        const SizedBox(height: 8),
        if (sample.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              sample,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: t.textSecondary,
              ),
            ),
          ),
        Text(
          'Format',
          style: TextStyle(fontSize: 12, color: t.textSecondary),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            for (var i = 0; i < options.length; i++)
              ChoiceChip(
                label: Text(options[i].label),
                selected: optionIndex == i,
                onSelected: _coreStyleLocked
                    ? null
                    : (_) => commit(DateFieldToken(
                          kind: kind,
                          optionIndex: i,
                          caps: token.caps,
                          enabled: token.enabled,
                        )),
              ),
          ],
        ),
        if (showCaps) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'ALL CAPS',
                style: TextStyle(fontSize: 12, color: t.textSecondary),
              ),
              const Spacer(),
              _allCapsButton(
                active: token.caps,
                onTap: _coreStyleLocked
                    ? null
                    : () => commit(DateFieldToken(
                          kind: kind,
                          optionIndex: optionIndex,
                          caps: !token.caps,
                          enabled: token.enabled,
                        )),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Pressable Aa control (not a switch) — same idea as byline / date chips.
  Widget _allCapsButton({
    required bool active,
    required VoidCallback? onTap,
  }) {
    final t = _ffOf(context);
    final enabled = onTap != null;
    return Tooltip(
      message: 'ALL CAPS',
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: active ? t.selectedFill : t.sunken,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: t.divider),
            borderRadius: BorderRadius.circular(6),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                'Aa',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle get _captionFullPreviewStyle => TextStyle(
        fontSize: 13,
        height: 1.45,
        color: _t.text,
        fontWeight: FontWeight.w500,
      );

  /// Game identifier is edited via the panel editor, not inline in the preview.
  bool get _singleCustomNarrativeInlineEligible => false;

  void _onLayoutEdgeFocusChanged({required bool prefix, required bool focused}) {
    setState(() {
      if (prefix) {
        _layoutPrefixFocused = focused;
      } else {
        _layoutSuffixFocused = focused;
      }
      if (focused) {
        _focusedGlueSegmentIndex = null;
        _activeFormulaIndex = null;
        _focusedGapIndex = null;
        _locationEditorOpen = false;
        _dateEditorOpen = false;
        _captionPreviewSelected = false;
        _venuePreviewSelected = false;
        _bylinePreviewSelected = false;
        _customTextSnippetEditorOpen = false;
        _freeTextSnippetEditorOpen = false;
        _separatorSnippetEditorOpen = false;
        _punctuationSnippetEditorOpen = false;
        if (prefix) {
          _layoutSuffixFocused = false;
        } else {
          _layoutPrefixFocused = false;
        }
      }
    });
  }

  /// Finds the selected structure chip or separator inside [full].
  ({int start, int end})? _highlightRangeInPreview({
    required String full,
    required String sampleCaption,
    required CreditSampleAgency sampleAgency,
  }) {
    final highlightIndex = _focusedGlueSegmentIndex ?? _activeFormulaIndex;
    final highlightPrefix = _layoutPrefixFocused;
    final highlightSuffix = _layoutSuffixFocused;
    if (full.isEmpty ||
        (highlightIndex == null && !highlightPrefix && !highlightSuffix)) {
      return null;
    }

    final order = _template.segmentOrder;
    final hasGlue = order.any(_isGlueSegment);
    final gaps = CaptionFormulaRenderer.effectiveSegmentGaps(_template);
    final pieces = <({String text, bool hit})>[];

    void add(String text, bool hit) {
      pieces.add((text: text, hit: hit));
    }

    add(_template.layoutPrefix, highlightPrefix);
    for (var i = 0; i < order.length; i++) {
      final seg = order[i];
      if ((seg == CaptionSegment.customText || seg == CaptionSegment.freeText) &&
          _previewSegmentText(i, sampleCaption, sampleAgency).trim().isEmpty) {
        continue;
      }
      add(
        _previewSegmentText(i, sampleCaption, sampleAgency),
        highlightIndex == i,
      );
      if (!hasGlue && i < order.length - 1 && i < gaps.length) {
        add(gaps[i], false);
      }
    }
    add(_template.layoutSuffix, highlightSuffix);

    var cursor = 0;
    ({int start, int end})? hit;
    for (final piece in pieces) {
      if (piece.text.isEmpty) continue;
      final found = _locatePreviewPiece(full, piece.text, cursor);
      if (found == null) continue;
      if (piece.hit) hit = found;
      cursor = found.end;
    }
    return hit;
  }

  ({int start, int end})? _locatePreviewPiece(
    String full,
    String part,
    int cursor,
  ) {
    if (cursor < 0 || cursor > full.length || part.isEmpty) return null;
    var idx = full.indexOf(part, cursor);
    var length = part.length;
    if (idx < 0) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) {
        var i = cursor;
        final take = part.length;
        while (i < full.length && i - cursor < take && full[i] == ' ') {
          i++;
        }
        if (i == cursor && cursor < full.length && full[cursor] == ' ') {
          i = cursor + 1;
        }
        if (i > cursor) return (start: cursor, end: i);
        return null;
      }
      idx = full.indexOf(trimmed, cursor);
      length = trimmed.length;
    }
    if (idx < 0) return null;
    return (start: idx, end: idx + length);
  }

  String _previewSegmentText(
    int segmentIndex,
    String sampleCaption,
    CreditSampleAgency sampleAgency,
  ) {
    final order = _template.segmentOrder;
    if (segmentIndex < 0 || segmentIndex >= order.length) return '';
    final s = order[segmentIndex];
    switch (s) {
      case CaptionSegment.location:
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            order, segmentIndex, CaptionSegment.location);
        final locOpts = CaptionFormulaRenderer.locationLineOptionsForOccurrence(
            _template, occ);
        final gettyWire = _template.wireStyle == WireStyle.getty ||
            _template.wireStyle == WireStyle.gettyInternational;
        return CaptionFormulaRenderer.formatLocationLine(
          _captionPreviewGame,
          locOpts,
          apStyleCaption: _template.wireStyle == WireStyle.ap,
          cpStyleCaption: _template.wireStyle == WireStyle.cp,
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
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            order, segmentIndex, s);
        final locOpts = CaptionFormulaRenderer.locationLineOptionsForOccurrence(
            _template, occ);
        return CaptionFormulaRenderer.formatGeoField(
          game: _captionPreviewGame,
          options: locOpts,
          kind: kind,
          apStyleCaption: _template.wireStyle == WireStyle.ap,
          cpStyleCaption: _template.wireStyle == WireStyle.cp,
          forceAutoAdaptUsIntl: _template.wireStyle == WireStyle.getty ||
              _template.wireStyle == WireStyle.gettyInternational,
          formulaIncludesCountry:
              order.contains(CaptionSegment.country),
        );
      case CaptionSegment.date:
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            order, segmentIndex, CaptionSegment.date);
        final f = CaptionFormulaRenderer.dateFormulaForOccurrence(_template, occ);
        return CaptionFormulaRenderer.formatTemplateDateLine(
          _previewGameInfo,
          _template,
          uppercaseAll: _template.wireStyle == WireStyle.getty ||
              _template.wireStyle == WireStyle.gettyInternational,
          dateFormulaOverride: f,
        );
      case CaptionSegment.month:
      case CaptionSegment.day:
      case CaptionSegment.year:
      case CaptionSegment.weekday:
        final kind = CaptionFormulaRenderer.dateFieldKindForSegment(s)!;
        final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
            order, segmentIndex, s);
        return CaptionFormulaRenderer.formatDatePart(
          game: _previewGameInfo,
          template: _template,
          kind: kind,
          occurrenceIndex: occ,
        );
      case CaptionSegment.caption:
        return '${_template.captionPrefix}$sampleCaption${_template.captionSuffix}';
      case CaptionSegment.customText:
        return '${_template.gameIdentifierPrefix}'
            '${_template.gameIdentifierText.trim()}'
            '${_template.gameIdentifierSuffix}';
      case CaptionSegment.freeText:
        return CaptionFormulaRenderer.freeTextSnippetFor(_template, segmentIndex);
      case CaptionSegment.venue:
        final venue = CaptionFormulaRenderer.venueLabel(_previewGameInfo);
        return '${_template.venuePrefix}$venue${_template.venueSuffix}';
      case CaptionSegment.creator:
        return CaptionFormulaRenderer.formatCreatorName(
          game: _previewGameInfo,
          bylineOptions: _template.bylineOptions,
        );
      case CaptionSegment.agency:
        return CaptionFormulaRenderer.formatAgencyCredit(
          game: _previewGameInfo,
          bylineOptions: _template.bylineOptions,
          sampleAgency: sampleAgency,
        );
      case CaptionSegment.credit:
        final omitCustomInCredit =
            _template.segmentOrder.contains(CaptionSegment.customText);
        return CaptionFormulaRenderer.formatCreditLine(
          format: _template.creditFormat,
          bylineOptions: _template.bylineOptions,
          photographerName: _previewGameInfo.photographerName,
          agencyName: _previewGameInfo.agencyName,
          iptcMetadata: _previewGameInfo.iptcMetadata,
          sampleAgency: sampleAgency,
          apShortParen: _template.wireStyle == WireStyle.ap ||
              _template.wireStyle == WireStyle.cp,
          customTexts: _template.bylineOptions.customTexts,
          includeCustomInCredit: !omitCustomInCredit,
        );
      case CaptionSegment.separator:
        return _normalizeSep(CaptionFormulaRenderer.separatorSnippetFor(
            _template, segmentIndex));
      case CaptionSegment.punctuation:
        return _normalizeSep(CaptionFormulaRenderer.punctuationSnippetFor(
            _template, segmentIndex));
    }
  }

  Widget _fullCaptionPreviewArea({
    required String fullCaptionPreview,
    required CaptionPreviewNarrativeSplit? narrativeSplit,
    ({int start, int end})? highlight,
  }) {
    if (narrativeSplit != null) {
      // No SelectionArea here — it swallows taps before the TextField gets them.
      return LayoutBuilder(
        builder: (context, c) {
          final fieldMax = (c.maxWidth * 0.55).clamp(80.0, 360.0);
          return Text.rich(
            TextSpan(
              style: _captionFullPreviewStyle,
              children: [
                TextSpan(text: narrativeSplit.before),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: 72,
                      maxWidth: fieldMax,
                    ),
                      child: TextField(
                        focusNode: _customNarrativeInlineFocus,
                        controller: _gameIdentifierCtrl,
                        style: _captionFullPreviewStyle,
                        strutStyle: StrutStyle.fromTextStyle(
                          _captionFullPreviewStyle,
                          forceStrutHeight: true,
                        ),
                        maxLines: 4,
                        minLines: 1,
                        decoration: InputDecoration(
                          isDense: true,
                          isCollapsed: false,
                          contentPadding: const EdgeInsets.only(bottom: 2),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: _ffOf(context).accent.withValues(alpha: 0.45), width: 1.5),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: _ffOf(context).accent.withValues(alpha: 0.35), width: 1.5),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: _ffOf(context).accent, width: 2),
                          ),
                          hintText: 'type here…',
                          hintStyle: _captionFullPreviewStyle.copyWith(
                            color: _ffOf(context).text.withValues(alpha: 0.40),
                            fontStyle: FontStyle.normal,
                          ),
                        ),
                      ),
                  ),
                ),
                TextSpan(text: narrativeSplit.after),
              ],
            ),
          );
        },
      );
    }
    // Plain text so the parent InkWell receives taps (SelectionArea would
    // swallow them). Structure chips below are the edit surface.
    final range = highlight;
    if (range != null &&
        range.start >= 0 &&
        range.end > range.start &&
        range.end <= fullCaptionPreview.length) {
      final base = _captionFullPreviewStyle;
      final mark = base.copyWith(
        backgroundColor: _t.accent.withValues(alpha: 0.45),
        color: _t.text,
      );
      return Text.rich(
        TextSpan(
          style: base,
          children: [
            TextSpan(text: fullCaptionPreview.substring(0, range.start)),
            TextSpan(
              text: fullCaptionPreview.substring(range.start, range.end),
              style: mark,
            ),
            TextSpan(text: fullCaptionPreview.substring(range.end)),
          ],
        ),
      );
    }
    return Text(
      fullCaptionPreview,
      style: _captionFullPreviewStyle,
    );
  }

  /// Plain editor for the narrative [CaptionSegment.customText] slot — not the
  /// IPTC byline chip row (name / credit / copyright).
  Widget _customTextSnippetEditor() {
    final rendered = '${_template.gameIdentifierPrefix}'
        '${_gameIdentifierCtrl.text}'
        '${_template.gameIdentifierSuffix}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldPreviewLine(rendered),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _BylineSeparatorInput(
              key: const ValueKey('game-identifier-prefix'),
              value: _template.gameIdentifierPrefix,
              onChanged: _setGameIdentifierPrefix,
            ),
            Expanded(
              child: _CaptionLayoutBorderedMultilineField(
                controller: _gameIdentifierCtrl,
                minLines: 1,
                maxLines: 5,
                autofocus: true,
              ),
            ),
            _BylineSeparatorInput(
              key: const ValueKey('game-identifier-suffix'),
              value: _template.gameIdentifierSuffix,
              onChanged: _setGameIdentifierSuffix,
            ),
          ],
        ),
      ],
    );
  }

  /// Freeform [CaptionSegment.freeText] editor (e.g. Getty NOTE TO USER).
  Widget _freeTextSnippetEditor() {
    final idx = _activeFormulaIndex;
    final suffix = (idx != null &&
            idx >= 0 &&
            idx < _template.segmentOrder.length &&
            _template.segmentOrder[idx] == CaptionSegment.freeText)
        ? CaptionFormulaRenderer.freeTextSuffixFor(_template, idx)
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _CaptionLayoutBorderedMultilineField(
                controller: _freeTextCtrl,
                minLines: 2,
                maxLines: 8,
                autofocus: true,
                hintText: 'Type custom text to include in the caption…',
              ),
            ),
            _BylineSeparatorInput(
              key: ValueKey('free-text-suffix-$idx'),
              value: suffix,
              onChanged: _setFreeTextSuffix,
            ),
          ],
        ),
      ],
    );
  }

  void _ensureExampleTeams() {
    if (_exampleTeamsLoaded) return;
    _exampleTeamsLoaded = true;
    PreferencesService.getInstance().then((prefs) async {
      final last = await prefs.getStartupLastTeams(sport: _sessionSport);
      if (!mounted) return;
      setState(() {
        _savedExampleHome = last.key;
        _savedExampleAway = last.value;
        _rosterPreviewPlayers = null;
        _rosterPreviewLoading = _hasSelectedExampleTeams;
      });
      unawaited(_refreshRosterPreviewPlayers(clearFirst: true));
      if (widget.adminMode) {
        unawaited(_loadAdminPreviewTeamList());
      }
    });
  }

  Future<void> _loadAdminPreviewTeamList({bool force = false}) async {
    if (!widget.adminMode) return;
    final sport = _sessionSport.trim().toLowerCase();
    if (!force &&
        _adminTeamsLoadedForSport == sport &&
        _adminTeamNames.isNotEmpty) {
      return;
    }
    if (mounted) {
      setState(() => _adminTeamsLoading = true);
    }
    try {
      final api = ApiManager()..setSport(sport);
      final teams = await api.fetchTeams();
      final names = teams
          .map((t) => t.name.trim())
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _adminTeamNames = names;
        _adminTeamsLoadedForSport = sport;
        _adminTeamsLoading = false;
      });
    } catch (e) {
      debugPrint('Admin preview team list failed for $sport: $e');
      if (!mounted) return;
      setState(() {
        _adminTeamNames = const [];
        _adminTeamsLoadedForSport = sport;
        _adminTeamsLoading = false;
      });
    }
  }

  Future<void> _setAdminExampleTeam({
    String? home,
    String? away,
  }) async {
    final nextHome = home ?? _savedExampleHome;
    final nextAway = away ?? _savedExampleAway;
    setState(() {
      _savedExampleHome =
          (nextHome == null || nextHome.trim().isEmpty) ? null : nextHome.trim();
      _savedExampleAway =
          (nextAway == null || nextAway.trim().isEmpty) ? null : nextAway.trim();
      // Drop stale roster immediately so the preview waits on the new clubs.
      _rosterPreviewPlayers = null;
      _rosterPreviewLoading = true;
      _previewHomeVenue = null;
    });
    unawaited(_refreshRosterPreviewPlayers(clearFirst: true));
    try {
      final prefs = await PreferencesService.getInstance();
      await prefs.saveStartupLastTeams(
        sport: _sessionSport,
        homeTeam: _savedExampleHome ?? '',
        awayTeam: _savedExampleAway ?? '',
      );
    } catch (e) {
      debugPrint('Could not save admin preview teams: $e');
    }
  }

  Widget _gettyPreviewToggle() {
    Widget pill(String label, bool selected, VoidCallback onTap) {
      return Material(
        color: selected ? _t.sunken : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: selected
                    ? _t.accent.withValues(alpha: 0.85)
                    : _t.text.withValues(alpha: 0.16),
                width: selected ? 1 : 0.5,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.w600,
                color: selected ? _t.text : _t.text.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
      );
    }

    final isUsa = _selectedWire != WireStyle.gettyInternational;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pill('USA', isUsa, () => _setGettyTerritory(unitedStates: true)),
        const SizedBox(width: 4),
        pill(
          'International',
          !isUsa,
          () => _setGettyTerritory(unitedStates: false),
        ),
      ],
    );
  }

  /// Getty USA and International keep separate structures / wire defaults.
  /// The toggle switches which one is being edited (and previewed).
  void _setGettyTerritory({required bool unitedStates}) {
    final target =
        unitedStates ? WireStyle.getty : WireStyle.gettyInternational;
    _gettyPreviewUnitedStates = unitedStates;
    // Saved library styles: preview only — don't abandon the library entry.
    if (_selectedSavedStyleId != null ||
        (_selectedWire != WireStyle.getty &&
            _selectedWire != WireStyle.gettyInternational)) {
      setState(() {});
      return;
    }
    if (_selectedWire == target) {
      setState(() {});
      return;
    }
    _applyWireStyle(target);
  }

  /// True when [text] is only field glue (spaces / commas) that should drop
  /// with an empty auto-adapted State/Country slot.
  bool _isStructureGeoGlue(String text) {
    final t = text.trim();
    if (t.isEmpty) return true;
    return RegExp(r'^[,;|/–—\-]+$').hasMatch(t);
  }

  void _shuffleCaptionSample() {
    final real = _realPreviewPlayers();
    if (_hasSelectedExampleTeams &&
        (real == null || real.isEmpty)) {
      unawaited(_refreshRosterPreviewPlayers());
      return;
    }
    setState(() {
      // Fresh entropy each tap so one-player / few-action cases still change.
      _captionSampleSeed =
          DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    });
  }

  /// Host (New session title row) can shuffle the preview sample.
  void shuffleCaptionSample() => _shuffleCaptionSample();

  /// Whether Structure PREVIEW colour-codes resolved slots.
  bool get structurePreviewColorCode => _structurePreviewColorCode;

  /// Host Caption header can toggle colour-coding on/off.
  void setStructurePreviewColorCode(bool on) {
    if (_structurePreviewColorCode == on) return;
    setState(() => _structurePreviewColorCode = on);
  }

  void toggleStructurePreviewColorCode() {
    setStructurePreviewColorCode(!_structurePreviewColorCode);
  }

  /// Apply sport immediately so preview verbs / timing / teams match the
  /// picker, then notify the host (admin flushes drafts + swaps templates).
  void _onSessionSportPicked(String sport) {
    final next = sport.trim().toLowerCase();
    if (next.isEmpty || next == _sessionSport) return;
    setState(() {
      _sessionSport = next;
      _captionSampleSeed =
          DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
      _exampleTeamsLoaded = false;
      _adminTeamsLoadedForSport = null;
      _rosterPreviewPlayers = null;
      _rosterPreviewLoading = false;
      _previewHomeVenue = null;
    });
    _ensureExampleTeams();
    unawaited(_loadAdminPreviewTeamList(force: true));
    unawaited(_refreshRosterPreviewPlayers(clearFirst: true));
    unawaited(() async {
      await _loadGameIdByWire();
      if (!mounted) return;
      final gid = _gameIdByWire[_selectedWire] ??
          defaultGameIdentifierText(next);
      setState(() {
        _template = _template.copyWith(gameIdentifierText: gid);
        if (_gameIdentifierCtrl.text != gid) {
          _gameIdentifierCtrl.text = gid;
        }
      });
    }());
    widget.onSportChanged?.call(next);
  }

  Widget _shuffleCaptionButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _shuffleCaptionSample,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(PhosphorIconsRegular.shuffle, size: 12, color: _ffOf(context).textSecondary),
              const SizedBox(width: 4),
              Text(
                'Shuffle sample',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: _ffOf(context).textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addFieldButtonChrome() {
    final t = _ffOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        border: Border.all(color: t.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: SizedBox(
          height: 34,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                PhosphorIconsRegular.plus,
                size: 16,
                color: _ffOf(context).text.withValues(alpha: 0.82),
              ),
              const SizedBox(width: 6),
              Text(
                'Add field',
                style: _ffOf(context).metaStyle.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _ffOf(context).text.withValues(alpha: 0.82),
                      height: 1,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bylineAddFieldButton() {
    final saved = _template.bylineOptions;
    final menuStyle = TextStyle(fontSize: 12, color: _ffOf(context).text);
    bool inUse(BylineFieldKind kind) =>
        saved.fieldOrder.contains(kind) &&
        !saved.disabledKinds.contains(kind);
    void add(BylineFieldKind kind) {
      if (saved.fieldOrder.contains(kind)) {
        _setBylineKindEnabled(kind, true);
      } else {
        _addBylineField(kind);
      }
    }

    const options = <(BylineFieldKind, String)>[
      (BylineFieldKind.name, 'IPTC Creator'),
      (BylineFieldKind.credit, 'IPTC Credit'),
      (BylineFieldKind.copyright, 'IPTC Copyright'),
      (BylineFieldKind.customCreator, 'Custom Creator'),
      (BylineFieldKind.customCredit, 'Custom Credit'),
    ];
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<BylineFieldKind>(
        tooltip: 'Add a byline field',
        padding: EdgeInsets.zero,
        offset: const Offset(0, 30),
        onSelected: add,
        itemBuilder: (context) => [
          for (final option in options)
            PopupMenuItem(
              value: option.$1,
              enabled: !inUse(option.$1),
              child: Text(
                inUse(option.$1)
                    ? '${option.$2} (already in layout)'
                    : option.$2,
                style: menuStyle,
              ),
            ),
        ],
        child: _addFieldButtonChrome(),
      ),
    );
  }

  Widget _userCaptionToolbar() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            height: 34,
            child: _buildCaptionStyleDropdown(),
          ),
          _nbaeToggle(),
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _duplicateCaptionStyle,
            child: Text(
              'Duplicate',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _ffOf(context).accent,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _selectedSavedStyleId == null
                ? null
                : _deleteSelectedCaptionStyle,
            child: Text(
              'Delete',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _selectedSavedStyleId == null
                    ? _ffOf(context).text.withValues(alpha: 0.40)
                    : FfTokens.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Nocturne structure editor (matches Caption Structure Editor.html)
  // ---------------------------------------------------------------------------

  String get _structureFormulaString {
    final raw = _liveStructureFormula ??
        StructureFormula.fromTemplate(_template, sport: _sessionSport);
    return StructureFormula.ensureCaption(
      StructureFormula.withoutLeagueTokens(raw, sport: _sessionSport),
    );
  }

  /// Whether the Structure formula includes a Country chip (needed for Getty
  /// auto-adapt: when absent, Country is shown in the State slot outside US).
  bool get _structureFormulaHasCountry {
    final f = _structureFormulaString;
    return f.contains('{${StructureFormulaKeys.country}}') ||
        f.contains('{${StructureFormulaKeys.dlCountry}}') ||
        _template.segmentOrder.contains(CaptionSegment.country);
  }

  bool get _structureEditorDirty =>
      _prefsLoaded &&
      (_structureFormulaString != _lastSavedStructureFormula ||
          _templateSnapshot() != _lastSavedTemplateSnapshot);

  void _setStructureHoverRef(StructureHoverRef? ref) {
    if (_structureHoverRef == ref) return;
    setState(() => _structureHoverRef = ref);
  }

  void _onStructureFormulaChanged(String formula) {
    if (_coreStyleLocked) return;
    final withCaption = StructureFormula.ensureCaption(formula);
    setState(() {
      _liveStructureFormula = withCaption;
      _template = StructureFormula.applyToTemplate(
        _template,
        withCaption,
        sport: _sessionSport,
      );
      _initGapControllers(_template);
    });
    widget.onDraftChanged?.call(_selectedWire, _template);
  }

  /// Cycle Month / Weekday format from Structure chip (Long / Short / …).
  void _onStructureDatePartOptionChanged(
    DateFieldKind kind,
    int occurrenceIndex,
    int optionIndex,
  ) {
    if (_coreStyleLocked) return;
    if (kind != DateFieldKind.month && kind != DateFieldKind.weekday) return;
    final current = _template.datePartTokenFor(
      kind: kind,
      occurrenceIndex: occurrenceIndex,
    );
    final next = DateFieldToken(
      kind: kind,
      optionIndex: optionIndex,
      caps: current.caps,
      enabled: current.enabled,
    );
    setState(() {
      _template = _templateWithDatePartAtOccurrence(
        _template,
        kind,
        occurrenceIndex,
        next,
      );
    });
    widget.onDraftChanged?.call(_selectedWire, _template);
    _scheduleAutosave();
  }

  List<int> _structureOptionIndexes(DateFieldKind kind) {
    var count = _template.segmentOrder
        .where((s) => switch (kind) {
              DateFieldKind.month => s == CaptionSegment.month,
              DateFieldKind.weekday => s == CaptionSegment.weekday,
              DateFieldKind.day => s == CaptionSegment.day,
              DateFieldKind.year => s == CaptionSegment.year,
            })
        .length;
    // Prefer live Structure formula counts so chip controls match what's shown.
    final live = _liveStructureFormula;
    if (live != null && live.isNotEmpty) {
      var fromFormula = 0;
      for (final node in StructureFormula.parse(live, sport: _sessionSport)) {
        if (node is! StructureVariableNode) continue;
        final fk = StructureFormulaKeys.formatKindFor(node.key);
        if (fk == kind) fromFormula++;
      }
      if (fromFormula > count) count = fromFormula;
    }
    final stored = switch (kind) {
      DateFieldKind.month => _template.monthTokensByOccurrence,
      DateFieldKind.weekday => _template.weekdayTokensByOccurrence,
      DateFieldKind.day => _template.dayTokensByOccurrence,
      DateFieldKind.year => _template.yearTokensByOccurrence,
    };
    if (stored != null && stored.length > count) count = stored.length;
    return List<int>.generate(
      count,
      (i) => _template
          .datePartTokenFor(kind: kind, occurrenceIndex: i)
          .optionIndex,
    );
  }

  IconData _sportPhosphorIcon(String sport) {
    switch (sport.toLowerCase().trim()) {
      case 'hockey':
        return PhosphorIconsRegular.hockey;
      case 'basketball':
      case 'wnba':
        return PhosphorIconsRegular.basketball;
      case 'soccer':
        return PhosphorIconsRegular.soccerBall;
      case 'football':
        return PhosphorIconsRegular.football;
      case 'baseball':
      default:
        return PhosphorIconsRegular.baseball;
    }
  }

  String _structureFormulaValue(
    String key, {
    required String sampleCaption,
    required CreditSampleAgency sampleAgency,
    int occurrenceIndex = 0,
  }) {
    final game = _structurePreviewGame;
    final venue = CaptionFormulaRenderer.venueLabel(game);
    final omitCustomInCredit =
        _template.segmentOrder.contains(CaptionSegment.customText);
    final formulaHasCountry = _structureFormulaHasCountry;
    switch (key) {
      case StructureFormulaKeys.dlCity:
      case StructureFormulaKeys.city:
        final caps = key == StructureFormulaKeys.dlCity;
        final text = CaptionFormulaRenderer.formatGeoField(
          game: game,
          options: _structurePreviewGeoOptions(caps: caps),
          kind: LocationChipKind.city,
          apStyleCaption: _template.wireStyle == WireStyle.ap,
          cpStyleCaption: _template.wireStyle == WireStyle.cp,
          // Getty only: State↔Country by territory in Structure preview.
          forceAutoAdaptUsIntl: _isGettyWire,
          formulaIncludesCountry: formulaHasCountry,
        );
        return caps ? text.toUpperCase() : text;
      case StructureFormulaKeys.dlState:
      case StructureFormulaKeys.state:
        final caps = key == StructureFormulaKeys.dlState;
        // Getty: blank State outside the US (or show Country when the formula
        // has no Country chip). AP/CP: always show State sample (abbrevs).
        final text = CaptionFormulaRenderer.formatGeoField(
          game: game,
          options: _structurePreviewGeoOptions(caps: caps),
          kind: LocationChipKind.region,
          apStyleCaption: false,
          forceAutoAdaptUsIntl: _isGettyWire,
          formulaIncludesCountry: formulaHasCountry,
        );
        if (text.isNotEmpty) {
          // When Getty substituted Country into the State slot, don't AP/CP-
          // abbreviate the country name as if it were a province.
          final swappedCountryForState = _isGettyWire &&
              !formulaHasCountry &&
              !CaptionFormulaRenderer.isUnitedStatesGame(game);
          if (!swappedCountryForState) {
            final regionRaw = game.resolvedRegionName.isNotEmpty
                ? game.resolvedRegionName
                : game.resolvedRegionShort;
            if (_template.wireStyle == WireStyle.cp) {
              final cp = abbreviateCpStyleProvince(regionRaw);
              final shown = cp.isNotEmpty ? cp : text;
              return caps ? shown.toUpperCase() : shown;
            }
            if (_template.wireStyle == WireStyle.ap) {
              final ap = abbreviateUsStateApStyle(regionRaw);
              final shown = ap.isNotEmpty ? ap : text;
              return caps ? shown.toUpperCase() : shown;
            }
          }
          return caps ? text.toUpperCase() : text;
        }
        return '';
      case StructureFormulaKeys.dlCountry:
      case StructureFormulaKeys.country:
        final caps = key == StructureFormulaKeys.dlCountry;
        final text = CaptionFormulaRenderer.formatGeoField(
          game: game,
          options: _structurePreviewGeoOptions(caps: caps),
          kind: LocationChipKind.country,
          apStyleCaption: _template.wireStyle == WireStyle.ap,
          cpStyleCaption: _template.wireStyle == WireStyle.cp,
          forceAutoAdaptUsIntl: _isGettyWire,
          formulaIncludesCountry: formulaHasCountry,
        );
        return caps ? text.toUpperCase() : text;
      case StructureFormulaKeys.dlCountryCode:
      case StructureFormulaKeys.countryCode:
        final caps = key == StructureFormulaKeys.dlCountryCode;
        final text = CaptionFormulaRenderer.formatGeoField(
          game: game,
          options: LocationLineOptions(
            uppercase: false,
            chips: [
              LocationChip(
                id: 'preview_cc',
                kind: LocationChipKind.countryCode,
                caps: caps,
              ),
            ],
            autoAdaptUsIntl: false,
          ),
          kind: LocationChipKind.countryCode,
          apStyleCaption: _template.wireStyle == WireStyle.ap,
          cpStyleCaption: _template.wireStyle == WireStyle.cp,
          forceAutoAdaptUsIntl: false,
        );
        return caps ? text.toUpperCase() : text;
      case StructureFormulaKeys.dlMonth:
      case StructureFormulaKeys.month:
        final text = CaptionFormulaRenderer.formatDatePart(
          game: _previewGameInfo,
          template: _template,
          kind: DateFieldKind.month,
          occurrenceIndex: occurrenceIndex,
        );
        return key == StructureFormulaKeys.dlMonth ? text.toUpperCase() : text;
      case StructureFormulaKeys.dlDay:
      case StructureFormulaKeys.day:
        return CaptionFormulaRenderer.formatDatePart(
          game: _previewGameInfo,
          template: _template,
          kind: DateFieldKind.day,
          occurrenceIndex: occurrenceIndex,
        );
      case StructureFormulaKeys.year:
        return CaptionFormulaRenderer.formatDatePart(
          game: _previewGameInfo,
          template: _template,
          kind: DateFieldKind.year,
          occurrenceIndex: occurrenceIndex,
        );
      case StructureFormulaKeys.dlWeekday:
      case StructureFormulaKeys.weekday:
        final text = CaptionFormulaRenderer.formatDatePart(
          game: _previewGameInfo,
          template: _template,
          kind: DateFieldKind.weekday,
          occurrenceIndex: occurrenceIndex,
        );
        return key == StructureFormulaKeys.dlWeekday
            ? text.toUpperCase()
            : text;
      case StructureFormulaKeys.caption:
        return '${_template.captionPrefix}$sampleCaption${_template.captionSuffix}';
      case StructureFormulaKeys.gameId:
        final fromWire = _gameIdByWire[_selectedWire]?.trim() ?? '';
        if (fromWire.isNotEmpty) return fromWire;
        final gid = _template.gameIdentifierText.trim();
        if (gid.isNotEmpty) return gid;
        return defaultGameIdentifierText(_sessionSport);
      case StructureFormulaKeys.location:
      case StructureFormulaKeys.venue:
        return '${_template.venuePrefix}$venue${_template.venueSuffix}';
      case StructureFormulaKeys.name:
        return CaptionFormulaRenderer.formatCreatorName(
          game: _previewGameInfo,
          bylineOptions: _template.bylineOptions,
        );
      case StructureFormulaKeys.credit:
        return CaptionFormulaRenderer.formatAgencyCredit(
          game: _previewGameInfo,
          bylineOptions: _template.bylineOptions,
          sampleAgency: sampleAgency,
        );
      case StructureFormulaKeys.byline:
        return CaptionFormulaRenderer.formatCreditLine(
          format: _template.creditFormat,
          bylineOptions: _template.bylineOptions,
          photographerName: _previewGameInfo.photographerName,
          agencyName: _previewGameInfo.agencyName,
          iptcMetadata: _previewGameInfo.iptcMetadata,
          sampleAgency: sampleAgency,
          apShortParen: _template.wireStyle == WireStyle.ap ||
              _template.wireStyle == WireStyle.cp,
          customTexts: _template.bylineOptions.customTexts,
          includeCustomInCredit: !omitCustomInCredit,
        );
      default:
        return '';
    }
  }

  Widget _nocturneTopBar() {
    final t = _ffOf(context);
    final sports = AppDefaultsFirestoreService.catalogSports;
    final sport =
        sports.contains(_sessionSport) ? _sessionSport : sports.first;
    return LayoutBuilder(
      builder: (context, constraints) {
        final veryTight = constraints.maxWidth < 920;
        // Cap flex children so they don't balloon on wide windows, but still
        // shrink under Flexible when the top bar is narrow.
        Widget capped({
          required int flex,
          required double maxWidth,
          required Widget child,
        }) {
          return Flexible(
            flex: flex,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          );
        }

        return Row(
          children: [
            // Session startup hosts the wire picker on the step title row.
            if (!_isSessionStartupEmbed)
              capped(
                flex: 3,
                maxWidth: 176,
                child: _nocturneSelectShell(
                  icon: PhosphorIconsRegular.newspaper,
                  label: _captionStyleMenuLabel(
                      _captionStyleDropdownInitialToken()),
                  child: _buildCaptionStyleDropdown(),
                  width: double.infinity,
                ),
              ),
            // Session startup already picked league/region context — hide
            // USA/International and the preview sport picker there.
            if (_isGettyWire && !_isSessionStartupEmbed) ...[
              const SizedBox(width: 6),
              _gettyPreviewToggle(),
            ],
            // Admin: each sport has its own Structure for this wire.
            // Session startup already chose the league — don't re-pick sport.
            if (!_isSessionStartupEmbed &&
                (!_isImagnWire || widget.adminMode)) ...[
              const SizedBox(width: 6),
              capped(
                flex: 3,
                maxWidth: 176,
                child: Tooltip(
                  message: widget.adminMode
                      ? 'Edit Structure for this sport within the wire style'
                      : 'Example sport for preview — sample verbs, teams, and game ID',
                  waitDuration: const Duration(milliseconds: 250),
                  child: _nocturneSelectShell(
                    icon: _sportPhosphorIcon(sport),
                    label: SportVerbCategories.displayLabel(sport),
                    width: double.infinity,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: sport,
                        isExpanded: true,
                        icon: const SizedBox.shrink(),
                        dropdownColor: t.surface,
                        style: TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.text,
                        ),
                        items: [
                          for (final id in sports)
                            DropdownMenuItem(
                              value: id,
                              child: Text(
                                SportVerbCategories.displayLabel(id),
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          _onSessionSportPicked(value);
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (widget.adminMode) ...[
              const SizedBox(width: 8),
              Container(
                width: 1,
                height: 22,
                color: t.divider,
              ),
              const SizedBox(width: 8),
              capped(
                flex: 4,
                maxWidth: 156,
                child: _nocturneTeamPicker(
                  role: 'Away',
                  value: _savedExampleAway,
                  width: double.infinity,
                  onChanged: (name) =>
                      unawaited(_setAdminExampleTeam(away: name)),
                ),
              ),
              const SizedBox(width: 6),
              capped(
                flex: 4,
                maxWidth: 156,
                child: _nocturneTeamPicker(
                  role: 'Home',
                  value: _savedExampleHome,
                  width: double.infinity,
                  onChanged: (name) =>
                      unawaited(_setAdminExampleTeam(home: name)),
                ),
              ),
            ],
            const Spacer(),
            Material(
              color: FfTokens.card,
              borderRadius: BorderRadius.circular(7),
              child: InkWell(
                onTap: _shuffleCaptionSample,
                borderRadius: BorderRadius.circular(7),
                child: Tooltip(
                  message: 'Shuffle sample',
                  child: Container(
                    height: 30,
                    padding: EdgeInsets.symmetric(
                      horizontal: veryTight ? 8 : 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      boxShadow: [
                        BoxShadow(
                          color: t.divider,
                          blurRadius: 0,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PhosphorIcon(
                          PhosphorIconsRegular.shuffle,
                          size: 14,
                          color: t.textSecondary,
                        ),
                        if (!veryTight) ...[
                          const SizedBox(width: 6),
                          Text(
                            'Shuffle sample',
                            style: TextStyle(
                              fontFamily: FfTokens.fontFamily,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1,
                              color: t.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _nocturneTeamPicker({
    required String role,
    required String? value,
    required ValueChanged<String> onChanged,
    double? width = 156,
  }) {
    final t = _ffOf(context);
    final current = value?.trim() ?? '';
    final names = List<String>.from(_adminTeamNames);
    if (current.isNotEmpty && !names.contains(current)) {
      names.insert(0, current);
    }
    final label = current.isEmpty
        ? role
        : current;
    return _nocturneSelectShell(
      width: width,
      icon: role == 'Home'
          ? PhosphorIconsRegular.house
          : PhosphorIconsRegular.airplaneTilt,
      label: _adminTeamsLoading && names.isEmpty ? 'Loading…' : label,
      child: FfDropdownButton<String>(
        value: current.isEmpty ? null : current,
        isExpanded: true,
        padding: EdgeInsets.zero,
        style: TextStyle(
          fontFamily: FfTokens.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: t.text,
        ),
        menuColor: t.surface,
        icon: const SizedBox.shrink(),
        hint: Text(
          role,
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: t.textTertiary,
          ),
        ),
        items: [
          for (final name in names)
            DropdownMenuItem<String>(
              value: name,
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: names.isEmpty
            ? null
            : (next) {
                if (next == null || next == current) return;
                onChanged(next);
              },
      ),
    );
  }

  Widget _nocturneSelectShell({
    required IconData icon,
    required String label,
    required Widget child,
    double? width = 176,
  }) {
    final t = _ffOf(context);
    return SizedBox(
      height: 30,
      width: width,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: t.sunken,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  children: [
                    PhosphorIcon(icon, size: 14, color: t.textTertiary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1,
                          color: t.text,
                        ),
                      ),
                    ),
                    PhosphorIcon(
                      PhosphorIconsRegular.caretDown,
                      size: 12,
                      color: t.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Opacity(opacity: 0.01, child: child),
          ),
        ],
      ),
    );
  }

  Widget _nocturnePreviewPanel({
    required String sampleCaption,
    required CreditSampleAgency sampleAgency,
  }) {
    final t = _ffOf(context);
    final embed = _isSessionStartupEmbed;
    final nodes = StructureFormula.parse(
      _structureFormulaString,
      sport: _sessionSport,
    );
    // Match StructureFormulaField body text (fontSize 16).
    const fontSize = 16.0;
    const lineHeight = 22.0;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        embed ? 10 : 16,
        embed ? 6 : 14,
        embed ? 10 : 16,
        embed ? 6 : 14,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(embed ? 9 : 12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!embed)
            Row(
              children: [
                Text(
                  'PREVIEW',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.1,
                    color: t.textTertiary,
                  ),
                ),
                const Spacer(),
                Material(
                  color: _structurePreviewColorCode
                      ? t.sunken
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _structurePreviewColorCode =
                            !_structurePreviewColorCode;
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _structurePreviewColorCode
                              ? t.accent.withValues(alpha: 0.85)
                              : t.text.withValues(alpha: 0.16),
                          width: _structurePreviewColorCode ? 1 : 0.5,
                        ),
                      ),
                      child: Text(
                        'Colour code',
                        style: TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: 11,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          color: _structurePreviewColorCode
                              ? t.text
                              : t.text.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          if (!embed) const SizedBox(height: 8),
          Builder(
            builder: (context) {
              // Resolve values, then emit with pending geo-glue so empty
              // City/State/Country don't leave orphan commas
              // (Getty: TORONTO, CANADA - … / Imagn: Toronto, Canada; …).
              final spans = <InlineSpan>[];
              String? pendingGlue;
              var slot = 0;
              var monthOcc = 0;
              var dayOcc = 0;
              var yearOcc = 0;
              var weekdayOcc = 0;
              final colorCode = _structurePreviewColorCode;

              void flushGlue() {
                final g = pendingGlue;
                pendingGlue = null;
                if (g != null && g.isNotEmpty) {
                  spans.add(TextSpan(text: g));
                }
              }

              for (final node in nodes) {
                switch (node) {
                  case StructureLiteralNode(:final text):
                    if (_holdsEmptyStructureGeoGlue &&
                        _isStructureGeoGlue(text)) {
                      pendingGlue = text;
                    } else {
                      flushGlue();
                      spans.add(TextSpan(text: text));
                    }
                  case StructureVariableNode(:final key):
                    final ref = StructureHoverRef(slot, key: key);
                    slot++;
                    var dateOcc = 0;
                    if (StructureFormulaKeys.isMonth(key)) {
                      dateOcc = monthOcc++;
                    } else if (key == StructureFormulaKeys.day ||
                        key == StructureFormulaKeys.dlDay) {
                      dateOcc = dayOcc++;
                    } else if (key == StructureFormulaKeys.year) {
                      dateOcc = yearOcc++;
                    } else if (StructureFormulaKeys.isWeekday(key)) {
                      dateOcc = weekdayOcc++;
                    }
                    final value = _structureFormulaValue(
                      key,
                      sampleCaption: sampleCaption,
                      sampleAgency: sampleAgency,
                      occurrenceIndex: dateOcc,
                    );
                    if (value.isEmpty) {
                      // Hold glue across empty State/Country (Getty + Imagn).
                      continue;
                    }
                    flushGlue();
                    final hot = _structureHoverRef?.slot == ref.slot;
                    final isCaption =
                        StructureFormulaKeys.isCaption(key);
                    // Off: plain white. On: Structure-chip colours
                    // (orange caption, teal wash on other slots).
                    final Color labelColor;
                    final Color? labelBg;
                    if (!colorCode) {
                      labelColor = t.text;
                      labelBg = hot ? FfTokens.sessionHot : null;
                    } else if (isCaption) {
                      labelColor = FfTokens.accent2;
                      labelBg = hot
                          ? FfTokens.accent2.withValues(alpha: 0.28)
                          : FfTokens.accent2.withValues(alpha: 0.16);
                    } else {
                      labelColor = FfTokens.accentHover;
                      labelBg = hot
                          ? FfTokens.nocturneAccentDeep
                          : FfTokens.sessionHot;
                    }
                    // Keep leading/trailing spaces outside the highlight so
                    // you can see whether a variable ends with a space.
                    final coreStart =
                        value.length - value.trimLeft().length;
                    final coreEnd = value.trimRight().length;
                    final leading = value.substring(0, coreStart);
                    final core = value.substring(coreStart, coreEnd);
                    final trailing = value.substring(coreEnd);
                    if (leading.isNotEmpty) {
                      spans.add(TextSpan(text: leading));
                    }
                    if (core.isNotEmpty) {
                      spans.add(
                        TextSpan(
                          text: core,
                          style: TextStyle(
                            color: labelColor,
                            backgroundColor: labelBg,
                            fontWeight:
                                colorCode ? FontWeight.w600 : null,
                          ),
                          onEnter: (_) => _setStructureHoverRef(ref),
                          onExit: (_) => _setStructureHoverRef(null),
                        ),
                      );
                    }
                    if (trailing.isNotEmpty) {
                      spans.add(TextSpan(text: trailing));
                    }
                }
              }
              flushGlue();
              final preview = Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: fontSize,
                    height: lineHeight / fontSize,
                    color: t.text,
                  ),
                  children: spans,
                ),
              );
              // New session: taller preview so the full caption is readable;
              // Structure + Player Output still take the remaining height.
              if (!embed) return preview;
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 128),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(scrollbars: false),
                  child: SingleChildScrollView(child: preview),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _nocturneTwoOptionSwitch({
    required List<(String, VoidCallback, bool)> options,
    bool expand = false,
    bool ignoreCoreLock = false,
    bool compact = false,
  }) {
    final t = _ffOf(context);
    Widget segment((String, VoidCallback, bool) o) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (!ignoreCoreLock && _coreStyleLocked) ? null : o.$2,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: compact ? 24 : 26,
            constraints: BoxConstraints(minWidth: compact ? 32 : 44),
            padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: o.$3 ? t.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: o.$3
                  ? Border.all(color: t.accentEdge)
                  : Border.all(color: Colors.transparent),
            ),
            child: Text(
              o.$1,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
                height: 1,
                color: o.$3 ? t.text : t.textTertiary,
              ),
            ),
          ),
        ),
      );
    }

    final row = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        for (final o in options)
          if (expand)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: segment(o),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: segment(o),
            ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: row,
    );
  }

  /// New-session Player Output row: label left, segmented control right (HTML `.or`).
  Widget _nocturnePlayerOutputOptionRow({
    required String label,
    required List<(String, VoidCallback, bool)> options,
  }) {
    final t = _ffOf(context);
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: t.textSecondary,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 128,
            child: _nocturneTwoOptionSwitch(
              options: options,
              compact: true,
              expand: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _nocturneOptionRow({
    required String label,
    required Widget control,
    VoidCallback? onTap,
    bool compact = false,
  }) {
    final t = _ffOf(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        hoverColor: t.text.withValues(alpha: 0.03),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: compact ? 28 : 34),
          child: Padding(
            padding: EdgeInsets.fromLTRB(compact ? 6 : 10, 0, compact ? 4 : 6, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: compact ? 11 : 13,
                      fontWeight: FontWeight.w500,
                      color: t.textSecondary,
                    ),
                  ),
                ),
                SizedBox(width: compact ? 6 : 12),
                control,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _nocturneOnOffSwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final t = _ffOf(context);
    return GestureDetector(
      onTap: _coreStyleLocked ? null : () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 34,
        height: 20,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? t.accent : t.hover,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: value ? Colors.white : t.textSecondary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _nocturneOptionGroup({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: FfTokens.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _nocturnePlayerSample(
    String playerPreviewText, {
    bool compact = false,
    bool inline = false,
  }) {
    final t = _ffOf(context);
    final baseStyle = TextStyle(
      fontFamily: FfTokens.fontFamily,
      fontSize: compact ? (inline ? 12.0 : 14.0) : 13,
      fontWeight: FontWeight.w600,
      height: compact ? (inline ? 1.25 : 20 / 14) : 18 / 13,
      color: t.text,
    );
    final maxLines = inline ? 2 : (compact ? 3 : 4);
    // Spelling changes the position label; flash that segment.
    final flash = _playerOutputFlashKey == 'eng' ? 'pos' : _playerOutputFlashKey;
    Widget body = Text(
      playerPreviewText,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: baseStyle,
    );
    if (compact && flash != null) {
      final realPlayers = _realPreviewPlayers();
      final canSegment = realPlayers == null || realPlayers.isNotEmpty;
      if (canSegment) {
        final parts = CaptionFormulaRenderer.randomSinglePlayerPreviewParts(
          _template,
          seed: _captionSampleSeed,
          previewPlayers: realPlayers,
          sport: _sessionSport,
        );
        if (parts.map((e) => e.$2).join() == playerPreviewText) {
          final tint = t.accent.withValues(alpha: 0.22);
          body = Text.rich(
            TextSpan(
              style: baseStyle,
              children: [
                for (final part in parts)
                  if (part.$1 != null &&
                      part.$1 == flash &&
                      part.$2.trim().isNotEmpty)
                    TextSpan(
                      text: part.$2,
                      style: baseStyle.copyWith(
                        background: Paint()..color = tint,
                      ),
                    )
                  else
                    TextSpan(text: part.$2),
              ],
            ),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          );
        }
      }
    }
    return Container(
      width: inline ? null : double.infinity,
      padding: inline
          ? const EdgeInsets.fromLTRB(8, 5, 8, 5)
          : const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
      ),
      child: body,
    );
  }

  /// Player-output toggles refresh the sample; Save as default persists them.
  void _commitPlayerOutputTemplate(
    CaptionTemplate next, {
    String? flashKey,
  }) {
    setState(() {
      _template = next;
      if (flashKey != null) {
        _playerOutputFlashKey = flashKey;
        _playerOutputFlashTimer?.cancel();
        _playerOutputFlashTimer = Timer(const Duration(milliseconds: 900), () {
          if (!mounted) return;
          setState(() => _playerOutputFlashKey = null);
        });
      }
    });
    widget.onDraftChanged?.call(_selectedWire, _template);
  }

  List<(String, List<(String, VoidCallback, bool)>)> _playerOutputToggleSpecs({
    required bool compact,
  }) {
    final gettyLocked = _selectedWire == WireStyle.getty ||
        _selectedWire == WireStyle.gettyInternational;
    final includePos = gettyLocked ? false : _template.includePlayerPosition;
    final teamBefore =
        _template.captionTeamOrder == CaptionTeamOrder.teamBefore;
    return [
      (
        'Team',
        [
          (
            compact ? 'Before' : 'Before name',
            () => _commitPlayerOutputTemplate(
                  _template.copyWith(
                      captionTeamOrder: CaptionTeamOrder.teamBefore),
                  flashKey: 'team',
                ),
            teamBefore,
          ),
          (
            compact ? 'After' : 'After name',
            () => _commitPlayerOutputTemplate(
                  // "of the Team" — possessive only applies with Before.
                  _template.copyWith(
                    captionTeamOrder: CaptionTeamOrder.teamAfter,
                    useTeamPossessive: false,
                  ),
                  flashKey: 'team',
                ),
            !teamBefore,
          ),
        ],
      ),
      // Beside Team when Before is on (Number / Spelling shift down a row).
      if (teamBefore)
        (
          'Possessive',
          [
            (
              "Team's",
              () => _commitPlayerOutputTemplate(
                    _template.copyWith(useTeamPossessive: true),
                    flashKey: 'poss',
                  ),
              _template.useTeamPossessive ?? false,
            ),
            (
              'Off',
              () => _commitPlayerOutputTemplate(
                    _template.copyWith(useTeamPossessive: false),
                    flashKey: 'poss',
                  ),
              !(_template.useTeamPossessive ?? false),
            ),
          ],
        ),
      (
        'Number',
        [
          (
            '#99',
            () => _commitPlayerOutputTemplate(
                  _template.copyWith(numberFormat: NumberFormatStyle.hash),
                  flashKey: 'num',
                ),
            _template.numberFormat == NumberFormatStyle.hash,
          ),
          (
            '(99)',
            () => _commitPlayerOutputTemplate(
                  _template.copyWith(numberFormat: NumberFormatStyle.parens),
                  flashKey: 'num',
                ),
            _template.numberFormat == NumberFormatStyle.parens,
          ),
        ],
      ),
      (
        'Position',
        [
          (
            'On',
            () {
              if (gettyLocked || _coreStyleLocked) return;
              _commitPlayerOutputTemplate(
                _template.copyWith(includePlayerPosition: true),
                flashKey: 'pos',
              );
            },
            includePos,
          ),
          (
            'Off',
            () {
              if (gettyLocked || _coreStyleLocked) return;
              _commitPlayerOutputTemplate(
                _template.copyWith(includePlayerPosition: false),
                flashKey: 'pos',
              );
            },
            !includePos,
          ),
        ],
      ),
      (
        'Spelling',
        [
          (
            compact ? 'US' : 'American',
            () => _commitPlayerOutputTemplate(
                  _template.copyWith(americanEnglish: true),
                  flashKey: 'eng',
                ),
            _template.americanEnglish,
          ),
          (
            compact ? 'Intl' : 'International',
            () => _commitPlayerOutputTemplate(
                  _template.copyWith(americanEnglish: false),
                  flashKey: 'eng',
                ),
            !_template.americanEnglish,
          ),
        ],
      ),
      (
        'Accents',
        [
          (
            'Keep',
            () => _commitPlayerOutputTemplate(
                  _template.copyWith(removeDiacritics: false),
                  flashKey: 'dia',
                ),
            !_template.removeDiacritics,
          ),
          (
            'Remove',
            () => _commitPlayerOutputTemplate(
                  _template.copyWith(removeDiacritics: true),
                  flashKey: 'dia',
                ),
            _template.removeDiacritics,
          ),
        ],
      ),
    ];
  }

  List<Widget> _nocturnePlayerOutputOptionGroups({bool compact = false}) {
    final gap = compact ? 2.0 : 6.0;
    final specs = _playerOutputToggleSpecs(compact: compact);
    if (compact) {
      // 2-col rows. When Team is Before, "Team's" sits beside Team so
      // Number / Spelling each shift down one row.
      final rows = <Widget>[];
      for (var i = 0; i < specs.length; i += 2) {
        if (i > 0) rows.add(SizedBox(height: gap));
        final a = specs[i];
        final b = i + 1 < specs.length ? specs[i + 1] : null;
        rows.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _nocturnePlayerOutputOptionRow(
                  label: a.$1,
                  options: a.$2,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: b == null
                    ? const SizedBox.shrink()
                    : _nocturnePlayerOutputOptionRow(
                        label: b.$1,
                        options: b.$2,
                      ),
              ),
            ],
          ),
        );
      }
      return rows;
    }
    return [
      _nocturneOptionGroup(
        children: [
          for (final spec in specs.take(4))
            _nocturneOptionRow(
              label: spec.$1,
              control: _nocturneTwoOptionSwitch(options: spec.$2),
            ),
        ],
      ),
      SizedBox(height: gap),
      _nocturneOptionGroup(
        children: [
          for (final spec in specs.skip(4))
            _nocturneOptionRow(
              label: spec.$1,
              control: _nocturneTwoOptionSwitch(options: spec.$2),
            ),
        ],
      ),
      SizedBox(height: gap),
      _nocturneOptionGroup(
        children: [
          _nocturneOptionRow(
            label: 'Write to IPTC Personality',
            onTap: _coreStyleLocked
                ? null
                : () => unawaited(_setShowPersonalityField(
                    !_template.showPersonalityField)),
            control: IgnorePointer(
              child: _nocturneOnOffSwitch(
                value: _template.showPersonalityField,
                onChanged: (_) {},
              ),
            ),
          ),
          _nocturneOptionRow(
            label: 'Write to IPTC Keywords',
            onTap: _coreStyleLocked
                ? null
                : () => unawaited(
                    _setShowKeywordsField(!_template.showKeywordsField)),
            control: IgnorePointer(
              child: _nocturneOnOffSwitch(
                value: _template.showKeywordsField,
                onChanged: (_) {},
              ),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _nocturnePlayerOutputPanel(
    String playerPreviewText, {
    bool compact = false,
  }) {
    final t = _ffOf(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 14,
        compact ? 10 : 12,
        compact ? 10 : 14,
        compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(compact ? 0 : 14),
          right: Radius.circular(compact ? 10 : 14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'PLAYER OUTPUT',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  color: t.textTertiary,
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: _nocturnePlayerSample(
                  playerPreviewText,
                  compact: compact,
                  inline: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _nocturnePlayerOutputOptionGroups(
                  compact: compact,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nocturneStructureAddPalette() {
    return StructureFormulaPalette(
      compactPopup: _isSessionStartupEmbed,
      onPointerDown: () {
        _structureFormulaFieldKey.currentState?.keepFocus();
      },
      onInsert: (key) {
        _structureFormulaFieldKey.currentState?.insertKey(key);
      },
    );
  }

  Widget _nocturneStructureFormulaField({bool expands = false}) {
    return StructureFormulaField(
      key: _structureFormulaFieldKey,
      formula: _structureFormulaString,
      hoverRef: _structureHoverRef,
      onHoverRef: _setStructureHoverRef,
      enabled: !_coreStyleLocked,
      expands: expands,
      onChanged: _onStructureFormulaChanged,
      onChipTap: _onStructureChipTap,
      monthOptionByOccurrence: _structureOptionIndexes(DateFieldKind.month),
      weekdayOptionByOccurrence:
          _structureOptionIndexes(DateFieldKind.weekday),
      onDatePartOptionChanged: _onStructureDatePartOptionChanged,
    );
  }

  void _onStructureChipTap(String key) {
    if (_isSessionStartupEmbed && widget.onSessionStructureChipTap != null) {
      final panel = StructureFormulaKeys.iptcPanelKey(key);
      // Caption / Camera time are not editable rows in the 4-quadrant editor.
      final focus = (panel != null &&
              panel != 'Caption' &&
              panel != 'Camera time')
          ? panel
          : null;
      widget.onSessionStructureChipTap!(focus);
      return;
    }
    unawaited(
      showStructureIptcSourceDialog(
        context,
        structureKey: key,
        wire: _selectedWire,
        game: _previewGameInfo,
      ),
    );
  }

  Widget _nocturneStructurePanel() {
    final t = _ffOf(context);
    final embed = _isSessionStartupEmbed;
    return Container(
      padding: EdgeInsets.fromLTRB(
        embed ? 6 : 12,
        embed ? 4 : 10,
        embed ? 6 : 12,
        embed ? 4 : 10,
      ),
      decoration: BoxDecoration(
        color: t.surface,
        // Flush against Player Output — square the shared edge when embedded.
        borderRadius: embed
            ? const BorderRadius.horizontal(
                left: Radius.circular(9),
                right: Radius.circular(0),
              )
            : BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'STRUCTURE',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  color: t.textTertiary,
                ),
              ),
              if (!embed) ...[
                const SizedBox(width: 8),
                Text(
                  'One master per wire',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: FfTokens.accentHover,
                  ),
                ),
                const Spacer(),
                Text(
                  'Type freely · pieces insert at the cursor',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 10,
                    color: t.textTertiary,
                  ),
                ),
              ] else ...[
                // Keep + visible above the fold — chips scroll underneath.
                const Spacer(),
                _nocturneStructureAddPalette(),
              ],
            ],
          ),
          SizedBox(height: embed ? 3 : 6),
          Expanded(
            child: embed
                ? _nocturneStructureFormulaField(expands: true)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _nocturneStructureFormulaField(),
                              const SizedBox(height: 8),
                              _nocturneStructureAddPalette(),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveStructureAsDefault() async {
    if (!_structureEditorDirty) return;
    try {
      if (widget.adminMode && widget.onAdminSaveAsDefault != null) {
        // Confirm + flush live inside the host publish so cancel does not
        // clear the dirty state / mark the current draft as saved.
        final published = await widget.onAdminSaveAsDefault!();
        if (!mounted || !published) return;
        setState(() {
          _liveStructureFormula = null;
          _markStructureSaved();
        });
        return;
      }
      await _persistCaptionLayoutToPreferences(
        syncBuiltInWireDefault: _selectedSavedStyleId == null,
        allowSkipIfUnchanged: false,
      );
      if (!mounted) return;
      setState(() {
        _liveStructureFormula = null;
        _markStructureSaved();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  void _discardStructureEdits() {
    if (!_structureEditorDirty) return;
    if (widget.adminMode && widget.onAdminDiscard != null) {
      widget.onAdminDiscard!();
      return;
    }
    if (_lastSavedTemplateSnapshot.isEmpty) return;
    try {
      final map =
          jsonDecode(_lastSavedTemplateSnapshot) as Map<String, dynamic>;
      final restored = CaptionTemplate.fromJson(map);
      setState(() {
        _template = restored;
        _selectedWire = restored.wireStyle;
        _structureHoverRef = null;
        _liveStructureFormula = null;
        _initGapControllers(_template);
        _markStructureSaved();
      });
      widget.onDraftChanged?.call(_selectedWire, _template);
    } catch (_) {}
  }

  Widget _nocturneStructureFooter() {
    final t = _ffOf(context);
    final dirty = _structureEditorDirty;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface,
          border: Border(top: BorderSide(color: t.divider)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (dirty) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: FfTokens.accent2,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Unsaved changes',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    color: t.textSecondary,
                  ),
                ),
              ] else ...[
                PhosphorIcon(
                  PhosphorIconsFill.checkCircle,
                  size: 14,
                  color: FfTokens.sessionOk,
                ),
                const SizedBox(width: 8),
                Text(
                  'Saved as default',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    color: t.textSecondary,
                  ),
                ),
              ],
              const Spacer(),
              TextButton(
                onPressed: dirty ? _discardStructureEdits : null,
                style: TextButton.styleFrom(
                  foregroundColor: t.textSecondary,
                  disabledForegroundColor:
                      t.textSecondary.withValues(alpha: 0.35),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                child: const Text(
                  'Discard',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              Opacity(
                opacity: dirty ? 1 : 0.35,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF243848),
                        Color(0xFF15242E),
                        Color(0xFF0E181F),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: t.accent.withValues(alpha: 0.95),
                        blurRadius: 0,
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: t.accent.withValues(alpha: 0.22),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: dirty
                          ? () => unawaited(_saveStructureAsDefault())
                          : null,
                      borderRadius: BorderRadius.circular(7),
                      child: const SizedBox(
                        height: 30,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Center(
                            child: Text(
                              'Save as default',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNocturneStructureEditor({
    required String sampleCaption,
    required CreditSampleAgency sampleAgency,
    required String playerPreviewText,
  }) {
    final embed = _isSessionStartupEmbed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              embed ? 4 : 12,
              embed ? 2 : 12,
              embed ? 4 : 12,
              embed ? 2 : 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // New session hosts wire + shuffle on the step title row.
                if (!embed) ...[
                  _nocturneTopBar(),
                  const SizedBox(height: 10),
                ],
                _nocturnePreviewPanel(
                  sampleCaption: sampleCaption,
                  sampleAgency: sampleAgency,
                ),
                SizedBox(height: embed ? 4 : 10),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Structure fills all leftover width; Player Output is a
                      // fixed column so no dead gap between the boxes.
                      Expanded(child: _nocturneStructurePanel()),
                      SizedBox(
                        width: embed ? 400 : 440,
                        child: _nocturnePlayerOutputPanel(
                          playerPreviewText,
                          compact: embed,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Session startup embeds this editor live — no prefs Save/Discard bar.
        if (!embed) _nocturneStructureFooter(),
      ],
    );
  }

  bool get _nbaeNoteApplies => GettyNoteVariant.applies(
        enabled: _gettyNoteIsNbae,
        wire: _selectedWire,
        sport: _sessionSport,
      );

  bool get _showsNbaeToggle =>
      _selectedSavedStyleId == null &&
      (_selectedWire == WireStyle.getty ||
          _selectedWire == WireStyle.gettyInternational) &&
      _sessionSport.trim().toLowerCase() == 'basketball';

  void _setNbaeNote(bool on) {
    if (_gettyNoteIsNbae == on) return;
    setState(() {
      _gettyNoteIsNbae = on;
      _template = GettyNoteVariant.applyToTemplate(
        _template,
        nbae: GettyNoteVariant.applies(
          enabled: on,
          wire: _selectedWire,
          sport: _sessionSport,
        ),
        insertIfMissing: on,
      );
      _initGapControllers(_template);
    });
    unawaited(
      PreferencesService.getInstance().then(
        (prefs) => prefs.saveGettyNoteIsNbae(on),
      ),
    );
  }

  Widget _nbaeToggle() {
    if (!_showsNbaeToggle) return const SizedBox.shrink();
    final t = _ffOf(context);
    final on = _gettyNoteIsNbae;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'NBAE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: on ? t.accent : t.text.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 40,
            height: 24,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Switch(
                value: on,
                onChanged: _setNbaeNote,
                activeTrackColor: t.accent,
                activeThumbColor: Colors.white,
                inactiveTrackColor: t.sunken,
                inactiveThumbColor: Colors.white,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _adminCaptionToolbar() {
    final t = _ffOf(context);
    final sports = AppDefaultsFirestoreService.catalogSports;
    Widget menuBox({required double width, required Widget child}) {
      return SizedBox(
        width: width,
        height: 34,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.sunken,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.divider),
          ),
          child: child,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 148,
            height: 34,
            child: _buildCaptionStyleDropdown(),
          ),
          const SizedBox(width: 8),
          menuBox(
            width: 132,
            child: FfDropdownButton<String>(
              value: sports.contains(_sessionSport) ? _sessionSport : sports.first,
              isExpanded: true,
              menuColor: t.surface,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              style: t.metaStyle.copyWith(color: t.text),
              items: [
                for (final sport in sports)
                  DropdownMenuItem(
                    value: sport,
                    child: Text(SportVerbCategories.displayLabel(sport)),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                _onSessionSportPicked(value);
              },
            ),
          ),
          _nbaeToggle(),
          const SizedBox(width: 4),
          Tooltip(
            message: widget.adminMode
                ? 'Each sport has its own Structure for this wire. '
                    'Switch sport to edit that sport’s caption layout.'
                : 'Sport changes preview sample, teams, verbs, and game ID.',
            waitDuration: const Duration(milliseconds: 300),
            child: PhosphorIcon(
              PhosphorIconsRegular.info,
              size: 16,
              color: t.text.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle get _panelTitleStyle => FfTokens.panelLabel(
        color: _t.textTertiary,
      ).copyWith(
        fontSize: 10,
        letterSpacing: 1.15,
        fontWeight: FontWeight.w600,
      );

  /// Same label treatment as the verb editor titles (Category, Verb).
  TextStyle get _sectionTitleStyle => TextStyle(
        fontFamily: FfTokens.labelFamily,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        height: 1.2,
        color: _t.text.withValues(alpha: 0.72),
      );

  /// Same as "Show Personality Field" / layout option rows (Player Output choices use this too).
  TextStyle get _layoutOptionTextStyle => _t.microStyle.copyWith(
        fontSize: 11,
        color: _t.text.withValues(alpha: 0.82),
      );

  CaptionSegment? _activePreviewSegment() {
    if (_customTextSnippetEditorOpen) return CaptionSegment.customText;
    if (_freeTextSnippetEditorOpen) return CaptionSegment.freeText;
    if (_singleCustomNarrativeInlineEligible) {
      final idx = _activeFormulaIndex;
      if (idx != null &&
          idx >= 0 &&
          idx < _template.segmentOrder.length &&
          _template.segmentOrder[idx] == CaptionSegment.customText) {
        return CaptionSegment.customText;
      }
    }
    if (_separatorSnippetEditorOpen) return CaptionSegment.separator;
    if (_punctuationSnippetEditorOpen) return CaptionSegment.punctuation;
    if (_focusedGlueSegmentIndex != null &&
        _focusedGlueSegmentIndex! >= 0 &&
        _focusedGlueSegmentIndex! < _template.segmentOrder.length) {
      return _template.segmentOrder[_focusedGlueSegmentIndex!];
    }
    if (_locationEditorOpen) {
      final idx = _activeFormulaIndex;
      if (idx != null &&
          idx >= 0 &&
          idx < _template.segmentOrder.length &&
          _isGeoFieldSegment(_template.segmentOrder[idx])) {
        return _template.segmentOrder[idx];
      }
      return CaptionSegment.city;
    }
    if (_dateEditorOpen) {
      final idx = _activeFormulaIndex;
      if (idx != null &&
          idx >= 0 &&
          idx < _template.segmentOrder.length &&
          (_isDatePartSegment(_template.segmentOrder[idx]) ||
              _template.segmentOrder[idx] == CaptionSegment.date)) {
        return _template.segmentOrder[idx];
      }
      return CaptionSegment.month;
    }
    if (_captionPreviewSelected) return CaptionSegment.caption;
    if (_venuePreviewSelected) return CaptionSegment.venue;
    if (_bylinePreviewSelected) {
      final idx = _activeFormulaIndex;
      if (idx != null && idx >= 0 && idx < _template.segmentOrder.length) {
        return _template.segmentOrder[idx];
      }
      return CaptionSegment.credit;
    }
    return null;
  }

  /// Fixed slate fill for formula preview snippets — same in every state so
  /// chips don't flash selectedFill / faded sunken while editing.
  /// Field chips in the structure row.
  static const Color _snippetFill = FfTokens.nocturneSunken;

  /// Punctuation and separator inputs. Same sunken fill as the field chips.

  /// Shared height for snippet chips and glue gaps so they sit on one baseline.
  static const double _snippetChipHeight = 16;
  static const double _structurePatternFontSize = 13;
  static const TextStyle _structurePatternTextStyle = TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: _structurePatternFontSize,
    fontWeight: FontWeight.w400,
    height: 1.0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const StrutStyle _structurePatternStrut = StrutStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: _structurePatternFontSize,
    height: 1.0,
    forceStrutHeight: true,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Preview chips + player sample share [_snippetFill] with light body text.
  _SegmentTint get _segmentTint => const _SegmentTint(
        bg: _snippetFill,
        fg: Color(0xFFE4EAF2),
      );

  Widget _buildPreviewStructure({
    required String sampleCaption,
    required CreditSampleAgency sampleAgency,
    required double maxTextWidth,
  }) {
    final active = _activePreviewSegment();
    final activeIndex = _activeFormulaIndex;
    final focusedGap = _focusedGapIndex;
    final dimNonActive = active != null ||
        activeIndex != null ||
        focusedGap != null ||
        _focusedGlueSegmentIndex != null;

    final venue = CaptionFormulaRenderer.venueLabel(_previewGameInfo);
    final omitCustomInCredit =
        _template.segmentOrder.contains(CaptionSegment.customText);
    final credit = CaptionFormulaRenderer.formatCreditLine(
      format: _template.creditFormat,
      bylineOptions: _template.bylineOptions,
      photographerName: _previewGameInfo.photographerName,
      agencyName: _previewGameInfo.agencyName,
      iptcMetadata: _previewGameInfo.iptcMetadata,
      sampleAgency: sampleAgency,
      apShortParen: _template.wireStyle == WireStyle.ap || _template.wireStyle == WireStyle.cp,
      customTexts: _template.bylineOptions.customTexts,
      includeCustomInCredit: !omitCustomInCredit,
    );

    String valueAt(int segmentIndex, List<CaptionSegment> order) {
      final s = order[segmentIndex];
      switch (s) {
        case CaptionSegment.location:
          final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
              order, segmentIndex, CaptionSegment.location);
          final locOpts =
              CaptionFormulaRenderer.locationLineOptionsForOccurrence(
                  _template, occ);
          final gettyWire = _template.wireStyle == WireStyle.getty ||
              _template.wireStyle == WireStyle.gettyInternational;
          return CaptionFormulaRenderer.formatLocationLine(
            _captionPreviewGame,
            locOpts,
            apStyleCaption: _template.wireStyle == WireStyle.ap,
          cpStyleCaption: _template.wireStyle == WireStyle.cp,
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
          final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
              order, segmentIndex, s);
          final locOpts =
              CaptionFormulaRenderer.locationLineOptionsForOccurrence(
                  _template, occ);
          return CaptionFormulaRenderer.formatGeoField(
            game: _captionPreviewGame,
            options: locOpts,
            kind: kind,
            apStyleCaption: _template.wireStyle == WireStyle.ap,
          cpStyleCaption: _template.wireStyle == WireStyle.cp,
            forceAutoAdaptUsIntl: _template.wireStyle == WireStyle.getty ||
                _template.wireStyle == WireStyle.gettyInternational,
            formulaIncludesCountry:
                order.contains(CaptionSegment.country),
          );
        case CaptionSegment.date:
          final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
              order, segmentIndex, CaptionSegment.date);
          final f =
              CaptionFormulaRenderer.dateFormulaForOccurrence(_template, occ);
          return CaptionFormulaRenderer.formatTemplateDateLine(
            _previewGameInfo,
            _template,
            uppercaseAll: _template.wireStyle == WireStyle.getty ||
                _template.wireStyle == WireStyle.gettyInternational,
            dateFormulaOverride: f,
          );
        case CaptionSegment.month:
        case CaptionSegment.day:
        case CaptionSegment.year:
        case CaptionSegment.weekday:
          final kind = CaptionFormulaRenderer.dateFieldKindForSegment(s)!;
          final occ = CaptionFormulaRenderer.segmentOccurrenceIndex(
              order, segmentIndex, s);
          return CaptionFormulaRenderer.formatDatePart(
            game: _previewGameInfo,
            template: _template,
            kind: kind,
            occurrenceIndex: occ,
          );
        case CaptionSegment.caption:
          return '${_template.captionPrefix}'
              '$sampleCaption'
              '${_template.captionSuffix}';
        case CaptionSegment.customText:
          return '${_template.gameIdentifierPrefix}'
              '${_template.gameIdentifierText.trim()}'
              '${_template.gameIdentifierSuffix}';
        case CaptionSegment.freeText:
          return CaptionFormulaRenderer.freeTextSnippetFor(
              _template, segmentIndex);
        case CaptionSegment.venue:
          return '${_template.venuePrefix}$venue${_template.venueSuffix}';
        case CaptionSegment.creator:
          return CaptionFormulaRenderer.formatCreatorName(
            game: _previewGameInfo,
            bylineOptions: _template.bylineOptions,
          );
        case CaptionSegment.agency:
          return CaptionFormulaRenderer.formatAgencyCredit(
            game: _previewGameInfo,
            bylineOptions: _template.bylineOptions,
            sampleAgency: sampleAgency,
          );
        case CaptionSegment.credit:
          return credit;
        case CaptionSegment.separator:
          return _normalizeSep(CaptionFormulaRenderer.separatorSnippetFor(
              _template, segmentIndex));
        case CaptionSegment.punctuation:
          return _normalizeSep(CaptionFormulaRenderer.punctuationSnippetFor(
              _template, segmentIndex));
      }
    }

    _PreviewSegmentState stateFor(int i, CaptionSegment seg) {
      if (_focusedGlueSegmentIndex != null) {
        return _focusedGlueSegmentIndex == i && _isStructureTextField(seg)
            ? _PreviewSegmentState.active
            : _PreviewSegmentState.dim;
      }
      if (focusedGap != null) return _PreviewSegmentState.dim;
      if (activeIndex != null) {
        return activeIndex == i
            ? _PreviewSegmentState.active
            : _PreviewSegmentState.dim;
      }
      if (active == seg) return _PreviewSegmentState.active;
      if (dimNonActive) return _PreviewSegmentState.dim;
      return _PreviewSegmentState.tinted;
    }

    final order = _template.segmentOrder;
    if (order.isEmpty) return const SizedBox.shrink();
    _scheduleSeparatorEnsure();
    final n = order.length;

    Widget glueBox(int index, {required bool ownRow}) {
      final controller = _glueSnippetControllers[index];
      final focus = _glueFocusNodes[index];
      if (controller == null || focus == null) return const SizedBox.shrink();
      final glueActive = _focusedGlueSegmentIndex == index;
      final glueDim = dimNonActive && !glueActive;
      return Tooltip(
        message: _glueFieldTooltip(index),
        waitDuration: const Duration(milliseconds: 400),
        child: Opacity(
          opacity: glueDim ? 0.45 : 1.0,
          child: _GapSeparatorField(
            controller: controller,
            focusNode: focus,
            maxWidth: maxTextWidth,
            forceFullWidth: ownRow,
            active: glueActive,
            onFocusChanged: (focused) =>
                _onGlueSnippetFocusChanged(index, focused),
          ),
        ),
      );
    }

    Widget prefixBox() {
      return Tooltip(
        message: 'Text before the first block',
        waitDuration: const Duration(milliseconds: 400),
        child: _GapSeparatorField(
          controller: _layoutPrefixCtrl,
          focusNode: _layoutPrefixFocus,
          maxWidth: maxTextWidth,
          active: _layoutPrefixFocused,
          onFocusChanged: (focused) =>
              _onLayoutEdgeFocusChanged(prefix: true, focused: focused),
        ),
      );
    }

    Widget suffixBox() {
      return Tooltip(
        message: 'Text after the last block',
        waitDuration: const Duration(milliseconds: 400),
        child: _GapSeparatorField(
          controller: _layoutSuffixCtrl,
          focusNode: _layoutSuffixFocus,
          maxWidth: maxTextWidth,
          active: _layoutSuffixFocused,
          onFocusChanged: (focused) =>
              _onLayoutEdgeFocusChanged(prefix: false, focused: focused),
        ),
      );
    }

    Widget snippetChip(int i) {
      final seg = order[i];
      final segState = stateFor(i, seg);
      final rawValue = valueAt(i, order);
      var chipValue = rawValue;
      if ((seg == CaptionSegment.customText ||
              seg == CaptionSegment.freeText) &&
          chipValue.trim().isEmpty) {
        chipValue = '(no text)';
      }
      final label = _segmentDisplayLabel(seg, i);
      final inner = _previewSegmentChip(
        seg: seg,
        value: chipValue,
        state: segState,
        tooltipLabel: label,
        onSnippetTap: () => _activateFormulaEditor(index: i, segment: seg),
        onRemove: () => _removeSegmentSnippet(i),
      );
      return DragTarget<int>(
        onWillAcceptWithDetails: (d) =>
            d.data != i && !_isStructureTextField(order[d.data]),
        onAcceptWithDetails: (d) => _reorderPreviewSegment(d.data, i),
        builder: (context, candidate, _) {
          final hot = candidate.isNotEmpty;
          return Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: hot ? _ffOf(context).accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Draggable<int>(
              data: i,
              feedback: Material(
                color: Colors.transparent,
                elevation: 4,
                child: Text(
                  '{$label}',
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _ffOf(context).accent,
                  ),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.28, child: inner),
              child: inner,
            ),
          );
        },
      );
    }

    ({
      Widget child,
      bool ownRow,
      bool isChip,
      bool leadingJoiner,
      bool trailingPunct,
      String? flowText,
      bool flowFocused,
      VoidCallback? onEditFlow,
    }) glueItem(
      Widget child,
      String text, {
      required bool focused,
      VoidCallback? onEdit,
    }) {
      final ownRow = _structureTextNeedsOwnRow(text, maxTextWidth);
      return (
        child: child,
        ownRow: ownRow,
        isChip: false,
        leadingJoiner: !ownRow && _structureTextIsLeadingJoiner(text),
        trailingPunct: !ownRow && _structureTextIsTrailingPunct(text),
        flowText: ownRow ? text : null,
        flowFocused: focused,
        onEditFlow: onEdit,
      );
    }

    final items = <
        ({
          Widget child,
          bool ownRow,
          bool isChip,
          bool leadingJoiner,
          bool trailingPunct,
          String? flowText,
          bool flowFocused,
          VoidCallback? onEditFlow,
        })>[
      glueItem(
        prefixBox(),
        _layoutPrefixCtrl.text,
        focused: _layoutPrefixFocused,
        onEdit: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _layoutPrefixFocus.requestFocus();
          });
        },
      ),
    ];
    for (var i = 0; i < n; i++) {
      if (_isStructureTextField(order[i])) {
        final text = _glueSnippetControllers[i]?.text ?? '';
        final ownRow = _structureTextNeedsOwnRow(text, maxTextWidth);
        final index = i;
        items.add(
          glueItem(
            glueBox(i, ownRow: ownRow),
            text,
            focused: _focusedGlueSegmentIndex == i,
            onEdit: () {
              _onGlueSnippetFocusChanged(index, true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _glueFocusNodes[index]?.requestFocus();
              });
            },
          ),
        );
        continue;
      }
      items.add((
        child: snippetChip(i),
        ownRow: false,
        isChip: true,
        leadingJoiner: false,
        trailingPunct: false,
        flowText: null,
        flowFocused: false,
        onEditFlow: null,
      ));
    }
    items.add(
      glueItem(
        suffixBox(),
        _layoutSuffixCtrl.text,
        focused: _layoutSuffixFocused,
        onEdit: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _layoutSuffixFocus.requestFocus();
          });
        },
      ),
    );
    return _structureReadingFlow(maxWidth: maxTextWidth, items: items);
  }

  /// Snippet chip: `{Label}` token style (matches filename builder).
  Widget _previewSegmentChip({
    required CaptionSegment seg,
    required String value,
    required _PreviewSegmentState state,
    required String tooltipLabel,
    VoidCallback? onSnippetTap,
    VoidCallback? onRemove,
  }) {
    final Color braceColor;
    switch (state) {
      case _PreviewSegmentState.active:
        braceColor = FfTokens.sessionOn;
        break;
      case _PreviewSegmentState.dim:
        braceColor = FfTokens.sessionOn.withValues(alpha: 0.40);
        break;
      case _PreviewSegmentState.tinted:
        braceColor = FfTokens.sessionOn;
        break;
    }
    final selected = state == _PreviewSegmentState.active;

    // Avoid Container.alignment: Wrap gives bounded width, so alignment would
    // expand every chip to full row width (one token per line).
    Widget chipContent = AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      height: _snippetChipHeight,
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: FfTokens.sessionOnRing,
                  blurRadius: 0,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '{',
            style: _structurePatternTextStyle.copyWith(color: braceColor),
            strutStyle: _structurePatternStrut,
          ),
          Text(
            tooltipLabel,
            style: _structurePatternTextStyle.copyWith(
              color: braceColor,
            ),
            strutStyle: _structurePatternStrut,
          ),
          Text(
            '}',
            style: _structurePatternTextStyle.copyWith(color: braceColor),
            strutStyle: _structurePatternStrut,
          ),
        ],
      ),
    );

    chipContent = Tooltip(
      message: value.trim().isEmpty ? tooltipLabel : '$tooltipLabel · $value',
      waitDuration: const Duration(milliseconds: 400),
      child: chipContent,
    );

    if (onSnippetTap != null || onRemove != null) {
      chipContent = MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onSnippetTap,
          onSecondaryTapDown: onRemove == null
              ? null
              : (details) => unawaited(
                    _showStructureChipRemoveMenu(
                      details: details,
                      onRemove: onRemove,
                    ),
                  ),
          child: chipContent,
        ),
      );
    }

    return chipContent;
  }

  /// Right-click menu on Structure chips — same pattern as filename rename.
  Future<void> _showStructureChipRemoveMenu({
    required TapDownDetails details,
    required VoidCallback onRemove,
  }) async {
    final t = _ffOf(context);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      color: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: t.divider),
      ),
      items: [
        PopupMenuItem<String>(
          value: 'remove',
          height: 36,
          child: Text(
            'Remove',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: t.text,
            ),
          ),
        ),
      ],
    );
    if (!mounted || action != 'remove') return;
    onRemove();
  }

  /// Plain text rendered between snippet chips. Kept as a single [Text] widget
  /// (no chip background) so the inter-snippet separator visually belongs to
  /// neither side.
  Widget _previewGapText(String text, _PreviewGapState state) {
    final tokens = _ffOf(context);
    TextStyle style;
    switch (state) {
      case _PreviewGapState.active:
        style = TextStyle(
          fontSize: 12,
          height: 1.35,
          color: tokens.text,
          backgroundColor: _snippetFill,
          fontWeight: FontWeight.w600,
        );
        break;
      case _PreviewGapState.dim:
        style = TextStyle(
          fontSize: 12,
          height: 1.35,
          color: tokens.text.withValues(alpha: 0.40),
        );
        break;
      case _PreviewGapState.normal:
        style = TextStyle(
          fontSize: 12,
          height: 1.35,
          color: tokens.text,
        );
        break;
    }
    return Text(text, style: style);
  }


  /// Compact style picker for the dialog header (fixed height; no DropdownFlutter).
  Widget _buildCaptionStyleDropdown() {
    final t = _ffOf(context);
    final tokens = _captionStyleDropdownTokens();
    final current = _captionStyleDropdownInitialToken();
    final locked = _tokenIsLockedCore(current);
    final label = _captionStyleMenuLabel(current);
    final firstCustom = CaptionStyleCatalog.firstCustomTokenIndex(tokens);

    return PopupMenuButton<String>(
      tooltip: 'Caption style',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 28),
      color: t.surface,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280, maxHeight: 380),
      onSelected: (token) {
        _rememberCurrentWireDraft();
        _applyCaptionStyleMenuToken(token);
      },
      itemBuilder: (ctx) {
        final items = <PopupMenuEntry<String>>[];
        for (var i = 0; i < tokens.length; i++) {
          final token = tokens[i];
          if (firstCustom >= 0 && i == firstCustom) {
            items.add(const PopupMenuDivider(height: 8));
          }
          final selected = token == current;
          final lockedTok = _tokenIsLockedCore(token);
          final fav = _favoriteCaptionStyleToken == token;
          items.add(
            PopupMenuItem<String>(
              value: token,
              height: 34,
              child: Row(
                children: [
                  if (lockedTok)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: PhosphorIcon(PhosphorIconsRegular.lock,
                          size: 13, color: t.textSecondary),
                    )
                  else if (token.startsWith('saved:'))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: PhosphorIcon(PhosphorIconsRegular.bookmarkSimple,
                          size: 14, color: t.textSecondary),
                    ),
                  Expanded(
                    child: Text(
                      _captionStyleMenuLabel(token),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: lockedTok ? t.textSecondary : t.text,
                      ),
                    ),
                  ),
                  Icon(
                    fav ? PhosphorIconsFill.star : PhosphorIconsRegular.star,
                    size: 15,
                    color: fav
                        ? const Color(0xFFE6B84A)
                        : t.text.withValues(alpha: 0.35),
                  ),
                ],
              ),
            ),
          );
        }
        return items;
      },
      child: Container(
        height: widget.embedded ? 34 : 26,
        width: double.infinity,
        decoration: BoxDecoration(
          color: t.sunken,
          borderRadius: BorderRadius.circular(FfTokens.radiusChip),
          border: Border.all(color: t.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              if (locked) ...[
                PhosphorIcon(PhosphorIconsRegular.lock,
                  size: 12,
                  color: t.text.withValues(alpha: 0.45),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.metaStyle.copyWith(
                    color: locked ? t.textSecondary : t.text,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: t.text.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _promptEditStructureSnippets() {
    final target = _structureSectionKey.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    }
    setState(() => _structureHintFlash = true);
    _structureHintFlashTimer?.cancel();
    _structureHintFlashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      setState(() => _structureHintFlash = false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Edit the snippets in Structure below.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _extraFieldToggle({
    required String label,
    required String explanation,
    required bool value,
    required Future<void> Function(bool) onSave,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _layoutOptionalFieldRow(
          label: label,
          value: value,
          onSave: onSave,
        ),
        const SizedBox(height: 2),
        Text(
          explanation,
          style: _t.microStyle.copyWith(
            color: _t.text.withValues(alpha: 0.45),
            height: 1.2,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildFieldsShownSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: _editorPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('DISPLAY EXTRA FIELDS', style: _panelTitleStyle),
          const SizedBox(height: 6),
          _lockableEditorSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _extraFieldToggle(
                  label: 'IPTC Personality',
                  explanation: 'Who is in the photo. Saved to IPTC.',
                  value: _template.showPersonalityField,
                  onSave: _setShowPersonalityField,
                ),
                const SizedBox(height: 8),
                _extraFieldToggle(
                  label: 'IPTC Keywords',
                  explanation: 'Search words, filled from the players and verb.',
                  value: _template.showKeywordsField,
                  onSave: _setShowKeywordsField,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerOptionCell(String label, Widget control) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: _layoutOptionTextStyle),
        const SizedBox(height: 6),
        control,
      ],
    );
  }

  Widget _buildPlayerOutputSection(String playerPreviewText) {
    final t = _ffOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'PLAYER OUTPUT',
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
            color: t.textTertiary,
          ),
        ),
        const SizedBox(height: 12),
        _nocturnePlayerSample(playerPreviewText),
        const SizedBox(height: 12),
        ..._nocturnePlayerOutputOptionGroups(),
      ],
    );
  }

  BoxDecoration _editorPanelDecoration() {
    final t = _ffOf(context);
    return BoxDecoration(
      color: t.surface,
      borderRadius: BorderRadius.circular(FfTokens.radiusChip),
      border: Border.all(color: t.divider),
    );
  }

  Widget _buildInlineFieldEditor() {
    return Container(
      decoration: BoxDecoration(
        color: _ffOf(context).surface,
        border: Border.all(color: _ffOf(context).divider),
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        boxShadow: [
          BoxShadow(
            color: _ffOf(context).bg.withValues(alpha: 0.45),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _ffOf(context).sunken,
              border: Border(
                bottom: BorderSide(color: _ffOf(context).divider),
              ),
            ),
            child: Row(
              children: [
                _activeEditIndicator(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_captionPreviewSelected)
                  _captionSegmentEditor()
                else if (_customTextSnippetEditorOpen)
                  _customTextSnippetEditor()
                else if (_freeTextSnippetEditorOpen)
                  _freeTextSnippetEditor()
                else if (_venuePreviewSelected)
                  _venueEditor()
                else if (_bylinePreviewSelected)
                  _bylineEditor(),
                if (_dateEditorOpen) _dateLineEditor(),
                if (_locationEditorOpen) _locationOptionsEditor(),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedGreyButton(
                    label: 'Done',
                    isPrimary: true,
                    fontSize: 12,
                    onPressed: _closeAllInlineEdits,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _timingUnitNoun {
    switch (_sessionSport.toLowerCase().trim()) {
      case 'hockey':
        return 'period';
      case 'basketball':
      case 'wnba':
      case 'football':
        return 'quarter';
      case 'soccer':
        return 'half';
      case 'baseball':
      default:
        return 'inning';
    }
  }

  void _setLinkedHover(int? index) {
    if (_linkedHoverIndex == index) return;
    setState(() => _linkedHoverIndex = index);
  }

  void _beginSepEdit(String key, String value) {
    final previous = _editingSepKey;
    if (previous != null && previous != key) {
      _applySepEdit(previous, _sepEditCtrl.text);
    }
    _sepEditCtrl.value = TextEditingValue(
      text: value,
      selection: TextSelection(baseOffset: 0, extentOffset: value.length),
    );
    setState(() => _editingSepKey = key);
  }

  void _cancelSepEdit() {
    if (_editingSepKey == null) return;
    setState(() => _editingSepKey = null);
  }

  void _applySepEdit(String key, String value) {
    if (key == 'prefix') {
      _layoutPrefixCtrl.text = value;
    } else if (key == 'suffix') {
      _layoutSuffixCtrl.text = value;
    } else if (key.startsWith('g')) {
      final index = int.tryParse(key.substring(1));
      if (index != null) {
        _glueSnippetControllers[index]?.text = value;
      }
    }
  }

  void _commitSepEdit() {
    final key = _editingSepKey;
    if (key == null) return;
    final value = _sepEditCtrl.text;
    setState(() => _editingSepKey = null);
    _applySepEdit(key, value);
  }

  void _removeSegmentWithUndo(int index) {
    if (index < 0 || index >= _template.segmentOrder.length) return;
    final snapshot = _template;
    _removeSegmentSnippet(index);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        content: const Text('Field removed'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted) return;
            setState(() {
              _template = snapshot;
              _initGapControllers(_template);
            });
            _scheduleAutosave();
            widget.onDraftChanged?.call(_selectedWire, _template);
          },
        ),
      ),
    );
  }

  String _sampleForUnusedField(CaptionSegment segment, String sampleCaption) {
    switch (segment) {
      case CaptionSegment.location:
        return CaptionFormulaRenderer.formatLocationLine(
          _captionPreviewGame,
          _template.locationOptions,
          apStyleCaption: _template.wireStyle == WireStyle.ap,
          cpStyleCaption: _template.wireStyle == WireStyle.cp,
          forceAutoAdaptUsIntl: _isGettyWire,
        );
      case CaptionSegment.city:
        return CaptionFormulaRenderer.formatGeoField(
          game: _captionPreviewGame,
          options: _template.locationOptions,
          kind: LocationChipKind.city,
          apStyleCaption: _template.wireStyle == WireStyle.ap,
          cpStyleCaption: _template.wireStyle == WireStyle.cp,
          forceAutoAdaptUsIntl: _isGettyWire,
        );
      case CaptionSegment.state:
        return CaptionFormulaRenderer.formatGeoField(
          game: _captionPreviewGame,
          options: _template.locationOptions,
          kind: LocationChipKind.region,
          apStyleCaption: _template.wireStyle == WireStyle.ap,
          cpStyleCaption: _template.wireStyle == WireStyle.cp,
          forceAutoAdaptUsIntl: _isGettyWire,
          formulaIncludesCountry:
              _template.segmentOrder.contains(CaptionSegment.country),
        );
      case CaptionSegment.country:
        return CaptionFormulaRenderer.formatGeoField(
          game: _captionPreviewGame,
          options: _template.locationOptions,
          kind: LocationChipKind.country,
          apStyleCaption: _template.wireStyle == WireStyle.ap,
          cpStyleCaption: _template.wireStyle == WireStyle.cp,
          forceAutoAdaptUsIntl: _isGettyWire,
          formulaIncludesCountry:
              _template.segmentOrder.contains(CaptionSegment.country),
        );
      case CaptionSegment.countryCode:
        return CaptionFormulaRenderer.formatGeoField(
          game: _captionPreviewGame,
          options: _template.locationOptions,
          kind: LocationChipKind.countryCode,
          apStyleCaption: _template.wireStyle == WireStyle.ap,
          cpStyleCaption: _template.wireStyle == WireStyle.cp,
          forceAutoAdaptUsIntl: false,
        );
      case CaptionSegment.date:
        return CaptionFormulaRenderer.formatTemplateDateLine(
          _previewGameInfo,
          _template,
          uppercaseAll: _isGettyWire,
        );
      case CaptionSegment.month:
        return CaptionFormulaRenderer.formatDatePart(
          game: _previewGameInfo,
          template: _template,
          kind: DateFieldKind.month,
          occurrenceIndex: 0,
        );
      case CaptionSegment.day:
        return CaptionFormulaRenderer.formatDatePart(
          game: _previewGameInfo,
          template: _template,
          kind: DateFieldKind.day,
          occurrenceIndex: 0,
        );
      case CaptionSegment.year:
        return CaptionFormulaRenderer.formatDatePart(
          game: _previewGameInfo,
          template: _template,
          kind: DateFieldKind.year,
          occurrenceIndex: 0,
        );
      case CaptionSegment.weekday:
        return CaptionFormulaRenderer.formatDatePart(
          game: _previewGameInfo,
          template: _template,
          kind: DateFieldKind.weekday,
          occurrenceIndex: 0,
        );
      case CaptionSegment.caption:
        return sampleCaption;
      case CaptionSegment.customText:
      case CaptionSegment.freeText:
        final text = _template.gameIdentifierText.trim();
        if (text.isNotEmpty) return text;
        return defaultGameIdentifierText(_sessionSport);
      case CaptionSegment.venue:
        return CaptionFormulaRenderer.venueLabel(_previewGameInfo);
      case CaptionSegment.creator:
        return CaptionFormulaRenderer.formatCreatorName(
          game: _previewGameInfo,
          bylineOptions: _template.bylineOptions,
        );
      case CaptionSegment.agency:
        return CaptionFormulaRenderer.formatAgencyCredit(
          game: _previewGameInfo,
          bylineOptions: _template.bylineOptions,
          sampleAgency: _sampleAgencyForWire(_template.wireStyle),
        );
      case CaptionSegment.credit:
        return '{photographer}';
      case CaptionSegment.separator:
      case CaptionSegment.punctuation:
        return '';
    }
  }

  Widget _outlinedGhostButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final t = _ffOf(context);
    final enabled = onPressed != null;
    final color = enabled ? t.text : t.text.withValues(alpha: 0.35);
    return Material(
      color: t.elevated,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: enabled ? t.accentEdge : t.divider,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(icon, size: 15, color: color),
              const SizedBox(width: 7),
              Text(
                label,
                softWrap: false,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _adminDarkSelect({required double width, required Widget child}) {
    final t = _ffOf(context);
    return SizedBox(
      width: width,
      height: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.sunken,
          borderRadius: BorderRadius.circular(FfTokens.radiusChip),
          border: Border.all(color: t.divider),
        ),
        child: child,
      ),
    );
  }

  Widget _adminStructuresToolbar() {
    final t = _ffOf(context);
    final sports = AppDefaultsFirestoreService.catalogSports;
    final sport =
        sports.contains(_sessionSport) ? _sessionSport : sports.first;
    return Row(
      children: [
        _adminDarkSelect(
          width: 148,
          child: FfDropdownButton<String>(
            value: sport,
            isExpanded: true,
            menuColor: t.surface,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            icon: PhosphorIcon(
              PhosphorIconsRegular.caretDown,
              size: 14,
              color: t.textSecondary,
            ),
            style: t.metaStyle.copyWith(color: t.text, fontSize: 12),
            items: [
              for (final id in sports)
                DropdownMenuItem(
                  value: id,
                  child: Text(
                    SportVerbCategories.displayLabel(id),
                    softWrap: false,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              _onSessionSportPicked(value);
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 148, height: 34, child: _buildCaptionStyleDropdown()),
        const SizedBox(width: 8),
        Tooltip(
          message: widget.adminMode
              ? 'Each sport has its own Structure for this wire. '
                  'Switch sport to edit that sport’s caption layout.'
              : 'Sport changes preview sample, teams, verbs, and game ID.',
          waitDuration: const Duration(milliseconds: 300),
          child: PhosphorIcon(
            PhosphorIconsRegular.info,
            size: 16,
            color: t.text.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }

  /// A joiner with more than one word (the Getty note) wraps in its own box.
  /// ` at ` and ` - ` stay single-line marks.
  bool _sepIsParagraph(String value) => value.trim().contains(' ');

  /// Box hugs the text. A long note wraps once it hits [maxWidth], then grows
  /// taller so every line stays visible.
  GrowingTextBoxSize _sepBoxSize(
    String visual,
    TextStyle style,
    double maxWidth, {
    required bool paragraph,
  }) {
    final cap = maxWidth.isFinite && maxWidth > 32 ? maxWidth : 360.0;
    return GrowingTextBoxSize.measure(
      text: visual,
      style: style,
      minWidth: 28,
      maxWidth: cap,
      minHeight: 34,
      horizontalPad: 16,
      verticalPad: paragraph ? 16 : 0,
    );
  }

  Widget _adminSepField({
    required int sepIndex,
    required TextEditingController controller,
    required FocusNode focusNode,
    required double maxWidth,
    bool forceFullWidth = false,
  }) {
    return _GapSeparatorField(
      controller: controller,
      focusNode: focusNode,
      maxWidth: maxWidth,
      forceFullWidth: forceFullWidth,
    );
  }

  Widget _adminFieldChip({
    required int index,
    required CaptionSegment segment,
  }) {
    final t = _ffOf(context);
    final selected = _activeFormulaIndex == index;
    final linked = _linkedHoverIndex == index;
    final label = _segmentDisplayLabel(segment, index);
    final braceColor = FfTokens.sessionOn;
    final chip = MouseRegion(
      onEnter: (_) => _setLinkedHover(index),
      onExit: (_) => _setLinkedHover(null),
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        onTap: () => _activateFormulaEditor(index: index, segment: segment),
        onSecondaryTapDown: (details) => unawaited(
          _showStructureChipRemoveMenu(
            details: details,
            onRemove: () => _removeSegmentWithUndo(index),
          ),
        ),
        // Avoid Container.alignment inside Wrap (see `_previewSegmentChip`).
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: _snippetChipHeight,
          margin: EdgeInsets.zero,
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            boxShadow: selected || linked
                ? const [
                    BoxShadow(
                      color: FfTokens.sessionOnRing,
                      blurRadius: 0,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '{',
                softWrap: false,
                style: _structurePatternTextStyle.copyWith(color: braceColor),
                strutStyle: _structurePatternStrut,
              ),
              Text(
                label,
                softWrap: false,
                style: _structurePatternTextStyle.copyWith(
                  color: braceColor,
                ),
                strutStyle: _structurePatternStrut,
              ),
              Text(
                '}',
                softWrap: false,
                style: _structurePatternTextStyle.copyWith(color: braceColor),
                strutStyle: _structurePatternStrut,
              ),
            ],
          ),
        ),
      ),
    );
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) =>
          details.data != index &&
          !_isStructureTextField(_template.segmentOrder[details.data]),
      onAcceptWithDetails: (details) =>
          _reorderPreviewSegment(details.data, index),
      builder: (context, candidate, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: candidate.isNotEmpty ? t.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Draggable<int>(
            data: index,
            feedback: Material(
              color: Colors.transparent,
              elevation: 4,
              child: Text(
                '{$label}',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: braceColor,
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.28, child: chip),
            child: chip,
          ),
        );
      },
    );
  }

  static const List<CaptionSegment> _structureAddKinds = <CaptionSegment>[
    CaptionSegment.city,
    CaptionSegment.state,
    CaptionSegment.country,
    CaptionSegment.countryCode,
    CaptionSegment.month,
    CaptionSegment.day,
    CaptionSegment.year,
    CaptionSegment.caption,
    CaptionSegment.freeText,
    CaptionSegment.venue,
    CaptionSegment.creator,
    CaptionSegment.agency,
    CaptionSegment.credit,
  ];

  IconData _structureAddIcon(CaptionSegment kind) {
    switch (kind) {
      case CaptionSegment.location:
      case CaptionSegment.city:
        return PhosphorIconsRegular.mapPin;
      case CaptionSegment.state:
        return PhosphorIconsRegular.mapTrifold;
      case CaptionSegment.country:
      case CaptionSegment.countryCode:
        return PhosphorIconsRegular.globeHemisphereWest;
      case CaptionSegment.date:
      case CaptionSegment.month:
      case CaptionSegment.day:
      case CaptionSegment.year:
      case CaptionSegment.weekday:
        return PhosphorIconsRegular.calendarBlank;
      case CaptionSegment.caption:
        return PhosphorIconsRegular.textAlignLeft;
      case CaptionSegment.customText:
        return PhosphorIconsRegular.identificationCard;
      case CaptionSegment.freeText:
        return PhosphorIconsRegular.textT;
      case CaptionSegment.venue:
        return PhosphorIconsRegular.buildings;
      case CaptionSegment.creator:
        return PhosphorIconsRegular.user;
      case CaptionSegment.agency:
        return PhosphorIconsRegular.copyright;
      case CaptionSegment.credit:
        return PhosphorIconsRegular.identificationBadge;
      case CaptionSegment.separator:
      case CaptionSegment.punctuation:
        return PhosphorIconsRegular.plus;
    }
  }

  void _onStructureAddKindSelected(CaptionSegment kind) {
    _addSegmentSnippet(kind);
  }

  Widget _buildStructureAddMenu(String sampleCaption) {
    final t = _ffOf(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<CaptionSegment>(
        tooltip: 'Add to caption',
        padding: EdgeInsets.zero,
        offset: const Offset(0, 36),
        color: t.surface,
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 360, maxHeight: 420),
        onSelected: _onStructureAddKindSelected,
        itemBuilder: (context) {
          return [
            for (final kind in _structureAddKinds)
              PopupMenuItem<CaptionSegment>(
                value: kind,
                height: 48,
                child: _structureAddMenuRow(t, kind, sampleCaption),
              ),
          ];
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.sunken,
            borderRadius: BorderRadius.circular(FfTokens.radiusChip),
            border: Border.all(color: t.divider),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: SizedBox(
              height: 34,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PhosphorIcon(
                    PhosphorIconsRegular.plus,
                    size: 16,
                    color: t.text.withValues(alpha: 0.82),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Add to caption',
                    style: t.metaStyle.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: t.text.withValues(alpha: 0.82),
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  PhosphorIcon(
                    PhosphorIconsRegular.caretDown,
                    size: 12,
                    color: t.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _structureAddMenuRow(
    FfTokens t,
    CaptionSegment kind,
    String sampleCaption,
  ) {
    final sample = _sampleForUnusedField(kind, sampleCaption).trim();
    return Row(
      children: [
        PhosphorIcon(
          _structureAddIcon(kind),
          size: 16,
          color: t.textTertiary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _pillShortLabel(kind),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: t.text,
                ),
              ),
              if (sample.isNotEmpty)
                Text(
                  sample,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: t.textTertiary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _adminStructureStrip() {
    final order = _template.segmentOrder;
    final sepSlots = _structureSepSlots();
    final cap = _gapBoxCap(context);
    Widget sepAt(int sepIndex, {required bool ownRow}) {
      if (sepIndex < 0 || sepIndex >= sepSlots.length) {
        return const SizedBox.shrink();
      }
      final slot = sepSlots[sepIndex];
      return _adminSepField(
        sepIndex: sepIndex,
        controller: slot.controller,
        focusNode: slot.focus,
        maxWidth: cap,
        forceFullWidth: ownRow,
      );
    }

    var sepIndex = 0;
    final items = <
        ({
          Widget child,
          bool ownRow,
          bool isChip,
          bool leadingJoiner,
          bool trailingPunct,
          String? flowText,
          bool flowFocused,
          VoidCallback? onEditFlow,
        })>[];
    void addSep() {
      if (sepIndex < 0 || sepIndex >= sepSlots.length) {
        sepIndex++;
        return;
      }
      final slot = sepSlots[sepIndex];
      final text = slot.controller.text;
      final ownRow = _structureTextNeedsOwnRow(text, cap);
      final node = slot.focus;
      items.add((
        child: sepAt(sepIndex, ownRow: ownRow),
        ownRow: ownRow,
        isChip: false,
        leadingJoiner: !ownRow && _structureTextIsLeadingJoiner(text),
        trailingPunct: !ownRow && _structureTextIsTrailingPunct(text),
        flowText: ownRow ? text : null,
        flowFocused: node.hasFocus,
        onEditFlow: () {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) node.requestFocus();
          });
        },
      ));
      sepIndex++;
    }

    addSep(); // prefix
    for (var i = 0; i < order.length; i++) {
      final segment = order[i];
      if (_isStructureTextField(segment)) {
        addSep();
      } else {
        items.add((
          child: _adminFieldChip(index: i, segment: segment),
          ownRow: false,
          isChip: true,
          leadingJoiner: false,
          trailingPunct: false,
          flowText: null,
          flowFocused: false,
          onEditFlow: null,
        ));
      }
    }
    addSep(); // suffix
    return _structureReadingFlow(maxWidth: cap, items: items);
  }

  bool get _fieldOptionsOpen =>
      _locationEditorOpen ||
      _dateEditorOpen ||
      _captionPreviewSelected ||
      _venuePreviewSelected ||
      _bylinePreviewSelected ||
      _customTextSnippetEditorOpen ||
      _freeTextSnippetEditorOpen ||
      _separatorSnippetEditorOpen ||
      _punctuationSnippetEditorOpen;

  Widget _adminStructureCard({
    required bool fill,
    required bool tight,
    required String sampleCaption,
  }) {
    final header = Text('STRUCTURE', style: _panelTitleStyle);
    Widget stripAndAdd(double maxWidth) {
      return _StructureTextLimit(
        maxWidth: maxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _adminStructureStrip(),
            // Hide while a field's options are open — keeps the editor uncluttered.
            if (!_fieldOptionsOpen) ...[
              SizedBox(height: tight ? 10 : 14),
              _buildStructureAddMenu(sampleCaption),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(12, tight ? 8 : 12, 12, tight ? 8 : 10),
      decoration: _editorPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          SizedBox(height: tight ? 6 : 10),
          if (fill)
            Expanded(
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth.isFinite &&
                            constraints.maxWidth > 0
                        ? constraints.maxWidth
                        : 400.0;
                    return ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false),
                      child: SingleChildScrollView(
                        child: stripAndAdd(w),
                      ),
                    );
                  },
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth.isFinite &&
                        constraints.maxWidth > 0
                    ? constraints.maxWidth
                    : 400.0;
                return stripAndAdd(w);
              },
            ),
        ],
      ),
    );
  }

  List<({String text, int? index})> _adminPreviewPieces({
    required String full,
    required String sampleCaption,
    required CreditSampleAgency sampleAgency,
  }) {
    final pieces = <({String text, int? index})>[];
    if (full.isEmpty) return pieces;
    var cursor = 0;
    void consume(String part, int? index) {
      if (part.isEmpty) return;
      final found = _locatePreviewPiece(full, part, cursor);
      if (found == null) return;
      if (found.start > cursor) {
        pieces.add((text: full.substring(cursor, found.start), index: null));
      }
      pieces.add((
        text: full.substring(found.start, found.end),
        index: index,
      ));
      cursor = found.end;
    }

    final order = _template.segmentOrder;
    final gaps = CaptionFormulaRenderer.effectiveSegmentGaps(_template);
    final hasGlue = order.any(_isGlueSegment);
    consume(_template.layoutPrefix, null);
    for (var i = 0; i < order.length; i++) {
      final segment = order[i];
      if ((segment == CaptionSegment.customText ||
              segment == CaptionSegment.freeText) &&
          _previewSegmentText(i, sampleCaption, sampleAgency).trim().isEmpty) {
        continue;
      }
      consume(
        _previewSegmentText(i, sampleCaption, sampleAgency),
        _isStructureTextField(segment) ? null : i,
      );
      if (!hasGlue && i < order.length - 1 && i < gaps.length) {
        consume(gaps[i], null);
      }
    }
    consume(_template.layoutSuffix, null);
    if (cursor < full.length) {
      pieces.add((text: full.substring(cursor), index: null));
    }
    final joined = pieces.map((piece) => piece.text).join();
    if (joined != full) {
      return [(text: full, index: null)];
    }
    return pieces;
  }

  Widget _adminResolvedPreview({
    required String fullCaptionPreview,
    required String sampleCaption,
    required CreditSampleAgency sampleAgency,
    required double fontSize,
  }) {
    final t = _ffOf(context);
    final style = TextStyle(
      fontSize: fontSize,
      height: 1.35,
      fontWeight: FontWeight.w500,
      color: t.text,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final pieces = _adminPreviewPieces(
          full: fullCaptionPreview,
          sampleCaption: sampleCaption,
          sampleAgency: sampleAgency,
        );
        final maxWidth = constraints.maxWidth;
        int? hitAt(Offset local) {
          final painter = TextPainter(
            text: TextSpan(
              style: style,
              children: [
                for (final piece in pieces) TextSpan(text: piece.text),
              ],
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: maxWidth);
          final offset = painter.getPositionForOffset(local).offset;
          painter.dispose();
          var cursor = 0;
          for (final piece in pieces) {
            final end = cursor + piece.text.length;
            if (piece.index != null && offset >= cursor && offset < end) {
              return piece.index;
            }
            cursor = end;
          }
          return null;
        }

        return MouseRegion(
          onHover: (event) => _setLinkedHover(hitAt(event.localPosition)),
          onExit: (_) => _setLinkedHover(null),
          child: GestureDetector(
            onTapUp: (details) {
              final index = hitAt(details.localPosition);
              if (index == null) return;
              _activateFormulaEditor(
                index: index,
                segment: _template.segmentOrder[index],
              );
            },
            child: Text.rich(
              TextSpan(
                style: style,
                children: [
                  for (final piece in pieces)
                    TextSpan(
                      text: piece.text,
                      style: piece.index != null &&
                              (_linkedHoverIndex == piece.index ||
                                  _activeFormulaIndex == piece.index)
                          ? style.copyWith(
                              backgroundColor: t.accent.withValues(alpha: 0.45),
                            )
                          : null,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _adminPlayerCard({
    required String playerPreviewText,
    required bool tight,
  }) {
    final t = _ffOf(context);
    Widget cell(String label, Widget control) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: _layoutOptionTextStyle,
          ),
          const SizedBox(height: 4),
          control,
        ],
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(12, tight ? 8 : 12, 12, tight ? 8 : 12),
      decoration: _editorPanelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('PLAYER OUTPUT', style: _panelTitleStyle),
          SizedBox(height: tight ? 6 : 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _snippetFill,
              borderRadius: BorderRadius.circular(FfTokens.radiusChip),
              border: Border.all(color: t.divider),
            ),
            child: Text(
              playerPreviewText,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.3, color: t.text),
            ),
          ),
          SizedBox(height: tight ? 6 : 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cell('Team order', _teamOrderSegments())),
              const SizedBox(width: 8),
              Expanded(child: cell('English', _englishSegments())),
            ],
          ),
          SizedBox(height: tight ? 6 : 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cell('Number', _numberFormatSegments())),
              const SizedBox(width: 8),
              Expanded(child: cell('Position', _positionSegments())),
            ],
          ),
          SizedBox(height: tight ? 6 : 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cell('Time of game', _timingPhraseSegments())),
              const SizedBox(width: 8),
              Expanded(child: cell('Diacritics', _diacriticsSegments())),
            ],
          ),
          Divider(height: tight ? 12 : 16, color: t.text.withValues(alpha: 0.08)),
          Row(
            children: [
              Expanded(
                child: _layoutOptionalFieldRow(
                  label: 'IPTC Personality',
                  value: _template.showPersonalityField,
                  onSave: _setShowPersonalityField,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _layoutOptionalFieldRow(
                  label: 'IPTC Keywords',
                  value: _template.showKeywordsField,
                  onSave: _setShowKeywordsField,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdminStructuresLayout({
    required String fullCaptionPreview,
    required String sampleCaption,
    required CreditSampleAgency sampleAgency,
    required String playerPreviewText,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final window = MediaQuery.sizeOf(context);
        final tight = window.height < 780;
        final stack = constraints.maxWidth < 860;
        final scroll =
            window.height < 700 || window.width < 1000 || stack;
        final gap = tight ? 6.0 : 8.0;
        final structure = _adminStructureCard(
          fill: !scroll,
          tight: tight,
          sampleCaption: sampleCaption,
        );
        final player = _adminPlayerCard(
          playerPreviewText: playerPreviewText,
          tight: tight,
        );
        final cards = stack
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  structure,
                  SizedBox(height: gap),
                  player,
                ],
              )
            : Row(
                crossAxisAlignment: scroll
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: structure),
                  SizedBox(width: gap + 4),
                  SizedBox(width: 400, child: player),
                ],
              );
        final column = Column(
          mainAxisSize: scroll ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _adminStructuresToolbar(),
            SizedBox(height: gap),
            Row(
              children: [
                Text('Resolves to', style: _panelTitleStyle),
                const Spacer(),
                _outlinedGhostButton(
                  icon: PhosphorIconsRegular.shuffle,
                  label: 'Shuffle sample',
                  onPressed: _shuffleCaptionSample,
                ),
              ],
            ),
            SizedBox(height: gap),
            DecoratedBox(
              decoration: BoxDecoration(
                color: _ffOf(context).sunken,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: tight ? 8 : 12,
                ),
                child: _adminResolvedPreview(
                  fullCaptionPreview: fullCaptionPreview,
                  sampleCaption: sampleCaption,
                  sampleAgency: sampleAgency,
                  fontSize: tight ? 13 : 16,
                ),
              ),
            ),
            SizedBox(height: gap),
            if (scroll) cards else Expanded(child: cards),
          ],
        );
        final padding = EdgeInsets.fromLTRB(
          tight ? 8 : 12,
          tight ? 8 : 10,
          tight ? 8 : 12,
          tight ? 6 : 8,
        );
        return ClipRect(
          child: scroll
              ? SingleChildScrollView(padding: padding, child: column)
              : Padding(padding: padding, child: column),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleAutosave();
    _ensureExampleTeams();
    final realPlayers = _realPreviewPlayers();
    // Prefer live session / selected-team rosters. Never invent names for
    // other clubs when teams are selected.
    final sampleCaption = _resolvedSampleCaption();
    final playerPreviewText = (realPlayers != null && realPlayers.isNotEmpty)
        ? CaptionFormulaRenderer.randomSinglePlayerPreview(
            _template,
            seed: _captionSampleSeed,
            previewPlayers: realPlayers,
            sport: _sessionSport,
          )
        : (_hasSelectedExampleTeams
            ? (_rosterPreviewLoading
                ? 'Loading roster…'
                : 'Waiting for roster…')
            : CaptionFormulaRenderer.randomSinglePlayerPreview(
                _template,
                seed: _captionSampleSeed,
                sport: _sessionSport,
              ));
    final previewAgency = _sampleAgencyForWire(_selectedWire);

    final mq = MediaQuery.sizeOf(context);
    final maxH = mq.height * 0.92;
    final dialogHeight = maxH.clamp(300.0, 720.0);
    // Size to the viewport (minus the insetPadding) up to a cap so the layout
    // stays usable on short windows while using more height on large displays.
    final dialogWidth = (mq.width - 32).clamp(320.0, 1400.0);

    final shell = SizedBox(
        width: widget.embedded ? double.infinity : dialogWidth,
        height: widget.embedded ? double.infinity : dialogHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.embedded ? Colors.transparent : _t.surface,
            borderRadius: BorderRadius.circular(
              widget.embedded ? 0 : FfTokens.radiusWindow,
            ),
            border: widget.embedded ? null : Border.all(color: _t.divider),
            boxShadow: widget.embedded
                ? null
                : [
                    BoxShadow(
                      color: _t.bg.withValues(alpha: 0.55),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              widget.embedded ? 0 : FfTokens.radiusWindow,
            ),
            child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!widget.embedded)
                    Container(
                      height: 40,
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: _t.surface,
                        border: Border(
                          bottom: BorderSide(color: _t.divider),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            'CAPTION LAYOUT',
                            style: FfTokens.railLabel.copyWith(
                              color: _t.text.withValues(alpha: 0.78),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 132,
                            height: 26,
                            child: _buildCaptionStyleDropdown(),
                          ),
                          const Spacer(),
                          if (!widget.adminMode) ...[
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: _duplicateCaptionStyle,
                              child: Text(
                                'Duplicate',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _t.accent,
                                ),
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: _selectedSavedStyleId == null
                                  ? null
                                  : _deleteSelectedCaptionStyle,
                              child: Text(
                                'Delete',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedSavedStyleId == null
                                      ? _t.text.withValues(alpha: 0.40)
                                      : FfTokens.danger,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => unawaited(_requestClose()),
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: PhosphorIcon(PhosphorIconsRegular.x,
                                  size: 18,
                                  color: _t.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ColoredBox(
                      color: widget.embedded ? Colors.transparent : _t.bg,
                      child: FutureBuilder<void>(
                      future: _load,
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return SizedBox(
                            height: 120,
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _t.accent,
                                ),
                              ),
                            ),
                          );
                        }
                        return _buildNocturneStructureEditor(
                          sampleCaption: sampleCaption,
                          sampleAgency: previewAgency,
                          playerPreviewText: playerPreviewText,
                        );
                      },
                    ),
                    ),
                  ),
                ],
              ),
              if (_renameCaptionStylePromptOpen)
                Positioned.fill(child: _renameCaptionStyleNameOverlay()),
            ],
          ),
          ),
        ),
      );

    if (widget.embedded) {
      return AppDialogFfStyle(enabled: true, child: shell);
    }
    return PopScope(
      canPop: _closeConfirmed,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _closeConfirmed) return;
        unawaited(_requestClose());
      },
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: shell,
      ),
    );
  }
}

/// What the Rename / Save-as prompt should do when the user submits.
enum _RenamePromptMode {
  libraryEntry,
  wireLabel,
  saveAsNewLibrary,
}

/// Background + foreground color pair used to tint a [CaptionSegment] in the
/// caption preview. Stand-alone class (not a record) because the project's
/// minimum SDK predates the Dart records feature.
class _SegmentTint {
  const _SegmentTint({required this.bg, required this.fg});
  final Color bg;
  final Color fg;
}

/// Visual state of a single snippet chip in the preview row.
///
/// `tinted` is the resting state where the chip wears its [CaptionSegment]'s
/// background color. `active` is the blue "you're editing this" highlight.
/// `dim` is for "another segment is being edited, fade me out".
enum _PreviewSegmentState { tinted, active, dim }

/// Visual state of a separator between two snippet chips in the preview row.
enum _PreviewGapState { normal, active, dim }

/// Widest a structure text box may grow, so a long note wraps inside the panel.
class _StructureTextLimit extends InheritedWidget {
  const _StructureTextLimit({
    required this.maxWidth,
    required super.child,
  });

  final double maxWidth;

  static double? maybeOf(BuildContext context) {
    final limit = context.dependOnInheritedWidgetOfExactType<_StructureTextLimit>();
    if (limit == null || !limit.maxWidth.isFinite || limit.maxWidth <= 0) {
      return null;
    }
    return limit.maxWidth;
  }

  @override
  bool updateShouldNotify(_StructureTextLimit oldWidget) =>
      oldWidget.maxWidth != maxWidth;
}

/// Separator editor that stays as wide as its text and as tall as a long note.
class _HugSepEditor extends StatefulWidget {
  const _HugSepEditor({
    super.key,
    required this.controller,
    required this.maxWidth,
    required this.onCommit,
    required this.onCancel,
  });

  final TextEditingController controller;
  final double maxWidth;
  final VoidCallback onCommit;
  final VoidCallback onCancel;

  @override
  State<_HugSepEditor> createState() => _HugSepEditorState();
}

class _HugSepEditorState extends State<_HugSepEditor> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(covariant _HugSepEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onText);
    widget.controller.addListener(_onText);
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _ffOf(context);
    final raw = widget.controller.text;
    // Decide from the text being typed. The stored gap can still be a short
    // mark, and that used to keep the field on one line while the note grew.
    final paragraph = raw.contains('\n') || raw.trim().contains(' ');
    final style = TextStyle(
      fontFamily: FfTokens.fontFamily,
      fontSize: paragraph ? 12.5 : 13,
      height: paragraph ? 1.35 : 1,
      color: t.text,
    );
    final cap = widget.maxWidth.isFinite && widget.maxWidth > 32
        ? widget.maxWidth
        : 360.0;
    final box = GrowingTextBoxSize.measure(
      text: raw.isEmpty ? ' ' : raw,
      style: style,
      minWidth: 28,
      maxWidth: cap,
      minHeight: 34,
      horizontalPad: 16,
      verticalPad: paragraph ? 16 : 0,
    );
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        width: box.width,
        height: box.height,
        // No chip/box chrome — typeable glue text like the filename builder.
        child: TextField(
          controller: widget.controller,
          autofocus: true,
          maxLines: paragraph ? null : 1,
          minLines: 1,
          scrollPhysics: const NeverScrollableScrollPhysics(),
          keyboardType:
              paragraph ? TextInputType.multiline : TextInputType.text,
          textAlign: TextAlign.left,
          cursorColor: t.accent,
          cursorWidth: 1.2,
          cursorHeight: paragraph ? null : 13,
          style: style,
          decoration: InputDecoration(
            isDense: true,
            isCollapsed: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 4,
              vertical: paragraph ? 8 : 0,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
          ),
          onSubmitted: paragraph ? null : (_) => widget.onCommit(),
          onTapOutside: (_) => widget.onCommit(),
        ),
      ),
    );
  }
}

/// Narrow separator field used between caption-formula chips.
///
/// Plain typeable glue (no sunken chip/box), matching the filename builder.
class _GapSeparatorField extends StatefulWidget {
  const _GapSeparatorField({
    required this.controller,
    this.maxWidth,
    this.onFocusChanged,
    this.active = false,
    this.focusNode,
    this.onKeyEvent,
    this.forceFullWidth = false,
  });

  final TextEditingController controller;

  /// Widest this field may grow. A longer note wraps and grows taller.
  final double? maxWidth;
  final ValueChanged<bool>? onFocusChanged;
  final bool active;

  /// Optional external focus node (owned by parent).
  final FocusNode? focusNode;

  /// Arrow / key handling (e.g. jump to the next separator).
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;

  /// When true, always claim [maxWidth] (full structure row for long notes).
  final bool forceFullWidth;

  @override
  State<_GapSeparatorField> createState() => _GapSeparatorFieldState();
}

class _GapSeparatorFieldState extends State<_GapSeparatorField> {
  FocusNode? _ownedFocus;

  FocusNode get _focus {
    final external = widget.focusNode;
    if (external != null) return external;
    return _ownedFocus ??= FocusNode();
  }

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _ownedFocus = FocusNode();
    }
    widget.controller.addListener(_onTextChanged);
    _focus.addListener(_onFocusNodeChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _GapSeparatorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _ownedFocus)?.removeListener(_onFocusNodeChanged);
      if (oldWidget.focusNode == null) {
        _ownedFocus?.dispose();
        _ownedFocus = null;
      }
      if (widget.focusNode == null) {
        _ownedFocus = FocusNode();
      }
      _focus.addListener(_onFocusNodeChanged);
    }
  }

  void _onFocusNodeChanged() {
    if (!mounted) return;
    final node = widget.focusNode ?? _ownedFocus;
    if (node == null) return;
    widget.onFocusChanged?.call(node.hasFocus);
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    (widget.focusNode ?? _ownedFocus)?.removeListener(_onFocusNodeChanged);
    _ownedFocus?.dispose();
    _ownedFocus = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final raw = widget.controller.text;
    final empty = raw.isEmpty;
    final style = CaptionLayoutBuilderDialogState._structurePatternTextStyle
        .copyWith(color: FfTokens.sessionTx);
    final strut = CaptionLayoutBuilderDialogState._structurePatternStrut;
    final cap = _gapBoxCap(
      context,
      passed: widget.maxWidth,
    );
    final chipHeight = CaptionLayoutBuilderDialogState._snippetChipHeight;
    const cursorHeight =
        CaptionLayoutBuilderDialogState._structurePatternFontSize;

    Widget field({
      required double width,
      required double height,
      required bool multiline,
    }) {
      return SizedBox(
        width: width,
        height: height,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Text(
              raw,
              maxLines: multiline ? null : 1,
              softWrap: multiline,
              overflow: TextOverflow.clip,
              style: multiline ? style.copyWith(height: 1.35) : style,
              strutStyle: multiline ? null : strut,
            ),
            TextField(
              controller: widget.controller,
              focusNode: _focus,
              maxLines: multiline ? null : 1,
              scrollPhysics: const NeverScrollableScrollPhysics(),
              cursorColor: FfTokens.sessionTx,
              cursorWidth: 1.5,
              cursorHeight: cursorHeight,
              style: (multiline ? style.copyWith(height: 1.35) : style)
                  .copyWith(color: Colors.transparent),
              strutStyle: multiline ? null : strut,
              decoration: const InputDecoration(
                isDense: true,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.forceFullWidth) {
      final noteStyle = style.copyWith(height: 1.35);
      final box = GrowingTextBoxSize.measure(
        text: raw.isEmpty ? ' ' : raw,
        style: noteStyle,
        minWidth: 12,
        maxWidth: cap,
        minHeight: chipHeight,
        horizontalPad: 0,
        verticalPad: 0,
      );
      return field(
        width: math.max(12.0, cap - 2),
        height: box.height,
        multiline: true,
      );
    }

    final double width;
    if (empty) {
      width = focused ? 12.0 : 0.0;
    } else {
      final painter = TextPainter(
        text: TextSpan(text: raw, style: style),
        maxLines: 1,
        textDirection: TextDirection.ltr,
        strutStyle: strut,
      )..layout();
      width = (painter.width + 1).clamp(1.0, math.max(1.0, cap));
    }
    return field(width: width, height: chipHeight, multiline: false);
  }
}

double _gapBoxCap(BuildContext context, {double? passed}) {
  final inherited = _StructureTextLimit.maybeOf(context);
  final raw = passed ?? inherited ?? 400;
  if (!raw.isFinite || raw <= 0) return 400;
  return raw;
}

/// Full-width multiline field matching [_GapSeparatorField] / byline chip
/// borders: white fill, grey border, blue focus ring.
class _CaptionLayoutBorderedMultilineField extends StatefulWidget {
  const _CaptionLayoutBorderedMultilineField({
    required this.controller,
    this.minLines = 1,
    this.maxLines = 5,
    this.autofocus = false,
    this.hintText,
  });

  final TextEditingController controller;
  final int minLines;
  final int maxLines;
  final bool autofocus;
  final String? hintText;

  @override
  State<_CaptionLayoutBorderedMultilineField> createState() =>
      _CaptionLayoutBorderedMultilineFieldState();
}

class _CaptionLayoutBorderedMultilineFieldState
    extends State<_CaptionLayoutBorderedMultilineField> {
  late final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = _focus.hasFocus;
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      decoration: BoxDecoration(
        color: _ffOf(context).sunken,
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        border: Border.all(
          color: on ? _ffOf(context).accent : _ffOf(context).divider,
          width: on ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        autofocus: widget.autofocus,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        style: TextStyle(
          fontSize: 13,
          color: _ffOf(context).text.withValues(alpha: 0.88),
          height: 1.35,
        ),
        cursorColor: _ffOf(context).accent,
        cursorWidth: 1.2,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: widget.hintText,
          hintStyle: TextStyle(
            fontSize: 13,
            color: _ffOf(context).text.withValues(alpha: 0.40),
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

/// One segment in [_CaptionLayoutBuilderDialogState._optionSegmentedControl].
class _SegOption {
  const _SegOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
}

/// Small square button used inside byline chips (Aa, edit pencil, X). Matches
/// the location/date editors' chip-icon button visual language.
class _BylineChipIconButton extends StatelessWidget {
  const _BylineChipIconButton({
    required this.child,
    required this.onTap,
    required this.background,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback onTap;
  final Color background;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = SizedBox(
      width: 18,
      height: 18,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: _ffOf(context).divider),
          borderRadius: BorderRadius.circular(3),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(3),
          onTap: onTap,
          child: Center(child: child),
        ),
      ),
    );
    if (tooltip != null) return Tooltip(message: tooltip, child: btn);
    return btn;
  }
}

/// 38-character-wide separator input between byline chips. The byline model
/// only stores a single shared between-string, so every separator slot in the
/// row reads/writes the same controller — typing in any one updates them all.
///
/// Mirrors `_LocSeparatorInput` from the location editor: stable key, owns
/// its own [TextEditingController], resyncs in [didUpdateWidget] only when
/// unfocused, wraps everything in a [GestureDetector] so clicks anywhere in
/// the 38×28 box focus on the first try, and never includes the current
/// value in the parent key (which would lose focus on every keystroke and
/// trigger macOS system beeps when backspace bubbles to the OS).
class _BylineSeparatorInput extends StatefulWidget {
  const _BylineSeparatorInput({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_BylineSeparatorInput> createState() => _BylineSeparatorInputState();
}

class _VisibleSpaceTextController extends TextEditingController {
  _VisibleSpaceTextController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return spaceTokenSpan(text, style ?? const TextStyle());
  }
}

class _BylineSeparatorInputState extends State<_BylineSeparatorInput> {
  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ctrl = _VisibleSpaceTextController(
      text: widget.value,
    );
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _BylineSeparatorInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = widget.value;
    if (!_focus.hasFocus && value != _ctrl.text) {
      _ctrl.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  void _handleChanged(String value) {
    setState(() {});
    widget.onChanged(value);
  }

  void _onFocus() {
    if (!mounted) return;
    setState(() => _focused = _focus.hasFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = spaceTokenLabel(_ctrl.text);
    final idleStyle = TextStyle(
      fontFamily: FfTokens.fontFamily,
      fontSize: 12,
      height: 1,
      fontWeight: FontWeight.w600,
      color: _focused
          ? _ffOf(context).text
          : _ffOf(context).text.withValues(alpha: 0.72),
    );
    final measureText = visual.isEmpty ? ' ' : visual;
    final limit = _StructureTextLimit.maybeOf(context);
    final fieldSize = GrowingTextBoxSize.measure(
      text: measureText,
      style: idleStyle,
      minWidth: visual.isEmpty ? (_focused ? 28 : 8) : 12,
      maxWidth: limit ?? 400,
      horizontalPad: 6,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!_focus.hasFocus) _focus.requestFocus();
        },
        child: SizedBox(
          width: fieldSize.width,
          height: fieldSize.height,
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            style: idleStyle,
            textAlign: TextAlign.center,
            textAlignVertical: TextAlignVertical.center,
            maxLines: null,
            cursorWidth: 1.2,
            cursorColor: _ffOf(context).accent,
            decoration: const InputDecoration(
              isDense: true,
              isCollapsed: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            onChanged: _handleChanged,
          ),
        ),
      ),
    );
  }

}

/// Wider labeled text field used at the start (Prefix) and end (Suffix) of
/// the byline editor's chip row. Renders the controller-bound input together
/// with a small "Prefix" / "Suffix" caption so users know what slot they're
/// in without having to read documentation.
class _BylineWideInput extends StatelessWidget {
  const _BylineWideInput({
    required this.label,
    required this.controller,
  });

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: _GapSeparatorField(controller: controller),
    );
  }
}

/// Labeled inline text field for custom-typed byline values.
class _BylineLabeledInput extends StatelessWidget {
  const _BylineLabeledInput({
    required this.label,
    required this.controller,
  });

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: _ffOf(context).textSecondary,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 180,
          height: 24,
          child: TextField(
            controller: controller,
            style: const TextStyle(fontSize: 11),
            textAlign: TextAlign.left,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              filled: true,
              fillColor: _ffOf(context).sunken,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: _ffOf(context).divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: _ffOf(context).text.withValues(alpha: 0.45)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tiny "+ Custom text" button shown at the right edge of the byline chip row.
/// Custom-text chips are the only kind that supports multiple instances, so unlike
/// name/credit/copyright they're added on demand rather than always shown.
class _BylineAddCustomButton extends StatelessWidget {
  const _BylineAddCustomButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Add custom text field',
      child: Material(
        color: _ffOf(context).sunken,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: _ffOf(context).divider),
          borderRadius: BorderRadius.circular(4),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PhosphorIcon(PhosphorIconsRegular.plus, size: 11, color: _ffOf(context).textSecondary),
                const SizedBox(width: 3),
                Text(
                  'Custom text',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: _ffOf(context).text.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
