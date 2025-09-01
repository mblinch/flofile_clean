import 'package:flutter/material.dart';
import 'metadata_widget.dart';

class MetadataPopupDialog extends StatefulWidget {
  final Map<String, dynamic>? metadata;
  final Function(Map<String, dynamic>) onMetadataUpdated;

  const MetadataPopupDialog({
    super.key,
    required this.metadata,
    required this.onMetadataUpdated,
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
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            
            // Metadata widget (exact same as bottom right quadrant)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: MetadataWidget(
                  metadata: currentMetadata,
                  onMetadataUpdated: _handleMetadataUpdated,
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
                    onPressed: _saveChanges,
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
}
