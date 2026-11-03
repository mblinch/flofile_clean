import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../caption_style/caption_template.dart';
import '../../../caption_style/wire_iptc_specs.dart';
import '../../../services/app_defaults_firestore_service.dart';
import '../../../services/iptc_template_apply_service.dart';
import '../../../theme/ff_tokens.dart';
import '../../../widgets/teal_action_button.dart';

const Color _warn = Color(0xFFE8B547);
const Color _warnLine = Color(0x73E8B547);

/// Session colors for the start-menu template. Workspace colors match captioning.
class IptcEditorColors {
  const IptcEditorColors.session() : workspace = false;
  const IptcEditorColors.workspace() : workspace = true;

  final bool workspace;

  Color get group => workspace ? FfTokens.nocturneEl : FfTokens.sessionBg;
  Color get field => workspace ? FfTokens.nocturneSunken : FfTokens.sessionEl;
  Color get hover => workspace ? FfTokens.nocturneHv : FfTokens.sessionHv;
  Color get line => workspace ? FfTokens.nocturneLn : FfTokens.sessionLn;
  Color get tx => workspace ? FfTokens.nocturneTx : FfTokens.sessionTx;
  Color get t2 => workspace ? FfTokens.nocturneT2 : FfTokens.sessionT2;
  Color get t3 => workspace ? FfTokens.nocturneT3 : FfTokens.sessionT3;
  Color get focus => workspace ? FfTokens.nocturneAc : FfTokens.sessionOn;
  Color get ok => FfTokens.sessionOk;
}

class IptcEditorPalette extends InheritedWidget {
  const IptcEditorPalette({super.key, required this.colors, required super.child});

  final IptcEditorColors colors;

  static IptcEditorColors of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<IptcEditorPalette>()
            ?.colors ??
        const IptcEditorColors.session();
  }

  @override
  bool updateShouldNotify(IptcEditorPalette oldWidget) =>
      colors.workspace != oldWidget.colors.workspace;
}

/// Layout-only IPTC template editor. Values stay in the parent dialog.
class IptcTemplateEditor extends StatelessWidget {
  const IptcTemplateEditor({
    super.key,
    required this.wire,
    required this.templates,
    required this.selectedTemplateId,
    required this.values,
    required this.foundInFilesKeys,
    required this.revision,
    required this.fieldsEnabled,
    required this.onTemplateSelected,
    required this.onValueChanged,
    required this.onLoadTemplate,
    required this.onClearTemplate,
    required this.onSaveTemplate,
    required this.onCancel,
    required this.onDone,
    this.loadEnabled = true,
    this.clearEnabled = true,
    this.loadingTemplate = false,
    this.title = 'IPTC template',
    this.subtitle,
    this.doneLabel = 'Done',
    this.showTemplateControls = true,
    this.workspacePalette = false,
    this.leading,
    this.applyMode,
    this.onApplyModeChanged,
  });

  final WireStyle wire;
  final List<IptcTemplateCatalogEntry> templates;
  final String selectedTemplateId;
  final Map<String, String> values;
  final Set<String> foundInFilesKeys;
  final int revision;
  final bool fieldsEnabled;
  final ValueChanged<IptcTemplateCatalogEntry> onTemplateSelected;
  final void Function(String storageKey, String value) onValueChanged;
  final VoidCallback? onLoadTemplate;
  final VoidCallback? onClearTemplate;
  final VoidCallback? onSaveTemplate;
  final VoidCallback onCancel;
  final VoidCallback onDone;
  final bool loadEnabled;
  final bool clearEnabled;
  final bool loadingTemplate;
  final String title;
  final String? subtitle;
  final String doneLabel;

  /// Template picker, load, and save. Off when editing one photo's IPTC.
  final bool showTemplateControls;

  /// Nocturne caption-workspace colors. The start menu keeps the session palette.
  final bool workspacePalette;

  /// Optional left column, used for the photo in Edit IPTC.
  final Widget? leading;

  /// When set, shows Apply on load / save / FTP under the header.
  final IptcApplyMode? applyMode;
  final ValueChanged<IptcApplyMode>? onApplyModeChanged;

  static const _monoKeys = {
    'MEID',
    'Object Name',
    'Category',
    'Supp Cat 1',
    'Supp Cat 2',
    'Supp Cat 3',
    'Country Code',
  };

  @override
  Widget build(BuildContext context) {
    final specs = {
      for (final spec in WireIptcSpecs.fieldsForPanel(wire)) spec.label: spec,
    };
    final colors = workspacePalette
        ? const IptcEditorColors.workspace()
        : const IptcEditorColors.session();
    return IptcEditorPalette(
      colors: colors,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Match IPTC Editor v2.html breakpoints.
          final h = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 800.0;
          final w = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 1200.0;
          final compact = h < 820 || w < 1100;
          final narrow = w < 1100;
          final fieldH = narrow ? 36.0 : 32.0;
          final gap = compact ? 8.0 : 10.0;

          final story = _group(
            colors: colors,
            icon: PhosphorIconsRegular.article,
            title: 'Story',
            compact: compact,
            children: [
              _text(specs, 'Headline', narrow, fieldH),
              _text(specs, 'Personality', narrow, fieldH),
              _text(specs, 'Keywords', narrow, fieldH),
              _text(
                specs,
                'Special Instructions',
                narrow,
                fieldH,
                display: 'Instructions',
              ),
            ],
          );
          final credit = _group(
            colors: colors,
            icon: PhosphorIconsRegular.user,
            title: 'Credit',
            compact: compact,
            children: [
              _text(specs, 'Creator', narrow, fieldH),
              _text(specs, 'Job Title', narrow, fieldH, display: 'Job title'),
              _text(
                specs,
                'Description Writers',
                narrow,
                fieldH,
                display: 'Writers',
              ),
              _text(specs, 'Credit', narrow, fieldH),
              _text(specs, 'Source', narrow, fieldH),
              _text(specs, 'Copyright', narrow, fieldH),
            ],
          );
          final location = _group(
            colors: colors,
            icon: PhosphorIconsRegular.mapPin,
            title: 'Location',
            compact: compact,
            children: [
              _text(specs, 'Location', narrow, fieldH, display: 'Venue'),
              _text(specs, 'City', narrow, fieldH),
              _text(
                specs,
                'Province/State',
                narrow,
                fieldH,
                display: 'State/Province',
              ),
              _country(specs, narrow, fieldH),
            ],
          );
          final filing = _group(
            colors: colors,
            icon: PhosphorIconsRegular.folderSimple,
            title: 'Filing',
            compact: compact,
            children: [
              _text(specs, 'MEID', narrow, fieldH),
              _text(
                specs,
                'Object Name',
                narrow,
                fieldH,
                display: 'Object name',
              ),
              _text(specs, 'Category', narrow, fieldH),
              _supp(specs, narrow, fieldH, colors),
              _urgency(specs, narrow, fieldH),
            ],
          );

          // Always 2×2: Story | Credit / Location | Filing.
          final grid = Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: story),
                  SizedBox(width: gap),
                  Expanded(child: credit),
                ],
              ),
              SizedBox(height: gap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: location),
                  SizedBox(width: gap),
                  Expanded(child: filing),
                ],
              ),
            ],
          );

          final body = ListView(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 16,
              compact ? 8 : 14,
              compact ? 12 : 16,
              compact ? 8 : 16,
            ),
            children: [
              if (applyMode != null) ...[
                _ApplyWhenBar(
                  mode: applyMode!,
                  onChanged: onApplyModeChanged,
                  compact: compact,
                ),
                SizedBox(height: compact ? 6 : 10),
              ],
              _CaptionOmittedNote(compact: compact),
              SizedBox(height: compact ? 6 : 10),
              grid,
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                title: title,
                subtitle: subtitle,
                showTemplateControls: showTemplateControls,
                templates: templates,
                selectedTemplateId: selectedTemplateId,
                onTemplateSelected: onTemplateSelected,
                onLoad: loadEnabled ? onLoadTemplate : null,
                onClear: clearEnabled ? onClearTemplate : null,
                onSave: fieldsEnabled ? onSaveTemplate : null,
                loadingTemplate: loadingTemplate,
                onClose: onCancel,
                compact: compact,
              ),
              Expanded(
                child: leading == null
                    ? body
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          leading!,
                          Expanded(child: body),
                        ],
                      ),
              ),
              _Footer(
                missingLabels: _emptyRequiredLabels(specs),
                compact: compact,
                doneLabel: doneLabel,
                onCancel: onCancel,
                onDone: onDone,
              ),
            ],
          );
        },
      ),
    );
  }

  String _raw(String label, WireIptcFieldSpec? spec) {
    final key = spec?.storageKey ?? label;
    return IptcTemplateApplyService.lookupValue(values, key) ?? '';
  }

  String _display(String label, WireIptcFieldSpec? spec) {
    final stored = _raw(label, spec);
    if (stored.isNotEmpty &&
        !IptcTemplateApplyService.isInAppGeneratedPlaceholder(stored)) {
      if (label == 'Keywords') return _listText(stored, ', ');
      if (label == 'Personality') {
        return _listText(stored, ';', commas: false);
      }
      return stored;
    }
    final found = spec != null && _found(spec.storageKey);
    if ((label == 'Caption' || label == 'Personality') && found) {
      return IptcTemplateApplyService.inAppGeneratedPlaceholder;
    }
    return stored;
  }

  bool _found(String storageKey) {
    if (foundInFilesKeys.contains(storageKey)) return true;
    final preset = IptcTemplateApplyService.toPresetKey(storageKey);
    return foundInFilesKeys.contains(preset) ||
        foundInFilesKeys.contains(IptcTemplateApplyService.toPanelKey(preset));
  }

  bool _required(WireIptcFieldSpec? spec) =>
      spec?.level == IptcFieldLevel.required;

  /// Keywords use a comma and a space. Personality uses a semicolon and no space.
  String _listText(String raw, String separator, {bool commas = true}) {
    final seen = <String>{};
    final parts = [
      for (final part in raw.split(commas ? RegExp(r'[,;]') : RegExp(';')))
        if (part.trim().isNotEmpty && seen.add(part.trim().toLowerCase()))
          part.trim(),
    ];
    return parts.join(separator);
  }

  bool _blank(String label, WireIptcFieldSpec? spec) {
    final shown = _display(label, spec).trim();
    return shown.isEmpty ||
        IptcTemplateApplyService.isInAppGeneratedPlaceholder(shown);
  }

  static const _suppLabels = ['Supp Cat 1', 'Supp Cat 2', 'Supp Cat 3'];

  bool get _gettyNeedsOneSupp => wire == WireStyle.getty;

  bool _suppBlank(Map<String, WireIptcFieldSpec> specs, String label) =>
      _blank(label, specs[label]);

  bool _allSuppBlank(Map<String, WireIptcFieldSpec> specs) =>
      _suppLabels.every((label) => _suppBlank(specs, label));

  List<String> _emptyRequiredLabels(Map<String, WireIptcFieldSpec> specs) {
    const keys = [
      'Headline',
      'Personality',
      'Keywords',
      'Special Instructions',
      'Creator',
      'Job Title',
      'Description Writers',
      'Credit',
      'Source',
      'Copyright',
      'Location',
      'City',
      'Province/State',
      'Country',
      'Country Code',
      'MEID',
      'Object Name',
      'Category',
      'Supp Cat 1',
      'Supp Cat 2',
      'Supp Cat 3',
      'Urgency',
    ];
    final out = <String>[];
    var countedSupp = false;
    for (final label in keys) {
      final spec = specs[label];
      if (label == 'Urgency') continue;
      if (_gettyNeedsOneSupp && _suppLabels.contains(label)) {
        if (!countedSupp && _allSuppBlank(specs)) {
          out.add('Supplemental Category');
          countedSupp = true;
        }
        continue;
      }
      if (!_required(spec)) continue;
      if (_blank(label, spec)) out.add(label);
    }
    return out;
  }

  Widget _group({
    required IptcEditorColors colors,
    required IconData icon,
    required String title,
    required List<Widget> children,
    bool compact = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : 12,
        compact ? 8 : 10,
        compact ? 8 : 12,
        compact ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: colors.group,
        borderRadius: BorderRadius.circular(12),
        border: colors.workspace
            ? Border.all(color: FfTokens.nocturneLn2)
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(2, 0, 2, compact ? 2 : 6),
            child: Row(
              children: [
                PhosphorIcon(icon, size: 15, color: colors.t3),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1 * 13,
                    color: colors.t3,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _text(
    Map<String, WireIptcFieldSpec> specs,
    String label,
    bool narrow,
    double fieldH, {
    String? display,
  }) {
    final spec = specs[label];
    final key = spec?.storageKey ?? label;
    final value = _display(label, spec);
    final required = _required(spec);
    final empty = required && _blank(label, spec);
    return _FieldSlot(
      label: display ?? label,
      required: required,
      empty: empty,
      narrow: narrow,
      height: fieldH,
      child: _TextInput(
        key: ValueKey('$key-$revision'),
        value: value,
        enabled: fieldsEnabled,
        mono: _monoKeys.contains(label),
        missing: empty,
        height: fieldH,
        narrow: narrow,
        maxLength: label == 'Country Code' ? 3 : null,
        normalize: label == 'Keywords'
            ? (v) => _listText(v, ', ')
            : label == 'Personality'
                ? (v) => _listText(v, ';', commas: false)
                : null,
        onChanged: (v) => onValueChanged(key, v),
      ),
    );
  }

  Widget _country(
    Map<String, WireIptcFieldSpec> specs,
    bool narrow,
    double fieldH,
  ) {
    final country = specs['Country'];
    final code = specs['Country Code'];
    final countryEmpty = _required(country) && _blank('Country', country);
    final codeEmpty = _required(code) && _blank('Country Code', code);
    return _FieldSlot(
      label: 'Country',
      required: _required(country) || _required(code),
      empty: countryEmpty || codeEmpty,
      narrow: narrow,
      height: fieldH,
      child: Row(
        children: [
          Expanded(
            child: _TextInput(
              key: ValueKey('Country-$revision'),
              value: _display('Country', country),
              enabled: fieldsEnabled,
              missing: countryEmpty,
              height: fieldH,
              narrow: narrow,
              onChanged: (v) => onValueChanged(country?.storageKey ?? 'Country', v),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 64,
            child: _TextInput(
              key: ValueKey('Country Code-$revision'),
              value: _display('Country Code', code),
              enabled: fieldsEnabled,
              mono: true,
              missing: codeEmpty,
              height: fieldH,
              narrow: narrow,
              center: true,
              maxLength: 3,
              onChanged: (v) =>
                  onValueChanged(code?.storageKey ?? 'Country Code', v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _supp(
    Map<String, WireIptcFieldSpec> specs,
    bool narrow,
    double fieldH,
    IptcEditorColors colors,
  ) {
    final labels = _suppLabels;
    final shorts = ['Supp 1', 'Supp 2', 'Supp 3'];
    final groupMissing = _gettyNeedsOneSupp && _allSuppBlank(specs);
    final empties = [
      for (final label in labels)
        _gettyNeedsOneSupp
            ? groupMissing
            : _required(specs[label]) && _blank(label, specs[label]),
    ];
    return _FieldSlot(
      label: 'Supp cats',
      required: _gettyNeedsOneSupp ||
          labels.any((label) => _required(specs[label])),
      empty: empties.any((e) => e),
      hideLabel: narrow,
      narrow: narrow,
      height: fieldH,
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Stack(
                children: [
                  _TextInput(
                    key: ValueKey('${labels[i]}-$revision'),
                    value: _display(labels[i], specs[labels[i]]),
                    enabled: fieldsEnabled,
                    mono: true,
                    missing: empties[i],
                    height: fieldH,
                    narrow: narrow,
                    center: true,
                    onChanged: (v) => onValueChanged(
                      specs[labels[i]]?.storageKey ?? labels[i],
                      v,
                    ),
                  ),
                  if (narrow)
                    Positioned(
                      top: 3,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Text(
                          shorts[i].toUpperCase(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4,
                            color: empties[i] ? _warn : colors.t3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _urgency(
    Map<String, WireIptcFieldSpec> specs,
    bool narrow,
    double fieldH,
  ) {
    final spec = specs['Urgency'];
    final key = spec?.storageKey ?? 'Urgency';
    final raw = _raw('Urgency', spec).trim();
    final value = raw.isEmpty
        ? '5'
        : IptcTemplateApplyService.normalizeUrgencyValue(raw);
    return _FieldSlot(
      label: 'Urgency',
      required: false,
      empty: false,
      narrow: narrow,
      height: fieldH,
      child: _UrgencyInput(
        value: value,
        enabled: fieldsEnabled,
        height: fieldH,
        narrow: narrow,
        onChanged: (v) => onValueChanged(key, v),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.showTemplateControls,
    required this.templates,
    required this.selectedTemplateId,
    required this.onTemplateSelected,
    required this.onLoad,
    required this.onClear,
    required this.onSave,
    required this.loadingTemplate,
    required this.onClose,
    required this.compact,
  });

  final String title;
  final String? subtitle;
  final bool showTemplateControls;
  final List<IptcTemplateCatalogEntry> templates;
  final String selectedTemplateId;
  final ValueChanged<IptcTemplateCatalogEntry> onTemplateSelected;
  final VoidCallback? onLoad;
  final VoidCallback? onClear;
  final VoidCallback? onSave;
  final bool loadingTemplate;
  final VoidCallback onClose;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    final entries = templates;
    return Container(
      padding: EdgeInsets.fromLTRB(20, compact ? 8 : 12, 12, compact ? 8 : 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colors.tx,
            ),
          ),
          if (!showTemplateControls) ...[
            if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    color: colors.t3,
                  ),
                ),
              ),
            ] else
              const Spacer(),
            _ClearLink(onTap: onClear),
            _IconButton(
              icon: PhosphorIconsRegular.x,
              tooltip: 'Close',
              onTap: onClose,
            ),
          ] else ...[
            const SizedBox(width: 8),
            _TemplateDropdown(
              entries: entries,
              selectedTemplateId: selectedTemplateId,
              onSelected: onTemplateSelected,
            ),
            const SizedBox(width: 4),
            _LinkButton(
              icon: PhosphorIconsRegular.floppyDisk,
              label: 'Save template',
              tooltip: 'Save changes to this template',
              onTap: onSave,
              compact: compact,
            ),
            const Spacer(),
            _LinkButton(
              icon: PhosphorIconsRegular.uploadSimple,
              label: loadingTemplate
                  ? 'Importing…'
                  : 'Import from JPG, Getty TXT, or XMP',
              tooltip: 'Import from JPG, Getty TXT, or XMP',
              onTap: onLoad,
            ),
            _ClearLink(onTap: onClear, compact: compact),
            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: colors.line,
            ),
            _IconButton(
              icon: PhosphorIconsRegular.x,
              tooltip: 'Close',
              onTap: onClose,
            ),
          ],
        ],
      ),
    );
  }
}

/// Apply bar: On load on/off only.
class _ApplyWhenBar extends StatelessWidget {
  const _ApplyWhenBar({
    required this.mode,
    required this.onChanged,
    required this.compact,
  });

  final IptcApplyMode mode;
  final ValueChanged<IptcApplyMode>? onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    final onLoad = mode.appliesOnLoad;
    return Row(
      children: [
        Text(
          'APPLY',
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1 * 13,
            color: colors.t3,
          ),
        ),
        const SizedBox(width: 12),
        Material(
          color: colors.group,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onChanged == null
                ? null
                : () => onChanged!(
                      onLoad ? IptcApplyMode.none : IptcApplyMode.onImport,
                    ),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 32,
              padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color:
                          onLoad ? FfTokens.sessionOn : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: onLoad
                          ? null
                          : Border.all(color: FfTokens.sessionLn2),
                    ),
                    child: onLoad
                        ? const PhosphorIcon(
                            PhosphorIconsBold.check,
                            size: 11,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'On load',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: onLoad ? colors.tx : colors.t2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!compact) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              onLoad
                  ? 'Written to every photo as soon as the folder opens'
                  : 'Don’t write IPTC when the folder opens',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12,
                color: colors.t3,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TemplateDropdown extends StatelessWidget {
  const _TemplateDropdown({
    required this.entries,
    required this.selectedTemplateId,
    required this.onSelected,
  });

  final List<IptcTemplateCatalogEntry> entries;
  final String selectedTemplateId;
  final ValueChanged<IptcTemplateCatalogEntry> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    final ids = entries.map((e) => e.id).toSet();
    final selected =
        ids.contains(selectedTemplateId) ? selectedTemplateId : null;
    return Container(
      width: 220,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          hint: Text(
            'Choose',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.t3,
            ),
          ),
          isExpanded: true,
          isDense: true,
          dropdownColor: colors.group,
          icon: PhosphorIcon(
            PhosphorIconsRegular.caretDown,
            size: 12,
            color: colors.t3,
          ),
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.tx,
          ),
          items: [
            for (final entry in entries)
              DropdownMenuItem(
                value: entry.id,
                child: Text(
                  entry.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) {
            if (id == null) return;
            for (final entry in entries) {
              if (entry.id == id) {
                onSelected(entry);
                return;
              }
            }
          },
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: colors.t2,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(icon, size: 16, color: colors.t2),
            if (!compact) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ClearLink extends StatefulWidget {
  const _ClearLink({required this.onTap, this.compact = false});
  final VoidCallback? onTap;
  final bool compact;

  @override
  State<_ClearLink> createState() => _ClearLinkState();
}

class _ClearLinkState extends State<_ClearLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    final enabled = widget.onTap != null;
    final hot = enabled && _hover;
    final color = hot ? const Color(0xFFF07167) : colors.t2;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: 'Clear all',
        child: TextButton(
          onPressed: widget.onTap,
          style: TextButton.styleFrom(
            foregroundColor: color,
            backgroundColor:
                hot ? const Color(0x1AF07167) : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(
                PhosphorIconsRegular.trash,
                size: 16,
                color: color,
              ),
              if (!widget.compact) ...[
                const SizedBox(width: 6),
                Text(
                  'Clear all',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 32,
          height: 32,
          child: PhosphorIcon(icon, size: 17, color: colors.t2),
        ),
      ),
    );
  }
}

class _CaptionOmittedNote extends StatelessWidget {
  const _CaptionOmittedNote({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        compact ? 8 : 10,
        14,
        compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: colors.group,
        borderRadius: BorderRadius.circular(12),
        border: colors.workspace
            ? Border.all(color: FfTokens.nocturneLn2)
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhosphorIcon(
            PhosphorIconsRegular.info,
            size: 16,
            color: colors.t3,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Caption isn’t in this template — existing captions stay on your '
              'photos and are written later when you caption in the session.\n'
              '\n'
              'If photos already have Personality or Keywords, Go time asks '
              'whether to merge (add onto what’s there) or overwrite with '
              'these values.',
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 12,
                height: 1.35,
                color: colors.t2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldSlot extends StatelessWidget {
  const _FieldSlot({
    required this.label,
    required this.required,
    required this.empty,
    required this.narrow,
    required this.height,
    required this.child,
    this.hideLabel = false,
  });

  final String label;
  final bool required;
  final bool empty;
  final bool narrow;
  final double height;
  final Widget child;
  final bool hideLabel;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    final labelColor = empty ? _warn : (narrow ? colors.t3 : colors.t2);
    final dot = required
        ? Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Container(
              width: narrow ? 4 : 5,
              height: narrow ? 4 : 5,
              decoration: BoxDecoration(
                color: empty ? _warn : colors.t3,
                shape: BoxShape.circle,
              ),
            ),
          )
        : const SizedBox.shrink();
    final labelWidget = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: label),
          if (required)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: dot,
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: FfTokens.fontFamily,
        fontSize: narrow ? 10 : 12,
        fontWeight: narrow ? FontWeight.w600 : FontWeight.w400,
        letterSpacing: narrow ? 0.4 : 0,
        color: labelColor,
      ),
    );

    if (narrow) {
      // Fixed height — never use Positioned.fill in a scroll view (unbounded).
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(child: child),
              if (!hideLabel)
                Positioned(
                  top: 3,
                  left: 8,
                  right: 8,
                  child: IgnorePointer(child: labelWidget),
                ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            SizedBox(width: 104, child: labelWidget),
            const SizedBox(width: 10),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _TextInput extends StatefulWidget {
  const _TextInput({
    super.key,
    required this.value,
    required this.enabled,
    required this.missing,
    required this.height,
    required this.narrow,
    required this.onChanged,
    this.mono = false,
    this.center = false,
    this.maxLength,
    this.normalize,
  });

  final String value;
  final bool enabled;
  final bool missing;
  final double height;
  final bool narrow;
  final ValueChanged<String> onChanged;
  final bool mono;
  final bool center;
  final int? maxLength;
  final String Function(String value)? normalize;

  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focus = FocusNode()..addListener(_onFocus);
  }

  void _onFocus() {
    if (!_focus.hasFocus) {
      final normalize = widget.normalize;
      if (normalize != null) {
        final next = normalize(_controller.text);
        if (next != _controller.text) _controller.text = next;
        if (next != widget.value) widget.onChanged(next);
      }
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(_TextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focus.hasFocus) return;
    if (_controller.text != widget.value) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    final focused = _focus.hasFocus;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _hover && !focused ? colors.hover : colors.field,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: focused
                ? colors.focus
                : widget.missing
                    ? _warnLine
                    : colors.workspace
                        ? FfTokens.nocturneLn
                        : Colors.transparent,
          ),
        ),
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          enabled: widget.enabled,
          maxLength: widget.maxLength,
          textAlign: widget.center ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontFamily: widget.mono ? FfTokens.monoFamily : FfTokens.fontFamily,
            fontSize: widget.mono ? 12 : 13,
            color: colors.tx,
          ),
          cursorColor: colors.focus,
          inputFormatters: widget.maxLength == null
              ? null
              : [LengthLimitingTextInputFormatter(widget.maxLength)],
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            border: InputBorder.none,
            contentPadding: EdgeInsets.fromLTRB(
              widget.center ? 6 : 10,
              widget.narrow ? 14 : 0,
              widget.center ? 6 : 10,
              0,
            ),
          ),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}


class _UrgencyInput extends StatefulWidget {
  const _UrgencyInput({
    required this.value,
    required this.enabled,
    required this.height,
    required this.narrow,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final double height;
  final bool narrow;
  final ValueChanged<String> onChanged;

  @override
  State<_UrgencyInput> createState() => _UrgencyInputState();
}

class _UrgencyInputState extends State<_UrgencyInput> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: widget.height,
        padding: EdgeInsets.fromLTRB(10, widget.narrow ? 12 : 0, 6, 0),
        decoration: BoxDecoration(
          color: _hover ? colors.hover : colors.field,
          borderRadius: BorderRadius.circular(7),
          border: colors.workspace
              ? Border.all(color: FfTokens.nocturneLn)
              : null,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: IptcTemplateApplyService.urgencyValues.contains(widget.value)
                ? widget.value
                : '5',
            isExpanded: true,
            isDense: true,
            dropdownColor: colors.group,
            icon: PhosphorIcon(
              PhosphorIconsRegular.caretDown,
              size: 12,
              color: colors.t3,
            ),
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 13,
              color: colors.tx,
            ),
            items: [
              for (final level in IptcTemplateApplyService.urgencyValues)
                DropdownMenuItem(
                  value: level,
                  child: Text(
                    '$level · ${IptcTemplateApplyService.urgencyMenuLabel(level)}',
                  ),
                ),
            ],
            onChanged: widget.enabled
                ? (v) {
                    if (v != null) widget.onChanged(v);
                  }
                : null,
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.missingLabels,
    required this.compact,
    required this.doneLabel,
    required this.onCancel,
    required this.onDone,
  });

  final List<String> missingLabels;
  final bool compact;
  final String doneLabel;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = IptcEditorPalette.of(context);
    final ok = missingLabels.isEmpty;
    final label = ok
        ? 'All suggested fields filled'
        : 'Missing: ${missingLabels.join(', ')}';
    return Container(
      padding: EdgeInsets.fromLTRB(20, compact ? 8 : 10, 12, compact ? 8 : 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: [
          PhosphorIcon(
            ok ? PhosphorIconsFill.checkCircle : PhosphorIconsFill.warningCircle,
            size: 16,
            color: ok ? colors.ok : _warn,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 13,
                color: ok ? colors.t2 : _warn,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: colors.t3,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Suggested',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 12,
              color: colors.t3,
            ),
          ),
          const SizedBox(width: 16),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: colors.t2,
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (colors.workspace)
            TealActionButton(
              label: doneLabel,
              onPressed: onDone,
              icon: const PhosphorIcon(
                PhosphorIconsBold.check,
                size: 14,
                color: Colors.white,
              ),
            )
          else
            _DoneButton(label: doneLabel, onPressed: onDone),
        ],
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(9),
        child: Ink(
          height: 38,
          padding: const EdgeInsets.fromLTRB(16, 0, 18, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF243848),
                Color(0xFF15242E),
                Color(0xFF0E181F),
              ],
            ),
            border: Border.all(color: const Color(0xF24A7A96)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x404A7A96),
                blurRadius: 18,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PhosphorIcon(
                PhosphorIconsBold.check,
                size: 15,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
