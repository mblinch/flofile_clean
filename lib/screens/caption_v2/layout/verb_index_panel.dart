import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../caption_style/verb_index_filter_mode.dart';
import '../../../theme/ff_tokens.dart';
import '../caption_v2_shortcuts.dart';
import '../data/caption_v2_controller.dart';
import '../data/effective_verb_catalog.dart';
import 'caption_v2_verb_editor.dart';
import 'verb_accordion.dart';

/// Motion system from Verb Index v3 / Verb Panel Polish.
const _kEase = Cubic(0.2, 0.8, 0.2, 1);
const _kPillMs = Duration(milliseconds: 90);
const _kUiMs = Duration(milliseconds: 220);
const _kHoldMs = Duration(milliseconds: 900);
const _kVerbInk = Color(0xFFD8DEE4);
const _kDimVerb = Color(0xFF454C52);
const _kDimLetter = Color(0xFF2F363C);
const _kFilterDim = Color(0xFF5A6168);
const _kDot = Color(0xFF3A4148);
/// Inter-verb separator circle diameter.
const _kSepDotSize = 5.0;
const _kMatch = Color(0xFFE8763A);
const _kPill = Color(0xFF2F363C);
const _kSelectedFill = Color(0xFF20313C);
const _kSelectedEdge = Color(0xFF3A6076);
const _kGold = Color(0xFFE8C547);
const _kGoldInk = Color(0xFF1A1606);
/// Index letter ink — matches roster jersey numbers.
const _kLetterInk = Color(0xFFF2F6FA);
const _kDivider = Color(0x0FE8EEF4); // ~.06
const _kHoverWash = Color(0x0FE8EEF4); // rgba(232,238,244,.06)
const _kHomeRow = 'asdfjkl';

/// Shared letter/icon column + gap for History and letter rows.
/// Header Fix: grid 28px / 14px, list inset 10, row left pad 6.
const _kLetterColW = 28.0;
const _kLetterColGap = 14.0;
const _kListSidePad = 10.0;
const _kRowSidePad = 6.0;
/// Match player-lane header height ([_RosterTopBar.barHeight] = 36).
const _kTopBarH = 36.0;

const _kFiller = {'to', 'the', 'a', 'off', 'in', 'of', 'on'};

/// Index letters + verb chips on Inter. Chips at weight 300 / opsz 22
/// (between text and display — a bit less crunchy than opsz 14).
/// `inherit: false` so Theme/DefaultTextStyle can't re-bold chips.
TextStyle _verbIndexTextStyle({
  required double fontSize,
  required Color color,
  FontWeight weight = FontWeight.w300,
  double height = 1,
  double? letterSpacing,
  bool thinFace = false,
  List<Shadow>? shadows,
}) {
  final wght = weight.value.toDouble();
  return TextStyle(
    inherit: false,
    fontFamily: FfTokens.fontFamily,
    fontSize: fontSize,
    fontWeight: FontWeight.w400,
    height: height,
    letterSpacing: letterSpacing,
    color: color,
    shadows: shadows,
    decoration: TextDecoration.none,
    fontVariations: [
      FontVariation('wght', thinFace ? 300.0 : wght),
      FontVariation('opsz', thinFace ? 22.0 : fontSize.clamp(14.0, 32.0)),
    ],
  );
}

/// Soft text glow for index letters — same recipe as roster jersey numbers.
List<Shadow> _letterGlow({
  required bool gold,
  required bool emphasized,
}) {
  return [
    Shadow(
      color: gold
          ? const Color(0x8CE8C547)
          : Colors.white.withValues(alpha: emphasized ? 0.55 : 0.35),
      blurRadius: gold ? 8 : (emphasized ? 10 : 6),
    ),
  ];
}

class VerbIndexDensityMetrics {
  const VerbIndexDensityMetrics({
    required this.lineHeight,
    required this.pad,
    required this.gap,
  });

  final double lineHeight;
  final double pad;
  final double gap;

  /// Cozy spacing for the verb index (lh ≈ fs+5 so A–W fits).
  factory VerbIndexDensityMetrics.from(double fontSize) {
    // Verb column gap is fixed at 20px (--cg).
    return VerbIndexDensityMetrics(
      lineHeight: fontSize + 5,
      pad: 1,
      gap: 20,
    );
  }

  /// Chip highlight pad each side (padding:0 6px; margin:0 -6px).
  static const double chipPad = 6;

  /// Wrap spacing so text-to-text distance equals [gap] (padding cancels).
  double get wrapSpacing => math.max(2, gap - chipPad * 2);

  /// Dot left inset so the circle is centered in the gap between chips.
  double get sepDotLeft => chipPad - gap / 2 - _kSepDotSize / 2;
}

/// How many wrap rows [verbs] need at [fontSize] inside [wrapWidth].
int estimateVerbWrapLines({
  required List<EffectiveVerb> verbs,
  required double fontSize,
  required VerbIndexDensityMetrics dens,
  required double wrapWidth,
  required TextScaler textScaler,
}) {
  if (verbs.isEmpty) return 1;
  final style = _verbIndexTextStyle(
    fontSize: fontSize,
    color: _kVerbInk,
    thinFace: true,
  );
  var lines = 1;
  var x = 0.0;
  const chrome = VerbIndexDensityMetrics.chipPad * 2 + 2;
  for (var i = 0; i < verbs.length; i++) {
    final painter = TextPainter(
      text: TextSpan(text: verbs[i].label, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final chipW = painter.width + chrome;
    if (i == 0) {
      x = chipW;
      continue;
    }
    final next = x + dens.wrapSpacing + chipW;
    if (next > wrapWidth + 0.5) {
      lines++;
      x = chipW;
    } else {
      x = next;
    }
  }
  return lines;
}

/// Largest type ≤ [preferredFs] that keeps history verbs within [maxLines].
double historyFontToFit({
  required List<EffectiveVerb> verbs,
  required double preferredFs,
  required double wrapWidth,
  required TextScaler textScaler,
  double minFs = 11,
  int maxLines = 3,
}) {
  if (verbs.isEmpty || wrapWidth < 1) return preferredFs;
  final steps = math.max(0, ((preferredFs - minFs) * 10).round());
  for (var i = 0; i <= steps; i++) {
    final fs = preferredFs - i / 10.0;
    final dens = VerbIndexDensityMetrics.from(fs);
    if (estimateVerbWrapLines(
          verbs: verbs,
          fontSize: fs,
          dens: dens,
          wrapWidth: wrapWidth,
          textScaler: textScaler,
        ) <=
        maxLines) {
      return fs;
    }
  }
  return minFs;
}

class VerbMatchScore {
  const VerbMatchScore({required this.rank, required this.ranges});

  final int rank;
  final List<(int, int)> ranges;
}

/// Whole-label prefix, any-word prefix, or initials skipping filler words.
VerbMatchScore? scoreVerbMatch(String label, String query) {
  final s = query.trim().toLowerCase();
  if (s.isEmpty) return null;
  final lo = label.toLowerCase();
  final words = lo.split(RegExp(r'\s+'));
  if (lo.startsWith(s)) {
    return VerbMatchScore(rank: 0, ranges: [(0, s.length)]);
  }
  var p = 0;
  for (final w in words) {
    if (w.startsWith(s)) {
      return VerbMatchScore(rank: 1, ranges: [(p, s.length)]);
    }
    p += w.length + 1;
  }
  if (s.length > 1) {
    final hl = <(int, int)>[];
    var j = 0;
    p = 0;
    for (final w in words) {
      if (j < s.length && !_kFiller.contains(w) && w.isNotEmpty && w[0] == s[j]) {
        hl.add((p, 1));
        j++;
      }
      p += w.length + 1;
    }
    if (j == s.length) return VerbMatchScore(rank: 2, ranges: hl);
  }
  return null;
}

class _UndoSnap {
  _UndoSnap({
    required this.selectedVerb,
    required this.history,
    required this.burstMemory,
    required this.hadSelected,
  });

  final String? selectedVerb;
  final List<String> history;
  final String? burstMemory;
  final bool hadSelected;
}

/// Scrollable Verb Index body (History + letter / category rows).
class VerbIndexPanel extends StatefulWidget {
  const VerbIndexPanel({
    super.key,
    required this.controller,
    required this.filterController,
    required this.filterFocusNode,
    required this.tokens,
    required this.onVerbArmed,
    required this.onToggleFavorite,
    this.onAddCustom,
    this.onMatchCountChanged,
  });

  final CaptionV2Controller controller;
  final TextEditingController filterController;
  final FocusNode filterFocusNode;
  final FfTokens tokens;
  final ValueChanged<EffectiveVerb> onVerbArmed;
  final Future<void> Function(String key) onToggleFavorite;
  final ValueChanged<String>? onAddCustom;
  final ValueChanged<int>? onMatchCountChanged;

  @override
  State<VerbIndexPanel> createState() => VerbIndexPanelState();
}

class VerbIndexPanelState extends State<VerbIndexPanel> {
  /// Fit snaps to the chosen size. Skip the chip/letter tween for that frame.
  static bool suppressMotion = false;
  final _scroll = ScrollController();
  final _listKey = GlobalKey();
  final _verbKeys = <String, GlobalKey>{};
  final _pressing = <String>{};

  String? _hoveredKey;
  String? _hoveredGroup;
  String? _focusKey;
  bool _keyboardMode = false;
  bool _cmdHeld = false;
  bool _altHints = false;
  bool _shortcutsOpen = false;
  String _altBuf = '';

  Rect? _pillRect;
  bool _pillVisible = false;
  bool _pillSnap = false;

  List<String> _matchKeys = [];
  Map<String, VerbMatchScore> _scores = {};

  _UndoSnap? _undo;
  Timer? _holdTimer;
  int _dotsTick = 0;
  double? _lastFs;
  VerbIndexFilterMode? _lastFilterMode;
  bool _lastHideOthers = false;
  bool _dotsScheduled = false;
  bool _canScrollDown = false;

  CaptionV2Controller get c => widget.controller;

  Size? _lastWindowSize;
  Size? _lastListSize;
  bool _fitScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final window = MediaQuery.sizeOf(context);
    final changed = _lastWindowSize != null && _lastWindowSize != window;
    _lastWindowSize = window;
    if (!changed) return;
    _scheduleFitToBox();
  }

  void _scheduleFitToBox() {
    if (_fitScheduled) return;
    _fitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitScheduled = false;
      if (mounted) fitToBox();
    });
  }

  void _onListSizeMaybeChanged(Size size) {
    if (_lastListSize != null &&
        (_lastListSize!.width - size.width).abs() < 0.5 &&
        (_lastListSize!.height - size.height).abs() < 0.5) {
      return;
    }
    final first = _lastListSize == null;
    _lastListSize = size;
    // Initial layout already fits via [_fitWhenReady]; only re-fit on change.
    if (!first) _scheduleFitToBox();
  }

  @override
  void initState() {
    super.initState();
    widget.filterController.addListener(_onFilterChanged);
    _scroll.addListener(_onScroll);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyBurstPrefocus();
      _recomputeMatches();
      _fitWhenReady();
    });
  }

  @override
  void dispose() {
    widget.filterController.removeListener(_onFilterChanged);
    _scroll.removeListener(_onScroll);
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _scroll.dispose();
    _holdTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    final key = _hoveredKey ?? (_keyboardMode ? _focusKey : null);
    if (key != null) _movePillTo(key);
    _updateScrollFade();
  }

  void _updateScrollFade() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final next = pos.maxScrollExtent > 2 &&
        pos.pixels < pos.maxScrollExtent - 2;
    if (next != _canScrollDown) {
      setState(() => _canScrollDown = next);
    }
  }

  /// Largest type that still fills the list box without scrolling.
  ///
  /// Chosen in 0.1px steps from the current chip widths and the gap under
  /// the last row, then applied once.
  Future<void> fitToBox() async {
    if (!_scroll.hasClients || !mounted) return;
    final size = _fitSizeFromChips();
    if (size == null) return;
    // Remember Fit so aA stepping can return to this size.
    c.rememberVerbIndexFitFontSize(size);
    if ((size - c.verbIndexFontSize).abs() < 0.05) return;
    VerbIndexPanelState.suppressMotion = true;
    try {
      await c.setVerbIndexFontSize(size);
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      await WidgetsBinding.instance.endOfFrame;
      VerbIndexPanelState.suppressMotion = false;
      if (mounted) setState(() {});
    }
  }

  void _fitWhenReady({int attempt = 0}) {
    if (!mounted) return;
    if (!_scroll.hasClients || _visualGap() == null) {
      if (attempt < 8) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _fitWhenReady(attempt: attempt + 1),
        );
      }
      return;
    }
    fitToBox();
  }

  /// Largest 0.1px size that still fits. Null when the list is not laid out.
  double? _fitSizeFromChips() {
    final viewport = _scroll.position.viewportDimension;
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null || !listBox.hasSize || viewport <= 0) return null;
    final contentW =
        (listBox.size.width - _kListSidePad * 2).clamp(1.0, listBox.size.width);
    final verbs = _allVerbs();
    final groups = c.verbIndexSortByCategory
        ? _categoryGroups(verbs)
        : _letterGroups(verbs);
    if (groups.isEmpty) return null;
    final widths = <String, double>{};
    for (final verb in verbs) {
      final box =
          _keyFor(verb.key).currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && box.size.width > 0) {
        widths[verb.key] = box.size.width;
      }
    }
    final scaler = MediaQuery.textScalerOf(context);
    final fromFont = c.verbIndexFontSize;
    double simulate(double fontSize) => _estimateIndexListHeight(
          fontSize: fontSize,
          contentWidth: contentW,
          groups: groups,
          categoryMode: c.verbIndexSortByCategory,
          textScaler: scaler,
          measuredWidths: widths,
          measuredFont: fromFont,
        );
    final gap = _visualGap();
    if (gap == null) return null;
    final nowH = simulate(fromFont);
    final overflow = _scroll.position.maxScrollExtent;
    // A positive gap is empty space to grow into. Once the list scrolls,
    // it is too tall by [overflow]; ignoring that kept Fit from shrinking.
    final double budget;
    if (overflow > 1 && nowH > 1) {
      final real = viewport + overflow;
      budget = viewport * nowH / real;
    } else {
      budget = nowH + gap;
    }
    const min = CaptionV2Controller.verbIndexFontSizeMin;
    const max = CaptionV2Controller.verbIndexFontSizeMax;
    const preferred = CaptionV2Controller.verbIndexFontSizeDefault;
    final steps = ((max - min) * 10).round();
    for (var i = steps; i >= 0; i--) {
      final size = min + i / 10.0;
      if (simulate(size) <= budget + 0.5) {
        // Fill the box up to the design default; aA can still go larger.
        return math.min(size, preferred);
      }
    }
    return min;
  }

  /// Pixels between the last verb row and the bottom of the list.
  /// Negative when that row hangs past the box.
  double? _visualGap() {
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null || !listBox.hasSize) return null;
    final listBottom = listBox.localToGlobal(Offset(0, listBox.size.height)).dy;
    double? chipBottom;
    for (final verb in _allVerbs()) {
      final box =
          _keyFor(verb.key).currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      if (chipBottom == null || bottom > chipBottom) chipBottom = bottom;
    }
    if (chipBottom == null) return null;
    // Chip sits [pad] above the row's bottom edge.
    return listBottom -
        chipBottom -
        VerbIndexDensityMetrics.from(c.verbIndexFontSize).pad;
  }

  double _estimateIndexListHeight({
    required double fontSize,
    required double contentWidth,
    required List<(String, List<EffectiveVerb>)> groups,
    required bool categoryMode,
    required TextScaler textScaler,
    Map<String, double>? measuredWidths,
    double measuredFont = 0,
  }) {
    final dens = VerbIndexDensityMetrics.from(fontSize);
    final columns = verbLetterBandColumns(
      groups,
      columnCount: 1,
    );
    final colGap = columns.length > 1 ? 12.0 : 0.0;
    final colW = columns.length > 1
        ? (contentWidth - colGap) / columns.length
        : contentWidth;

    double columnHeight(List<(String, List<EffectiveVerb>)> col) {
      var h = 0.0;
      for (var i = 0; i < col.length; i++) {
        h += _estimateIndexGroupHeight(
          verbs: col[i].$2,
          fontSize: fontSize,
          dens: dens,
          columnWidth: colW,
          categoryMode: categoryMode,
          textScaler: textScaler,
          measuredWidths: measuredWidths,
          measuredFont: measuredFont,
        );
        if (i < col.length - 1) h += 1;
      }
      return h;
    }

    var h = 0.0;
    for (final col in columns) {
      h = math.max(h, columnHeight(col));
    }
    return h + 2; // ListView bottom padding
  }

  double _estimateIndexGroupHeight({
    required List<EffectiveVerb> verbs,
    required double fontSize,
    required VerbIndexDensityMetrics dens,
    required double columnWidth,
    required bool categoryMode,
    required TextScaler textScaler,
    Map<String, double>? measuredWidths,
    double measuredFont = 0,
  }) {
    const verticalPad = 2.0; // 1 top + 1 bottom
    final sideL = categoryMode ? 8.0 : _kRowSidePad;
    var wrapW = columnWidth - sideL;
    var headerH = 0.0;
    if (categoryMode) {
      headerH = 3 + 16;
    } else {
      wrapW -= _kLetterColW + _kLetterColGap;
    }
    if (wrapW < 1) wrapW = 1;
    final lines = _estimateVerbWrapLines(
      verbs: verbs,
      fontSize: fontSize,
      dens: dens,
      wrapWidth: wrapW,
      textScaler: textScaler,
      measuredWidths: measuredWidths,
      measuredFont: measuredFont,
    );
    return verticalPad + headerH + lines * dens.lineHeight;
  }

  int _estimateVerbWrapLines({
    required List<EffectiveVerb> verbs,
    required double fontSize,
    required VerbIndexDensityMetrics dens,
    required double wrapWidth,
    required TextScaler textScaler,
    Map<String, double>? measuredWidths,
    double measuredFont = 0,
  }) {
    if (verbs.isEmpty) return 1;
    // Prefer live chip widths when Fit is iterating font sizes.
    if (measuredWidths == null || measuredFont <= 0) {
      return estimateVerbWrapLines(
        verbs: verbs,
        fontSize: fontSize,
        dens: dens,
        wrapWidth: wrapWidth,
        textScaler: textScaler,
      );
    }
    final style = _verbIndexTextStyle(
      fontSize: fontSize,
      color: _kVerbInk,
      thinFace: true,
    );
    var lines = 1;
    var x = 0.0;
    const chrome = VerbIndexDensityMetrics.chipPad * 2 + 2;
    for (var i = 0; i < verbs.length; i++) {
      final measured = measuredWidths[verbs[i].key];
      final double chipW;
      if (measured != null) {
        final textW = math.max(0.0, measured - chrome);
        chipW = textW * (fontSize / measuredFont) + chrome;
      } else {
        final painter = TextPainter(
          text: TextSpan(text: verbs[i].label, style: style),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
          maxLines: 1,
        )..layout();
        chipW = painter.width + chrome;
      }
      if (i == 0) {
        x = chipW;
        continue;
      }
      final next = x + dens.wrapSpacing + chipW;
      if (next > wrapWidth + 0.5) {
        lines++;
        x = chipW;
      } else {
        x = next;
      }
    }
    return lines;
  }

  @override
  void didUpdateWidget(covariant VerbIndexPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterController != widget.filterController) {
      oldWidget.filterController.removeListener(_onFilterChanged);
      widget.filterController.addListener(_onFilterChanged);
    }
  }

  GlobalKey _keyFor(String id) =>
      _verbKeys.putIfAbsent(id, GlobalKey.new);

  void _onFilterChanged() {
    _recomputeMatches();
    setState(() {});
  }

  void _recomputeMatches() {
    final q = widget.filterController.text.trim().toLowerCase();
    final scores = <String, VerbMatchScore>{};
    final matches = <(String, int)>[];
    for (final verb in _allVerbs()) {
      if (q.isEmpty) continue;
      final score = scoreVerbMatch(verb.label, q);
      if (score == null) continue;
      scores[verb.key] = score;
      matches.add((verb.key, score.rank));
    }
    matches.sort((a, b) {
      final byRank = a.$2.compareTo(b.$2);
      if (byRank != 0) return byRank;
      return a.$1.compareTo(b.$1);
    });
    _scores = scores;
    _matchKeys = [for (final m in matches) m.$1];
    widget.onMatchCountChanged?.call(q.isEmpty ? 0 : _matchKeys.length);

    if (q.isEmpty) {
      c.setVerbGhostPreview(null);
      if (_focusKey != null && !_keyboardMode) {
        // Keep selection highlight; clear ephemeral focus unless burst hold.
      }
    } else if (_matchKeys.isNotEmpty) {
      _setFocus(_matchKeys.first, keyboard: true);
    } else {
      _setFocus(null, keyboard: false);
      c.setVerbGhostPreview(null);
    }
  }

  List<EffectiveVerb> _allVerbs({bool applyHideOthers = true}) {
    final byKey = <String, EffectiveVerb>{};
    for (final entry in c.verbDefinitionsByCategory.entries) {
      if (entry.key == 'Favorites' || entry.key == 'All') continue;
      for (final verb in entry.value) {
        byKey.putIfAbsent(verb.key, () => verb);
      }
    }
    // Ensure All catalog members are present.
    for (final verb
        in c.verbDefinitionsByCategory['All'] ?? const <EffectiveVerb>[]) {
      byKey.putIfAbsent(verb.key, () => verb);
    }
    var list = byKey.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    // Faves (star): hide non-favorites entirely.
    if (applyHideOthers &&
        c.verbIndexFilterMode == VerbIndexFilterMode.faves) {
      list = [
        for (final verb in list)
          if (_verbMatchesFilter(verb)) verb,
      ];
    }
    return list;
  }

  bool _verbMatchesFilter(EffectiveVerb verb) {
    switch (c.verbIndexFilterMode) {
      case VerbIndexFilterMode.faves:
        return verb.isFavorite;
      case VerbIndexFilterMode.mostUsed:
        return c.verbMostUsedTier(verb.key) > 0;
      case VerbIndexFilterMode.all:
        return true;
    }
  }

  List<(String, List<EffectiveVerb>)> _letterGroups(List<EffectiveVerb> verbs) {
    return verbLetterBands(verbs)
        .map((band) => (band.$1, band.$2))
        .toList(growable: false);
  }

  List<(String, List<EffectiveVerb>)> _categoryGroups(
    List<EffectiveVerb> verbs,
  ) {
    // Use the sport catalog's real categories (same order as the verb accordion).
    final out = <(String, List<EffectiveVerb>)>[];
    final byCat = <String, List<EffectiveVerb>>{};
    final other = <EffectiveVerb>[];
    final order = verbCategoriesForDisplay(c.verbCategories)
        .where((name) => name != 'Favorites' && name != 'All')
        .toList();
    for (final verb in verbs) {
      final cat = verb.category;
      if (verb.isCustom || cat.isEmpty || cat == 'Favorites' || cat == 'All') {
        other.add(verb);
        continue;
      }
      (byCat[cat] ??= <EffectiveVerb>[]).add(verb);
    }
    for (final name in order) {
      final list = byCat.remove(name);
      if (list == null || list.isEmpty) continue;
      list.sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
      out.add((name, list));
    }
    for (final entry in byCat.entries) {
      entry.value.sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
      out.add((entry.key, entry.value));
    }
    if (other.isNotEmpty) {
      other.sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
      out.add(('Other', other));
    }
    return out;
  }

  String _homeCode(int index) {
    final a = _kHomeRow[index ~/ _kHomeRow.length % _kHomeRow.length];
    final b = _kHomeRow[index % _kHomeRow.length];
    return '$a$b';
  }

  void _applyBurstPrefocus() {
    final key = c.burstMemoryVerb;
    if (key == null) return;
    if (c.selectedVerb != null && c.selectedVerb != key) return;
    final verb = c.verbDefinition(key);
    if (verb == null) return;
    _setFocus(key, keyboard: true);
    c.setVerbGhostPreview(verb.label);
  }

  void _setFocus(String? key, {required bool keyboard}) {
    setState(() {
      _focusKey = key;
      _keyboardMode = keyboard && key != null;
    });
    if (key != null && widget.filterController.text.trim().isNotEmpty) {
      final verb = c.verbDefinition(key);
      c.setVerbGhostPreview(verb?.label);
    } else if (widget.filterController.text.trim().isEmpty &&
        key != null &&
        key == c.burstMemoryVerb) {
      final verb = c.verbDefinition(key);
      c.setVerbGhostPreview(verb?.label);
    } else if (widget.filterController.text.trim().isEmpty) {
      // Don't clear burst ghost unless focus cleared.
      if (key == null && c.burstMemoryVerb == null) {
        c.setVerbGhostPreview(null);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _movePillTo(key);
      _ensureVisible(key);
    });
  }

  void _movePillTo(String? key) {
    if (key == null) {
      if (_pillVisible) {
        setState(() {
          _pillVisible = false;
          _pillRect = null;
        });
      }
      return;
    }
    final ctx = _keyFor(key).currentContext;
    final listCtx = _listKey.currentContext;
    if (ctx == null || listCtx == null) return;
    final verbBox = ctx.findRenderObject() as RenderBox?;
    final listBox = listCtx.findRenderObject() as RenderBox?;
    if (verbBox == null || listBox == null || !verbBox.hasSize) return;
    final origin = verbBox.localToGlobal(Offset.zero, ancestor: listBox);
    final next = origin & verbBox.size;
    final fresh = !_pillVisible;
    setState(() {
      _pillSnap = fresh;
      _pillVisible = true;
      _pillRect = next;
    });
    if (fresh) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _pillSnap = false);
      });
    }
  }

  void _ensureVisible(String? key) {
    if (key == null || !_scroll.hasClients) return;
    final ctx = _keyFor(key).currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.15,
      duration: const Duration(milliseconds: 180),
      curve: _kEase,
    );
  }

  void _scheduleDots({bool force = false}) {
    final fs = c.verbIndexFontSize;
    final filter = c.verbIndexFilterMode;
    final hide = c.verbIndexHideOthers;
    final changed = _lastFs != fs ||
        _lastFilterMode != filter ||
        _lastHideOthers != hide;
    if (!force && !changed) return;
    _lastFs = fs;
    _lastFilterMode = filter;
    _lastHideOthers = hide;
    if (_dotsScheduled) return;
    _dotsScheduled = true;
    final snap = VerbIndexPanelState.suppressMotion;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dotsScheduled = false;
      if (!mounted) return;
      setState(() => _dotsTick++);
      if (snap) return;
      Future<void>.delayed(_kUiMs, () {
        if (mounted) setState(() => _dotsTick++);
      });
    });
  }

  Future<void> _showVerbContextMenu(
    EffectiveVerb verb,
    Offset globalPosition,
  ) async {
    final action = await _showVerbIndexContextMenu(
      context: context,
      globalPosition: globalPosition,
      verbLabel: verb.label,
      isFavorite: verb.isFavorite,
      isPinned: c.isVerbPinned(verb.key),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'favorite':
        await widget.onToggleFavorite(verb.key);
        break;
      case 'pin':
        c.toggleVerbPin(verb.key);
        break;
      case 'edit':
        await showCaptionV2VerbEditor(context, c, verb.key);
        break;
    }
  }

  Future<void> _pick(EffectiveVerb verb, {Offset? origin}) async {
    _undo = _UndoSnap(
      selectedVerb: c.selectedVerb,
      history: List<String>.from(c.verbIndexHistory),
      burstMemory: c.burstMemoryVerb,
      hadSelected: c.selectedVerb != null,
    );
    setState(() => _pressing.add(verb.key));
    Future<void>.delayed(_kUiMs, () {
      if (mounted) setState(() => _pressing.remove(verb.key));
    });

    // History updates on save/FTP only — selecting must not reorder History.
    c.selectVerb(verb.key);
    widget.onVerbArmed(verb);

    widget.filterController.clear();
    widget.filterFocusNode.unfocus();
    _recomputeMatches();
    _setFocus(verb.key, keyboard: false);
    _holdTimer?.cancel();
    _holdTimer = Timer(_kHoldMs, () {
      if (!mounted) return;
      if (_hoveredKey == null && !_keyboardMode) {
        _movePillTo(null);
      }
    });
  }

  void _undoPick() {
    final snap = _undo;
    if (snap == null) return;
    _undo = null;
    if (snap.selectedVerb != null) {
      c.selectVerb(snap.selectedVerb!);
    } else {
      c.clearSelectedVerbOnly();
    }
    c.restoreVerbIndexHistory(snap.history);
    c.burstMemoryVerb = snap.burstMemory;
    setState(() {});
  }

  bool _onHardwareKey(KeyEvent event) {
    final isDown = event is KeyDownEvent;
    final isUp = event is KeyUpEvent;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight) {
      final held = HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed;
      if (held != _cmdHeld) setState(() => _cmdHeld = held);
    }
    if (key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight) {
      if (isDown) {
        setState(() {
          _altHints = true;
          _altBuf = '';
        });
      }
      if (isUp) {
        setState(() {
          _altHints = false;
          _altBuf = '';
        });
      }
    }

    if (!isDown) return false;

    // Custom verb (and any other text field) is not the verb search.
    if (captionV2FocusIsEditable() && !widget.filterFocusNode.hasFocus) {
      return false;
    }

    final meta = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;

    if (meta && key == LogicalKeyboardKey.keyZ) {
      if (_undo != null) {
        _undoPick();
        return true;
      }
    }

    // F toggles All ↔ Faves (not while the search field is focused).
    if (!meta &&
        !alt &&
        !HardwareKeyboard.instance.isShiftPressed &&
        key == LogicalKeyboardKey.keyF &&
        !widget.filterFocusNode.hasFocus) {
      unawaited(c.cycleVerbIndexFilterMode());
      return true;
    }

    if (meta && !_altHints) {
      final digit = _digitFor(key);
      if (digit != null) {
        final favs = _favoriteVerbs();
        if (digit >= 1 && digit <= favs.length && digit <= 9) {
          unawaited(_pick(favs[digit - 1]));
          return true;
        }
      }
    }

    if (key == LogicalKeyboardKey.slash &&
        HardwareKeyboard.instance.isShiftPressed &&
        widget.filterController.text.isEmpty) {
      setState(() => _shortcutsOpen = !_shortcutsOpen);
      return true;
    }

    if (_shortcutsOpen && key == LogicalKeyboardKey.escape) {
      setState(() => _shortcutsOpen = false);
      return true;
    }

    if (alt) {
      final letter = _letterFromCode(event);
      if (letter != null) {
        _altBuf += letter;
        final verbs = _allVerbs();
        final codes = {
          for (var i = 0; i < verbs.length; i++) verbs[i].key: _homeCode(i),
        };
        final hit = codes.entries.where((e) => e.value == _altBuf);
        if (hit.isNotEmpty) {
          final verb = c.verbDefinition(hit.first.key);
          _altBuf = '';
          if (verb != null) unawaited(_pick(verb));
        } else if (_altBuf.length >= 2) {
          _altBuf = '';
        }
        setState(() {});
        return true;
      }
    }

    // Typing anywhere focuses search (letters only, no modifiers).
    if (!meta &&
        !alt &&
        widget.filterFocusNode.canRequestFocus &&
        !widget.filterFocusNode.hasFocus) {
      final ch = event.character;
      if (ch != null && RegExp(r'^[a-zA-Z]$').hasMatch(ch)) {
        widget.filterFocusNode.requestFocus();
      }
    }

    return false;
  }

  String? _letterFromCode(KeyEvent event) {
    // Prefer physical/logical Key* so Option doesn't produce special chars.
    final keyId = event.logicalKey.keyId;
    final map = <int, String>{
      LogicalKeyboardKey.keyA.keyId: 'a',
      LogicalKeyboardKey.keyS.keyId: 's',
      LogicalKeyboardKey.keyD.keyId: 'd',
      LogicalKeyboardKey.keyF.keyId: 'f',
      LogicalKeyboardKey.keyJ.keyId: 'j',
      LogicalKeyboardKey.keyK.keyId: 'k',
      LogicalKeyboardKey.keyL.keyId: 'l',
      LogicalKeyboardKey.keyG.keyId: 'g',
      LogicalKeyboardKey.keyH.keyId: 'h',
      LogicalKeyboardKey.keyQ.keyId: 'q',
      LogicalKeyboardKey.keyW.keyId: 'w',
      LogicalKeyboardKey.keyE.keyId: 'e',
      LogicalKeyboardKey.keyR.keyId: 'r',
      LogicalKeyboardKey.keyT.keyId: 't',
      LogicalKeyboardKey.keyY.keyId: 'y',
      LogicalKeyboardKey.keyU.keyId: 'u',
      LogicalKeyboardKey.keyI.keyId: 'i',
      LogicalKeyboardKey.keyO.keyId: 'o',
      LogicalKeyboardKey.keyP.keyId: 'p',
      LogicalKeyboardKey.keyZ.keyId: 'z',
      LogicalKeyboardKey.keyX.keyId: 'x',
      LogicalKeyboardKey.keyC.keyId: 'c',
      LogicalKeyboardKey.keyV.keyId: 'v',
      LogicalKeyboardKey.keyB.keyId: 'b',
      LogicalKeyboardKey.keyN.keyId: 'n',
      LogicalKeyboardKey.keyM.keyId: 'm',
    };
    return map[keyId];
  }

  int? _digitFor(LogicalKeyboardKey key) {
    const keys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    final i = keys.indexOf(key);
    return i < 0 ? null : i + 1;
  }

  List<EffectiveVerb> _favoriteVerbs() {
    final favs = c.verbDefinitionsByCategory['Favorites'] ?? const [];
    return favs.toList(growable: false);
  }

  List<EffectiveVerb> _historyVerbs() {
    if (!c.verbIndexShowHistory) return const [];
    final limit = c.verbIndexHistoryLimit.clamp(
      1,
      CaptionV2Controller.verbIndexHistoryLimitMax,
    );
    final out = <EffectiveVerb>[];
    for (final key in c.verbIndexHistory) {
      final verb = c.verbDefinition(key);
      if (verb == null) continue;
      out.add(verb);
      if (out.length >= limit) break;
    }
    return out;
  }

  KeyEventResult onFilterKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final q = widget.filterController.text;
    final searching = q.trim().isNotEmpty;

    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.tab) {
      setState(() => _keyboardMode = true);
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      _moveSpatial(0, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveSpatial(0, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight &&
        (q.isEmpty ||
            widget.filterController.selection.baseOffset >= q.length)) {
      _moveSpatial(1, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft &&
        (q.isEmpty ||
            widget.filterController.selection.baseOffset >= q.length)) {
      _moveSpatial(-1, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab && _matchKeys.isNotEmpty) {
      final shift = HardwareKeyboard.instance.isShiftPressed;
      final i = _matchKeys.indexOf(_focusKey ?? '');
      final next = _matchKeys[
          ((i < 0 ? 0 : i) + (shift ? -1 : 1) + _matchKeys.length) %
              _matchKeys.length];
      _setFocus(next, keyboard: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        final k = _focusKey;
        if (k != null) unawaited(widget.onToggleFavorite(k));
        return KeyEventResult.handled;
      }
      if (_focusKey != null) {
        final verb = c.verbDefinition(_focusKey!);
        if (verb != null) unawaited(_pick(verb));
        return KeyEventResult.handled;
      }
      if (!searching) {
        final hist = _historyVerbs();
        if (hist.isNotEmpty) {
          unawaited(_pick(hist.first));
          return KeyEventResult.handled;
        }
      } else if (_matchKeys.isEmpty) {
        final raw = q.trim();
        if (raw.isNotEmpty) widget.onAddCustom?.call(raw);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_shortcutsOpen) {
        setState(() => _shortcutsOpen = false);
        return KeyEventResult.handled;
      }
      if (q.isNotEmpty) {
        widget.filterController.clear();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _moveSpatial(int dx, int dy) {
    final poolKeys = widget.filterController.text.trim().isEmpty
        ? [for (final v in _allVerbs()) v.key]
        : List<String>.from(_matchKeys);
    if (poolKeys.isEmpty) return;
    if (_focusKey == null || !poolKeys.contains(_focusKey)) {
      final start = c.selectedVerb != null && poolKeys.contains(c.selectedVerb)
          ? c.selectedVerb!
          : poolKeys.first;
      _setFocus(start, keyboard: true);
      return;
    }
    final curCtx = _keyFor(_focusKey!).currentContext;
    final curBox = curCtx?.findRenderObject() as RenderBox?;
    if (curBox == null) return;
    final cur = curBox.localToGlobal(Offset.zero) & curBox.size;
    final cx = cur.center.dx;
    final cy = cur.center.dy;
    String? best;
    var bestDist = double.infinity;
    for (final key in poolKeys) {
      if (key == _focusKey) continue;
      final box =
          _keyFor(key).currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final r = box.localToGlobal(Offset.zero) & box.size;
      final ddx = r.center.dx - cx;
      final ddy = r.center.dy - cy;
      if (dy != 0) {
        if (ddy.sign != dy || ddy.abs() < 4) continue;
        final d = ddy.abs() * 3 + ddx.abs();
        if (d < bestDist) {
          bestDist = d;
          best = key;
        }
      } else {
        if (ddy.abs() > 4 || ddx.sign != dx) continue;
        final d = ddx.abs();
        if (d < bestDist) {
          bestDist = d;
          best = key;
        }
      }
    }
    if (best == null && dx != 0) {
      final i = poolKeys.indexOf(_focusKey!);
      final ni = i + dx;
      if (ni >= 0 && ni < poolKeys.length) best = poolKeys[ni];
    }
    if (best != null) _setFocus(best, keyboard: true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final fs = c.verbIndexFontSize;
        final dens = VerbIndexDensityMetrics.from(fs);
        final searching = widget.filterController.text.trim().isNotEmpty;
        final verbs = _allVerbs();
        final groups = c.verbIndexSortByCategory
            ? _categoryGroups(verbs)
            : _letterGroups(verbs);
        final codes = {
          for (var i = 0; i < verbs.length; i++) verbs[i].key: _homeCode(i),
        };

        _scheduleDots();

        return Listener(
          onPointerMove: (_) {
            if (_keyboardMode) setState(() => _keyboardMode = false);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _NoisePainter()),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: NotificationListener<SizeChangedLayoutNotification>(
                      onNotification: (_) {
                        _scheduleDots(force: true);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _updateScrollFade();
                          final box = _listKey.currentContext
                              ?.findRenderObject() as RenderBox?;
                          if (box != null && box.hasSize) {
                            _onListSizeMaybeChanged(box.size);
                          }
                        });
                        return false;
                      },
                      child: SizeChangedLayoutNotifier(
                        child: RepaintBoundary(
                          key: _listKey,
                          child: Stack(
                            children: [
                              // Pill behind verbs — keyboard focus only.
                              if (_pillRect != null && _keyboardMode)
                                AnimatedPositioned(
                                  duration:
                                      _pillSnap ? Duration.zero : _kPillMs,
                                  curve: _kEase,
                                  left: _pillRect!.left,
                                  top: _pillRect!.top,
                                  width: _pillRect!.width,
                                  height: _pillRect!.height,
                                  child: IgnorePointer(
                                    child: AnimatedOpacity(
                                      duration:
                                          const Duration(milliseconds: 60),
                                      opacity: _pillVisible ? 1 : 0,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: _kPill,
                                          borderRadius:
                                              BorderRadius.circular(7),
                                          boxShadow: [
                                            const BoxShadow(
                                              color: Color(0x1AE8EEF4),
                                              blurRadius: 0,
                                              spreadRadius: 1,
                                            ),
                                            if (_keyboardMode)
                                              BoxShadow(
                                                color: FfTokens.accentHover
                                                    .withValues(alpha: 1),
                                                blurRadius: 0,
                                                spreadRadius: 1.5,
                                              ),
                                            if (_keyboardMode)
                                              BoxShadow(
                                                color: FfTokens.nocturneAc
                                                    .withValues(alpha: 0.20),
                                                blurRadius: 0,
                                                spreadRadius: 3,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned.fill(
                                child: ScrollConfiguration(
                                  behavior: ScrollConfiguration.of(context)
                                      .copyWith(scrollbars: false),
                                  child: ListView(
                                    controller: _scroll,
                                    padding: const EdgeInsets.fromLTRB(
                                      _kListSidePad,
                                      0,
                                      _kListSidePad,
                                      2,
                                    ),
                                    children: [
                                      if (!searching &&
                                          c.verbIndexShowHistory)
                                        _HistoryBlock(
                                          verbs: _historyVerbs(),
                                          dens: dens,
                                          fs: fs,
                                          selectedKey: c.selectedVerb,
                                          pinnedKey: c.pinnedVerb,
                                          focusKey: _focusKey,
                                          dotsTick: _dotsTick,
                                          onPick: _pick,
                                          onContextMenu:
                                              _showVerbContextMenu,
                                          onToggleFavorite: (v) =>
                                              widget.onToggleFavorite(v.key),
                                          onTogglePin: (v) =>
                                              c.toggleVerbPin(v.key),
                                        ),
                                      if (searching && _matchKeys.isEmpty)
                                        _EmptyMatches(
                                          query: widget.filterController.text
                                              .trim(),
                                          onAdd: () {
                                            final raw = widget
                                                .filterController.text
                                                .trim();
                                            if (raw.isNotEmpty) {
                                              widget.onAddCustom?.call(raw);
                                            }
                                          },
                                        )
                                      else if (verbs.isEmpty &&
                                          c.verbIndexFilterMode ==
                                              VerbIndexFilterMode.faves)
                                        const Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            12,
                                            28,
                                            12,
                                            12,
                                          ),
                                          child: Text(
                                            'No favorites yet — right-click a verb to add one',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontFamily: FfTokens.fontFamily,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: FfTokens.nocturneT3,
                                            ),
                                          ),
                                        )
                                      else if (verbs.isEmpty &&
                                          c.verbIndexFilterMode ==
                                              VerbIndexFilterMode.mostUsed)
                                        const Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            12,
                                            28,
                                            12,
                                            12,
                                          ),
                                          child: Text(
                                            'No usage yet — save captions to rank verbs',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontFamily: FfTokens.fontFamily,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: FfTokens.nocturneT3,
                                            ),
                                          ),
                                        )
                                      else if (verbs.isNotEmpty ||
                                          searching)
                                        _VerbIndexGroupGrid(
                                          groups: groups,
                                          categoryMode:
                                              c.verbIndexSortByCategory,
                                          dens: dens,
                                          fs: fs,
                                          filterMode: searching
                                              ? VerbIndexFilterMode.all
                                              : c.verbIndexFilterMode,
                                          selectedKey: c.selectedVerb,
                                          pinnedKey: c.pinnedVerb,
                                          focusKey: _focusKey,
                                          hoveredKey: _hoveredKey,
                                          hoveredGroup: _hoveredGroup,
                                          searching: searching,
                                          scores: _scores,
                                          altHints: _altHints,
                                          altBuf: _altBuf,
                                          codes: codes,
                                          pressing: _pressing,
                                          keyFor: _keyFor,
                                          dotsTick: _dotsTick,
                                          tierFor: c.verbMostUsedTier,
                                          onHoverGroup: (g) => setState(
                                            () => _hoveredGroup = g,
                                          ),
                                          onHoverVerb: (k) {
                                            setState(() {
                                              _hoveredKey = k;
                                              _keyboardMode = false;
                                            });
                                            _movePillTo(null);
                                          },
                                          onLeaveVerb: () {
                                            setState(
                                                () => _hoveredKey = null);
                                            if (!_keyboardMode) {
                                              _movePillTo(null);
                                            }
                                          },
                                          onPick: _pick,
                                          onToggleFavorite: (v) =>
                                              widget.onToggleFavorite(v.key),
                                          onTogglePin: (v) =>
                                              c.toggleVerbPin(v.key),
                                          onContextMenu:
                                              _showVerbContextMenu,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                height: 16,
                                child: IgnorePointer(
                                  child: AnimatedOpacity(
                                    duration: _kUiMs,
                                    opacity: _canScrollDown ? 1 : 0,
                                    child: const DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Color(0x00181D22),
                                            Color(0xFF181D22),
                                          ],
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
                    ),
                  ),
                ],
              ),
              if (_shortcutsOpen)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => _shortcutsOpen = false),
                    child: const ColoredBox(color: Color(0x66000000)),
                  ),
                ),
              if (_shortcutsOpen)
                Positioned(
                  left: 8,
                  right: 8,
                  top: 8,
                  child: _ShortcutsCard(
                    onClose: () => setState(() => _shortcutsOpen = false),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Subwidgets ──────────────────────────────────────────────────────────────

/// Letter/category groups in a single column (never split on wide screens).
class _VerbIndexGroupGrid extends StatelessWidget {
  const _VerbIndexGroupGrid({
    required this.groups,
    required this.categoryMode,
    required this.dens,
    required this.fs,
    required this.filterMode,
    required this.selectedKey,
    required this.pinnedKey,
    required this.focusKey,
    required this.hoveredKey,
    required this.hoveredGroup,
    required this.searching,
    required this.scores,
    required this.altHints,
    required this.altBuf,
    required this.codes,
    required this.pressing,
    required this.keyFor,
    required this.dotsTick,
    required this.tierFor,
    required this.onHoverGroup,
    required this.onHoverVerb,
    required this.onLeaveVerb,
    required this.onPick,
    required this.onToggleFavorite,
    required this.onTogglePin,
    required this.onContextMenu,
  });

  final List<(String, List<EffectiveVerb>)> groups;
  final bool categoryMode;
  final VerbIndexDensityMetrics dens;
  final double fs;
  final VerbIndexFilterMode filterMode;
  final String? selectedKey;
  final String? pinnedKey;
  final String? focusKey;
  final String? hoveredKey;
  final String? hoveredGroup;
  final bool searching;
  final Map<String, VerbMatchScore> scores;
  final bool altHints;
  final String altBuf;
  final Map<String, String> codes;
  final Set<String> pressing;
  final GlobalKey Function(String) keyFor;
  final int dotsTick;
  final int Function(String key) tierFor;
  final ValueChanged<String?> onHoverGroup;
  final ValueChanged<String?> onHoverVerb;
  final VoidCallback onLeaveVerb;
  final Future<void> Function(EffectiveVerb verb, {Offset? origin}) onPick;
  final ValueChanged<EffectiveVerb> onToggleFavorite;
  final ValueChanged<EffectiveVerb> onTogglePin;
  final void Function(EffectiveVerb verb, Offset globalPosition) onContextMenu;

  Widget _row((String, List<EffectiveVerb>) group, {required bool isLast}) {
    return _LetterRow(
      groupId: group.$1,
      letter: group.$1,
      verbs: group.$2,
      categoryMode: categoryMode,
      dens: dens,
      fs: fs,
      filterMode: filterMode,
      selectedKey: selectedKey,
      pinnedKey: pinnedKey,
      focusKey: focusKey,
      hoveredKey: hoveredKey,
      hoveredGroup: hoveredGroup,
      searching: searching,
      scores: scores,
      altHints: altHints,
      altBuf: altBuf,
      codes: codes,
      pressing: pressing,
      keyFor: keyFor,
      dotsTick: dotsTick,
      tierFor: tierFor,
      isLast: isLast,
      onHoverGroup: onHoverGroup,
      onHoverVerb: onHoverVerb,
      onLeaveVerb: onLeaveVerb,
      onPick: onPick,
      onToggleFavorite: onToggleFavorite,
      onTogglePin: onTogglePin,
      onContextMenu: onContextMenu,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < groups.length; i++)
          _row(groups[i], isLast: i == groups.length - 1),
      ],
    );
  }
}

/// Faves / Frequent filter track — shared by Index and A–Z layouts.
/// Pills stay content-sized; the pinned slot takes the remaining width.
/// One top row: 🔍 · Faves · pin | ⚙  (Header Fix).
class VerbIndexTopBar extends StatefulWidget {
  const VerbIndexTopBar({
    super.key,
    required this.controller,
    required this.filterController,
    required this.filterFocusNode,
    required this.tokens,
    this.onFilterKey,
    this.onFilterChanged,
  });

  final CaptionV2Controller controller;
  final TextEditingController filterController;
  final FocusNode filterFocusNode;
  final FfTokens tokens;
  final KeyEventResult Function(FocusNode, KeyEvent)? onFilterKey;
  final ValueChanged<String>? onFilterChanged;

  @override
  State<VerbIndexTopBar> createState() => _VerbIndexTopBarState();
}

class _VerbIndexTopBarState extends State<VerbIndexTopBar>
    with SingleTickerProviderStateMixin {
  static const _expandMs = Duration(milliseconds: 220);

  bool _searchOpen = false;
  bool _tabsTight = false;
  bool _searchHovered = false;
  late final AnimationController _expand;

  @override
  void initState() {
    super.initState();
    _expand = AnimationController(vsync: this, duration: _expandMs);
    widget.filterController.addListener(_onFilterText);
    widget.filterFocusNode.addListener(_onFilterFocus);
    if (widget.filterController.text.isNotEmpty ||
        widget.filterFocusNode.hasFocus) {
      _searchOpen = true;
      _expand.value = 1;
    }
  }

  @override
  void dispose() {
    widget.filterController.removeListener(_onFilterText);
    widget.filterFocusNode.removeListener(_onFilterFocus);
    _expand.dispose();
    super.dispose();
  }

  void _onFilterText() {
    widget.onFilterChanged?.call(widget.filterController.text);
    final hasText = widget.filterController.text.isNotEmpty;
    if (hasText && !_searchOpen) {
      _openSearch(requestFocus: false);
    }
    setState(() {});
  }

  void _onFilterFocus() {
    if (widget.filterFocusNode.hasFocus) {
      if (!_searchOpen) _openSearch(requestFocus: false);
    } else if (widget.filterController.text.isEmpty) {
      // Blur when empty → close (slight delay so × tap can win).
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        if (!widget.filterFocusNode.hasFocus &&
            widget.filterController.text.isEmpty) {
          _closeSearch();
        }
      });
    }
  }

  void _openSearch({bool requestFocus = true}) {
    if (_searchOpen && _expand.value == 1) {
      if (requestFocus) widget.filterFocusNode.requestFocus();
      return;
    }
    setState(() => _searchOpen = true);
    _expand.forward();
    if (requestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.filterFocusNode.requestFocus();
      });
    }
  }

  void _closeSearch() {
    widget.filterController.clear();
    widget.filterFocusNode.unfocus();
    _expand.reverse().whenComplete(() {
      if (mounted) setState(() => _searchOpen = false);
    });
    setState(() {});
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _closeSearch();
      return KeyEventResult.handled;
    }
    return widget.onFilterKey?.call(node, event) ?? KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        // Frequent tab removed — migrate leftover mostUsed → all.
        if (c.verbIndexFilterMode == VerbIndexFilterMode.mostUsed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            c.setVerbIndexFilterMode(VerbIndexFilterMode.all);
          });
        }
        final mode = c.verbIndexFilterMode == VerbIndexFilterMode.mostUsed
            ? VerbIndexFilterMode.all
            : c.verbIndexFilterMode;
        final pinned = c.pinnedVerbDefinition;
        final customPhrase = c.customVerbPhrase.trim();
        final customPinned =
            c.customVerbPinned && customPhrase.isNotEmpty;
        final pinLabel =
            pinned?.label ?? (customPinned ? customPhrase : null);
        final searchVisible = _searchOpen || _expand.value > 0;

        // Same height as the player-lane header (36).
        return SizedBox(
          height: _kTopBarH,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final fullW = math.max(28.0, constraints.maxWidth - 28);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        IgnorePointer(
                          ignoring: searchVisible,
                          child: Opacity(
                            opacity: searchVisible ? 0 : 1,
                            child: _SearchIconButton(
                              hovered: _searchHovered,
                              onHover: (v) =>
                                  setState(() => _searchHovered = v),
                              onTap: () => _openSearch(),
                            ),
                          ),
                        ),
                        IgnorePointer(
                          ignoring: searchVisible,
                          child: Opacity(
                            opacity: searchVisible ? 0 : 1,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: SizedBox(
                                width: 1,
                                height: 14,
                                child: ColoredBox(color: Color(0x24E8EEF4)),
                              ),
                            ),
                          ),
                        ),
                        IgnorePointer(
                          ignoring: searchVisible,
                          child: Opacity(
                            opacity: searchVisible ? 0 : 1,
                            child: _FilterTabs(
                              mode: mode,
                              tight: _tabsTight,
                              onToggle: (next) {
                                c.setVerbIndexFilterMode(
                                  mode == next
                                      ? VerbIndexFilterMode.all
                                      : next,
                                );
                              },
                              onOverflow: (overflow) {
                                if (overflow != _tabsTight) {
                                  setState(() => _tabsTight = overflow);
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 150),
                            opacity: searchVisible ? 0 : 1,
                            child: IgnorePointer(
                              ignoring: searchVisible,
                              child: Row(
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(right: 6),
                                    child: SizedBox(
                                      width: 1,
                                      height: 14,
                                      child: ColoredBox(
                                        color: Color(0x24E8EEF4),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Align(
                                      alignment: pinLabel == null
                                          ? Alignment.center
                                          : Alignment.centerLeft,
                                      child: _PinnedSlot(
                                        label: pinLabel,
                                        onSelect: pinLabel == null
                                            ? null
                                            : () {
                                                if (pinned != null) {
                                                  c.selectVerb(pinned.key);
                                                }
                                              },
                                        onUnpin: pinLabel == null
                                            ? null
                                            : () {
                                                if (pinned != null) {
                                                  c.unpinVerb();
                                                } else if (customPinned) {
                                                  c.toggleCustomVerbPin();
                                                }
                                              },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(left: 8, right: 8),
                          child: SizedBox(
                            width: 1,
                            height: 14,
                            child: ColoredBox(color: Color(0x24E8EEF4)),
                          ),
                        ),
                        VerbMenuTools(
                          controller: c,
                          tokens: widget.tokens,
                          showInlineTextSize: true,
                          gearSize: 24,
                          textSizeHeight: 20,
                        ),
                      ],
                    ),
                    // Expanding search — grows rightward over tabs to gear.
                    if (searchVisible)
                      Positioned(
                        left: 0,
                        top: (_kTopBarH - 24) / 2,
                        height: 24,
                        child: AnimatedBuilder(
                          animation: _expand,
                          builder: (context, child) {
                            final t = _kEase.transform(_expand.value);
                            final w = 28 + (fullW - 28) * t;
                            return SizedBox(
                              width: w,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: OverflowBox(
                                  alignment: Alignment.centerLeft,
                                  maxWidth: fullW,
                                  minWidth: fullW,
                                  child: SizedBox(
                                    width: fullW,
                                    child: child,
                                  ),
                                ),
                              ),
                            );
                          },
                          child: _ExpandingSearchField(
                            controller: widget.filterController,
                            focusNode: widget.filterFocusNode,
                            onKeyEvent: _onSearchKey,
                            onClose: _closeSearch,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _SearchIconButton extends StatelessWidget {
  const _SearchIconButton({
    required this.hovered,
    required this.onHover,
    required this.onTap,
  });

  final bool hovered;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered ? FfTokens.nocturneHv : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: PhosphorIcon(
            PhosphorIconsRegular.magnifyingGlass,
            size: 14,
            color: hovered ? FfTokens.nocturneTx : FfTokens.nocturneT2,
          ),
        ),
      ),
    );
  }
}

class _ExpandingSearchField extends StatelessWidget {
  const _ExpandingSearchField({
    required this.controller,
    required this.focusNode,
    required this.onKeyEvent,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    // Border (not spread shadow) so the focus ring follows the radius —
    // spreadRadius paints square corners that peek past the rounded fill.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FfTokens.nocturneSunken,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: const Color(0x594A7A96), // rgba(74,122,150,.35)
          width: 1.5,
        ),
      ),
      child: SizedBox(
        height: 24,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Row(
            children: [
              const PhosphorIcon(
                PhosphorIconsRegular.magnifyingGlass,
                size: 14,
                color: FfTokens.nocturneT2,
              ),
              // Vertical rule after 🔍 inside the open field.
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: SizedBox(
                  width: 1,
                  height: 12,
                  child: ColoredBox(color: Color(0x38E8EEF4)),
                ),
              ),
              Expanded(
                child: Focus(
                  onKeyEvent: onKeyEvent,
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: FfTokens.nocturneTx,
                      height: 1,
                    ),
                    cursorColor: FfTokens.nocturneAc,
                    cursorHeight: 13,
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      // User-requested placeholder for expanding search.
                      hintText: 'Search verbs',
                      hintStyle: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: FfTokens.nocturneT3,
                      ),
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: 'Close (Esc)',
                waitDuration: const Duration(milliseconds: 400),
                child: _IconHit(
                  size: 18,
                  iconSize: 11,
                  icon: PhosphorIconsRegular.x,
                  onTap: onClose,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterTabs extends StatefulWidget {
  const _FilterTabs({
    super.key,
    required this.mode,
    required this.tight,
    required this.onToggle,
    required this.onOverflow,
  });

  final VerbIndexFilterMode mode;
  final bool tight;
  final ValueChanged<VerbIndexFilterMode> onToggle;
  final ValueChanged<bool> onOverflow;

  @override
  State<_FilterTabs> createState() => _FilterTabsState();
}

class _FilterTabsState extends State<_FilterTabs> {
  final _probeKey = GlobalKey();

  @override
  void didUpdateWidget(covariant _FilterTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  void _checkOverflow() {
    final box = context.findRenderObject() as RenderBox?;
    final probe = _probeKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || probe == null || !probe.hasSize) {
      return;
    }
    final overflow = probe.size.width > box.size.width + 1;
    widget.onOverflow(overflow);
  }

  @override
  Widget build(BuildContext context) {
    final tight = widget.tight;
    final selected = widget.mode == VerbIndexFilterMode.faves;
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Opacity(
          opacity: 0,
          child: IgnorePointer(
            child: Row(
              key: _probeKey,
              mainAxisSize: MainAxisSize.min,
              children: [
                _TabButton(
                  icon: PhosphorIconsFill.star,
                  selected: true,
                  tight: false,
                  fave: true,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            _TabButton(
              icon: selected
                  ? PhosphorIconsFill.star
                  : PhosphorIconsRegular.star,
              selected: selected,
              tight: tight,
              fave: true,
              onTap: () => widget.onToggle(VerbIndexFilterMode.faves),
            ),
          ],
        ),
      ],
    );
  }
}

class _TabButton extends StatefulWidget {
  const _TabButton({
    required this.icon,
    required this.selected,
    required this.tight,
    required this.fave,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final bool tight;
  final bool fave;
  final VoidCallback onTap;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final Color ink;
    if (selected) {
      ink = Colors.white;
    } else if (_hovered) {
      ink = FfTokens.nocturneTx;
    } else {
      ink = FfTokens.nocturneT3;
    }
    // Gold underline marks Faves when active.
    final underline = selected
        ? (widget.fave ? _kGold : FfTokens.nocturneAc)
        : Colors.transparent;

    return Tooltip(
      message: 'Faves',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: _kTopBarH,
            width: 24,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PhosphorIcon(widget.icon, size: 14, color: ink),
                Positioned(
                  left: 4,
                  right: 4,
                  bottom: 2,
                  height: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: underline,
                      borderRadius: BorderRadius.circular(1),
                    ),
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

class _PinnedSlot extends StatefulWidget {
  const _PinnedSlot({
    this.label,
    this.onSelect,
    this.onUnpin,
  });

  final String? label;
  final VoidCallback? onSelect;
  final VoidCallback? onUnpin;

  @override
  State<_PinnedSlot> createState() => _PinnedSlotState();
}

class _PinnedSlotState extends State<_PinnedSlot> {
  bool _closeHovered = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final hasPin = label != null && label.isNotEmpty;

    if (!hasPin) {
      // Plain hint — no chip/fill (don't read as a search field).
      return const SizedBox(
        height: 24,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(
              PhosphorIconsRegular.pushPin,
              size: 12,
              color: FfTokens.pinnedHint,
            ),
            SizedBox(width: 5),
            Text(
              'CMD+Click to pin verb',
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1,
                color: FfTokens.pinnedHint,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x1F4A7A96), // rgba(74,122,150,.12)
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4D4A7A96), // rgba(74,122,150,.30)
              blurRadius: 0,
              spreadRadius: 1,
            ),
          ],
        ),
        child: SizedBox(
          height: 22,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(7, 0, 2, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PhosphorIcon(
                  PhosphorIconsFill.pushPin,
                  size: 11,
                  color: FfTokens.accentHover,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: GestureDetector(
                    onTap: widget.onSelect,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      label!,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        height: 1,
                        color: Colors.white,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
                Tooltip(
                  message: 'Unpin',
                  waitDuration: const Duration(milliseconds: 400),
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _closeHovered = true),
                    onExit: (_) => setState(() => _closeHovered = false),
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: widget.onUnpin,
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 80),
                        width: 16,
                        height: 16,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _closeHovered
                              ? const Color(0x14E8EEF4)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: PhosphorIcon(
                          PhosphorIconsRegular.x,
                          size: 11,
                          color: _closeHovered
                              ? FfTokens.nocturneTx
                              : FfTokens.nocturneT3,
                        ),
                      ),
                    ),
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

class _IconHit extends StatefulWidget {
  const _IconHit({
    required this.size,
    required this.iconSize,
    required this.icon,
    required this.onTap,
  });

  final double size;
  final double iconSize;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_IconHit> createState() => _IconHitState();
}

class _IconHitState extends State<_IconHit> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0x14E8EEF4) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: PhosphorIcon(
            widget.icon,
            size: widget.iconSize,
            color: _hovered ? FfTokens.nocturneTx : FfTokens.nocturneT3,
          ),
        ),
      ),
    );
  }
}

class _HistoryBlock extends StatelessWidget {
  const _HistoryBlock({
    required this.verbs,
    required this.dens,
    required this.fs,
    required this.selectedKey,
    required this.pinnedKey,
    required this.focusKey,
    required this.dotsTick,
    required this.onPick,
    required this.onContextMenu,
    required this.onToggleFavorite,
    required this.onTogglePin,
  });

  final List<EffectiveVerb> verbs;
  final VerbIndexDensityMetrics dens;
  final double fs;
  final String? selectedKey;
  final String? pinnedKey;
  final String? focusKey;
  final int dotsTick;
  final Future<void> Function(EffectiveVerb verb, {Offset? origin}) onPick;
  final void Function(EffectiveVerb verb, Offset globalPosition) onContextMenu;
  final ValueChanged<EffectiveVerb> onToggleFavorite;
  final ValueChanged<EffectiveVerb> onTogglePin;

  @override
  Widget build(BuildContext context) {
    // 2px smaller than the index; shrink further if needed to fit three lines.
    final preferredFs = math.max(
      CaptionV2Controller.verbIndexFontSizeMin,
      fs - 2,
    );
    final scaler = MediaQuery.textScalerOf(context);
    // Soft teal row aligned to the letter grid (Header Fix).
    // No top pad — flush under the 36px header so roster range rules line up.
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x144A7A96), // rgba(74,122,150,.08)
          borderRadius: BorderRadius.circular(7),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2E4A7A96), // rgba(74,122,150,.18)
              blurRadius: 0,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Padding(
            padding: const EdgeInsets.only(left: _kRowSidePad),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wrapW = math.max(
                  1.0,
                  constraints.maxWidth - _kLetterColW - _kLetterColGap,
                );
                final histFs = verbs.isEmpty
                    ? preferredFs
                    : historyFontToFit(
                        verbs: verbs,
                        preferredFs: preferredFs,
                        wrapWidth: wrapW,
                        textScaler: scaler,
                      );
                final histDens = VerbIndexDensityMetrics.from(histFs);
                final lines = verbs.isEmpty
                    ? 1
                    : estimateVerbWrapLines(
                        verbs: verbs,
                        fontSize: histFs,
                        dens: histDens,
                        wrapWidth: wrapW,
                        textScaler: scaler,
                      ).clamp(1, 3);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _kLetterColW,
                      height: histDens.lineHeight,
                      child: Center(
                        child: PhosphorIcon(
                          PhosphorIconsRegular.clockCounterClockwise,
                          size: histFs >= 14 ? 15 : 13,
                          color: FfTokens.accentHover,
                        ),
                      ),
                    ),
                    const SizedBox(width: _kLetterColGap),
                    Expanded(
                      child: verbs.isEmpty
                          ? SizedBox(
                              height: histDens.lineHeight,
                              child: const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '—',
                                  style: TextStyle(
                                    fontFamily: FfTokens.fontFamily,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: FfTokens.nocturneT3,
                                    height: 1,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            )
                          : SizedBox(
                              height: histDens.lineHeight * lines,
                              child: _DottedVerbWrap(
                                verbs: verbs,
                                dens: histDens,
                                fs: histFs,
                                color: FfTokens.nocturneT2,
                                newestFirst: true,
                                selectedKey: selectedKey,
                                pinnedKey: pinnedKey,
                                focusKey: focusKey,
                                dotsTick: dotsTick,
                                onPick: onPick,
                                onContextMenu: onContextMenu,
                                onToggleFavorite: onToggleFavorite,
                                onTogglePin: onTogglePin,
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Wrap of verbs with 3px inter-verb dots that hide on line starts.
class _DottedVerbWrap extends StatefulWidget {
  const _DottedVerbWrap({
    required this.verbs,
    required this.dens,
    required this.fs,
    required this.color,
    required this.selectedKey,
    required this.pinnedKey,
    required this.focusKey,
    required this.onPick,
    required this.onContextMenu,
    required this.onToggleFavorite,
    required this.onTogglePin,
    this.dotsTick = 0,
    this.newestFirst = false,
    this.singleLine = false,
  });

  final List<EffectiveVerb> verbs;
  final VerbIndexDensityMetrics dens;
  final double fs;
  final Color color;
  final bool newestFirst;
  /// History: keep verbs on one row; scale down if the strip is tight.
  final bool singleLine;
  final String? selectedKey;
  final String? pinnedKey;
  final String? focusKey;
  final int dotsTick;
  final Future<void> Function(EffectiveVerb verb, {Offset? origin}) onPick;
  final void Function(EffectiveVerb verb, Offset globalPosition) onContextMenu;
  final ValueChanged<EffectiveVerb> onToggleFavorite;
  final ValueChanged<EffectiveVerb> onTogglePin;

  @override
  State<_DottedVerbWrap> createState() => _DottedVerbWrapState();
}

class _DottedVerbWrapState extends State<_DottedVerbWrap> {
  final _keys = <String, GlobalKey>{};
  Set<String> _lineStarts = {};

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    if (!widget.singleLine) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  @override
  void didUpdateWidget(covariant _DottedVerbWrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.singleLine) return;
    if (oldWidget.dotsTick != widget.dotsTick ||
        oldWidget.dens.gap != widget.dens.gap ||
        oldWidget.dens.lineHeight != widget.dens.lineHeight ||
        oldWidget.fs != widget.fs ||
        oldWidget.verbs.length != widget.verbs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  void _measure() {
    if (!mounted || widget.singleLine) return;
    int? prevTop;
    final starts = <String>{};
    for (var i = 0; i < widget.verbs.length; i++) {
      final verb = widget.verbs[i];
      final box =
          _keyFor(verb.key).currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy.round();
      final h = box.size.height;
      if (prevTop == null || top - prevTop > h / 2) {
        starts.add(verb.key);
      }
      prevTop = top;
    }
    if (starts.length != _lineStarts.length ||
        !starts.containsAll(_lineStarts) ||
        !_lineStarts.containsAll(starts)) {
      setState(() => _lineStarts = starts);
    }
  }

  List<Widget> _chips({required bool forceSep}) {
    return [
      for (var i = 0; i < widget.verbs.length; i++) ...[
        if (i > 0 && forceSep) SizedBox(width: widget.dens.wrapSpacing),
        _VerbChip(
          key: _keyFor(widget.verbs[i].key),
          verb: widget.verbs[i],
          fs: widget.fs,
          lh: widget.dens.lineHeight,
          color: widget.newestFirst && i == 0
              ? Colors.white
              : widget.color,
          selected: widget.verbs[i].key == widget.selectedKey,
          pinned: widget.verbs[i].key == widget.pinnedKey,
          focused: widget.verbs[i].key == widget.focusKey,
          showSep: forceSep
              ? i > 0
              : !_lineStarts.contains(widget.verbs[i].key),
          gap: widget.dens.gap,
          sepDotLeft: widget.dens.sepDotLeft,
          onTap: () => widget.onPick(widget.verbs[i]),
          onSecondary: (pos) =>
              widget.onContextMenu(widget.verbs[i], pos),
          onAltClick: () => widget.onToggleFavorite(widget.verbs[i]),
          onCmdClick: () => widget.onTogglePin(widget.verbs[i]),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.singleLine) {
      return SizedBox(
        height: widget.dens.lineHeight,
        width: double.infinity,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _chips(forceSep: true),
          ),
        ),
      );
    }
    return Wrap(
      spacing: widget.dens.wrapSpacing,
      runSpacing: 0,
      children: _chips(forceSep: false),
    );
  }
}

class _LetterRow extends StatefulWidget {
  const _LetterRow({
    required this.groupId,
    required this.letter,
    required this.verbs,
    required this.categoryMode,
    required this.dens,
    required this.fs,
    required this.filterMode,
    required this.selectedKey,
    required this.pinnedKey,
    required this.focusKey,
    required this.hoveredKey,
    required this.hoveredGroup,
    required this.searching,
    required this.scores,
    required this.altHints,
    required this.altBuf,
    required this.codes,
    required this.pressing,
    required this.keyFor,
    required this.dotsTick,
    required this.tierFor,
    required this.isLast,
    required this.onHoverGroup,
    required this.onHoverVerb,
    required this.onLeaveVerb,
    required this.onPick,
    required this.onToggleFavorite,
    required this.onTogglePin,
    required this.onContextMenu,
  });

  final String groupId;
  final String letter;
  final List<EffectiveVerb> verbs;
  final bool categoryMode;
  final VerbIndexDensityMetrics dens;
  final double fs;
  final VerbIndexFilterMode filterMode;
  final String? selectedKey;
  final String? pinnedKey;
  final String? focusKey;
  final String? hoveredKey;
  final String? hoveredGroup;
  final bool searching;
  final Map<String, VerbMatchScore> scores;
  final bool altHints;
  final String altBuf;
  final Map<String, String> codes;
  final Set<String> pressing;
  final GlobalKey Function(String) keyFor;
  final int dotsTick;
  final int Function(String key) tierFor;
  final bool isLast;
  final ValueChanged<String?> onHoverGroup;
  final ValueChanged<String?> onHoverVerb;
  final VoidCallback onLeaveVerb;
  final Future<void> Function(EffectiveVerb verb, {Offset? origin}) onPick;
  final ValueChanged<EffectiveVerb> onToggleFavorite;
  final ValueChanged<EffectiveVerb> onTogglePin;
  final void Function(EffectiveVerb verb, Offset globalPosition) onContextMenu;

  @override
  State<_LetterRow> createState() => _LetterRowState();
}

class _LetterRowState extends State<_LetterRow> {
  final _wrapKey = GlobalKey();
  Set<String> _lineStarts = {};

  @override
  void didUpdateWidget(covariant _LetterRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dotsTick != widget.dotsTick ||
        oldWidget.dens.gap != widget.dens.gap ||
        oldWidget.dens.lineHeight != widget.dens.lineHeight ||
        oldWidget.fs != widget.fs) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureDots());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureDots());
  }

  void _measureDots() {
    if (!mounted) return;
    int? prevTop;
    final starts = <String>{};
    for (var i = 0; i < widget.verbs.length; i++) {
      final verb = widget.verbs[i];
      final box = widget.keyFor(verb.key).currentContext?.findRenderObject()
          as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy.round();
      final h = box.size.height;
      if (prevTop == null || top - prevTop > h / 2) {
        starts.add(verb.key);
      }
      prevTop = top;
    }
    if (starts.length != _lineStarts.length ||
        !starts.containsAll(_lineStarts) ||
        !_lineStarts.containsAll(starts)) {
      setState(() => _lineStarts = starts);
    }
  }

  Color _letterColor({
    required bool hasMatch,
  }) {
    if (!hasMatch && widget.searching) return _kDimLetter;
    switch (widget.filterMode) {
      case VerbIndexFilterMode.faves:
        final hasFav = widget.verbs.any((v) => v.isFavorite);
        return hasFav ? _kGold : _kDot;
      case VerbIndexFilterMode.mostUsed:
        final hasRanked =
            widget.verbs.any((v) => widget.tierFor(v.key) > 0);
        return hasRanked ? _kLetterInk : _kDot;
      case VerbIndexFilterMode.all:
        return _kLetterInk;
    }
  }

  List<Shadow>? _letterShadows({
    required Color letterColor,
    required bool emphasized,
  }) {
    // Dim / empty letters stay flat.
    if (letterColor == _kDimLetter || letterColor == _kDot) return null;
    return _letterGlow(
      gold: widget.filterMode == VerbIndexFilterMode.faves,
      emphasized: emphasized,
    );
  }

  Color _verbColor(EffectiveVerb verb) {
    if (widget.searching) {
      return widget.scores.containsKey(verb.key)
          ? FfTokens.nocturneTx
          : _kDimVerb;
    }
    switch (widget.filterMode) {
      case VerbIndexFilterMode.faves:
        // Non-faves are hidden; keep remaining verbs at normal ink.
        return _kVerbInk;
      case VerbIndexFilterMode.mostUsed:
        return widget.tierFor(verb.key) > 0 ? Colors.white : _kFilterDim;
      case VerbIndexFilterMode.all:
        return _kVerbInk;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMatch = !widget.searching ||
        widget.verbs.any((v) => widget.scores.containsKey(v.key));
    // Teal letter only for the row that contains the selected or pinned verb.
    final letterTeal = (widget.pinnedKey != null &&
            widget.verbs.any((v) => v.key == widget.pinnedKey)) ||
        (widget.selectedKey != null &&
            widget.verbs.any((v) => v.key == widget.selectedKey));
    final letterColor = _letterColor(hasMatch: hasMatch);
    final letterShadows = _letterShadows(
      letterColor: letterColor,
      emphasized: letterTeal,
    );
    // Fixed 18px letter column (Header Fix); category labels stay compact.
    final letterSize = widget.categoryMode ? widget.fs + 1 : 18.0;

    return MouseRegion(
      onEnter: (_) => widget.onHoverGroup(widget.groupId),
      onExit: (_) => widget.onHoverGroup(null),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: widget.isLast
              ? null
              : const Border(
                  bottom: BorderSide(color: _kDivider, width: 1),
                ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            widget.categoryMode ? 8 : _kRowSidePad,
            widget.dens.pad,
            0,
            widget.dens.pad,
          ),
          child: widget.categoryMode
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3, bottom: 0),
                      child: Text(
                        widget.letter.toUpperCase(),
                        style: TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          height: 1.6,
                          color: letterColor,
                          shadows: letterShadows,
                        ),
                      ),
                    ),
                    _verbWrap(),
                  ],
                )
              : Row(
                  // align-items:start — letter lh matches verb lh so it
                  // doesn't inflate the row.
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _kLetterColW,
                      child: Text(
                        widget.letter,
                        textAlign: TextAlign.center,
                        style: _verbIndexTextStyle(
                          fontSize: letterSize,
                          weight: FontWeight.w600,
                          height: widget.dens.lineHeight / letterSize,
                          color: letterColor,
                          shadows: letterShadows,
                        ),
                      ),
                    ),
                    const SizedBox(width: _kLetterColGap),
                    Expanded(child: _verbWrap()),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _verbWrap() {
    return Wrap(
      key: _wrapKey,
      spacing: widget.dens.wrapSpacing,
      runSpacing: 0,
      children: [
        for (var i = 0; i < widget.verbs.length; i++)
          _chipAt(i),
      ],
    );
  }

  Widget _chipAt(int i) {
    final verb = widget.verbs[i];
    return _VerbChip(
      key: widget.keyFor(verb.key),
      verb: verb,
      fs: widget.fs,
      lh: widget.dens.lineHeight,
      color: _verbColor(verb),
      selected: verb.key == widget.selectedKey,
      pinned: verb.key == widget.pinnedKey,
      focused: verb.key == widget.focusKey,
      score: widget.scores[verb.key],
      showSep: !_lineStarts.contains(verb.key),
      gap: widget.dens.gap,
      sepDotLeft: widget.dens.sepDotLeft,
      homeCode: widget.codes[verb.key],
      showHomeCode: widget.altHints,
      homeHighlight: widget.altBuf.isNotEmpty &&
          (widget.codes[verb.key] ?? '').startsWith(widget.altBuf),
      homeDim: widget.altBuf.isNotEmpty &&
          !(widget.codes[verb.key] ?? '').startsWith(widget.altBuf),
      pressing: widget.pressing.contains(verb.key),
      onTap: () {
        final box = widget.keyFor(verb.key).currentContext?.findRenderObject()
            as RenderBox?;
        final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
        onPickWithOrigin(verb, origin);
      },
      onHover: () => widget.onHoverVerb(verb.key),
      onLeave: widget.onLeaveVerb,
      onSecondary: (pos) => widget.onContextMenu(verb, pos),
      onAltClick: () => widget.onToggleFavorite(verb),
      onCmdClick: () => widget.onTogglePin(verb),
    );
  }

  void onPickWithOrigin(EffectiveVerb verb, Offset origin) {
    widget.onPick(verb, origin: origin);
  }
}

class _VerbChip extends StatefulWidget {
  const _VerbChip({
    super.key,
    required this.verb,
    required this.fs,
    required this.lh,
    required this.color,
    required this.selected,
    required this.focused,
    this.pinned = false,
    this.score,
    this.showSep = false,
    this.gap = 20,
    this.sepDotLeft = -5.5,
    this.homeCode,
    this.showHomeCode = false,
    this.homeHighlight = false,
    this.homeDim = false,
    this.pressing = false,
    this.badge,
    this.showBadge = false,
    required this.onTap,
    this.onHover,
    this.onLeave,
    this.onSecondary,
    this.onAltClick,
    this.onCmdClick,
  });

  final EffectiveVerb verb;
  final double fs;
  final double lh;
  final Color color;
  final bool selected;
  final bool focused;
  final bool pinned;
  final VerbMatchScore? score;
  final bool showSep;
  final double gap;
  final double sepDotLeft;
  final String? homeCode;
  final bool showHomeCode;
  final bool homeHighlight;
  final bool homeDim;
  final bool pressing;
  final String? badge;
  final bool showBadge;
  final VoidCallback onTap;
  final VoidCallback? onHover;
  final VoidCallback? onLeave;
  final void Function(Offset globalPosition)? onSecondary;
  final VoidCallback? onAltClick;
  final VoidCallback? onCmdClick;

  @override
  State<_VerbChip> createState() => _VerbChipState();
}

class _VerbChipState extends State<_VerbChip> {
  bool _hot = false;
  // Read modifiers on pointer-down — by tap-up ⌘/⌥ is often already released.
  bool _handledByAlt = false;
  bool _handledByCmd = false;

  @override
  Widget build(BuildContext context) {
    final pinned = widget.pinned;
    final ink = pinned || widget.selected || _hot || widget.focused
        ? Colors.white
        : widget.color;
    final Color fill;
    final Color edge;
    // Selected / pinned: #20313C + inset #3A6076. Hover/press: light wash.
    if (pinned || widget.selected) {
      fill = _kSelectedFill;
      edge = _kSelectedEdge;
    } else if (_hot || widget.pressing) {
      fill = _kHoverWash;
      edge = Colors.transparent;
    } else {
      fill = Colors.transparent;
      edge = Colors.transparent;
    }
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hot = true);
        widget.onHover?.call();
      },
      onExit: (_) {
        setState(() => _hot = false);
        widget.onLeave?.call();
      },
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) {
          final kb = HardwareKeyboard.instance;
          _handledByAlt = kb.isAltPressed && widget.onAltClick != null;
          _handledByCmd = !_handledByAlt &&
              (kb.isMetaPressed || kb.isControlPressed) &&
              widget.onCmdClick != null;
        },
        onTapCancel: () {
          _handledByAlt = false;
          _handledByCmd = false;
        },
        onTap: () {
          if (_handledByAlt) {
            _handledByAlt = false;
            widget.onAltClick?.call();
            return;
          }
          if (_handledByCmd) {
            _handledByCmd = false;
            widget.onCmdClick?.call();
            return;
          }
          widget.onTap();
        },
        onSecondaryTapDown: widget.onSecondary == null
            ? null
            : (details) => widget.onSecondary!(details.globalPosition),
        child: Transform.scale(
          scale: widget.pressing ? 0.94 : 1,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (widget.showSep)
                Positioned(
                  // Center separator circle on mid-x-height of the verb glyphs.
                  left: widget.sepDotLeft,
                  top: (widget.lh / 2) - (_kSepDotSize / 2) + 1,
                  child: const SizedBox(
                    width: _kSepDotSize,
                    height: _kSepDotSize,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _kDot,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              // Do not set [alignment] — Container expands to max width when
              // alignment is non-null, which forces Wrap to one verb per line.
              // Plain box so Fit changes size in one frame, with no tween.
              Container(
                height: widget.lh,
                padding: const EdgeInsets.symmetric(
                  horizontal: VerbIndexDensityMetrics.chipPad,
                ),
                // Always paint a 1px border so selected/hover don't change
                // chip size and overflow the wrap row.
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: edge, width: 1),
                ),
                // height:1 text + Center so glyphs sit mid-pill (not bottom).
                child: Center(
                  widthFactor: 1,
                  child: Transform.translate(
                    offset: const Offset(0, -0.5),
                    child: _label(ink),
                  ),
                ),
              ),
              if (pinned)
                Positioned(
                  top: -4,
                  right: -4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: FfTokens.nocturneEl, // #181D22 ring
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: FfTokens.nocturneEl,
                        width: 1.5,
                      ),
                    ),
                    child: const PhosphorIcon(
                      PhosphorIconsFill.pushPin,
                      size: 9,
                      color: FfTokens.accentHover, // #5A8EAB
                    ),
                  ),
                ),
              if (widget.showHomeCode && widget.homeCode != null)
                Positioned(
                  left: -2,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Opacity(
                      opacity: widget.homeDim ? 0.25 : 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: widget.homeHighlight ? Colors.white : _kGold,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x66000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 3,
                          ),
                          child: Text(
                            widget.homeCode!,
                            style: const TextStyle(
                              fontFamily: 'SF Mono',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              height: 1,
                              color: _kGoldInk,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.badge != null)
                Positioned(
                  left: -4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: widget.showBadge ? 1 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: AnimatedScale(
                        scale: widget.showBadge ? 1 : 0.8,
                        duration: const Duration(milliseconds: 180),
                        curve: _kEase,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _kGold,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 3,
                            ),
                            child: Text(
                              widget.badge!,
                              style: const TextStyle(
                                fontFamily: FfTokens.fontFamily,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                height: 1,
                                color: _kGoldInk,
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

  Widget _label(Color ink) {
    final score = widget.score;
    final text = widget.verb.label;
    // Tight line box; chip Center places glyphs mid-pill.
    const styleHeight = 1.0;
    final style = _verbIndexTextStyle(
      fontSize: widget.fs,
      height: styleHeight,
      color: ink,
      thinFace: true,
    );
    if (score == null || score.ranges.isEmpty) {
      return Text(
        text,
        softWrap: false,
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
        style: style,
      );
    }
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final (start, len) in score.ranges) {
      if (start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, start)));
      }
      spans.add(TextSpan(
        text: text.substring(start, math.min(start + len, text.length)),
        style: const TextStyle(color: _kMatch),
      ));
      cursor = start + len;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      softWrap: false,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    );
  }
}

class _EmptyMatches extends StatelessWidget {
  const _EmptyMatches({required this.query, required this.onAdd});

  final String query;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 28, 12, 12),
      child: Column(
        children: [
          Text.rich(
            TextSpan(
              style: const TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: FfTokens.nocturneT3,
              ),
              children: [
                const TextSpan(text: 'No verb matches '),
                TextSpan(
                  text: '"$query"',
                  style: const TextStyle(
                    color: FfTokens.nocturneTx,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onAdd,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF243848),
                    Color(0xFF15242E),
                    Color(0xFF0E181F),
                  ],
                  stops: [0, 0.6, 1],
                ),
                boxShadow: [
                  BoxShadow(
                    color: FfTokens.nocturneAc.withValues(alpha: 0.95),
                    blurRadius: 0,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: FfTokens.nocturneAc.withValues(alpha: 0.25),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PhosphorIcon(
                      PhosphorIconsRegular.plus,
                      size: 14,
                      color: Colors.white,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Add as custom verb',
                      style: TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0x40000000),
                        borderRadius: BorderRadius.all(Radius.circular(4)),
                        border: Border.fromBorderSide(
                          BorderSide(color: Color(0x2EE8EEF4)),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        child: Text(
                          '↵',
                          style: TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: FfTokens.nocturneTx,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutsCard extends StatelessWidget {
  const _ShortcutsCard({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('Type', 'Filter verbs'),
      ('F', 'All · Faves'),
      ('↑ ↓ ← →', 'Move'),
      ('Tab', 'Next match'),
      ('↵', 'Pick · first history when empty'),
      ('⇧ ↵', 'Add / remove favorite'),
      ('⌘-click', 'Pin / unpin verb'),
      ('⌘ 1–9', 'Pick favorite'),
      ('Hold ⌥', 'Show two-key codes'),
      ('⌘ Z', 'Undo'),
      ('Esc', 'Clear / close'),
    ];
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () {},
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF71E242A),
            borderRadius: BorderRadius.circular(11),
            boxShadow: const [
              BoxShadow(
                color: FfTokens.nocturneLn2,
                blurRadius: 0,
                spreadRadius: 1,
              ),
              BoxShadow(
                color: Color(0x80000000),
                blurRadius: 40,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(6, 2, 6, 6),
                  child: Text(
                    'SHORTCUTS',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.88,
                      color: FfTokens.nocturneT3,
                    ),
                  ),
                ),
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Text(
                          row.$1,
                          style: const TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: FfTokens.nocturneTx,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          row.$2,
                          style: const TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 12.5,
                            color: FfTokens.nocturneT2,
                          ),
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
}

/// Verb Index right-click menu — visuals only; same actions as before.
Future<String?> _showVerbIndexContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required String verbLabel,
  required bool isFavorite,
  required bool isPinned,
}) {
  final overlayState = Overlay.of(context);
  final overlayBox = overlayState.context.findRenderObject() as RenderBox?;
  if (overlayBox == null || !overlayBox.hasSize) {
    return Future<String?>.value();
  }
  final origin = overlayBox.globalToLocal(globalPosition);
  const menuW = 188.0;
  final completer = Completer<String?>();
  late OverlayEntry entry;
  var closed = false;

  void close([String? value]) {
    if (closed) return;
    closed = true;
    entry.remove();
    if (!completer.isCompleted) completer.complete(value);
  }

  entry = OverlayEntry(
    builder: (menuContext) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => close(),
            ),
          ),
          CustomSingleChildLayout(
            delegate: _VerbIndexMenuPlace(
              origin: origin,
              width: menuW,
            ),
            child: Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  close();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Material(
                color: Colors.transparent,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: FfTokens.nocturneSunken, // #262D35
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x29E8EEF4),
                        blurRadius: 0,
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: Color(0x80000000),
                        blurRadius: 32,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 5, 8, 3),
                          child: Text(
                            verbLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: FfTokens.fontFamily,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1,
                              color: FfTokens.nocturneT3,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                        _VerbIndexMenuItem(
                          icon: isFavorite
                              ? PhosphorIconsFill.star
                              : PhosphorIconsRegular.star,
                          label: isFavorite
                              ? 'Remove from Favorites'
                              : 'Add to Favorites',
                          shortcut: '⇧↵',
                          onTap: () => close('favorite'),
                        ),
                        _VerbIndexMenuItem(
                          icon: isPinned
                              ? PhosphorIconsFill.pushPin
                              : PhosphorIconsRegular.pushPin,
                          label: isPinned ? 'Unpin Verb' : 'Pin Verb',
                          shortcut: '⌘',
                          onTap: () => close('pin'),
                        ),
                        _VerbIndexMenuItem(
                          icon: PhosphorIconsRegular.pencilSimple,
                          label: 'Edit verb…',
                          onTap: () => close('edit'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
  overlayState.insert(entry);
  return completer.future;
}

class _VerbIndexMenuPlace extends SingleChildLayoutDelegate {
  _VerbIndexMenuPlace({required this.origin, required this.width});

  final Offset origin;
  final double width;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: constraints.maxHeight - 16,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = origin.dx;
    var y = origin.dy;
    final maxX = size.width - 8 - childSize.width;
    final maxY = size.height - 8 - childSize.height;
    if (x > maxX) x = maxX < 8 ? 8.0 : maxX;
    if (x < 8) x = 8;
    if (y > maxY) y = maxY < 8 ? 8.0 : maxY;
    if (y < 8) y = 8;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(covariant _VerbIndexMenuPlace oldDelegate) {
    return origin != oldDelegate.origin || width != oldDelegate.width;
  }
}

class _VerbIndexMenuItem extends StatefulWidget {
  const _VerbIndexMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.shortcut,
  });

  final IconData icon;
  final String label;
  final String? shortcut;
  final VoidCallback onTap;

  @override
  State<_VerbIndexMenuItem> createState() => _VerbIndexMenuItemState();
}

class _VerbIndexMenuItemState extends State<_VerbIndexMenuItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF2F363C) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              PhosphorIcon(
                widget.icon,
                size: 14,
                color: FfTokens.nocturneT2,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1,
                    color: FfTokens.nocturneTx,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              if (widget.shortcut != null) ...[
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E242A),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0x1FE8EEF4)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    child: Text(
                      widget.shortcut!,
                      style: const TextStyle(
                        fontFamily: FfTokens.fontFamily,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        height: 1,
                        color: FfTokens.nocturneT2,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x0AE8EEF4);
    final rng = math.Random(7);
    final count = (size.width * size.height / 90).clamp(40, 900).toInt();
    for (var i = 0; i < count; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

