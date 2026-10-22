import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../caption_style/wire_iptc_specs.dart';
import '../../../services/preferences_service.dart';
import '../../../theme/ff_tokens.dart';
import '../../../widgets/app_styled_dialogs.dart';
import '../../../widgets/ff_menu.dart';
import '../../../widgets/oriented_file_preview.dart';
import '../data/caption_transfer_payload.dart';
import '../data/caption_v2_controller.dart';
import 'iptc_template_editor.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

enum _PhotoAction {
  copyCaption,
  pasteCaption,
  applyTemplate,
  editIptc,
  editPhotoshop,
  ftp,
  clearFtp,
  reveal,
  rename,
  delete,
}

Future<void> showCaptionV2Zoom(
  BuildContext context,
  String imagePath,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.9),
    builder: (dialogContext) {
      final t = Theme.of(dialogContext).extension<FfTokens>() ?? FfTokens.dark;
      return Dialog(
        insetPadding: const EdgeInsets.all(20),
        backgroundColor: t.sunken,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
          side: BorderSide(color: t.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 8,
                boundaryMargin: const EdgeInsets.all(240),
                child: Center(
                  child: OrientedFilePreview(
                    path: imagePath,
                    fit: BoxFit.contain,
                    cacheWidth: 4096,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              bottom: 12,
              child: _OverlayLabel(
                label: '${p.basename(imagePath)}  ·  scroll or pinch to zoom',
                tokens: t,
              ),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const PhosphorIcon(PhosphorIconsRegular.x),
                tooltip: 'Close',
                style: IconButton.styleFrom(
                  backgroundColor: t.surface.withValues(alpha: 0.9),
                  foregroundColor: t.text,
                  side: BorderSide(color: t.divider),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> showCaptionV2PhotoMenu({
  required BuildContext context,
  required CaptionV2Controller controller,
  required String imagePath,
  required Offset position,
  List<String>? pasteTargets,
}) async {
  FfMenuChoice<_PhotoAction> item(
    _PhotoAction value,
    String label,
    IconData icon, {
    bool destructive = false,
  }) {
    final color = destructive ? FfTokens.danger : null;
    return FfMenuChoice<_PhotoAction>(
      value: value,
      child: Row(
        children: [
          PhosphorIcon(icon, color: color),
          const SizedBox(width: 10),
          Text(label, style: color == null ? null : TextStyle(color: color)),
        ],
      ),
    );
  }

  final sent = controller.sentImages.contains(imagePath);
  final targets = (pasteTargets == null || pasteTargets.isEmpty
          ? <String>[imagePath]
          : pasteTargets)
      .toSet()
      .toList();
  final picked = await showFfMenu<_PhotoAction>(
    context: context,
    anchorGlobal: Rect.fromLTWH(position.dx, position.dy, 0, 0),
    width: 260,
    scrollable: false,
    choices: [
      item(_PhotoAction.copyCaption, 'Copy Caption', PhosphorIconsRegular.copy),
      item(
        _PhotoAction.pasteCaption,
        targets.length > 1
            ? 'Paste Caption to ${targets.length} Photos'
            : 'Paste Caption',
        PhosphorIconsRegular.clipboardText,
      ),
      item(
        _PhotoAction.applyTemplate,
        'Apply IPTC Template',
        PhosphorIconsRegular.fileText,
      ),
      item(_PhotoAction.editIptc, 'Edit IPTC', PhosphorIconsRegular.pencilSimple),
      item(
        _PhotoAction.editPhotoshop,
        'Edit in Photoshop',
        PhosphorIconsRegular.paintBrush,
      ),
      const FfMenuChoice<_PhotoAction>.divider(),
      if (controller.ftpModeEnabled) ...[
        if (targets.length > 1)
          item(
            _PhotoAction.ftp,
            'FTP ${targets.length} images',
            PhosphorIconsRegular.cloudArrowUp,
          )
        else if (sent)
          item(
            _PhotoAction.clearFtp,
            'Remove FTP Status',
            PhosphorIconsRegular.cloudCheck,
          )
        else
          item(_PhotoAction.ftp, 'FTP Image', PhosphorIconsRegular.cloudArrowUp),
        const FfMenuChoice<_PhotoAction>.divider(),
      ],
      item(_PhotoAction.reveal, 'Open in Finder', PhosphorIconsRegular.arrowSquareOut),
      item(
        _PhotoAction.rename,
        'Rename Image',
        PhosphorIconsRegular.pencilSimple,
      ),
      const FfMenuChoice<_PhotoAction>.divider(),
      item(
        _PhotoAction.delete,
        targets.length > 1
            ? 'Delete ${targets.length} Images'
            : 'Delete Image',
        PhosphorIconsRegular.trash,
        destructive: true,
      ),
    ],
  );
  final action = picked?.value;
  if (action == null || !context.mounted) return;

  switch (action) {
    case _PhotoAction.copyCaption:
      final values = await controller.readIptcPanelValues(imagePath);
      final photographer = await controller.photographerNameForPath(imagePath);
      final payload = CaptionTransferPayload(
        caption: values['Caption'] ?? '',
        personality: values['Personality'] ?? '',
        keywords: values['Keywords'] ?? '',
        photographerName: photographer,
        clicks: controller.clicksForTransfer(imagePath),
      );
      await Clipboard.setData(ClipboardData(text: payload.encode()));
      if (context.mounted) _message(context, 'Caption copied');
      break;
    case _PhotoAction.pasteCaption:
      await _pasteCaption(context, controller, targets);
      break;
    case _PhotoAction.applyTemplate:
      final ok = await controller.applySelectedIptcTemplate(imagePath);
      if (context.mounted) {
        _message(
            context, ok ? 'IPTC template applied' : 'No IPTC template set');
      }
      break;
    case _PhotoAction.editIptc:
      await showCaptionV2MetadataEditor(context, controller, imagePath);
      break;
    case _PhotoAction.editPhotoshop:
      await _openInPhotoshop(context, imagePath);
      break;
    case _PhotoAction.ftp:
      if (targets.length > 1) {
        final n = targets.length;
        final ok = await showAppConfirmDialog(
          context: context,
          title: 'FTP $n images',
          message: 'Upload $n selected photos.',
          cancelLabel: 'Cancel',
          confirmLabel: 'FTP',
        );
        if (ok == true && context.mounted) {
          await controller.transmitPaths(targets);
        }
      } else {
        await controller.transmitPath(imagePath);
      }
      break;
    case _PhotoAction.clearFtp:
      controller.clearSentStatus(imagePath);
      _message(context, 'FTP status removed');
      break;
    case _PhotoAction.reveal:
      await Process.run('open', ['-R', imagePath]);
      break;
    case _PhotoAction.rename:
      await _renameImage(context, controller, imagePath);
      break;
    case _PhotoAction.delete:
      await _deleteImages(context, controller, targets);
      break;
  }
}

Future<void> _pasteCaption(
  BuildContext context,
  CaptionV2Controller controller,
  List<String> imagePaths,
) async {
  try {
    final text = (await Clipboard.getData('text/plain'))?.text;
    final payload = text == null ? null : CaptionTransferPayload.decode(text);
    if (payload == null || payload.caption.trim().isEmpty) {
      throw const FormatException();
    }
    var pastedCount = 0;
    String? openCaption;
    final current = controller.currentPath;
    final includesCurrent = current != null && imagePaths.contains(current);
    controller.rememberClicks(imagePaths, payload.clicks);
    final clicksApplied = includesCurrent &&
        payload.clicks != null &&
        controller.applyCaptionClicks(payload.clicks!);
    if (clicksApplied) controller.notifyListeners();
    for (final imagePath in imagePaths) {
      final destinationPhotographer =
          await controller.photographerNameForPath(imagePath);
      final caption = CaptionTransferPayload.captionForDestinationPhotographer(
        caption: payload.caption,
        sourcePhotographer: payload.photographerName,
        destinationPhotographer: destinationPhotographer,
        removeDiacritics: controller.captionTemplate.removeDiacritics,
      );
      if (imagePath == current) {
        openCaption = clicksApplied ? controller.displayedCaption : caption;
      }
      final values = <String, String>{
        'Caption': imagePath == current ? (openCaption ?? caption) : caption,
        if (payload.personality.trim().isNotEmpty)
          'Personality': payload.personality,
        if (payload.keywords.trim().isNotEmpty) 'Keywords': payload.keywords,
      };
      final ok = await controller.writeIptcPanelValues(imagePath, values);
      if (ok) pastedCount++;
    }

    final appliesToOpenPreview =
        current != null && imagePaths.contains(current);
    if (appliesToOpenPreview && !clicksApplied) {
      controller.applyPastedPhotoCaption(
        caption: openCaption ?? payload.caption,
        personality: payload.personality,
        keywords: payload.keywords,
      );
    } else {
      controller.selectedImagePaths.clear();
      controller.notifyListeners();
    }

    if (context.mounted) {
      final message = pastedCount == imagePaths.length
          ? (pastedCount == 1
              ? 'Caption pasted'
              : 'Caption pasted to $pastedCount photos')
          : 'Caption pasted to $pastedCount of ${imagePaths.length} photos';
      _message(context, message);
    }
  } catch (_) {
    if (context.mounted) _message(context, 'Clipboard has no FloFile caption');
  }
}

Future<void> _openInPhotoshop(
  BuildContext context,
  String imagePath,
) async {
  final prefs = await PreferencesService.getInstance();
  final photoshopPath = await prefs.getPhotoshopPath();
  if (photoshopPath == null || photoshopPath.isEmpty) {
    if (context.mounted) {
      _message(context, 'Set the Photoshop path in Options first');
    }
    return;
  }
  final result = await Process.run('open', ['-a', photoshopPath, imagePath]);
  if (context.mounted) {
    _message(
      context,
      result.exitCode == 0
          ? 'Opening ${p.basename(imagePath)} in Photoshop'
          : 'Could not open Photoshop',
    );
  }
}

Future<void> _renameImage(
  BuildContext context,
  CaptionV2Controller controller,
  String imagePath,
) async {
  final extension = p.extension(imagePath);
  final text =
      TextEditingController(text: p.basenameWithoutExtension(imagePath));
  final result = await _showTextDialog(
    context,
    title: 'Rename image',
    description: p.basename(imagePath),
    controller: text,
    confirmLabel: 'Rename',
    suffix: extension,
  );
  text.dispose();
  if (result == null || result.trim().isEmpty) return;
  final ok = await controller.renameImage(
    imagePath,
    '${result.trim()}$extension',
  );
  if (context.mounted) {
    _message(context, ok ? 'Image renamed' : 'That filename already exists');
  }
}

Future<void> _deleteImages(
  BuildContext context,
  CaptionV2Controller controller,
  List<String> imagePaths,
) async {
  final paths = imagePaths.toSet().toList(growable: false);
  if (paths.isEmpty) return;
  final n = paths.length;
  final confirmed = await _showConfirmDialog(
    context,
    title: n == 1 ? 'Delete image?' : 'Delete $n images?',
    body: n == 1
        ? '${p.basename(paths.first)} will be permanently deleted.'
        : '$n selected photos will be permanently deleted.',
    confirmLabel: 'Delete',
  );
  if (!confirmed) return;
  final deleted = await controller.deleteImages(paths);
  if (!context.mounted) return;
  if (deleted == 0) {
    _message(context, 'Could not delete images');
  } else if (deleted == 1 && n == 1) {
    _message(context, 'Image deleted');
  } else if (deleted == n) {
    _message(context, '$deleted images deleted');
  } else {
    _message(context, 'Deleted $deleted of $n images');
  }
}

Future<void> showCaptionV2MetadataEditor(
  BuildContext context,
  CaptionV2Controller controller,
  String imagePath,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CaptionV2MetadataEditor(
      controller: controller,
      imagePath: imagePath,
    ),
  );
}

class _CaptionV2MetadataEditor extends StatefulWidget {
  const _CaptionV2MetadataEditor({
    required this.controller,
    required this.imagePath,
  });

  final CaptionV2Controller controller;
  final String imagePath;

  @override
  State<_CaptionV2MetadataEditor> createState() =>
      _CaptionV2MetadataEditorState();
}

class _CaptionV2MetadataEditorState extends State<_CaptionV2MetadataEditor> {
  Map<String, String> _values = const {};
  int _revision = 0;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values =
        await widget.controller.readIptcPanelValues(widget.imagePath);
    if (!mounted) return;
    setState(() {
      _values = values;
      _loading = false;
    });
  }

  void _onValueChanged(String key, String value) {
    setState(() {
      final next = Map<String, String>.from(_values);
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        next.remove(key);
      } else {
        next[key] = trimmed;
      }
      _values = next;
    });
  }

  void _clear() {
    setState(() {
      _values = const {};
      _revision++;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final values = <String, String>{
      for (final entry in _values.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };
    final fieldsToClear = WireIptcSpecs.fieldsForPanel(
      widget.controller.captionTemplate.wireStyle,
    )
        .map((spec) => spec.storageKey)
        .where((key) => key != 'Time and Date' && !values.containsKey(key))
        .toSet();
    final ok = await widget.controller.writeIptcPanelValues(
      widget.imagePath,
      values,
      fieldsToClear: fieldsToClear,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      _message(context, 'IPTC saved');
    } else {
      setState(() => _saving = false);
      _message(context, 'Could not save IPTC');
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wire = widget.controller.captionTemplate.wireStyle;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      backgroundColor: FfTokens.nocturneBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
        side: const BorderSide(color: FfTokens.nocturneLn2),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: (size.width - 32).clamp(0.0, 1240.0),
        height: size.height - 32,
        child: _loading
            ? const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: FfTokens.nocturneAc,
                  ),
                ),
              )
            : IptcTemplateEditor(
                wire: wire,
                templates: const [],
                selectedTemplateId: '',
                values: _values,
                foundInFilesKeys: const {},
                revision: _revision,
                fieldsEnabled: !_saving,
                onTemplateSelected: (_) {},
                onValueChanged: _onValueChanged,
                onLoadTemplate: null,
                onClearTemplate: _saving ? null : _clear,
                onSaveTemplate: null,
                loadEnabled: false,
                clearEnabled: !_saving,
                onCancel: () {
                  if (_saving) return;
                  Navigator.of(context).pop();
                },
                onDone: _save,
                title: 'Edit IPTC',
                subtitle: p.basename(widget.imagePath),
                doneLabel: _saving ? 'Saving' : 'Save',
                showTemplateControls: false,
                workspacePalette: true,
                leading: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 0, 12),
                  child: SizedBox(
                    width: 280,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: FfTokens.nocturneSunken,
                        borderRadius:
                            BorderRadius.circular(FfTokens.radiusCard),
                        border: Border.all(color: FfTokens.nocturneLn2),
                      ),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(FfTokens.radiusCard),
                        child: OrientedFilePreview(
                          path: widget.imagePath,
                          version: widget.controller
                              .imageContentStamp(widget.imagePath),
                          fit: BoxFit.contain,
                          cacheWidth: 1000,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _OverlayLabel extends StatelessWidget {
  const _OverlayLabel({required this.label, required this.tokens});
  final String label;
  final FfTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        border: Border.all(color: tokens.divider),
      ),
      child:
          Text(label, style: tokens.monoMetaStyle.copyWith(color: tokens.text)),
    );
  }
}

Future<String?> _showTextDialog(
  BuildContext context, {
  required String title,
  required String description,
  required TextEditingController controller,
  required String confirmLabel,
  String? suffix,
}) {
  final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
        side: BorderSide(color: t.divider),
      ),
      title: Text(title, style: t.labelStyle.copyWith(fontSize: 16)),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description, style: t.monoMetaStyle),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              style: t.bodyStyle,
              onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
              decoration: InputDecoration(
                filled: true,
                fillColor: t.sunken,
                suffixText: suffix,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                  borderSide: BorderSide(color: t.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(FfTokens.radiusChip),
                  borderSide: BorderSide(color: t.accent),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          style: FilledButton.styleFrom(
            backgroundColor: FfTokens.gold,
            foregroundColor: FfTokens.inkOnGold,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

Future<bool> _showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
            side: BorderSide(color: t.divider),
          ),
          title: Text(title, style: t.labelStyle.copyWith(fontSize: 16)),
          content: Text(body, style: t.bodyStyle),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: FfTokens.danger,
                foregroundColor: FfTokens.inkOnGold,
              ),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;
}

void _message(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
  );
}
