import '../../../services/mlb_api_service.dart';

enum RosterNameOrder {
  firstLast,
  lastFirst,
}

class ParsedRosterEntry {
  const ParsedRosterEntry({
    required this.rawName,
    required this.jerseyNumber,
    this.position,
    this.playerId,
  });

  final String rawName;
  final String jerseyNumber;
  final String? position;
  final String? playerId;

  String nameFor(RosterNameOrder order) {
    final commaParts = rawName.split(',');
    if (commaParts.length == 2) {
      final left = commaParts.first.trim();
      final right = commaParts.last.trim();
      return order == RosterNameOrder.lastFirst
          ? '$right $left'.trim()
          : '$left $right'.trim();
    }

    final parts = rawName.trim().split(RegExp(r'\s+'));
    if (order == RosterNameOrder.lastFirst && parts.length > 1) {
      return '${parts.sublist(1).join(' ')} ${parts.first}'.trim();
    }
    return rawName.trim();
  }

  Player toPlayer(RosterNameOrder order) {
    final fullName = nameFor(order);
    final firstName = fullName.split(RegExp(r'\s+')).first;
    return Player(
      fullName: fullName,
      firstName: firstName,
      jerseyNumber: jerseyNumber,
      displayName: '$fullName #$jerseyNumber',
      playerId: playerId,
      position: position,
    );
  }
}

class RosterParseResult {
  const RosterParseResult({
    required this.entries,
    required this.detectedNameOrder,
    required this.ignoredLineCount,
  });

  final List<ParsedRosterEntry> entries;
  final RosterNameOrder detectedNameOrder;
  final int ignoredLineCount;

  List<Player> players(RosterNameOrder order) =>
      entries.map((entry) => entry.toPlayer(order)).toList();
}

/// Parses roster text copied from tables such as ESPN's roster pages.
///
/// The parser intentionally keeps name-order interpretation separate so the
/// user can confirm it before entries become [Player] objects.
class RosterTextParser {
  const RosterTextParser();

  static const Map<String, String> _baseballPositions = {
    'P': 'Pitcher',
    'SP': 'Pitcher',
    'RP': 'Pitcher',
    'LHP': 'Pitcher',
    'RHP': 'Pitcher',
    'C': 'Catcher',
    '1B': 'First Baseman',
    '1ST BASE': 'First Baseman',
    'FIRST BASE': 'First Baseman',
    'FIRST BASEMAN': 'First Baseman',
    '2B': 'Second Baseman',
    '2ND BASE': 'Second Baseman',
    'SECOND BASE': 'Second Baseman',
    'SECOND BASEMAN': 'Second Baseman',
    '3B': 'Third Baseman',
    '3RD BASE': 'Third Baseman',
    'THIRD BASE': 'Third Baseman',
    'THIRD BASEMAN': 'Third Baseman',
    'SS': 'Shortstop',
    'IF': 'Infielder',
    'INF': 'Infielder',
    'LF': 'Left Fielder',
    'CF': 'Center Fielder',
    'RF': 'Right Fielder',
    'OF': 'Outfielder',
    'DH': 'Designated Hitter',
    'UTIL': 'Utility',
    'UTL': 'Utility',
    'PH': 'Pinch Hitter',
    'PR': 'Pinch Runner',
  };

  static final RegExp _imagePlayerId = RegExp(
      r'/players/(?:full/)?(\d+)\.[a-z]+(?:\?.*)?$',
      caseSensitive: false);
  static final RegExp _trailingJersey =
      RegExp(r"^(.+?[A-Za-zÀ-ÖØ-öø-ÿ.'’-])\s*#?(\d{1,3})$");
  static final RegExp _leadingJersey =
      RegExp(r"^#?(\d{1,3})\s+(.+?[A-Za-zÀ-ÖØ-öø-ÿ.'’-])$");
  static final RegExp _position = RegExp(r'^[A-Z0-9]{1,4}$');

  RosterParseResult parse(String text, {String? sport}) {
    final entries = <ParsedRosterEntry>[];
    var ignored = 0;
    var commaNames = 0;
    String? pendingPlayerId;

    for (final rawLine in text.replaceAll('\r\n', '\n').split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('http://') || line.startsWith('https://')) {
        pendingPlayerId = _imagePlayerId.firstMatch(line)?.group(1);
        ignored++;
        continue;
      }

      final columns = line.split('\t').map((value) => value.trim()).toList();
      final nameAndNumber = columns.first;
      final trailing = _trailingJersey.firstMatch(nameAndNumber);
      final leading =
          trailing == null ? _leadingJersey.firstMatch(nameAndNumber) : null;

      String? name;
      String? jersey;
      if (trailing != null) {
        name = trailing.group(1)?.trim();
        jersey = trailing.group(2);
      } else if (leading != null) {
        jersey = leading.group(1);
        name = leading.group(2)?.trim();
      }

      if (name == null || name.isEmpty || jersey == null) {
        ignored++;
        pendingPlayerId = null;
        continue;
      }

      if (name.contains(',')) commaNames++;
      final rawPosition = columns.length > 1 ? columns[1].toUpperCase() : null;
      final baseballPosition =
          rawPosition == null ? null : _baseballPositions[rawPosition];
      final position = rawPosition == null ||
              (baseballPosition == null && !_position.hasMatch(rawPosition))
          ? null
          : sport?.toLowerCase() == 'baseball'
              ? (baseballPosition ?? rawPosition)
              : rawPosition;
      entries.add(
        ParsedRosterEntry(
          rawName: name,
          jerseyNumber: jersey,
          position: position,
          playerId: pendingPlayerId,
        ),
      );
      pendingPlayerId = null;
    }

    return RosterParseResult(
      entries: entries,
      detectedNameOrder: commaNames > entries.length / 2
          ? RosterNameOrder.lastFirst
          : RosterNameOrder.firstLast,
      ignoredLineCount: ignored,
    );
  }
}
