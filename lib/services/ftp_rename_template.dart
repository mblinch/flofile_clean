import 'package:path/path.dart' as p;

/// Tokens available in FTP “Rename uploaded file” templates.
///
/// Examples: `{date}_{away}_{home}_{n}`, `{initials}_{original}`, `{iptc:Object Name}`
class FtpRenameTokens {
  static const date = 'date';
  static const time = 'time';
  static const away = 'away';
  static const home = 'home';

  /// Legacy combined token (`AWAY-HOME`). Prefer [away] / [home].
  static const teams = 'teams';
  static const n = 'n';
  static const original = 'original';
  static const photographer = 'photographer';
  static const initials = 'initials';

  /// Optional chips (sequence `{n}` is required and shown separately).
  static const chipTokens = <String>[
    date,
    time,
    away,
    home,
    original,
    photographer,
    initials,
  ];

  static String brace(String token) => '{$token}';

  static String get sequenceBrace => brace(n);
}

/// `{date}` format options — order + separator compose the token label.
class FtpRenameDateFormats {
  FtpRenameDateFormats._();

  /// Order keys (no separator).
  static const orders = <String>[
    'YYYYMMDD',
    'YYMMDD',
    'MMDDYY',
    'DDMMYY',
  ];

  /// Separators between year/month/day parts.
  static const separators = <String>['', '-', '_'];

  static const defaultFormat = 'YYYYMMDD';

  /// All composed formats (legacy + new).
  static List<String> get formats {
    final out = <String>[];
    for (final order in orders) {
      for (final sep in separators) {
        out.add(compose(order: order, separator: sep));
      }
    }
    return out;
  }

  static final _dateTokenRe = RegExp(
    r'\{date(?::([^{}|]+))?(?:\|[^{}]*)?\}',
    caseSensitive: false,
  );

  static String compose({required String order, required String separator}) {
    final o = orders.contains(order) ? order : orders.first;
    final sep = separators.contains(separator) ? separator : '';
    if (sep.isEmpty) return o;
    switch (o) {
      case 'YYMMDD':
        return 'YY${sep}MM${sep}DD';
      case 'MMDDYY':
        return 'MM${sep}DD${sep}YY';
      case 'DDMMYY':
        return 'DD${sep}MM${sep}YY';
      case 'YYYYMMDD':
      default:
        return 'YYYY${sep}MM${sep}DD';
    }
  }

  static String orderOf(String? format) {
    final n = (format ?? '')
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[-_.]'), '');
    for (final o in orders) {
      if (o == n) return o;
    }
    return orders.first;
  }

  static String separatorOf(String? format) {
    final n = (format ?? '').trim().toUpperCase();
    for (final sep in separators) {
      if (sep.isEmpty) continue;
      if (n.contains(sep)) return sep;
    }
    return '';
  }

  static String separatorLabel(String sep) => sep.isEmpty ? 'none' : sep;

  static String nextOrder(String? format) {
    final i = orders.indexOf(orderOf(format));
    final next = orders[(i < 0 ? 0 : i + 1) % orders.length];
    return compose(order: next, separator: separatorOf(format));
  }

  static String previousOrder(String? format) {
    final i = orders.indexOf(orderOf(format));
    final prev = orders[(i < 0 ? 0 : i - 1 + orders.length) % orders.length];
    return compose(order: prev, separator: separatorOf(format));
  }

  static String nextSeparator(String? format) {
    final i = separators.indexOf(separatorOf(format));
    final next = separators[(i < 0 ? 0 : i + 1) % separators.length];
    return compose(order: orderOf(format), separator: next);
  }

  static String previousSeparator(String? format) {
    final i = separators.indexOf(separatorOf(format));
    final prev =
        separators[(i < 0 ? 0 : i - 1 + separators.length) % separators.length];
    return compose(order: orderOf(format), separator: prev);
  }

  static String normalize(String? raw) {
    final key = (raw ?? '').trim().toUpperCase();
    if (key.isEmpty) return defaultFormat;
    for (final f in formats) {
      if (f.toUpperCase() == key) return f;
    }
    // Legacy / partial: strip unknown chars and rebuild.
    final order = orderOf(key);
    final sep = separatorOf(key);
    return compose(order: order, separator: sep);
  }

  static int indexOf(String? raw) {
    final n = normalize(raw);
    final i = formats.indexOf(n);
    return i < 0 ? 0 : i;
  }

  static String next(String? current) {
    final i = indexOf(current);
    return formats[(i + 1) % formats.length];
  }

  static String previous(String? current) {
    final i = indexOf(current);
    return formats[(i - 1 + formats.length) % formats.length];
  }

  /// Brace token for [format]. Default format uses plain `{date}`.
  static String brace(String format) {
    final n = normalize(format);
    if (n == defaultFormat) return FtpRenameTokens.brace(FtpRenameTokens.date);
    return '{date:$n}';
  }

  /// Format label currently used in [template], if any `{date…}` is present.
  static String? formatInTemplate(String template) {
    final m = _dateTokenRe.firstMatch(template);
    if (m == null) return null;
    final raw = m.group(1);
    if (raw == null || raw.trim().isEmpty) return defaultFormat;
    return normalize(FtpRenameCaseFormats.split(raw).body);
  }

  static bool hasDateToken(String template) =>
      _dateTokenRe.hasMatch(template);

  /// Replace every `{date}` / `{date:…}` with [format]'s token.
  static String applyFormat(String template, String format) {
    final token = brace(format);
    return template.replaceAllMapped(_dateTokenRe, (_) => token);
  }

  static String formatDate(DateTime d, [String? format]) {
    final y = d.year.toString().padLeft(4, '0');
    final yy = y.length >= 2 ? y.substring(y.length - 2) : y.padLeft(2, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final order = orderOf(format);
    final sep = separatorOf(format);
    switch (order) {
      case 'YYMMDD':
        return '$yy$sep$m$sep$day';
      case 'MMDDYY':
        return '$m$sep$day$sep$yy';
      case 'DDMMYY':
        return '$day$sep$m$sep$yy';
      case 'YYYYMMDD':
      default:
        return '$y$sep$m$sep$day';
    }
  }
}

/// `{time}` format options — clock style + separator compose the token label.
class FtpRenameTimeFormats {
  FtpRenameTimeFormats._();

  static const clocks = <String>['military', 'ampm'];
  static const separators = <String>[':', '-', '', '_', '.'];

  static const defaultFormat = 'HH:MM:SS';

  static List<String> get formats {
    final out = <String>[];
    for (final clock in clocks) {
      for (final sep in separators) {
        for (final seconds in [true, false]) {
          out.add(
            compose(clock: clock, separator: sep, seconds: seconds),
          );
        }
      }
    }
    return out;
  }

  static final _timeTokenRe = RegExp(
    r'\{time(?::([^{}|]+))?(?:\|[^{}]*)?\}',
    caseSensitive: false,
  );

  static String compose({
    required String clock,
    required String separator,
    required bool seconds,
  }) {
    final c = clocks.contains(clock) ? clock : clocks.first;
    final sep = separators.contains(separator) ? separator : ':';
    if (c == 'ampm') {
      if (seconds) {
        if (sep.isEmpty) return 'hMMSSa';
        return 'h${sep}MM${sep}SS a';
      }
      if (sep.isEmpty) return 'hMMa';
      return 'h${sep}MM a';
    }
    if (seconds) {
      if (sep.isEmpty) return 'HHMMSS';
      return 'HH${sep}MM${sep}SS';
    }
    if (sep.isEmpty) return 'HHMM';
    return 'HH${sep}MM';
  }

  static String clockOf(String? format) {
    final n = (format ?? '').trim();
    if (n.isEmpty) return 'military';
    // Military tokens use "HH"; AM/PM tokens use lowercase "h" and/or a trailing "a".
    // Do not lowercase before this check — "HH:MM:SS".toLowerCase() starts with "h".
    if (n.contains('HH') || n.startsWith('H')) return 'military';
    if (n.startsWith('h') || n.endsWith('a') || n.contains(' a')) {
      return 'ampm';
    }
    return 'military';
  }

  static String clockLabel(String? format) =>
      clockOf(format) == 'ampm' ? 'AM/PM' : 'Military';

  static String separatorOf(String? format) {
    final n = (format ?? '').trim();
    for (final sep in [':', '-', '_', '.']) {
      if (n.contains(sep)) return sep;
    }
    return '';
  }

  static String separatorLabel(String sep) => sep.isEmpty ? 'none' : sep;

  static bool secondsOf(String? format) {
    final n = (format ?? '').trim().toUpperCase();
    // "SS" as seconds token; avoid matching lone S in odd labels.
    return n.contains('SS');
  }

  static String nextClock(String? format) {
    final i = clocks.indexOf(clockOf(format));
    final next = clocks[(i < 0 ? 0 : i + 1) % clocks.length];
    return compose(
      clock: next,
      separator: separatorOf(format),
      seconds: secondsOf(format),
    );
  }

  static String previousClock(String? format) {
    final i = clocks.indexOf(clockOf(format));
    final prev = clocks[(i < 0 ? 0 : i - 1 + clocks.length) % clocks.length];
    return compose(
      clock: prev,
      separator: separatorOf(format),
      seconds: secondsOf(format),
    );
  }

  static String nextSeparator(String? format) {
    final i = separators.indexOf(separatorOf(format));
    final next = separators[(i < 0 ? 0 : i + 1) % separators.length];
    return compose(
      clock: clockOf(format),
      separator: next,
      seconds: secondsOf(format),
    );
  }

  static String previousSeparator(String? format) {
    final i = separators.indexOf(separatorOf(format));
    final prev =
        separators[(i < 0 ? 0 : i - 1 + separators.length) % separators.length];
    return compose(
      clock: clockOf(format),
      separator: prev,
      seconds: secondsOf(format),
    );
  }

  static String normalize(String? raw) {
    final key = (raw ?? '').trim();
    if (key.isEmpty) return defaultFormat;
    for (final f in formats) {
      if (f.toLowerCase() == key.toLowerCase()) return f;
    }
    // Legacy aliases.
    final lower = key.toLowerCase();
    if (lower == 'h:mm:ss a') return 'h:MM:SS a';
    if (lower == 'h:mm a') return 'h:MM a';
    return compose(
      clock: clockOf(key),
      separator: separatorOf(key),
      seconds: secondsOf(key),
    );
  }

  static int indexOf(String? raw) {
    final n = normalize(raw);
    final i = formats.indexOf(n);
    return i < 0 ? 0 : i;
  }

  static String next(String? current) {
    final i = indexOf(current);
    return formats[(i + 1) % formats.length];
  }

  static String previous(String? current) {
    final i = indexOf(current);
    return formats[(i - 1 + formats.length) % formats.length];
  }

  /// Brace token for [format]. Default format uses plain `{time}`.
  static String brace(String format) {
    final n = normalize(format);
    if (n == defaultFormat) return FtpRenameTokens.brace(FtpRenameTokens.time);
    return '{time:$n}';
  }

  static String? formatInTemplate(String template) {
    final m = _timeTokenRe.firstMatch(template);
    if (m == null) return null;
    final raw = m.group(1);
    if (raw == null || raw.trim().isEmpty) return defaultFormat;
    return normalize(FtpRenameCaseFormats.split(raw).body);
  }

  static bool hasTimeToken(String template) =>
      _timeTokenRe.hasMatch(template);

  static String applyFormat(String template, String format) {
    final token = brace(format);
    return template.replaceAllMapped(_timeTokenRe, (_) => token);
  }

  static String formatTime(DateTime d, [String? format]) {
    final h24 = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    final s = d.second.toString().padLeft(2, '0');
    final hour12 = (d.hour % 12 == 0 ? 12 : d.hour % 12).toString();
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final clock = clockOf(format);
    final sep = separatorOf(format);
    final seconds = secondsOf(format);
    if (clock == 'ampm') {
      final core = seconds ? '$hour12$sep$m$sep$s' : '$hour12$sep$m';
      return '${core}_$ampm';
    }
    return seconds ? '$h24$sep$m$sep$s' : '$h24$sep$m';
  }
}

/// Letter-case options for rename token values (`|upper`, `|lower`, `|title`).
class FtpRenameCaseFormats {
  FtpRenameCaseFormats._();

  /// Compact Caps button cycles uppercase ↔ lowercase.
  static const formats = <String>['upper', 'lower'];
  static const defaultFormat = 'upper';

  static String labelOf(String? format) {
    switch (normalize(format)) {
      case 'lower':
        return 'aa';
      case 'upper':
      default:
        return 'AA';
    }
  }

  static String normalize(String? raw) {
    final key = (raw ?? '').trim().toLowerCase().replaceAll('-', '_');
    if (key == 'lower') return 'lower';
    if (key == 'upper') return 'upper';
    // Legacy: treat title / as-is as uppercase for the compact AA/aa control.
    if (key == 'title' ||
        key == 'as_is' ||
        key == 'asis' ||
        key == 'none' ||
        key == 'default' ||
        key.isEmpty) {
      return defaultFormat;
    }
    return defaultFormat;
  }

  static int indexOf(String? raw) {
    final n = normalize(raw);
    final i = formats.indexOf(n);
    return i < 0 ? 0 : i;
  }

  static String next(String? current) {
    return normalize(current) == 'lower' ? 'upper' : 'lower';
  }

  static String previous(String? current) => next(current);

  static bool isCaseToken(String? raw) {
    final key = (raw ?? '').trim().toLowerCase().replaceAll('-', '_');
    // Legacy title / as_is still recognized in templates.
    return formats.contains(key) ||
        key == 'title' ||
        key == 'as_is' ||
        key == 'asis' ||
        key == 'none' ||
        key == 'default';
  }

  /// Peel trailing `|case` from a token interior (`date:YYYY|upper`).
  static ({String body, String casing}) split(String raw) {
    final text = raw.trim();
    final i = text.lastIndexOf('|');
    if (i <= 0 || i >= text.length - 1) {
      return (body: text, casing: defaultFormat);
    }
    final suffix = text.substring(i + 1);
    if (!isCaseToken(suffix)) {
      return (body: text, casing: defaultFormat);
    }
    return (body: text.substring(0, i), casing: normalize(suffix));
  }

  static String join(String body, String? casing) {
    final c = normalize(casing);
    if (c == defaultFormat) return body;
    return '$body|$c';
  }

  static String apply(String input, [String? format]) {
    final s = input;
    if (s.isEmpty) return s;
    return normalize(format) == 'lower' ? s.toLowerCase() : s.toUpperCase();
  }
}

/// `{photographer}` name style options.
class FtpRenamePhotographerFormats {
  FtpRenamePhotographerFormats._();

  /// Cycle order for the Photographer tile stepper.
  static const formats = <String>[
    'last_first',
    'last',
    'first',
    'initial_last',
  ];

  static const defaultFormat = 'last_first';

  static final _photoTokenRe = RegExp(
    r'\{photographer(?::([^{}|]+))?(?:\|[^{}]*)?\}',
    caseSensitive: false,
  );

  static String labelOf(String? format) {
    switch (normalize(format)) {
      case 'last':
        return 'Last';
      case 'first':
        return 'First';
      case 'initial_last':
        return 'F Last';
      case 'last_first':
      default:
        return 'Last First';
    }
  }

  static String normalize(String? raw) {
    final key = (raw ?? '').trim().toLowerCase().replaceAll('-', '_');
    if (key.isEmpty) return defaultFormat;
    for (final f in formats) {
      if (f == key) return f;
    }
    // Legacy aliases.
    if (key == 'lastname_firstname' || key == 'lastfirst') return 'last_first';
    if (key == 'lastname' || key == 'last_name') return 'last';
    if (key == 'firstname' || key == 'first_name') return 'first';
    if (key == 'initiallast' || key == 'f_last' || key == 'flast') {
      return 'initial_last';
    }
    return defaultFormat;
  }

  static int indexOf(String? raw) {
    final n = normalize(raw);
    final i = formats.indexOf(n);
    return i < 0 ? 0 : i;
  }

  static String next(String? current) {
    final i = indexOf(current);
    return formats[(i + 1) % formats.length];
  }

  static String previous(String? current) {
    final i = indexOf(current);
    return formats[(i - 1 + formats.length) % formats.length];
  }

  static String brace(String format) {
    final n = normalize(format);
    return '{photographer:$n}';
  }

  static String? formatInTemplate(String template) {
    final m = _photoTokenRe.firstMatch(template);
    if (m == null) return null;
    final raw = m.group(1);
    if (raw == null || raw.trim().isEmpty) return defaultFormat;
    return normalize(FtpRenameCaseFormats.split(raw).body);
  }

  static bool hasPhotographerToken(String template) =>
      _photoTokenRe.hasMatch(template);

  static String applyFormat(String template, String format) {
    final token = brace(format);
    return template.replaceAllMapped(_photoTokenRe, (_) => token);
  }

  /// Split a creator / byline into (first, last). Single token → both same.
  static ({String first, String last}) splitName(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (parts.isEmpty) return (first: '', last: '');
    if (parts.length == 1) return (first: parts.first, last: parts.first);
    return (first: parts.first, last: parts.last);
  }

  static String formatName(String name, [String? format]) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    final parts = splitName(trimmed);
    switch (normalize(format)) {
      case 'last':
        return parts.last;
      case 'first':
        return parts.first;
      case 'initial_last':
        final initial = RegExp(r'[A-Za-z0-9]').firstMatch(parts.first);
        final letter = initial?.group(0)?.toUpperCase() ?? '';
        if (letter.isEmpty) return parts.last;
        if (parts.last.isEmpty) return letter;
        // No separator — e.g. Mark Blinch → MBlinch (not M_Blinch).
        return '$letter${parts.last}';
      case 'last_first':
      default:
        if (parts.first == parts.last) return parts.last;
        return '${parts.last} ${parts.first}';
    }
  }
}

/// Context for resolving an FTP rename template for one file.
class FtpRenameContext {
  const FtpRenameContext({
    required this.sourcePath,
    this.date,
    this.awayTeam = '',
    this.homeTeam = '',
    String teams = '',
    this.photographer = '',
    this.initials = '',
    this.sequence,
    this.sequenceWidth = 4,
    this.iptc = const {},
    this.letterCase = FtpRenameCaseFormats.defaultFormat,
  }) : _teamsOverride = teams;

  final String sourcePath;

  /// Capture / session date used for `{date}` / `{date:…}`.
  final DateTime? date;

  /// Away abbreviation for `{away}` (e.g. `BOS`).
  final String awayTeam;

  /// Home abbreviation for `{home}` (e.g. `TOR`).
  final String homeTeam;

  final String _teamsOverride;

  /// Combined `AWAY-HOME` for legacy `{teams}`.
  String get teams {
    final override = _teamsOverride.trim();
    if (override.isNotEmpty) return override;
    final parts = [
      if (awayTeam.trim().isNotEmpty) awayTeam.trim(),
      if (homeTeam.trim().isNotEmpty) homeTeam.trim(),
    ];
    return parts.join('-');
  }

  /// Creator / byline for `{photographer}`.
  final String photographer;

  /// Preferred `{initials}` value (camera serial initials or user override).
  /// Empty → first letter of each word in Creator / [photographer].
  final String initials;

  /// Explicit sequence for `{n}`. When null, falls back to IPTC then `0001`.
  final int? sequence;

  /// Zero-pad width for `{n}` (default 4 → `0042`).
  final int sequenceWidth;

  /// IPTC/Exif panel values for `{iptc:…}` and sequence fallbacks.
  final Map<String, String> iptc;

  /// Whole-filename letter case (`upper` / `lower`), applied after token resolve.
  final String letterCase;
}

/// Resolves FTP rename templates with `{token}` / `{iptc:Field}` variables.
class FtpRenameTemplate {
  FtpRenameTemplate._();

  static final _tokenRe = RegExp(r'\{([^{}]+)\}');

  /// Whether [template] includes the required `{n}` sequence token.
  static bool hasSequenceToken(String template) =>
      template.toLowerCase().contains('{n}');

  /// Whether [template] includes the required `{initials}` token.
  static bool hasInitialsToken(String template) =>
      RegExp(r'\{initials(?:\|[^{}]*)?\}', caseSensitive: false)
          .hasMatch(template);

  /// Default rename pattern when none is set.
  static const defaultTemplate = '{initials}-{date}-{n}';

  /// Ensures required `{initials}` and `{n}` are present. Empty → [defaultTemplate].
  static String ensureSequenceToken(String template) {
    var trimmed = template.trim();
    if (trimmed.isEmpty) return defaultTemplate;
    if (!hasSequenceToken(trimmed)) {
      trimmed = '$trimmed${FtpRenameTokens.sequenceBrace}';
    }
    if (!hasInitialsToken(trimmed)) {
      trimmed = '${FtpRenameTokens.brace(FtpRenameTokens.initials)}-$trimmed';
    }
    return trimmed;
  }

  /// Digits pulled from IPTC for the number-sequence system.
  ///
  /// Prefers trailing digits in Object Name, then any digits in MEID /
  /// Transmission Reference / Original Transmission Reference.
  static int? sequenceFromIptc(Map<String, String> iptc) {
    String? pick(List<String> keys) {
      for (final key in keys) {
        final v = _iptcLookup(iptc, key);
        if (v != null && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    final objectName = pick(const [
      'Object Name',
      'ObjectName',
      'Title',
    ]);
    final fromObject = _trailingDigits(objectName);
    if (fromObject != null) return fromObject;

    final meid = pick(const [
      'MEID',
      'Original Transmission Reference',
      'OriginalTransmissionReference',
      'Transmission Reference',
      'TransmissionReference',
      'Job Id',
      'JobID',
    ]);
    return _anyDigits(meid);
  }

  /// Formats a sequence number (default width 4 → `0042`).
  static String formatSequence(int n, {int width = 4}) {
    final safe = n < 0 ? 0 : n;
    final raw = '$safe';
    if (raw.length >= width) return raw;
    return raw.padLeft(width, '0');
  }

  /// First letter of each whitespace-separated name in [creator].
  ///
  /// Example: `Mark Blinch` → `MB`, `Jean-Luc Picard` → `JP`.
  static String initialsFromName(String creator) {
    final words = creator
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    final buf = StringBuffer();
    for (final word in words) {
      final m = RegExp(r'[A-Za-z0-9]').firstMatch(word);
      if (m != null) buf.write(m.group(0)!.toUpperCase());
    }
    return buf.toString();
  }

  /// Fallback when Creator / photographer is blank.
  static const defaultInitials = 'DSC';

  /// Resolves `{initials}`: prefer [explicit], else first letters of Creator,
  /// else [defaultInitials].
  static String resolveInitials({
    String explicit = '',
    String photographer = '',
    Map<String, String> iptc = const {},
  }) {
    final preferred = explicit.trim();
    if (preferred.isNotEmpty) return _sanitize(preferred);

    final name = photographer.trim().isNotEmpty
        ? photographer.trim()
        : (_iptcLookup(iptc, 'Creator') ??
            _iptcLookup(iptc, 'By-line') ??
            _iptcLookup(iptc, 'Author') ??
            '');
    final fromName = _sanitize(initialsFromName(name));
    if (fromName.isNotEmpty) return fromName;
    return defaultInitials;
  }

  /// Preview string for the settings UI (no file extension).
  static String preview(
    String template, {
    DateTime? date,
    String awayTeam = 'LAK',
    String homeTeam = 'TOR',
    String teams = '',
    String photographer = 'Mark Blinch',
    String initials = '',
    int sequence = 42,
    int sequenceWidth = 4,
    String original = 'MB1_4821',
    Map<String, String> iptc = const {},
  }) {
    final trimmed = template.trim();
    if (trimmed.isEmpty) return '$original.jpg';
    final resolved = resolve(
      template: trimmed,
      context: FtpRenameContext(
        sourcePath: '$original.jpg',
        date: date ?? DateTime.now(),
        awayTeam: awayTeam,
        homeTeam: homeTeam,
        teams: teams,
        photographer: photographer,
        initials: initials,
        sequence: sequence,
        sequenceWidth: sequenceWidth,
        iptc: iptc,
      ),
    );
    return resolved;
  }

  /// Resolves [template] for [context]. Empty template → original basename.
  static String resolve({
    required String template,
    required FtpRenameContext context,
  }) {
    final original = p.basename(context.sourcePath);
    final stem = p.basenameWithoutExtension(original);
    final ext = p.extension(original);
    var custom = template.trim();
    if (custom.isEmpty) return original;

    custom = custom.replaceAll('\\', '/');
    custom = p.basename(custom);
    if (custom.isEmpty) return original;

    final seq = context.sequence ??
        sequenceFromIptc(context.iptc) ??
        1;

    final out = custom.replaceAllMapped(_tokenRe, (match) {
      final raw = match.group(1)?.trim() ?? '';
      if (raw.isEmpty) return '';
      final split = FtpRenameCaseFormats.split(raw);
      final body = split.body;
      final casing = split.casing;
      final key = body.toLowerCase();

      String finish(String value) =>
          FtpRenameCaseFormats.apply(_sanitize(value), casing);

      if (key == FtpRenameTokens.date || key.startsWith('date:')) {
        final fmt = key == FtpRenameTokens.date
            ? FtpRenameDateFormats.defaultFormat
            : body.substring(body.indexOf(':') + 1);
        return finish(
          FtpRenameDateFormats.formatDate(
            context.date ?? DateTime.now(),
            fmt,
          ),
        );
      }
      if (key == FtpRenameTokens.time || key.startsWith('time:')) {
        final fmt = key == FtpRenameTokens.time
            ? FtpRenameTimeFormats.defaultFormat
            : body.substring(body.indexOf(':') + 1);
        return finish(
          FtpRenameTimeFormats.formatTime(
            context.date ?? DateTime.now(),
            fmt,
          ),
        );
      }
      if (key == FtpRenameTokens.away || key.startsWith('away:')) {
        return finish(context.awayTeam);
      }
      if (key == FtpRenameTokens.home || key.startsWith('home:')) {
        return finish(context.homeTeam);
      }
      if (key == FtpRenameTokens.teams || key.startsWith('teams:')) {
        return finish(context.teams);
      }
      if (key == FtpRenameTokens.n || key.startsWith('n:')) {
        return finish(
          formatSequence(seq, width: context.sequenceWidth),
        );
      }
      if (key == FtpRenameTokens.original || key.startsWith('original:')) {
        return finish(stem);
      }
      if (key == FtpRenameTokens.photographer ||
          key.startsWith('photographer:')) {
        final fromCtx = context.photographer.trim();
        final fromIptc = fromCtx.isNotEmpty
            ? fromCtx
            : (_iptcLookup(context.iptc, 'Creator') ??
                _iptcLookup(context.iptc, 'By-line') ??
                _iptcLookup(context.iptc, 'Author') ??
                '');
        if (fromIptc.isEmpty) return '';
        // Plain `{photographer}` keeps the full name (legacy).
        if (key == FtpRenameTokens.photographer) {
          return finish(fromIptc);
        }
        final fmt = body.substring(body.indexOf(':') + 1);
        return finish(
          FtpRenamePhotographerFormats.formatName(fromIptc, fmt),
        );
      }
      if (key == FtpRenameTokens.initials || key.startsWith('initials:')) {
        return finish(
          resolveInitials(
            explicit: context.initials,
            photographer: context.photographer,
            iptc: context.iptc,
          ),
        );
      }
      if (key.startsWith('iptc:')) {
        final field = body.substring(5).trim();
        return finish(_iptcLookup(context.iptc, field) ?? '');
      }
      // Unknown token → leave blank (avoid leaking braces into filenames).
      return '';
    });

    final cleaned = out.trim();
    if (cleaned.isEmpty) return original;

    // Apply whole-name letter case to the stem only (keep extension casing).
    String withCase(String fileName) {
      final e = p.extension(fileName);
      final stem = e.isEmpty
          ? fileName
          : fileName.substring(0, fileName.length - e.length);
      final cased = FtpRenameCaseFormats.apply(stem, context.letterCase);
      return e.isEmpty ? cased : '$cased$e';
    }

    if (p.extension(cleaned).isEmpty && ext.isNotEmpty) {
      return withCase('$cleaned$ext');
    }
    return withCase(cleaned);
  }

  /// Default separator between rename variables (any filename-safe string).
  static const defaultSeparator = '-';

  static String normalizeSeparator(String? raw) {
    final s = raw ?? defaultSeparator;
    return s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
  }

  static String _sanitize(String input) {
    var s = input.trim();
    if (s.isEmpty) return '';
    // Keep filenames FTP-safe: collapse whitespace, strip path separators.
    s = s.replaceAll(RegExp(r'[\\/]+'), '-');
    s = s.replaceAll(RegExp(r'\s+'), '_');
    s = s.replaceAll(RegExp(r'[^\w.\-+=@]+'), '');
    return s;
  }

  static String? _iptcLookup(Map<String, String> iptc, String field) {
    if (iptc.isEmpty || field.isEmpty) return null;
    final direct = iptc[field];
    if (direct != null && direct.trim().isNotEmpty) return direct;
    final lower = field.toLowerCase();
    for (final entry in iptc.entries) {
      if (entry.key.toLowerCase() == lower && entry.value.trim().isNotEmpty) {
        return entry.value;
      }
    }
    return null;
  }

  static int? _trailingDigits(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final m = RegExp(r'(\d+)\s*$').firstMatch(raw);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  static int? _anyDigits(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final m = RegExp(r'(\d+)').firstMatch(raw);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }
}
