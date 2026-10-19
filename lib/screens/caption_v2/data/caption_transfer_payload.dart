import 'dart:convert';

import '../../../caption_style/caption_text_normalize.dart';

/// One roster button that was on when a caption was copied.
class CaptionClickPlayer {
  const CaptionClickPlayer({
    required this.fullName,
    required this.isHome,
    this.jerseyNumber,
    this.playerId,
    this.primary = false,
  });

  final String fullName;
  final String? jerseyNumber;
  final String? playerId;
  final bool isHome;

  /// True for the player who was the main focus (first selected subject).
  /// List order still puts that player first; this flag keeps the focus if
  /// a teammate is stored ahead of them.
  final bool primary;

  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        'isHome': isHome,
        if (jerseyNumber != null) 'jerseyNumber': jerseyNumber,
        if (playerId != null) 'playerId': playerId,
        if (primary) 'primary': true,
      };

  static CaptionClickPlayer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = (raw['fullName'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final jersey = raw['jerseyNumber']?.toString().trim();
    final id = raw['playerId']?.toString().trim();
    return CaptionClickPlayer(
      fullName: name,
      isHome: raw['isHome'] == true,
      jerseyNumber: jersey == null || jersey.isEmpty ? null : jersey,
      playerId: id == null || id.isEmpty ? null : id,
      primary: raw['primary'] == true,
    );
  }
}

/// Buttons that built a caption, so paste can press them again.
class CaptionClickSnapshot {
  const CaptionClickSnapshot({
    this.players = const [],
    this.verb,
    this.customVerb = '',
    this.rbi = 0,
    this.base,
    this.celebration,
    this.modifiers = const {},
    this.preGame = false,
    this.postGame = false,
    this.inning,
    this.timingHalf,
    this.teamPlayersIsHome,
    this.teamSubjectKind,
    this.withTeammatesIsHome,
  });

  final List<CaptionClickPlayer> players;
  final String? verb;
  final String customVerb;
  final int rbi;
  final String? base;
  final String? celebration;
  final Map<String, String> modifiers;
  final bool preGame;
  final bool postGame;
  final int? inning;
  final String? timingHalf;
  final bool? teamPlayersIsHome;
  final String? teamSubjectKind;
  final bool? withTeammatesIsHome;

  bool get hasButtons =>
      players.isNotEmpty ||
      (verb?.trim().isNotEmpty ?? false) ||
      customVerb.trim().isNotEmpty ||
      teamPlayersIsHome != null ||
      withTeammatesIsHome != null;

  Map<String, dynamic> toJson() => {
        'players': players.map((player) => player.toJson()).toList(),
        if (verb != null) 'verb': verb,
        'customVerb': customVerb,
        'rbi': rbi,
        if (base != null) 'base': base,
        if (celebration != null) 'celebration': celebration,
        if (modifiers.isNotEmpty) 'modifiers': modifiers,
        'preGame': preGame,
        'postGame': postGame,
        if (inning != null) 'inning': inning,
        if (timingHalf != null) 'timingHalf': timingHalf,
        if (teamPlayersIsHome != null) 'teamPlayersIsHome': teamPlayersIsHome,
        if (teamSubjectKind != null) 'teamSubjectKind': teamSubjectKind,
        if (withTeammatesIsHome != null)
          'withTeammatesIsHome': withTeammatesIsHome,
      };

  static CaptionClickSnapshot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final players = <CaptionClickPlayer>[];
    final rawPlayers = raw['players'];
    if (rawPlayers is List) {
      for (final item in rawPlayers) {
        final player = CaptionClickPlayer.fromJson(item);
        if (player != null) players.add(player);
      }
    }
    final modifiers = <String, String>{};
    final rawModifiers = raw['modifiers'];
    if (rawModifiers is Map) {
      for (final entry in rawModifiers.entries) {
        final value = entry.value?.toString().trim() ?? '';
        if (value.isEmpty) continue;
        modifiers[entry.key.toString()] = value;
      }
    }
    final verb = raw['verb']?.toString().trim();
    final custom = (raw['customVerb'] ?? '').toString();
    final teamRaw = raw['teamPlayersIsHome'];
    final teammatesRaw = raw['withTeammatesIsHome'];
    final snapshot = CaptionClickSnapshot(
      players: players,
      verb: verb == null || verb.isEmpty ? null : verb,
      customVerb: custom,
      rbi: raw['rbi'] is int ? raw['rbi'] as int : int.tryParse('${raw['rbi']}') ?? 0,
      base: raw['base']?.toString(),
      celebration: raw['celebration']?.toString(),
      modifiers: modifiers,
      preGame: raw['preGame'] == true,
      postGame: raw['postGame'] == true,
      inning: raw['inning'] is int
          ? raw['inning'] as int
          : int.tryParse('${raw['inning'] ?? ''}'),
      timingHalf: raw['timingHalf']?.toString(),
      teamPlayersIsHome: teamRaw is bool ? teamRaw : null,
      teamSubjectKind: raw['teamSubjectKind']?.toString(),
      withTeammatesIsHome: teammatesRaw is bool ? teammatesRaw : null,
    );
    return snapshot.hasButtons ? snapshot : null;
  }
}

class CaptionTransferPayload {
  const CaptionTransferPayload({
    required this.caption,
    this.personality = '',
    this.headline = '',
    this.keywords = '',
    this.photographerName = '',
    this.clicks,
  });

  static const int currentVersion = 1;

  final String caption;
  final String personality;
  final String headline;
  final String keywords;

  /// Photographer baked into [caption] when it was copied.
  ///
  /// Paste uses this to swap in the destination photo's IPTC photographer so
  /// two shooters covering the same moment keep their own credit.
  final String photographerName;

  /// Players, verb, and other buttons that produced [caption].
  final CaptionClickSnapshot? clicks;

  Map<String, dynamic> toJson() {
    return {
      'version': currentVersion,
      'caption': caption,
      'personality': personality,
      'headline': headline,
      'keywords': keywords,
      'photographerName': photographerName,
      if (clicks != null) 'clicks': clicks!.toJson(),
    };
  }

  /// Caption text with [sourcePhotographer] replaced by the destination photo's
  /// IPTC photographer. The rest of the caption, including the agency credit,
  /// stays as copied.
  static String captionForDestinationPhotographer({
    required String caption,
    required String sourcePhotographer,
    required String destinationPhotographer,
    bool removeDiacritics = false,
  }) {
    final source = sourcePhotographer.trim();
    final destination = destinationPhotographer.trim();
    if (caption.isEmpty || source.isEmpty || destination.isEmpty) {
      return caption;
    }
    if (source.toLowerCase() == destination.toLowerCase()) return caption;

    final match = _lastNameMatch(caption, source);
    if (match == null) return caption;

    final matched = caption.substring(match.start, match.end);
    var replacement = destination;
    final captionStrippedName =
        CaptionTextNormalize.stripDiacritics(matched) == matched &&
            CaptionTextNormalize.stripDiacritics(source) != source;
    if (removeDiacritics || captionStrippedName) {
      replacement = CaptionTextNormalize.stripDiacritics(replacement);
    }
    if (_isAllCaps(matched)) {
      replacement = replacement.toUpperCase();
    }
    return caption.replaceRange(match.start, match.end, replacement);
  }

  String encode() => jsonEncode(toJson());

  static CaptionTransferPayload? decode(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return CaptionTransferPayload(caption: raw);
    }
    if (decoded is! Map) {
      return CaptionTransferPayload(caption: raw);
    }
    final map = decoded;

    String value(List<String> keys) {
      for (final key in keys) {
        final candidate = map[key];
        if (candidate is String) return candidate;
        if (candidate is List) {
          return candidate.map((item) => item.toString()).join(';');
        }
      }
      return '';
    }

    final caption = value(const [
      'caption',
      'Caption',
      'IPTC:Description',
      'Description',
      'Caption-Abstract',
      'IPTC:Caption-Abstract',
      'XMP:Description',
      'ImageDescription',
    ]);
    if (caption.isEmpty) return null;

    return CaptionTransferPayload(
      caption: caption,
      personality: value(const [
        'personality',
        'Personality',
        'XMP-getty:Personality',
      ]),
      headline: value(const ['headline', 'Headline', 'IPTC:Headline']),
      keywords: value(const [
        'keywords',
        'Keywords',
        'IPTC:Keywords',
        'XMP:Subject',
      ]),
      photographerName: value(const [
        'photographerName',
        'Photographer',
        'Creator',
        'IPTC:By-line',
        'By-line',
        'Byline',
      ]),
      clicks: CaptionClickSnapshot.fromJson(map['clicks']),
    );
  }
}

class _NameSpan {
  const _NameSpan(this.start, this.end);

  final int start;
  final int end;
}

_NameSpan? _lastNameMatch(String caption, String name) {
  final direct = _lastBoundedMatch(caption, name);
  if (direct != null) return direct;
  final foldedName = CaptionTextNormalize.stripDiacritics(name);
  if (foldedName.toLowerCase() == name.toLowerCase()) return null;
  return _lastBoundedFoldedMatch(caption, foldedName);
}

_NameSpan? _lastBoundedMatch(String caption, String needle) {
  if (needle.isEmpty || needle.length > caption.length) return null;
  _NameSpan? last;
  for (var i = 0; i <= caption.length - needle.length; i++) {
    final end = i + needle.length;
    if (!_equalsIgnoreCase(caption.substring(i, end), needle)) continue;
    if (!_bounded(caption, i, end)) continue;
    last = _NameSpan(i, end);
  }
  return last;
}

_NameSpan? _lastBoundedFoldedMatch(
  String caption,
  String foldedNeedle,
) {
  final folded = StringBuffer();
  final origin = <int>[];
  for (var i = 0; i < caption.length; i++) {
    final piece = CaptionTextNormalize.stripDiacritics(caption[i]);
    for (var j = 0; j < piece.length; j++) {
      folded.write(piece[j]);
      origin.add(i);
    }
  }
  final haystack = folded.toString();
  final match = _lastBoundedMatch(haystack, foldedNeedle);
  if (match == null || origin.isEmpty) return null;
  final start = origin[match.start];
  final end = origin[match.end - 1] + 1;
  if (!_bounded(caption, start, end)) return null;
  return _NameSpan(start, end);
}

bool _equalsIgnoreCase(String a, String b) =>
    a.toLowerCase() == b.toLowerCase();

bool _bounded(String text, int start, int end) {
  return !_isLetterAt(text, start - 1) && !_isLetterAt(text, end);
}

bool _isLetterAt(String text, int index) {
  if (index < 0 || index >= text.length) return false;
  final char = text[index];
  return char.toLowerCase() != char.toUpperCase();
}

bool _isAllCaps(String text) {
  var sawLetter = false;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (char.toLowerCase() == char.toUpperCase()) continue;
    sawLetter = true;
    if (char != char.toUpperCase()) return false;
  }
  return sawLetter;
}
