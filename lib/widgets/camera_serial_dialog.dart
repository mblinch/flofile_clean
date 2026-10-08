import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../services/camera_serial_service.dart';
import '../theme/ff_tokens.dart';
import 'app_styled_dialogs.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class CameraSerialDialog extends StatefulWidget {
  final CameraSerialService cameraService;

  const CameraSerialDialog({
    super.key,
    required this.cameraService,
  });

  @override
  State<CameraSerialDialog> createState() => _CameraSerialDialogState();
}

class _CameraSerialDialogState extends State<CameraSerialDialog> {
  final TextEditingController _serialController = TextEditingController();
  final TextEditingController _photographerController = TextEditingController();
  final TextEditingController _initialsController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  List<MapEntry<String, String>> _filteredMappings = [];
  String _searchQuery = '';
  @override
  void initState() {
    super.initState();
    _initializeCameraService();
    _updateFilteredMappings();
    _searchController.addListener(_onSearchChanged);
    widget.cameraService.mappingsRevision.addListener(_onMappingsChanged);
  }

  Future<void> _initializeCameraService() async {
    await widget.cameraService.initialize();
    if (mounted) {
      setState(_updateFilteredMappings);
    }
  }

  void _onMappingsChanged() {
    if (!mounted) return;
    setState(_updateFilteredMappings);
  }

  @override
  void dispose() {
    widget.cameraService.mappingsRevision.removeListener(_onMappingsChanged);
    _serialController.dispose();
    _photographerController.dispose();
    _initialsController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _updateFilteredMappings();
    });
  }

  void _updateFilteredMappings() {
    final allMappings =
        widget.cameraService.fullCameraMappings.entries.toList();

    if (_searchQuery.isEmpty) {
      _filteredMappings = allMappings
          .map((entry) => MapEntry(entry.key, entry.value['name'] ?? ''))
          .toList();
    } else {
      _filteredMappings = allMappings
          .where((entry) {
            final name = entry.value['name'] ?? '';
            final initials = entry.value['initials'] ?? '';
            return entry.key.toLowerCase().contains(_searchQuery) ||
                name.toLowerCase().contains(_searchQuery) ||
                initials.toLowerCase().contains(_searchQuery);
          })
          .map((entry) => MapEntry(entry.key, entry.value['name'] ?? ''))
          .toList();
    }

    _filteredMappings.sort((a, b) {
      final nameCompare = a.value.compareTo(b.value);
      if (nameCompare != 0) return nameCompare;
      return a.key.compareTo(b.key);
    });
  }

  Future<void> _addCamera() async {
    final serial = _serialController.text.trim();
    final photographer = _photographerController.text.trim();
    final initials = _initialsController.text.trim();

    if (serial.isEmpty || photographer.isEmpty) {
      _showSnackBar('Please enter both serial number and photographer name',
          isError: true);
      return;
    }

    final alreadyRegistered = widget.cameraService.isCameraRegistered(serial);
    if (alreadyRegistered) {
      final ok = await showAppConfirmDialog(
        context: context,
        title: 'Serial already mapped',
        message:
            'Serial “$serial” is already in your list. Update the photographer '
            'name and initials for that camera? A second entry will not be created.',
        cancelLabel: 'Cancel',
        confirmLabel: 'Update',
      );
      if (ok != true || !mounted) return;
    }

    try {
      final updated = await widget.cameraService
          .addCameraMapping(serial, photographer, initials: initials);
      _serialController.clear();
      _photographerController.clear();
      _initialsController.clear();
      setState(_updateFilteredMappings);
      _showSnackBar(
        updated
            ? 'Updated existing mapping for $serial'
            : 'Camera mapping added',
      );
    } catch (e) {
      _showSnackBar('Error adding camera mapping: $e', isError: true);
    }
  }

  Future<void> _removeCamera(String serialNumber) async {
    try {
      await widget.cameraService.removeCameraMapping(serialNumber);
      setState(() {
        _updateFilteredMappings();
      });
      _showSnackBar('Camera mapping removed');
    } catch (e) {
      _showSnackBar('Error removing camera mapping: $e', isError: true);
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Clear All Mappings',
      message:
          'Are you sure you want to remove all camera serial number mappings? This action cannot be undone.',
      cancelLabel: 'Cancel',
      confirmLabel: 'Clear All',
    );

    if (confirmed == true) {
      try {
        await widget.cameraService.clearAllMappings();
        setState(() {
          _updateFilteredMappings();
        });
        _showSnackBar('All camera mappings cleared');
      } catch (e) {
        _showSnackBar('Error clearing mappings: $e', isError: true);
      }
    }
  }

  Future<void> _importFromFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        await _processImportContent(content);
      }
    } catch (e) {
      _showSnackBar('Error importing file: $e', isError: true);
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text != null) {
        await _processImportContent(clipboardData!.text!);
      } else {
        _showSnackBar('No text found in clipboard', isError: true);
      }
    } catch (e) {
      _showSnackBar('Error reading clipboard: $e', isError: true);
    }
  }

  Future<void> _processImportContent(String content) async {
    final rows = <({String serial, String name, String initials})>[];
    final lines = content.split('\n');
    for (final lineRaw in lines) {
      final line = lineRaw.trim();
      if (line.isEmpty ||
          line.startsWith('serial#') ||
          line.startsWith('Name')) {
        continue;
      }

      final parts = line.split('\t');
      if (parts.length < 2) continue;
      final serialNumber = parts[0].trim();
      final photographerName = parts[1].trim();
      final initials = parts.length >= 3 ? parts[2].trim() : '';
      if (serialNumber.isEmpty || photographerName.isEmpty) continue;
      rows.add((
        serial: serialNumber,
        name: photographerName,
        initials: initials,
      ));
    }

    if (rows.isEmpty) {
      _showSnackBar('No valid camera rows found to import', isError: true);
      return;
    }

    try {
      final result = await widget.cameraService.mergeMappings(rows);
      setState(_updateFilteredMappings);

      final parts = <String>[];
      if (result.added > 0) {
        parts.add('${result.added} added');
      }
      if (result.updated > 0) {
        parts.add('${result.updated} updated (same serial, no duplicate)');
      }
      if (parts.isEmpty) {
        parts.add('No changes');
      }
      var message = 'Import: ${parts.join(', ')}';
      if (result.errors.isNotEmpty) {
        final shown = result.errors.take(5).join('\n');
        message += '\n\n${result.errors.length} issue(s):\n$shown';
      }
      _showSnackBar(message, isError: result.errors.isNotEmpty);
    } catch (e) {
      _showSnackBar('Error importing: $e', isError: true);
    }
  }

  Future<void> _detectFromCurrentImage() async {
    try {
      _showSnackBar('Camera serial detection feature coming soon!');
    } catch (e) {
      _showSnackBar('Error detecting camera serial: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? FfTokens.danger : t.accent,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  InputDecoration _fieldDecoration(
    FfTokens t, {
    required String label,
    String? hint,
    Widget? prefixIcon,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(FfTokens.radiusChip),
      borderSide: BorderSide(color: t.divider),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      isDense: true,
      filled: true,
      fillColor: t.sunken,
      labelStyle: t.metaStyle.copyWith(color: t.textSecondary),
      hintStyle: t.metaStyle.copyWith(
        color: t.text.withValues(alpha: 0.35),
      ),
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

  Widget _toolbarButton({
    required FfTokens t,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    final c = color ?? t.textSecondary;
    return TextButton.icon(
      onPressed: onPressed,
      icon: PhosphorIcon(icon, size: 15, color: c),
      label: Text(
        label,
        style: t.metaStyle.copyWith(
          color: c,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      style: TextButton.styleFrom(
        foregroundColor: c,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;

    return AppDialogFfStyle(
      enabled: true,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          width: 640,
          height: 540,
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
                  decoration: BoxDecoration(
                    color: t.bg,
                    border: Border(
                      bottom: BorderSide(color: t.divider),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Camera Serial Numbers',
                              style: t.labelStyle.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Map serials to photographers for automatic bylines. '
                              'Synced to your account when signed in.',
                              style: t.metaStyle.copyWith(
                                color: t.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Close',
                        icon: PhosphorIcon(
                          PhosphorIconsRegular.x,
                          size: 18,
                          color: t.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: t.sunken,
                            borderRadius:
                                BorderRadius.circular(FfTokens.radiusCard),
                            border: Border.all(color: t.divider),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Add New Camera',
                                style: t.labelStyle.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: _serialController,
                                      style: t.bodyStyle.copyWith(fontSize: 13),
                                      cursorColor: t.accent,
                                      decoration: _fieldDecoration(
                                        t,
                                        label: 'Serial number',
                                        hint: 'e.g. 1234567890',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: _photographerController,
                                      style: t.bodyStyle.copyWith(fontSize: 13),
                                      cursorColor: t.accent,
                                      decoration: _fieldDecoration(
                                        t,
                                        label: 'Photographer',
                                        hint: 'e.g. Mark Blinch',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: 88,
                                    child: TextField(
                                      controller: _initialsController,
                                      style: t.bodyStyle.copyWith(fontSize: 13),
                                      cursorColor: t.accent,
                                      decoration: _fieldDecoration(
                                        t,
                                        label: 'Initials',
                                        hint: 'MDB',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: ElevatedGreyButton(
                                      label: 'Add',
                                      fontSize: 11,
                                      isPrimary: true,
                                      onPressed: _addCamera,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: t.bodyStyle.copyWith(fontSize: 13),
                                cursorColor: t.accent,
                                decoration: _fieldDecoration(
                                  t,
                                  label: '',
                                  hint: 'Search cameras or photographers…',
                                  prefixIcon: PhosphorIcon(
                                    PhosphorIconsRegular.magnifyingGlass,
                                    size: 16,
                                    color: t.textSecondary,
                                  ),
                                ).copyWith(
                                  labelText: null,
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.never,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _toolbarButton(
                              t: t,
                              label: 'Import',
                              icon: PhosphorIconsRegular.uploadSimple,
                              onPressed: _importFromFile,
                              color: t.accent,
                            ),
                            _toolbarButton(
                              t: t,
                              label: 'Paste',
                              icon: PhosphorIconsRegular.clipboardText,
                              onPressed: _pasteFromClipboard,
                              color: t.accent,
                            ),
                            _toolbarButton(
                              t: t,
                              label: 'Detect',
                              icon: PhosphorIconsRegular.camera,
                              onPressed: _detectFromCurrentImage,
                              color: t.accent,
                            ),
                            if (_filteredMappings.isNotEmpty)
                              _toolbarButton(
                                t: t,
                                label: 'Clear',
                                icon: PhosphorIconsRegular.trash,
                                onPressed: _clearAll,
                                color: FfTokens.danger,
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: t.bg,
                              borderRadius:
                                  BorderRadius.circular(FfTokens.radiusCard),
                              border: Border.all(color: t.divider),
                            ),
                            child: _filteredMappings.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        PhosphorIcon(
                                          PhosphorIconsRegular.camera,
                                          size: 40,
                                          color: t.text.withValues(alpha: 0.28),
                                        ),
                                        const SizedBox(height: 14),
                                        Text(
                                          _searchQuery.isEmpty
                                              ? 'No camera mappings yet'
                                              : 'No cameras match “$_searchQuery”',
                                          style: t.bodyStyle.copyWith(
                                            fontSize: 14,
                                            color: t.textSecondary,
                                          ),
                                        ),
                                        if (_searchQuery.isEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            'Add a serial number above to get started',
                                            style: t.metaStyle.copyWith(
                                              color: t.text
                                                  .withValues(alpha: 0.45),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    itemCount: _filteredMappings.length,
                                    separatorBuilder: (_, __) => Divider(
                                      height: 1,
                                      color: t.divider.withValues(alpha: 0.7),
                                    ),
                                    itemBuilder: (context, index) {
                                      final entry = _filteredMappings[index];
                                      final serialNumber = entry.key;
                                      final photographerName = entry.value;
                                      final photographerData = widget
                                          .cameraService
                                          .getPhotographerData(serialNumber);
                                      final initials =
                                          photographerData?['initials'] ?? '';
                                      final primary = photographerName;
                                      final secondary = initials.isNotEmpty
                                          ? 'SN: $serialNumber · $initials'
                                          : 'SN: $serialNumber';

                                      return Material(
                                        color: index.isEven
                                            ? t.sunken.withValues(alpha: 0.45)
                                            : Colors.transparent,
                                        child: ListTile(
                                          dense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 2,
                                          ),
                                          leading: PhosphorIcon(
                                            PhosphorIconsRegular.camera,
                                            color: t.textSecondary,
                                            size: 18,
                                          ),
                                          title: Text(
                                            primary,
                                            style: t.bodyStyle.copyWith(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: t.text,
                                            ),
                                          ),
                                          subtitle: Text(
                                            secondary,
                                            style: t.metaStyle.copyWith(
                                              fontSize: 11.5,
                                              color: t.textSecondary,
                                            ),
                                          ),
                                          trailing: IconButton(
                                            onPressed: () =>
                                                _removeCamera(serialNumber),
                                            tooltip: 'Remove',
                                            icon: PhosphorIcon(
                                              PhosphorIconsRegular.trash,
                                              size: 16,
                                              color: FfTokens.danger
                                                  .withValues(alpha: 0.85),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ],
                    ),
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
