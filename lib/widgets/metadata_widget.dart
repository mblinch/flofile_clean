import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'metadata_preset_dialog.dart';

class MetadataWidget extends StatefulWidget {
  final Map<String, dynamic>? metadata;
  final Function(Map<String, dynamic>?)? onMetadataUpdated;

  const MetadataWidget({
    super.key,
    this.metadata,
    this.onMetadataUpdated,
  });

  @override
  State<MetadataWidget> createState() => _MetadataWidgetState();
}

class _MetadataWidgetState extends State<MetadataWidget> {
  // Getty Images metadata controllers
  final jobIdController = TextEditingController();
  final descriptionWritersController = TextEditingController(text: 'MB');
  final headlineController = TextEditingController();
  final keywordsController = TextEditingController();
  final keywordsTestController = TextEditingController();
  final creatorController = TextEditingController(text: 'Mark Blinch');
  final creatorJobTitleController = TextEditingController(text: 'Contributor');
  final creditController = TextEditingController(text: 'Getty Images');
  final copyrightController = TextEditingController(text: '2025 Mark Blinch');
  final sourceController =
      TextEditingController(text: 'Getty Images North America');

  // IPTC metadata controllers
  final urgencyController = TextEditingController(text: '5');
  final countryController = TextEditingController(text: 'Canada');
  final countryCodeController = TextEditingController(text: 'CAN');

  // Location controllers
  final stadiumController = TextEditingController();
  final cityController = TextEditingController();
  final provinceController = TextEditingController();

  // Date and time controllers
  final dateController = TextEditingController();
  final timeController = TextEditingController();

  // Track if original date/time has been modified
  bool _hasModifiedOriginalDateTime = false;
  String? _originalDateTimeString;

  // Location and categorization controllers
  final titleObjectNameController = TextEditingController();
  final categoryController = TextEditingController();
  final suppCat1Controller = TextEditingController();
  final suppCat2Controller = TextEditingController();
  final suppCat3Controller = TextEditingController();
  final specialInstructionsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMetadataPreset();

    // Wire change listeners so edits notify parent immediately
    void addListener(TextEditingController c) {
      c.addListener(() {
        _notifyMetadataChanged();
      });
    }

    addListener(jobIdController);
    addListener(descriptionWritersController);
    addListener(headlineController);
    addListener(keywordsController);
    addListener(keywordsTestController);
    addListener(creatorController);
    addListener(creatorJobTitleController);
    addListener(creditController);
    addListener(copyrightController);
    addListener(sourceController);

    addListener(stadiumController);
    addListener(cityController);
    addListener(provinceController);
    addListener(dateController);
    addListener(timeController);
    addListener(titleObjectNameController);
    addListener(categoryController);
    addListener(suppCat1Controller);
    addListener(suppCat2Controller);
    addListener(suppCat3Controller);
    addListener(specialInstructionsController);
  }

  Future<void> _loadMetadataPreset() async {
    final prefs = await SharedPreferences.getInstance();
    final presetJson = prefs.getString('selected_metadata_preset');

    if (presetJson != null) {
      try {
        final presetData = jsonDecode(presetJson) as Map<String, dynamic>;

        // Apply preset values to controllers
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

        // Clear the preset after applying it
        await prefs.remove('selected_metadata_preset');

        print('DEBUG: Applied metadata preset successfully');
      } catch (e) {
        print('DEBUG: Error applying metadata preset: $e');
      }
    }
  }

  void _loadMetadata() {
    if (widget.metadata == null) return;

    final meta = widget.metadata!;

    setState(() {
      // Load Getty metadata fields - prefer Photo Mechanic's IPTC fields
      jobIdController.text = (meta['IPTC:OriginalTransmissionReference'] ??
                  meta['OriginalTransmissionReference'] ??
                  meta['TransmissionReference'])
              ?.toString() ??
          '';

      // Load Description Writer from CaptionWriter (Photoshop XMP field)
      descriptionWritersController.text =
          meta['CaptionWriter']?.toString() ?? '';

      headlineController.text =
          (meta['IPTC:Headline'] ?? meta['Headline'])?.toString() ?? '';

      // Handle Keywords strictly from IPTC Keywords (Photo Mechanic's field)
      // Try IPTC:Keywords first, fallback to generic Keywords field
      final keywordsValue = meta['IPTC:Keywords'] ?? meta['Keywords'];
      if (keywordsValue is List) {
        // Remove duplicates and clean the keywords
        final cleanKeywords = keywordsValue
            .map((k) => k.toString().trim())
            .where((k) => k.isNotEmpty)
            .toSet() // Remove duplicates
            .toList();
        keywordsTestController.text = cleanKeywords.join(', ');
      } else if (keywordsValue != null) {
        // NEVER use .toString() on arrays - it creates literal brackets!
        String kwString = keywordsValue.toString();
        // If it looks like an array string, clean it up
        if (kwString.startsWith('[') && kwString.endsWith(']')) {
          kwString = kwString.substring(1, kwString.length - 1);
        }
        // Clean any remaining array artifacts and split by comma
        final cleanKeywords = kwString
            .split(',')
            .map((k) => k.trim())
            .where((k) => k.isNotEmpty)
            .toSet()
            .toList();
        keywordsTestController.text = cleanKeywords.join(', ');
      } else {
        keywordsTestController.text = '';
      }

      // Handle Creator field - prefer Photo Mechanic's IPTC field, could be String or List
      final creatorValue =
          meta['IPTC:By-line'] ?? meta['By-line'] ?? meta['Creator'];
      if (creatorValue != null) {
        if (creatorValue is List) {
          // If it's a list, take the first value only to avoid duplication
          final firstValue =
              creatorValue.isNotEmpty ? creatorValue.first.toString() : '';
          creatorController.text = firstValue;
          print(
              'DEBUG: Creator field loaded from List, using first value: "$firstValue"');
        } else {
          creatorController.text = creatorValue.toString();
          print(
              'DEBUG: Creator field loaded from String: "${creatorController.text}"');
        }
      } else {
        creatorController.text = '';
        print('DEBUG: Creator field is null or empty');
      }

      // Load Creator's Job Title from Photo Mechanic's preferred field
      creatorJobTitleController.text = (meta['IPTC:By-lineTitle'] ??
                  meta['By-lineTitle'] ??
                  meta['AuthorsPosition'])
              ?.toString() ??
          '';

      final extractedCredit =
          (meta['IPTC:Credit'] ?? meta['Credit'])?.toString() ?? '';
      creditController.text = extractedCredit;

      final extractedCopyright = (meta['IPTC:CopyrightNotice'] ??
                  meta['CopyrightNotice'] ??
                  meta['Copyright'])
              ?.toString() ??
          '';
      copyrightController.text = extractedCopyright;

      final extractedSource =
          (meta['IPTC:Source'] ?? meta['Source'])?.toString() ?? '';
      sourceController.text = extractedSource;

      // Load IPTC metadata fields only if they exist - prefer Photo Mechanic's fields

      // Load categorization metadata - prefer Photo Mechanic's fields
      titleObjectNameController.text = (meta['IPTC:ObjectName'] ??
              meta['ObjectName'] ??
              meta['XMP:Title'])
          ?.toString() ??
          '';
      categoryController.text =
          (meta['IPTC:Category'] ?? meta['Category'])?.toString() ?? '';

      // Handle supplemental categories from multiple possible keys
      List<String> supplementalValues = [];
      final dynamic sc1 = meta['SupplementalCategories'];
      final dynamic sc2 = meta['IPTC:SupplementalCategory'];
      final dynamic sc3 = meta['XMP-photoshop:SupplementalCategories'];

      print('DEBUG: Loading supplemental categories:');
      print('  SupplementalCategories: $sc1 (${sc1.runtimeType})');
      print('  IPTC:SupplementalCategory: $sc2 (${sc2.runtimeType})');
      print(
          '  XMP-photoshop:SupplementalCategories: $sc3 (${sc3.runtimeType})');
      print('DEBUG: All metadata keys: ${meta.keys.toList()}');

      // The issue is ExifTool is only returning the last value instead of comma-separated
      // Let's check if sc1 should be split but isn't being detected properly
      if (sc1 != null && sc1.toString() == 'BBN') {
        print(
            'DEBUG: FOUND THE BUG! ExifTool returning only last value instead of "SPO,BBA,BBN"');
      }

      void _collect(dynamic v) {
        if (v == null) return;
        if (v is List) {
          supplementalValues.addAll(v.map((e) => e.toString()));
        } else {
          final s = v.toString();
          if (s.contains(',')) {
            supplementalValues.addAll(s.split(',').map((e) => e.trim()));
          } else if (s.isNotEmpty) {
            supplementalValues.add(s);
          }
        }
      }

      _collect(sc1);
      _collect(sc2);
      _collect(sc3);

      // Deduplicate while preserving order
      final seen = <String>{};
      supplementalValues =
          supplementalValues.where((e) => seen.add(e)).toList(growable: false);

      // Assign to controllers
      suppCat1Controller.text =
          supplementalValues.isNotEmpty ? supplementalValues[0] : '';
      suppCat2Controller.text =
          supplementalValues.length > 1 ? supplementalValues[1] : '';
      suppCat3Controller.text =
          supplementalValues.length > 2 ? supplementalValues[2] : '';

      // Load special instructions - prefer Photo Mechanic's IPTC field, then fallback
      final specialInstructions =
          (meta['IPTC:SpecialInstructions'] ?? meta['SpecialInstructions'])
                  ?.toString() ??
              meta['Instructions']?.toString() ??
              meta['XMP-photoshop:Instructions']?.toString() ??
              '';
      // Always assign (clears when empty)
      specialInstructionsController.text = specialInstructions;

      // Load location fields from JPEG metadata - prefer Photo Mechanic's IPTC fields
      final extractedStadium = (meta['IPTC:SubLocation'] ??
                  meta['SubLocation'] ??
                  meta['Sub-location'])
              ?.toString() ??
          '';
      stadiumController.text = extractedStadium;

      final extractedCity =
          (meta['IPTC:City'] ?? meta['City'])?.toString() ?? '';
      cityController.text = extractedCity;

      final extractedProvince = (meta['IPTC:ProvinceState'] ??
                  meta['ProvinceState'] ??
                  meta['Province-State'])
              ?.toString() ??
          '';
      provinceController.text = extractedProvince;

      // Load date and time from metadata
      final dateTimeOriginal = meta['DateTimeOriginal']?.toString() ?? '';
      final createDate = meta['CreateDate']?.toString() ?? '';
      final modifyDate = meta['ModifyDate']?.toString() ?? '';
      final timeDate = meta['TimeDate']?.toString() ?? '';

      // Use the first available date/time field
      final dateTimeString = dateTimeOriginal.isNotEmpty
          ? dateTimeOriginal
          : createDate.isNotEmpty
              ? createDate
              : modifyDate.isNotEmpty
                  ? modifyDate
                  : timeDate;

      if (dateTimeString.isNotEmpty) {
        try {
          // Parse the date string (format: YYYY:MM:DD HH:MM:SS)
          final parts = dateTimeString.split(' ');
          if (parts.length >= 2) {
            final datePart = parts[0].replaceAll(':', '-');
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
            } else if (timeComponents.length >= 2) {
              int hour = int.parse(timeComponents[0]);
              final minute = timeComponents[1];
              final period = hour >= 12 ? 'PM' : 'AM';

              // Convert to 12-hour format
              if (hour == 0) {
                hour = 12;
              } else if (hour > 12) {
                hour -= 12;
              }

              final formattedTime = '$hour:$minute:00 $period';
              timeController.text = formattedTime;
            } else {
              timeController.text = timePart;
            }

            dateController.text = datePart;

            // Store original date/time for comparison
            _originalDateTimeString = '$datePart ${timeController.text}';
            _hasModifiedOriginalDateTime = false;
          }
        } catch (e) {
          print('Error parsing date/time: $e');
        }
      }
    });
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    int? maxLines = 1,
    bool expands = false,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      expands: expands,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: 'Enter $label...',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: Colors.grey.shade400),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: Colors.grey.shade400),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: Colors.blue.shade400, width: 2),
        ),
        contentPadding: const EdgeInsets.all(8),
        filled: true,
        fillColor: Colors.grey.shade50,
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildDropdownField(
    String label,
    String? value,
    List<Map<String, String>> items,
    ValueChanged<String?> onChanged,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(6),
        color: Colors.grey.shade50,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Floating label
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ),
          // Dropdown content
          PopupMenuButton<String>(
            initialValue: value,
            onSelected: onChanged,
            constraints: const BoxConstraints(maxHeight: 300),
            itemBuilder: (context) => items
                .map(
                  (item) => PopupMenuItem<String>(
                    value: item['code'],
                    height: 32,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      item['name']!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                )
                .toList(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value != null
                          ? items.firstWhere((item) => item['code'] == value,
                              orElse: () => {'name': 'Select'})['name']!
                          : 'Select $label',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            value != null ? Colors.black : Colors.grey.shade600,
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
      ),
    );
  }

  Widget _buildDateField() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 70,
          alignment: Alignment.topLeft,
          child: const Text(
            'Date',
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: () async {
              await _showDatePicker();
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: Colors.white,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      dateController.text.isNotEmpty
                          ? dateController.text
                          : 'Select Date',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 10,
                        color: dateController.text.isNotEmpty
                            ? Colors.black
                            : Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.calendar_today, size: 16),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeField() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 70,
          alignment: Alignment.topLeft,
          child: const Text(
            'Time',
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: () async {
              await _showTimePicker();
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: Colors.white,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      timeController.text.isNotEmpty
                          ? timeController.text
                          : 'Select Time',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 10,
                        color: timeController.text.isNotEmpty
                            ? Colors.black
                            : Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.access_time, size: 16),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 1.0),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.black87),
                const SizedBox(width: 8),
                const Text(
                  'Metadata',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),

          // Main content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Getty Images metadata fields
                  Row(
                    children: [
                      Expanded(
                          child: _buildField('Creator', creatorController)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildField('MEID', jobIdController)),
                      const SizedBox(width: 8),
                      SizedBox(
                          width: 120,
                          child: _buildField('Description Writers',
                              descriptionWritersController)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildField(
                              'Job Title', creatorJobTitleController)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildField('Copyright', copyrightController)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _buildField('Credit', creditController)),
                      const SizedBox(width: 8),
                      Expanded(child: _buildField('Source', sourceController)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          child: _buildField('Headline', headlineController)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildField(
                              'Keywords (Test)', keywordsTestController)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          child: _buildField(
                              'Object Name', titleObjectNameController)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildField('Category', categoryController)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                          child: _buildField('Supp Cat 1', suppCat1Controller)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildField('Supp Cat 2', suppCat2Controller)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildField('Supp Cat 3', suppCat3Controller)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildField(
                      'Special Instructions', specialInstructionsController,
                      maxLines: 2),
                  const SizedBox(height: 8),

                  // IPTC metadata fields
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdownField(
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
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildField('Country', countryController)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDropdownField(
                          'Country Code',
                          countryCodeController.text.isNotEmpty
                              ? countryCodeController.text
                              : null,
                          countryCodes,
                          (value) {
                            setState(() {
                              countryCodeController.text = value ?? '';
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Location fields
                  Row(
                    children: [
                      Expanded(child: _buildField('City', cityController)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildField(
                              'Province/State', provinceController)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildField('Stadium', stadiumController),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    jobIdController.dispose();
    descriptionWritersController.dispose();
    headlineController.dispose();
    keywordsController.dispose();
    keywordsTestController.dispose();
    creatorController.dispose();
    creatorJobTitleController.dispose();
    creditController.dispose();
    copyrightController.dispose();
    sourceController.dispose();
    urgencyController.dispose();
    countryController.dispose();
    countryCodeController.dispose();
    stadiumController.dispose();
    cityController.dispose();
    provinceController.dispose();
    titleObjectNameController.dispose();
    categoryController.dispose();
    suppCat1Controller.dispose();
    suppCat2Controller.dispose();
    suppCat3Controller.dispose();
    specialInstructionsController.dispose();
    super.dispose();
  }
}
