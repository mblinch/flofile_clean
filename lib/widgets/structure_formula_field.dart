import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../caption_style/date_formula.dart';
import '../caption_style/structure_formula.dart';
import '../theme/ff_tokens.dart';
import 'app_styled_dialogs.dart';
import 'ff_menu.dart';

/// Compact label for a date-part optionIndex on a Structure chip.
String structureDateFormatChipLabel(DateFieldKind kind, int optionIndex) {
  final opts = kDateFieldOptions[kind]!;
  final i = optionIndex.clamp(0, opts.length - 1);
  switch (kind) {
    case DateFieldKind.month:
      switch (i) {
        case 0:
          return 'Long';
        case 1:
          return 'Short';
        case 2:
          return 'Num';
        case 3:
          return '00';
        default:
          return opts[i].label;
      }
    case DateFieldKind.weekday:
      switch (i) {
        case 0:
          return 'Long';
        case 1:
          return 'Short';
        default:
          return opts[i].label;
      }
    case DateFieldKind.day:
    case DateFieldKind.year:
      return opts[i].label;
  }
}

/// Next format optionIndex for [kind] (cycles through [kDateFieldOptions]).
int structureDateFormatNextIndex(DateFieldKind kind, int optionIndex) {
  final opts = kDateFieldOptions[kind]!;
  final i = optionIndex.clamp(0, opts.length - 1);
  return (i + 1) % opts.length;
}

/// Hover target for one variable slot in the formula / preview.
///
/// [slot] is the 0-based index among all variable chips left-to-right, so two
/// State fields (e.g. `{dl_state}` then `{state}`) stay distinct.
class StructureHoverRef {
  const StructureHoverRef(this.slot, {this.key = ''});
  final int slot;
  final String key;

  @override
  bool operator ==(Object other) =>
      other is StructureHoverRef && other.slot == slot;

  @override
  int get hashCode => slot;
}

/// Contenteditable-style structure formula editor.
///
/// Variables are single private-use placeholder characters painted as chips;
/// literals are normal editable text between them.
class StructureFormulaField extends StatefulWidget {
  const StructureFormulaField({
    super.key,
    required this.formula,
    required this.onChanged,
    this.hoverRef,
    this.onHoverRef,
    this.onChipTap,
    this.enabled = true,
    this.expands = false,
    this.monthOptionByOccurrence,
    this.weekdayOptionByOccurrence,
    this.onDatePartOptionChanged,
  });

  final String formula;
  final ValueChanged<String> onChanged;
  final StructureHoverRef? hoverRef;
  final ValueChanged<StructureHoverRef?>? onHoverRef;

  /// Primary click on the chip body (not AA / format controls).
  final ValueChanged<String>? onChipTap;
  final bool enabled;

  /// When true, fill the parent and scroll inside the field (needs a
  /// bounded-height parent such as [Expanded]).
  final bool expands;

  /// Per-occurrence [DateFieldToken.optionIndex] for Month chips.
  final List<int>? monthOptionByOccurrence;

  /// Per-occurrence [DateFieldToken.optionIndex] for Weekday chips.
  final List<int>? weekdayOptionByOccurrence;

  /// Fired when the user cycles format on a Month / Weekday chip.
  final void Function(DateFieldKind kind, int occurrenceIndex, int optionIndex)?
      onDatePartOptionChanged;

  @override
  State<StructureFormulaField> createState() => StructureFormulaFieldState();
}

class StructureFormulaFieldState extends State<StructureFormulaField> {
  static const int _tokenBase = 0xE000;

  late final _FormulaEditingController _controller;
  late final FocusNode _focus;
  final Map<int, String> _tokenKeys = {};
  int _nextTokenCode = 0;
  bool _syncing = false;
  /// True while a chip secondary-click menu is active so the text toolbar
  /// does not stack on top of Remove.
  bool _suppressContextMenu = false;
  /// Ignore selection-only [TextEditingController] notifications while a
  /// chip format/caps control is handling the pointer (EditableText also
  /// receives that down and would re-apply the formula via [onChanged]).
  bool _ignoreEdits = false;

  @override
  void initState() {
    super.initState();
    _controller = _FormulaEditingController(
      tokenKeys: _tokenKeys,
      hoverRef: widget.hoverRef,
      onHoverRef: widget.onHoverRef,
      onToggleCaps: _toggleCapsForCode,
      onCycleDateFormat: _cycleDateFormatForCode,
      onPickDateFormat: _pickDateFormatForCode,
      onChipContextMenu: _onChipContextMenu,
      onChipTap: (code) {
        final key = _tokenKeys[code];
        if (key != null) widget.onChipTap?.call(key);
      },
      monthOptionByOccurrence: widget.monthOptionByOccurrence,
      weekdayOptionByOccurrence: widget.weekdayOptionByOccurrence,
      enabled: widget.enabled,
    );
    _focus = FocusNode(onKeyEvent: _onKeyEvent);
    _loadFormula(widget.formula);
    _controller.addListener(_onEdited);
  }

  @override
  void didUpdateWidget(covariant StructureFormulaField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.hoverRef = widget.hoverRef;
    _controller.onHoverRef = widget.onHoverRef;
    _controller.enabled = widget.enabled;
    // Only adopt parent option lists when they actually change — a hover
    // rebuild must not clobber an optimistic chip format update.
    final monthChanged = !_listEq(
        oldWidget.monthOptionByOccurrence, widget.monthOptionByOccurrence);
    final weekdayChanged = !_listEq(
        oldWidget.weekdayOptionByOccurrence, widget.weekdayOptionByOccurrence);
    if (monthChanged) {
      _controller.monthOptionByOccurrence = widget.monthOptionByOccurrence;
    }
    if (weekdayChanged) {
      _controller.weekdayOptionByOccurrence = widget.weekdayOptionByOccurrence;
    }
    if (oldWidget.hoverRef != widget.hoverRef ||
        monthChanged ||
        weekdayChanged) {
      setState(() {});
    }
    if (oldWidget.formula != widget.formula &&
        widget.formula != _serialize()) {
      _loadFormula(widget.formula);
    }
  }

  static bool _listEq(List<int>? a, List<int>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _controller.removeListener(_onEdited);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void insertKey(String key) {
    if (!widget.enabled) return;
    final code = _allocToken(key);
    final ch = String.fromCharCode(code);
    final sel = _controller.selection;
    final text = _controller.text;
    final start = sel.isValid ? sel.start.clamp(0, text.length) : text.length;
    final end = sel.isValid ? sel.end.clamp(0, text.length) : text.length;
    final next = text.replaceRange(start, end, ch);
    _syncing = true;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + 1),
    );
    _syncing = false;
    widget.onChanged(_serialize());
    _focus.requestFocus();
  }

  /// Preserve focus when palette buttons use onPointerDown + preventDefault.
  void keepFocus() {
    if (!_focus.hasFocus) _focus.requestFocus();
  }

  void _toggleCapsForCode(int code) {
    if (!widget.enabled) return;
    final key = _tokenKeys[code];
    if (key == null || !StructureFormulaKeys.supportsCaps(key)) return;
    _tokenKeys[code] =
        StructureFormulaKeys.withCaps(key, !StructureFormulaKeys.isCaps(key));
    // Value text is unchanged (same private-use char); notify so buildTextSpan
    // re-reads tokenKeys for label / AA state. Listener also fires _onEdited.
    _ignoreEdits = true;
    _syncing = true;
    _controller.notifyListeners();
    _syncing = false;
    widget.onChanged(_serialize());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ignoreEdits = false;
    });
  }

  (DateFieldKind kind, int occ)? _dateFormatTargetForCode(int code) {
    final key = _tokenKeys[code];
    if (key == null) return null;
    final kind = StructureFormulaKeys.formatKindFor(key);
    if (kind == null) return null;
    var occ = 0;
    for (final cu in _controller.text.codeUnits) {
      if (cu < _tokenBase || cu >= _tokenBase + 256) continue;
      final k = _tokenKeys[cu];
      if (k == null) continue;
      if (StructureFormulaKeys.formatKindFor(k) != kind) continue;
      if (cu == code) return (kind, occ);
      occ++;
    }
    return null;
  }

  void _applyDateFormatOption(DateFieldKind kind, int occ, int optionIndex) {
    // Optimistic local update so the chip label flips immediately.
    final local = List<int>.from(
      (kind == DateFieldKind.month
              ? _controller.monthOptionByOccurrence
              : _controller.weekdayOptionByOccurrence) ??
          (kind == DateFieldKind.month
              ? widget.monthOptionByOccurrence
              : widget.weekdayOptionByOccurrence) ??
          const <int>[],
    );
    while (local.length <= occ) {
      local.add(0);
    }
    local[occ] = optionIndex;
    if (kind == DateFieldKind.month) {
      _controller.monthOptionByOccurrence = local;
    } else {
      _controller.weekdayOptionByOccurrence = local;
    }
    _ignoreEdits = true;
    _syncing = true;
    _controller.notifyListeners();
    _syncing = false;
    widget.onDatePartOptionChanged?.call(kind, occ, optionIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ignoreEdits = false;
    });
  }

  void _cycleDateFormatForCode(int code) {
    if (!widget.enabled) return;
    final target = _dateFormatTargetForCode(code);
    if (target == null) return;
    final (kind, occ) = target;
    final current = _optionIndexFor(kind, occ);
    final next = structureDateFormatNextIndex(kind, current);
    _applyDateFormatOption(kind, occ, next);
  }

  Future<void> _pickDateFormatForCode(int code, Offset globalPosition) async {
    if (!widget.enabled || !mounted) return;
    final target = _dateFormatTargetForCode(code);
    if (target == null) return;
    final (kind, occ) = target;
    final current = _optionIndexFor(kind, occ);
    final opts = kDateFieldOptions[kind]!;
    _ignoreEdits = true;
    _suppressContextMenu = true;
    try {
      final picked = await showFfMenu<int>(
        context: context,
        anchorGlobal: Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        width: 168,
        scrollable: false,
        maxHeight: 4 * 40.0,
        colors: FfMenuColors.session,
        choices: [
          for (var i = 0; i < opts.length; i++)
            FfMenuChoice(
              value: i,
              selected: i == current,
              child: Text(
                structureDateFormatChipLabel(kind, i),
                style: ffMenuTextStyle,
              ),
            ),
        ],
      );
      if (!mounted || picked?.value == null) return;
      _applyDateFormatOption(kind, occ, picked!.value!);
    } finally {
      _suppressContextMenu = false;
      _ignoreEdits = false;
    }
  }

  int _optionIndexFor(DateFieldKind kind, int occurrence) {
    // Prefer controller (optimistic) over widget props.
    final list = kind == DateFieldKind.month
        ? (_controller.monthOptionByOccurrence ?? widget.monthOptionByOccurrence)
        : kind == DateFieldKind.weekday
            ? (_controller.weekdayOptionByOccurrence ??
                widget.weekdayOptionByOccurrence)
            : null;
    if (list != null && occurrence < list.length) return list[occurrence];
    return 0;
  }

  Future<void> _onChipContextMenu(int code, Offset globalPosition) async {
    if (!widget.enabled || !mounted) return;
    // Hide the editable Cut/Copy/Paste toolbar for this secondary click.
    _suppressContextMenu = true;
    final key = _tokenKeys[code] ?? '';
    if (StructureFormulaKeys.isCaption(key)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      _suppressContextMenu = false;
      return;
    }

    try {
      final picked = await showFfMenu<String>(
        context: context,
        anchorGlobal: Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        width: 160,
        scrollable: false,
        maxHeight: 64,
        colors: FfMenuColors.session,
        choices: [
          FfMenuChoice(
            value: 'remove',
            child: Row(
              children: [
                PhosphorIcon(
                  PhosphorIconsRegular.trash,
                  size: 15,
                  color: FfTokens.danger,
                ),
                const SizedBox(width: 8),
                Text(
                  'Remove',
                  style: ffMenuTextStyle.copyWith(color: FfTokens.danger),
                ),
              ],
            ),
          ),
        ],
      );
      if (!mounted || picked?.value != 'remove') return;
      final ch = String.fromCharCode(code);
      final index = _controller.text.indexOf(ch);
      if (index < 0) return;
      await _confirmDeleteRange(index, index + 1, [key]);
    } finally {
      _suppressContextMenu = false;
    }
  }

  void _onEdited() {
    if (_syncing || _ignoreEdits) return;
    _pruneTokens();
    widget.onChanged(_serialize());
  }

  bool _isTokenCode(int cu) => cu >= _tokenBase && cu < _tokenBase + 256;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // Copy/cut: serialize chips as `{key}` so handwritten + field ranges
    // round-trip. Paste is intentionally NOT intercepted — EditableText's
    // native paste is what makes plain/handwritten clipboard text reliable.
    final shortcut = HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (shortcut && event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.keyC) {
        unawaited(_copySelection());
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyX) {
        unawaited(_cutSelection());
        return KeyEventResult.handled;
      }
    }

    final isBack = event.logicalKey == LogicalKeyboardKey.backspace;
    final isDel = event.logicalKey == LogicalKeyboardKey.delete;
    if (!isBack && !isDel) return KeyEventResult.ignored;

    final text = _controller.text;
    final sel = _controller.selection;
    if (!sel.isValid) return KeyEventResult.ignored;

    late final int start;
    late final int end;
    if (!sel.isCollapsed) {
      start = sel.start;
      end = sel.end;
    } else if (isBack) {
      if (sel.start <= 0) return KeyEventResult.ignored;
      start = sel.start - 1;
      end = sel.start;
    } else {
      if (sel.start >= text.length) return KeyEventResult.ignored;
      start = sel.start;
      end = sel.start + 1;
    }
    if (start < 0 || end > text.length || start >= end) {
      return KeyEventResult.ignored;
    }

    final keys = <String>[];
    for (var i = start; i < end; i++) {
      final cu = text.codeUnitAt(i);
      if (_isTokenCode(cu)) {
        keys.add(_tokenKeys[cu] ?? '');
      }
    }
    if (keys.isEmpty) return KeyEventResult.ignored;

    unawaited(_confirmDeleteRange(start, end, keys));
    return KeyEventResult.handled;
  }

  String _serializeRange(int start, int end) {
    final text = _controller.text;
    final lo = start.clamp(0, text.length);
    final hi = end.clamp(0, text.length);
    if (lo >= hi) return '';
    final buf = StringBuffer();
    for (var i = lo; i < hi; i++) {
      final cu = text.codeUnitAt(i);
      if (_isTokenCode(cu)) {
        final key = _tokenKeys[cu];
        if (key != null) buf.write('{$key}');
      } else {
        buf.writeCharCode(cu);
      }
    }
    return buf.toString();
  }

  /// Turn clipboard / typed paste into internal text (newlines → spaces;
  /// known `{key}` tokens → chips).
  String _ingestPlain(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\r\n]+'), ' ');
    final buf = StringBuffer();
    for (final node in StructureFormula.parse(cleaned)) {
      switch (node) {
        case StructureLiteralNode(:final text):
          buf.write(text);
        case StructureVariableNode(:final key):
          buf.writeCharCode(_allocToken(key));
      }
    }
    return buf.toString();
  }

  Future<void> _copySelection() async {
    final sel = _controller.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final serialized = _serializeRange(sel.start, sel.end);
    await Clipboard.setData(ClipboardData(text: serialized));
  }

  Future<void> _cutSelection() async {
    final sel = _controller.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final start = sel.start;
    final end = sel.end;
    final serialized = _serializeRange(start, end);
    final text = _controller.text;
    final keys = <String>[];
    for (var i = start; i < end; i++) {
      final cu = text.codeUnitAt(i);
      if (_isTokenCode(cu)) keys.add(_tokenKeys[cu] ?? '');
    }
    if (keys.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: serialized));
      await _confirmDeleteRange(start, end, keys);
      return;
    }
    await Clipboard.setData(ClipboardData(text: serialized));
    final next = text.replaceRange(start, end, '');
    _syncing = true;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start.clamp(0, next.length)),
    );
    _syncing = false;
    widget.onChanged(_serialize());
  }

  Future<void> _confirmDeleteRange(
    int start,
    int end,
    List<String> keys,
  ) async {
    if (!mounted) return;

    final onlyCaption =
        keys.isNotEmpty && keys.every(StructureFormulaKeys.isCaption);
    if (onlyCaption) {
      final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: t.divider),
          ),
          title: Text(
            'Caption required',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          content: Text(
            'Caption can’t be removed — it stays in every structure.',
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
      if (mounted) _focus.requestFocus();
      return;
    }

    final removable = keys.where((k) => !StructureFormulaKeys.isCaption(k));
    final labels = removable
        .map(StructureFormulaKeys.label)
        .toSet()
        .toList(growable: false);
    final message = labels.length == 1
        ? 'Remove ${labels.first} from the structure?'
        : 'Remove ${labels.join(', ')} from the structure?';

    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Remove field?',
      message: message,
      cancelLabel: 'Cancel',
      confirmLabel: 'Remove',
    );
    if (!mounted || ok != true) {
      if (mounted) _focus.requestFocus();
      return;
    }

    final text = _controller.text;
    if (start < 0 || end > text.length || start >= end) return;

    // Keep Caption if it was part of a larger selection.
    final buf = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i >= start && i < end) {
        final cu = text.codeUnitAt(i);
        if (_isTokenCode(cu) &&
            StructureFormulaKeys.isCaption(_tokenKeys[cu] ?? '')) {
          buf.writeCharCode(cu);
        }
        continue;
      }
      buf.writeCharCode(text.codeUnitAt(i));
    }
    final next = buf.toString();
    final caret = next.length < start ? next.length : start;
    _syncing = true;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret.clamp(0, next.length)),
    );
    _syncing = false;
    _pruneTokens();
    widget.onChanged(_serialize());
    _focus.requestFocus();
  }

  void _pruneTokens() {
    final live = <int>{};
    for (final cu in _controller.text.codeUnits) {
      if (cu >= _tokenBase && cu < _tokenBase + 256) live.add(cu);
    }
    _tokenKeys.removeWhere((code, _) => !live.contains(code));
  }

  int _allocToken(String key) {
    final code = _tokenBase + (_nextTokenCode % 200);
    _nextTokenCode++;
    _tokenKeys[code] = key;
    return code;
  }

  void _loadFormula(String formula) {
    _syncing = true;
    _tokenKeys.clear();
    _nextTokenCode = 0;
    final buf = StringBuffer();
    for (final node in StructureFormula.parse(formula)) {
      switch (node) {
        case StructureLiteralNode(:final text):
          buf.write(text.replaceAll('\n', ' ').replaceAll('\r', ''));
        case StructureVariableNode(:final key):
          buf.writeCharCode(_allocToken(key));
      }
    }
    _controller.value = TextEditingValue(
      text: buf.toString(),
      selection: TextSelection.collapsed(offset: buf.length),
    );
    _syncing = false;
  }

  String _serialize() {
    final buf = StringBuffer();
    for (final cu in _controller.text.codeUnits) {
      if (cu >= _tokenBase && cu < _tokenBase + 256) {
        final key = _tokenKeys[cu];
        if (key != null) buf.write('{$key}');
      } else {
        buf.writeCharCode(cu);
      }
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final focused = _focus.hasFocus;
    final field = TextSelectionTheme(
      data: TextSelectionThemeData(
        // Visible so handwritten ranges can be selected for copy/paste.
        selectionColor: t.accent.withValues(alpha: 0.35),
        selectionHandleColor: FfTokens.accentHover,
      ),
      // Transparent selection: WidgetSpan chips sit on top of the caret
      // selection rect, which otherwise shows as a square teal slab under
      // the rounded chip border (especially on right-click).
      child: TextField(
          controller: _controller,
          focusNode: _focus,
          enabled: widget.enabled,
          expands: widget.expands,
          // Content-height when not filling a parent (avoids empty formula box).
          minLines: widget.expands ? null : 1,
          maxLines: widget.expands ? null : null,
          textAlignVertical: TextAlignVertical.top,
          cursorColor: t.accent,
          enableInteractiveSelection: true,
          // Real Cut/Copy/Paste toolbar; suppressed while a chip Remove menu
          // is open so the two don't stack on secondary click.
          contextMenuBuilder: (context, editableTextState) {
            if (_suppressContextMenu) {
              return const SizedBox.shrink();
            }
            final items = editableTextState.contextMenuButtonItems.map((item) {
              switch (item.type) {
                case ContextMenuButtonType.copy:
                  return ContextMenuButtonItem(
                    type: ContextMenuButtonType.copy,
                    onPressed: () {
                      unawaited(_copySelection());
                      editableTextState.hideToolbar();
                    },
                  );
                case ContextMenuButtonType.cut:
                  return ContextMenuButtonItem(
                    type: ContextMenuButtonType.cut,
                    onPressed: () {
                      unawaited(_cutSelection());
                      editableTextState.hideToolbar();
                    },
                  );
                case ContextMenuButtonType.paste:
                  return ContextMenuButtonItem(
                    type: ContextMenuButtonType.paste,
                    onPressed: () {
                      // Native paste path — reliable for handwritten/plain text.
                      editableTextState.pasteText(SelectionChangedCause.toolbar);
                    },
                  );
                default:
                  return item;
              }
            }).toList(growable: false);
            return AdaptiveTextSelectionToolbar.buttonItems(
              anchors: editableTextState.contextMenuAnchors,
              buttonItems: items,
            );
          },
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 15,
            height: 28 / 15,
            color: t.text,
          ),
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
            _PlainPasteFormatter(ingest: _ingestPlain),
          ],
        ),
    );
    final shell = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(10),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: t.accent.withValues(alpha: 0.95),
                  blurRadius: 0,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: FfTokens.sessionHot,
                  blurRadius: 0,
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      child: field,
    );
    if (widget.expands) return SizedBox.expand(child: shell);
    return shell;
  }
}

class _FormulaEditingController extends TextEditingController {
  _FormulaEditingController({
    required this.tokenKeys,
    this.hoverRef,
    this.onHoverRef,
    this.onToggleCaps,
    this.onCycleDateFormat,
    this.onPickDateFormat,
    this.onChipContextMenu,
    this.onChipTap,
    this.monthOptionByOccurrence,
    this.weekdayOptionByOccurrence,
    this.enabled = true,
  });

  final Map<int, String> tokenKeys;
  StructureHoverRef? hoverRef;
  ValueChanged<StructureHoverRef?>? onHoverRef;
  ValueChanged<int>? onToggleCaps;
  ValueChanged<int>? onCycleDateFormat;
  void Function(int code, Offset globalPosition)? onPickDateFormat;
  void Function(int code, Offset globalPosition)? onChipContextMenu;
  ValueChanged<int>? onChipTap;
  List<int>? monthOptionByOccurrence;
  List<int>? weekdayOptionByOccurrence;
  bool enabled;

  static const int _tokenBase = 0xE000;

  int _optionFor(DateFieldKind kind, int occurrence) {
    final list = kind == DateFieldKind.month
        ? monthOptionByOccurrence
        : kind == DateFieldKind.weekday
            ? weekdayOptionByOccurrence
            : null;
    if (list != null && occurrence < list.length) return list[occurrence];
    return 0;
  }

  Widget _formatControl({
    required FfTokens t,
    required DateFieldKind kind,
    required int optionIndex,
    required int code,
  }) {
    final label = structureDateFormatChipLabel(kind, optionIndex);
    // Highlight when not the default Long (index 0).
    final active = optionIndex != 0;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        // Open format menu on primary / trackpad / touch. EditableText also
        // sees this pointer; _ignoreEdits on the field absorbs the fallout.
        if (event.buttons == kPrimaryMouseButton ||
            event.buttons == 0 ||
            event.kind == PointerDeviceKind.touch ||
            event.kind == PointerDeviceKind.trackpad) {
          onPickDateFormat?.call(code, event.position);
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 5,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: active
                ? t.accent.withValues(alpha: 0.35)
                : t.text.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: active ? t.accentEdge : t.divider,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: 0.2,
              color: active ? FfTokens.accentHover : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final children = <InlineSpan>[];
    final text = value.text;
    var slot = 0;
    var monthOcc = 0;
    var weekdayOcc = 0;
    var i = 0;
    while (i < text.length) {
      final cu = text.codeUnitAt(i);
      if (cu >= _tokenBase && cu < _tokenBase + 256) {
        final key = tokenKeys[cu] ?? '';
        final ref = StructureHoverRef(slot, key: key);
        slot++;
        final label = StructureFormulaKeys.label(key);
        final capsOn = StructureFormulaKeys.isCaps(key);
        final canCaps = StructureFormulaKeys.supportsCaps(key);
        final formatKind = StructureFormulaKeys.formatKindFor(key);
        final isCaption = StructureFormulaKeys.isCaption(key);
        final hot = hoverRef?.slot == ref.slot;
        // Caption chip: warm orange so it reads apart from teal variables.
        final Color chipFill = isCaption
            ? (hot
                ? FfTokens.accent2.withValues(alpha: 0.28)
                : FfTokens.accent2.withValues(alpha: 0.16))
            : (hot ? FfTokens.nocturneAccentDeep : t.selected);
        final Color chipBorder = isCaption
            ? (hot
                ? FfTokens.accent2
                : FfTokens.accent2.withValues(alpha: 0.55))
            : (hot ? FfTokens.accentHover : t.accentEdge);
        final Color chipText =
            isCaption ? FfTokens.accent2 : t.text;

        int? formatOcc;
        int formatOption = 0;
        if (formatKind == DateFieldKind.month) {
          formatOcc = monthOcc;
          formatOption = _optionFor(DateFieldKind.month, monthOcc);
          monthOcc++;
        } else if (formatKind == DateFieldKind.weekday) {
          formatOcc = weekdayOcc;
          formatOption = _optionFor(DateFieldKind.weekday, weekdayOcc);
          weekdayOcc++;
        }

        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: MouseRegion(
              onEnter: (_) => onHoverRef?.call(ref),
              onExit: (_) => onHoverRef?.call(null),
              // Listener (not GestureDetector): EditableText wins the
              // gesture arena over WidgetSpan detectors; secondary click
              // still arrives on pointer events.
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: enabled
                    ? (event) {
                        if (event.buttons == kSecondaryMouseButton) {
                          onChipContextMenu?.call(cu, event.position);
                        }
                      }
                    : null,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  padding: const EdgeInsets.fromLTRB(8, 2, 5, 2),
                  decoration: BoxDecoration(
                    color: chipFill,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: chipBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Label only — AA / format controls handle their own
                      // taps so they do not open the IPTC source dialog.
                      Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: enabled
                            ? (event) {
                                if (event.buttons == kPrimaryMouseButton) {
                                  onChipTap?.call(cu);
                                }
                              }
                            : null,
                        child: MouseRegion(
                          cursor: onChipTap != null
                              ? SystemMouseCursors.click
                              : SystemMouseCursors.basic,
                          child: Text(
                            label,
                            style: TextStyle(
                              fontFamily: FfTokens.fontFamily,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                              color: chipText,
                            ),
                          ),
                        ),
                      ),
                      if (formatKind != null && formatOcc != null) ...[
                        Container(
                          width: 1,
                          height: 12,
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          color: t.accentEdge,
                        ),
                        _formatControl(
                          t: t,
                          kind: formatKind,
                          optionIndex: formatOption,
                          code: cu,
                        ),
                      ],
                      if (canCaps) ...[
                        Container(
                          width: 1,
                          height: 12,
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          color: t.accentEdge,
                        ),
                        // Listener (not InkWell): EditableText wins the gesture
                        // arena over WidgetSpan InkWells, so onTap never fires.
                        Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (event) {
                            if (event.buttons == kPrimaryMouseButton) {
                              onToggleCaps?.call(cu);
                            }
                          },
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: capsOn
                                    ? t.accent.withValues(alpha: 0.35)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                'AA',
                                style: TextStyle(
                                  fontFamily: FfTokens.fontFamily,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                  letterSpacing: 0.2,
                                  color: capsOn
                                      ? FfTokens.accentHover
                                      : t.textTertiary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        i++;
      } else {
        final start = i;
        while (i < text.length) {
          final c = text.codeUnitAt(i);
          if (c >= _tokenBase && c < _tokenBase + 256) break;
          i++;
        }
        children.add(TextSpan(text: text.substring(start, i), style: style));
      }
    }
    return TextSpan(style: style, children: children);
  }
}

/// Normalize pasted text: newlines → spaces; known `{key}` → chips via [ingest].
class _PlainPasteFormatter extends TextInputFormatter {
  _PlainPasteFormatter({required this.ingest});

  final String Function(String raw) ingest;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Only rewrite when the edit inserted a chunk (paste / replace), not
    // single-character typing.
    final oldText = oldValue.text;
    final newText = newValue.text;
    if (newText.length <= oldText.length + 1 &&
        !newText.contains('\n') &&
        !newText.contains('\r') &&
        !newText.contains('{')) {
      return newValue;
    }

    final oldSel = oldValue.selection;
    final replaceStart =
        oldSel.isValid ? oldSel.start.clamp(0, oldText.length) : oldText.length;
    final replaceEnd =
        oldSel.isValid ? oldSel.end.clamp(0, oldText.length) : oldText.length;
    if (replaceStart > newText.length) return newValue;

    // Reconstruct the inserted slice from the edit.
    final prefix = oldText.substring(0, replaceStart);
    final suffix = oldText.substring(replaceEnd);
    if (!newText.startsWith(prefix) || !newText.endsWith(suffix)) {
      // Fallback: whole-string newline cleanup only.
      if (!newText.contains('\n') && !newText.contains('\r')) return newValue;
      final cleaned = newText.replaceAll(RegExp(r'[\r\n]+'), ' ');
      final caret = newValue.selection.extentOffset
          .clamp(0, cleaned.length);
      return TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: caret),
      );
    }
    final inserted = newText.substring(
      prefix.length,
      newText.length - suffix.length,
    );
    if (inserted.isEmpty) return newValue;
    final ingested = ingest(inserted);
    final next = '$prefix$ingested$suffix';
    return TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: prefix.length + ingested.length),
    );
  }
}

/// Insert palette: section title, then a clean wrap of equal chip buttons.
///
/// When [compactPopup] is true (New session), shows a small + that opens an
/// [showFfMenu] of the same insert options instead of the always-visible chips.
class StructureFormulaPalette extends StatelessWidget {
  const StructureFormulaPalette({
    super.key,
    required this.onInsert,
    required this.onPointerDown,
    this.compactPopup = false,
  });

  final ValueChanged<String> onInsert;
  final VoidCallback onPointerDown;
  final bool compactPopup;

  static const _groups = <(String, List<String>)>[
    ('Date', StructureFormulaKeys.date),
    ('Geographical', StructureFormulaKeys.locationGroup),
    ('Byline', StructureFormulaKeys.bylineGroup),
  ];

  Future<void> _openInsertMenu(BuildContext context, Rect anchor) async {
    onPointerDown();
    final choices = <FfMenuChoice<String>>[];
    for (var i = 0; i < _groups.length; i++) {
      if (i > 0) choices.add(const FfMenuChoice.divider());
      final group = _groups[i];
      choices.add(
        FfMenuChoice<String>(
          enabled: false,
          child: Text(
            group.$1.toUpperCase(),
            style: const TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: FfTokens.sessionT3,
            ),
          ),
        ),
      );
      for (final key in group.$2) {
        choices.add(
          FfMenuChoice<String>(
            value: key,
            child: Text(StructureFormulaKeys.label(key)),
          ),
        );
      }
    }
    final result = await showFfMenu<String>(
      context: context,
      anchorGlobal: anchor,
      choices: choices,
      width: 220,
      maxHeight: 360,
      colors: FfMenuColors.session,
      place: FfMenuPlace.below,
    );
    final key = result?.value;
    if (key == null || key.isEmpty) return;
    onInsert(key);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    if (compactPopup) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Builder(
          builder: (buttonContext) {
            return Material(
              color: t.sunken,
              borderRadius: BorderRadius.circular(7),
              child: InkWell(
                borderRadius: BorderRadius.circular(7),
                hoverColor: t.hover,
                onTap: () {
                  final box = buttonContext.findRenderObject() as RenderBox?;
                  if (box == null || !box.hasSize) return;
                  final anchor = box.localToGlobal(Offset.zero) & box.size;
                  unawaited(_openInsertMenu(context, anchor));
                },
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Center(
                    child: PhosphorIcon(
                      PhosphorIconsBold.plus,
                      size: 14,
                      color: t.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }
    // Side-by-side columns stay above the fold (avoids Structure panel scroll).
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _groups.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _groups[i].$1,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final key in _groups[i].$2)
                      _PaletteButton(
                        label: StructureFormulaKeys.label(key),
                        dateline: StructureFormulaKeys.isDateline(key),
                        caption: StructureFormulaKeys.isCaption(key),
                        onPointerDown: onPointerDown,
                        onTap: () => onInsert(key),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PaletteButton extends StatelessWidget {
  const _PaletteButton({
    required this.label,
    required this.dateline,
    required this.caption,
    required this.onPointerDown,
    required this.onTap,
  });

  final String label;
  final bool dateline;
  final bool caption;
  final VoidCallback onPointerDown;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Listener(
      onPointerDown: (_) => onPointerDown(),
      child: Material(
        color: FfTokens.card,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          hoverColor: t.hover,
          child: Container(
            height: 28,
            padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PhosphorIcon(
                  PhosphorIconsBold.plus,
                  size: 11,
                  color: caption ? FfTokens.accent2 : t.textTertiary,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: dateline ? 10 : 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: dateline ? 0.06 * 10 : 0,
                    height: 1,
                    color: caption ? FfTokens.accent2 : t.textSecondary,
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
