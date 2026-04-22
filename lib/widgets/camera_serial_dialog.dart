import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../services/camera_serial_service.dart';
import 'app_compact_checkbox.dart';

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
  bool _serialNumberMode = false;

  @override
  void initState() {
    super.initState();
    _initializeCameraService();
    _updateFilteredMappings();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _initializeCameraService() async {
    await widget.cameraService.initialize();
  }

  @override
  void dispose() {
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

    // Sort based on current mode
    _filteredMappings.sort((a, b) {
      if (_serialNumberMode) {
        // In serial mode: sort by serial number first, then by name
        final serialCompare = a.key.compareTo(b.key);
        if (serialCompare != 0) return serialCompare;
        return a.value.compareTo(b.value);
      } else {
        // In name mode: sort by photographer name first, then by serial number
        final nameCompare = a.value.compareTo(b.value);
        if (nameCompare != 0) return nameCompare;
        return a.key.compareTo(b.key);
      }
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

    try {
      await widget.cameraService
          .addCameraMapping(serial, photographer, initials: initials);
      _serialController.clear();
      _photographerController.clear();
      _initialsController.clear();
      setState(() {
        _updateFilteredMappings();
      });
      _showSnackBar('Camera mapping added successfully');
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Mappings'),
        content: const Text(
            'Are you sure you want to remove all camera serial number mappings? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
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
      print('DEBUG: Starting file import...');
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
        allowMultiple: false,
      );

      print('DEBUG: File picker result: $result');

      if (result != null && result.files.single.path != null) {
        print('DEBUG: Selected file path: ${result.files.single.path}');
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        print('DEBUG: File content length: ${content.length}');

        int importedCount = 0;
        int skippedCount = 0;
        List<String> errors = [];

        final lines = content.split('\n');
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.isEmpty ||
              line.startsWith('serial#') ||
              line.startsWith('Name')) {
            continue; // Skip header lines
          }

          final parts = line.split('\t');
          if (parts.length >= 2) {
            final serialNumber = parts[0].trim();
            final photographerName = parts[1].trim();
            final initials = parts.length >= 3 ? parts[2].trim() : '';

            if (serialNumber.isNotEmpty && photographerName.isNotEmpty) {
              try {
                await widget.cameraService.addCameraMapping(
                    serialNumber, photographerName,
                    initials: initials);
                importedCount++;
              } catch (e) {
                skippedCount++;
                errors.add('Line ${i + 1}: $e');
              }
            }
          }
        }

        setState(() {
          _updateFilteredMappings();
        });

        String message = 'Imported $importedCount camera mappings';
        if (skippedCount > 0) {
          message += ', skipped $skippedCount entries';
        }

        if (errors.isNotEmpty && errors.length <= 5) {
          message += '\n\nErrors:\n${errors.join('\n')}';
        } else if (errors.length > 5) {
          message +=
              '\n\n${errors.length} errors occurred (showing first 5):\n${errors.take(5).join('\n')}';
        }

        _showSnackBar(message, isError: skippedCount > 0);
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
    int importedCount = 0;
    int skippedCount = 0;
    List<String> errors = [];

    final lines = content.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty ||
          line.startsWith('serial#') ||
          line.startsWith('Name')) {
        continue; // Skip header lines
      }

      final parts = line.split('\t');
      if (parts.length >= 2) {
        final serialNumber = parts[0].trim();
        final photographerName = parts[1].trim();
        final initials = parts.length >= 3 ? parts[2].trim() : '';

        if (serialNumber.isNotEmpty && photographerName.isNotEmpty) {
          try {
            await widget.cameraService.addCameraMapping(
                serialNumber, photographerName,
                initials: initials);
            importedCount++;
          } catch (e) {
            skippedCount++;
            errors.add('Line ${i + 1}: $e');
          }
        }
      }
    }

    setState(() {
      _updateFilteredMappings();
    });

    String message = 'Imported $importedCount camera mappings';
    if (skippedCount > 0) {
      message += ', skipped $skippedCount entries';
    }

    if (errors.isNotEmpty && errors.length <= 5) {
      message += '\n\nErrors:\n${errors.join('\n')}';
    } else if (errors.length > 5) {
      message +=
          '\n\n${errors.length} errors occurred (showing first 5):\n${errors.take(5).join('\n')}';
    }

    _showSnackBar(message, isError: skippedCount > 0);
  }

  Future<void> _detectFromCurrentImage() async {
    try {
      // This would need access to the current image metadata
      // For now, let's show a placeholder implementation
      _showSnackBar('Camera serial detection feature coming soon!',
          isError: false);

      // TODO: Implement actual detection from current image EXIF data
      // This would read the SerialNumber field from the current image
      // and populate the form fields automatically
    } catch (e) {
      _showSnackBar('Error detecting camera serial: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Camera Serial Numbers',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _serialNumberMode
                            ? Colors.blue.shade100
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _serialNumberMode
                              ? Colors.blue.shade300
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _serialNumberMode ? Icons.numbers : Icons.person,
                            size: 16,
                            color: _serialNumberMode
                                ? Colors.blue.shade700
                                : Colors.grey.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _serialNumberMode ? 'Serial Mode' : 'Name Mode',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _serialNumberMode
                                  ? Colors.blue.shade700
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    AppCompactCheckbox(
                      value: _serialNumberMode,
                      accentColor: Colors.blue.shade700,
                      onChanged: (value) {
                        setState(() {
                          _serialNumberMode = value;
                          _updateFilteredMappings();
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Manage camera serial numbers and their associated photographers for automatic byline generation.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),

            // Add new camera section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add New Camera',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _serialController,
                          decoration: const InputDecoration(
                            labelText: 'Camera Serial Number',
                            hintText: 'e.g., 1234567890',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _photographerController,
                          decoration: const InputDecoration(
                            labelText: 'Photographer Name',
                            hintText: 'e.g., Mark Blinch',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: _initialsController,
                          decoration: const InputDecoration(
                            labelText: 'Initials',
                            hintText: 'MDB',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _addCamera,
                        child: const Text('Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Search and controls
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: _serialNumberMode
                          ? 'Search by serial numbers...'
                          : 'Search cameras or photographers...',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _importFromFile,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Import'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: const Text('Paste'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _detectFromCurrentImage,
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Detect'),
                  style: TextButton.styleFrom(foregroundColor: Colors.green),
                ),
                const SizedBox(width: 8),
                if (_filteredMappings.isNotEmpty)
                  TextButton.icon(
                    onPressed: _clearAll,
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('Clear All'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Camera mappings list
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _filteredMappings.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.camera_alt_outlined,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No camera mappings yet'
                                  : 'No cameras found matching "$_searchQuery"',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            if (_searchQuery.isEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Add a camera serial number above to get started',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _filteredMappings.length,
                        itemBuilder: (context, index) {
                          final entry = _filteredMappings[index];
                          final serialNumber = entry.key;
                          final photographerName = entry.value;
                          final photographerData = widget.cameraService
                              .getPhotographerData(serialNumber);
                          final initials = photographerData?['initials'] ?? '';

                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              leading: Icon(
                                Icons.camera_alt,
                                color: Colors.grey.shade600,
                                size: 20,
                              ),
                              title: Text(
                                _serialNumberMode
                                    ? serialNumber
                                    : photographerName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: _serialNumberMode ? 14 : null,
                                  color: _serialNumberMode
                                      ? Colors.blue.shade700
                                      : null,
                                ),
                              ),
                              subtitle: Text(
                                _serialNumberMode
                                    ? (initials.isNotEmpty
                                        ? '$photographerName • $initials'
                                        : photographerName)
                                    : (initials.isNotEmpty
                                        ? 'SN: $serialNumber • $initials'
                                        : 'SN: $serialNumber'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              trailing: IconButton(
                                onPressed: () => _removeCamera(serialNumber),
                                icon: const Icon(Icons.delete_outline),
                                color: Colors.red,
                                iconSize: 18,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              tileColor: index % 2 == 0
                                  ? Colors.grey.shade50
                                  : Colors.white,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
