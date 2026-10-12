import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Size of a structure text box. Width grows with the text until [maxWidth],
/// then the box grows taller and the text wraps.
class GrowingTextBoxSize {
  const GrowingTextBoxSize(this.width, this.height);

  final double width;
  final double height;

  static GrowingTextBoxSize measure({
    required String text,
    required TextStyle style,
    double minWidth = 36,
    double maxWidth = 400,
    double minHeight = 32,
    double horizontalPad = 16,
    double verticalPad = 10,
  }) {
    final visible = text.isEmpty ? ' ' : text;
    final innerMax = math.max(1.0, maxWidth - horizontalPad);
    final painter = TextPainter(
      text: TextSpan(text: visible, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: innerMax);
    final width = (painter.width + horizontalPad).clamp(minWidth, maxWidth);
    final height = math.max(minHeight, painter.height + verticalPad);
    return GrowingTextBoxSize(width, height);
  }
}

/// Visible mark for one stored space in a short separator. One caret stop.
const String kSpaceTokenSymbol = '␣';

/// True for a spacer or a one-word joiner (` at `, ` on `). A sentence keeps
/// normal spaces so it does not turn into a row of space marks.
bool showSpaceTokens(String text) {
  if (!text.contains(' ')) return false;
  return !text.trim().contains(' ');
}

/// Display form of [raw]. Spaces stay spaces once the box has more than one word.
String spaceTokenLabel(String raw) {
  if (raw.isEmpty || !showSpaceTokens(raw)) return raw;
  if (raw.trim().isEmpty) {
    return List.filled(raw.length, kSpaceTokenSymbol).join();
  }
  return raw.replaceAll(' ', kSpaceTokenSymbol);
}

/// Paints a short joiner's spaces as the open-box character, one caret stop
/// each. Longer text is drawn as typed. The stored text stays a real space.
TextSpan spaceTokenSpan(String text, TextStyle style) {
  if (!showSpaceTokens(text)) {
    return TextSpan(text: text, style: style);
  }
  return TextSpan(text: spaceTokenLabel(text), style: style);
}

/// [TextEditingController] that draws spaces with [spaceTokenSpan].
class SpaceTokenEditingController extends TextEditingController {
  SpaceTokenEditingController({super.text});

  /// Mirrors [source] so a field can paint space tokens without replacing the
  /// controller its parent already owns.
  SpaceTokenEditingController.mirror(TextEditingController source)
      : super.fromValue(source.value) {
    _source = source;
    source.addListener(_pull);
    addListener(_push);
  }

  TextEditingController? _source;
  var _busy = false;

  void retarget(TextEditingController source) {
    if (identical(_source, source)) return;
    _source?.removeListener(_pull);
    removeListener(_push);
    _source = source;
    _busy = true;
    value = source.value;
    _busy = false;
    source.addListener(_pull);
    addListener(_push);
  }

  void _pull() {
    final source = _source;
    if (source == null || _busy || value == source.value) return;
    _busy = true;
    value = source.value;
    _busy = false;
  }

  void _push() {
    final source = _source;
    if (source == null || _busy || source.value == value) return;
    _busy = true;
    source.value = value;
    _busy = false;
  }

  @override
  void dispose() {
    _source?.removeListener(_pull);
    removeListener(_push);
    _source = null;
    super.dispose();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return spaceTokenSpan(text, style ?? const TextStyle());
  }
}
