import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:extended_image/extended_image.dart';
import '../utils/exiftool_helper.dart';
import '../helpers.dart';

class MetadataPopupDialog extends StatefulWidget {
  final Map<String, dynamic>? metadata;
  final Function(Map<String, dynamic>) onMetadataUpdated;
  final String? imagePath;
  final VoidCallback? onPreviousImage;
  final VoidCallback? onNextImage;
  final VoidCallback? onCopyMetadata;
  final VoidCallback? onPasteMetadata;
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

  // Controllers for caption and personality fields
  late TextEditingController captionController;
  late TextEditingController personalityController;

  // Cache for field controllers to prevent cursor jumping
  final Map<String, TextEditingController> _fieldControllers = {};

  @override
  void initState() {
    super.initState();
    currentMetadata = Map<String, dynamic>.from(widget.metadata ?? {});
    _currentImagePath = widget.imagePath;
    _normalizeMetadataForUi();

    // Debug: Print what metadata we received
    print('DEBUG: Metadata popup received metadata: $currentMetadata');
    print('DEBUG: Available keys: ${currentMetadata?.keys.toList()}');
    print(
        'DEBUG: Caption fields: IPTC:Description=${currentMetadata?['IPTC:Description']}, Description=${currentMetadata?['Description']}, Caption-Abstract=${currentMetadata?['Caption-Abstract']}');
    print(
        'DEBUG: Personality: XMP-getty:Personality=${currentMetadata?['XMP-getty:Personality']}, Personality=${currentMetadata?['Personality']}');
    print(
        'DEBUG: SupplementalCategories: ${currentMetadata?['SupplementalCategories']} (${currentMetadata?['SupplementalCategories'].runtimeType})');
    print(
        'DEBUG: IPTC:SupplementalCategories: ${currentMetadata?['IPTC:SupplementalCategories']} (${currentMetadata?['IPTC:SupplementalCategories'].runtimeType})');
    print(
        'DEBUG: After normalization - SupplementalCategories1=${currentMetadata?['SupplementalCategories1']}, SupplementalCategories2=${currentMetadata?['SupplementalCategories2']}, SupplementalCategories3=${currentMetadata?['SupplementalCategories3']}');

    // Initialize controllers with current values (fallback across common keys, prioritizing Photo Mechanic's field)
    final String initialCaption =
        (currentMetadata?['IPTC:Description']?.toString() ??
                currentMetadata?['Description']?.toString() ??
                currentMetadata?['Caption-Abstract']?.toString() ??
                currentMetadata?['IPTC:Caption-Abstract']?.toString() ??
                currentMetadata?['ImageDescription']?.toString() ??
                currentMetadata?['XMP:Description']?.toString() ??
                '')
            .toString();

    print('DEBUG: Initializing controllers - Caption: "$initialCaption"');
    captionController = TextEditingController(text: initialCaption);

    final String initialPersonality =
        (currentMetadata?['XMP-getty:Personality']?.toString() ??
                currentMetadata?['Personality']?.toString() ??
                '')
            .toString();

    print(
        'DEBUG: Initializing controllers - Personality: "$initialPersonality"');
    personalityController = TextEditingController(text: initialPersonality);

    // Load EXIF data for the image
    _loadExifData();
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
      });
      // Update controllers with new metadata
      _updateControllersFromMetadata();
    }
  }

  // Update caption and personality controllers from current metadata
  void _updateControllersFromMetadata() {
    final String updatedCaption =
        (currentMetadata?['IPTC:Description']?.toString() ??
                currentMetadata?['Description']?.toString() ??
                currentMetadata?['Caption-Abstract']?.toString() ??
                currentMetadata?['IPTC:Caption-Abstract']?.toString() ??
                currentMetadata?['ImageDescription']?.toString() ??
                currentMetadata?['XMP:Description']?.toString() ??
                '')
            .toString();
    if (captionController.text != updatedCaption) {
      captionController.text = updatedCaption;
    }

    final String updatedPersonality =
        (currentMetadata?['XMP-getty:Personality']?.toString() ??
                currentMetadata?['Personality']?.toString() ??
                '')
            .toString();
    if (personalityController.text != updatedPersonality) {
      personalityController.text = updatedPersonality;
    }
  }

  void _saveChanges() async {
    print('DEBUG: === _saveChanges() FUNCTION CALLED ===');
    print(
        'DEBUG: Starting _saveChanges - using _buildOutgoingMetadataFromState()');

    // Use the same method as Next/Previous buttons to ensure consistency
    final Map<String, dynamic> outgoing = _buildOutgoingMetadataFromState();

    try {
      // Use the same save method as Next/Previous buttons to ensure consistency
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

      // Notify parent of changes
      widget.onMetadataUpdated(outgoing);

      // Close the dialog
      Navigator.of(context).pop();
    } catch (e) {
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

  // Build an outgoing metadata map that reflects current controller values
  Map<String, dynamic> _buildOutgoingMetadataFromState() {
    print('DEBUG: _buildOutgoingMetadataFromState() called');

    // Start with currentMetadata which contains all the field changes from regular text fields
    final Map<String, dynamic> outgoing =
        Map<String, dynamic>.from(currentMetadata ?? {});

    // Override with ALL field controller values to ensure we capture any changes
    // This fixes issues where onChanged callbacks might not have fired
    print('DEBUG: Field controllers count: ${_fieldControllers.length}');
    _fieldControllers.forEach((key, controller) {
      final value = controller.text.trim();
      print('DEBUG: Field $key = "$value"');
      if (value.isNotEmpty) {
        outgoing[key] = value;

        // Also write to Photo Mechanic's preferred IPTC field
        final photoMechanicKey = _getPhotoMechanicField(key);
        if (photoMechanicKey != null) {
          outgoing[photoMechanicKey] = value;
        }
      } else {
        // Remove empty fields
        outgoing.remove(key);
        final photoMechanicKey = _getPhotoMechanicField(key);
        if (photoMechanicKey != null) {
          outgoing.remove(photoMechanicKey);
        }
      }
    });

    // Override with Caption controller value (since it's handled separately)
    final String cap = captionController.text.trim();
    if (cap.isNotEmpty) {
      // Only save to the primary field to avoid duplication
      outgoing['IPTC:Description'] = cap;
      // Remove duplicates
      outgoing.remove('Description');
      outgoing.remove('Caption-Abstract');
      outgoing.remove('IPTC:Caption-Abstract');
      outgoing.remove('ImageDescription');
    } else {
      outgoing.remove('IPTC:Description');
      outgoing.remove('Description');
      outgoing.remove('Caption-Abstract');
      outgoing.remove('IPTC:Caption-Abstract');
      outgoing.remove('ImageDescription');
    }

    // Override with Personality controller value (since it's handled separately)
    final String pers = personalityController.text.trim();
    if (pers.isNotEmpty) {
      outgoing['XMP-getty:Personality'] = pers;
      outgoing.remove('Personality');
    } else {
      outgoing.remove('XMP-getty:Personality');
      outgoing.remove('Personality');
    }

    // Supplemental categories are now handled in the _fieldControllers loop above

    print('DEBUG: Final outgoing metadata count: ${outgoing.length}');
    print(
        'DEBUG: Supplemental categories in outgoing: 1="${outgoing['SupplementalCategories1']}", 2="${outgoing['SupplementalCategories2']}", 3="${outgoing['SupplementalCategories3']}"');

    return outgoing;
  }

  // Save metadata to the image file using ExifTool
  Future<void> _saveMetadataToFile(Map<String, dynamic> metadata) async {
    final imagePath = _currentImagePath ?? widget.imagePath;
    if (imagePath == null) return;

    // Build ExifTool command arguments
    List<String> args = [];

    // Map metadata fields to ExifTool format
    metadata.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) {
        // Skip date/time fields as they shouldn't be modified
        if ([
          'Date',
          'Time',
          'DateTimeOriginal',
          'CreateDate',
          'ModifyDate',
          'FileModifyDate'
        ].contains(key)) {
          print('DEBUG: Skipping date/time field: $key');
          return;
        }

        // Handle supplemental categories specially
        if (key == 'SupplementalCategories1' ||
            key == 'SupplementalCategories2' ||
            key == 'SupplementalCategories3' ||
            key == 'SupplementalCategories') {
          // Skip individual fields AND the corrupted master field, we'll handle them together with helper
          print('DEBUG: Skipping supp cat field: $key');
          return;
        }

        // Use the key directly as the ExifTool field name
        // This matches how the main screen saves metadata
        args.add('-$key=$value');
        print('DEBUG: Adding field: -$key=$value');
      }
    });

    // Handle supplemental categories with overwrite semantics
    final List<String> rawInputs = [
      metadata['SupplementalCategories1']?.toString() ?? '',
      metadata['SupplementalCategories2']?.toString() ?? '',
      metadata['SupplementalCategories3']?.toString() ?? '',
    ];

    args.addAll(buildSupplementalCategoriesArgs(rawInputs));

    // Add overwrite flag and image path
    args.add('-overwrite_original');
    args.add(imagePath);

    print('DEBUG: ExifTool command args: $args');
    print('DEBUG: Image path: $imagePath');
    print('DEBUG: Full command would be: exiftool ${args.join(' ')}');

    // Run ExifTool command
    final proc = await ExiftoolHelper.run(args);

    if (proc.exitCode != 0) {
      throw Exception('ExifTool failed: ${proc.stderrText}');
    }
  }

  void _discardChanges() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    captionController.dispose();
    personalityController.dispose();
    // Dispose all cached field controllers
    for (final controller in _fieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MetadataPopupDialog oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if the image path changed (indicating a new image)
    if (oldWidget.imagePath != widget.imagePath) {
      // Only reload EXIF data when the image actually changes
      // Don't clear exifData first - let it keep showing until new data loads
      _currentImagePath = widget.imagePath;
      _loadExifData(path: _currentImagePath);
    }

    if (oldWidget.metadata != widget.metadata) {
      currentMetadata = Map<String, dynamic>.from(widget.metadata ?? {});
      _normalizeMetadataForUi();
      // Rehydrate controllers from the possibly new metadata (prioritizing Photo Mechanic's field)
      final String updatedCaption =
          (currentMetadata?['IPTC:Description']?.toString() ??
                  currentMetadata?['Description']?.toString() ??
                  currentMetadata?['Caption-Abstract']?.toString() ??
                  currentMetadata?['IPTC:Caption-Abstract']?.toString() ??
                  currentMetadata?['ImageDescription']?.toString() ??
                  currentMetadata?['XMP:Description']?.toString() ??
                  '')
              .toString();
      if (captionController.text != updatedCaption) {
        captionController.text = updatedCaption;
      }

      final String updatedPersonality =
          (currentMetadata?['XMP-getty:Personality']?.toString() ??
                  currentMetadata?['Personality']?.toString() ??
                  '')
              .toString();
      if (personalityController.text != updatedPersonality) {
        personalityController.text = updatedPersonality;
      }
    }
  }

  // Ensure UI-only fields like SupplementalCategories1/2/3 are populated
  void _normalizeMetadataForUi() {
    if (currentMetadata == null) return;

    print('DEBUG: _normalizeMetadataForUi called');
    print(
        'DEBUG: Available supplemental category fields: SupplementalCategories=${currentMetadata!['SupplementalCategories']}, IPTC:SupplementalCategories=${currentMetadata!['IPTC:SupplementalCategories']}, XMP:SupplementalCategories=${currentMetadata!['XMP:SupplementalCategories']}');

    // Clear existing values first
    currentMetadata!.remove('SupplementalCategories1');
    currentMetadata!.remove('SupplementalCategories2');
    currentMetadata!.remove('SupplementalCategories3');

    final dynamic supp =
        currentMetadata!['XMP-photoshop:SupplementalCategories'] ??
            currentMetadata!['IPTC:SupplementalCategories'] ??
            currentMetadata!['SupplementalCategories'] ??
            currentMetadata!['XMP:SupplementalCategories'];

    String sourceField = 'none';
    if (currentMetadata!['XMP-photoshop:SupplementalCategories'] != null)
      sourceField = 'XMP-photoshop:SupplementalCategories';
    else if (currentMetadata!['IPTC:SupplementalCategories'] != null)
      sourceField = 'IPTC:SupplementalCategories';
    else if (currentMetadata!['SupplementalCategories'] != null)
      sourceField = 'SupplementalCategories';
    else if (currentMetadata!['XMP:SupplementalCategories'] != null)
      sourceField = 'XMP:SupplementalCategories';

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

    print(
        'DEBUG: Final supplemental categories: 1="${currentMetadata!['SupplementalCategories1']}", 2="${currentMetadata!['SupplementalCategories2']}", 3="${currentMetadata!['SupplementalCategories3']}"');
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

      // Update controllers with new values
      _updateControllersFromMetadata();

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

  Widget _buildTwoColumnMetadata() {
    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400, width: 1.0),
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey.shade50,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Caption and Personality fields at the top spanning full width
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Caption field with persistent controller
                Text(
                  'Caption',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 3),
                TextField(
                  controller: captionController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    focusColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade500),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade500),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide:
                          BorderSide(color: Colors.grey.shade500, width: 1),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade500),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 11),
                ),

                const SizedBox(height: 5),

                // Personality field with persistent controller
                Text(
                  'Personality',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 3),
                TextField(
                  controller: personalityController,
                  maxLines: 1,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    focusColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade500),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade500),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide:
                          BorderSide(color: Colors.grey.shade500, width: 1),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: BorderSide(color: Colors.grey.shade500),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 5),
            // Two-column layout
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // First column
                  Expanded(
                    child: Column(
                      children: [
                        _buildField('Category', 'Category'),
                        _buildField('Supp Cat 1', 'SupplementalCategories1'),
                        _buildField('Supp Cat 2', 'SupplementalCategories2'),
                        _buildField('Supp Cat 3', 'SupplementalCategories3'),
                        _buildField('Object Name', 'ObjectName'),
                        _buildField('Stadium', 'Sub-location'),
                        _buildField('City', 'City'),
                        _buildField('Province/State', 'Province-State'),
                        _buildField('Country', 'Country'),
                        _buildField('Country Code', 'CountryCode'),
                        _buildField(
                            'Special Instructions', 'SpecialInstructions'),
                      ]
                          .map((widget) => Padding(
                                padding: const EdgeInsets.only(bottom: 5.0),
                                child: widget,
                              ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Second column
                  Expanded(
                    child: Column(
                      children: [
                        _buildField('Photographer', 'Creator'),
                        _buildField(
                            'MEID (Job Reference)', 'TransmissionReference'),
                        _buildField('Description Writers', 'CaptionWriter'),
                        _buildField('Creator\'s Job Title', 'AuthorsPosition'),
                        _buildField('Copyright', 'Copyright'),
                        _buildField('Credit', 'Credit'),
                        _buildField('Source', 'Source'),
                        _buildField('Headline', 'Headline'),
                        _buildField('Keywords', 'Keywords'),
                        _buildField('Urgency', 'Urgency'),
                      ]
                          .map((widget) => Padding(
                                padding: const EdgeInsets.only(bottom: 5.0),
                                child: widget,
                              ))
                          .toList(),
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

  Widget _buildField(String label, String key, {int? maxLines}) {
    // Prioritize Photo Mechanic's preferred IPTC field, then fallback to original key
    final photoMechanicKey = _getPhotoMechanicField(key);

    // Handle array values properly - extract first value or join with commas
    String value = '';
    final rawValue =
        currentMetadata?[photoMechanicKey] ?? currentMetadata?[key];
    if (rawValue != null) {
      if (rawValue is List) {
        // If it's a list, join with commas (no space for keywords)
        if (key == 'Keywords') {
          value = rawValue.map((e) => e.toString()).join(',');
        } else {
          value = rawValue.map((e) => e.toString()).join(', ');
        }
      } else {
        // Check if it's a string that looks like an array (starts with [ and ends with ])
        final stringValue = rawValue.toString();
        if (stringValue.startsWith('[') && stringValue.endsWith(']')) {
          // Remove brackets and clean up
          final cleaned = stringValue.substring(1, stringValue.length - 1);
          if (key == 'Keywords') {
            value = cleaned; // Keep as-is for keywords
          } else {
            value = cleaned; // Keep as-is for other fields too
          }
        } else {
          value = stringValue;
        }
      }
    }

    // Special handling for Urgency field - use popup menu
    if (key == 'Urgency') {
      // Extract just the number from "5 (normal urgency)" format if needed
      if (value.isNotEmpty) {
        final match = RegExp(r'^(\d+)').firstMatch(value);
        if (match != null) {
          value = match.group(1)!;
        }
      }

      // Default to '5' (Normal) if no urgency is defined or invalid value
      if (value.isEmpty ||
          !['0', '1', '2', '3', '4', '5', '6', '7', '8'].contains(value)) {
        value = '5';
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 3),
          PopupMenuButton<String>(
            initialValue:
                value, // value is already validated and defaulted to '5' above
            onSelected: (newValue) {
              setState(() {
                currentMetadata =
                    Map<String, dynamic>.from(currentMetadata ?? {});
                if (newValue.isNotEmpty) {
                  currentMetadata![key] = newValue;
                  final photoMechanicKey = _getPhotoMechanicField(key);
                  if (photoMechanicKey != null) {
                    currentMetadata![photoMechanicKey] = newValue;
                  }
                } else {
                  currentMetadata!.remove(key);
                  final photoMechanicKey = _getPhotoMechanicField(key);
                  if (photoMechanicKey != null) {
                    currentMetadata!.remove(photoMechanicKey);
                  }
                }
              });
            },
            constraints: const BoxConstraints(maxHeight: 300),
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: '',
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  'Select urgency',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: '0',
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '0 - Undefined',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: '1',
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '1 - High',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: '2',
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '2',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: '3',
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '3',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: '4',
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '4',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: '5',
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '5 - Normal',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: '6',
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '6',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: '7',
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '7',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: '8',
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '8 - Low',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ],
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.grey.shade500),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _getUrgencyDisplayText(
                          value), // value is already validated above
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors
                            .black, // Always black since value is always valid
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 16),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Regular text field for other fields - use cached controller to prevent cursor jumping
    if (!_fieldControllers.containsKey(key)) {
      _fieldControllers[key] = TextEditingController(text: value);
    } else {
      // Update existing controller text if it's different
      if (_fieldControllers[key]!.text != value) {
        _fieldControllers[key]!.text = value;
      }
    }
    final controller = _fieldControllers[key]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 3),
        TextField(
          controller: controller,
          maxLines: maxLines ?? 1,
          onChanged: (newValue) {
            setState(() {
              currentMetadata =
                  Map<String, dynamic>.from(currentMetadata ?? {});
              if (newValue.isNotEmpty) {
                // Write to both the original key and Photo Mechanic's preferred field
                currentMetadata![key] = newValue;

                // Also write to Photo Mechanic's preferred IPTC field
                final photoMechanicKey = _getPhotoMechanicField(key);
                if (photoMechanicKey != null) {
                  currentMetadata![photoMechanicKey] = newValue;
                }
              } else {
                currentMetadata!.remove(key);

                // Also remove Photo Mechanic's preferred field
                final photoMechanicKey = _getPhotoMechanicField(key);
                if (photoMechanicKey != null) {
                  currentMetadata!.remove(photoMechanicKey);
                }
              }
            });
          },
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey.shade500),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey.shade500),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey.shade500, width: 1),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey.shade500),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }

  // Get Photo Mechanic's preferred IPTC field for a given key
  String _getUrgencyDisplayText(String value) {
    switch (value) {
      case '0':
        return '0 - Undefined';
      case '1':
        return '1 - High';
      case '2':
        return '2';
      case '3':
        return '3';
      case '4':
        return '4';
      case '5':
        return '5 - Normal';
      case '6':
        return '6';
      case '7':
        return '7';
      case '8':
        return '8 - Low';
      default:
        return value;
    }
  }

  String? _getPhotoMechanicField(String key) {
    switch (key) {
      // Core IPTC fields that should be written directly
      case 'IPTC:Description':
      case 'Description':
      case 'Caption-Abstract':
      case 'IPTC:Caption-Abstract':
      case 'ImageDescription':
        return 'IPTC:Description';

      case 'IPTC:By-line':
      case 'By-line':
      case 'Creator':
      case 'XMP:Creator':
        return 'IPTC:By-line';

      case 'IPTC:OriginalTransmissionReference':
      case 'OriginalTransmissionReference':
      case 'TransmissionReference':
      case 'JobID':
      case 'MEID':
        return 'IPTC:OriginalTransmissionReference';

      case 'IPTC:By-lineTitle':
      case 'By-lineTitle':
      case 'AuthorsPosition':
        return 'IPTC:By-lineTitle';

      case 'IPTC:CopyrightNotice':
      case 'CopyrightNotice':
      case 'Copyright':
      case 'XMP:Rights':
        return 'IPTC:CopyrightNotice';

      case 'IPTC:Credit':
      case 'Credit':
        return 'IPTC:Credit';

      case 'IPTC:Source':
      case 'Source':
      case 'XMP:Source':
        return 'IPTC:Source';

      case 'IPTC:Headline':
      case 'Headline':
      case 'XMP:Title':
        return 'IPTC:Headline';

      case 'IPTC:Keywords':
      case 'Keywords':
      case 'XMP:Subject':
        return 'IPTC:Keywords';

      case 'IPTC:Category':
      case 'Category':
        return 'IPTC:Category';

      case 'IPTC:ObjectName':
      case 'ObjectName':
        return 'IPTC:ObjectName';

      case 'IPTC:SubLocation':
      case 'Sub-location':
      case 'SubLocation':
      case 'XMP:Location':
        return 'IPTC:SubLocation';

      case 'IPTC:City':
      case 'City':
      case 'XMP:City':
        return 'IPTC:City';

      case 'IPTC:ProvinceState':
      case 'Province-State':
      case 'ProvinceState':
      case 'XMP:State':
        return 'IPTC:ProvinceState';

      case 'IPTC:CountryPrimaryLocationName':
      case 'CountryPrimaryLocationName':
      case 'Country':
      case 'XMP:Country':
        return 'IPTC:CountryPrimaryLocationName';

      case 'IPTC:CountryPrimaryLocationCode':
      case 'CountryPrimaryLocationCode':
      case 'CountryCode':
        return 'IPTC:CountryPrimaryLocationCode';

      case 'IPTC:Urgency':
      case 'Urgency':
        return 'IPTC:Urgency';

      case 'IPTC:SpecialInstructions':
      case 'SpecialInstructions':
      case 'XMP:Instructions':
      case 'XMP-photoshop:Instructions':
        return 'IPTC:SpecialInstructions';

      case 'XMP-getty:Personality':
      case 'XMP:Personality':
      case 'Personality':
        return 'XMP-getty:Personality';

      default:
        return null;
    }
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
            // Format date/time for display
            try {
              final dt = DateTime.parse(
                  value.replaceFirst(':', '-').replaceFirst(':', '-'));
              value =
                  '${dt.month}/${dt.day}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
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

  String _formatDateForDisplay() {
    if (exifData == null || exifData!['DateTimeOriginal'] == null) return '';

    try {
      final dateTimeStr = exifData!['DateTimeOriginal'].toString();
      final dt = DateTime.parse(
          dateTimeStr.replaceFirst(':', '-').replaceFirst(':', '-'));

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
      final dt = DateTime.parse(
          dateTimeStr.replaceFirst(':', '-').replaceFirst(':', '-'));
      final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final minute = dt.minute.toString().padLeft(2, '0');
      final second = dt.second.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute:$second $ampm';
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ensure controllers are updated with current metadata
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateControllersFromMetadata();
    });

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
                                child: ExtendedImage.file(
                                  File(_currentImagePath ?? widget.imagePath!),
                                  key: ValueKey(
                                      _currentImagePath ?? widget.imagePath),
                                  fit: BoxFit.contain,
                                  enableLoadState: false,
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
                                        setState(() {});
                                        _loadExifData(path: _currentImagePath);
                                      } catch (_) {}
                                    } else if (widget.onPreviousImage != null) {
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
                                        setState(() {});
                                        _loadExifData(path: _currentImagePath);
                                      } catch (_) {}
                                    } else if (widget.onNextImage != null) {
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
                        child: _buildTwoColumnMetadata(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Footer with action buttons
            Container(
              padding: const EdgeInsets.all(16),
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
                      print('DEBUG: === SAVE BUTTON CLICKED ===');
                      print('DEBUG: About to call _saveChanges()');
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
