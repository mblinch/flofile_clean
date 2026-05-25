import 'package:dropdown_flutter/custom_dropdown.dart';
import 'package:flutter/material.dart';

import '../caption_style/caption_formula_renderer.dart';
import '../caption_style/caption_style_catalog.dart';
import '../caption_style/caption_template.dart';
import '../services/caption_preview_data_service.dart';
import '../services/preferences_service.dart';
import 'app_styled_dialogs.dart';
import 'caption_layout_builder_dialog.dart';
import 'caption_style_dropdown_row.dart';

/// Caption layout sample line on the startup screen, with style picker and edit.
class StartupCaptionLayoutPreview extends StatefulWidget {
  const StartupCaptionLayoutPreview({super.key, this.sport});

  final String? sport;

  @override
  State<StartupCaptionLayoutPreview> createState() =>
      _StartupCaptionLayoutPreviewState();
}

class _StartupCaptionLayoutPreviewState
    extends State<StartupCaptionLayoutPreview> {
  final int _previewSeed = DateTime.now().millisecondsSinceEpoch;

  CaptionStyleCatalog? _catalog;
  CaptionTemplate? _template;
  String? _selectedToken;
  String? _favoriteCaptionStyleToken;
  CaptionPreviewSnapshot? _preview;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(StartupCaptionLayoutPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sport != widget.sport) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final prefs = await PreferencesService.getInstance();
    final sport = widget.sport?.toLowerCase() ?? 'baseball';
    final catalog = await CaptionStyleCatalog.load(prefs, sport: widget.sport);
    final preview = CaptionPreviewDataService.load(sport: sport);
    final favoriteToken =
        await prefs.getFavoriteCaptionStyleToken(sport: sport);
    var selectedToken = catalog.activeToken;
    if (favoriteToken != null &&
        catalog.options.any((o) => o.token == favoriteToken)) {
      selectedToken = favoriteToken;
    }
    final template = catalog.resolve(selectedToken);
    await prefs.saveCaptionTemplate(template.normalizePerOccurrenceLists());
    if (!mounted) return;
    setState(() {
      _catalog = catalog;
      _selectedToken = selectedToken;
      _favoriteCaptionStyleToken = favoriteToken;
      _template = template;
      _preview = preview;
      _loading = false;
    });
  }

  Future<void> _toggleFavoriteCaptionStyle(String token) async {
    final sport = widget.sport?.toLowerCase() ?? 'baseball';
    final prefs = await PreferencesService.getInstance();
    setState(() {
      if (_favoriteCaptionStyleToken == token) {
        _favoriteCaptionStyleToken = null;
      } else {
        _favoriteCaptionStyleToken = token;
      }
    });
    await prefs.saveFavoriteCaptionStyleToken(
      _favoriteCaptionStyleToken,
      sport: sport,
    );
  }

  Future<void> _onStyleChanged(String? token) async {
    if (token == null || _catalog == null || token == _selectedToken) return;
    final prefs = await PreferencesService.getInstance();
    final template = _catalog!
        .resolve(token, refForCustom: _template)
        .normalizePerOccurrenceLists();
    await prefs.saveCaptionTemplate(template);
    if (!mounted) return;
    setState(() {
      _selectedToken = token;
      _template = template;
    });
  }

  CreditSampleAgency _agencyFor(WireStyle wire) {
    switch (wire) {
      case WireStyle.imagn:
        return CreditSampleAgency.imagn;
      case WireStyle.ap:
        return CreditSampleAgency.ap;
      case WireStyle.getty:
      case WireStyle.gettyInternational:
      case WireStyle.custom:
        return CreditSampleAgency.gettyImages;
    }
  }

  String? _fullCaptionPreview(CaptionTemplate template) {
    final snap = _preview;
    if (snap == null) return null;

    final body = CaptionFormulaRenderer.randomSinglePlayerCaption(
      template,
      seed: _previewSeed,
      sport: widget.sport,
      previewPlayers: snap.players,
      previewActions: snap.actions,
    );
    return CaptionFormulaRenderer.render(
      template: template,
      game: snap.gameInfo,
      sampleAgency: _agencyFor(template.wireStyle),
      captionOverride: body,
    );
  }

  Future<void> _openEditor() async {
    await CaptionLayoutBuilderDialog.show(context);
    if (!mounted) return;
    await _load();
  }

  Widget _styleDropdown(CaptionStyleCatalog catalog) {
    final tokens = catalog.options.map((o) => o.token).toList();
    final overlayHeight = () {
      final h = tokens.length * 36.0;
      if (h < 120) return 120.0;
      if (h > 280) return 280.0;
      return h;
    }();

    return DropdownFlutter<String>(
      key: ValueKey(
        'startup_style_${tokens.length}_${catalog.library.map((e) => e.id).join()}',
      ),
      hintText: 'Caption style',
      items: tokens,
      initialItem: _selectedToken,
      excludeSelected: false,
      hideSelectedFieldWhenExpanded: true,
      overlayHeight: overlayHeight,
      closedHeaderPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      expandedHeaderPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      listItemPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      headerBuilder: (context, selectedItem, enabled) {
        return Text(
          catalog.labelFor(selectedItem),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade900,
          ),
        );
      },
      listItemBuilder: (context, item, isSelected, onItemSelect) {
        return CaptionStyleDropdownListRow(
          label: catalog.labelFor(item),
          isSelected: isSelected,
          isFavorite: _favoriteCaptionStyleToken == item,
          showSavedIcon: item.startsWith('saved:'),
          onSelect: onItemSelect,
          onToggleFavorite: () => _toggleFavoriteCaptionStyle(item),
        );
      },
      decoration: CustomDropdownDecoration(
        closedFillColor: Colors.white,
        expandedFillColor: Colors.white,
        closedBorder: Border.all(color: Colors.grey.shade300),
        expandedBorder: Border.all(color: Colors.grey.shade300),
        closedBorderRadius: BorderRadius.circular(4),
        expandedBorderRadius: BorderRadius.circular(4),
        hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        listItemDecoration: ListItemDecoration(
          selectedColor: Colors.grey.shade100,
        ),
      ),
      onChanged: _onStyleChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final catalog = _catalog;
    final template = _template;
    if (catalog == null || template == null) return const SizedBox.shrink();

    final preview = _fullCaptionPreview(template);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _styleDropdown(catalog),
        if (preview != null && preview.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'PREVIEW',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
              border: Border(
                left: BorderSide(
                  color: Colors.grey.shade400,
                  width: 3,
                ),
              ),
            ),
            child: SelectionArea(
              child: Text(
                preview,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.45,
                  color: Colors.grey.shade800,
                  fontFamily: 'Menlo',
                  fontFamilyFallback: const [
                    'Consolas',
                    'Courier New',
                    'monospace',
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        AppSecondaryButton(
          label: 'Edit caption layout',
          icon: Icons.view_agenda_outlined,
          onTap: _openEditor,
        ),
      ],
    );
  }
}
