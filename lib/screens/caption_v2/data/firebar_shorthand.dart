import 'package:quick_cap/services/mlb_api_service.dart';

import '../../../caption_style/caption_text_normalize.dart';

enum FirebarMatchKind { player, verb }

/// A roster or verb hit for shorthand matching / dropdown rows.
class FirebarMatch {
  const FirebarMatch.player({
    required this.player,
    required this.isHome,
  })  : kind = FirebarMatchKind.player,
        verbKey = null;

  const FirebarMatch.verb(this.verbKey)
      : kind = FirebarMatchKind.verb,
        player = null,
        isHome = null;

  final FirebarMatchKind kind;
  final Player? player;
  final bool? isHome;
  final String? verbKey;

  String get key => kind == FirebarMatchKind.player
      ? 'player:${isHome == true ? 'home' : 'away'}:'
          '${player?.playerId ?? ''}:${player?.jerseyNumber ?? ''}:'
          '${player?.fullName ?? ''}'
      : 'verb:$verbKey';
}

/// One Firebar shorthand token after matching against this game's roster/verbs.
class FirebarShorthandToken {
  const FirebarShorthandToken({
    required this.typed,
    required this.display,
    required this.completed,
    required this.error,
    this.errorReason,
    this.resolved,
    this.matches = const [],
    this.code,
  });

  /// What the user actually typed (for un-complete on Backspace).
  final String typed;

  /// Inline text shown in the line (completed label/name, or typed text).
  final String display;

  final bool completed;
  final bool error;
  final String? errorReason;
  final FirebarMatch? resolved;
  final List<FirebarMatch> matches;
  final String? code;

  bool get isPlayer => resolved?.kind == FirebarMatchKind.player;
  bool get isVerb => resolved?.kind == FirebarMatchKind.verb;

  FirebarShorthandToken copyWith({
    String? typed,
    String? display,
    bool? completed,
    bool? error,
    String? errorReason,
    FirebarMatch? resolved,
    List<FirebarMatch>? matches,
    String? code,
    bool clearResolved = false,
    bool clearErrorReason = false,
  }) {
    return FirebarShorthandToken(
      typed: typed ?? this.typed,
      display: display ?? this.display,
      completed: completed ?? this.completed,
      error: error ?? this.error,
      errorReason: clearErrorReason ? null : (errorReason ?? this.errorReason),
      resolved: clearResolved ? null : (resolved ?? this.resolved),
      matches: matches ?? this.matches,
      code: code ?? this.code,
    );
  }
}

/// Live preview of what Return would apply.
class FirebarShorthandPreview {
  const FirebarShorthandPreview({
    this.subjects = const [],
    this.action,
    this.opponents = const [],
    this.errorReason,
    this.errorTokenIndex,
  });

  final List<FirebarMatch> subjects;
  final FirebarMatch? action;
  final List<FirebarMatch> opponents;
  final String? errorReason;
  final int? errorTokenIndex;

  bool get hasContent =>
      subjects.isNotEmpty || action != null || opponents.isNotEmpty;

  /// True when Return can write the selection. Ambiguous tokens set
  /// [errorTokenIndex] without a lecture message.
  bool get canApply =>
      errorReason == null && errorTokenIndex == null && hasContent;
}

/// Result of parsing / auto-completing one Firebar shorthand line.
class FirebarShorthandLine {
  const FirebarShorthandLine({
    required this.tokens,
    required this.displayLine,
    required this.trailingSpace,
    required this.preview,
    required this.activeTokenIndex,
  });

  final List<FirebarShorthandToken> tokens;
  final String displayLine;
  final bool trailingSpace;
  final FirebarShorthandPreview preview;
  final int activeTokenIndex;

  FirebarShorthandToken? get activeToken {
    if (tokens.isEmpty) return null;
    if (activeTokenIndex < 0 || activeTokenIndex >= tokens.length) return null;
    return tokens[activeTokenIndex];
  }

  List<FirebarMatch> get activeMatches => activeToken?.matches ?? const [];
}

class FirebarVerbCatalogEntry {
  const FirebarVerbCatalogEntry({
    required this.key,
    required this.label,
    required this.matchTexts,
  });

  final String key;
  final String label;
  final List<String> matchTexts;
}

/// Photo Mechanic–style shorthand caption line for FloFile Firebar.
class FirebarShorthand {
  FirebarShorthand({
    required this.homeRoster,
    required this.awayRoster,
    required this.verbs,
    required this.homeAbbrev,
    required this.awayAbbrev,
    this.playerLastName,
    this.excludedPlayerKeys = const {},
  });

  final List<Player> homeRoster;
  final List<Player> awayRoster;
  final List<FirebarVerbCatalogEntry> verbs;
  final String homeAbbrev;
  final String awayAbbrev;
  final String Function(Player player)? playerLastName;

  /// Player match keys already picked (chips / selection) — omit from matches.
  final Set<String> excludedPlayerKeys;

  static String normalize(String value) =>
      CaptionTextNormalize.stripDiacritics(value)
          .replaceAll('\u00A0', ' ')
          .trim()
          .toLowerCase();

  static final RegExp jerseyToken = RegExp(r'^([hv])?(\d+)$');

  /// Parse [rawLine] into tokens with unique auto-complete applied.
  ///
  /// [suppressAutoCompleteFor] keeps that exact typed token open after
  /// Backspace un-completes it, so unique matches don't snap closed again.
  FirebarShorthandLine parse(
    String rawLine, {
    List<FirebarShorthandToken>? prior,
    bool finalizeOpenNumber = false,
    String? suppressAutoCompleteFor,
  }) {
    // Split on ASCII spaces only — completed names use NBSP so they stay one token.
    final trailingSpace = rawLine.endsWith(' ') && rawLine.trimRight().isNotEmpty;
    final trimmed = rawLine.replaceAll(RegExp(r' +'), ' ').trim();
    final parts = trimmed.isEmpty ? <String>[] : trimmed.split(' ');

    // Also block players already resolved earlier on this same line.
    final blocked = Set<String>.from(excludedPlayerKeys);
    final tokens = <FirebarShorthandToken>[];
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final isLast = i == parts.length - 1;
      final forceFinalize =
          !isLast || trailingSpace || (isLast && finalizeOpenNumber);
      final priorTok = _priorFor(prior, i, part);
      final suppress = isLast &&
          suppressAutoCompleteFor != null &&
          normalize(part) == normalize(suppressAutoCompleteFor);
      final token = _resolveToken(
        part,
        priorTok,
        forceFinalize: forceFinalize,
        suppressAutoComplete: suppress,
        blockedPlayers: blocked,
      );
      tokens.add(token);
      final resolved = token.resolved;
      if (token.completed &&
          !token.error &&
          resolved != null &&
          resolved.kind == FirebarMatchKind.player) {
        blocked.add(resolved.key);
      }
    }

    final collapsed = _collapseAbsorbedNameFragments(
      _collapseExtraActions(tokens),
    );
    final activeIndex = collapsed.isEmpty
        ? -1
        : (trailingSpace ? collapsed.length : collapsed.length - 1);
    // Finalize open jersey prefixes on space or Return only — not every keystroke.
    final preview = _buildPreview(
      collapsed,
      finalize: finalizeOpenNumber || trailingSpace,
    );
    final display = _displayLine(collapsed, trailingSpace);

    return FirebarShorthandLine(
      tokens: collapsed,
      displayLine: display,
      trailingSpace: trailingSpace,
      preview: preview,
      activeTokenIndex:
          activeIndex.clamp(-1, collapsed.isEmpty ? -1 : collapsed.length - 1),
    );
  }

  /// Replace the active token with a menu choice (`h34`, `Faceoff`, …).
  /// Always leaves a trailing space so the next token is ready to type.
  FirebarShorthandLine pickMatch(
    FirebarShorthandLine current,
    FirebarMatch match,
  ) {
    final picked = _tokenFromPick(
      match,
      typed: current.activeToken?.typed ?? '',
    );
    if (current.tokens.isEmpty) {
      return parse('${picked.display} ', prior: [picked]);
    }
    final index = current.activeTokenIndex < 0
        ? current.tokens.length - 1
        : current.activeTokenIndex;
    final next = [...current.tokens];
    next[index] = picked;
    final line = next.map((t) => t.display).join(' ');
    return parse('$line ', prior: next);
  }

  /// Dropdown label: `h34 Auston Matthews (TOR)` / `Faceoff`.
  String matchLabel(FirebarMatch result) {
    if (result.kind == FirebarMatchKind.verb) {
      final key = result.verbKey ?? '';
      for (final verb in verbs) {
        if (verb.key == key) return verb.label;
      }
      return key;
    }
    final player = result.player;
    if (player == null) return '';
    final side = result.isHome == true ? 'h' : 'v';
    final jersey = (player.jerseyNumber ?? '').trim();
    final abbr = result.isHome == true ? homeAbbrev : awayAbbrev;
    final team = abbr.isEmpty ? '' : ' ($abbr)';
    return '$side$jersey ${player.fullName}$team';
  }

  String insertCode(FirebarMatch result) {
    if (result.kind == FirebarMatchKind.verb) {
      final key = result.verbKey ?? '';
      for (final verb in verbs) {
        if (verb.key == key) return verb.label;
      }
      return key;
    }
    final player = result.player;
    if (player == null) return '';
    final side = result.isHome == true ? 'h' : 'v';
    final jersey = (player.jerseyNumber ?? '').trim();
    return '$side$jersey';
  }

  FirebarShorthandToken? _priorFor(
    List<FirebarShorthandToken>? prior,
    int index,
    String part,
  ) {
    if (prior == null || index >= prior.length) return null;
    final old = prior[index];
    final partN = normalize(part);
    final displayN = normalize(old.display);
    final typedN = normalize(old.typed);
    if (old.completed &&
        (displayN == partN ||
            displayN.startsWith(partN) ||
            partN.startsWith(typedN))) {
      return old;
    }
    if (typedN == partN) return old;
    return null;
  }

  FirebarShorthandToken _resolveToken(
    String raw,
    FirebarShorthandToken? prior, {
    required bool forceFinalize,
    bool suppressAutoComplete = false,
    Set<String> blockedPlayers = const {},
  }) {
    final typed = raw;
    final lower = normalize(typed);
    if (lower.isEmpty) {
      return FirebarShorthandToken(
        typed: typed,
        display: typed,
        completed: false,
        error: false,
      );
    }

    if (prior != null &&
        prior.completed &&
        prior.resolved != null &&
        !prior.error) {
      // Field was expanded to the label; further letters from finishing the
      // word (Faceoff + e) must not stick on the end.
      final absorbed = _absorbExpandedKeystrokes(prior, typed);
      if (absorbed != null) {
        return prior.copyWith(
          typed: absorbed,
          display: prior.display,
          error: false,
          clearErrorReason: true,
        );
      }
      if (_completedStillFits(prior, typed)) {
        return prior.copyWith(
          typed: _preserveCompletionSeed(prior, typed),
          display: prior.display,
        );
      }
      return prior.copyWith(
        typed: typed,
        display: typed,
        completed: false,
        error: true,
        errorReason: 'doesn’t match ${prior.display}',
        clearResolved: true,
        matches: const [],
      );
    }

    final jersey = jerseyToken.firstMatch(lower);
    if (jersey != null) {
      return _resolveJersey(
        typed: typed,
        side: jersey.group(1),
        digits: jersey.group(2)!,
        forceFinalize: forceFinalize,
        suppressAutoComplete: suppressAutoComplete,
        blockedPlayers: blockedPlayers,
      );
    }

    if (RegExp(r'^\d+$').hasMatch(lower)) {
      return _resolveJersey(
        typed: typed,
        side: null,
        digits: lower,
        forceFinalize: forceFinalize,
        suppressAutoComplete: suppressAutoComplete,
        blockedPlayers: blockedPlayers,
      );
    }

    return _resolveNameOrVerb(
      typed: typed,
      forceFinalize: forceFinalize,
      suppressAutoComplete: suppressAutoComplete,
      blockedPlayers: blockedPlayers,
    );
  }

  bool _completedStillFits(FirebarShorthandToken prior, String typed) {
    final completed = normalize(prior.display);
    final t = normalize(typed);
    if (completed.startsWith(t) || completed == t) return true;
    final original = normalize(prior.typed);
    if (t.startsWith(original) && completed.startsWith(t)) return true;
    return false;
  }

  /// Keep the short typed seed after the text field syncs to the full label,
  /// so later keystrokes can still be absorbed as finishing that word.
  String _preserveCompletionSeed(FirebarShorthandToken prior, String typed) {
    final completed = normalize(prior.display);
    final t = normalize(typed);
    final seed = normalize(prior.typed);
    if (t == completed &&
        seed.isNotEmpty &&
        seed.length < completed.length &&
        completed.startsWith(seed)) {
      return prior.typed;
    }
    return typed;
  }

  /// After auto-expand (`fa` → `Faceoff`), ignore letters typed onto the end of
  /// the expanded label (`Faceoffe`) when they finish the same word — or when
  /// they are stray trailing junk before a space starts the next token.
  String? _absorbExpandedKeystrokes(FirebarShorthandToken prior, String typed) {
    final completed = normalize(prior.display);
    final t = normalize(typed);
    if (!t.startsWith(completed) || t.length <= completed.length) return null;
    final extras = t.substring(completed.length);
    if (!RegExp(r'^[a-z0-9]+$').hasMatch(extras)) return null;

    final seed = normalize(prior.typed);
    if (seed.isNotEmpty &&
        seed.length < completed.length &&
        completed.startsWith(seed)) {
      final remainder = completed.substring(seed.length);
      if (remainder.startsWith(extras)) {
        return seed + extras;
      }
    }

    // Seed was already replaced by the full label (field sync). Drop trailing
    // letters so "Faceoffe" snaps back to "Faceoff".
    return prior.typed.isNotEmpty ? prior.typed : prior.display;
  }

  /// "Nick" → "Nick Paul" then a leftover "Paul" token from typing the space
  /// in the name — drop the duplicate same-player fragment.
  List<FirebarShorthandToken> _collapseAbsorbedNameFragments(
    List<FirebarShorthandToken> tokens,
  ) {
    if (tokens.length < 2) return tokens;
    final out = <FirebarShorthandToken>[];
    for (final token in tokens) {
      if (out.isNotEmpty) {
        final prev = out.last;
        if (prev.completed &&
            prev.isPlayer &&
            !prev.error &&
            prev.resolved?.player != null) {
          final prevPlayer = prev.resolved!.player!;
          final frag = normalize(token.typed);
          final prevWords = normalize(prev.display)
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty);
          final samePlayer = token.resolved?.player == prevPlayer ||
              (token.matches.length == 1 &&
                  token.matches.single.player == prevPlayer);
          if (frag.isNotEmpty &&
              prevWords.contains(frag) &&
              (samePlayer || (!token.completed && token.matches.every(
                    (m) => m.player == prevPlayer,
                  )))) {
            continue;
          }
        }
      }
      out.add(token);
    }
    return out;
  }

  FirebarShorthandToken _resolveJersey({
    required String typed,
    required String? side,
    required String digits,
    required bool forceFinalize,
    bool suppressAutoComplete = false,
    Set<String> blockedPlayers = const {},
  }) {
    final prefix = _jerseyCandidates(
      side: side,
      digits: digits,
      blockedPlayers: blockedPlayers,
    );
    final exact = prefix
        .where((c) => (c.player?.jerseyNumber ?? '').trim() == digits)
        .toList(growable: false);

    if (prefix.isEmpty) {
      final label = side == null ? '#$digits' : '$side$digits';
      return FirebarShorthandToken(
        typed: typed,
        display: typed,
        completed: false,
        error: true,
        errorReason: 'no player $label',
        matches: const [],
      );
    }

    // Complete immediately only when the exact jersey is unique and no longer
    // number shares this prefix (h34 yes; h3 while #34 exists no; h8 while
    // #81/#82/#88 exist no).
    if (!suppressAutoComplete && exact.length == 1 && prefix.length == 1) {
      return _completePlayer(typed, exact.first);
    }

    // Space / Return: take the exact jersey even if longer numbers also match
    // the prefix (h8 → #8).
    if (forceFinalize) {
      if (exact.length == 1) {
        return _completePlayer(typed, exact.first);
      }
      if (exact.length > 1 && side == null) {
        // Keep the dropdown open — never lecture about typing h/v.
        return FirebarShorthandToken(
          typed: typed,
          display: typed,
          completed: false,
          error: false,
          matches: [
            ...exact.where((c) => c.isHome == true),
            ...exact.where((c) => c.isHome == false),
          ],
        );
      }
      if (exact.isEmpty) {
        return FirebarShorthandToken(
          typed: typed,
          display: typed,
          completed: false,
          error: true,
          errorReason: 'no player ${side ?? ''}#$digits',
          matches: prefix,
        );
      }
      if (exact.length > 1) {
        return FirebarShorthandToken(
          typed: typed,
          display: typed,
          completed: false,
          error: true,
          errorReason: 'ambiguous $side$digits',
          matches: exact,
        );
      }
    }

    final shown = side == null
        ? [
            ...exact.where((c) => c.isHome == true),
            ...exact.where((c) => c.isHome == false),
            ...prefix.where((c) => !exact.any((e) => e.key == c.key) && c.isHome == true),
            ...prefix.where((c) => !exact.any((e) => e.key == c.key) && c.isHome == false),
          ]
        : prefix;

    return FirebarShorthandToken(
      typed: typed,
      display: typed,
      completed: false,
      error: false,
      matches: shown,
      code: side == null ? digits : '$side$digits',
    );
  }

  List<FirebarMatch> _jerseyCandidates({
    required String? side,
    required String digits,
    Set<String> blockedPlayers = const {},
  }) {
    final out = <FirebarMatch>[];
    if (side != 'v') {
      for (final player in homeRoster) {
        final jersey = (player.jerseyNumber ?? '').trim();
        if (jersey == digits || jersey.startsWith(digits)) {
          final match = FirebarMatch.player(player: player, isHome: true);
          if (blockedPlayers.contains(match.key)) continue;
          out.add(match);
        }
      }
    }
    if (side != 'h') {
      for (final player in awayRoster) {
        final jersey = (player.jerseyNumber ?? '').trim();
        if (jersey == digits || jersey.startsWith(digits)) {
          final match = FirebarMatch.player(player: player, isHome: false);
          if (blockedPlayers.contains(match.key)) continue;
          out.add(match);
        }
      }
    }
    return out;
  }

  FirebarShorthandToken _resolveNameOrVerb({
    required String typed,
    required bool forceFinalize,
    bool suppressAutoComplete = false,
    Set<String> blockedPlayers = const {},
  }) {
    final q = normalize(typed);
    final players = _playerNameMatches(q, blockedPlayers: blockedPlayers);
    final verbHits = _verbMatches(q);

    // Actions complete as soon as exactly one verb remains (fa → Faceoff).
    if (!suppressAutoComplete && verbHits.length == 1 && players.isEmpty) {
      return _completeVerb(typed, verbHits.first);
    }

    // Player names: exact last/first/full name completes immediately; otherwise
    // wait until the typed prefix is unique and at least 5 letters (matt vs matth).
    if (!suppressAutoComplete && players.length == 1 && verbHits.isEmpty) {
      final player = players.first.player!;
      if (_isExactPlayerName(player, q) || q.length >= 5) {
        return _completePlayer(typed, players.first);
      }
    }

    if (players.isEmpty && verbHits.isEmpty) {
      return FirebarShorthandToken(
        typed: typed,
        display: typed,
        completed: false,
        error: true,
        errorReason: 'unrecognized “$typed”',
        matches: const [],
      );
    }

    final matches = <FirebarMatch>[
      ...players.where((p) => p.isHome == true),
      ...verbHits.map((v) => FirebarMatch.verb(v.key)),
      ...players.where((p) => p.isHome == false),
    ];

    if (forceFinalize && matches.length != 1) {
      return FirebarShorthandToken(
        typed: typed,
        display: typed,
        completed: false,
        error: true,
        errorReason: 'ambiguous “$typed”',
        matches: matches,
      );
    }

    if (forceFinalize && players.length == 1 && verbHits.isEmpty) {
      return _completePlayer(typed, players.first);
    }

    return FirebarShorthandToken(
      typed: typed,
      display: typed,
      completed: false,
      error: false,
      matches: matches,
    );
  }

  bool _isExactPlayerName(Player player, String q) {
    final name = normalize(player.fullName);
    final first = normalize(player.firstName);
    final last = normalize(
      playerLastName?.call(player) ?? _fallbackLastName(player),
    );
    return name == q || first == q || last == q;
  }

  List<FirebarMatch> _playerNameMatches(
    String q, {
    Set<String> blockedPlayers = const {},
  }) {
    final out = <FirebarMatch>[];
    for (final player in homeRoster) {
      if (!_playerMatchesQuery(player, q)) continue;
      final match = FirebarMatch.player(player: player, isHome: true);
      if (blockedPlayers.contains(match.key)) continue;
      out.add(match);
    }
    for (final player in awayRoster) {
      if (!_playerMatchesQuery(player, q)) continue;
      final match = FirebarMatch.player(player: player, isHome: false);
      if (blockedPlayers.contains(match.key)) continue;
      out.add(match);
    }
    return out;
  }

  bool _playerMatchesQuery(Player player, String q) {
    if (q.isEmpty) return false;
    final name = normalize(player.fullName);
    final first = normalize(player.firstName);
    final last = normalize(
      playerLastName?.call(player) ?? _fallbackLastName(player),
    );
    return last.startsWith(q) ||
        first.startsWith(q) ||
        name.startsWith(q) ||
        name.contains(q) ||
        last.contains(q);
  }

  static String _fallbackLastName(Player player) {
    final parts = player.fullName.trim().split(RegExp(r'\s+'));
    return parts.length <= 1 ? player.fullName : parts.last;
  }

  List<FirebarVerbCatalogEntry> _verbMatches(String q) {
    if (q.isEmpty) return const [];
    return [
      for (final verb in verbs)
        if (_verbMatchesQuery(verb, q)) verb,
    ];
  }

  bool _verbMatchesQuery(FirebarVerbCatalogEntry verb, String q) {
    for (final text in verb.matchTexts) {
      final n = normalize(text);
      if (n.isEmpty) continue;
      if (n == q || n.startsWith(q)) return true;
      final words =
          n.split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty);
      if (words.any((w) => w == q || w.startsWith(q))) return true;
    }
    return false;
  }

  /// Spaces inside a completed name would start a new Firebar token — use NBSP.
  static String _lineSafeName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), '\u00A0');

  FirebarShorthandToken _completePlayer(String typed, FirebarMatch result) {
    final player = result.player!;
    final display = jerseyToken.hasMatch(normalize(typed))
        ? _lineSafeName(player.fullName)
        : _lineSafeName(_shortPlayerDisplay(player, typed));
    return FirebarShorthandToken(
      typed: typed,
      display: display,
      completed: true,
      error: false,
      resolved: result,
      matches: [result],
      code: insertCode(result),
    );
  }

  String _shortPlayerDisplay(Player player, String typed) {
    final last = playerLastName?.call(player) ?? _fallbackLastName(player);
    final q = normalize(typed);
    if (normalize(last).startsWith(q)) return last;
    return player.fullName;
  }

  FirebarShorthandToken _completeVerb(
    String typed,
    FirebarVerbCatalogEntry verb,
  ) {
    final display = _lineSafeName(verb.label);
    return FirebarShorthandToken(
      typed: typed,
      display: display,
      completed: true,
      error: false,
      resolved: FirebarMatch.verb(verb.key),
      matches: [FirebarMatch.verb(verb.key)],
      code: verb.label,
    );
  }

  FirebarShorthandToken _tokenFromPick(
    FirebarMatch match, {
    required String typed,
  }) {
    if (match.kind == FirebarMatchKind.verb) {
      final key = match.verbKey ?? '';
      String label = key;
      for (final verb in verbs) {
        if (verb.key == key) {
          label = verb.label;
          break;
        }
      }
      return FirebarShorthandToken(
        typed: typed.isEmpty ? label : typed,
        display: _lineSafeName(label),
        completed: true,
        error: false,
        resolved: match,
        matches: [match],
        code: label,
      );
    }
    final code = insertCode(match);
    return FirebarShorthandToken(
      typed: typed.isEmpty ? code : typed,
      display: code,
      completed: true,
      error: false,
      resolved: match,
      matches: [match],
      code: code,
    );
  }

  /// Second action replaces the first completed verb token.
  List<FirebarShorthandToken> _collapseExtraActions(
    List<FirebarShorthandToken> tokens,
  ) {
    final verbIndexes = <int>[
      for (var i = 0; i < tokens.length; i++)
        if (tokens[i].resolved?.kind == FirebarMatchKind.verb) i,
    ];
    if (verbIndexes.length <= 1) return tokens;
    final keep = verbIndexes.last;
    return [
      for (var i = 0; i < tokens.length; i++)
        if (i == keep || !verbIndexes.contains(i)) tokens[i],
    ];
  }

  FirebarShorthandPreview _buildPreview(
    List<FirebarShorthandToken> tokens, {
    required bool finalize,
  }) {
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.error) {
        return FirebarShorthandPreview(
          errorReason: t.errorReason ?? 'invalid token',
          errorTokenIndex: i,
        );
      }
    }

    // While typing (not applying), preview resolved/completed pieces only.
    if (!finalize) {
      return _structurePreview(tokens, requireComplete: false);
    }

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.completed && t.resolved != null) continue;
      if (t.matches.length == 1) continue;
      if (t.matches.isEmpty) {
        return FirebarShorthandPreview(
          errorReason: t.errorReason ?? 'unrecognized “${t.typed}”',
          errorTokenIndex: i,
        );
      }
      // Multiple matches — block apply and leave the dropdown open. No lecture.
      return FirebarShorthandPreview(
        errorTokenIndex: i,
      );
    }

    return _structurePreview(tokens, requireComplete: true);
  }

  FirebarShorthandPreview _structurePreview(
    List<FirebarShorthandToken> tokens, {
    required bool requireComplete,
  }) {
    final resolved = <({int index, FirebarMatch match})>[];
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      final match = t.resolved ??
          (t.matches.length == 1 ? t.matches.single : null);
      if (match == null) {
        if (requireComplete && t.typed.isNotEmpty) {
          return FirebarShorthandPreview(
            errorReason: 'ambiguous “${t.typed}”',
            errorTokenIndex: i,
          );
        }
        continue;
      }
      resolved.add((index: i, match: match));
    }

    var actionIndex = -1;
    for (final row in resolved) {
      if (row.match.kind == FirebarMatchKind.verb) {
        actionIndex = row.index;
      }
    }

    final subjects = <FirebarMatch>[];
    final opponents = <FirebarMatch>[];
    FirebarMatch? action;
    for (final row in resolved) {
      if (row.match.kind == FirebarMatchKind.verb) {
        if (row.index == actionIndex) action = row.match;
        continue;
      }
      if (actionIndex < 0 || row.index < actionIndex) {
        subjects.add(row.match);
      } else {
        opponents.add(row.match);
      }
    }

    return FirebarShorthandPreview(
      subjects: subjects,
      action: action,
      opponents: opponents,
    );
  }

  String _displayLine(List<FirebarShorthandToken> tokens, bool trailingSpace) {
    if (tokens.isEmpty) return '';
    final body = tokens.map((t) => t.display).join(' ');
    return trailingSpace ? '$body ' : body;
  }
}
