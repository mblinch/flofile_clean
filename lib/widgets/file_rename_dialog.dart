import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_icons/phosphor_icons.dart';

import '../caption_style/caption_template.dart';
import '../caption_style/wire_iptc_specs.dart';
import '../services/camera_serial_service.dart';
import '../services/ftp_rename_template.dart';
import '../services/iptc_template_apply_service.dart';
import '../services/iptc_template_import_service.dart';
import '../services/number_sequence_service.dart';
import '../services/preferences_service.dart';
import '../theme/ff_tokens.dart';
import 'app_styled_dialogs.dart';
import 'camera_serial_dialog.dart';

/// Preview inputs loaded from a real image in the edit folder.
class FileRenamePreviewData {
  const FileRenamePreviewData({
    this.date,
    this.sourcePath,
    this.iptc = const {},
    this.awayTeam = '',
    this.homeTeam = '',
  });

  final DateTime? date;
  final String? sourcePath;
  final Map<String, String> iptc;
  final String awayTeam;
  final String homeTeam;

  String get originalStem {
    final path = sourcePath?.trim() ?? '';
    if (path.isEmpty) return 'IMG_4821';
    return p.basenameWithoutExtension(path);
  }

  String get photographer {
    final v = iptc['Creator'] ?? iptc['By-line'] ?? iptc['Author'] ?? '';
    return v.trim();
  }
}

/// Edit the current FTP profile’s rename template — matches File Renaming.html.
class FileRenameDialog extends StatefulWidget {
  const FileRenameDialog({
    super.key,
    this.preview,
  });

  /// Capture date / IPTC / filename used for live rename preview.
  final FileRenamePreviewData? preview;

  static const _imageExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.tif',
    '.tiff',
    '.heic',
    '.webp',
  };

  /// EXIF date from the first image in [folderPath], else file mtime.
  static Future<DateTime?> previewDateFromFolder(String? folderPath) async {
    final data = await previewDataFromFolder(folderPath);
    return data?.date;
  }

  /// IPTC + date + filename from the first image in [folderPath].
  static Future<FileRenamePreviewData?> previewDataFromFolder(
    String? folderPath, {
    String awayTeam = '',
    String homeTeam = '',
  }) async {
    final folder = folderPath?.trim() ?? '';
    if (folder.isEmpty) return null;
    try {
      final files = <String>[];
      await for (final entity in Directory(folder).list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.startsWith('.') || name.startsWith('._')) continue;
        final lower = name.toLowerCase();
        if (lower.startsWith('tmp.') || lower.endsWith('.tmp')) continue;
        if (_imageExtensions.contains(p.extension(lower))) {
          files.add(entity.path);
        }
      }
      if (files.isEmpty) return null;
      files.sort();
      final path = files.first;
      var date = await File(path).lastModified();
      var iptc = <String, String>{};
      try {
        final meta = await IptcTemplateImportService.readMetadata(path);
        if (meta != null) {
          final fromExif =
              IptcTemplateImportService.parseExifDateTimeFromMeta(meta);
          if (fromExif != null) date = fromExif;
          iptc = IptcTemplateImportService.panelValuesFromExiftool(meta);
        }
      } catch (_) {}
      return FileRenamePreviewData(
        date: date,
        sourcePath: path,
        iptc: iptc,
        awayTeam: awayTeam.trim(),
        homeTeam: homeTeam.trim(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Returns the saved template when the user taps Save; `null` on cancel.
  static Future<String?> show(
    BuildContext context, {
    FileRenamePreviewData? preview,
    @Deprecated('Use preview') DateTime? previewDate,
  }) {
    final tokens =
        Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final data = preview ??
        (previewDate != null ? FileRenamePreviewData(date: previewDate) : null);
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) => Theme(
        data: Theme.of(context).copyWith(
          brightness: Brightness.dark,
          extensions: <ThemeExtension<dynamic>>[tokens],
        ),
        child: AppDialogFfStyle(
          enabled: true,
          child: FileRenameDialog(preview: data),
        ),
      ),
    );
  }

  @override
  State<FileRenameDialog> createState() => _FileRenameDialogState();
}

class _FileRenameDialogState extends State<FileRenameDialog> {
  static const _optionalOrder = <String>[
    FtpRenameTokens.date,
    FtpRenameTokens.time,
    FtpRenameTokens.away,
    FtpRenameTokens.home,
    FtpRenameTokens.photographer,
    FtpRenameTokens.original,
  ];

  /// IPTC panel fields usable as `{iptc:…}` rename tokens (storage key → label).
  static const _iptcFields = <({String key, String label})>[
    (key: 'Creator', label: 'Creator'),
    (key: 'Headline', label: 'Headline'),
    (key: 'Object Name', label: 'Object Name'),
    (key: 'MEID', label: 'MEID'),
    (key: 'Credit', label: 'Credit'),
    (key: 'Source', label: 'Source'),
    (key: 'Copyright', label: 'Copyright'),
    (key: 'Job Title', label: 'Job Title'),
    (key: 'Description Writers', label: 'Writers'),
    (key: 'Personality', label: 'Personality'),
    (key: 'Keywords', label: 'Keywords'),
    (key: 'Category', label: 'Category'),
    (key: 'Supp Cat 1', label: 'Supp Cat 1'),
    (key: 'Supp Cat 2', label: 'Supp Cat 2'),
    (key: 'Supp Cat 3', label: 'Supp Cat 3'),
    (key: 'Stadium', label: 'Location'),
    (key: 'City', label: 'City'),
    (key: 'Province/State', label: 'Province/State'),
    (key: 'Country', label: 'Country'),
    (key: 'Country Code', label: 'Country Code'),
    (key: 'Special Instructions', label: 'Special Instructions'),
    (key: 'Urgency', label: 'Urgency'),
  ];

  static const _badChars = r'\/:*?"<>|';

  static String _iptcToken(String storageKey) => 'iptc:$storageKey';

  bool _loading = true;
  bool _serialBylines = false;
  String? _profileName;
  String? _error;

  /// Token keys in pattern order (`n`, `date`, `date:YYMMDD`, …).
  List<String> _toks = [FtpRenameTokens.n];

  /// Separators around tokens; length is always `_toks.length + 1`.
  List<String> _gaps = ['', ''];

  final List<TextEditingController> _gapCtrls = [];
  final List<FocusNode> _gapFocus = [];

  int _digits = PreferencesService.numberSequenceDigitsDefault;
  int _nextSeq = NumberSequenceService.startValue;
  String _dateFormat = FtpRenameDateFormats.defaultFormat;
  String _timeFormat = FtpRenameTimeFormats.defaultFormat;
  String _photoFormat = FtpRenamePhotographerFormats.defaultFormat;
  /// Letter case per token kind (`date`, `away`, `iptc:Creator`, …).
  final Map<String, String> _cases = {};
  /// Whole-filename caps (AA / aa).
  String _globalCase = FtpRenameCaseFormats.defaultFormat;
  /// Default gap inserted between variables.
  String _defaultSep = FtpRenameTemplate.defaultSeparator;
  String _initials = '';
  int _selectedTok = -1;
  int _dragTok = -1;
  int _gapIndex = 0;
  int _gapCursor = 0;

  final _initialsCtrl = TextEditingController();
  final _defaultSepCtrl = TextEditingController(text: '-');

  FileRenamePreviewData get _preview =>
      widget.preview ?? const FileRenamePreviewData();

  DateTime get _previewDate => _preview.date ?? DateTime.now();

  Map<String, String> get _previewIptc => _preview.iptc;

  String get _previewSourcePath =>
      _preview.sourcePath?.trim().isNotEmpty == true
          ? _preview.sourcePath!.trim()
          : '${_preview.originalStem}.jpg';

  @override
  void initState() {
    super.initState();
    _initialsCtrl.addListener(() {
      if (!mounted) return;
      setState(() => _initials = _initialsCtrl.text);
    });
    _defaultSepCtrl.addListener(_onDefaultSepEdited);
    _load();
  }

  Future<void> _load() async {
    final prefs = await PreferencesService.getInstance();
    final seq = NumberSequenceService.instance;
    await seq.ensureLoaded();
    final current = await prefs.getCurrentFtpProfile();
    final profiles = await prefs.getFtpProfiles();
    final name = current != null && profiles.containsKey(current)
        ? current
        : (profiles.isNotEmpty ? profiles.keys.first : null);
    final serialOn = await prefs.getSerialNumberBylines();
    final initials = await prefs.getRenameInitials();
    if (!mounted) return;
    if (name == null) {
      setState(() {
        _loading = false;
        _error = 'Choose an FTP profile first.';
      });
      return;
    }
    var rename = profiles[name]?['renameAs']?.toString() ?? '';
    final trimmed = rename.trim();
    // Empty / sequence-only → initials_date_sequence default.
    if (trimmed.isEmpty || trimmed.toLowerCase() == '{n}') {
      rename = FtpRenameTemplate.defaultTemplate;
    }
    // Legacy `{teams}` → separate away / home tokens.
    rename = rename.replaceAll(
      RegExp(r'\{teams\}', caseSensitive: false),
      '{away}-{home}',
    );
    final ensured = FtpRenameTemplate.ensureSequenceToken(rename);
    final parsed = _parseTemplate(ensured);
    final fromPhotographer = FtpRenameTemplate.initialsFromName(
      widget.preview?.photographer ?? '',
    );
    final startInitials = initials.trim().isNotEmpty
        ? initials.trim()
        : (fromPhotographer.isNotEmpty
            ? fromPhotographer
            : FtpRenameTemplate.defaultInitials);
    setState(() {
      _profileName = name;
      _serialBylines = serialOn;
      _initials = startInitials;
      _initialsCtrl.text = startInitials;
      _digits = seq.digitsOrDefault;
      _nextSeq = seq.nextOrDefault;
      _toks = parsed.toks;
      _gaps = parsed.gaps;
      _dateFormat = FtpRenameDateFormats.formatInTemplate(ensured) ??
          FtpRenameDateFormats.defaultFormat;
      _timeFormat = FtpRenameTimeFormats.formatInTemplate(ensured) ??
          FtpRenameTimeFormats.defaultFormat;
      _photoFormat = FtpRenamePhotographerFormats.formatInTemplate(ensured) ??
          FtpRenamePhotographerFormats.defaultFormat;
      _cases
        ..clear()
        ..addAll(_casesFromToks(parsed.toks));
      _globalCase = FtpRenameCaseFormats.normalize(
        profiles[name]?['renameLetterCase']?.toString(),
      );
      _defaultSep = FtpRenameTemplate.normalizeSeparator(
        profiles[name]?['renameDefaultSep']?.toString() ??
            FtpRenameTemplate.defaultSeparator,
      );
      _defaultSepCtrl.removeListener(_onDefaultSepEdited);
      _defaultSepCtrl.text = _defaultSep;
      _defaultSepCtrl.addListener(_onDefaultSepEdited);
      _loading = false;
      _syncGapControllers();
      _gapIndex = _gaps.length - 1;
      _gapCursor = _gaps.last.length;
    });
  }

  Map<String, String> _casesFromToks(List<String> toks) {
    final out = <String, String>{};
    for (final tok in toks) {
      final split = FtpRenameCaseFormats.split(tok);
      final kind = _tokenKind(split.body);
      out[kind] = split.casing;
    }
    return out;
  }

  String _caseOf(String kind) =>
      FtpRenameCaseFormats.normalize(_cases[kind]);

  String _bodyOfTok(String rawTok) => FtpRenameCaseFormats.split(rawTok).body;

  String _tokWithCase(String body, String kind) =>
      FtpRenameCaseFormats.join(body, _caseOf(kind));

  @override
  void dispose() {
    for (final c in _gapCtrls) {
      c.dispose();
    }
    for (final f in _gapFocus) {
      f.dispose();
    }
    _initialsCtrl.dispose();
    _defaultSepCtrl.removeListener(_onDefaultSepEdited);
    _defaultSepCtrl.dispose();
    super.dispose();
  }

  void _syncGapControllers() {
    while (_gapCtrls.length > _gaps.length) {
      _gapCtrls.removeLast().dispose();
      _gapFocus.removeLast().dispose();
    }
    while (_gapCtrls.length < _gaps.length) {
      final c = TextEditingController();
      late final FocusNode f;
      f = FocusNode(
        onKeyEvent: (node, event) {
          final i = _gapFocus.indexOf(node);
          if (i < 0) return KeyEventResult.ignored;
          return _handleGapKey(i, event);
        },
      );
      c.addListener(() {
        final i = _gapCtrls.indexOf(c);
        if (i >= 0) _onGapEdited(i);
      });
      f.addListener(() {
        if (!mounted) return;
        final i = _gapFocus.indexOf(f);
        if (i < 0) return;
        if (f.hasFocus) {
          _gapIndex = i;
          _gapCursor = c.selection.baseOffset.clamp(0, c.text.length);
        }
        setState(() {});
      });
      _gapCtrls.add(c);
      _gapFocus.add(f);
    }
    for (var i = 0; i < _gaps.length; i++) {
      if (_gapCtrls[i].text != _gaps[i]) {
        _gapCtrls[i].value = TextEditingValue(
          text: _gaps[i],
          selection: TextSelection.collapsed(
            offset: math.min(_gapCursor, _gaps[i].length),
          ),
        );
      }
    }
  }

  void _onGapEdited(int index) {
    if (index < 0 || index >= _gapCtrls.length) return;
    final c = _gapCtrls[index];
    final raw = c.text;
    final cleaned = raw.replaceAll(RegExp('[$_badChars]'), '');
    if (cleaned != raw) {
      final off = c.selection.baseOffset.clamp(0, cleaned.length);
      c.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: off),
      );
    }
    if (index < _gaps.length) _gaps[index] = c.text;
    _gapIndex = index;
    _gapCursor = c.selection.baseOffset.clamp(0, c.text.length);
    setState(() {});
  }

  static ({List<String> toks, List<String> gaps}) _parseTemplate(
    String template,
  ) {
    final re = RegExp(r'\{([^{}]+)\}');
    final toks = <String>[];
    final gaps = <String>[];
    var last = 0;
    for (final m in re.allMatches(template)) {
      gaps.add(template.substring(last, m.start));
      toks.add(m.group(1)!.trim());
      last = m.end;
    }
    gaps.add(template.substring(last));
    if (toks.isEmpty) {
      return (
        toks: [FtpRenameTokens.initials, FtpRenameTokens.n],
        gaps: ['', '-', ''],
      );
    }
    final hasN = toks.any((t) =>
        t.toLowerCase() == FtpRenameTokens.n ||
        t.toLowerCase().startsWith('n|'));
    if (!hasN) {
      toks.add(FtpRenameTokens.n);
      gaps.add('');
    }
    final hasInitials = toks.any((t) {
      final k = t.toLowerCase();
      return k == FtpRenameTokens.initials || k.startsWith('initials|');
    });
    if (!hasInitials) {
      toks.insert(0, FtpRenameTokens.initials);
      gaps.insert(0, '');
      if (gaps.length > 1 && gaps[1].isEmpty) gaps[1] = '-';
    }
    return (toks: toks, gaps: gaps);
  }

  String _serialize() {
    final buf = StringBuffer(_gaps.isEmpty ? '' : _gaps.first);
    for (var i = 0; i < _toks.length; i++) {
      buf.write(_braceFor(_toks[i]));
      buf.write(i + 1 < _gaps.length ? _gaps[i + 1] : '');
    }
    return FtpRenameTemplate.ensureSequenceToken(buf.toString());
  }

  String _braceFor(String rawTok) {
    final body = _bodyOfTok(rawTok);
    final kind = _tokenKind(body);
    if (kind == FtpRenameTokens.date) {
      return '{${_tokWithCase(
        _dateFormat == FtpRenameDateFormats.defaultFormat
            ? FtpRenameTokens.date
            : 'date:$_dateFormat',
        kind,
      )}}';
    }
    if (kind == FtpRenameTokens.time) {
      return '{${_tokWithCase(
        _timeFormat == FtpRenameTimeFormats.defaultFormat
            ? FtpRenameTokens.time
            : 'time:$_timeFormat',
        kind,
      )}}';
    }
    if (kind == FtpRenameTokens.photographer) {
      return '{${_tokWithCase('photographer:$_photoFormat', kind)}}';
    }
    return '{${_tokWithCase(body, kind)}}';
  }

  String _tokenKind(String rawTok) {
    final key = _bodyOfTok(rawTok).toLowerCase();
    if (key == FtpRenameTokens.date || key.startsWith('date:')) {
      return FtpRenameTokens.date;
    }
    if (key == FtpRenameTokens.time || key.startsWith('time:')) {
      return FtpRenameTokens.time;
    }
    if (key == FtpRenameTokens.photographer ||
        key.startsWith('photographer:')) {
      return FtpRenameTokens.photographer;
    }
    if (key == FtpRenameTokens.away || key.startsWith('away:')) {
      return FtpRenameTokens.away;
    }
    if (key == FtpRenameTokens.home || key.startsWith('home:')) {
      return FtpRenameTokens.home;
    }
    if (key == FtpRenameTokens.original || key.startsWith('original:')) {
      return FtpRenameTokens.original;
    }
    if (key == FtpRenameTokens.initials || key.startsWith('initials:')) {
      return FtpRenameTokens.initials;
    }
    if (key == FtpRenameTokens.n || key.startsWith('n:')) {
      return FtpRenameTokens.n;
    }
    if (key.startsWith('iptc:')) {
      final body = _bodyOfTok(rawTok);
      return 'iptc:${body.substring(body.indexOf(':') + 1).trim()}';
    }
    return key;
  }

  bool _isIptcKind(String kind) => kind.toLowerCase().startsWith('iptc:');

  String? _iptcFieldFromKind(String kind) {
    if (!_isIptcKind(kind)) return null;
    final i = kind.indexOf(':');
    if (i < 0) return null;
    final field = kind.substring(i + 1).trim();
    return field.isEmpty ? null : field;
  }

  bool _hasOptional(String kind) {
    final want = _tokenKind(kind).toLowerCase();
    return _toks.any((t) => _tokenKind(t).toLowerCase() == want);
  }

  FtpRenameContext _previewContext(int seqOffset) {
    final photo = _preview.photographer;
    final away = _preview.awayTeam.trim().isNotEmpty
        ? _preview.awayTeam.trim()
        : 'LAK';
    final home = _preview.homeTeam.trim().isNotEmpty
        ? _preview.homeTeam.trim()
        : 'TOR';
    return FtpRenameContext(
      sourcePath: _previewSourcePath,
      date: _previewDate,
      awayTeam: away,
      homeTeam: home,
      photographer: photo,
      initials: _initials,
      sequence: _nextSeq + seqOffset,
      sequenceWidth: _digits,
      iptc: _previewIptc,
      letterCase: _globalCase,
    );
  }

  String _filenameSanitize(String input) {
    var s = input.trim();
    if (s.isEmpty) return '';
    s = s.replaceAll(RegExp(r'[\\/]+'), '-');
    s = s.replaceAll(RegExp(r'\s+'), '_');
    s = s.replaceAll(RegExp(r'[^\w.\-+=@]+'), '');
    return s;
  }

  String _previewValue(String rawTok, int seqOffset) {
    final kind = _tokenKind(rawTok);
    final casing = _caseOf(kind);
    String finish(String value) => FtpRenameCaseFormats.apply(
          _filenameSanitize(value),
          casing,
        );
    switch (kind) {
      case FtpRenameTokens.away:
        final fromSession = _preview.awayTeam.trim();
        return finish(fromSession.isNotEmpty ? fromSession : 'LAK');
      case FtpRenameTokens.home:
        final fromSession = _preview.homeTeam.trim();
        return finish(fromSession.isNotEmpty ? fromSession : 'TOR');
      case FtpRenameTokens.teams:
        final parts = [
          if (_preview.awayTeam.trim().isNotEmpty) _preview.awayTeam.trim(),
          if (_preview.homeTeam.trim().isNotEmpty) _preview.homeTeam.trim(),
        ];
        return finish(parts.isNotEmpty ? parts.join('-') : 'LAK-TOR');
      case FtpRenameTokens.date:
        return finish(
          FtpRenameDateFormats.formatDate(_previewDate, _dateFormat),
        );
      case FtpRenameTokens.time:
        return finish(
          FtpRenameTimeFormats.formatTime(_previewDate, _timeFormat),
        );
      case FtpRenameTokens.photographer:
        final photo = _preview.photographer.trim().isNotEmpty
            ? _preview.photographer.trim()
            : 'Mark Blinch';
        return finish(
          FtpRenamePhotographerFormats.formatName(photo, _photoFormat),
        );
      case FtpRenameTokens.initials:
        return finish(
          FtpRenameTemplate.resolveInitials(
            explicit: _initials,
            photographer: _preview.photographer,
            iptc: _previewIptc,
          ),
        );
      case FtpRenameTokens.original:
        return finish(_preview.originalStem);
      case FtpRenameTokens.n:
        return finish(
          FtpRenameTemplate.formatSequence(
            _nextSeq + seqOffset,
            width: _digits,
          ),
        );
      default:
        final field = _iptcFieldFromKind(kind);
        if (field != null) return finish(_iptcSample(field));
        return '';
    }
  }

  String _iptcSample(String storageKey) {
    final fromFile =
        IptcTemplateApplyService.lookupValue(_previewIptc, storageKey);
    if (fromFile != null && fromFile.trim().isNotEmpty) {
      return _filenameSanitize(fromFile);
    }

    final specs = WireIptcSpecs.fieldsForPanel(WireStyle.getty);
    for (final s in specs) {
      if (s.storageKey.toLowerCase() == storageKey.toLowerCase()) {
        final ex = (s.example ?? '').trim();
        if (ex.isNotEmpty) {
          return ex.replaceAll(RegExp(r'\s+'), '_');
        }
        break;
      }
    }
    switch (storageKey.toLowerCase()) {
      case 'object name':
        return 'OBJ001';
      case 'meid':
        return 'MEID123';
      case 'urgency':
        return '5';
      case 'caption':
        return 'Caption_text';
      case 'keywords':
        return 'hockey';
      case 'personality':
        return 'Player_Name';
      case 'special instructions':
        return 'HAND_OUT';
      default:
        return storageKey.replaceAll(' ', '_');
    }
  }

  String _previewName(int seqOffset) {
    final template = _serialize();
    final resolved = FtpRenameTemplate.resolve(
      template: template,
      context: _previewContext(seqOffset),
    );
    var name = resolved.trim();
    if (name.isEmpty) name = '${_preview.originalStem}.jpg';
    return name;
  }

  IconData _iconFor(String kind) {
    if (_isIptcKind(kind)) return PhosphorIconsRegular.tag;
    switch (kind) {
      case FtpRenameTokens.n:
        return PhosphorIconsRegular.hash;
      case FtpRenameTokens.away:
      case FtpRenameTokens.home:
      case FtpRenameTokens.teams:
        return PhosphorIconsRegular.usersThree;
      case FtpRenameTokens.date:
        return PhosphorIconsRegular.calendarBlank;
      case FtpRenameTokens.time:
        return PhosphorIconsRegular.clock;
      case FtpRenameTokens.photographer:
        return PhosphorIconsRegular.camera;
      case FtpRenameTokens.initials:
        return PhosphorIconsRegular.signature;
      case FtpRenameTokens.original:
        return PhosphorIconsRegular.file;
      default:
        return PhosphorIconsRegular.plus;
    }
  }

  String _labelFor(String kind) {
    final field = _iptcFieldFromKind(kind);
    if (field != null) {
      for (final f in _iptcFields) {
        if (f.key.toLowerCase() == field.toLowerCase()) return f.label;
      }
      return field;
    }
    switch (kind) {
      case FtpRenameTokens.n:
        return 'Sequence';
      case FtpRenameTokens.away:
        return 'Away team';
      case FtpRenameTokens.home:
        return 'Home team';
      case FtpRenameTokens.teams:
        return 'Teams';
      case FtpRenameTokens.date:
        return 'Date';
      case FtpRenameTokens.time:
        return 'Time';
      case FtpRenameTokens.photographer:
        return 'Photographer';
      case FtpRenameTokens.initials:
        return 'Initials';
      case FtpRenameTokens.original:
        return 'Original name';
      default:
        return kind;
    }
  }

  String _chipLabel(String raw) {
    final kind = _tokenKind(raw);
    if (kind == FtpRenameTokens.date) return 'Date $_dateFormat';
    if (kind == FtpRenameTokens.time) return 'Time $_timeFormat';
    return _labelFor(kind);
  }

  Future<void> _pickIptcField() async {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          child: Material(
            color: t.surface,
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: 0.55),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
              side: const BorderSide(color: FfTokens.panelOutline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
                  child: Row(
                    children: [
                      Text(
                        'ADD IPTC FIELD',
                        style: FfTokens.railLabel.copyWith(
                          color: t.text.withValues(alpha: 0.78),
                        ),
                      ),
                      const Spacer(),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.of(ctx).pop(),
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: PhosphorIcon(
                              PhosphorIconsRegular.x,
                              size: 18,
                              color: t.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: t.divider),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: _iptcFields.length,
                    itemBuilder: (context, i) {
                      final f = _iptcFields[i];
                      final tok = _iptcToken(f.key);
                      final on = _hasOptional(tok);
                      return InkWell(
                        onTap: on ? null : () => Navigator.of(ctx).pop(tok),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              PhosphorIcon(
                                PhosphorIconsRegular.tag,
                                size: 16,
                                color: on ? t.textTertiary : t.textSecondary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  f.label,
                                  style: TextStyle(
                                    fontFamily: FfTokens.fontFamily,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: on ? t.textTertiary : t.text,
                                  ),
                                ),
                              ),
                              Text(
                                _iptcSample(f.key),
                                style: TextStyle(
                                  fontFamily: 'JetBrains Mono',
                                  fontSize: 11,
                                  color: t.textTertiary,
                                ),
                              ),
                              const SizedBox(width: 10),
                              PhosphorIcon(
                                on
                                    ? PhosphorIconsBold.check
                                    : PhosphorIconsRegular.plus,
                                size: 15,
                                color: on
                                    ? FfTokens.sessionOk
                                    : t.textTertiary,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || chosen == null) return;
    _addTok(chosen);
  }

  bool _isRequiredKind(String kind) =>
      kind == FtpRenameTokens.n || kind == FtpRenameTokens.initials;

  void _removeTok(int j) {
    if (j < 0 || j >= _toks.length) return;
    if (_isRequiredKind(_tokenKind(_toks[j]))) return;
    final merged = '${_gaps[j]}${_gaps[j + 1]}';
    _gaps
      ..removeAt(j)
      ..[j] = merged;
    _toks.removeAt(j);
    _selectedTok = -1;
    _gapIndex = j;
    _gapCursor = _gaps[j].length;
    _syncGapControllers();
    setState(() {});
    _focusGap(j, _gapCursor);
  }

  Future<void> _confirmRemoveTok(int j) async {
    if (j < 0 || j >= _toks.length) return;
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final kind = _tokenKind(_toks[j]);
    final label = _chipLabel(_toks[j]);
    if (_isRequiredKind(kind)) {
      final title = kind == FtpRenameTokens.n
          ? 'Sequence required'
          : 'Initials required';
      final body = kind == FtpRenameTokens.n
          ? '{$label} can’t be removed — every file name needs a sequence number.'
          : '{$label} can’t be removed — every file name needs initials.';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: t.divider),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          content: Text(
            body,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 13,
              height: 1.35,
              color: t.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'OK',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontWeight: FontWeight.w600,
                  color: t.accent,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: t.divider),
        ),
        title: Text(
          'Remove from pattern?',
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: t.text,
          ),
        ),
        content: Text(
          'Remove {$label} from the name pattern?',
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 13,
            height: 1.35,
            color: t.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontWeight: FontWeight.w600,
                color: t.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Remove',
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontWeight: FontWeight.w700,
                color: FfTokens.danger,
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    _removeTok(j);
  }

  KeyEventResult _handleGapKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (index < 0 || index >= _gapCtrls.length) {
      return KeyEventResult.ignored;
    }
    final c = _gapCtrls[index];
    final text = c.text;
    final sel = c.selection;
    final pos = sel.isValid ? sel.extentOffset : text.length;
    final collapsed = !sel.isValid || sel.isCollapsed;

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (collapsed && pos >= text.length && index < _gaps.length - 1) {
        _focusGap(index + 1, 0);
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (collapsed && pos <= 0 && index > 0) {
        final prev = index - 1;
        final prevLen =
            prev < _gapCtrls.length ? _gapCtrls[prev].text.length : 0;
        _focusGap(prev, prevLen);
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (collapsed && pos <= 0 && index > 0) {
        unawaited(_confirmRemoveTok(index - 1));
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      if (collapsed && pos >= text.length && index < _toks.length) {
        unawaited(_confirmRemoveTok(index));
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _addTok(String kind) {
    if (_hasOptional(kind) || _isRequiredKind(kind)) return;
    final String body;
    if (kind == FtpRenameTokens.date) {
      body = _dateFormat == FtpRenameDateFormats.defaultFormat
          ? FtpRenameTokens.date
          : 'date:$_dateFormat';
    } else if (kind == FtpRenameTokens.time) {
      body = _timeFormat == FtpRenameTimeFormats.defaultFormat
          ? FtpRenameTokens.time
          : 'time:$_timeFormat';
    } else if (kind == FtpRenameTokens.photographer) {
      body = 'photographer:$_photoFormat';
    } else {
      body = kind;
    }
    final raw = _tokWithCase(body, kind);

    // Always append after the last variable, inserting the default separator
    // between the previous token and the new one.
    while (_gaps.length < _toks.length + 1) {
      _gaps.add('');
    }
    while (_gaps.length > _toks.length + 1) {
      _gaps.removeLast();
    }
    final trailing = _gaps.isEmpty ? '' : _gaps.last;
    if (_toks.isEmpty) {
      _toks.add(raw);
      _gaps
        ..clear()
        ..addAll(['', '']);
    } else {
      _gaps[_gaps.length - 1] = _defaultSep;
      _toks.add(raw);
      _gaps.add(trailing);
    }

    _selectedTok = -1;
    _gapIndex = _gaps.length - 1;
    _gapCursor = _gaps.last.length;
    _syncGapControllers();
    setState(() {});
    _focusGap(_gapIndex, _gapCursor);
  }

  /// ReorderableListView reports [to] as the index before removal adjustment.
  void _reorderTok(int from, int to) {
    if (from < 0 || from >= _toks.length) return;
    var insertAt = to;
    if (insertAt > from) insertAt -= 1;
    if (insertAt < 0) insertAt = 0;
    if (insertAt >= _toks.length) insertAt = _toks.length - 1;
    if (from == insertAt) return;
    final tok = _toks.removeAt(from);
    // Keep the gap that sits before this token with it.
    final gap = (from < _gaps.length) ? _gaps.removeAt(from) : '';
    _toks.insert(insertAt, tok);
    if (insertAt <= _gaps.length) {
      _gaps.insert(insertAt, gap);
    } else {
      _gaps.add(gap);
    }
    // gaps must stay toks.length + 1
    while (_gaps.length < _toks.length + 1) {
      _gaps.add('');
    }
    while (_gaps.length > _toks.length + 1) {
      _gaps.removeLast();
    }
    _dragTok = -1;
    _selectedTok = insertAt;
    _syncGapControllers();
    setState(() {});
  }

  void _setDateFormat(String format) {
    setState(() {
      _dateFormat = FtpRenameDateFormats.normalize(format);
      for (var i = 0; i < _toks.length; i++) {
        if (_tokenKind(_toks[i]) == FtpRenameTokens.date) {
          _toks[i] = _tokWithCase(
            _dateFormat == FtpRenameDateFormats.defaultFormat
                ? FtpRenameTokens.date
                : 'date:$_dateFormat',
            FtpRenameTokens.date,
          );
        }
      }
    });
  }

  void _setTimeFormat(String format) {
    setState(() {
      _timeFormat = FtpRenameTimeFormats.normalize(format);
      for (var i = 0; i < _toks.length; i++) {
        if (_tokenKind(_toks[i]) == FtpRenameTokens.time) {
          _toks[i] = _tokWithCase(
            _timeFormat == FtpRenameTimeFormats.defaultFormat
                ? FtpRenameTokens.time
                : 'time:$_timeFormat',
            FtpRenameTokens.time,
          );
        }
      }
    });
  }

  void _setPhotoFormat(String format) {
    setState(() {
      _photoFormat = FtpRenamePhotographerFormats.normalize(format);
      for (var i = 0; i < _toks.length; i++) {
        if (_tokenKind(_toks[i]) == FtpRenameTokens.photographer) {
          _toks[i] = _tokWithCase(
            'photographer:$_photoFormat',
            FtpRenameTokens.photographer,
          );
        }
      }
    });
  }

  void _applyCaseToKind(String kind, String casing) {
    _cases[kind] = FtpRenameCaseFormats.normalize(casing);
    for (var i = 0; i < _toks.length; i++) {
      if (_tokenKind(_toks[i]) != kind) continue;
      final body = _bodyOfTok(_toks[i]);
      if (kind == FtpRenameTokens.date) {
        _toks[i] = _tokWithCase(
          _dateFormat == FtpRenameDateFormats.defaultFormat
              ? FtpRenameTokens.date
              : 'date:$_dateFormat',
          kind,
        );
      } else if (kind == FtpRenameTokens.time) {
        _toks[i] = _tokWithCase(
          _timeFormat == FtpRenameTimeFormats.defaultFormat
              ? FtpRenameTokens.time
              : 'time:$_timeFormat',
          kind,
        );
      } else if (kind == FtpRenameTokens.photographer) {
        _toks[i] = _tokWithCase('photographer:$_photoFormat', kind);
      } else {
        _toks[i] = _tokWithCase(body, kind);
      }
    }
  }

  void _setCase(String kind, String casing) {
    setState(() => _applyCaseToKind(kind, casing));
  }

  void _stepCase(String kind, int delta) {
    final cur = _caseOf(kind);
    _setCase(
      kind,
      delta < 0
          ? FtpRenameCaseFormats.previous(cur)
          : FtpRenameCaseFormats.next(cur),
    );
  }

  void _stepGlobalCase() {
    setState(() {
      _globalCase = FtpRenameCaseFormats.next(_globalCase);
      // Sync every variable tile + token in the pattern to match.
      final kinds = <String>{
        ..._optionalOrder,
        FtpRenameTokens.initials,
        FtpRenameTokens.n,
        for (final tok in _toks) _tokenKind(tok),
      };
      for (final kind in kinds) {
        _applyCaseToKind(kind, _globalCase);
      }
    });
  }

  void _onDefaultSepEdited() {
    if (!mounted) return;
    final raw = _defaultSepCtrl.text;
    final cleaned = FtpRenameTemplate.normalizeSeparator(raw);
    if (cleaned != raw) {
      _defaultSepCtrl.value = TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
    }
    final prev = _defaultSep;
    if (cleaned == prev) return;
    setState(() {
      _defaultSep = cleaned;
      // Gaps that still match the previous default follow the new one.
      for (var i = 1; i < _toks.length; i++) {
        if (i >= _gaps.length) break;
        if (_gaps[i] == prev) _gaps[i] = cleaned;
      }
      _syncGapControllers();
    });
  }

  void _stepPhotoFormat(int delta) {
    _setPhotoFormat(
      delta < 0
          ? FtpRenamePhotographerFormats.previous(_photoFormat)
          : FtpRenamePhotographerFormats.next(_photoFormat),
    );
  }

  void _stepDateOrder(int delta) {
    _setDateFormat(
      delta < 0
          ? FtpRenameDateFormats.previousOrder(_dateFormat)
          : FtpRenameDateFormats.nextOrder(_dateFormat),
    );
  }

  void _stepDateSeparator(int delta) {
    _setDateFormat(
      delta < 0
          ? FtpRenameDateFormats.previousSeparator(_dateFormat)
          : FtpRenameDateFormats.nextSeparator(_dateFormat),
    );
  }

  void _stepTimeClock(int delta) {
    _setTimeFormat(
      delta < 0
          ? FtpRenameTimeFormats.previousClock(_timeFormat)
          : FtpRenameTimeFormats.nextClock(_timeFormat),
    );
  }

  void _stepTimeSeparator(int delta) {
    _setTimeFormat(
      delta < 0
          ? FtpRenameTimeFormats.previousSeparator(_timeFormat)
          : FtpRenameTimeFormats.nextSeparator(_timeFormat),
    );
  }

  void _focusGap(int index, int cursor) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (index < 0 || index >= _gapFocus.length) return;
      _gapFocus[index].requestFocus();
      final c = _gapCtrls[index];
      final off = cursor.clamp(0, c.text.length);
      c.selection = TextSelection.collapsed(offset: off);
    });
  }

  Future<void> _openCameraSerials() async {
    final camera = CameraSerialService.instance;
    await camera.initialize();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) => CameraSerialDialog(cameraService: camera),
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _save() async {
    final name = _profileName;
    if (name == null) return;
    final template = _serialize();
    final prefs = await PreferencesService.getInstance();
    final profiles = await prefs.getFtpProfiles();
    final existing = Map<String, dynamic>.from(profiles[name] ?? {});
    existing['renameAs'] = template;
    existing['renameLetterCase'] = _globalCase;
    existing['renameDefaultSep'] = _defaultSep;
    profiles[name] = existing;
    await prefs.saveFtpProfiles(profiles);
    await prefs.saveCurrentFtpProfile(name);
    await NumberSequenceService.instance.save(
      digits: _digits,
      next: _nextSeq,
    );
    await prefs.saveRenameInitials(_initialsCtrl.text);
    if (!mounted) return;
    Navigator.of(context).pop(template);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final screenH = MediaQuery.sizeOf(context).height;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1150,
          minHeight: (screenH * 0.82).clamp(560.0, 900.0),
          maxHeight: screenH - 32,
        ),
        child: Material(
          color: t.surface,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.55),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
            side: const BorderSide(color: FfTokens.panelOutline),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: (screenH * 0.88).clamp(600.0, screenH - 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(t),
                if (_loading)
                  const Expanded(
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (_error != null)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _error!,
                            style: TextStyle(
                              fontFamily: FfTokens.fontFamily,
                              fontSize: 13,
                              color: t.textSecondary,
                            ),
                          ),
                          const Spacer(),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedGreyButton(
                              label: 'Close',
                              fontSize: 12,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildPreviewAndSequence(t),
                          const SizedBox(height: 18),
                          _buildPattern(t),
                          const SizedBox(height: 18),
                          _buildAddGrid(t),
                        ],
                      ),
                    ),
                  ),
                if (!_loading && _error == null) _buildFooter(t),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(FfTokens t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 16, 16, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.divider)),
      ),
      child: Row(
        children: [
          Text(
            'FILE RENAMING',
            style: FfTokens.railLabel.copyWith(
              color: t.text.withValues(alpha: 0.78),
            ),
          ),
          if (_profileName != null) ...[
            const SizedBox(width: 12),
            Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: FfTokens.card,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PhosphorIcon(
                    PhosphorIconsFill.cloudArrowUp,
                    size: 13,
                    color: t.accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _profileName!,
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 32,
                height: 32,
                child: PhosphorIcon(
                  PhosphorIconsRegular.x,
                  size: 18,
                  color: t.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewAndSequence(FfTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(t, 'Preview'),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 420, child: _buildPreviewCard(t)),
              const SizedBox(width: 12),
              SizedBox(width: 120, child: _buildInitialsCard(t)),
              const SizedBox(width: 12),
              SizedBox(width: 340, child: _buildSequenceCard(t)),
              const Spacer(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInitialsCard(FfTokens t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: FfTokens.nocturneAccentRow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FfTokens.nocturneAccentEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: FfTokens.nocturneAccentSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const PhosphorIcon(
                  PhosphorIconsRegular.signature,
                  size: 18,
                  color: FfTokens.accentHover,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Initials',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            height: 38,
            child: TextField(
              controller: _initialsCtrl,
              textCapitalization: TextCapitalization.characters,
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: t.text,
              ),
              inputFormatters: [
                LengthLimitingTextInputFormatter(8),
                FilteringTextInputFormatter.deny(RegExp('[$_badChars]')),
              ],
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: t.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard(FfTokens t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PhosphorIcon(
                PhosphorIconsRegular.image,
                size: 18,
                color: t.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _previewName(0),
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 22 / 16,
                    color: t.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              '${_previewName(1)}\n${_previewName(2)}',
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 18 / 12,
                color: t.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPattern(FfTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(
          t,
          'Name pattern',
          trailing: 'Type between · drag to reorder · right-click for options',
        ),
        Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: t.sunken,
            borderRadius: BorderRadius.circular(11),
          ),
          child: SizedBox(
            height: _patternLineHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    buildDefaultDragHandles: false,
                    primary: false,
                    onReorderStart: (i) => setState(() => _dragTok = i),
                    onReorderEnd: (_) => setState(() => _dragTok = -1),
                    onReorder: _reorderTok,
                    proxyDecorator: (child, index, animation) {
                      return Material(
                        color: Colors.transparent,
                        elevation: 6,
                        child: child,
                      );
                    },
                    itemCount: _toks.length,
                    itemBuilder: (context, i) {
                      return KeyedSubtree(
                        key: ValueKey('pattern-${_toks[i]}#$i'),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IgnorePointer(
                              ignoring: _dragTok >= 0,
                              child: _gapEditor(t, i),
                            ),
                            _tokenChip(t, i),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                IgnorePointer(
                  ignoring: _dragTok >= 0,
                  child: _gapEditor(
                    t,
                    _toks.length,
                    solo: _toks.isEmpty,
                    trailing: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static const _patternFontSize = 15.0;
  static const _patternLineHeight = 28.0;

  static const _patternTextStyle = TextStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: _patternFontSize,
    fontWeight: FontWeight.w600,
    height: 1.0,
    leadingDistribution: TextLeadingDistribution.even,
  );

  static const _patternStrut = StrutStyle(
    fontFamily: 'JetBrains Mono',
    fontSize: _patternFontSize,
    height: 1.0,
    forceStrutHeight: true,
    leadingDistribution: TextLeadingDistribution.even,
  );

  double _measureGapWidth(
    String text, {
    required bool solo,
    bool trailing = false,
  }) {
    if (solo && text.isEmpty) return 120;
    // Empty trailing gap needs a real click target after the last chip.
    // Keep mid empty gaps tiny so `_` separators don't look spaced out.
    if (text.isEmpty) return trailing ? 56 : 2;
    final painter = TextPainter(
      text: TextSpan(text: text, style: _patternTextStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      strutStyle: _patternStrut,
    )..layout();
    // +1 for caret only — extra padding made `_` look like `_ `.
    final w = painter.width + 1;
    if (trailing) return w.clamp(56.0, 280.0);
    return w.clamp(2.0, 280.0);
  }

  Widget _gapEditor(
    FfTokens t,
    int index, {
    bool solo = false,
    bool trailing = false,
  }) {
    if (index >= _gapCtrls.length) return const SizedBox.shrink();
    final text = _gapCtrls[index].text;
    final width = _measureGapWidth(text, solo: solo, trailing: trailing);
    final style = _patternTextStyle.copyWith(color: FfTokens.sessionTx);
    final focused = index < _gapFocus.length && _gapFocus[index].hasFocus;
    // TextField on desktop paints off the Text baseline. Show matching Text
    // for glyphs; keep a transparent field on top for caret + typing.
    return SizedBox(
      width: width,
      height: _patternLineHeight,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (trailing && text.isEmpty && !focused)
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 1.5,
                height: 16,
                margin: const EdgeInsets.only(left: 1),
                color: t.textTertiary.withValues(alpha: 0.35),
              ),
            ),
          Text(
            text.isEmpty && solo ? '' : text,
            maxLines: 1,
            softWrap: false,
            style: style,
            strutStyle: _patternStrut,
          ),
          TextField(
            controller: _gapCtrls[index],
            focusNode: _gapFocus[index],
            style: style.copyWith(color: Colors.transparent),
            strutStyle: _patternStrut,
            cursorColor: FfTokens.sessionTx,
            cursorWidth: 1.5,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp('[$_badChars]')),
            ],
            onTap: () {
              _gapIndex = index;
              _gapCursor = _gapCtrls[index].selection.baseOffset
                  .clamp(0, _gapCtrls[index].text.length);
              setState(() {});
            },
            onChanged: (_) {
              _gapIndex = index;
              _gapCursor = _gapCtrls[index].selection.baseOffset
                  .clamp(0, _gapCtrls[index].text.length);
            },
          ),
        ],
      ),
    );
  }

  Widget _tokenChipFace(
    FfTokens t, {
    required int index,
    required String raw,
    required bool selected,
    double opacity = 1,
    bool highlight = false,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Opacity(
        opacity: opacity,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: _patternLineHeight,
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: highlight ? FfTokens.sessionOn.withValues(alpha: 0.12) : null,
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '{',
                style: _patternTextStyle.copyWith(color: FfTokens.sessionOn),
                strutStyle: _patternStrut,
              ),
              Text(
                _chipLabel(raw),
                style: _patternTextStyle.copyWith(
                  fontWeight: FontWeight.w700,
                  color: FfTokens.sessionOn,
                ),
                strutStyle: _patternStrut,
              ),
              Text(
                '}',
                style: _patternTextStyle.copyWith(color: FfTokens.sessionOn),
                strutStyle: _patternStrut,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tokenChip(FfTokens t, int index) {
    final raw = _toks[index];
    final kind = _tokenKind(raw);
    final required = _isRequiredKind(kind);
    final selected = _selectedTok == index;
    final dragging = _dragTok == index;

    // ReorderableDragStartListener: immediate mouse drag on desktop for every
    // chip — including required {n} / {initials} (required only blocks remove).
    return ReorderableDragStartListener(
      index: index,
      child: GestureDetector(
        onTap: () => setState(() => _selectedTok = selected ? -1 : index),
        onSecondaryTapDown: required
            ? null
            : (details) async {
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
                if (action == 'remove') unawaited(_confirmRemoveTok(index));
              },
        child: _tokenChipFace(
          t,
          index: index,
          raw: raw,
          selected: selected,
          opacity: dragging ? 0.4 : 1,
        ),
      ),
    );
  }

  Widget _buildSequenceCard(FfTokens t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: FfTokens.nocturneAccentRow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FfTokens.nocturneAccentEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: FfTokens.nocturneAccentSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const PhosphorIcon(
                  PhosphorIconsRegular.hash,
                  size: 18,
                  color: FfTokens.accentHover,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sequence',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Number of digits',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: t.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 148,
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: t.bg,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    children: [
                      _stepBtn(
                        t,
                        icon: PhosphorIconsRegular.minus,
                        enabled: _digits >
                            PreferencesService.numberSequenceDigitsMin,
                        onTap: () => setState(() {
                          _digits = (_digits - 1).clamp(
                            PreferencesService.numberSequenceDigitsMin,
                            PreferencesService.numberSequenceDigitsMax,
                          );
                        }),
                      ),
                      Expanded(
                        child: Text(
                          FtpRenameTemplate.formatSequence(
                            _nextSeq,
                            width: _digits,
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                      _stepBtn(
                        t,
                        icon: PhosphorIconsRegular.plus,
                        enabled: _digits <
                            PreferencesService.numberSequenceDigitsMax,
                        onTap: () => setState(() {
                          _digits = (_digits + 1).clamp(
                            PreferencesService.numberSequenceDigitsMin,
                            PreferencesService.numberSequenceDigitsMax,
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(
    FfTokens t, {
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 30,
          height: 32,
          child: PhosphorIcon(
            icon,
            size: 13,
            color: enabled ? t.textSecondary : t.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _caseButton(
    FfTokens t, {
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: t.sunken,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 32,
          width: 34,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formatStepper(
    FfTokens t, {
    required String label,
    required String value,
    required VoidCallback onPrev,
    required VoidCallback onNext,
    double minValueWidth = 72,
  }) {
    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 8, right: 2),
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(width: 4),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPrev,
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 20,
                height: 28,
                child: PhosphorIcon(
                  PhosphorIconsRegular.caretLeft,
                  size: 12,
                  color: t.textSecondary,
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: minValueWidth),
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: t.text,
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onNext,
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 20,
                height: 28,
                child: PhosphorIcon(
                  PhosphorIconsRegular.caretRight,
                  size: 12,
                  color: t.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddGrid(FfTokens t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Text(
                'ADD TO NAME',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1 * 11,
                  color: t.textTertiary,
                ),
              ),
              const Spacer(),
              _caseButton(
                t,
                label: FtpRenameCaseFormats.labelOf(_globalCase),
                onTap: _stepGlobalCase,
              ),
              const SizedBox(width: 8),
              Text(
                'Separator between variables',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: t.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 56,
                height: 32,
                child: TextField(
                  controller: _defaultSepCtrl,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(8),
                    FilteringTextInputFormatter.deny(RegExp('[$_badChars]')),
                  ],
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: t.sunken,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 520;
            final tileW = wide
                ? (constraints.maxWidth - 4) / 2
                : constraints.maxWidth;
            final iptcKinds = <String>[
              for (final tok in _toks)
                if (_isIptcKind(_tokenKind(tok))) _tokenKind(tok),
            ];
            final seenIptc = <String>{};
            final uniqueIptc = <String>[
              for (final k in iptcKinds)
                if (seenIptc.add(k)) k,
            ];
            return Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final kind in _optionalOrder)
                  SizedBox(
                    width: tileW,
                    child: _addTile(t, kind),
                  ),
                for (final kind in uniqueIptc)
                  SizedBox(
                    width: tileW,
                    child: _addTile(t, kind),
                  ),
                SizedBox(
                  width: tileW,
                  child: _addIptcTile(t),
                ),
              ],
            );
          },
        ),
        if (_serialBylines) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedGreyButton(
              label: 'Cameras',
              fontSize: 11,
              onPressed: () => unawaited(_openCameraSerials()),
            ),
          ),
        ],
      ],
    );
  }

  Widget _addIptcTile(FfTokens t) {
    final added = _toks.where((tok) => _isIptcKind(_tokenKind(tok))).length;
    return Material(
      color: FfTokens.card,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: () => unawaited(_pickIptcField()),
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                PhosphorIcon(
                  PhosphorIconsRegular.tag,
                  size: 17,
                  color: t.textTertiary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    added > 0 ? 'IPTC field ($added)' : 'IPTC field',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                ),
                PhosphorIcon(
                  PhosphorIconsRegular.plus,
                  size: 15,
                  color: t.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _addTile(FfTokens t, String kind) {
    final required = _isRequiredKind(kind);
    final on = required || _hasOptional(kind);
    final sample = _previewValue(kind, 0);
    void toggle() {
      if (required) return;
      if (on) {
        final i = _toks.indexWhere((tok) => _tokenKind(tok) == kind);
        if (i >= 0) _removeTok(i);
      } else {
        _addTok(kind);
      }
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: on ? Colors.transparent : FfTokens.card,
        borderRadius: BorderRadius.circular(9),
        border: on ? Border.all(color: t.divider) : null,
      ),
      child: Row(
        children: [
          MouseRegion(
            cursor: required
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: toggle,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PhosphorIcon(
                    _iconFor(kind),
                    size: 17,
                    color: t.textTertiary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _labelFor(kind),
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: on ? t.textSecondary : t.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: MouseRegion(
              cursor: required
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click,
              child: GestureDetector(
                onTap: toggle,
                child: Text(
                  sample,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: t.textTertiary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (kind == FtpRenameTokens.date) ...[
            _formatStepper(
              t,
              label: 'Order',
              value: FtpRenameDateFormats.orderOf(_dateFormat),
              onPrev: () => _stepDateOrder(-1),
              onNext: () => _stepDateOrder(1),
              minValueWidth: 78,
            ),
            const SizedBox(width: 4),
            _formatStepper(
              t,
              label: 'Separator',
              value: FtpRenameDateFormats.separatorLabel(
                FtpRenameDateFormats.separatorOf(_dateFormat),
              ),
              onPrev: () => _stepDateSeparator(-1),
              onNext: () => _stepDateSeparator(1),
              minValueWidth: 36,
            ),
            const SizedBox(width: 4),
          ] else if (kind == FtpRenameTokens.time) ...[
            _formatStepper(
              t,
              label: 'Clock',
              value: FtpRenameTimeFormats.clockLabel(_timeFormat),
              onPrev: () => _stepTimeClock(-1),
              onNext: () => _stepTimeClock(1),
              minValueWidth: 64,
            ),
            const SizedBox(width: 4),
            _formatStepper(
              t,
              label: 'Separator',
              value: FtpRenameTimeFormats.separatorLabel(
                FtpRenameTimeFormats.separatorOf(_timeFormat),
              ),
              onPrev: () => _stepTimeSeparator(-1),
              onNext: () => _stepTimeSeparator(1),
              minValueWidth: 36,
            ),
            const SizedBox(width: 4),
          ] else if (kind == FtpRenameTokens.photographer) ...[
            _formatStepper(
              t,
              label: 'Name',
              value: FtpRenamePhotographerFormats.labelOf(_photoFormat),
              onPrev: () => _stepPhotoFormat(-1),
              onNext: () => _stepPhotoFormat(1),
              minValueWidth: 72,
            ),
            const SizedBox(width: 4),
          ],
          _caseButton(
            t,
            label: FtpRenameCaseFormats.labelOf(_caseOf(kind)),
            onTap: () => _stepCase(kind, 1),
          ),
          const SizedBox(width: 8),
          MouseRegion(
            cursor: required
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: GestureDetector(
              onTap: toggle,
              child: PhosphorIcon(
                on ? PhosphorIconsBold.check : PhosphorIconsRegular.plus,
                size: 15,
                color: on ? FfTokens.sessionOk : t.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(FfTokens t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 16, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.divider)),
      ),
      child: Row(
        children: [
          PhosphorIcon(
            PhosphorIconsFill.checkCircle,
            size: 15,
            color: FfTokens.sessionOk,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Applies on FTP upload',
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12,
                color: t.textTertiary,
              ),
            ),
          ),
          ElevatedGreyButton(
            label: 'Cancel',
            fontSize: 13,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          ElevatedGreyButton(
            label: 'Save',
            fontSize: 13,
            isPrimary: true,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(FfTokens t, String title, {String? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1 * 11,
              color: t.textTertiary,
            ),
          ),
          if (trailing != null && trailing.isNotEmpty) ...[
            const Spacer(),
            Text(
              trailing,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: t.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
