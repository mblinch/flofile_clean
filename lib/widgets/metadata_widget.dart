import 'package:flutter/material.dart';

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
  final descriptionWritersController = TextEditingController();
  final headlineController = TextEditingController();
  final keywordsController = TextEditingController();
  final creatorController = TextEditingController();
  final creatorJobTitleController = TextEditingController();
  final creditController = TextEditingController();
  final copyrightController = TextEditingController();
  final sourceController = TextEditingController();

  // IPTC metadata controllers
  final urgencyController = TextEditingController();
  final countryController = TextEditingController();
  final countryCodeController = TextEditingController();

  // Location controllers
  final stadiumController = TextEditingController();
  final cityController = TextEditingController();
  final provinceController = TextEditingController();

  // Location and categorization controllers
  final titleObjectNameController = TextEditingController();
  final categoryController = TextEditingController();
  final suppCat1Controller = TextEditingController();
  final suppCat2Controller = TextEditingController();
  final suppCat3Controller = TextEditingController();
  final specialInstructionsController = TextEditingController();

  // Country codes for dropdown
  final List<Map<String, String>> countryCodes = [
    {'code': 'CAN', 'name': 'Canada'},
    {'code': 'USA', 'name': 'United States'},
    {'code': 'MEX', 'name': 'Mexico'},
    {'code': 'GBR', 'name': 'United Kingdom'},
    {'code': 'FRA', 'name': 'France'},
    {'code': 'DEU', 'name': 'Germany'},
    {'code': 'ITA', 'name': 'Italy'},
    {'code': 'ESP', 'name': 'Spain'},
    {'code': 'NLD', 'name': 'Netherlands'},
    {'code': 'BEL', 'name': 'Belgium'},
    {'code': 'CHE', 'name': 'Switzerland'},
    {'code': 'AUT', 'name': 'Austria'},
    {'code': 'SWE', 'name': 'Sweden'},
    {'code': 'NOR', 'name': 'Norway'},
    {'code': 'DNK', 'name': 'Denmark'},
    {'code': 'FIN', 'name': 'Finland'},
    {'code': 'JPN', 'name': 'Japan'},
    {'code': 'KOR', 'name': 'South Korea'},
    {'code': 'CHN', 'name': 'China'},
    {'code': 'AUS', 'name': 'Australia'},
    {'code': 'NZL', 'name': 'New Zealand'},
    {'code': 'BRA', 'name': 'Brazil'},
    {'code': 'ARG', 'name': 'Argentina'},
    {'code': 'ZAF', 'name': 'South Africa'},
    {'code': 'EGY', 'name': 'Egypt'},
    {'code': 'NGA', 'name': 'Nigeria'},
    {'code': 'KEN', 'name': 'Kenya'},
    {'code': 'IND', 'name': 'India'},
    {'code': 'PAK', 'name': 'Pakistan'},
    {'code': 'BGD', 'name': 'Bangladesh'},
    {'code': 'THA', 'name': 'Thailand'},
    {'code': 'VNM', 'name': 'Vietnam'},
    {'code': 'PHL', 'name': 'Philippines'},
    {'code': 'IDN', 'name': 'Indonesia'},
    {'code': 'MYS', 'name': 'Malaysia'},
    {'code': 'SGP', 'name': 'Singapore'},
    {'code': 'HKG', 'name': 'Hong Kong'},
    {'code': 'TWN', 'name': 'Taiwan'},
  ];

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
  void didUpdateWidget(MetadataWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.metadata != oldWidget.metadata) {
      _loadMetadata();
    }
  }

  // Method to get current values from all controllers
  Map<String, String> getCurrentValues() {
    return {
      'TransmissionReference': jobIdController.text,
      'CaptionWriter': descriptionWritersController.text,
      'Headline': headlineController.text,
      'Keywords': keywordsController.text,
      'Creator': creatorController.text,
      'AuthorsPosition': creatorJobTitleController.text,
      'Credit': creditController.text,
      'Copyright': copyrightController.text,
      'Source': sourceController.text,
      'Urgency': urgencyController.text,
      'Country': countryController.text,
      'CountryCode': countryCodeController.text,
      'Sub-location': stadiumController.text,
      'City': cityController.text,
      'Province-State': provinceController.text,
      'ObjectName': titleObjectNameController.text,
      'Category': categoryController.text,
      'SupplementalCategories1': suppCat1Controller.text,
      'SupplementalCategories2': suppCat2Controller.text,
      'SupplementalCategories3': suppCat3Controller.text,
      'SpecialInstructions': specialInstructionsController.text,
    };
  }

  void _loadMetadata() {
    if (widget.metadata == null) return;

    final meta = widget.metadata!;

    setState(() {
      // Load Getty metadata fields
      jobIdController.text = meta['TransmissionReference']?.toString() ?? '';

      // Load Description Writer from CaptionWriter (Photoshop XMP field)
      descriptionWritersController.text =
          meta['CaptionWriter']?.toString() ?? '';

      headlineController.text = meta['Headline']?.toString() ?? '';

      // Handle Keywords properly - convert arrays to comma-separated strings
      final keywords = meta['Keywords'];
      if (keywords is List) {
        keywordsController.text = keywords.join(', ');
      } else {
        keywordsController.text = keywords?.toString() ?? '';
      }

      final extractedCreator = meta['Creator']?.toString() ?? '';
      if (extractedCreator.isNotEmpty) {
        creatorController.text = extractedCreator;
      }

      // Load Creator's Job Title from AuthorsPosition (Photoshop XMP field)
      creatorJobTitleController.text =
          meta['AuthorsPosition']?.toString() ?? '';

      final extractedCredit = meta['Credit']?.toString() ?? '';
      if (extractedCredit.isNotEmpty) {
        creditController.text = extractedCredit;
      }

      final extractedCopyright = meta['Copyright']?.toString() ?? '';
      if (extractedCopyright.isNotEmpty) {
        copyrightController.text = extractedCopyright;
      }

      final extractedSource = meta['Source']?.toString() ?? '';
      if (extractedSource.isNotEmpty) {
        sourceController.text = extractedSource;
      }

      // Load IPTC metadata fields only if they exist
      // Extract urgency number from descriptive text like "5 (normal urgency)"
      final urgencyValue = meta['Urgency']?.toString() ?? '';
      if (urgencyValue.isNotEmpty) {
        // Extract just the number from "5 (normal urgency)" format
        final match = RegExp(r'^(\d+)').firstMatch(urgencyValue);
        urgencyController.text = match?.group(1) ?? '';
      } else {
        urgencyController.text = '';
      }
      countryController.text = meta['Country']?.toString() ?? '';
      countryCodeController.text = meta['CountryCode']?.toString() ?? '';

      // Load categorization metadata
      titleObjectNameController.text = meta['ObjectName']?.toString() ?? '';
      categoryController.text = meta['Category']?.toString() ?? '';

      // Handle supplemental categories (could be a single string, comma-separated string, or array)
      final suppCats = meta['SupplementalCategories'];
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
          }
        }
      }

      // Load special instructions - try IPTC field first, then XMP field
      final specialInstructions = meta['SpecialInstructions']?.toString() ??
          meta['Instructions']?.toString() ??
          meta['XMP-photoshop:Instructions']?.toString() ??
          '';
      if (specialInstructions.isNotEmpty) {
        specialInstructionsController.text = specialInstructions;
      }

      // Load location fields from JPEG metadata
      final extractedStadium = meta['Sub-location']?.toString() ?? '';
      if (extractedStadium.isNotEmpty) {
        stadiumController.text = extractedStadium;
      }

      final extractedCity = meta['City']?.toString() ?? '';
      if (extractedCity.isNotEmpty) {
        cityController.text = extractedCity;
      }

      final extractedProvince = meta['Province-State']?.toString() ?? '';
      if (extractedProvince.isNotEmpty) {
        provinceController.text = extractedProvince;
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
      child: PopupMenuButton<String>(
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
          height: 40, // Match the height of regular text fields
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Floating label (always visible)
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    // Value text
                    Text(
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
                  ],
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 16),
            ],
          ),
        ),
      ),
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
                          child: _buildField('Creator\'s Job Title',
                              creatorJobTitleController)),
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
                          child: _buildField('Keywords', keywordsController)),
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
