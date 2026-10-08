import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../services/camera_serial_service.dart';
import '../theme/ff_tokens.dart';
import 'app_styled_dialogs.dart';
import 'ff_dropdown.dart';

/// Result of assigning a photographer for an unknown / missing camera serial.
class UnknownSerialAssignment {
  const UnknownSerialAssignment({
    required this.name,
    this.initials = '',
  });

  final String name;
  final String initials;
}

/// Asks who shot the photo when serial bylines is on and the serial is missing
/// from EXIF or not yet mapped. Saves name + initials to the camera list when
/// a serial is available.
class UnknownSerialDialog extends StatefulWidget {
  const UnknownSerialDialog({
    super.key,
    required this.cameraService,
    this.serialNumber,
  });

  final CameraSerialService cameraService;

  /// Camera serial from EXIF, or null/empty when the file has none.
  final String? serialNumber;

  /// Shows the dialog and returns the assignment, or null if cancelled.
  static Future<UnknownSerialAssignment?> show(
    BuildContext context, {
    required CameraSerialService cameraService,
    String? serialNumber,
  }) {
    return showDialog<UnknownSerialAssignment>(
      context: context,
      barrierDismissible: true,
      builder: (context) => UnknownSerialDialog(
        cameraService: cameraService,
        serialNumber: serialNumber,
      ),
    );
  }

  @override
  State<UnknownSerialDialog> createState() => _UnknownSerialDialogState();
}

class _UnknownSerialDialogState extends State<UnknownSerialDialog> {
  final _nameController = TextEditingController();
  final _initialsController = TextEditingController();
  String? _selectedExisting;
  bool _useExisting = false;

  String get _serial => widget.serialNumber?.trim() ?? '';
  bool get _hasSerial => _serial.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final existing = widget.cameraService.getUniquePhotographerNames();
    _useExisting = existing.isNotEmpty;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _initialsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String name;
    String initials = _initialsController.text.trim();

    if (_useExisting && _selectedExisting != null) {
      name = _selectedExisting!.trim();
      if (name.isEmpty) return;
      // Reuse initials already stored for that photographer, if any.
      if (initials.isEmpty) {
        for (final entry
            in widget.cameraService.fullCameraMappings.entries) {
          if ((entry.value['name'] ?? '') == name) {
            initials = entry.value['initials'] ?? '';
            break;
          }
        }
      }
    } else {
      name = _nameController.text.trim();
      if (name.isEmpty) return;
    }

    if (_hasSerial) {
      await widget.cameraService.addCameraMapping(
        _serial,
        name,
        initials: initials,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      UnknownSerialAssignment(name: name, initials: initials),
    );
  }

  InputDecoration _fieldDecoration(FfTokens t, {required String label}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(FfTokens.radiusChip),
      borderSide: BorderSide(color: t.divider),
    );
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: t.sunken,
      labelStyle: t.metaStyle.copyWith(color: t.textSecondary),
      floatingLabelStyle: t.metaStyle.copyWith(color: t.accent),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        borderSide: BorderSide(color: t.accent, width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final existing = widget.cameraService.getUniquePhotographerNames();
    final canSubmit = _useExisting
        ? _selectedExisting != null && _selectedExisting!.trim().isNotEmpty
        : _nameController.text.trim().isNotEmpty;

    return AppDialogFfStyle(
      enabled: true,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          width: 420,
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
            border: Border.all(color: t.divider),
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
                  padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
                  decoration: BoxDecoration(
                    color: t.bg,
                    border: Border(bottom: BorderSide(color: t.divider)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Who took this photo?',
                          style: t.labelStyle.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: PhosphorIcon(
                          PhosphorIconsRegular.x,
                          size: 18,
                          color: t.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _hasSerial
                            ? 'Serial “$_serial” isn’t in your camera list yet. '
                                'Enter the photographer so bylines can use them next time.'
                            : 'This photo has no camera serial number. '
                                'Enter the photographer for the byline.',
                        style: t.bodyStyle.copyWith(
                          fontSize: 13,
                          height: 1.35,
                          color: t.text.withValues(alpha: 0.88),
                        ),
                      ),
                      if (_hasSerial) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: t.sunken,
                            borderRadius:
                                BorderRadius.circular(FfTokens.radiusChip),
                            border: Border.all(color: t.divider),
                          ),
                          child: Text(
                            'SN: $_serial',
                            style: t.metaStyle.copyWith(
                              fontWeight: FontWeight.w600,
                              color: t.accent,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      if (existing.isNotEmpty) ...[
                        Row(
                          children: [
                            ChoiceChip(
                              label: const Text('Existing'),
                              selected: _useExisting,
                              onSelected: (_) => setState(() {
                                _useExisting = true;
                              }),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('New'),
                              selected: !_useExisting,
                              onSelected: (_) => setState(() {
                                _useExisting = false;
                                _selectedExisting = null;
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (_useExisting && existing.isNotEmpty)
                        InputDecorator(
                          decoration: _fieldDecoration(
                            t,
                            label: 'Photographer',
                          ),
                          child: FfDropdownButton<String>(
                            value: _selectedExisting,
                            isExpanded: true,
                            menuColor: t.surface,
                            style: t.bodyStyle.copyWith(fontSize: 13),
                            items: [
                              for (final name in existing)
                                DropdownMenuItem(
                                  value: name,
                                  child: Text(name),
                                ),
                            ],
                            onChanged: (v) => setState(() {
                              _selectedExisting = v;
                            }),
                          ),
                        )
                      else ...[
                        TextField(
                          controller: _nameController,
                          autofocus: true,
                          style: t.bodyStyle.copyWith(fontSize: 13),
                          cursorColor: t.accent,
                          decoration: _fieldDecoration(
                            t,
                            label: 'Photographer name',
                          ),
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) {
                            if (canSubmit) _submit();
                          },
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _initialsController,
                            style: t.bodyStyle.copyWith(fontSize: 13),
                            cursorColor: t.accent,
                            textCapitalization: TextCapitalization.characters,
                            decoration: _fieldDecoration(
                              t,
                              label: 'Initials',
                            ),
                          ),
                        ),
                      ],
                      if (_useExisting && existing.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _initialsController,
                            style: t.bodyStyle.copyWith(fontSize: 13),
                            cursorColor: t.accent,
                            textCapitalization: TextCapitalization.characters,
                            decoration: _fieldDecoration(
                              t,
                              label: 'Initials',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedGreyButton(
                        label: 'Skip',
                        fontSize: 11,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      ElevatedGreyButton(
                        label: _hasSerial ? 'Save & use' : 'Use for byline',
                        fontSize: 11,
                        isPrimary: true,
                        onPressed: canSubmit ? _submit : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
