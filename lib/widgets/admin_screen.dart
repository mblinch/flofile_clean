import 'package:dropdown_flutter/custom_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../caption_style/caption_template.dart';
import '../caption_style/sport_verb_categories.dart';
import '../caption_style/verb_caption_wording.dart';
import '../caption_style/wire_iptc_specs.dart';
import '../flo_layout_constants.dart';
import '../theme/auth_ui_constants.dart';
import '../services/admin_service.dart';
import '../services/app_defaults_firestore_service.dart';
import '../services/preferences_service.dart';
import '../caption_style/verb_sub_options.dart';
import 'app_compact_checkbox.dart';
import 'app_styled_dialogs.dart';
import 'verb_edit_plural_field.dart';
import 'verb_edit_sub_options_section.dart';
import 'caption_layout_builder_dialog.dart';

enum _AdminSection { verbs, captionStructures }

/// Admin console for editing app originals (verbs + caption structures).
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  static Future<void> open(BuildContext context) async {
    final isAdmin = await AdminService.isCurrentUserAdmin();
    if (!context.mounted) return;
    if (!isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin access required.')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => const AdminScreen(),
    );
  }

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late PreferencesService _prefs;

  bool _loading = true;
  bool _busy = false;
  String? _error;
  _AdminSection _section = _AdminSection.verbs;

  AppDefaultsCatalog? _catalog;
  final Map<String, Map<String, dynamic>> _verbBundles = {};
  String _verbSport = 'baseball';

  WireStyle _captionWire = WireStyle.getty;
  String _captionSport = 'baseball';
  final Map<WireStyle, CaptionTemplate> _captionDrafts = {};
  final Map<WireStyle, Map<String, String>> _gameIdDrafts = {};
  int _captionBuilderRevision = 0;
  Future<void> Function()? _flushCaptionBuilder;

  static const _sports = AppDefaultsFirestoreService.catalogSports;
  static const _dialogWidth = 920.0;
  static const _dialogHeight = 780.0;
  static const _sidebarWidth = 180.0;
  static const _contentPadding = 24.0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _prefs = await PreferencesService.getInstance();
      await AppDefaultsFirestoreService.loadCacheFromDisk();
      await AppDefaultsFirestoreService.fetchAndCacheAppDefaults(
        forceNetwork: true,
      );
      _catalog = AppDefaultsFirestoreService.getCachedCatalog();
      _verbBundles.clear();
      for (final sport in _sports) {
        _verbBundles[sport] = _sportBundleFromCatalog(sport);
      }
      _captionDrafts.clear();
      _gameIdDrafts.clear();
      for (final w in AppDefaultsFirestoreService.captionWireStyles) {
        final fromCatalog = _catalog?.captionWireDefault(w);
        _captionDrafts[w] = (fromCatalog ??
                AppDefaultsFirestoreService.factoryCaptionForWire(w))
            .copyWith(wireStyle: w);
        final bySport = <String, String>{};
        for (final sport in _sports) {
          final fromMap = _catalog?.gameIdentifierText(w, sport);
          bySport[sport] = fromMap ?? defaultGameIdentifierText(sport);
        }
        _gameIdDrafts[w] = bySport;
      }
      _applyGameIdToCaptionDraft(_captionWire, _captionSport);
      _captionBuilderRevision++;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _sportBundleFromCatalog(String sport) {
    final fromCatalog = _catalog?.sportVerbSettings(sport);
    if (fromCatalog != null && fromCatalog.isNotEmpty) {
      return Map<String, dynamic>.from(fromCatalog);
    }
    return _emptySportBundle(sport);
  }

  Map<String, dynamic> _emptySportBundle(String sport) {
    final factory = SportVerbCategories.forSport(sport);
    return {
      'categoryOrder': [...factory.keys, 'Favorites'],
      'favoriteVerbs': <String>[],
      'deletedVerbs': <String>[],
      'verbOrder': <String, dynamic>{},
      'customVerbs': <Map<String, dynamic>>[],
      'verbOverrides': <String, dynamic>{},
      'customVerbWordings': <String, dynamic>{},
      'favoriteTeams': <String>[],
    };
  }

  Map<String, dynamic> get _activeVerbBundle =>
      _verbBundles[_verbSport] ?? _emptySportBundle(_verbSport);

  void _setActiveVerbBundle(Map<String, dynamic> next) {
    _verbBundles[_verbSport] = next;
  }

  Future<void> _importLocalVerbsForSport() async {
    final sport = _verbSport;
    final bundle = {
      'categoryOrder': await _prefs.getCategoryOrder(sport: sport),
      'favoriteVerbs': (await _prefs.getFavoriteVerbs(sport: sport)).toList(),
      'deletedVerbs': (await _prefs.getDeletedVerbs(sport: sport)).toList(),
      'verbOrder': await _prefs.getVerbOrder(sport: sport),
      'customVerbs': await _prefs.getCustomVerbs(sport: sport),
      'verbOverrides': await _prefs.getVerbOverrides(sport: sport),
      'customVerbWordings': await _prefs.getCustomVerbWordings(sport: sport),
      'favoriteTeams': (await _prefs.getFavoriteTeams(sport: sport)).toList(),
    };
    setState(() => _setActiveVerbBundle(bundle));
  }

  Future<void> _importLocalCaptionForWire() async {
    final local = await _prefs.getCaptionTemplateWireDefault(_captionWire);
    if (!mounted) return;
    if (local == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No local caption structure saved for '
            '${WireIptcSpecs.factoryWireLabel(_captionWire)}.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _captionDrafts[_captionWire] = local.copyWith(wireStyle: _captionWire);
      _stashGameIdFromTemplate(_captionWire, local);
      _applyGameIdToCaptionDraft(_captionWire, _captionSport);
      _captionBuilderRevision++;
    });
  }

  void _stashGameIdFromTemplate(WireStyle wire, CaptionTemplate template) {
    _gameIdDrafts.putIfAbsent(wire, () => {});
    _gameIdDrafts[wire]![_captionSport] = template.gameIdentifierText.trim();
  }

  void _applyGameIdToCaptionDraft(WireStyle wire, String sport) {
    final draft = _captionDrafts[wire];
    if (draft == null) return;
    final text = _gameIdDrafts[wire]?[sport] ?? defaultGameIdentifierText(sport);
    _captionDrafts[wire] = draft.copyWith(
      wireStyle: wire,
      gameIdentifierText: text,
    );
  }

  void _onCaptionDraftChanged(WireStyle wire, CaptionTemplate template) {
    _captionDrafts[wire] = template.copyWith(wireStyle: wire);
    _stashGameIdFromTemplate(wire, template);
  }

  Future<void> _onCaptionSportChanged(String sport) async {
    if (sport == _captionSport) return;
    await _flushCaptionBuilderDrafts();
    if (!mounted) return;
    setState(() {
      _captionSport = sport;
      _applyGameIdToCaptionDraft(_captionWire, sport);
    });
  }

  void _onCaptionWireChanged(WireStyle wire) {
    if (wire == _captionWire) return;
    setState(() => _captionWire = wire);
  }

  Map<String, Map<String, String>> _gameIdDraftsForFirestore() {
    final out = <String, Map<String, String>>{};
    for (final wire in AppDefaultsFirestoreService.captionWireStyles) {
      final bySport = _gameIdDrafts[wire];
      if (bySport != null && bySport.isNotEmpty) {
        out[wire.name] = Map<String, String>.from(bySport);
      }
    }
    return out;
  }

  Future<void> _flushCaptionBuilderDrafts() async {
    await _flushCaptionBuilder?.call();
  }

  Future<void> _publishVerbs({bool allSports = false}) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: allSports ? 'Publish all verb defaults?' : 'Publish verb defaults?',
      message: allSports
          ? 'Updates Firebase app originals for every sport.'
          : 'Updates Firebase app originals for $_verbSport.',
      confirmLabel: 'Publish',
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      if (allSports) {
        await AppDefaultsFirestoreService.publishAllVerbs(_verbBundles);
      } else {
        await AppDefaultsFirestoreService.publishVerbsForSport(
          _verbSport,
          _activeVerbBundle,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            allSports
                ? 'Published verb defaults for all sports.'
                : 'Published verb defaults for $_verbSport.',
          ),
          backgroundColor: kFloTealLight,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Publish failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publishCaptions({bool allWires = false}) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: allWires
          ? 'Publish all caption structures?'
          : 'Publish caption structure?',
      message: allWires
          ? 'Updates every wire caption layout in Firebase app originals.'
          : 'Updates ${WireIptcSpecs.factoryWireLabel(_captionWire)} in Firebase.',
      confirmLabel: 'Publish',
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _flushCaptionBuilderDrafts();
      final wires = allWires
          ? AppDefaultsFirestoreService.captionWireStyles
          : [_captionWire];
      _stashGameIdFromTemplate(
        _captionWire,
        _captionDrafts[_captionWire] ??
            AppDefaultsFirestoreService.factoryCaptionForWire(_captionWire),
      );
      if (allWires) {
        final defaults = <String, Map<String, dynamic>>{};
        for (final wire in wires) {
          final template = _captionDrafts[wire] ??
              AppDefaultsFirestoreService.factoryCaptionForWire(wire);
          defaults[wire.name] = CaptionTemplate.wireMasterJsonFromTemplate(
            template.copyWith(wireStyle: wire),
          );
        }
        await AppDefaultsFirestoreService.publishCaptionWireDefaults(
          defaults,
          gameIdentifierByWireAndSport: _gameIdDraftsForFirestore(),
        );
      } else {
        final template = _captionDrafts[_captionWire] ??
            AppDefaultsFirestoreService.factoryCaptionForWire(_captionWire);
        await AppDefaultsFirestoreService.publishCaptionWireDefault(
          _captionWire,
          template,
          gameIdentifierForSport:
              _gameIdDrafts[_captionWire]?[_captionSport] ??
                  template.gameIdentifierText,
          gameIdentifierSport: _captionSport,
        );
        await AppDefaultsFirestoreService.publishGameIdentifierByWireAndSport(
          _gameIdDraftsForFirestore(),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            allWires
                ? 'Published all caption structures.'
                : 'Published caption structure for '
                    '${WireIptcSpecs.factoryWireLabel(_captionWire)}.',
          ),
          backgroundColor: kFloTealLight,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Publish failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publishCaptionStyleLibrary() async {
    final prefs = await PreferencesService.getInstance();
    final library = await prefs.getCaptionStyleLibrary();
    if (library.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No saved caption styles to publish.'),
        ),
      );
      return;
    }
    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Publish caption style library?',
      message:
          'Pushes ${library.length} saved style(s) to Firebase as the default '
          'starter library for new users. Existing users who have never saved '
          'a custom style will also receive these on next launch.',
      confirmLabel: 'Publish',
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await AppDefaultsFirestoreService.publishCaptionStyleLibrary(
        library.map((e) => e.toJson()).toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Published ${library.length} caption style(s).'),
          backgroundColor: kFloTealLight,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Publish failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<String> _categoryOrder(Map<String, dynamic> bundle, String sport) {
    final raw = bundle['categoryOrder'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => e.toString()).toList();
    }
    return List<String>.from(_emptySportBundle(sport)['categoryOrder'] as List);
  }

  List<_AdminVerbRow> _verbsForCategory(
    String sport,
    String category,
    Map<String, dynamic> bundle,
  ) {
    final factory = SportVerbCategories.forSport(sport);
    final deleted =
        (bundle['deletedVerbs'] as List?)?.map((e) => e.toString()).toSet() ??
            {};
    final overrides = Map<String, dynamic>.from(
      (bundle['verbOverrides'] as Map?) ?? {},
    );
    final custom = ((bundle['customVerbs'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final verbOrder = (bundle['verbOrder'] as Map?) ?? {};
    final ordered = verbOrder[category];
    final base = ordered is List && ordered.isNotEmpty
        ? ordered.map((e) => e.toString()).toList()
        : List<String>.from(factory[category] ?? []);

    final rows = <_AdminVerbRow>[];
    final seen = <String>{};

    void add(String key, {required bool isCustom}) {
      if (key.isEmpty || deleted.contains(key) || !seen.add(key)) return;
      Map<String, dynamic>? meta;
      if (isCustom) {
        for (final c in custom) {
          if (c['label']?.toString() == key) {
            meta = c;
            break;
          }
        }
      } else {
        meta = overrides[key] as Map<String, dynamic>?;
      }
      final label = meta?['label']?.toString() ?? key;
      final phrase = meta?['verbPhrase']?.toString().trim() ?? '';
      final singular = phrase.isNotEmpty
          ? phrase
          : VerbCaptionWording.defaultWording(key);
      final savedPlural = meta?['pluralPhrase']?.toString().trim() ?? '';
      final plural = savedPlural.isNotEmpty
          ? savedPlural
          : VerbCaptionWording.defaultPluralWording(key, singular);
      rows.add(
        _AdminVerbRow(
          key: key,
          isCustom: isCustom,
          label: label,
          verbPhrase: singular,
          pluralPhrase: plural,
          usePluralPhrase: meta?['usePluralPhrase'] as bool? ?? true,
          category: meta?['category']?.toString() ?? category,
          wantsOpponent: meta?['wantsOpponent'] == true,
          omitAgainst: meta?['omitAgainst'] == true,
          keywords: ((meta?['keywords'] as List?) ?? [])
              .map((e) => e.toString())
              .join(', '),
          subOptions: VerbSubOptions.fromJson(
            meta?['subOptions'],
            verbLabel: label,
          ),
        ),
      );
    }

    for (final v in base) {
      final isCustom = custom.any((c) => c['label']?.toString() == v);
      add(v, isCustom: isCustom);
    }
    for (final c in custom) {
      if (c['category']?.toString() == category) {
        add(c['label']?.toString() ?? '', isCustom: true);
      }
    }
    return rows;
  }

  Future<void> _editVerb(_AdminVerbRow row) async {
    final bundle = Map<String, dynamic>.from(_activeVerbBundle);
    final categories = _categoryOrder(bundle, _verbSport);
    final result = await showDialog<_AdminVerbRow>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => _VerbEditDialog(initial: row, categories: categories),
    );
    if (result == null) return;

    if (result.isCustom) {
      final list = ((bundle['customVerbs'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final idx = list.indexWhere((e) => e['label']?.toString() == row.key);
      final map = result.toCustomVerbMap();
      if (idx >= 0) {
        list[idx] = map;
      } else {
        list.add(map);
      }
      bundle['customVerbs'] = list;
    } else {
      final overrides = Map<String, dynamic>.from(
        (bundle['verbOverrides'] as Map?) ?? {},
      );
      overrides[row.key] = result.toOverrideMap();
      bundle['verbOverrides'] = overrides;
    }
    setState(() => _setActiveVerbBundle(bundle));
  }

  Future<void> _addVerb() async {
    final bundle = Map<String, dynamic>.from(_activeVerbBundle);
    final categories = _categoryOrder(bundle, _verbSport);
    final result = await showDialog<_AdminVerbRow>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => _VerbEditDialog(
        initial: _AdminVerbRow(
          key: '',
          isCustom: true,
          label: '',
          verbPhrase: '',
          pluralPhrase: '',
          usePluralPhrase: true,
          category: categories.firstWhere(
            (c) => c != 'Favorites',
            orElse: () => categories.first,
          ),
        ),
        categories: categories,
        isNew: true,
      ),
    );
    if (result == null || result.label.trim().isEmpty) return;
    final list = ((bundle['customVerbs'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    list.add(result.toCustomVerbMap());
    bundle['customVerbs'] = list;
    setState(() => _setActiveVerbBundle(bundle));
  }

  void _deleteVerb(_AdminVerbRow row) {
    final bundle = Map<String, dynamic>.from(_activeVerbBundle);
    if (row.isCustom) {
      final list = ((bundle['customVerbs'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => e['label']?.toString() != row.key)
          .toList();
      bundle['customVerbs'] = list;
    } else {
      final deleted =
          ((bundle['deletedVerbs'] as List?) ?? []).map((e) => e.toString()).toSet();
      deleted.add(row.key);
      bundle['deletedVerbs'] = deleted.toList();
    }
    setState(() => _setActiveVerbBundle(bundle));
  }

  static CustomDropdownDecoration get _dropdownDecoration =>
      CustomDropdownDecoration(
        closedFillColor: Colors.grey.shade50,
        expandedFillColor: Colors.white,
        closedBorder: Border.all(color: AuthUiColors.panelBorder, width: 0.7),
        expandedBorder: Border.all(color: kFloTealLight, width: 1),
        closedBorderRadius: BorderRadius.circular(6),
        expandedBorderRadius: BorderRadius.circular(8),
        hintStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          color: Colors.grey.shade500,
        ),
        headerStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          color: AuthUiColors.brand,
        ),
        listItemStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          color: Colors.grey.shade800,
        ),
        listItemDecoration: const ListItemDecoration(
          selectedColor: kFloTealSelectedFill,
        ),
      );

  static BoxDecoration get _sectionDecoration => BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8F8F8), Color(0xFFFFFFFF)],
        ),
        border: Border.all(color: AuthUiColors.panelBorder, width: 0.7),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 3,
            offset: const Offset(0, 1.5),
          ),
        ],
      );

  static const TextStyle _sectionTitleStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 13,
    fontVariations: [FontVariation('wght', 700)],
    color: Color(0xFF333333),
    letterSpacing: -0.5,
  );

  static const TextStyle _bodyStyle = TextStyle(
    fontFamily: 'Inter',
    fontSize: 11,
    color: AuthUiColors.subtitle,
    height: 1.35,
  );

  Widget _sectionCard({
    required String label,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _sectionDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: _sectionTitleStyle),
              if (trailing != null) ...[const Spacer(), trailing],
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _sidebarTile(_AdminSection section, String label) {
    final selected = _section == section;
    return Material(
      color: selected ? kFloTealSelectedFill : Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : () => setState(() => _section = section),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            border: selected
                ? const Border(
                    left: BorderSide(color: kFloTealLight, width: 2),
                  )
                : null,
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? kFloTealDark : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _captionSportDropdown() {
    return SizedBox(
      width: 160,
      child: DropdownFlutter<String>(
        hintText: 'Sport',
        items: _sports.map((s) => s[0].toUpperCase() + s.substring(1)).toList(),
        initialItem:
            _captionSport[0].toUpperCase() + _captionSport.substring(1),
        closedHeaderPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        expandedHeaderPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        listItemPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: _dropdownDecoration,
        onChanged: _busy
            ? null
            : (label) {
                if (label == null) return;
                _onCaptionSportChanged(label.toLowerCase());
              },
      ),
    );
  }

  Widget _sportDropdown({required void Function(String sport) onChanged}) {
    return SizedBox(
      width: 160,
      child: DropdownFlutter<String>(
        hintText: 'Sport',
        items: _sports.map((s) => s[0].toUpperCase() + s.substring(1)).toList(),
        initialItem: _verbSport[0].toUpperCase() + _verbSport.substring(1),
        closedHeaderPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        expandedHeaderPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        listItemPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: _dropdownDecoration,
        onChanged: (label) {
          if (label == null) return;
          onChanged(label.toLowerCase());
        },
      ),
    );
  }

  Widget _verbRow(_AdminVerbRow v) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.7),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      v.label,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 11,
                        fontVariations: [FontVariation('wght', 600)],
                        color: Colors.black87,
                      ),
                    ),
                    if (v.isCustom) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: kFloTealSelectedFill,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: kFloTealLight, width: 0.5),
                        ),
                        child: const Text(
                          'Custom',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: kFloTealDark,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  v.verbPhrase.isEmpty ? '(default phrase)' : v.verbPhrase,
                  style: _bodyStyle,
                ),
              ],
            ),
          ),
          _iconAction(
            icon: Icons.edit_outlined,
            tooltip: 'Edit verb',
            onPressed: _busy ? null : () => _editVerb(v),
          ),
          _iconAction(
            icon: Icons.delete_outline,
            tooltip: 'Remove verb',
            onPressed: _busy ? null : () => _deleteVerb(v),
          ),
        ],
      ),
    );
  }

  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(icon, size: 16, color: Colors.grey.shade600),
          ),
        ),
      ),
    );
  }

  Widget _buildVerbsContent() {
    final bundle = _activeVerbBundle;
    final categories =
        _categoryOrder(bundle, _verbSport).where((c) => c != 'Favorites');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'App verb originals',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade900,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Edit the verb catalog published to Firebase. Users receive these on restore and first sign-in.',
          style: _bodyStyle,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _sportDropdown(onChanged: (sport) => setState(() => _verbSport = sport)),
            ElevatedGreyButton(
              label: 'Copy from my local settings',
              fontSize: 11,
              onPressed: _busy ? null : _importLocalVerbsForSport,
            ),
            ElevatedGreyButton(
              label: 'Add verb',
              fontSize: 11,
              icon: Icons.add,
              onPressed: _busy ? null : _addVerb,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...categories.map((category) {
          final verbs = _verbsForCategory(_verbSport, category, bundle);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _sectionCard(
              label: category.toUpperCase(),
              trailing: Text(
                '${verbs.length} verbs',
                style: _bodyStyle,
              ),
              children: verbs.isEmpty
                  ? [
                      const Text('No verbs in this category.', style: _bodyStyle),
                    ]
                  : verbs.map(_verbRow).toList(),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildCaptionContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _captionSportDropdown(),
            ElevatedGreyButton(
              label: 'Copy from my local layout',
              fontSize: 11,
              onPressed: _busy ? null : _importLocalCaptionForWire,
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Layout is per wire; game identifier (game ID segment) is per wire and sport. '
          'Switch sport to edit that phrase, then publish.',
          style: _bodyStyle,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: CaptionLayoutBuilderDialog(
            key: ValueKey('admin_caption_$_captionBuilderRevision'),
            embedded: true,
            adminMode: true,
            initialWire: _captionWire,
            initialSport: _captionSport,
            initialTemplate: _captionDrafts[_captionWire],
            wireDraftsSeed: Map<WireStyle, CaptionTemplate>.from(_captionDrafts),
            gameIdDraftsSeed:
                Map<WireStyle, Map<String, String>>.from(_gameIdDrafts),
            onDraftChanged: _onCaptionDraftChanged,
            onWireChanged: _onCaptionWireChanged,
            onRegisterFlush: (flush) => _flushCaptionBuilder = flush,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    final isVerbs = _section == _AdminSection.verbs;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          if (isVerbs) ...[
            ElevatedGreyButton(
              label: _busy ? 'Publishing…' : 'Publish $_verbSport',
              fontSize: 11,
              icon: Icons.cloud_upload_outlined,
              isTealGradient: true,
              onPressed: _busy ? null : () => _publishVerbs(),
            ),
            const SizedBox(width: 8),
            ElevatedGreyButton(
              label: 'Publish all sports',
              fontSize: 11,
              icon: Icons.cloud_upload_outlined,
              onPressed: _busy ? null : () => _publishVerbs(allSports: true),
            ),
          ] else ...[
            ElevatedGreyButton(
              label: _busy
                  ? 'Publishing…'
                  : 'Publish ${WireIptcSpecs.factoryWireLabel(_captionWire)}',
              fontSize: 11,
              icon: Icons.cloud_upload_outlined,
              isTealGradient: true,
              onPressed: _busy ? null : () => _publishCaptions(),
            ),
            const SizedBox(width: 8),
            ElevatedGreyButton(
              label: 'Publish all wires',
              fontSize: 11,
              icon: Icons.cloud_upload_outlined,
              onPressed: _busy ? null : () => _publishCaptions(allWires: true),
            ),
            const SizedBox(width: 8),
            ElevatedGreyButton(
              label: 'Publish style library',
              fontSize: 11,
              icon: Icons.style_outlined,
              onPressed: _busy ? null : _publishCaptionStyleLibrary,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: _dialogWidth,
        height: _dialogHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  gradient: kFloTealGradientHorizontal,
                  border: Border(
                    bottom: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8C547).withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE8C547)),
                      ),
                      child: const Text(
                        'Admin',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFFF3C4),
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'App originals',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    ElevatedGreyButton(
                      label: _loading ? 'Loading…' : 'Reload',
                      fontSize: 10,
                      icon: Icons.cloud_download_outlined,
                      onPressed: _loading || _busy ? null : _bootstrap,
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _busy ? null : () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(4),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close, size: 20, color: Colors.white70),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: kFloTealLight),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 11,
                                  color: Colors.red,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                width: _sidebarWidth,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  border: Border(
                                    right: BorderSide(color: Colors.grey.shade200),
                                  ),
                                ),
                                child: ListView(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  children: [
                                    _sidebarTile(_AdminSection.verbs, 'Verbs'),
                                    Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: Colors.grey.shade300,
                                    ),
                                    _sidebarTile(
                                      _AdminSection.captionStructures,
                                      'Caption Structures',
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: _section == _AdminSection.verbs
                                    ? SingleChildScrollView(
                                        padding: const EdgeInsets.all(
                                            _contentPadding),
                                        child: _buildVerbsContent(),
                                      )
                                    : Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          _contentPadding,
                                          _contentPadding,
                                          _contentPadding,
                                          0,
                                        ),
                                        child: _buildCaptionContent(),
                                      ),
                              ),
                            ],
                          ),
              ),
              if (!_loading && _error == null) _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminVerbRow {
  const _AdminVerbRow({
    required this.key,
    required this.isCustom,
    required this.label,
    required this.verbPhrase,
    required this.pluralPhrase,
    this.usePluralPhrase = true,
    required this.category,
    this.wantsOpponent = false,
    this.omitAgainst = false,
    this.keywords = '',
    this.subOptions = const VerbSubOptions(),
  });

  final String key;
  final bool isCustom;
  final String label;
  final String verbPhrase;
  final String pluralPhrase;
  final bool usePluralPhrase;
  final String category;
  final bool wantsOpponent;
  final bool omitAgainst;
  final String keywords;
  final VerbSubOptions subOptions;

  Map<String, dynamic> toOverrideMap() => {
        'label': label,
        'verbPhrase': verbPhrase,
        'pluralPhrase': pluralPhrase.trim().isEmpty ? null : pluralPhrase.trim(),
        'usePluralPhrase': usePluralPhrase,
        'category': category,
        'wantsOpponent': wantsOpponent,
        'omitAgainst': omitAgainst,
        'isCustom': false,
        if (keywords.trim().isNotEmpty)
          'keywords': keywords
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
        if (subOptions.differsFromDefaults(label))
          'subOptions': subOptions.toJson(),
      };

  Map<String, dynamic> toCustomVerbMap() => {
        ...toOverrideMap(),
        'isCustom': true,
      };
}

class _VerbEditDialog extends StatefulWidget {
  const _VerbEditDialog({
    required this.initial,
    required this.categories,
    this.isNew = false,
  });

  final _AdminVerbRow initial;
  final List<String> categories;
  final bool isNew;

  @override
  State<_VerbEditDialog> createState() => _VerbEditDialogState();
}

class _VerbEditDialogState extends State<_VerbEditDialog> {
  late final TextEditingController _label;
  late final TextEditingController _phrase;
  late final TextEditingController _plural;
  late final TextEditingController _keywords;
  late String _category;
  late bool _wantsOpponent;
  late bool _omitAgainst;
  late bool _usePluralPhrase;
  late VerbSubOptions _subOptions;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: widget.initial.label);
    _phrase = TextEditingController(text: widget.initial.verbPhrase);
    _plural = TextEditingController(text: widget.initial.pluralPhrase);
    _keywords = TextEditingController(text: widget.initial.keywords);
    _category = widget.initial.category;
    _wantsOpponent = widget.initial.wantsOpponent;
    _omitAgainst = widget.initial.omitAgainst;
    _usePluralPhrase = widget.initial.usePluralPhrase;
    _subOptions = widget.initial.subOptions;
  }

  @override
  void dispose() {
    _label.dispose();
    _phrase.dispose();
    _plural.dispose();
    _keywords.dispose();
    super.dispose();
  }

  Widget _captionFlagRow({
    required bool value,
    required String label,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: appDialogCardDecoration(radius: 6),
      child: Row(
        children: [
          AppCompactCheckbox(
            value: value,
            accentColor: kFloTealLight,
            onChanged: onChanged,
          ),
          const SizedBox(width: 8),
          Text(label, style: kAppDialogFieldTextStyle),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cats = widget.categories.where((c) => c != 'Favorites').toList();
    final categoryValue =
        cats.contains(_category) ? _category : (cats.isNotEmpty ? cats.first : _category);
    return Center(
      child: SizedBox(
        width: kVerbEditDialogWidth,
        child: AlertDialog(
          shape: kAppDialogShape,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          title: Text(
            widget.isNew ? 'Add verb' : 'Edit verb',
            style: kAppDialogTitleStyle,
          ),
          content: SizedBox(
            width: kVerbEditDialogWidth - 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: AppDialogLabeledTextField(
                              label: 'Label',
                              controller: _label,
                              bottomGap: 0,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppDialogLabeledDropdown<String>(
                              label: 'Category',
                              value: categoryValue,
                              items: cats
                                  .map((c) => DropdownMenuItem(
                                      value: c, child: Text(c)))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _category = v ?? _category),
                              bottomGap: 0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      AppDialogLabeledTextField(
                        label: 'Singular phrase (1 player)',
                        controller: _phrase,
                        bottomGap: 0,
                        onChanged: (_) {
                          if (_plural.text.trim().isEmpty ||
                              _plural.text == VerbCaptionWording
                                  .defaultPluralWording(
                                widget.initial.key,
                                _phrase.text,
                              )) {
                            _plural.text = VerbCaptionWording
                                .defaultPluralWording(
                              _label.text.trim().isEmpty
                                  ? widget.initial.key
                                  : _label.text.trim(),
                              _phrase.text.trim(),
                            );
                          }
                          setState(() {});
                        },
                      ),
                      VerbEditPluralPhraseField(
                        pluralController: _plural,
                        usePluralPhrase: _usePluralPhrase,
                        onUsePluralChanged: (v) =>
                            setState(() => _usePluralPhrase = v),
                        onPluralChanged: (_) => setState(() {}),
                        bottomGap: 0,
                      ),
                      const SizedBox(height: 4),
                      AppDialogLabeledTextField(
                        label: 'Keywords',
                        controller: _keywords,
                        hintText: 'comma-separated',
                        maxLines: 2,
                        bottomGap: 8,
                      ),
                      Row(
                        children: [
                          Expanded(child: _captionFlagRow(
                            value: _wantsOpponent,
                            label: 'Wants opponent',
                            onChanged: (v) =>
                                setState(() => _wantsOpponent = v),
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: _captionFlagRow(
                            value: _omitAgainst,
                            label: 'Omit "against"',
                            onChanged: (v) => setState(() => _omitAgainst = v),
                          )),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                VerbEditSubOptionsSection(
                  verbLabel: _label.text.trim().isEmpty
                      ? widget.initial.label
                      : _label.text.trim(),
                  value: _subOptions,
                  onChanged: (v) => setState(() => _subOptions = v),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedGreyButton(
              label: 'Cancel',
              fontSize: 11,
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 8),
            ElevatedGreyButton(
              label: 'Save',
              fontSize: 11,
              isPrimary: true,
              onPressed: () {
                Navigator.pop(
                  context,
                  _AdminVerbRow(
                    key: widget.isNew ? _label.text.trim() : widget.initial.key,
                    isCustom: widget.isNew || widget.initial.isCustom,
                    label: _label.text.trim(),
                    verbPhrase: _phrase.text.trim(),
                    pluralPhrase: _plural.text.trim(),
                    usePluralPhrase: _usePluralPhrase,
                    category: _category,
                    wantsOpponent: _wantsOpponent,
                    omitAgainst: _omitAgainst,
                    keywords: _keywords.text.trim(),
                    subOptions: _subOptions,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Tappable admin badge for chrome headers.
class AdminBadgeButton extends StatelessWidget {
  const AdminBadgeButton({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AdminService.isCurrentUserAdminSync()) {
      return child;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => AdminScreen.open(context),
        child: child,
      ),
    );
  }
}
