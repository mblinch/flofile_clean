import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart';
import '../data/firebar_shorthand.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Inline Firebar. Roster / verb columns remain the board reference list.
class CaptionV2SearchBar extends StatefulWidget {
  const CaptionV2SearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.textController,
    required this.onActivate,
    required this.onExit,
    this.onSave,
    this.onTransmit,
  });

  final CaptionV2Controller controller;
  final FocusNode focusNode;
  final TextEditingController textController;
  final VoidCallback onActivate;
  final VoidCallback onExit;
  final VoidCallback? onSave;
  final VoidCallback? onTransmit;

  @override
  State<CaptionV2SearchBar> createState() => _CaptionV2SearchBarState();
}

class _CaptionV2SearchBarState extends State<CaptionV2SearchBar>
    with SingleTickerProviderStateMixin {
  String? _completionQuery;
  late final AnimationController _ambNudge;
  bool _writtenToast = false;
  /// Keeps the EditableText element alive across the amb ↔ typing layout swap
  /// so the caret is not dropped when H/V closes.
  final GlobalKey _firebarInputKey = GlobalKey();
  final LayerLink _menuLink = LayerLink();
  final OverlayPortalController _menuPortal = OverlayPortalController();

  @override
  void initState() {
    super.initState();
    _ambNudge = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    widget.controller.addListener(_syncText);
    widget.focusNode.addListener(_onFocusOrController);
    widget.controller.addListener(_onFocusOrController);
  }

  @override
  void didUpdateWidget(covariant CaptionV2SearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncText);
      oldWidget.controller.removeListener(_onFocusOrController);
      widget.controller.addListener(_syncText);
      widget.controller.addListener(_onFocusOrController);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusOrController);
      widget.focusNode.addListener(_onFocusOrController);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncText);
    widget.controller.removeListener(_onFocusOrController);
    widget.focusNode.removeListener(_onFocusOrController);
    if (_menuPortal.isShowing) _menuPortal.hide();
    _ambNudge.dispose();
    super.dispose();
  }

  void _onFocusOrController() {
    final controller = widget.controller;
    final query = controller.searchQuery;
    if (_completionQuery != query) {
      _completionQuery = query;
      final verb = controller.firebarWordCompletionResult;
      if (verb != null && verb.kind == FirebarResultKind.verb) {
        final index = controller.firebarMenuResults
            .indexWhere((result) => result.key == verb.key);
        if (index >= 0 && index != controller.firebarMenuIndex) {
          controller.hoverFirebarMenu(index);
        }
      }
    }
    _syncMenuPortal();
    if (mounted) setState(() {});
  }

  bool get _showSuggestions {
    final controller = widget.controller;
    return controller.searchOpen &&
        !controller.firebarJerseySideChoiceOpen &&
        controller.firebarMenuOpen &&
        controller.firebarMenuResults.isNotEmpty;
  }

  void _syncMenuPortal() {
    final show = _showSuggestions;
    if (show && !_menuPortal.isShowing) {
      _menuPortal.show();
    } else if (!show && _menuPortal.isShowing) {
      _menuPortal.hide();
    }
  }

  void _syncText() {
    final query = widget.controller.searchQuery;
    if (widget.textController.text == query) return;
    widget.textController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  void _syncFieldFromController() {
    final left = widget.controller.searchQuery;
    widget.textController.value = TextEditingValue(
      text: left,
      selection: TextSelection.collapsed(offset: left.length),
    );
  }

  /// After H/V or a menu pick, keep the cursor in the Firebar field.
  /// Layout may swap the field's parent; request focus now and for two frames
  /// so the caret lands on the visible, mounted TextField.
  void _retainFirebarFocus() {
    if (!widget.controller.searchOpen) {
      widget.controller.setSearchOpen(true);
    }
    _syncFieldFromController();
    void focusIfReady() {
      if (!mounted || !widget.controller.searchOpen) return;
      // Re-assert even if already focused so a remounted EditableText shows the caret.
      widget.focusNode.requestFocus();
    }

    focusIfReady();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focusIfReady();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        focusIfReady();
      });
    });
  }

  bool _backspaceFirebarEntry() {
    final text = widget.textController.text;
    final sel = widget.textController.selection;
    if (!sel.isCollapsed || sel.baseOffset != text.length) return false;
    if (!widget.controller.backspaceFirebarShorthand()) return false;
    _syncFieldFromController();
    return true;
  }

  void _nudgeAmbiguous() {
    _ambNudge
      ..reset()
      ..forward();
  }

  Future<void> _flashWrittenToast() async {
    if (!mounted) return;
    setState(() => _writtenToast = true);
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    setState(() => _writtenToast = false);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final controller = widget.controller;
    if (!controller.searchOpen || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final amb = controller.firebarJerseySideChoiceOpen;

    // While H/V is open: only h/v (or click). Space/Tab/Enter/arrows nudge.
    if (amb) {
      if (event.logicalKey == LogicalKeyboardKey.keyH) {
        controller.chooseFirebarJerseySide(isHome: true);
        _retainFirebarFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyV) {
        controller.chooseFirebarJerseySide(isHome: false);
        _retainFirebarFocus();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.tab ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter ||
          event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _nudgeAmbiguous();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onExit();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // ⌘1–⌘4 pick a suggestion directly.
    if ((keys.isMetaPressed || keys.isControlPressed) &&
        !keys.isShiftPressed &&
        !keys.isAltPressed) {
      final digit = switch (event.logicalKey) {
        LogicalKeyboardKey.digit1 || LogicalKeyboardKey.numpad1 => 0,
        LogicalKeyboardKey.digit2 || LogicalKeyboardKey.numpad2 => 1,
        LogicalKeyboardKey.digit3 || LogicalKeyboardKey.numpad3 => 2,
        LogicalKeyboardKey.digit4 || LogicalKeyboardKey.numpad4 => 3,
        _ => -1,
      };
      if (digit >= 0) {
        final results = controller.firebarMenuResults;
        if (digit < results.length) {
          controller.hoverFirebarMenu(digit);
          controller.commitFirebarMenu();
          _retainFirebarFocus();
        }
        return KeyEventResult.handled;
      }
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown) {
      final delta =
          event.logicalKey == LogicalKeyboardKey.arrowUp ? -1 : 1;
      if (controller.firebarMenuOpen) {
        controller.moveFirebarMenu(delta);
      } else {
        controller.moveFirebarSelection(delta);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (controller.firebarMenuOpen) {
        controller.commitFirebarMenu();
        _retainFirebarFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.space) {
      // Shared jersey # → trailing space opens H/V (do not commit the menu).
      if (controller.firebarSpaceOpensJerseySide) {
        final raw = controller.searchQuery.trimRight();
        controller.setSearchQuery(raw.isEmpty ? ' ' : '$raw ');
        _syncFieldFromController();
        _retainFirebarFocus();
        return KeyEventResult.handled;
      }
      final q = controller.searchQuery.trim();
      if (q.isNotEmpty &&
          controller.firebarMenuOpen &&
          !controller.firebarJerseySideChoiceOpen) {
        controller.commitFirebarMenu();
        _retainFirebarFocus();
        return KeyEventResult.handled;
      }
      // Empty / mid-token space falls through to the field.
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (keys.isShiftPressed || keys.isMetaPressed || keys.isControlPressed) {
        return KeyEventResult.ignored;
      }
      final wrote = controller.applyFirebarLine();
      if (wrote) {
        _flashWrittenToast();
      } else if (controller.firebarJerseySideChoiceOpen) {
        _retainFirebarFocus();
        return KeyEventResult.handled;
      } else if (controller.firebarMenuOpen) {
        controller.commitFirebarMenu();
      }
      _retainFirebarFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onExit();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_backspaceFirebarEntry()) return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final active = controller.searchOpen;
    final amb = controller.firebarJerseySideChoiceOpen;
    final labelColor = active ? FfTokens.firebar : const Color(0xFF959AA0);
    final borderColor = active
        ? FfTokens.firebar.withValues(alpha: 0.7)
        : const Color(0x1EE8EEF4);

    // Keep portal visibility in sync even when rebuilds arrive without a
    // controller listener tick (e.g. focus-only paint paths).
    if (_showSuggestions != _menuPortal.isShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncMenuPortal();
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        OverlayPortal(
          controller: _menuPortal,
          overlayChildBuilder: (context) {
            final width = _menuLink.leaderSize?.width;
            if (width == null || width <= 0) {
              return const SizedBox.shrink();
            }
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _retainFirebarFocus,
                    child: const ColoredBox(
                      color: Color(0x99000000),
                    ),
                  ),
                ),
                CompositedTransformFollower(
                  link: _menuLink,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.bottomLeft,
                  followerAnchor: Alignment.topLeft,
                  offset: const Offset(0, 6),
                  child: Align(
                    alignment: Alignment.topLeft,
                    // At least as wide as the typing field; grow for long
                    // names so rows don't overflow.
                    child: SizedBox(
                      width: width.clamp(280.0, 420.0),
                      child: Material(
                        type: MaterialType.transparency,
                        child: _FirebarInlineSuggestions(
                          key: const Key('firebar_suggestions_overlay'),
                          controller: controller,
                          tokens: tokens,
                          onCommit: (index) {
                            controller.hoverFirebarMenu(index);
                            controller.commitFirebarMenu();
                            _retainFirebarFocus();
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
          child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (!active) widget.onActivate();
                widget.focusNode.requestFocus();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E242A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PhosphorIcon(
                  PhosphorIconsFill.fire,
                  size: 16,
                  color: labelColor,
                ),
                const SizedBox(width: 6),
                Text(
                  'Firebar',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    color: labelColor,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 1,
                  height: 22,
                  color: const Color(0x1EE8EEF4),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      if (!amb &&
                          controller.firebarCommitted.isNotEmpty) ...[
                        Flexible(
                          flex: 3,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var index = 0;
                                    index <
                                        controller.firebarCommitted.length;
                                    index++) ...[
                                  if (index > 0) const SizedBox(width: 6),
                                  _FirebarChip(
                                    result:
                                        controller.firebarCommitted[index],
                                    controller: controller,
                                    tokens: tokens,
                                    selected: index ==
                                        controller.firebarChipCursor,
                                    onSelect: () => controller
                                        .selectFirebarChip(index),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      // One TextField identity across amb ↔ typing layouts so
                      // H/V teardown does not dispose the EditableText / caret.
                      // LayerLink anchors the suggestions under this field.
                      if (amb)
                        SizedBox(
                          width: _shrunkInputWidth(
                            widget.textController.text,
                          ),
                          child: CompositedTransformTarget(
                            link: _menuLink,
                            child: _buildTypingField(
                              controller: controller,
                              tokens: tokens,
                              active: active,
                              amb: true,
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: CompositedTransformTarget(
                            link: _menuLink,
                            child: _buildTypingField(
                              controller: controller,
                              tokens: tokens,
                              active: active,
                              amb: false,
                            ),
                          ),
                        ),
                      if (amb) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: AnimatedBuilder(
                            animation: _ambNudge,
                            builder: (context, child) {
                              final t = _ambNudge.value;
                              final dx = t == 0
                                  ? 0.0
                                  : (t < 0.5 ? -3.0 : 3.0) *
                                      (1 - (t - 0.5).abs() * 2);
                              return Transform.translate(
                                offset: Offset(dx, 0),
                                child: child,
                              );
                            },
                            child: _FirebarJerseySideChoices(
                              controller: controller,
                              tokens: tokens,
                              onPicked: _retainFirebarFocus,
                            ),
                          ),
                        ),
                      ],
                      if (!amb &&
                          controller.firebarOptions.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  controller.firebarOptionPrompt ??
                                      'Choose:',
                                  style: tokens.metaStyle.copyWith(
                                    color: tokens.text,
                                    fontSize: 12,
                                  ),
                                ),
                                for (var index = 0;
                                    index <
                                        controller
                                            .filteredFirebarOptions.length;
                                    index++) ...[
                                  const SizedBox(width: 4),
                                  _FirebarOptionButton(
                                    option: controller
                                        .filteredFirebarOptions[index],
                                    selected: index ==
                                        controller.firebarOptionIndex,
                                    controller: controller,
                                    tokens: tokens,
                                    onPicked: _retainFirebarFocus,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (active && !amb) ...[
                  const SizedBox(width: 8),
                  const _FirebarKbd('Tab accept'),
                  const SizedBox(width: 4),
                  const _FirebarKbd('↵ write'),
                  const SizedBox(width: 4),
                  const _FirebarKbd('Esc'),
                ] else if (!active) ...[
                  const SizedBox(width: 8),
                  const _FirebarKbd('⌘K'),
                ],
              ],
                ),
              ),
            ),
        ),
        if (_writtenToast) ...[
          const SizedBox(height: 6),
          const Row(
            children: [
              PhosphorIcon(
                PhosphorIconsBold.check,
                size: 14,
                color: Color(0xFF7FD6A0),
              ),
              SizedBox(width: 6),
              Text(
                'Written to caption',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12,
                  color: Color(0xFF7FD6A0),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Prototype `inw.sh` width while the H/V chooser owns the bar.
  double _shrunkInputWidth(String text) {
    final chars = text.isEmpty ? 1 : text.length;
    return (chars * 9.5) + 6;
  }

  Widget _buildTypingField({
    required CaptionV2Controller controller,
    required FfTokens tokens,
    required bool active,
    required bool amb,
  }) {
    return _FirebarTypingField(
      inputKey: _firebarInputKey,
      active: active,
      focusNode: widget.focusNode,
      textController: widget.textController,
      tokens: tokens,
      lineTokens: amb ? const [] : controller.firebarLineTokens,
      ghostCompletion: amb ? null : _ghostSuffix(controller),
      onKey: _handleKey,
      onChanged: (value) {
        controller.setSearchQuery(value);
        if (controller.searchQuery != value) {
          _syncFieldFromController();
        }
      },
      // H/V chips and suggestions sit outside the TextField; unfocusing on
      // tap-outside races with pick handlers and drops the caret.
      onTapOutside: active
          ? null
          : (_) {
              widget.focusNode.unfocus();
            },
      onSubmitted: amb
          ? () {}
          : () {
              final wrote = controller.applyFirebarLine();
              if (wrote) {
                _flashWrittenToast();
              } else if (controller.firebarMenuOpen) {
                controller.commitFirebarMenu();
              }
              _retainFirebarFocus();
            },
    );
  }

  /// Grey ghost completion after the caret (top unique / word completion).
  String? _ghostSuffix(CaptionV2Controller controller) {
    if (controller.firebarJerseySideChoiceOpen) return null;
    final typed = controller.searchQuery;
    if (typed.isEmpty) return null;
    final completion = controller.firebarWordCompletion;
    if (completion != null &&
        completion.toLowerCase().startsWith(typed.toLowerCase()) &&
        completion.length > typed.length) {
      return completion.substring(typed.length);
    }
    final sel = controller.firebarMenuSelection;
    if (sel == null) return null;
    final label = sel.kind == FirebarResultKind.player
        ? (sel.player?.fullName ?? '')
        : (controller.verbDefinition(sel.verbKey ?? '')?.label ??
            sel.verbKey ??
            '');
    if (label.isEmpty) return null;
    final lower = label.toLowerCase();
    final q = typed.toLowerCase();
    if (lower.startsWith(q)) return label.substring(typed.length);
    final words = lower.split(RegExp(r'\s+'));
    for (final w in words) {
      if (w.startsWith(q)) {
        final at = lower.indexOf(w);
        if (at >= 0) return '  → ${label.substring(at)}';
      }
    }
    return null;
  }
}

class _FirebarKbd extends StatelessWidget {
  const _FirebarKbd(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF262D35),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: FfTokens.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF959AA0),
        ),
      ),
    );
  }
}

class _FirebarTypingField extends StatelessWidget {
  const _FirebarTypingField({
    required this.inputKey,
    required this.active,
    required this.focusNode,
    required this.textController,
    required this.tokens,
    required this.lineTokens,
    required this.onKey,
    required this.onChanged,
    required this.onSubmitted,
    this.onTapOutside,
    this.ghostCompletion,
  });

  final GlobalKey inputKey;
  final bool active;
  final FocusNode focusNode;
  final TextEditingController textController;
  final FfTokens tokens;
  final List<FirebarShorthandToken> lineTokens;
  final FocusOnKeyEventCallback onKey;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final TapRegionCallback? onTapOutside;
  final String? ghostCompletion;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontFamily: FfTokens.fontFamily,
      color: tokens.text,
      fontSize: 15,
      fontWeight: FontWeight.w500,
      height: 1.2,
    );
    final typed = textController.text;
    final errorStyle = baseStyle.copyWith(color: const Color(0xFFFF5A5A));
    final verbStyle = baseStyle.copyWith(color: const Color(0xFFFFB08F));
    final field = Focus(
      onKeyEvent: onKey,
      child: KeyedSubtree(
        key: const ValueKey('firebar-input'),
        child: TextField(
          key: inputKey,
          // Keep enabled while Firebar is open so focus/caret survive rebuilds.
          enabled: active,
          readOnly: false,
          showCursor: active,
          focusNode: focusNode,
          controller: textController,
          maxLines: 1,
          style: baseStyle.copyWith(color: Colors.transparent),
          cursorColor: FfTokens.firebar,
          cursorWidth: 2,
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 6),
          ),
          onChanged: onChanged,
          onSubmitted: (_) => onSubmitted(),
          onTapOutside: onTapOutside,
        ),
      ),
    );

    final spans = <InlineSpan>[];
    if (lineTokens.isEmpty) {
      spans.add(
        TextSpan(
          text: typed.isEmpty ? (active ? '' : ' ') : typed,
          style: baseStyle,
        ),
      );
    } else {
      for (var i = 0; i < lineTokens.length; i++) {
        if (i > 0) spans.add(TextSpan(text: ' ', style: baseStyle));
        final token = lineTokens[i];
        final TextStyle tokenStyle;
        if (token.error) {
          tokenStyle = errorStyle;
        } else if (token.completed && token.isVerb) {
          tokenStyle = verbStyle;
        } else {
          tokenStyle = baseStyle;
        }
        spans.add(TextSpan(text: token.display, style: tokenStyle));
      }
      if (typed.endsWith(' ')) {
        spans.add(TextSpan(text: ' ', style: baseStyle));
      }
    }
    if (ghostCompletion != null && ghostCompletion!.isNotEmpty) {
      spans.add(
        TextSpan(
          text: ghostCompletion,
          style: baseStyle.copyWith(color: const Color(0xFF6A6E73)),
        ),
      );
    }

    return SizedBox(
      height: 30,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          field,
          IgnorePointer(
            child: Text.rich(
              TextSpan(style: baseStyle, children: spans),
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _FirebarChip extends StatelessWidget {
  const _FirebarChip({
    required this.result,
    required this.controller,
    required this.tokens,
    this.selected = false,
    this.onSelect,
  });

  final FirebarResult result;
  final CaptionV2Controller controller;
  final FfTokens tokens;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final player = result.player;
    final isVerb = result.kind == FirebarResultKind.verb;
    final isHome = result.isHome == true;
    final abbr = isVerb
        ? ''
        : (isHome ? controller.homeAbbr : controller.awayAbbr).toUpperCase();
    final jersey = (player?.jerseyNumber ?? '').trim();
    final name = isVerb
        ? (controller.verbDefinition(result.verbKey ?? '')?.label ??
            result.verbKey ??
            '')
        : (player?.fullName ?? '');

    final fill = isVerb
        ? FfTokens.firebar.withValues(alpha: 0.14)
        : const Color(0xFF262D35);
    final textColor = isVerb ? const Color(0xFFFFB08F) : tokens.text;
    final border = selected
        ? FfTokens.firebar
        : Colors.transparent;

    return Container(
      height: 28,
      padding: const EdgeInsets.fromLTRB(9, 0, 4, 0),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSelect,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isVerb && jersey.isNotEmpty) ...[
                  Text(
                    jersey,
                    style: const TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: FfTokens.firebar,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  name,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                if (!isVerb && abbr.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    abbr,
                    style: const TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6A6E73),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => controller.removeFirebarChip(result),
            child: const SizedBox(
              width: 20,
              height: 20,
              child: Center(
                child: PhosphorIcon(
                  PhosphorIconsBold.x,
                  size: 11,
                  color: Color(0xFF6A6E73),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prototype H/V chooser: "Which #22?" + [H] #22 Name TOR · [V] #22 Name OTT.
class _FirebarJerseySideChoices extends StatelessWidget {
  const _FirebarJerseySideChoices({
    required this.controller,
    required this.tokens,
    required this.onPicked,
  });

  final CaptionV2Controller controller;
  final FfTokens tokens;
  final VoidCallback onPicked;

  @override
  Widget build(BuildContext context) {
    final options = controller.filteredFirebarOptions;
    final prompt = controller.firebarOptionPrompt ?? 'Which player?';
    final jersey = RegExp(r'#(\d+)').firstMatch(prompt)?.group(1) ?? '';
    String nameOf(FirebarOption o) {
      final label = o.label;
      final dash = label.indexOf('-');
      if (dash < 0) return label;
      return label.substring(dash + 1).trim();
    }

    FirebarOption? home;
    FirebarOption? away;
    for (final o in options) {
      if (o.jerseyIsHome == true) home = o;
      if (o.jerseyIsHome == false) away = o;
    }

    void pick(FirebarOption option) {
      controller.chooseFirebarOption(option);
      onPicked();
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        Text(
          prompt,
          style: const TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF959AA0),
          ),
        ),
        if (home != null)
          _AmbiguousPickButton(
            sideKey: 'H',
            jersey: jersey,
            name: nameOf(home),
            abbr: controller.homeAbbr.toUpperCase(),
            onTap: () => pick(home!),
          ),
        if (away != null)
          _AmbiguousPickButton(
            sideKey: 'V',
            jersey: jersey,
            name: nameOf(away),
            abbr: controller.awayAbbr.toUpperCase(),
            onTap: () => pick(away!),
          ),
      ],
    );
  }
}

class _AmbiguousPickButton extends StatefulWidget {
  const _AmbiguousPickButton({
    required this.sideKey,
    required this.jersey,
    required this.name,
    required this.abbr,
    required this.onTap,
  });

  final String sideKey;
  final String jersey;
  final String name;
  final String abbr;
  final VoidCallback onTap;

  @override
  State<_AmbiguousPickButton> createState() => _AmbiguousPickButtonState();
}

class _AmbiguousPickButtonState extends State<_AmbiguousPickButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 28,
          padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF2A3035) : const Color(0xFF262D35),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: _hovered
                  ? FfTokens.firebar.withValues(alpha: 0.6)
                  : const Color(0x1EE8EEF4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FfTokens.firebar,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  widget.sideKey,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A0A03),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              if (widget.jersey.isNotEmpty) ...[
                Text(
                  widget.jersey,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FfTokens.firebar,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                widget.name,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE8EEF4),
                ),
              ),
              if (widget.abbr.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  widget.abbr,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6A6E73),
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

class _FirebarInlineSuggestions extends StatelessWidget {
  const _FirebarInlineSuggestions({
    super.key,
    required this.controller,
    required this.tokens,
    required this.onCommit,
  });

  final CaptionV2Controller controller;
  final FfTokens tokens;
  final ValueChanged<int> onCommit;

  @override
  Widget build(BuildContext context) {
    final results = controller.firebarMenuResults.take(4).toList();
    if (results.isEmpty) return const SizedBox.shrink();
    final selected = controller.firebarMenuIndex.clamp(0, results.length - 1);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E242A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x1EE8EEF4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < results.length; i++)
            _SuggestionRow(
              controller: controller,
              result: results[i],
              selected: i == selected,
              hint: i == selected ? '↵' : '⌘${i + 1}',
              onHover: () => controller.hoverFirebarMenu(i),
              onCommit: () => onCommit(i),
            ),
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatefulWidget {
  const _SuggestionRow({
    required this.controller,
    required this.result,
    required this.selected,
    required this.hint,
    required this.onHover,
    required this.onCommit,
  });

  final CaptionV2Controller controller;
  final FirebarResult result;
  final bool selected;
  final String hint;
  final VoidCallback onHover;
  final VoidCallback onCommit;

  @override
  State<_SuggestionRow> createState() => _SuggestionRowState();
}

class _SuggestionRowState extends State<_SuggestionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final isPlayer = result.kind == FirebarResultKind.player;
    final player = result.player;
    final jersey = (player?.jerseyNumber ?? '').trim();
    final name = isPlayer
        ? (player?.fullName ?? '')
        : (widget.controller.verbDefinition(result.verbKey ?? '')?.label ??
            result.verbKey ??
            '');
    final abbr = isPlayer
        ? ((result.isHome == true
                ? widget.controller.homeAbbr
                : widget.controller.awayAbbr)
            .toUpperCase())
        : '';
    final fill = widget.selected
        ? const Color(0xFF2A3035)
        : (_hovered ? const Color(0xFF262D35) : Colors.transparent);
    final showKbd = widget.selected || _hovered;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hovered = true);
        widget.onHover();
      },
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onCommit,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              PhosphorIcon(
                PhosphorIconsRegular.arrowBendDownRight,
                size: 15,
                color: widget.selected
                    ? FfTokens.firebar
                    : const Color(0xFF6A6E73),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 13,
                      color: Color(0xFFE8EEF4),
                    ),
                    children: [
                      if (isPlayer) ...[
                        TextSpan(
                          text: name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (jersey.isNotEmpty)
                          TextSpan(
                            text: ' #$jersey',
                            style: const TextStyle(
                              color: Color(0xFFFF8A5C),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (abbr.isNotEmpty)
                          TextSpan(
                            text: '  $abbr',
                            style: const TextStyle(
                              color: Color(0xFF6A6E73),
                              fontSize: 12,
                            ),
                          ),
                      ] else
                        TextSpan(
                          text: name,
                          style: const TextStyle(
                            color: Color(0xFFFFB08F),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Opacity(
                opacity: showKbd ? 1 : 0,
                child: _FirebarKbd(widget.hint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FirebarOptionButton extends StatelessWidget {
  const _FirebarOptionButton({
    required this.option,
    required this.selected,
    required this.controller,
    required this.tokens,
    required this.onPicked,
  });

  final FirebarOption option;
  final bool selected;
  final CaptionV2Controller controller;
  final FfTokens tokens;
  final VoidCallback onPicked;

  @override
  Widget build(BuildContext context) {
    final fill = selected
        ? FfTokens.firebar.withValues(alpha: 0.16)
        : tokens.badgeFill;
    final border = selected
        ? FfTokens.firebar.withValues(alpha: 0.42)
        : tokens.divider;
    final textColor = selected ? FfTokens.firebar : tokens.text;

    return InkWell(
      canRequestFocus: false,
      onTap: () {
        controller.chooseFirebarOption(option);
        onPicked();
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 26,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: border),
        ),
        child: Text(
          option.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: tokens.metaStyle.copyWith(
            color: textColor,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
