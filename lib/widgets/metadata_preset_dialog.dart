import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class MetadataPresetDialog extends StatefulWidget {
  final Map<String, String>? currentPreset;

  const MetadataPresetDialog({Key? key, this.currentPreset}) : super(key: key);

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
  final TextEditingController countryController = TextEditingController();
  final TextEditingController countryCodeController = TextEditingController();
  final TextEditingController urgencyController = TextEditingController();
  final TextEditingController specialInstructionsController =
      TextEditingController();

  // Preset management
  final TextEditingController presetNameController = TextEditingController();
  List<String> savedPresets = [];
  String? selectedPreset;
  String? selectedCaptionStyle = 'getty';

  // Urgency levels for dropdown
  final List<Map<String, String>> urgencyLevels = [
    {'code': '1', 'name': '1 - High'},
    {'code': '2', 'name': '2'},
    {'code': '3', 'name': '3'},
    {'code': '4', 'name': '4'},
    {'code': '5', 'name': '5 - Normal'},
    {'code': '6', 'name': '6'},
    {'code': '7', 'name': '7'},
    {'code': '8', 'name': '8 - Low'},
    {'code': '0', 'name': '0 - Undefined'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedPresets();
    _loadCurrentPreset();
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

  void _loadCurrentPreset() {
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
      countryController.text = widget.currentPreset!['Country'] ?? '';
      countryCodeController.text = widget.currentPreset!['Country Code'] ?? '';
      urgencyController.text = widget.currentPreset!['Urgency'] ?? '';
      specialInstructionsController.text =
          widget.currentPreset!['Special Instructions'] ?? '';
    }
  }

  Future<void> _savePreset() async {
    final presetName = presetNameController.text.trim();
    if (presetName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a preset name')),
      );
      return;
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
      'Country': countryController.text,
      'Country Code': countryCodeController.text,
      'Urgency': urgencyController.text,
      'Special Instructions': specialInstructionsController.text,
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
          countryController.text = presetData['Country'] ?? '';
          countryCodeController.text = presetData['Country Code'] ?? '';
          urgencyController.text = presetData['Urgency'] ?? '';
          specialInstructionsController.text =
              presetData['Special Instructions'] ?? '';
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Container(
        width: 900,
        height: 800,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title
            Row(
              children: [
                Icon(Icons.settings, size: 20, color: Colors.grey.shade700),
                const SizedBox(width: 8),
                Text(
                  'IPTC Metadata Settings',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
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
                ),
              ),
            ),
            const SizedBox(height: 16),

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
                Checkbox(
                  value: selectedCaptionStyle == 'getty',
                  onChanged: (value) {
                    setState(() {
                      selectedCaptionStyle = value == true ? 'getty' : null;
                    });
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                Text(
                  'Getty Style',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

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
                // Caption box (75% width)
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    height: 80,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(4),
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
                const SizedBox(width: 10),
                // Personality field (25% width)
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    height: 80,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(4),
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
                _buildField('Country', countryController),
                _buildField('Country Code', countryCodeController),
                _buildDropdownField(
                  'Urgency',
                  urgencyController.text.isNotEmpty
                      ? urgencyController.text
                      : null,
                  urgencyLevels,
                  (value) {
                    setState(() {
                      urgencyController.text = value ?? '';
                    });
                  },
                ),
              ];

              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: items
                    .map((w) => Container(
                          width: columnWidth,
                          height: 45,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          child: w,
                        ))
                    .toList(),
              );
            }),

            // Special Instructions field as full-width row
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.white,
                ),
                child: _buildField(
                    'Special Instructions', specialInstructionsController,
                    maxLines: 2),
              ),
            ),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: _savePreset,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade300,
                    foregroundColor: Colors.black87,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  child: const Text('Save as Template',
                      style: TextStyle(fontSize: 12)),
                ),
                ElevatedButton(
                  onPressed: _loadIptcFromJpg,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade300,
                    foregroundColor: Colors.black87,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  child: const Text('Load IPTC from JPG',
                      style: TextStyle(fontSize: 12)),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child:
                          const Text('Cancel', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _savePreset,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                      ),
                      child: const Text('Save Settings',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadIptcFromJpg() async {
    // TODO: Implement file picker and IPTC loading logic
    // This will need to be connected to the main app's file selection
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Load IPTC from JPG - Coming soon!')),
    );
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
    countryController.dispose();
    countryCodeController.dispose();
    urgencyController.dispose();
    specialInstructionsController.dispose();
    presetNameController.dispose();
    super.dispose();
  }
}
