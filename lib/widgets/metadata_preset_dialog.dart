import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/native_file_picker.dart';
import 'dart:convert';
import 'dart:io';
import '../utils/exiftool_helper.dart';
import 'app_compact_checkbox.dart';
import 'app_styled_dialogs.dart';

class MetadataPresetDialog extends StatefulWidget {
  final Map<String, String>? currentPreset;
  final DateTime? detectedDate;

  const MetadataPresetDialog({Key? key, this.currentPreset, this.detectedDate})
      : super(key: key);

  @override
  State<MetadataPresetDialog> createState() => _MetadataPresetDialogState();
}

class _MetadataPresetDialogState extends State<MetadataPresetDialog> {
  // IPTC metadata controllers
  final TextEditingController creatorController = TextEditingController();
  final TextEditingController jobIdController = TextEditingController();
  final TextEditingController descriptionWritersController =
      TextEditingController();
  final TextEditingController creatorJobTitleController =
      TextEditingController();
  final TextEditingController copyrightController = TextEditingController();
  final TextEditingController creditController = TextEditingController();
  final TextEditingController sourceController = TextEditingController();
  final TextEditingController headlineController = TextEditingController();
  final TextEditingController keywordsController = TextEditingController();
  final TextEditingController suppCat1Controller = TextEditingController();
  final TextEditingController suppCat2Controller = TextEditingController();
  final TextEditingController suppCat3Controller = TextEditingController();
  final TextEditingController categoryController = TextEditingController();
  final TextEditingController titleObjectNameController =
      TextEditingController();
  final TextEditingController stadiumController = TextEditingController();
  final TextEditingController cityController = TextEditingController();
  final TextEditingController provinceController = TextEditingController();

  final TextEditingController specialInstructionsController =
      TextEditingController();
  final TextEditingController personalityController = TextEditingController();
  final TextEditingController captionController = TextEditingController();
  final TextEditingController dateController = TextEditingController();
  final TextEditingController timeController = TextEditingController();

  // Preset management
  final TextEditingController presetNameController = TextEditingController();
  List<String> savedPresets = [];
  String? selectedPreset;
  String? selectedCaptionStyle = 'getty';
  DateTime? detectedDate;

  @override
  void initState() {
    super.initState();
    _loadSavedPresets();
    _initializePreset();
    detectedDate = widget.detectedDate;
  }

  Future<void> _initializePreset() async {
    await _loadCurrentPreset();
  }

  Future<void> _loadSavedPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final presetsJson = prefs.getString('metadata_presets');
    if (presetsJson != null && mounted) {
      final presets = jsonDecode(presetsJson) as Map<String, dynamic>;
      setState(() {
        savedPresets = presets.keys.toList();
      });
    }
  }

  Future<void> _loadCurrentPreset() async {
    // First try to load from widget.currentPreset if provided
    if (widget.currentPreset != null) {
      creatorController.text = widget.currentPreset!['Creator'] ?? '';
      jobIdController.text = widget.currentPreset!['MEID'] ?? '';
      descriptionWritersController.text =
          widget.currentPreset!['Description Writers'] ?? '';
      creatorJobTitleController.text =
          widget.currentPreset!['Creator\'s Job Title'] ?? '';
      copyrightController.text = widget.currentPreset!['Copyright'] ?? '';
      creditController.text = widget.currentPreset!['Credit'] ?? '';
      sourceController.text = widget.currentPreset!['Source'] ?? '';
      headlineController.text = widget.currentPreset!['Headline'] ?? '';
      keywordsController.text = widget.currentPreset!['Keywords'] ?? '';
      suppCat1Controller.text = widget.currentPreset!['Supp Cat 1'] ?? '';
      suppCat2Controller.text = widget.currentPreset!['Supp Cat 2'] ?? '';
      suppCat3Controller.text = widget.currentPreset!['Supp Cat 3'] ?? '';
      categoryController.text = widget.currentPreset!['Category'] ?? '';
      titleObjectNameController.text =
          widget.currentPreset!['Object Name'] ?? '';
      stadiumController.text = widget.currentPreset!['Stadium'] ?? '';
      cityController.text = widget.currentPreset!['City'] ?? '';
      provinceController.text = widget.currentPreset!['Province/State'] ?? '';

      specialInstructionsController.text =
          widget.currentPreset!['Special Instructions'] ?? '';
      personalityController.text = widget.currentPreset!['Personality'] ?? '';
      captionController.text = widget.currentPreset!['Caption'] ?? '';
    } else {
      // If no current preset provided, try to load the default template
      final prefs = await SharedPreferences.getInstance();
      final defaultTemplateJson = prefs.getString('default_metadata_template');
      if (defaultTemplateJson != null) {
        try {
          final defaultTemplate =
              jsonDecode(defaultTemplateJson) as Map<String, dynamic>;
          creatorController.text = defaultTemplate['Creator'] ?? '';
          jobIdController.text = defaultTemplate['MEID'] ?? '';
          descriptionWritersController.text =
              defaultTemplate['Description Writers'] ?? '';
          creatorJobTitleController.text =
              defaultTemplate['Creator\'s Job Title'] ?? '';
          copyrightController.text = defaultTemplate['Copyright'] ?? '';
          creditController.text = defaultTemplate['Credit'] ?? '';
          sourceController.text = defaultTemplate['Source'] ?? '';
          headlineController.text = defaultTemplate['Headline'] ?? '';
          keywordsController.text = defaultTemplate['Keywords'] ?? '';
          suppCat1Controller.text = defaultTemplate['Supp Cat 1'] ?? '';
          suppCat2Controller.text = defaultTemplate['Supp Cat 2'] ?? '';
          suppCat3Controller.text = defaultTemplate['Supp Cat 3'] ?? '';
          categoryController.text = defaultTemplate['Category'] ?? '';
          titleObjectNameController.text = defaultTemplate['Object Name'] ?? '';
          stadiumController.text = defaultTemplate['Stadium'] ?? '';
          cityController.text = defaultTemplate['City'] ?? '';
          provinceController.text = defaultTemplate['Province/State'] ?? '';

          specialInstructionsController.text =
              defaultTemplate['Special Instructions'] ?? '';
          personalityController.text = defaultTemplate['Personality'] ?? '';
          captionController.text = defaultTemplate['Caption'] ?? '';
        } catch (e) {
          print('Error loading default template: $e');
        }
      }
    }
  }

  Future<void> _savePreset() async {
    // Show dialog to get template name
    final presetName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final nameController =
            TextEditingController(text: selectedPreset ?? '');
        return Dialog(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(Icons.save, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Text(
                      'Save Template',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Content
                Text(
                  'Enter a name for this template:',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    color: Colors.white,
                  ),
                  child: TextField(
                    controller: nameController,
                    style: const TextStyle(fontSize: 10),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      hintText: 'Template name',
                      hintStyle: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    autofocus: true,
                  ),
                ),
                const SizedBox(height: 16),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedGreyButton(
                      label: 'Cancel',
                      fontSize: 10,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    ElevatedGreyButton(
                      label: 'Save',
                      fontSize: 10,
                      isPrimary: true,
                      onPressed: () {
                        final name = nameController.text.trim();
                        if (name.isNotEmpty) {
                          Navigator.of(context).pop(name);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (presetName == null || presetName.isEmpty) {
      return; // User cancelled or entered empty name
    }

    final presetData = {
      'Creator': creatorController.text,
      'MEID': jobIdController.text,
      'Description Writers': descriptionWritersController.text,
      'Creator\'s Job Title': creatorJobTitleController.text,
      'Copyright': copyrightController.text,
      'Credit': creditController.text,
      'Source': sourceController.text,
      'Headline': headlineController.text,
      'Keywords': keywordsController.text,
      'Supp Cat 1': suppCat1Controller.text,
      'Supp Cat 2': suppCat2Controller.text,
      'Supp Cat 3': suppCat3Controller.text,
      'Category': categoryController.text,
      'Object Name': titleObjectNameController.text,
      'Stadium': stadiumController.text,
      'City': cityController.text,
      'Province/State': provinceController.text,
      'Special Instructions': specialInstructionsController.text,
      'Personality': personalityController.text,
      'Caption': captionController.text,
      'Date': dateController.text,
      'Time': timeController.text,
    };

    final prefs = await SharedPreferences.getInstance();
    final presetsJson = prefs.getString('metadata_presets');
    Map<String, dynamic> presets = {};

    if (presetsJson != null) {
      presets = Map<String, dynamic>.from(jsonDecode(presetsJson));
    }

    presets[presetName] = presetData;
    await prefs.setString('metadata_presets', jsonEncode(presets));

    if (mounted) {
      setState(() {
        savedPresets = presets.keys.toList();
        selectedPreset = presetName;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preset "$presetName" saved successfully!')),
      );
    }
  }

  Future<void> _saveSettings() async {
    // Get current metadata values
    final metadataValues = {
      'Creator': creatorController.text,
      'MEID': jobIdController.text,
      'Description Writers': descriptionWritersController.text,
      'Creator\'s Job Title': creatorJobTitleController.text,
      'Copyright': copyrightController.text,
      'Credit': creditController.text,
      'Source': sourceController.text,
      'Headline': headlineController.text,
      'Keywords': keywordsController.text,
      'Supp Cat 1': suppCat1Controller.text,
      'Supp Cat 2': suppCat2Controller.text,
      'Supp Cat 3': suppCat3Controller.text,
      'Category': categoryController.text,
      'Object Name': titleObjectNameController.text,
      'Stadium': stadiumController.text,
      'City': cityController.text,
      'Province/State': provinceController.text,
      'Special Instructions': specialInstructionsController.text,
      'Personality': personalityController.text,
      'Caption': captionController.text,
      'Date': dateController.text,
      'Time': timeController.text,
    };

    // Save as default template for next time
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'default_metadata_template', jsonEncode(metadataValues));

    // Return just the metadata - apply to all images is handled in startup dialog
    Navigator.of(context).pop({
      'metadata': metadataValues,
    });
  }

  Future<void> _loadPreset(String presetName) async {
    final prefs = await SharedPreferences.getInstance();
    final presetsJson = prefs.getString('metadata_presets');
    if (presetsJson != null) {
      final presets = jsonDecode(presetsJson) as Map<String, dynamic>;
      final presetData = presets[presetName] as Map<String, dynamic>?;

      if (presetData != null && mounted) {
        setState(() {
          creatorController.text = presetData['Creator'] ?? '';
          jobIdController.text = presetData['MEID'] ?? '';
          descriptionWritersController.text =
              presetData['Description Writers'] ?? '';
          creatorJobTitleController.text =
              presetData['Creator\'s Job Title'] ?? '';
          copyrightController.text = presetData['Copyright'] ?? '';
          creditController.text = presetData['Credit'] ?? '';
          sourceController.text = presetData['Source'] ?? '';
          headlineController.text = presetData['Headline'] ?? '';
          keywordsController.text = presetData['Keywords'] ?? '';
          suppCat1Controller.text = presetData['Supp Cat 1'] ?? '';
          suppCat2Controller.text = presetData['Supp Cat 2'] ?? '';
          suppCat3Controller.text = presetData['Supp Cat 3'] ?? '';
          categoryController.text = presetData['Category'] ?? '';
          titleObjectNameController.text = presetData['Object Name'] ?? '';
          stadiumController.text = presetData['Stadium'] ?? '';
          cityController.text = presetData['City'] ?? '';
          provinceController.text = presetData['Province/State'] ?? '';
          specialInstructionsController.text =
              presetData['Special Instructions'] ?? '';
          personalityController.text = presetData['Personality'] ?? '';
          captionController.text = presetData['Caption'] ?? '';
          dateController.text = presetData['Date'] ?? '';
          timeController.text = presetData['Time'] ?? '';
          selectedPreset = presetName;
        });
      }
    }
  }

  Future<void> _deletePreset(String presetName) async {
    final prefs = await SharedPreferences.getInstance();
    final presetsJson = prefs.getString('metadata_presets');
    if (presetsJson != null) {
      final presets = Map<String, dynamic>.from(jsonDecode(presetsJson));
      presets.remove(presetName);
      await prefs.setString('metadata_presets', jsonEncode(presets));

      if (mounted) {
        setState(() {
          savedPresets = presets.keys.toList();
          if (selectedPreset == presetName) {
            selectedPreset = null;
          }
        });
      }
    }
  }

  Widget _buildField(String label, TextEditingController controller,
      {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 1),
        TextField(
          controller: controller,
          style: const TextStyle(fontSize: 11),
          maxLines: maxLines,
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField(String label, String? value,
      List<Map<String, String>> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 1),
        DropdownButtonFormField<String>(
          value: value,
          items: items
              .map((item) => DropdownMenuItem(
                    value: item['code'],
                    child: Text(item['name']!,
                        style: const TextStyle(fontSize: 11)),
                  ))
              .toList(),
          onChanged: onChanged,
          decoration: const InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            filled: false,
          ),
          style: const TextStyle(fontSize: 11, color: Colors.black),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 1000,
        height: 900,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title
            Row(
              children: [
                Icon(Icons.settings, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  'IPTC Metadata Settings',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Select Profile Section
            Text(
              'Select Profile',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                // Dropdown
                Expanded(
                  flex: 2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(2),
                      color: Colors.white,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedPreset,
                        hint: Row(
                          children: [
                            Icon(Icons.settings,
                                size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Text('Select an IPTC profile',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                        items: [
                          ...savedPresets.map((preset) => DropdownMenuItem(
                                value: preset,
                                child: Row(
                                  children: [
                                    Icon(Icons.settings,
                                        size: 16, color: Colors.grey.shade600),
                                    const SizedBox(width: 6),
                                    Text(preset,
                                        style: const TextStyle(fontSize: 11)),
                                  ],
                                ),
                              )),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _loadPreset(value);
                          }
                        },
                        selectedItemBuilder: (context) => [
                          Row(
                            children: [
                              Icon(Icons.settings,
                                  size: 16, color: Colors.grey.shade600),
                              const SizedBox(width: 6),
                              Text('Select an IPTC profile',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Save as Template button
                ElevatedGreyButton(
                  label: 'Save as Template',
                  fontSize: 11,
                  onPressed: _savePreset,
                ),
                const SizedBox(width: 8),
                ElevatedGreyButton(
                  label: 'Load IPTC from JPG',
                  fontSize: 11,
                  onPressed: _loadIptcFromJpg,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Caption Style Section
            Text(
              'Caption Style',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                AppCompactCheckbox(
                  value: selectedCaptionStyle == 'getty',
                  onChanged: (value) {
                    setState(() {
                      selectedCaptionStyle = value ? 'getty' : null;
                    });
                  },
                ),
                const SizedBox(width: 6),
                Text(
                  'Getty Style',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Divider line under Getty Style
            Container(
              height: 1,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),

            // IPTC Fields Section
            Text(
              'IPTC Metadata Fields',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 6),

            // Caption and Personality fields row
            Row(
              children: [
                // Caption box (2/3 width - spans 2 grid columns)
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    height: 80,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(2),
                      color: Colors.white,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Caption',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: captionController,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 11),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Personality field (1/3 width - spans 1 grid column)
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    height: 80,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(2),
                      color: Colors.white,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Personality',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: personalityController,
                          maxLines: 2,
                          style: const TextStyle(fontSize: 11),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Generate Caption button under caption box
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                ElevatedGreyButton(
                  label: 'Generate Caption from IPTC',
                  fontSize: 11,
                  onPressed: _generateCaption,
                ),
                if (detectedDate != null) ...[
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today,
                          size: 12, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'Date detected: ${_formatDate(detectedDate!)}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),

            // IPTC fields grid
            LayoutBuilder(builder: (context, constraints) {
              const int columns = 3;
              const int rows = 10;
              const double gap = 6.0;
              final double columnWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;

              final List<Widget> items = [
                _buildField('Photographer', creatorController),
                _buildField('MEID', jobIdController),
                _buildField(
                    'Description Writers', descriptionWritersController),
                _buildField('Creator\'s Job Title', creatorJobTitleController),
                _buildField('Copyright', copyrightController),
                _buildField('Credit', creditController),
                _buildField('Source', sourceController),
                _buildField('Headline', headlineController),
                _buildField('Keywords', keywordsController),
                _buildField('Supp Cat 1', suppCat1Controller),
                _buildField('Supp Cat 2', suppCat2Controller),
                _buildField('Supp Cat 3', suppCat3Controller),
                _buildField('Category', categoryController),
                _buildField('Object Name', titleObjectNameController),
                _buildField('Stadium', stadiumController),
                _buildField('City', cityController),
                _buildField('Province/State', provinceController),
                _buildField(
                    'Special Instructions', specialInstructionsController,
                    maxLines: 1),
              ];

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: items.asMap().entries.map((entry) {
                    final index = entry.key;
                    final widget = entry.value;
                    final isSpecialInstructions = index ==
                        items.length - 1; // Last item is Special Instructions

                    return Container(
                      width: columnWidth,
                      height: 45, // All fields same height now
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      child: widget,
                    );
                  }).toList(),
                ),
              );
            }),

            const SizedBox(height: 12),

            // Divider line above buttons
            Container(
              height: 1,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedGreyButton(
                  label: 'Cancel',
                  fontSize: 11,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                ElevatedGreyButton(
                  label: 'Apply Template',
                  fontSize: 11,
                  isPrimary: true,
                  onPressed: _saveSettings,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadIptcFromJpg() async {
    try {
      // Get the last used directory
      final prefs = await SharedPreferences.getInstance();
      final lastDirectory = prefs.getString('last_iptc_folder');

      // Pick a JPG file
      final String? filePath = await NativeFilePicker.pickFile(
        allowedExtensions: ['jpg', 'jpeg'],
        initialDirectory: lastDirectory,
      );

      if (filePath == null) {
        return; // User cancelled
      }

      // Save the directory for next time
      final file = File(filePath);
      final directory = file.parent.path;
      await prefs.setString('last_iptc_folder', directory);

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Loading IPTC metadata...'),
              ],
            ),
          );
        },
      );

      // Read all metadata first to see what's available
      final args = <String>['-j', filePath];

      final exifResult = await ExiftoolHelper.run(args);

      // Close loading dialog
      Navigator.of(context).pop();

      if (exifResult == null || !exifResult.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Error reading IPTC metadata: ${exifResult?.stderrText ?? 'Unknown error'}'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Parse JSON response
      print('DEBUG: ExifTool stdout: ${exifResult.stdoutText}');
      final jsonData = jsonDecode(exifResult.stdoutText);
      if (jsonData.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No metadata found in the selected file'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final metadata = jsonData[0]; // First (and only) file
      print('DEBUG: Extracted metadata: $metadata');
      print('DEBUG: Available fields: ${metadata.keys.toList()}');
      print('DEBUG: MEID value: ${metadata['MEID']}');
      print(
          'DEBUG: TransmissionReference value: ${metadata['TransmissionReference']}');
      print('DEBUG: JobID value: ${metadata['JobID']}');
      print('DEBUG: ImageUniqueID value: ${metadata['ImageUniqueID']}');
      print('DEBUG: DocumentName value: ${metadata['DocumentName']}');
      print('DEBUG: Personality field - checking for possible mappings:');
      print('DEBUG: - CaptionWriter: ${metadata['CaptionWriter']}');
      print('DEBUG: - By-lineTitle: ${metadata['By-lineTitle']}');
      print('DEBUG: - CreatorTool: ${metadata['CreatorTool']}');
      print(
          'DEBUG: - XMP-getty:Personality: ${metadata['XMP-getty:Personality']}');
      print('DEBUG: - Personality: ${metadata['Personality']}');

      // Helper function to safely extract string values from metadata
      String _extractString(dynamic value) {
        if (value == null) return '';
        if (value is String) return value;
        if (value is List) {
          return value.map((item) => item.toString()).join('; ');
        }
        return value.toString();
      }

      // Populate the form fields with the extracted metadata using correct ExifTool field names
      setState(() {
        // Load Caption from Caption-Abstract
        captionController.text = _extractString(metadata['Caption-Abstract']) ??
            _extractString(metadata['Description']) ??
            _extractString(metadata['XMP:Description']) ??
            '';

        creatorController.text = _extractString(metadata['By-line']) ??
            _extractString(metadata['Creator']);
        // Load Personality from XMP-getty:Personality (same as main app)
        final xmpGettyPersonality =
            _extractString(metadata['XMP-getty:Personality']);
        final personality = _extractString(metadata['Personality']);
        final xmpPersonality = _extractString(metadata['XMP:Personality']);

        print('DEBUG: - xmpGettyPersonality: "$xmpGettyPersonality"');
        print('DEBUG: - personality: "$personality"');
        print('DEBUG: - xmpPersonality: "$xmpPersonality"');
        print(
            'DEBUG: - Raw metadata["Personality"]: ${metadata['Personality']}');
        print(
            'DEBUG: - Type of metadata["Personality"]: ${metadata['Personality'].runtimeType}');

        // Choose the first non-empty personality value
        final List<String> personalityCandidates = [
          xmpGettyPersonality,
          personality,
          xmpPersonality,
        ];
        final String selectedPersonality = personalityCandidates.firstWhere(
          (p) => p.trim().isNotEmpty,
          orElse: () => '',
        );
        personalityController.text = selectedPersonality;
        print(
            'DEBUG: - Final Personality value loaded: "${personalityController.text}"');
        jobIdController.text =
            _extractString(metadata['OriginalTransmissionReference']) ??
                _extractString(metadata['JobID']) ??
                _extractString(metadata['MEID']) ??
                _extractString(metadata['TransmissionReference']) ??
                _extractString(metadata['ImageUniqueID']) ??
                _extractString(metadata['DocumentName']);
        descriptionWritersController.text =
            _extractString(metadata['CaptionWriter']);
        creatorJobTitleController.text =
            _extractString(metadata['By-lineTitle']) ??
                _extractString(metadata['AuthorsPosition']);
        copyrightController.text =
            _extractString(metadata['CopyrightNotice']) ??
                _extractString(metadata['Copyright']);
        creditController.text = _extractString(metadata['Credit']);
        sourceController.text = _extractString(metadata['Source']);
        headlineController.text = _extractString(metadata['Headline']);
        keywordsController.text = _extractString(metadata['Keywords']);
        // Handle supplemental categories - they come as a list in SupplementalCategories
        final suppCats = metadata['SupplementalCategories'];
        if (suppCats != null) {
          if (suppCats is List) {
            if (suppCats.isNotEmpty) {
              suppCat1Controller.text = suppCats[0].toString();
            }
            if (suppCats.length > 1) {
              suppCat2Controller.text = suppCats[1].toString();
            }
            if (suppCats.length > 2) {
              suppCat3Controller.text = suppCats[2].toString();
            }
          } else {
            // Single string - check if it's comma-separated
            String suppCatsStr = suppCats.toString();
            if (suppCatsStr.contains(',')) {
              // Split comma-separated values
              List<String> parts =
                  suppCatsStr.split(',').map((s) => s.trim()).toList();
              if (parts.isNotEmpty) {
                suppCat1Controller.text = parts[0];
              }
              if (parts.length > 1) {
                suppCat2Controller.text = parts[1];
              }
              if (parts.length > 2) {
                suppCat3Controller.text = parts[2];
              }
            } else {
              // Single value, put in first field
              suppCat1Controller.text = suppCatsStr;
              suppCat2Controller.text = '';
              suppCat3Controller.text = '';
            }
          }
        } else {
          // Try individual fields as fallback
          suppCat1Controller.text =
              _extractString(metadata['SupplementalCategories1']);
          suppCat2Controller.text =
              _extractString(metadata['SupplementalCategories2']);
          suppCat3Controller.text =
              _extractString(metadata['SupplementalCategories3']);
        }
        categoryController.text = _extractString(metadata['Category']);
        titleObjectNameController.text = _extractString(metadata['ObjectName']);
        stadiumController.text = _extractString(metadata['Sub-location']);
        cityController.text = _extractString(metadata['City']);
        provinceController.text = _extractString(metadata['Province-State']);
        specialInstructionsController.text =
            _extractString(metadata['SpecialInstructions']);

        // Load date and time from metadata
        final dateTimeOriginal = _extractString(metadata['DateTimeOriginal']);
        final createDate = _extractString(metadata['CreateDate']);
        final dateCreated = _extractString(metadata['DateCreated']);

        // Use the first available date/time field
        final dateTimeString = dateTimeOriginal.isNotEmpty
            ? dateTimeOriginal
            : createDate.isNotEmpty
                ? createDate
                : dateCreated.isNotEmpty
                    ? dateCreated
                    : '';

        if (dateTimeString.isNotEmpty) {
          try {
            // Parse the date string (format: YYYY:MM:DD HH:MM:SS or YYYY:MM:DD)
            final parts = dateTimeString.split(' ');
            if (parts.isNotEmpty) {
              final datePart = parts[0].replaceAll(':', '-');
              dateController.text = datePart;

              if (parts.length > 1) {
                final timePart = parts[1];
                // Convert 24-hour time to 12-hour format with AM/PM
                final timeComponents = timePart.split(':');
                if (timeComponents.length >= 3) {
                  int hour = int.parse(timeComponents[0]);
                  final minute = timeComponents[1];
                  final second = timeComponents[2];
                  final period = hour >= 12 ? 'PM' : 'AM';

                  // Convert to 12-hour format
                  if (hour == 0) {
                    hour = 12;
                  } else if (hour > 12) {
                    hour -= 12;
                  }

                  final formattedTime = '$hour:$minute:$second $period';
                  timeController.text = formattedTime;
                }
              }
            }
          } catch (e) {
            print('Error parsing date/time: $e');
          }
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'IPTC metadata loaded from ${File(filePath).uri.pathSegments.last}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Close loading dialog if it's still open
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading IPTC metadata: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _generateCaption() {
    // Build caption based on IPTC metadata in Getty style
    final List<String> captionParts = [];

    // Add city if available
    if (cityController.text.isNotEmpty) {
      captionParts.add(cityController.text.toUpperCase());
    }

    // Add date if available (use detected date first, then fallback to date field)
    DateTime? dateToUse;
    if (detectedDate != null) {
      dateToUse = detectedDate;
    } else if (dateController.text.isNotEmpty) {
      try {
        dateToUse = DateTime.parse(dateController.text);
      } catch (e) {
        // If date parsing fails, skip it
      }
    }

    if (dateToUse != null) {
      final month = _getMonthName(dateToUse.month).toUpperCase();
      final day = dateToUse.day;
      final year = dateToUse.year;
      captionParts.add('- $month $day:');
    }

    // Add placeholder for caption content
    captionParts.add('<<enter caption here>>');

    // Add location/stadium if available
    if (stadiumController.text.isNotEmpty) {
      captionParts.add('at ${stadiumController.text}');
    }

    // Add date and location info
    if (dateToUse != null) {
      final month = _getMonthName(dateToUse.month);
      final day = dateToUse.day;
      final year = dateToUse.year;
      captionParts.add('on $month $day, $year');
    }

    // Add city again for location
    if (cityController.text.isNotEmpty) {
      captionParts.add('in ${cityController.text}.');
    }

    // Add photographer credit
    if (creatorController.text.isNotEmpty) {
      String credit = '(Photo by ${creatorController.text}';
      if (creditController.text.isNotEmpty) {
        credit += '/${creditController.text}';
      }
      credit += ')';
      captionParts.add(credit);
    }

    // Combine all parts
    final generatedCaption = captionParts.join(' ');

    // Set the caption
    setState(() {
      captionController.text = generatedCaption;
    });

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Caption generated from IPTC metadata!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return months[month - 1];
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  @override
  void dispose() {
    creatorController.dispose();
    jobIdController.dispose();
    descriptionWritersController.dispose();
    creatorJobTitleController.dispose();
    copyrightController.dispose();
    creditController.dispose();
    sourceController.dispose();
    headlineController.dispose();
    keywordsController.dispose();
    suppCat1Controller.dispose();
    suppCat2Controller.dispose();
    suppCat3Controller.dispose();
    categoryController.dispose();
    titleObjectNameController.dispose();
    stadiumController.dispose();
    cityController.dispose();
    provinceController.dispose();

    specialInstructionsController.dispose();
    personalityController.dispose();
    captionController.dispose();
    dateController.dispose();
    timeController.dispose();
    presetNameController.dispose();
    super.dispose();
  }
}
