import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../../../caption_style/caption_template.dart';
import '../../../caption_style/wire_iptc_specs.dart';
import '../../../services/app_defaults_firestore_service.dart';
import '../../../services/iptc_template_apply_service.dart';
import '../../../theme/ff_tokens.dart';

const Color _warn = Color(0xFFE8B547);
const Color _warnLine = Color(0x73E8B547);

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 1100;
        final short = constraints.maxHeight < 700;
        final tight = constraints.maxHeight < 560;
        final fieldH = narrow ? (tight ? 32.0 : 38.0) : (short ? 28.0 : 32.0);
        final padV = short ? 8.0 : 12.0;
        return Column(
          children: [
            _Header(
              templates: templates,
              selectedTemplateId: selectedTemplateId,
              onTemplateSelected: onTemplateSelected,
              onLoad: loadEnabled ? onLoadTemplate : null,
              onClear: clearEnabled ? onClearTemplate : null,
              onSave: fieldsEnabled ? onSaveTemplate : null,
              loadingTemplate: loadingTemplate,
              onClose: onCancel,
              compact: short,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: _CaptionBox(
                value: _display('Caption', specs['Caption']),
                revision: revision,
                enabled: fieldsEnabled,
                compact: short,
                onChanged: (v) => onValueChanged('Caption', v),
              ),
            ),
            SizedBox(height: tight ? 6 : 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, padV),
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _group(
                            icon: PhosphorIconsRegular.article,
                            title: 'Story',
                            children: [
                              _text(specs, 'Headline', narrow, fieldH),
                              _text(specs, 'Personality', narrow, fieldH),
                              _text(specs, 'Keywords', narrow, fieldH),
                              _text(specs, 'Special Instructions', narrow, fieldH),
                            ],
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: _group(
                            icon: PhosphorIconsRegular.user,
                            title: 'Credit',
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
                          )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _group(
                            icon: PhosphorIconsRegular.mapPin,
                            title: 'Location',
                            children: [
                              _text(specs, 'Location', narrow, fieldH, display: 'Venue'),
                              _text(specs, 'City', narrow, fieldH),
                              _text(
                                specs,
                                'Province/State',
                                narrow,
                                fieldH,
                                display: 'Province',
                              ),
                              _country(specs, narrow, fieldH),
                            ],
                          )),
                          const SizedBox(width: 10),
                          Expanded(child: _group(
                            icon: PhosphorIconsRegular.folderSimple,
                            title: 'Filing',
                            children: [
                              _text(specs, 'MEID', narrow, fieldH),
                              _text(specs, 'Object Name', narrow, fieldH, display: 'Object name'),
                              _text(specs, 'Category', narrow, fieldH),
                              _supp(specs, narrow, fieldH),
                              _urgency(specs, narrow, fieldH),
                            ],
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _Footer(
              emptyRequired: _emptyRequiredCount(specs),
              compact: short,
              onCancel: onCancel,
              onDone: onDone,
            ),
          ],
        );
      },
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

  int _emptyRequiredCount(Map<String, WireIptcFieldSpec> specs) {
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
    var n = 0;
    var countedSupp = false;
    for (final label in keys) {
      final spec = specs[label];
      if (label == 'Urgency') continue;
      if (_gettyNeedsOneSupp && _suppLabels.contains(label)) {
        if (!countedSupp && _allSuppBlank(specs)) {
          n++;
          countedSupp = true;
        }
        continue;
      }
      if (!_required(spec)) continue;
      if (_blank(label, spec)) n++;
    }
    return n;
  }

  Widget _group({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: FfTokens.sessionBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Row(
              children: [
                PhosphorIcon(icon, size: 14, color: FfTokens.sessionT3),
                const SizedBox(width: 6),
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: FfTokens.sessionT3,
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
                            color: empties[i] ? _warn : FfTokens.sessionT3,
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
    final entries = templates;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, compact ? 8 : 12, 12, compact ? 8 : 12),
      child: Row(
        children: [
          const Text(
            'IPTC template',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: FfTokens.sessionTx,
            ),
          ),
          const SizedBox(width: 12),
          _TemplateDropdown(
            entries: entries,
            selectedTemplateId: selectedTemplateId,
            onSelected: onTemplateSelected,
          ),
          const SizedBox(width: 4),
          _LinkButton(
            icon: PhosphorIconsRegular.uploadSimple,
            label: loadingTemplate ? 'Loading' : 'Load',
            tooltip: 'Load from XMP, Getty TXT, or JPG',
            onTap: onLoad,
          ),
          const Text(
            'XMP, Getty TXT, or JPG',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 12,
              color: FfTokens.sessionT3,
            ),
          ),
          const SizedBox(width: 16),
          _LinkButton(
            icon: PhosphorIconsRegular.floppyDisk,
            label: 'Save template',
            tooltip: 'Save these fields as a template',
            onTap: onSave,
          ),
          _ClearLink(onTap: onClear),
          const Spacer(),
          _IconButton(icon: PhosphorIconsRegular.x, tooltip: 'Close', onTap: onClose),
        ],
      ),
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
    final ids = entries.map((e) => e.id).toSet();
    final selected = ids.contains(selectedTemplateId) ? selectedTemplateId : null;
    return Container(
      width: 220,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: FfTokens.sessionEl,
        borderRadius: BorderRadius.circular(7),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          isDense: true,
          dropdownColor: FfTokens.sessionEl,
          icon: const PhosphorIcon(
            PhosphorIconsRegular.caretDown,
            size: 12,
            color: FfTokens.sessionT3,
          ),
          style: const TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: FfTokens.sessionTx,
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
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: FfTokens.sessionT2,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: PhosphorIcon(icon, size: 15, color: FfTokens.sessionT2),
        label: Text(
          label,
          style: const TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ClearLink extends StatefulWidget {
  const _ClearLink({required this.onTap});
  final VoidCallback? onTap;

  @override
  State<_ClearLink> createState() => _ClearLinkState();
}

class _ClearLinkState extends State<_ClearLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final hot = enabled && _hover;
    final color = hot ? const Color(0xFFF07A7A) : FfTokens.sessionT2;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: TextButton.icon(
        onPressed: widget.onTap,
        style: TextButton.styleFrom(
          foregroundColor: color,
          backgroundColor: hot ? const Color(0x14F07A7A) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: PhosphorIcon(PhosphorIconsRegular.trash, size: 15, color: color),
        label: Text(
          'Clear all',
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: color,
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
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 32,
          height: 32,
          child: PhosphorIcon(icon, size: 17, color: FfTokens.sessionT2),
        ),
      ),
    );
  }
}

class _CaptionBox extends StatefulWidget {
  const _CaptionBox({
    required this.value,
    required this.revision,
    required this.enabled,
    required this.compact,
    required this.onChanged,
  });

  final String value;
  final int revision;
  final bool enabled;
  final bool compact;
  final ValueChanged<String> onChanged;

  @override
  State<_CaptionBox> createState() => _CaptionBoxState();
}

class _CaptionBoxState extends State<_CaptionBox> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focus = FocusNode();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (_focus.hasFocus &&
        IptcTemplateApplyService.isInAppGeneratedPlaceholder(_controller.text)) {
      _controller.clear();
      widget.onChanged('');
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(_CaptionBox oldWidget) {
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
    final count = _controller.text.trim() ==
            IptcTemplateApplyService.inAppGeneratedPlaceholder
        ? 0
        : _controller.text.length;
    return Container(
      padding: EdgeInsets.fromLTRB(14, widget.compact ? 8 : 10, 14, widget.compact ? 8 : 10),
      decoration: BoxDecoration(
        color: FfTokens.sessionBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'CAPTION',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: FfTokens.sessionT3,
                ),
              ),
              const Spacer(),
              Text(
                '$count / 2000',
                style: const TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 11,
                  color: FfTokens.sessionT3,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _controller,
            focusNode: _focus,
            enabled: widget.enabled,
            maxLines: null,
            minLines: 2,
            scrollPhysics: const NeverScrollableScrollPhysics(),
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: widget.compact ? 13 : 14,
              height: widget.compact ? 19 / 13 : 21 / 14,
              color: FfTokens.sessionTx,
            ),
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (v) {
              setState(() {});
              widget.onChanged(v);
            },
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
    final labelColor = empty ? _warn : (narrow ? FfTokens.sessionT3 : FfTokens.sessionT2);
    final dot = required
        ? Padding(
            padding: const EdgeInsets.only(left: 5),
            child: Container(
              width: narrow ? 4 : 5,
              height: narrow ? 4 : 5,
              decoration: BoxDecoration(
                color: empty ? _warn : FfTokens.sessionT3,
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
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
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
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Row(
          children: [
            SizedBox(width: 96, child: labelWidget),
            const SizedBox(width: 8),
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
    final focused = _focus.hasFocus;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: widget.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _hover && !focused ? FfTokens.sessionHv : FfTokens.sessionEl,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: focused
                ? FfTokens.sessionOn
                : widget.missing
                    ? _warnLine
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
            color: FfTokens.sessionTx,
          ),
          cursorColor: FfTokens.sessionOn,
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
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: widget.height,
        padding: EdgeInsets.fromLTRB(10, widget.narrow ? 12 : 0, 6, 0),
        decoration: BoxDecoration(
          color: _hover ? FfTokens.sessionHv : FfTokens.sessionEl,
          borderRadius: BorderRadius.circular(7),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: IptcTemplateApplyService.urgencyValues.contains(widget.value)
                ? widget.value
                : '5',
            isExpanded: true,
            isDense: true,
            dropdownColor: FfTokens.sessionEl,
            icon: const PhosphorIcon(
              PhosphorIconsRegular.caretDown,
              size: 12,
              color: FfTokens.sessionT3,
            ),
            style: const TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 13,
              color: FfTokens.sessionTx,
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
    required this.emptyRequired,
    required this.compact,
    required this.onCancel,
    required this.onDone,
  });

  final int emptyRequired;
  final bool compact;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final ok = emptyRequired == 0;
    final label = ok
        ? 'All required fields filled'
        : '$emptyRequired required field${emptyRequired == 1 ? '' : 's'} empty';
    return Container(
      padding: EdgeInsets.fromLTRB(20, compact ? 8 : 10, 12, compact ? 8 : 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: FfTokens.sessionLn)),
      ),
      child: Row(
        children: [
          PhosphorIcon(
            ok ? PhosphorIconsFill.checkCircle : PhosphorIconsFill.warningCircle,
            size: 16,
            color: ok ? FfTokens.sessionOk : _warn,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontSize: 13,
                color: FfTokens.sessionT2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: FfTokens.sessionT3,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Required',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 12,
              color: FfTokens.sessionT3,
            ),
          ),
          const SizedBox(width: 16),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: FfTokens.sessionT2,
              minimumSize: Size(0, compact ? 32 : 36),
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
          FilledButton.icon(
            onPressed: onDone,
            icon: const PhosphorIcon(
              PhosphorIconsBold.check,
              size: 14,
              color: FfTokens.sessionBg,
            ),
            label: const Text('Done'),
            style: FilledButton.styleFrom(
              backgroundColor: FfTokens.sessionTx,
              foregroundColor: FfTokens.sessionBg,
              minimumSize: Size(0, compact ? 32 : 36),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
              textStyle: const TextStyle(
                fontFamily: FfTokens.fontFamily,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
