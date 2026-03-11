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
  bool _showPlayoffOvertimes = false;
  Offset? _verbPopupGlobalOffset;

  OverlayEntry? _verbActionsOverlayEntry;

  // New single firebar under periods: one bar, steps H/V → team1 → team2 → category → verb
  final TextEditingController _firebarController = TextEditingController();
  final FocusNode _firebarFocus = FocusNode();
  int _firebarStep = 0; // 0=H/V, 1=team1, 2=team2, 3=category, 4=verb
  String? _firebarHv; // 'H' or 'V'
  String _firebarTeam1Value = '';
  String _firebarTeam2Value = '';
  String _firebarCategoryValue = '';
  String _firebarVerbValue = '';

  final GlobalKey _verbColumnKey = GlobalKey();

  void _showVerbActionsPopup() {
    final offset = _verbPopupGlobalOffset;
    if (offset == null || !mounted) return;
    _verbActionsOverlayEntry?.remove();
    // Prefer root overlay so the popup appears when panel is in a nested route
    OverlayState? overlay;
    try {
      overlay = Navigator.of(context, rootNavigator: true).overlay;
    } catch (_) {}
    overlay ??= Overlay.of(context);

    const double popupHeight = 68.0;
    const double margin = 8.0;
    final screenSize = MediaQuery.sizeOf(context);

    // Size and horizontal position: 4px less wide than verb column, aligned inside column outline
    double popupWidth = 120.0;
    double left = offset.dx - popupWidth / 2;
    final box = _verbColumnKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      popupWidth = (box.size.width - 4).clamp(80.0, double.infinity);
      final columnLeft = box.localToGlobal(Offset.zero).dx;
      left = columnLeft + 2; // 2px inset from column left so popup sits inside the outline
    }
    if (left + popupWidth > screenSize.width - margin) left = screenSize.width - popupWidth - margin;
    if (left < margin) left = margin;

    // Vertical: show right where the verb was clicked
    double top = offset.dy + 2;
    if (top + popupHeight > screenSize.height - margin) top = offset.dy - popupHeight - 2;
    if (top < margin) top = margin;

    _verbActionsOverlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _verbActionsOverlayEntry?.remove();
              _verbActionsOverlayEntry = null;
              setState(() {});
            },
            child: const SizedBox.expand(),
          ),
          Positioned(
            left: left,
            top: top,
            child: SizedBox(
              width: popupWidth,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 26,
                            child: GestureDetector(
                              onTap: () {
                                widget.captionState?.updateCaptionFromKeyboardFire();
                                if (widget.onSaveIptc != null) widget.onSaveIptc!();
                                widget.onNextImage?.call();
                                _verbActionsOverlayEntry?.remove();
                                _verbActionsOverlayEntry = null;
                                if (mounted) setState(() {});
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.grey.shade300),
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.save, size: 12, color: Colors.grey.shade700),
                                    const SizedBox(width: 2),
                                    Text(
                                      'Save',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: SizedBox(
                            height: 26,
                            child: GestureDetector(
                              onTap: widget.onCopy != null
                                  ? () {
                                      widget.onCopy!();
                                      _verbActionsOverlayEntry?.remove();
                                      _verbActionsOverlayEntry = null;
                                      if (mounted) setState(() {});
                                    }
                                  : null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                                decoration: BoxDecoration(
                                  color: widget.onCopy != null
                                      ? Colors.grey.shade100
                                      : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: widget.onCopy != null
                                        ? Colors.grey.shade300
                                        : Colors.grey.shade400,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.copy, size: 12, color: Colors.grey.shade700),
                                    const SizedBox(width: 2),
                                    Text(
                                      'Copy',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      height: 26,
                      child: GestureDetector(
                        onTap: widget.ftpDisabled
                            ? null
                            : () {
                                widget.onFtp?.call();
                                _verbActionsOverlayEntry?.remove();
                                _verbActionsOverlayEntry = null;
                                if (mounted) setState(() {});
                              },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                          decoration: BoxDecoration(
                            color: widget.ftpDisabled
                                ? Colors.grey.shade300
                                : const Color(0xFF0052CC),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: widget.ftpDisabled
                                  ? Colors.grey.shade400
                                  : const Color(0xFF0052CC),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.rocket_launch,
                                size: 12,
                                color: widget.ftpDisabled
                                    ? Colors.grey.shade600
                                    : Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  widget.ftpDisabled
                                      ? 'FTP OFF'
                                      : (widget.currentFtpProfile ?? 'FTP'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: widget.ftpDisabled
                                          ? Colors.grey.shade600
                                          : Colors.white),
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
            ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_verbActionsOverlayEntry!);
    setState(() {});
  }

  void _onVerbTapped(int selectedCatNum, int verbNum) {
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
    // Defer popup to next frame so overlay is ready and tap position is committed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showVerbActionsPopup();
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
      _pickedVerbCategory = null;
      _pickedVerbIndex = null;
      // Reset firebar so next caption starts at H/V
      _firebarStep = 0;
      _firebarHv = null;
      _firebarTeam1Value = '';
      _firebarTeam2Value = '';
      _firebarCategoryValue = '';
      _firebarVerbValue = '';
      _firebarController.clear();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _verbActionsOverlayEntry?.remove();
    _verbActionsOverlayEntry = null;
    _inputController.dispose();
    _inputFocus.dispose();
    _firebarController.dispose();
    _firebarFocus.dispose();
    _homeBarController.dispose();
    _awayBarController.dispose();
    _categoryBarController.dispose();
    _verbBarController.dispose();
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
      widget.captionState?.updateCaptionFromKeyboardFire();
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
            contentPadding: const EdgeInsets.all(8),
            filled: true,
            fillColor: Colors.grey.shade50,
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
          contentPadding: const EdgeInsets.all(8),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
      );
    });
  }


  List<Widget> _buildRosterRows(List<Player> roster, bool isHomeTeam) {
    if (roster.isEmpty) return [];
    final selectedNames = _getSelectedPlayerNames(isHomeTeam);
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
          return InkWell(
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
              color: isPicked ? Colors.blue.shade50 : null,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      displayName,
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList();
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
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: inputFormatters,
      onSubmitted: (_) => onSubmitted(),
      onChanged: onChanged,
    );
    if (rosterForGhostNames == null || rosterForGhostNames.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: field,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final names = _playerNamesForNumbers(value.text, rosterForGhostNames);
              if (names.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 4),
                child: Text(
                  names,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
          field,
        ],
      ),
    );
  }

  Widget _buildRosterColumn(String teamLabel, List<Player> roster, {required bool isHomeTeam}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: _buildRosterSection(teamLabel, roster, isHomeTeam: isHomeTeam),
      ),
    );
  }

  /// Roster list only (no border; caller wraps with bar inside same box).
  Widget _buildRosterColumnContent(List<Player> roster, bool isHomeTeam) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildRosterRows(roster, isHomeTeam),
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
  Widget _buildCategoryPanelContent() {
    final cats = _verbList;
    if (cats.isEmpty) {
      return Center(
        child: Text('No categories',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      );
    }
    return ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: cats.length,
              itemBuilder: (context, i) {
          final cat = cats[i];
          final catNum = cat['number'] as int? ?? (i + 1);
          final name = cat['name'] as String? ?? '';
          final isFavs = name == 'Favorites';
          final isSelected = _selectedCategoryIndex == i;
          return InkWell(
            onTap: () => setState(() => _selectedCategoryIndex = i),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.grey.shade200
                    : (isFavs ? Colors.amber.shade50 : Colors.transparent),
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
                      color: isSelected
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

  void _showVerbContextMenu(
      BuildContext context, Offset position, String verb, bool isFavorite) {
    final state = widget.captionState;
    if (state == null) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
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
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade800,
                ),
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
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) async {
      if (value == 'favorite') {
        await state.toggleFavoriteVerbFromKeyboardFire(verb);
        if (mounted) setState(() {});
      } else if (value == 'edit') {
        state.showEditVerbDialogForKeyboardFire(verb);
      }
    });
  }

  /// Verb list only (no border; caller wraps with bar inside same box).
  Widget _buildVerbPanelContent() {
    final cats = _verbList;
    final selectedVerbs = _selectedCategoryIndex != null && cats.isNotEmpty
        ? ((cats[_selectedCategoryIndex!]['verbs'] as List<dynamic>?)
                ?.cast<String>() ??
            [])
        : <String>[];
    final selectedCatNum =
        _selectedCategoryIndex != null ? _selectedCategoryIndex! + 1 : null;

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
                final isLastUsed = _lastUsedVerbLabel == verb;
                final dynamic state = widget.captionState;
                final isFavorite = state != null &&
                    (state.isFavoriteVerbFromKeyboardFire(verb) == true);
                return Listener(
                  onPointerDown: (PointerDownEvent e) {
                    _verbPopupGlobalOffset = e.position;
                  },
                  child: GestureDetector(
                    onTapDown: (TapDownDetails d) {
                      _verbPopupGlobalOffset = d.globalPosition;
                    },
                    onSecondaryTapDown: (TapDownDetails d) {
                      _showVerbContextMenu(context, d.globalPosition, verb, isFavorite);
                    },
                    child: InkWell(
                      onTap: () => _onVerbTapped(selectedCatNum!, verbNum),
                      child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: isPicked ? Colors.blue.shade50 : null,
                      border: Border(
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
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  verb,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black87),
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
    return SizedBox(
      width: width,
      height: 26,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          decoration: BoxDecoration(
            color: bg ?? (enabled ? Colors.grey.shade100 : Colors.grey.shade200),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: enabled ? Colors.grey.shade300 : Colors.grey.shade400,
            ),
          ),
          child: child,
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
                    widget.captionState?.updateCaptionFromKeyboardFire();
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
                    widget.captionState?.updateCaptionFromKeyboardFire();
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
                Text('Reset', style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
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
    setState(() {
      _firebarStep = 0;
      _firebarHv = null;
      _firebarTeam1Value = '';
      _firebarTeam2Value = '';
      _firebarCategoryValue = '';
      _firebarVerbValue = '';
    });
    _firebarController.clear();
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
    final periodLabels = _showPlayoffOvertimes
        ? ['1OT', '2OT', '3OT', '4OT', '5OT', 'Pre-Game', 'Post Game']
        : ['1', '2', '3', 'OT', 'SO', 'Pre-Game', 'Post Game'];
    final selected = _getSelectedPeriod();

    Widget periodButton(String label) {
      final isSelected = selected == label;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: SizedBox(
          height: 26,
          child: OutlinedButton(
            onPressed: () => _onPeriodSelect(label),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
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

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              'Period',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...periodLabels.map(periodButton),
              const SizedBox(width: 4),
              SizedBox(
                width: 28,
                height: 26,
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
            ],
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
                      borderRadius: BorderRadius.circular(4),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
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
                // Caption (title outside outline box)
                Expanded(
                  flex: 7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 4),
                        child: Text(
                          'Caption',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                        child: _buildCaptionField(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Personality (title outside outline box)
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 4),
                        child: Text(
                          'Personality',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
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
                                contentPadding: const EdgeInsets.all(8),
                                filled: true,
                                fillColor: Colors.grey.shade50,
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
                              contentPadding: const EdgeInsets.all(8),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!widget.showDialogActions) _buildActionBar(),
            if (!widget.showDialogActions) _buildPeriodPicker(),
            if (!widget.showDialogActions) _buildNewFirebar(),
            if (widget.homeRoster.isNotEmpty ||
                widget.awayRoster.isNotEmpty ||
                _step == 2) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Text(
                  'Caption Builder',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── 1: Home roster (title, then box: number bar + list) ───────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
                            child: Text(
                              homeName,
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
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _isFirebarColumnActive(0) ? Colors.red : Colors.grey.shade300,
                                  width: _isFirebarColumnActive(0) ? 2 : 1,
                                ),
                              ),
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
                                    child: _buildRosterColumnContent(widget.homeRoster, true),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ── 2: Away roster (title, then box: number bar + list) ───────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
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
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _isFirebarColumnActive(1) ? Colors.red : Colors.grey.shade300,
                                  width: _isFirebarColumnActive(1) ? 2 : 1,
                                ),
                              ),
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
                                    child: _buildRosterColumnContent(widget.awayRoster, false),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ── 3: Verb categories (title, then box: number bar + list) ───
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
                            child: Text(
                              'Verb Category',
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
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _isFirebarColumnActive(2) ? Colors.red : Colors.grey.shade300,
                                  width: _isFirebarColumnActive(2) ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildColumnBar(
                                    controller: _categoryBarController,
                                    focusNode: _categoryBarFocus,
                                    onSubmitted: _onCategoryBarSubmit,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(2),
                                    ],
                                  ),
                                  Expanded(
                                    child: _buildCategoryPanelContent(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ── 4: Verbs (title, then box: number bar + list) ──────────────
                    Expanded(
                      child: Column(
                        key: _verbColumnKey,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
                            child: Text(
                              'Verb',
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
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: _isFirebarColumnActive(3) ? Colors.red : Colors.grey.shade300,
                                  width: _isFirebarColumnActive(3) ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildColumnBar(
                                    controller: _verbBarController,
                                    focusNode: _verbBarFocus,
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
                                    child: _buildVerbPanelContent(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
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
          borderRadius: BorderRadius.circular(4),
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
