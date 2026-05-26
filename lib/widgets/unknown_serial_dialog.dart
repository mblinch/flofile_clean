import 'package:flutter/material.dart';
import '../services/camera_serial_service.dart';
import 'app_styled_dialogs.dart';

class UnknownSerialDialog extends StatefulWidget {
  final String serialNumber;
  final CameraSerialService cameraService;
  final Function(String) onPhotographerAssigned;

  const UnknownSerialDialog({
    super.key,
    required this.serialNumber,
    required this.cameraService,
    required this.onPhotographerAssigned,
  });

  @override
  State<UnknownSerialDialog> createState() => _UnknownSerialDialogState();
}

class _UnknownSerialDialogState extends State<UnknownSerialDialog> {
  String? _selectedPhotographer;
  final _newPhotographerController = TextEditingController();
  bool _isAddingNew = false;

  @override
  void dispose() {
    _newPhotographerController.dispose();
    super.dispose();
  }

  Future<void> _handleAssignment() async {
    if (_isAddingNew) {
      final newName = _newPhotographerController.text.trim();
      if (newName.isNotEmpty) {
        await widget.cameraService.addCameraMapping(
          widget.serialNumber,
          newName,
        );
        widget.onPhotographerAssigned(newName);
        Navigator.of(context).pop();
      }
    } else if (_selectedPhotographer != null) {
      await widget.cameraService.addSerialToExistingPhotographer(
        widget.serialNumber,
        _selectedPhotographer!,
      );
      widget.onPhotographerAssigned(_selectedPhotographer!);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final existingPhotographers =
        widget.cameraService.getUniquePhotographerNames();

    return AlertDialog(
      title: const Text('Unknown Camera Serial Number'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Serial Number: ${widget.serialNumber}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'This camera serial number is not recognized. Would you like to:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),

            // Option 1: Add to existing photographer
            if (existingPhotographers.isNotEmpty) ...[
              RadioListTile<bool>(
                title: const Text('Add to existing photographer'),
                value: false,
                groupValue: _isAddingNew,
                onChanged: (value) {
                  setState(() {
                    _isAddingNew = false;
                    _selectedPhotographer = null;
                  });
                },
                contentPadding: EdgeInsets.zero,
              ),
              if (!_isAddingNew) ...[
                Container(
                  margin: const EdgeInsets.only(left: 28, bottom: 16),
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Select Photographer',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    value: _selectedPhotographer,
                    items: existingPhotographers.map((name) {
                      return DropdownMenuItem(
                        value: name,
                        child: Text(name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedPhotographer = value;
                      });
                    },
                  ),
                ),
              ],
            ],

            // Option 2: Create new photographer
            RadioListTile<bool>(
              title: const Text('Create new photographer'),
              value: true,
              groupValue: _isAddingNew,
              onChanged: (value) {
                setState(() {
                  _isAddingNew = true;
                  _selectedPhotographer = null;
                });
              },
              contentPadding: EdgeInsets.zero,
            ),
            if (_isAddingNew) ...[
              Container(
                margin: const EdgeInsets.only(left: 28, bottom: 16),
                child: TextField(
                  controller: _newPhotographerController,
                  decoration: const InputDecoration(
                    labelText: 'Photographer Name',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        ElevatedGreyButton(
          label: 'Cancel',
          fontSize: 11,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        ElevatedGreyButton(
          label: 'Add Serial Number',
          fontSize: 11,
          isPrimary: true,
          onPressed: () {
            if ((!_isAddingNew && _selectedPhotographer != null) ||
                (_isAddingNew &&
                    _newPhotographerController.text.trim().isNotEmpty)) {
              _handleAssignment();
            }
          },
        ),
      ],
    );
  }
}
