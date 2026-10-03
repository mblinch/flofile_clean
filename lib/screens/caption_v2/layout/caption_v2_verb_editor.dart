import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../services/app_defaults_firestore_service.dart';
import '../../../services/preferences_service.dart';
import '../../../services/verb_user_catalog_service.dart';
import '../../../theme/ff_tokens.dart';
import '../../../widgets/admin_verb_authoring_editor.dart';
import '../../../widgets/app_styled_dialogs.dart';
import '../data/caption_v2_controller.dart';

/// Opens the admin-style verb editor for personal (per-user) customization.
///
/// Saves go to [PreferencesService] and sync to the signed-in user's Firebase
/// preferences doc — never to app-default originals.
Future<void> showCaptionV2VerbEditor(
  BuildContext context,
  CaptionV2Controller controller,
  String initialVerb, {
  bool createOnOpen = false,
}) async {
  final prefs = await PreferencesService.getInstance();
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (context) => AppDialogFfStyle(
      enabled: true,
      child: _PersonalVerbEditorDialog(
        controller: controller,
        prefs: prefs,
        initialVerbKey: initialVerb,
        createOnOpen: createOnOpen,
      ),
    ),
  );
  await controller.reloadVerbCatalog();
}

class _PersonalVerbEditorDialog extends StatefulWidget {
  const _PersonalVerbEditorDialog({
    required this.controller,
    required this.prefs,
    required this.initialVerbKey,
    required this.createOnOpen,
  });

  final CaptionV2Controller controller;
  final PreferencesService prefs;
  final String initialVerbKey;
  final bool createOnOpen;

  @override
  State<_PersonalVerbEditorDialog> createState() =>
      _PersonalVerbEditorDialogState();
}

class _PersonalVerbEditorDialogState extends State<_PersonalVerbEditorDialog> {
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
    _sport = widget.controller.sport;
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
      // Keep the live caption session in sync when editing the active sport.
      if (_sport == widget.controller.sport) {
        await widget.controller.reloadVerbCatalog();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final size = MediaQuery.sizeOf(context);
    final width = math.min(1100.0, size.width * 0.94);
    final height = math.min(720.0, size.height * 0.90);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: width,
        height: height,
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
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                child: Row(
                  children: [
                    Text(
                      'Verb editor',
                      style: TextStyle(
                        fontFamily: FfTokens.labelFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Personal',
                      style: t.metaStyle.copyWith(
                        fontSize: 11,
                        color: t.text.withValues(alpha: 0.50),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: t.text.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: t.divider),
              Expanded(child: _buildBody(t)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(FfTokens t) {
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: t.accent,
          ),
        ),
      );
    }
    if (_error != null || _bundle == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error ?? 'Could not load verbs.',
            style: t.metaStyle.copyWith(color: t.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return AdminVerbAuthoringEditor(
      key: ValueKey('personal-verb-editor-$_sport'),
      sport: _sport,
      sports: _sports,
      bundle: _bundle!,
      busy: _busy,
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
}

/// V2-themed popup menu used for verb right-clicks.
Future<T?> showCaptionV2PopupMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
}) {
  final tokens = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
  return showMenu<T>(
    context: context,
    position: position,
    color: tokens.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 12,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(FfTokens.radiusRow),
      side: BorderSide(color: tokens.divider),
    ),
    items: [
      for (final item in items)
        if (item is PopupMenuItem<T>)
          PopupMenuItem<T>(
            value: item.value,
            enabled: item.enabled,
            height: item.height,
            padding: item.padding,
            child: DefaultTextStyle(
              style: tokens.metaStyle.copyWith(
                color: item.enabled ? tokens.text : tokens.textSecondary,
                fontSize: 13,
              ),
              child: item.child!,
            ),
          )
        else
          item,
    ],
  );
}
