import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_icons/phosphor_icons.dart';

import '../services/camera_serial_service.dart';
import '../theme/ff_tokens.dart';
import '../utils/oriented_image_bytes.dart';
import 'app_styled_dialogs.dart';
import 'photographer_name_field.dart';

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
    this.imagePath,
    this.cameraBody,
  });

  final CameraSerialService cameraService;

  /// Camera serial from EXIF, or null/empty when the file has none.
  final String? serialNumber;

  /// Photo this serial was read from.
  final String? imagePath;

  /// Camera body (make and model) read from the same EXIF as [serialNumber].
  final String? cameraBody;

  /// Shows the dialog and returns the assignment, or null if cancelled.
  static Future<UnknownSerialAssignment?> show(
    BuildContext context, {
    required CameraSerialService cameraService,
    String? serialNumber,
    String? imagePath,
    String? cameraBody,
  }) {
    return showDialog<UnknownSerialAssignment>(
      context: context,
      barrierDismissible: true,
      builder: (context) => UnknownSerialDialog(
        cameraService: cameraService,
        serialNumber: serialNumber,
        imagePath: imagePath,
        cameraBody: cameraBody,
      ),
    );
  }

  @override
  State<UnknownSerialDialog> createState() => _UnknownSerialDialogState();
}

class _UnknownSerialDialogState extends State<UnknownSerialDialog> {
  final _nameController = TextEditingController();
  final _initialsController = TextEditingController();

  String get _serial => widget.serialNumber?.trim() ?? '';
  bool get _hasSerial => _serial.isNotEmpty;
  String get _body => widget.cameraBody?.trim() ?? '';

  @override
  void dispose() {
    _nameController.dispose();
    _initialsController.dispose();
    super.dispose();
  }

  void _applyPhotographerInitials(String name) {
    var initials = '';
    for (final entry in widget.cameraService.fullCameraMappings.entries) {
      if ((entry.value['name'] ?? '') == name) {
        initials = entry.value['initials'] ?? '';
        break;
      }
    }
    setState(() => _initialsController.text = initials);
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    var initials = _initialsController.text.trim();
    if (initials.isEmpty) {
      for (final entry in widget.cameraService.fullCameraMappings.entries) {
        if ((entry.value['name'] ?? '') == name) {
          initials = entry.value['initials'] ?? '';
          break;
        }
      }
    }

    if (_hasSerial) {
      await widget.cameraService.addCameraMapping(
        _serial,
        name,
        initials: initials,
        body: widget.cameraBody ?? '',
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop(
      UnknownSerialAssignment(name: name, initials: initials),
    );
  }

  Widget _label(FfTokens t, String text) {
    return Text(
      text,
      style: t.metaStyle.copyWith(
        fontSize: 11,
        color: t.textTertiary,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  InputDecoration _fieldDecoration(FfTokens t, {String? hint}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(FfTokens.radiusChip),
      borderSide: BorderSide(color: t.divider),
    );
    return InputDecoration(
      isDense: true,
      hintText: hint,
      filled: true,
      fillColor: t.sunken,
      hintStyle: t.metaStyle.copyWith(color: t.textTertiary),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        borderSide: BorderSide(color: t.accent, width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final existing = widget.cameraService.getUniquePhotographerNames();
    final canSubmit = _nameController.text.trim().isNotEmpty;

    return AppDialogFfStyle(
      enabled: true,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          width: 520,
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Assign serial number to photographer byline',
                              style: t.labelStyle.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                            if ((widget.imagePath ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                p.basename(widget.imagePath!.trim()),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.metaStyle.copyWith(
                                  color: t.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
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
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.62,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if ((widget.imagePath ?? '').trim().isNotEmpty)
                          _SerialPromptPhoto(path: widget.imagePath!.trim()),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                          child: Text(
                            _hasSerial
                                ? 'Serial number $_serial${_body.isEmpty ? '' : ' · $_body'} is not on the list.'
                                : 'This photo has no camera serial.',
                            style: t.metaStyle.copyWith(
                              color: t.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(t, 'Photographer'),
                              const SizedBox(height: 6),
                              PhotographerNameField(
                                controller: _nameController,
                                names: existing,
                                onSelected: _applyPhotographerInitials,
                              ),
                              const SizedBox(height: 10),
                              _label(t, 'Initials'),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: 96,
                                height: 36,
                                child: TextField(
                                  controller: _initialsController,
                                  style: t.bodyStyle.copyWith(
                                    fontSize: 13,
                                    height: 1.2,
                                  ),
                                  cursorColor: t.accent,
                                  textAlignVertical: TextAlignVertical.center,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  decoration: _fieldDecoration(t, hint: 'MDB')
                                      .copyWith(isCollapsed: true),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedGreyButton(
                        label: 'Cancel',
                        fontSize: 11,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      ElevatedGreyButton(
                        label: 'Save',
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

class _SerialPromptPhoto extends StatefulWidget {
  const _SerialPromptPhoto({required this.path});

  final String path;

  @override
  State<_SerialPromptPhoto> createState() => _SerialPromptPhotoState();
}

class _SerialPromptPhotoState extends State<_SerialPromptPhoto> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await OrientedImageBytes.load(
      widget.path,
      maxWidth: 960,
      priority: true,
    );
    if (!mounted) return;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: t.bg,
          child: SizedBox(
            height: 180,
            width: double.infinity,
            child: _bytes == null
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Image.memory(_bytes!, fit: BoxFit.contain),
          ),
        ),
      ],
    );
  }
}
