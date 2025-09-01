import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'package:extended_image/extended_image.dart';
import '../utils/exiftool_helper.dart';

class MetadataPopupDialog extends StatefulWidget {
  final Map<String, dynamic>? metadata;
  final Function(Map<String, dynamic>) onMetadataUpdated;
  final String? imagePath;

  const MetadataPopupDialog({
    super.key,
    required this.metadata,
    required this.onMetadataUpdated,
    this.imagePath,
  });

  @override
  State<MetadataPopupDialog> createState() => _MetadataPopupDialogState();
}

class _MetadataPopupDialogState extends State<MetadataPopupDialog> {
  Map<String, dynamic>? currentMetadata;
  Map<String, dynamic>? exifData;

  // Controllers for caption and personality fields
  late TextEditingController captionController;
  late TextEditingController personalityController;

  @override
  void initState() {
    super.initState();
    currentMetadata = Map<String, dynamic>.from(widget.metadata ?? {});

    // Debug: Print what metadata we received
    print('DEBUG: Metadata popup received metadata: $currentMetadata');
    print('DEBUG: Available keys: ${currentMetadata?.keys.toList()}');

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
    captionController = TextEditingController(text: initialCaption);

    final String initialPersonality =
        (currentMetadata?['XMP-getty:Personality']?.toString() ??
                currentMetadata?['Personality']?.toString() ??
                '')
            .toString();
    personalityController = TextEditingController(text: initialPersonality);

    // Load EXIF data for the image
    _loadExifData();
  }

  // Load EXIF data from the image file
  Future<void> _loadExifData() async {
    if (widget.imagePath == null) return;

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
        widget.imagePath!,
      ]);

      if (exiftool.exitCode == 0) {
        final List data = jsonDecode(exiftool.stdoutText);
        if (data.isNotEmpty) {
          final exifDataMap = data.first as Map<String, dynamic>;
          print('DEBUG: EXIF data loaded: $exifDataMap');
          setState(() {
            exifData = exifDataMap;
          });
        }
      }
    } catch (e) {
      print('Error loading EXIF data: $e');
    }
  }

  void _handleMetadataUpdated(Map<String, dynamic>? metadata) {
    if (metadata != null) {
      setState(() {
        currentMetadata = metadata;
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

  void _saveChanges() {
    // Ensure controller values are reflected in the outgoing metadata
    final Map<String, dynamic> outgoing =
        Map<String, dynamic>.from(currentMetadata ?? {});
    final String cap = captionController.text.trim();
    if (cap.isNotEmpty) {
      outgoing['IPTC:Description'] = cap; // Photo Mechanic's preferred field
      outgoing['Description'] = cap; // Alternative name
      outgoing['Caption-Abstract'] = cap;
      outgoing['IPTC:Caption-Abstract'] = cap;
      outgoing['ImageDescription'] = cap; // keep in sync with common field
    } else {
      outgoing.remove('IPTC:Description');
      outgoing.remove('Description');
      outgoing.remove('Caption-Abstract');
      outgoing.remove('IPTC:Caption-Abstract');
      outgoing.remove('ImageDescription');
    }

    final String pers = personalityController.text.trim();
    if (pers.isNotEmpty) {
      outgoing['XMP-getty:Personality'] = pers;
      outgoing['Personality'] = pers;
    } else {
      outgoing.remove('XMP-getty:Personality');
      outgoing.remove('Personality');
    }

    // Also write all other fields to Photo Mechanic's preferred IPTC fields
    currentMetadata?.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) {
        final photoMechanicKey = _getPhotoMechanicField(key);
        if (photoMechanicKey != null) {
          outgoing[photoMechanicKey] = value;
        }
      }
    });

    widget.onMetadataUpdated(outgoing);
    Navigator.of(context).pop();
  }

  void _discardChanges() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    captionController.dispose();
    personalityController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MetadataPopupDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metadata != widget.metadata) {
      currentMetadata = Map<String, dynamic>.from(widget.metadata ?? {});
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

  Widget _buildTwoColumnMetadata() {
    return Container(
      margin: const EdgeInsets.all(3.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 1.0),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Two-column grid layout
            LayoutBuilder(builder: (context, constraints) {
              const double gap = 16.0;

              // First column items (Category and Supplemental Categories grouped together)
              final List<Widget> firstColumnItems = [
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
                _buildField('Urgency', 'Urgency'),
                _buildField('Special Instructions', 'SpecialInstructions'),
              ];

              // Second column items
              final List<Widget> secondColumnItems = [
                _buildField('Photographer', 'Creator'),
                _buildField('MEID (Job Reference)', 'TransmissionReference'),
                _buildField('Description Writers', 'CaptionWriter'),
                _buildField('Creator\'s Job Title', 'AuthorsPosition'),
                _buildField('Copyright', 'Copyright'),
                _buildField('Credit', 'Credit'),
                _buildField('Source', 'Source'),
                _buildField('Headline', 'Headline'),
                _buildField('Keywords', 'Keywords'),
              ];

              return Column(
                children: [
                  // Caption and Personality fields at the top spanning full width
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Caption field with persistent controller
                      Text(
                        'Caption',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      TextField(
                        controller: captionController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(
                                color: Colors.grey.shade600, width: 1),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),

                      const SizedBox(height: 16),

                      // Personality field with persistent controller
                      Text(
                        'Personality',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      TextField(
                        controller: personalityController,
                        maxLines: 1,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(
                                color: Colors.grey.shade600, width: 1),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Two-column layout
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // First column
                      Expanded(
                        child: Column(
                          children: firstColumnItems
                              .map((widget) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 16.0),
                                    child: widget,
                                  ))
                              .toList(),
                        ),
                      ),
                      const SizedBox(width: gap),
                      // Second column
                      Expanded(
                        child: Column(
                          children: secondColumnItems
                              .map((widget) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 16.0),
                                    child: widget,
                                  ))
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, String key, {int? maxLines}) {
    // Prioritize Photo Mechanic's preferred IPTC field, then fallback to original key
    final photoMechanicKey = _getPhotoMechanicField(key);
    final value = currentMetadata?[photoMechanicKey]?.toString() ??
        currentMetadata?[key]?.toString() ??
        '';
    final controller = TextEditingController(text: value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
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
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: Colors.grey.shade600, width: 1),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  // Get Photo Mechanic's preferred IPTC field for a given key
  String? _getPhotoMechanicField(String key) {
    switch (key) {
      case 'Creator':
        return 'IPTC:By-line';
      case 'TransmissionReference':
        return 'IPTC:OriginalTransmissionReference';
      case 'AuthorsPosition':
        return 'IPTC:By-lineTitle';
      case 'Copyright':
        return 'IPTC:CopyrightNotice';
      case 'Credit':
        return 'IPTC:Credit';
      case 'Source':
        return 'IPTC:Source';
      case 'Headline':
        return 'IPTC:Headline';
      case 'Keywords':
        return 'IPTC:Keywords';
      case 'Category':
        return 'IPTC:Category';
      case 'ObjectName':
        return 'IPTC:ObjectName';
      case 'Sub-location':
        return 'IPTC:SubLocation';
      case 'City':
        return 'IPTC:City';
      case 'Province-State':
        return 'IPTC:ProvinceState';
      case 'Country':
        return 'IPTC:CountryPrimaryLocationName';
      case 'CountryCode':
        return 'IPTC:CountryPrimaryLocationCode';
      case 'Urgency':
        return 'IPTC:Urgency';
      case 'SpecialInstructions':
        return 'IPTC:SpecialInstructions';
      default:
        return null;
    }
  }

  Widget _buildExifRow(String label, String exifKey) {
    // Get the actual EXIF value from the loaded data
    String value = 'N/A';

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
                if (den == 1) {
                  formattedShutter = '${num}s';
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
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $ampm';
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
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
                  ),
                ],
              ),
            ),

            // Image preview and metadata in a row
            Expanded(
              child: Row(
                children: [
                  // Left side - Image preview with EXIF data
                  if (widget.imagePath != null)
                    Container(
                      width: 600,
                      padding: const EdgeInsets.all(16),
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
                                File(widget.imagePath!),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // EXIF data section
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                RichText(
                                  text: TextSpan(
                                    children: [
                                      TextSpan(
                                        text: widget.imagePath != null
                                            ? widget.imagePath!.split('/').last
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

                  // Right side - Metadata widget with custom two-column layout
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildTwoColumnMetadata(),
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
                  TextButton(
                    onPressed: _discardChanges,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _saveChanges,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade300,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                    ),
                    child: const Text('Save Changes'),
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
