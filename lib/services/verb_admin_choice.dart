import 'dart:convert';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../caption_style/verb_defaults_bundle.dart';
import '../theme/ff_tokens.dart';
import 'app_defaults_firestore_service.dart';
import 'preferences_service.dart';
import 'verb_user_catalog_service.dart';

/// Asks whether to keep personal verbs after a published default changes.
///
/// The first time a sport is seen, the current admin catalog is remembered
/// and no question is shown. Later loads stay quiet until that published
/// catalog actually changes.
class VerbAdminChoice {
  VerbAdminChoice._();

  static const String _ackPrefix = 'v2:';

  static final Set<String> _asking = <String>{};

  static Future<void> offer({
    required BuildContext context,
    required String sport,
    bool Function()? stillCurrent,
  }) async {
    final normalized = sport.toLowerCase().trim();
    if (normalized.isEmpty) return;
    if (!context.mounted) return;
    if (stillCurrent != null && !stillCurrent()) return;
    if (!_asking.add(normalized)) return;
    try {
      final prefs = await PreferencesService.getInstance();
      final published =
          await AppDefaultsFirestoreService.getCachedSportVerbSettings(
        normalized,
      );
      if (published == null || published.isEmpty) return;
      if (stillCurrent != null && !stillCurrent()) return;

      final publishedComplete = VerbDefaultsBundle.ensureComplete(
        Map<String, dynamic>.from(published),
        normalized,
      );
      final token = '$_ackPrefix${_fingerprint(published)}';
      final snapshot = _snapshot(publishedComplete);
      final acknowledged = await prefs.getVerbAdminAcknowledgement(normalized);
      // Remember the catalog already on disk. Differences that existed before
      // this check are not a new publish.
      if (acknowledged == null || !acknowledged.startsWith(_ackPrefix)) {
        await prefs.saveVerbAdminAcknowledgement(normalized, token);
        await prefs.saveVerbAdminSnapshot(normalized, snapshot);
        return;
      }
      if (acknowledged == token) {
        if (await prefs.getVerbAdminSnapshot(normalized) == null) {
          await prefs.saveVerbAdminSnapshot(normalized, snapshot);
        }
        return;
      }

      final merged = await VerbUserCatalogService.loadMergedBundle(
        prefs: prefs,
        sport: normalized,
      );
      if (json.encode(_slice(publishedComplete)) ==
          json.encode(_slice(merged))) {
        await prefs.saveVerbAdminAcknowledgement(normalized, token);
        await prefs.saveVerbAdminSnapshot(normalized, snapshot);
        return;
      }
      final previous = await prefs.getVerbAdminSnapshot(normalized);
      final changes = previous == null
          ? _changes(published: publishedComplete, personal: merged)
          : _changesSince(
              previous: previous,
              published: publishedComplete,
              personal: merged,
            );
      if (!context.mounted) return;
      if (stillCurrent != null && !stillCurrent()) return;
      if (changes.isEmpty) {
        await prefs.saveVerbAdminAcknowledgement(normalized, token);
        await prefs.saveVerbAdminSnapshot(normalized, snapshot);
        return;
      }
      final label = _sportLabel(normalized);
      final picks = await showDialog<List<_VerbChange>>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (context) => _AdminVerbChoiceDialog(
          sportLabel: label,
          changes: changes,
        ),
      );
      if (picks == null) return;
      await prefs.applyAdminVerbChoices(
        sport: normalized,
        published: publishedComplete,
        choices: [
          for (final change in picks)
            AdminVerbChoice(
              key: change.key,
              added: change.added,
              takeAdmin: change.takeAdmin,
            ),
        ],
      );
      await prefs.saveVerbAdminAcknowledgement(normalized, token);
      await prefs.saveVerbAdminSnapshot(normalized, snapshot);
    } finally {
      _asking.remove(normalized);
    }
  }

  static String _sportLabel(String sport) {
    return sport
        .split(RegExp(r'[\s_]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  static String _fingerprint(Map<String, dynamic> bundle) {
    final slice = _slice(bundle);
    slice.remove('publishedRevision');
    final encoded = json.encode(slice);
    var hash = 0xcbf29ce484222325;
    for (final unit in encoded.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  /// Verb content that personal prefs can hide. Order and favorites stay out.
  static Map<String, Object?> _slice(Map<String, dynamic> bundle) {
    return <String, Object?>{
      'verbOverrides': _canon(bundle['verbOverrides']),
      'customVerbs': _canon(bundle['customVerbs']),
      'deletedVerbs': _canon(bundle['deletedVerbs']),
      'categoryOverrides': _canon(bundle['categoryOverrides']),
    };
  }

  static Map<String, String> _snapshot(Map<String, dynamic> bundle) {
    return {
      for (final entry in _visibleVerbs(bundle).entries)
        entry.key: _verbSignature(entry.value),
    };
  }

  static List<_VerbChange> _changesSince({
    required Map<String, String> previous,
    required Map<String, dynamic> published,
    required Map<String, dynamic> personal,
  }) {
    final publishedVerbs = _visibleVerbs(published);
    final personalVerbs = _visibleVerbs(personal);
    final personalHidden = _deletedKeys(personal);
    final changes = <_VerbChange>[];
    for (final entry in publishedVerbs.entries) {
      final before = previous[entry.key];
      final mine = personalVerbs[entry.key];
      if (before == null) {
        if (personalHidden.contains(entry.key.toLowerCase())) continue;
        changes.add(_VerbChange(
          key: entry.key,
          label: _verbLabel(entry.key, entry.value),
          category: (entry.value['category'] ?? '').toString().trim(),
          added: true,
        ));
        continue;
      }
      if (before == _verbSignature(entry.value)) continue;
      if (mine == null) continue;
      if (_verbSignature(mine) == _verbSignature(entry.value)) continue;
      changes.add(_VerbChange(
        key: entry.key,
        label: _verbLabel(entry.key, entry.value),
        category: (entry.value['category'] ?? '').toString().trim(),
        added: false,
      ));
    }
    changes.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    return changes;
  }

  static List<_VerbChange> _changes({
    required Map<String, dynamic> published,
    required Map<String, dynamic> personal,
  }) {
    final publishedVerbs = _visibleVerbs(published);
    final personalVerbs = _visibleVerbs(personal);
    final personalHidden = _deletedKeys(personal);
    final changes = <_VerbChange>[];
    for (final entry in publishedVerbs.entries) {
      final mine = personalVerbs[entry.key];
      if (mine == null) {
        if (personalHidden.contains(entry.key.toLowerCase())) continue;
        changes.add(_VerbChange(
          key: entry.key,
          label: _verbLabel(entry.key, entry.value),
          category: (entry.value['category'] ?? '').toString().trim(),
          added: true,
        ));
        continue;
      }
      if (_verbSignature(entry.value) == _verbSignature(mine)) continue;
      changes.add(_VerbChange(
        key: entry.key,
        label: _verbLabel(entry.key, entry.value),
        category: (entry.value['category'] ?? '').toString().trim(),
        added: false,
      ));
    }
    changes.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    return changes;
  }

  static Map<String, Map<String, dynamic>> _visibleVerbs(
    Map<String, dynamic> bundle,
  ) {
    final hidden = _deletedKeys(bundle);
    final verbs = <String, Map<String, dynamic>>{};
    final overrides = bundle['verbOverrides'];
    if (overrides is Map) {
      overrides.forEach((key, value) {
        if (value is! Map) return;
        final name = key.toString().trim();
        if (name.isEmpty || hidden.contains(name.toLowerCase())) return;
        verbs[name] = Map<String, dynamic>.from(value);
      });
    }
    for (final raw in ((bundle['customVerbs'] as List?) ?? const [])) {
      if (raw is! Map) continue;
      final name = (raw['key'] ?? raw['label'] ?? '').toString().trim();
      if (name.isEmpty || hidden.contains(name.toLowerCase())) continue;
      verbs[name] = Map<String, dynamic>.from(raw);
    }
    return verbs;
  }

  static Set<String> _deletedKeys(Map<String, dynamic> bundle) {
    return {
      for (final value in ((bundle['deletedVerbs'] as List?) ?? const []))
        value.toString().trim().toLowerCase(),
    }..removeWhere((value) => value.isEmpty);
  }

  static String _verbLabel(String key, Map<String, dynamic> record) {
    final label = (record['label'] ?? '').toString().trim();
    return label.isEmpty ? key : label;
  }

  static String _verbSignature(Map<String, dynamic> record) {
    const fields = [
      'label',
      'category',
      'verbPhrase',
      'pluralPhrase',
      'ingPhrase',
      'keywords',
      'opponentJoiner',
      'wantsOpponent',
      'omitAgainst',
      'usePluralPhrase',
      'withTeammates',
      'subOptions',
      'modifierGroups',
    ];
    return json.encode({
      for (final field in fields) field: _canon(record[field]),
    });
  }

  static Object? _canon(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canon(value[key]),
      };
    }
    if (value is List) {
      final items = <Object?>[for (final item in value) _canon(item)];
      final keyed = items.every(
        (item) => item is Map && (item['key'] ?? '').toString().isNotEmpty,
      );
      if (keyed) {
        items.sort(
          (a, b) => ((a as Map)['key'] ?? '')
              .toString()
              .compareTo(((b as Map)['key'] ?? '').toString()),
        );
      } else if (items.every((item) => item is String || item is num)) {
        items.sort((a, b) => a.toString().compareTo(b.toString()));
      }
      return items;
    }
    if (value is num && value == value.roundToDouble()) {
      return value.toInt();
    }
    return value;
  }
}

class _VerbChange {
  _VerbChange({
    required this.key,
    required this.label,
    required this.category,
    required this.added,
  });

  final String key;
  final String label;
  final String category;
  final bool added;

  /// Added: show the verb. Changed: replace the personal copy.
  bool takeAdmin = false;
}

class _AdminVerbChoiceDialog extends StatefulWidget {
  const _AdminVerbChoiceDialog({
    required this.sportLabel,
    required this.changes,
  });

  final String sportLabel;
  final List<_VerbChange> changes;

  @override
  State<_AdminVerbChoiceDialog> createState() => _AdminVerbChoiceDialogState();
}

class _AdminVerbChoiceDialogState extends State<_AdminVerbChoiceDialog> {
  void _close() => Navigator.pop(context, widget.changes);

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(560.0, screen.width * 0.92);
    final added = widget.changes.where((change) => change.added).length;
    final changed = widget.changes.length - added;
    final summary = [
      if (added > 0) added == 1 ? '1 added' : '$added added',
      if (changed > 0) changed == 1 ? '1 changed' : '$changed changed',
    ].join(' · ');
    return Center(
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width, maxHeight: 560),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
              border: Border.all(color: tokens.divider),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                    decoration: BoxDecoration(
                      color: tokens.bg,
                      border: Border(
                        bottom: BorderSide(color: tokens.divider),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${widget.sportLabel} verbs',
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: tokens.labelStyle.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _close,
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: tokens.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      'Admin updated $summary. For each verb, keep your list or take the admin version.',
                      style: tokens.labelStyle.copyWith(
                        fontSize: 12,
                        height: 1.35,
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      itemCount: widget.changes.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: tokens.divider),
                      itemBuilder: (context, index) {
                        final change = widget.changes[index];
                        final detail = change.category.isEmpty
                            ? (change.added ? 'Added' : 'Changed')
                            : '${change.added ? 'Added' : 'Changed'} · ${change.category}';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      change.label,
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: tokens.labelStyle.copyWith(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      detail,
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: tokens.labelStyle.copyWith(
                                        fontSize: 11,
                                        color: tokens.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              _ChoiceSegments(
                                added: change.added,
                                takeAdmin: change.takeAdmin,
                                onChanged: (takeAdmin) {
                                  setState(() => change.takeAdmin = takeAdmin);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _close,
                        style: TextButton.styleFrom(
                          backgroundColor: tokens.accent,
                          foregroundColor: tokens.inkOnAccent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                        child: Text(
                          'Done',
                          maxLines: 1,
                          softWrap: false,
                          style: tokens.labelStyle.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: tokens.inkOnAccent,
                          ),
                        ),
                      ),
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

class _ChoiceSegments extends StatelessWidget {
  const _ChoiceSegments({
    required this.added,
    required this.takeAdmin,
    required this.onChanged,
  });

  final bool added;
  final bool takeAdmin;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final left = added ? 'Add' : 'Use admin';
    final right = added ? 'Hide' : 'Keep mine';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FfTokens.nocturneBg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: FfTokens.nocturneLn2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Segment(
            label: left,
            selected: takeAdmin,
            onTap: () => onChanged(true),
          ),
          _Segment(
            label: right,
            selected: !takeAdmin,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Material(
      color: selected ? FfTokens.nocturneHv : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: tokens.labelStyle.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? tokens.text : tokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
