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
    final values = {
      // IPTC fields
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
      'Date': dateController.text,
      'Time': timeController.text,
      'ObjectName': titleObjectNameController.text,
      'Category': categoryController.text,
      'SupplementalCategories1': suppCat1Controller.text,
      'SupplementalCategories2': suppCat2Controller.text,
      'SupplementalCategories3': suppCat3Controller.text,
      'SpecialInstructions': specialInstructionsController.text,

      // XMP equivalents for Photo Mechanic compatibility
      'XMP:Title': headlineController.text,
      'XMP:Subject': keywordsController.text,
      'XMP:Creator': creatorController.text,
      'XMP:Rights': copyrightController.text,
      'XMP:Source': sourceController.text,
      'XMP:Country': countryController.text,
      'XMP:State': provinceController.text,
      'XMP:City': cityController.text,
      'XMP:Location': stadiumController.text,
      'XMP:Instructions': specialInstructionsController.text,
    };

    // If original date/time has been modified, include the EXIF fields
    if (_hasModifiedOriginalDateTime &&
        dateController.text.isNotEmpty &&
        timeController.text.isNotEmpty) {
      try {
        // Convert back to EXIF format (YYYY:MM:DD HH:MM:SS)
        final dateParts = dateController.text.split('-');
        final timeParts = timeController.text.split(' ');
        final timeComponent = timeParts[0];
        final period = timeParts[1];
        final hourMinute = timeComponent.split(':');

        if (dateParts.length >= 3 && hourMinute.length >= 2) {
          int hour = int.parse(hourMinute[0]);
          final minute = hourMinute[1];
          String second = '00';

          // Extract seconds if available
          if (hourMinute.length >= 3) {
            second = hourMinute[2];
          }

          // Convert to 24-hour format
          if (period == 'PM' && hour != 12) {
            hour += 12;
          } else if (period == 'AM' && hour == 12) {
            hour = 0;
          }

          final exifDateTime =
              '${dateParts[0]}:${dateParts[1]}:${dateParts[2]} ${hour.toString().padLeft(2, '0')}:$minute:$second';

          // Add the original EXIF fields
          values['DateTimeOriginal'] = exifDateTime;
          values['CreateDate'] = exifDateTime;
          values['ModifyDate'] = exifDateTime;
        }
      } catch (e) {
        print('Error converting date/time to EXIF format: $e');
      }
    }

    return values;
  }

  // Show calendar picker for date selection
  Future<void> _showDatePicker() async {
    DateTime? currentDate;

    // Try to parse current date from controller
    if (dateController.text.isNotEmpty) {
      try {
        currentDate = DateTime.parse(dateController.text);
      } catch (e) {
        print('Error parsing current date: $e');
      }
    }

    // Default to today if no valid date
    currentDate ??= DateTime.now();

    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: Colors.blue.shade600,
                ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      // Check if this would modify the original date/time
      if (_originalDateTimeString != null && !_hasModifiedOriginalDateTime) {
        final shouldProceed = await _showDateTimeModificationWarning();
        if (!shouldProceed) {
          return;
        }
      }

      setState(() {
        dateController.text =
            '${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}';
        _checkForOriginalDateTimeModification();
      });
    }
  }

  // Show warning dialog when modifying original capture date/time
  Future<bool> _showDateTimeModificationWarning() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Modify Original Capture Time?'),
                ],
              ),
              content: const Text(
                'You are about to change the original capture date and time of this image. '
                'This will modify the EXIF data that records when the photo was actually taken. '
                'Are you sure you want to proceed?',
                style: TextStyle(fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Yes, Modify Original'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  // Check if the date/time has been modified from original
  void _checkForOriginalDateTimeModification() {
    if (_originalDateTimeString != null) {
      final currentDateTimeString =
          '${dateController.text} ${timeController.text}';
      if (currentDateTimeString != _originalDateTimeString) {
        _hasModifiedOriginalDateTime = true;
      }
    }
  }

  // Show time picker
  Future<void> _showTimePicker() async {
    TimeOfDay? currentTime;
    int currentSeconds = 0;

    // Try to parse current time from controller
    if (timeController.text.isNotEmpty) {
      try {
        final timeParts = timeController.text.split(' ');
        if (timeParts.length >= 2) {
          final timeComponent = timeParts[0];
          final period = timeParts[1];
          final hourMinuteSecond = timeComponent.split(':');

          if (hourMinuteSecond.length >= 3) {
            int hour = int.parse(hourMinuteSecond[0]);
            final minute = int.parse(hourMinuteSecond[1]);
            currentSeconds = int.parse(hourMinuteSecond[2]);

            // Convert to 24-hour format for TimeOfDay
            if (period == 'PM' && hour != 12) {
              hour += 12;
            } else if (period == 'AM' && hour == 12) {
              hour = 0;
            }

            currentTime = TimeOfDay(hour: hour, minute: minute);
          } else if (hourMinuteSecond.length >= 2) {
            int hour = int.parse(hourMinuteSecond[0]);
            final minute = int.parse(hourMinuteSecond[1]);

            // Convert to 24-hour format for TimeOfDay
            if (period == 'PM' && hour != 12) {
              hour += 12;
            } else if (period == 'AM' && hour == 12) {
              hour = 0;
            }

            currentTime = TimeOfDay(hour: hour, minute: minute);
          }
        }
      } catch (e) {
        print('Error parsing current time: $e');
      }
    }

    // Default to current time if no valid time
    currentTime ??= TimeOfDay.now();

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: currentTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: Colors.blue.shade600,
                ),
          ),
          child: child!,
        );
      },
    );

    if (pickedTime != null) {
      // Check if this would modify the original date/time
      if (_originalDateTimeString != null && !_hasModifiedOriginalDateTime) {
        final shouldProceed = await _showDateTimeModificationWarning();
        if (!shouldProceed) {
          return;
        }
      }

      setState(() {
        final hour = pickedTime.hour;
        final minute = pickedTime.minute.toString().padLeft(2, '0');
        final second = currentSeconds.toString().padLeft(2, '0');
        final period = hour >= 12 ? 'PM' : 'AM';

        // Convert to 12-hour format
        int displayHour = hour;
        if (hour == 0) {
          displayHour = 12;
        } else if (hour > 12) {
          displayHour = hour - 12;
        }

        timeController.text = '$displayHour:$minute:$second $period';
        _checkForOriginalDateTimeModification();
      });
    }
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

      // Handle Creator field - could be String or List
      final creatorValue = meta['Creator'];
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

      // Load Creator's Job Title from AuthorsPosition (Photoshop XMP field)
      creatorJobTitleController.text =
          meta['AuthorsPosition']?.toString() ?? '';

      final extractedCredit = meta['Credit']?.toString() ?? '';
      creditController.text = extractedCredit;

      final extractedCopyright = meta['Copyright']?.toString() ?? '';
      copyrightController.text = extractedCopyright;

      final extractedSource = meta['Source']?.toString() ?? '';
      sourceController.text = extractedSource;

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
            suppCat2Controller.text = '';
            suppCat3Controller.text = '';
          }
        }
      } else {
        // Explicitly clear when not present
        suppCat1Controller.text = '';
        suppCat2Controller.text = '';
        suppCat3Controller.text = '';
      }

      // Load special instructions - try IPTC field first, then XMP field
      final specialInstructions = meta['SpecialInstructions']?.toString() ??
          meta['Instructions']?.toString() ??
          meta['XMP-photoshop:Instructions']?.toString() ??
          '';
      // Always assign (clears when empty)
      specialInstructionsController.text = specialInstructions;

      // Load location fields from JPEG metadata
      final extractedStadium = meta['Sub-location']?.toString() ?? '';
      stadiumController.text = extractedStadium;

      final extractedCity = meta['City']?.toString() ?? '';
      cityController.text = extractedCity;

      final extractedProvince = meta['Province-State']?.toString() ?? '';
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 70,
          alignment: Alignment.topLeft,
          child: Text(
            label,
            textAlign: TextAlign.left,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            expands: expands,
            textAlign: TextAlign.left,
            style: const TextStyle(fontSize: 10),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: Colors.blue.shade400, width: 1.2),
              ),
              contentPadding: const EdgeInsets.all(10),
              filled: true,
              fillColor: Colors.grey.shade50,
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField(
    String label,
    String? value,
    List<Map<String, String>> items,
    ValueChanged<String?> onChanged,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 70,
          alignment: Alignment.topLeft,
          child: Text(
            label,
            textAlign: TextAlign.left,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: PopupMenuButton<String>(
            initialValue: value,
            onSelected: onChanged,
            constraints: const BoxConstraints(maxHeight: 300),
            itemBuilder: (context) => items
                .map(
                  (item) => PopupMenuItem<String>(
                    value: item['code'],
                    height: 28,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      item['name']!,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                )
                .toList(),
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
                      value ?? 'Select $label',
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 10,
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
        ),
      ],
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
      margin: const EdgeInsets.all(3.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300, width: 1.0),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Column(
        children: [
          // Main content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(left: 6, right: 6, top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // IPTC metadata fields - 3 columns x 10 rows grid
                  LayoutBuilder(builder: (context, constraints) {
                    const int columns = 3;
                    const int rows = 10;
                    const double gap = 1.0;
                    final double columnWidth =
                        (constraints.maxWidth - gap * (columns - 1)) / columns;

                    final List<Widget> items = [
                      _buildField('Photographer', creatorController),
                      _buildField('MEID', jobIdController),
                      _buildField(
                          'Description Writers', descriptionWritersController),
                      _buildField(
                          'Creator\'s Job Title', creatorJobTitleController),
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
                      _buildField(
                          'Special Instructions', specialInstructionsController,
                          maxLines: 2),
                      _buildDateField(),
                      _buildTimeField(),
                    ];

                    // Pad to exactly columns*rows slots
                    final int target = columns * rows;
                    while (items.length < target) {
                      items.add(const SizedBox(height: 40));
                    }

                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: items
                          .map((w) => Container(
                                width: columnWidth,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 0),
                                child: w,
                              ))
                          .toList(),
                    );
                  }),
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
    dateController.dispose();
    timeController.dispose();
    titleObjectNameController.dispose();
    categoryController.dispose();
    suppCat1Controller.dispose();
    suppCat2Controller.dispose();
    suppCat3Controller.dispose();
    specialInstructionsController.dispose();
    super.dispose();
  }
}
