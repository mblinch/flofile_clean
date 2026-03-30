import 'package:flutter/material.dart';

import '../utils/default_verb_keywords.dart';

/// Keyword shortcut chips: append preset groups (comma-separated) into [controller].
class VerbKeywordQuickBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onInserted;

  const VerbKeywordQuickBar({
    Key? key,
    required this.controller,
    required this.onInserted,
  }) : super(key: key);

  void _insert(List<String> words) {
    controller.text = mergeVerbKeywordFieldText(controller.text, words);
    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);
    onInserted();
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
          _chip('c', verbKeywordQuickGroupC),
          _chip('p', verbKeywordQuickGroupP),
          _chip('ps', verbKeywordQuickGroupPs),
          _chip('b', verbKeywordQuickGroupB),
          _chip('o', verbKeywordQuickGroupO),
          _chip('TPX', verbKeywordQuickTpx),
        ],
      ),
    );
  }

  /// Same body text size/weight as Keyboard Fire roster player names (fontSize 11).
  Widget _chip(String label, List<String> words) {
    final tip = words.join(', ');
    return Tooltip(
      message: tip.isEmpty ? label : tip,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _insert(words),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border.all(color: Colors.grey.shade400),
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
        ),
      ),
    );
  }
}
