import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_defaults_firestore_service.dart';
import '../services/preferences_service.dart';
import '../services/verb_user_catalog_service.dart';
import '../theme/ff_tokens.dart';
import 'admin_verb_authoring_editor.dart';
import 'app_styled_dialogs.dart';

/// Personal (per-user) verb editor — the single body used by Preferences and
/// caption V2 right-click → Preferences → Verbs.
///
/// Saves go to [PreferencesService] / the signed-in user's Firebase prefs doc,
/// never to app-default originals.
class PersonalVerbEditor extends StatefulWidget {
  const PersonalVerbEditor({
    super.key,
    required this.prefs,
    this.initialSport,
    this.initialVerbKey,
    this.createOnOpen = false,
    this.onCatalogChanged,
  });

  final PreferencesService prefs;
  final String? initialSport;
  final String? initialVerbKey;
  final bool createOnOpen;

  /// Fired after a successful persist (e.g. reload a live caption session).
  final Future<void> Function(String sport)? onCatalogChanged;

  @override
  State<PersonalVerbEditor> createState() => _PersonalVerbEditorState();
}

class _PersonalVerbEditorState extends State<PersonalVerbEditor> {
  static const _sports = AppDefaultsFirestoreService.catalogSports;

  late String _sport;
  Map<String, dynamic>? _bundle;
  bool _busy = false;
  bool _loading = true;
  String? _error;
  bool _openedCreate = false;

  @override
  void initState() {
    super.initState();
    final sport = (widget.initialSport ?? '').trim();
    _sport = sport.isEmpty ? 'baseball' : sport;
    unawaited(_loadSport(_sport));
  }

  Future<void> _loadSport(String sport) async {
    setState(() {
      _loading = true;
      _error = null;
      _sport = sport;
    });
    try {
      final bundle = await VerbUserCatalogService.loadMergedBundle(
        prefs: widget.prefs,
        sport: sport,
      );
      if (!mounted) return;
      setState(() {
        _bundle = bundle;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _onBundleChanged(Map<String, dynamic> next) async {
    setState(() {
      _bundle = next;
      _busy = true;
    });
    try {
      await VerbUserCatalogService.persistBundle(
        prefs: widget.prefs,
        sport: _sport,
        bundle: next,
      );
      final notify = widget.onCatalogChanged;
      if (notify != null) await notify(_sport);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;

    final Widget body;
    if (_loading && _bundle == null) {
      body = Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: t.accent,
          ),
        ),
      );
    } else if (_error != null || _bundle == null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error ?? 'Could not load verbs.',
            style: t.metaStyle.copyWith(color: t.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else {
      body = AdminVerbAuthoringEditor(
        key: ValueKey('personal-verb-editor-$_sport'),
        sport: _sport,
        sports: _sports,
        bundle: _bundle!,
        busy: _busy || _loading,
        embedded: true,
        personalMode: true,
        initialVerbKey: widget.initialVerbKey,
        createOnOpen: widget.createOnOpen && !_openedCreate,
        onSportChanged: _loadSport,
        onBundleChanged: (next) {
          if (widget.createOnOpen) _openedCreate = true;
          unawaited(_onBundleChanged(next));
        },
      );
    }

    // Shared field chrome uses FF tokens only under this flag (dark fills).
    return AppDialogFfStyle(enabled: true, child: body);
  }
}
