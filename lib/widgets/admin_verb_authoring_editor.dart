import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../caption_style/sport_verb_categories.dart';
import '../services/app_defaults_firestore_service.dart';
import '../caption_style/verb_authoring_model.dart';
import '../caption_style/verb_caption_wording.dart';
import '../caption_style/verb_defaults_bundle.dart';
import '../caption_style/verb_sub_options.dart';
import '../screens/caption_v2/data/caption_v2_caption_domain.dart';
import '../theme/ff_tokens.dart';
import '../utils/default_verb_keywords.dart';
import '../utils/verb_name_casing.dart';
import 'admin_verb_editor_v3_chrome.dart';
import 'app_styled_dialogs.dart';
import 'ff_dropdown.dart';
import 'new_verb_dialog.dart';
import 'verb_edit_sub_options_section.dart';

typedef AdminVerbAction = Future<void> Function({
  required String key,
  required Map<String, dynamic> record,
  required bool isCustom,
});

/// Virtual category in the verb editor. Not stored on a verb.
const _kAllVerbsCategory = 'All';

/// Quieter than [FfTokens.accent2] so the app-default tag does not glow.
const _appDefaultVerbLabel = Color(0xFFA86A45);

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
    this.onPersistIdle,
    this.onPendingChanges,
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
  /// Returns false when the write did not land.
  final Future<bool> Function({String? successLabel})? onWriteSportDefaults;
  /// Personal mode: wait until the latest bundle write has finished.
  final Future<void> Function()? onPersistIdle;
  /// Unpublished edit count for [sport]. `0` means that sport is clean.
  final void Function(String sport, int count)? onPendingChanges;

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
  final TextEditingController _verbRenameController = TextEditingController();
  final FocusNode _verbRenameFocus = FocusNode();
  final GlobalKey<_VerbEditorPaneState> _editorPaneKey =
      GlobalKey<_VerbEditorPaneState>();
  final GlobalKey _moveButtonKey = GlobalKey();
  final GlobalKey _selectedRowKey = GlobalKey();

  /// Wording the open verb pane is showing right now, for the top preview.
  final ValueNotifier<_VerbLive?> _live = ValueNotifier<_VerbLive?>(null);
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

  /// Last bundle emitted to the parent. The verb dropdown reads this so a
  /// save shows up before the parent passes the map back.
  Map<String, dynamic>? _pendingBundle;
  _EditorSnapshot? _undoSnapshot;
  String? _undoMessage;
  /// When true, Undo must write the restored catalog, not only the local draft.
  bool _undoLive = false;

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
    if (identical(widget.bundle, _pendingBundle)) {
      _pendingBundle = null;
    }
    if (oldWidget.sport != widget.sport) {
      widget.onPendingChanges?.call(oldWidget.sport, _pendingChanges);
      _pendingBundle = null;
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
    widget.onPendingChanges?.call(widget.sport, _pendingChanges);
    _saveDebounce?.cancel();
    _undoTimer?.cancel();
    _nameFocus.dispose();
    _live.dispose();
    _searchFocus.dispose();
    _searchController.dispose();
    _verbRenameFocus.dispose();
    _categoryRenameController.dispose();
    _verbRenameController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _deepCopyMap(Map<String, dynamic> source) {
    return Map<String, dynamic>.from(
      (jsonDecode(jsonEncode(source)) as Map).cast<String, dynamic>(),
    );
  }

  void _reportPending([String? sport]) {
    widget.onPendingChanges?.call(sport ?? widget.sport, _pendingChanges);
  }

  void _markDraftChange() {
    if (!mounted) {
      _pendingChanges += 1;
      _reportPending();
      return;
    }
    setState(() => _pendingChanges += 1);
    _reportPending();
  }

  void _clearUndo() {
    _undoTimer?.cancel();
    _undoSnapshot = null;
    _undoMessage = null;
    _undoLive = false;
  }

  void _pushUndo(String message, {bool live = false}) {
    _undoSnapshot = _EditorSnapshot(
      bundle: _deepCopyMap(_bundle),
      selectedCategory: _selectedCategory,
      selectedKey: _selectedKey,
      pendingChanges: _pendingChanges,
    );
    _undoTimer?.cancel();
    _undoTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(_clearUndo);
    });
    _undoLive = live;
    if (mounted) {
      setState(() => _undoMessage = message);
    } else {
      _undoMessage = message;
    }
  }

  void _undo() {
    final snap = _undoSnapshot;
    if (snap == null) return;
    final live = _undoLive;
    _clearUndo();
    setState(() {
      _selectedCategory = snap.selectedCategory;
      _selectedKey = snap.selectedKey;
      _pendingChanges = snap.pendingChanges;
    });
    _reportPending();
    widget.onBundleChanged(_deepCopyMap(snap.bundle));
    setState(_ensureSelection);
    if (live) unawaited(_commitLiveBundle(successLabel: 'Restored'));
  }

  /// Writes the current catalog now. Delete uses this so Publish or Save is
  /// not a second step. Other drafts in the catalog go out with it.
  Future<void> _commitLiveBundle({String successLabel = 'Deleted'}) async {
    await widget.onPersistIdle?.call();
    if (!widget.personalMode) {
      final write = widget.onWriteSportDefaults;
      if (write == null) {
        _markDraftChange();
        return;
      }
      final ok = await write(successLabel: successLabel);
      if (!ok || !mounted) {
        if (mounted) _markDraftChange();
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _publishedBaseline = _deepCopyMap(_bundle);
      _pendingChanges = 0;
    });
    _reportPending();
  }

  void _discardDrafts() {
    final baseline = _publishedBaseline;
    if (baseline == null) return;
    _flushSelectedVerb();
    _clearUndo();
    setState(() => _pendingChanges = 0);
    _reportPending();
    widget.onBundleChanged(_deepCopyMap(baseline));
    setState(_ensureSelection);
  }

  List<String> _changedVerbLines() {
    final baseline = _publishedBaseline;
    if (baseline == null) return const [];
    final before = _indexedVerbRecords(baseline);
    final after = _indexedVerbRecords(_bundle);
    final hiddenBefore = _deletedVerbKeys(baseline);
    final hiddenAfter = _deletedVerbKeys(_bundle);
    final keys = <String>{
      ...before.keys,
      ...after.keys,
      ...hiddenBefore,
      ...hiddenAfter,
    };
    final lines = <String>[];
    for (final key in keys) {
      final previous = before[key];
      final next = after[key];
      final wasHidden = hiddenBefore.contains(key);
      final isHidden = hiddenAfter.contains(key);
      final previousLabel = _verbRecordLabel(previous, key);
      final nextLabel = _verbRecordLabel(next ?? previous, key);
      if (previous == null && next != null) {
        lines.add('Added $nextLabel');
      } else if (previous != null && next == null) {
        lines.add('Removed $previousLabel');
      } else if (wasHidden != isHidden) {
        lines.add(isHidden ? 'Hidden $nextLabel' : 'Restored $nextLabel');
      } else if (previous != null &&
          next != null &&
          jsonEncode(_canonJson(previous)) != jsonEncode(_canonJson(next))) {
        lines.add(
          previousLabel.toLowerCase() == nextLabel.toLowerCase()
              ? nextLabel
              : '$previousLabel → $nextLabel',
        );
      }
    }
    lines.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return lines;
  }

  Map<String, Map<String, dynamic>> _indexedVerbRecords(
    Map<String, dynamic> bundle,
  ) {
    final out = <String, Map<String, dynamic>>{};
    final overrides = bundle['verbOverrides'];
    if (overrides is Map) {
      overrides.forEach((key, value) {
        if (value is! Map) return;
        final name = key.toString().trim();
        if (name.isEmpty) return;
        out[name.toLowerCase()] = Map<String, dynamic>.from(value);
      });
    }
    for (final raw in (bundle['customVerbs'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final record = Map<String, dynamic>.from(raw);
      final name = (record['key'] ?? record['label'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      out[name.toLowerCase()] = record;
    }
    return out;
  }

  Set<String> _deletedVerbKeys(Map<String, dynamic> bundle) {
    return {
      for (final value in (bundle['deletedVerbs'] as List?) ?? const [])
        value.toString().trim().toLowerCase(),
    }..removeWhere((value) => value.isEmpty);
  }

  String _verbRecordLabel(Map<String, dynamic>? record, String key) {
    final label = (record?['label'] ?? '').toString().trim();
    if (label.isNotEmpty) return label;
    if (key.isEmpty) return 'Untitled verb';
    return key;
  }

  Object? _canonJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonJson(value[key])};
    }
    if (value is List) {
      return [for (final item in value) _canonJson(item)];
    }
    return value;
  }

  Future<bool> _confirmPublishChangedVerbs(List<String> changed) async {
    final t = _t;
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        return AppDialogFfStyle(
          enabled: true,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
                    border: Border.all(color: t.divider),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Publish these verbs?',
                          style: t.labelStyle.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          changed.isEmpty
                              ? 'No verb wording changed. Category or order changes will still publish.'
                              : 'These verbs differ from the last published defaults:',
                          style: t.metaStyle.copyWith(
                            fontSize: 12,
                            height: 1.35,
                            color: t.text.withValues(alpha: 0.72),
                          ),
                        ),
                        if (changed.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Flexible(
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: changed.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (_, index) => Text(
                                changed[index],
                                style: t.metaStyle.copyWith(
                                  fontSize: 13,
                                  color: t.text,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ElevatedGreyButton(
                              label: 'Cancel',
                              fontSize: 11,
                              onPressed: () => Navigator.pop(ctx, false),
                            ),
                            const SizedBox(width: 8),
                            ElevatedGreyButton(
                              label: 'Publish',
                              fontSize: 11,
                              isPrimary: true,
                              isAdmin: true,
                              onPressed: () => Navigator.pop(ctx, true),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    return ok == true;
  }

  Future<void> _publishDrafts() async {
    final typed = _verbRenameController.text;
    final wasRenaming = _renaming;
    if (wasRenaming) {
      _saveDebounce?.cancel();
      if (_pendingDraft != null) _commitPendingDraft();
      final current = _selectedVerb;
      if (current != null) {
        _rename(current, typed);
      }
    } else {
      _flushSelectedVerb();
    }
    if (_renamingCategory) {
      _commitRenameCategory(_categoryRenameController.text);
    }
    setState(() {
      _renaming = false;
      _renamingCategory = false;
    });
    _verbRenameFocus.unfocus();
    _emit(_copyBundle(), countAsDraft: false);
    await widget.onPersistIdle?.call();
    if (!widget.personalMode) {
      final changed = _changedVerbLines();
      final ok = await _confirmPublishChangedVerbs(changed);
      if (!ok || !mounted) return;
      final write = widget.onWriteSportDefaults;
      if (write != null) {
        await write(successLabel: 'Published');
      } else if (widget.onPublishCurrentVerb != null) {
        await _runCurrentVerbAction(widget.onPublishCurrentVerb);
      }
    }
    if (!mounted) return;
    setState(() {
      _publishedBaseline = _deepCopyMap(_bundle);
      _pendingChanges = 0;
      _clearUndo();
    });
    _reportPending();
  }

  FfTokens get _t => Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;

  Map<String, dynamic> get _bundle {
    final pending = _pendingBundle;
    if (pending != null && !identical(pending, widget.bundle)) return pending;
    return widget.bundle;
  }

  List<String> get _categories {
    final raw = _bundle['categoryOrder'];
    final categories = raw is List
        ? raw.map((value) => value.toString()).toList()
        : SportVerbCategories.forSport(widget.sport).keys.toList();
    return categories
        .where((category) => category != 'Favorites' && category != 'All')
        .toList();
  }

  List<String> get _defaultCategoryList {
    final raw = _bundle['defaultCategories'];
    if (raw is List && raw.isNotEmpty) {
      return [
        for (final value in raw)
          if (value.toString().trim().isNotEmpty &&
              value.toString() != 'Favorites' &&
              value.toString() != 'All')
            value.toString(),
      ];
    }
    return SportVerbCategories.forSport(widget.sport).keys.toList();
  }

  Set<String> get _hiddenCategories =>
      ((_bundle['hiddenCategories'] as List?) ?? const [])
          .map((value) => value.toString())
          .toSet();

  bool _isDefaultCategory(String category) {
    final name = category.trim().toLowerCase();
    return _defaultCategoryList.any((item) => item.toLowerCase() == name);
  }

  Set<String> get _favorites =>
      ((_bundle['favoriteVerbs'] as List?) ?? const [])
          .map((value) => value.toString())
          .toSet();

  Map<String, Map<String, dynamic>> get _overrides {
    final raw = _bundle['verbOverrides'];
    if (raw is! Map) return {};
    return raw.map(
      (key, value) => MapEntry(
        key.toString(),
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{},
      ),
    );
  }

  List<Map<String, dynamic>> get _customs =>
      ((_bundle['customVerbs'] as List?) ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();

  List<_VerbDraft> get _allVerbs {
    final deleted = ((_bundle['deletedVerbs'] as List?) ?? const [])
        .map((value) => value.toString())
        .toSet();
    // Personal editor keeps hidden defaults visible so they can be unhidden.
    final includeHidden = widget.personalMode;
    final overrides = _overrides;
    final customs = _customs;
    final byKey = <String, _VerbDraft>{};
    final catalogComplete = VerbDefaultsBundle.isComplete(_bundle);

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

    // Shipped verbs stay in the list even when a complete catalog's override
    // map never stored them. Hidden ones stay visible in the personal editor.
    final factory = SportVerbCategories.forSport(widget.sport);
    for (final entry in factory.entries) {
      for (final key in entry.value) {
        if (key.trim().isEmpty || byKey.containsKey(key)) continue;
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

    for (final record in customs) {
      final key = (record['key'] ?? record['label'] ?? '').toString().trim();
      if (key.isEmpty) continue;
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

    final orderRaw = _bundle['verbOrder'];
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
    // The editor no longer has an "All" chip (search replaces it), so a
    // leftover All selection falls back to the first real category.
    if (!categories.contains(_selectedCategory)) {
      _selectedCategory = categories.first;
    }
    final visible = _allVerbs
        .where((verb) => verb.category == _selectedCategory)
        .toList();
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
      ..._bundle,
      'categoryOrder': [..._categories],
      'favoriteVerbs': _favorites.toList(),
      'verbOverrides': {
        for (final entry in _overrides.entries)
          entry.key: Map<String, dynamic>.from(entry.value),
      },
      'customVerbs': _customs.map(Map<String, dynamic>.from).toList(),
      'defaultCategories': _defaultCategoryList,
      'hiddenCategories': _hiddenCategories.toList(),
    };
  }

  void _emit(Map<String, dynamic> bundle, {bool countAsDraft = true}) {
    if (!widget.personalMode) {
      bundle['defaultCategories'] = [
        for (final value in ((bundle['categoryOrder'] as List?) ?? _categories))
          if (value.toString() != 'Favorites' && value.toString() != 'All')
            value.toString(),
      ];
      bundle['hiddenCategories'] = <String>[];
    }
    _pendingBundle = bundle;
    if (countAsDraft) {
      _markDraftChange();
    } else if (mounted) {
      setState(() {});
    }
    widget.onBundleChanged(bundle);
  }

  /// Insert [key] among [keys] by label, case-insensitive. Existing order of
  /// the other verbs is left alone.
  void _insertVerbKeyAlphabetically(
    List<String> keys,
    String key,
    String label,
  ) {
    keys.remove(key);
    final name = label.trim().toLowerCase();
    final labels = {
      for (final verb in _allVerbs) verb.key: verb.label,
    };
    var index = keys.length;
    for (var i = 0; i < keys.length; i++) {
      final other = (labels[keys[i]] ?? keys[i]).trim().toLowerCase();
      if (name.compareTo(other) < 0) {
        index = i;
        break;
      }
    }
    keys.insert(index, key);
  }

  void _placeInVerbOrder(Map<String, dynamic> bundle, _VerbDraft draft) {
    final order = Map<String, dynamic>.from(
      (bundle['verbOrder'] as Map?) ?? const {},
    );
    final keys = <String>[
      for (final value in ((order[draft.category] as List?) ?? const []))
        value.toString(),
    ];
    if (keys.contains(draft.key)) return;
    _insertVerbKeyAlphabetically(keys, draft.key, draft.label);
    order[draft.category] = keys;
    bundle['verbOrder'] = order;
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

  void _undeleteKey(Map<String, dynamic> bundle, String key) {
    final name = key.trim().toLowerCase();
    if (name.isEmpty) return;
    final deleted = ((bundle['deletedVerbs'] as List?) ?? const [])
        .map((value) => value.toString())
        .where((value) => value.toLowerCase() != name)
        .toList();
    bundle['deletedVerbs'] = deleted;
  }

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
      _undeleteKey(bundle, draft.key);
      _undeleteKey(bundle, draft.label);
      _placeInVerbOrder(bundle, draft);
    } else {
      final overrides = Map<String, dynamic>.from(
        (bundle['verbOverrides'] as Map?) ?? const {},
      );
      overrides[draft.key] = record;
      bundle['verbOverrides'] = overrides;
      _placeInVerbOrder(bundle, draft);
    }
    _emit(bundle);
  }

  _VerbDraft? _flushSelectedVerb() {
    if (_renaming) return _selectedVerb;
    // Pull the latest wording from the open editor before committing.
    // Ignore a pane draft whose key does not match the selected verb — that
    // is a stale Untitled-verb capture from before a rename.
    final captured = _editorPaneKey.currentState?.captureDraft();
    if (captured != null && captured.key == _selectedKey) {
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
    if (pending != null && pending.key == _selectedKey) {
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
      if (match != null && _selectedCategory != _kAllVerbsCategory) {
        _selectedCategory = match.category;
      }
      _selectedKey = key;
      _selectedGroupId = _selectedVerb?.authoring.groups.firstOrNull?.id;
      _renaming = false;
    });
  }

  void _stepVerb(int delta) {
    final list = _visibleVerbs;
    if (list.isEmpty) return;
    final index = list.indexWhere((verb) => verb.key == _selectedKey);
    final nextIndex = index < 0
        ? 0
        : (index + delta + list.length) % list.length;
    _selectVerbFromBrowser(list[nextIndex].key);
    _scrollSelectedRowIntoView();
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
    for (final entry in order.entries.toList()) {
      if (entry.value is! List) continue;
      final list = List<String>.from(entry.value as List)..remove(oldKey);
      order[entry.key] = list;
    }
    final renamedKeys = List<String>.from(
      (order[updated.category] as List?) ?? const <String>[],
    );
    _insertVerbKeyAlphabetically(renamedKeys, newKey, trimmed);
    order[updated.category] = renamedKeys;
    bundle['verbOrder'] = order;
    _undeleteKey(bundle, oldKey);
    _undeleteKey(bundle, newKey);
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
      _pinFactoryCategoryOverride(bundle, updated.key, next);
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
    _insertVerbKeyAlphabetically(dest, updated.key, updated.label);
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

  Future<void> _openOrderBoard() async {
    final verbsByCategory = <String, List<_OrderVerb>>{
      for (final category in _categories)
        category: [
          for (final verb in _allVerbs.where((verb) => verb.category == category))
            _OrderVerb(key: verb.key, label: verb.label),
        ],
    };
    final result = await showDialog<_OrderBoardResult>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) => _OrderBoardDialog(
        tokens: _t,
        categories: List<String>.from(_categories),
        verbsByCategory: verbsByCategory,
        selectedCategory: _selectedCategory != null &&
                _categories.contains(_selectedCategory)
            ? _selectedCategory!
            : (_categories.isEmpty ? null : _categories.first),
      ),
    );
    if (!mounted || result == null) return;
    _applyOrderBoard(result);
  }

  void _applyOrderBoard(_OrderBoardResult result) {
    _pushUndo('Reordered categories');
    final bundle = _copyBundle();
    bundle['categoryOrder'] = result.categories;
    final order = Map<String, dynamic>.from(
      (bundle['verbOrder'] as Map?) ?? const {},
    );
    final byKey = {for (final verb in _allVerbs) verb.key: verb};
    for (final category in result.categories) {
      final keys = result.verbKeys[category] ?? const <String>[];
      order[category] = List<String>.from(keys);
      for (final key in keys) {
        final verb = byKey[key];
        if (verb == null || verb.category == category) continue;
        final base = (_pendingDraft != null && _pendingDraft!.key == key)
            ? _pendingDraft!
            : verb;
        _writeVerbRecord(bundle, base.copyWith(category: category));
        if (_pendingDraft?.key == key) _pendingDraft = null;
      }
    }
    bundle['verbOrder'] = order;
    if (result.selectedCategory != null) {
      setState(() => _selectedCategory = result.selectedCategory);
    }
    _emit(bundle);
  }

  Future<void> _setCategoryHidden(String category, {required bool hidden}) async {
    final current = category.trim();
    if (current.isEmpty || !_isDefaultCategory(current)) return;
    if (hidden) {
      final ok = await showAppConfirmDialog(
            context: context,
            title: 'Hide “$current”?',
            message:
                'Hides this default category from your verb list. You can show it again here.',
            confirmLabel: 'Hide category',
          ) ==
          true;
      if (!ok || !mounted) return;
    }
    final names = _hiddenCategories.toSet();
    if (hidden) {
      names.add(current);
    } else {
      names.removeWhere((item) => item.toLowerCase() == current.toLowerCase());
    }
    final bundle = _copyBundle();
    bundle['hiddenCategories'] = names.toList();
    _emit(bundle);
  }

  Future<void> _deleteCategory([String? categoryName]) async {
    final current = (categoryName ??
            _selectedVerb?.category ??
            _selectedCategory ??
            '')
        .trim();
    if (current.isEmpty || current == 'Favorites') return;
    if (widget.personalMode && _isDefaultCategory(current)) {
      await _setCategoryHidden(current, hidden: true);
      return;
    }

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
        _insertVerbKeyAlphabetically(destList, verb.key, updated.label);
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
      _pinFactoryCategoryOverride(bundle, updated.key, updated.category);
    }
  }

  /// Persist intentional factory-verb category moves across ensureComplete.
  void _pinFactoryCategoryOverride(
    Map<String, dynamic> bundle,
    String verbKey,
    String category,
  ) {
    final pins = Map<String, dynamic>.from(
      (bundle['categoryOverrides'] as Map?) ?? const {},
    );
    final factoryCat =
        SportVerbCategories.categoryForVerb(verbKey, sport: widget.sport) ?? '';
    if (factoryCat.isNotEmpty && category.trim() == factoryCat) {
      pins.remove(verbKey);
    } else if (category.trim().isNotEmpty) {
      pins[verbKey] = category.trim();
    }
    bundle['categoryOverrides'] = pins;
  }

  void _removeVerbFromBundle(Map<String, dynamic> bundle, _VerbDraft verb) {
    if (_pendingDraft?.key == verb.key) _pendingDraft = null;
    // Tombstone every delete so Firebase/app-default catalogs cannot resurrect
    // the verb on the next merge (custom or default).
    // Tombstone every delete so a shared custom verb cannot come back from
    // another account's local copy.
    final deleted = ((bundle['deletedVerbs'] as List?) ?? const [])
        .map((value) => value.toString())
        .toSet()
      ..add(verb.key);
    final label = verb.label.trim();
    if (label.isNotEmpty) deleted.add(label);
    bundle['deletedVerbs'] = deleted.toList();
    if (verb.isCustom) {
      final customs = ((bundle['customVerbs'] as List?) ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .where((item) {
            final key = (item['key'] ?? item['label']).toString();
            return key != verb.key &&
                key.toLowerCase() != verb.key.toLowerCase();
          })
          .toList();
      bundle['customVerbs'] = customs;
      final overrides = Map<String, dynamic>.from(
        (bundle['verbOverrides'] as Map?) ?? const {},
      )..removeWhere(
          (key, _) =>
              key == verb.key || key.toLowerCase() == verb.key.toLowerCase(),
        );
      bundle['verbOverrides'] = overrides;
    } else {
      if (!widget.personalMode) {
        final overrides = Map<String, dynamic>.from(
          (bundle['verbOverrides'] as Map?) ?? const {},
        )..removeWhere(
            (key, _) =>
                key == verb.key || key.toLowerCase() == verb.key.toLowerCase(),
          );
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

  Future<void> _newVerb() async {
    final keys = {
      for (final verb in _allVerbs) verb.key.toLowerCase(),
      for (final verb in _allVerbs) verb.label.toLowerCase(),
      for (final value in ((_bundle['deletedVerbs'] as List?) ?? const []))
        value.toString().toLowerCase(),
    };
    final result = await showNewVerbDialog(
      context: context,
      tokens: _t,
      categories: _categories,
      existingVerbNames: keys,
    );
    if (!mounted || result == null) return;

    if (result.createdCategory) {
      _pushUndo('Added “${result.category}”');
      final bundle = _copyBundle();
      final categories = List<String>.from(
        (bundle['categoryOrder'] as List?) ?? _categories,
      )..add(result.category);
      bundle['categoryOrder'] = categories;
      final order = Map<String, dynamic>.from(
        (bundle['verbOrder'] as Map?) ?? const {},
      );
      order.putIfAbsent(result.category, () => <String>[]);
      bundle['verbOrder'] = order;
      setState(() => _selectedCategory = result.category);
      _emit(bundle);
    }

    final key = result.title;
    final category = result.category;
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
      _selectedCategory = category;
      _selectedKey = key;
      _renaming = false;
    });
    _saveVerb(draft, debounce: Duration.zero);
  }

  void _focusVerbRename() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _verbRenameFocus.requestFocus();
      final text = _verbRenameController.text;
      _verbRenameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: text.length,
      );
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

    _pushUndo('Deleted “${verb.label}”', live: true);
    final bundle = _copyBundle();
    _removeVerbFromBundle(bundle, verb);
    if (hideDefault) {
      _selectedKey = verb.key;
    } else {
      _selectedKey = nextKey;
      _selectedCategory = category;
    }
    _emit(bundle, countAsDraft: false);
    setState(_ensureSelection);
    await _commitLiveBundle();
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
    _insertVerbKeyAlphabetically(list, verb.key, verb.label);
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

  /// Orange dot: shipped with the app (factory list or published catalog).
  /// Blue dot: a verb that exists only in this user's own list.
  bool _dotIsUserMade(_VerbDraft verb) {
    if (!verb.isCustom) return false;
    final defaults = _appDefaultVerbKeysLower;
    final key = verb.key.trim().toLowerCase();
    final label = verb.label.trim().toLowerCase();
    return !defaults.contains(key) && !defaults.contains(label);
  }

  Set<String> get _appDefaultVerbKeysLower {
    final keys = <String>{
      for (final entry in SportVerbCategories.forSport(widget.sport).entries)
        for (final label in entry.value)
          if (label.trim().isNotEmpty) label.trim().toLowerCase(),
    };
    final published =
        AppDefaultsFirestoreService.peekCachedSportVerbSettings(widget.sport);
    if (published == null) return keys;
    final overrides = published['verbOverrides'];
    if (overrides is Map) {
      for (final key in overrides.keys) {
        final name = key.toString().trim().toLowerCase();
        if (name.isNotEmpty) keys.add(name);
      }
    }
    for (final raw in ((published['customVerbs'] as List?) ?? const [])) {
      if (raw is! Map) continue;
      final name =
          (raw['key'] ?? raw['label'] ?? '').toString().trim().toLowerCase();
      if (name.isNotEmpty) keys.add(name);
    }
    return keys;
  }

  List<_VerbDraft> get _verbsInSelectedCategory {
    final cat = _selectedCategory;
    if (cat == null) return const [];
    final list = cat == _kAllVerbsCategory
        ? _allVerbs
        : _allVerbs.where((v) => v.category == cat).toList();
    if (cat != _kAllVerbsCategory && !widget.personalMode) return list;
    final sorted = List<_VerbDraft>.from(list);
    sorted.sort((a, b) {
      final byLabel =
          a.label.toLowerCase().compareTo(b.label.toLowerCase());
      if (byLabel != 0) return byLabel;
      return a.category.toLowerCase().compareTo(b.category.toLowerCase());
    });
    return sorted;
  }

  String get _searchQuery => _searchController.text.trim();

  bool get _searching => _searchQuery.isNotEmpty;

  /// Verbs across every category whose name, wording, keywords or category
  /// contain the query. Empty when there is no query.
  List<_VerbDraft> get _searchResults {
    final q = _searchQuery.toLowerCase();
    if (q.isEmpty) return const <_VerbDraft>[];
    bool has(String value) => value.toLowerCase().contains(q);
    return [
      for (final verb in _allVerbs)
        if (has(verb.label) ||
            has(verb.key) ||
            has(verb.category) ||
            has(verb.singular) ||
            has(verb.plural) ||
            has(verb.ing) ||
            verb.keywords.any(has))
          verb,
    ];
  }

  /// What the left list shows: search results, else the open category.
  List<_VerbDraft> get _visibleVerbs =>
      _searching ? _searchResults : _verbsInSelectedCategory;

  void _onSearchChanged() {
    final results = _searchResults;
    if (results.isNotEmpty && !results.any((v) => v.key == _selectedKey)) {
      _selectVerbFromBrowser(results.first.key);
      return;
    }
    setState(() {});
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
  }

  KeyEventResult _onEditorKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_searchFocus.hasFocus) {
      if (key == LogicalKeyboardKey.escape) {
        if (_searchController.text.isNotEmpty) {
          _clearSearch();
        } else {
          _searchFocus.unfocus();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowUp) {
        _stepVerb(key == LogicalKeyboardKey.arrowDown ? 1 : -1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key != LogicalKeyboardKey.slash) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext != null &&
        (focusContext.widget is EditableText ||
            focusContext.findAncestorWidgetOfExactType<EditableText>() !=
                null)) {
      return KeyEventResult.ignored;
    }
    _searchFocus.requestFocus();
    return KeyEventResult.handled;
  }

  void _selectCategoryOnly(String category) {
    if (category == '__new__') {
      unawaited(_addCategory());
      return;
    }
    if (category == '__rename__') {
      unawaited(_startRenameCategory());
      return;
    }
    if (category == '__delete_cat__') {
      final current = _selectedCategory;
      if (current != null) unawaited(_deleteCategory(current));
      return;
    }
    _flushSelectedVerb();
    setState(() {
      _selectedCategory = category;
      _renamingCategory = false;
      final visible = category == _kAllVerbsCategory
          ? _verbsInSelectedCategory
          : _allVerbs.where((v) => v.category == category).toList();
      _selectedKey = visible.isEmpty ? null : visible.first.key;
    });
  }

  void _beginVerbRename() {
    final verb = _selectedVerb;
    if (verb == null) return;
    _verbRenameController.text = verb.label;
    setState(() => _renaming = true);
    _focusVerbRename();
  }

  void _cancelVerbRename() {
    setState(() => _renaming = false);
  }

  void _commitVerbRename(String raw) {
    final verb = _selectedVerb;
    if (verb == null) {
      _cancelVerbRename();
      return;
    }
    _rename(verb, raw);
    if (!mounted) return;
    setState(() => _renaming = false);
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
    final next = titleCaseVerbName(raw);
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

  Widget _verbKindDot(FfTokens t, bool isCustom) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: isCustom ? t.accent : _appDefaultVerbLabel,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _verbKindKey(FfTokens t, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: appDialogFieldLabelStyleOf(context).copyWith(
            fontSize: 11,
            height: 1,
            color: t.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  void _pickCategoryChip(String name) {
    final wasSearching = _searching;
    if (wasSearching) _searchController.clear();
    if (name == _selectedCategory) {
      setState(() {});
      return;
    }
    _selectCategoryOnly(name);
  }

  void _scrollSelectedRowIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _selectedRowKey.currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 120),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  Widget _categoryChip(
    FfTokens t, {
    required String name,
    required int count,
    required bool selected,
    required bool dimmed,
  }) {
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Material(
        color: selected ? t.selected : FfTokens.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: selected ? BorderSide(color: t.accentEdge) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          hoverColor: t.hover,
          onTap: widget.busy ? null : () => _pickCategoryChip(name),
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  softWrap: false,
                  style: t.metaStyle.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected ? t.text : t.textSecondary,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '$count',
                  softWrap: false,
                  style: t.metaStyle.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: selected ? FfTokens.accentHover : t.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _addCategoryChip(FfTokens t) {
    return Tooltip(
      message: 'Add category',
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: t.divider),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          hoverColor: t.hover,
          onTap: widget.busy ? null : () => unawaited(_addCategory()),
          child: SizedBox(
            width: 28,
            height: 24,
            child: Center(
              child: PhosphorIcon(
                PhosphorIconsBold.plus,
                size: 12,
                color: t.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _verbRow(FfTokens t, _VerbDraft item, {required bool selected}) {
    final searching = _searching;
    final label = item.label.trim().isEmpty ? 'Untitled' : item.label;
    Widget flag(IconData icon, bool on, String tip) => Tooltip(
          message: tip,
          child: PhosphorIcon(
            icon,
            size: 12,
            color: t.textTertiary.withValues(alpha: on ? 1 : 0.25),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? FfTokens.nocturneAccentRow : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          hoverColor: t.text.withValues(alpha: 0.04),
          onTap: widget.busy ? null : () => _selectVerbFromBrowser(item.key),
          child: Stack(
            children: [
              Container(
                key: selected ? _selectedRowKey : null,
                constraints: const BoxConstraints(minHeight: 28),
                padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
                child: Row(
                  children: [
                    if (widget.personalMode) ...[
                      _verbKindDot(t, _dotIsUserMade(item)),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.metaStyle.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: (selected ? t.text : t.textSecondary)
                              .withValues(alpha: item.isHidden ? 0.55 : 1),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (searching)
                      Text(
                        item.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.metaStyle.copyWith(
                          fontSize: 11,
                          color: t.textTertiary,
                        ),
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          flag(
                            PhosphorIconsRegular.usersThree,
                            item.usePluralPhrase,
                            'Two or more',
                          ),
                          const SizedBox(width: 4),
                          flag(
                            PhosphorIconsRegular.smiley,
                            item.subOptions.celebrationEnabled,
                            'Reaction',
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (selected)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: ColoredBox(color: t.accent),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeftPanel(FfTokens t, String? category) {
    final searching = _searching;
    final all = _allVerbs;
    final list = _visibleVerbs;
    final hiddenNames = _hiddenCategories.map((c) => c.toLowerCase()).toSet();
    final categoryHidden =
        category != null && hiddenNames.contains(category.toLowerCase());
    final canRename = category != null &&
        category != 'Favorites' &&
        !_renamingCategory &&
        !widget.busy;
    final canDelete =
        category != null && _categories.length > 1 && !widget.busy;
    final personalDefault = widget.personalMode &&
        category != null &&
        _isDefaultCategory(category);

    final tools = <Widget>[
      _VerbToolButton(
        tokens: t,
        icon: PhosphorIconsRegular.dotsSixVertical,
        tooltip: 'Order categories',
        onPressed: widget.busy || _categories.isEmpty
            ? null
            : () => unawaited(_openOrderBoard()),
      ),
      _VerbToolButton(
        tokens: t,
        icon: PhosphorIconsRegular.pencilSimple,
        tooltip: 'Rename category',
        onPressed: canRename ? () => unawaited(_startRenameCategory()) : null,
      ),
      if (personalDefault)
        _VerbToolButton(
          tokens: t,
          icon: categoryHidden
              ? PhosphorIconsRegular.eye
              : PhosphorIconsRegular.eyeSlash,
          tooltip: categoryHidden ? 'Show category' : 'Hide category',
          onPressed: widget.busy
              ? null
              : () => unawaited(
                    _setCategoryHidden(category, hidden: !categoryHidden),
                  ),
        )
      else
        _VerbToolButton(
          tokens: t,
          icon: PhosphorIconsRegular.trash,
          tooltip: 'Delete category',
          danger: true,
          onPressed: canDelete
              ? () => unawaited(_deleteCategory(category))
              : null,
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: verbEditorPanelDecoration(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 24,
            child: Row(
              children: [
                Text(
                  searching ? 'RESULTS' : 'CATEGORIES',
                  style: verbEditorPanelTitle(t),
                ),
                const Spacer(),
                if (!searching) ...tools,
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final c in _categories)
                if (_renamingCategory && !searching && c == category)
                  SizedBox(
                    width: 170,
                    child: CategoryRenameField(
                      tokens: t,
                      controller: _categoryRenameController,
                      onSubmit: _commitRenameCategory,
                      onCancel: _cancelRenameCategory,
                    ),
                  )
                else
                  _categoryChip(
                    t,
                    name: c,
                    count: all.where((v) => v.category == c).length,
                    selected: !searching && c == category,
                    dimmed: hiddenNames.contains(c.toLowerCase()),
                  ),
              _addCategoryChip(t),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: FfTokens.card,
                borderRadius: BorderRadius.circular(8),
              ),
              child: list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      child: Text(
                        searching
                            ? 'No verbs match “$_searchQuery”'
                            : 'No verbs yet',
                        style: t.metaStyle.copyWith(
                          fontSize: 12,
                          color: t.textTertiary,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final item = list[index];
                        return _verbRow(
                          t,
                          item,
                          selected: item.key == _selectedKey,
                        );
                      },
                    ),
            ),
          ),
          if (!searching) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  hoverColor: t.hover,
                  onTap: widget.busy || category == null ? null : _newVerb,
                  child: Container(
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PhosphorIcon(
                          PhosphorIconsBold.plus,
                          size: 11,
                          color: t.textSecondary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Add verb',
                          style: t.metaStyle.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (widget.personalMode) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                _verbKindKey(t, _appDefaultVerbLabel, 'App default verb'),
                const SizedBox(width: 10),
                _verbKindKey(t, t.accent, 'User made verb'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRightPanel(
    FfTokens t,
    _VerbDraft? verb,
    String? category,
    Color canvas,
  ) {
    if (verb == null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 28),
        decoration: verbEditorPanelDecoration(t),
        child: Center(
          child: Text(
            category == null ? 'Choose a category' : 'No verbs in $category yet',
            style: t.metaStyle.copyWith(color: t.textSecondary),
          ),
        ),
      );
    }
    final favorite = _favorites.contains(verb.key);
    final hasVerbs = _visibleVerbs.isNotEmpty;
    final unhide = widget.personalMode && verb.isHidden;

    final title = _renaming
        ? CategoryRenameField(
            tokens: t,
            controller: _verbRenameController,
            focusNode: _verbRenameFocus,
            onSubmit: _commitVerbRename,
            onCancel: _cancelVerbRename,
          )
        : Text(
            verb.label.trim().isEmpty ? 'Untitled' : verb.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: t.text,
            ),
          );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: verbEditorPanelDecoration(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 28,
            child: Row(
              children: [
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: title),
                ),
                const SizedBox(width: 6),
                if (widget.personalMode)
                  _VerbToolButton(
                    tokens: t,
                    icon: favorite
                        ? PhosphorIconsFill.star
                        : PhosphorIconsRegular.star,
                    tooltip: favorite ? 'Remove favorite' : 'Favorite',
                    color: favorite ? FfTokens.favorites : null,
                    onPressed: () => _toggleFavorite(verb),
                  ),
                _VerbToolButton(
                  tokens: t,
                  icon: PhosphorIconsRegular.caretUp,
                  tooltip: 'Previous verb',
                  onPressed: hasVerbs ? () => _stepVerb(-1) : null,
                ),
                _VerbToolButton(
                  tokens: t,
                  icon: PhosphorIconsRegular.caretDown,
                  tooltip: 'Next verb',
                  onPressed: hasVerbs ? () => _stepVerb(1) : null,
                ),
                KeyedSubtree(
                  key: _moveButtonKey,
                  child: _VerbToolButton(
                    tokens: t,
                    icon: PhosphorIconsRegular.arrowBendUpRight,
                    tooltip: 'Move to category',
                    onPressed: widget.busy ||
                            _categories.length < 2 ||
                            _renaming
                        ? null
                        : () => unawaited(_moveCategoryMenu()),
                  ),
                ),
                _VerbToolButton(
                  tokens: t,
                  icon: PhosphorIconsRegular.pencilSimple,
                  tooltip: 'Rename verb',
                  onPressed: widget.busy || _renaming ? null : _beginVerbRename,
                ),
                if (unhide)
                  _VerbToolButton(
                    tokens: t,
                    icon: PhosphorIconsRegular.eye,
                    tooltip: 'Unhide verb',
                    onPressed: widget.busy ? null : () => _unhideVerb(verb),
                  )
                else
                  _VerbToolButton(
                    tokens: t,
                    icon: PhosphorIconsRegular.trash,
                    tooltip: 'Delete verb',
                    danger: true,
                    onPressed: widget.busy || _renaming
                        ? null
                        : () => unawaited(_deleteVerb(verb)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _VerbEditorPane(
              key: _editorPaneKey,
              tokens: t,
              canvasColor: canvas,
              sport: widget.sport,
              categories: _categories,
              verb: verb,
              isFavorite: favorite,
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
              onGroupSelected: (id) => setState(() => _selectedGroupId = id),
              onAuthoringChanged: (value) => _updateAuthoring(verb, value),
              onDraftChanged: _saveVerb,
              onShuffle: () => setState(() => _sampleIndex++),
              onLiveChanged: (live) => _live.value = live,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(FfTokens t, _VerbDraft verb) {
    return ValueListenableBuilder<_VerbLive?>(
      valueListenable: _live,
      builder: (context, live, _) {
        final l = live != null && live.verbKey == verb.key
            ? live
            : _VerbLive.fromDraft(verb);
        final label = verb.label;
        final singular = l.singular;
        return _ResolvedPreview(
          tokens: t,
          sport: widget.sport,
          verbKey: verb.key,
          verbLabel: label,
          phrase: singular,
          pluralPhrase: l.plural.isEmpty ? singular : l.plural,
          useSingularPhrase: l.useSingularPhrase,
          usePluralPhrase: l.usePluralPhrase,
          ingPhrase: l.ing.isEmpty
              ? VerbCaptionWording.defaultIngWording(
                  label,
                  singular.isEmpty ? verb.key : singular,
                )
              : l.ing,
          sampleIndex: _sampleIndex,
          omitAgainst: l.opponentJoiner.trim().isEmpty,
          opponentJoiner: l.opponentJoiner.trim(),
          withTeammates: l.withTeammates,
          showPlural: false,
          subOptions: l.subOptions,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final verb = _selectedVerb;
    final category = _selectedCategory ??
        (_categories.isEmpty ? null : _categories.first);
    final canvas = widget.personalMode ? Colors.transparent : t.bg;

    final body = Column(
      children: [
        VerbEditorTopBar(
          tokens: t,
          sport: widget.sport,
          sports: widget.sports,
          busy: widget.busy,
          searchController: _searchController,
          searchFocus: _searchFocus,
          searchResults: const <VerbSearchHit>[],
          onSportChanged: widget.onSportChanged,
          onSearchChanged: (_) => _onSearchChanged(),
          onPickSearchResult: (_) {},
          onClearSearch: _clearSearch,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stack = constraints.maxWidth < 860;
                final left = _buildLeftPanel(t, category);
                final right = _buildRightPanel(t, verb, category, canvas);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (verb != null) ...[
                      _buildPreview(t, verb),
                      const SizedBox(height: 8),
                    ],
                    Expanded(
                      child: stack
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(flex: 10, child: left),
                                const SizedBox(height: 8),
                                Expanded(flex: 17, child: right),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(flex: 10, child: left),
                                const SizedBox(width: 8),
                                Expanded(flex: 17, child: right),
                              ],
                            ),
                    ),
                  ],
                );
              },
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
          changedVerbs: widget.personalMode ? const [] : _changedVerbLines(),
          onDiscard: _discardDrafts,
          onPublish: _publishDrafts,
        ),
      ],
    );

    final clipped = ClipRect(
      child: ColoredBox(
        color: canvas,
        // "/" jumps to search; arrows and Esc work while search has focus.
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onEditorKey,
          child: body,
        ),
      ),
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
}

class _OrderVerb {
  const _OrderVerb({required this.key, required this.label});

  final String key;
  final String label;
}

class _OrderBoardResult {
  const _OrderBoardResult({
    required this.categories,
    required this.verbKeys,
    required this.selectedCategory,
  });

  final List<String> categories;
  final Map<String, List<String>> verbKeys;
  final String? selectedCategory;
}

class _OrderBoardDialog extends StatefulWidget {
  const _OrderBoardDialog({
    required this.tokens,
    required this.categories,
    required this.verbsByCategory,
    required this.selectedCategory,
  });

  final FfTokens tokens;
  final List<String> categories;
  final Map<String, List<_OrderVerb>> verbsByCategory;
  final String? selectedCategory;

  @override
  State<_OrderBoardDialog> createState() => _OrderBoardDialogState();
}

class _OrderBoardDialogState extends State<_OrderBoardDialog> {
  late List<String> _categories;
  late Map<String, List<_OrderVerb>> _verbs;
  String? _selected;
  String? _hoverCategory;

  @override
  void initState() {
    super.initState();
    _categories = List<String>.from(widget.categories);
    _verbs = {
      for (final entry in widget.verbsByCategory.entries)
        entry.key: List<_OrderVerb>.from(entry.value),
    };
    _selected = widget.selectedCategory;
  }

  List<_OrderVerb> get _selectedVerbs =>
      _selected == null ? const [] : (_verbs[_selected] ?? const []);

  void _reorderCategories(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final category = _categories.removeAt(oldIndex);
      _categories.insert(newIndex, category);
      _selected = category;
    });
  }

  void _sortCategories() {
    setState(() {
      _categories.sort(
        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );
    });
  }

  void _sortVerbs() {
    final category = _selected;
    if (category == null) return;
    setState(() {
      _verbs[category]?.sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
    });
  }

  void _reorderVerbs(int oldIndex, int newIndex) {
    final category = _selected;
    if (category == null) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final list = _verbs.putIfAbsent(category, () => <_OrderVerb>[]);
      final verb = list.removeAt(oldIndex);
      list.insert(newIndex, verb);
    });
  }

  void _moveVerbToCategory(String key, String category) {
    final current = _verbs[category];
    if (current != null && current.any((item) => item.key == key)) {
      setState(() {
        _selected = category;
        _hoverCategory = null;
      });
      return;
    }
    _OrderVerb? verb;
    for (final entry in _verbs.entries) {
      final index = entry.value.indexWhere((item) => item.key == key);
      if (index < 0) continue;
      verb = entry.value.removeAt(index);
      break;
    }
    if (verb == null) return;
    setState(() {
      _verbs.putIfAbsent(category, () => <_OrderVerb>[]).add(verb!);
      _selected = category;
      _hoverCategory = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final verbs = _selectedVerbs;
    return AppDialogFfStyle(
      enabled: true,
      child: Theme(
        data: Theme.of(context).copyWith(
          extensions: <ThemeExtension<dynamic>>[t],
        ),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 720,
            height: 520,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
              border: Border.all(color: t.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Order',
                          style: t.bodyStyle.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: t.text,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: PhosphorIcon(
                          PhosphorIconsRegular.x,
                          size: 18,
                          color: t.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text(
                    'Drag a category to change its place. Drag a verb onto a category, or onto another verb, to move it.',
                    style: t.metaStyle.copyWith(color: t.textSecondary),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(child: _categoryColumn(t)),
                        const SizedBox(width: 10),
                        Expanded(child: _verbColumn(t, verbs)),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(
                            context,
                            _OrderBoardResult(
                              categories: List<String>.from(_categories),
                              verbKeys: {
                                for (final category in _categories)
                                  category: [
                                    for (final verb
                                        in _verbs[category] ?? const <_OrderVerb>[])
                                      verb.key,
                                  ],
                              },
                              selectedCategory: _selected,
                            ),
                          );
                        },
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryColumn(FfTokens t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FfTokens.panelOutline, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _columnHeader(t, 'Categories', _sortCategories),
          Expanded(
            child: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _categories.length,
        onReorder: _reorderCategories,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final count = _verbs[category]?.length ?? 0;
          final selected = category == _selected;
          final hover = category == _hoverCategory;
          return DragTarget<String>(
            key: ValueKey('order-cat-$category'),
            onWillAcceptWithDetails: (_) {
              if (_hoverCategory != category) {
                setState(() => _hoverCategory = category);
              }
              return true;
            },
            onLeave: (_) {
              if (_hoverCategory == category) {
                setState(() => _hoverCategory = null);
              }
            },
            onAcceptWithDetails: (details) =>
                _moveVerbToCategory(details.data, category),
            builder: (context, candidate, rejected) {
              return Material(
                color: hover || candidate.isNotEmpty
                    ? t.selected
                    : selected
                        ? t.hover
                        : Colors.transparent,
                child: InkWell(
                  onTap: () => setState(() => _selected = category),
                  child: SizedBox(
                    height: 36,
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: PhosphorIcon(
                              PhosphorIconsRegular.dotsSixVertical,
                              size: 16,
                              color: t.textSecondary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.metaStyle.copyWith(
                              color: t.text,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Text(
                            '$count',
                            style: t.metaStyle.copyWith(color: t.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
          ),
        ],
      ),
    );
  }

  Widget _columnHeader(FfTokens t, String title, VoidCallback onSort) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.metaStyle.copyWith(
                color: t.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onSort,
            child: Text(
              'Alphabetical',
              style: t.metaStyle.copyWith(color: t.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _verbColumn(FfTokens t, List<_OrderVerb> verbs) {
    final category = _selected;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FfTokens.panelOutline, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _columnHeader(
            t,
            category == null ? 'Verbs' : category,
            _sortVerbs,
          ),
          Expanded(
            child: verbs.isEmpty
                ? Center(
                    child: Text(
                      'No verbs in this category',
                      style: t.metaStyle.copyWith(color: t.textSecondary),
                    ),
                  )
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: verbs.length,
                    onReorder: _reorderVerbs,
                    itemBuilder: (context, index) {
                      final verb = verbs[index];
                      return Draggable<String>(
                        key: ValueKey('order-verb-${verb.key}'),
                        data: verb.key,
                        feedback: Material(
                          color: t.surface,
                          elevation: 4,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Text(
                              verb.label,
                              style: t.metaStyle.copyWith(color: t.text),
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.35,
                          child: _verbTile(t, verb, index),
                        ),
                        child: _verbTile(t, verb, index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _verbTile(FfTokens t, _OrderVerb verb, int index) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: PhosphorIcon(
                PhosphorIconsRegular.dotsSixVertical,
                size: 16,
                color: t.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              verb.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.metaStyle.copyWith(color: t.text),
            ),
          ),
        ],
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
            child: FfDropdownButton<String>(
                value: sport,
                menuColor: tokens.surface,
                style: tokens.metaStyle.copyWith(color: tokens.text),
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
    final matched = q.isEmpty
        ? widget.verbs
        : widget.verbs.where((verb) {
            final hay =
                '${verb.label} ${verb.category} ${verb.key}'.toLowerCase();
            return hay.contains(q);
          });
    final list = List<_VerbDraft>.from(matched);
    list.sort((a, b) {
      final byLabel =
          a.label.toLowerCase().compareTo(b.label.toLowerCase());
      if (byLabel != 0) return byLabel;
      return a.category.toLowerCase().compareTo(b.category.toLowerCase());
    });
    return list;
  }

  List<Object> get _rows => _filtered;

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
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'All verbs',
                  style: t.metaStyle.copyWith(
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
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
                      itemCount: _rows.length,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        if (row is String) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                            child: Text(
                              row,
                              style: t.microStyle.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: t.textSecondary,
                              ),
                            ),
                          );
                        }
                        final verb = row as _VerbDraft;
                        final verbIndex = list.indexWhere(
                          (item) => item.key == verb.key,
                        );
                        final selected = verbIndex == _highlight;
                        return Material(
                          color: selected
                              ? t.accent.withValues(alpha: 0.14)
                              : Colors.transparent,
                          child: InkWell(
                            onTap: () => _confirm(verb),
                            onHover: (hovering) {
                              if (hovering && verbIndex >= 0) {
                                setState(() => _highlight = verbIndex);
                              }
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

/// Fields the preview needs while the user is still typing.
class _VerbLive {
  const _VerbLive({
    required this.verbKey,
    required this.singular,
    required this.plural,
    required this.ing,
    required this.useSingularPhrase,
    required this.usePluralPhrase,
    required this.opponentJoiner,
    required this.withTeammates,
    required this.subOptions,
  });

  factory _VerbLive.fromDraft(_VerbDraft verb) => _VerbLive(
        verbKey: verb.key,
        singular: verb.singular,
        plural: verb.plural,
        ing: verb.ing,
        useSingularPhrase: verb.useSingularPhrase,
        usePluralPhrase: verb.usePluralPhrase,
        opponentJoiner: verb.opponentJoiner,
        withTeammates: verb.withTeammates,
        subOptions: verb.subOptions,
      );

  final String verbKey;
  final String singular;
  final String plural;
  final String ing;
  final bool useSingularPhrase;
  final bool usePluralPhrase;
  final String opponentJoiner;
  final bool withTeammates;
  final VerbSubOptions subOptions;
}

const InputDecoration _kBareFieldDecoration = InputDecoration(
  isCollapsed: true,
  filled: false,
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
  errorBorder: InputBorder.none,
  focusedErrorBorder: InputBorder.none,
  contentPadding: EdgeInsets.zero,
);

/// Compact square tool with hover fill.
class _VerbToolButton extends StatefulWidget {
  const _VerbToolButton({
    required this.tokens,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
    this.color,
  });

  final FfTokens tokens;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool danger;
  final Color? color;

  @override
  State<_VerbToolButton> createState() => _VerbToolButtonState();
}

class _VerbToolButtonState extends State<_VerbToolButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final enabled = widget.onPressed != null;
    final hot = _hover && enabled;
    final Color fg;
    if (!enabled) {
      fg = t.textTertiary.withValues(alpha: 0.4);
    } else if (hot) {
      fg = widget.danger ? FfTokens.danger : t.text;
    } else {
      fg = widget.color ?? t.textTertiary;
    }
    final fill = !hot
        ? Colors.transparent
        : (widget.danger ? FfTokens.dangerBg : t.hover);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(6),
            ),
            child: PhosphorIcon(widget.icon, size: 13, color: fg),
          ),
        ),
      ),
    );
  }
}

/// Compact switch pill.
class _VerbSwitch extends StatelessWidget {
  const _VerbSwitch({
    required this.tokens,
    required this.value,
    required this.onChanged,
  });

  final FfTokens tokens;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Semantics(
      toggled: value,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 30,
            height: 18,
            padding: const EdgeInsets.all(2),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: value ? t.accent : t.hover,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: value ? Colors.white : t.textSecondary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact field on the control fill with accent focus ring.
class _VerbFieldBox extends StatefulWidget {
  const _VerbFieldBox({
    required this.tokens,
    required this.controller,
    required this.onChanged,
    this.enabled = true,
  });

  final FfTokens tokens;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  State<_VerbFieldBox> createState() => _VerbFieldBoxState();
}

class _VerbFieldBoxState extends State<_VerbFieldBox> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final focused = _focused && widget.enabled;
    return Opacity(
      opacity: widget.enabled ? 1 : 0.35,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: t.sunken,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: focused ? t.accent : Colors.transparent,
          ),
          boxShadow: focused
              ? const [
                  BoxShadow(
                    color: FfTokens.sessionHot,
                    blurRadius: 0,
                    spreadRadius: 3,
                  ),
                ]
              : null,
        ),
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (f) => setState(() => _focused = f),
          child: TextField(
            controller: widget.controller,
            enabled: widget.enabled,
            onChanged: widget.onChanged,
            cursorColor: t.accent,
            style: t.metaStyle.copyWith(
              fontSize: 14,
              height: 1.25,
              color: t.text,
            ),
            decoration: _kBareFieldDecoration,
          ),
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
    required this.onLiveChanged,
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

  /// Fires on every edit so the parent preview can follow while typing.
  final ValueChanged<_VerbLive> onLiveChanged;

  @override
  State<_VerbEditorPane> createState() => _VerbEditorPaneState();
}

class _VerbEditorPaneState extends State<_VerbEditorPane> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _singular = TextEditingController();
  final TextEditingController _plural = TextEditingController();
  final TextEditingController _ing = TextEditingController();
  final TextEditingController _kwInput = TextEditingController();
  final FocusNode _kwFocus = FocusNode();
  final TextEditingController _opponentJoiner = TextEditingController();
  List<String> _keywordList = <String>[];
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
    _kwFocus.addListener(_onKeywordFocus);
    _loadFromVerb(widget.verb);
    _scheduleLive();
  }

  void _scheduleLive() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifyLive();
    });
  }

  void _notifyLive() {
    widget.onLiveChanged(
      _VerbLive(
        verbKey: widget.verb.key,
        singular: _singular.text.trim(),
        plural: _plural.text.trim(),
        ing: _ing.text.trim(),
        useSingularPhrase: _useSingularPhrase,
        usePluralPhrase: _usePluralPhrase,
        opponentJoiner: _opponentJoiner.text.trim(),
        withTeammates: _withTeammates,
        subOptions: _subOptions,
      ),
    );
  }

  void _loadFromVerb(_VerbDraft verb) {
    _name.text = verb.label;
    _singular.text = verb.singular;
    _plural.text = verb.plural;
    _ing.text = verb.ing;
    _keywordList = List<String>.from(verb.keywords);
    _kwInput.clear();
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
      _scheduleLive();
      return;
    }
    if (!widget.renaming &&
        oldWidget.verb.label != widget.verb.label &&
        _name.text.trim() != widget.verb.label) {
      _name.text = widget.verb.label;
    }
  }

  /// Latest name + wording from the open editor (including unsaved rename text
  /// and a keyword that was typed but not yet turned into a chip).
  _VerbDraft captureDraft() => _currentDraft(includePendingKeyword: true);

  @override
  void dispose() {
    _kwFocus.removeListener(_onKeywordFocus);
    _kwFocus.dispose();
    _name.dispose();
    _singular.dispose();
    _plural.dispose();
    _ing.dispose();
    _kwInput.dispose();
    _opponentJoiner.dispose();
    super.dispose();
  }

  void _seedSelections() {
    for (final group in _authoring.groups) {
      _selections[group.id] = group.defaultOptionId;
    }
  }

  List<String> _keywordsForDraft({required bool includePending}) {
    if (!includePending) return List<String>.from(_keywordList);
    final out = List<String>.from(_keywordList);
    for (final extra in parseVerbKeywordsField(_kwInput.text)) {
      if (!out.any((k) => k.toLowerCase() == extra.toLowerCase())) {
        out.add(extra);
      }
    }
    return out;
  }

  _VerbDraft _currentDraft({
    VerbAuthoringData? authoring,
    bool includePendingKeyword = false,
  }) {
    final name = widget.verb.label;
    return widget.verb.copyWith(
      label: name.isEmpty ? widget.verb.key : name,
      singular: _singular.text.trim(),
      plural: _plural.text.trim(),
      useSingularPhrase: _useSingularPhrase,
      usePluralPhrase: _usePluralPhrase,
      ing: _ing.text.trim(),
      keywords: _keywordsForDraft(includePending: includePendingKeyword),
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
    _notifyLive();
  }

  void _onKeywordFocus() {
    if (!mounted) return;
    if (!_kwFocus.hasFocus) {
      _commitKeywordInput();
    } else {
      setState(() {});
    }
  }

  /// Turns the typed text into chips. Commas split into several.
  void _commitKeywordInput() {
    final parts = parseVerbKeywordsField(_kwInput.text);
    if (parts.isEmpty) {
      if (_kwInput.text.isNotEmpty) _kwInput.clear();
      if (mounted) setState(() {});
      return;
    }
    var changed = false;
    for (final part in parts) {
      if (_keywordList.any((k) => k.toLowerCase() == part.toLowerCase())) {
        continue;
      }
      _keywordList.add(part);
      changed = true;
    }
    _kwInput.clear();
    setState(() {});
    if (changed) _emitDraft();
  }

  void _removeKeyword(int index) {
    if (index < 0 || index >= _keywordList.length) return;
    setState(() => _keywordList.removeAt(index));
    _emitDraft();
  }

  KeyEventResult _onKeywordKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _kwInput.text.isEmpty &&
        _keywordList.isNotEmpty) {
      _removeKeyword(_keywordList.length - 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        _kwInput.text.trim().isNotEmpty) {
      _commitKeywordInput();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onWordingChanged(String value) {
    final label = widget.verb.label.trim().isEmpty
        ? widget.verb.key
        : widget.verb.label.trim();
    final wording = value.trim().isEmpty ? widget.verb.key : value.trim();
    final autoIng = VerbCaptionWording.defaultIngWording(label, wording);
    if (_subOptions.celebrationEnabled &&
        (_ing.text.trim().isEmpty || _ing.text.trim() == _lastAutoIng)) {
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

  Widget _formRow({
    required FfTokens t,
    required double labelWidth,
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    Widget? toggle,
    bool enabled = true,
  }) {
    return SizedBox(
      height: 32,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
        child: Row(
          children: [
            SizedBox(
              width: labelWidth,
              child: Text(
                label,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: verbEditorFieldLabel(t).copyWith(fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 30, child: toggle),
            const SizedBox(width: 8),
            Expanded(
              child: _VerbFieldBox(
                tokens: t,
                controller: controller,
                enabled: enabled,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _keywordChip(FfTokens t, String keyword, int index) {
    return Container(
      height: 24,
      padding: const EdgeInsets.fromLTRB(7, 0, 2, 0),
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            keyword,
            softWrap: false,
            style: t.metaStyle.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: t.text,
            ),
          ),
          const SizedBox(width: 2),
          _VerbToolButtonMini(
            tokens: t,
            onPressed: () => _removeKeyword(index),
          ),
        ],
      ),
    );
  }

  Widget _keywordsBox(FfTokens t) {
    final focused = _kwFocus.hasFocus;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _kwFocus.requestFocus,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: FfTokens.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: focused ? t.accent : Colors.transparent,
          ),
          boxShadow: focused
              ? const [
                  BoxShadow(
                    color: FfTokens.sessionHot,
                    blurRadius: 0,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < _keywordList.length; i++)
              _keywordChip(t, _keywordList[i], i),
            SizedBox(
              width: 120,
              height: 24,
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _onKeywordKey,
                child: TextField(
                  controller: _kwInput,
                  focusNode: _kwFocus,
                  cursorColor: t.accent,
                  style: t.metaStyle.copyWith(fontSize: 12, color: t.text),
                  onChanged: (value) {
                    if (value.contains(',')) _commitKeywordInput();
                  },
                  onEditingComplete: _commitKeywordInput,
                  decoration: _kBareFieldDecoration.copyWith(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 3,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidth = constraints.maxWidth < 440 ? 90.0 : 110.0;
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('FORMS', style: verbEditorPanelTitle(t)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: FfTokens.card,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      _formRow(
                        t: t,
                        labelWidth: labelWidth,
                        label: 'Single player',
                        controller: _singular,
                        onChanged: _onWordingChanged,
                      ),
                      _formRow(
                        t: t,
                        labelWidth: labelWidth,
                        label: 'Two or more',
                        controller: _plural,
                        enabled: _usePluralPhrase,
                        toggle: _VerbSwitch(
                          tokens: t,
                          value: _usePluralPhrase,
                          onChanged: (value) {
                            setState(() {
                              _usePluralPhrase = value;
                              if (!value) _plural.clear();
                            });
                            _emitDraft();
                          },
                        ),
                        onChanged: (_) {
                          setState(() {});
                          _emitDraft();
                        },
                      ),
                      _formRow(
                        t: t,
                        labelWidth: labelWidth,
                        label: 'Reaction',
                        controller: _ing,
                        enabled: _subOptions.celebrationEnabled,
                        toggle: _VerbSwitch(
                          tokens: t,
                          value: _subOptions.celebrationEnabled,
                          onChanged: (value) {
                            if (!value) {
                              setState(() {
                                _ing.clear();
                                _lastAutoIng = '';
                              });
                            }
                            _setSubOptions(
                              _subOptions.copyWith(celebrationEnabled: value),
                            );
                          },
                        ),
                        onChanged: (_) {
                          setState(() {});
                          _emitDraft();
                        },
                      ),
                      _formRow(
                        t: t,
                        labelWidth: labelWidth,
                        label: 'Joiner',
                        controller: _opponentJoiner,
                        onChanged: (_) {
                          setState(() {});
                          _emitDraft();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: FfTokens.card,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        setState(() => _withTeammates = !_withTeammates);
                        _emitDraft();
                      },
                      child: SizedBox(
                        height: 32,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'With teammates',
                                  style: verbEditorFieldLabel(t)
                                      .copyWith(fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _VerbSwitch(
                                tokens: t,
                                value: _withTeammates,
                                onChanged: (value) {
                                  setState(() => _withTeammates = value);
                                  _emitDraft();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text('KEYWORDS', style: verbEditorPanelTitle(t)),
                const SizedBox(height: 6),
                _keywordsBox(t),
                const SizedBox(height: 8),
                VerbEditSubOptionsSection(
                  verbLabel: widget.verb.key,
                  sport: widget.sport,
                  value: _subOptions,
                  onChanged: _setSubOptions,
                  showBorder: false,
                  showCelebrationToggle: false,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// HTML `.chip button`: 18px close target.
class _VerbToolButtonMini extends StatefulWidget {
  const _VerbToolButtonMini({required this.tokens, required this.onPressed});

  final FfTokens tokens;
  final VoidCallback onPressed;

  @override
  State<_VerbToolButtonMini> createState() => _VerbToolButtonMiniState();
}

class _VerbToolButtonMiniState extends State<_VerbToolButtonMini> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? t.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: PhosphorIcon(
            PhosphorIconsBold.x,
            size: 11,
            color: _hover ? t.text : t.textTertiary,
          ),
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
    required this.showPlural,
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
  final bool showPlural;
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
        const _PreviewVariant('base', 'Single player'),
    ];
    if (widget.withTeammates) {
      variants.add(const _PreviewVariant('with_teammates', 'With teammates'));
    } else if (widget.usePluralPhrase) {
      variants.add(const _PreviewVariant('plural', 'Two or more'));
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
    final ofAt = subject.indexOf(' of ');
    final player = ofAt < 0 ? subject : subject.substring(0, ofAt);
    final club = ofAt < 0 ? '' : subject.substring(ofAt);
    final team =
        _opponentTeams[widget.sampleIndex % _opponentTeams.length];
    final timing = _timing[widget.sampleIndex % _timing.length];
    final joiner = CaptionV2CaptionDomain.opponentConnector(
      opponentJoiner: widget.opponentJoiner,
    ).trim();
    final action = _actionFor(selectedId);

    final base = t.bodyStyle.copyWith(
      fontSize: 14,
      height: 20 / 14,
      color: t.textSecondary,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: verbEditorPanelDecoration(t),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('PREVIEW', style: verbEditorPanelTitle(t)),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: variants.isEmpty
                      ? const SizedBox.shrink()
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: _PreviewSegments(
                            tokens: t,
                            variants: variants,
                            selectedId: selectedId,
                            onSelected: (id) =>
                                setState(() => _variantId = id),
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 20),
            child: Text.rich(
              TextSpan(
                style: base,
                children: [
                  TextSpan(text: player, style: TextStyle(color: t.text)),
                  TextSpan(text: club.isEmpty ? ' ' : '$club '),
                  TextSpan(
                    text: action,
                    style: TextStyle(
                      color: t.text,
                      backgroundColor: t.selected,
                    ),
                  ),
                  if (joiner.isNotEmpty) ...[
                    const TextSpan(text: ' '),
                    TextSpan(
                      text: joiner,
                      style: TextStyle(
                        color: t.text,
                        decoration: TextDecoration.underline,
                        decorationStyle: TextDecorationStyle.dashed,
                        decorationColor: t.accentEdge,
                      ),
                    ),
                  ],
                  TextSpan(text: ' $team $timing'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// HTML `.sg`: dark track, `button.on` = accent-soft fill + accent-edge inset.
class _PreviewSegments extends StatelessWidget {
  const _PreviewSegments({
    required this.tokens,
    required this.variants,
    required this.selectedId,
    required this.onSelected,
  });

  final FfTokens tokens;
  final List<_PreviewVariant> variants;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < variants.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            _segment(variants[i]),
          ],
        ],
      ),
    );
  }

  Widget _segment(_PreviewVariant v) {
    final t = tokens;
    final on = v.id == selectedId;
    return Material(
      color: on ? t.selected : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(5),
        side: on ? BorderSide(color: t.accentEdge) : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => onSelected(v.id),
        borderRadius: BorderRadius.circular(5),
        hoverColor: Colors.transparent,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          child: Text(
            v.label,
            softWrap: false,
            style: t.metaStyle.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: on ? t.text : t.textTertiary,
            ),
          ),
        ),
      ),
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
    final baseballSingular = VerbCaptionWording.defaultWording(key);
    final sportSingular = VerbCaptionWording.defaultWording(key, sport: sport);
    final effective = hasSingular
        ? (singular == baseballSingular &&
                !VerbSubOptions.isBaseballSport(sport)
            ? sportSingular
            : singular)
        : sportSingular;
    final fallbackPhrase = effective.isEmpty ? sportSingular : effective;
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
          ? (plural ==
                      VerbCaptionWording.defaultPluralWording(
                        key,
                        fallbackPhrase,
                      ) &&
                  !VerbSubOptions.isBaseballSport(sport)
              ? VerbCaptionWording.defaultPluralWording(
                  key,
                  fallbackPhrase,
                  sport: sport,
                )
              : plural)
          : VerbCaptionWording.defaultPluralWording(
              key,
              fallbackPhrase,
              sport: sport,
            ),
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
