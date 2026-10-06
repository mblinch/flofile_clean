import 'package:dropdown_flutter/custom_dropdown.dart';
import 'package:flutter/material.dart';

import '../caption_style/caption_formula_renderer.dart';
import '../caption_style/caption_style_catalog.dart';
import '../caption_style/caption_template.dart';
import '../caption_style/game_info.dart';
import '../services/caption_preview_data_service.dart';
import '../services/preferences_service.dart';
import '../theme/ff_tokens.dart';
import 'app_styled_dialogs.dart';
import 'caption_layout_builder_dialog.dart';
import 'caption_style_dropdown_row.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Caption layout sample line on the startup screen, with style picker and edit.
class StartupCaptionLayoutPreview extends StatefulWidget {
  const StartupCaptionLayoutPreview({
    super.key,
    this.sport,
    this.compact = false,
    this.onWireStyleChanged,
    this.locationOverride,
  });

  final String? sport;
  final bool compact;
  final ValueChanged<WireStyle>? onWireStyleChanged;

  /// When set (e.g. IPTC City / State / Country from the load screen), the
  /// sample caption uses this location instead of the mock LA / USA preview.
  final GameInfo? locationOverride;

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

  /// DropdownFlutter calls [onChanged] when its selection notifier updates
  /// (including programmatic remounts). Ignore those writes during load /
  /// after Done applies a template directly.
  bool _ignoreStyleWrites = false;

  FfTokens get _t =>
      Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(StartupCaptionLayoutPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sport != widget.sport) {
      _load();
      return;
    }
    if (!_sameLocation(oldWidget.locationOverride, widget.locationOverride)) {
      setState(() {});
    }
  }

  bool _sameLocation(GameInfo? a, GameInfo? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return a == b;
    return a.city == b.city &&
        a.region == b.region &&
        a.regionCode == b.regionCode &&
        a.country == b.country &&
        a.countryCode == b.countryCode &&
        a.venue == b.venue;
  }

  GameInfo _effectiveGameInfo(GameInfo base) {
    final o = widget.locationOverride;
    if (o == null) return base;
    final hasLocation = o.city.trim().isNotEmpty ||
        o.region.trim().isNotEmpty ||
        o.country.trim().isNotEmpty ||
        o.countryCode.trim().isNotEmpty;
    if (!hasLocation) return base;
    return base.copyWith(
      city: o.city,
      region: o.region,
      regionCode: o.regionCode,
      country: o.country,
      countryCode: o.countryCode,
      venue: o.venue.trim().isNotEmpty ? o.venue : base.venue,
      gameDate: o.gameDate ?? base.gameDate,
    );
  }

  String _tokenFor(CaptionTemplate template, CaptionStyleCatalog catalog) {
    for (final e in catalog.library) {
      if (e.id == template.id) return 'saved:${e.id}';
    }
    switch (template.wireStyle) {
      case WireStyle.imagn:
        return CaptionStyleCatalog.tokImagn;
      case WireStyle.ap:
        return CaptionStyleCatalog.tokAp;
      case WireStyle.cp:
        return CaptionStyleCatalog.tokCp;
      case WireStyle.custom:
        return CaptionStyleCatalog.tokCustom;
      case WireStyle.getty:
      case WireStyle.gettyInternational:
        return CaptionStyleCatalog.tokGetty;
    }
  }

  Future<void> _load() async {
    _ignoreStyleWrites = true;
    setState(() => _loading = true);
    final prefs = await PreferencesService.getInstance();
    final sport = widget.sport?.toLowerCase() ?? 'baseball';
    final catalog = await CaptionStyleCatalog.load(prefs, sport: widget.sport);
    final preview = CaptionPreviewDataService.load(sport: sport);
    final favoriteToken =
        await prefs.getFavoriteCaptionStyleToken(sport: sport);
    // Use the active template that Done / Save wrote. Do not resolve a favorite
    // over it or write prefs on load (that was wiping edits after Done).
    final template = await prefs.getCaptionTemplate();
    if (!mounted) return;
    setState(() {
      _catalog = catalog;
      _selectedToken = catalog.activeToken;
      _favoriteCaptionStyleToken = favoriteToken;
      _template = template;
      _preview = preview;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ignoreStyleWrites = false;
    });
  }

  Future<void> _applyTemplateLocally(CaptionTemplate template) async {
    _ignoreStyleWrites = true;
    final prefs = await PreferencesService.getInstance();
    final catalog = await CaptionStyleCatalog.load(prefs, sport: widget.sport);
    if (!mounted) return;
    setState(() {
      _catalog = catalog;
      _template = template;
      _selectedToken = _tokenFor(template, catalog);
      _loading = false;
    });
    widget.onWireStyleChanged?.call(template.wireStyle);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ignoreStyleWrites = false;
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
    if (_ignoreStyleWrites) return;
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
    widget.onWireStyleChanged?.call(template.wireStyle);
  }

  CreditSampleAgency _agencyFor(WireStyle wire) {
    switch (wire) {
      case WireStyle.imagn:
        return CreditSampleAgency.imagn;
      case WireStyle.ap:
      case WireStyle.cp:
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
      game: _effectiveGameInfo(snap.gameInfo),
      sampleAgency: _agencyFor(template.wireStyle),
      captionOverride: body,
      sport: widget.sport,
    );
  }

  Future<void> _openEditor() async {
    final applied = await CaptionLayoutBuilderDialog.show(context);
    if (!mounted) return;
    if (applied != null) {
      // Apply what Done just wrote immediately — do not wait on a prefs re-read
      // that can race with dropdown remounts / sport overlay side effects.
      await _applyTemplateLocally(applied);
      return;
    }
    await _load();
  }

  Widget _styleDropdown(CaptionStyleCatalog catalog) {
    final tokens = catalog.options.map((o) => o.token).toList();
    final compact = widget.compact;
    final t = _t;
    final overlayHeight = () {
      final h = tokens.length * (compact ? 30.0 : 36.0);
      if (h < 120) return 120.0;
      if (h > 280) return 280.0;
      return h;
    }();

    // Key must include the active token — DropdownFlutter only honors
    // initialItem on first mount, so without this the header stays on Getty
    // after Done promotes the layout to Custom.
    return DropdownFlutter<String>(
      key: ValueKey(
        'startup_style_${_selectedToken}_${_template?.wireStyle.name}_'
        '${_template?.id}_${tokens.length}',
      ),
      hintText: 'Caption style',
      items: tokens,
      initialItem: _selectedToken != null && tokens.contains(_selectedToken)
          ? _selectedToken
          : null,
      excludeSelected: false,
      hideSelectedFieldWhenExpanded: true,
      overlayHeight: overlayHeight,
      closedHeaderPadding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 5,
      ),
      expandedHeaderPadding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 5,
      ),
      listItemPadding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      headerBuilder: (context, selectedItem, enabled) {
        return Text(
          catalog.labelFor(selectedItem),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 13 : 14,
            fontWeight: FontWeight.w600,
            color: t.text,
          ),
        );
      },
      listItemBuilder: (context, item, isSelected, onItemSelect) {
        final firstCustom = CaptionStyleCatalog.firstCustomTokenIndex(tokens);
        return CaptionStyleDropdownListRow(
          label: catalog.labelFor(item),
          isSelected: isSelected,
          isFavorite: _favoriteCaptionStyleToken == item,
          showSavedIcon: item.startsWith('saved:'),
          showDividerAbove:
              firstCustom >= 0 && tokens.indexOf(item) == firstCustom,
          onSelect: onItemSelect,
          onToggleFavorite: () => _toggleFavoriteCaptionStyle(item),
        );
      },
      decoration: CustomDropdownDecoration(
        closedFillColor: t.sunken,
        expandedFillColor: t.surface,
        closedBorder: Border.all(color: t.divider),
        expandedBorder: Border.all(color: t.divider),
        closedBorderRadius: BorderRadius.circular(FfTokens.radiusChip),
        expandedBorderRadius: BorderRadius.circular(FfTokens.radiusChip),
        hintStyle: t.metaStyle.copyWith(fontSize: 11, color: t.textSecondary),
        listItemDecoration: ListItemDecoration(
          selectedColor: t.selectedFill,
        ),
      ),
      onChanged: _onStyleChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: t.accent,
          ),
        ),
      );
    }

    final catalog = _catalog;
    final template = _template;
    if (catalog == null || template == null) return const SizedBox.shrink();

    final preview = _fullCaptionPreview(template);
    final compact = widget.compact;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (compact)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: _styleDropdown(catalog),
              ),
              const SizedBox(width: 6),
              Material(
                type: MaterialType.transparency,
                borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                child: InkWell(
                  onTap: _openEditor,
                  borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 28),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                      border: Border.all(color: t.accent, width: 1.5),
                    ),
                    child: Text(
                      'Edit',
                      style: t.labelStyle.copyWith(fontSize: 11),
                    ),
                  ),
                ),
              ),
            ],
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 240,
              child: _styleDropdown(catalog),
            ),
          ),
        if (preview != null && preview.isNotEmpty) ...[
          SizedBox(height: compact ? 4 : 10),
          if (!compact)
            Text(
              'PREVIEW',
              style: FfTokens.railLabel.copyWith(
                color: t.text.withValues(alpha: 0.70),
              ),
            ),
          if (!compact) const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 12,
              vertical: compact ? 4 : 10,
            ),
            decoration: BoxDecoration(
              color: t.sunken,
              borderRadius: BorderRadius.circular(FfTokens.radiusChip),
              border: Border.all(color: t.divider),
            ),
            child: SelectionArea(
              child: Text(
                preview,
                maxLines: compact ? 2 : null,
                overflow: compact ? TextOverflow.ellipsis : null,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: compact ? 12 : 13,
                  height: compact ? 1.25 : 1.35,
                  color: t.text,
                ),
              ),
            ),
          ),
        ],
        if (!compact) ...[
          const SizedBox(height: 10),
          AppSecondaryButton(
            label: 'Edit caption layout',
            icon: PhosphorIconsRegular.rows,
            onTap: _openEditor,
          ),
        ],
      ],
    );
  }
}
