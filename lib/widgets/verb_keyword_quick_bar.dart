import 'package:flutter/material.dart';

import '../utils/default_verb_keywords.dart';

/// Keyword shortcut chips. Tapping a chip toggles it:
///   - ON  → keywords are merged into [controller]; chip turns blue.
///   - OFF → those keywords are removed from [controller]; chip returns to grey.
/// Right-clicking fires [onContextMenu] with the chip index + global position.
class VerbKeywordQuickBar extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onInserted;

  /// Ordered list of shortcuts. Each entry has:
  ///   'label'    – String shown on the chip
  ///   'keywords' – List<dynamic> of keyword strings
  final List<Map<String, dynamic>> shortcuts;

  /// Called on right-click (secondary tap). Passes chip index + global position.
  final void Function(int index, Offset position)? onContextMenu;

  const VerbKeywordQuickBar({
    Key? key,
    required this.controller,
    required this.onInserted,
    required this.shortcuts,
    this.onContextMenu,
  }) : super(key: key);

  @override
  State<VerbKeywordQuickBar> createState() => _VerbKeywordQuickBarState();
}

class _VerbKeywordQuickBarState extends State<VerbKeywordQuickBar> {
  /// Indices of chips whose keywords are currently active in the field.
  final Set<int> _activeIndices = {};

  @override
  void didUpdateWidget(covariant VerbKeywordQuickBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the shortcuts list changed (e.g. after an edit/delete), clear stale
    // active indices that no longer correspond to valid chips.
    _activeIndices.removeWhere((i) => i >= widget.shortcuts.length);
  }

  List<String> _wordsFor(int index) =>
      (widget.shortcuts[index]['keywords'] as List?)
          ?.map((e) => e.toString())
          .toList() ??
      [];

  /// Remove a list of keywords (case-insensitive) from the field text.
  String _removeKeywords(String current, List<String> toRemove) {
    final removeSet = toRemove.map((k) => k.trim().toLowerCase()).toSet();
    final kept = parseVerbKeywordsField(current)
        .where((k) => !removeSet.contains(k.toLowerCase()))
        .toList();
    return kept.join(', ');
  }

  void _toggle(int index) {
    final words = _wordsFor(index);
    if (_activeIndices.contains(index)) {
      // Turn OFF — remove these keywords from the field.
      final updated = _removeKeywords(widget.controller.text, words);
      widget.controller.text = updated;
      widget.controller.selection =
          TextSelection.collapsed(offset: updated.length);
      setState(() => _activeIndices.remove(index));
    } else {
      // Turn ON — merge keywords into the field.
      final merged = mergeVerbKeywordFieldText(widget.controller.text, words);
      widget.controller.text = merged;
      widget.controller.selection =
          TextSelection.collapsed(offset: merged.length);
      setState(() => _activeIndices.add(index));
    }
    widget.onInserted();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        alignment: WrapAlignment.start,
        spacing: 3,
        runSpacing: 3,
        children: [
          for (int i = 0; i < widget.shortcuts.length; i++)
            _chip(i),
        ],
      ),
    );
  }

  Widget _chip(int index) {
    final label = widget.shortcuts[index]['label'] as String? ?? '';
    final words = _wordsFor(index);
    final isActive = _activeIndices.contains(index);
    final tip = words.join(', ');

    return GestureDetector(
      onSecondaryTapDown: widget.onContextMenu != null
          ? (d) => widget.onContextMenu!(index, d.globalPosition)
          : null,
      child: Tooltip(
        message: tip.isEmpty ? label : tip,
        waitDuration: const Duration(milliseconds: 400),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _toggle(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF1976D2)
                    : Colors.grey.shade100,
                border: Border.all(
                  color: isActive
                      ? const Color(0xFF1565C0)
                      : Colors.grey.shade400,
                ),
                borderRadius: BorderRadius.zero,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                  height: 1.0,
                  color: isActive ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
