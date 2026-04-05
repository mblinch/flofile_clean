import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_switch/flutter_switch.dart';
import '../services/mlb_api_service.dart';
import '../services/preferences_service.dart';
import '../utils/default_verb_keywords.dart';
import 'verb_keyword_quick_bar.dart';

/// Intents for global H/V firebar shortcut (only when not in a text field).
class _FirebarHIntent extends Intent {
  const _FirebarHIntent();
}

class _FirebarVIntent extends Intent {
  const _FirebarVIntent();
}

/// ShortcutManager that does not handle H/V when focus is in a text input (TextField/EditableText).
class _FirebarShortcutManager extends ShortcutManager {
  _FirebarShortcutManager({required super.shortcuts});

  static bool _isFocusInTextInput(FocusNode? focus) {
    if (focus == null) return false;
    final context = focus.context;
    if (context == null) return false;
    bool inTextInput = false;
    (context as Element).visitAncestorElements((element) {
      final w = element.widget;
      if (w is TextField ||
          w is TextFormField ||
          w.runtimeType.toString() == 'EditableText') {
        inTextInput = true;
        return false;
      }
      return true;
    });
    return inTextInput;
  }

  @override
  KeyEventResult handleKeypress(BuildContext context, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.keyH ||
            event.logicalKey == LogicalKeyboardKey.keyV)) {
      if (_isFocusInTextInput(FocusManager.instance.primaryFocus)) {
        return KeyEventResult.ignored;
      }
    }
    return super.handleKeypress(context, event);
  }
}

/// Reusable keyboard-fire content. Use [KeyboardFireDialog] for modal, or embed this inline.
class KeyboardFirePanel extends StatefulWidget {
  final List<Player> homeRoster;
  final List<Player> awayRoster;
  final String? homeTeamName;
  final String? awayTeamName;
  final dynamic captionState;

  /// When true, show Cancel/Done buttons (e.g. in dialog). When false, caption updates live (inline).
  final bool showDialogActions;

  /// Called when user taps Done (only when [showDialogActions] is true).
  final VoidCallback? onDone;

  // Action bar callbacks (inline mode only)
  final VoidCallback? onPreviousImage;
  final VoidCallback? onNextImage;
  final Future<void> Function()? onSaveIptc;
  final VoidCallback? onFtp;
  final VoidCallback? onFtpSettings;
  final VoidCallback? onReset;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final VoidCallback? onPastePrevious;
  final int? currentIndex;
  final int? totalImages;
  final bool ftpDisabled;
  final String? currentFtpProfile;

  const KeyboardFirePanel({
    super.key,
    required this.homeRoster,
    required this.awayRoster,
    this.homeTeamName,
    this.awayTeamName,
    required this.captionState,
    this.showDialogActions = false,
    this.onDone,
    this.onPreviousImage,
    this.onNextImage,
    this.onSaveIptc,
    this.onFtp,
    this.onFtpSettings,
    this.onReset,
    this.onCopy,
    this.onPaste,
    this.onPastePrevious,
    this.currentIndex,
    this.totalImages,
    this.ftpDisabled = false,
    this.currentFtpProfile,
  });

  @override
  State<KeyboardFirePanel> createState() => _KeyboardFirePanelState();
}

class _KeyboardFirePanelState extends State<KeyboardFirePanel> {
  int _step = 0;
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final TextEditingController _homeBarController = TextEditingController();
  final TextEditingController _awayBarController = TextEditingController();
  final TextEditingController _categoryBarController = TextEditingController();
  final TextEditingController _verbBarController = TextEditingController();
  final TextEditingController _customVerbController = TextEditingController();
  final ScrollController _categoriesScrollController = ScrollController();
  final ScrollController _verbsScrollController = ScrollController();
  final FocusNode _homeBarFocus = FocusNode();
  final FocusNode _awayBarFocus = FocusNode();
  final FocusNode _categoryBarFocus = FocusNode();
  final FocusNode _verbBarFocus = FocusNode();
  String _homeSummary = '';
  String _awaySummary = '';
  String _verbSummary = '';
  bool _waitingForVerb = true;
  // Cascading verb picker state
  int? _selectedCategoryIndex; // index into _verbList
  int? _pickedVerbCategory; // 1-based category of last picked verb
  int? _pickedVerbIndex; // 1-based index of last picked verb
  String?
      _lastUsedVerbLabel; // verb label to show "(last used)" in red when image changes

  // Pinned verb: Cmd+click to pin; auto-applies to every subsequent image
  int? _pinnedVerbCategory;
  int? _pinnedVerbIndex;

  /// Set in Reset Caption [InkWell.onTapDown] so the confirm dialog can anchor near the tap.
  Offset? _resetCaptionTapAnchor;

  /// When true, the upcoming verb row [InkWell.onTap] must be ignored because Cmd+pin
  /// was already handled in [onTapDown]. Otherwise [onTap] runs after Meta is released
  /// and calls [selectVerbByCategoryAndIndexFromKeyboardFire] again, toggling the verb off.
  bool _verbRowTapConsumedByCmd = false;

  bool _showPlayoffOvertimes = false;

  // Category drag-to-reorder state (raw pointer events)
  int? _dragFromCatIndex;
  int? _dragToCatIndex;
  Timer? _catLongPressTimer;
  final Map<int, GlobalKey> _catRowKeys = {};

  GlobalKey _catKey(int i) => _catRowKeys.putIfAbsent(i, () => GlobalKey());

  int? _catIndexAtGlobalY(double y) {
    for (final entry in _catRowKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final pos = box.localToGlobal(Offset.zero);
      if (y >= pos.dy && y < pos.dy + box.size.height) return entry.key;
    }
    return null;
  }

  /// Baseball Keyboard Fire: 0 = innings 1–9, 1 = 10–18, 2 = 19–27.
  int _baseballInningPage = 0;

  /// When true, show players in a **number grid**: one row per decade (0–9, 10–19, …),
  /// ten columns per row. When false, list view with names.
  bool _useSquarePlayerView = false;

  /// Mirrors Preferences → Application → Caption fields (same as CaptionFieldsWidget).
  PreferencesService? _prefsService;
  bool _showHeadlineField = false;
  bool _showKeywordsField = false;
  bool _showPersonalityField = true;

  bool _applyVerbKeywordsEnabledKb = true;
  bool _applyPlayerNamesToKeywordsEnabledKb = true;

  /// Editable keyword shortcut chips shown under "Keyword Shortcuts".
  /// Seeded with built-in defaults immediately so chips are visible before
  /// the async prefs load completes.
  List<Map<String, dynamic>> _keywordShortcuts = [
    {'label': 'c', 'keywords': List<String>.from(verbKeywordQuickGroupC)},
    {'label': 'p', 'keywords': List<String>.from(verbKeywordQuickGroupP)},
    {'label': 'ps', 'keywords': List<String>.from(verbKeywordQuickGroupPs)},
    {'label': 'b', 'keywords': List<String>.from(verbKeywordQuickGroupB)},
    {'label': 'o', 'keywords': List<String>.from(verbKeywordQuickGroupO)},
    {'label': 'TPX', 'keywords': List<String>.from(verbKeywordQuickTpx)},
  ];

  /// Actions column shortcut list (under FTP); persisted.
  bool _showKeyboardFireShortcutsHelp = true;

  /// Index of the one expanded category (verbs visible). Null = none expanded.
  int? _expandedCategoryIndex;

  /// Hover highlight: "home_12" / "away_5" for roster; "catNum_verbNum" for verbs.
  String? _hoveredRosterKey;
  String? _hoveredVerbKey;

  // New single firebar under periods: one bar, steps H/V → team1 → team2 → category → verb
  static const bool _showFirebar =
      false; // set true to show firebar (top bars preferred for now)
  final TextEditingController _firebarController = TextEditingController();
  final FocusNode _firebarFocus = FocusNode();
  int _firebarStep = 0; // 0=H/V, 1=team1, 2=team2, 3=category, 4=verb
  String? _firebarHv; // 'H' or 'V'
  String _firebarTeam1Value = '';
  String _firebarTeam2Value = '';
  String _firebarCategoryValue = '';
  String _firebarVerbValue = '';

  final GlobalKey _verbColumnKey = GlobalKey();

  void _onVerbTapped(int selectedCatNum, int verbNum, {bool cmdHeld = false}) {
    if (cmdHeld) {
      // Cmd+click: toggle pin on this verb
      final alreadyPinned =
          _pinnedVerbCategory == selectedCatNum && _pinnedVerbIndex == verbNum;
      setState(() {
        if (alreadyPinned) {
          _pinnedVerbCategory = null;
          _pinnedVerbIndex = null;
        } else {
          _pinnedVerbCategory = selectedCatNum;
          _pinnedVerbIndex = verbNum;
          // Also select it immediately
          _pickedVerbCategory = selectedCatNum;
          _pickedVerbIndex = verbNum;
        }
      });
      if (!alreadyPinned) {
        widget.captionState?.selectVerbByCategoryAndIndexFromKeyboardFire(
            selectedCatNum, verbNum);
        widget.captionState?.updateCaptionFromKeyboardFire();
        _refreshCaptionPreviewLater();
      }
      return;
    }
    widget.captionState
        ?.selectVerbByCategoryAndIndexFromKeyboardFire(selectedCatNum, verbNum);
    widget.captionState?.updateCaptionFromKeyboardFire();
    setState(() {
      _verbSummary = 'Category $selectedCatNum, verb $verbNum selected';
      _waitingForVerb = false;
      _pickedVerbCategory = selectedCatNum;
      _pickedVerbIndex = verbNum;
    });
    _refreshCaptionPreviewLater();
  }

  /// Pin a verb by category+index (from context menu).
  void _setPinnedVerb(int catNum, int verbNum) {
    setState(() {
      _pinnedVerbCategory = catNum;
      _pinnedVerbIndex = verbNum;
      _pickedVerbCategory = catNum;
      _pickedVerbIndex = verbNum;
    });
    widget.captionState
        ?.selectVerbByCategoryAndIndexFromKeyboardFire(catNum, verbNum);
    widget.captionState?.updateCaptionFromKeyboardFire();
    _refreshCaptionPreviewLater();
  }

  /// Unpin the currently pinned verb (from context menu).
  void _clearPinnedVerb() {
    setState(() {
      _pinnedVerbCategory = null;
      _pinnedVerbIndex = null;
    });
  }

  @override
  void initState() {
    super.initState();
    PreferencesService.getInstance().then((p) {
      if (!mounted) return;
      _prefsService = p;
      _showKeyboardFireShortcutsHelp = p.showKeyboardFireShortcutsHelpSync;
      _applyKeyboardFireCaptionFieldVisibility();
      p.getApplyVerbKeywords().then((enabled) {
        if (!mounted) return;
        setState(() => _applyVerbKeywordsEnabledKb = enabled);
      });
      p.getApplyPlayerNamesToKeywords().then((enabled) {
        if (!mounted) return;
        setState(() => _applyPlayerNamesToKeywordsEnabledKb = enabled);
      });
      p.getKeywordShortcuts().then((saved) {
        if (!mounted || saved.isEmpty) return;
        setState(() => _keywordShortcuts = saved);
      });
      p.captionFieldVisibilityRevision
          .addListener(_onKeyboardFireCaptionFieldVisibilityRevision);
    });
    // Defer state changes to avoid setState() during build (CaptionFieldsWidget).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.captionState?.clearPlayersForKeyboardFire();
      if (mounted) _homeBarFocus.requestFocus();
    });
  }

  void _onKeyboardFireCaptionFieldVisibilityRevision() {
    _applyKeyboardFireCaptionFieldVisibility();
  }

  void _applyKeyboardFireCaptionFieldVisibility() {
    final p = _prefsService;
    if (p == null || !mounted) return;
    setState(() {
      _showHeadlineField = p.captionFieldHeadlineVisibleSync;
      _showKeywordsField = p.captionFieldKeywordsVisibleSync;
      _showPersonalityField = p.captionFieldPersonalityVisibleSync;
    });
  }

  // ── Keyword shortcut helpers ──────────────────────────────────────────────

  List<Map<String, dynamic>> _defaultKeywordShortcuts() => [
        {'label': 'c', 'keywords': List<String>.from(verbKeywordQuickGroupC)},
        {'label': 'p', 'keywords': List<String>.from(verbKeywordQuickGroupP)},
        {'label': 'ps', 'keywords': List<String>.from(verbKeywordQuickGroupPs)},
        {'label': 'b', 'keywords': List<String>.from(verbKeywordQuickGroupB)},
        {'label': 'o', 'keywords': List<String>.from(verbKeywordQuickGroupO)},
        {'label': 'TPX', 'keywords': List<String>.from(verbKeywordQuickTpx)},
      ];

  Future<void> _saveKeywordShortcuts() async {
    try {
      await _prefsService?.saveKeywordShortcuts(_keywordShortcuts);
    } catch (_) {}
  }

  void _showKeywordShortcutContextMenu(int index, Offset position) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: Colors.grey.shade50,
      elevation: 3,
      items: [
        PopupMenuItem(
          value: 'edit',
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('Edit',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade800)),
        ),
        PopupMenuItem(
          value: 'delete',
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('Delete',
              style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
        ),
      ],
    );
    if (!mounted) return;
    if (result == 'edit') {
      _showKeywordShortcutEditor(editIndex: index);
    } else if (result == 'delete') {
      setState(() => _keywordShortcuts.removeAt(index));
      _saveKeywordShortcuts();
    }
  }

  void _showKeywordShortcutEditor({int? editIndex}) {
    final existing = editIndex != null ? _keywordShortcuts[editIndex] : null;
    showDialog<void>(
      context: context,
      builder: (ctx) => _KeywordShortcutEditorDialog(
        initialLabel: existing?['label'] as String? ?? '',
        initialKeywords: (existing?['keywords'] as List?)
                ?.map((e) => e.toString())
                .join(', ') ??
            '',
        isEdit: editIndex != null,
        onSave: (label, keywords) {
          final entry = <String, dynamic>{
            'label': label,
            'keywords': keywords,
          };
          setState(() {
            if (editIndex != null) {
              _keywordShortcuts[editIndex] = entry;
            } else {
              _keywordShortcuts.add(entry);
            }
          });
          _saveKeywordShortcuts();
        },
      ),
    );
  }

  @override
  void didUpdateWidget(covariant KeyboardFirePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When image changes (next/previous), deselect verb and show "(last used)" beside it; reset firebar
    if (oldWidget.currentIndex != widget.currentIndex) {
      final cat = _pickedVerbCategory;
      final idx = _pickedVerbIndex;
      final cats = _verbList;
      if (cat != null && idx != null && cats.length >= cat) {
        final verbList =
            (cats[cat - 1]['verbs'] as List<dynamic>?)?.cast<String>();
        if (verbList != null && idx <= verbList.length) {
          _lastUsedVerbLabel = verbList[idx - 1];
        }
      }

      // If a verb is pinned, keep it selected and auto-apply it to the new image.
      // We tell CaptionFieldsWidget about the pending verb BEFORE _loadMetadata()
      // runs, so it applies the verb at the end of _loadMetadata() — after the
      // metadata caption is written, with no post-frame timing race.
      if (_pinnedVerbCategory != null && _pinnedVerbIndex != null) {
        _pickedVerbCategory = _pinnedVerbCategory;
        _pickedVerbIndex = _pinnedVerbIndex;
        widget.captionState
            ?.setPendingPinnedVerb(_pinnedVerbCategory!, _pinnedVerbIndex!);
        if (mounted) setState(() {});
      } else {
        _pickedVerbCategory = null;
        _pickedVerbIndex = null;
      }

      // Reset firebar so next caption starts at H/V
      _firebarStep = 0;
      _firebarHv = null;
      _firebarTeam1Value = '';
      _firebarTeam2Value = '';
      _firebarCategoryValue = '';
      _firebarVerbValue = '';
      _firebarController.clear();
      _customVerbController.clear();
      widget.captionState?.updateCustomVerbFromPopup('');
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _prefsService?.captionFieldVisibilityRevision
        .removeListener(_onKeyboardFireCaptionFieldVisibilityRevision);
    _inputController.dispose();
    _inputFocus.dispose();
    _firebarController.dispose();
    _firebarFocus.dispose();
    _homeBarController.dispose();
    _awayBarController.dispose();
    _categoryBarController.dispose();
    _verbBarController.dispose();
    _customVerbController.dispose();
    _categoriesScrollController.dispose();
    _verbsScrollController.dispose();
    _homeBarFocus.dispose();
    _awayBarFocus.dispose();
    _categoryBarFocus.dispose();
    _verbBarFocus.dispose();
    super.dispose();
  }

  List<String> _parseNumbers(String text) {
    return text
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Given number string(s) (e.g. "7 23") and roster, return ghosted text like "Smith, Jones".
  String _playerNamesForNumbers(String text, List<Player> roster) {
    if (roster.isEmpty) return '';
    final numbers = _parseNumbers(text);
    if (numbers.isEmpty) return '';
    final names = <String>[];
    for (final numStr in numbers) {
      try {
        final p = roster
            .firstWhere((p) => (p.jerseyNumber ?? '').trim() == numStr.trim());
        final raw = p.displayName;
        final name = raw.replaceFirst(RegExp(r' #\d+$'), '').trim();
        names.add(name.isEmpty ? raw : name);
      } catch (_) {}
    }
    return names.join(', ');
  }

  void _onStep1Submit() {
    final numbers = _parseNumbers(_inputController.text);
    if (numbers.isEmpty) return;
    for (final n in numbers) {
      widget.captionState?.addPlayerByJersey(true, n);
    }
    widget.captionState?.updateCaptionFromKeyboardFire();
    setState(() {
      _homeSummary = numbers.map((n) => '#$n').join(', ');
      _inputController.clear();
      _step = 1;
    });
    _inputFocus.requestFocus();
  }

  void _onStep2Submit() {
    final text = _inputController.text.trim().toLowerCase();
    if (text == 'n' || text == 'no' || text.isEmpty) {
      widget.captionState?.updateCaptionFromKeyboardFire();
      setState(() {
        _awaySummary = 'None';
        _inputController.clear();
        _step = 2;
      });
      _inputFocus.requestFocus();
      return;
    }
    final numbers = _parseNumbers(_inputController.text);
    for (final n in numbers) {
      widget.captionState?.addPlayerByJersey(false, n);
    }
    widget.captionState?.updateCaptionFromKeyboardFire();
    setState(() {
      _awaySummary =
          numbers.isEmpty ? 'None' : numbers.map((n) => '#$n').join(', ');
      _inputController.clear();
      _step = 2;
    });
    _inputFocus.requestFocus();
  }

  void _onHomeBarSubmit() {
    final numbers = _parseNumbers(_homeBarController.text);
    if (numbers.isEmpty) return;
    for (final n in numbers) {
      widget.captionState?.addPlayerByJersey(true, n);
    }
    widget.captionState?.updateCaptionFromKeyboardFire();
    _homeBarController.clear();
    setState(() {
      _homeSummary = numbers.map((n) => '#$n').join(', ');
      if (_step == 0) _step = 1;
    });
    _awayBarFocus.requestFocus();
    _refreshCaptionPreviewLater();
  }

  void _onAwayBarSubmit() {
    final text = _awayBarController.text.trim().toLowerCase();
    if (text == 'n' || text == 'no' || text.isEmpty) {
      widget.captionState?.updateCaptionFromKeyboardFire();
      _awayBarController.clear();
      setState(() {
        _awaySummary = 'None';
        _step = 2;
      });
      _categoryBarFocus.requestFocus();
      _refreshCaptionPreviewLater();
      return;
    }
    final numbers = _parseNumbers(_awayBarController.text);
    for (final n in numbers) {
      widget.captionState?.addPlayerByJersey(false, n);
    }
    widget.captionState?.updateCaptionFromKeyboardFire();
    _awayBarController.clear();
    setState(() {
      _awaySummary =
          numbers.isEmpty ? 'None' : numbers.map((n) => '#$n').join(', ');
      _step = 2;
    });
    _categoryBarFocus.requestFocus();
    _refreshCaptionPreviewLater();
  }

  void _onCategoryBarSubmit() {
    final n = int.tryParse(_categoryBarController.text.trim());
    if (n == null || n < 1) return;
    final cats = _verbList;
    if (cats.isEmpty) return;
    final index = (n - 1).clamp(0, cats.length - 1);
    setState(() {
      _selectedCategoryIndex = index;
      _categoryBarController.clear();
    });
    _verbBarFocus.requestFocus();
  }

  void _onVerbBarInput(String value) {
    if (value.length < 2) return;
    final cat = int.tryParse(value[0]);
    final verbNum = value[1] == '0' ? 10 : int.tryParse(value[1]);
    if (cat == null || verbNum == null || cat < 1 || cat > 6) return;
    widget.captionState?.selectVerbByCategoryAndIndex(cat, verbNum);
    widget.captionState?.updateCaptionFromKeyboardFire();
    setState(() {
      _verbSummary = 'Category $cat, verb $verbNum selected';
      _waitingForVerb = false;
      _pickedVerbCategory = cat;
      _pickedVerbIndex = verbNum;
      _selectedCategoryIndex = (cat - 1).clamp(0, _verbList.length - 1);
    });
    _refreshCaptionPreviewLater();
  }

  void _refreshCaptionPreviewLater() {
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() {});
    });
  }

  /// Apply H or V choice (step 0). Used by firebar submit, onChanged, and global shortcut.
  void _applyFirebarHv(String hv) {
    if (hv != 'H' && hv != 'V') return;
    widget.captionState?.clearPlayersForKeyboardFire();
    setState(() {
      _firebarHv = hv;
      _firebarTeam1Value = '';
      _firebarTeam2Value = '';
      _firebarCategoryValue = '';
      _firebarVerbValue = '';
      _firebarStep = 1;
    });
    _firebarController.clear();
    _firebarFocus.requestFocus();
  }

  /// Handle category step (3): one digit selects category and advances to verb step.
  void _firebarApplyCategoryInput(String text) {
    final n = int.tryParse(text.trim());
    final cats = _verbList;
    if (n == null || n < 1 || cats.isEmpty) return;
    final index = (n - 1).clamp(0, cats.length - 1);
    setState(() {
      _selectedCategoryIndex = index;
      _firebarCategoryValue = text.trim();
      _firebarStep = 4;
    });
    _firebarController.clear();
    _firebarFocus.requestFocus();
  }

  /// Handle verb step (4): one digit = verb in current category; two digits = category + verb. Applies and resets.
  void _firebarApplyVerbInput(String text) {
    final cats = _verbList;
    if (cats.isEmpty) return;
    int catNum =
        _selectedCategoryIndex != null ? _selectedCategoryIndex! + 1 : 1;
    int verbNum;
    if (text.length >= 2) {
      final c = int.tryParse(text[0]);
      final v = text[1] == '0' ? 10 : int.tryParse(text[1]);
      if (c != null && c >= 1 && v != null && v >= 1) {
        catNum = c;
        verbNum = v;
      } else {
        verbNum = int.tryParse(text) ?? 0;
        if (verbNum < 1) return;
      }
    } else {
      verbNum = text == '0' ? 10 : (int.tryParse(text) ?? 0);
      if (verbNum < 1) return;
    }
    widget.captionState
        ?.selectVerbByCategoryAndIndexFromKeyboardFire(catNum, verbNum);
    widget.captionState?.updateCaptionFromKeyboardFire();
    setState(() {
      _verbSummary = 'Category $catNum, verb $verbNum selected';
      _waitingForVerb = false;
      _pickedVerbCategory = catNum;
      _pickedVerbIndex = verbNum;
      _firebarStep = 5; // next: (S)ave (C)opy (F)TP
    });
    _firebarController.clear();
    _firebarFocus.requestFocus();
    _refreshCaptionPreviewLater();
  }

  /// Handle firebar step 5: (S)ave (C)opy (F)TP. Copy keeps you on step 5; Save and FTP reset.
  void _firebarApplyActionInput(String letter) {
    final c = letter.trim().toUpperCase();
    if (c.isEmpty) return;
    if (c == 'S') {
      if (widget.onSaveIptc != null) widget.onSaveIptc!();
      widget.onNextImage?.call();
      setState(() {
        _firebarStep = 0;
        _firebarHv = null;
        _firebarTeam1Value = '';
        _firebarTeam2Value = '';
        _firebarCategoryValue = '';
        _firebarVerbValue = '';
      });
      _firebarController.clear();
      _firebarFocus.requestFocus();
    } else if (c == 'C' && widget.onCopy != null) {
      widget.onCopy!();
      _firebarController.clear();
      _firebarFocus.requestFocus();
      // Stay on step 5 so user can still hit Save or FTP
    } else if (c == 'F' && !widget.ftpDisabled && widget.onFtp != null) {
      widget.onFtp!();
      setState(() {
        _firebarStep = 0;
        _firebarHv = null;
        _firebarTeam1Value = '';
        _firebarTeam2Value = '';
        _firebarCategoryValue = '';
        _firebarVerbValue = '';
      });
      _firebarController.clear();
      _firebarFocus.requestFocus();
    }
  }

  void _onFirebarSubmit() {
    final text = _firebarController.text.trim();
    _firebarController.clear();

    switch (_firebarStep) {
      case 0: // H or V (normally handled by onChanged or global shortcut; Enter also works)
        final hv = text.toUpperCase();
        _applyFirebarHv(hv);
        return;
      case 1: // Players on chosen team (home if H, away if V)
        final numbers = _parseNumbers(text);
        final isHome = _firebarHv == 'H';
        for (final n in numbers) {
          widget.captionState?.addPlayerByJersey(isHome, n);
        }
        setState(() {
          _firebarTeam1Value =
              numbers.isEmpty ? '—' : numbers.map((n) => '#$n').join(' ');
          _firebarStep = 2;
        });
        widget.captionState?.updateCaptionFromKeyboardFire();
        break;
      case 2: // Players on other team (or Enter to skip)
        final numbers = _parseNumbers(text);
        final isHome = _firebarHv == 'V'; // other team
        for (final n in numbers) {
          widget.captionState?.addPlayerByJersey(isHome, n);
        }
        setState(() {
          _firebarTeam2Value =
              numbers.isEmpty ? '—' : numbers.map((n) => '#$n').join(' ');
          _firebarStep = 3;
        });
        widget.captionState?.updateCaptionFromKeyboardFire();
        break;
      case 3: // Verb category number (Enter also works)
        _firebarApplyCategoryInput(text);
        return;
      case 4: // Verb number (Enter also works)
        _firebarApplyVerbInput(text);
        return;
      case 5: // (S)ave (C)opy (F)TP (Enter with S/C/F also works)
        _firebarApplyActionInput(text);
        return;
    }
    _firebarFocus.requestFocus();
  }

  void _done() {
    widget.captionState?.updateCaptionFromKeyboardFire();
    if (widget.showDialogActions) {
      Navigator.of(context).pop();
    }
  }

  String get _captionPreview {
    final state = widget.captionState;
    if (state == null) return '';
    try {
      return (state as dynamic).currentCaptionText as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Editable caption field bound to captionState's caption controller.
  Widget _buildCaptionField() {
    return Builder(builder: (context) {
      TextEditingController? ctrl;
      try {
        ctrl = (widget.captionState as dynamic).captionTextController
            as TextEditingController?;
      } catch (_) {}
      if (ctrl == null) {
        return TextField(
          expands: true,
          maxLines: null,
          textAlignVertical: TextAlignVertical.top,
          cursorHeight: 12,
          cursorColor: Colors.black87,
          style: const TextStyle(fontSize: 11),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Caption will appear here as you add players and a verb.',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            filled: true,
            fillColor: _panelBackgroundLight,
          ),
        );
      }
      return TextField(
        controller: ctrl,
        expands: true,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        cursorHeight: 12,
        cursorColor: Colors.black87,
        style: const TextStyle(fontSize: 11),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Caption will appear here as you add players and a verb.',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          filled: true,
          fillColor: _panelBackgroundLight,
        ),
      );
    });
  }

  Widget _buildBylineButton() {
    final hasOverride =
        (widget.captionState as dynamic?)?.hasBylineOverride == true;
    return GestureDetector(
      onTap: () => (widget.captionState as dynamic?)?.openBylineEditor(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.edit_outlined,
            size: 11,
            color: hasOverride
                ? const Color(0xFF1976D2)
                : Colors.grey.shade500,
          ),
          const SizedBox(width: 2),
          Text(
            'Byline',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: hasOverride
                  ? const Color(0xFF1976D2)
                  : Colors.grey.shade500,
            ),
          ),
          if (hasOverride) ...[
            const SizedBox(width: 3),
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: Color(0xFF1976D2),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKbLabeledBox(String label, Widget child,
      {Widget? trailingAction}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 1),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.zero,
            border: Border(
              left: BorderSide(color: Colors.grey.shade300, width: 1),
              top: BorderSide(color: Colors.grey.shade300, width: 1),
              right: BorderSide(color: Colors.grey.shade300, width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: trailingAction != null
              ? Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const Spacer(),
                    trailingAction,
                  ],
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: _panelBackgroundLight,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: Colors.grey.shade300, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            padding: const EdgeInsets.all(3),
            child: child,
          ),
        ),
      ],
    );
  }

  Widget _buildHeadlineFieldKb() {
    TextEditingController? ctrl;
    try {
      ctrl = (widget.captionState as dynamic).headlineTextController
          as TextEditingController?;
    } catch (_) {}
    if (ctrl == null) {
      return TextField(
        expands: true,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        cursorHeight: 12,
        cursorColor: Colors.black87,
        style: const TextStyle(fontSize: 11),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Headline',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          filled: true,
          fillColor: _panelBackgroundLight,
        ),
      );
    }
    return TextField(
      controller: ctrl,
      expands: true,
      maxLines: null,
      textAlignVertical: TextAlignVertical.top,
        cursorHeight: 12,
        cursorColor: Colors.black87,
        style: const TextStyle(fontSize: 11),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Headline',
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        filled: true,
        fillColor: _panelBackgroundLight,
      ),
    );
  }

  Widget _buildKeywordsFieldKb() {
    TextEditingController? ctrl;
    try {
      ctrl = (widget.captionState as dynamic).keywordsTextController
          as TextEditingController?;
    } catch (_) {}
    if (ctrl == null) {
      return TextField(
        expands: true,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        cursorHeight: 12,
        cursorColor: Colors.black87,
        style: const TextStyle(fontSize: 11),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Keywords',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          filled: true,
          fillColor: _panelBackgroundLight,
        ),
      );
    }
    return TextField(
      controller: ctrl,
      expands: true,
      maxLines: null,
      textAlignVertical: TextAlignVertical.top,
        cursorHeight: 12,
        cursorColor: Colors.black87,
        style: const TextStyle(fontSize: 11),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Keywords',
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        filled: true,
        fillColor: _panelBackgroundLight,
      ),
    );
  }

  Widget _buildPersonalityFieldKb() {
    return Builder(builder: (context) {
      TextEditingController? ctrl;
      try {
        ctrl = (widget.captionState as dynamic).personalityTextController
            as TextEditingController?;
      } catch (_) {}
      if (ctrl == null) {
        return TextField(
          expands: true,
          maxLines: null,
          textAlignVertical: TextAlignVertical.top,
        cursorHeight: 12,
        cursorColor: Colors.black87,
        style: const TextStyle(fontSize: 11),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Personality',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            filled: true,
            fillColor: _panelBackgroundLight,
          ),
        );
      }
      return TextField(
        controller: ctrl,
        expands: true,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        cursorHeight: 12,
        cursorColor: Colors.black87,
        style: const TextStyle(fontSize: 11),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          filled: true,
          fillColor: _panelBackgroundLight,
        ),
      );
    });
  }

  /// Caption with optional Personality/Headline/Keywords stacked vertically.
  Widget _buildKeyboardFireCaptionStrip() {
    final hasSecondary =
        _showHeadlineField || _showKeywordsField || _showPersonalityField;

    if (!hasSecondary) {
      return _buildKbLabeledBox('Caption', _buildCaptionField(),
          trailingAction: _buildBylineButton());
    }

    final cards = <Widget>[];
    if (_showPersonalityField) {
      cards.add(_buildKbLabeledBox('Personality', _buildPersonalityFieldKb()));
    }
    if (_showHeadlineField) {
      cards.add(_buildKbLabeledBox('Headline', _buildHeadlineFieldKb()));
    }
    if (_showKeywordsField) {
      cards.add(_buildKbLabeledBox('Keywords', _buildKeywordsFieldKb()));
    }

    final rightChildren = <Widget>[];
    for (var i = 0; i < cards.length; i++) {
      if (i > 0) rightChildren.add(const SizedBox(height: 6));
      rightChildren.add(Expanded(child: cards[i]));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: _buildKbLabeledBox('Caption', _buildCaptionField(),
              trailingAction: _buildBylineButton()),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rightChildren,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildRosterRows(List<Player> roster, bool isHomeTeam,
      {String? barText}) {
    if (roster.isEmpty) return [];
    final selectedNames = _getSelectedPlayerNames(isHomeTeam);
    final currentNumbers = _parseNumbers(barText ?? '');
    final sorted = List<Player>.from(roster)
      ..sort((a, b) {
        final an = int.tryParse(a.jerseyNumber ?? '') ?? 999;
        final bn = int.tryParse(b.jerseyNumber ?? '') ?? 999;
        return an.compareTo(bn);
      });
    return sorted.map((p) {
      final num = p.jerseyNumber ?? '—';
      final raw = p.displayName;
      final name = raw.replaceFirst(RegExp(r' #\d+$'), '').trim();
      final displayName = name.isEmpty ? raw : name;
      final jersey = p.jerseyNumber ?? '';
      final isPicked = raw.isNotEmpty && selectedNames.contains(raw);
      final isCurrent = jersey.isNotEmpty &&
          currentNumbers.any((n) => n.trim() == jersey.trim());
      final rosterKey = jersey.isNotEmpty ? '${isHomeTeam}_$jersey' : null;
      final isHovered = rosterKey != null && _hoveredRosterKey == rosterKey;
      final bgColor = isPicked
          ? const Color(0xFFDBEAFF)
          : (isCurrent
              ? Colors.grey.shade200
              : (isHovered ? Colors.grey.shade200 : null));
      return MouseRegion(
        onEnter: rosterKey != null
            ? (_) => setState(() => _hoveredRosterKey = rosterKey)
            : null,
        onExit: rosterKey != null
            ? (_) => setState(() => _hoveredRosterKey = null)
            : null,
        child: InkWell(
          onTap: jersey.isNotEmpty
              ? () {
                  final state = widget.captionState;
                  if (state == null) return;
                  if (isPicked) {
                    (state as dynamic).removePlayerByJersey(isHomeTeam, jersey);
                  } else {
                    state.addPlayerByJersey(isHomeTeam, jersey);
                  }
                  state.updateCaptionFromKeyboardFire();
                  setState(() {});
                  _refreshCaptionPreviewLater();
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            decoration: BoxDecoration(
              color: bgColor,
              border: isPicked
                  ? const Border(
                      left: BorderSide(color: Color(0xFF4A90E2), width: 3),
                    )
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    num,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isPicked
                          ? const Color(0xFF0052CC)
                          : Colors.grey.shade800,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isPicked ? const Color(0xFF0052CC) : Colors.black87,
                      fontWeight:
                          isPicked ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  /// One cell in the number grid (jersey + last name) or empty decade slot.
  Widget _buildRosterSquareGridCell({
    required Player? player,
    required bool isHomeTeam,
    required Set<String> selectedNames,
  }) {
    const double gridCellHeight = 30;
    if (player == null) {
      return SizedBox(
        height: gridCellHeight,
        child: Container(
            margin: const EdgeInsets.all(0.5),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border.all(color: Colors.grey.shade200, width: 0.5),
              borderRadius: BorderRadius.circular(2),
            )),
      );
    }
    final jersey = player.jerseyNumber ?? '?';
    final isPicked = selectedNames.contains(player.displayName);
    final lastName = player.fullName.contains(' ')
        ? player.fullName.split(' ').sublist(1).join(' ').trim()
        : player.fullName;
    return SizedBox(
      height: gridCellHeight,
      child: Tooltip(
        message: player.fullName,
        waitDuration: const Duration(milliseconds: 250),
        child: GestureDetector(
          onTap: () {
            final state = widget.captionState;
            if (state == null) return;
            if (isPicked) {
              (state as dynamic).removePlayerByJersey(isHomeTeam, jersey);
            } else {
              state.addPlayerByJersey(isHomeTeam, jersey);
            }
            state.updateCaptionFromKeyboardFire();
            setState(() {});
            _refreshCaptionPreviewLater();
          },
          child: Container(
            margin: const EdgeInsets.all(0.5),
            decoration: BoxDecoration(
              color: isPicked ? const Color(0xFFDBEAFF) : Colors.white,
              border: Border.all(
                color: isPicked ? const Color(0xFF4A90E2) : Colors.grey.shade300,
                width: isPicked ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            // Keep name text at a fixed size across all cells.
            padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  jersey,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isPicked ? FontWeight.w600 : FontWeight.w500,
                    color: isPicked ? const Color(0xFF0052CC) : Colors.black87,
                  ),
                ),
                Text(
                  lastName,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    height: 1.0,
                    color: isPicked ? const Color(0xFF0052CC) : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Number grid: one row per decade (0–9, 10–19, 20–29, …) and only real
  /// player cells are rendered (no empty placeholder squares).
  Widget _buildRosterSquareGrid(List<Player> roster, bool isHomeTeam) {
    if (roster.isEmpty) {
      return Center(
        child: Text('No players',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      );
    }
    final selectedNames = _getSelectedPlayerNames(isHomeTeam);
    final byNum = <int, Player>{};
    final nonNumeric = <Player>[];
    for (final p in roster) {
      final j = int.tryParse(p.jerseyNumber?.trim() ?? '');
      if (j != null) {
        byNum[j] = p;
      } else {
        nonNumeric.add(p);
      }
    }
    if (byNum.isEmpty && nonNumeric.isEmpty) {
      return Center(
        child: Text('No players',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      );
    }

    final buckets = byNum.keys.map((j) => j ~/ 10).toSet().toList()..sort();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in buckets)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Wrap(
                spacing: 1,
                runSpacing: 1,
                children: [
                  for (int d = 0; d < 10; d++)
                    if (byNum[b * 10 + d] != null)
                      SizedBox(
                        width: 40,
                        child: _buildRosterSquareGridCell(
                          player: byNum[b * 10 + d],
                          isHomeTeam: isHomeTeam,
                          selectedNames: selectedNames,
                        ),
                      ),
                ],
              ),
            ),
          if (nonNumeric.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Other',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: nonNumeric.map((player) {
                final jersey = player.jerseyNumber ?? '?';
                final isPicked = selectedNames.contains(player.displayName);
                final lastName = player.fullName.contains(' ')
                    ? player.fullName.split(' ').sublist(1).join(' ').trim()
                    : player.fullName;
                return GestureDetector(
                  onTap: () {
                    final state = widget.captionState;
                    if (state == null) return;
                    if (isPicked) {
                      (state as dynamic).removePlayerByJersey(isHomeTeam, jersey);
                    } else {
                      state.addPlayerByJersey(isHomeTeam, jersey);
                    }
                    state.updateCaptionFromKeyboardFire();
                    setState(() {});
                    _refreshCaptionPreviewLater();
                  },
                  child: Container(
                    width: 56,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 6),
                    decoration: BoxDecoration(
                      color: isPicked ? const Color(0xFFDBEAFF) : Colors.white,
                      border: Border.all(
                        color: isPicked
                            ? const Color(0xFF4A90E2)
                            : Colors.grey.shade300,
                        width: isPicked ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          jersey,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                isPicked ? FontWeight.w600 : FontWeight.w500,
                            color: isPicked
                                ? const Color(0xFF0052CC)
                                : Colors.black87,
                          ),
                        ),
                        Text(
                          lastName,
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w500,
                            height: 1.05,
                            color: isPicked
                                ? const Color(0xFF0052CC)
                                : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRosterSection(String teamLabel, List<Player> roster,
      {required bool isHomeTeam}) {
    if (roster.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 1),
          child: Text(
            teamLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        ..._buildRosterRows(roster, isHomeTeam),
      ],
    );
  }

  /// Returns the set of selected player identifiers (display names) for the given team.
  Set<String> _getSelectedPlayerNames(bool isHomeTeam) {
    final state = widget.captionState;
    if (state == null) return {};
    try {
      final set = isHomeTeam
          ? (state as dynamic).selectedHomePlayers
          : (state as dynamic).selectedAwayPlayers;
      return set is Set<String> ? set : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _setKeyboardShortcutsHelpVisible(bool visible) async {
    setState(() => _showKeyboardFireShortcutsHelp = visible);
    final p = _prefsService;
    if (p != null) await p.saveShowKeyboardFireShortcutsHelp(visible);
  }

  Widget _shortcutHelpRow(String keys, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 56),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.zero,
            ),
            child: Text(
              keys,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                fontSize: 10,
                height: 1.35,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyboardShortcutsHelpSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          height: 1,
          color: Colors.grey.shade300,
        ),
        const SizedBox(height: 6),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _setKeyboardShortcutsHelpVisible(
                !_showKeyboardFireShortcutsHelp),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    _showKeyboardFireShortcutsHelp
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 12,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Shortcuts',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _showKeyboardFireShortcutsHelp ? 'Hide' : 'Show',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_showKeyboardFireShortcutsHelp) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
            decoration: BoxDecoration(
              color: _panelBackgroundLight,
              borderRadius: BorderRadius.zero,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _shortcutHelpRow('⌘S', 'Save caption & next image (Ctrl+S)'),
                _shortcutHelpRow(
                    '⌘⏎',
                    'Save, FTP upload, next image (Ctrl+Enter). Uses active FTP profile.'),
                _shortcutHelpRow(
                    '⌘⇧V', 'Paste previous caption (Ctrl+Shift+V)'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPlayerViewModeToggle() {
    Widget segment({
      required bool selected,
      required IconData icon,
      required String tooltip,
      required VoidCallback onTap,
    }) {
      return Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onTap,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 20, height: 20),
          visualDensity: VisualDensity.compact,
          splashRadius: 14,
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: selected ? Colors.black87 : Colors.grey.shade500,
          ),
          icon: Icon(icon, size: 14),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        segment(
          selected: !_useSquarePlayerView,
          icon: Icons.format_list_bulleted,
          tooltip: 'List view (names)',
          onTap: () => setState(() => _useSquarePlayerView = false),
        ),
        const SizedBox(width: 2),
        segment(
          selected: _useSquarePlayerView,
          icon: Icons.grid_view,
          tooltip: 'Number grid: rows 0–9, 10–19, 20–29 … (10 per row)',
          onTap: () => setState(() => _useSquarePlayerView = true),
        ),
      ],
    );
  }

  Widget _buildColumnBar({
    required TextEditingController controller,
    required FocusNode focusNode,
    required void Function() onSubmitted,
    List<TextInputFormatter>? inputFormatters,
    void Function(String)? onChanged,
    List<Player>? rosterForGhostNames,
    Widget? trailing,
  }) {
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      cursorHeight: 14,
      cursorColor: Colors.black87,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Colors.black87, width: 1),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: inputFormatters,
      onSubmitted: (_) => onSubmitted(),
      onChanged: onChanged,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: trailing == null
          ? field
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: field),
                const SizedBox(width: 4),
                trailing,
              ],
            ),
    );
  }

  Widget _buildKeywordShortcutChipsKb() {
    try {
      final dynamic st = widget.captionState;
      if (st == null) return const SizedBox.shrink();
      final ctrl = st.keywordsTextController;
      if (ctrl is! TextEditingController) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Keyword Shortcuts',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _showKeywordShortcutEditor(),
                  child: Tooltip(
                    message: 'Add keyword shortcut',
                    waitDuration: const Duration(milliseconds: 500),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Icon(Icons.add,
                          size: 11, color: Colors.grey.shade700),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            VerbKeywordQuickBar(
              key: ValueKey(widget.currentIndex ?? 0),
              controller: ctrl,
              shortcuts: _keywordShortcuts,
              onInserted: () {
                _refreshCaptionPreviewLater();
                if (mounted) setState(() {});
              },
              onContextMenu: _showKeywordShortcutContextMenu,
            ),
          ],
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildApplyKeywordsToggleKb() {
    Future<void> syncKeywordsFieldVisibility({
      required bool applyVerbKeywords,
      required bool applyNameKeywords,
    }) async {
      final shouldShowKeywords = applyVerbKeywords || applyNameKeywords;
      if (_showKeywordsField == shouldShowKeywords) return;
      setState(() => _showKeywordsField = shouldShowKeywords);
      try {
        await _prefsService?.saveShowKeywordsField(shouldShowKeywords);
      } catch (_) {}
    }

    return Tooltip(
      message:
          'When On, choosing a verb adds its keyword presets to the Keywords field.',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: () async {
          final v = !_applyVerbKeywordsEnabledKb;
          setState(() => _applyVerbKeywordsEnabledKb = v);
          try {
            await (widget.captionState as dynamic)
                .setApplyVerbKeywordsEnabled(v);
          } catch (_) {
            try {
              await _prefsService?.saveApplyVerbKeywords(v);
            } catch (_) {}
          }
          await syncKeywordsFieldVisibility(
            applyVerbKeywords: v,
            applyNameKeywords: _applyPlayerNamesToKeywordsEnabledKb,
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildKeywordToggleLabel('Keyword Verbs', fontSize: 9),
            const SizedBox(width: 4),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFF1976D2),
                  width: 1.2,
                ),
                borderRadius: BorderRadius.circular(2),
                color: _applyVerbKeywordsEnabledKb
                    ? const Color(0xFF1976D2)
                    : Colors.white,
              ),
              child: _applyVerbKeywordsEnabledKb
                  ? const Center(
                      child: Icon(
                        Icons.check,
                        size: 10,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerNamesKeywordsToggleKb() {
    Future<void> setKeywordNamesEnabled(bool v) async {
      setState(() => _applyPlayerNamesToKeywordsEnabledKb = v);
      try {
        await (widget.captionState as dynamic)
            .setApplyPlayerNamesToKeywordsEnabled(v);
      } catch (_) {
        try {
          await _prefsService?.saveApplyPlayerNamesToKeywords(v);
        } catch (_) {}
      }
      final shouldShowKeywords = _applyVerbKeywordsEnabledKb || v;
      if (_showKeywordsField != shouldShowKeywords) {
        setState(() => _showKeywordsField = shouldShowKeywords);
        try {
          await _prefsService?.saveShowKeywordsField(shouldShowKeywords);
        } catch (_) {}
      }
    }

    return Tooltip(
      message:
          'When On, selected player names are added to Keywords when applying verb keywords.',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
          onTap: () =>
              setKeywordNamesEnabled(!_applyPlayerNamesToKeywordsEnabledKb),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildKeywordToggleLabel('Keyword Names', fontSize: 9),
              const SizedBox(width: 4),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFF1976D2),
                    width: 1.2,
                  ),
                  borderRadius: BorderRadius.circular(2),
                  color: _applyPlayerNamesToKeywordsEnabledKb
                      ? const Color(0xFF1976D2)
                      : Colors.white,
                ),
                child: _applyPlayerNamesToKeywordsEnabledKb
                    ? const Center(
                        child: Icon(
                          Icons.check,
                          size: 10,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 2),
            ],
          ),
        ),
    );
  }

  Widget _buildKeywordToggleLabel(String text, {double fontSize = 9}) {
    return Text(
      text,
      softWrap: false,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.normal,
        height: 1.0,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildRosterColumn(String teamLabel, List<Player> roster,
      {required bool isHomeTeam}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
        child: _buildRosterSection(teamLabel, roster, isHomeTeam: isHomeTeam),
      ),
    );
  }

  /// Roster list only (no border; caller wraps with bar inside same box).
  /// [barText] is the current bar input; matching rows get grey, committed get blue.
  Widget _buildRosterColumnContent(List<Player> roster, bool isHomeTeam,
      {String? barText}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildRosterRows(roster, isHomeTeam, barText: barText),
      ),
    );
  }

  List<Map<String, dynamic>> get _verbList {
    final state = widget.captionState;
    if (state == null) return [];
    try {
      final list = (state as dynamic).keyboardFireVerbList;
      if (list is List<Map<String, dynamic>>) return list;
      if (list is List) return List<Map<String, dynamic>>.from(list);
    } catch (_) {}
    return [];
  }

  /// Category list only (no border; caller wraps with bar inside same box).
  /// Hold a row ~500 ms then drag to reorder; quick tap selects.
  Widget _buildCategoryPanelContent({String? barText}) {
    final cats = _verbList;
    if (cats.isEmpty) {
      return Center(
        child: Text('No categories',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      );
    }
    final barCatNum = int.tryParse(barText?.trim() ?? '');
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: cats.length,
      itemBuilder: (context, i) {
        final cat = cats[i];
        final catNum = cat['number'] as int? ?? (i + 1);
        final name = cat['name'] as String? ?? '';
        final isFavs = name == 'Favorites';
        final isSelected = _selectedCategoryIndex == i;
        final isCurrent = barCatNum != null && barCatNum == catNum;
        final isDragging = _dragFromCatIndex == i;
        final isDragOver = _dragToCatIndex == i && _dragFromCatIndex != i;

        Color bgColor;
        if (isDragging) {
          bgColor = Colors.blue.shade100;
        } else if (isDragOver) {
          bgColor = Colors.blue.shade50;
        } else if (isSelected) {
          bgColor = Colors.blue.shade50;
        } else if (isCurrent) {
          bgColor = Colors.grey.shade200;
        } else if (isFavs) {
          bgColor = Colors.amber.shade50;
        } else {
          bgColor = Colors.transparent;
        }

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            _catLongPressTimer?.cancel();
            _catLongPressTimer = Timer(const Duration(milliseconds: 500), () {
              setState(() {
                _dragFromCatIndex = i;
                _dragToCatIndex = i;
              });
            });
          },
          onPointerMove: (e) {
            if (_dragFromCatIndex != null) {
              final target = _catIndexAtGlobalY(e.position.dy);
              if (target != null && target != _dragToCatIndex) {
                setState(() => _dragToCatIndex = target);
              }
            }
          },
          onPointerUp: (e) {
            _catLongPressTimer?.cancel();
            if (_dragFromCatIndex != null &&
                _dragToCatIndex != null &&
                _dragFromCatIndex != _dragToCatIndex) {
              final state = widget.captionState;
              if (state != null) {
                try {
                  (state as dynamic)
                      .reorderCategories(_dragFromCatIndex!, _dragToCatIndex!);
                } catch (_) {}
              }
              setState(() {
                _dragFromCatIndex = null;
                _dragToCatIndex = null;
              });
            } else if (_dragFromCatIndex == null) {
              setState(() => _selectedCategoryIndex = i);
            } else {
              setState(() {
                _dragFromCatIndex = null;
                _dragToCatIndex = null;
              });
            }
          },
          onPointerCancel: (_) {
            _catLongPressTimer?.cancel();
            setState(() {
              _dragFromCatIndex = null;
              _dragToCatIndex = null;
            });
          },
          child: MouseRegion(
            cursor: _dragFromCatIndex != null
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.grab,
            child: Container(
              key: _catKey(i),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              decoration: BoxDecoration(
                color: bgColor,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
                  top: isDragOver
                      ? BorderSide(color: Colors.blue.shade400, width: 2)
                      : BorderSide.none,
                ),
              ),
              child: Opacity(
                opacity: isDragging ? 0.5 : 1.0,
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: Text(
                        '$catNum',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: (isSelected || isCurrent)
                              ? Colors.grey.shade900
                              : Colors.grey.shade800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 12,
                      color: isSelected
                          ? Colors.grey.shade700
                          : Colors.grey.shade400,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Single column: each category as a header, then its verb rows (if expanded). One bar = 2 digits (cat + verb).
  Widget _buildCategoriesWithVerbsContent({String? barText}) {
    final cats = _verbList;
    if (cats.isEmpty) {
      return Center(
        child: Text('No categories',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      );
    }
    // Build flat list: for each category, one header then verb rows only if this one is expanded.
    int totalCount = 0;
    for (int ci = 0; ci < cats.length; ci++) {
      final verbs = (cats[ci]['verbs'] as List<dynamic>?)?.cast<String>() ?? [];
      final isExpanded = _expandedCategoryIndex == ci;
      totalCount += 1 + (isExpanded ? verbs.length : 0);
    }
    // +1 for the custom verb input at the end of the list
    final customVerbIndex = totalCount;
    totalCount += 1;
    return Scrollbar(
      controller: _categoriesScrollController,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _categoriesScrollController,
        padding: const EdgeInsets.only(top: 6),
        itemCount: totalCount,
        itemBuilder: (context, flatIndex) {
          // Custom verb input — last item in the list
          if (flatIndex == customVerbIndex) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    height: 1,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Text(
                      'Custom Verb',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  TextField(
                    controller: _customVerbController,
                    cursorHeight: 14,
                    cursorColor: Colors.black87,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: '',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(3)),
                        borderSide: BorderSide(color: Colors.black87, width: 1),
                      ),
                    ),
                    onChanged: (value) {
                      widget.captionState
                          ?.updateCustomVerbFromPopup(value.trim());
                      if (value.trim().isNotEmpty) {
                        setState(() {
                          _pickedVerbCategory = null;
                          _pickedVerbIndex = null;
                        });
                      }
                    },
                  ),
                ],
              ),
            );
          }
          int offset = 0;
          for (int ci = 0; ci < cats.length; ci++) {
            final cat = cats[ci];
            final catNum = cat['number'] as int? ?? (ci + 1);
            final name = cat['name'] as String? ?? '';
            final verbs =
                (cat['verbs'] as List<dynamic>?)?.cast<String>() ?? [];
            final headerIndex = offset;
            offset += 1;
            if (flatIndex == headerIndex) {
              final isExpanded = _expandedCategoryIndex == ci;
              final isDragging = _dragFromCatIndex == ci;
              final isDragOver =
                  _dragToCatIndex == ci && _dragFromCatIndex != ci;
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  _catLongPressTimer?.cancel();
                  _catLongPressTimer =
                      Timer(const Duration(milliseconds: 500), () {
                    setState(() {
                      _dragFromCatIndex = ci;
                      _dragToCatIndex = ci;
                    });
                  });
                },
                onPointerMove: (e) {
                  if (_dragFromCatIndex != null) {
                    final target = _catIndexAtGlobalY(e.position.dy);
                    if (target != null && target != _dragToCatIndex) {
                      setState(() => _dragToCatIndex = target);
                    }
                  }
                },
                onPointerUp: (e) {
                  _catLongPressTimer?.cancel();
                  if (_dragFromCatIndex != null &&
                      _dragToCatIndex != null &&
                      _dragFromCatIndex != _dragToCatIndex) {
                    final state = widget.captionState;
                    if (state != null) {
                      try {
                        (state as dynamic).reorderCategories(
                            _dragFromCatIndex!, _dragToCatIndex!);
                      } catch (_) {}
                    }
                    setState(() {
                      _dragFromCatIndex = null;
                      _dragToCatIndex = null;
                    });
                  } else if (_dragFromCatIndex == null) {
                    setState(() {
                      if (_expandedCategoryIndex == ci) {
                        _expandedCategoryIndex = null;
                      } else {
                        _expandedCategoryIndex = ci;
                      }
                    });
                  } else {
                    setState(() {
                      _dragFromCatIndex = null;
                      _dragToCatIndex = null;
                    });
                  }
                },
                onPointerCancel: (_) {
                  _catLongPressTimer?.cancel();
                  setState(() {
                    _dragFromCatIndex = null;
                    _dragToCatIndex = null;
                  });
                },
                child: MouseRegion(
                  cursor: _dragFromCatIndex != null
                      ? SystemMouseCursors.grabbing
                      : SystemMouseCursors.grab,
                  child: Container(
                    key: _catKey(ci),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDragging
                          ? Colors.blue.shade100
                          : isDragOver
                              ? Colors.blue.shade50
                              : Colors.grey.shade100,
                      border: Border(
                        top: isDragOver
                            ? BorderSide(color: Colors.blue.shade400, width: 2)
                            : BorderSide(color: Colors.white, width: 1),
                        bottom:
                            BorderSide(color: Colors.grey.shade200, width: 0.5),
                      ),
                    ),
                    child: Opacity(
                      opacity: isDragging ? 0.5 : 1.0,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            child: Text(
                              '$catNum',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade800),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade800),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            isExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 12,
                            color: Colors.grey.shade600,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
            if (_expandedCategoryIndex == ci) {
              for (int vi = 0; vi < verbs.length; vi++) {
                if (flatIndex == offset) {
                  final verb = verbs[vi];
                  final verbNum = vi + 1;
                  if (verb.trim().isEmpty) {
                    return const SizedBox(height: 12);
                  }
                  final isLastUsed = _lastUsedVerbLabel == verb;
                  final dynamic state = widget.captionState;
                  final isFavorite = state != null &&
                      (state.isFavoriteVerbFromKeyboardFire(verb) == true);
                  final verbKey = '${catNum}_$verbNum';
                  final isHovered = _hoveredVerbKey == verbKey;
                  final isPicked = _pickedVerbCategory == catNum &&
                      _pickedVerbIndex == verbNum;
                  final isPinned = _pinnedVerbCategory == catNum &&
                      _pinnedVerbIndex == verbNum;
                  final isActive = isPicked || isPinned;
                  const hitVerbs = {
                    'Single',
                    'Double',
                    'Triple',
                    'Home Run',
                    'Sacrifice Fly',
                    'Bunt',
                    'Hit by Pitch'
                  };
                  const runningVerbs = {'Steals', 'Slides', 'Runs', 'Rounds'};
                  final isHitVerb = hitVerbs.contains(verb);
                  final isRunningVerb = runningVerbs.contains(verb);
                  final isHomeRun = verb == 'Home Run';
                  final showRbiMenu = isActive && isHitVerb;
                  final showBaseMenu = isActive && isRunningVerb;

                  final verbRow = MouseRegion(
                    onEnter: (_) => setState(() => _hoveredVerbKey = verbKey),
                    onExit: (_) => setState(() => _hoveredVerbKey = null),
                    child: GestureDetector(
                      onSecondaryTapDown: (TapDownDetails d) {
                        _showVerbContextMenu(
                            context, d.globalPosition, verb, isFavorite,
                            catNum: catNum,
                            verbNum: verbNum,
                            isPinned: isPinned);
                      },
                      child: InkWell(
                        onTapDown: (TapDownDetails d) {
                          _verbRowTapConsumedByCmd = false;
                          if (HardwareKeyboard.instance.isMetaPressed) {
                            _verbRowTapConsumedByCmd = true;
                            _onVerbTapped(catNum, verbNum, cmdHeld: true);
                          }
                        },
                        onTap: () {
                          if (_verbRowTapConsumedByCmd) {
                            _verbRowTapConsumedByCmd = false;
                            return;
                          }
                          if (!HardwareKeyboard.instance.isMetaPressed) {
                            _onVerbTapped(catNum, verbNum);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.only(
                              left: 20, right: 6, top: 4, bottom: 4),
                          decoration: BoxDecoration(
                            color: isPinned
                                ? const Color(0xFFFFF8E1)
                                : (isPicked
                                    ? const Color(0xFFDBEAFF)
                                    : (isHovered
                                        ? Colors.grey.shade200
                                        : null)),
                            border: isPinned
                                ? Border(
                                    left: const BorderSide(
                                        color: Color(0xFFF59E0B), width: 3),
                                    bottom: BorderSide(
                                        color: Colors.grey.shade100,
                                        width: 0.5),
                                  )
                                : (isPicked
                                    ? Border(
                                        left: const BorderSide(
                                            color: Color(0xFF4A90E2), width: 3),
                                        bottom: BorderSide(
                                            color: Colors.grey.shade100,
                                            width: 0.5),
                                      )
                                    : Border(
                                        bottom: BorderSide(
                                            color: Colors.grey.shade100,
                                            width: 0.5),
                                      )),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              SizedBox(
                                width: 24,
                                child: Text(
                                  '$verbNum',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isPinned
                                        ? const Color(0xFFB45309)
                                        : (isPicked
                                            ? const Color(0xFF0052CC)
                                            : Colors.grey.shade800),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        verb,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isPinned
                                              ? const Color(0xFFB45309)
                                              : (isPicked
                                                  ? const Color(0xFF0052CC)
                                                  : Colors.black87),
                                          fontWeight: (isPinned || isPicked)
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isPinned)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 4),
                                        child: Icon(Icons.push_pin,
                                            size: 11, color: Color(0xFFF59E0B)),
                                      ),
                                    if (isLastUsed && !isPinned)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 4),
                                        child: Text(
                                          '← Last used',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.red,
                                              fontWeight: FontWeight.w500),
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

                  if (!showRbiMenu && !showBaseMenu) return verbRow;

                  if (showBaseMenu) {
                    final currentBase =
                        (state as dynamic).currentSelectedBase as String?;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        verbRow,
                        _buildBaseSubMenu(state, verb, currentBase),
                      ],
                    );
                  }

                  // RBI / Home Run type sub-menu
                  final currentRbi = (state as dynamic).currentRbiCount as int?;
                  final currentHrType = isHomeRun
                      ? (state as dynamic).currentHomeRunType as String?
                      : null;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      verbRow,
                      if (isHomeRun)
                        _buildHomeRunTypeSubMenu(state, currentHrType)
                      else
                        _buildRbiSubMenu(state, verb, currentRbi),
                    ],
                  );
                }
                offset += 1;
              }
            }
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildRbiSubMenu(dynamic captionState, String verb, int? currentRbi) {
    final maxRbi =
        (verb == 'Sacrifice Fly' || verb == 'Bunt' || verb == 'Hit by Pitch')
            ? 1
            : 3;
    return Container(
      padding: const EdgeInsets.only(left: 36, right: 8, top: 2, bottom: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
          left: const BorderSide(color: Color(0xFF4A90E2), width: 3),
        ),
      ),
      child: Row(
        children: [
          Text('RBI:',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600)),
          const SizedBox(width: 6),
          ...List.generate(maxRbi, (i) {
            final rbi = i + 1;
            final isSelected = currentRbi == rbi;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(3),
                onTap: () {
                  try {
                    (captionState as dynamic)
                        .setRbiFromKeyboardFire(isSelected ? null : rbi);
                  } catch (_) {}
                  setState(() {});
                  _refreshCaptionPreviewLater();
                },
                child: Container(
                  width: 22,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF4A90E2) : Colors.white,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF4A90E2)
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    '$rbi',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.grey.shade800,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHomeRunTypeSubMenu(dynamic captionState, String? currentType) {
    const types = ['Solo', 'Two-Run', 'Three-Run', 'Grand Slam'];
    return Container(
      padding: const EdgeInsets.only(left: 36, right: 8, top: 2, bottom: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
          left: const BorderSide(color: Color(0xFF4A90E2), width: 3),
        ),
      ),
      child: Row(
        children: [
          Text('HR:',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600)),
          const SizedBox(width: 6),
          ...types.map((type) {
            final isSelected = currentType == type;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(3),
                onTap: () {
                  try {
                    (captionState as dynamic).setHomeRunTypeFromKeyboardFire(
                        isSelected ? null : type);
                  } catch (_) {}
                  setState(() {});
                  _refreshCaptionPreviewLater();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF4A90E2) : Colors.white,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF4A90E2)
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    type,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.grey.shade800,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBaseSubMenu(
      dynamic captionState, String verb, String? currentBase) {
    final bases = verb == 'Steals'
        ? const ['2nd', '3rd', 'Home', 'Tagged Out']
        : const ['1st', '2nd', '3rd', 'Home', 'Tagged Out'];
    final storedBase = (captionState as dynamic).baseBeforeTaggedOut as String?;
    final isTaggedOut = currentBase == 'Tagged Out';

    return Container(
      padding: const EdgeInsets.only(left: 36, right: 8, top: 2, bottom: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
          left: const BorderSide(color: Color(0xFF4A90E2), width: 3),
        ),
      ),
      child: Row(
        children: [
          Text('Base:',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600)),
          const SizedBox(width: 6),
          ...bases.map((base) {
            final isSelected = currentBase == base;
            // When Tagged Out is active, also highlight the stored original base
            final isStoredBase =
                isTaggedOut && base != 'Tagged Out' && storedBase == base;

            final Color bgColor;
            final Color borderColor;
            final Color textColor;
            if (isSelected) {
              bgColor = base == 'Tagged Out'
                  ? const Color(0xFFE53935)
                  : const Color(0xFF4A90E2);
              borderColor = bgColor;
              textColor = Colors.white;
            } else if (isStoredBase) {
              bgColor = const Color(0xFF4A90E2).withOpacity(0.15);
              borderColor = const Color(0xFF4A90E2);
              textColor = const Color(0xFF4A90E2);
            } else {
              bgColor = Colors.white;
              borderColor = Colors.grey.shade300;
              textColor = Colors.grey.shade800;
            }

            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(3),
                onTap: () {
                  try {
                    (captionState as dynamic).setBaseFromKeyboardFire(base);
                  } catch (_) {}
                  setState(() {});
                  _refreshCaptionPreviewLater();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: borderColor),
                  ),
                  child: Text(
                    base,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _showVerbContextMenu(
      BuildContext context, Offset position, String verb, bool isFavorite,
      {int? catNum, int? verbNum, bool isPinned = false}) {
    final state = widget.captionState;
    if (state == null) return;

    final menuItems = <PopupMenuItem<String>>[
      // Pin / Unpin
      if (catNum != null && verbNum != null)
        PopupMenuItem<String>(
          value: isPinned ? 'unpin' : 'pin',
          height: 32,
          child: Row(
            children: [
              Icon(
                isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 16,
                color:
                    isPinned ? const Color(0xFFF59E0B) : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                isPinned ? 'Unpin verb' : 'Pin verb (holds for every image)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
              ),
            ],
          ),
        ),
      PopupMenuItem<String>(
        value: 'favorite',
        height: 32,
        child: Row(
          children: [
            Icon(
              isFavorite ? Icons.star : Icons.star_border,
              size: 16,
              color: isFavorite ? Colors.amber : Colors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Text(
              isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
            ),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'edit',
        height: 32,
        child: Row(
          children: [
            Icon(Icons.edit, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(
              'Edit Verb',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
            ),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'delete',
        height: 32,
        child: Row(
          children: [
            Icon(Icons.delete_outline, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(
              'Delete verb',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
            ),
          ],
        ),
      ),
    ];

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: menuItems,
    ).then((value) async {
      if (value == 'pin' && catNum != null && verbNum != null) {
        _setPinnedVerb(catNum, verbNum);
      } else if (value == 'unpin') {
        _clearPinnedVerb();
      } else if (value == 'favorite') {
        await state.toggleFavoriteVerbFromKeyboardFire(verb);
        if (mounted) setState(() {});
      } else if (value == 'edit') {
        state.showEditVerbDialogForKeyboardFire(verb);
      } else if (value == 'delete') {
        await state.deleteVerbOverrideFromKeyboardFire(verb);
        if (mounted) setState(() {});
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Verb removed from list.')),
          );
        }
      }
    });
  }

  /// Verb list only (no border; caller wraps with bar inside same box).
  /// [barText] = current bar input; matching row gets grey, picked verb gets blue.
  Widget _buildVerbPanelContent({String? barText}) {
    final cats = _verbList;
    final selectedVerbs = _selectedCategoryIndex != null && cats.isNotEmpty
        ? ((cats[_selectedCategoryIndex!]['verbs'] as List<dynamic>?)
                ?.cast<String>() ??
            [])
        : <String>[];
    final selectedCatNum =
        _selectedCategoryIndex != null ? _selectedCategoryIndex! + 1 : null;

    // Parse bar: 2 digits = category + verb (0 = 10); 1 digit = verb in current category
    int? barVerbNum;
    if (barText != null && barText.isNotEmpty) {
      final t = barText.trim();
      if (t.length >= 2) {
        final barCat = int.tryParse(t[0]);
        final v = t[1] == '0' ? 10 : int.tryParse(t[1]);
        if (barCat == selectedCatNum && v != null && v >= 1) barVerbNum = v;
      } else {
        barVerbNum = t == '0' ? 10 : int.tryParse(t);
      }
    }

    return _selectedCategoryIndex == null
        ? Center(
            child: Text(
              'Select a category',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade400,
                  fontStyle: FontStyle.italic),
            ),
          )
        : Scrollbar(
            controller: _verbsScrollController,
            thumbVisibility: true,
            child: ListView.builder(
              controller: _verbsScrollController,
              padding: EdgeInsets.zero,
              itemCount: selectedVerbs.length,
              itemBuilder: (context, vi) {
                final verb = selectedVerbs[vi];
                final verbNum = vi + 1;
                if (verb.trim().isEmpty) {
                  return const SizedBox(height: 12);
                }
                final isPicked = _pickedVerbCategory == selectedCatNum &&
                    _pickedVerbIndex == verbNum;
                final isCurrent = barVerbNum != null && barVerbNum == verbNum;
                final bgColor = isPicked
                    ? const Color(0xFFDBEAFF)
                    : (isCurrent ? Colors.grey.shade200 : null);
                final isLastUsed = _lastUsedVerbLabel == verb;
                final dynamic state = widget.captionState;
                final isFavorite = state != null &&
                    (state.isFavoriteVerbFromKeyboardFire(verb) == true);
                return GestureDetector(
                  onSecondaryTapDown: (TapDownDetails d) {
                    _showVerbContextMenu(
                        context, d.globalPosition, verb, isFavorite);
                  },
                  child: InkWell(
                    onTapDown: (TapDownDetails d) {
                      _verbRowTapConsumedByCmd = false;
                      if (HardwareKeyboard.instance.isMetaPressed) {
                        _verbRowTapConsumedByCmd = true;
                        _onVerbTapped(selectedCatNum!, verbNum, cmdHeld: true);
                      }
                    },
                    onTap: () {
                      if (_verbRowTapConsumedByCmd) {
                        _verbRowTapConsumedByCmd = false;
                        return;
                      }
                      if (!HardwareKeyboard.instance.isMetaPressed) {
                        _onVerbTapped(selectedCatNum!, verbNum);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      decoration: BoxDecoration(
                        color: bgColor,
                        border: isPicked
                            ? Border(
                                left: const BorderSide(
                                    color: Color(0xFF4A90E2), width: 3),
                                bottom: BorderSide(
                                    color: Colors.grey.shade100, width: 0.5),
                              )
                            : Border(
                                bottom: BorderSide(
                                    color: Colors.grey.shade100, width: 0.5),
                              ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          SizedBox(
                            width: 24,
                            child: Text(
                              '$verbNum',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isPicked
                                    ? const Color(0xFF0052CC)
                                    : Colors.grey.shade800,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    verb,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isPicked
                                          ? const Color(0xFF0052CC)
                                          : Colors.black87,
                                      fontWeight: isPicked
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isLastUsed)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Text(
                                      '← Last used',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.red,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
  }

  Widget _btn({
    required Widget child,
    required VoidCallback? onTap,
    void Function(TapDownDetails)? onTapDown,
    Color? bg,
    double width = 60,
  }) {
    final enabled = onTap != null;
    final color = bg ?? (enabled ? Colors.grey.shade100 : Colors.grey.shade200);
    final borderColor = enabled ? Colors.grey.shade300 : Colors.grey.shade400;
    return SizedBox(
      width: width,
      height: 28,
      child: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: InkRipple.splashFactory,
          highlightColor: Colors.black.withOpacity(0.06),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTapDown: enabled ? onTapDown : null,
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.zero,
            splashColor: Colors.black.withOpacity(0.08),
            highlightColor: Colors.black.withOpacity(0.05),
            child: Ink(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: borderColor),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const Color _ftpButtonBlue = Color(0xFF0052CC);

  /// Very light grey, one step above white (for column bodies, caption, personality).
  static const Color _panelBackgroundLight = Color(0xFFFCFCFC);

  Widget _buildFtpButtonWithContextMenu() {
    return SizedBox(
      width: double.infinity,
      height: 28,
      child: GestureDetector(
        onSecondaryTapDown: widget.onFtpSettings != null
            ? (TapDownDetails details) {
                showMenu<String>(
                  context: context,
                  position: RelativeRect.fromLTRB(
                    details.globalPosition.dx,
                    details.globalPosition.dy,
                    details.globalPosition.dx + 1,
                    details.globalPosition.dy + 1,
                  ),
                  items: [
                    const PopupMenuItem<String>(
                      value: 'ftp_settings',
                      child: Row(
                        children: [
                          Icon(Icons.settings,
                              size: 18, color: Colors.black87),
                          SizedBox(width: 8),
                          Text('FTP Settings'),
                        ],
                      ),
                    ),
                  ],
                ).then((value) {
                  if (value == 'ftp_settings') widget.onFtpSettings?.call();
                });
              }
            : null,
        child: Theme(
          data: Theme.of(context).copyWith(
            splashFactory: InkRipple.splashFactory,
            highlightColor: Colors.white.withOpacity(0.15),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onFtp,
              borderRadius: BorderRadius.zero,
              splashColor: Colors.white.withOpacity(0.25),
              highlightColor: Colors.white.withOpacity(0.15),
              child: Ink(
                decoration: BoxDecoration(
                  color: _ftpButtonBlue,
                  borderRadius: BorderRadius.zero,
                  border: Border.all(color: _ftpButtonBlue),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_upload,
                          size: 11, color: Colors.white),
                      const SizedBox(width: 3),
                      Text(
                        widget.currentFtpProfile != null
                            ? 'FTP (${widget.currentFtpProfile})'
                            : 'FTP',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    final hasPrev = widget.currentIndex != null && widget.currentIndex! > 0;
    final hasNext = widget.currentIndex != null &&
        widget.totalImages != null &&
        widget.currentIndex! < widget.totalImages! - 1;

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          // ← Save Prev
          _btn(
            width: 72,
            onTap: hasPrev
                ? () async {
                    if (widget.onSaveIptc != null) widget.onSaveIptc!();
                    widget.onPreviousImage?.call();
                  }
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chevron_left,
                    size: 12, color: Colors.grey.shade700),
                const SizedBox(width: 2),
                Text('Save',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          // Save → Next
          _btn(
            width: 72,
            onTap: hasNext
                ? () async {
                    if (widget.onSaveIptc != null) widget.onSaveIptc!();
                    widget.onNextImage?.call();
                  }
                : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Save',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500)),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right,
                    size: 12, color: Colors.grey.shade700),
              ],
            ),
          ),
          // Paste
          _btn(
            width: 55,
            onTap: widget.onPaste,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.content_paste,
                    size: 12, color: Colors.grey.shade700),
                const SizedBox(width: 2),
                Text('Paste',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          // Paste Prev
          _btn(
            width: 90,
            onTap: widget.onPastePrevious,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 12, color: Colors.grey.shade700),
                const SizedBox(width: 2),
                Text('Paste Prev',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          // FTP Settings
          _btn(
            width: 100,
            onTap: widget.onFtpSettings,
            bg: const Color(0xFF4A90E2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.settings,
                    size: 12, color: Colors.white),
                const SizedBox(width: 4),
                Text('FTP Settings',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.white)),
              ],
            ),
          ),
          // Reset
          _btn(
            width: 60,
            onTapDown: (d) => _resetCaptionTapAnchor = d.globalPosition,
            onTap: _onResetPressed,
            bg: Colors.grey.shade200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.refresh,
                    size: 12, color: Colors.grey.shade700),
                const SizedBox(width: 2),
                Text('Reset Caption',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _getSelectedPeriod() {
    try {
      return (widget.captionState as dynamic).selectedPeriod as String?;
    } catch (_) {
      return null;
    }
  }

  String? _verbLabelForCategoryAndVerb(int cat1Based, int verb1Based) {
    final cats = _verbList;
    if (cat1Based < 1 || cat1Based > cats.length) return null;
    final verbs =
        (cats[cat1Based - 1]['verbs'] as List<dynamic>?)?.cast<String>() ?? [];
    if (verb1Based < 1 || verb1Based > verbs.length) return null;
    final v = verbs[verb1Based - 1].trim();
    return v.isEmpty ? null : v;
  }

  void _showPinnedResetConfirmNear(Offset anchor, String verbLabel) {
    final media = MediaQuery.of(context);
    final padding = media.padding;
    final size = media.size;
    const dialogW = 280.0;
    const dialogH = 88.0;
    var left = anchor.dx - dialogW / 2;
    var top = anchor.dy + 8;
    final maxRight = size.width - padding.right - 8;
    final minLeft = padding.left + 8;
    if (left < minLeft) left = minLeft;
    if (left + dialogW > maxRight) left = maxRight - dialogW;
    if (top + dialogH > size.height - padding.bottom - 8) {
      top = anchor.dy - dialogH - 8;
    }
    if (top < padding.top + 8) top = padding.top + 8;

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel:
          MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (ctx, _, __) {
        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(ctx).pop(),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                width: dialogW,
                child: Material(
                  color: Colors.grey.shade50,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            GestureDetector(
                              onTap: () => Navigator.of(ctx).pop(),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: GestureDetector(
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  _performCaptionReset();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1976D2),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    'Unpin "$verbLabel"',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onResetPressed() {
    final anchor = _resetCaptionTapAnchor;
    _resetCaptionTapAnchor = null;

    final pinned =
        _pinnedVerbCategory != null && _pinnedVerbIndex != null;
    if (pinned) {
      final verbLabel = _verbLabelForCategoryAndVerb(
            _pinnedVerbCategory!, _pinnedVerbIndex!,
          ) ??
          'verb';
      final a = anchor ??
          Offset(
            MediaQuery.of(context).size.width / 2,
            MediaQuery.of(context).size.height / 3,
          );
      _showPinnedResetConfirmNear(a, verbLabel);
      return;
    }
    _performCaptionReset();
  }

  void _performCaptionReset() {
    // Reset all caption/verb/player state via the caption state object
    try {
      (widget.captionState as dynamic)?.resetCaption();
    } catch (_) {}

    setState(() {
      _firebarStep = 0;
      _firebarHv = null;
      _firebarTeam1Value = '';
      _firebarTeam2Value = '';
      _firebarCategoryValue = '';
      _firebarVerbValue = '';
      // Clear verb highlight and pin
      _pickedVerbCategory = null;
      _pickedVerbIndex = null;
      _lastUsedVerbLabel = null;
      _pinnedVerbCategory = null;
      _pinnedVerbIndex = null;
    });
    _firebarController.clear();
    _customVerbController.clear();
    widget.captionState?.updateCustomVerbFromPopup('');
    widget.onReset?.call();
  }

  void _onPeriodSelect(String period) {
    final state = widget.captionState;
    if (state == null) return;
    try {
      final current = _getSelectedPeriod();
      final next = current == period ? null : period;
      (state as dynamic).updatePeriodFromPopup(next);
      setState(() {});
    } catch (_) {}
  }

  int? _getSelectedRbiInning() {
    try {
      return (widget.captionState as dynamic).selectedRbiInning as int?;
    } catch (_) {
      return null;
    }
  }

  void _onInningSelect(int? inning) {
    final state = widget.captionState;
    if (state == null) return;
    try {
      (state as dynamic).updateInningFromPopup(inning);
      setState(() {});
    } catch (_) {}
  }

  Widget _buildPeriodPicker() {
    final sport = (() {
      try {
        return (widget.captionState as dynamic).currentSportName as String? ??
            'hockey';
      } catch (_) {
        return 'hockey';
      }
    })();
    final isBasketball = sport == 'basketball';
    final isBaseball = sport == 'baseball';
    final periodLabels = isBasketball
        ? (_showPlayoffOvertimes
            ? ['Pre-Game', '2OT', '3OT', '4OT', '5OT', 'Post Game']
            : ['Pre-Game', 'Q1', 'Q2', 'Q3', 'Q4', 'OT', '1H', '2H'])
        : (_showPlayoffOvertimes
            ? ['Pre-Game', '1OT', '2OT', '3OT', '4OT', '5OT']
            : ['Pre-Game', '1', '2', '3', 'OT', 'SO']);
    final selected = _getSelectedPeriod();

    const Set<String> wideLabels = {'Pre-Game', 'Post Game'};
    /// Wide enough for "Post Game" / "Pre-Game" on one line (both use the same width).
    const double widePeriodButtonWidth = 76;

    Widget periodButton(String label) {
      final isSelected = selected == label;
      final isWide = wideLabels.contains(label);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: SizedBox(
          width: isWide ? widePeriodButtonWidth : 24,
          height: 24,
          child: OutlinedButton(
            onPressed: () => _onPeriodSelect(label),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(
                color: isSelected ? Colors.blue.shade500 : Colors.grey.shade400,
              ),
              backgroundColor: isSelected ? Colors.blue.shade50 : Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color:
                      isSelected ? Colors.blue.shade700 : Colors.grey.shade700,
                ),
              ),
            ),
          ),
        ),
      );
    }

    const double baseballInningCellW = 26.0;

    Widget inningDigitButton(int inningNum) {
      final sel = _getSelectedRbiInning();
      final isSelected = sel == inningNum;
      final label = '$inningNum';
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: SizedBox(
          width: baseballInningCellW,
          height: 24,
          child: OutlinedButton(
            onPressed: () => _onInningSelect(isSelected ? null : inningNum),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(
                color: isSelected ? Colors.blue.shade500 : Colors.grey.shade400,
              ),
              backgroundColor: isSelected ? Colors.blue.shade50 : Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? Colors.blue.shade700 : Colors.grey.shade700,
              ),
            ),
          ),
        ),
      );
    }

    Widget baseballPageButton({
      required IconData icon,
      required bool enabled,
      required VoidCallback? onPressed,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: SizedBox(
          width: baseballInningCellW,
          height: 24,
          child: OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(
                color: enabled ? Colors.grey.shade400 : Colors.grey.shade300,
              ),
              backgroundColor: enabled ? Colors.white : Colors.grey.shade100,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: Icon(
              icon,
              size: 12,
              color: enabled ? Colors.grey.shade700 : Colors.grey.shade400,
            ),
          ),
        ),
      );
    }

    final String headerLabel =
        isBasketball ? 'Quarter' : (isBaseball ? 'Inning' : 'Period');

    if (isBaseball) {
      final page = _baseballInningPage.clamp(0, 2);
      final startInning = page * 9 + 1;
      final inningNums =
          List<int>.generate(9, (i) => startInning + i); // 1–9, 10–18, or 19–27
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          decoration: BoxDecoration(
            color: _panelBackgroundLight,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: Colors.grey.shade300, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                headerLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      periodButton('Pre-Game'),
                      ...inningNums.map(inningDigitButton),
                      baseballPageButton(
                        icon: Icons.remove,
                        enabled: page > 0,
                        onPressed: page > 0
                            ? () => setState(() {
                                  _baseballInningPage =
                                      (_baseballInningPage - 1).clamp(0, 2);
                                })
                            : null,
                      ),
                      baseballPageButton(
                        icon: Icons.add,
                        enabled: page < 2,
                        onPressed: page < 2
                            ? () => setState(() {
                                  _baseballInningPage =
                                      (_baseballInningPage + 1).clamp(0, 2);
                                })
                            : null,
                      ),
                      periodButton('Post Game'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: _panelBackgroundLight,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: Colors.grey.shade300, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              headerLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ...periodLabels.map(periodButton),
                    const SizedBox(width: 3),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() =>
                              _showPlayoffOvertimes = !_showPlayoffOvertimes);
                        },
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: BorderSide(
                            color: _showPlayoffOvertimes
                                ? Colors.blue.shade500
                                : Colors.grey.shade400,
                          ),
                          backgroundColor: _showPlayoffOvertimes
                              ? Colors.blue.shade50
                              : Colors.white,
                          shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero),
                        ),
                        child: Icon(
                          _showPlayoffOvertimes ? Icons.remove : Icons.add,
                          size: 12,
                          color: _showPlayoffOvertimes
                              ? Colors.blue.shade700
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    periodButton('Post Game'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Which of the 4 columns (0=Home, 1=Away, 2=Category, 3=Verb) should have red outline for firebar step.
  /// Step 0 (H/V) = no highlight; step 1 = team first picked; step 2 = other team; step 3 = category; step 4 = verb.
  bool _isFirebarColumnActive(int columnIndex) {
    switch (_firebarStep) {
      case 0:
        return false; // H/V: don't highlight either column
      case 1:
        return _firebarHv == 'H'
            ? columnIndex == 0
            : columnIndex == 1; // team 1
      case 2:
        return _firebarHv == 'H'
            ? columnIndex == 1
            : columnIndex == 0; // team 2
      case 3:
        return columnIndex == 2; // category
      case 4:
        return columnIndex == 3; // verb
      default:
        return false;
    }
  }

  Widget _buildNewFirebar() {
    final catCount = _verbList.isEmpty ? 6 : _verbList.length;
    final placeholders = [
      '(H)ome or (V)isitor',
      'Player #s (e.g. 7 23)',
      'Other team #s or Enter for none',
      'Category 1–$catCount',
      'Verb # or 2 digits (e.g. 34)',
      '(S)ave (C)opy (F)TP',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 3),
            child: Text(
              'Firebar',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _firebarController,
                  focusNode: _firebarFocus,
                  cursorHeight: 15,
                  cursorColor: Colors.black87,
                  onChanged: (value) {
                    if (_firebarStep == 0 && value.isNotEmpty) {
                      final hv = value.trim().toUpperCase();
                      if (hv == 'H' || hv == 'V') _applyFirebarHv(hv);
                      return;
                    }
                    if (_firebarStep == 3 && value.isNotEmpty) {
                      final n = int.tryParse(value.trim());
                      final cats = _verbList;
                      if (n != null &&
                          n >= 1 &&
                          cats.isNotEmpty &&
                          n <= cats.length) {
                        _firebarApplyCategoryInput(value);
                      }
                      return;
                    }
                    if (_firebarStep == 4 && value.isNotEmpty) {
                      final t = value.trim();
                      if (t.length == 1) {
                        final v = t == '0' ? 10 : int.tryParse(t);
                        if (v != null && v >= 1) _firebarApplyVerbInput(t);
                      } else if (t.length >= 2) {
                        final c = int.tryParse(t[0]);
                        final v = t[1] == '0' ? 10 : int.tryParse(t[1]);
                        if (c != null && c >= 1 && v != null && v >= 1) {
                          _firebarApplyVerbInput(t);
                        }
                      }
                      return;
                    }
                    if (_firebarStep == 5 && value.isNotEmpty) {
                      final letter = value.trim().toUpperCase();
                      if (letter == 'S' || letter == 'C' || letter == 'F') {
                        _firebarApplyActionInput(letter);
                      }
                    }
                  },
                  onSubmitted: (_) => _onFirebarSubmit(),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '',
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: BorderSide(color: Colors.black87, width: 1),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Helper: ${placeholders[_firebarStep]}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _firebarController,
                        builder: (context, value, _) {
                          if (_firebarStep != 1 && _firebarStep != 2)
                            return const SizedBox.shrink();
                          final roster = _firebarStep == 1
                              ? (_firebarHv == 'H'
                                  ? widget.homeRoster
                                  : widget.awayRoster)
                              : (_firebarHv == 'H'
                                  ? widget.awayRoster
                                  : widget.homeRoster);
                          final names =
                              _playerNamesForNumbers(value.text, roster);
                          if (names.isEmpty) return const SizedBox.shrink();
                          return Text(
                            names,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final homeName = widget.homeTeamName ?? 'Home';
    final awayName = widget.awayTeamName ?? 'Away';

    VoidCallback? onPrimary;
    String primaryLabel = 'Next';

    if (_step == 0) {
      onPrimary = _onStep1Submit;
    } else if (_step == 1) {
      onPrimary = _onStep2Submit;
      primaryLabel = 'Next';
    } else {
      if (!_waitingForVerb) {
        onPrimary = _done;
        primaryLabel = 'Done';
      } else {
        onPrimary = null;
      }
    }

    final content = Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 150,
          child: _buildKeyboardFireCaptionStrip(),
        ),
        if (!widget.showDialogActions) _buildPeriodPicker(),
        if (!widget.showDialogActions && _showFirebar) _buildNewFirebar(),
        // Always show roster + verb columns so layout isn't blank when roster load fails
        const SizedBox(height: 4),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 1: Home roster (title, then box: number bar + list) ───────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(4, 2, 4, 1),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.zero,
                        border: Border(
                          left:
                              BorderSide(color: Colors.grey.shade300, width: 1),
                          top:
                              BorderSide(color: Colors.grey.shade300, width: 1),
                          right:
                              BorderSide(color: Colors.grey.shade300, width: 1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        homeName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: _panelBackgroundLight,
                          borderRadius: BorderRadius.zero,
                          border: Border.all(
                            color: _isFirebarColumnActive(0)
                                ? Colors.red
                                : Colors.grey.shade300,
                            width: _isFirebarColumnActive(0) ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildColumnBar(
                                controller: _homeBarController,
                                focusNode: _homeBarFocus,
                                onSubmitted: _onHomeBarSubmit,
                                rosterForGhostNames: widget.homeRoster,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 1,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: _buildPlayerViewModeToggle(),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: _buildPlayerNamesKeywordsToggleKb(),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: _useSquarePlayerView
                                    ? Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 6),
                                        child: _buildRosterSquareGrid(
                                            widget.homeRoster, true),
                                      )
                                    : ValueListenableBuilder<TextEditingValue>(
                                        valueListenable: _homeBarController,
                                        builder: (_, value, __) =>
                                            _buildRosterColumnContent(
                                                widget.homeRoster, true,
                                                barText: value.text),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // ── 2: Categories + verbs (one bar: 2 digits = cat + verb) ───
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(4, 2, 4, 1),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.zero,
                        border: Border(
                          left:
                              BorderSide(color: Colors.grey.shade300, width: 1),
                          top:
                              BorderSide(color: Colors.grey.shade300, width: 1),
                          right:
                              BorderSide(color: Colors.grey.shade300, width: 1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        'Verbs',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: _panelBackgroundLight,
                          borderRadius: BorderRadius.zero,
                          border: Border.all(
                            color: _isFirebarColumnActive(2)
                                ? Colors.red
                                : Colors.grey.shade300,
                            width: _isFirebarColumnActive(2) ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildColumnBar(
                                controller: _categoryBarController,
                                focusNode: _categoryBarFocus,
                                onSubmitted: () {},
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(2),
                                ],
                                onChanged: (v) {
                                  if (v.length >= 2) _onVerbBarInput(v);
                                },
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: _buildApplyKeywordsToggleKb(),
                                  ),
                                ],
                              ),
                              Expanded(
                                child: ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _categoryBarController,
                                  builder: (_, value, __) =>
                                      _buildCategoriesWithVerbsContent(
                                          barText: value.text),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // ── 3: Away roster (title, then box: number bar + list) ───────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(4, 2, 4, 1),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.zero,
                        border: Border(
                          left:
                              BorderSide(color: Colors.grey.shade300, width: 1),
                          top:
                              BorderSide(color: Colors.grey.shade300, width: 1),
                          right:
                              BorderSide(color: Colors.grey.shade300, width: 1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        awayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: _panelBackgroundLight,
                          borderRadius: BorderRadius.zero,
                          border: Border.all(
                            color: _isFirebarColumnActive(1)
                                ? Colors.red
                                : Colors.grey.shade300,
                            width: _isFirebarColumnActive(1) ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildColumnBar(
                                controller: _awayBarController,
                                focusNode: _awayBarFocus,
                                onSubmitted: _onAwayBarSubmit,
                                rosterForGhostNames: widget.awayRoster,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 1,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: _buildPlayerViewModeToggle(),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: _buildPlayerNamesKeywordsToggleKb(),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: _useSquarePlayerView
                                    ? Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 6),
                                        child: _buildRosterSquareGrid(
                                            widget.awayRoster, false),
                                      )
                                    : ValueListenableBuilder<TextEditingValue>(
                                        valueListenable: _awayBarController,
                                        builder: (_, value, __) =>
                                            _buildRosterColumnContent(
                                                widget.awayRoster, false,
                                                barText: value.text),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // ── 4: Actions (Save Prev/Next, Paste, Copy, etc.) ─────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.zero,
                        border: Border(
                          left:
                              BorderSide(color: Colors.grey.shade300, width: 1),
                          top:
                              BorderSide(color: Colors.grey.shade300, width: 1),
                          right:
                              BorderSide(color: Colors.grey.shade300, width: 1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        'Actions',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(6, 4, 6, 5),
                        decoration: BoxDecoration(
                          color: _panelBackgroundLight,
                          borderRadius: BorderRadius.zero,
                          border: Border.all(
                            color: Colors.grey.shade300,
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            key: _verbColumnKey,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _btn(
                                      width: double.infinity,
                                      onTap: (widget.currentIndex != null &&
                                              widget.currentIndex! > 0)
                                          ? () async {
                                              if (widget.onSaveIptc != null)
                                                widget.onSaveIptc!();
                                              widget.onPreviousImage?.call();
                                            }
                                          : null,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.chevron_left,
                                              size: 12,
                                              color: Colors.grey.shade700),
                                          const SizedBox(width: 2),
                                          Text('Save',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade700,
                                                  fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: _btn(
                                      width: double.infinity,
                                      onTap: (widget.currentIndex != null &&
                                              widget.totalImages != null &&
                                              widget.currentIndex! <
                                                  widget.totalImages! - 1)
                                          ? () async {
                                              if (widget.onSaveIptc != null)
                                                widget.onSaveIptc!();
                                              widget.onNextImage?.call();
                                            }
                                          : null,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text('Save',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade700,
                                                  fontWeight: FontWeight.w500)),
                                          const SizedBox(width: 2),
                                          Icon(Icons.chevron_right,
                                              size: 12,
                                              color: Colors.grey.shade700),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  if (widget.onCopy != null)
                                    Expanded(
                                      child: _btn(
                                        width: double.infinity,
                                        onTap: widget.onCopy,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.copy,
                                                size: 12,
                                                color: Colors.grey.shade700),
                                            const SizedBox(width: 2),
                                            Text('Copy',
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey.shade700,
                                                    fontWeight:
                                                        FontWeight.w500)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (widget.onCopy != null)
                                    const SizedBox(width: 4),
                                  Expanded(
                                    child: _btn(
                                      width: double.infinity,
                                      onTap: widget.onPaste,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.content_paste,
                                              size: 12,
                                              color: Colors.grey.shade700),
                                          const SizedBox(width: 2),
                                          Text('Paste',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade700,
                                                  fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              _btn(
                                width: double.infinity,
                                onTap: widget.onPastePrevious,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.history,
                                        size: 12, color: Colors.grey.shade700),
                                    const SizedBox(width: 2),
                                    Text('Paste Prev',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade700,
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 3),
                              _btn(
                                width: double.infinity,
                                onTapDown: (d) =>
                                    _resetCaptionTapAnchor = d.globalPosition,
                                onTap: _onResetPressed,
                                bg: Colors.grey.shade200,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.refresh,
                                        size: 12, color: Colors.grey.shade700),
                                    const SizedBox(width: 2),
                                    Text('Reset Caption',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade700,
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                              if (!widget.ftpDisabled &&
                                  widget.onFtp != null) ...[
                                const SizedBox(height: 3),
                                _buildFtpButtonWithContextMenu(),
                              ],
                              _buildKeywordShortcutChipsKb(),
                              _buildKeyboardShortcutsHelpSection(),
                              const SizedBox(height: 2),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (widget.showDialogActions) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Cancel',
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade700)),
              ),
              if (onPrimary != null) ...[
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    if (_step == 0)
                      _onStep1Submit();
                    else if (_step == 1)
                      _onStep2Submit();
                    else if (_step == 2) _done();
                  },
                  child:
                      Text(primaryLabel, style: const TextStyle(fontSize: 13)),
                ),
              ],
            ],
          ),
        ],
      ],
    );

    final container = Container(
      constraints:
          widget.showDialogActions ? const BoxConstraints(maxWidth: 780) : null,
      padding: widget.showDialogActions
          ? const EdgeInsets.all(16)
          : const EdgeInsets.fromLTRB(10, 3, 10, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: widget.showDialogActions
            ? Border.all(color: Colors.grey.shade400)
            : null,
      ),
      child: Shortcuts.manager(
        manager: _FirebarShortcutManager(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.keyH): _FirebarHIntent(),
              SingleActivator(LogicalKeyboardKey.keyV): _FirebarVIntent(),
            }),
        child: Actions(
          actions: <Type, Action<Intent>>{
            _FirebarHIntent: CallbackAction<_FirebarHIntent>(
              onInvoke: (_) {
                if (_firebarStep == 0) _applyFirebarHv('H');
                return null;
              },
            ),
            _FirebarVIntent: CallbackAction<_FirebarVIntent>(
              onInvoke: (_) {
                if (_firebarStep == 0) _applyFirebarHv('V');
                return null;
              },
            ),
          },
          child: content,
        ),
      ),
    );

    if (widget.showDialogActions) {
      return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: Colors.grey.shade400),
        ),
        backgroundColor: Colors.white,
        child: container,
      );
    }
    return container;
  }
}

/// Modal dialog version of [KeyboardFirePanel].
class KeyboardFireDialog extends StatelessWidget {
  final List<Player> homeRoster;
  final List<Player> awayRoster;
  final String? homeTeamName;
  final String? awayTeamName;
  final dynamic captionState;

  const KeyboardFireDialog({
    super.key,
    required this.homeRoster,
    required this.awayRoster,
    this.homeTeamName,
    this.awayTeamName,
    required this.captionState,
  });

  @override
  Widget build(BuildContext context) {
    return KeyboardFirePanel(
      homeRoster: homeRoster,
      awayRoster: awayRoster,
      homeTeamName: homeTeamName,
      awayTeamName: awayTeamName,
      captionState: captionState,
      showDialogActions: true,
      onDone: () => Navigator.of(context).pop(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Keyword shortcut editor dialog (add / edit)
// ─────────────────────────────────────────────────────────────────────────────

class _KeywordShortcutEditorDialog extends StatefulWidget {
  final String initialLabel;
  final String initialKeywords;
  final bool isEdit;
  final void Function(String label, List<String> keywords) onSave;

  const _KeywordShortcutEditorDialog({
    required this.initialLabel,
    required this.initialKeywords,
    required this.isEdit,
    required this.onSave,
  });

  @override
  State<_KeywordShortcutEditorDialog> createState() =>
      _KeywordShortcutEditorDialogState();
}

class _KeywordShortcutEditorDialogState
    extends State<_KeywordShortcutEditorDialog> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _keywordsCtrl;
  final FocusNode _labelFocus = FocusNode();
  final FocusNode _keywordsFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.initialLabel);
    _keywordsCtrl = TextEditingController(text: widget.initialKeywords);
    _labelCtrl.addListener(() => setState(() {}));
    _keywordsCtrl.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _labelFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _keywordsCtrl.dispose();
    _labelFocus.dispose();
    _keywordsFocus.dispose();
    super.dispose();
  }

  List<String> get _parsedKeywords => _keywordsCtrl.text
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  bool get _canSave => _labelCtrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final parsed = _parsedKeywords;
    final label = _labelCtrl.text.trim();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      backgroundColor: Colors.grey.shade50,
      child: Container(
        width: 360,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header bar
            Container(
              padding: const EdgeInsets.fromLTRB(8, 4, 6, 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade300, width: 1),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.07),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.label_outline,
                      size: 11, color: Colors.black54),
                  const SizedBox(width: 4),
                  Text(
                    widget.isEdit ? 'Edit Keyword Shortcut' : 'Add Keyword Shortcut',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.close,
                        size: 13, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Label field
                  Text(
                    'Chip label',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _inputField(_labelCtrl,
                      hint: 'e.g. c, TPX, sport',
                      focusNode: _labelFocus),

                  const SizedBox(height: 8),

                  // Keywords field
                  Text(
                    'Keywords (comma-separated)',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _inputField(_keywordsCtrl,
                      hint: 'e.g. capture, caught, catching',
                      focusNode: _keywordsFocus,
                      maxLines: 2),

                  const SizedBox(height: 8),

                  // Preview
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCFCFC),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PREVIEW',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Chip preview
                            if (label.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  border: Border.all(
                                      color: Colors.grey.shade400),
                                  borderRadius: BorderRadius.zero,
                                ),
                                child: Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.normal,
                                    height: 1.0,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            if (label.isNotEmpty)
                              const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                parsed.isNotEmpty
                                    ? '→ ${parsed.join(', ')}'
                                    : label.isEmpty
                                        ? 'Enter a label above'
                                        : 'No keywords — enter comma-separated keywords',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: parsed.isNotEmpty
                                      ? Colors.black87
                                      : Colors.grey.shade400,
                                  fontStyle: parsed.isEmpty
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _canSave
                            ? () {
                                widget.onSave(
                                  _labelCtrl.text.trim(),
                                  _parsedKeywords,
                                );
                                Navigator.of(context).pop();
                              }
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _canSave
                                ? const Color(0xFF1976D2)
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            widget.isEdit ? 'Save' : 'Add',
                            style: TextStyle(
                              fontSize: 10,
                              color: _canSave
                                  ? Colors.white
                                  : Colors.grey.shade500,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputField(
    TextEditingController ctrl, {
    String hint = '',
    FocusNode? focusNode,
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      focusNode: focusNode,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 11),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 11),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(3)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: BorderSide(color: Colors.grey.shade400),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide:
              const BorderSide(color: Color(0xFF1976D2), width: 1.5),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}
