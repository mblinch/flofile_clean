import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/mlb_api_service.dart';

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
      if (w is TextField || w is TextFormField || w.runtimeType.toString() == 'EditableText') {
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
  String? _lastUsedVerbLabel; // verb label to show "(last used)" in red when image changes

  // Pinned verb: Cmd+click to pin; auto-applies to every subsequent image
  int? _pinnedVerbCategory;
  int? _pinnedVerbIndex;

  bool _showPlayoffOvertimes = false;

  /// When true, show players as number-only squares (classic style) in Home/Away columns.
  bool _useSquarePlayerView = false;

  /// Index of the one expanded category (verbs visible). Null = none expanded.
  int? _expandedCategoryIndex;

  /// Hover highlight: "home_12" / "away_5" for roster; "catNum_verbNum" for verbs.
  String? _hoveredRosterKey;
  String? _hoveredVerbKey;

  // New single firebar under periods: one bar, steps H/V → team1 → team2 → category → verb
  static const bool _showFirebar = false; // set true to show firebar (top bars preferred for now)
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
    widget.captionState?.selectVerbByCategoryAndIndexFromKeyboardFire(
        selectedCatNum, verbNum);
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
    widget.captionState?.selectVerbByCategoryAndIndexFromKeyboardFire(
        catNum, verbNum);
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
    // Defer state changes to avoid setState() during build (CaptionFieldsWidget).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.captionState?.clearPlayersForKeyboardFire();
      if (mounted) _homeBarFocus.requestFocus();
    });
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
        final verbList = (cats[cat - 1]['verbs'] as List<dynamic>?)?.cast<String>();
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
        widget.captionState?.setPendingPinnedVerb(
            _pinnedVerbCategory!, _pinnedVerbIndex!);
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
    _inputController.dispose();
    _inputFocus.dispose();
    _firebarController.dispose();
    _firebarFocus.dispose();
    _homeBarController.dispose();
    _awayBarController.dispose();
    _categoryBarController.dispose();
    _verbBarController.dispose();
    _customVerbController.dispose();
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
        final p = roster.firstWhere(
            (p) => (p.jerseyNumber ?? '').trim() == numStr.trim());
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
      _awaySummary = numbers.isEmpty ? 'None' : numbers.map((n) => '#$n').join(', ');
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
      _awaySummary = numbers.isEmpty ? 'None' : numbers.map((n) => '#$n').join(', ');
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
    int catNum = _selectedCategoryIndex != null ? _selectedCategoryIndex! + 1 : 1;
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
    widget.captionState?.selectVerbByCategoryAndIndexFromKeyboardFire(catNum, verbNum);
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
          _firebarTeam1Value = numbers.isEmpty ? '—' : numbers.map((n) => '#$n').join(' ');
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
          _firebarTeam2Value = numbers.isEmpty ? '—' : numbers.map((n) => '#$n').join(' ');
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
        ctrl = (widget.captionState as dynamic).captionTextController as TextEditingController?;
      } catch (_) {}
      if (ctrl == null) {
        return TextField(
          maxLines: 4,
          minLines: 4,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Caption will appear here as you add players and a verb.',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.all(4),
            filled: true,
            fillColor: _panelBackgroundLight,
          ),
        );
      }
      return TextField(
        controller: ctrl,
        maxLines: 4,
        minLines: 4,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Caption will appear here as you add players and a verb.',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.all(4),
          filled: true,
          fillColor: _panelBackgroundLight,
        ),
      );
    });
  }


  List<Widget> _buildRosterRows(List<Player> roster, bool isHomeTeam, {String? barText}) {
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
          final isCurrent = jersey.isNotEmpty && currentNumbers.any((n) => n.trim() == jersey.trim());
          final rosterKey = jersey.isNotEmpty ? '${isHomeTeam}_$jersey' : null;
          final isHovered = rosterKey != null && _hoveredRosterKey == rosterKey;
          final bgColor = isPicked
              ? const Color(0xFFDBEAFF)
              : (isCurrent ? Colors.grey.shade200 : (isHovered ? Colors.grey.shade200 : null));
          return MouseRegion(
            onEnter: rosterKey != null ? (_) => setState(() => _hoveredRosterKey = rosterKey) : null,
            onExit: rosterKey != null ? (_) => setState(() => _hoveredRosterKey = null) : null,
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                    width: 28,
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
                ],
              ),
            ),
          ),
          );
        }).toList();
  }

  /// Square-style (number-only) grid for Keyboard Fire roster column.
  Widget _buildRosterSquareGrid(List<Player> roster, bool isHomeTeam) {
    if (roster.isEmpty) {
      return Center(
        child: Text('No players', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      );
    }
    final selectedNames = _getSelectedPlayerNames(isHomeTeam);
    final sorted = List<Player>.from(roster)
      ..sort((a, b) {
        final an = int.tryParse(a.jerseyNumber ?? '') ?? 999;
        final bn = int.tryParse(b.jerseyNumber ?? '') ?? 999;
        return an.compareTo(bn);
      });
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1.0,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final player = sorted[index];
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
            decoration: BoxDecoration(
              color: isPicked ? const Color(0xFFDBEAFF) : Colors.white,
              border: Border.all(
                color: isPicked ? const Color(0xFF4A90E2) : Colors.grey.shade300,
                width: isPicked ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Center(
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
                  const SizedBox(height: 1),
                  Text(
                    lastName,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w500,
                      color: isPicked ? const Color(0xFF0052CC) : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRosterSection(String teamLabel, List<Player> roster, {required bool isHomeTeam}) {
    if (roster.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
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

  Widget _buildColumnBar({
    required TextEditingController controller,
    required FocusNode focusNode,
    required void Function() onSubmitted,
    List<TextInputFormatter>? inputFormatters,
    void Function(String)? onChanged,
    List<Player>? rosterForGhostNames,
  }) {
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: inputFormatters,
      onSubmitted: (_) => onSubmitted(),
      onChanged: onChanged,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: field,
    );
  }

  Widget _buildRosterColumn(String teamLabel, List<Player> roster, {required bool isHomeTeam}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: _buildRosterSection(teamLabel, roster, isHomeTeam: isHomeTeam),
      ),
    );
  }

  /// Roster list only (no border; caller wraps with bar inside same box).
  /// [barText] is the current bar input; matching rows get grey, committed get blue.
  Widget _buildRosterColumnContent(List<Player> roster, bool isHomeTeam, {String? barText}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
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
  /// [barText] = current bar input; matching row gets grey, selected category gets blue.
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
          final bgColor = isSelected
              ? Colors.blue.shade50
              : (isCurrent ? Colors.grey.shade200 : (isFavs ? Colors.amber.shade50 : Colors.transparent));
          return InkWell(
            onTap: () => setState(() => _selectedCategoryIndex = i),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: bgColor,
                border: Border(
                  bottom:
                      BorderSide(color: Colors.grey.shade200, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 16,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (isSelected || isCurrent)
                          ? Colors.grey.shade300
                          : (isFavs
                              ? Colors.amber.shade200
                              : Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      '$catNum',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? Colors.grey.shade800
                            : Colors.grey.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.grey.shade800
                            : Colors.grey.shade800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 14,
                    color:
                        isSelected ? Colors.grey.shade700 : Colors.grey.shade400,
                  ),
                ],
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
      thumbVisibility: true,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: totalCount,
        itemBuilder: (context, flatIndex) {
          // Custom verb input — last item in the list
          if (flatIndex == customVerbIndex) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
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
                    style: const TextStyle(fontSize: 11),
                    decoration: InputDecoration(
                      hintText: '',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide:
                            BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide:
                            BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide:
                            BorderSide(color: Colors.grey.shade500),
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
            final isFavs = name == 'Favorites';
            final verbs = (cat['verbs'] as List<dynamic>?)?.cast<String>() ?? [];
            final headerIndex = offset;
            offset += 1;
            if (flatIndex == headerIndex) {
              final isExpanded = _expandedCategoryIndex == ci;
              return InkWell(
                onTap: () {
                  setState(() {
                    if (_expandedCategoryIndex == ci) {
                      _expandedCategoryIndex = null;
                    } else {
                      _expandedCategoryIndex = ci;
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    border: Border(
                      top: BorderSide(color: Colors.white, width: 1),
                      bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 18,
                        height: 16,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          '$catNum',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey.shade800),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                    ],
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
                  return const SizedBox(height: 16);
                }
                final isLastUsed = _lastUsedVerbLabel == verb;
                final dynamic state = widget.captionState;
                final isFavorite = state != null && (state.isFavoriteVerbFromKeyboardFire(verb) == true);
                final verbKey = '${catNum}_$verbNum';
                final isHovered = _hoveredVerbKey == verbKey;
                final isPicked = _pickedVerbCategory == catNum && _pickedVerbIndex == verbNum;
                final isPinned = _pinnedVerbCategory == catNum && _pinnedVerbIndex == verbNum;
                return MouseRegion(
                  onEnter: (_) => setState(() => _hoveredVerbKey = verbKey),
                  onExit: (_) => setState(() => _hoveredVerbKey = null),
                  child: GestureDetector(
                    onSecondaryTapDown: (TapDownDetails d) {
                      _showVerbContextMenu(context, d.globalPosition, verb, isFavorite,
                          catNum: catNum, verbNum: verbNum, isPinned: isPinned);
                    },
                    child: InkWell(
                        onTapDown: (TapDownDetails d) {
                          if (HardwareKeyboard.instance.isMetaPressed) {
                            _onVerbTapped(catNum, verbNum, cmdHeld: true);
                          }
                        },
                        onTap: () {
                          if (!HardwareKeyboard.instance.isMetaPressed) {
                            _onVerbTapped(catNum, verbNum);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.only(left: 24, right: 8, top: 2, bottom: 2),
                          decoration: BoxDecoration(
                            color: isPinned
                                ? const Color(0xFFFFF8E1)
                                : (isPicked
                                    ? const Color(0xFFDBEAFF)
                                    : (isHovered ? Colors.grey.shade200 : null)),
                            border: isPinned
                                ? Border(
                                    left: const BorderSide(color: Color(0xFFF59E0B), width: 3),
                                    bottom: BorderSide(color: Colors.grey.shade100, width: 0.5),
                                  )
                                : (isPicked
                                    ? Border(
                                        left: const BorderSide(color: Color(0xFF4A90E2), width: 3),
                                        bottom: BorderSide(color: Colors.grey.shade100, width: 0.5),
                                      )
                                    : Border(
                                        bottom: BorderSide(color: Colors.grey.shade100, width: 0.5),
                                      )),
                          ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            SizedBox(
                              width: 28,
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
                                      child: Icon(Icons.push_pin, size: 11, color: Color(0xFFF59E0B)),
                                    ),
                                  if (isLastUsed && !isPinned)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: Text(
                                        '← Last used',
                                        style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.w500),
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
            offset += 1;
          }
          }
          }
          return const SizedBox.shrink();
        },
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
                color: isPinned ? const Color(0xFFF59E0B) : Colors.grey.shade600,
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
        position.dx, position.dy, position.dx + 1, position.dy + 1,
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
              thumbVisibility: true,
              child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: selectedVerbs.length,
                  itemBuilder: (context, vi) {
                final verb = selectedVerbs[vi];
                final verbNum = vi + 1;
                if (verb.trim().isEmpty) {
                  return const SizedBox(height: 20);
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
                    _showVerbContextMenu(context, d.globalPosition, verb, isFavorite);
                  },
                  child: InkWell(
                    onTap: () => _onVerbTapped(selectedCatNum!, verbNum),
                      child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
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
                          width: 28,
                          child: Text(
                            '$verbNum',
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
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  verb,
                                  style: TextStyle(
                                    fontSize: 12,
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
    Color? bg,
    double width = 60,
  }) {
    final enabled = onTap != null;
    final color = bg ?? (enabled ? Colors.grey.shade100 : Colors.grey.shade200);
    final borderColor = enabled ? Colors.grey.shade300 : Colors.grey.shade400;
    return SizedBox(
      width: width,
      height: 32,
      child: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: InkRipple.splashFactory,
          highlightColor: Colors.black.withOpacity(0.06),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
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
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
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
      height: 32,
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
                          Icon(Icons.settings, size: 18, color: Colors.black87),
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
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_upload, size: 12, color: Colors.white),
              const SizedBox(width: 4),
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
      padding: const EdgeInsets.only(top: 8),
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
                Icon(Icons.arrow_back, size: 12, color: Colors.grey.shade700),
                const SizedBox(width: 2),
                Text('Save', style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
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
                Text('Save', style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                const SizedBox(width: 2),
                Icon(Icons.arrow_forward, size: 12, color: Colors.grey.shade700),
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
                Icon(Icons.content_paste, size: 12, color: Colors.grey.shade700),
                const SizedBox(width: 2),
                Text('Paste', style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
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
                Text('Paste Prev', style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
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
                const Icon(Icons.settings, size: 12, color: Colors.white),
                const SizedBox(width: 4),
                Text('FTP Settings', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white)),
              ],
            ),
          ),
          // Reset
          _btn(
            width: 60,
            onTap: _onResetPressed,
            bg: Colors.grey.shade200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.refresh, size: 12, color: Colors.grey.shade700),
                const SizedBox(width: 2),
                Text('Reset Caption', style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
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

  void _onResetPressed() {
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

  Widget _buildPeriodPicker() {
    final sport = (() {
      try {
        return (widget.captionState as dynamic).currentSportName as String? ?? 'hockey';
      } catch (_) {
        return 'hockey';
      }
    })();
    final isBasketball = sport == 'basketball';
    final periodLabels = isBasketball
        ? (  _showPlayoffOvertimes
              ? ['Pre-Game', '2OT', '3OT', '4OT', '5OT', 'Post Game']
              : ['Pre-Game', 'Q1', 'Q2', 'Q3', 'Q4', 'OT', '1H', '2H'])
        : (_showPlayoffOvertimes
              ? ['Pre-Game', '1OT', '2OT', '3OT', '4OT', '5OT']
              : ['Pre-Game', '1', '2', '3', 'OT', 'SO']);
    final selected = _getSelectedPeriod();

    const Set<String> wideLabels = {'Pre-Game', 'Post Game'};

    Widget periodButton(String label) {
      final isSelected = selected == label;
      final isWide = wideLabels.contains(label);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: SizedBox(
          width: isWide ? 64 : 32,
          height: 32,
          child: OutlinedButton(
            onPressed: () => _onPeriodSelect(label),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(
                color: isSelected
                    ? Colors.blue.shade500
                    : Colors.grey.shade400,
              ),
              backgroundColor: isSelected
                  ? Colors.blue.shade50
                  : Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? Colors.blue.shade700
                    : Colors.grey.shade700,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
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
          child: Text(
            isBasketball ? 'Quarter' : 'Period',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        Container(
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
          padding: const EdgeInsets.all(6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...periodLabels.map(periodButton),
              const SizedBox(width: 4),
              SizedBox(
                width: 32,
                height: 32,
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
                    size: 14,
                    color: _showPlayoffOvertimes
                        ? Colors.blue.shade700
                        : Colors.grey.shade700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              periodButton('Post Game'),
            ],
          ),
        ),
      ],
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
        return _firebarHv == 'H' ? columnIndex == 0 : columnIndex == 1; // team 1
      case 2:
        return _firebarHv == 'H' ? columnIndex == 1 : columnIndex == 0; // team 2
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
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              'Firebar',
              style: TextStyle(
                fontSize: 11,
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
                  onChanged: (value) {
                    if (_firebarStep == 0 && value.isNotEmpty) {
                      final hv = value.trim().toUpperCase();
                      if (hv == 'H' || hv == 'V') _applyFirebarHv(hv);
                      return;
                    }
                    if (_firebarStep == 3 && value.isNotEmpty) {
                      final n = int.tryParse(value.trim());
                      final cats = _verbList;
                      if (n != null && n >= 1 && cats.isNotEmpty && n <= cats.length) {
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
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.zero,
                      borderSide: const BorderSide(color: Colors.red, width: 2),
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
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _firebarController,
                        builder: (context, value, _) {
                          if (_firebarStep != 1 && _firebarStep != 2) return const SizedBox.shrink();
                          final roster = _firebarStep == 1
                              ? (_firebarHv == 'H' ? widget.homeRoster : widget.awayRoster)
                              : (_firebarHv == 'H' ? widget.awayRoster : widget.homeRoster);
                          final names = _playerNamesForNumbers(value.text, roster);
                          if (names.isEmpty) return const SizedBox.shrink();
                          return Text(
                            names,
                            style: TextStyle(
                              fontSize: 11,
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Caption (column-style: title bar + content with shadow)
                Expanded(
                  flex: 7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
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
                        child: Text(
                          'Caption',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      Container(
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
                        padding: const EdgeInsets.all(4),
                        child: _buildCaptionField(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Personality (column-style: title bar + content with shadow)
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
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
                        child: Text(
                          'Personality',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      Container(
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
                        padding: const EdgeInsets.all(4),
                        child: Builder(builder: (context) {
                          TextEditingController? ctrl;
                          try {
                            ctrl = (widget.captionState as dynamic)
                                .personalityTextController as TextEditingController?;
                          } catch (_) {}
                          if (ctrl == null) {
                            return TextField(
                              maxLines: 4,
                              style: const TextStyle(fontSize: 12),
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.all(4),
                                filled: true,
                                fillColor: _panelBackgroundLight,
                              ),
                            );
                          }
                          return TextField(
                            controller: ctrl,
                            maxLines: 4,
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.all(4),
                              filled: true,
                              fillColor: _panelBackgroundLight,
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!widget.showDialogActions) _buildPeriodPicker(),
            if (!widget.showDialogActions && _showFirebar) _buildNewFirebar(),
            // Always show roster + verb columns so layout isn't blank when roster load fails
            const SizedBox(height: 8),
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
                            padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
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
                            child: Row(
                              children: [
                                Text(
                                  homeName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () => setState(() => _useSquarePlayerView = false),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: !_useSquarePlayerView ? Colors.blue.shade100 : Colors.grey.shade200,
                                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(3), bottomLeft: Radius.circular(3)),
                                      border: Border.all(color: Colors.grey.shade400),
                                    ),
                                    child: Text('List', style: TextStyle(fontSize: 9, color: !_useSquarePlayerView ? Colors.blue.shade800 : Colors.grey.shade600)),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => setState(() => _useSquarePlayerView = true),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _useSquarePlayerView ? Colors.blue.shade100 : Colors.grey.shade200,
                                      borderRadius: const BorderRadius.only(topRight: Radius.circular(3), bottomRight: Radius.circular(3)),
                                      border: Border.all(color: Colors.grey.shade400),
                                    ),
                                    child: Text('Squares', style: TextStyle(fontSize: 9, color: _useSquarePlayerView ? Colors.blue.shade800 : Colors.grey.shade600)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: _panelBackgroundLight,
                                borderRadius: BorderRadius.zero,
                                border: Border.all(
                                  color: _isFirebarColumnActive(0) ? Colors.red : Colors.grey.shade300,
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
                                padding: const EdgeInsets.all(6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _buildColumnBar(
                                      controller: _homeBarController,
                                    focusNode: _homeBarFocus,
                                    onSubmitted: _onHomeBarSubmit,
                                    rosterForGhostNames: widget.homeRoster,
                                  ),
                                  Expanded(
                                    child: _useSquarePlayerView
                                        ? Padding(
                                            padding: const EdgeInsets.only(bottom: 12),
                                            child: _buildRosterSquareGrid(widget.homeRoster, true),
                                          )
                                        : ValueListenableBuilder<TextEditingValue>(
                                            valueListenable: _homeBarController,
                                            builder: (_, value, __) =>
                                                _buildRosterColumnContent(widget.homeRoster, true, barText: value.text),
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
                    const SizedBox(width: 8),
                    // ── 2: Categories + verbs (one bar: 2 digits = cat + verb) ───
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
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
                            child: Text(
                              'Verbs',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
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
                                  color: _isFirebarColumnActive(2) ? Colors.red : Colors.grey.shade300,
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
                                padding: const EdgeInsets.all(6),
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
                                  Expanded(
                                    child: ValueListenableBuilder<TextEditingValue>(
                                      valueListenable: _categoryBarController,
                                      builder: (_, value, __) =>
                                          _buildCategoriesWithVerbsContent(barText: value.text),
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
                    const SizedBox(width: 8),
                    // ── 3: Away roster (title, then box: number bar + list) ───────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
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
                            child: Text(
                              awayName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
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
                                  color: _isFirebarColumnActive(1) ? Colors.red : Colors.grey.shade300,
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
                                padding: const EdgeInsets.all(6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _buildColumnBar(
                                      controller: _awayBarController,
                                    focusNode: _awayBarFocus,
                                    onSubmitted: _onAwayBarSubmit,
                                    rosterForGhostNames: widget.awayRoster,
                                  ),
                                  Expanded(
                                    child: _useSquarePlayerView
                                        ? Padding(
                                            padding: const EdgeInsets.only(bottom: 12),
                                            child: _buildRosterSquareGrid(widget.awayRoster, false),
                                          )
                                        : ValueListenableBuilder<TextEditingValue>(
                                            valueListenable: _awayBarController,
                                            builder: (_, value, __) =>
                                                _buildRosterColumnContent(widget.awayRoster, false, barText: value.text),
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
                    const SizedBox(width: 8),
                    // ── 4: Actions (Save Prev/Next, Paste, Copy, etc.) ─────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
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
                            child: Text(
                              'Actions',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(6),
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
                                    const SizedBox(height: 8),
                                    Row(
                              children: [
                                Expanded(
                                  child: _btn(
                                    width: double.infinity,
                    onTap: (widget.currentIndex != null && widget.currentIndex! > 0)
                        ? () async {
                            if (widget.onSaveIptc != null) widget.onSaveIptc!();
                            widget.onPreviousImage?.call();
                          }
                        : null,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.arrow_back, size: 12, color: Colors.grey.shade700),
                                        const SizedBox(width: 2),
                                        Text('Save', style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _btn(
                                    width: double.infinity,
                    onTap: (widget.currentIndex != null && widget.totalImages != null && widget.currentIndex! < widget.totalImages! - 1)
                        ? () async {
                            if (widget.onSaveIptc != null) widget.onSaveIptc!();
                            widget.onNextImage?.call();
                          }
                                        : null,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text('Save', style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                                        const SizedBox(width: 2),
                                        Icon(Icons.arrow_forward, size: 12, color: Colors.grey.shade700),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                if (widget.onCopy != null)
                                  Expanded(
                                    child: _btn(
                                      width: double.infinity,
                                      onTap: widget.onCopy,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.copy, size: 12, color: Colors.grey.shade700),
                                          const SizedBox(width: 2),
                                          Text('Copy', style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (widget.onCopy != null) const SizedBox(width: 6),
                                Expanded(
                                  child: _btn(
                                    width: double.infinity,
                                    onTap: widget.onPaste,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.content_paste, size: 12, color: Colors.grey.shade700),
                                        const SizedBox(width: 2),
                                        Text('Paste', style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            _btn(
                              width: double.infinity,
                              onTap: widget.onPastePrevious,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.history, size: 12, color: Colors.grey.shade700),
                                  const SizedBox(width: 2),
                                  Text('Paste Prev', style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            _btn(
                              width: double.infinity,
                              onTap: _onResetPressed,
                              bg: Colors.grey.shade200,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.refresh, size: 12, color: Colors.grey.shade700),
                                  const SizedBox(width: 2),
                                  Text('Reset Caption', style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            if (!widget.ftpDisabled && widget.onFtp != null) ...[
                              const SizedBox(height: 6),
                              _buildFtpButtonWithContextMenu(),
                            ],
                                  const SizedBox(height: 6),
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
                child: Text('Cancel', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ),
              if (onPrimary != null) ...[
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    if (_step == 0) _onStep1Submit();
                    else if (_step == 1) _onStep2Submit();
                    else if (_step == 2) _done();
                  },
                  child: Text(primaryLabel, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ],
      ],
    );

    final container = Container(
      constraints: widget.showDialogActions ? const BoxConstraints(maxWidth: 780) : null,
      padding: widget.showDialogActions
          ? const EdgeInsets.all(16)
          : const EdgeInsets.fromLTRB(10, 10, 10, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.zero,
        border: widget.showDialogActions ? Border.all(color: Colors.grey.shade400) : null,
      ),
      child: Shortcuts.manager(
        manager: _FirebarShortcutManager(shortcuts: const <ShortcutActivator, Intent>{
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
