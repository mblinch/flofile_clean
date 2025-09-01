import 'package:flutter/material.dart';
import 'dart:io';
import 'package:extended_image/extended_image.dart';

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

  @override
  void initState() {
    super.initState();
    currentMetadata = Map<String, dynamic>.from(widget.metadata ?? {});
  }

  void _handleMetadataUpdated(Map<String, dynamic>? metadata) {
    if (metadata != null) {
      setState(() {
        currentMetadata = metadata;
      });
    }
  }

  void _saveChanges() {
    widget.onMetadataUpdated(currentMetadata ?? {});
    Navigator.of(context).pop();
  }

  void _discardChanges() {
    Navigator.of(context).pop();
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
              const int columns = 2;
              const double gap = 16.0;
              final double columnWidth = (constraints.maxWidth - gap) / columns;

              final List<Widget> items = [
                _buildField('Photographer', 'Creator'),
                _buildField('MEID (Job Reference)', 'TransmissionReference'),
                _buildField('Description Writers', 'CaptionWriter'),
                _buildField('Creator\'s Job Title', 'AuthorsPosition'),
                _buildField('Copyright', 'Copyright'),
                _buildField('Credit', 'Credit'),
                _buildField('Source', 'Source'),
                _buildField('Headline', 'Headline'),
                _buildField('Keywords', 'Keywords'),
                _buildField('Supp Cat 1', 'SupplementalCategories1'),
                _buildField('Supp Cat 2', 'SupplementalCategories2'),
                _buildField('Supp Cat 3', 'SupplementalCategories3'),
                _buildField('Category', 'Category'),
                _buildField('Object Name', 'ObjectName'),
                _buildField('Stadium', 'Sub-location'),
                _buildField('City', 'City'),
                _buildField('Province/State', 'Province-State'),
                _buildField('Country', 'Country'),
                _buildField('Country Code', 'CountryCode'),
                _buildField('Urgency', 'Urgency'),
                _buildField('Special Instructions', 'SpecialInstructions'),
                _buildField('Caption', 'Caption-Abstract'),
              ];

              return Column(
                children: [
                  Wrap(
                    spacing: gap,
                    runSpacing: 16.0,
                    children: items.map((widget) => SizedBox(
                      width: columnWidth,
                      child: widget,
                    )).toList(),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, String key) {
    final controller = TextEditingController(text: currentMetadata?[key]?.toString() ?? '');
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          onChanged: (newValue) {
            setState(() {
              currentMetadata = Map<String, dynamic>.from(currentMetadata ?? {});
              if (newValue.isNotEmpty) {
                currentMetadata![key] = newValue;
              } else {
                currentMetadata!.remove(key);
              }
            });
          },
          decoration: InputDecoration(
            hintText: 'Enter $label',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: Colors.blue.shade400, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
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
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
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
                      fontSize: 18,
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
                  // Left side - Image preview
                  if (widget.imagePath != null)
                    Container(
                      width: 280,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 248,
                              height: 200,
                              child: ExtendedImage.file(
                                File(widget.imagePath!),
                                fit: BoxFit.contain,
                              ),
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
                      foregroundColor: Colors.grey.shade700,
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _saveChanges,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade600,
                      foregroundColor: Colors.white,
                      elevation: 2,
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
