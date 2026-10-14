import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import '../services/camera_serial_service.dart';
import '../theme/ff_tokens.dart';
import 'app_styled_dialogs.dart';
import 'photographer_name_field.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

enum _NameSort { first, last }

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
  _NameSort _nameSort = _NameSort.last;
  bool _sortAscending = true;
  String? _editingSerial;
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
      var nameCompare = _compareNames(a.value, b.value);
      if (nameCompare == 0) {
        nameCompare = a.key.toLowerCase().compareTo(b.key.toLowerCase());
      }
      return _sortAscending ? nameCompare : -nameCompare;
    });
  }

  int _compareNames(String a, String b) {
    final primary = _nameSort == _NameSort.first
        ? _namePart(a, first: true).compareTo(_namePart(b, first: true))
        : _namePart(a, first: false).compareTo(_namePart(b, first: false));
    if (primary != 0) return primary;
    final other = _nameSort == _NameSort.first
        ? _namePart(a, first: false).compareTo(_namePart(b, first: false))
        : _namePart(a, first: true).compareTo(_namePart(b, first: true));
    if (other != 0) return other;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  /// First word, or the last word when [first] is false.
  static String _namePart(String name, {required bool first}) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    final part = first ? parts.first : parts.last;
    return part.toLowerCase();
  }

  /// Last-name sort shows the surname first: "Lahodynskyj, Andrew".
  static String _displayName(String name, {required bool lastFirst}) {
    final trimmed = name.trim();
    if (!lastFirst || trimmed.isEmpty) return trimmed;
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) return trimmed;
    final last = parts.last;
    final rest = parts.sublist(0, parts.length - 1).join(' ');
    return '$last, $rest';
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

  Future<void> _saveEdit({
    required String originalSerial,
    required String serial,
    required String name,
    required String initials,
  }) async {
    final nextSerial = serial.trim();
    final nextName = name.trim();
    final nextInitials = initials.trim();
    if (nextSerial.isEmpty || nextName.isEmpty) {
      _showSnackBar('Serial and photographer are required', isError: true);
      return;
    }
    final camera = widget.cameraService;
    final originalKey = camera.existingSerialKey(originalSerial);
    final otherKey = camera.existingSerialKey(nextSerial);
    if (otherKey != null && otherKey != originalKey) {
      final who = camera.getPhotographerForSerial(nextSerial) ?? 'another photographer';
      _showSnackBar('Serial $nextSerial is already mapped to $who', isError: true);
      return;
    }
    try {
      final data =
          originalKey == null ? null : camera.getPhotographerData(originalKey);
      final body = data?['body'] ?? '';
      if (originalKey != null && originalKey != nextSerial) {
        await camera.removeCameraMapping(originalKey);
      }
      await camera.addCameraMapping(
        nextSerial,
        nextName,
        initials: nextInitials,
        body: body,
      );
      if (!mounted) return;
      setState(() {
        _editingSerial = null;
        _updateFilteredMappings();
      });
    } catch (e) {
      _showSnackBar('Could not save that serial: $e', isError: true);
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

  Future<void> _exportList() async {
    final mappings = widget.cameraService.fullCameraMappings;
    if (mappings.isEmpty) {
      _showSnackBar('No serials to export', isError: true);
      return;
    }
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export serial list',
        fileName: 'camera_serials.txt',
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );
      if (path == null) return;
      final lines = <String>['serial#\tName\tInitials\tCamera'];
      final entries = mappings.entries.toList()
        ..sort(
          (a, b) => (a.value['name'] ?? '')
              .toLowerCase()
              .compareTo((b.value['name'] ?? '').toLowerCase()),
        );
      for (final entry in entries) {
        lines.add(
          '${entry.key}\t${entry.value['name'] ?? ''}\t${entry.value['initials'] ?? ''}\t${entry.value['body'] ?? ''}',
        );
      }
      final filePath = path.toLowerCase().endsWith('.txt') ? path : '$path.txt';
      await File(filePath).writeAsString('${lines.join('\n')}\n');
      if (!mounted) return;
      _showSnackBar('Exported ${entries.length} serials');
    } catch (e) {
      _showSnackBar('Could not export the list: $e', isError: true);
    }
  }

  Future<void> _processImportContent(String content) async {
    final rows = <({String serial, String name, String initials})>[];
    final bodies = <String, String>{};
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
      final body = parts.length >= 4 ? parts[3].trim() : '';
      if (serialNumber.isEmpty || photographerName.isEmpty) continue;
      rows.add((
        serial: serialNumber,
        name: photographerName,
        initials: initials,
      ));
      if (body.isNotEmpty) bodies[serialNumber] = body;
    }

    if (rows.isEmpty) {
      _showSnackBar('No valid camera rows found to import', isError: true);
      return;
    }

    try {
      final result = await widget.cameraService.mergeMappings(rows);
      if (bodies.isNotEmpty) {
        await widget.cameraService.rememberCameraBodies(bodies);
      }
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

  Widget _searchField(FfTokens t) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: t.divider),
    );
    return SizedBox(
      width: 120,
      height: 26,
      child: TextField(
        controller: _searchController,
        style: t.bodyStyle.copyWith(fontSize: 12, height: 1),
        cursorColor: t.accent,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: t.sunken,
          prefixIcon: PhosphorIcon(
            PhosphorIconsRegular.magnifyingGlass,
            size: 12,
            color: t.textTertiary,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 28,
            minHeight: 26,
          ),
          contentPadding: EdgeInsets.zero,
          border: border,
          enabledBorder: border,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: t.accent, width: 1.2),
          ),
        ),
      ),
    );
  }

  Widget _nameSortControl(FfTokens t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.divider),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sortSegment(t, 'First', 'first name', _NameSort.first),
            Container(width: 1, height: 22, color: t.divider),
            _sortSegment(t, 'Last', 'last name', _NameSort.last),
          ],
        ),
      ),
    );
  }

  Widget _sortSegment(
    FfTokens t,
    String label,
    String fullName,
    _NameSort sort,
  ) {
    final selected = _nameSort == sort;
    final direction = _sortAscending ? 'A to Z' : 'Z to A';
    return Tooltip(
      message: selected
          ? 'Sorted by $fullName, $direction. Click to reverse.'
          : 'Sort by $fullName',
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: () {
          setState(() {
            if (selected) {
              _sortAscending = !_sortAscending;
            } else {
              _nameSort = sort;
              _sortAscending = true;
            }
            _updateFilteredMappings();
          });
        },
        child: ColoredBox(
          color: selected ? t.sunken : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: t.metaStyle.copyWith(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? t.text : t.textTertiary,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 4),
                  PhosphorIcon(
                    _sortAscending
                        ? PhosphorIconsRegular.arrowUp
                        : PhosphorIconsRegular.arrowDown,
                    size: 11,
                    color: t.text,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quietAction({
    required FfTokens t,
    required String label,
    required VoidCallback onPressed,
    bool danger = false,
  }) {
    final color = danger ? FfTokens.danger : t.textSecondary;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: t.metaStyle.copyWith(
          color: color,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _columnLabel(FfTokens t, String text) {
    return Text(
      text,
      style: t.metaStyle.copyWith(
        fontSize: 11,
        color: t.textTertiary,
        fontWeight: FontWeight.w500,
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
          width: 960,
          height: 560,
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
                              'Serial numbers',
                              style: t.labelStyle.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Photographer bylines from camera serials. Saved with your account.',
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
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _labeledAddField(
                              t,
                              label: 'Serial',
                              width: 168,
                              controller: _serialController,
                            ),
                            const SizedBox(width: 8),
                            _labeledAddField(
                              t,
                              label: 'Photographer',
                              width: 168,
                              controller: _photographerController,
                              names: widget.cameraService
                                  .getUniquePhotographerNames(),
                              onNameSelected: _applyPhotographerInitials,
                            ),
                            const SizedBox(width: 8),
                            _labeledAddField(
                              t,
                              label: 'Initials',
                              width: 88,
                              controller: _initialsController,
                            ),
                            const SizedBox(width: 8),
                            _addButton(t),
                            const Spacer(),
                            _quietAction(
                              t: t,
                              label: 'Import',
                              onPressed: _importFromFile,
                            ),
                            _quietAction(
                              t: t,
                              label: 'Export list',
                              onPressed: _exportList,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _listHeader(t),
                        Divider(height: 1, color: t.divider),
                        Expanded(
                          child: _filteredMappings.isEmpty
                              ? Center(
                                  child: Text(
                                    _searchQuery.isEmpty
                                        ? 'No serials yet'
                                        : 'No matches',
                                    style: t.metaStyle.copyWith(
                                      color: t.textTertiary,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _filteredMappings.length,
                                  separatorBuilder: (_, __) => Divider(
                                    height: 1,
                                    color: t.divider,
                                  ),
                                  itemBuilder: (context, index) {
                                    final entry = _filteredMappings[index];
                                    final serialNumber = entry.key;
                                    final photographerName = entry.value;
                                    final data = widget.cameraService
                                        .getPhotographerData(serialNumber);
                                    final initials = data?['initials'] ?? '';
                                    final body = data?['body'] ?? '';
                                    if (_editingSerial == serialNumber) {
                                      return _SerialEditRow(
                                        serial: serialNumber,
                                        name: photographerName,
                                        initials: initials,
                                        onCancel: () => setState(
                                          () => _editingSerial = null,
                                        ),
                                        onSave: (serial, name, initials) =>
                                            _saveEdit(
                                          originalSerial: serialNumber,
                                          serial: serial,
                                          name: name,
                                          initials: initials,
                                        ),
                                      );
                                    }
                                    return _SerialMappingRow(
                                      name: _displayName(
                                        photographerName,
                                        lastFirst: _nameSort == _NameSort.last,
                                      ),
                                      serial: serialNumber,
                                      body: body,
                                      initials: initials,
                                      onEdit: () => setState(
                                        () => _editingSerial = serialNumber,
                                      ),
                                      onRemove: () =>
                                          _removeCamera(serialNumber),
                                    );
                                  },
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

  static const double _addControlHeight = 32;

  InputDecoration _bareFieldDecoration() {
    return const InputDecoration(
      isCollapsed: true,
      isDense: true,
      border: InputBorder.none,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.standard,
    );
  }

  Widget _addControlShell({
    required FfTokens t,
    required Widget child,
    Gradient? gradient,
    Color? fill,
  }) {
    return SizedBox(
      height: _addControlHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: gradient == null ? (fill ?? t.sunken) : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(FfTokens.radiusChip),
          border: Border.all(color: t.divider),
        ),
        child: child,
      ),
    );
  }

  Widget _addButton(FfTokens t) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _addCamera,
        child: _addControlShell(
          t: t,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF243848),
              Color(0xFF15242E),
              Color(0xFF0E181F),
            ],
            stops: [0.0, 0.45, 1.0],
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Text(
                'Add',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _labeledAddField(
    FfTokens t, {
    required String label,
    required double width,
    required TextEditingController controller,
    List<String> names = const [],
    ValueChanged<String>? onNameSelected,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _columnLabel(t, label),
          const SizedBox(height: 6),
          _addInput(
            t,
            controller: controller,
            names: names,
            onNameSelected: onNameSelected,
          ),
        ],
      ),
    );
  }

  Widget _addInput(
    FfTokens t, {
    required TextEditingController controller,
    List<String> names = const [],
    ValueChanged<String>? onNameSelected,
  }) {
    final style = t.bodyStyle.copyWith(fontSize: 13);
    final field = names.isEmpty
        ? TextField(
            controller: controller,
            maxLines: 1,
            style: style,
            cursorColor: t.accent,
            textAlignVertical: TextAlignVertical.center,
            decoration: _bareFieldDecoration(),
            onSubmitted: (_) => _addCamera(),
          )
        : PhotographerNameField(
            controller: controller,
            names: names,
            onSelected: onNameSelected,
            decoration: _bareFieldDecoration(),
            style: style,
          );
    return _addControlShell(
      t: t,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: field,
        ),
      ),
    );
  }

  Widget _listHeader(FfTokens t) {
    final style = t.metaStyle.copyWith(
      fontSize: 11,
      color: t.textTertiary,
      fontWeight: FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 72, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: Row(
              children: [
                Text('Photographer', style: style),
                const SizedBox(width: 8),
                _nameSortControl(t),
                const SizedBox(width: 8),
                _searchField(t),
              ],
            ),
          ),
          Expanded(flex: 2, child: Text('Serial', style: style)),
          SizedBox(width: 220, child: Text('Camera', style: style)),
          SizedBox(width: 64, child: Text('Initials', style: style)),
        ],
      ),
    );
  }
}

class _SerialMappingRow extends StatelessWidget {
  const _SerialMappingRow({
    required this.name,
    required this.serial,
    this.body = '',
    required this.initials,
    required this.onEdit,
    required this.onRemove,
  });

  final String name;
  final String serial;
  final String body;
  final String initials;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final value = t.bodyStyle.copyWith(fontSize: 13, color: t.text);
    final muted = t.metaStyle.copyWith(fontSize: 12, color: t.textSecondary);
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              name.isEmpty ? '—' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: value,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              serial,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted.copyWith(fontFamily: FfTokens.monoFamily),
            ),
          ),
          SizedBox(
            width: 220,
            child: Text(
              body.isEmpty ? '—' : body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              initials.isEmpty ? '—' : initials,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ),
          IconButton(
            onPressed: onEdit,
            tooltip: 'Edit',
            visualDensity: VisualDensity.compact,
            icon: PhosphorIcon(
              PhosphorIconsRegular.pencilSimple,
              size: 14,
              color: t.textTertiary,
            ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            icon: PhosphorIcon(
              PhosphorIconsRegular.x,
              size: 14,
              color: t.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SerialEditRow extends StatefulWidget {
  const _SerialEditRow({
    required this.serial,
    required this.name,
    required this.initials,
    required this.onSave,
    required this.onCancel,
  });

  final String serial;
  final String name;
  final String initials;
  final void Function(String serial, String name, String initials) onSave;
  final VoidCallback onCancel;

  @override
  State<_SerialEditRow> createState() => _SerialEditRowState();
}

class _SerialEditRowState extends State<_SerialEditRow> {
  late final TextEditingController _serial =
      TextEditingController(text: widget.serial);
  late final TextEditingController _name =
      TextEditingController(text: widget.name);
  late final TextEditingController _initials =
      TextEditingController(text: widget.initials);

  @override
  void dispose() {
    _serial.dispose();
    _name.dispose();
    _initials.dispose();
    super.dispose();
  }

  InputDecoration _decoration(FfTokens t) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(FfTokens.radiusChip),
      borderSide: BorderSide(color: t.divider),
    );
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: t.sunken,
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        borderSide: BorderSide(color: t.accent, width: 1.2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    );
  }

  void _save() {
    widget.onSave(_serial.text, _name.text, _initials.text);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final style = t.bodyStyle.copyWith(fontSize: 13, height: 1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: TextField(
              controller: _name,
              autofocus: true,
              style: style,
              cursorColor: t.accent,
              textAlignVertical: TextAlignVertical.center,
              decoration: _decoration(t),
              onSubmitted: (_) => _save(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _serial,
              style: style.copyWith(fontFamily: FfTokens.monoFamily),
              cursorColor: t.accent,
              textAlignVertical: TextAlignVertical.center,
              decoration: _decoration(t),
              onSubmitted: (_) => _save(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: TextField(
              controller: _initials,
              style: style,
              cursorColor: t.accent,
              textCapitalization: TextCapitalization.characters,
              textAlignVertical: TextAlignVertical.center,
              decoration: _decoration(t),
              onSubmitted: (_) => _save(),
            ),
          ),
          IconButton(
            onPressed: _save,
            tooltip: 'Save',
            visualDensity: VisualDensity.compact,
            icon: PhosphorIcon(
              PhosphorIconsRegular.check,
              size: 14,
              color: t.accent,
            ),
          ),
          IconButton(
            onPressed: widget.onCancel,
            tooltip: 'Cancel',
            visualDensity: VisualDensity.compact,
            icon: PhosphorIcon(
              PhosphorIconsRegular.x,
              size: 14,
              color: t.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
