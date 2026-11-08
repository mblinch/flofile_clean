import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../caption_style/wire_iptc_specs.dart';
import '../../../services/iptc_template_import_service.dart';
import '../../../services/preferences_service.dart';
import '../../../theme/ff_tokens.dart';
import '../../../utils/exiftool_helper.dart';
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
      return _CaptionV2ZoomDialog(imagePath: imagePath);
    },
  );
}

class _CaptionV2ZoomDialog extends StatefulWidget {
  const _CaptionV2ZoomDialog({required this.imagePath});

  final String imagePath;

  @override
  State<_CaptionV2ZoomDialog> createState() => _CaptionV2ZoomDialogState();
}

class _CaptionV2ZoomDialogState extends State<_CaptionV2ZoomDialog> {
  static const double _minScale = 0.8;
  static const double _maxScale = 8.0;
  static const double _zoomStep = 1.35;

  final TransformationController _transform = TransformationController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _zoomBy(double factor) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final size = box.size;
    final focal = Offset(size.width / 2, size.height / 2);
    final sceneFocal = _transform.toScene(focal);
    final current = _transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(_minScale, _maxScale);
    if ((next - current).abs() < 0.001) return;
    final ratio = next / current;
    final updated = Matrix4.identity()
      ..translate(focal.dx, focal.dy)
      ..scale(ratio)
      ..translate(-sceneFocal.dx, -sceneFocal.dy);
    _transform.value = updated;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isMetaPressed || keys.isControlPressed || keys.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyZ) {
      _zoomBy(keys.isShiftPressed ? (1 / _zoomStep) : _zoomStep);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.numpadAdd) {
      _zoomBy(_zoomStep);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _zoomBy(1 / _zoomStep);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Dialog(
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
                transformationController: _transform,
                minScale: _minScale,
                maxScale: _maxScale,
                boundaryMargin: const EdgeInsets.all(240),
                child: Center(
                  child: OrientedFilePreview(
                    path: widget.imagePath,
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
                label:
                    '${p.basename(widget.imagePath)}  ·  Z to zoom in  ·  scroll or pinch',
                tokens: t,
              ),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
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
      ),
    );
  }
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
  /// Near Edit IPTC.html `minmax(220px, 300px)`, with room to drag wider.
  static const double _defaultPhotoWidth = 260;
  static const double _minPhotoWidth = 220;
  static const double _maxPhotoWidth = 360;

  /// Capture tags for the under-photo EXIF list (aligned with photo_column /
  /// picture_preview_widget / metadata_popup_dialog).
  static const _captureExifTags = <String>[
    '-Model',
    '-Make',
    '-ShutterSpeed',
    '-ExposureTime',
    '-FNumber',
    '-ISO',
    '-ISOSpeed',
    '-PhotographicSensitivity',
    '-FocalLength',
    '-LensID',
    '-LensModel',
    '-Lens',
    '-DateTimeOriginal',
    '-CreateDate',
    '-ModifyDate',
    '-SubSecTimeOriginal',
    '-SerialNumber',
    '-BodySerialNumber',
    '-ImageWidth',
    '-ImageHeight',
    '-ExifImageWidth',
    '-ExifImageHeight',
    '-PixelXDimension',
    '-PixelYDimension',
    '-ImageSize',
  ];

  static const _captureKeys = <String>{
    'DateTimeOriginal',
    'CreateDate',
    'ModifyDate',
    'SubSecTimeOriginal',
    'Make',
    'Model',
    'ShutterSpeed',
    'ExposureTime',
    'FNumber',
    'ISO',
    'ISOSpeed',
    'PhotographicSensitivity',
    'FocalLength',
    'LensID',
    'LensModel',
    'Lens',
    'SerialNumber',
    'BodySerialNumber',
    'ImageWidth',
    'ImageHeight',
    'ExifImageWidth',
    'ExifImageHeight',
    'PixelXDimension',
    'PixelYDimension',
    'ImageSize',
  };

  Map<String, String> _values = const {};
  int _revision = 0;
  bool _loading = true;
  bool _exifLoading = true;
  bool _saving = false;
  double _photoWidth = _defaultPhotoWidth;
  Map<String, dynamic>? _exif;

  @override
  void initState() {
    super.initState();
    _seedExifFromController();
    _load();
  }

  void _seedExifFromController() {
    if (widget.controller.currentPath != widget.imagePath) return;
    final meta = widget.controller.currentIptcMeta;
    if (meta.isEmpty) return;
    final capture = _captureOnly(Map<String, dynamic>.from(meta));
    if (capture.isEmpty) return;
    _exif = capture;
    _exifLoading = false;
  }

  /// Keep camera/capture tags only; normalize group prefixes to short keys so
  /// [IptcTemplateImportService.formatExifDateHeading] and row lookups match.
  static Map<String, dynamic> _captureOnly(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    raw.forEach((key, value) {
      if (value == null) return;
      final short = key.contains(':') ? key.split(':').last : key;
      if (short == 'SourceFile' || short == 'ExifToolVersion') return;
      if (!_captureKeys.contains(short) && !_captureKeys.contains(key)) return;
      final dest = _captureKeys.contains(short) ? short : key;
      if (out.containsKey(dest) && out[dest] != null) return;
      if (value is String && value.trim().isEmpty) return;
      if (value is List && value.isEmpty) return;
      out[dest] = value;
    });
    return out;
  }

  static bool _hasCaptureData(Map<String, dynamic>? meta) {
    if (meta == null || meta.isEmpty) return false;
    return meta.keys.any((k) {
      final short = k.contains(':') ? k.split(':').last : k;
      return short != 'SourceFile' && _captureKeys.contains(short);
    });
  }

  Future<void> _load() async {
    final valuesFuture =
        widget.controller.readIptcPanelValues(widget.imagePath);
    final exifFuture = _loadExif(widget.imagePath);
    final values = await valuesFuture;
    final exif = await exifFuture;
    if (!mounted) return;
    setState(() {
      _values = values;
      if (_hasCaptureData(exif)) {
        // Merge onto seed so a thin/partial load cannot wipe populated rows.
        _exif = <String, dynamic>{
          ...?_exif,
          ...exif!,
        };
      }
      _exifLoading = false;
      _loading = false;
    });
  }

  Future<Map<String, dynamic>?> _loadExif(String path) async {
    try {
      final proc = await ExiftoolHelper.run([
        '-j',
        ..._captureExifTags,
        path,
      ]);
      if (!proc.isSuccess) return null;
      final decoded = jsonDecode(proc.stdoutText);
      if (decoded is! List || decoded.isEmpty) return null;
      final first = decoded.first;
      if (first is! Map) return null;
      final capture = _captureOnly(Map<String, dynamic>.from(first));
      return capture.isEmpty ? null : capture;
    } catch (_) {
      return null;
    }
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
      // Edit IPTC.html `.m` panel — `--p: #181D22`
      backgroundColor: FfTokens.nocturneEl,
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
                captionTemplate: widget.controller.captionTemplate,
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
                leading: _EditIptcLeadingColumn(
                  imagePath: widget.imagePath,
                  imageVersion:
                      widget.controller.imageContentStamp(widget.imagePath),
                  width: _photoWidth.clamp(_minPhotoWidth, _maxPhotoWidth),
                  exif: _exif,
                  exifLoading: _exifLoading,
                  onDragWidth: (delta) => setState(() {
                    _photoWidth = (_photoWidth + delta)
                        .clamp(_minPhotoWidth, _maxPhotoWidth);
                  }),
                  onResetWidth: () =>
                      setState(() => _photoWidth = _defaultPhotoWidth),
                ),
              ),
      ),
    );
  }
}

/// Photo on top (3:2), scrollable capture/EXIF underneath, drag handle on right.
class _EditIptcLeadingColumn extends StatelessWidget {
  const _EditIptcLeadingColumn({
    required this.imagePath,
    required this.imageVersion,
    required this.width,
    required this.exif,
    required this.exifLoading,
    required this.onDragWidth,
    required this.onResetWidth,
  });

  final String imagePath;
  final int imageVersion;
  final double width;
  final Map<String, dynamic>? exif;
  final bool exifLoading;
  final ValueChanged<double> onDragWidth;
  final VoidCallback onResetWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 0, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: width,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final photoHeight = (width * 2 / 3)
                    .clamp(0.0, constraints.maxHeight * 0.55);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: photoHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF101418),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: OrientedFilePreview(
                            path: imagePath,
                            version: imageVersion,
                            fit: BoxFit.cover,
                            cacheWidth: 1000,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _EditIptcExifList(
                        exif: exif,
                        loading: exifLoading,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          _EditIptcResizeHandle(
            onDrag: onDragWidth,
            onReset: onResetWidth,
          ),
        ],
      ),
    );
  }
}

class _EditIptcResizeHandle extends StatelessWidget {
  const _EditIptcResizeHandle({
    required this.onDrag,
    required this.onReset,
  });

  final ValueChanged<double> onDrag;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        onDoubleTap: onReset,
        child: const Tooltip(
          message: 'Drag to resize the preview. Double-click to reset.',
          waitDuration: Duration(milliseconds: 400),
          child: SizedBox(
            width: 22,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 10),
                SizedBox(
                  width: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: FfTokens.sessionLn2,
                      borderRadius: BorderRadius.all(Radius.circular(1)),
                    ),
                  ),
                ),
                SizedBox(width: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditIptcExifList extends StatelessWidget {
  const _EditIptcExifList({
    required this.exif,
    required this.loading,
  });

  final Map<String, dynamic>? exif;
  final bool loading;

  String _stringify(dynamic raw) {
    if (raw == null) return '';
    if (raw is List) {
      for (final item in raw) {
        final s = item?.toString().trim() ?? '';
        if (s.isNotEmpty) return s;
      }
      return '';
    }
    return raw.toString().trim();
  }

  String _first(List<String> keys) {
    final meta = exif;
    if (meta == null) return '';
    for (final key in keys) {
      final direct = _stringify(meta[key]);
      if (direct.isNotEmpty) return direct;
      // Group-prefixed fallbacks (EXIF:Make, Composite:ImageSize, …).
      for (final entry in meta.entries) {
        final k = entry.key;
        final short = k.contains(':') ? k.split(':').last : k;
        if (short != key) continue;
        final value = _stringify(entry.value);
        if (value.isNotEmpty) return value;
      }
    }
    return '';
  }

  String _formatShutter(String raw) {
    if (raw.isEmpty) return '';
    if (raw.contains('/')) return raw;
    final value = double.tryParse(raw);
    if (value == null || value <= 0) return raw;
    return value < 1
        ? '1/${(1 / value).round()}s'
        : '${value.toStringAsFixed(1)}s';
  }

  String _formatAperture(String raw) {
    if (raw.isEmpty) return '';
    final f = double.tryParse(raw);
    if (f != null) return 'f/${f.toStringAsFixed(1)}';
    if (raw.startsWith('f/') || raw.startsWith('F/')) return raw;
    return 'f/$raw';
  }

  String _formatFocal(String raw) {
    if (raw.isEmpty) return '';
    final cleaned = raw.replaceAll(RegExp(r'm+$'), '').trim();
    final d = double.tryParse(cleaned);
    if (d != null) return '${d.toInt()}mm';
    return cleaned.toLowerCase().endsWith('mm') ? cleaned : '${cleaned}mm';
  }

  String _dimensions() {
    final w = _first(const [
      'ImageWidth',
      'ExifImageWidth',
      'PixelXDimension',
    ]);
    final h = _first(const [
      'ImageHeight',
      'ExifImageHeight',
      'PixelYDimension',
    ]);
    if (w.isNotEmpty && h.isNotEmpty) return '$w×$h';
    final size = _first(const ['ImageSize']);
    if (size.isEmpty) return '';
    return size.replaceAll(RegExp(r'[xX]'), '×');
  }

  String _camera() {
    final make = _first(const ['Make']);
    final model = _first(const ['Model']);
    final serial = _first(const ['SerialNumber', 'BodySerialNumber']);
    final name = '$make $model'.trim();
    if (name.isEmpty) return '';
    if (serial.isEmpty) return name;
    return '$name · SN $serial';
  }

  String _settings() {
    final shutter = _formatShutter(
      _first(const ['ShutterSpeed', 'ExposureTime']),
    );
    final aperture = _formatAperture(_first(const ['FNumber']));
    if (shutter.isNotEmpty && aperture.isNotEmpty) {
      return '$shutter @ $aperture';
    }
    if (shutter.isNotEmpty) return shutter;
    return aperture;
  }

  List<({String label, String value})> _rows() {
    final meta = exif;
    final date = meta == null
        ? ''
        : IptcTemplateImportService.formatExifDateHeading(meta);
    final time = meta == null
        ? ''
        : IptcTemplateImportService.formatExifTimeHeading(meta);
    final iso = _first(const ['ISO', 'ISOSpeed', 'PhotographicSensitivity']);
    return [
      (label: 'Date', value: date),
      (label: 'Time', value: time),
      (label: 'Dimensions', value: _dimensions()),
      (label: 'Settings', value: _settings()),
      (label: 'ISO', value: iso.isEmpty ? '' : 'ISO $iso'),
      (label: 'Focal length', value: _formatFocal(_first(const ['FocalLength']))),
      (label: 'Camera', value: _camera()),
      (
        label: 'Lens',
        value: _first(const ['LensModel', 'Lens', 'LensID']),
      ),
    ].where((row) => row.value.isNotEmpty).toList(growable: false);
  }

  Widget _panel({required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FfTokens.nocturneSunken,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: FfTokens.nocturneLn2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    if (rows.isEmpty && loading) {
      return _panel(
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: FfTokens.nocturneAc,
            ),
          ),
        ),
      );
    }
    if (rows.isEmpty) {
      // Hide the empty decorated box that previously looked like a blank panel.
      return const SizedBox.shrink();
    }
    const labelStyle = TextStyle(
      fontSize: 11,
      height: 1.25,
      fontWeight: FontWeight.w500,
      color: FfTokens.nocturneT3,
    );
    const valueStyle = TextStyle(
      fontSize: 12,
      height: 1.3,
      fontWeight: FontWeight.w500,
      color: FfTokens.nocturneTx,
    );
    return _panel(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final row = rows[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.label, style: labelStyle),
              const SizedBox(height: 2),
              Text(row.value, style: valueStyle),
            ],
          );
        },
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
