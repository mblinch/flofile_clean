import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../caption_style/verb_index_filter_mode.dart';
import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';
import '../data/effective_verb_catalog.dart';
import 'caption_v2_verb_editor.dart';
import 'verb_accordion.dart';

/// Motion system from Verb Index v3 / Verb Panel Polish.
const _kEase = Cubic(0.2, 0.8, 0.2, 1);
const _kPillMs = Duration(milliseconds: 90);
const _kUiMs = Duration(milliseconds: 220);
const _kHoldMs = Duration(milliseconds: 900);
const _kColorMs = Duration(milliseconds: 200);

const _kVerbInk = Color(0xFFD8DEE4);
const _kDimVerb = Color(0xFF454C52);
const _kDimLetter = Color(0xFF2F363C);
const _kFilterDim = Color(0xFF5A6168);
const _kDot = Color(0xFF3A4148);
const _kMatch = Color(0xFFE8763A);
const _kPill = Color(0xFF2F363C);
const _kSelectedFill = Color(0xFF20313C);
const _kSelectedEdge = Color(0xFF3A6076);
const _kGold = Color(0xFFE8C547);
const _kGoldInk = Color(0xFF1A1606);
const _kFaveInk = Color(0xFF5A8EAB);
const _kFaveLetter = Color(0xFF4A7A96);
const _kFaveFill = Color(0x385A8EAB); // ~.22
const _kFaveEdge = Color(0x805A8EAB); // ~.50
const _kFaveWash = Color(0x145A8EAB); // list wash
/// Cooler / deeper teal for Most used (distinct from Faves).
const _kMostInk = Color(0xFF6F98AE);
const _kMostFill = Color(0x383A6076); // ~.22
const _kMostEdge = Color(0x803A6076); // ~.50
const _kMostWash = Color(0x163A6076); // list wash
const _kMostLetter = Color(0xFF4A7A96);
const _kDivider = Color(0x0FE8EEF4); // ~.06
const _kHistoryWash = Color(0x124A7A96); // slight teal behind History
const _kHomeRow = 'asdfjkl';

/// Shared letter/icon column + gap for History and letter rows.
const _kLetterColW = 22.0;
const _kLetterColGap = 10.0;
/// ListView side pad + row side pad → History uses the same total inset.
const _kListSidePad = 8.0;
const _kRowSidePad = 10.0;

const _kFiller = {'to', 'the', 'a', 'off', 'in', 'of', 'on'};

class VerbIndexDensityMetrics {
  const VerbIndexDensityMetrics({
    required this.lineHeight,
    required this.pad,
    required this.gap,
  });

  final double lineHeight;
  final double pad;
  final double gap;

  factory VerbIndexDensityMetrics.from(int density, double fontSize) {
    // Verb column gap is fixed at 20px (cleanup --cg).
    const gap = 20.0;
    switch (density.clamp(0, 2)) {
      case 0:
        return VerbIndexDensityMetrics(
          lineHeight: fontSize + 5,
          pad: 0,
          gap: gap,
        );
      case 2:
        return VerbIndexDensityMetrics(
          lineHeight: fontSize + 10,
          pad: 2,
          gap: gap,
        );
      case 1:
      default:
        return VerbIndexDensityMetrics(
          lineHeight: fontSize + 7,
          pad: 0.5,
          gap: gap,
        );
    }
  }

  /// Chip highlight pad each side (padding:0 6px; margin:0 -6px).
  static const double chipPad = 6;

  /// Wrap spacing so text-to-text distance equals [gap] (padding cancels).
  double get wrapSpacing => math.max(2, gap - chipPad * 2);

  /// Dot left inset matching `.w::before{left:calc(6px - var(--cg)/2 - 1.5px)}`.
  double get sepDotLeft => chipPad - gap / 2 - 1.5;
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
  int? _lastDensity;
  VerbIndexFilterMode? _lastFilterMode;
  bool _lastHideOthers = false;
  bool _dotsScheduled = false;
  bool _canScrollDown = false;

  CaptionV2Controller get c => widget.controller;

  @override
  void initState() {
    super.initState();
    widget.filterController.addListener(_onFilterChanged);
    _scroll.addListener(_onScroll);
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyBurstPrefocus();
      _recomputeMatches();
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

  /// Height of the under-mode-bar pinned chip (+ gap above it).
  static const _kPinnedChipBlockH = 3.0 + 22.0;

  /// Grow/shrink Verb Index type so the list fills the on-screen box
  /// without scrolling when possible (largest size that still fits).
  ///
  /// Estimates each step off-screen and applies the winner once so the list
  /// doesn't flash through larger sizes first. Reserves the pinned-verb chip
  /// under the mode bar when a pin is active.
  Future<void> fitToBox() async {
    final panelBox = context.findRenderObject() as RenderBox?;
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (panelBox == null ||
        !panelBox.hasSize ||
        listBox == null ||
        !listBox.hasSize) {
      return;
    }

    final searching = widget.filterController.text.trim().isNotEmpty;
    final customPhrase = c.customVerbPhrase.trim();
    final hasPinnedChip = !searching &&
        (c.pinnedVerbDefinition != null ||
            (c.customVerbPinned && customPhrase.isNotEmpty));

    // Chrome above the scrollable list (History + mode pills + optional pin).
    var chrome = 0.0;
    if (!searching && c.verbIndexShowHistory) {
      chrome += 3 + 22 + 3; // gap + History row + gap
    } else if (!searching) {
      chrome += 3; // gap before mode bar when History is off
    }
    if (!searching) {
      chrome += 22; // All / Faves / Frequent
      if (hasPinnedChip) chrome += _kPinnedChipBlockH;
      chrome += 3; // gap before list
    }

    final listW = listBox.size.width;
    final contentW = (listW - _kListSidePad * 2).clamp(1.0, listW);
    // Prefer the live list viewport; fall back to panel minus chrome.
    final viewportH = _scroll.hasClients
        ? _scroll.position.viewportDimension
        : (panelBox.size.height - chrome).clamp(0.0, panelBox.size.height);
    // When a pin is showing, trust the smaller of measured viewport vs
    // chrome-subtracted panel so a stale layout can't ignore the chip.
    final chromeBudget =
        (panelBox.size.height - chrome).clamp(0.0, panelBox.size.height);
    final listH = hasPinnedChip
        ? math.min(viewportH, chromeBudget)
        : viewportH;
    // ListView bottom pad (+ top pad while searching).
    final heightBudget = listH - 8 - (searching ? 8 : 0);
    if (heightBudget <= 0) return;

    final verbs = _allVerbs();
    final groups = c.verbIndexSortByCategory
        ? _categoryGroups(verbs)
        : _letterGroups(verbs);
    final pinnedKey = c.pinnedVerb;

    var best = 0;
    for (var step = 2; step >= 0; step--) {
      final fs = CaptionV2Controller.verbIndexFontSizes[step];
      final needed = _estimateIndexListHeight(
        fontSize: fs,
        density: c.verbIndexDensity,
        contentWidth: contentW,
        groups: groups,
        categoryMode: c.verbIndexSortByCategory,
        pinnedKey: pinnedKey,
      );
      // Slight fudge so a tight estimate doesn't leave a scrollable sliver.
      if (needed <= heightBudget - 2) {
        best = step;
        break;
      }
    }
    await c.setVerbIndexFontStep(best);
  }

  /// Approximate list height for [fontSize] (wrap + letter/category rows).
  double _estimateIndexListHeight({
    required double fontSize,
    required int density,
    required double contentWidth,
    required List<(String, List<EffectiveVerb>)> groups,
    required bool categoryMode,
    String? pinnedKey,
  }) {
    if (groups.isEmpty) return 0;
    final dens = VerbIndexDensityMetrics.from(density, fontSize);
    final twoCol = contentWidth >= 420;
    final columns = verbLetterBandColumns(
      groups,
      columnCount: twoCol ? 2 : 1,
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
          pinnedKey: pinnedKey,
        );
        if (i < col.length - 1) h += 1; // row divider
      }
      return h;
    }

    if (columns.length <= 1) return columnHeight(groups);
    var tallest = 0.0;
    for (final col in columns) {
      tallest = math.max(tallest, columnHeight(col));
    }
    return tallest;
  }

  double _estimateIndexGroupHeight({
    required List<EffectiveVerb> verbs,
    required double fontSize,
    required VerbIndexDensityMetrics dens,
    required double columnWidth,
    required bool categoryMode,
    String? pinnedKey,
  }) {
    const verticalPad = 4.0; // AnimatedPadding 2 + 2
    final sideL = categoryMode ? 8.0 : _kRowSidePad;
    const sideR = _kRowSidePad;
    var wrapW = columnWidth - sideL - sideR;
    var headerH = 0.0;
    if (categoryMode) {
      // top:3 + 10px label at height 1.6
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
      pinnedKey: pinnedKey,
    );
    return verticalPad + headerH + lines * dens.lineHeight;
  }

  int _estimateVerbWrapLines({
    required List<EffectiveVerb> verbs,
    required double fontSize,
    required VerbIndexDensityMetrics dens,
    required double wrapWidth,
    String? pinnedKey,
  }) {
    if (verbs.isEmpty) return 1;
    final style = TextStyle(
      fontFamily: FfTokens.fontFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w400,
      height: 1,
    );
    var lines = 1;
    var x = 0.0;
    for (var i = 0; i < verbs.length; i++) {
      final painter = TextPainter(
        text: TextSpan(text: verbs[i].label, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      // Chip pad + 1px border each side (selected/hover always reserves it).
      var chipW = painter.width + VerbIndexDensityMetrics.chipPad * 2 + 2;
      // Pinned chip shows a leading pin icon + gap inside the wrap.
      if (pinnedKey != null && verbs[i].key == pinnedKey) {
        chipW += math.max(9.0, fontSize - 3) + 3;
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
    if (applyHideOthers &&
        c.verbIndexHideOthers &&
        c.verbIndexFilterMode != VerbIndexFilterMode.all) {
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
    final dens = c.verbIndexDensity;
    final filter = c.verbIndexFilterMode;
    final hide = c.verbIndexHideOthers;
    final changed = _lastFs != fs ||
        _lastDensity != dens ||
        _lastFilterMode != filter ||
        _lastHideOthers != hide;
    if (!force && !changed) return;
    _lastFs = fs;
    _lastDensity = dens;
    _lastFilterMode = filter;
    _lastHideOthers = hide;
    if (_dotsScheduled) return;
    _dotsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dotsScheduled = false;
      if (!mounted) return;
      setState(() => _dotsTick++);
      Future<void>.delayed(_kUiMs, () {
        if (mounted) setState(() => _dotsTick++);
      });
    });
  }

  Future<void> _showVerbContextMenu(
    EffectiveVerb verb,
    Offset globalPosition,
  ) async {
    final action = await showCaptionV2PopupMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'favorite',
          child: Text(
            verb.isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
          ),
        ),
        PopupMenuItem(
          value: 'pin',
          child: Text(
            c.isVerbPinned(verb.key) ? 'Unpin Verb' : 'Pin Verb',
          ),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: Text('Edit verb…'),
        ),
      ],
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

    final meta = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;

    if (meta && key == LogicalKeyboardKey.keyZ) {
      if (_undo != null) {
        _undoPick();
        return true;
      }
    }

    // F cycles All → Faves → Frequent (not while the search field is focused).
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
    final limit = c.verbIndexHistoryLimit.clamp(1, 10);
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
        final dens = VerbIndexDensityMetrics.from(c.verbIndexDensity, fs);
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
                  if (!searching && c.verbIndexShowHistory) ...[
                    // Gap under the search bar, before History.
                    const SizedBox(height: 3),
                    _HistoryBlock(
                      verbs: _historyVerbs(),
                      dens: dens,
                      fs: fs,
                      selectedKey: c.selectedVerb,
                      pinnedKey: c.pinnedVerb,
                      focusKey: _focusKey,
                      dotsTick: _dotsTick,
                      onPick: _pick,
                      onContextMenu: _showVerbContextMenu,
                      onToggleFavorite: (v) =>
                          widget.onToggleFavorite(v.key),
                      onTogglePin: (v) => c.toggleVerbPin(v.key),
                    ),
                    const SizedBox(height: 3),
                  ],
                  if (!searching) ...[
                    if (!c.verbIndexShowHistory) const SizedBox(height: 3),
                    VerbIndexModeBar(controller: c),
                    // Gap before letter list.
                    const SizedBox(height: 3),
                  ],
                  Expanded(
                    child: AnimatedContainer(
                      duration: _kColorMs,
                      curve: _kEase,
                      // Subtle teal wash so filter modes read as active.
                      color: !searching
                          ? switch (c.verbIndexFilterMode) {
                              VerbIndexFilterMode.faves => _kFaveWash,
                              VerbIndexFilterMode.mostUsed => _kMostWash,
                              VerbIndexFilterMode.all => Colors.transparent,
                            }
                          : Colors.transparent,
                      child: NotificationListener<SizeChangedLayoutNotification>(
                      onNotification: (_) {
                        _scheduleDots(force: true);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _updateScrollFade();
                        });
                        return false;
                      },
                      child: SizeChangedLayoutNotifier(
                        child: Stack(
                          key: _listKey,
                          children: [
                            // Pill behind verbs (prototype z-index:1 under z-index:2).
                            if (_pillRect != null)
                              AnimatedPositioned(
                                duration: _pillSnap ? Duration.zero : _kPillMs,
                                curve: _kEase,
                                left: _pillRect!.left,
                                top: _pillRect!.top,
                                width: _pillRect!.width,
                                height: _pillRect!.height,
                                child: IgnorePointer(
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 60),
                                    opacity: _pillVisible ? 1 : 0,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: _kPill,
                                        borderRadius: BorderRadius.circular(7),
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
                                  padding: EdgeInsets.fromLTRB(
                                    _kListSidePad,
                                    searching ? 8 : 0,
                                    _kListSidePad,
                                    8,
                                  ),
                                  children: [
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
                                    else
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
                                          _movePillTo(k);
                                        },
                                        onLeaveVerb: () {
                                          setState(() => _hoveredKey = null);
                                          if (!_keyboardMode) {
                                            _movePillTo(null);
                                          }
                                        },
                                        onPick: _pick,
                                        onToggleFavorite: (v) =>
                                            widget.onToggleFavorite(v.key),
                                        onTogglePin: (v) =>
                                            c.toggleVerbPin(v.key),
                                        onContextMenu: _showVerbContextMenu,
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

/// Packs letter/category groups into 1–2 columns so wide panels don't leave
/// a dead zone on the right.
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoCol = constraints.maxWidth >= 420;
        final columns = verbLetterBandColumns(
          groups,
          columnCount: twoCol ? 2 : 1,
        );
        if (columns.length <= 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < groups.length; i++)
                _row(groups[i], isLast: i == groups.length - 1),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < columns.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < columns[i].length; j++)
                      _row(
                        columns[i][j],
                        isLast: j == columns[i].length - 1,
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// All / Faves / Frequent filter pills — shared by Index and A–Z layouts.
/// Pinned verb (if any) sits under the mode bar at the same height.
class VerbIndexModeBar extends StatelessWidget {
  const VerbIndexModeBar({
    super.key,
    required this.controller,
    this.showPinned = true,
  });

  final CaptionV2Controller controller;
  /// When false (A–Z lane), skip the under-bar pin — that layout has its own.
  final bool showPinned;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final mode = controller.verbIndexFilterMode;
        final pinned = controller.pinnedVerbDefinition;
        final customPhrase = controller.customVerbPhrase.trim();
        final customPinned =
            controller.customVerbPinned && customPhrase.isNotEmpty;
        final pinLabel = pinned?.label ?? (customPinned ? customPhrase : null);
        final pinSelected = pinned != null
            ? controller.selectedVerb == pinned.key
            : customPinned &&
                controller.selectedVerb == null &&
                controller.customVerbPhrase.trim() == customPhrase;

        return Padding(
          padding: const EdgeInsets.fromLTRB(3, 0, 3, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E242A),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14E8EEF4),
                      blurRadius: 0,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: Row(
                    children: [
                      _VerbIndexModePill(
                        label: 'All',
                        selected: mode == VerbIndexFilterMode.all,
                        style: _ModePillStyle.neutral,
                        onTap: () => controller
                            .setVerbIndexFilterMode(VerbIndexFilterMode.all),
                      ),
                      const SizedBox(width: 2),
                      _VerbIndexModePill(
                        label: 'Faves',
                        icon: PhosphorIconsRegular.star,
                        selected: mode == VerbIndexFilterMode.faves,
                        style: _ModePillStyle.faves,
                        onTap: () => controller.setVerbIndexFilterMode(
                          VerbIndexFilterMode.faves,
                        ),
                      ),
                      const SizedBox(width: 2),
                      _VerbIndexModePill(
                        label: 'Frequent',
                        icon: PhosphorIconsRegular.chartBar,
                        selected: mode == VerbIndexFilterMode.mostUsed,
                        style: _ModePillStyle.most,
                        onTap: () => controller.setVerbIndexFilterMode(
                          VerbIndexFilterMode.mostUsed,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (showPinned && pinLabel != null) ...[
                const SizedBox(height: 3),
                _VerbIndexPinnedChip(
                  label: pinLabel,
                  selected: pinSelected,
                  onSelect: () {
                    if (pinned != null) {
                      controller.selectVerb(pinned.key);
                    }
                  },
                  onUnpin: () {
                    if (pinned != null) {
                      controller.unpinVerb();
                    } else if (customPinned) {
                      controller.toggleCustomVerbPin();
                    }
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _VerbIndexPinnedChip extends StatefulWidget {
  const _VerbIndexPinnedChip({
    required this.label,
    required this.selected,
    required this.onSelect,
    required this.onUnpin,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onUnpin;

  @override
  State<_VerbIndexPinnedChip> createState() => _VerbIndexPinnedChipState();
}

class _VerbIndexPinnedChipState extends State<_VerbIndexPinnedChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final fill = widget.selected
        ? const Color(0xFF20313C)
        : (_hovered ? FfTokens.nocturneHv : const Color(0xFF1E242A));
    final edge = widget.selected
        ? const Color(0xFF3A6076)
        : const Color(0x14E8EEF4);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: _kEase,
        // Match VerbIndexModeBar height (pill 20 + pad 1+1).
        height: 22,
        padding: const EdgeInsets.only(left: 5, right: 2),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: edge, width: 1),
        ),
        child: Row(
          children: [
            Tooltip(
              message: 'Unpin',
              waitDuration: const Duration(milliseconds: 400),
              child: GestureDetector(
                onTap: widget.onUnpin,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 3),
                  child: PhosphorIcon(
                    PhosphorIconsFill.pushPin,
                    size: 11,
                    color: FfTokens.pinned,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                onTap: widget.onSelect,
                child: Text(
                  widget.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1,
                    color: widget.selected
                        ? Colors.white
                        : FfTokens.nocturneTx,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
            Tooltip(
              message: 'Unpin',
              waitDuration: const Duration(milliseconds: 400),
              child: GestureDetector(
                onTap: widget.onUnpin,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(2, 3, 2, 3),
                  child: PhosphorIcon(
                    PhosphorIconsRegular.x,
                    size: 11,
                    color: FfTokens.nocturneT3,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ModePillStyle { neutral, faves, most }

class _VerbIndexModePill extends StatefulWidget {
  const _VerbIndexModePill({
    required this.label,
    required this.selected,
    required this.style,
    required this.onTap,
    this.icon,
    this.flex = 1,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final _ModePillStyle style;
  final VoidCallback onTap;
  final int flex;

  @override
  State<_VerbIndexModePill> createState() => _VerbIndexModePillState();
}

class _VerbIndexModePillState extends State<_VerbIndexModePill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final Color fill;
    final Color edge;
    final Color ink;
    if (selected && widget.style == _ModePillStyle.faves) {
      fill = _kFaveFill;
      edge = _kFaveEdge;
      ink = Colors.white;
    } else if (selected && widget.style == _ModePillStyle.most) {
      fill = _kMostFill;
      edge = _kMostEdge;
      ink = Colors.white;
    } else if (selected) {
      fill = const Color(0xFF20313C);
      edge = const Color(0xFF3A6076);
      ink = Colors.white;
    } else if (_hovered) {
      fill = FfTokens.nocturneHv;
      edge = Colors.transparent;
      ink = FfTokens.nocturneTx;
    } else {
      fill = Colors.transparent;
      edge = Colors.transparent;
      ink = FfTokens.nocturneT2;
    }
    // Selected Faves / Frequent: white label, teal icon.
    final iconInk = switch (widget.style) {
      _ModePillStyle.faves when selected => _kFaveInk,
      _ModePillStyle.most when selected => _kMostInk,
      _ => ink,
    };
    return Expanded(
      flex: widget.flex,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: _kEase,
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(5),
              border: edge.a == 0
                  ? null
                  : Border.all(color: edge, width: 1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  PhosphorIcon(widget.icon!, size: 11, color: iconInk),
                  const SizedBox(width: 2),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1,
                      color: ink,
                      decoration: TextDecoration.none,
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
    // Full-bleed slight teal wash; same content inset as letter rows.
    // Height matches VerbIndexModeBar (pill 20 + pad 1+1 = 22).
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _kHistoryWash,
      ),
      child: SizedBox(
        height: 22,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: _kListSidePad + _kRowSidePad,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: _kLetterColW,
                child: Align(
                  alignment: Alignment.center,
                  child: PhosphorIcon(
                    PhosphorIconsRegular.clockCounterClockwise,
                    size: fs + 3,
                    color: FfTokens.accentHover,
                  ),
                ),
              ),
              const SizedBox(width: _kLetterColGap),
              Expanded(
                child: verbs.isEmpty
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '—',
                          style: TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: fs,
                            fontWeight: FontWeight.w400,
                            color: FfTokens.nocturneT3,
                            height: 1,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      )
                    : _DottedVerbWrap(
                        verbs: verbs,
                        dens: dens,
                        fs: fs,
                        color: _kVerbInk,
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
            ],
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
  });

  final List<EffectiveVerb> verbs;
  final VerbIndexDensityMetrics dens;
  final double fs;
  final Color color;
  final bool newestFirst;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant _DottedVerbWrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dotsTick != widget.dotsTick ||
        oldWidget.dens.gap != widget.dens.gap ||
        oldWidget.fs != widget.fs ||
        oldWidget.verbs.length != widget.verbs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  void _measure() {
    if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: widget.dens.wrapSpacing,
      runSpacing: 0,
      children: [
        for (var i = 0; i < widget.verbs.length; i++)
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
            showSep: !_lineStarts.contains(widget.verbs[i].key),
            gap: widget.dens.gap,
            sepDotLeft: widget.dens.sepDotLeft,
            onTap: () => widget.onPick(widget.verbs[i]),
            onSecondary: (pos) =>
                widget.onContextMenu(widget.verbs[i], pos),
            onAltClick: () => widget.onToggleFavorite(widget.verbs[i]),
            onCmdClick: () => widget.onTogglePin(widget.verbs[i]),
          ),
      ],
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
    required bool letterTeal,
  }) {
    if (!hasMatch && widget.searching) return _kDimLetter;
    if (letterTeal) return FfTokens.accentHover;
    switch (widget.filterMode) {
      case VerbIndexFilterMode.faves:
        final hasFav = widget.verbs.any((v) => v.isFavorite);
        return hasFav ? _kFaveLetter : _kDot;
      case VerbIndexFilterMode.mostUsed:
        final hasRanked =
            widget.verbs.any((v) => widget.tierFor(v.key) > 0);
        return hasRanked ? _kMostLetter : _kDot;
      case VerbIndexFilterMode.all:
        return FfTokens.nocturneT3;
    }
  }

  Color _verbColor(EffectiveVerb verb) {
    if (widget.searching) {
      return widget.scores.containsKey(verb.key)
          ? FfTokens.nocturneTx
          : _kDimVerb;
    }
    switch (widget.filterMode) {
      case VerbIndexFilterMode.faves:
        // Verbs stay bright; teal is reserved for the letter column.
        return verb.isFavorite ? Colors.white : _kFilterDim;
      case VerbIndexFilterMode.mostUsed:
        // Same idea as Faves: ranked verbs white, teal only on letters.
        return widget.tierFor(verb.key) > 0 ? Colors.white : _kFilterDim;
      case VerbIndexFilterMode.all:
        return _kVerbInk;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMatch = !widget.searching ||
        widget.verbs.any((v) => widget.scores.containsKey(v.key));
    final selectedHere =
        widget.verbs.any((v) => v.key == widget.selectedKey);
    final hovered = widget.hoveredGroup == widget.groupId ||
        widget.verbs.any((v) => v.key == widget.hoveredKey) ||
        widget.verbs.any((v) => v.key == widget.focusKey);
    final letterTeal = selectedHere || hovered;
    final letterColor = _letterColor(
      hasMatch: hasMatch,
      letterTeal: letterTeal,
    );

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
        child: AnimatedPadding(
          duration: _kUiMs,
          curve: _kEase,
          // 2px clearance above/below so selected pill doesn't touch dividers.
          padding: EdgeInsets.fromLTRB(
            widget.categoryMode ? 8 : _kRowSidePad,
            2,
            _kRowSidePad,
            2,
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
                        ),
                      ),
                    ),
                    _verbWrap(),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    SizedBox(
                      width: _kLetterColW,
                      child: AnimatedDefaultTextStyle(
                        duration: _kColorMs,
                        curve: _kEase,
                        style: TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: widget.fs + 2,
                          fontWeight: FontWeight.w700,
                          height: widget.dens.lineHeight / (widget.fs + 2),
                          color: letterColor,
                        ),
                        child: Text(
                          widget.letter,
                          textAlign: TextAlign.center,
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
        for (final verb in widget.verbs)
          _VerbChip(
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
              final box = widget
                  .keyFor(verb.key)
                  .currentContext
                  ?.findRenderObject() as RenderBox?;
              final origin =
                  box?.localToGlobal(Offset.zero) ?? Offset.zero;
              onPickWithOrigin(verb, origin);
            },
            onHover: () => widget.onHoverVerb(verb.key),
            onLeave: widget.onLeaveVerb,
            onSecondary: (pos) => widget.onContextMenu(verb, pos),
            onAltClick: () => widget.onToggleFavorite(verb),
            onCmdClick: () => widget.onTogglePin(verb),
          ),
      ],
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
    final ink = widget.selected || _hot || widget.focused
        ? Colors.white
        : widget.color;
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
        child: AnimatedScale(
          scale: widget.pressing ? 0.94 : 1,
          duration: _kUiMs,
          curve: _kEase,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (widget.showSep)
                Positioned(
                  // Center 3px dot on mid-x-height of the verb glyphs.
                  left: widget.sepDotLeft,
                  top: (widget.lh / 2) - 1.5 + 1,
                  child: const SizedBox(
                    width: 3,
                    height: 3,
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
              AnimatedContainer(
                duration: _kUiMs,
                curve: _kEase,
                height: widget.lh,
                padding: const EdgeInsets.symmetric(
                  horizontal: VerbIndexDensityMetrics.chipPad,
                ),
                // Always paint a 1px border so selected/hover don't change
                // chip size and overflow the wrap row.
                decoration: BoxDecoration(
                  color: widget.selected
                      ? _kSelectedFill
                      : (_hot || widget.focused)
                          ? _kPill
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: widget.selected
                        ? _kSelectedEdge
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                // height:1 text + Center so glyphs sit mid-pill (not bottom).
                child: Center(
                  widthFactor: 1,
                  child: Transform.translate(
                    offset: const Offset(0, -0.5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.pinned) ...[
                          PhosphorIcon(
                            PhosphorIconsFill.pushPin,
                            size: math.max(9.0, widget.fs - 3),
                            color: FfTokens.pinned,
                          ),
                          const SizedBox(width: 3),
                        ],
                        _label(ink),
                      ],
                    ),
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
    if (score == null || score.ranges.isEmpty) {
      return AnimatedDefaultTextStyle(
        duration: _kColorMs,
        curve: _kEase,
        style: TextStyle(
          fontFamily: FfTokens.fontFamily,
          fontSize: widget.fs,
          fontWeight: FontWeight.w400,
          height: styleHeight,
          color: ink,
        ),
        child: Text(
          text,
          softWrap: false,
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        ),
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
      TextSpan(
        style: TextStyle(
          fontFamily: FfTokens.fontFamily,
          fontSize: widget.fs,
          fontWeight: FontWeight.w400,
          height: styleHeight,
          color: ink,
        ),
        children: spans,
      ),
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
      ('F', 'All · Faves · Frequent'),
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

