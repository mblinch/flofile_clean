import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../caption_style/sport_verb_categories.dart';
import '../caption_style/verb_authoring_model.dart';
import '../caption_style/verb_caption_wording.dart';
import '../caption_style/verb_defaults_bundle.dart';
import '../caption_style/verb_sub_options.dart';
import '../screens/caption_v2/data/caption_v2_caption_domain.dart';
import '../theme/ff_tokens.dart';
import '../utils/default_verb_keywords.dart';
import 'app_compact_checkbox.dart';
import 'app_styled_dialogs.dart';
import 'verb_edit_sub_options_section.dart';

typedef AdminVerbAction = Future<void> Function({
  required String key,
  required Map<String, dynamic> record,
  required bool isCustom,
});

class AdminVerbAuthoringEditor extends StatefulWidget {
  const AdminVerbAuthoringEditor({
    super.key,
    required this.sport,
    required this.sports,
    required this.bundle,
    required this.busy,
    required this.onSportChanged,
    required this.onBundleChanged,
    this.embedded = false,
    this.personalMode = false,
    this.initialVerbKey,
    this.createOnOpen = false,
    this.onPublishCurrentVerb,
    this.onWriteSportDefaults,
  });

  final String sport;
  final List<String> sports;
  final Map<String, dynamic> bundle;
  final bool busy;
  final bool embedded;
  /// Personal mode: same editor UI, saves via [onBundleChanged] only (no app
  /// defaults publish). Shows an account-save footer instead of Publish.
  final bool personalMode;
  final String? initialVerbKey;
  final bool createOnOpen;
  final ValueChanged<String> onSportChanged;
  final ValueChanged<Map<String, dynamic>> onBundleChanged;
  final AdminVerbAction? onPublishCurrentVerb;
  /// Publishes the full in-editor sport catalog to Firebase app defaults.
  final Future<void> Function({String? successLabel})? onWriteSportDefaults;

  @override
  State<AdminVerbAuthoringEditor> createState() =>
      _AdminVerbAuthoringEditorState();
}

class _AdminVerbAuthoringEditorState extends State<AdminVerbAuthoringEditor> {
  final FocusNode _nameFocus = FocusNode();
  final GlobalKey<_VerbEditorPaneState> _editorPaneKey =
      GlobalKey<_VerbEditorPaneState>();
  String? _selectedCategory;
  String? _selectedKey;
  String? _selectedGroupId;
  bool _renaming = false;
  int _sampleIndex = 0;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialVerbKey?.trim();
    if (initial != null && initial.isNotEmpty) {
      _selectedKey = initial;
      for (final verb in _allVerbs) {
        if (verb.key == initial) {
          _selectedCategory = verb.category;
          break;
        }
      }
    }
    _ensureSelection();
    if (widget.createOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _newVerb();
      });
    }
  }

  @override
  void didUpdateWidget(covariant AdminVerbAuthoringEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sport != widget.sport ||
        !identical(oldWidget.bundle, widget.bundle)) {
      _ensureSelection();
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _nameFocus.dispose();
    super.dispose();
  }

  FfTokens get _t => Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;

  List<String> get _categories {
    final raw = widget.bundle['categoryOrder'];
    final categories = raw is List
        ? raw.map((value) => value.toString()).toList()
        : SportVerbCategories.forSport(widget.sport).keys.toList();
    return categories
        .where((category) => category != 'Favorites')
        .toSet()
        .toList();
  }

  Set<String> get _favorites =>
      ((widget.bundle['favoriteVerbs'] as List?) ?? const [])
          .map((value) => value.toString())
          .toSet();

  Map<String, Map<String, dynamic>> get _overrides {
    final raw = widget.bundle['verbOverrides'];
    if (raw is! Map) return {};
    return raw.map(
      (key, value) => MapEntry(
        key.toString(),
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{},
      ),
    );
  }

  List<Map<String, dynamic>> get _customs =>
      ((widget.bundle['customVerbs'] as List?) ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();

  List<_VerbDraft> get _allVerbs {
    final deleted = ((widget.bundle['deletedVerbs'] as List?) ?? const [])
        .map((value) => value.toString())
        .toSet();
    // Personal editor keeps hidden defaults visible so they can be unhidden.
    final includeHidden = widget.personalMode;
    final overrides = _overrides;
    final customs = _customs;
    final byKey = <String, _VerbDraft>{};
    final catalogComplete = VerbDefaultsBundle.isComplete(widget.bundle);

    if (catalogComplete) {
      for (final entry in overrides.entries) {
        final hidden = deleted.contains(entry.key);
        if (hidden && !includeHidden) continue;
        byKey[entry.key] = _VerbDraft.fromRecord(
          key: entry.key,
          category: (entry.value['category'] ??
                  (_categories.isEmpty ? 'Other' : _categories.first))
              .toString(),
          record: entry.value,
          isCustom: false,
          isHidden: hidden,
          sport: widget.sport,
        );
      }
    } else {
      final factory = SportVerbCategories.forSport(widget.sport);
      for (final entry in factory.entries) {
        for (final key in entry.value) {
          if (key.trim().isEmpty) continue;
          final hidden = deleted.contains(key);
          if (hidden && !includeHidden) continue;
          final override = overrides[key] ?? const <String, dynamic>{};
          byKey[key] = _VerbDraft.fromRecord(
            key: key,
            category: (override['category'] ?? entry.key).toString(),
            record: override,
            isCustom: false,
            isHidden: hidden,
            sport: widget.sport,
          );
        }
      }
    }

    // Also surface factory defaults that were hidden and dropped from overrides.
    if (includeHidden) {
      final factory = SportVerbCategories.forSport(widget.sport);
      for (final entry in factory.entries) {
        for (final key in entry.value) {
          if (key.trim().isEmpty || byKey.containsKey(key)) continue;
          if (!deleted.contains(key)) continue;
          final override = overrides[key] ?? const <String, dynamic>{};
          byKey[key] = _VerbDraft.fromRecord(
            key: key,
            category: (override['category'] ?? entry.key).toString(),
            record: override,
            isCustom: false,
            isHidden: true,
            sport: widget.sport,
          );
        }
      }
    }

    for (final record in customs) {
      final key = (record['key'] ?? record['label'] ?? '').toString().trim();
      if (key.isEmpty || deleted.contains(key)) continue;
      byKey[key] = _VerbDraft.fromRecord(
        key: key,
        category: (record['category'] ??
                (_categories.isEmpty ? 'Other' : _categories.first))
            .toString(),
        record: record,
        isCustom: true,
        isHidden: false,
        sport: widget.sport,
      );
    }

    final orderRaw = widget.bundle['verbOrder'];
    final order = orderRaw is Map ? orderRaw : const {};
    final result = <_VerbDraft>[];
    final added = <String>{};
    for (final category in _categories) {
      final values = order[category];
      if (values is List) {
        for (final value in values) {
          final key = value.toString();
          final verb = byKey[key];
          if (verb != null && added.add(key)) result.add(verb);
        }
      }
      for (final verb in byKey.values) {
        if (verb.category == category && added.add(verb.key)) result.add(verb);
      }
    }
    for (final verb in byKey.values) {
      if (added.add(verb.key)) result.add(verb);
    }
    return result;
  }

  _VerbDraft? get _selectedVerb {
    final key = _selectedKey;
    if (key == null) return null;
    for (final verb in _allVerbs) {
      if (verb.key == key) return verb;
    }
    return null;
  }

  void _ensureSelection() {
    final categories = _categories;
    if (categories.isEmpty) return;
    if (!categories.contains(_selectedCategory)) {
      _selectedCategory = categories.first;
    }
    final visible =
        _allVerbs.where((verb) => verb.category == _selectedCategory).toList();
    if (!visible.any((verb) => verb.key == _selectedKey)) {
      _selectedKey = visible.isEmpty ? null : visible.first.key;
    }
    final verb = _selectedVerb;
    if (verb != null &&
        !verb.authoring.groups.any((group) => group.id == _selectedGroupId)) {
      _selectedGroupId =
          verb.authoring.groups.isEmpty ? null : verb.authoring.groups.first.id;
    }
  }

  Map<String, dynamic> _copyBundle() {
    return {
      ...widget.bundle,
      'categoryOrder': [..._categories],
      'favoriteVerbs': _favorites.toList(),
      'verbOverrides': {
        for (final entry in _overrides.entries)
          entry.key: Map<String, dynamic>.from(entry.value),
      },
      'customVerbs': _customs.map(Map<String, dynamic>.from).toList(),
    };
  }

  void _emit(Map<String, dynamic> bundle) {
    widget.onBundleChanged(bundle);
  }

  void _saveVerb(
    _VerbDraft draft, {
    Duration debounce = const Duration(milliseconds: 180),
  }) {
    _pendingDraft = draft;
    _saveDebounce?.cancel();
    if (debounce == Duration.zero) {
      _commitPendingDraft();
      return;
    }
    _saveDebounce = Timer(debounce, () {
      if (!mounted) return;
      _commitPendingDraft();
    });
  }

  _VerbDraft? _pendingDraft;

  void _commitPendingDraft() {
    final draft = _pendingDraft;
    _pendingDraft = null;
    if (draft == null) return;
    final bundle = _copyBundle();
    final record = draft.toRecord();
    if (draft.isCustom) {
      final list = ((bundle['customVerbs'] as List?) ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
      final index = list.indexWhere(
        (item) => (item['key'] ?? item['label']).toString() == draft.key,
      );
      if (index < 0) {
        list.add(record);
      } else {
        list[index] = record;
      }
      bundle['customVerbs'] = list;
    } else {
      final overrides = Map<String, dynamic>.from(
        (bundle['verbOverrides'] as Map?) ?? const {},
      );
      overrides[draft.key] = record;
      bundle['verbOverrides'] = overrides;
    }
    _emit(bundle);
  }

  _VerbDraft? _flushSelectedVerb() {
    // Pull the latest name/wording from the open editor before committing.
    final captured = _editorPaneKey.currentState?.captureDraft();
    if (captured != null) {
      _pendingDraft = captured;
      final name = captured.label.trim();
      if (captured.isCustom && name.isNotEmpty && name != captured.key) {
        _rename(captured, name);
        _saveDebounce?.cancel();
        _pendingDraft = null;
        return _allVerbs.where((verb) => verb.key == name).firstOrNull ??
            captured.copyWith(key: name);
      }
    }
    _saveDebounce?.cancel();
    final pending = _pendingDraft;
    if (pending != null) {
      _commitPendingDraft();
      return pending;
    }
    return _selectedVerb;
  }

  Future<void> _runCurrentVerbAction(AdminVerbAction? action) async {
    if (action == null) return;
    final verb = _flushSelectedVerb();
    if (verb == null) return;
    if (_renaming) setState(() => _renaming = false);
    await action(
      key: verb.key,
      record: verb.toRecord(),
      isCustom: verb.isCustom,
    );
  }

  void _selectVerbFromBrowser(String key) {
    // Commit any in-flight name/wording edits before swapping verbs.
    _flushSelectedVerb();
    if (_renaming) _renaming = false;
    _VerbDraft? match;
    for (final verb in _allVerbs) {
      if (verb.key == key) {
        match = verb;
        break;
      }
    }
    setState(() {
      if (match != null) _selectedCategory = match.category;
      _selectedKey = key;
      _selectedGroupId = _selectedVerb?.authoring.groups.firstOrNull?.id;
      _renaming = false;
    });
  }

  void _stepVerb(int delta) {
    final list = _allVerbs;
    if (list.isEmpty) return;
    final index = list.indexWhere((verb) => verb.key == _selectedKey);
    final nextIndex = index < 0
        ? 0
        : (index + delta + list.length) % list.length;
    _selectVerbFromBrowser(list[nextIndex].key);
  }

  Future<void> _openVerbPicker() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => _VerbJumpDialog(
        tokens: _t,
        verbs: _allVerbs,
        selectedKey: _selectedKey,
      ),
    );
    if (!mounted || selected == null) return;
    _selectVerbFromBrowser(selected);
  }

  void _rename(_VerbDraft verb, String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;
    // Prefer in-flight editor draft so rename doesn't drop wording edits.
    final base = (_pendingDraft != null && _pendingDraft!.key == verb.key)
        ? _pendingDraft!
        : verb;
    if (trimmed == base.label && (!verb.isCustom || trimmed == verb.key)) {
      return;
    }
    final updated = base.copyWith(label: trimmed);
    if (!verb.isCustom) {
      _saveVerb(updated, debounce: Duration.zero);
      return;
    }

    final oldKey = verb.key;
    final newKey = trimmed;
    final bundle = _copyBundle();
    final list = _customs;
    final index = list.indexWhere(
      (item) => (item['key'] ?? item['label']).toString() == oldKey,
    );
    final renamed = updated.copyWith(key: newKey);
    if (index >= 0) {
      list[index] = renamed.toRecord();
    } else {
      list.add(renamed.toRecord());
    }
    // Drop a stale pending draft still keyed by the old custom id.
    if (_pendingDraft?.key == oldKey) _pendingDraft = null;
    bundle['customVerbs'] = list;

    final favorites = _favorites;
    if (favorites.remove(oldKey)) favorites.add(newKey);
    bundle['favoriteVerbs'] = favorites.toList();

    final order = Map<String, dynamic>.from(
      (bundle['verbOrder'] as Map?) ?? const {},
    );
    for (final value in order.values) {
      if (value is! List) continue;
      final i = value.indexOf(oldKey);
      if (i >= 0) value[i] = newKey;
    }
    bundle['verbOrder'] = order;
    setState(() => _selectedKey = newKey);
    _emit(bundle);
  }

  void _newVerb() {
    final category = _selectedCategory ??
        (_categories.isEmpty ? 'Other' : _categories.first);
    var suffix = 1;
    var key = 'Untitled verb';
    final keys = _allVerbs.map((verb) => verb.key).toSet();
    while (keys.contains(key)) {
      suffix++;
      key = 'Untitled verb $suffix';
    }
    final draft = _VerbDraft(
      key: key,
      label: key,
      category: category,
      singular: '',
      plural: '',
      useSingularPhrase: true,
      usePluralPhrase: true,
      ing: '',
      keywords: const [],
      wantsOpponent: true,
      omitAgainst: false,
      opponentJoiner: 'against',
      withTeammates: false,
      subOptions: VerbSubOptions.defaultsFor(key, sport: widget.sport),
      isCustom: true,
      authoring: const VerbAuthoringData(
        phrase: VerbPhraseTemplate([VerbPhraseText('')]),
        groups: [],
      ),
      record: const {},
    );
    setState(() {
      _selectedKey = key;
      _renaming = true;
    });
    _saveVerb(draft, debounce: Duration.zero);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _nameFocus.requestFocus();
      if (!widget.personalMode) {
        unawaited(
          widget.onWriteSportDefaults?.call(successLabel: 'Added “$key”'),
        );
      }
    });
  }

  String _uniqueVerbName(String desired) {
    final base = desired.trim().isEmpty ? 'Untitled verb' : desired.trim();
    final taken = <String>{
      for (final verb in _allVerbs) ...[
        verb.key.toLowerCase(),
        verb.label.toLowerCase(),
      ],
    };
    if (!taken.contains(base.toLowerCase())) return base;
    var suffix = 2;
    while (taken.contains('$base $suffix'.toLowerCase())) {
      suffix++;
    }
    return '$base $suffix';
  }

  Future<void> _duplicateVerb() async {
    final source = _flushSelectedVerb();
    if (source == null) return;
    final initialName = _uniqueVerbName('${source.label} duplicate');
    final result = await showDialog<_DuplicateVerbResult>(
      context: context,
      builder: (context) => _DuplicateVerbDialog(
        tokens: _t,
        sourceLabel: source.label,
        initialName: initialName,
        singular: source.singular,
        plural: source.plural,
        ing: source.ing,
      ),
    );
    if (result == null || !mounted) return;
    final key = _uniqueVerbName(result.name);
    final draft = _VerbDraft(
      key: key,
      label: key,
      category: source.category,
      singular: result.singular,
      plural: result.plural,
      useSingularPhrase: source.useSingularPhrase,
      usePluralPhrase: source.usePluralPhrase,
      ing: result.ing,
      keywords: List<String>.from(source.keywords),
      wantsOpponent: source.wantsOpponent,
      omitAgainst: source.omitAgainst,
      opponentJoiner: source.opponentJoiner,
      withTeammates: source.withTeammates,
      subOptions: source.subOptions,
      isCustom: true,
      authoring: source.authoring,
      record: const {},
    );
    final bundle = _copyBundle();
    final customs = _customs..add(draft.toRecord());
    bundle['customVerbs'] = customs;
    final order = Map<String, dynamic>.from(
      (bundle['verbOrder'] as Map?) ?? const {},
    );
    final categoryList = List<String>.from(
      (order[source.category] as List?) ?? const <String>[],
    );
    if (!categoryList.contains(key)) {
      final sourceIndex = categoryList.indexOf(source.key);
      if (sourceIndex >= 0) {
        categoryList.insert(sourceIndex + 1, key);
      } else {
        categoryList.add(key);
      }
      order[source.category] = categoryList;
      bundle['verbOrder'] = order;
    }
    _emit(bundle);
    // Select after the parent bundle lands so the copy is in [_allVerbs].
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedKey = key;
        _selectedCategory = source.category;
        _renaming = false;
      });
      if (!widget.personalMode) {
        unawaited(
          widget.onWriteSportDefaults?.call(successLabel: 'Added “$key”'),
        );
      }
    });
  }

  Future<void> _deleteVerb([_VerbDraft? target]) async {
    final verb = target ?? _flushSelectedVerb();
    if (verb == null) return;
    final t = _t;
    // Personal mode: defaults are hidden (per-user), customs are deleted.
    // Admin mode keeps delete language for both, and clears factory overrides.
    final hideDefault = widget.personalMode && !verb.isCustom;
    // Hide is immediate; only real deletes ask for confirmation.
    if (!hideDefault) {
      final title = 'Delete “${verb.label}”?';
      final body = verb.isCustom
          ? 'Removes this custom verb from your catalog.'
          : 'Hides this default verb from the catalog. '
              'Saved captions keep their rendered text.';
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AppDialogFfStyle(
          enabled: true,
          child: Theme(
            data: Theme.of(context).copyWith(
              extensions: <ThemeExtension<dynamic>>[t],
            ),
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(24),
              child: Container(
                width: 400,
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
                  border: Border.all(color: t.divider),
                  boxShadow: [
                    BoxShadow(
                      color: t.bg.withValues(alpha: 0.55),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontFamily: FfTokens.labelFamily,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                                color: t.text,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              body,
                              style: t.metaStyle.copyWith(
                                color: t.text.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: t.divider),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                        child: Row(
                          children: [
                            const Spacer(),
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(
                                'Cancel',
                                style: t.metaStyle.copyWith(
                                  color: t.text.withValues(alpha: 0.62),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedGreyButton(
                              label: 'Delete verb',
                              fontSize: 11,
                              isDanger: true,
                              onPressed: () => Navigator.pop(context, true),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      if (ok != true || !mounted) return;
    }
    if (_pendingDraft?.key == verb.key) _pendingDraft = null;
    final bundle = _copyBundle();
    if (verb.isCustom) {
      bundle['customVerbs'] = _customs
          .where(
            (item) => (item['key'] ?? item['label']).toString() != verb.key,
          )
          .toList();
      final overrides = Map<String, dynamic>.from(
        (bundle['verbOverrides'] as Map?) ?? const {},
      )..remove(verb.key);
      bundle['verbOverrides'] = overrides;
    } else {
      final deleted = ((bundle['deletedVerbs'] as List?) ?? const [])
          .map((value) => value.toString())
          .toSet()
        ..add(verb.key);
      bundle['deletedVerbs'] = deleted.toList();
      // Personal hide keeps per-user wording overrides; admin delete clears them.
      if (!widget.personalMode) {
        final overrides = Map<String, dynamic>.from(
          (bundle['verbOverrides'] as Map?) ?? const {},
        )..remove(verb.key);
        bundle['verbOverrides'] = overrides;
      }
    }
    final order = Map<String, dynamic>.from(
      (bundle['verbOrder'] as Map?) ?? const {},
    );
    for (final entry in order.entries.toList()) {
      if (entry.value is! List) continue;
      final list = List<String>.from(entry.value as List)..remove(verb.key);
      order[entry.key] = list;
    }
    bundle['verbOrder'] = order;
    final favorites = _favorites..remove(verb.key);
    bundle['favoriteVerbs'] = favorites.toList();
    // Keep selection on a personally hidden default so Unhide is one click away.
    if (hideDefault) _selectedKey = verb.key;
    _emit(bundle);
    setState(_ensureSelection);
    if (!widget.personalMode) {
      unawaited(
        widget.onWriteSportDefaults?.call(
          successLabel: hideDefault
              ? 'Hidden “${verb.label}”'
              : 'Removed “${verb.label}”',
        ),
      );
    }
  }

  void _unhideVerb(_VerbDraft verb) {
    if (!verb.isHidden) return;
    final bundle = _copyBundle();
    final deleted = ((bundle['deletedVerbs'] as List?) ?? const [])
        .map((value) => value.toString())
        .toSet()
      ..remove(verb.key);
    bundle['deletedVerbs'] = deleted.toList();

    final order = Map<String, dynamic>.from(
      (bundle['verbOrder'] as Map?) ?? const {},
    );
    for (final entry in order.entries.toList()) {
      if (entry.value is! List) continue;
      final list = List<String>.from(entry.value as List)..remove(verb.key);
      order[entry.key] = list;
    }
    final category = verb.category.trim().isEmpty
        ? (_categories.isEmpty ? 'Other' : _categories.first)
        : verb.category;
    final list = List<String>.from((order[category] as List?) ?? const []);
    if (!list.contains(verb.key)) list.add(verb.key);
    order[category] = list;
    bundle['verbOrder'] = order;

    // Ensure a factory/default override record exists after unhide.
    if (!verb.isCustom) {
      final overrides = Map<String, dynamic>.from(
        (bundle['verbOverrides'] as Map?) ?? const {},
      );
      overrides.putIfAbsent(verb.key, () => verb.toRecord());
      bundle['verbOverrides'] = overrides;
    }

    _selectedKey = verb.key;
    _selectedCategory = category;
    _emit(bundle);
    setState(_ensureSelection);
  }

  void _updateAuthoring(_VerbDraft verb, VerbAuthoringData authoring) {
    final defaults = {
      for (final group in authoring.groups) group.id: group.defaultOptionId,
    };
    final singular = authoring.phrase.resolve(authoring.groups, defaults);
    _saveVerb(
      verb.copyWith(
        singular: singular,
        authoring: authoring,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final all = _allVerbs;
    final verb = _selectedVerb;

    final body = Column(
      children: [
        _Header(
          tokens: t,
          sport: widget.sport,
          sports: widget.sports,
          busy: widget.busy,
          categoryLabel: verb?.category ?? _selectedCategory,
          verbLabel: verb?.label,
          canStep: all.isNotEmpty,
          onSportChanged: widget.onSportChanged,
          onOpenPicker: _openVerbPicker,
          onPrevious: () => _stepVerb(-1),
          onNext: () => _stepVerb(1),
          onNewVerb: _newVerb,
          onDuplicateVerb: verb == null ? null : _duplicateVerb,
          onDeleteVerb: verb == null
              ? null
              : verb.isHidden
                  ? () => _unhideVerb(verb)
                  : () => _deleteVerb(verb),
          deleteActionIsHide:
              widget.personalMode && verb != null && !verb.isCustom,
          deleteActionIsUnhide: verb?.isHidden == true,
        ),
        Expanded(
          child: verb == null
              ? Center(
                  child: Text(
                    'Choose a verb',
                    style: t.metaStyle,
                  ),
                )
              : _VerbEditorPane(
                  key: _editorPaneKey,
                  tokens: t,
                  sport: widget.sport,
                  verb: verb,
                  selectedGroupId: _selectedGroupId,
                  renaming: _renaming,
                  nameFocus: _nameFocus,
                  sampleIndex: _sampleIndex,
                  onRenameMode: () => setState(() => _renaming = true),
                  onRename: (value) {
                    _rename(verb, value);
                    setState(() => _renaming = false);
                  },
                  onGroupSelected: (id) =>
                      setState(() => _selectedGroupId = id),
                  onAuthoringChanged: (value) =>
                      _updateAuthoring(verb, value),
                  onDraftChanged: _saveVerb,
                  onShuffle: () => setState(() => _sampleIndex++),
                ),
        ),
        if (widget.onPublishCurrentVerb != null)
          _VerbActionBar(
            tokens: t,
            busy: widget.busy,
            hasSelection: verb != null,
            onPublish: () => _runCurrentVerbAction(widget.onPublishCurrentVerb),
          ),
      ],
    );

    if (widget.embedded) {
      return ColoredBox(color: t.bg, child: body);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.bg,
        border: Border.all(color: t.divider),
        borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
        child: body,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.tokens,
    required this.sport,
    required this.sports,
    required this.busy,
    required this.categoryLabel,
    required this.verbLabel,
    required this.canStep,
    required this.onSportChanged,
    required this.onOpenPicker,
    required this.onPrevious,
    required this.onNext,
    required this.onNewVerb,
    this.onDuplicateVerb,
    this.onDeleteVerb,
    this.deleteActionIsHide = false,
    this.deleteActionIsUnhide = false,
  });

  final FfTokens tokens;
  final String sport;
  final List<String> sports;
  final bool busy;
  final String? categoryLabel;
  final String? verbLabel;
  final bool canStep;
  final ValueChanged<String> onSportChanged;
  final VoidCallback onOpenPicker;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onNewVerb;
  final VoidCallback? onDuplicateVerb;
  final VoidCallback? onDeleteVerb;
  /// When true, the destructive header action is labeled Hide (default verbs
  /// in personal mode) instead of Delete.
  final bool deleteActionIsHide;
  /// When true, the action restores a hidden default (Unhide).
  final bool deleteActionIsUnhide;

  @override
  Widget build(BuildContext context) {
    final crumbCategory = (categoryLabel ?? '').trim();
    final crumbVerb = (verbLabel ?? '').trim();
    final hasCrumb = crumbCategory.isNotEmpty || crumbVerb.isNotEmpty;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.divider)),
      ),
      child: Row(
        children: [
          Text(
            'VERB EDITOR',
            style: FfTokens.railLabel.copyWith(
              color: tokens.text.withValues(alpha: 0.70),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 32,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: sport,
                dropdownColor: tokens.surface,
                style: tokens.metaStyle.copyWith(color: tokens.text),
                borderRadius: BorderRadius.circular(7),
                items: sports
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(SportVerbCategories.displayLabel(item)),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (value) => value == null ? null : onSportChanged(value),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: tokens.bg,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: busy ? null : onOpenPicker,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: tokens.divider),
                  ),
                  child: Row(
                    children: [
                      PhosphorIcon(
                        PhosphorIconsRegular.magnifyingGlass,
                        size: 14,
                        color: tokens.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '/',
                        style: tokens.metaStyle.copyWith(
                          color: tokens.text.withValues(alpha: 0.40),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: hasCrumb
                            ? Text.rich(
                                TextSpan(
                                  style: tokens.metaStyle,
                                  children: [
                                    if (crumbCategory.isNotEmpty)
                                      TextSpan(
                                        text: crumbCategory,
                                        style: TextStyle(
                                          color: tokens.text
                                              .withValues(alpha: 0.48),
                                        ),
                                      ),
                                    if (crumbCategory.isNotEmpty &&
                                        crumbVerb.isNotEmpty)
                                      TextSpan(
                                        text: ' ',
                                        style: TextStyle(
                                          color: tokens.text
                                              .withValues(alpha: 0.48),
                                        ),
                                      ),
                                    if (crumbVerb.isNotEmpty)
                                      TextSpan(
                                        text: crumbVerb,
                                        style: TextStyle(
                                          color: deleteActionIsUnhide
                                              ? tokens.text
                                                  .withValues(alpha: 0.55)
                                              : tokens.text,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    if (deleteActionIsUnhide)
                                      TextSpan(
                                        text: '  · hidden',
                                        style: TextStyle(
                                          color: tokens.text
                                              .withValues(alpha: 0.40),
                                          fontWeight: FontWeight.w500,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : Text(
                                'Jump to verb',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tokens.metaStyle.copyWith(
                                  color: tokens.textSecondary,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _HeaderIconButton(
            tokens: tokens,
            icon: Icons.chevron_left,
            tooltip: 'Previous verb',
            onPressed: busy || !canStep ? null : onPrevious,
          ),
          _HeaderIconButton(
            tokens: tokens,
            icon: Icons.chevron_right,
            tooltip: 'Next verb',
            onPressed: busy || !canStep ? null : onNext,
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              onPressed: busy || onDuplicateVerb == null
                  ? null
                  : onDuplicateVerb,
              icon: PhosphorIcon(
                PhosphorIconsRegular.copy,
                size: 13,
                color: onDuplicateVerb == null
                    ? tokens.text.withValues(alpha: 0.28)
                    : tokens.text.withValues(alpha: 0.72),
              ),
              label: const Text('Duplicate'),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.text.withValues(alpha: 0.80),
                side: BorderSide(color: tokens.divider),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              onPressed:
                  busy || onDeleteVerb == null ? null : onDeleteVerb,
              icon: PhosphorIcon(
                deleteActionIsUnhide
                    ? PhosphorIconsRegular.eye
                    : deleteActionIsHide
                        ? PhosphorIconsRegular.eyeSlash
                        : PhosphorIconsRegular.trash,
                size: 13,
                color: onDeleteVerb == null
                    ? tokens.text.withValues(alpha: 0.28)
                    : deleteActionIsUnhide
                        ? tokens.text.withValues(alpha: 0.72)
                        : const Color(0xFFFF6B6B),
              ),
              label: Text(
                deleteActionIsUnhide
                    ? 'Unhide'
                    : deleteActionIsHide
                        ? 'Hide'
                        : 'Delete',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: onDeleteVerb == null
                    ? tokens.text.withValues(alpha: 0.28)
                    : deleteActionIsUnhide
                        ? tokens.text.withValues(alpha: 0.80)
                        : const Color(0xFFFF6B6B),
                side: BorderSide(
                  color: onDeleteVerb == null
                      ? tokens.divider
                      : deleteActionIsUnhide
                          ? tokens.divider
                          : const Color(0x55FF6B6B),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: OutlinedButton.icon(
              onPressed: busy ? null : onNewVerb,
              icon: PhosphorIcon(
                PhosphorIconsRegular.plus,
                size: 13,
                color: tokens.accent,
              ),
              label: const Text('New verb'),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.accent,
                side: BorderSide(color: tokens.accent),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DuplicateVerbResult {
  const _DuplicateVerbResult({
    required this.name,
    required this.singular,
    required this.plural,
    required this.ing,
  });

  final String name;
  final String singular;
  final String plural;
  final String ing;
}

class _DuplicateVerbDialog extends StatefulWidget {
  const _DuplicateVerbDialog({
    required this.tokens,
    required this.sourceLabel,
    required this.initialName,
    required this.singular,
    required this.plural,
    required this.ing,
  });

  final FfTokens tokens;
  final String sourceLabel;
  final String initialName;
  final String singular;
  final String plural;
  final String ing;

  @override
  State<_DuplicateVerbDialog> createState() => _DuplicateVerbDialogState();
}

class _DuplicateVerbDialogState extends State<_DuplicateVerbDialog> {
  late final TextEditingController _name;
  late final TextEditingController _singular;
  late final TextEditingController _plural;
  late final TextEditingController _ing;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _singular = TextEditingController(text: widget.singular);
    _plural = TextEditingController(text: widget.plural);
    _ing = TextEditingController(text: widget.ing);
  }

  @override
  void dispose() {
    _name.dispose();
    _singular.dispose();
    _plural.dispose();
    _ing.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      _DuplicateVerbResult(
        name: name,
        singular: _singular.text.trim(),
        plural: _plural.text.trim(),
        ing: _ing.text.trim(),
      ),
    );
  }

  Widget _field({
    required FfTokens tokens,
    required String label,
    required TextEditingController controller,
    bool autofocus = false,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
  }) {
    return AppDialogLabeledField(
      label: label,
      bottomGap: 10,
      child: AppDialogControlShell(
        child: TextField(
          controller: controller,
          autofocus: autofocus,
          style: tokens.metaStyle.copyWith(
            fontSize: 11,
            color: tokens.text,
            height: 1.25,
          ),
          cursorColor: tokens.accent,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          decoration: appDialogBareFieldDecoration(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final canCreate = _name.text.trim().isNotEmpty;
    return AppDialogFfStyle(
      enabled: true,
      child: Theme(
        data: Theme.of(context).copyWith(extensions: <ThemeExtension<dynamic>>[t]),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 440,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
              border: Border.all(color: t.divider),
              boxShadow: [
                BoxShadow(
                  color: t.bg.withValues(alpha: 0.55),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Duplicate “${widget.sourceLabel}”',
                                style: TextStyle(
                                  fontFamily: FfTokens.labelFamily,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                  color: t.text,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Rename the copy and set its wording.',
                                style: t.metaStyle.copyWith(
                                  color: t.text.withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cancel',
                          onPressed: () => Navigator.pop(context),
                          icon: PhosphorIcon(
                            PhosphorIconsRegular.x,
                            size: 16,
                            color: t.text.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: t.divider),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _field(
                          tokens: t,
                          label: 'Verb name',
                          controller: _name,
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) => _submit(),
                        ),
                        _field(
                          tokens: t,
                          label: 'Single player',
                          controller: _singular,
                        ),
                        _field(
                          tokens: t,
                          label: 'Two or more players',
                          controller: _plural,
                        ),
                        _field(
                          tokens: t,
                          label: 'Wording for reactions',
                          controller: _ing,
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: t.divider),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Row(
                      children: [
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: t.metaStyle.copyWith(
                              color: t.text.withValues(alpha: 0.62),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedGreyButton(
                          label: 'Create duplicate',
                          fontSize: 11,
                          isPrimary: true,
                          onPressed: canCreate ? _submit : null,
                        ),
                      ],
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
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tokens,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final FfTokens tokens;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          icon,
          size: 18,
          color: onPressed == null
              ? tokens.text.withValues(alpha: 0.28)
              : tokens.text.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}

class _VerbActionBar extends StatelessWidget {
  const _VerbActionBar({
    required this.tokens,
    required this.busy,
    required this.hasSelection,
    required this.onPublish,
  });

  final FfTokens tokens;
  final bool busy;
  final bool hasSelection;
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    final enabled = hasSelection && !busy;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.divider)),
      ),
      child: Row(
        children: [
          Text(
            hasSelection
                ? 'Applies to the selected verb only'
                : 'Select a verb to publish',
            style: tokens.microStyle.copyWith(
              fontSize: 10.5,
              color: tokens.text.withValues(alpha: 0.48),
            ),
          ),
          const Spacer(),
          ElevatedGreyButton(
            label: busy ? 'Publishing…' : 'Publish default',
            fontSize: 11,
            icon: Icons.cloud_upload_outlined,
            isAdmin: true,
            onPressed: enabled ? onPublish : null,
          ),
        ],
      ),
    );
  }
}

class _VerbJumpDialog extends StatefulWidget {
  const _VerbJumpDialog({
    required this.tokens,
    required this.verbs,
    required this.selectedKey,
  });

  final FfTokens tokens;
  final List<_VerbDraft> verbs;
  final String? selectedKey;

  @override
  State<_VerbJumpDialog> createState() => _VerbJumpDialogState();
}

class _VerbJumpDialogState extends State<_VerbJumpDialog> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  int _highlight = 0;

  @override
  void initState() {
    super.initState();
    final index = widget.verbs.indexWhere((v) => v.key == widget.selectedKey);
    _highlight = index < 0 ? 0 : index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<_VerbDraft> get _filtered {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return widget.verbs;
    return widget.verbs.where((verb) {
      final hay = '${verb.label} ${verb.category} ${verb.key}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  void _move(int delta) {
    final list = _filtered;
    if (list.isEmpty) return;
    setState(() {
      _highlight = (_highlight + delta + list.length) % list.length;
    });
  }

  void _confirm([_VerbDraft? verb]) {
    final list = _filtered;
    final pick = verb ??
        (list.isEmpty
            ? null
            : list[_highlight.clamp(0, list.length - 1)]);
    if (pick == null) return;
    Navigator.of(context).pop(pick.key);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final list = _filtered;
    if (_highlight >= list.length) _highlight = list.isEmpty ? 0 : list.length - 1;

    return Dialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 440,
        height: 460,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  PhosphorIcon(
                    PhosphorIconsRegular.magnifyingGlass,
                    size: 15,
                    color: t.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.arrowDown):
                            () => _move(1),
                        const SingleActivator(LogicalKeyboardKey.arrowUp):
                            () => _move(-1),
                        const SingleActivator(LogicalKeyboardKey.enter):
                            _confirm,
                        const SingleActivator(LogicalKeyboardKey.escape):
                            () => Navigator.of(context).pop(),
                      },
                      child: TextField(
                        controller: _query,
                        focusNode: _focus,
                        autofocus: true,
                        style: t.metaStyle.copyWith(color: t.text),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Find a verb…',
                          hintStyle: t.metaStyle.copyWith(
                            color: t.textSecondary,
                          ),
                        ),
                        onChanged: (_) => setState(() => _highlight = 0),
                        onSubmitted: (_) => _confirm(),
                      ),
                    ),
                  ),
                  Text(
                    '↑↓  ⏎',
                    style: t.monoMetaStyle.copyWith(
                      fontSize: 10,
                      color: t.text.withValues(alpha: 0.40),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: t.divider),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text(
                        'No matches',
                        style: t.metaStyle.copyWith(color: t.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: list.length,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemBuilder: (context, index) {
                        final verb = list[index];
                        final selected = index == _highlight;
                        return Material(
                          color: selected
                              ? t.accent.withValues(alpha: 0.14)
                              : Colors.transparent,
                          child: InkWell(
                            onTap: () => _confirm(verb),
                            onHover: (hovering) {
                              if (hovering) setState(() => _highlight = index);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            verb.label,
                                            overflow: TextOverflow.ellipsis,
                                            style: t.metaStyle.copyWith(
                                              color: verb.isHidden
                                                  ? t.text
                                                      .withValues(alpha: 0.45)
                                                  : t.text,
                                              fontWeight: selected
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                        if (verb.isHidden) ...[
                                          const SizedBox(width: 6),
                                          PhosphorIcon(
                                            PhosphorIconsRegular.eyeSlash,
                                            size: 12,
                                            color: const Color(0xFFFF6B6B),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Text(
                                    verb.category,
                                    style: t.metaStyle.copyWith(
                                      fontSize: 11,
                                      color: t.text.withValues(alpha: 0.45),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerbEditorPane extends StatefulWidget {
  const _VerbEditorPane({
    super.key,
    required this.tokens,
    required this.sport,
    required this.verb,
    required this.selectedGroupId,
    required this.renaming,
    required this.nameFocus,
    required this.sampleIndex,
    required this.onRenameMode,
    required this.onRename,
    required this.onGroupSelected,
    required this.onAuthoringChanged,
    required this.onDraftChanged,
    required this.onShuffle,
  });

  final FfTokens tokens;
  final String sport;
  final _VerbDraft verb;
  final String? selectedGroupId;
  final bool renaming;
  final FocusNode nameFocus;
  final int sampleIndex;
  final VoidCallback onRenameMode;
  final ValueChanged<String> onRename;
  final ValueChanged<String?> onGroupSelected;
  final ValueChanged<VerbAuthoringData> onAuthoringChanged;
  final ValueChanged<_VerbDraft> onDraftChanged;
  final VoidCallback onShuffle;

  @override
  State<_VerbEditorPane> createState() => _VerbEditorPaneState();
}

class _VerbEditorPaneState extends State<_VerbEditorPane> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _singular = TextEditingController();
  final TextEditingController _plural = TextEditingController();
  final TextEditingController _ing = TextEditingController();
  final TextEditingController _keywords = TextEditingController();
  final TextEditingController _opponentJoiner = TextEditingController();
  late VerbAuthoringData _authoring;
  late bool _useSingularPhrase;
  late bool _usePluralPhrase;
  late bool _withTeammates;
  late VerbSubOptions _subOptions;
  final Map<String, String?> _selections = {};
  String _lastAutoIng = '';

  @override
  void initState() {
    super.initState();
    _loadFromVerb(widget.verb);
  }

  void _loadFromVerb(_VerbDraft verb) {
    _name.text = verb.label;
    _singular.text = verb.singular;
    _plural.text = verb.plural;
    _ing.text = verb.ing;
    _keywords.text = verb.keywords.join(', ');
    _authoring = verb.authoring;
    _useSingularPhrase = verb.useSingularPhrase;
    _usePluralPhrase = verb.usePluralPhrase;
    _withTeammates = verb.withTeammates;
    final storedJoiner = verb.opponentJoiner.trim();
    // Always put real text in the box (not hint). Default is "against".
    _opponentJoiner.value = TextEditingValue(
      text: storedJoiner.isNotEmpty
          ? storedJoiner
          : (verb.omitAgainst ? '' : 'against'),
      selection: TextSelection.collapsed(
        offset: (storedJoiner.isNotEmpty
                ? storedJoiner
                : (verb.omitAgainst ? '' : 'against'))
            .length,
      ),
    );
    _subOptions = verb.subOptions;
    _lastAutoIng = VerbCaptionWording.defaultIngWording(
      verb.label,
      verb.singular,
    );
    _selections.clear();
    _seedSelections();
  }

  @override
  void didUpdateWidget(covariant _VerbEditorPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.verb.key != widget.verb.key ||
        oldWidget.sport != widget.sport) {
      _loadFromVerb(widget.verb);
      return;
    }
    if (!widget.renaming &&
        oldWidget.verb.label != widget.verb.label &&
        _name.text.trim() != widget.verb.label) {
      _name.text = widget.verb.label;
    }
  }

  /// Latest name + wording from the open editor (including unsaved rename text).
  _VerbDraft captureDraft() => _currentDraft();

  @override
  void dispose() {
    _name.dispose();
    _singular.dispose();
    _plural.dispose();
    _ing.dispose();
    _keywords.dispose();
    _opponentJoiner.dispose();
    super.dispose();
  }

  void _seedSelections() {
    for (final group in _authoring.groups) {
      _selections[group.id] = group.defaultOptionId;
    }
  }

  _VerbDraft _currentDraft({
    VerbAuthoringData? authoring,
  }) {
    final name = _name.text.trim();
    return widget.verb.copyWith(
      label: name.isEmpty ? widget.verb.label : name,
      singular: _singular.text.trim(),
      plural: _plural.text.trim(),
      useSingularPhrase: _useSingularPhrase,
      usePluralPhrase: _usePluralPhrase,
      ing: _ing.text.trim(),
      keywords: parseVerbKeywordsField(_keywords.text),
      wantsOpponent: true,
      // Legacy flag: only true when the box is intentionally blank.
      omitAgainst: _opponentJoiner.text.trim().isEmpty,
      opponentJoiner: _opponentJoiner.text.trim(),
      withTeammates: _withTeammates,
      subOptions: _subOptions,
      authoring: authoring ?? _authoring,
    );
  }

  void _emitDraft() {
    widget.onDraftChanged(_currentDraft());
  }

  void _clearWordingField(TextEditingController controller) {
    if (controller.text.isEmpty) return;
    setState(() {
      controller.clear();
      if (identical(controller, _ing)) {
        _lastAutoIng = '';
      }
    });
    // Don't route singular clears through [_onWordingChanged] — that refills -ing.
    _emitDraft();
  }

  Widget _wordingClearButton({
    required FfTokens tokens,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          'Clear',
          style: tokens.metaStyle.copyWith(
            fontSize: 10.5,
            color: tokens.text.withValues(alpha: enabled ? 0.55 : 0.22),
          ),
        ),
      ),
    );
  }

  void _onWordingChanged(String value) {
    final label = _name.text.trim().isEmpty
        ? widget.verb.label
        : _name.text.trim();
    final wording = value.trim().isEmpty ? widget.verb.key : value.trim();
    final autoIng = VerbCaptionWording.defaultIngWording(label, wording);
    if (_ing.text.trim().isEmpty || _ing.text.trim() == _lastAutoIng) {
      _ing.text = autoIng;
    }
    _lastAutoIng = autoIng;
    setState(() {});
    _emitDraft();
  }

  void _setSubOptions(VerbSubOptions value) {
    setState(() {
      _subOptions = value;
      // Keep reaction modifier chips in sync with celebration phrases.
      final reaction = _authoring.groups.where((g) => g.id == 'reaction');
      if (reaction.isNotEmpty) {
        final options = value.reactionPhraseList
            .map(
              (label) => VerbModifierOption(
                id: label.toLowerCase().replaceAll(' ', '_'),
                label: label.isEmpty
                    ? label
                    : label[0].toUpperCase() + label.substring(1),
                value: label,
              ),
            )
            .toList();
        _authoring = VerbAuthoringData(
          phrase: _authoring.phrase,
          groups: [
            for (final group in _authoring.groups)
              if (group.id == 'reaction')
                group.copyWith(options: options)
              else
                group,
          ],
        );
      }
    });
    _emitDraft();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final liveLabel = _name.text.trim().isEmpty
        ? widget.verb.label
        : _name.text.trim();
    final liveSingular = _singular.text.trim();
    final livePlural = _plural.text.trim();
    final liveIng = _ing.text.trim();
    return Container(
      color: t.bg,
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.divider)),
            ),
            child: Row(
              children: [
                if (widget.renaming)
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _name,
                      focusNode: widget.nameFocus,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: widget.onRename,
                      onEditingComplete: () => widget.onRename(_name.text),
                      style: TextStyle(
                        fontFamily: FfTokens.labelFamily,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                        color: t.text,
                      ),
                    ),
                  )
                else ...[
                  Text(
                    widget.verb.label,
                    style: TextStyle(
                      fontFamily: FfTokens.labelFamily,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                      color: t.text,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Rename verb',
                    onPressed: widget.onRenameMode,
                    icon: PhosphorIcon(
                      PhosphorIconsRegular.notePencil,
                      size: 15,
                      color: t.text.withValues(alpha: 0.50),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionHeading(
                    tokens: t,
                    label: 'WORDING',
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppDialogLabeledField(
                          label: 'Single player',
                          bottomGap: 0,
                          labelLeading: SizedBox(
                            width: 28,
                            height: 16,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: Switch.adaptive(
                                value: _useSingularPhrase,
                                onChanged: (value) {
                                  setState(() => _useSingularPhrase = value);
                                  _emitDraft();
                                },
                                activeThumbColor: Colors.white,
                                activeTrackColor: t.accent,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                          labelTrailing: _wordingClearButton(
                            tokens: t,
                            enabled: _singular.text.isNotEmpty,
                            onPressed: () => _clearWordingField(_singular),
                          ),
                          child: AppDialogControlShell(
                            height: 52,
                            enabled: _useSingularPhrase,
                            child: TextField(
                              controller: _singular,
                              enabled: _useSingularPhrase,
                              minLines: 2,
                              maxLines: 2,
                              style: appDialogFieldTextStyleOf(
                                context,
                                enabled: _useSingularPhrase,
                              ),
                              onChanged: _onWordingChanged,
                              decoration: appDialogBareFieldDecoration(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppDialogLabeledField(
                          label: 'Two or more players',
                          bottomGap: 0,
                          labelLeading: SizedBox(
                            width: 28,
                            height: 16,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: Switch.adaptive(
                                value: _usePluralPhrase,
                                onChanged: (value) {
                                  setState(() => _usePluralPhrase = value);
                                  _emitDraft();
                                },
                                activeThumbColor: Colors.white,
                                activeTrackColor: t.accent,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                          labelTrailing: _wordingClearButton(
                            tokens: t,
                            enabled: _plural.text.isNotEmpty,
                            onPressed: () => _clearWordingField(_plural),
                          ),
                          child: AppDialogControlShell(
                            height: 52,
                            enabled: _usePluralPhrase,
                            child: TextField(
                              controller: _plural,
                              enabled: _usePluralPhrase,
                              minLines: 2,
                              maxLines: 2,
                              style: appDialogFieldTextStyleOf(
                                context,
                                enabled: _usePluralPhrase,
                              ),
                              onChanged: (_) {
                                setState(() {});
                                _emitDraft();
                              },
                              decoration: appDialogBareFieldDecoration(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppDialogLabeledField(
                          label: 'Wording for reactions',
                          bottomGap: 0,
                          labelTrailing: _wordingClearButton(
                            tokens: t,
                            enabled: _ing.text.isNotEmpty,
                            onPressed: () => _clearWordingField(_ing),
                          ),
                          child: AppDialogControlShell(
                            height: 52,
                            child: TextField(
                              controller: _ing,
                              minLines: 2,
                              maxLines: 2,
                              style: appDialogFieldTextStyleOf(context),
                              onChanged: (_) {
                                setState(() {});
                                _emitDraft();
                              },
                              decoration: appDialogBareFieldDecoration(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Opponent joiner',
                        style: appDialogFieldLabelStyleOf(context),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 220,
                        child: AppDialogControlShell(
                          child: TextField(
                            controller: _opponentJoiner,
                            style: appDialogFieldTextStyleOf(context),
                            onChanged: (_) {
                              setState(() {});
                              _emitDraft();
                            },
                            decoration: appDialogBareFieldDecoration(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      AppCompactCheckbox(
                        value: _withTeammates,
                        accentColor: t.accent,
                        onChanged: (value) {
                          setState(() => _withTeammates = value);
                          _emitDraft();
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'With teammates — first pick does the action; '
                          'other same-team picks are named after “with”',
                          style: appDialogFieldLabelStyleOf(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: t.divider),
                  const SizedBox(height: 12),
                  _SectionHeading(
                    tokens: t,
                    label: 'PREVIEW',
                    trailingWidget: TextButton.icon(
                      onPressed: widget.onShuffle,
                      icon: PhosphorIcon(
                        PhosphorIconsRegular.shuffle,
                        size: 12,
                        color: t.text.withValues(alpha: 0.60),
                      ),
                      label: Text(
                        'Shuffle sample',
                        style: t.metaStyle.copyWith(
                          fontSize: 11,
                          color: t.text.withValues(alpha: 0.60),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _ResolvedPreview(
                    tokens: t,
                    sport: widget.sport,
                    verbKey: widget.verb.key,
                    verbLabel: liveLabel,
                    phrase: liveSingular,
                    pluralPhrase:
                        livePlural.isEmpty ? liveSingular : livePlural,
                    useSingularPhrase: _useSingularPhrase,
                    usePluralPhrase: _usePluralPhrase,
                    ingPhrase: liveIng.isEmpty
                        ? VerbCaptionWording.defaultIngWording(
                            liveLabel,
                            liveSingular.isEmpty
                                ? widget.verb.key
                                : liveSingular,
                          )
                        : liveIng,
                    sampleIndex: widget.sampleIndex,
                    omitAgainst: _opponentJoiner.text.trim().isEmpty,
                    opponentJoiner: _opponentJoiner.text.trim(),
                    withTeammates: _withTeammates,
                    subOptions: _subOptions,
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: t.divider),
                  const SizedBox(height: 12),
                  VerbEditSubOptionsSection(
                    verbLabel: widget.verb.key,
                    sport: widget.sport,
                    value: _subOptions,
                    onChanged: _setSubOptions,
                    showBorder: false,
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: t.divider),
                  const SizedBox(height: 12),
                  AppDialogLabeledField(
                    label: 'Keywords',
                    bottomGap: 0,
                    labelTrailing: Text(
                      'Only applied when keyword mode is activated',
                      style: t.metaStyle.copyWith(
                        fontSize: 10.5,
                        color: t.textSecondary,
                      ),
                    ),
                    child: AppDialogControlShell(
                      child: TextField(
                        controller: _keywords,
                        style: appDialogFieldTextStyleOf(context),
                        onChanged: (_) => _emitDraft(),
                        decoration: appDialogBareFieldDecoration(
                          hintText: 'comma, separated, keywords',
                        ),
                      ),
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
}


class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.tokens,
    required this.label,
    this.trailing,
    this.trailingWidget,
  });

  final FfTokens tokens;
  final String label;
  final String? trailing;
  final Widget? trailingWidget;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          Text(
            label,
            style: FfTokens.railLabel.copyWith(
              color: tokens.text.withValues(alpha: 0.70),
            ),
          ),
          const Spacer(),
          if (trailing != null)
            Text(
              trailing!,
              style: tokens.metaStyle.copyWith(
                fontSize: 10.5,
                color: tokens.text.withValues(alpha: 0.46),
              ),
            ),
          if (trailingWidget != null) trailingWidget!,
        ],
      ),
    );
  }
}

class _PreviewVariant {
  const _PreviewVariant(this.id, this.label);
  final String id;
  final String label;
}

class _ResolvedPreview extends StatefulWidget {
  const _ResolvedPreview({
    required this.tokens,
    required this.sport,
    required this.verbKey,
    required this.verbLabel,
    required this.phrase,
    required this.pluralPhrase,
    required this.useSingularPhrase,
    required this.usePluralPhrase,
    required this.ingPhrase,
    required this.sampleIndex,
    required this.omitAgainst,
    required this.opponentJoiner,
    required this.withTeammates,
    required this.subOptions,
  });

  final FfTokens tokens;
  final String sport;
  final String verbKey;
  final String verbLabel;
  final String phrase;
  final String pluralPhrase;
  final bool useSingularPhrase;
  final bool usePluralPhrase;
  final String ingPhrase;
  final int sampleIndex;
  final bool omitAgainst;
  final String opponentJoiner;
  final bool withTeammates;
  final VerbSubOptions subOptions;

  @override
  State<_ResolvedPreview> createState() => _ResolvedPreviewState();
}

class _ResolvedPreviewState extends State<_ResolvedPreview> {
  String _variantId = 'base';

  static const _soloPlayers = [
    'Heater Ace #24 of the Los Angeles Boulevards',
    'Fastbreak Finn #21 of the New York Liberty',
    'Maya North #7 of the Toronto Arrows',
  ];
  static const _pluralPlayers = [
    'Heater Ace #24 and Dunkin Deuces #8 of the Los Angeles Boulevards',
    'Fastbreak Finn #21 and Swish McBucket #20 of the New York Liberty',
    'Maya North #7 and Netfront Nova #3 of the Toronto Arrows',
  ];
  static const _opponentTeams = [
    'the New York Avenues',
    'the Chicago Comets',
    'the Montreal Royals',
  ];
  static const _timing = [
    'during the third inning',
    'during the fifth inning',
    'during the seventh inning',
  ];

  String get _hitNoun {
    switch (widget.verbKey) {
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
      case 'Bunts':
        return 'bunt';
      case 'Hit by Pitch':
        return 'hit by pitch';
      case 'Grand Slam':
        return 'grand slam';
      default:
        return widget.phrase.trim().isEmpty ? '…' : widget.phrase.trim();
    }
  }

  List<_PreviewVariant> get _variants {
    final live = widget.subOptions;
    final label = widget.verbLabel.trim().isEmpty
        ? widget.verbKey
        : widget.verbLabel.trim();
    final showRbi = VerbSubOptions.showRbiEditor(
      sport: widget.sport,
      verbLabel: label,
      value: live,
    );
    final showCele = VerbSubOptions.showCelebrationEditor(
      verbLabel: label,
      value: live,
      sport: widget.sport,
    );
    final isHit = VerbSubOptions.isHitVerb(widget.verbKey) ||
        VerbSubOptions.isHitVerb(label);
    final isHomeRun = widget.verbKey == 'Home Run' || label == 'Home Run';

    final variants = <_PreviewVariant>[
      if (widget.useSingularPhrase)
        const _PreviewVariant('base', 'Single Player'),
    ];
    if (widget.withTeammates) {
      variants.add(const _PreviewVariant('with_teammates', 'With teammates'));
    } else if (widget.usePluralPhrase) {
      variants.add(const _PreviewVariant('plural', 'Two or more players'));
    }
    if (showRbi && live.rbiEnabled) {
      variants.add(
        _PreviewVariant(
          isHomeRun ? 'two_run' : 'rbi',
          isHomeRun ? 'Two-Run' : 'RBI',
        ),
      );
    }
    if (isHomeRun) {
      variants.add(const _PreviewVariant('grand_slam', 'Grand Slam'));
    }
    if (showCele && live.celebrationEnabled) {
      if (isHit) {
        variants.add(const _PreviewVariant('cele', 'Reaction'));
        if (live.rbiEnabled) {
          variants.add(
            _PreviewVariant(
              isHomeRun ? 'cele_two_run' : 'cele_rbi',
              isHomeRun ? 'Reaction · Two-Run' : 'Reaction · RBI',
            ),
          );
        }
        if (isHomeRun) {
          variants.add(
            const _PreviewVariant('cele_grand_slam', 'Reaction · Grand Slam'),
          );
        }
      } else if (VerbSubOptions.isCelebrationVerb(label) ||
          VerbSubOptions.isCelebrationVerb(widget.verbKey)) {
        variants.add(const _PreviewVariant('cele', 'Reaction'));
      } else {
        variants.add(const _PreviewVariant('cele', 'Reaction'));
      }
    }
    return variants;
  }

  String get _resolvedVariantId {
    final variants = _variants;
    if (variants.isEmpty) return 'base';
    if (variants.any((v) => v.id == _variantId)) return _variantId;
    return variants.first.id;
  }

  String _actionFor(String id) {
    final live = widget.subOptions;
    final phrase =
        widget.phrase.trim().isEmpty ? '…' : widget.phrase.trim();
    final cele = live.primaryReactionPhrase;
    final label = widget.verbLabel.trim().isEmpty
        ? widget.verbKey
        : widget.verbLabel.trim();
    switch (id) {
      case 'plural':
        return widget.pluralPhrase.trim().isEmpty
            ? phrase
            : widget.pluralPhrase.trim();
      case 'with_teammates':
        return '$phrase with Dunkin Deuces #8';
      case 'rbi':
        return live.hitClauseWithRbi(
          leadIn: 'hits a',
          hitNoun: _hitNoun,
          count: 2,
        );
      case 'two_run':
        return live.hitClauseWithHomeRun(
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
        if (!VerbSubOptions.isHitVerb(widget.verbKey) &&
            !VerbSubOptions.isHitVerb(label)) {
          final parts = VerbSubOptions.reactionAfterPartsFor(
            widget.verbKey,
            singularPhrase: phrase,
            ingPhrase: widget.ingPhrase,
          );
          if (parts.appendNoun) {
            return '$cele ${parts.afterText} $_hitNoun';
          }
          return '$cele ${parts.afterText}';
        }
        final parts = VerbSubOptions.reactionAfterPartsFor(widget.verbKey);
        return '$cele ${parts.afterText} $_hitNoun';
      case 'cele_rbi':
        final celeParts = VerbSubOptions.reactionAfterPartsFor(widget.verbKey);
        return live.hitClauseWithRbi(
          leadIn: '$cele ${celeParts.afterText}',
          hitNoun: _hitNoun,
          count: 2,
        );
      case 'cele_two_run':
        final celeParts = VerbSubOptions.reactionAfterPartsFor(widget.verbKey);
        return live.hitClauseWithHomeRun(
          leadIn: '$cele ${celeParts.afterText}',
          hitNoun: _hitNoun,
          count: 2,
        );
      case 'cele_grand_slam':
        final celeParts = VerbSubOptions.reactionAfterPartsFor(widget.verbKey);
        return live.hitClauseWithGrandSlam(
          leadIn: '$cele ${celeParts.afterText}',
          hitNoun: _hitNoun,
        );
      case 'base':
      default:
        return phrase;
    }
  }

  @override
  void didUpdateWidget(covariant _ResolvedPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.verbKey != widget.verbKey ||
        oldWidget.subOptions != widget.subOptions ||
        oldWidget.useSingularPhrase != widget.useSingularPhrase ||
        oldWidget.usePluralPhrase != widget.usePluralPhrase ||
        oldWidget.withTeammates != widget.withTeammates) {
      final id = _resolvedVariantId;
      if (id != _variantId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _variantId = id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final variants = _variants;
    final selectedId = _resolvedVariantId;
    final index = widget.sampleIndex % _soloPlayers.length;
    final subject = selectedId == 'plural'
        ? _pluralPlayers[index]
        : _soloPlayers[index];
    final team =
        _opponentTeams[widget.sampleIndex % _opponentTeams.length];
    final timing = _timing[widget.sampleIndex % _timing.length];
    final connector = CaptionV2CaptionDomain.opponentConnector(
      opponentJoiner: widget.opponentJoiner,
    ).trimLeft();
    final tail = connector.isEmpty
        ? '$team $timing'
        : '$connector $team $timing';
    final action = _actionFor(selectedId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: t.sunken,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.divider),
          ),
          child: Text.rich(
            TextSpan(
              style: t.bodyStyle.copyWith(
                fontSize: 13.5,
                color: t.text.withValues(alpha: 0.82),
              ),
              children: [
                TextSpan(text: '$subject '),
                TextSpan(
                  text: action,
                  style: TextStyle(
                    color: t.text,
                    backgroundColor: t.accent.withValues(alpha: 0.20),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: ' $tail'),
              ],
            ),
          ),
        ),
        if (variants.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Modifier Options Preview:',
            style: FfTokens.railLabel.copyWith(
              color: t.text.withValues(alpha: 0.70),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final v in variants)
                Material(
                  color: v.id == selectedId
                      ? t.selectedFill
                      : t.badgeFill,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                    side: BorderSide(
                      color: v.id == selectedId
                          ? t.selectedBorder
                          : t.divider,
                      width: v.id == selectedId ? 1.2 : 1,
                    ),
                  ),
                  child: InkWell(
                    onTap: () => setState(() => _variantId = v.id),
                    borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        v.label,
                        style: t.metaStyle.copyWith(
                          fontSize: 11,
                          fontWeight: v.id == selectedId
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: t.text,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _VerbDraft {
  const _VerbDraft({
    required this.key,
    required this.label,
    required this.category,
    required this.singular,
    required this.plural,
    required this.useSingularPhrase,
    required this.usePluralPhrase,
    required this.ing,
    required this.keywords,
    required this.wantsOpponent,
    required this.omitAgainst,
    required this.opponentJoiner,
    required this.withTeammates,
    required this.subOptions,
    required this.isCustom,
    this.isHidden = false,
    required this.authoring,
    required this.record,
  });

  final String key;
  final String label;
  final String category;
  final String singular;
  final String plural;
  final bool useSingularPhrase;
  final bool usePluralPhrase;
  final String ing;
  final List<String> keywords;
  final bool wantsOpponent;
  final bool omitAgainst;
  final String opponentJoiner;
  final bool withTeammates;
  final VerbSubOptions subOptions;
  final bool isCustom;
  final bool isHidden;
  final VerbAuthoringData authoring;
  final Map<String, dynamic> record;

  factory _VerbDraft.fromRecord({
    required String key,
    required String category,
    required Map<String, dynamic> record,
    required bool isCustom,
    bool isHidden = false,
    required String sport,
  }) {
    final label = (record['label'] ?? key).toString();
    // Empty wording fields are intentional clears — only fill factory defaults
    // when the field was never stored on the record.
    final hasSingular = record.containsKey('verbPhrase');
    final singular = (record['verbPhrase'] ?? '').toString().trim();
    final effective = hasSingular
        ? singular
        : VerbCaptionWording.defaultWording(key);
    final fallbackPhrase = effective.isEmpty
        ? VerbCaptionWording.defaultWording(key)
        : effective;
    final hasPlural = record.containsKey('pluralPhrase');
    final plural = (record['pluralPhrase'] ?? '').toString().trim();
    final hasIng = record.containsKey('ingPhrase');
    final ing = (record['ingPhrase'] ?? '').toString().trim();
    final subOptions = VerbSubOptions.fromJson(
      record['subOptions'],
      verbLabel: key,
      sport: sport,
    );
    final keywords = (record['keywords'] is List)
        ? List<String>.from(record['keywords'] as List)
        : defaultKeywordsForVerbLabel(key);
    return _VerbDraft(
      key: key,
      label: label,
      category: category,
      singular: effective,
      plural: hasPlural
          ? plural
          : VerbCaptionWording.defaultPluralWording(key, fallbackPhrase),
      useSingularPhrase: record['useSingularPhrase'] != false,
      usePluralPhrase: record['usePluralPhrase'] != false,
      ing: hasIng
          ? ing
          : VerbCaptionWording.defaultIngWording(key, fallbackPhrase),
      keywords: keywords,
      wantsOpponent: record['wantsOpponent'] is bool
          ? record['wantsOpponent'] as bool
          : key != 'Post Game Win' && key != 'Post Game Loss',
      omitAgainst: record['omitAgainst'] == true,
      opponentJoiner: () {
        if (record.containsKey('opponentJoiner')) {
          final joiner = (record['opponentJoiner'] ?? '').toString().trim();
          if (joiner.isNotEmpty) return joiner;
          return record['omitAgainst'] == true ? '' : 'against';
        }
        return record['omitAgainst'] == true ? '' : 'against';
      }(),
      withTeammates: record['withTeammates'] is bool
          ? record['withTeammates'] as bool
          : key == 'Celebrates a Goal',
      subOptions: subOptions,
      isCustom: isCustom,
      isHidden: isHidden,
      authoring: VerbAuthoringData.fromRecord(
        record,
        verbLabel: key,
        sport: sport,
        fallbackPhrase: fallbackPhrase,
        subOptions: subOptions,
      ),
      record: record,
    );
  }

  _VerbDraft copyWith({
    String? key,
    String? label,
    String? category,
    String? singular,
    String? plural,
    bool? useSingularPhrase,
    bool? usePluralPhrase,
    String? ing,
    List<String>? keywords,
    bool? wantsOpponent,
    bool? omitAgainst,
    String? opponentJoiner,
    bool? withTeammates,
    VerbSubOptions? subOptions,
    bool? isHidden,
    VerbAuthoringData? authoring,
  }) {
    return _VerbDraft(
      key: key ?? this.key,
      label: label ?? this.label,
      category: category ?? this.category,
      singular: singular ?? this.singular,
      plural: plural ?? this.plural,
      useSingularPhrase: useSingularPhrase ?? this.useSingularPhrase,
      usePluralPhrase: usePluralPhrase ?? this.usePluralPhrase,
      ing: ing ?? this.ing,
      keywords: keywords ?? this.keywords,
      wantsOpponent: wantsOpponent ?? this.wantsOpponent,
      omitAgainst: omitAgainst ?? this.omitAgainst,
      opponentJoiner: opponentJoiner ?? this.opponentJoiner,
      withTeammates: withTeammates ?? this.withTeammates,
      subOptions: subOptions ?? this.subOptions,
      isCustom: isCustom,
      isHidden: isHidden ?? this.isHidden,
      authoring: authoring ?? this.authoring,
      record: record,
    );
  }

  Map<String, dynamic> toRecord() => {
        ...record,
        'key': key,
        'label': label,
        'verbPhrase': singular,
        'pluralPhrase': plural,
        'useSingularPhrase': useSingularPhrase,
        'usePluralPhrase': usePluralPhrase,
        'ingPhrase': ing,
        'keywords': keywords,
        'wantsOpponent': wantsOpponent,
        'omitAgainst': omitAgainst,
        'opponentJoiner': opponentJoiner,
        'withTeammates': withTeammates,
        'subOptions': subOptions.toJson(),
        'category': category,
        'isCustom': isCustom,
        ...authoring.toRecordFields(),
      };
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
