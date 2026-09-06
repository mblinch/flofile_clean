import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app_styled_dialogs.dart';
import 'package:flutter/services.dart';
import '../services/mlb_api_service.dart';
import '../services/preferences_service.dart';
import '../services/api_manager.dart';
import '../utils/default_verb_keywords.dart';
import '../utils/home_run_type_ui.dart';
import 'verb_keyword_quick_bar.dart';
import '../caption_style/verb_sub_options.dart';
import '../caption_style/sport_verb_categories.dart';
import '../flo_layout_constants.dart';
import '../services/admin_service.dart';
import '../theme/app_tokens.dart';
import '../utils/baseball_tags_popup_rows.dart';
import 'admin_screen.dart';
import 'app_compact_checkbox.dart';
import 'card_container.dart';
import 'caption_layout_builder_dialog.dart';

/// Which Keyboard Fire column Tab currently targets (left → right).
enum _KbShortcutPanel { home, verbs, away }

/// Intents for global H/V firebar shortcut (only when not in a text field).
class _FirebarHIntent extends Intent {
  const _FirebarHIntent();
}

class _FirebarVIntent extends Intent {
  const _FirebarVIntent();
}

/// US Mac Option+digit characters → jersey digit.
const Map<String, String> _kMacOptionDigitChars = {
  'º': '0',
  '¡': '1',
  '™': '2',
  '£': '3',
  '¢': '4',
  '∞': '5',
  '§': '6',
  '¶': '7',
  '•': '8',
  'ª': '9',
};

const Map<ShortcutActivator, Intent> _kFirebarShortcuts =
    <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.keyH): _FirebarHIntent(),
  SingleActivator(LogicalKeyboardKey.keyV): _FirebarVIntent(),
};

/// ShortcutManager that does not handle firebar H/V when focus is in a text
/// input. Ctrl/Alt jersey digit shortcuts still apply in search bars.
class _FirebarShortcutManager extends ShortcutManager {
  _FirebarShortcutManager({required super.shortcuts});

  static bool isFocusInTextInput([FocusNode? focus]) {
    focus ??= FocusManager.instance.primaryFocus;
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
            event.logicalKey == LogicalKeyboardKey.keyV) &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isMetaPressed) {
      if (isFocusInTextInput()) {
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

  /// When >1, action-bar Save shows "Save (N)" for bulk IPTC write.
  final int? bulkSaveCount;
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

  /// Optional widget injected to the right of the teams/verbs row.
  final Widget? trailingSidebar;

  /// When true (sidebar Keyword mode), always show the Keywords box.
  final bool keywordModeEnabled;

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
    this.bulkSaveCount,
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
    this.trailingSidebar,
    this.keywordModeEnabled = false,
  });

  @override
  State<KeyboardFirePanel> createState() => _KeyboardFirePanelState();
}

class _KeyboardFirePanelState extends State<KeyboardFirePanel> {
  static const MethodChannel _jerseyShortcutChannel =
      MethodChannel('caption_writer/jersey_shortcuts');

  /// Must match [_buildCaptionField] — roster player names use this too.
  static const TextStyle _captionFieldTextStyle = TextStyle(
    fontSize: 11.5,
    letterSpacing: 0,
    height: 1.4,
    fontFamily: 'Inter',
  );

  TextStyle _rosterPlayerTextStyle({
    Color? color,
    FontWeight? fontWeight,
  }) {
    return _captionFieldTextStyle.copyWith(
      color: color ?? const Color(0xFF1A1A1A),
      fontWeight: fontWeight,
    );
  }

  String _bulkSaveLabel() {
    final n = widget.bulkSaveCount;
    if (n != null && n > 1) return 'Save ($n)';
    return 'Save';
  }

  int _saveActionBarBtnWidth() {
    final n = widget.bulkSaveCount;
    if (n != null && n > 1) return 88;
    return 72;
  }

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
  final ScrollController _homeRosterScrollController = ScrollController();
  final ScrollController _awayRosterScrollController = ScrollController();
  final FocusNode _homeBarFocus = FocusNode();
  final FocusNode _awayBarFocus = FocusNode();
  final FocusNode _categoryBarFocus = FocusNode();
  final FocusNode _verbBarFocus = FocusNode();
  /// Caption text field in the Caption card.
  final FocusNode _captionFocus = FocusNode();

  /// Personality field in the Caption card header.
  final FocusNode _personalityFieldFocus = FocusNode();

  /// Column highlighted by Tab cycling (Home / Verbs / Visiting).
  _KbShortcutPanel? _shortcutPanel;
  String _homeSummary = '';
  String _awaySummary = '';
  String _verbSummary = '';
  final ApiManager _apiManager = ApiManager();
  List<Player> _homeRosterView = [];
  List<Player> _awayRosterView = [];

  /// In-scroll coaching block: each map has `title` (e.g. Manager) and `name`.
  List<Map<String, String>> _homeStaffDisplay = [];
  List<Map<String, String>> _awayStaffDisplay = [];
  bool _waitingForVerb = true;
  // Cascading verb picker state
  int? _selectedCategoryIndex; // index into _verbList
  int? _pickedVerbCategory; // 1-based category of last picked verb
  int? _pickedVerbIndex; // 1-based index of last picked verb
  String?
      _lastUsedVerbLabel; // verb label to show "(last used)" in red when image changes
  /// Last reaction picked in the Cele control (defaults to celebrates on first tap).
  String? _lastReactionPhrase;

  // Pinned verb: Cmd+click to pin; auto-applies to every subsequent image
  int? _pinnedVerbCategory;
  int? _pinnedVerbIndex;
  String? _pinnedCustomVerb;
  String? _lastCustomVerb;

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

  /// Stack that owns the category list + drag ghost (for coordinate conversion).
  final GlobalKey _categoryReorderStackKey = GlobalKey();

  /// Pointer position in [_categoryReorderStackKey] space while dragging a category.
  Offset? _categoryDragGhostLocal;

  /// Latest pointer position (global) during category row interaction — seeds ghost at long-press.
  Offset? _categoryDragLastGlobal;

  // Verb drag-to-reorder (same model as category: long-press, ghost, swap on release).
  int? _dragFromVerbCatIndex;
  int? _dragFromVerbIndex;
  int? _dragToVerbCatIndex;
  int? _dragToVerbIndex;
  Timer? _verbLongPressTimer;
  final Map<String, GlobalKey> _verbRowKeys = {};
  Offset? _verbDragGhostLocal;
  Offset? _verbDragLastGlobal;

  /// After a verb drag session, ignore the synthetic [InkWell.onTap] on pointer up.
  bool _suppressVerbTapAfterVerbDrag = false;

  /// Ctrl/Alt + digits: buffer for multi-digit jersey shortcuts.
  String _modJerseyBuffer = '';
  bool? _modJerseyIsHome;
  Timer? _modJerseyTimer;

  /// True while Shift is held — shows shortcut badges on verb sub-option chips.
  bool _shiftHintHeld = false;

  GlobalKey _catKey(int i) => _catRowKeys.putIfAbsent(i, () => GlobalKey());

  GlobalKey _verbRowKey(int ci, int vi) =>
      _verbRowKeys.putIfAbsent('${ci}_$vi', () => GlobalKey());

  MapEntry<int, int>? _verbRowAtGlobal(Offset global) {
    for (final entry in _verbRowKeys.entries) {
      final parts = entry.key.split('_');
      if (parts.length != 2) continue;
      final ci = int.tryParse(parts[0]);
      final vi = int.tryParse(parts[1]);
      if (ci == null || vi == null) continue;
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final pos = box.localToGlobal(Offset.zero);
      if (global.dx >= pos.dx &&
          global.dx < pos.dx + box.size.width &&
          global.dy >= pos.dy &&
          global.dy < pos.dy + box.size.height) {
        return MapEntry(ci, vi);
      }
    }
    return null;
  }

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

  /// Floating preview card that follows the pointer while reordering categories.
  Widget _buildCategoryReorderGhost(double maxStackWidth) {
    final from = _dragFromCatIndex;
    final local = _categoryDragGhostLocal;
    if (from == null || local == null) return const SizedBox.shrink();
    final cats = _verbList;
    if (from < 0 || from >= cats.length) return const SizedBox.shrink();
    final cat = cats[from];
    final catNum = cat['number'] as int? ?? (from + 1);
    final name = cat['name'] as String? ?? '';
    final isFavs = name == 'Favorites';
    final ghostW = math.min(260.0, math.max(80.0, maxStackWidth - 8));
    final left = math.max(
      4.0,
      math.min(local.dx - ghostW * 0.2, maxStackWidth - ghostW - 4),
    );
    final top = local.dy - 24;
    return Positioned(
      left: left,
      top: top,
      width: ghostW,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          elevation: 12,
          shadowColor: Colors.black38,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            decoration: BoxDecoration(
                color: (isFavs ? Colors.amber.shade50 : Colors.white)
                    .withOpacity(0.97),
                border: Border.all(
                  color: isFavs ? Colors.amber.shade400 : Colors.blue.shade300,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(5)),
            child: Row(
              children: [
                Icon(Icons.drag_indicator,
                    size: 13, color: Colors.grey.shade700),
                const SizedBox(width: 4),
                SizedBox(
                  width: 19,
                  child: Text(
                    '$catNum',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade900,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade900,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Floating preview while reordering verbs (same interaction as category reorder).
  Widget _buildVerbReorderGhost(double maxStackWidth) {
    final fCi = _dragFromVerbCatIndex;
    final fVi = _dragFromVerbIndex;
    final local = _verbDragGhostLocal;
    if (fCi == null || fVi == null || local == null) {
      return const SizedBox.shrink();
    }
    final cats = _verbList;
    if (fCi < 0 || fCi >= cats.length) return const SizedBox.shrink();
    final cat = cats[fCi];
    final verbs = (cat['verbs'] as List<dynamic>?)?.cast<String>() ?? [];
    if (fVi < 0 || fVi >= verbs.length) return const SizedBox.shrink();
    final label = verbs[fVi];
    final catNum = cat['number'] as int? ?? (fCi + 1);
    final verbNum = fVi + 1;
    final ghostW = math.min(260.0, math.max(80.0, maxStackWidth - 8));
    final left = math.max(
      4.0,
      math.min(local.dx - ghostW * 0.2, maxStackWidth - ghostW - 4),
    );
    final top = local.dy - 24;
    return Positioned(
      left: left,
      top: top,
      width: ghostW,
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          elevation: 12,
          shadowColor: Colors.black38,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.97),
                border: Border.all(
                  color: Colors.blue.shade300,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(5)),
            child: Row(
              children: [
                Icon(Icons.drag_indicator,
                    size: 13, color: Colors.grey.shade700),
                const SizedBox(width: 4),
                SizedBox(
                  width: 23,
                  child: Text(
                    '$verbNum',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade900,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade900,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    '($catNum)',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
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

  void _swapVerbsKeyboardFire(String categoryName, String verbA, String verbB) {
    if (verbA.isEmpty || verbB.isEmpty || verbA == verbB) return;
    final state = widget.captionState;
    if (state == null) return;
    try {
      (state as dynamic)
          .swapVerbsInCategoryForKeyboardFire(categoryName, verbA, verbB);
    } catch (_) {}
  }

  /// Long-press ~500ms then drag; ghost follows pointer; release on another verb to swap.
  Widget _wrapVerbRowForReorder({
    required int ci,
    required int vi,
    required Widget child,
  }) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        _verbDragLastGlobal = e.position;
        _catLongPressTimer?.cancel();
        _verbLongPressTimer?.cancel();
        if (_dragFromCatIndex != null) {
          setState(() {
            _dragFromCatIndex = null;
            _dragToCatIndex = null;
            _categoryDragGhostLocal = null;
          });
        }
        _verbLongPressTimer = Timer(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          setState(() {
            _dragFromVerbCatIndex = ci;
            _dragFromVerbIndex = vi;
            _dragToVerbCatIndex = ci;
            _dragToVerbIndex = vi;
            final box = _categoryReorderStackKey.currentContext
                ?.findRenderObject() as RenderBox?;
            if (box != null && box.hasSize && _verbDragLastGlobal != null) {
              _verbDragGhostLocal = box.globalToLocal(_verbDragLastGlobal!);
            }
          });
        });
      },
      onPointerMove: (e) {
        _verbDragLastGlobal = e.position;
        if (_dragFromVerbCatIndex == null) return;
        final box = _categoryReorderStackKey.currentContext?.findRenderObject()
            as RenderBox?;
        final hit = _verbRowAtGlobal(e.position);
        setState(() {
          if (box != null && box.hasSize) {
            _verbDragGhostLocal = box.globalToLocal(e.position);
          }
          if (hit != null && hit.key == _dragFromVerbCatIndex) {
            _dragToVerbCatIndex = hit.key;
            _dragToVerbIndex = hit.value;
          } else {
            _dragToVerbCatIndex = _dragFromVerbCatIndex;
            _dragToVerbIndex = _dragFromVerbIndex;
          }
        });
      },
      onPointerUp: (e) {
        _verbLongPressTimer?.cancel();
        final hadSession = _dragFromVerbCatIndex != null;
        if (hadSession &&
            _dragFromVerbCatIndex != null &&
            _dragToVerbCatIndex != null &&
            _dragFromVerbIndex != null &&
            _dragToVerbIndex != null &&
            _dragFromVerbCatIndex == _dragToVerbCatIndex &&
            _dragFromVerbIndex != _dragToVerbIndex) {
          final cats = _verbList;
          final fc = _dragFromVerbCatIndex!;
          if (fc >= 0 && fc < cats.length) {
            final cat = cats[fc];
            final cname = cat['name'] as String? ?? '';
            final canon =
                (cat['verbsCanonical'] as List<dynamic>?)?.cast<String>();
            if (canon != null &&
                _dragFromVerbIndex! < canon.length &&
                _dragToVerbIndex! < canon.length) {
              _swapVerbsKeyboardFire(
                cname,
                canon[_dragFromVerbIndex!],
                canon[_dragToVerbIndex!],
              );
            }
          }
        }
        if (hadSession) {
          setState(() {
            _dragFromVerbCatIndex = null;
            _dragFromVerbIndex = null;
            _dragToVerbCatIndex = null;
            _dragToVerbIndex = null;
            _verbDragGhostLocal = null;
          });
          _suppressVerbTapAfterVerbDrag = true;
        }
      },
      onPointerCancel: (_) {
        _verbLongPressTimer?.cancel();
        setState(() {
          _dragFromVerbCatIndex = null;
          _dragFromVerbIndex = null;
          _dragToVerbCatIndex = null;
          _dragToVerbIndex = null;
          _verbDragGhostLocal = null;
        });
      },
      child: child,
    );
  }

  /// Baseball Keyboard Fire: 0 = innings 1–9, 1 = 10–18, 2 = 19–27.
  int _baseballInningPage = 0;

  /// When true, show players in a **number grid**: one row per decade (0–9, 10–19, …),
  /// ten columns per row. When false, list view with names.
  bool _useSquarePlayerView = false;
  String _kbPlayerSortBy = 'number'; // 'number', 'lastname', 'firstname'
  bool _kbPlayerSortAscending = true;
  bool _showHomeCoachingPanel = false;
  bool _showAwayCoachingPanel = false;

  // Lock list sizing to each column's initial viewport height so resizing the
  // dialog does not keep changing player text/row size.
  double? _lockedHomeRosterListViewportHeight;
  double? _lockedAwayRosterListViewportHeight;

  double _sanitizeKbRosterListViewport(double height) {
    if (!height.isFinite || height <= 0) return 340.0;
    return height.clamp(120.0, 640.0);
  }

  /// Jersey/name `fontSize` for list roster — locked to caption field size.
  double _keyboardFireListRosterFontSize(double listViewportHeight) {
    return _captionFieldTextStyle.fontSize!;
  }

  /// Shared roster text size used as the typography baseline for verbs/categories.
  /// Locks to the same initial roster viewport measurement used by player rows.
  double _keyboardFireRosterReferenceFontSize() {
    final home = _lockedHomeRosterListViewportHeight;
    final away = _lockedAwayRosterListViewportHeight;
    final viewport = (home != null && away != null)
        ? ((_sanitizeKbRosterListViewport(home) +
                _sanitizeKbRosterListViewport(away)) /
            2.0)
        : _sanitizeKbRosterListViewport(home ?? away ?? 340.0);
    return _keyboardFireListRosterFontSize(viewport);
  }

  /// Fit category + expanded verb rows into the list viewport.
  /// Current (unscaled) sizes are the max; shrink only when needed to avoid scroll.
  /// Width: full column when content fits; reserve scrollbar gutter when scrolling.
  static const double _kKbCatVerbMinScale = 0.40;
  static const double _kKbCatMaxPadV = 6.0;
  static const double _kKbCatMaxFont = 11.0;
  static const double _kKbVerbMaxPadV = 5.0;
  static const double _kKbCatVerbListTopPad = 4.0;

  /// Reserve room for the Custom Verb footer so it isn't scaled away.
  static const double _kKbCustomVerbReserve = 72.0;

  _KbCatVerbMetrics _kbCatVerbMetrics({
    required double listViewportHeight,
    required double baseVerbFont,
    required int categoryCount,
    required int expandedVerbCount,
  }) {
    final maxCatH = _kKbCatMaxPadV * 2 + _kKbCatMaxFont;
    final maxVerbH = _kKbVerbMaxPadV * 2 + baseVerbFont;
    final catN = math.max(1, categoryCount);
    final verbN = math.max(0, expandedVerbCount);
    final neededAtMax = catN * maxCatH + verbN * maxVerbH;

    final available =
        (listViewportHeight - _kKbCatVerbListTopPad - _kKbCustomVerbReserve)
            .clamp(64.0, 8000.0);

    final scale = neededAtMax <= available
        ? 1.0
        : (available / neededAtMax).clamp(_kKbCatVerbMinScale, 1.0);

    final catPadH = 5.0 * scale;
    final catPadV = _kKbCatMaxPadV * scale;
    final catFont = math.max(8.0, _kKbCatMaxFont * scale);
    final catIcon = math.max(8.0, 11.0 * scale);
    final catNumW = math.max(12.0, 18.0 * scale);

    final verbPadT = _kKbVerbMaxPadV * scale;
    final verbPadB = _kKbVerbMaxPadV * scale;
    final verbPadLReorder = 7.0 * scale;
    final verbPadLPlain = 18.0 * scale;
    final verbPadR = 5.0 * scale;
    final verbFont = math.max(8.0, baseVerbFont * scale);
    final verbNumFont = math.max(7.0, catFont - 2.0);
    final verbIcon = math.max(8.0, 11.0 * scale);
    final verbNumW = math.max(16.0, 24.0 * scale);
    final dragGap = 3.0 * scale;
    final submenuContentLeft = 0.0;

    return _KbCatVerbMetrics(
      scale: scale,
      catPadH: catPadH,
      catPadV: catPadV,
      catFont: catFont,
      catIcon: catIcon,
      catNumW: catNumW,
      verbPadT: verbPadT,
      verbPadB: verbPadB,
      verbPadLReorder: verbPadLReorder,
      verbPadLPlain: verbPadLPlain,
      verbPadR: verbPadR,
      verbFont: verbFont,
      verbNumFont: verbNumFont,
      verbIcon: verbIcon,
      verbNumW: verbNumW,
      submenuContentLeft: submenuContentLeft,
    );
  }

  /// Mirrors Preferences → Application → Caption fields (Keywords / Personality; headline strip removed).
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

  /// When true, verb category list reserves right gutter for the scrollbar.
  /// Defaults true to avoid a first-frame overlap; cleared only after layout
  /// confirms the list truly does not scroll.
  bool _categoriesListNeedsScrollGutter = true;
  bool _categoriesScrollGutterCheckScheduled = false;

  /// Hover highlight: "home_12" / "away_5" for roster; "catNum_verbNum" for verbs.
  String? _hoveredRosterKey;
  String? _hoveredVerbKey;

  void _scheduleCategoriesScrollGutterCheck() {
    if (_categoriesScrollGutterCheckScheduled) return;
    _categoriesScrollGutterCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _categoriesScrollGutterCheckScheduled = false;
      if (!mounted) return;
      _applyCategoriesScrollGutterFromController();
    });
  }

  void _applyCategoriesScrollGutterFromController() {
    if (!_categoriesScrollController.hasClients) {
      _scheduleCategoriesScrollGutterCheck();
      return;
    }
    final need = _categoriesScrollController.position.maxScrollExtent > 0.5;
    if (need == _categoriesListNeedsScrollGutter) return;
    setState(() => _categoriesListNeedsScrollGutter = need);
  }

  void _syncCategoriesScrollGutter(ScrollMetrics metrics) {
    final need = metrics.maxScrollExtent > 0.5;
    // Eagerly add the gutter when overflow is clear.
    if (need) {
      if (!_categoriesListNeedsScrollGutter) {
        setState(() => _categoriesListNeedsScrollGutter = true);
      }
      return;
    }
    // Clearing the gutter waits until after layout — early metrics often
    // report maxScrollExtent == 0 before children are measured.
    _scheduleCategoriesScrollGutterCheck();
  }

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

  void _applyCustomVerb(String rawText, {bool pin = false}) {
    final text = rawText.trim();
    _customVerbController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    widget.captionState?.updateCustomVerbFromPopup(text);
    setState(() {
      if (text.isNotEmpty) {
        _lastCustomVerb = text;
        _pickedVerbCategory = null;
        _pickedVerbIndex = null;
      }
      if (pin) {
        _pinnedCustomVerb = text.isEmpty ? null : text;
        _pinnedVerbCategory = null;
        _pinnedVerbIndex = null;
      }
    });
    _refreshCaptionPreviewLater();
  }

  /// List-verb selection overrides custom text: clear the field and any custom pin.
  /// The next [selectVerbByCategoryAndIndexFromKeyboardFire] clears the popup custom phrase; do not call
  /// `updateCustomVerbFromPopup('')` here first — that method awaits prefs and could clear the verb after selection.
  void _discardCustomVerbFieldForListSelection() {
    final hasField = _customVerbController.text.trim().isNotEmpty;
    final hadPinnedCustom = _pinnedCustomVerb != null;
    if (!hasField && !hadPinnedCustom) return;
    if (hasField) {
      _customVerbController.clear();
    }
    if (hadPinnedCustom) {
      setState(() => _pinnedCustomVerb = null);
    }
  }

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
          _pinnedCustomVerb = null;
          // Also select it immediately
          _pickedVerbCategory = selectedCatNum;
          _pickedVerbIndex = verbNum;
        }
      });
      if (!alreadyPinned) {
        _discardCustomVerbFieldForListSelection();
        widget.captionState?.selectVerbByCategoryAndIndexFromKeyboardFire(
            selectedCatNum, verbNum,
            forceSelect: true);
        widget.captionState?.updateCaptionFromKeyboardFire();
        _refreshCaptionPreviewLater();
      }
      return;
    }

    // Re-clicking the active verb clears pick + pin and restores undimmed list.
    final thisPicked =
        _pickedVerbCategory == selectedCatNum && _pickedVerbIndex == verbNum;
    final thisPinned =
        _pinnedVerbCategory == selectedCatNum && _pinnedVerbIndex == verbNum;
    if (thisPicked || thisPinned) {
      setState(() {
        _pickedVerbCategory = null;
        _pickedVerbIndex = null;
        if (thisPinned) {
          _pinnedVerbCategory = null;
          _pinnedVerbIndex = null;
        }
        _waitingForVerb = false;
        _verbSummary = '';
      });
      try {
        (widget.captionState as dynamic)?.clearVerbSelectionFromKeyboardFire();
      } catch (_) {
        widget.captionState?.selectVerbByCategoryAndIndexFromKeyboardFire(
            selectedCatNum, verbNum);
        widget.captionState?.updateCaptionFromKeyboardFire();
      }
      _refreshCaptionPreviewLater();
      return;
    }

    _discardCustomVerbFieldForListSelection();
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

  /// When leaving a category (collapse or switch), clear its picked verb.
  /// Pinned verbs stay pinned and keep the caption; unpinned picks are cleared.
  void _unpickVerbIfInCategory(int catNum) {
    if (_pickedVerbCategory != catNum || _pickedVerbIndex == null) return;
    final cat = catNum;
    final idx = _pickedVerbIndex!;
    final keepCaption =
        _pinnedVerbCategory == cat && _pinnedVerbIndex == idx;
    setState(() {
      _pickedVerbCategory = null;
      _pickedVerbIndex = null;
    });
    if (!keepCaption) {
      widget.captionState
          ?.selectVerbByCategoryAndIndexFromKeyboardFire(cat, idx);
      widget.captionState?.updateCaptionFromKeyboardFire();
      _refreshCaptionPreviewLater();
    }
  }

  /// Pin a verb by category+index (from context menu).
  void _setPinnedVerb(int catNum, int verbNum) {
    _discardCustomVerbFieldForListSelection();
    setState(() {
      _pinnedVerbCategory = catNum;
      _pinnedVerbIndex = verbNum;
      _pinnedCustomVerb = null;
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
      _pinnedCustomVerb = null;
    });
  }

  /// Unpin and drop the selected verb so multi-player selection can proceed.
  void _clearPinnedVerbAndSelection() {
    setState(() {
      _pinnedVerbCategory = null;
      _pinnedVerbIndex = null;
      _pinnedCustomVerb = null;
      _pickedVerbCategory = null;
      _pickedVerbIndex = null;
    });
  }

  bool _hasPinnedVerb() =>
      _pinnedVerbCategory != null ||
      _pinnedVerbIndex != null ||
      (_pinnedCustomVerb != null && _pinnedCustomVerb!.trim().isNotEmpty);

  void _wireCaptionPinHooks() {
    final cs = widget.captionState;
    if (cs == null) return;
    try {
      (cs as dynamic).keyboardFireClearPinnedVerb = _clearPinnedVerbAndSelection;
      (cs as dynamic).keyboardFireHasPinnedVerb = _hasPinnedVerb;
    } catch (_) {}
  }

  void _clearCaptionPinHooks() {
    final cs = widget.captionState;
    if (cs == null) return;
    try {
      (cs as dynamic).keyboardFireClearPinnedVerb = null;
      (cs as dynamic).keyboardFireHasPinnedVerb = null;
    } catch (_) {}
  }

  List<Map<String, String>> _computeStaffDisplayLines(
      Map<String, String?> staff, String sport) {
    final out = <Map<String, String>>[];
    void push(String title, String key) {
      final n = (staff[key] ?? '').trim();
      if (n.isEmpty) return;
      out.add({'title': title, 'name': n});
    }

    final headTitle =
        (sport == 'baseball' || sport == 'soccer') ? 'Manager' : 'Head Coach';
    push(headTitle, 'headCoach');
    if (sport == 'baseball') {
      push('Pitching Coach', 'pitchingCoach');
      push('First Base Coach', 'firstBaseCoach');
      push('Third Base Coach', 'thirdBaseCoach');
    }
    if (out.isEmpty) {
      return [
        {'title': headTitle, 'name': 'data missing'},
      ];
    }
    return out;
  }

  Future<void> _refreshCoachLabel({required bool isHome}) async {
    final teamName = isHome ? widget.homeTeamName : widget.awayTeamName;
    if (teamName == null || teamName.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        if (isHome) {
          _homeStaffDisplay = [];
        } else {
          _awayStaffDisplay = [];
        }
      });
      return;
    }

    try {
      final sport = (() {
        try {
          return (widget.captionState as dynamic).currentSportName as String? ??
              'baseball';
        } catch (_) {
          return 'baseball';
        }
      })();
      _apiManager.setSport(sport);
      final staff = await _apiManager.fetchTeamStaff(teamName);
      final lines = _computeStaffDisplayLines(staff, sport);
      if (!mounted) return;
      setState(() {
        if (isHome) {
          _homeStaffDisplay = lines;
        } else {
          _awayStaffDisplay = lines;
        }
      });
    } catch (_) {
      if (!mounted) return;
      final sport = (() {
        try {
          return (widget.captionState as dynamic).currentSportName as String? ??
              'baseball';
        } catch (_) {
          return 'baseball';
        }
      })();
      final headTitle =
          (sport == 'baseball' || sport == 'soccer') ? 'Manager' : 'Head Coach';
      setState(() {
        if (isHome) {
          _homeStaffDisplay = [
            {'title': headTitle, 'name': 'data missing'},
          ];
        } else {
          _awayStaffDisplay = [
            {'title': headTitle, 'name': 'data missing'},
          ];
        }
      });
    }
  }

  void _syncRostersFromWidget() {
    _homeRosterView = List<Player>.from(widget.homeRoster);
    _awayRosterView = List<Player>.from(widget.awayRoster);
  }

  String _kbPlayerLastName(Player player) {
    final name = player.fullName.trim();
    if (name.isEmpty) return player.displayName;
    final parts = name.split(RegExp(r'\s+'));
    return parts.length >= 2 ? parts.last : name;
  }

  String _kbPlayerFirstName(Player player) {
    final name = player.fullName.trim();
    if (name.isEmpty) return player.displayName;
    final parts = name.split(RegExp(r'\s+'));
    return parts.isNotEmpty ? parts.first : name;
  }

  int _compareKbPlayers(Player a, Player b) {
    int cmp;
    switch (_kbPlayerSortBy) {
      case 'lastname':
        cmp = _kbPlayerLastName(a)
            .toLowerCase()
            .compareTo(_kbPlayerLastName(b).toLowerCase());
        break;
      case 'firstname':
        cmp = _kbPlayerFirstName(a)
            .toLowerCase()
            .compareTo(_kbPlayerFirstName(b).toLowerCase());
        break;
      case 'number':
      default:
        final an = int.tryParse(a.jerseyNumber?.trim() ?? '') ?? 9999;
        final bn = int.tryParse(b.jerseyNumber?.trim() ?? '') ?? 9999;
        cmp = an.compareTo(bn);
    }
    if (cmp == 0) {
      cmp = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    }
    return _kbPlayerSortAscending ? cmp : -cmp;
  }

  List<Player> _sortedKbRoster(List<Player> roster) {
    final sorted = List<Player>.from(roster);
    sorted.sort(_compareKbPlayers);
    return sorted;
  }

  void _onKbSortChipTap(String field) {
    setState(() {
      if (_kbPlayerSortBy == field) {
        _kbPlayerSortAscending = !_kbPlayerSortAscending;
      } else {
        _kbPlayerSortBy = field;
        _kbPlayerSortAscending = true;
      }
    });
  }

  Widget _buildKbSortChip(String label, String field) {
    final selected = _kbPlayerSortBy == field;
    return Material(
      color: selected
          ? AppTokens.accentTint
          : AppTokens.surface.withValues(alpha: 0),
      child: InkWell(
        onTap: () => _onKbSortChipTap(field),
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: AppTokens.microLabel.copyWith(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color:
                      selected ? AppTokens.accentDeep : AppTokens.inkSecondary,
                  height: 1.0,
                  letterSpacing: 0,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 1),
                Icon(
                  _kbPlayerSortAscending
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 12,
                  color: AppTokens.accent,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKbPlayerSortControls() {
    final segments = [
      _buildKbSortChip('#', 'number'),
      _buildKbSortChip('Last', 'lastname'),
      _buildKbSortChip('First', 'firstname'),
    ];
    return Container(
      width: double.infinity,
      height: 22,
      decoration: BoxDecoration(
        border: Border.all(color: AppTokens.cardBorder),
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusControl - 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < segments.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  height: 22,
                  color: AppTokens.cardBorder,
                ),
              Expanded(child: segments[i]),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openAddPlayerFromKeyboardFire(bool isHome) async {
    final cs = widget.captionState;
    if (cs == null) return;
    try {
      await (cs as dynamic).showAddCustomPlayerFromKeyboardFire(isHome: isHome);
    } catch (_) {}
    if (mounted) {
      setState(_syncRostersFromWidget);
    }
  }

  /// Compact “+” above the roster; opens the same add-player dialog as classic mode.
  Widget _buildKbAddPlayerIconButton(bool isHome) {
    return Tooltip(
      message: 'Add player',
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: AppTokens.surface.withValues(alpha: 0),
        child: InkWell(
          onTap: () => _openAddPlayerFromKeyboardFire(isHome),
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(
              Icons.add_rounded,
              size: 14,
              color: AppTokens.accent,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _wireCaptionPinHooks();
    _personalityFieldFocus.addListener(_onPersonalityFieldFocusChanged);
    _homeBarFocus.addListener(_syncShortcutPanelFromFocus);
    _awayBarFocus.addListener(_syncShortcutPanelFromFocus);
    _categoryBarFocus.addListener(_syncShortcutPanelFromFocus);
    _captionFocus.addListener(_syncShortcutPanelFromFocus);
    HardwareKeyboard.instance.addHandler(_handlePanelFocusKeys);
    HardwareKeyboard.instance.addHandler(_handlePlayerJerseyShortcut);
    _enableNativeJerseyShortcuts(true);
    if (widget.keywordModeEnabled) {
      _showKeywordsField = true;
    }
    _syncRostersFromWidget();
    _refreshCoachLabel(isHome: true);
    _refreshCoachLabel(isHome: false);
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
      if (mounted) _captionFocus.requestFocus();
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload does not re-run initState; keep handlers live.
    HardwareKeyboard.instance.removeHandler(_handlePanelFocusKeys);
    HardwareKeyboard.instance.removeHandler(_handlePlayerJerseyShortcut);
    HardwareKeyboard.instance.addHandler(_handlePanelFocusKeys);
    HardwareKeyboard.instance.addHandler(_handlePlayerJerseyShortcut);
    _enableNativeJerseyShortcuts(true);
  }

  /// Keep the column outline in sync when a search bar or the caption is focused.
  /// Tab can highlight a column without focusing a bar — don't clear that when
  /// focus is nowhere.
  void _syncShortcutPanelFromFocus() {
    if (!mounted) return;
    final _KbShortcutPanel? next;
    if (_homeBarFocus.hasFocus) {
      next = _KbShortcutPanel.home;
    } else if (_categoryBarFocus.hasFocus) {
      next = _KbShortcutPanel.verbs;
    } else if (_awayBarFocus.hasFocus) {
      next = _KbShortcutPanel.away;
    } else if (_captionFocus.hasFocus || _personalityFieldFocus.hasFocus) {
      next = null;
    } else {
      return; // Leave Tab-only highlight alone.
    }
    if (next != _shortcutPanel) {
      setState(() => _shortcutPanel = next);
    }
  }

  FocusNode _focusNodeForPanel(_KbShortcutPanel panel) {
    switch (panel) {
      case _KbShortcutPanel.home:
        return _homeBarFocus;
      case _KbShortcutPanel.verbs:
        return _categoryBarFocus;
      case _KbShortcutPanel.away:
        return _awayBarFocus;
    }
  }

  /// Highlight a column. [focusBar] is for click; Tab uses highlight only.
  void _selectShortcutPanel(_KbShortcutPanel panel, {bool focusBar = false}) {
    if (_shortcutPanel != panel) {
      setState(() => _shortcutPanel = panel);
    }
    if (focusBar) {
      final node = _focusNodeForPanel(panel);
      if (!node.hasFocus) node.requestFocus();
    }
  }

  void _cycleShortcutPanel({required bool reverse}) {
    const order = _KbShortcutPanel.values;
    final current = _shortcutPanel;
    final int nextIndex;
    if (current == null) {
      nextIndex = reverse ? order.length - 1 : 0;
    } else {
      final i = order.indexOf(current);
      nextIndex = reverse
          ? (i - 1 + order.length) % order.length
          : (i + 1) % order.length;
    }
    // Leave any typing box so Tab doesn't park the caret in a search bar.
    FocusManager.instance.primaryFocus?.unfocus();
    _selectShortcutPanel(order[nextIndex], focusBar: false);
  }

  /// Esc leaves any typing box; Tab / Shift+Tab cycles Home → Verbs → Visiting.
  bool _handlePanelFocusKeys(KeyEvent event) {
    if (!mounted) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    final kb = HardwareKeyboard.instance;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final focus = FocusManager.instance.primaryFocus;
      final hadFocus = focus != null && focus.hasFocus;
      if (hadFocus) focus.unfocus();
      if (_shortcutPanel != null) {
        setState(() => _shortcutPanel = null);
        return true;
      }
      return hadFocus;
    }

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      // Leave ⌘Tab / ⌃Tab / ⌥Tab alone (system or other shortcuts).
      if (kb.isMetaPressed || kb.isControlPressed || kb.isAltPressed) {
        return false;
      }
      _cycleShortcutPanel(reverse: kb.isShiftPressed);
      return true;
    }

    return false;
  }

  /// Accent outline around the Tab/click-targeted column.
  /// Click selects the column highlight; the number bar only takes the caret
  /// when you click the bar itself (so verb/roster taps aren't eaten by focus).
  Widget _wrapShortcutPanelHighlight({
    required _KbShortcutPanel panel,
    required bool active,
    required Widget child,
  }) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _selectShortcutPanel(panel, focusBar: false),
      child: AnimatedContainer(
        duration: AppTokens.motionFast,
        curve: AppTokens.motionCurve,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard + 1),
          border: Border.all(
            color: active ? AppTokens.accent : Colors.transparent,
            width: 2,
          ),
        ),
        padding: const EdgeInsets.all(1),
        child: child,
      ),
    );
  }

  void _onKeyboardFireCaptionFieldVisibilityRevision() {
    _applyKeyboardFireCaptionFieldVisibility();
  }

  void _onPersonalityFieldFocusChanged() {
    if (mounted) setState(() {});
  }

  void _applyKeyboardFireCaptionFieldVisibility() {
    final p = _prefsService;
    if (p == null || !mounted) return;
    setState(() {
      _showHeadlineField = p.captionFieldHeadlineVisibleSync;
      // Keyword mode from the parent wins over prefs when it is on.
      _showKeywordsField =
          widget.keywordModeEnabled || p.captionFieldKeywordsVisibleSync;
      _showPersonalityField = p.captionFieldPersonalityVisibleSync;
    });
  }

  bool get _keywordsBoxVisible =>
      widget.keywordModeEnabled || _showKeywordsField;

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
    final result = await showAppContextMenu<String>(
      context: context,
      position: appContextMenuPosition(context, position),
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
    // Parent may mutate the same roster list instance in place; always mirror
    // latest widget rosters so Keyboard Fire never shows stale/empty lists.
    if (!listEquals(_homeRosterView, widget.homeRoster) ||
        !listEquals(_awayRosterView, widget.awayRoster) ||
        oldWidget.homeRoster == widget.homeRoster ||
        oldWidget.awayRoster == widget.awayRoster) {
      _syncRostersFromWidget();
    }
    if (oldWidget.homeTeamName != widget.homeTeamName) {
      _refreshCoachLabel(isHome: true);
    }
    if (oldWidget.awayTeamName != widget.awayTeamName) {
      _refreshCoachLabel(isHome: false);
    }
    if (widget.keywordModeEnabled && !oldWidget.keywordModeEnabled) {
      setState(() => _showKeywordsField = true);
      PreferencesService.getInstance().then((p) {
        if (!mounted) return;
        p.saveShowKeywordsField(true);
      });
    } else if (!widget.keywordModeEnabled && oldWidget.keywordModeEnabled) {
      setState(() => _showKeywordsField = false);
    }
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

      // Custom verb behavior on image change:
      // - pinned custom: keep applying it
      // - otherwise clear custom verb
      final pinnedCustom = _pinnedCustomVerb?.trim() ?? '';
      if (_pinnedVerbCategory == null &&
          _pinnedVerbIndex == null &&
          pinnedCustom.isNotEmpty) {
        _applyCustomVerb(pinnedCustom);
      } else {
        _customVerbController.clear();
        widget.captionState?.updateCustomVerbFromPopup('');
      }
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handlePanelFocusKeys);
    HardwareKeyboard.instance.removeHandler(_handlePlayerJerseyShortcut);
    _enableNativeJerseyShortcuts(false);
    _modJerseyTimer?.cancel();
    _clearCaptionPinHooks();
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
    _homeRosterScrollController.dispose();
    _awayRosterScrollController.dispose();
    _homeBarFocus
      ..removeListener(_syncShortcutPanelFromFocus)
      ..dispose();
    _awayBarFocus
      ..removeListener(_syncShortcutPanelFromFocus)
      ..dispose();
    _categoryBarFocus
      ..removeListener(_syncShortcutPanelFromFocus)
      ..dispose();
    _verbBarFocus.dispose();
    _captionFocus
      ..removeListener(_syncShortcutPanelFromFocus)
      ..dispose();
    _personalityFieldFocus
      ..removeListener(_onPersonalityFieldFocusChanged)
      ..dispose();
    super.dispose();
  }

  /// Digits arrive from the native layer (see `MainFlutterWindow.swift`); Dart
  /// only watches for the modifier release, which commits the typed number.
  /// Shift+# selects a verb, or RBI/HR sub-options when those chips are showing.
  bool _handlePlayerJerseyShortcut(KeyEvent event) {
    if (!mounted) return false;

    if (_updateShiftHintHeld(event)) {
      // Fall through so Shift+digit / Shift+C can still be handled below.
    }

    if (event is KeyDownEvent) {
      if (_tryConsumeShiftCelebrationShortcut(event)) return true;
      if (_tryConsumeShiftVerbShortcut(event)) return true;
    }

    if (event is! KeyUpEvent) return false;
    final k = event.logicalKey;
    final isModifier = k == LogicalKeyboardKey.controlLeft ||
        k == LogicalKeyboardKey.controlRight ||
        k == LogicalKeyboardKey.metaLeft ||
        k == LogicalKeyboardKey.metaRight ||
        k == LogicalKeyboardKey.altLeft ||
        k == LogicalKeyboardKey.altRight ||
        k == LogicalKeyboardKey.altGraph;
    if (!isModifier) return false;

    final stillCtrl = HardwareKeyboard.instance.isControlPressed;
    final stillAlt = HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance
            .isLogicalKeyPressed(LogicalKeyboardKey.altGraph);
    if (_modJerseyIsHome == true && !stillCtrl) {
      _flushModJerseyBuffer();
    } else if (_modJerseyIsHome == false && !stillAlt) {
      _flushModJerseyBuffer();
    }
    return false;
  }

  /// Keeps [_shiftHintHeld] in sync so RBI/🎉 chips can show shortcut badges.
  bool _updateShiftHintHeld(KeyEvent event) {
    final held = HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isAltPressed;
    if (held == _shiftHintHeld) return false;
    setState(() => _shiftHintHeld = held);
    return true;
  }

  /// Active verb's inline sub-option mode (RBI / Home Run), if any.
  String? _activeVerbSubMode() {
    final cat = _pickedVerbCategory;
    final idx = _pickedVerbIndex;
    if (cat == null || idx == null) return null;
    final cats = _verbList;
    final ci = cats.indexWhere(
        (c) => (c['number'] as int? ?? (cats.indexOf(c) + 1)) == cat);
    final useCi = ci >= 0 ? ci : (cat - 1);
    if (useCi < 0 || useCi >= cats.length) return null;
    final verbs =
        (cats[useCi]['verbs'] as List<dynamic>?)?.cast<String>() ?? const [];
    if (idx < 1 || idx > verbs.length) return null;
    final verb = verbs[idx - 1];
    final canon = (() {
      final raw = cats[useCi]['verbsCanonical'];
      if (raw is List && idx - 1 < raw.length) {
        return (raw[idx - 1] as String?) ?? verb;
      }
      return verb;
    })();
    if (VerbSubOptions.legacyHomeRunTypeMenu(verb)) return 'homeRun';
    if (verb == 'Bunts' || canon == 'Bunts') return null;
    try {
      final opts = (widget.captionState as dynamic)
          .getVerbSubOptionsFromKeyboardFire(verb) as VerbSubOptions;
      if (opts.rbiEnabled) return 'rbi';
    } catch (_) {}
    return null;
  }

  bool _activeVerbHasCelebration() {
    final cat = _pickedVerbCategory;
    final idx = _pickedVerbIndex;
    if (cat == null || idx == null) return false;
    final cats = _verbList;
    final ci = cats.indexWhere(
        (c) => (c['number'] as int? ?? (cats.indexOf(c) + 1)) == cat);
    final useCi = ci >= 0 ? ci : (cat - 1);
    if (useCi < 0 || useCi >= cats.length) return false;
    final verbs =
        (cats[useCi]['verbs'] as List<dynamic>?)?.cast<String>() ?? const [];
    if (idx < 1 || idx > verbs.length) return false;
    final verb = verbs[idx - 1];
    try {
      final opts = (widget.captionState as dynamic)
          .getVerbSubOptionsFromKeyboardFire(verb) as VerbSubOptions;
      return opts.celebrationEnabled;
    } catch (_) {
      return false;
    }
  }

  void _applyRbiShortcut(int rbi) {
    final state = widget.captionState;
    if (state == null) return;
    try {
      final current = (state as dynamic).currentRbiCount as int?;
      (state as dynamic).setRbiFromKeyboardFire(current == rbi ? null : rbi);
    } catch (_) {}
    setState(() {});
    _refreshCaptionPreviewLater();
  }

  void _applyHomeRunShortcut(int n) {
    const types = ['Solo', 'Two-Run', 'Three-Run', 'Grand Slam'];
    if (n < 1 || n > types.length) return;
    final type = types[n - 1];
    final state = widget.captionState;
    if (state == null) return;
    try {
      final current = (state as dynamic).currentHomeRunType as String?;
      (state as dynamic)
          .setHomeRunTypeFromKeyboardFire(current == type ? null : type);
    } catch (_) {}
    setState(() {});
    _refreshCaptionPreviewLater();
  }

  void _toggleCelebrationShortcut() {
    final state = widget.captionState;
    if (state == null || !_activeVerbHasCelebration()) return;
    final cat = _pickedVerbCategory!;
    final idx = _pickedVerbIndex!;
    final cats = _verbList;
    final ci = cats.indexWhere(
        (c) => (c['number'] as int? ?? (cats.indexOf(c) + 1)) == cat);
    final useCi = ci >= 0 ? ci : (cat - 1);
    if (useCi < 0 || useCi >= cats.length) return;
    final verbs =
        (cats[useCi]['verbs'] as List<dynamic>?)?.cast<String>() ?? const [];
    if (idx < 1 || idx > verbs.length) return;
    final verb = verbs[idx - 1];
    try {
      final opts = (state as dynamic).getVerbSubOptionsFromKeyboardFire(verb)
          as VerbSubOptions;
      final phrases = opts.reactionPhraseList;
      if (phrases.isEmpty) return;
      final current = (state as dynamic).currentHittingAction as String?;
      final isOn = current != null &&
          phrases.any((p) => p.toLowerCase() == current.toLowerCase());
      if (isOn) {
        (state as dynamic).setHittingActionFromKeyboardFire(null);
      } else {
        final target = _lastReactionPhrase ?? opts.primaryReactionPhrase;
        _lastReactionPhrase = target;
        (state as dynamic).setHittingActionFromKeyboardFire(target);
      }
    } catch (_) {}
    setState(() {});
    _refreshCaptionPreviewLater();
  }

  bool _tryConsumeShiftCelebrationShortcut(KeyEvent event) {
    final kb = HardwareKeyboard.instance;
    if (!kb.isShiftPressed) return false;
    if (kb.isControlPressed || kb.isMetaPressed || kb.isAltPressed) {
      return false;
    }
    if (event.logicalKey != LogicalKeyboardKey.keyC) return false;
    if (!_activeVerbHasCelebration()) return false;
    _toggleCelebrationShortcut();
    return true;
  }

  /// Shift+1…9 (0 = 10) → verb number, or RBI/HR chip when those are showing.
  bool _tryConsumeShiftVerbShortcut(KeyEvent event) {
    final kb = HardwareKeyboard.instance;
    if (!kb.isShiftPressed) return false;
    if (kb.isControlPressed || kb.isMetaPressed || kb.isAltPressed) {
      return false;
    }
    final verbNum = _logicalKeyToVerbNumber(event.logicalKey);
    if (verbNum == null) return false;
    _handleShiftAssignedNumber(verbNum);
    return true;
  }

  void _handleShiftAssignedNumber(int n) {
    final mode = _activeVerbSubMode();
    if (mode == 'rbi' && n >= 1 && n <= 3) {
      _applyRbiShortcut(n);
      return;
    }
    if (mode == 'homeRun' && n >= 1 && n <= 4) {
      _applyHomeRunShortcut(n);
      return;
    }
    _selectVerbByAssignedNumber(n);
  }

  int? _logicalKeyToVerbNumber(LogicalKeyboardKey k) {
    if (k == LogicalKeyboardKey.digit1 || k == LogicalKeyboardKey.numpad1) {
      return 1;
    }
    if (k == LogicalKeyboardKey.digit2 || k == LogicalKeyboardKey.numpad2) {
      return 2;
    }
    if (k == LogicalKeyboardKey.digit3 || k == LogicalKeyboardKey.numpad3) {
      return 3;
    }
    if (k == LogicalKeyboardKey.digit4 || k == LogicalKeyboardKey.numpad4) {
      return 4;
    }
    if (k == LogicalKeyboardKey.digit5 || k == LogicalKeyboardKey.numpad5) {
      return 5;
    }
    if (k == LogicalKeyboardKey.digit6 || k == LogicalKeyboardKey.numpad6) {
      return 6;
    }
    if (k == LogicalKeyboardKey.digit7 || k == LogicalKeyboardKey.numpad7) {
      return 7;
    }
    if (k == LogicalKeyboardKey.digit8 || k == LogicalKeyboardKey.numpad8) {
      return 8;
    }
    if (k == LogicalKeyboardKey.digit9 || k == LogicalKeyboardKey.numpad9) {
      return 9;
    }
    if (k == LogicalKeyboardKey.digit0 || k == LogicalKeyboardKey.numpad0) {
      return 10;
    }
    return null;
  }

  void _selectVerbByAssignedNumber(int verbNum) {
    final cats = _verbList;
    if (cats.isEmpty || verbNum < 1) return;
    final ci = (_expandedCategoryIndex ?? _selectedCategoryIndex ?? 0)
        .clamp(0, cats.length - 1);
    final verbs =
        (cats[ci]['verbs'] as List<dynamic>?)?.cast<String>() ?? const [];
    if (verbNum > verbs.length) return;
    final catNum = cats[ci]['number'] as int? ?? (ci + 1);
    if (_expandedCategoryIndex != ci || _selectedCategoryIndex != ci) {
      setState(() {
        _expandedCategoryIndex = ci;
        _selectedCategoryIndex = ci;
      });
    }
    _onVerbTapped(catNum, verbNum);
  }

  void _enableNativeJerseyShortcuts(bool enabled) {
    _jerseyShortcutChannel.setMethodCallHandler(
      enabled ? _onNativeJerseyShortcut : null,
    );
    _jerseyShortcutChannel.invokeMethod<void>('setEnabled', enabled);
  }

  Future<void> _onNativeJerseyShortcut(MethodCall call) async {
    if (call.method == 'verbDigit') {
      final args = call.arguments;
      if (args is! Map) return;
      final digit = args['digit']?.toString() ?? '';
      if (digit.isEmpty) return;
      final verbNum = digit == '0' ? 10 : int.tryParse(digit);
      if (verbNum == null) return;
      _handleShiftAssignedNumber(verbNum);
      return;
    }
    if (call.method != 'jerseyDigit') return;
    final args = call.arguments;
    if (args is! Map) return;
    final digit = args['digit']?.toString() ?? '';
    if (digit.isEmpty) return;
    _appendModJerseyDigit(isHome: args['isHome'] == true, digit: digit);
  }

  List<String> _rosterJerseys(bool isHome) {
    final roster = isHome ? _homeRosterView : _awayRosterView;
    return roster
        .map((p) => (p.jerseyNumber ?? '').trim())
        .where((j) => j.isNotEmpty)
        .toList();
  }

  /// Builds up a jersey number across keystrokes, firing as soon as the number
  /// is unambiguous for the roster (so single-digit jerseys are instant).
  void _appendModJerseyDigit({required bool isHome, required String digit}) {
    _modJerseyTimer?.cancel();
    _modJerseyTimer = null;
    if (_modJerseyIsHome != isHome) _modJerseyBuffer = '';
    _modJerseyIsHome = isHome;

    final jerseys = _rosterJerseys(isHome);
    var candidate = _modJerseyBuffer + digit;
    if (!jerseys.any((j) => j.startsWith(candidate))) {
      candidate = digit;
    }
    _modJerseyBuffer = candidate;

    final hasExact = jerseys.contains(candidate);
    final hasLonger = jerseys.any(
        (j) => j.length > candidate.length && j.startsWith(candidate));

    if (hasExact && !hasLonger) {
      _flushModJerseyBuffer();
      return;
    }
    if (!hasExact && !hasLonger) {
      _modJerseyBuffer = '';
      _modJerseyIsHome = null;
      return;
    }
    // Ambiguous (e.g. "4" with "44" on the roster): the number is committed when
    // the modifier is released. The timer is only a fallback if that is missed.
    _modJerseyTimer = Timer(
        const Duration(milliseconds: 1500), _flushModJerseyBuffer);
  }

  void _flushModJerseyBuffer() {
    _modJerseyTimer?.cancel();
    _modJerseyTimer = null;
    final buf = _modJerseyBuffer;
    final isHome = _modJerseyIsHome;
    _modJerseyBuffer = '';
    _modJerseyIsHome = null;
    if (buf.isEmpty || isHome == null) return;
    _togglePlayerJerseyShortcut(isHome: isHome, jersey: buf);
  }

  void _togglePlayerJerseyShortcut({
    required bool isHome,
    required String jersey,
  }) {
    final state = widget.captionState;
    if (state == null) return;
    final roster = isHome ? _homeRosterView : _awayRosterView;
    Player? match;
    for (final p in roster) {
      if ((p.jerseyNumber ?? '').trim() == jersey.trim()) {
        match = p;
        break;
      }
    }
    if (match == null) return;
    final selected = _getSelectedPlayerNames(isHome);
    if (selected.contains(match.displayName)) {
      state.removePlayerByJersey(isHome, jersey);
    } else {
      state.addPlayerByJersey(isHome, jersey);
    }
    state.updateCaptionFromKeyboardFire();
    if (mounted) setState(() {});
    _refreshCaptionPreviewLater();
  }

  List<String> _parseNumbers(String text) {
    return text
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  List<Player> _searchPlayersInRoster(List<Player> roster, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const <Player>[];
    final tokens =
        q.split(RegExp(r'[\s,]+')).where((t) => t.isNotEmpty).toList();
    return roster.where((p) {
      final display = p.displayName.toLowerCase();
      final jersey = (p.jerseyNumber ?? '').toLowerCase();
      return tokens.every((t) => display.contains(t) || jersey == t);
    }).toList();
  }

  bool _applyPlayerSearchSelection({
    required bool isHomeTeam,
    required List<Player> roster,
    required String query,
  }) {
    final matches = _searchPlayersInRoster(roster, query);
    if (matches.isEmpty) return false;
    for (final p in matches) {
      final jersey = (p.jerseyNumber ?? '').trim();
      if (jersey.isNotEmpty) {
        widget.captionState?.addPlayerByJersey(isHomeTeam, jersey);
      }
    }
    widget.captionState?.updateCaptionFromKeyboardFire();
    return true;
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
    if (numbers.isNotEmpty) {
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
      return;
    }

    final query = _homeBarController.text.trim();
    if (!_applyPlayerSearchSelection(
      isHomeTeam: true,
      roster: _homeRosterView,
      query: query,
    )) {
      return;
    }

    _homeBarController.clear();
    setState(() {
      _homeSummary = query;
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
    if (numbers.isNotEmpty) {
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
      return;
    }

    final rawQuery = _awayBarController.text.trim();
    final matched = _applyPlayerSearchSelection(
      isHomeTeam: false,
      roster: _awayRosterView,
      query: rawQuery,
    );
    if (!matched) return;

    _awayBarController.clear();
    setState(() {
      _awaySummary = rawQuery;
      _step = 2;
    });
    _categoryBarFocus.requestFocus();
    _refreshCaptionPreviewLater();
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
      _expandedCategoryIndex = (cat - 1).clamp(0, _verbList.length - 1);
    });
    _refreshCaptionPreviewLater();
  }

  void _onCategoryVerbBarSubmit() {
    final raw = _categoryBarController.text.trim();
    if (raw.isEmpty) return;

    if (RegExp(r'^\d{2}$').hasMatch(raw)) {
      _onVerbBarInput(raw);
      return;
    }

    if (RegExp(r'^\d$').hasMatch(raw)) {
      final n = int.tryParse(raw);
      if (n != null) {
        final cats = _verbList;
        if (cats.isNotEmpty) {
          final index = (n - 1).clamp(0, cats.length - 1);
          final leavingCi = _expandedCategoryIndex;
          if (leavingCi != null && leavingCi != index) {
            final leavingCatNum =
                cats[leavingCi]['number'] as int? ?? (leavingCi + 1);
            _unpickVerbIfInCategory(leavingCatNum);
          }
          setState(() {
            _selectedCategoryIndex = index;
            _expandedCategoryIndex = index;
            _categoryBarController.clear();
          });
          _categoryBarFocus.requestFocus();
        }
      }
      return;
    }

    final q = raw.toLowerCase();
    final cats = _verbList;
    int? matchedCatNum;
    int? matchedVerbNum;
    for (int ci = 0; ci < cats.length; ci++) {
      final cat = cats[ci];
      final catName = (cat['name'] as String? ?? '').toLowerCase();
      final verbs =
          (cat['verbs'] as List<dynamic>? ?? const <dynamic>[]).cast<String>();
      if (matchedCatNum == null && catName.contains(q)) {
        matchedCatNum = ci + 1;
      }
      if (matchedVerbNum == null) {
        for (int vi = 0; vi < verbs.length; vi++) {
          if (verbs[vi].toLowerCase().contains(q)) {
            matchedCatNum = ci + 1;
            matchedVerbNum = vi + 1;
            break;
          }
        }
      }
      if (matchedVerbNum != null) break;
    }

    if (matchedCatNum == null) return;
    if (matchedVerbNum != null) {
      _onVerbTapped(matchedCatNum, matchedVerbNum);
      _categoryBarController.clear();
      _refreshCaptionPreviewLater();
      return;
    }

    setState(() {
      _selectedCategoryIndex = matchedCatNum! - 1;
      _expandedCategoryIndex = matchedCatNum! - 1;
      _categoryBarController.clear();
    });
    _categoryBarFocus.requestFocus();
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
      _expandedCategoryIndex = index;
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
    _discardCustomVerbFieldForListSelection();
    widget.captionState
        ?.selectVerbByCategoryAndIndexFromKeyboardFire(catNum, verbNum);
    widget.captionState?.updateCaptionFromKeyboardFire();
    setState(() {
      _verbSummary = 'Category $catNum, verb $verbNum selected';
      _waitingForVerb = false;
      _pickedVerbCategory = catNum;
      _pickedVerbIndex = verbNum;
      _selectedCategoryIndex = (catNum - 1).clamp(0, cats.length - 1);
      _expandedCategoryIndex = (catNum - 1).clamp(0, cats.length - 1);
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
      return TextField(
        controller: ctrl,
        focusNode: _captionFocus,
        expands: true,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        cursorHeight: 12,
        cursorColor: AppTokens.ink,
        style: AppTokens.listBody.copyWith(
          fontSize: 12,
          color: AppTokens.ink,
          height: 1.5,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Caption will appear here as you add players and a verb.',
          hintStyle: AppTokens.listBody.copyWith(
            fontSize: 12,
            color: AppTokens.inkMuted,
            height: 1.5,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.zero,
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
            color: hasOverride ? const Color(0xFF1976D2) : Colors.grey.shade500,
          ),
          const SizedBox(width: 2),
          Text(
            'Byline',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color:
                  hasOverride ? const Color(0xFF1976D2) : Colors.grey.shade500,
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

  Widget _buildKbLabeledBox(
    String label,
    Widget child, {
    Widget? trailingAction,
    Widget? footer,
  }) {
    const TextStyle _headerStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: Color(0xFF3A3A3A),
      height: 1.0,
      letterSpacing: -0.3,
      fontVariations: [
        FontVariation('wght', 700),
        FontVariation('opsz', 28),
      ],
    );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFE6E6E6), width: 0.7),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFFF8F8F8), Color(0xFFFEFEFE)],
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
              border: Border(
                bottom: BorderSide(color: Color(0xFFE8E8E8), width: 0.5),
              ),
            ),
            child: trailingAction != null
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(label, style: _headerStyle),
                      const Spacer(),
                      trailingAction,
                    ],
                  )
                : Text(label, style: _headerStyle),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
              child: child,
            ),
          ),
          if (footer != null)
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: const BoxDecoration(
                color: Color(0xFFFAFAFA),
                border: Border(
                  top: BorderSide(color: Color(0xFFE8E8E8), width: 0.5),
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(7),
                  bottomRight: Radius.circular(7),
                ),
              ),
              child: footer,
            ),
        ],
      ),
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
        style: const TextStyle(fontSize: 11.5, letterSpacing: 0, height: 1.4),
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
      style: const TextStyle(fontSize: 11.5, letterSpacing: 0, height: 1.4),
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
        style: const TextStyle(fontSize: 11.5, letterSpacing: 0, height: 1.4),
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
      style: const TextStyle(fontSize: 11.5, letterSpacing: 0, height: 1.4),
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

  /// Inline Personality field for the Caption card header. The controller's
  /// value remains complete; only the unfocused display is visually ellipsized.
  Widget _buildPersonalityFieldKb() {
    return Builder(builder: (context) {
      TextEditingController? ctrl;
      try {
        ctrl = (widget.captionState as dynamic).personalityTextController
            as TextEditingController?;
      } catch (_) {}

      final isFocused = _personalityFieldFocus.hasFocus;

      Widget displayValue(TextEditingValue value) {
        final text = value.text;
        return Text(
          text.isEmpty ? 'No player' : text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTokens.secondaryLabel.copyWith(
            fontSize: 10.5,
            color: text.isEmpty ? AppTokens.inkMuted : AppTokens.ink,
          ),
        );
      }

      final display = ctrl == null
          ? displayValue(TextEditingValue.empty)
          : ValueListenableBuilder<TextEditingValue>(
              valueListenable: ctrl,
              builder: (context, value, child) => displayValue(value),
            );

      return SizedBox(
        height: 24,
        child: AnimatedContainer(
          duration: AppTokens.motionFast,
          curve: AppTokens.motionCurve,
          decoration: BoxDecoration(
            color: AppTokens.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              TextField(
                controller: ctrl,
                focusNode: _personalityFieldFocus,
                maxLines: 1,
                cursorColor: AppTokens.accent,
                cursorWidth: 1,
                cursorHeight: 12,
                style: AppTokens.secondaryLabel.copyWith(
                  fontSize: 10.5,
                  color: isFocused
                      ? AppTokens.ink
                      : AppTokens.surface.withValues(alpha: 0),
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.only(right: 6),
                ),
              ),
              if (!isFocused)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: display,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  TextStyle get _kbHeaderTitleStyle => AppTokens.panelHeading.copyWith(
        color: AppTokens.ink,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.0,
      );

  /// Caption card (with Personality in its header) plus optional
  /// Headline/Keywords stacked vertically on the right.
  Widget _buildKeyboardFireCaptionStrip() {
    final showKeywords = _keywordsBoxVisible;
    final hasSecondary = _showHeadlineField || showKeywords;

    Widget _captionStyleBtn() => Tooltip(
          message: 'Edit caption style',
          waitDuration: const Duration(milliseconds: 350),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => CaptionLayoutBuilderDialog.show(context),
              borderRadius: BorderRadius.circular(AppTokens.radiusKeycap),
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(
                  Icons.edit_outlined,
                  size: 12,
                  color: AppTokens.accent,
                ),
              ),
            ),
          ),
        );

    Widget captionCard() {
      return CardContainer(
        headerHeight: 24,
        headerPadding: const EdgeInsets.symmetric(horizontal: 6),
        header: Row(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Caption',
                  style: _kbHeaderTitleStyle,
                ),
                const SizedBox(width: 2),
                _captionStyleBtn(),
              ],
            ),
            if (_showPersonalityField) ...[
              const SizedBox(width: 8),
              Container(
                width: 1,
                height: 14,
                color: AppTokens.cardBorder,
              ),
              const SizedBox(width: 8),
              Text(
                'Personality:',
                style: AppTokens.microLabel.copyWith(
                  color: AppTokens.inkSecondary,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(width: 3),
              Expanded(child: _buildPersonalityFieldKb()),
            ],
          ],
        ),
        child: Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: _buildCaptionField(),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!hasSecondary) {
      return captionCard();
    }

    final rightChildren = <Widget>[];
    void addSecondary(String label, Widget field) {
      if (rightChildren.isNotEmpty) {
        rightChildren.add(const SizedBox(height: 8));
      }
      rightChildren.add(
        Expanded(child: _buildKbLabeledBox(label, field)),
      );
    }

    if (_showHeadlineField) {
      addSecondary('Headline', _buildHeadlineFieldKb());
    }
    if (showKeywords) {
      addSecondary('Keywords', _buildKeywordsFieldKb());
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 12,
          child: captionCard(),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rightChildren,
          ),
        ),
      ],
    );
  }

  String _displayNameForPlayer(String fullName, String jersey) {
    final j = jersey.trim();
    return j.isEmpty ? fullName.trim() : '${fullName.trim()} #$j';
  }

  Future<void> _showPlayerEditDialog({
    required bool isHome,
    Player? existing,
  }) async {
    final numberController =
        TextEditingController(text: (existing?.jerseyNumber ?? '').trim());
    final fullNameController =
        TextEditingController(text: (existing?.fullName ?? '').trim());

    final captionState = widget.captionState;
    String? dialogError;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            backgroundColor: Colors.transparent,
            child: Container(
              width: 360,
              decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300)),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    existing == null ? 'Add Custom Player' : 'Edit Player',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Number',
                      style:
                          TextStyle(fontSize: 10, color: Colors.grey.shade700),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    decoration: BoxDecoration(),
                    child: TextField(
                      controller: numberController,
                      autofocus: true,
                      style: const TextStyle(fontSize: 11),
                      onChanged: (_) =>
                          setDialogState(() => dialogError = null),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 7),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(3),
                          borderSide: BorderSide(color: Colors.grey.shade400),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(3),
                          borderSide: BorderSide(color: Colors.grey.shade400),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Player Name',
                      style:
                          TextStyle(fontSize: 10, color: Colors.grey.shade700),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    decoration: BoxDecoration(),
                    child: TextField(
                      controller: fullNameController,
                      style: const TextStyle(fontSize: 11),
                      onChanged: (_) =>
                          setDialogState(() => dialogError = null),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 7),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(3),
                          borderSide: BorderSide(color: Colors.grey.shade400),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(3),
                          borderSide: BorderSide(color: Colors.grey.shade400),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    width: double.infinity,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: dialogError == null
                          ? const SizedBox.shrink()
                          : Text(
                              dialogError!,
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.red.shade800,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedGreyButton(
                        label: 'Cancel',
                        fontSize: 11,
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                      const SizedBox(width: 8),
                      ElevatedGreyButton(
                        label: 'Save',
                        fontSize: 11,
                        isPrimary: true,
                        onPressed: () {
                          final jersey = numberController.text.trim();
                          final name = fullNameController.text.trim();
                          if (jersey.isEmpty || name.isEmpty) {
                            setDialogState(() {
                              dialogError =
                                  'Please enter both player number and name.';
                            });
                            return;
                          }
                          if (captionState != null) {
                            final conflict = (captionState as dynamic)
                                .jerseyConflictMessageForPlayerEdit(
                              isHome: isHome,
                              existing: existing,
                              jerseyNumber: jersey,
                            ) as String?;
                            if (conflict != null) {
                              setDialogState(() => dialogError = conflict);
                              return;
                            }
                          }
                          Navigator.of(ctx)
                              .pop({'jersey': jersey, 'fullName': name});
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (!mounted || result == null) return;
    final jersey = (result['jersey'] ?? '').trim();
    final fullName = (result['fullName'] ?? '').trim();
    if (jersey.isEmpty || fullName.isEmpty) return;

    final replacement = Player(
      fullName: fullName,
      firstName: fullName.split(' ').first,
      jerseyNumber: jersey,
      displayName: _displayNameForPlayer(fullName, jersey),
    );

    if (captionState != null) {
      try {
        (captionState as dynamic).applyPlayerRosterEdit(
          isHome: isHome,
          existing: existing,
          replacement: replacement,
        );
      } catch (_) {}
    }

    if (mounted) {
      setState(_syncRostersFromWidget);
    }

    if (captionState != null) {
      try {
        captionState.updateCaptionFromKeyboardFire();
      } catch (_) {}
    }
    _refreshCaptionPreviewLater();
  }

  Future<void> _showPlayerContextMenu({
    required TapDownDetails details,
    required Player player,
    required bool isHome,
  }) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(details.globalPosition, details.globalPosition),
      Offset.zero & overlay.size,
    );
    final action = await showAppContextMenu<String>(
      context: context,
      position: position,
      items: [
        const PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, size: 16),
              SizedBox(width: 8),
              Text('Edit player'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'add',
          child: Row(
            children: [
              const Icon(Icons.person_add, size: 16),
              const SizedBox(width: 8),
              Text('Add custom player to ${isHome ? 'Home' : 'Away'}'),
            ],
          ),
        ),
      ],
    );

    if (action == 'edit') {
      await _showPlayerEditDialog(isHome: isHome, existing: player);
    } else if (action == 'add') {
      await _showPlayerEditDialog(isHome: isHome);
    }
  }

  String _kbRosterNameLabel(Player player) {
    final parts = player.fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return player.fullName;
    final first = parts.first;
    final last = parts.length >= 2 ? parts.sublist(1).join(' ').trim() : '';
    switch (_kbPlayerSortBy) {
      case 'lastname':
        return last.isNotEmpty ? '$last, $first' : first;
      case 'firstname':
        return last.isNotEmpty ? '$first $last' : first;
      default:
        return last.isNotEmpty ? '$first $last' : player.fullName;
    }
  }

  List<Widget> _buildRosterRows(
    List<Player> roster,
    bool isHomeTeam, {
    String? barText,
  }) {
    if (roster.isEmpty) return [];
    final selectedNames = _getSelectedPlayerNames(isHomeTeam);
    final currentNumbers = _parseNumbers(barText ?? '');
    final sorted = _sortedKbRoster(roster);

    return sorted.map((p) {
      final num = p.jerseyNumber ?? '—';
      final raw = p.displayName;
      final displayName = _kbRosterNameLabel(p);
      final jersey = p.jerseyNumber ?? '';
      final isPicked = raw.isNotEmpty && selectedNames.contains(raw);
      final isCurrent = jersey.isNotEmpty &&
          currentNumbers.any((n) => n.trim() == jersey.trim());
      final barQuery = (barText ?? '').trim().toLowerCase();
      final isNumberPrefix = barQuery.isNotEmpty &&
          RegExp(r'^\d+$').hasMatch(barQuery) &&
          jersey.isNotEmpty &&
          jersey.startsWith(barQuery);
      final isNameMatch = barQuery.isNotEmpty &&
          !RegExp(r'^\d+$').hasMatch(barQuery) &&
          (p.fullName.toLowerCase().contains(barQuery) ||
              displayName.toLowerCase().contains(barQuery));
      final rosterKey = jersey.isNotEmpty ? '${isHomeTeam}_$jersey' : null;
      final isHovered = rosterKey != null && _hoveredRosterKey == rosterKey;
      final isSearchMatch = isCurrent || isNameMatch || isNumberPrefix;
      final backgroundColor = isPicked
          ? AppTokens.accentTint
          : (isSearchMatch || isHovered ? AppTokens.canvas : AppTokens.surface);
      final inkCore = InkWell(
        onSecondaryTapDown: (details) => _showPlayerContextMenu(
            details: details, player: p, isHome: isHomeTeam),
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
        child: AnimatedContainer(
          duration: AppTokens.motionFast,
          curve: AppTokens.motionCurve,
          padding: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: backgroundColor,
            border: Border(
              left: BorderSide(
                color: isPicked
                    ? AppTokens.accent
                    : AppTokens.surface.withValues(alpha: 0),
                width: 3,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  num,
                  textAlign: TextAlign.right,
                  style: AppTokens.mono.copyWith(
                    fontSize: 12,
                    color: isPicked ? AppTokens.accent : AppTokens.inkMuted,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  displayName,
                  style: AppTokens.listBody.copyWith(
                    fontSize: 12,
                    color: isPicked ? AppTokens.accentDeep : AppTokens.ink,
                    fontWeight: isPicked ? FontWeight.w600 : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
      return MouseRegion(
        onEnter: rosterKey != null
            ? (_) => setState(() => _hoveredRosterKey = rosterKey)
            : null,
        onExit: rosterKey != null
            ? (_) => setState(() => _hoveredRosterKey = null)
            : null,
        child: SizedBox(height: 20, child: inkCore),
      );
    }).toList();
  }

  /// Roster token for a coaching row: full name then role title (e.g. `John Schneider Manager`),
  /// parallel to players’ `Name #99` but without a `#` code.
  String? _syntheticDisplayTokenForStaffLine(String title, String name) {
    final n = name.trim();
    if (n.isEmpty || n == 'data missing') return null;
    final t = title.trim();
    if (t.isEmpty) return null;
    return '$n $t';
  }

  /// Horizontal rule + **Coaching** title + staff lines, inside the roster scroll view.
  Widget _buildRosterCoachScrollSuffix(bool isHomeTeam) {
    final showCoaching =
        isHomeTeam ? _showHomeCoachingPanel : _showAwayCoachingPanel;
    if (!showCoaching) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(3, 4, 3, 2),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            message: 'Show coaching',
            child: InkWell(
              onTap: () => setState(() {
                if (isHomeTeam) {
                  _showHomeCoachingPanel = true;
                } else {
                  _showAwayCoachingPanel = true;
                }
              }),
              borderRadius: BorderRadius.circular(3),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_off,
                      size: 15,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Coaching',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final lines = isHomeTeam ? _homeStaffDisplay : _awayStaffDisplay;
    final teamName = isHomeTeam ? widget.homeTeamName : widget.awayTeamName;
    final children = <Widget>[
      const SizedBox(height: 6),
      Container(
        height: 1,
        color: Colors.grey.shade300,
      ),
      const SizedBox(height: 5),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'Coaching',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                  height: 1.15,
                ),
              ),
            ),
            Tooltip(
              message: 'Hide coaching',
              child: InkWell(
                onTap: () => setState(() {
                  if (isHomeTeam) {
                    _showHomeCoachingPanel = false;
                  } else {
                    _showAwayCoachingPanel = false;
                  }
                }),
                borderRadius: BorderRadius.circular(3),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Icon(
                    Icons.visibility,
                    size: 16,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 3),
    ];

    if (lines.isEmpty && teamName != null && teamName.trim().isNotEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(3, 0, 3, 3),
          child: Text(
            'Loading…',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    } else {
      for (final e in lines) {
        children.add(
          _buildStaffLineRow(
            isHomeTeam: isHomeTeam,
            title: e['title'] ?? '',
            name: e['name'] ?? '',
          ),
        );
      }
      children.add(const SizedBox(height: 3));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  /// One coaching line: same [TextStyle]s / Row layout as [_buildRosterRows] (jersey column → role, name → name).
  Widget _buildStaffLineRow({
    required bool isHomeTeam,
    required String title,
    required String name,
  }) {
    final synthetic = _syntheticDisplayTokenForStaffLine(title, name);
    final selectedNames = _getSelectedPlayerNames(isHomeTeam);
    final isPicked = synthetic != null && selectedNames.contains(synthetic);
    final rosterKey =
        '${isHomeTeam}_staff_${title.replaceAll(RegExp(r'\s+'), '_')}';
    final isHovered = synthetic != null && _hoveredRosterKey == rosterKey;
    final canToggle = synthetic != null;

    final nameText = name == 'data missing' ? 'data missing' : name;

    String _abbrevTitle(String t) {
      final lower = t.toLowerCase().trim();
      if (lower == 'manager') return 'MGR';
      if (lower == 'pitching coach') return 'PIC';
      if (lower == 'first base coach') return '1BC';
      if (lower == 'third base coach') return '3BC';
      if (lower == 'hitting coach') return 'HIT';
      if (lower == 'bench coach') return 'BNC';
      if (lower == 'bullpen coach') return 'BPC';
      final words = t.split(' ');
      if (words.length >= 2) {
        return words.map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
      }
      return t.substring(0, t.length.clamp(0, 3)).toUpperCase();
    }

    final abbrev = _abbrevTitle(title);
    final titleStyle = AppTokens.monoSmall.copyWith(
      fontSize: 10.5,
      color: isPicked ? AppTokens.accent : AppTokens.inkMuted,
      fontWeight: isPicked ? FontWeight.w500 : FontWeight.w400,
    );
    final nameStyle = AppTokens.listBody.copyWith(
      fontSize: 12,
      color: isPicked
          ? AppTokens.accentDeep
          : (name == 'data missing' ? AppTokens.inkMuted : AppTokens.ink),
      fontWeight: isPicked ? FontWeight.w600 : FontWeight.w400,
      fontStyle: name == 'data missing' ? FontStyle.italic : FontStyle.normal,
    );
    final backgroundColor = isPicked
        ? AppTokens.accentTint
        : (isHovered ? AppTokens.canvas : AppTokens.surface);
    final decoration = BoxDecoration(
      color: backgroundColor,
      border: Border(
        left: BorderSide(
          color: isPicked
              ? AppTokens.accent
              : AppTokens.surface.withValues(alpha: 0),
          width: 3,
        ),
      ),
    );

    final row = Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 20,
            child: Text(
              abbrev,
              textAlign: TextAlign.right,
              style: titleStyle,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              nameText,
              style: nameStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    Widget animatedRow() => AnimatedContainer(
          duration: AppTokens.motionFast,
          curve: AppTokens.motionCurve,
          decoration: decoration,
          child: row,
        );

    if (!canToggle) {
      return SizedBox(
        width: double.infinity,
        height: 20,
        child: animatedRow(),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredRosterKey = rosterKey),
      onExit: (_) => setState(() => _hoveredRosterKey = null),
      child: SizedBox(
        height: 20,
        child: InkWell(
          onTap: () {
            final state = widget.captionState;
            if (state == null) return;
            try {
              (state as dynamic).toggleCoachFromKeyboardFire(
                isHomeTeam: isHomeTeam,
                coachSyntheticDisplayName: synthetic,
              );
            } catch (_) {}
            state.updateCaptionFromKeyboardFire();
            setState(() {});
            _refreshCaptionPreviewLater();
          },
          child: animatedRow(),
        ),
      ),
    );
  }

  /// One cell in the number grid (jersey + last name) or empty decade slot.
  Widget _buildRosterSquareGridCell({
    required Player? player,
    required bool isHomeTeam,
    required Set<String> selectedNames,
  }) {
    const double gridCellHeight = 38;
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
    final nameLabel = _kbRosterNameLabel(player);
    return SizedBox(
      height: gridCellHeight,
      child: Tooltip(
        message: player.fullName,
        waitDuration: const Duration(milliseconds: 250),
        child: GestureDetector(
          onSecondaryTapDown: (details) {
            _showPlayerContextMenu(
                details: details, player: player, isHome: isHomeTeam);
          },
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
              gradient: isPicked ? kFloTealGradientHorizontal : null,
              color: isPicked ? null : Colors.white,
              border: Border.all(
                color: isPicked ? kFloTealDark : Colors.grey.shade300,
                width: isPicked ? 1.5 : 1,
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
                  style: _rosterPlayerTextStyle(
                    color: isPicked ? Colors.white : Colors.black87,
                    fontWeight: isPicked ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                Text(
                  nameLabel,
                  style: _rosterPlayerTextStyle(
                    color: isPicked ? Colors.white : Colors.black87,
                    fontWeight: isPicked ? FontWeight.w600 : null,
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
  Widget _buildRosterSquareGrid(
    List<Player> roster,
    bool isHomeTeam,
  ) {
    if (roster.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(3, 2, 3, 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No players',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
            _buildRosterCoachScrollSuffix(isHomeTeam),
          ],
        ),
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
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(3, 2, 3, 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No players',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
            _buildRosterCoachScrollSuffix(isHomeTeam),
          ],
        ),
      );
    }

    final buckets = byNum.keys.map((j) => j ~/ 10).toSet().toList()
      ..sort(
          (a, b) => _kbPlayerSortAscending ? a.compareTo(b) : b.compareTo(a));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(3, 2, 3, 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int bi = 0; bi < buckets.length; bi++) ...[
            Wrap(
              // Keep each decade (0-9, 10-19, ...) tight as one cluster.
              spacing: 1,
              runSpacing: 1,
              children: [
                for (int i = 0; i < 10; i++) ...[
                  if (byNum[buckets[bi] * 10 +
                          (_kbPlayerSortAscending ? i : 9 - i)] !=
                      null)
                    SizedBox(
                      width: 40,
                      child: _buildRosterSquareGridCell(
                        player: byNum[buckets[bi] * 10 +
                            (_kbPlayerSortAscending ? i : 9 - i)]!,
                        isHomeTeam: isHomeTeam,
                        selectedNames: selectedNames,
                      ),
                    ),
                ],
              ],
            ),
            if (bi != buckets.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Container(
                  height: 1,
                  color: Colors.grey.shade300,
                ),
              ),
            if (bi == buckets.length - 1) const SizedBox(height: 2),
          ],
          if (nonNumeric.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Text(
                'Other',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: _sortedKbRoster(nonNumeric).map((player) {
                final jersey = player.jerseyNumber ?? '?';
                final isPicked = selectedNames.contains(player.displayName);
                final nameLabel = _kbRosterNameLabel(player);
                return GestureDetector(
                  onTap: () {
                    final state = widget.captionState;
                    if (state == null) return;
                    if (isPicked) {
                      (state as dynamic)
                          .removePlayerByJersey(isHomeTeam, jersey);
                    } else {
                      state.addPlayerByJersey(isHomeTeam, jersey);
                    }
                    state.updateCaptionFromKeyboardFire();
                    setState(() {});
                    _refreshCaptionPreviewLater();
                  },
                  child: Container(
                    width: 53,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      gradient: isPicked ? kFloTealGradientHorizontal : null,
                      color: isPicked ? null : Colors.white,
                      border: Border.all(
                        color: isPicked ? kFloTealDark : Colors.grey.shade300,
                        width: isPicked ? 1.5 : 1,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          jersey,
                          style: _rosterPlayerTextStyle(
                            color: isPicked ? Colors.white : Colors.black87,
                            fontWeight:
                                isPicked ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                        Text(
                          nameLabel,
                          style: _rosterPlayerTextStyle(
                            color: isPicked ? Colors.white : Colors.black87,
                            fontWeight: isPicked ? FontWeight.w600 : null,
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
          if (AdminService.isCurrentUserAdminSync())
            _buildAdminRosterCompareAfterPlayers(),
          _buildRosterCoachScrollSuffix(isHomeTeam),
        ],
      ),
    );
  }

  Widget _buildRosterSection(
    String teamLabel,
    List<Player> roster, {
    required bool isHomeTeam,
  }) {
    if (roster.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(3, 2, 3, 1),
          child: Text(
            teamLabel,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF3A3A3A),
              letterSpacing: -0.45,
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _shortcutHelpRow('Tab / ⇧Tab',
                    'Cycle Home → Verbs → Visiting (highlight only; click bar to type)'),
                _shortcutHelpRow('Esc',
                    'Leave the current typing box / clear column highlight'),
                _shortcutHelpRow('⇧⏎', 'Save caption & next image (also ⌘S)'),
                _shortcutHelpRow('⇧⌘⏎',
                    'Save, FTP upload, next image (⇧Ctrl+Enter). Uses active FTP profile.'),
                _shortcutHelpRow(
                    '⌘⇧V', 'Paste previous caption (Ctrl+Shift+V)'),
                _shortcutHelpRow('Ctrl+#',
                    'Hold Ctrl, type a jersey number → home player'),
                _shortcutHelpRow('⌘+# / ⌥+#',
                    'Hold Cmd (or Option), type a jersey number → away player'),
                _shortcutHelpRow('⇧+#',
                    'Hold Shift, press a verb’s number → select that verb'),
                _shortcutHelpRow('⇧+1/2/3',
                    'With RBI/HR chips showing: set RBI or HR type (badges appear while Shift is held)'),
                _shortcutHelpRow('⇧+C',
                    'Toggle celebration (🎉) on the selected verb'),
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
        child: Material(
          color: selected
              ? AppTokens.accentTint
              : AppTokens.surface.withValues(alpha: 0),
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 26,
              height: 22,
              child: Icon(
                icon,
                size: 13,
                color: selected ? AppTokens.accent : AppTokens.inkMuted,
              ),
            ),
          ),
        ),
      );
    }

    final segments = [
      segment(
        selected: !_useSquarePlayerView,
        icon: Icons.format_list_bulleted,
        tooltip: 'List view (names)',
        onTap: () => setState(() => _useSquarePlayerView = false),
      ),
      segment(
        selected: _useSquarePlayerView,
        icon: Icons.grid_view,
        tooltip: 'Number grid: rows 0–9, 10–19, 20–29 … (10 per row)',
        onTap: () => setState(() => _useSquarePlayerView = true),
      ),
    ];
    return Container(
      height: 22,
      decoration: BoxDecoration(
        border: Border.all(color: AppTokens.cardBorder),
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusControl - 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            segments.first,
            Container(
              width: 1,
              height: 22,
              color: AppTokens.cardBorder,
            ),
            segments.last,
          ],
        ),
      ),
    );
  }

  Widget _buildRosterSearchBar({
    required TextEditingController controller,
    required FocusNode focusNode,
    required void Function() onSubmitted,
  }) {
    return SizedBox(
      height: 24,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        cursorHeight: 13,
        cursorColor: AppTokens.accent,
        style: AppTokens.listBody.copyWith(color: AppTokens.ink),
        inputFormatters: const [_MacOptionCharStripper()],
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppTokens.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
            borderSide: const BorderSide(color: AppTokens.cardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
            borderSide: const BorderSide(color: AppTokens.cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
            borderSide: const BorderSide(color: AppTokens.accent),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        keyboardType: TextInputType.text,
        onSubmitted: (_) => onSubmitted(),
      ),
    );
  }

  Widget _buildColumnBar({
    required TextEditingController controller,
    required FocusNode focusNode,
    required void Function() onSubmitted,
    List<TextInputFormatter>? inputFormatters,
    void Function(String)? onChanged,
    Widget? trailing,
  }) {
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      cursorHeight: 13,
      cursorColor: AppTokens.accent,
      style: AppTokens.listBody.copyWith(color: AppTokens.ink),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppTokens.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          borderSide: const BorderSide(color: AppTokens.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          borderSide: const BorderSide(color: AppTokens.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          borderSide: const BorderSide(color: AppTokens.accent),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      keyboardType: TextInputType.text,
      inputFormatters: inputFormatters,
      onSubmitted: (_) => onSubmitted(),
      onChanged: onChanged,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 3, 4, 0),
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

  /// Called externally (e.g. from sidebar) to sync internal keyword state.
  Future<void> setKeywordVerbsEnabled(bool enabled) =>
      _setApplyVerbKeywordsKb(enabled);
  Future<void> setKeywordNamesEnabled(bool enabled) =>
      _setApplyPlayerNamesToKeywordsKb(enabled);

  /// Force Keywords box visibility (Keyword mode master toggle / startup sync).
  Future<void> setKeywordsFieldVisible(bool show) async {
    if (_showKeywordsField != show) {
      setState(() => _showKeywordsField = show);
    }
    try {
      final p = _prefsService ?? await PreferencesService.getInstance();
      _prefsService ??= p;
      await p.saveShowKeywordsField(show);
    } catch (_) {}
    if (show) {
      try {
        (widget.captionState as dynamic).reapplyVerbKeywordsIfEnabled();
      } catch (_) {}
    }
  }

  /// Clears home/away player search bars after save.
  void clearPlayerSearchBars() {
    if (!mounted) return;
    setState(() {
      _homeBarController.clear();
      _awayBarController.clear();
    });
  }

  Future<void> _setApplyVerbKeywordsKb(bool enabled) async {
    if (_applyVerbKeywordsEnabledKb == enabled) {
      if (enabled) {
        try {
          (widget.captionState as dynamic).reapplyVerbKeywordsIfEnabled();
        } catch (_) {}
      }
      return;
    }
    setState(() => _applyVerbKeywordsEnabledKb = enabled);
    try {
      await (widget.captionState as dynamic)
          .setApplyVerbKeywordsEnabled(enabled);
    } catch (_) {
      try {
        await _prefsService?.saveApplyVerbKeywords(enabled);
      } catch (_) {}
    }
  }

  Future<void> _setApplyPlayerNamesToKeywordsKb(bool enabled) async {
    if (_applyPlayerNamesToKeywordsEnabledKb == enabled) return;
    setState(() => _applyPlayerNamesToKeywordsEnabledKb = enabled);
    try {
      await (widget.captionState as dynamic)
          .setApplyPlayerNamesToKeywordsEnabled(enabled);
    } catch (_) {
      try {
        await _prefsService?.saveApplyPlayerNamesToKeywords(enabled);
      } catch (_) {}
    }
  }

  /// Same compact [CustomCheckBox] styling as caption layout date source.
  Widget _kbKeywordToggleRow({
    required bool value,
    required Future<void> Function(bool enabled) onSet,
    required String label,
    required String tooltipMessage,
  }) {
    return Tooltip(
      message: tooltipMessage,
      waitDuration: const Duration(milliseconds: 400),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSet(!value),
            child: _buildKeywordToggleLabel(label, fontSize: 9),
          ),
          const SizedBox(width: 2),
          AppCompactCheckbox(
            value: value,
            onChanged: (v) => onSet(v),
            accentColor: _ftpButtonBlue,
          ),
        ],
      ),
    );
  }

  Widget _buildApplyKeywordsToggleKb() {
    return _kbKeywordToggleRow(
      value: _applyVerbKeywordsEnabledKb,
      onSet: _setApplyVerbKeywordsKb,
      label: 'Keyword Verbs',
      tooltipMessage:
          'When On, choosing a verb adds its keyword presets to the Keywords field.',
    );
  }

  Widget _buildPlayerNamesKeywordsToggleKb() {
    return _kbKeywordToggleRow(
      value: _applyPlayerNamesToKeywordsEnabledKb,
      onSet: _setApplyPlayerNamesToKeywordsKb,
      label: 'Keyword Names',
      tooltipMessage:
          'When On, selected player names are added to Keywords when applying verb keywords.',
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

  Widget _buildRosterColumn(
    String teamLabel,
    List<Player> roster, {
    required bool isHomeTeam,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(3, 2, 3, 3),
        child: _buildRosterSection(teamLabel, roster, isHomeTeam: isHomeTeam),
      ),
    );
  }

  /// Roster list only (no border; caller wraps with bar inside same box).
  /// [barText] is the current bar input; matching rows get grey, committed get blue.
  Widget _buildRosterColumnContent(
    List<Player> roster,
    bool isHomeTeam, {
    String? barText,
  }) {
    final controller =
        isHomeTeam ? _homeRosterScrollController : _awayRosterScrollController;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final currentViewport =
                  _sanitizeKbRosterListViewport(constraints.maxHeight);
              if (isHomeTeam) {
                _lockedHomeRosterListViewportHeight ??= currentViewport;
              } else {
                _lockedAwayRosterListViewportHeight ??= currentViewport;
              }
              return SingleChildScrollView(
                controller: controller,
                padding: floScrollPadding(left: 3, top: 2, bottom: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ..._buildRosterRows(
                      roster,
                      isHomeTeam,
                      barText: barText,
                    ),
                    if (AdminService.isCurrentUserAdminSync())
                      _buildAdminRosterCompareAfterPlayers(),
                  ],
                ),
              );
            },
          ),
        ),
        _buildRosterCoachScrollSuffix(isHomeTeam),
      ],
    );
  }

  Widget _buildRosterPanel({
    required String teamName,
    required List<Player> roster,
    required bool isHomeTeam,
    required TextEditingController searchController,
    required FocusNode searchFocus,
    required void Function() onSearchSubmitted,
  }) {
    return CardContainer(
      headerHeight: 24,
      headerPadding: const EdgeInsets.symmetric(horizontal: 8),
      header: Text(
        teamName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _kbHeaderTitleStyle,
      ),
      trailingHeader: _buildKbAddPlayerIconButton(isHomeTeam),
      child: Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildRosterSearchBar(
                      controller: searchController,
                      focusNode: searchFocus,
                      onSubmitted: onSearchSubmitted,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Transform.translate(
                    offset: const Offset(0, -2),
                    child: _buildPlayerViewModeToggle(),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildKbPlayerSortControls(),
                ),
              ),
              Expanded(
                child: _useSquarePlayerView
                    ? _buildRosterSquareGrid(roster, isHomeTeam)
                    : ValueListenableBuilder<TextEditingValue>(
                        valueListenable: searchController,
                        builder: (_, value, __) => _buildRosterColumnContent(
                          roster,
                          isHomeTeam,
                          barText: value.text,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerbsPanel() {
    return CardContainer(
      headerHeight: 24,
      headerPadding: const EdgeInsets.symmetric(horizontal: 8),
      header: Text(
        'Verbs',
        style: _kbHeaderTitleStyle,
      ),
      child: Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildColumnBar(
                controller: _categoryBarController,
                focusNode: _categoryBarFocus,
                onSubmitted: _onCategoryVerbBarSubmit,
                onChanged: (value) {
                  if (RegExp(r'^\d{2}$').hasMatch(value.trim())) {
                    _onVerbBarInput(value.trim());
                  }
                },
              ),
              const SizedBox(height: 3),
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
    );
  }

  Widget _buildAdminRosterCompareAfterPlayers() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(3, 8, 3, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ElevatedGreyButton(
          label: 'Compare rosters',
          fontSize: 10,
          icon: Icons.compare_arrows,
          isAdmin: true,
          onPressed: () => AdminScreen.open(
            context,
            openRosterCompare: true,
          ),
        ),
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

  Widget _buildVerbKeycap(
    String label, {
    required bool selected,
    bool small = false,
    bool onDark = false,
    bool dimmed = false,
  }) {
    final size = small ? 18.0 : 20.0;
    final textStyle = (small ? AppTokens.monoSmall : AppTokens.mono).copyWith(
      fontSize: small ? 10 : 11,
      color: onDark
          ? AppTokens.surface
          : selected
              ? AppTokens.accentDeep
              : dimmed
                  ? AppTokens.inkMuted.withValues(alpha: 0.55)
                  : AppTokens.inkMuted,
      fontWeight: selected || onDark ? FontWeight.w600 : FontWeight.w400,
      height: 1.0,
    );
    return SizedBox(
      width: size,
      height: size,
      child: Center(child: Text(label, style: textStyle)),
    );
  }

  /// Category list only (no border; caller wraps with bar inside same box).
  /// Hold a row ~500 ms then drag to reorder; quick tap selects.
  Widget _buildCategoryPanelContent({String? barText}) {
    final cats = _verbList;
    final rosterTextSize = _keyboardFireRosterReferenceFontSize();
    if (cats.isEmpty) {
      return Center(
        child: Text('No categories',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
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
          bgColor = const Color(0xFFF2F2F2);
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
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
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
                opacity: isDragging ? 0.35 : 1.0,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(
                        Icons.drag_indicator,
                        size: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    SizedBox(
                      width: 17,
                      child: Text(
                        '$catNum',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: (isSelected || isCurrent)
                              ? Colors.grey.shade900
                              : Colors.grey.shade800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 11,
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
    final rosterTextSize = _keyboardFireRosterReferenceFontSize();
    if (cats.isEmpty) {
      return Center(
        child: Text('No categories',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      );
    }
    // Build flat list: for each category, one header then verb rows only if this one is expanded.
    int totalCount = 0;
    int expandedVerbCount = 0;
    for (int ci = 0; ci < cats.length; ci++) {
      final verbs = (cats[ci]['verbs'] as List<dynamic>?)?.cast<String>() ?? [];
      final isExpanded = _expandedCategoryIndex == ci;
      final nonEmpty = verbs.where((v) => v.trim().isNotEmpty).length;
      if (isExpanded) expandedVerbCount = nonEmpty;
      totalCount += 1 + (isExpanded ? verbs.length : 0);
    }
    // +1 for the custom verb input at the end of the list
    final customVerbIndex = totalCount;
    totalCount += 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final m = _kbCatVerbMetrics(
          listViewportHeight: constraints.maxHeight,
          baseVerbFont: rosterTextSize,
          categoryCount: cats.length,
          expandedVerbCount: expandedVerbCount,
        );
        // Re-check after this build — expand/collapse changes overflow.
        _scheduleCategoriesScrollGutterCheck();
        return Stack(
          key: _categoryReorderStackKey,
          clipBehavior: Clip.none,
          children: [
            NotificationListener<ScrollMetricsNotification>(
              onNotification: (notification) {
                _syncCategoriesScrollGutter(notification.metrics);
                return false;
              },
              child: ListView.builder(
                controller: _categoriesScrollController,
                // Full width when content fits; reserve gutter when scrolling.
                padding: _categoriesListNeedsScrollGutter
                    ? floScrollPadding(top: _kKbCatVerbListTopPad)
                    : const EdgeInsets.only(
                        top: _kKbCatVerbListTopPad, right: 2),
                itemCount: totalCount,
                itemBuilder: (context, flatIndex) {
                  // Custom verb input — last item in the list
                  if (flatIndex == customVerbIndex) {
                    final customVerbPinned = _pinnedCustomVerb != null;
                    final s = m.scale;
                    return Padding(
                      padding: EdgeInsets.fromLTRB(5 * s, 6 * s, 5 * s, 10 * s),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 8 * s),
                          Container(
                            width: double.infinity,
                            height: 1,
                            color: Colors.grey.shade300,
                          ),
                          SizedBox(height: 10 * s),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Custom Verb',
                                style: TextStyle(
                                  fontSize: math.max(9.0, 12 * s),
                                  fontWeight: FontWeight.w500,
                                  height: 1.0,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const Spacer(),
                              Builder(
                                builder: (_) {
                                  final canPin = _customVerbController.text
                                          .trim()
                                          .isNotEmpty ||
                                      _pinnedCustomVerb != null;
                                  final fg = canPin
                                      ? Colors.black87
                                      : Colors.grey.shade500;
                                  return TextButton(
                                    onPressed: canPin
                                        ? () {
                                            final t = _customVerbController.text
                                                .trim();
                                            if (t.isEmpty &&
                                                _pinnedCustomVerb == null) {
                                              return;
                                            }
                                            setState(() {
                                              if (_pinnedCustomVerb != null) {
                                                _pinnedCustomVerb = null;
                                              } else {
                                                _pinnedCustomVerb = t;
                                                _lastCustomVerb = t;
                                                _pinnedVerbCategory = null;
                                                _pinnedVerbIndex = null;
                                              }
                                            });
                                          }
                                        : null,
                                    style: TextButton.styleFrom(
                                      foregroundColor: fg,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 0),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      alignment: Alignment.centerRight,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Transform.translate(
                                          offset: const Offset(0, 1.0),
                                          child: Icon(
                                            _pinnedCustomVerb != null
                                                ? Icons.push_pin
                                                : Icons.push_pin_outlined,
                                            size: 9,
                                            color: fg,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          _pinnedCustomVerb != null
                                              ? 'Unpin'
                                              : 'Pin',
                                          style: TextStyle(
                                            fontSize: 11,
                                            height: 1.0,
                                            fontWeight: FontWeight.w500,
                                            color: fg,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          TextField(
                            controller: _customVerbController,
                            readOnly: customVerbPinned,
                            cursorHeight: 14,
                            cursorColor: customVerbPinned
                                ? Colors.transparent
                                : Colors.black87,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.25,
                              color: customVerbPinned
                                  ? Colors.grey.shade600
                                  : Colors.black87,
                            ),
                            decoration: InputDecoration(
                              hintText: '',
                              isDense: true,
                              filled: customVerbPinned,
                              fillColor: customVerbPinned
                                  ? Colors.grey.shade100
                                  : null,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 7),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(3),
                                borderSide: BorderSide(
                                  color: customVerbPinned
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade300,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(3),
                                borderSide: BorderSide(
                                  color: customVerbPinned
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade300,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius:
                                    const BorderRadius.all(Radius.circular(3)),
                                borderSide: BorderSide(
                                  color: customVerbPinned
                                      ? Colors.grey.shade400
                                      : Colors.black87,
                                  width: 1,
                                ),
                              ),
                            ),
                            onChanged: (value) {
                              final t = value.trim();
                              widget.captionState?.updateCustomVerbFromPopup(t);
                              setState(() {
                                if (t.isNotEmpty) {
                                  _lastCustomVerb = t;
                                  _pickedVerbCategory = null;
                                  _pickedVerbIndex = null;
                                  if (_pinnedCustomVerb != null)
                                    _pinnedCustomVerb = t;
                                } else if (_pinnedCustomVerb != null) {
                                  _pinnedCustomVerb = null;
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: (_lastCustomVerb == null ||
                                      _lastCustomVerb!.trim().isEmpty)
                                  ? null
                                  : () {
                                      _applyCustomVerb(_lastCustomVerb!);
                                    },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                alignment: Alignment.centerLeft,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.history,
                                    size: 12,
                                    color: (_lastCustomVerb == null ||
                                            _lastCustomVerb!.trim().isEmpty)
                                        ? Colors.grey.shade400
                                        : Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Use last custom verb',
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 1.0,
                                      color: (_lastCustomVerb == null ||
                                              _lastCustomVerb!.trim().isEmpty)
                                          ? Colors.grey.shade500
                                          : Theme.of(context)
                                              .colorScheme
                                              .primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                    final verbsCanon = (cat['verbsCanonical'] as List<dynamic>?)
                        ?.cast<String>();
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
                          _categoryDragLastGlobal = e.position;
                          _verbLongPressTimer?.cancel();
                          if (_dragFromVerbCatIndex != null) {
                            setState(() {
                              _dragFromVerbCatIndex = null;
                              _dragFromVerbIndex = null;
                              _dragToVerbCatIndex = null;
                              _dragToVerbIndex = null;
                              _verbDragGhostLocal = null;
                            });
                          }
                          _catLongPressTimer?.cancel();
                          _catLongPressTimer =
                              Timer(const Duration(milliseconds: 500), () {
                            _verbLongPressTimer?.cancel();
                            setState(() {
                              _dragFromVerbCatIndex = null;
                              _dragFromVerbIndex = null;
                              _dragToVerbCatIndex = null;
                              _dragToVerbIndex = null;
                              _verbDragGhostLocal = null;
                              _dragFromCatIndex = ci;
                              _dragToCatIndex = ci;
                              final box = _categoryReorderStackKey
                                  .currentContext
                                  ?.findRenderObject() as RenderBox?;
                              if (box != null &&
                                  box.hasSize &&
                                  _categoryDragLastGlobal != null) {
                                _categoryDragGhostLocal =
                                    box.globalToLocal(_categoryDragLastGlobal!);
                              }
                            });
                          });
                        },
                        onPointerMove: (e) {
                          _categoryDragLastGlobal = e.position;
                          if (_dragFromCatIndex != null) {
                            final box = _categoryReorderStackKey.currentContext
                                ?.findRenderObject() as RenderBox?;
                            setState(() {
                              if (box != null && box.hasSize) {
                                _categoryDragGhostLocal =
                                    box.globalToLocal(e.position);
                              }
                              final target = _catIndexAtGlobalY(e.position.dy);
                              if (target != null && target != _dragToCatIndex) {
                                _dragToCatIndex = target;
                              }
                            });
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
                              _categoryDragGhostLocal = null;
                            });
                          } else if (_dragFromCatIndex == null) {
                            final leavingCi = _expandedCategoryIndex;
                            final collapsing = leavingCi == ci;
                            if (leavingCi != null &&
                                (collapsing || leavingCi != ci)) {
                              final leavingCatNum =
                                  cats[leavingCi]['number'] as int? ??
                                      (leavingCi + 1);
                              _unpickVerbIfInCategory(leavingCatNum);
                            }
                            setState(() {
                              if (collapsing) {
                                _expandedCategoryIndex = null;
                              } else {
                                _expandedCategoryIndex = ci;
                                _selectedCategoryIndex = ci;
                              }
                            });
                          } else {
                            setState(() {
                              _dragFromCatIndex = null;
                              _dragToCatIndex = null;
                              _categoryDragGhostLocal = null;
                            });
                          }
                        },
                        onPointerCancel: (_) {
                          _catLongPressTimer?.cancel();
                          setState(() {
                            _dragFromCatIndex = null;
                            _dragToCatIndex = null;
                            _categoryDragGhostLocal = null;
                          });
                        },
                        child: MouseRegion(
                          cursor: _dragFromCatIndex != null
                              ? SystemMouseCursors.grabbing
                              : SystemMouseCursors.grab,
                          child: AnimatedContainer(
                            key: _catKey(ci),
                            duration: AppTokens.motionFast,
                            curve: AppTokens.motionCurve,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDragging
                                  ? AppTokens.accentTint
                                  : isDragOver
                                      ? AppTokens.canvas
                                      : (isExpanded
                                          ? AppTokens.accent
                                          : AppTokens.surface),
                              border: Border(
                                top: isDragOver
                                    ? const BorderSide(
                                        color: AppTokens.accent,
                                        width: 2,
                                      )
                                    : BorderSide.none,
                                bottom: BorderSide.none,
                              ),
                            ),
                            child: Opacity(
                              opacity: isDragging ? 0.35 : 1.0,
                              child: Row(
                                children: [
                                  _buildVerbKeycap(
                                    '$catNum',
                                    selected: false,
                                    onDark: isExpanded,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: AppTokens.listBody.copyWith(
                                        color: isExpanded
                                            ? AppTokens.surface
                                            : AppTokens.ink,
                                        fontWeight: isExpanded
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        height: 1.0,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  AnimatedRotation(
                                    turns: isExpanded ? 0.25 : 0,
                                    duration: AppTokens.motionFast,
                                    curve: AppTokens.motionCurve,
                                    child: Icon(
                                      Icons.chevron_right,
                                      size: 16,
                                      color: isExpanded
                                          ? AppTokens.surface
                                          : AppTokens.inkMuted,
                                    ),
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
                          final canonVerb =
                              (verbsCanon != null && vi < verbsCanon.length)
                                  ? verbsCanon[vi]
                                  : verb;
                          final verbNum = vi + 1;
                          if (verb.trim().isEmpty) {
                            return SizedBox(height: 8 * m.scale);
                          }
                          final isLastUsed = _lastUsedVerbLabel == verb;
                          final dynamic state = widget.captionState;
                          final isFavorite = state != null &&
                              (state.isFavoriteVerbFromKeyboardFire(verb) ==
                                  true);
                          final verbKey = '${catNum}_$verbNum';
                          final isHovered = _hoveredVerbKey == verbKey;
                          final isPicked = _pickedVerbCategory == catNum &&
                              _pickedVerbIndex == verbNum;
                          final isPinned = _pinnedVerbCategory == catNum &&
                              _pinnedVerbIndex == verbNum;
                          final isActive = isPicked || isPinned;
                          String kbSport = 'baseball';
                          try {
                            kbSport = (state as dynamic).currentSportName
                                    as String? ??
                                'baseball';
                          } catch (_) {}
                          final subOpts = state != null
                              ? (state as dynamic)
                                      .getVerbSubOptionsFromKeyboardFire(verb)
                                  as VerbSubOptions
                              : VerbSubOptions.defaultsFor(verb,
                                  sport: kbSport);
                          final showTagsMenu = isActive &&
                              kbSport == 'baseball' &&
                              VerbSubOptions.legacyTagsSubMenu(canonVerb);
                          final isHomeRun =
                              VerbSubOptions.legacyHomeRunTypeMenu(verb);
                          final isBunts =
                              verb == 'Bunts' || canonVerb == 'Bunts';
                          final showBuntMenu =
                              isActive && isBunts && kbSport == 'baseball';
                          final showRbiMenu =
                              isActive && subOpts.rbiEnabled && !isBunts;
                          final showHomeRunMenu = isActive && isHomeRun;
                          final showBaseMenu = isActive &&
                              VerbSubOptions.legacyBaseSubMenu(verb);
                          // Cele-only strip for customs / non-RBI verbs with celebration on.
                          final showCeleOnlyMenu = isActive &&
                              subOpts.celebrationEnabled &&
                              !showRbiMenu &&
                              !showHomeRunMenu &&
                              !showBaseMenu &&
                              !showTagsMenu &&
                              !showBuntMenu;
                          // RBI / Home Run options sit on a row under the verb.
                          final showRbiInline =
                              showRbiMenu && !showHomeRunMenu;
                          final showHomeRunInline = showHomeRunMenu;

                          int? currentRbi;
                          String? currentAction;
                          String? currentHrType;
                          bool currentBuntSingle = false;
                          if (state != null &&
                              (showRbiInline ||
                                  showHomeRunInline ||
                                  showBuntMenu ||
                                  showHomeRunMenu ||
                                  showCeleOnlyMenu ||
                                  showRbiMenu)) {
                            try {
                              currentRbi =
                                  (state as dynamic).currentRbiCount as int?;
                            } catch (_) {}
                            try {
                              currentAction = (state as dynamic)
                                  .currentHittingAction as String?;
                            } catch (_) {}
                            if (showHomeRunInline || isHomeRun) {
                              try {
                                currentHrType = (state as dynamic)
                                    .currentHomeRunType as String?;
                              } catch (_) {}
                            }
                            if (showBuntMenu) {
                              try {
                                currentBuntSingle = (state as dynamic)
                                        .currentBuntSingle as bool? ??
                                    false;
                              } catch (_) {}
                            }
                          }
                          final showBuntSubExtras = showBuntMenu &&
                              (subOpts.rbiEnabled ||
                                  subOpts.celebrationEnabled);

                          final allowVerbReorder = name != 'Favorites' &&
                              canonVerb.trim().isNotEmpty;
                          final isVerbDragging = allowVerbReorder &&
                              _dragFromVerbCatIndex == ci &&
                              _dragFromVerbIndex == vi;
                          final isVerbDragOver = allowVerbReorder &&
                              _dragFromVerbCatIndex != null &&
                              _dragToVerbCatIndex == ci &&
                              _dragToVerbIndex == vi &&
                              !(_dragFromVerbCatIndex == ci &&
                                  _dragFromVerbIndex == vi);

                          Widget verbRow = MouseRegion(
                            cursor: (allowVerbReorder &&
                                    _dragFromVerbCatIndex == ci &&
                                    _dragFromVerbIndex == vi)
                                ? SystemMouseCursors.grabbing
                                : (allowVerbReorder
                                    ? SystemMouseCursors.grab
                                    : SystemMouseCursors.basic),
                            onEnter: (_) =>
                                setState(() => _hoveredVerbKey = verbKey),
                            onExit: (_) =>
                                setState(() => _hoveredVerbKey = null),
                            child: GestureDetector(
                              onSecondaryTapDown: (TapDownDetails d) {
                                _showVerbContextMenu(
                                    context, d.globalPosition, verb, isFavorite,
                                    catNum: catNum,
                                    verbNum: verbNum,
                                    isPinned: isPinned);
                              },
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTapDown: (TapDownDetails d) {
                                    _verbRowTapConsumedByCmd = false;
                                    if (HardwareKeyboard
                                        .instance.isControlPressed) {
                                      _verbRowTapConsumedByCmd = true;
                                      _showVerbContextMenu(
                                          context,
                                          d.globalPosition,
                                          verb,
                                          isFavorite,
                                          catNum: catNum,
                                          verbNum: verbNum,
                                          isPinned: isPinned);
                                      return;
                                    }
                                    if (HardwareKeyboard
                                        .instance.isMetaPressed) {
                                      _verbRowTapConsumedByCmd = true;
                                      _onVerbTapped(catNum, verbNum,
                                          cmdHeld: true);
                                      return;
                                    }
                                    if (isPicked || isPinned) {
                                      _verbRowTapConsumedByCmd = true;
                                      _onVerbTapped(catNum, verbNum);
                                    }
                                  },
                                  onTap: () {
                                    if (_suppressVerbTapAfterVerbDrag) {
                                      _suppressVerbTapAfterVerbDrag = false;
                                      return;
                                    }
                                    if (_verbRowTapConsumedByCmd) {
                                      _verbRowTapConsumedByCmd = false;
                                      return;
                                    }
                                    if (!HardwareKeyboard
                                            .instance.isMetaPressed &&
                                        !HardwareKeyboard
                                            .instance.isControlPressed) {
                                      _onVerbTapped(catNum, verbNum);
                                    }
                                  },
                                  child: AnimatedContainer(
                                    key: allowVerbReorder
                                        ? _verbRowKey(ci, vi)
                                        : null,
                                    duration: AppTokens.motionFast,
                                    curve: AppTokens.motionCurve,
                                    width: double.infinity,
                                    padding: EdgeInsets.only(
                                      left: 12,
                                      right: 4,
                                      top: (showRbiInline ||
                                              showHomeRunInline ||
                                              showBuntSubExtras)
                                          ? 3
                                          : 2,
                                      bottom: (showRbiInline ||
                                              showHomeRunInline ||
                                              showBuntSubExtras)
                                          ? 0
                                          : 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isPicked
                                          ? AppTokens.accentTint
                                          : (isHovered
                                              ? AppTokens.canvas
                                              : AppTokens.surface),
                                      borderRadius: (showRbiInline ||
                                              showHomeRunInline)
                                          ? const BorderRadius.vertical(
                                              top: Radius.circular(
                                                AppTokens.radiusControl,
                                              ),
                                            )
                                          : ((showBuntSubExtras ||
                                                  showCeleOnlyMenu ||
                                                  showTagsMenu ||
                                                  showBaseMenu)
                                              ? const BorderRadius.vertical(
                                                  top: Radius.circular(
                                                    AppTokens.radiusControl,
                                                  ),
                                                )
                                              : null),
                                      border: Border(
                                        top: isVerbDragOver
                                            ? const BorderSide(
                                                color: AppTokens.accent,
                                                width: 2,
                                              )
                                            : BorderSide.none,
                                        bottom: BorderSide.none,
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        _buildVerbKeycap(
                                          '$verbNum',
                                          selected: isPicked,
                                          small: true,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  verb,
                                                  style: AppTokens
                                                      .secondaryLabel
                                                      .copyWith(
                                                    height: 1.0,
                                                    color: isPicked
                                                        ? AppTokens.accentDeep
                                                        : AppTokens.ink,
                                                    fontWeight: isPicked
                                                        ? FontWeight.w600
                                                        : FontWeight.w400,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (isPinned)
                                                const Padding(
                                                  padding: EdgeInsets.only(
                                                      left: 4),
                                                  child: Icon(
                                                    Icons.push_pin,
                                                    size: 12,
                                                    color: AppTokens.inkMuted,
                                                  ),
                                                ),
                                              if (isLastUsed && !isPinned)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    left: 4,
                                                  ),
                                                  child: Text(
                                                    '← Last used',
                                                    style: AppTokens.microLabel
                                                        .copyWith(
                                                      color:
                                                          AppTokens.inkMuted,
                                                      letterSpacing: 0,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (showBuntMenu && state != null) ...[
                                          const SizedBox(width: 6),
                                          _buildBuntSingleChip(
                                            state,
                                            currentBuntSingle,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );

                          if (isVerbDragging) {
                            verbRow = Opacity(opacity: 0.35, child: verbRow);
                          }

                          final Widget wrappedVerbRow = allowVerbReorder
                              ? _wrapVerbRowForReorder(
                                  ci: ci, vi: vi, child: verbRow)
                              : verbRow;

                          if (!showRbiMenu &&
                              !showHomeRunMenu &&
                              !showBaseMenu &&
                              !showTagsMenu &&
                              !showBuntSubExtras &&
                              !showCeleOnlyMenu) {
                            return wrappedVerbRow;
                          }

                          if (showRbiInline) {
                            if (state == null) return wrappedVerbRow;
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                wrappedVerbRow,
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    3,
                                    6,
                                    5,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: AppTokens.accentTint,
                                    borderRadius: BorderRadius.vertical(
                                      bottom: Radius.circular(
                                        AppTokens.radiusControl,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      if (subOpts.celebrationEnabled) ...[
                                        _buildCelebrationEmojiButton(
                                          state,
                                          subOpts,
                                          currentAction,
                                        ),
                                        const SizedBox(width: 3),
                                      ],
                                      Flexible(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: _buildRbiLabeledControl(
                                                state, currentRbi),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }

                          if (showHomeRunInline) {
                            if (state == null) return wrappedVerbRow;
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                wrappedVerbRow,
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    3,
                                    6,
                                    5,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: AppTokens.accentTint,
                                    borderRadius: BorderRadius.vertical(
                                      bottom: Radius.circular(
                                        AppTokens.radiusControl,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      if (subOpts.celebrationEnabled) ...[
                                        _buildCelebrationEmojiButton(
                                          state,
                                          subOpts,
                                          currentAction,
                                        ),
                                        const SizedBox(width: 3),
                                      ],
                                      Flexible(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: _buildHomeRunTypeControl(
                                                state, currentHrType),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }

                          if (showTagsMenu) {
                            final currentTags =
                                (state as dynamic).currentTagsAction as String?;
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                wrappedVerbRow,
                                _buildTagsSubMenuKb(state, currentTags),
                              ],
                            );
                          }

                          if (showBaseMenu) {
                            final currentBase = (state as dynamic)
                                .currentSelectedBase as String?;
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                wrappedVerbRow,
                                _buildBaseSubMenu(
                                    state, verb, currentBase, subOpts,
                                    contentLeft: m.submenuContentLeft),
                              ],
                            );
                          }

                          // Bunt extras (RBI / celebration) under the title row.
                          // Single chip lives on the Bunts title line.
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              wrappedVerbRow,
                              if (showBuntSubExtras)
                                _buildBuntSubMenu(
                                  state,
                                  currentRbi,
                                  subOpts,
                                )
                              else if (showCeleOnlyMenu)
                                _buildCeleOnlySubMenu(
                                    state, subOpts, currentAction,
                                    contentLeft: m.submenuContentLeft),
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
            ),
            _buildCategoryReorderGhost(constraints.maxWidth),
            _buildVerbReorderGhost(constraints.maxWidth),
          ],
        );
      },
    );
  }

  /// Compact 🎉 toggle + chevron menu for celebration phrases.
  Widget _buildCelebrationEmojiButton(
    dynamic captionState,
    VerbSubOptions subOpts,
    String? currentAction,
  ) {
    final phrases = subOpts.reactionPhraseList;
    if (phrases.isEmpty) return const SizedBox.shrink();

    String? selected;
    for (final p in phrases) {
      if (currentAction != null &&
          currentAction.toLowerCase() == p.toLowerCase()) {
        selected = p;
        break;
      }
    }
    final isActive = selected != null;
    final target = _lastReactionPhrase ?? subOpts.primaryReactionPhrase;
    final showHint = _shiftHintHeld;

    void applyReaction(String? value) {
      try {
        (captionState as dynamic).setHittingActionFromKeyboardFire(value);
      } catch (_) {}
      setState(() {});
      _refreshCaptionPreviewLater();
    }

    Future<void> onArrowTap(BuildContext context) async {
      final box = context.findRenderObject() as RenderBox?;
      if (box == null) return;
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;
      final topLeft = box.localToGlobal(Offset.zero);
      final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero));
      // Drop directly under the chevron; grow right from its left edge.
      final position = RelativeRect.fromLTRB(
        topLeft.dx,
        bottomRight.dy,
        0,
        overlay.size.height - bottomRight.dy,
      );

      final picked = await showMenu<String>(
        context: context,
        position: position,
        color: AppTokens.surface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          side: const BorderSide(color: AppTokens.cardBorder),
        ),
        items: [
          for (final phrase in phrases)
            PopupMenuItem<String>(
              value: phrase,
              height: 26,
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    child: selected != null &&
                            selected.toLowerCase() == phrase.toLowerCase()
                        ? const Icon(
                            Icons.check,
                            size: 12,
                            color: AppTokens.accent,
                          )
                        : null,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    phrase,
                    style: AppTokens.listBody.copyWith(
                      fontSize: 12,
                      fontWeight: selected != null &&
                              selected.toLowerCase() == phrase.toLowerCase()
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: AppTokens.ink,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );

      if (picked == null) return;
      final clear =
          selected != null && selected.toLowerCase() == picked.toLowerCase();
      if (clear) {
        applyReaction(null);
      } else {
        _lastReactionPhrase = picked;
        applyReaction(picked);
      }
    }

    final button = SizedBox(
      height: _kbInlineReactionHeight,
      child: AnimatedContainer(
        duration: AppTokens.motionFast,
        curve: AppTokens.motionCurve,
        decoration: BoxDecoration(
          color: isActive ? AppTokens.accentTint : AppTokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          border: Border.all(
            color: showHint
                ? AppTokens.accent
                : (isActive ? AppTokens.accent : AppTokens.cardBorder),
            width: showHint ? 1.5 : 1,
          ),
          boxShadow: showHint
              ? [
                  BoxShadow(
                    color: AppTokens.accent.withValues(alpha: 0.35),
                    blurRadius: 4,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl - 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: AppTokens.surface.withValues(alpha: 0),
                child: InkWell(
                  onTap: () {
                    if (isActive) {
                      applyReaction(null);
                    } else {
                      _lastReactionPhrase = target;
                      applyReaction(target);
                    }
                  },
                  child: SizedBox(
                    width: _kbInlineReactionHeight,
                    height: _kbInlineReactionHeight,
                    child: Center(
                      // 🎉's ink sits left in its em-box; shift right to look centered.
                      child: Transform.translate(
                        offset: const Offset(2.5, -0.5),
                        child: const Text(
                          '🎉',
                          style: TextStyle(fontSize: 16, height: 1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                width: 1,
                height: _kbInlineReactionHeight,
                color: AppTokens.cardBorder,
              ),
              Builder(
                builder: (arrowCtx) => Material(
                  color: AppTokens.surface.withValues(alpha: 0),
                  child: InkWell(
                    onTap: () => onArrowTap(arrowCtx),
                    child: SizedBox(
                      width: 14,
                      height: _kbInlineReactionHeight,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 14,
                        color:
                            isActive ? AppTokens.accent : AppTokens.inkMuted,
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

    if (!showHint) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          top: -7,
          right: -5,
          child: _buildSubOptionShortcutBadge('C'),
        ),
      ],
    );
  }

  /// Tiny keycap badge shown while Shift is held on verb sub-option chips.
  Widget _buildSubOptionShortcutBadge(String label) {
    return Container(
      height: 14,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTokens.accent,
        borderRadius: BorderRadius.circular(3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: AppTokens.mono.copyWith(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: AppTokens.surface,
          height: 1,
        ),
      ),
    );
  }

  Widget _buildRbiSegmentedControl(
    dynamic captionState,
    int? currentRbi,
  ) {
    const values = [1, 2, 3];
    final showHint = _shiftHintHeld;

    Widget segment(int rbi) {
      final selected = currentRbi == rbi;
      return Material(
        color: selected ? AppTokens.accent : AppTokens.surface,
        child: InkWell(
          onTap: () {
            try {
              (captionState as dynamic)
                  .setRbiFromKeyboardFire(selected ? null : rbi);
            } catch (_) {}
            setState(() {});
            _refreshCaptionPreviewLater();
          },
          child: SizedBox(
            width: _kbRbiSegmentWidth,
            height: _kbInlineReactionHeight,
            child: Center(
              child: Text(
                '$rbi',
                style: AppTokens.mono.copyWith(
                  fontSize: showHint ? 11 : 10,
                  fontWeight:
                      selected || showHint ? FontWeight.w700 : FontWeight.w400,
                  color: selected
                      ? AppTokens.surface
                      : (showHint
                          ? AppTokens.accentDeep
                          : AppTokens.inkSecondary),
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: _kbInlineReactionHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < values.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: _kbInlineReactionHeight,
                color: AppTokens.cardBorder,
              ),
            segment(values[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildRbiLabeledControl(
    dynamic captionState,
    int? currentRbi,
  ) {
    final showHint = _shiftHintHeld;
    return SizedBox(
      height: _kbInlineReactionHeight,
      child: AnimatedContainer(
        duration: AppTokens.motionFast,
        decoration: BoxDecoration(
          color: AppTokens.surface,
          border: Border.all(
            color: showHint ? AppTokens.accent : AppTokens.cardBorder,
            width: showHint ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          boxShadow: showHint
              ? [
                  BoxShadow(
                    color: AppTokens.accent.withValues(alpha: 0.28),
                    blurRadius: 4,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl - 1),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  'RBI',
                  style: AppTokens.microLabel.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: showHint
                        ? AppTokens.accentDeep
                        : AppTokens.inkSecondary,
                    letterSpacing: 0,
                    height: 1,
                  ),
                ),
              ),
              Container(
                width: 1,
                height: _kbInlineReactionHeight,
                color: AppTokens.cardBorder,
              ),
              _buildRbiSegmentedControl(captionState, currentRbi),
            ],
          ),
        ),
      ),
    );
  }

  /// Compact Home Run type segments (1R / 2R / 3R / GS), matching RBI control height.
  Widget _buildHomeRunTypeControl(
    dynamic captionState,
    String? currentType,
  ) {
    const types = ['Solo', 'Two-Run', 'Three-Run', 'Grand Slam'];
    final showHint = _shiftHintHeld;

    Widget segment(String type, int shortcutNum) {
      final selected = currentType == type;
      final label = shortHomeRunTypeLabel(type);
      final body = Material(
        color: selected ? AppTokens.accent : AppTokens.surface,
        child: InkWell(
          onTap: () {
            try {
              (captionState as dynamic).setHomeRunTypeFromKeyboardFire(
                  selected ? null : type);
            } catch (_) {}
            setState(() {});
            _refreshCaptionPreviewLater();
          },
          child: SizedBox(
            width: _kbHomeRunSegmentWidth,
            height: _kbInlineReactionHeight,
            child: Center(
              child: Text(
                label,
                style: AppTokens.mono.copyWith(
                  fontSize: 10,
                  fontWeight:
                      selected || showHint ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? AppTokens.surface
                      : (showHint
                          ? AppTokens.accentDeep
                          : AppTokens.inkSecondary),
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      );
      if (!showHint) return body;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          body,
          Positioned(
            top: -7,
            right: -2,
            child: _buildSubOptionShortcutBadge('$shortcutNum'),
          ),
        ],
      );
    }

    return AnimatedContainer(
      duration: AppTokens.motionFast,
      height: showHint ? _kbInlineReactionHeight + 4 : _kbInlineReactionHeight,
      padding: showHint ? const EdgeInsets.only(top: 4) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: AppTokens.surface,
        border: Border.all(
          color: showHint ? AppTokens.accent : AppTokens.cardBorder,
          width: showHint ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        boxShadow: showHint
            ? [
                BoxShadow(
                  color: AppTokens.accent.withValues(alpha: 0.28),
                  blurRadius: 4,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusControl - 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < types.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  height: _kbInlineReactionHeight,
                  color: AppTokens.cardBorder,
                ),
              segment(types[i], i + 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBuntSingleChip(dynamic captionState, bool buntSingle) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
        onTap: () {
          try {
            (captionState as dynamic)
                .setBuntSingleFromKeyboardFire(!buntSingle);
          } catch (_) {}
          setState(() {});
          _refreshCaptionPreviewLater();
        },
        child: Container(
          height: _kbInlineReactionHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: buntSingle ? AppTokens.accentTint : AppTokens.surface,
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
            border: Border.all(
              color: buntSingle ? AppTokens.accent : AppTokens.cardBorder,
            ),
          ),
          child: Text(
            'Single',
            style: AppTokens.microLabel.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              height: 1,
              color: buntSingle ? AppTokens.accentDeep : AppTokens.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBuntSubMenu(
    dynamic captionState,
    int? currentRbi,
    VerbSubOptions subOpts,
  ) {
    String? currentAction;
    try {
      currentAction = (captionState as dynamic).currentHittingAction as String?;
    } catch (_) {}
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 3, 6, 5),
      decoration: const BoxDecoration(
        color: AppTokens.accentTint,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(AppTokens.radiusControl),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (subOpts.celebrationEnabled) ...[
            _buildCelebrationEmojiButton(
              captionState,
              subOpts,
              currentAction,
            ),
            if (subOpts.rbiEnabled) const SizedBox(width: 3),
          ],
          if (subOpts.rbiEnabled)
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _buildRbiLabeledControl(captionState, currentRbi),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCeleOnlySubMenu(
    dynamic captionState,
    VerbSubOptions subOpts,
    String? currentAction, {
    double contentLeft = _kbSubmenuContentLeft,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(left: contentLeft, right: 8, top: 3, bottom: 4),
      decoration: BoxDecoration(
        color: kFloTealSubmenuFill,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
          left: const BorderSide(color: kFloTealLight, width: 3),
        ),
      ),
      child: SizedBox(
        width: _reactionDropdownWidth,
        child: _buildReactionDropdown(captionState, subOpts, currentAction),
      ),
    );
  }

  /// Wide enough for the compact reaction label, leading icon, and chevron.
  static const double _reactionDropdownWidth = 148;

  /// Verb label indent: left pad (7) + drag icon (11+3) + number column (24).
  static const double _kbVerbLabelIndent = 7 + 11 + 3 + 24;
  static const double _kbSubmenuContentLeft = 0;
  static const double _kbSubmenuChipHeight = 18;
  static const double _kbSubmenuChipFontSize = 9.5;
  static const double _kbSubmenuChipRadius = 3;
  static const double _kbSubmenuChipWidth = 20;
  static const double _kbInlineReactionHeight = 24;
  static const double _kbRbiSegmentWidth = 28;
  static const double _kbHomeRunSegmentWidth = 30;

  /// Full label for the reaction dropdown; sizing is handled by its parent.
  String _reactionChipLabel(String phrase) {
    final p = phrase.trim();
    if (p.isEmpty) return p;
    return '${p[0].toUpperCase()}${p.substring(1).toLowerCase()}';
  }

  /// Reaction phrases are user-configurable and can exceed five options, so a
  /// dropdown remains more appropriate than a fixed segmented control.
  Widget _buildReactionDropdown(
    dynamic captionState,
    VerbSubOptions subOpts,
    String? currentAction, {
    bool inline = false,
    double? width,
  }) {
    final phrases = subOpts.reactionPhraseList;
    if (phrases.isEmpty) return const SizedBox.shrink();

    String? selected;
    for (final p in phrases) {
      if (currentAction != null &&
          currentAction.toLowerCase() == p.toLowerCase()) {
        selected = p;
        break;
      }
    }
    final lastPhrase = _lastReactionPhrase ?? subOpts.primaryReactionPhrase;
    final isActive = selected != null;
    final displayPhrase = selected ?? lastPhrase;
    final triggerLabel = _reactionChipLabel(displayPhrase);
    final chipHeight = inline ? _kbInlineReactionHeight : _kbSubmenuChipHeight;
    final boxDecoration = BoxDecoration(
      color: isActive ? AppTokens.accentTint : AppTokens.surface,
      borderRadius: BorderRadius.circular(AppTokens.radiusControl),
      border: Border.all(
        color: isActive ? AppTokens.accent : AppTokens.cardBorder,
      ),
    );

    void applyReaction(String? value) {
      try {
        (captionState as dynamic).setHittingActionFromKeyboardFire(value);
      } catch (_) {}
      setState(() {});
      _refreshCaptionPreviewLater();
    }

    void onMainTap() {
      final target = _lastReactionPhrase ?? subOpts.primaryReactionPhrase;
      if (isActive &&
          selected != null &&
          selected.toLowerCase() == target.toLowerCase()) {
        applyReaction(null);
        return;
      }
      _lastReactionPhrase = target;
      applyReaction(target);
    }

    Future<void> onArrowTap(BuildContext context) async {
      final box = context.findRenderObject() as RenderBox?;
      if (box == null) return;
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;
      final topLeft = box.localToGlobal(Offset.zero);
      final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero));
      final position = RelativeRect.fromLTRB(
        topLeft.dx,
        bottomRight.dy,
        overlay.size.width - bottomRight.dx,
        overlay.size.height - bottomRight.dy,
      );

      final picked = await showMenu<String>(
        context: context,
        position: position,
        color: AppTokens.surface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          side: const BorderSide(color: AppTokens.cardBorder),
        ),
        items: [
          for (final phrase in phrases)
            PopupMenuItem<String>(
              value: phrase,
              height: 28,
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    child: selected != null &&
                            selected.toLowerCase() == phrase.toLowerCase()
                        ? const Icon(
                            Icons.check,
                            size: 12,
                            color: AppTokens.accent,
                          )
                        : null,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    phrase,
                    style: AppTokens.listBody.copyWith(
                      fontWeight: selected != null &&
                              selected.toLowerCase() == phrase.toLowerCase()
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: AppTokens.ink,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );

      if (picked == null) return;
      final clear =
          selected != null && selected.toLowerCase() == picked.toLowerCase();
      if (clear) {
        applyReaction(null);
      } else {
        _lastReactionPhrase = picked;
        applyReaction(picked);
      }
    }

    return Container(
      width: width ?? double.infinity,
      height: chipHeight,
      decoration: boxDecoration,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusControl - 1),
        child: Row(
          children: [
            Expanded(
              child: Material(
                color: AppTokens.surface.withValues(alpha: 0),
                child: InkWell(
                  onTap: onMainTap,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: inline ? 5 : 7),
                    child: Row(
                      children: [
                        Icon(
                          Icons.celebration_outlined,
                          size: inline ? 11 : 13,
                          color:
                              isActive ? AppTokens.accent : AppTokens.inkMuted,
                        ),
                        SizedBox(width: inline ? 4 : 5),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                triggerLabel,
                                maxLines: 1,
                                style: AppTokens.listBody.copyWith(
                                  fontSize: inline ? 11 : null,
                                  color: isActive
                                      ? AppTokens.accentDeep
                                      : AppTokens.ink,
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  height: 1,
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
            Container(
              width: inline ? 22 : 29,
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: AppTokens.cardBorder),
                ),
              ),
              child: Builder(
                builder: (arrowCtx) => Material(
                  color: AppTokens.surface.withValues(alpha: 0),
                  child: InkWell(
                    onTap: () => onArrowTap(arrowCtx),
                    child: Center(
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: inline ? 13 : 15,
                        color: isActive
                            ? AppTokens.accent
                            : AppTokens.inkMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagsSubMenuKb(dynamic captionState, String? currentAction) {
    final rows = baseballTagsPopupChoiceRows();
    return Container(
      padding: const EdgeInsets.only(left: 36, right: 6, top: 2, bottom: 4),
      decoration: BoxDecoration(
        color: kFloTealSubmenuFill,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
          left: const BorderSide(color: kFloTealLight, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Tag / base detail',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 92,
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final row = rows[i];
                final label = row['label']!;
                final value = row['value']!;
                final isSel = value.isEmpty
                    ? (currentAction == null || currentAction.isEmpty)
                    : currentAction == value;
                return InkWell(
                  onTap: () {
                    try {
                      (captionState as dynamic).applyTagsSubOptionFromPopup(
                        value.isEmpty ? null : value,
                      );
                    } catch (_) {}
                    setState(() {});
                    _refreshCaptionPreviewLater();
                  },
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                    color: isSel ? Colors.blue.shade100 : null,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade900,
                        fontWeight: isSel ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBaseSubMenu(
    dynamic captionState,
    String verb,
    String? currentBase,
    VerbSubOptions subOpts, {
    double contentLeft = _kbSubmenuContentLeft,
  }) {
    final primaryBases = verb == 'Steals'
        ? const ['2nd', '3rd', 'Home']
        : const ['1st', '2nd', '3rd', 'Home'];
    const taggedOutBase = 'Tagged Out';
    final storedBase = (captionState as dynamic).baseBeforeTaggedOut as String?;
    final isTaggedOut = currentBase == 'Tagged Out';
    String? currentAction;
    try {
      currentAction = (captionState as dynamic).currentHittingAction as String?;
    } catch (_) {}

    String kbBaseChipLabel(String base) => base == 'Tagged Out' ? 'Out' : base;

    double kbBaseChipWidth(String base) {
      if (base == 'Home') return 28;
      if (base == 'Tagged Out') return 22;
      return 22;
    }

    Widget baseChip(String base) {
      final isSelected = currentBase == base;
      final isStoredBase =
          isTaggedOut && base != 'Tagged Out' && storedBase == base;

      final Color bgColor;
      final Color borderColor;
      final Color textColor;
      if (isSelected) {
        if (base == 'Tagged Out') {
          bgColor = const Color(0xFFE53935);
          borderColor = bgColor;
        } else {
          bgColor = Colors.transparent;
          borderColor = kFloTealDark;
        }
        textColor = Colors.white;
      } else if (isStoredBase) {
        bgColor = kFloTealLight.withValues(alpha: 0.15);
        borderColor = kFloTealLight;
        textColor = kFloTealDark;
      } else {
        bgColor = Colors.white;
        borderColor = Colors.grey.shade300;
        textColor = Colors.grey.shade800;
      }

      final w = kbBaseChipWidth(base);

      return Padding(
        padding: const EdgeInsets.only(right: 5),
        child: InkWell(
          borderRadius: BorderRadius.circular(_kbSubmenuChipRadius),
          onTap: () {
            try {
              (captionState as dynamic).setBaseFromKeyboardFire(base);
            } catch (_) {}
            setState(() {});
            _refreshCaptionPreviewLater();
          },
          child: Container(
            width: w,
            height: _kbSubmenuChipHeight,
            alignment: Alignment.center,
            decoration: isSelected && base != 'Tagged Out'
                ? floTealSelectedDecoration(
                    borderRadius: BorderRadius.circular(_kbSubmenuChipRadius),
                  )
                : BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(_kbSubmenuChipRadius),
                    border: Border.all(color: borderColor),
                  ),
            child: Text(
              kbBaseChipLabel(base),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: _kbSubmenuChipFontSize,
                fontWeight: FontWeight.w600,
                height: 1.0,
                color: textColor,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(left: contentLeft, right: 8, top: 3, bottom: 4),
      decoration: BoxDecoration(
        color: kFloTealSubmenuFill,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
          left: const BorderSide(color: kFloTealLight, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: primaryBases.map(baseChip).toList(),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              baseChip(taggedOutBase),
              if (subOpts.celebrationEnabled) ...[
                const SizedBox(width: 4),
                SizedBox(
                  width: _reactionDropdownWidth,
                  child: _buildReactionDropdown(
                      captionState, subOpts, currentAction),
                ),
              ],
            ],
          ),
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

    showAppContextMenu<String>(
      context: context,
      position: appContextMenuPosition(context, position),
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
    final rosterTextSize = _keyboardFireRosterReferenceFontSize();
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
        : ListView.builder(
            controller: _verbsScrollController,
            padding: floScrollPadding(),
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
              final bgDecoration = isPicked
                  ? BoxDecoration(
                      gradient: kFloTealGradientHorizontalLight,
                      border: Border(
                        left: const BorderSide(color: kFloTealLight, width: 3),
                        bottom:
                            BorderSide(color: Colors.grey.shade100, width: 0.5),
                      ),
                    )
                  : BoxDecoration(
                      color: isCurrent ? Colors.grey.shade200 : null,
                      border: Border(
                        bottom:
                            BorderSide(color: Colors.grey.shade100, width: 0.5),
                      ),
                    );
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
                    if (HardwareKeyboard.instance.isControlPressed) {
                      _verbRowTapConsumedByCmd = true;
                      _showVerbContextMenu(
                          context, d.globalPosition, verb, isFavorite);
                      return;
                    }
                    if (HardwareKeyboard.instance.isMetaPressed) {
                      _verbRowTapConsumedByCmd = true;
                      _onVerbTapped(selectedCatNum!, verbNum, cmdHeld: true);
                      return;
                    }
                    if (isPicked) {
                      _verbRowTapConsumedByCmd = true;
                      _onVerbTapped(selectedCatNum!, verbNum);
                    }
                  },
                  onTap: () {
                    if (_verbRowTapConsumedByCmd) {
                      _verbRowTapConsumedByCmd = false;
                      return;
                    }
                    if (!HardwareKeyboard.instance.isMetaPressed &&
                        !HardwareKeyboard.instance.isControlPressed) {
                      _onVerbTapped(selectedCatNum!, verbNum);
                    }
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    decoration: bgDecoration,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            '$verbNum',
                            style: TextStyle(
                              fontSize: rosterTextSize,
                              fontWeight: FontWeight.w600,
                              color: isPicked
                                  ? kFloTealDark
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
                                    fontSize: rosterTextSize,
                                    color: isPicked
                                        ? kFloTealDark
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
          );
  }

  static const LinearGradient _btnGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF4A7A96), Color(0xFF2A4858)],
  );

  Widget _btn({
    required Widget child,
    required VoidCallback? onTap,
    void Function(TapDownDetails)? onTapDown,
    Color? bg,
    bool useGradient = false,
    double width = 60,
  }) {
    final enabled = onTap != null;
    final color = useGradient
        ? null
        : (bg ?? (enabled ? Colors.grey.shade100 : Colors.grey.shade200));
    final borderColor = useGradient
        ? Colors.transparent
        : (enabled ? Colors.grey.shade300 : Colors.grey.shade400);
    return SizedBox(
      width: width,
      height: 28,
      child: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: InkRipple.splashFactory,
          highlightColor: useGradient
              ? Colors.white.withOpacity(0.15)
              : Colors.black.withOpacity(0.06),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTapDown: enabled ? onTapDown : null,
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.zero,
            splashColor: useGradient
                ? Colors.white.withOpacity(0.25)
                : Colors.black.withOpacity(0.08),
            highlightColor: useGradient
                ? Colors.white.withOpacity(0.15)
                : Colors.black.withOpacity(0.05),
            child: Ink(
              decoration: BoxDecoration(
                color: color,
                gradient: useGradient ? _btnGradient : null,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
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
  static const Color _panelBackgroundLight = Colors.white;

  Widget _buildFtpButtonWithContextMenu() {
    return SizedBox(
      width: double.infinity,
      height: 28,
      child: GestureDetector(
        onSecondaryTapDown: widget.onFtpSettings != null
            ? (TapDownDetails details) {
                showAppContextMenu<String>(
                  context: context,
                  position:
                      appContextMenuPosition(context, details.globalPosition),
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
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF4A7A96), Color(0xFF2A4858)],
                  ),
                  borderRadius: BorderRadius.zero,
                  border: Border.all(color: const Color(0xFF4A7A96)),
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

    final saveW = _saveActionBarBtnWidth().toDouble();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFFE6E6E6), width: 0.7),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            // ← Save Prev
            _btn(
              width: saveW,
              useGradient: true,
              onTap: hasPrev
                  ? () async {
                      if (widget.onSaveIptc != null) widget.onSaveIptc!();
                      widget.onPreviousImage?.call();
                    }
                  : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.chevron_left, size: 12, color: Colors.white),
                  const SizedBox(width: 2),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(_bulkSaveLabel(),
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                ],
              ),
            ),
            // Save → Next
            _btn(
              width: saveW,
              useGradient: true,
              onTap: hasNext
                  ? () async {
                      if (widget.onSaveIptc != null) widget.onSaveIptc!();
                      widget.onNextImage?.call();
                    }
                  : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(_bulkSaveLabel(),
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.chevron_right,
                      size: 12, color: Colors.white),
                ],
              ),
            ),
            // Paste
            _btn(
              width: 55,
              useGradient: true,
              onTap: widget.onPaste,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.content_paste, size: 12, color: Colors.white),
                  SizedBox(width: 2),
                  Text('Paste',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            // Paste Prev
            _btn(
              width: 90,
              useGradient: true,
              onTap: widget.onPastePrevious,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 12, color: Colors.white),
                  SizedBox(width: 2),
                  Text('Paste Prev',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            // FTP Settings
            _btn(
              width: 100,
              useGradient: true,
              onTap: widget.onFtpSettings,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.settings, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text('FTP Settings',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.white)),
                ],
              ),
            ),
            // Reset
            _btn(
              width: 60,
              useGradient: true,
              onTapDown: (d) => _resetCaptionTapAnchor = d.globalPosition,
              onTap: _onResetPressed,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh, size: 12, color: Colors.white),
                  SizedBox(width: 2),
                  Text('Reset Caption',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
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
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
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
                  borderRadius: BorderRadius.circular(3),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
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

    final pinnedClassic =
        _pinnedVerbCategory != null && _pinnedVerbIndex != null;
    final pinnedCustom = (_pinnedCustomVerb?.trim().isNotEmpty ?? false);
    if (pinnedClassic || pinnedCustom) {
      final verbLabel = pinnedClassic
          ? (_verbLabelForCategoryAndVerb(
                _pinnedVerbCategory!,
                _pinnedVerbIndex!,
              ) ??
              'verb')
          : (_pinnedCustomVerb!.trim());
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
      _pinnedCustomVerb = null;
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

  /// "MLB timestamp" labeled switch. Same three-state behavior as the legacy
  /// button: off → enable + run matching; on + matched → disable; on without a
  /// match → rerun matching.
  Widget _buildMlbTimestampToggle() {
    final cs = widget.captionState;
    if (cs == null) return const SizedBox.shrink();

    ValueListenable<int>? revision;
    try {
      revision = (cs as dynamic).mlbClockUiRevision as ValueListenable<int>?;
    } catch (_) {}
    if (revision == null) return const SizedBox.shrink();

    return ValueListenableBuilder<int>(
      valueListenable: revision,
      builder: (context, _, __) {
        bool enabled = false;
        bool matched = false;
        try {
          enabled = (cs as dynamic).mlbInningFromClockEnabled as bool? ?? false;
          matched =
              (cs as dynamic).showMlbInningFromClockIndicator as bool? ?? false;
        } catch (_) {}

        void onTap() {
          try {
            final dyn = cs as dynamic;
            if (enabled && matched) {
              dyn.setMlbInningFromClockEnabled(false);
            } else {
              dyn.applyMlbInningFromExifClock(userInitiated: true);
            }
          } catch (_) {}
          setState(() {});
        }

        return Tooltip(
          message: !enabled
              ? 'MLB Time Stamp is off. Tap to turn on and set inning from '
                  'EXIF.'
              : matched
                  ? 'Inning set from MLB play-by-play vs this photo’s EXIF '
                      'time. Tap to turn off.'
                  : 'Set inning from MLB play-by-play using EXIF time, game '
                      'date, and teams. Tap to run or refresh; tap again '
                      'after a match to turn off.',
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'MLB timestamp',
                    style: AppTokens.secondaryLabel.copyWith(
                      color: AppTokens.inkSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: AppTokens.motionFast,
                    curve: AppTokens.motionCurve,
                    width: 34,
                    height: 18,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: enabled ? AppTokens.accent : AppTokens.cardBorder,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: AnimatedAlign(
                      duration: AppTokens.motionFast,
                      curve: AppTokens.motionCurve,
                      alignment: enabled
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: AppTokens.surface,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
    final isBasketball = SportVerbCategories.usesBasketballRules(sport);
    final isBaseball = sport == 'baseball';
    final isSoccer = sport == 'soccer';
    final periodLabels = isBasketball
        ? (_showPlayoffOvertimes
            ? ['Pre-Game', '2OT', '3OT', '4OT', '5OT', 'Post Game']
            : ['Pre-Game', 'Q1', 'Q2', 'Q3', 'Q4', 'OT', '1H', '2H'])
        : (_showPlayoffOvertimes
            ? ['Pre-Game', '1OT', '2OT', '3OT', '4OT', '5OT']
            : ['Pre-Game', '1', '2', '3', 'OT', 'SO']);
    final selected = _getSelectedPeriod();

    final String headerLabel = isBasketball
        ? 'Quarter'
        : (isBaseball ? 'Inning' : (isSoccer ? 'Half' : 'Period'));

    if (isBaseball) {
      ValueListenable<int>? revision;
      try {
        revision = (widget.captionState as dynamic).mlbClockUiRevision
            as ValueListenable<int>?;
      } catch (_) {}

      Widget buildBaseballInningStrip() {
        final page = _baseballInningPage.clamp(0, 2);
        final startInning = page * 9 + 1;
        final inningNums = List<int>.generate(
            9, (i) => startInning + i); // 1–9, 10–18, or 19–27
        final selInning = _getSelectedRbiInning();
        final selectedPeriod = _getSelectedPeriod();
        // Keep the visible page on the MLB-/user-selected inning.
        final matched = selInning;
        if (matched != null && matched >= 1 && matched <= 27) {
          final neededPage = ((matched - 1) ~/ 9).clamp(0, 2);
          if (neededPage != page) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (_baseballInningPage != neededPage) {
                setState(() => _baseballInningPage = neededPage);
              }
            });
          }
        }

        TextStyle segStyle(bool isSelected) => TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? AppTokens.surface : AppTokens.ink,
              height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
            );

        Widget segment({
          required bool isSelected,
          required VoidCallback? onTap,
          required Widget child,
          double? width,
        }) {
          return Material(
            color: isSelected
                ? AppTokens.accent
                : AppTokens.surface.withValues(alpha: 0),
            child: InkWell(
              onTap: onTap,
              child: Container(
                width: width,
                height: kFloInningButtonHeight,
                alignment: Alignment.center,
                padding: width == null
                    ? const EdgeInsets.symmetric(horizontal: 8)
                    : null,
                child: child,
              ),
            ),
          );
        }

        final segments = <Widget>[
          segment(
            isSelected: selectedPeriod == 'Pre-Game',
            onTap: () => _onPeriodSelect('Pre-Game'),
            child: Text('Pre-Game',
                style: segStyle(selectedPeriod == 'Pre-Game')),
          ),
          for (final n in inningNums)
            segment(
              width: 26,
              isSelected: selInning == n,
              onTap: () => _onInningSelect(selInning == n ? null : n),
              child: Text('$n', style: segStyle(selInning == n)),
            ),
          segment(
            width: 26,
            isSelected: false,
            onTap: page > 0
                ? () => setState(() {
                      _baseballInningPage =
                          (_baseballInningPage - 1).clamp(0, 2);
                    })
                : null,
            child: Icon(
              Icons.remove,
              size: 12,
              color: page > 0 ? AppTokens.inkSecondary : AppTokens.inkMuted,
            ),
          ),
          segment(
            width: 26,
            isSelected: false,
            onTap: page < 2
                ? () => setState(() {
                      _baseballInningPage =
                          (_baseballInningPage + 1).clamp(0, 2);
                    })
                : null,
            child: Icon(
              Icons.add,
              size: 12,
              color: page < 2 ? AppTokens.inkSecondary : AppTokens.inkMuted,
            ),
          ),
          segment(
            isSelected: selectedPeriod == 'Post Game',
            onTap: () => _onPeriodSelect('Post Game'),
            child: Text('Post Game',
                style: segStyle(selectedPeriod == 'Post Game')),
          ),
        ];

        final segmentedControl = Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppTokens.cardBorder),
            borderRadius: BorderRadius.circular(AppTokens.radiusControl),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTokens.radiusControl - 1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < segments.length; i++) ...[
                  if (i > 0)
                    Container(
                      width: 1,
                      height: kFloInningButtonHeight,
                      color: AppTokens.cardBorder,
                    ),
                  segments[i],
                ],
              ],
            ),
          ),
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: CardContainer(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  headerLabel,
                  style: _kbHeaderTitleStyle,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: segmentedControl,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildMlbTimestampToggle(),
              ],
            ),
          ),
        );
      }

      // Rebuild the inning strip when MLB async matching updates selection —
      // otherwise the highlight stays stale until a manual toggle.
      if (revision != null) {
        return ValueListenableBuilder<int>(
          valueListenable: revision,
          builder: (context, _, __) => buildBaseballInningStrip(),
        );
      }
      return buildBaseballInningStrip();
    }

    TextStyle periodSegmentStyle(bool isSelected) => TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? AppTokens.surface : AppTokens.ink,
          height: 1.0,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    Widget periodSegment({
      required bool isSelected,
      required VoidCallback onTap,
      required Widget child,
      double? width,
    }) {
      return Material(
        color: isSelected
            ? AppTokens.accent
            : AppTokens.surface.withValues(alpha: 0),
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: width,
            height: kFloInningButtonHeight,
            alignment: Alignment.center,
            padding: width == null
                ? const EdgeInsets.symmetric(horizontal: 8)
                : null,
            child: child,
          ),
        ),
      );
    }

    final labels = isSoccer
        ? const ['Pre-Game', '1H', '2H', 'ET', 'Pens']
        : periodLabels.where((label) => label != 'Post Game').toList();
    final segments = <Widget>[
      for (final label in labels)
        periodSegment(
          isSelected: selected == label,
          onTap: () => _onPeriodSelect(label),
          child: Text(
            label,
            style: periodSegmentStyle(selected == label),
          ),
        ),
      if (!isSoccer)
        periodSegment(
          width: 26,
          isSelected: _showPlayoffOvertimes,
          onTap: () => setState(
            () => _showPlayoffOvertimes = !_showPlayoffOvertimes,
          ),
          child: Icon(
            _showPlayoffOvertimes ? Icons.remove : Icons.add,
            size: 12,
            color: _showPlayoffOvertimes
                ? AppTokens.surface
                : AppTokens.inkSecondary,
          ),
        ),
      periodSegment(
        isSelected: selected == 'Post Game',
        onTap: () => _onPeriodSelect('Post Game'),
        child: Text(
          'Post Game',
          style: periodSegmentStyle(selected == 'Post Game'),
        ),
      ),
    ];

    final segmentedControl = Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTokens.cardBorder),
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusControl - 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < segments.length; i++) ...[
              if (i > 0)
                Container(
                  width: 1,
                  height: kFloInningButtonHeight,
                  color: AppTokens.cardBorder,
                ),
              segments[i],
            ],
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: CardContainer(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              headerLabel,
              style: _kbHeaderTitleStyle,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: segmentedControl,
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
                                  ? _homeRosterView
                                  : _awayRosterView)
                              : (_firebarHv == 'H'
                                  ? _awayRosterView
                                  : _homeRosterView);
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
          // Fit three caption lines (12px × 1.5 = 18) plus card chrome:
          // 24px header + 12px body padding + 2px borders,
          // Longer captions scroll in-field.
          height: 38 +
              (3 * 18) +
              (_keywordsBoxVisible || _showHeadlineField ? 44 : 0),
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
                child: _wrapShortcutPanelHighlight(
                  panel: _KbShortcutPanel.home,
                  active: _shortcutPanel == _KbShortcutPanel.home,
                  child: _buildRosterPanel(
                    teamName: homeName,
                    roster: _homeRosterView,
                    isHomeTeam: true,
                    searchController: _homeBarController,
                    searchFocus: _homeBarFocus,
                    onSearchSubmitted: _onHomeBarSubmit,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // ── 2: Categories + verbs (one bar: 2 digits = cat + verb) ───
              Expanded(
                child: _wrapShortcutPanelHighlight(
                  panel: _KbShortcutPanel.verbs,
                  active: _shortcutPanel == _KbShortcutPanel.verbs,
                  child: _buildVerbsPanel(),
                ),
              ),
              const SizedBox(width: 8),
              // ── 3: Away roster (title, then box: number bar + list) ───────
              Expanded(
                child: _wrapShortcutPanelHighlight(
                  panel: _KbShortcutPanel.away,
                  active: _shortcutPanel == _KbShortcutPanel.away,
                  child: _buildRosterPanel(
                    teamName: awayName,
                    roster: _awayRosterView,
                    isHomeTeam: false,
                    searchController: _awayBarController,
                    searchFocus: _awayBarFocus,
                    onSearchSubmitted: _onAwayBarSubmit,
                  ),
                ),
              ),
              // Trailing sidebar injected from parent (e.g. save/ftp buttons)
              if (widget.trailingSidebar != null) ...[
                const SizedBox(width: 6),
                widget.trailingSidebar!,
              ],
            ],
          ),
        ),
        if (widget.showDialogActions) ...[
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedGreyButton(
                label: 'Cancel',
                fontSize: 13,
                onPressed: () => Navigator.of(context).pop(),
              ),
              if (onPrimary != null) ...[
                const SizedBox(width: 8),
                ElevatedGreyButton(
                  label: primaryLabel,
                  fontSize: 13,
                  isPrimary: true,
                  onPressed: () {
                    if (_step == 0)
                      _onStep1Submit();
                    else if (_step == 1)
                      _onStep2Submit();
                    else if (_step == 2) _done();
                  },
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
          : const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color:
            widget.showDialogActions ? Colors.white : const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.zero,
        border: widget.showDialogActions
            ? Border.all(color: Colors.grey.shade400)
            : null,
      ),
      child: Shortcuts.manager(
        manager: _FirebarShortcutManager(shortcuts: _kFirebarShortcuts),
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
  final int? bulkSaveCount;

  const KeyboardFireDialog({
    super.key,
    required this.homeRoster,
    required this.awayRoster,
    this.homeTeamName,
    this.awayTeamName,
    required this.captionState,
    this.bulkSaveCount,
  });

  @override
  Widget build(BuildContext context) {
    return KeyboardFirePanel(
      homeRoster: homeRoster,
      awayRoster: awayRoster,
      homeTeamName: homeTeamName,
      awayTeamName: awayTeamName,
      captionState: captionState,
      bulkSaveCount: bulkSaveCount,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      backgroundColor: Colors.grey.shade50,
      child: Container(
        width: 360,
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(3),
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
                  )),
              child: Row(
                children: [
                  Icon(Icons.label_outline, size: 11, color: Colors.black54),
                  const SizedBox(width: 4),
                  Text(
                    widget.isEdit
                        ? 'Edit Keyword Shortcut'
                        : 'Add Keyword Shortcut',
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
                      hint: 'e.g. c, TPX, sport', focusNode: _labelFocus),

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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
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
                        const SizedBox(height: 6),
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
                                  border:
                                      Border.all(color: Colors.grey.shade400),
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
                            if (label.isNotEmpty) const SizedBox(width: 6),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(3)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: BorderSide(color: Colors.grey.shade400),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(3),
          borderSide: const BorderSide(color: Color(0xFF1976D2), width: 1.5),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}

/// Scaled category/verb row metrics for Keyboard Fire (current sizes = max).
class _KbCatVerbMetrics {
  const _KbCatVerbMetrics({
    required this.scale,
    required this.catPadH,
    required this.catPadV,
    required this.catFont,
    required this.catIcon,
    required this.catNumW,
    required this.verbPadT,
    required this.verbPadB,
    required this.verbPadLReorder,
    required this.verbPadLPlain,
    required this.verbPadR,
    required this.verbFont,
    required this.verbNumFont,
    required this.verbIcon,
    required this.verbNumW,
    required this.submenuContentLeft,
  });

  final double scale;
  final double catPadH;
  final double catPadV;
  final double catFont;
  final double catIcon;
  final double catNumW;
  final double verbPadT;
  final double verbPadB;
  final double verbPadLReorder;
  final double verbPadLPlain;
  final double verbPadR;
  final double verbFont;
  final double verbNumFont;
  final double verbIcon;
  final double verbNumW;
  final double submenuContentLeft;
}

/// Keeps stray macOS Option+digit characters (¡™£¢∞…) out of the search bars.
class _MacOptionCharStripper extends TextInputFormatter {
  const _MacOptionCharStripper();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    for (final char in _kMacOptionDigitChars.keys) {
      text = text.replaceAll(char, '');
    }
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
