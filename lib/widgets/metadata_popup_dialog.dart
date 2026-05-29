import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../caption_style/caption_template.dart';
import '../services/iptc_template_apply_service.dart';
import '../services/iptc_template_import_service.dart';
import '../utils/exiftool_helper.dart';
import 'oriented_file_preview.dart';
import 'startup_iptc_template_panel.dart';
import '../helpers.dart';

class MetadataPopupDialog extends StatefulWidget {
  final Map<String, dynamic>? metadata;
  final Function(Map<String, dynamic>) onMetadataUpdated;
  final String? imagePath;
  final VoidCallback? onPreviousImage;
  final VoidCallback? onNextImage;
  final VoidCallback? onCopyMetadata;
  final VoidCallback? onPasteMetadata;
  final WireStyle wireStyle;
  // Optional: request parent to change image without closing dialog.
  // Should return a map containing 'path' (String) and 'metadata' (Map<String,dynamic>).
  final Future<Map<String, dynamic>> Function(int delta)? onRequestImageChange;

  const MetadataPopupDialog({
    super.key,
    required this.metadata,
    required this.onMetadataUpdated,
    this.imagePath,
    this.onPreviousImage,
    this.onNextImage,
    this.onCopyMetadata,
    this.onPasteMetadata,
    this.onRequestImageChange,
    this.wireStyle = WireStyle.getty,
  });

  @override
  State<MetadataPopupDialog> createState() => _MetadataPopupDialogState();
}

class _MetadataPopupDialogState extends State<MetadataPopupDialog> {
  Map<String, dynamic>? currentMetadata;
  Map<String, dynamic>? exifData;
  // Track whether we've ever successfully loaded EXIF in this dialog session
  bool _hasEverLoadedExif = false;
  String? _currentImagePath;
  Map<String, String> _panelValues = {};
  int _panelRevision = 0;

  @override
  void initState() {
    super.initState();
    currentMetadata = Map<String, dynamic>.from(widget.metadata ?? {});
    _currentImagePath = widget.imagePath;
    _normalizeMetadataForUi();
    _syncPanelValuesFromMetadata();

    // Load EXIF data for the image
    _loadExifData();
  }

  void _syncPanelValuesFromMetadata() {
    _panelValues = IptcTemplateImportService.panelValuesFromExiftool(
      Map<String, dynamic>.from(currentMetadata ?? {}),
    );
    _panelRevision++;
  }

  void _onPanelValueChanged(String storageKey, String value) {
    setState(() {
      if (value.isEmpty) {
        _panelValues.remove(storageKey);
      } else {
        _panelValues[storageKey] = value;
      }
      currentMetadata = IptcTemplateApplyService.exiftoolMapFromPanelValues(
        _panelValues,
        mergeInto: currentMetadata,
      );
    });
  }

  // Load EXIF data from the image file
  Future<void> _loadExifData({String? path}) async {
    final String? targetPath = path ?? _currentImagePath ?? widget.imagePath;
    if (targetPath == null) return;

    try {
      // Import ExifToolHelper
      final exiftool = await ExiftoolHelper.run([
        '-j',
        '-Model',
        '-Make',
        '-ShutterSpeed',
        '-ExposureTime',
        '-FNumber',
        '-ISO',
        '-FocalLength',
        '-LensID',
        '-LensModel',
        '-DateTimeOriginal',
        '-SubSecTimeOriginal',
        '-SerialNumber',
        targetPath,
      ]);

      if (exiftool.exitCode == 0) {
        final List data = jsonDecode(exiftool.stdoutText);
        if (data.isNotEmpty) {
          final exifDataMap = data.first as Map<String, dynamic>;
          print('DEBUG: EXIF data loaded: $exifDataMap');
          setState(() {
            exifData = exifDataMap;
            _hasEverLoadedExif = true;
          });
        }
      } else {
        print('ExifTool failed with exit code: ${exiftool.exitCode}');
        // Don't clear exifData on failure - keep previous data
      }
    } catch (e) {
      print('Error loading EXIF data: $e');
    }
  }

  void _handleMetadataUpdated(Map<String, dynamic>? metadata) {
    if (metadata != null) {
      setState(() {
        currentMetadata = metadata;
        _normalizeMetadataForUi();
        _syncPanelValuesFromMetadata();
      });
    }
  }

  void _saveChanges() async {
    // Use the same method as Next/Previous buttons to ensure consistency
    final Map<String, dynamic> outgoing = _buildOutgoingMetadataFromState();

    print(
        '🔥 POPUP SAVE START: Keywords in outgoing data: "${outgoing['IPTC:Keywords']}"');
    print(
        '🔥 POPUP SAVE START: Current metadata IPTC:Keywords: "${currentMetadata?['IPTC:Keywords']}"');
    print(
        '🔥 POPUP SAVE START: Current metadata KeywordsTest: "${currentMetadata?['KeywordsTest']}"');
    print('🔥 POPUP SAVE START: Subject in outgoing: "${outgoing['Subject']}"');
    print('🔥 POPUP SAVE START: All outgoing keys: ${outgoing.keys.toList()}');

    try {
      // FIRST: Actually save to file using ExifTool
      await _saveMetadataToFile(outgoing);

      // THEN: Update the app state
      widget.onMetadataUpdated(outgoing);

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Metadata saved successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      // Update our local metadata to match what was saved
      currentMetadata = Map<String, dynamic>.from(outgoing);

      print('🔥 POPUP SAVE SUCCESS: Save completed, closing dialog');

      // Close the dialog
      Navigator.of(context).pop();
    } catch (e) {
      print('🔥 POPUP SAVE ERROR: $e');
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving metadata: $e'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // Build an outgoing metadata map that reflects current panel values.
  Map<String, dynamic> _buildOutgoingMetadataFromState() {
    return IptcTemplateApplyService.exiftoolMapFromPanelValues(
      _panelValues,
      mergeInto: currentMetadata,
    );
  }

  // Save metadata to the image file using shared IPTC apply service.
  Future<void> _saveMetadataToFile(Map<String, dynamic> metadata) async {
    final imagePath = _currentImagePath ?? widget.imagePath;
    if (imagePath == null) return;

    final result = await IptcTemplateApplyService.applyToImage(
      imagePath,
      _panelValues,
      skipInAppGenerated: false,
      existingMetadata: metadata,
    );

    if (!result.success) {
      throw Exception('Failed to save IPTC metadata to file');
    }
  }

  void _discardChanges() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MetadataPopupDialog oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.imagePath != widget.imagePath) {
      _currentImagePath = widget.imagePath;
      _loadExifData(path: _currentImagePath);
    }

    if (oldWidget.metadata != widget.metadata) {
      currentMetadata = Map<String, dynamic>.from(widget.metadata ?? {});
      _normalizeMetadataForUi();
      _syncPanelValuesFromMetadata();
      if (mounted) setState(() {});
    }
  }

  // Ensure UI-only fields like SupplementalCategories1/2/3 are populated
  void _normalizeMetadataForUi() {
    if (currentMetadata == null) return;

    print('DEBUG: _normalizeMetadataForUi called');
    print(
        'DEBUG: Available supplemental category fields: SupplementalCategories=${currentMetadata!['SupplementalCategories']}, IPTC:SupplementalCategories=${currentMetadata!['IPTC:SupplementalCategories']}, XMP:SupplementalCategories=${currentMetadata!['XMP:SupplementalCategories']}');

    // Preserve split fields if combined IPTC/XMP parse yields nothing (e.g. only
    // in-memory edits, or empty XMP shadowing IPTC before we skipped empties).
    final String prev1 =
        currentMetadata!['SupplementalCategories1']?.toString() ?? '';
    final String prev2 =
        currentMetadata!['SupplementalCategories2']?.toString() ?? '';
    final String prev3 =
        currentMetadata!['SupplementalCategories3']?.toString() ?? '';

    // Clear existing values first
    currentMetadata!.remove('SupplementalCategories1');
    currentMetadata!.remove('SupplementalCategories2');
    currentMetadata!.remove('SupplementalCategories3');

    final String sourceField =
        sourceKeyForSupplementalCategories(currentMetadata!) ?? 'none';
    final dynamic supp = combinedSupplementalCategoriesValue(currentMetadata!);

    print(
        'DEBUG: Found supplemental categories: $supp (${supp.runtimeType}) from field: $sourceField');

    List<String> parts = [];
    if (supp is List) {
      print('DEBUG: Processing as List');
      parts = supp
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else if (supp is String && supp.isNotEmpty) {
      print('DEBUG: Processing as String: "$supp"');
      String cleanSupp = supp.trim();

      // Remove brackets if present (e.g., "[SPO, BBN, BBA]" -> "SPO, BBN, BBA")
      if (cleanSupp.startsWith('[') && cleanSupp.endsWith(']')) {
        cleanSupp = cleanSupp.substring(1, cleanSupp.length - 1);
        print('DEBUG: Removed brackets: "$cleanSupp"');
      }

      // Split by comma or semicolon; trim spaces and filter empty
      if (cleanSupp.contains(',')) {
        parts = cleanSupp
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      } else if (cleanSupp.contains(';')) {
        parts = cleanSupp
            .split(';')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      } else if (cleanSupp.isNotEmpty) {
        // Single category
        parts = [cleanSupp];
      }
      print('DEBUG: Split into parts: $parts');
    }

    // Assign to UI keys
    if (parts.isNotEmpty) {
      currentMetadata!['SupplementalCategories1'] = parts[0];
      print('DEBUG: Set SupplementalCategories1 = "${parts[0]}"');
    }
    if (parts.length > 1) {
      currentMetadata!['SupplementalCategories2'] = parts[1];
      print('DEBUG: Set SupplementalCategories2 = "${parts[1]}"');
    }
    if (parts.length > 2) {
      currentMetadata!['SupplementalCategories3'] = parts[2];
      print('DEBUG: Set SupplementalCategories3 = "${parts[2]}"');
    }

    if (parts.isEmpty) {
      if (prev1.isNotEmpty) {
        currentMetadata!['SupplementalCategories1'] = prev1;
      }
      if (prev2.isNotEmpty) {
        currentMetadata!['SupplementalCategories2'] = prev2;
      }
      if (prev3.isNotEmpty) {
        currentMetadata!['SupplementalCategories3'] = prev3;
      }
    }

    print(
        'DEBUG: Final supplemental categories: 1="${currentMetadata!['SupplementalCategories1']}", 2="${currentMetadata!['SupplementalCategories2']}", 3="${currentMetadata!['SupplementalCategories3']}"');

    // Force a setState to ensure UI updates
    if (mounted) {
      setState(() {});
    }
  }

  // Copy all metadata fields except date and time
  void _copyMetadata() {
    if (currentMetadata == null) return;

    // Create a copy of current metadata excluding date/time fields
    final Map<String, dynamic> metadataToCopy =
        Map<String, dynamic>.from(currentMetadata!);

    // Remove date and time fields
    metadataToCopy.remove('Date');
    metadataToCopy.remove('Time');
    metadataToCopy.remove('DateTimeOriginal');
    metadataToCopy.remove('CreateDate');
    metadataToCopy.remove('ModifyDate');
    metadataToCopy.remove('FileModifyDate');

    // Clean up duplicate fields to prevent future issues
    // Only keep the primary fields for caption and personality
    if (metadataToCopy.containsKey('IPTC:Description')) {
      metadataToCopy.remove('Description');
      metadataToCopy.remove('Caption-Abstract');
      metadataToCopy.remove('IPTC:Caption-Abstract');
      metadataToCopy.remove('ImageDescription');
    }

    if (metadataToCopy.containsKey('XMP-getty:Personality')) {
      metadataToCopy.remove('Personality');
    }

    // Convert to JSON string for clipboard
    final metadataJson = jsonEncode(metadataToCopy);
    Clipboard.setData(ClipboardData(text: metadataJson));

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Metadata copied to clipboard (excluding date/time)'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // Paste metadata from clipboard to all fields
  void _pasteMetadata() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData?.text == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No data found in clipboard'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      final pastedMetadata =
          jsonDecode(clipboardData!.text!) as Map<String, dynamic>;

      // Clean up any duplicate fields in the pasted data
      if (pastedMetadata.containsKey('IPTC:Description')) {
        pastedMetadata.remove('Description');
        pastedMetadata.remove('Caption-Abstract');
        pastedMetadata.remove('IPTC:Caption-Abstract');
        pastedMetadata.remove('ImageDescription');
      }

      if (pastedMetadata.containsKey('XMP-getty:Personality')) {
        pastedMetadata.remove('Personality');
      }

      // Update current metadata with pasted data
      setState(() {
        currentMetadata = Map<String, dynamic>.from(currentMetadata ?? {});
        currentMetadata!.addAll(pastedMetadata);
      });

      // Normalize UI fields
      _normalizeMetadataForUi();
      _syncPanelValuesFromMetadata();

      // Notify parent of changes
      _handleMetadataUpdated(currentMetadata);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Metadata pasted successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // Try to provide more helpful error messages
      String errorMessage = 'Invalid metadata format in clipboard';
      if (e.toString().contains('Unexpected character')) {
        errorMessage =
            'Clipboard contains invalid data. Try copying fresh metadata.';
      } else if (e.toString().contains('FormatException')) {
        errorMessage =
            'Clipboard data is corrupted. Try copying fresh metadata.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Clear Clipboard',
            textColor: Colors.white,
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: ''));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Clipboard cleared'),
                  backgroundColor: Colors.blue,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ),
      );
    }
  }

  Widget _buildIptcFieldsPanel() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD0D0D0), width: 0.7),
        borderRadius: BorderRadius.circular(4),
        color: Colors.white,
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: StartupIptcTemplatePanel(
          fieldsOnly: true,
          selectedWire: widget.wireStyle,
          wireLabels: const {},
          values: _panelValues,
          iptcApplyMode: IptcApplyMode.none,
          onValueChanged: _onPanelValueChanged,
          templateRevision: _panelRevision,
        ),
      ),
    );
  }

  Widget _buildExifRow(String label, String exifKey) {
    // Get the actual EXIF value from the loaded data. Avoid flicker by not
    // showing 'N/A' while switching images if we have previous EXIF.
    String value = _hasEverLoadedExif ? 'N/A' : '';

    if (exifData != null) {
      // Handle special composite fields
      if (exifKey == 'Camera') {
        // Combine Make, Model, and Serial Number like in picture preview
        final make = exifData!['Make']?.toString() ?? '';
        final model = exifData!['Model']?.toString() ?? '';
        final serialNumber = exifData!['SerialNumber']?.toString() ?? '';

        if (make.isNotEmpty && model.isNotEmpty) {
          if (serialNumber.isNotEmpty) {
            value = '$make $model • SN: $serialNumber';
          } else {
            value = '$make $model'.trim();
          }
        } else if (make.isNotEmpty) {
          value = make;
        } else if (model.isNotEmpty) {
          value = model;
        }
        return _buildExifRowDisplay(label, value);
      } else if (exifKey == 'Settings') {
        // Combine Shutter Speed and Aperture like in picture preview
        final shutterSpeed = exifData!['ShutterSpeed']?.toString() ??
            exifData!['ExposureTime']?.toString() ??
            '';
        final fNumber = exifData!['FNumber']?.toString() ?? '';

        if (shutterSpeed.isNotEmpty && fNumber.isNotEmpty) {
          // Format shutter speed
          String formattedShutter = shutterSpeed;
          if (shutterSpeed.contains('/')) {
            try {
              final parts = shutterSpeed.split('/');
              if (parts.length == 2) {
                final num = int.parse(parts[0]);
                final den = int.parse(parts[1]);
                // Convert to ordinal format like "1/1000th"
                if (num == 1 && den == 1) {
                  formattedShutter = '1 second';
                } else if (den == 1) {
                  formattedShutter = '${num} seconds';
                } else if (den == 2) {
                  formattedShutter = '${num}/2nd';
                } else if (den == 3) {
                  formattedShutter = '${num}/3rd';
                } else if (den >= 4) {
                  formattedShutter = '${num}/${den}th';
                }
              }
            } catch (e) {
              // Keep original value if parsing fails
            }
          }
          // Format aperture
          String formattedAperture = fNumber;
          if (fNumber.contains('/')) {
            try {
              final parts = fNumber.split('/');
              if (parts.length == 2) {
                final num = double.parse(parts[0]);
                final den = double.parse(parts[1]);
                formattedAperture = 'f/${(num / den).toStringAsFixed(1)}';
              }
            } catch (e) {
              // Keep original value if parsing fails
            }
          }
          value = '$formattedShutter @ $formattedAperture';
        } else if (shutterSpeed.isNotEmpty) {
          value = shutterSpeed;
        } else if (fNumber.isNotEmpty) {
          value = fNumber;
        }
        return _buildExifRowDisplay(label, value);
      } else if (exifKey == 'Lens') {
        // Handle lens information - prefer LensModel, then LensID
        final lensModel = exifData!['LensModel']?.toString() ?? '';
        final lensId = exifData!['LensID']?.toString() ?? '';
        if (lensModel.isNotEmpty) {
          value = lensModel;
        } else if (lensId.isNotEmpty) {
          value = lensId;
        }
        return _buildExifRowDisplay(label, value);
      } else {
        // Handle regular EXIF fields
        final exifValue = exifData![exifKey];
        if (exifValue != null) {
          value = exifValue.toString();

          // Format specific EXIF values for better display
          if (exifKey == 'DateTimeOriginal') {
            // Format date/time for display with milliseconds
            try {
              final subSecTime = exifData!['SubSecTimeOriginal']?.toString();
              final dt = _parseExifDateTime(value, subSecTime);
              final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
              final minute = dt.minute.toString().padLeft(2, '0');
              final second = dt.second.toString().padLeft(2, '0');
              final millisecond = dt.millisecond.toString().padLeft(3, '0');
              final ampm = dt.hour >= 12 ? 'PM' : 'AM';
              value =
                  '${dt.month}/${dt.day}/${dt.year} $hour:$minute:$second.$millisecond $ampm';
            } catch (e) {
              // Keep original value if parsing fails
            }
          } else if (exifKey == 'FocalLength') {
            // Remove decimal from focal length
            if (value.contains('.')) {
              final parts = value.split('.');
              if (parts.length == 2 && parts[1] == '0') {
                value = '${parts[0]} mm';
              } else {
                value = value.replaceAll('.0 mm', ' mm');
              }
            }
          }
        }
        return _buildExifRowDisplay(label, value);
      }
    }

    // If we never had EXIF yet and value would be N/A, render empty to avoid flicker
    if (!_hasEverLoadedExif && (value == 'N/A' || value.isEmpty)) {
      return const SizedBox.shrink();
    }
    return _buildExifRowDisplay(label, value);
  }

  Widget _buildExifRowDisplay(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Parse EXIF DateTime with support for milliseconds
  DateTime _parseExifDateTime(String dateStr, [String? subSecTime]) {
    // Handle EXIF date format: YYYY:MM:DD HH:MM:SS or YYYY:MM:DD HH:MM:SS.sss
    // Replace colons in date part with dashes for ISO format
    String isoStr = dateStr.replaceFirst(':', '-').replaceFirst(':', '-');

    // Check if milliseconds are present in the main date string
    if (isoStr.contains('.')) {
      // Already has milliseconds, parse directly
      return DateTime.parse(isoStr);
    } else if (subSecTime != null && subSecTime.isNotEmpty) {
      // Combine DateTimeOriginal with SubSecTimeOriginal for milliseconds
      // SubSecTimeOriginal is typically in format like "123" (milliseconds) or "1234" (microseconds)
      int milliseconds = 0;
      try {
        final subSec = int.parse(subSecTime);
        if (subSecTime.length <= 3) {
          // Direct milliseconds
          milliseconds = subSec;
        } else if (subSecTime.length == 4) {
          // Microseconds, convert to milliseconds
          milliseconds = subSec ~/ 10;
        } else if (subSecTime.length == 6) {
          // Nanoseconds, convert to milliseconds
          milliseconds = subSec ~/ 1000000;
        }
      } catch (e) {
        print('Error parsing SubSecTimeOriginal: $e');
      }

      // Parse the base datetime and add milliseconds
      final baseDateTime = DateTime.parse(isoStr);
      return DateTime(
        baseDateTime.year,
        baseDateTime.month,
        baseDateTime.day,
        baseDateTime.hour,
        baseDateTime.minute,
        baseDateTime.second,
        milliseconds,
      );
    } else {
      // No milliseconds, parse and return with 0 milliseconds
      return DateTime.parse(isoStr);
    }
  }

  String _formatDateForDisplay() {
    if (exifData == null || exifData!['DateTimeOriginal'] == null) return '';

    try {
      final dateTimeStr = exifData!['DateTimeOriginal'].toString();
      final subSecTime = exifData!['SubSecTimeOriginal']?.toString();
      final dt = _parseExifDateTime(dateTimeStr, subSecTime);

      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];

      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (e) {
      return '';
    }
  }

  String _formatTimeForDisplay() {
    if (exifData == null || exifData!['DateTimeOriginal'] == null) return '';

    try {
      final dateTimeStr = exifData!['DateTimeOriginal'].toString();
      final subSecTime = exifData!['SubSecTimeOriginal']?.toString();
      final dt = _parseExifDateTime(dateTimeStr, subSecTime);
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final second = dt.second.toString().padLeft(2, '0');
      final millisecond = dt.millisecond.toString().padLeft(3, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute:$second.$millisecond $ampm';
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.7,
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_note, color: Colors.black87),
                  const SizedBox(width: 12),
                  const Text(
                    'Edit IPTC Metadata',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.black87),
                    tooltip: 'Close',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Image preview and metadata in a row
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left side - Image preview with EXIF data
                  if ((_currentImagePath ?? widget.imagePath) != null)
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Container(
                        width: 600,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border:
                              Border.all(color: Colors.grey.shade400, width: 1),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 568,
                                height: 400,
                                child: OrientedFilePreview(
                                  key: ValueKey(
                                      _currentImagePath ?? widget.imagePath),
                                  path: _currentImagePath ?? widget.imagePath!,
                                  fit: BoxFit.contain,
                                  cacheWidth: 1200,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),

                            // Navigation and utility buttons
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Previous button (left)
                                GestureDetector(
                                  onTap: () async {
                                    // Save current metadata before moving to previous image
                                    final outgoing =
                                        _buildOutgoingMetadataFromState();
                                    widget.onMetadataUpdated(outgoing);

                                    if (widget.onRequestImageChange != null) {
                                      // Ask parent to move -1 and return new path/metadata
                                      try {
                                        final result = await widget
                                            .onRequestImageChange!(-1);
                                        // Update without animation to prevent flashing
                                        _currentImagePath =
                                            (result['path'] as String?);
                                        currentMetadata =
                                            Map<String, dynamic>.from(
                                                (result['metadata'] ?? {})
                                                    as Map);
                                        _normalizeMetadataForUi(); // Split supplemental categories
                                        _syncPanelValuesFromMetadata();
                                        setState(() {});
                                        _loadExifData(path: _currentImagePath);
                                      } catch (_) {}
                                    } else if (widget.onPreviousImage != null) {
                                      print(
                                          'DEBUG: Calling widget.onPreviousImage from popup');
                                      widget.onPreviousImage!();
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: Colors.grey.shade300),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Prev',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Copy and Paste buttons grouped in the middle
                                Row(
                                  children: [
                                    // Copy button
                                    GestureDetector(
                                      onTap: _copyMetadata,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: Colors.grey.shade300),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Copy',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(width: 12),

                                    // Paste button
                                    GestureDetector(
                                      onTap: _pasteMetadata,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: Colors.grey.shade300),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Paste',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // Next button (right)
                                GestureDetector(
                                  onTap: () async {
                                    // Save current metadata before moving to next image
                                    final outgoing =
                                        _buildOutgoingMetadataFromState();
                                    widget.onMetadataUpdated(outgoing);

                                    if (widget.onRequestImageChange != null) {
                                      try {
                                        final result = await widget
                                            .onRequestImageChange!(1);
                                        // Update without animation to prevent flashing
                                        _currentImagePath =
                                            (result['path'] as String?);
                                        currentMetadata =
                                            Map<String, dynamic>.from(
                                                (result['metadata'] ?? {})
                                                    as Map);
                                        _normalizeMetadataForUi(); // Split supplemental categories
                                        _syncPanelValuesFromMetadata();
                                        setState(() {});
                                        _loadExifData(path: _currentImagePath);
                                      } catch (_) {}
                                    } else if (widget.onNextImage != null) {
                                      print(
                                          'DEBUG: Calling widget.onNextImage from popup');
                                      widget.onNextImage!();
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: Colors.grey.shade300),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Next',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // Divider under buttons
                            const SizedBox(height: 6),
                            Container(
                              height: 1,
                              width: double.infinity,
                              color: Colors.grey.shade300,
                            ),

                            const SizedBox(height: 16),
                            // EXIF data section
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  RichText(
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: (_currentImagePath ??
                                                      widget.imagePath) !=
                                                  null
                                              ? (_currentImagePath ??
                                                      widget.imagePath)!
                                                  .split('/')
                                                  .last
                                              : 'Image',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                        TextSpan(
                                          text:
                                              ' • ${_formatDateForDisplay()} • ${_formatTimeForDisplay()}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w400,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildExifRow('Settings', 'Settings'),
                                  _buildExifRow('ISO', 'ISO'),
                                  _buildExifRow('Focal Length', 'FocalLength'),
                                  _buildExifRow('Camera', 'Camera'),
                                  _buildExifRow('Lens', 'Lens'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Right side - Metadata widget with custom two-column layout
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Container(
                        height: double.infinity,
                        child: _buildIptcFieldsPanel(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Footer with action buttons
            Container(
              padding: const EdgeInsets.only(
                  left: 16, right: 16, top: 16, bottom: 0),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: _discardChanges,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () {
                      _saveChanges();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Save Changes',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
