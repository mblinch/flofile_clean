import 'dart:convert';

import 'package:flutter/material.dart';

import '../caption_style/verb_defaults_bundle.dart';
import 'app_defaults_firestore_service.dart';
import 'preferences_service.dart';
import 'verb_user_catalog_service.dart';
import '../widgets/app_styled_dialogs.dart';

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
      final acknowledged = await prefs.getVerbAdminAcknowledgement(normalized);
      // Remember the catalog already on disk. Differences that existed before
      // this check are not a new publish.
      if (acknowledged == null || !acknowledged.startsWith(_ackPrefix)) {
        await prefs.saveVerbAdminAcknowledgement(normalized, token);
        return;
      }
      if (acknowledged == token) return;

      final merged = await VerbUserCatalogService.loadMergedBundle(
        prefs: prefs,
        sport: normalized,
      );
      if (json.encode(_slice(publishedComplete)) ==
          json.encode(_slice(merged))) {
        await prefs.saveVerbAdminAcknowledgement(normalized, token);
        return;
      }
      if (!context.mounted) return;
      if (stillCurrent != null && !stillCurrent()) return;

      final label = _sportLabel(normalized);
      final useAdmin = await showAppConfirmDialog(
        context: context,
        title: '$label verbs',
        message:
            'Admin updated the $label verbs. Your saved $label verbs are what the app is using.\n\nKeep your verbs, or switch $label to the admin verbs? Favorites stay either way.',
        cancelLabel: 'Keep my verbs',
        confirmLabel: 'Use admin verbs',
        barrierDismissible: false,
      );
      if (useAdmin == true) {
        await prefs.adoptPublishedVerbs(normalized);
      }
      await prefs.saveVerbAdminAcknowledgement(normalized, token);
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
