import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/mlb_api_service.dart';

/// Guided keyboard flow: pick main-team players → optional other-team players → pick verb by numbers.
class KeyboardFireDialog extends StatefulWidget {
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
  State<KeyboardFireDialog> createState() => _KeyboardFireDialogState();
}

class _KeyboardFireDialogState extends State<KeyboardFireDialog> {
  int _step = 0;
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final TextEditingController _homeBarController = TextEditingController();
  final TextEditingController _awayBarController = TextEditingController();
  final TextEditingController _verbBarController = TextEditingController();
  final FocusNode _homeBarFocus = FocusNode();
  final FocusNode _awayBarFocus = FocusNode();
  final FocusNode _verbBarFocus = FocusNode();
  String _homeSummary = '';
  String _awaySummary = '';
  String _verbSummary = '';
  bool _waitingForVerb = true;

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
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    _homeBarController.dispose();
    _awayBarController.dispose();
    _verbBarController.dispose();
    _homeBarFocus.dispose();
    _awayBarFocus.dispose();
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
      _verbBarFocus.requestFocus();
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
    _verbBarFocus.requestFocus();
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
    });
    _refreshCaptionPreviewLater();
  }

  void _refreshCaptionPreviewLater() {
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() {});
    });
  }

  void _done() {
    widget.captionState?.updateCaptionFromKeyboardFire();
    Navigator.of(context).pop();
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

  Widget _buildCaptionPreview() {
    final state = widget.captionState;
    if (state == null) {
      return Text(
        'Caption will appear here as you add players and a verb.',
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey.shade600,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    try {
      final notifier = (state as dynamic).keyboardFireCaptionNotifier;
      if (notifier != null && notifier is ValueNotifier<String>) {
        return ValueListenableBuilder<String>(
          valueListenable: notifier,
          builder: (_, captionText, __) {
            final empty = captionText.isEmpty;
            return Text(
              empty ? 'Caption will appear here as you add players and a verb.' : captionText,
              style: TextStyle(
                fontSize: 12,
                color: empty ? Colors.grey.shade600 : Colors.black87,
                fontStyle: empty ? FontStyle.italic : FontStyle.normal,
              ),
            );
          },
        );
      }
    } catch (_) {}
    final captionText = _captionPreview;
    final empty = captionText.isEmpty;
    return Text(
      empty ? 'Caption will appear here as you add players and a verb.' : captionText,
      style: TextStyle(
        fontSize: 12,
        color: empty ? Colors.grey.shade600 : Colors.black87,
        fontStyle: empty ? FontStyle.italic : FontStyle.normal,
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
      return [];
    } catch (_) {
      return [];
    }
  }

  Widget _buildRosterSection(String teamLabel, List<Player> roster) {
    if (roster.isEmpty) return const SizedBox.shrink();
    final sorted = List<Player>.from(roster)
      ..sort((a, b) {
        final an = int.tryParse(a.jerseyNumber ?? '') ?? 999;
        final bn = int.tryParse(b.jerseyNumber ?? '') ?? 999;
        return an.compareTo(bn);
      });
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Text(
            teamLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        ...sorted.map((p) {
          final num = p.jerseyNumber ?? '—';
          final raw = p.displayName;
          final name = raw.replaceFirst(RegExp(r' #\d+$'), '').trim();
          final displayName = name.isEmpty ? raw : name;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          );
        }),
      ],
    );
  }

  Widget _buildColumnBar({
    required TextEditingController controller,
    required FocusNode focusNode,
    required void Function() onSubmitted,
    List<TextInputFormatter>? inputFormatters,
    void Function(String)? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: TextField(
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
      ),
    );
  }

  Widget _buildRosterColumn(String teamLabel, List<Player> roster) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: _buildRosterSection(teamLabel, roster),
      ),
    );
  }

  Widget _buildVerbListWidget() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(8),
        children: _verbList.map((cat) {
          final catNum = cat['number'] as int? ?? 0;
          final name = cat['name'] as String? ?? '';
          final verbs = (cat['verbs'] as List<dynamic>?)?.cast<String>() ?? [];
          final isFavorites = name == 'Favorites';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Category header – match main app
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: isFavorites ? Colors.amber.shade200 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '$catNum. $name',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                // Verb options – same layout and style as main app _buildVerbOption
                ...verbs.asMap().entries.map((e) {
                  final verb = e.value;
                  final verbNum = e.key + 1; // 1-based, 10 for 10th
                  return _buildVerbOptionChip(verb, verbNum);
                }),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// One verb row matching main app _buildVerbOption styling (no tap/selection).
  Widget _buildVerbOptionChip(String verb, int verbNumber) {
    if (verb.trim().isEmpty) {
      return Container(
        width: double.infinity,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 6),
        margin: const EdgeInsets.only(bottom: 1),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.grey.shade200, width: 0.5),
        ),
        child: const Center(
          child: Text(
            '',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Colors.transparent,
            ),
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      margin: const EdgeInsets.only(bottom: 1),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.grey.shade300, width: 0.5),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.grey.shade500,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '$verbNumber',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Flexible(
              child: Text(
                verb,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: Colors.grey.shade400),
      ),
      backgroundColor: Colors.white,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 780),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade400),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.keyboard, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Keyboard fire mode',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Caption',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildCaptionPreview(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (widget.homeRoster.isNotEmpty ||
                widget.awayRoster.isNotEmpty ||
                _step == 2) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 420,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildRosterColumn(homeName, widget.homeRoster),
                          ),
                          _buildColumnBar(
                            controller: _homeBarController,
                            focusNode: _homeBarFocus,
                            onSubmitted: _onHomeBarSubmit,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildRosterColumn(awayName, widget.awayRoster),
                          ),
                          _buildColumnBar(
                            controller: _awayBarController,
                            focusNode: _awayBarFocus,
                            onSubmitted: _onAwayBarSubmit,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildVerbListWidget(),
                          ),
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
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
        ),
      ),
    );
  }
}
