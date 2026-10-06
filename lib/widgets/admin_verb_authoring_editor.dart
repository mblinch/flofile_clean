import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../caption_style/sport_verb_categories.dart';
import '../caption_style/verb_authoring_model.dart';
import '../caption_style/verb_caption_wording.dart';
import '../caption_style/verb_defaults_bundle.dart';
import '../caption_style/verb_sub_options.dart';
import '../screens/caption_v2/data/caption_v2_caption_domain.dart';
import '../theme/ff_icons.dart';
import '../theme/ff_tokens.dart';
import '../utils/default_verb_keywords.dart';
import '../utils/verb_name_casing.dart';
import 'admin_verb_editor_v3_chrome.dart';
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
  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _categoryRenameController =
      TextEditingController();
  final GlobalKey<_VerbEditorPaneState> _editorPaneKey =
      GlobalKey<_VerbEditorPaneState>();
  final GlobalKey _moveButtonKey = GlobalKey();
  String? _selectedCategory;
  String? _selectedKey;
  String? _selectedGroupId;
  bool _renaming = false;
  bool _renamingCategory = false;
  int _sampleIndex = 0;
  int _pendingChanges = 0;
  Timer? _saveDebounce;
  Timer? _undoTimer;
  Map<String, dynamic>? _publishedBaseline;
  _EditorSnapshot? _undoSnapshot;
  String? _undoMessage;

  @override
  void initState() {
    super.initState();
    _publishedBaseline = _deepCopyMap(widget.bundle);
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });
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
    if (oldWidget.sport != widget.sport) {
      _publishedBaseline = _deepCopyMap(widget.bundle);
      _pendingChanges = 0;
      _clearUndo();
    }
    if (oldWidget.sport != widget.sport ||
        !identical(oldWidget.bundle, widget.bundle)) {
      _ensureSelection();
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _undoTimer?.cancel();
    _nameFocus.dispose();
    _searchFocus.dispose();
    _searchController.dispose();
    _categoryRenameController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _deepCopyMap(Map<String, dynamic> source) {
    return Map<String, dynamic>.from(
      (jsonDecode(jsonEncode(source)) as Map).cast<String, dynamic>(),
    );
  }

  void _markDraftChange() {
    _pendingChanges += 1;
  }

  void _clearUndo() {
    _undoTimer?.cancel();
    _undoSnapshot = null;
    _undoMessage = null;
  }

  void _pushUndo(String message) {
    _undoSnapshot = _EditorSnapshot(
      bundle: _deepCopyMap(widget.bundle),
      selectedCategory: _selectedCategory,
      selectedKey: _selectedKey,
      pendingChanges: _pendingChanges,
    );
    _undoTimer?.cancel();
    _undoTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(_clearUndo);
    });
    if (mounted) {
      setState(() => _undoMessage = message);
    } else {
      _undoMessage = message;
    }
  }

  void _undo() {
    final snap = _undoSnapshot;
    if (snap == null) return;
    _clearUndo();
    setState(() {
      _selectedCategory = snap.selectedCategory;
      _selectedKey = snap.selectedKey;
      _pendingChanges = snap.pendingChanges;
    });
    widget.onBundleChanged(_deepCopyMap(snap.bundle));
    setState(_ensureSelection);
  }

  void _discardDrafts() {
    final baseline = _publishedBaseline;
    if (baseline == null) return;
    _flushSelectedVerb();
    _clearUndo();
    setState(() => _pendingChanges = 0);
    widget.onBundleChanged(_deepCopyMap(baseline));
    setState(_ensureSelection);
  }

  Future<void> _publishDrafts() async {
    _flushSelectedVerb();
    if (!widget.personalMode) {
      final write = widget.onWriteSportDefaults;
      if (write != null) {
        await write(successLabel: 'Published');
      } else if (widget.onPublishCurrentVerb != null) {
        await _runCurrentVerbAction(widget.onPublishCurrentVerb);
      }
    }
    if (!mounted) return;
    setState(() {
      _publishedBaseline = _deepCopyMap(widget.bundle);
      _pendingChanges = 0;
      _clearUndo();
    });
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

  void _emit(Map<String, dynamic> bundle, {bool countAsDraft = true}) {
    if (countAsDraft) _markDraftChange();
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
    final trimmed = titleCaseVerbName(label);
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

  void _setVerbCategory(_VerbDraft verb, String category) {
    final next = category.trim();
    if (next.isEmpty || next == verb.category) return;
    if (!_categories.contains(next)) return;

    // Prefer in-flight editor draft so category change doesn't drop wording edits.
    final base = (_pendingDraft != null && _pendingDraft!.key == verb.key)
        ? _pendingDraft!
        : verb;
    final updated = base.copyWith(category: next);

    final bundle = _copyBundle();
    final record = updated.toRecord();
    if (updated.isCustom) {
      final list = ((bundle['customVerbs'] as List?) ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
      final index = list.indexWhere(
        (item) => (item['key'] ?? item['label']).toString() == updated.key,
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
      overrides[updated.key] = record;
      bundle['verbOverrides'] = overrides;
    }

    final order = Map<String, dynamic>.from(
      (bundle['verbOrder'] as Map?) ?? const {},
    );
    for (final entry in order.entries.toList()) {
      if (entry.value is! List) continue;
      final list = List<String>.from(entry.value as List)..remove(updated.key);
      order[entry.key] = list;
    }
    final dest = List<String>.from((order[next] as List?) ?? const <String>[]);
    if (!dest.contains(updated.key)) dest.add(updated.key);
    order[next] = dest;
    bundle['verbOrder'] = order;

    if (_pendingDraft?.key == updated.key) _pendingDraft = null;
    setState(() => _selectedCategory = next);
    _emit(bundle);
  }

  Future<void> _addCategory() async {
    final existing = _categories;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _AddCategoryDialog(
        tokens: _t,
        existing: existing,
        moveSelectedVerb: false,
      ),
    );
    if (!mounted || name == null) return;
    final next = name.trim();
    if (next.isEmpty || next == 'Favorites') return;

    for (final category in existing) {
      if (category.toLowerCase() == next.toLowerCase()) {
        setState(() {
          _selectedCategory = category;
          _selectedKey = null;
          _ensureSelection();
        });
        return;
      }
    }

    _pushUndo('Added “$next”');
    final bundle = _copyBundle();
    final categories = List<String>.from(
      (bundle['categoryOrder'] as List?) ?? existing,
    )..add(next);
    bundle['categoryOrder'] = categories;
    final order = Map<String, dynamic>.from(
      (bundle['verbOrder'] as Map?) ?? const {},
    );
    order.putIfAbsent(next, () => <String>[]);
    bundle['verbOrder'] = order;
    setState(() {
      _selectedCategory = next;
      _selectedKey = null;
    });
    _emit(bundle);
  }

  Future<void> _deleteCategory([String? categoryName]) async {
    final current = (categoryName ??
            _selectedVerb?.category ??
            _selectedCategory ??
            '')
        .trim();
    if (current.isEmpty || current == 'Favorites') return;

    final destinations =
        _categories.where((category) => category != current).toList();
    if (destinations.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keep at least one category.')),
      );
      return;
    }

    final verbsInCategory =
        _allVerbs.where((verb) => verb.category == current).toList();

    // Empty category: delete immediately with undo.
    if (verbsInCategory.isEmpty) {
      _pushUndo('Deleted “$current”');
      final bundle = _copyBundle();
      final categories = List<String>.from(
        (bundle['categoryOrder'] as List?) ?? _categories,
      )..remove(current);
      bundle['categoryOrder'] = categories;
      final order = Map<String, dynamic>.from(
        (bundle['verbOrder'] as Map?) ?? const {},
      )..remove(current);
      bundle['verbOrder'] = order;
      setState(() => _selectedCategory = destinations.first);
      _emit(bundle);
      setState(_ensureSelection);
      return;
    }

    final choice = await showVerbEditorDeleteCategoryDialog(
      context: context,
      tokens: _t,
      category: current,
      verbLabels: [for (final v in verbsInCategory) v.label],
      destinations: destinations,
    );
    if (!mounted || choice == null) return;

    _pushUndo('Deleted “$current”');
    final bundle = _copyBundle();
    final categories = List<String>.from(
      (bundle['categoryOrder'] as List?) ?? _categories,
    )..remove(current);
    bundle['categoryOrder'] = categories;

    final order = <String, List<String>>{};
    final rawOrder = bundle['verbOrder'];
    if (rawOrder is Map) {
      rawOrder.forEach((key, value) {
        order[key.toString()] = value is List
            ? value.map((item) => item.toString()).toList()
            : <String>[];
      });
    }
    order.remove(current);

    if (choice.deleteAll) {
      for (final verb in verbsInCategory) {
        _removeVerbFromBundle(bundle, verb);
      }
      bundle['verbOrder'] = order;
      setState(() => _selectedCategory = destinations.first);
    } else {
      final dest = choice.destination!;
      if (!categories.contains(dest)) categories.add(dest);
      bundle['categoryOrder'] = categories;
      final destList = order.putIfAbsent(dest, () => <String>[]);
      for (final verb in verbsInCategory) {
        final base = (_pendingDraft != null && _pendingDraft!.key == verb.key)
            ? _pendingDraft!
            : verb;
        final updated = base.copyWith(category: dest);
        _writeVerbRecord(bundle, updated);
        if (_pendingDraft?.key == verb.key) _pendingDraft = null;
        destList.remove(verb.key);
        destList.add(verb.key);
      }
      bundle['verbOrder'] = order;
      setState(() => _selectedCategory = dest);
    }

    _emit(bundle);
    setState(_ensureSelection);
  }

  void _writeVerbRecord(Map<String, dynamic> bundle, _VerbDraft updated) {
    final record = updated.toRecord();
    if (updated.isCustom) {
      final list = ((bundle['customVerbs'] as List?) ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
      final index = list.indexWhere(
        (item) => (item['key'] ?? item['label']).toString() == updated.key,
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
      overrides[updated.key] = record;
      bundle['verbOverrides'] = overrides;
    }
  }

  void _removeVerbFromBundle(Map<String, dynamic> bundle, _VerbDraft verb) {
    if (_pendingDraft?.key == verb.key) _pendingDraft = null;
    if (verb.isCustom) {
      final customs = ((bundle['customVerbs'] as List?) ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .where(
            (item) => (item['key'] ?? item['label']).toString() != verb.key,
          )
          .toList();
      bundle['customVerbs'] = customs;
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
    final favorites =
        ((bundle['favoriteVerbs'] as List?) ?? const [])
            .map((value) => value.toString())
            .toSet()
          ..remove(verb.key);
    bundle['favoriteVerbs'] = favorites.toList();
  }

  void _toggleFavorite(_VerbDraft verb) {
    final bundle = _copyBundle();
    final favorites = _favorites;
    if (!favorites.add(verb.key)) favorites.remove(verb.key);
    bundle['favoriteVerbs'] = favorites.toList();
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
    });
  }

  Future<void> _deleteVerb([_VerbDraft? target]) async {
    final verb = target ?? _flushSelectedVerb();
    if (verb == null) return;
    final hideDefault = widget.personalMode && !verb.isCustom;
    final ok = hideDefault
        ? await showAppConfirmDialog(
              context: context,
              title: 'Hide “${verb.label}”?',
              message:
                  'Hides this default verb from your catalog. You can unhide it later.',
              confirmLabel: 'Hide verb',
            ) ==
            true
        : await showVerbEditorDeleteVerbDialog(
            context: context,
            tokens: _t,
            verb: verb.label,
            category: verb.category,
            sport: widget.sport,
          );
    if (!ok || !mounted) return;

    final category = verb.category;
    final siblings =
        _allVerbs.where((v) => v.category == category).toList(growable: false);
    final index = siblings.indexWhere((v) => v.key == verb.key);
    final nextKey = () {
      if (siblings.length <= 1) return null;
      if (index < 0) return siblings.first.key;
      if (index + 1 < siblings.length) return siblings[index + 1].key;
      return siblings[index - 1].key;
    }();

    _pushUndo('Deleted “${verb.label}”');
    final bundle = _copyBundle();
    _removeVerbFromBundle(bundle, verb);
    if (hideDefault) {
      _selectedKey = verb.key;
    } else {
      _selectedKey = nextKey;
      _selectedCategory = category;
    }
    _emit(bundle);
    setState(_ensureSelection);
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

  List<_VerbDraft> get _verbsInSelectedCategory {
    final cat = _selectedCategory;
    if (cat == null) return const [];
    return _allVerbs.where((v) => v.category == cat).toList();
  }

  List<VerbSearchHit> get _searchHits {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return const <VerbSearchHit>[];
    final hits = <VerbSearchHit>[];
    for (final verb in _allVerbs) {
      final hay = '${verb.category} ${verb.label} ${verb.key}'.toLowerCase();
      if (hay.contains(q)) {
        hits.add(VerbSearchHit(
          key: verb.key,
          category: verb.category,
          label: verb.label,
        ));
      }
      if (hits.length >= 40) break;
    }
    return hits;
  }

  void _selectCategoryOnly(String category) {
    if (category == '__new__') {
      unawaited(_addCategory());
      return;
    }
    _flushSelectedVerb();
    setState(() {
      _selectedCategory = category;
      _renamingCategory = false;
      final visible =
          _allVerbs.where((v) => v.category == category).toList();
      _selectedKey = visible.isEmpty ? null : visible.first.key;
    });
  }

  void _selectVerbOnly(String? key) {
    if (key == '__new__') {
      _newVerb();
      return;
    }
    if (key == null) return;
    _selectVerbFromBrowser(key);
  }

  Future<void> _startRenameCategory() async {
    final current = _selectedCategory;
    if (current == null || current == 'Favorites') return;
    setState(() {
      _renamingCategory = true;
      _categoryRenameController.text = current;
    });
  }

  void _cancelRenameCategory() {
    setState(() => _renamingCategory = false);
  }

  void _commitRenameCategory(String raw) {
    final current = _selectedCategory;
    if (current == null) {
      _cancelRenameCategory();
      return;
    }
    final next = raw.trim();
    if (next.isEmpty || next == current || next == 'Favorites') {
      _cancelRenameCategory();
      return;
    }
    if (_categories.any((c) => c.toLowerCase() == next.toLowerCase())) {
      _cancelRenameCategory();
      return;
    }
    _pushUndo('Renamed “$current” to $next');
    final bundle = _copyBundle();
    final categories = List<String>.from(
      (bundle['categoryOrder'] as List?) ?? _categories,
    );
    final index = categories.indexOf(current);
    if (index >= 0) {
      categories[index] = next;
    } else {
      categories.add(next);
    }
    bundle['categoryOrder'] = categories;
    final order = Map<String, dynamic>.from(
      (bundle['verbOrder'] as Map?) ?? const {},
    );
    final moved = List<String>.from((order.remove(current) as List?) ?? const []);
    order[next] = [...moved, ...List<String>.from((order[next] as List?) ?? const [])];
    bundle['verbOrder'] = order;
    for (final verb in _allVerbs.where((v) => v.category == current)) {
      _writeVerbRecord(bundle, verb.copyWith(category: next));
    }
    setState(() {
      _selectedCategory = next;
      _renamingCategory = false;
    });
    _emit(bundle);
  }

  Future<void> _moveCategoryMenu() async {
    final verb = _flushSelectedVerb();
    if (verb == null) return;
    final others =
        _categories.where((c) => c != verb.category).toList(growable: false);
    if (others.isEmpty) return;
    final picked = await showMoveCategoryMenu(
      context: context,
      anchorKey: _moveButtonKey,
      tokens: _t,
      verbLabel: verb.label,
      categories: others,
    );
    if (!mounted || picked == null) return;
    _pushUndo('Moved “${verb.label}” to $picked');
    _setVerbCategory(verb, picked);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final all = _allVerbs;
    final verb = _selectedVerb;
    final category = _selectedCategory ??
        ( _categories.isEmpty ? null : _categories.first);
    final inCategory = _verbsInSelectedCategory;
    final width = MediaQuery.sizeOf(context).width;
    final stackBoxes = width < 760;
    final iconOnlySecondary = width < 1100;
    final iconOnlyMost = width < 900;
    final canvas = widget.personalMode ? t.surface : t.bg;

    final categoryBox = VerbEditorPickerBox(
      tokens: t,
      label: 'CATEGORY',
      actions: [
        VerbEditorActionButton(
          tokens: t,
          icon: PhosphorIconsRegular.pencilSimple,
          label: 'Rename',
          iconOnly: iconOnlySecondary || iconOnlyMost,
          enabled: category != null && category != 'Favorites',
          onPressed: _startRenameCategory,
        ),
        VerbEditorActionButton(
          tokens: t,
          icon: PhosphorIconsRegular.trash,
          label: 'Delete category',
          danger: true,
          enabled: category != null &&
              category != 'Favorites' &&
              _categories.length > 1,
          onPressed: () => _deleteCategory(category),
        ),
      ],
      child: _renamingCategory
          ? CategoryRenameField(
              tokens: t,
              controller: _categoryRenameController,
              onSubmit: _commitRenameCategory,
              onCancel: _cancelRenameCategory,
            )
          : _boxedSelect<String>(
              tokens: t,
              value: category,
              enabled: !widget.busy && _categories.isNotEmpty,
              items: [
                for (final c in _categories)
                  DropdownMenuItem(
                    value: c,
                    child: Text(
                      '$c (${all.where((v) => v.category == c).length})',
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const DropdownMenuItem(
                  value: '__new__',
                  child: Text('＋ New category…', softWrap: false),
                ),
              ],
              onChanged: (v) {
                if (v != null) _selectCategoryOnly(v);
              },
            ),
    );

    final verbBox = VerbEditorPickerBox(
      tokens: t,
      label: 'VERB',
      actions: [
        KeyedSubtree(
          key: _moveButtonKey,
          child: VerbEditorActionButton(
            tokens: t,
            icon: PhosphorIconsRegular.arrowBendUpRight,
            label: 'Move category',
            iconOnly: iconOnlyMost,
            enabled: verb != null && _categories.length > 1,
            onPressed: _moveCategoryMenu,
          ),
        ),
        VerbEditorActionButton(
          tokens: t,
          icon: PhosphorIconsRegular.copy,
          label: 'Duplicate',
          iconOnly: iconOnlySecondary || iconOnlyMost,
          enabled: verb != null,
          onPressed: verb == null ? null : _duplicateVerb,
        ),
        VerbEditorActionButton(
          tokens: t,
          icon: PhosphorIconsRegular.trash,
          label: 'Delete verb',
          danger: true,
          enabled: verb != null,
          onPressed: verb == null ? null : () => _deleteVerb(verb),
        ),
      ],
      child: inCategory.isEmpty
          ? Row(
              children: [
                Expanded(
                  child: _boxedSelect<String>(
                    tokens: t,
                    value: null,
                    enabled: false,
                    hint: 'No verbs yet',
                    items: const [],
                    onChanged: null,
                  ),
                ),
                const SizedBox(width: 8),
                VerbEditorActionButton(
                  tokens: t,
                  icon: PhosphorIconsRegular.plus,
                  label: 'New verb',
                  onPressed: _newVerb,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: _boxedSelect<String>(
                    tokens: t,
                    value: verb?.key,
                    enabled: !widget.busy,
                    items: [
                      for (final v in inCategory)
                        DropdownMenuItem(
                          value: v.key,
                          child: Text(
                            v.label,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const DropdownMenuItem(
                        value: '__new__',
                        child: Text('＋ New verb…', softWrap: false),
                      ),
                    ],
                    onChanged: _selectVerbOnly,
                  ),
                ),
                const SizedBox(width: 6),
                _iconSquare(
                  tokens: t,
                  tooltip: verb != null && _favorites.contains(verb.key)
                      ? 'Remove favorite'
                      : 'Favorite',
                  icon: verb != null && _favorites.contains(verb.key)
                      ? PhosphorIconsFill.star
                      : PhosphorIconsRegular.star,
                  color: verb != null && _favorites.contains(verb.key)
                      ? FfTokens.favorites
                      : t.textSecondary,
                  onPressed: verb == null ? null : () => _toggleFavorite(verb),
                ),
                _iconSquare(
                  tokens: t,
                  tooltip: 'Previous verb',
                  icon: PhosphorIconsRegular.caretLeft,
                  onPressed: all.isEmpty ? null : () => _stepVerb(-1),
                ),
                _iconSquare(
                  tokens: t,
                  tooltip: 'Next verb',
                  icon: PhosphorIconsRegular.caretRight,
                  onPressed: all.isEmpty ? null : () => _stepVerb(1),
                ),
              ],
            ),
    );

    final body = Column(
      children: [
        VerbEditorTopBar(
          tokens: t,
          sport: widget.sport,
          sports: widget.sports,
          busy: widget.busy,
          searchController: _searchController,
          searchFocus: _searchFocus,
          searchResults: _searchHits,
          onSportChanged: widget.onSportChanged,
          onSearchChanged: (_) => setState(() {}),
          onPickSearchResult: (key) {
            _selectVerbFromBrowser(key);
            _searchController.clear();
            _searchFocus.unfocus();
            setState(() {});
          },
          onClearSearch: () {
            _searchController.clear();
            setState(() {});
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: stackBoxes
              ? Column(
                  children: [
                    categoryBox,
                    const SizedBox(height: 8),
                    verbBox,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: categoryBox),
                    const SizedBox(width: 8),
                    Expanded(child: verbBox),
                  ],
                ),
        ),
        Expanded(
          child: ClipRect(
            child: verb == null
                ? Center(
                    child: Text(
                      category == null
                          ? 'Choose a category'
                          : 'No verbs in $category yet',
                      style: t.metaStyle.copyWith(color: t.textSecondary),
                    ),
                  )
                : _VerbEditorPane(
                    key: _editorPaneKey,
                    tokens: t,
                    canvasColor: canvas,
                    sport: widget.sport,
                    categories: _categories,
                    verb: verb,
                    isFavorite: _favorites.contains(verb.key),
                    selectedGroupId: _selectedGroupId,
                    renaming: _renaming,
                    nameFocus: _nameFocus,
                    sampleIndex: _sampleIndex,
                    onRenameMode: () => setState(() => _renaming = true),
                    onRename: (value) {
                      _rename(verb, value);
                      setState(() => _renaming = false);
                    },
                    onToggleFavorite: () => _toggleFavorite(verb),
                    onGroupSelected: (id) =>
                        setState(() => _selectedGroupId = id),
                    onAuthoringChanged: (value) =>
                        _updateAuthoring(verb, value),
                    onDraftChanged: _saveVerb,
                    onShuffle: () => setState(() => _sampleIndex++),
                  ),
          ),
        ),
        if (_undoMessage != null)
          Material(
            color: t.selected,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _undoMessage!,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: t.metaStyle.copyWith(color: t.text),
                    ),
                  ),
                  TextButton(
                    onPressed: _undo,
                    child: Text(
                      'Undo',
                      style: t.metaStyle.copyWith(
                        color: FfTokens.gold,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        VerbEditorFooter(
          tokens: t,
          busy: widget.busy,
          pendingChanges: _pendingChanges,
          personalMode: widget.personalMode,
          onDiscard: _discardDrafts,
          onPublish: _publishDrafts,
        ),
      ],
    );

    final clipped = ClipRect(
      child: ColoredBox(color: canvas, child: body),
    );

    if (widget.embedded) return clipped;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: canvas,
        border: Border.all(color: t.divider),
        borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
        child: clipped,
      ),
    );
  }

  Widget _boxedSelect<T>({
    required FfTokens tokens,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
    bool enabled = true,
    String? hint,
  }) {
    return SizedBox(
      height: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.sunken,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tokens.divider),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            hint: hint == null
                ? null
                : Text(
                    hint,
                    softWrap: false,
                    style: tokens.metaStyle.copyWith(color: tokens.textSecondary),
                  ),
            dropdownColor: tokens.surface,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            style: tokens.metaStyle.copyWith(color: tokens.text),
            borderRadius: BorderRadius.circular(8),
            items: items,
            onChanged: enabled ? onChanged : null,
          ),
        ),
      ),
    );
  }

  Widget _iconSquare({
    required FfTokens tokens,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 30,
        height: 34,
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          icon: PhosphorIcon(
            icon,
            size: FfIcons.size,
            color: color ??
                (onPressed == null
                    ? tokens.text.withValues(alpha: 0.28)
                    : null),
          ),
        ),
      ),
    );
  }
}

class _EditorSnapshot {
  const _EditorSnapshot({
    required this.bundle,
    required this.selectedCategory,
    required this.selectedKey,
    required this.pendingChanges,
  });

  final Map<String, dynamic> bundle;
  final String? selectedCategory;
  final String? selectedKey;
  final int pendingChanges;
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
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
              color: tokens.sunken,
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
            icon: PhosphorIconsRegular.caretLeft,
            tooltip: 'Previous verb',
            onPressed: busy || !canStep ? null : onPrevious,
          ),
          _HeaderIconButton(
            tokens: tokens,
            icon: PhosphorIconsRegular.caretRight,
            tooltip: 'Next verb',
            onPressed: busy || !canStep ? null : onNext,
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 26,
            child: OutlinedButton.icon(
              onPressed: busy || onDuplicateVerb == null
                  ? null
                  : onDuplicateVerb,
              icon: PhosphorIcon(
                PhosphorIconsRegular.copy,
                size: 11,
                color: onDuplicateVerb == null
                    ? tokens.text.withValues(alpha: 0.28)
                    : tokens.text.withValues(alpha: 0.72),
              ),
              label: const Text('Duplicate'),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.text.withValues(alpha: 0.80),
                side: BorderSide(color: tokens.divider),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 26,
            child: OutlinedButton.icon(
              onPressed:
                  busy || onDeleteVerb == null ? null : onDeleteVerb,
              icon: PhosphorIcon(
                deleteActionIsUnhide
                    ? PhosphorIconsRegular.eye
                    : deleteActionIsHide
                        ? PhosphorIconsRegular.eyeSlash
                        : PhosphorIconsRegular.trash,
                size: 11,
                color: onDeleteVerb == null
                    ? tokens.text.withValues(alpha: 0.28)
                    : deleteActionIsUnhide
                        ? tokens.text.withValues(alpha: 0.72)
                        : const Color(0xFFF07167),
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
                        : const Color(0xFFF07167),
                side: BorderSide(
                  color: onDeleteVerb == null
                      ? tokens.divider
                      : deleteActionIsUnhide
                          ? tokens.divider
                          : const Color(0x55FF6B6B),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 26,
            child: OutlinedButton.icon(
              onPressed: busy ? null : onNewVerb,
              icon: PhosphorIcon(
                PhosphorIconsRegular.plus,
                size: 11,
                color: tokens.accent,
              ),
              label: const Text('New verb'),
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.accent,
                side: BorderSide(color: tokens.accent),
                padding: const EdgeInsets.symmetric(horizontal: 7),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
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
    final name = titleCaseVerbName(_name.text);
    if (name.isEmpty) return;
    if (_name.text != name) {
      _name.value = TextEditingValue(
        text: name,
        selection: TextSelection.collapsed(offset: name.length),
      );
    }
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

class _AddCategoryDialog extends StatefulWidget {
  const _AddCategoryDialog({
    required this.tokens,
    required this.existing,
    this.moveSelectedVerb = false,
  });

  final FfTokens tokens;
  final List<String> existing;

  /// When true, creating the category also moves the selected verb into it.
  final bool moveSelectedVerb;

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _normalized {
    final parts = _name.text.trim().split(RegExp(r'\s+'));
    return parts
        .where((part) => part.isNotEmpty)
        .map(
          (part) => part.length == 1
              ? part.toUpperCase()
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  String? get _error {
    final name = _normalized;
    if (name.isEmpty) return null;
    if (name == 'Favorites') return 'Favorites is reserved.';
    final taken = widget.existing.any(
      (category) => category.toLowerCase() == name.toLowerCase(),
    );
    if (taken) return 'That category already exists.';
    return null;
  }

  void _submit() {
    final name = _normalized;
    if (name.isEmpty || _error != null) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final error = _error;
    final canCreate = _normalized.isNotEmpty && error == null;
    return AppDialogFfStyle(
      enabled: true,
      child: Theme(
        data: Theme.of(context).copyWith(extensions: <ThemeExtension<dynamic>>[t]),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 360,
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
                          child: Text(
                            widget.moveSelectedVerb
                                ? 'MOVE VERB TO NEW CATEGORY'
                                : 'Add category',
                            style: TextStyle(
                              fontFamily: FfTokens.labelFamily,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: t.text,
                            ),
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
                        if (widget.moveSelectedVerb) ...[
                          Text(
                            'Creates a category and moves the selected verb into it.',
                            style: t.metaStyle.copyWith(
                              color: t.text.withValues(alpha: 0.70),
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        AppDialogLabeledField(
                          label: 'Category name',
                          bottomGap: 6,
                          child: AppDialogControlShell(
                            child: TextField(
                              controller: _name,
                              autofocus: true,
                              style: t.metaStyle.copyWith(
                                fontSize: 11,
                                color: t.text,
                                height: 1.25,
                              ),
                              cursorColor: t.accent,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => _submit(),
                              decoration: appDialogBareFieldDecoration(),
                            ),
                          ),
                        ),
                        if (error != null)
                          Text(
                            error,
                            style: t.metaStyle.copyWith(
                              fontSize: 11,
                              color: FfTokens.danger,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
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
                          label: widget.moveSelectedVerb
                              ? 'Move verb'
                              : 'Add category',
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

class _DeleteCategoryVerbRow {
  const _DeleteCategoryVerbRow({
    required this.key,
    required this.label,
  });

  final String key;
  final String label;
}

class _DeleteCategoryResult {
  const _DeleteCategoryResult({
    required this.destination,
    required this.deleteKeys,
  });

  final String destination;
  final Set<String> deleteKeys;
}

class _DeleteCategoryDialog extends StatefulWidget {
  const _DeleteCategoryDialog({
    required this.tokens,
    required this.category,
    required this.verbs,
    required this.destinations,
  });

  final FfTokens tokens;
  final String category;
  final List<_DeleteCategoryVerbRow> verbs;
  final List<String> destinations;

  @override
  State<_DeleteCategoryDialog> createState() => _DeleteCategoryDialogState();
}

class _DeleteCategoryDialogState extends State<_DeleteCategoryDialog> {
  late String _destination;
  late final Set<String> _deleteKeys;

  @override
  void initState() {
    super.initState();
    _destination = widget.destinations.first;
    _deleteKeys = <String>{};
  }

  void _submit() {
    Navigator.pop(
      context,
      _DeleteCategoryResult(
        destination: _destination,
        deleteKeys: Set<String>.from(_deleteKeys),
      ),
    );
  }

  Widget _actionChip({
    required FfTokens tokens,
    required String label,
    required bool selected,
    required bool danger,
    required VoidCallback onTap,
  }) {
    final border = selected
        ? (danger ? const Color(0xFFF07167) : tokens.accent)
        : tokens.divider;
    final fill = selected
        ? (danger
            ? const Color(0xFFF07167).withValues(alpha: 0.16)
            : tokens.selectedFill)
        : tokens.badgeFill;
    final color = selected
        ? (danger ? const Color(0xFFF07167) : tokens.text)
        : tokens.text.withValues(alpha: 0.55);
    return Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        side: BorderSide(color: border, width: selected ? 1.2 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: tokens.metaStyle.copyWith(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final hasVerbs = widget.verbs.isNotEmpty;
    final deleteCount = _deleteKeys.length;
    final moveCount = widget.verbs.length - deleteCount;
    return AppDialogFfStyle(
      enabled: true,
      child: Theme(
        data: Theme.of(context).copyWith(extensions: <ThemeExtension<dynamic>>[t]),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 440,
            constraints: const BoxConstraints(maxHeight: 520),
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
                          child: Text(
                            'Delete “${widget.category}”',
                            style: TextStyle(
                              fontFamily: FfTokens.labelFamily,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: t.text,
                            ),
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
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            hasVerbs
                                ? 'Choose whether each verb is moved or deleted '
                                    'before removing this category.'
                                : 'This category is empty and can be removed.',
                            style: t.metaStyle.copyWith(
                              color: t.text.withValues(alpha: 0.70),
                              height: 1.35,
                            ),
                          ),
                          if (hasVerbs) ...[
                            const SizedBox(height: 12),
                            AppDialogLabeledDropdown<String>(
                              label: 'Move selected verbs to',
                              bottomGap: 10,
                              value: _destination,
                              items: [
                                for (final category in widget.destinations)
                                  DropdownMenuItem(
                                    value: category,
                                    child: Text(category),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _destination = value);
                              },
                            ),
                            Row(
                              children: [
                                Text(
                                  'Verbs in ${widget.category}',
                                  style: appDialogFieldLabelStyleOf(context),
                                ),
                                const Spacer(),
                                TextButton(
                                  onPressed: () => setState(_deleteKeys.clear),
                                  child: Text(
                                    'Move all',
                                    style: t.metaStyle.copyWith(
                                      fontSize: 11,
                                      color: t.text.withValues(alpha: 0.62),
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => setState(() {
                                    _deleteKeys
                                      ..clear()
                                      ..addAll(
                                        widget.verbs.map((verb) => verb.key),
                                      );
                                  }),
                                  child: Text(
                                    'Delete all',
                                    style: t.metaStyle.copyWith(
                                      fontSize: 11,
                                      color: const Color(0xFFF07167)
                                          .withValues(alpha: 0.90),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: t.sunken,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: t.divider),
                              ),
                              child: Column(
                                children: [
                                  for (var i = 0;
                                      i < widget.verbs.length;
                                      i++) ...[
                                    if (i > 0)
                                      Divider(height: 1, color: t.divider),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        8,
                                        8,
                                        8,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              widget.verbs[i].label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: t.metaStyle.copyWith(
                                                color: t.text,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          _actionChip(
                                            tokens: t,
                                            label: 'Move',
                                            selected: !_deleteKeys
                                                .contains(widget.verbs[i].key),
                                            danger: false,
                                            onTap: () => setState(
                                              () => _deleteKeys.remove(
                                                widget.verbs[i].key,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          _actionChip(
                                            tokens: t,
                                            label: 'Delete',
                                            selected: _deleteKeys
                                                .contains(widget.verbs[i].key),
                                            danger: true,
                                            onTap: () => setState(
                                              () => _deleteKeys.add(
                                                widget.verbs[i].key,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (hasVerbs) ...[
                              const SizedBox(height: 8),
                              Text(
                                [
                                  if (moveCount > 0)
                                    'Move $moveCount → $_destination',
                                  if (deleteCount > 0) 'Delete $deleteCount',
                                ].join(' · '),
                                style: t.metaStyle.copyWith(
                                  fontSize: 11,
                                  color: t.text.withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
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
                          label: 'Delete category',
                          fontSize: 11,
                          isPrimary: true,
                          onPressed: _submit,
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
        icon: PhosphorIcon(
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
            icon: PhosphorIconsRegular.cloudArrowUp,
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
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
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
                                            color: const Color(0xFFF07167),
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
    required this.canvasColor,
    required this.sport,
    required this.categories,
    required this.verb,
    required this.isFavorite,
    required this.selectedGroupId,
    required this.renaming,
    required this.nameFocus,
    required this.sampleIndex,
    required this.onRenameMode,
    required this.onRename,
    required this.onToggleFavorite,
    required this.onGroupSelected,
    required this.onAuthoringChanged,
    required this.onDraftChanged,
    required this.onShuffle,
  });

  final FfTokens tokens;
  final Color canvasColor;
  final String sport;
  final List<String> categories;
  final _VerbDraft verb;
  final bool isFavorite;
  final String? selectedGroupId;
  final bool renaming;
  final FocusNode nameFocus;
  final int sampleIndex;
  final VoidCallback onRenameMode;
  final ValueChanged<String> onRename;
  final VoidCallback onToggleFavorite;
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

  void _commitVerbName([String? _]) {
    final titled = titleCaseVerbName(_name.text);
    if (_name.text != titled) {
      _name.value = TextEditingValue(
        text: titled,
        selection: TextSelection.collapsed(offset: titled.length),
      );
      setState(() {});
    }
    widget.onRename(titled);
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
      color: widget.canvasColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
                  AppDialogLabeledField(
                    label: 'Verb name',
                    bottomGap: 10,
                    child: AppDialogControlShell(
                      child: TextField(
                        controller: _name,
                        focusNode: widget.nameFocus,
                        style: appDialogFieldTextStyleOf(context),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: _commitVerbName,
                        onEditingComplete: _commitVerbName,
                        decoration: appDialogBareFieldDecoration(),
                      ),
                    ),
                  ),
                  _SectionHeading(
                    tokens: t,
                    label: 'WORDING',
                  ),
                  const SizedBox(height: 6),
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
                                activeTrackColor: t.accent,
                                inactiveTrackColor: t.hover,
                                thumbColor: WidgetStateProperty.resolveWith((states) {
                                  if (states.contains(WidgetState.selected)) {
                                    return t.bg;
                                  }
                                  return t.textTertiary;
                                }),
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
                            enabled: _useSingularPhrase,
                            child: TextField(
                              controller: _singular,
                              enabled: _useSingularPhrase,
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
                      const SizedBox(width: 8),
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
                                activeTrackColor: t.accent,
                                inactiveTrackColor: t.hover,
                                thumbColor: WidgetStateProperty.resolveWith((states) {
                                  if (states.contains(WidgetState.selected)) {
                                    return t.bg;
                                  }
                                  return t.textTertiary;
                                }),
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
                            enabled: _usePluralPhrase,
                            child: TextField(
                              controller: _plural,
                              enabled: _usePluralPhrase,
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
                      const SizedBox(width: 8),
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
                            child: TextField(
                              controller: _ing,
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
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppDialogLabeledField(
                          label: 'Opponent joiner',
                          bottomGap: 0,
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
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppDialogLabeledField(
                          label: 'With teammates',
                          bottomGap: 0,
                          labelLeading: SizedBox(
                            width: 28,
                            height: 16,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: Switch.adaptive(
                                value: _withTeammates,
                                onChanged: (value) {
                                  setState(() => _withTeammates = value);
                                  _emitDraft();
                                },
                                activeTrackColor: t.accent,
                                inactiveTrackColor: t.hover,
                                thumbColor: WidgetStateProperty.resolveWith((states) {
                                  if (states.contains(WidgetState.selected)) {
                                    return t.bg;
                                  }
                                  return t.textTertiary;
                                }),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                          child: AppDialogControlShell(
                            enabled: _withTeammates,
                            child: Text(
                              'Celebrates with teammates Heater Ace #24 and Dunkin Deuces #8 (pick from teams selected)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: appDialogFieldTextStyleOf(
                                context,
                                enabled: _withTeammates,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: t.divider),
                  const SizedBox(height: 10),
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
                  const SizedBox(height: 14),
                  Divider(height: 1, color: t.divider),
                  const SizedBox(height: 10),
                  VerbEditSubOptionsSection(
                    verbLabel: widget.verb.key,
                    sport: widget.sport,
                    value: _subOptions,
                    onChanged: _setSubOptions,
                    showBorder: false,
                  ),
                  const SizedBox(height: 14),
                  Divider(height: 1, color: t.divider),
                  const SizedBox(height: 10),
                  AppDialogLabeledField(
                    label: 'Keywords',
                    bottomGap: 0,
                    labelTrailing: Text(
                      'Only applied when keyword mode is on',
                      softWrap: false,
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
                        decoration: appDialogBareFieldDecoration(),
                      ),
                    ),
                  ),
          ],
        ),
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
  List<String> get _timing {
    final unit = sportPeriodNoun(widget.sport);
    return [
      'during the second $unit',
      'during the third $unit',
      'during the first $unit',
    ];
  }

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

    Widget chip(String id, String label) {
      final selected = id == 'plural'
          ? selectedId == 'plural'
          : selectedId != 'plural';
      return Material(
        color: selected ? t.selectedFill : t.badgeFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FfTokens.radiusChip),
          side: BorderSide(
            color: selected ? t.accent : t.divider,
          ),
        ),
        child: InkWell(
          onTap: () => setState(() => _variantId = id),
          borderRadius: BorderRadius.circular(FfTokens.radiusChip),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              label,
              softWrap: false,
              style: t.metaStyle.copyWith(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: t.text,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 28,
          child: Row(
            children: [
              Text(
                'PREVIEW',
                style: FfTokens.railLabel.copyWith(
                  color: t.text.withValues(alpha: 0.70),
                ),
              ),
              const Spacer(),
              chip('base', 'Single player'),
              const SizedBox(width: 6),
              chip('plural', 'Two or more players'),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: t.sunken,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.divider),
          ),
          child: Text.rich(
            TextSpan(
              style: t.bodyStyle.copyWith(
                fontSize: 13,
                height: 1.4,
                color: t.text.withValues(alpha: 0.82),
              ),
              children: [
                TextSpan(text: '$subject '),
                TextSpan(
                  text: action,
                  style: TextStyle(
                    color: t.text,
                    backgroundColor: t.selected.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: ' $tail'),
              ],
            ),
          ),
        ),
        if (variants.where((v) => v.id != 'base' && v.id != 'plural').isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final v in variants.where((v) => v.id != 'base' && v.id != 'plural'))
                Material(
                  color: v.id == selectedId ? t.selectedFill : t.badgeFill,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                    side: BorderSide(
                      color: v.id == selectedId ? t.accent : t.divider,
                    ),
                  ),
                  child: InkWell(
                    onTap: () => setState(() => _variantId = v.id),
                    borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        v.label,
                        softWrap: false,
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
