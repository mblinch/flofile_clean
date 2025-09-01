import 'package:flutter/material.dart';

class MetadataPopupDialog extends StatefulWidget {
  final Map<String, dynamic>? metadata;
  final Function(Map<String, dynamic>) onMetadataUpdated;
  final VoidCallback? onSaveAsTemplate;
  final VoidCallback? onLoadFromJpg;

  const MetadataPopupDialog({
    super.key,
    required this.metadata,
    required this.onMetadataUpdated,
    this.onSaveAsTemplate,
    this.onLoadFromJpg,
  });

  @override
  State<MetadataPopupDialog> createState() => _MetadataPopupDialogState();
}

class _MetadataPopupDialogState extends State<MetadataPopupDialog> {
  late Map<String, TextEditingController> controllers;
  late Map<String, String> originalValues;
  bool hasChanges = false;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    controllers = {};
    originalValues = {};

    // Define all IPTC fields with their display names
    final fields = {
      'Creator': 'Creator',
      'TransmissionReference': 'MEID (Job Reference)',
      'CaptionWriter': 'Description Writers',
      'AuthorsPosition': 'Creator\'s Job Title',
      'Copyright': 'Copyright',
      'Credit': 'Credit',
      'Source': 'Source',
      'Headline': 'Headline',
      'Keywords': 'Keywords',
      'SupplementalCategories': 'Supplemental Categories',
      'Category': 'Category',
      'ObjectName': 'Object Name',
      'Sub-location': 'Stadium',
      'City': 'City',
      'Province-State': 'Province/State',
      'Country': 'Country',
      'CountryCode': 'Country Code',
      'Urgency': 'Urgency',
      'SpecialInstructions': 'Special Instructions',
      'Caption-Abstract': 'Caption',
      'XMP-getty:Personality': 'Personality',
    };

    // Initialize controllers with current values or empty strings
    for (final entry in fields.entries) {
      final key = entry.key;
      final value = widget.metadata?[key]?.toString() ?? '';
      controllers[key] = TextEditingController(text: value);
      originalValues[key] = value;
      
      // Add listeners to detect changes
      controllers[key]!.addListener(() {
        _checkForChanges();
      });
    }
  }

  void _checkForChanges() {
    bool changed = false;
    for (final entry in controllers.entries) {
      final key = entry.key;
      final controller = entry.value;
      if (controller.text != originalValues[key]) {
        changed = true;
      }
    }
    
    if (changed != hasChanges) {
      setState(() {
        hasChanges = changed;
      });
    }
  }

  void _saveChanges() {
    final updatedMetadata = <String, dynamic>{};
    for (final entry in controllers.entries) {
      final key = entry.key;
      final controller = entry.value;
      if (controller.text.isNotEmpty) {
        updatedMetadata[key] = controller.text;
      }
    }
    
    widget.onMetadataUpdated(updatedMetadata);
    Navigator.of(context).pop();
  }

  void _discardChanges() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    // Remove listeners
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
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
                color: Colors.blue.shade50,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_note, color: Colors.blue),
                  const SizedBox(width: 12),
                  const Text(
                    'Edit IPTC Metadata',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (hasChanges)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Text(
                        'Unsaved Changes',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            
            // Metadata fields
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Action buttons at top
                    Row(
                      children: [
                        if (widget.onSaveAsTemplate != null)
                          ElevatedButton.icon(
                            onPressed: widget.onSaveAsTemplate,
                            icon: const Icon(Icons.save),
                            label: const Text('Save as Template'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        if (widget.onSaveAsTemplate != null && widget.onLoadFromJpg != null)
                          const SizedBox(width: 12),
                        if (widget.onLoadFromJpg != null)
                          ElevatedButton.icon(
                            onPressed: widget.onLoadFromJpg,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Load from JPG'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade600,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        const Spacer(),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Metadata fields in a grid layout
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 3.5,
                      children: [
                        _buildField('Creator', 'Creator'),
                        _buildField('TransmissionReference', 'MEID (Job Reference)'),
                        _buildField('CaptionWriter', 'Description Writers'),
                        _buildField('AuthorsPosition', 'Creator\'s Job Title'),
                        _buildField('Copyright', 'Copyright'),
                        _buildField('Credit', 'Credit'),
                        _buildField('Source', 'Source'),
                        _buildField('Headline', 'Headline'),
                        _buildField('Keywords', 'Keywords'),
                        _buildField('SupplementalCategories', 'Supplemental Categories'),
                        _buildField('Category', 'Category'),
                        _buildField('ObjectName', 'Object Name'),
                        _buildField('Sub-location', 'Stadium'),
                        _buildField('City', 'City'),
                        _buildField('Province-State', 'Province/State'),
                        _buildField('Country', 'Country'),
                        _buildField('CountryCode', 'Country Code'),
                        _buildField('Urgency', 'Urgency'),
                        _buildField('SpecialInstructions', 'Special Instructions'),
                        _buildField('Caption-Abstract', 'Caption'),
                        _buildField('XMP-getty:Personality', 'Personality'),
                      ],
                    ),
                  ],
                ),
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
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: hasChanges ? _saveChanges : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
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

  Widget _buildField(String key, String label) {
    final controller = controllers[key];
    if (controller == null) return const SizedBox.shrink();

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
}
