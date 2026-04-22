import 'dart:convert';

import 'package:intl/intl.dart';

/// Which date part a [DateFieldToken] renders.
enum DateFieldKind { weekday, month, day, year }

/// Named format option for a [DateFieldKind] (label + ICU token used by [DateFormat]).
///
/// The label is human-facing (shown in the gear popover + chip subscript).
/// [icuToken] is passed to [DateFormat] to render that field in isolation,
/// so callers can concatenate fields with arbitrary literal separators.
class DateFieldFormatOption {
  const DateFieldFormatOption(this.label, this.icuToken);

  final String label;
  final String icuToken;
}

/// Built-in format options per [DateFieldKind].
///
/// Index into these lists via [DateFieldToken.optionIndex]; this is what gets
/// persisted in JSON so the order is load-bearing — append, don't reorder.
const Map<DateFieldKind, List<DateFieldFormatOption>> kDateFieldOptions = {
  DateFieldKind.weekday: [
    DateFieldFormatOption('Long', 'EEEE'),
    DateFieldFormatOption('Short', 'EEE'),
  ],
  DateFieldKind.month: [
    DateFieldFormatOption('Long', 'MMMM'),
    DateFieldFormatOption('Short', 'MMM'),
    DateFieldFormatOption('Numeric', 'M'),
    DateFieldFormatOption('Numeric 0-padded', 'MM'),
  ],
  DateFieldKind.day: [
    DateFieldFormatOption('Numeric', 'd'),
    DateFieldFormatOption('Numeric 0-padded', 'dd'),
  ],
  DateFieldKind.year: [
    DateFieldFormatOption('4-digit', 'yyyy'),
    DateFieldFormatOption('2-digit', 'yy'),
  ],
};

String dateFieldKindLabel(DateFieldKind k) {
  switch (k) {
    case DateFieldKind.weekday:
      return 'Day of Week';
    case DateFieldKind.month:
      return 'Month';
    case DateFieldKind.day:
      return 'Day';
    case DateFieldKind.year:
      return 'Year';
  }
}

/// Single renderable field inside a [DateFormula] — mutable because the editor
/// patches optionIndex/caps in place on user interaction.
class DateFieldToken {
  DateFieldToken({
    required this.kind,
    this.optionIndex = 0,
    this.caps = false,
  });

  final DateFieldKind kind;
  int optionIndex;
  bool caps;

  /// Clamped current option (guards against stale indexes from old JSON).
  DateFieldFormatOption get option {
    final opts = kDateFieldOptions[kind]!;
    final i = optionIndex.clamp(0, opts.length - 1);
    return opts[i];
  }

  String render(DateTime date) {
    final raw = DateFormat(option.icuToken).format(date);
    return caps ? raw.toUpperCase() : raw;
  }

  DateFieldToken copy() =>
      DateFieldToken(kind: kind, optionIndex: optionIndex, caps: caps);

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'optionIndex': optionIndex,
        'caps': caps,
      };

  static DateFieldToken fromJson(Map<String, dynamic> j) {
    final kindName = j['kind']?.toString() ?? 'day';
    final kind = DateFieldKind.values.firstWhere(
      (e) => e.name == kindName,
      orElse: () => DateFieldKind.day,
    );
    return DateFieldToken(
      kind: kind,
      optionIndex: (j['optionIndex'] as num?)?.toInt() ?? 0,
      caps: j['caps'] as bool? ?? false,
    );
  }
}

/// Ordered list of [DateFieldToken]s with one editable separator around each
/// (length = fields.length + 1 so you always have a "leading" and "trailing"
/// literal slot). Use [render] to turn a [DateTime] into the final string.
class DateFormula {
  DateFormula({
    required this.fields,
    required this.separators,
  }) {
    assert(
      separators.length == fields.length + 1,
      'separators must be fields.length + 1 long',
    );
  }

  final List<DateFieldToken> fields;
  final List<String> separators;

  String render(DateTime date) {
    final buf = StringBuffer();
    for (var i = 0; i < fields.length; i++) {
      // Leading (i == 0) literal is written verbatim. Between-field separators
      // default to a single space when empty so chips never run together like
      // "AprilMonth9" just because the user left the slot blank.
      if (i == 0) {
        buf.write(separators[i]);
      } else {
        buf.write(separators[i].isEmpty ? ' ' : separators[i]);
      }
      buf.write(fields[i].render(date));
    }
    buf.write(separators.last);
    return buf.toString();
  }

  DateFormula clone() => DateFormula(
        fields: fields.map((f) => f.copy()).toList(),
        separators: List<String>.from(separators),
      );

  Map<String, dynamic> toJson() => {
        'fields': fields.map((f) => f.toJson()).toList(),
        'separators': separators,
      };

  static DateFormula fromJson(Map<String, dynamic> j) {
    final rawFields = (j['fields'] as List<dynamic>?) ?? const [];
    final fields = rawFields
        .map((e) => DateFieldToken.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    var seps = ((j['separators'] as List<dynamic>?) ?? const [])
        .map((e) => e.toString())
        .toList();
    if (seps.length != fields.length + 1) {
      // Legacy / malformed — pad or truncate to the canonical length so we
      // never throw on user data.
      seps = List<String>.filled(fields.length + 1, '', growable: true);
    }
    return DateFormula(fields: fields, separators: seps);
  }

  String encode() => json.encode(toJson());

  static DateFormula? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = json.decode(raw) as Map<String, dynamic>;
      return DateFormula.fromJson(m);
    } catch (_) {
      return null;
    }
  }

  // -- Presets ---------------------------------------------------------------

  /// `APRIL 9, 2026` — Month (long, caps), day (numeric), year (4-digit).
  static DateFormula getty() => DateFormula(
        fields: [
          DateFieldToken(kind: DateFieldKind.month, optionIndex: 0, caps: true),
          DateFieldToken(kind: DateFieldKind.day, optionIndex: 0),
          DateFieldToken(kind: DateFieldKind.year, optionIndex: 0),
        ],
        separators: ['', ' ', ', ', ''],
      );

  /// `Apr 9, 2026` — Month (short), day, year.
  static DateFormula imagn() => DateFormula(
        fields: [
          DateFieldToken(kind: DateFieldKind.month, optionIndex: 1),
          DateFieldToken(kind: DateFieldKind.day, optionIndex: 0),
          DateFieldToken(kind: DateFieldKind.year, optionIndex: 0),
        ],
        separators: ['', ' ', ', ', ''],
      );

  /// `April 9, 2026` — Month (long), day, year.
  static DateFormula ap() => DateFormula(
        fields: [
          DateFieldToken(kind: DateFieldKind.month, optionIndex: 0),
          DateFieldToken(kind: DateFieldKind.day, optionIndex: 0),
          DateFieldToken(kind: DateFieldKind.year, optionIndex: 0),
        ],
        separators: ['', ' ', ', ', ''],
      );

  /// `4/9/26` — Month (numeric), day, year (2-digit).
  static DateFormula shortFmt() => DateFormula(
        fields: [
          DateFieldToken(kind: DateFieldKind.month, optionIndex: 2),
          DateFieldToken(kind: DateFieldKind.day, optionIndex: 0),
          DateFieldToken(kind: DateFieldKind.year, optionIndex: 1),
        ],
        separators: ['', '/', '/', ''],
      );

  /// `Tuesday, April 9, 2026` — weekday + AP layout.
  static DateFormula withWeekday() => DateFormula(
        fields: [
          DateFieldToken(kind: DateFieldKind.weekday, optionIndex: 0),
          DateFieldToken(kind: DateFieldKind.month, optionIndex: 0),
          DateFieldToken(kind: DateFieldKind.day, optionIndex: 0),
          DateFieldToken(kind: DateFieldKind.year, optionIndex: 0),
        ],
        separators: ['', ', ', ' ', ', ', ''],
      );

  /// Named preset identifiers used by the editor's segmented row.
  static const List<String> presetIds = [
    'getty',
    'imagn',
    'ap',
    'short',
    'weekday',
  ];

  static String presetLabel(String id) {
    switch (id) {
      case 'getty':
        return 'Getty';
      case 'imagn':
        return 'Imagn';
      case 'ap':
        return 'AP';
      case 'short':
        return 'Short';
      case 'weekday':
        return 'With weekday';
      default:
        return id;
    }
  }

  static DateFormula byPresetId(String id) {
    switch (id) {
      case 'getty':
        return DateFormula.getty();
      case 'imagn':
        return DateFormula.imagn();
      case 'ap':
        return DateFormula.ap();
      case 'short':
        return DateFormula.shortFmt();
      case 'weekday':
        return DateFormula.withWeekday();
      default:
        return DateFormula.ap();
    }
  }

  /// Returns the preset id that exactly matches [candidate], or `null`
  /// when the formula has been tweaked ("Custom").
  static String? matchPresetId(DateFormula candidate) {
    for (final id in presetIds) {
      if (_formulasEqual(candidate, byPresetId(id))) return id;
    }
    return null;
  }

  static bool _formulasEqual(DateFormula a, DateFormula b) {
    if (a.fields.length != b.fields.length) return false;
    if (a.separators.length != b.separators.length) return false;
    for (var i = 0; i < a.fields.length; i++) {
      final x = a.fields[i];
      final y = b.fields[i];
      if (x.kind != y.kind ||
          x.optionIndex != y.optionIndex ||
          x.caps != y.caps) {
        return false;
      }
    }
    for (var i = 0; i < a.separators.length; i++) {
      if (a.separators[i] != b.separators[i]) return false;
    }
    return true;
  }
}

/// Where the [DateTime] fed to [DateFormula.render] comes from.
enum DateFormulaSource {
  /// Embedded photo metadata — EXIF DateTimeOriginal.
  photo,

  /// Session / template game date (e.g. user-set match day).
  template,
}

String dateFormulaSourceToString(DateFormulaSource s) => s.name;

DateFormulaSource dateFormulaSourceFromString(String? s) {
  for (final v in DateFormulaSource.values) {
    if (v.name == s) return v;
  }
  return DateFormulaSource.photo;
}
