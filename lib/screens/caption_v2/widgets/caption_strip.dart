import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../services/mac_spell_check_service.dart';
import '../../../theme/ff_tokens.dart';
import '../data/caption_v2_controller.dart' show CaptionProvenanceSpan;

/// One editable value chip inside [CaptionStrip].
class CaptionChipData {
  const CaptionChipData({
    required this.id,
    this.label,
    this.placeholder = '…',
  });

  final String id;

  /// Filled chip text. Null/empty → dashed empty chip with [placeholder].
  final String? label;
  final String placeholder;

  bool get isEmpty => label == null || label!.trim().isEmpty;
}

/// Caption sentence with player / verb / RBI / inning as inline editable chips.
///
/// A dashed outlined chip means that value is still empty.
class CaptionStrip extends StatelessWidget {
  const CaptionStrip({
    super.key,
    required this.leading,
    required this.chips,
    required this.trailing,
    this.fullCaption,
    this.highlightPhrases = const [],
    this.provenanceSpans = const [],
    this.onChipTap,
    this.inningLabel,
    this.timingUnitLabel = 'Inning',
    this.inning,
    this.regulationCount = 9,
    this.maxInning,
    this.extraLabel = 'X',
    this.segmentPrefix,
    this.selectedHalf,
    this.onHalfSelected,
    this.onInningSelected,
    this.onInningDecrement,
    this.onInningIncrement,
    this.inningDisabled = false,
    this.onInningActivate,
    this.timingPhraseEnabled = true,
    this.onTimingPhraseEnabledChanged,
    this.preSelected = false,
    this.postSelected = false,
    this.onPreTap,
    this.onPostTap,
    this.inningStepperOnly = false,
    this.mlbTimestampVisible = false,
    this.mlbTimestampEnabled = false,
    this.mlbTimestampLoading = false,
    this.mlbTimestampMatched = false,
    this.onMlbTimestampTap,
    this.personality,
    this.onPersonalityChanged,
    this.headline,
    this.onHeadlineChanged,
    this.keywords,
    this.onKeywordsChanged,
    this.onCaptionChanged,
    this.captionHint =
        'Caption will appear here as you add players and a verb.',
    this.onEditTap,
    this.footer,
  });

  /// Static text before the first chip (e.g. "Toronto Blue Jays ").
  final String leading;

  /// Ordered editable chips (player, verb, RBI, …).
  final List<CaptionChipData> chips;

  /// Static text after the chips (e.g. " in the … against …").
  final String trailing;

  /// When set (complete selection + caption style), show the full rendered
  /// caption instead of the chip sentence.
  final String? fullCaption;

  /// Phrases within [fullCaption] drawn in Firebar orange.
  final List<String> highlightPhrases;

  /// Phrases with hover tips explaining where caption pieces came from.
  final List<CaptionProvenanceSpan> provenanceSpans;

  final ValueChanged<String>? onChipTap;

  /// When set, [fullCaption] is shown in an editable field (mouse + keyboard).
  final ValueChanged<String>? onCaptionChanged;
  final String captionHint;

  /// Current inning display (e.g. "2nd"). Null hides the inning controls.
  final String? inningLabel;

  /// Left label for the timing bar ("Inning", "Half/Quarter", …).
  final String timingUnitLabel;
  final int? inning;
  final int regulationCount;

  /// Highest selectable inning. When greater than [regulationCount] + 1
  /// (baseball), squares page by nines with arrow controls up to this value.
  final int? maxInning;
  final String extraLabel;

  /// When set (e.g. `Q`), regulation squares show `Q1`… instead of `1`….
  final String? segmentPrefix;

  /// Basketball/WNBA half selection (`1H` / `2H`).
  final String? selectedHalf;
  final ValueChanged<String>? onHalfSelected;
  final ValueChanged<int>? onInningSelected;
  final VoidCallback? onInningDecrement;
  final VoidCallback? onInningIncrement;
  final bool inningDisabled;
  final VoidCallback? onInningActivate;

  /// When false, the timing bar controls are greyed out (Time of Game off).
  final bool timingPhraseEnabled;
  final ValueChanged<bool>? onTimingPhraseEnabledChanged;

  final bool preSelected;
  final bool postSelected;
  final VoidCallback? onPreTap;
  final VoidCallback? onPostTap;

  /// Mobile compact mode: only the +/- stepper (no Pre/Post, squares, or clock).
  final bool inningStepperOnly;
  final bool mlbTimestampVisible;
  final bool mlbTimestampEnabled;
  final bool mlbTimestampLoading;
  final bool mlbTimestampMatched;
  final VoidCallback? onMlbTimestampTap;
  final String? personality;
  final ValueChanged<String>? onPersonalityChanged;
  final String? headline;
  final ValueChanged<String>? onHeadlineChanged;
  final String? keywords;
  final ValueChanged<String>? onKeywordsChanged;
  final VoidCallback? onEditTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CaptionPanel(
            tokens: t,
            onTap: onEditTap,
            headerTrailing: onPersonalityChanged == null
                ? null
                : _PersonalityBar(
                    value: personality ?? '',
                    tokens: t,
                    onChanged: onPersonalityChanged!,
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: t.textSizeCaption * 1.35 * 2,
                  ),
                  child: onCaptionChanged != null
                      ? _CaptionEditor(
                          value: fullCaption ?? '',
                          hintText: captionHint,
                          tokens: t,
                          highlightPhrases: highlightPhrases,
                          provenanceSpans: provenanceSpans,
                          onChanged: onCaptionChanged!,
                        )
                      : fullCaption != null && fullCaption!.trim().isNotEmpty
                          ? Text.rich(
                              _captionAnnotatedSpan(
                                fullCaption!,
                                firebarPhrases: highlightPhrases,
                                provenance: provenanceSpans,
                                base: t.captionStyle,
                                firebarColor: FfTokens.firebar,
                                provenanceColor: t.accent,
                                tokens: t,
                                interactiveTips: true,
                              ),
                            )
                          : Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                Text(leading, style: t.captionStyle),
                                for (final chip
                                    in chips.where((chip) => !chip.isEmpty))
                                  _CaptionChip(
                                    data: chip,
                                    tokens: t,
                                    onTap: onChipTap == null
                                        ? null
                                        : () => onChipTap!(chip.id),
                                  ),
                                if (trailing.isNotEmpty)
                                  Text(trailing, style: t.captionStyle),
                              ],
                            ),
                ),
                if (inningLabel != null ||
                    onPreTap != null ||
                    onPostTap != null) ...[
                  const SizedBox(height: 10),
                  _InningCard(
                    inningLabel: inningLabel,
                    timingUnitLabel: timingUnitLabel,
                    inning: inning,
                    regulationCount: regulationCount,
                    extraLabel: extraLabel,
                    maxInning: maxInning,
                    segmentPrefix: segmentPrefix,
                    selectedHalf: selectedHalf,
                    onHalfSelected: inningStepperOnly ? null : onHalfSelected,
                    onInningSelected: onInningSelected,
                    onInningDecrement: onInningDecrement,
                    onInningIncrement: onInningIncrement,
                    inningDisabled: inningDisabled,
                    onInningActivate: onInningActivate,
                    timingPhraseEnabled: timingPhraseEnabled,
                    onTimingPhraseEnabledChanged: onTimingPhraseEnabledChanged,
                    preSelected: preSelected,
                    postSelected: postSelected,
                    onPreTap: inningStepperOnly ? null : onPreTap,
                    onPostTap: inningStepperOnly ? null : onPostTap,
                    mlbTimestampVisible:
                        inningStepperOnly ? false : mlbTimestampVisible,
                    mlbTimestampEnabled: mlbTimestampEnabled,
                    mlbTimestampLoading: mlbTimestampLoading,
                    mlbTimestampMatched: mlbTimestampMatched,
                    onMlbTimestampTap: onMlbTimestampTap,
                    stepperOnly: inningStepperOnly,
                    tokens: t,
                  ),
                ],
                if (footer != null) ...[
                  const SizedBox(height: 10),
                  footer!,
                ],
              ],
            ),
          ),
          if (onHeadlineChanged != null) ...[
            const SizedBox(height: 4),
            _MetadataBar(
              label: 'HEADLINE',
              hintText: 'Enter headline',
              value: headline ?? '',
              tokens: t,
              onChanged: onHeadlineChanged!,
            ),
          ],
          if (onKeywordsChanged != null) ...[
            const SizedBox(height: 4),
            _MetadataBar(
              label: 'KEYWORDS',
              hintText: 'Comma-separated keywords',
              value: keywords ?? '',
              tokens: t,
              onChanged: onKeywordsChanged!,
            ),
          ],
        ],
      ),
    );
  }
}

class _CaptionEditor extends StatefulWidget {
  const _CaptionEditor({
    required this.value,
    required this.hintText,
    required this.tokens,
    required this.onChanged,
    this.highlightPhrases = const [],
    this.provenanceSpans = const [],
  });

  final String value;
  final String hintText;
  final FfTokens tokens;
  final ValueChanged<String> onChanged;
  final List<String> highlightPhrases;
  final List<CaptionProvenanceSpan> provenanceSpans;

  @override
  State<_CaptionEditor> createState() => _CaptionEditorState();
}

class _CaptionEditorState extends State<_CaptionEditor> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode(debugLabel: 'Caption editor');

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _CaptionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _hasAnnotations =>
      widget.highlightPhrases.isNotEmpty || widget.provenanceSpans.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final baseStyle = t.captionStyle;
    final text = _controller.text;

    // Unfocused: show tip-able highlights. Tap/focus switches to the editor.
    if (!_focusNode.hasFocus && _hasAnnotations && text.trim().isNotEmpty) {
      return Focus(
        focusNode: _focusNode,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _focusNode.requestFocus(),
          child: Text.rich(
            _captionAnnotatedSpan(
              text,
              firebarPhrases: widget.highlightPhrases,
              provenance: widget.provenanceSpans,
              base: baseStyle,
              firebarColor: FfTokens.firebar,
              provenanceColor: t.accent,
              tokens: t,
              interactiveTips: true,
            ),
          ),
        ),
      );
    }

    final field = TextField(
      controller: _controller,
      focusNode: _focusNode,
      maxLines: null,
      minLines: 2,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      style: _hasAnnotations
          ? baseStyle.copyWith(color: Colors.transparent)
          : baseStyle,
      cursorColor:
          widget.highlightPhrases.isNotEmpty ? FfTokens.firebar : t.accent,
      mouseCursor: SystemMouseCursors.text,
      spellCheckConfiguration: floSpellCheckConfiguration(),
      contextMenuBuilder: floSpellCheckContextMenuBuilder,
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        hintText: _hasAnnotations ? null : widget.hintText,
        hintStyle: baseStyle.copyWith(color: t.textSecondary),
      ),
      onChanged: widget.onChanged,
    );
    if (!_hasAnnotations) return field;
    return Stack(
      children: [
        IgnorePointer(
          child: Text.rich(
            _captionAnnotatedSpan(
              text,
              firebarPhrases: widget.highlightPhrases,
              provenance: widget.provenanceSpans,
              base: baseStyle,
              firebarColor: FfTokens.firebar,
              provenanceColor: t.accent,
              tokens: t,
              interactiveTips: false,
            ),
          ),
        ),
        field,
      ],
    );
  }
}

class _CaptionAnnoRange {
  const _CaptionAnnoRange({
    required this.start,
    required this.end,
    this.firebar = false,
    this.tip,
  });

  final int start;
  final int end;
  final bool firebar;
  final String? tip;
}

TextSpan _captionAnnotatedSpan(
  String text, {
  required List<String> firebarPhrases,
  required List<CaptionProvenanceSpan> provenance,
  required TextStyle base,
  required Color firebarColor,
  required Color provenanceColor,
  required FfTokens tokens,
  required bool interactiveTips,
}) {
  final ranges = <_CaptionAnnoRange>[];
  for (final phrase in firebarPhrases) {
    if (phrase.isEmpty) continue;
    var from = 0;
    while (from < text.length) {
      final index = text.indexOf(phrase, from);
      if (index < 0) break;
      ranges.add(_CaptionAnnoRange(
        start: index,
        end: index + phrase.length,
        firebar: true,
      ));
      from = index + phrase.length;
    }
  }
  for (final span in provenance) {
    final phrase = span.phrase;
    if (phrase.isEmpty) continue;
    var from = 0;
    while (from < text.length) {
      final index = text.indexOf(phrase, from);
      if (index < 0) break;
      ranges.add(_CaptionAnnoRange(
        start: index,
        end: index + phrase.length,
        tip: span.tip,
      ));
      from = index + phrase.length;
    }
  }
  if (ranges.isEmpty) return TextSpan(text: text, style: base);

  ranges.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    if (byStart != 0) return byStart;
    return b.end.compareTo(a.end);
  });

  // Merge overlapping ranges; firebar color wins, tips concatenate.
  final merged = <_CaptionAnnoRange>[];
  for (final range in ranges) {
    if (merged.isEmpty || range.start >= merged.last.end) {
      merged.add(range);
      continue;
    }
    final prev = merged.removeLast();
    final tip = <String>{
      if (prev.tip != null && prev.tip!.isNotEmpty) prev.tip!,
      if (range.tip != null && range.tip!.isNotEmpty) range.tip!,
    }.join('\n');
    merged.add(_CaptionAnnoRange(
      start: prev.start,
      end: prev.end > range.end ? prev.end : range.end,
      firebar: prev.firebar || range.firebar,
      tip: tip.isEmpty ? null : tip,
    ));
  }

  final children = <InlineSpan>[];
  var cursor = 0;
  for (final range in merged) {
    if (range.start < cursor) continue;
    if (range.start > cursor) {
      children.add(TextSpan(text: text.substring(cursor, range.start)));
    }
    final phrase = text.substring(range.start, range.end);
    final style = range.firebar
        ? base.copyWith(color: firebarColor)
        : base.copyWith(
            color: base.color,
            backgroundColor: provenanceColor.withValues(alpha: 0.16),
            decoration: TextDecoration.underline,
            decorationColor: provenanceColor.withValues(alpha: 0.7),
            decorationStyle: TextDecorationStyle.dotted,
          );
    if (interactiveTips && range.tip != null && range.tip!.isNotEmpty) {
      children.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: _ProvenanceTip(
          tip: range.tip!,
          tokens: tokens,
          child: Text(phrase, style: style),
        ),
      ));
    } else {
      children.add(TextSpan(text: phrase, style: style));
    }
    cursor = range.end;
  }
  if (cursor < text.length) {
    children.add(TextSpan(text: text.substring(cursor)));
  }
  return TextSpan(style: base, children: children);
}

/// Dark, compact hover card for caption field provenance.
class _ProvenanceTip extends StatelessWidget {
  const _ProvenanceTip({
    required this.tip,
    required this.tokens,
    required this.child,
  });

  final String tip;
  final FfTokens tokens;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lines = tip
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    return Tooltip(
      waitDuration: const Duration(milliseconds: 280),
      showDuration: const Duration(seconds: 6),
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(top: 6),
      decoration: const BoxDecoration(color: Colors.transparent),
      richMessage: WidgetSpan(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 260),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: tokens.elevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tokens.divider),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  lines.length > 1 ? 'SOURCES' : 'SOURCE',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.9,
                    color: tokens.textTertiary,
                  ),
                ),
                const SizedBox(height: 5),
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0) const SizedBox(height: 3),
                  _ProvenanceTipLine(line: lines[i], tokens: tokens),
                ],
              ],
            ),
          ),
        ),
      ),
      child: child,
    );
  }
}

class _ProvenanceTipLine extends StatelessWidget {
  const _ProvenanceTipLine({
    required this.line,
    required this.tokens,
  });

  final String line;
  final FfTokens tokens;

  @override
  Widget build(BuildContext context) {
    final parts = line.split(' · ');
    final source = parts.first.trim();
    final detail = parts.length > 1 ? parts.sublist(1).join(' · ').trim() : '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: tokens.accent,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: detail.isEmpty
              ? Text(
                  source,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                    color: tokens.text,
                  ),
                )
              : Text.rich(
                  TextSpan(
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 12,
                      height: 1.25,
                      color: tokens.text,
                    ),
                    children: [
                      TextSpan(
                        text: source,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: '  $detail',
                        style: TextStyle(
                          fontWeight: FontWeight.w400,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _CaptionPanel extends StatefulWidget {
  const _CaptionPanel({
    required this.tokens,
    required this.child,
    this.headerTrailing,
    this.onTap,
  });

  final FfTokens tokens;
  final Widget child;
  final Widget? headerTrailing;
  final VoidCallback? onTap;

  @override
  State<_CaptionPanel> createState() => _CaptionPanelState();
}

class _CaptionPanelState extends State<_CaptionPanel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.accent.withValues(alpha: 0.85)),
        boxShadow: FfTokens.accentButtonGlow(t.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MouseRegion(
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: Tooltip(
                  message: 'Edit caption style',
                  child: InkWell(
                    onTap: widget.onTap,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 1,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'CAPTION',
                            style: FfTokens.panelLabel(color: t.textSecondary),
                            textHeightBehavior: const TextHeightBehavior(
                              applyHeightToFirstAscent: false,
                              applyHeightToLastDescent: false,
                            ),
                          ),
                          const SizedBox(width: 6),
                          PhosphorIcon(
                            PhosphorIconsRegular.notePencil,
                            size: 14,
                            color:
                                t.text.withValues(alpha: _hovered ? 1 : 0.55),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.headerTrailing != null) ...[
                const SizedBox(width: 10),
                Container(
                  width: 1,
                  height: 14,
                  color: t.divider,
                ),
                const SizedBox(width: 10),
                Expanded(child: widget.headerTrailing!),
              ],
            ],
          ),
          const SizedBox(height: 8),
          widget.child,
        ],
      ),
    );
  }
}

class _InningCard extends StatefulWidget {
  const _InningCard({
    required this.inningLabel,
    required this.timingUnitLabel,
    required this.inning,
    required this.regulationCount,
    required this.maxInning,
    required this.extraLabel,
    required this.segmentPrefix,
    required this.selectedHalf,
    required this.onHalfSelected,
    required this.onInningSelected,
    required this.onInningDecrement,
    required this.onInningIncrement,
    required this.inningDisabled,
    required this.onInningActivate,
    required this.timingPhraseEnabled,
    required this.onTimingPhraseEnabledChanged,
    required this.preSelected,
    required this.postSelected,
    required this.onPreTap,
    required this.onPostTap,
    required this.mlbTimestampVisible,
    required this.mlbTimestampEnabled,
    required this.mlbTimestampLoading,
    required this.mlbTimestampMatched,
    required this.onMlbTimestampTap,
    this.stepperOnly = false,
    required this.tokens,
  });

  final String? inningLabel;
  final String timingUnitLabel;
  final int? inning;
  final int regulationCount;
  final int? maxInning;
  final String extraLabel;
  final String? segmentPrefix;
  final String? selectedHalf;
  final ValueChanged<String>? onHalfSelected;
  final ValueChanged<int>? onInningSelected;
  final VoidCallback? onInningDecrement;
  final VoidCallback? onInningIncrement;
  final bool inningDisabled;
  final VoidCallback? onInningActivate;
  final bool timingPhraseEnabled;
  final ValueChanged<bool>? onTimingPhraseEnabledChanged;
  final bool preSelected;
  final bool postSelected;
  final VoidCallback? onPreTap;
  final VoidCallback? onPostTap;
  final bool mlbTimestampVisible;
  final bool mlbTimestampEnabled;
  final bool mlbTimestampLoading;
  final bool mlbTimestampMatched;
  final VoidCallback? onMlbTimestampTap;
  final bool stepperOnly;
  final FfTokens tokens;

  @override
  State<_InningCard> createState() => _InningCardState();
}

class _InningCardState extends State<_InningCard> {
  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final timingOn = widget.timingPhraseEnabled;
    final canSquares = !widget.stepperOnly &&
        widget.inningLabel != null &&
        widget.onInningSelected != null;
    final periodButtons = <Widget>[
      if (widget.onPreTap != null) ...[
        SizedBox(
          width: 44,
          height: 30,
          child: _ToggleChip(
            label: 'Pre',
            selected: widget.preSelected,
            tokens: t,
            onTap: widget.onPreTap,
          ),
        ),
        if (canSquares || widget.inningLabel != null) const SizedBox(width: 4),
      ],
      if (canSquares)
        _InningSquares(
          selected: widget.inning ?? 1,
          regulationCount: widget.regulationCount,
          maxInning: widget.maxInning ?? (widget.regulationCount + 1),
          extraLabel: widget.extraLabel,
          segmentPrefix: widget.segmentPrefix,
          quarterSelected: widget.selectedHalf == null,
          tokens: t,
          disabled: widget.inningDisabled,
          onActivate: widget.onInningActivate,
          onSelected: widget.onInningSelected!,
        )
      else if (widget.inningLabel != null)
        SizedBox(
          height: 30,
          child: _InningStepper(
            label: widget.inningLabel!,
            tokens: t,
            onDecrement: widget.onInningDecrement,
            onIncrement: widget.onInningIncrement,
            disabled: widget.stepperOnly ? false : widget.inningDisabled,
            onActivate: widget.onInningActivate,
          ),
        ),
      if (widget.onHalfSelected != null && canSquares) ...[
        const SizedBox(width: 4),
        SizedBox(
          width: 40,
          height: 30,
          child: _ToggleChip(
            label: '1H',
            selected: !widget.inningDisabled && widget.selectedHalf == '1H',
            tokens: t,
            onTap: () => widget.onHalfSelected!('1H'),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 40,
          height: 30,
          child: _ToggleChip(
            label: '2H',
            selected: !widget.inningDisabled && widget.selectedHalf == '2H',
            tokens: t,
            onTap: () => widget.onHalfSelected!('2H'),
          ),
        ),
      ],
      if (widget.onPostTap != null) ...[
        if (canSquares || widget.inningLabel != null) const SizedBox(width: 4),
        SizedBox(
          width: 48,
          height: 30,
          child: _ToggleChip(
            label: 'Post',
            selected: widget.postSelected,
            tokens: t,
            onTap: widget.onPostTap,
          ),
        ),
      ],
      if (widget.mlbTimestampVisible) ...[
        const SizedBox(width: 4),
        SizedBox(
          width: 108,
          height: 30,
          child: _MlbTimestampChip(
            enabled: widget.mlbTimestampEnabled,
            loading: widget.mlbTimestampLoading,
            matched: widget.mlbTimestampMatched,
            tokens: t,
            onTap: widget.onMlbTimestampTap,
          ),
        ),
      ],
    ];

    return SizedBox(
      height: 30,
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Tooltip(
              message: timingOn
                  ? 'Time of game on — tap to turn off'
                  : 'Time of game off — tap to turn on',
              waitDuration: const Duration(milliseconds: 400),
              child: InkWell(
                onTap: widget.onTimingPhraseEnabledChanged == null
                    ? null
                    : () => widget.onTimingPhraseEnabledChanged!(!timingOn),
                borderRadius: BorderRadius.circular(4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.timingUnitLabel.toUpperCase(),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: FfTokens.panelLabel(
                      color: timingOn
                          ? t.textSecondary
                          : t.textSecondary.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Opacity(
            opacity: timingOn || widget.stepperOnly ? 1 : 0.4,
            child: IgnorePointer(
              ignoring: !(timingOn || widget.stepperOnly),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: periodButtons,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataBar extends StatefulWidget {
  const _MetadataBar({
    required this.label,
    required this.hintText,
    required this.value,
    required this.tokens,
    required this.onChanged,
  });

  final String label;
  final String hintText;
  final String value;
  final FfTokens tokens;
  final ValueChanged<String> onChanged;

  @override
  State<_MetadataBar> createState() => _MetadataBarState();
}

class _MetadataBarState extends State<_MetadataBar> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _MetadataBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return SizedBox(
      height: 24,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: 1,
        style: t.metaStyle.copyWith(color: t.text, fontSize: 12, height: 1.1),
        cursorColor: t.accent,
        spellCheckConfiguration: floSpellCheckConfiguration(),
        contextMenuBuilder: floSpellCheckContextMenuBuilder,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 7, right: 7),
            child: Text(widget.label, style: t.microStyle),
          ),
          prefixIconConstraints: const BoxConstraints(),
          hintText: widget.hintText,
          hintStyle: t.metaStyle.copyWith(fontSize: 12),
          filled: true,
          fillColor: t.sunken,
          contentPadding: const EdgeInsets.symmetric(horizontal: 7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: t.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: t.divider),
          ),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _PersonalityBar extends StatefulWidget {
  const _PersonalityBar({
    required this.value,
    required this.tokens,
    required this.onChanged,
  });

  final String value;
  final FfTokens tokens;
  final ValueChanged<String> onChanged;

  @override
  State<_PersonalityBar> createState() => _PersonalityBarState();
}

class _PersonalityBarState extends State<_PersonalityBar> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _PersonalityBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          Text(
            'PERSONALITY',
            softWrap: false,
            style: FfTokens.panelLabel(color: t.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: 1,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: t.text,
                height: 1.1,
              ),
              cursorColor: t.accent,
              spellCheckConfiguration: floSpellCheckConfiguration(),
              contextMenuBuilder: floSpellCheckContextMenuBuilder,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'Person shown in image',
                hintStyle: t.metaStyle,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: widget.onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptionChip extends StatelessWidget {
  const _CaptionChip({
    required this.data,
    required this.tokens,
    this.onTap,
  });

  final CaptionChipData data;
  final FfTokens tokens;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final empty = data.isEmpty;
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        empty ? data.placeholder : data.label!,
        style: tokens.chipStyle.copyWith(
          color: empty ? tokens.textSecondary : tokens.text,
          fontWeight: empty ? FfTokens.weightRegular : FfTokens.weightMedium,
        ),
      ),
    );

    if (empty) {
      return GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedRRectPainter(
            color: tokens.accent.withValues(alpha: 0.55),
            radius: FfTokens.radiusChip,
          ),
          child: child,
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.badgeFill,
          borderRadius: BorderRadius.circular(FfTokens.radiusChip),
          border: Border.all(color: tokens.divider),
        ),
        child: child,
      ),
    );
  }
}

class _InningSquares extends StatefulWidget {
  const _InningSquares({
    required this.selected,
    required this.regulationCount,
    required this.maxInning,
    required this.extraLabel,
    required this.segmentPrefix,
    required this.quarterSelected,
    required this.tokens,
    required this.disabled,
    required this.onActivate,
    required this.onSelected,
  });

  final int selected;
  final int regulationCount;
  final int maxInning;
  final String extraLabel;
  final String? segmentPrefix;
  final bool quarterSelected;
  final FfTokens tokens;
  final bool disabled;
  final VoidCallback? onActivate;
  final ValueChanged<int> onSelected;

  bool get pagesExtras => maxInning > regulationCount + 1;

  @override
  State<_InningSquares> createState() => _InningSquaresState();
}

class _InningSquaresState extends State<_InningSquares> {
  late int _page;

  int get _pageSize => widget.regulationCount;

  int get _lastPage =>
      ((_pageSize <= 0 ? 1 : widget.maxInning) - 1) ~/
      (_pageSize <= 0 ? 1 : _pageSize);

  int _pageForInning(int inning) =>
      ((inning - 1) ~/ _pageSize).clamp(0, _lastPage);

  @override
  void initState() {
    super.initState();
    _page = widget.pagesExtras ? _pageForInning(widget.selected) : 0;
  }

  @override
  void didUpdateWidget(covariant _InningSquares oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.pagesExtras) {
      _page = 0;
      return;
    }
    if (oldWidget.selected != widget.selected ||
        oldWidget.maxInning != widget.maxInning ||
        oldWidget.regulationCount != widget.regulationCount) {
      final needed = _pageForInning(widget.selected);
      if (needed != _page) _page = needed;
    }
  }

  void _setPage(int page) {
    final next = page.clamp(0, _lastPage);
    if (next == _page) return;
    setState(() => _page = next);
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.pagesExtras ? _page.clamp(0, _lastPage) : 0;
    final startInning = page * _pageSize + 1;
    final innings = <int>[
      for (var i = 0; i < _pageSize; i++)
        if (startInning + i <= widget.maxInning) startInning + i,
    ];
    final showBack = widget.pagesExtras && page > 0;
    final showForward = widget.pagesExtras && page < _lastPage;
    final showExtraSlot = !widget.pagesExtras;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.disabled ? widget.onActivate : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: widget.disabled ? 0.20 : 1,
        child: IgnorePointer(
          ignoring: widget.disabled,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showBack) ...[
                SizedBox(
                  width: 34,
                  height: 30,
                  child: _InningNavSquare(
                    icon: PhosphorIconsRegular.arrowLeft,
                    tokens: widget.tokens,
                    onTap: () => _setPage(page - 1),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              for (var i = 0; i < innings.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                SizedBox(
                  width: 34,
                  height: 30,
                  child: _InningSquare(
                    label: widget.segmentPrefix == null
                        ? '${innings[i]}'
                        : '${widget.segmentPrefix}${innings[i]}',
                    selected: widget.quarterSelected &&
                        !widget.disabled &&
                        widget.selected == innings[i],
                    tokens: widget.tokens,
                    onTap: () => widget.onSelected(innings[i]),
                  ),
                ),
              ],
              if (showForward) ...[
                const SizedBox(width: 4),
                SizedBox(
                  width: 34,
                  height: 30,
                  child: _InningNavSquare(
                    icon: PhosphorIconsRegular.arrowRight,
                    tokens: widget.tokens,
                    onTap: () => _setPage(page + 1),
                  ),
                ),
              ],
              if (showExtraSlot) ...[
                const SizedBox(width: 4),
                SizedBox(
                  width: 34,
                  height: 30,
                  child: _InningSquare(
                    label: widget.extraLabel,
                    selected: widget.quarterSelected &&
                        !widget.disabled &&
                        widget.selected == widget.regulationCount + 1,
                    tokens: widget.tokens,
                    onTap: () => widget.onSelected(widget.regulationCount + 1),
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

class _InningSquare extends StatefulWidget {
  const _InningSquare({
    required this.label,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final FfTokens tokens;
  final VoidCallback onTap;

  @override
  State<_InningSquare> createState() => _InningSquareState();
}

class _InningSquareState extends State<_InningSquare> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 30,
          width: double.infinity,
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          decoration: BoxDecoration(
            color: widget.selected
                ? t.selected
                : (_hovered ? t.hover : t.bg),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.selected ? t.accent : t.divider,
            ),
            boxShadow:
                widget.selected ? FfTokens.selectionGlow(t.accent) : null,
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: widget.label.length > 2 ? 11 : 13,
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
              letterSpacing: 0,
              color: widget.selected ? t.text : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _InningNavSquare extends StatefulWidget {
  const _InningNavSquare({
    required this.icon,
    required this.tokens,
    required this.onTap,
  });

  final IconData icon;
  final FfTokens tokens;
  final VoidCallback onTap;

  @override
  State<_InningNavSquare> createState() => _InningNavSquareState();
}

class _InningNavSquareState extends State<_InningNavSquare> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered ? t.hover : t.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: t.divider),
          ),
          child: PhosphorIcon(
            widget.icon,
            size: 16,
            color: t.text.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}

class _InningStepper extends StatelessWidget {
  const _InningStepper({
    required this.label,
    required this.tokens,
    this.onDecrement,
    this.onIncrement,
    this.disabled = false,
    this.onActivate,
  });

  final String label;
  final FfTokens tokens;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;
  final bool disabled;
  final VoidCallback? onActivate;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? onActivate : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: disabled ? 0.20 : 1,
        child: IgnorePointer(
          ignoring: disabled,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: tokens.elevated,
              borderRadius: BorderRadius.circular(FfTokens.radiusChip),
              border: Border.all(color: tokens.divider),
            ),
            child: Row(
              children: [
                _StepButton(
                    icon: PhosphorIconsRegular.minus, onTap: onDecrement, tokens: tokens),
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: FfTokens.inningValue.copyWith(color: tokens.text),
                  ),
                ),
                _StepButton(
                    icon: PhosphorIconsRegular.plus, onTap: onIncrement, tokens: tokens),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tokens,
    this.onTap,
  });

  final IconData icon;
  final FfTokens tokens;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: PhosphorIcon(
          icon,
          size: 15,
          color: tokens.text.withValues(alpha: 0.65),
        ),
      ),
    );
  }
}

class _MlbTimestampChip extends StatelessWidget {
  const _MlbTimestampChip({
    required this.enabled,
    required this.loading,
    required this.matched,
    required this.tokens,
    this.onTap,
  });

  final bool enabled;
  final bool loading;
  final bool matched;
  final FfTokens tokens;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final on = enabled;
    final labelColor = on ? tokens.accent : tokens.textSecondary;
    return Tooltip(
      message: on
          ? (matched
              ? 'MLB time is on. Inning matched from this photo. Tap to turn off.'
              : 'MLB time is on. Tap to turn off.')
          : 'MLB time is off. Tap to turn on.',
      child: Material(
        color: on ? tokens.selectedFill : tokens.badgeFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: on ? tokens.accent : tokens.divider,
          ),
        ),
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  PhosphorIcon(PhosphorIconsRegular.arrowsClockwise, size: 13, color: labelColor)
                else
                  Icon(
                    on ? PhosphorIconsRegular.clock : PhosphorIconsRegular.clock,
                    size: 13,
                    color: labelColor,
                  ),
                const SizedBox(width: 5),
                Text(
                  'MLB',
                  style: FfTokens.railLabel.copyWith(
                    letterSpacing: 0.4,
                    color: labelColor,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  on ? 'ON' : 'OFF',
                  style: FfTokens.railLabel.copyWith(
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: labelColor,
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

class _ToggleChip extends StatefulWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.tokens,
    this.onTap,
  });

  final String label;
  final bool selected;
  final FfTokens tokens;
  final VoidCallback? onTap;

  @override
  State<_ToggleChip> createState() => _ToggleChipState();
}

class _ToggleChipState extends State<_ToggleChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          height: double.infinity,
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          decoration: BoxDecoration(
            color: selected
                ? tokens.selected
                : (_hovered ? tokens.hover : tokens.bg),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? tokens.accent : tokens.divider,
            ),
            boxShadow:
                selected ? FfTokens.selectionGlow(tokens.accent) : null,
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              letterSpacing: 0,
              color: selected ? tokens.text : tokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;
  static const double _strokeWidth = 1;
  static const double _dash = 4;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dash;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
