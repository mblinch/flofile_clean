import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../caption_style/sport_verb_categories.dart';
import '../caption_style/verb_authoring_model.dart';
import '../caption_style/verb_caption_wording.dart';
import '../caption_style/verb_defaults_bundle.dart';
import '../caption_style/verb_sub_options.dart';
import '../theme/ff_tokens.dart';
import '../utils/default_verb_keywords.dart';
import 'app_compact_checkbox.dart';
import 'app_styled_dialogs.dart';
import 'verb_edit_plural_field.dart';
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
    this.onSaveCurrentVerb,
    this.onPublishCurrentVerb,
  });

  final String sport;
  final List<String> sports;
  final Map<String, dynamic> bundle;
  final bool busy;
  final bool embedded;
  final ValueChanged<String> onSportChanged;
  final ValueChanged<Map<String, dynamic>> onBundleChanged;
  final AdminVerbAction? onSaveCurrentVerb;
  final AdminVerbAction? onPublishCurrentVerb;

  @override
  State<AdminVerbAuthoringEditor> createState() =>
      _AdminVerbAuthoringEditorState();
}

class _AdminVerbAuthoringEditorState extends State<AdminVerbAuthoringEditor> {
  final TextEditingController _find = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  String? _selectedCategory;
  String? _selectedKey;
  String? _selectedGroupId;
  bool _renaming = false;
  int _sampleIndex = 0;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _ensureSelection();
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
    _find.dispose();
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
    final overrides = _overrides;
    final customs = _customs;
    final byKey = <String, _VerbDraft>{};
    final catalogComplete = VerbDefaultsBundle.isComplete(widget.bundle);

    if (catalogComplete) {
      for (final entry in overrides.entries) {
        if (deleted.contains(entry.key)) continue;
        byKey[entry.key] = _VerbDraft.fromRecord(
          key: entry.key,
          category: (entry.value['category'] ??
                  (_categories.isEmpty ? 'Other' : _categories.first))
              .toString(),
          record: entry.value,
          isCustom: false,
          sport: widget.sport,
        );
      }
    } else {
      final factory = SportVerbCategories.forSport(widget.sport);
      for (final entry in factory.entries) {
        for (final key in entry.value) {
          if (key.trim().isEmpty || deleted.contains(key)) continue;
          final override = overrides[key] ?? const <String, dynamic>{};
          byKey[key] = _VerbDraft.fromRecord(
            key: key,
            category: (override['category'] ?? entry.key).toString(),
            record: override,
            isCustom: false,
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
    await action(
      key: verb.key,
      record: verb.toRecord(),
      isCustom: verb.isCustom,
    );
  }

  void _selectCategory(String category) {
    setState(() {
      _selectedCategory = category;
      final verbs =
          _allVerbs.where((verb) => verb.category == category).toList();
      _selectedKey = verbs.isEmpty ? null : verbs.first.key;
      _selectedGroupId = _selectedVerb?.authoring.groups.firstOrNull?.id;
    });
  }

  void _selectVerb(String key) {
    setState(() {
      _selectedKey = key;
      _selectedGroupId = _selectedVerb?.authoring.groups.firstOrNull?.id;
      _renaming = false;
    });
  }

  void _toggleFavorite(_VerbDraft verb) {
    final bundle = _copyBundle();
    final favorites = ((bundle['favoriteVerbs'] as List?) ?? const [])
        .map((value) => value.toString())
        .toSet();
    if (!favorites.remove(verb.key)) favorites.add(verb.key);
    bundle['favoriteVerbs'] = favorites.toList();
    _emit(bundle);
  }

  void _changeCategory(_VerbDraft verb, String category) {
    final updated = verb.copyWith(category: category);
    final bundle = _copyBundle();
    final order = <String, List<String>>{};
    final raw = bundle['verbOrder'];
    if (raw is Map) {
      raw.forEach((key, value) {
        order[key.toString()] =
            value is List ? value.map((item) => item.toString()).toList() : [];
      });
    }
    for (final values in order.values) {
      values.remove(verb.key);
    }
    order.putIfAbsent(category, () => []).add(verb.key);
    bundle['verbOrder'] = order;
    if (verb.isCustom) {
      final list = _customs;
      final index = list.indexWhere(
        (item) => (item['key'] ?? item['label']).toString() == verb.key,
      );
      if (index >= 0) list[index] = updated.toRecord();
      bundle['customVerbs'] = list;
    } else {
      final overrides = _overrides;
      overrides[verb.key] = updated.toRecord();
      bundle['verbOverrides'] = overrides;
    }
    setState(() => _selectedCategory = category);
    _emit(bundle);
  }

  void _rename(_VerbDraft verb, String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty || trimmed == verb.label) return;
    final updated = verb.copyWith(label: trimmed);
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
    if (index >= 0) list[index] = renamed.toRecord();
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
      usePluralPhrase: true,
      ing: '',
      keywords: const [],
      wantsOpponent: true,
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _nameFocus.requestFocus());
  }

  Future<void> _deleteVerb(_VerbDraft verb) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _t.surface,
        title: Text('Delete ${verb.label}?', style: _t.labelStyle),
        content: Text(
          '0 saved captions reference this verb by ID. Saved captions keep '
          'their rendered text and will not be rewritten.',
          style: _t.bodyStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final bundle = _copyBundle();
    if (verb.isCustom) {
      bundle['customVerbs'] = _customs
          .where(
            (item) => (item['key'] ?? item['label']).toString() != verb.key,
          )
          .toList();
    } else {
      final deleted = ((bundle['deletedVerbs'] as List?) ?? const [])
          .map((value) => value.toString())
          .toSet()
        ..add(verb.key);
      bundle['deletedVerbs'] = deleted.toList();
    }
    final favorites = _favorites..remove(verb.key);
    bundle['favoriteVerbs'] = favorites.toList();
    _emit(bundle);
    setState(_ensureSelection);
  }

  void _addCategory() {
    var n = 1;
    var name = 'New category';
    while (_categories.contains(name)) {
      n++;
      name = 'New category $n';
    }
    final bundle = _copyBundle();
    bundle['categoryOrder'] = [..._categories, name];
    final order = Map<String, dynamic>.from(
      (bundle['verbOrder'] as Map?) ?? const {},
    );
    order[name] = <String>[];
    bundle['verbOrder'] = order;
    _emit(bundle);
    setState(() => _selectedCategory = name);
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
    final categories = _categories;
    final all = _allVerbs;
    final favoriteCount =
        all.where((verb) => _favorites.contains(verb.key)).length;
    final verb = _selectedVerb;

    final body = Column(
      children: [
        _Header(
          tokens: t,
          sport: widget.sport,
          sports: widget.sports,
          verbCount: all.length,
          favoriteCount: favoriteCount,
          busy: widget.busy,
          onSportChanged: widget.onSportChanged,
          onNewVerb: _newVerb,
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 96,
                child: _CategoryRail(
                  tokens: t,
                  categories: categories,
                  selected: _selectedCategory,
                  counts: {
                    for (final category in categories)
                      category: all
                          .where((verb) => verb.category == category)
                          .length,
                  },
                  onSelected: _selectCategory,
                  onAdd: _addCategory,
                ),
              ),
              SizedBox(
                width: 212,
                child: _VerbList(
                  tokens: t,
                  findController: _find,
                  verbs: all
                      .where(
                        (item) => item.category == _selectedCategory,
                      )
                      .toList(),
                  favorites: _favorites,
                  selectedKey: _selectedKey,
                  onFindChanged: (_) => setState(() {}),
                  onSelected: _selectVerb,
                ),
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
                        key: ValueKey('${widget.sport}:${verb.key}'),
                        tokens: t,
                        sport: widget.sport,
                        verb: verb,
                        categories: categories,
                        favorite: _favorites.contains(verb.key),
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
                        onCategoryChanged: (value) =>
                            _changeCategory(verb, value),
                        onGroupSelected: (id) =>
                            setState(() => _selectedGroupId = id),
                        onAuthoringChanged: (value) =>
                            _updateAuthoring(verb, value),
                        onDraftChanged: _saveVerb,
                        onDelete: () => _deleteVerb(verb),
                        onShuffle: () => setState(() => _sampleIndex++),
                      ),
              ),
            ],
          ),
        ),
        if (!widget.embedded)
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.divider)),
            ),
            child: Text(
              'One screen: pick the verb on the left, author its phrase and modifiers on the right, read the result at the bottom.',
              style: t.microStyle.copyWith(
                fontSize: 10,
                color: t.text.withValues(alpha: 0.48),
              ),
            ),
          ),
        if (widget.onSaveCurrentVerb != null ||
            widget.onPublishCurrentVerb != null)
          _VerbActionBar(
            tokens: t,
            busy: widget.busy,
            hasSelection: verb != null,
            onSave: widget.onSaveCurrentVerb == null
                ? null
                : () => _runCurrentVerbAction(widget.onSaveCurrentVerb),
            onPublish: widget.onPublishCurrentVerb == null
                ? null
                : () => _runCurrentVerbAction(widget.onPublishCurrentVerb),
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
    required this.verbCount,
    required this.favoriteCount,
    required this.busy,
    required this.onSportChanged,
    required this.onNewVerb,
  });

  final FfTokens tokens;
  final String sport;
  final List<String> sports;
  final int verbCount;
  final int favoriteCount;
  final bool busy;
  final ValueChanged<String> onSportChanged;
  final VoidCallback onNewVerb;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
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
          const SizedBox(width: 12),
          Text(
            '$verbCount verbs · $favoriteCount favourites',
            style: tokens.monoMetaStyle.copyWith(
              fontSize: 10.5,
              color: tokens.text.withValues(alpha: 0.44),
            ),
          ),
          const Spacer(),
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

class _VerbActionBar extends StatelessWidget {
  const _VerbActionBar({
    required this.tokens,
    required this.busy,
    required this.hasSelection,
    required this.onSave,
    required this.onPublish,
  });

  final FfTokens tokens;
  final bool busy;
  final bool hasSelection;
  final VoidCallback? onSave;
  final VoidCallback? onPublish;

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
                : 'Select a verb to save or publish',
            style: tokens.microStyle.copyWith(
              fontSize: 10.5,
              color: tokens.text.withValues(alpha: 0.48),
            ),
          ),
          const Spacer(),
          if (onSave != null) ...[
            ElevatedGreyButton(
              label: 'Save',
              fontSize: 11,
              icon: Icons.save_outlined,
              onPressed: enabled ? onSave : null,
            ),
            const SizedBox(width: 8),
          ],
          if (onPublish != null)
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

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.tokens,
    required this.categories,
    required this.selected,
    required this.counts,
    required this.onSelected,
    required this.onAdd,
  });

  final FfTokens tokens;
  final List<String> categories;
  final String? selected;
  final Map<String, int> counts;
  final ValueChanged<String> onSelected;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(right: BorderSide(color: tokens.divider)),
      ),
      child: Column(
        children: [
          for (final category in categories)
            InkWell(
              onTap: () => onSelected(category),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                color: selected == category
                    ? tokens.accent.withValues(alpha: 0.15)
                    : Colors.transparent,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.metaStyle.copyWith(
                          fontSize: 12,
                          color: tokens.text.withValues(alpha: 0.84),
                        ),
                      ),
                    ),
                    Text(
                      '${counts[category] ?? 0}',
                      style: tokens.monoMetaStyle.copyWith(
                        fontSize: 9.5,
                        color: tokens.text.withValues(alpha: 0.42),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: 'Add category',
            onPressed: onAdd,
            icon: PhosphorIcon(
              PhosphorIconsRegular.plus,
              size: 14,
              color: tokens.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerbList extends StatelessWidget {
  const _VerbList({
    required this.tokens,
    required this.findController,
    required this.verbs,
    required this.favorites,
    required this.selectedKey,
    required this.onFindChanged,
    required this.onSelected,
  });

  final FfTokens tokens;
  final TextEditingController findController;
  final List<_VerbDraft> verbs;
  final Set<String> favorites;
  final String? selectedKey;
  final ValueChanged<String> onFindChanged;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final query = findController.text.trim().toLowerCase();
    final filtered = verbs
        .where(
          (verb) => query.isEmpty || verb.label.toLowerCase().contains(query),
        )
        .toList();
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(right: BorderSide(color: tokens.divider)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(6),
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: findController,
                onChanged: onFindChanged,
                style: tokens.metaStyle.copyWith(color: tokens.text),
                decoration: InputDecoration(
                  hintText: 'Find a verb',
                  hintStyle: tokens.metaStyle,
                  prefixIcon: PhosphorIcon(
                    PhosphorIconsRegular.magnifyingGlass,
                    size: 14,
                    color: tokens.textSecondary,
                  ),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  filled: true,
                  fillColor: tokens.bg,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(color: tokens.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(7),
                    borderSide: BorderSide(color: tokens.accent),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemExtent: 30,
              itemBuilder: (context, index) {
                final verb = filtered[index];
                final selected = verb.key == selectedKey;
                return InkWell(
                  onTap: () => onSelected(verb.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? tokens.accent.withValues(alpha: 0.15)
                          : null,
                      border: selected
                          ? Border.all(
                              color: tokens.accent.withValues(alpha: 0.44),
                            )
                          : null,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 10,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: 4,
                              height: 4,
                              decoration: favorites.contains(verb.key)
                                  ? BoxDecoration(
                                      color: tokens.accent,
                                      shape: BoxShape.circle,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            verb.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.labelStyle.copyWith(
                              fontSize: 13,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (verb.authoring.groups.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.badgeFill,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '${verb.authoring.groups.length}',
                              style: tokens.monoMetaStyle.copyWith(
                                fontSize: 9,
                                color: tokens.text.withValues(alpha: 0.56),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
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
    required this.categories,
    required this.favorite,
    required this.selectedGroupId,
    required this.renaming,
    required this.nameFocus,
    required this.sampleIndex,
    required this.onRenameMode,
    required this.onRename,
    required this.onToggleFavorite,
    required this.onCategoryChanged,
    required this.onGroupSelected,
    required this.onAuthoringChanged,
    required this.onDraftChanged,
    required this.onDelete,
    required this.onShuffle,
  });

  final FfTokens tokens;
  final String sport;
  final _VerbDraft verb;
  final List<String> categories;
  final bool favorite;
  final String? selectedGroupId;
  final bool renaming;
  final FocusNode nameFocus;
  final int sampleIndex;
  final VoidCallback onRenameMode;
  final ValueChanged<String> onRename;
  final VoidCallback onToggleFavorite;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String?> onGroupSelected;
  final ValueChanged<VerbAuthoringData> onAuthoringChanged;
  final ValueChanged<_VerbDraft> onDraftChanged;
  final VoidCallback onDelete;
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
  late VerbAuthoringData _authoring;
  late bool _usePluralPhrase;
  late bool _wantsOpponent;
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
    _usePluralPhrase = verb.usePluralPhrase;
    _wantsOpponent = verb.wantsOpponent;
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
    if (oldWidget.verb.key != widget.verb.key) {
      _loadFromVerb(widget.verb);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _singular.dispose();
    _plural.dispose();
    _ing.dispose();
    _keywords.dispose();
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
    final wording = _singular.text.trim();
    return widget.verb.copyWith(
      singular: wording.isEmpty ? widget.verb.singular : wording,
      plural: _plural.text.trim(),
      usePluralPhrase: _usePluralPhrase,
      ing: _ing.text.trim(),
      keywords: parseVerbKeywordsField(_keywords.text),
      wantsOpponent: _wantsOpponent,
      subOptions: _subOptions,
      authoring: authoring ?? _authoring,
    );
  }

  void _emitDraft() {
    widget.onDraftChanged(_currentDraft());
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
    return Container(
      color: t.bg,
      child: Column(
        children: [
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
                      onSubmitted: widget.onRename,
                      onEditingComplete: () => widget.onRename(_name.text),
                      style: TextStyle(
                        fontFamily: FfTokens.labelFamily,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                        color: t.text,
                      ),
                    ),
                  )
                else ...[
                  Text(
                    widget.verb.label,
                    style: TextStyle(
                      fontFamily: FfTokens.labelFamily,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
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
                const Spacer(),
                _FavoriteToggle(
                  tokens: t,
                  value: widget.favorite,
                  onTap: widget.onToggleFavorite,
                ),
                const SizedBox(width: 8),
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: t.divider),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: widget.categories.contains(widget.verb.category)
                          ? widget.verb.category
                          : widget.categories.firstOrNull,
                      dropdownColor: t.surface,
                      style: t.metaStyle.copyWith(
                        fontSize: 11.5,
                        color: t.text.withValues(alpha: 0.72),
                      ),
                      items: widget.categories
                          .map(
                            (category) => DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => value == null
                          ? null
                          : widget.onCategoryChanged(value),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: ListView(
                children: [
                  _SectionHeading(
                    tokens: t,
                    label: 'CAPTION WORDING',
                    trailing: 'What appears in the caption after the player',
                  ),
                  const SizedBox(height: 6),
                  AppDialogLabeledField(
                    label: 'Wording',
                    bottomGap: 10,
                    child: AppDialogControlShell(
                      child: TextField(
                        controller: _singular,
                        style: appDialogFieldTextStyleOf(context),
                        onChanged: _onWordingChanged,
                        decoration: appDialogBareFieldDecoration(
                          hintText: 'e.g., hits a single',
                        ),
                      ),
                    ),
                  ),
                  VerbEditPluralPhraseField(
                    pluralController: _plural,
                    usePluralPhrase: _usePluralPhrase,
                    onUsePluralChanged: (value) {
                      setState(() => _usePluralPhrase = value);
                      _emitDraft();
                    },
                    onPluralChanged: (_) => _emitDraft(),
                    bottomGap: 10,
                  ),
                  AppDialogLabeledField(
                    label: '-ing form',
                    bottomGap: 12,
                    child: AppDialogControlShell(
                      child: TextField(
                        controller: _ing,
                        style: appDialogFieldTextStyleOf(context),
                        onChanged: (_) => _emitDraft(),
                        decoration: appDialogBareFieldDecoration(
                          hintText: 'e.g., hitting a single',
                        ),
                      ),
                    ),
                  ),
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
                    phrase: _singular.text.trim().isEmpty
                        ? widget.verb.singular
                        : _singular.text.trim(),
                    sampleIndex: widget.sampleIndex,
                    wantsOpponent: _wantsOpponent,
                  ),
                  const SizedBox(height: 16),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: t.divider),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      title: Text(
                        'Advanced',
                        style: t.metaStyle.copyWith(
                          fontSize: 11,
                          letterSpacing: 0.6,
                          color: t.text.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Keywords, opponent, RBI & reactions',
                        style: t.metaStyle.copyWith(
                          fontSize: 10.5,
                          color: t.text.withValues(alpha: 0.40),
                        ),
                      ),
                      children: [
                        AppDialogLabeledField(
                          label: 'Keywords',
                          bottomGap: 8,
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
                        Row(
                          children: [
                            AppCompactCheckbox(
                              value: _wantsOpponent,
                              accentColor: t.accent,
                              onChanged: (value) {
                                setState(() => _wantsOpponent = value);
                                _emitDraft();
                              },
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Include opponent in caption',
                              style: t.metaStyle.copyWith(color: t.text),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        VerbEditSubOptionsSection(
                          verbLabel: widget.verb.key,
                          sport: widget.sport,
                          value: _subOptions,
                          onChanged: _setSubOptions,
                          showBorder: false,
                        ),
                      ],
                    ),
                  ),
                  if (widget.verb.isCustom) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: widget.onDelete,
                        icon: const PhosphorIcon(
                          PhosphorIconsRegular.trash,
                          size: 14,
                          color: Color(0xFFFF6B6B),
                        ),
                        label: Text(
                          'Delete custom verb',
                          style: t.metaStyle.copyWith(
                            color: const Color(0xFFFF6B6B),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _FavoriteToggle extends StatelessWidget {
  const _FavoriteToggle({
    required this.tokens,
    required this.value,
    required this.onTap,
  });

  final FfTokens tokens;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: value
              ? tokens.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          border: Border.all(
            color:
                value ? tokens.accent.withValues(alpha: 0.44) : tokens.divider,
          ),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: value ? tokens.accent : tokens.textSecondary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Favourite',
              style: tokens.metaStyle.copyWith(
                fontSize: 11.5,
                color: value ? tokens.accent : tokens.textSecondary,
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
      height: 20,
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: FfTokens.labelFamily,
              fontWeight: FontWeight.w600,
              fontSize: 8.5,
              letterSpacing: 1.36,
              color: tokens.text.withValues(alpha: 0.44),
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

class _ResolvedPreview extends StatelessWidget {
  const _ResolvedPreview({
    required this.tokens,
    required this.phrase,
    required this.sampleIndex,
    this.wantsOpponent = true,
  });

  final FfTokens tokens;
  final String phrase;
  final int sampleIndex;
  final bool wantsOpponent;

  static const _players = [
    'Heater Ace #24 of the Los Angeles Boulevards',
    'Han Xu #21 of the New York Liberty',
    'Maya North #7 of the Toronto Arrows',
  ];
  static const _tails = [
    'against the New York Avenues during the third inning',
    'against the Chicago Comets during the fifth inning',
    'against the Montreal Royals during the seventh inning',
  ];

  @override
  Widget build(BuildContext context) {
    final player = _players[sampleIndex % _players.length];
    final tail = wantsOpponent ? _tails[sampleIndex % _tails.length] : 'during the third inning';
    final resolved = phrase.trim().isEmpty ? '…' : phrase.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.divider),
      ),
      child: Text.rich(
        TextSpan(
          style: tokens.bodyStyle.copyWith(
            fontSize: 13.5,
            color: tokens.text.withValues(alpha: 0.82),
          ),
          children: [
            TextSpan(text: '$player '),
            TextSpan(
              text: resolved,
              style: TextStyle(
                color: tokens.text,
                backgroundColor: tokens.accent.withValues(alpha: 0.20),
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: ' $tail'),
          ],
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
    required this.usePluralPhrase,
    required this.ing,
    required this.keywords,
    required this.wantsOpponent,
    required this.subOptions,
    required this.isCustom,
    required this.authoring,
    required this.record,
  });

  final String key;
  final String label;
  final String category;
  final String singular;
  final String plural;
  final bool usePluralPhrase;
  final String ing;
  final List<String> keywords;
  final bool wantsOpponent;
  final VerbSubOptions subOptions;
  final bool isCustom;
  final VerbAuthoringData authoring;
  final Map<String, dynamic> record;

  factory _VerbDraft.fromRecord({
    required String key,
    required String category,
    required Map<String, dynamic> record,
    required bool isCustom,
    required String sport,
  }) {
    final label = (record['label'] ?? key).toString();
    final singular = (record['verbPhrase'] ?? '').toString().trim();
    final effective =
        singular.isEmpty ? VerbCaptionWording.defaultWording(key) : singular;
    final plural = (record['pluralPhrase'] ?? '').toString().trim();
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
      plural: plural.isEmpty
          ? VerbCaptionWording.defaultPluralWording(key, effective)
          : plural,
      usePluralPhrase: record['usePluralPhrase'] != false,
      ing: ing.isEmpty
          ? VerbCaptionWording.defaultIngWording(key, effective)
          : ing,
      keywords: keywords,
      wantsOpponent: record['wantsOpponent'] is bool
          ? record['wantsOpponent'] as bool
          : key != 'Post Game Win' && key != 'Post Game Loss',
      subOptions: subOptions,
      isCustom: isCustom,
      authoring: VerbAuthoringData.fromRecord(
        record,
        verbLabel: key,
        sport: sport,
        fallbackPhrase: effective,
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
    bool? usePluralPhrase,
    String? ing,
    List<String>? keywords,
    bool? wantsOpponent,
    VerbSubOptions? subOptions,
    VerbAuthoringData? authoring,
  }) {
    return _VerbDraft(
      key: key ?? this.key,
      label: label ?? this.label,
      category: category ?? this.category,
      singular: singular ?? this.singular,
      plural: plural ?? this.plural,
      usePluralPhrase: usePluralPhrase ?? this.usePluralPhrase,
      ing: ing ?? this.ing,
      keywords: keywords ?? this.keywords,
      wantsOpponent: wantsOpponent ?? this.wantsOpponent,
      subOptions: subOptions ?? this.subOptions,
      isCustom: isCustom,
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
        'usePluralPhrase': usePluralPhrase,
        'ingPhrase': ing,
        'keywords': keywords,
        'wantsOpponent': wantsOpponent,
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
