import 'dart:convert';

import 'package:flutter/material.dart';

import '../caption_style/verb_sub_options.dart';
import '../flo_layout_constants.dart';
import '../utils/default_verb_keywords.dart';
import 'app_compact_checkbox.dart';
import 'app_styled_dialogs.dart';
import 'verb_edit_plural_field.dart';

/// Edit Verb dialog: category/verb browser + editor.
class FullVerbEditDialog extends StatefulWidget {
  const FullVerbEditDialog({
    super.key,
    required this.initialVerb,
    required this.sport,
    required this.categories,
    required this.verbsByCategory,
    required this.favoriteVerbs,
    required this.loadInitialData,
    required this.onSave,
    required this.onReset,
    required this.onFavoriteChanged,
    required this.hasSavedDefault,
    required this.isAdmin,
    required this.homeTeamName,
    required this.awayTeamName,
    this.homePlayer1Name,
    this.homePlayer1Jersey,
    this.homePlayer2Name,
    this.homePlayer2Jersey,
    this.awaySampleName,
    this.awaySampleJersey,
    this.selectedAwayPlayerLabel,
    this.onCategoryOrderChanged,
    this.onVerbOrderChanged,
  });

  final String initialVerb;
  final String sport;
  final List<String> categories;
  final Map<String, List<String>> verbsByCategory;
  final Set<String> favoriteVerbs;
  final Map<String, dynamic> Function(String verb) loadInitialData;
  final Future<void> Function({
    required String overrideKey,
    required String newLabel,
    required String newSingular,
    required String pluralText,
    required bool usePluralPhrase,
    required List<String> keywords,
    required bool wantsOpponent,
    required bool omitAgainst,
    required String selectedCategory,
    required VerbSubOptions subOptions,
    required bool asDefault,
  }) onSave;
  final Future<void> Function(String verb) onReset;
  final Future<void> Function(String verb, bool isFavorite) onFavoriteChanged;
  final Future<void> Function(List<String> categoryOrder)? onCategoryOrderChanged;
  final Future<void> Function(Map<String, List<String>> verbsByCategory)?
      onVerbOrderChanged;
  final bool Function(String verb) hasSavedDefault;
  final bool isAdmin;
  final String homeTeamName;
  final String awayTeamName;
  final String? homePlayer1Name;
  final String? homePlayer1Jersey;
  final String? homePlayer2Name;
  final String? homePlayer2Jersey;
  final String? awaySampleName;
  final String? awaySampleJersey;
  final String? selectedAwayPlayerLabel;

  @override
  State<FullVerbEditDialog> createState() => _FullVerbEditDialogState();
}

class _FullVerbEditDialogState extends State<FullVerbEditDialog> {
  late String _currentVerb;
  late String _browseCategory;
  late final TextEditingController _label;
  late final TextEditingController _singular;
  late final TextEditingController _plural;
  late final TextEditingController _keywords;
  late final TextEditingController _celebrationPhrase;
  late final TextEditingController _celebrationTypes;
  late final TextEditingController _grandSlamPhrase;
  late bool _omitAgainst;
  late bool _wantsOpponent;
  late bool _usePluralPhrase;
  late String _assignedCategory;
  late bool _isFavorite;
  late VerbSubOptions _subOptions;
  late Set<String> _favorites;
  /// Categories currently expanded in the cascaded browser.
  late Set<String> _expandedCategories;
  /// Mutable browser order (matches app; Favorites excluded).
  late List<String> _categories;
  late Map<String, List<String>> _verbsByCategory;
  String _snapshot = '';
  bool _busy = false;
  String _previewVariantId = 'no_opp';

  @override
  void initState() {
    super.initState();
    _categories = List<String>.from(widget.categories);
    _verbsByCategory = {
      for (final e in widget.verbsByCategory.entries)
        e.key: List<String>.from(e.value),
    };
    _favorites = Set<String>.from(widget.favoriteVerbs);
    _label = TextEditingController();
    _singular = TextEditingController();
    _plural = TextEditingController();
    _keywords = TextEditingController();
    _celebrationPhrase = TextEditingController();
    _celebrationTypes = TextEditingController();
    _grandSlamPhrase = TextEditingController();
    _currentVerb = widget.initialVerb;
    _browseCategory = _resolveBrowseCategory(widget.initialVerb);
    _expandedCategories = {_browseCategory};
    _loadVerb(widget.initialVerb, markClean: true);
  }

  @override
  void dispose() {
    _label.dispose();
    _singular.dispose();
    _plural.dispose();
    _keywords.dispose();
    _celebrationPhrase.dispose();
    _celebrationTypes.dispose();
    _grandSlamPhrase.dispose();
    super.dispose();
  }

  String _resolveBrowseCategory(String verb) {
    for (final cat in _categories) {
      final verbs = _verbsByCategory[cat] ?? const <String>[];
      if (verbs.contains(verb)) return cat;
    }
    return _categories.isNotEmpty ? _categories.first : '';
  }

  void _setText(TextEditingController controller, String text) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _loadVerb(
    String verb, {
    required bool markClean,
    bool keepBrowseCategory = false,
  }) {
    final initial = widget.loadInitialData(verb);
    final label = initial['label'] as String? ?? verb;
    final singular = initial['verbPhrase'] as String? ?? verb;
    final plural = initial['pluralPhrase'] as String? ?? singular;
    _currentVerb = verb;
    _setText(_label, label);
    _setText(_singular, singular);
    _setText(_plural, plural);
    _omitAgainst = initial['omitAgainst'] as bool? ?? false;
    _wantsOpponent = initial['wantsOpponent'] as bool? ?? true;
    _usePluralPhrase = initial['usePluralPhrase'] as bool? ?? true;
    final rawKw = initial['keywords'];
    final kwList = rawKw is List
        ? rawKw
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList()
        : <String>[];
    _setText(_keywords, kwList.join(', '));
    var cat = initial['category'] as String? ?? '';
    if (cat == 'Favorites' || !_categories.contains(cat)) {
      cat = _resolveBrowseCategory(verb);
    }
    if (!_categories.contains(cat) && _categories.isNotEmpty) {
      cat = _categories.first;
    }
    _assignedCategory = cat;
    _isFavorite = _favorites.contains(verb);
    _subOptions = initial['subOptions'] as VerbSubOptions? ??
        VerbSubOptions.defaultsFor(verb, sport: widget.sport);
    _setText(_celebrationPhrase, _subOptions.celebrationPhrase);
    _setText(_celebrationTypes, _subOptions.celebrationTypes);
    _setText(_grandSlamPhrase, _subOptions.grandSlamPhrase);

    final inCurrentBrowse =
        (_verbsByCategory[_browseCategory] ?? const <String>[])
            .contains(verb);
    if (!keepBrowseCategory || !inCurrentBrowse) {
      _browseCategory = _resolveBrowseCategory(verb);
    }
    if (_browseCategory.isNotEmpty) {
      _expandedCategories
        ..clear()
        ..add(_browseCategory);
    }
    _previewVariantId = 'no_opp';

    if (markClean) {
      _snapshot = _formFingerprint();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _snapshot = _formFingerprint();
      });
    }
  }

  String _formFingerprint() {
    return jsonEncode({
      'label': _label.text.trim(),
      'singular': _singular.text.trim(),
      'plural': _plural.text.trim(),
      'keywords': _keywords.text.trim(),
      'omitAgainst': _omitAgainst,
      'wantsOpponent': _wantsOpponent,
      'usePluralPhrase': _usePluralPhrase,
      'category': _assignedCategory,
      'subOptions': _liveSubOptions.toJson(),
    });
  }

  bool get _isDirty => _formFingerprint() != _snapshot;

  VerbSubOptions get _liveSubOptions => _subOptions.copyWith(
        celebrationPhrase: _celebrationPhrase.text,
        celebrationTypes: _celebrationTypes.text,
        grandSlamPhrase: _grandSlamPhrase.text,
      );

  String get _singularPhrase {
    final t = _singular.text.trim();
    return t.isEmpty ? _currentVerb : t;
  }

  String get _pluralPhrase {
    if (!_usePluralPhrase) return _singularPhrase;
    final t = _plural.text.trim();
    return t.isEmpty ? _singularPhrase : t;
  }

  String get _verbLabelForMods {
    final t = _label.text.trim();
    return t.isEmpty ? _currentVerb : t;
  }

  String get _hitNoun {
    switch (_currentVerb) {
      case 'Single':
        return 'single';
      case 'Double':
        return 'double';
      case 'Triple':
        return 'triple';
      case 'Home Run':
        return 'home run';
      case 'Sacrifice Fly':
        return 'sacrifice fly';
      case 'Bunt':
        return 'bunt';
      case 'Hit by Pitch':
        return 'hit by pitch';
      case 'Grand Slam':
        return 'grand slam';
      default:
        return _singularPhrase;
    }
  }

  List<_CaptionVariant> _previewVariants() {
    final variants = <_CaptionVariant>[
      const _CaptionVariant(id: 'no_opp', label: 'No opposing player'),
      const _CaptionVariant(id: 'singular', label: '1 player'),
    ];
    if (_usePluralPhrase) {
      variants.add(const _CaptionVariant(id: 'plural', label: '2+ players'));
    }

    final showRbi = VerbSubOptions.showRbiEditor(
      sport: widget.sport,
      verbLabel: _verbLabelForMods,
      value: _liveSubOptions,
    );
    final showCele = VerbSubOptions.showCelebrationEditor(
      verbLabel: _verbLabelForMods,
      value: _liveSubOptions,
    );
    final isHit = VerbSubOptions.isHitVerb(_currentVerb) ||
        VerbSubOptions.isHitVerb(_verbLabelForMods);

    if (showRbi && _liveSubOptions.rbiEnabled) {
      variants.add(const _CaptionVariant(id: 'rbi', label: 'RBI'));
    }
    final isHomeRun =
        _currentVerb == 'Home Run' || _verbLabelForMods == 'Home Run';
    if (isHomeRun) {
      variants.add(const _CaptionVariant(id: 'grand_slam', label: 'Grand Slam'));
    }
    if (showCele && _liveSubOptions.celebrationEnabled) {
      if (isHit) {
        variants.add(const _CaptionVariant(id: 'cele', label: 'Celebration'));
        if (_liveSubOptions.rbiEnabled) {
          variants.add(
            const _CaptionVariant(id: 'cele_rbi', label: 'Celebration · RBI'),
          );
        }
        if (isHomeRun) {
          variants.add(
            const _CaptionVariant(
              id: 'cele_grand_slam',
              label: 'Celebration · Grand Slam',
            ),
          );
        }
      } else if (VerbSubOptions.isCelebrationVerb(_verbLabelForMods)) {
        final chips = _liveSubOptions.celebrationTypeList(sport: widget.sport);
        final chip = chips.isNotEmpty ? chips.first : 'Scoring';
        variants.add(
          _CaptionVariant(id: 'cele_chip', label: 'Celebration · $chip'),
        );
      }
    }
    return variants;
  }

  String get _resolvedPreviewVariantId {
    final variants = _previewVariants();
    if (variants.any((v) => v.id == _previewVariantId)) {
      return _previewVariantId;
    }
    return variants.first.id;
  }

  String _subjectForPlayers(int playerCount) {
    final p1Name = widget.homePlayer1Name ?? 'Player One';
    final p1Jersey = widget.homePlayer1Jersey ?? '00';
    final p2Name = widget.homePlayer2Name ?? 'Player Two';
    final p2Jersey = widget.homePlayer2Jersey ?? '00';
    if (playerCount <= 1) {
      return '$p1Name #$p1Jersey of the ${widget.homeTeamName}';
    }
    return '$p1Name #$p1Jersey and $p2Name #$p2Jersey of the ${widget.homeTeamName}';
  }

  String _withOpponent(String base) {
    if (!_wantsOpponent) return base;
    final againstText = _omitAgainst ? '' : ' against';
    final selectedOpp = widget.selectedAwayPlayerLabel?.trim();
    if (selectedOpp != null && selectedOpp.isNotEmpty) {
      return '$base$againstText $selectedOpp of the ${widget.awayTeamName}';
    }
    if (widget.awaySampleName != null) {
      return '$base$againstText ${widget.awaySampleName} '
          '#${widget.awaySampleJersey ?? '00'} of the ${widget.awayTeamName}';
    }
    return '$base$againstText the ${widget.awayTeamName}';
  }

  /// Team only — no opposing player name (e.g. "… against the Yankees").
  String _withOpposingTeamOnly(String base) {
    final againstText = _omitAgainst ? '' : ' against';
    return '$base$againstText the ${widget.awayTeamName}';
  }

  String _actionPhraseForVariant(String id) {
    final live = _liveSubOptions;
    final cele = live.celebrationPhrase.trim().isEmpty
        ? 'celebrates'
        : live.celebrationPhrase.trim();
    switch (id) {
      case 'plural':
        return _pluralPhrase;
      case 'rbi':
        return live.hitClauseWithRbi(
          leadIn: 'hits a',
          hitNoun: _hitNoun,
          count: 2,
        );
      case 'grand_slam':
        return live.hitClauseWithGrandSlam(
          leadIn: 'hits a',
          hitNoun: _hitNoun,
        );
      case 'cele':
        return '$cele a $_hitNoun';
      case 'cele_rbi':
        return live.hitClauseWithRbi(
          leadIn: '$cele a',
          hitNoun: _hitNoun,
          count: 2,
        );
      case 'cele_grand_slam':
        return live.hitClauseWithGrandSlam(
          leadIn: '$cele a',
          hitNoun: _hitNoun,
        );
      case 'cele_chip':
        final chips = live.celebrationTypeList(sport: widget.sport);
        final chip = chips.isNotEmpty ? chips.first : 'Scoring';
        return '$cele $chip';
      case 'no_opp':
      case 'singular':
      default:
        return _singularPhrase;
    }
  }

  String _buildSelectedCaption() {
    final id = _resolvedPreviewVariantId;
    final players = id == 'plural' ? 2 : 1;
    final base = '${_subjectForPlayers(players)} ${_actionPhraseForVariant(id)}';
    if (id == 'no_opp') return _withOpposingTeamOnly(base);
    return _withOpponent(base);
  }

  Widget _buildCaptionPreview() {
    final variants = _previewVariants();
    final selectedId = _resolvedPreviewVariantId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Caption variant', style: kAppDialogFieldLabelStyle),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < variants.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _variantChip(
                  label: variants[i].label,
                  selected: variants[i].id == selectedId,
                  onTap: () =>
                      setState(() => _previewVariantId = variants[i].id),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        AppDialogExamplePreview(
          compact: true,
          title: 'Caption',
          text: _buildSelectedCaption(),
        ),
      ],
    );
  }

  Widget _variantChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? kFloTealSelectedFill : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: selected ? kFloTealDark : const Color(0xFFE0E0E0),
          width: selected ? 1.2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: kAppDialogFieldTextStyle.copyWith(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? kFloTealDark : const Color(0xFF555555),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmLeaveIfDirty() async {
    if (!_isDirty) return true;
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Unsaved changes',
      message:
          'You have unsaved changes for "$_currentVerb". Discard them and switch verbs?',
      cancelLabel: 'Stay',
      confirmLabel: 'Discard',
    );
    return result == true;
  }

  Future<void> _selectBrowseCategory(String category) async {
    setState(() {
      if (_expandedCategories.contains(category)) {
        _expandedCategories.remove(category);
      } else {
        _expandedCategories
          ..clear()
          ..add(category);
        _browseCategory = category;
      }
    });
  }

  Future<void> _selectVerb(String verb) async {
    if (verb == _currentVerb) return;
    if (!await _confirmLeaveIfDirty()) return;
    if (!mounted) return;
    setState(() {
      _loadVerb(verb, markClean: true, keepBrowseCategory: true);
    });
  }

  Future<void> _toggleFavorite() => _toggleFavoriteFor(_currentVerb);

  Future<void> _toggleFavoriteFor(String verb) async {
    final next = !_favorites.contains(verb);
    setState(() {
      if (next) {
        _favorites.add(verb);
      } else {
        _favorites.remove(verb);
      }
      if (verb == _currentVerb) {
        _isFavorite = next;
      }
    });
    await widget.onFavoriteChanged(verb, next);
  }

  Future<void> _save({required bool asDefault, bool closeAfter = false}) async {
    final newLabel = _label.text.trim();
    final newSingular = _singular.text.trim();
    if (newLabel.isEmpty || newSingular.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSave(
        overrideKey: _currentVerb,
        newLabel: newLabel,
        newSingular: newSingular,
        pluralText: _plural.text.trim(),
        usePluralPhrase: _usePluralPhrase,
        keywords: parseVerbKeywordsField(_keywords.text),
        wantsOpponent: _wantsOpponent,
        omitAgainst: _omitAgainst,
        selectedCategory: _assignedCategory,
        subOptions: _liveSubOptions,
        asDefault: asDefault,
      );
      if (!mounted) return;
      _snapshot = _formFingerprint();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            asDefault
                ? 'Saved "$newLabel" as default for this sport'
                : 'Saved "$newLabel"',
            style: const TextStyle(fontSize: 11),
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (closeAfter) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final hadSaved = widget.hasSavedDefault(_currentVerb);
      await widget.onReset(_currentVerb);
      if (!mounted) return;
      setState(() => _loadVerb(_currentVerb, markClean: true));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hadSaved
                ? 'Reset "$_currentVerb" to your saved default'
                : 'Reset "$_currentVerb" to factory default',
            style: const TextStyle(fontSize: 11),
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onCancel() async {
    if (_isDirty) {
      final ok = await showAppConfirmDialog(
        context: context,
        title: 'Discard changes?',
        message: 'Close without saving changes to "$_currentVerb"?',
        cancelLabel: 'Stay',
        confirmLabel: 'Discard',
      );
      if (ok != true || !mounted) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    // Leave room for teal title + action row inside the AlertDialog.
    final contentH = (screenH * 0.92) - 96;
    final hasSavedDefault = widget.hasSavedDefault(_currentVerb);

    return Center(
      child: SizedBox(
        width: kVerbEditDialogWidth,
        child: AlertDialog(
          shape: kAppDialogShape,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          clipBehavior: Clip.antiAlias,
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          title: AppDialogTealTitleBar(
            title: 'Edit Verb',
            trailing: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _busy ? null : _onCancel,
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 20, color: Colors.white70),
                ),
              ),
            ),
          ),
          content: SizedBox(
            width: kVerbEditDialogWidth - 32,
            height: contentH,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildBrowser(),
                const SizedBox(width: 12),
                Expanded(
                  child: SingleChildScrollView(
                    key: ValueKey('verb-editor-$_currentVerb'),
                    child: _buildEditor(),
                  ),
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actionsOverflowAlignment: OverflowBarAlignment.end,
          actionsOverflowButtonSpacing: 8,
          actions: [
            if (widget.isAdmin)
              Tooltip(
                message:
                    'Admin only: save this wording as the Reset baseline for ${widget.sport}',
                child: ElevatedGreyButton(
                  label: 'Set as Default · Admin',
                  fontSize: 11,
                  onPressed: _busy
                      ? null
                      : () => _save(asDefault: true, closeAfter: false),
                ),
              )
            else
              const SizedBox.shrink(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: hasSavedDefault
                      ? 'Restore this verb to your saved default for ${widget.sport}'
                      : 'Restore this verb to the built-in factory wording',
                  child: ElevatedGreyButton(
                    label: 'Reset to Default',
                    fontSize: 11,
                    onPressed: _busy ? null : _reset,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedGreyButton(
                  label: 'Cancel',
                  fontSize: 11,
                  onPressed: _busy ? null : _onCancel,
                ),
                const SizedBox(width: 8),
                ElevatedGreyButton(
                  label: 'Save',
                  fontSize: 11,
                  isPrimary: true,
                  onPressed: _busy
                      ? null
                      : () => _save(asDefault: false, closeAfter: false),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _persistCategoryOrder() async {
    final cb = widget.onCategoryOrderChanged;
    if (cb == null) return;
    await cb(List<String>.from(_categories));
  }

  Future<void> _persistVerbOrder() async {
    final cb = widget.onVerbOrderChanged;
    if (cb == null) return;
    await cb({
      for (final e in _verbsByCategory.entries)
        e.key: List<String>.from(e.value),
    });
  }

  Future<void> _reorderCategories(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    setState(() {
      final cat = _categories.removeAt(oldIndex);
      _categories.insert(newIndex, cat);
    });
    await _persistCategoryOrder();
  }

  Future<void> _reorderVerbsInCategory(
    String category,
    int oldIndex,
    int newIndex,
  ) async {
    final list = _verbsByCategory[category];
    if (list == null) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex < 0 || oldIndex >= list.length) return;
    if (newIndex < 0 || newIndex > list.length) return;
    if (oldIndex == newIndex) return;
    setState(() {
      final verb = list.removeAt(oldIndex);
      list.insert(newIndex, verb);
    });
    await _persistVerbOrder();
  }

  Future<void> _moveVerbToCategory(
    String verb,
    String toCategory, {
    bool selectAfter = true,
  }) async {
    if (verb.isEmpty || !_categories.contains(toCategory)) return;
    String? fromCategory;
    for (final e in _verbsByCategory.entries) {
      if (e.value.contains(verb)) {
        fromCategory = e.key;
        break;
      }
    }
    if (fromCategory == toCategory) {
      setState(() => _assignedCategory = toCategory);
      return;
    }
    setState(() {
      if (fromCategory != null) {
        _verbsByCategory[fromCategory]?.remove(verb);
      }
      final dest = _verbsByCategory.putIfAbsent(toCategory, () => <String>[]);
      if (!dest.contains(verb)) dest.add(verb);
      _assignedCategory = toCategory;
      _browseCategory = toCategory;
      _expandedCategories
        ..clear()
        ..add(toCategory);
    });
    await _persistVerbOrder();
    if (selectAfter && mounted && verb == _currentVerb) {
      setState(() {});
    }
  }

  Widget _buildBrowser() {
    return SizedBox(
      width: kVerbEditDialogBrowserWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8F9),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE4E4E4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 8, 10, 2),
              child: Text('Verbs', style: kAppDialogFieldLabelStyle),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Text(
                'Drag ≡ to reorder categories or verbs. Change Category to move a verb.',
                style: kAppDialogFieldTextStyle.copyWith(
                  fontSize: 9.5,
                  color: const Color(0xFF888888),
                  height: 1.25,
                ),
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: _categories.length,
                onReorder: (oldIndex, newIndex) {
                  _reorderCategories(oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  return _buildCascadedCategory(cat, index);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCascadedCategory(String cat, int categoryIndex) {
    final expanded = _expandedCategories.contains(cat);
    final verbs = (_verbsByCategory[cat] ?? const <String>[])
        .where((v) => v.trim().isNotEmpty)
        .toList();
    final categorySelected = cat == _browseCategory;
    return Material(
      key: ValueKey('verb-edit-cat-$cat'),
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: categorySelected && expanded
                ? kFloTealSelectedFill
                : Colors.transparent,
            child: InkWell(
              onTap: () => _selectBrowseCategory(cat),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color:
                          categorySelected ? kFloTealDark : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: categoryIndex,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(
                          Icons.drag_indicator,
                          size: 16,
                          color: Color(0xFFAAAAAA),
                        ),
                      ),
                    ),
                    Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: categorySelected
                          ? kFloTealDark
                          : const Color(0xFF666666),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        cat,
                        style: kAppDialogFieldTextStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          color: categorySelected
                              ? kFloTealDark
                              : const Color(0xFF333333),
                        ),
                      ),
                    ),
                    Text(
                      '${verbs.length}',
                      style: kAppDialogFieldTextStyle.copyWith(
                        fontSize: 10,
                        color: const Color(0xFF888888),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: verbs.length,
              onReorder: (oldIndex, newIndex) {
                _reorderVerbsInCategory(cat, oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final verb = verbs[index];
                return _buildCascadedVerbRow(verb, index);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCascadedVerbRow(String verb, int verbIndex) {
    final selected = verb == _currentVerb;
    final fav = _favorites.contains(verb);
    return Material(
      key: ValueKey('verb-edit-verb-$verb'),
      color: selected ? kFloTealSelectedFill : Colors.transparent,
      child: InkWell(
        onTap: () {
          _selectVerb(verb);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 5, 6, 5),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? kFloTealDark : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: verbIndex,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 14,
                    color: Color(0xFFBBBBBB),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  verb,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kAppDialogFieldTextStyle.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? kFloTealDark : const Color(0xFF333333),
                  ),
                ),
              ),
              Tooltip(
                message: fav ? 'Remove from favorites' : 'Add to favorites',
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _toggleFavoriteFor(verb),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      fav ? Icons.star : Icons.star_border,
                      size: 14,
                      color: fav
                          ? Colors.amber.shade700
                          : const Color(0xFFAAAAAA),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditor() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppDialogLabeledTextField(
                label: 'Display name',
                controller: _label,
                hintText: 'e.g., Skates',
                bottomGap: 0,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppDialogLabeledDropdown<String>(
                      label: 'Category',
                      value: _categories.contains(_assignedCategory)
                          ? _assignedCategory
                          : (_categories.isNotEmpty
                              ? _categories.first
                              : _assignedCategory),
                      items: _categories
                          .map((cat) => DropdownMenuItem(
                                value: cat,
                                child: Text(cat),
                              ))
                          .toList(),
                      onChanged: (value) async {
                        if (value == null) return;
                        await _moveVerbToCategory(_currentVerb, value);
                      },
                      bottomGap: 0,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(
                      top: kAppDialogLabelRowHeight + 5,
                      left: 4,
                    ),
                    child: SizedBox(
                      width: kAppDialogControlHeight,
                      height: kAppDialogControlHeight,
                      child: Tooltip(
                        message: _isFavorite
                            ? 'Remove from favorites'
                            : 'include in favorites',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: _toggleFavorite,
                          child: Icon(
                            _isFavorite ? Icons.star : Icons.star_border,
                            size: 20,
                            color: _isFavorite
                                ? Colors.amber.shade700
                                : const Color(0xFF888888),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildOptionsBox(),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppDialogLabeledTextField(
                label: 'Singular phrase (1 player)',
                controller: _singular,
                hintText: 'e.g., skates, battles, shoots',
                onChanged: (_) => setState(() {}),
                bottomGap: 0,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: VerbEditPluralPhraseField(
                pluralController: _plural,
                usePluralPhrase: _usePluralPhrase,
                onUsePluralChanged: (v) =>
                    setState(() => _usePluralPhrase = v),
                onPluralChanged: (_) => setState(() {}),
                bottomGap: 0,
              ),
            ),
          ],
        ),
        if (_currentVerb == 'Home Run' || _verbLabelForMods == 'Home Run') ...[
          const SizedBox(height: 10),
          AppDialogLabeledTextField(
            label: 'Grand Slam phrase',
            controller: _grandSlamPhrase,
            hintText: 'e.g., grand slam home run',
            onChanged: (_) => setState(() {}),
            bottomGap: 0,
          ),
        ],
        const SizedBox(height: 10),
        _buildCaptionPreview(),
        const SizedBox(height: 12),
        AppDialogLabeledField(
          label: 'Keywords',
          bottomGap: 0,
          child: TextField(
            controller: _keywords,
            style: kAppDialogFieldTextStyle,
            maxLines: 2,
            onChanged: (_) => setState(() {}),
            decoration: appDialogFieldDecoration(
              hintText: 'comma-separated',
            ),
          ),
        ),
      ],
    );
  }

  Widget _optionCheckbox({
    required bool value,
    required String label,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        AppCompactCheckbox(
          value: value,
          accentColor: kFloTealLight,
          onChanged: onChanged,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: kAppDialogFieldTextStyle),
        ),
      ],
    );
  }

  Widget _buildOptionsBox() {
    final showRbi = VerbSubOptions.showRbiEditor(
      sport: widget.sport,
      verbLabel: _verbLabelForMods,
      value: _subOptions,
    );
    final showCele = VerbSubOptions.showCelebrationEditor(
      verbLabel: _verbLabelForMods,
      value: _subOptions,
    );
    final showCeleTypes =
        showCele && VerbSubOptions.isCelebrationVerb(_verbLabelForMods);
    final chipsHint =
        VerbSubOptions.defaultCelebrationTypesForSport(widget.sport);

    final checks = <Widget>[
      Expanded(
        child: _optionCheckbox(
          value: _wantsOpponent,
          label: 'Include opponent',
          onChanged: (v) => setState(() => _wantsOpponent = v),
        ),
      ),
      Expanded(
        child: _optionCheckbox(
          value: _omitAgainst,
          label: 'Omit "against"',
          onChanged: (v) => setState(() => _omitAgainst = v),
        ),
      ),
      if (showRbi)
        Expanded(
          child: _optionCheckbox(
            value: _subOptions.rbiEnabled,
            label: 'RBI',
            onChanged: (v) =>
                setState(() => _subOptions = _subOptions.copyWith(rbiEnabled: v)),
          ),
        ),
      if (showCele)
        Expanded(
          child: _optionCheckbox(
            value: _subOptions.celebrationEnabled,
            label: 'Celebration',
            onChanged: (v) => setState(
              () => _subOptions = _subOptions.copyWith(celebrationEnabled: v),
            ),
          ),
        ),
    ];

    // Two rows if all four are present so labels stay readable.
    final Widget checkRows;
    if (checks.length <= 2) {
      checkRows = Row(children: _withGaps(checks));
    } else if (checks.length == 3) {
      checkRows = Column(
        children: [
          Row(children: _withGaps(checks.sublist(0, 2))),
          const SizedBox(height: 6),
          Row(children: [checks[2], const Spacer(), const Spacer()]),
        ],
      );
    } else {
      checkRows = Column(
        children: [
          Row(children: _withGaps(checks.sublist(0, 2))),
          const SizedBox(height: 6),
          Row(children: _withGaps(checks.sublist(2))),
        ],
      );
    }

    final fieldChildren = <Widget>[];
    if (showRbi && _subOptions.rbiEnabled) {
      fieldChildren.add(
        Expanded(
          child: AppDialogLabeledDropdown<RbiCaptionStyle>(
            label: 'RBI style',
            value: _subOptions.rbiStyle,
            items: RbiCaptionStyle.values
                .map(
                  (s) => DropdownMenuItem<RbiCaptionStyle>(
                    value: s,
                    child: Text(s.menuLabel),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) {
                setState(
                  () => _subOptions = _subOptions.copyWith(rbiStyle: v),
                );
              }
            },
            bottomGap: 0,
          ),
        ),
      );
    }
    if (showCele && _subOptions.celebrationEnabled) {
      fieldChildren.add(
        Expanded(
          child: AppDialogLabeledTextField(
            label: 'Celebration verb',
            controller: _celebrationPhrase,
            hintText: 'e.g., celebrates',
            bottomGap: 0,
            onChanged: (_) => setState(() {}),
          ),
        ),
      );
    }

    return AppDialogLabeledField(
      label: 'Options',
      bottomGap: 0,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: appDialogCardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            checkRows,
            if (fieldChildren.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: _withGaps(fieldChildren)),
            ],
            if (showCeleTypes && _subOptions.celebrationEnabled) ...[
              const SizedBox(height: 8),
              AppDialogLabeledTextField(
                label: 'Celebration chips (comma-separated)',
                controller: _celebrationTypes,
                hintText: chipsHint,
                maxLines: 2,
                bottomGap: 0,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _withGaps(List<Widget> items) {
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) out.add(const SizedBox(width: 12));
      out.add(items[i]);
    }
    return out;
  }
}

class _CaptionVariant {
  const _CaptionVariant({required this.id, required this.label});

  final String id;
  final String label;
}
