import 'package:flutter/material.dart';
import '../utils/native_file_picker.dart';
import 'dart:async';
import 'dart:io';
import '../services/api_manager.dart';
import 'dart:convert'; // Added for jsonDecode
import '../utils/exiftool_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'metadata_preset_dialog.dart';
import '../services/preferences_service.dart';

// Custom button widget with cursor styling (matching the one in caption_fields_widget.dart)
class CustomButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  final Color? backgroundColor;
  final Color? borderColor;
  final BorderRadius? borderRadius;

  const CustomButton({
    super.key,
    required this.onTap,
    required this.child,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: child,
      ),
    );
  }
}

class StartupDialog extends StatefulWidget {
  final Function(String folderPath, String? homeTeam, String? awayTeam)
      onConfigurationComplete;
  final String? sport; // Current sport mode

  const StartupDialog({
    Key? key,
    required this.onConfigurationComplete,
    this.sport,
  }) : super(key: key);

  @override
  State<StartupDialog> createState() => _StartupDialogState();
}

class _StartupDialogState extends State<StartupDialog> {
  String? selectedFolderPath;
  String? selectedHomeTeam;
  String? selectedAwayTeam;
  DateTime? selectedGameDate;
  List<String> availableTeams = [];
  bool isLoadingTeams = true;
  bool isLoadingFolder = false;
  bool hasImagesInFolder = false;
  bool isExtractingDate = false;
  bool _applyPresetToAllImages = false;

  // Questionnaire state
  int currentQuestion = 0;
  String displayedText = '';
  bool isTyping = false;
  int typingIndex = 0;
  Timer? typingTimer;

  // Team selection typewriter state
  String _teamSelectionText = '';
  bool _isTypingTeamSelection = false;
  int _teamSelectionTypingIndex = 0;
  Timer? _teamSelectionTypingTimer;

  // Network status
  bool _isOffline = false;

  final ApiManager _apiManager = ApiManager();

  // Preferences service and favorite teams
  late PreferencesService _preferencesService;
  Set<String> _favoriteTeams = {};
  String? _favoriteHomeTeam;
  String? _favoriteAwayTeam;

  final List<String> questions = [
    'Where is your images folder?',
    'What is the game date?',
  ];

  @override
  void initState() {
    super.initState();

    // Configure API Manager based on sport
    if (widget.sport != null) {
      _apiManager.setSport(widget.sport!);
    }

    _initializeAndLoadData();
    _startTyping();
  }

  Future<void> _initializeAndLoadData() async {
    // Wait for preferences to load first, then load teams
    await _initializePreferences();
    await _loadTeams();
  }

  Future<void> _initializePreferences() async {
    _preferencesService = await PreferencesService.getInstance();

    // Load favorite teams for the current sport
    final sport = widget.sport?.toLowerCase() ?? 'baseball';
    print('DEBUG _initializePreferences: Loading favorites for sport=$sport');
    _favoriteTeams = await _preferencesService.getFavoriteTeams(sport: sport);
    print(
        'DEBUG _initializePreferences: Loaded favorite teams: $_favoriteTeams');

    // Extract home and away favorites from the set
    // We'll use a simple convention: favorites are stored as "HOME:teamname" and "AWAY:teamname"
    for (var team in _favoriteTeams) {
      if (team.startsWith('HOME:')) {
        _favoriteHomeTeam = team.substring(5);
        print(
            'DEBUG _initializePreferences: Found home favorite: $_favoriteHomeTeam');
      } else if (team.startsWith('AWAY:')) {
        _favoriteAwayTeam = team.substring(5);
        print(
            'DEBUG _initializePreferences: Found away favorite: $_favoriteAwayTeam');
      }
    }

    // Automatically select favorite teams if they exist
    if (_favoriteHomeTeam != null) {
      selectedHomeTeam = _favoriteHomeTeam;
      print(
          'DEBUG _initializePreferences: Set selectedHomeTeam=$selectedHomeTeam');
    }
    if (_favoriteAwayTeam != null) {
      selectedAwayTeam = _favoriteAwayTeam;
      print(
          'DEBUG _initializePreferences: Set selectedAwayTeam=$selectedAwayTeam');
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    typingTimer?.cancel();
    super.dispose();
  }

  void _startTyping() {
    setState(() {
      displayedText = '';
      typingIndex = 0;
      isTyping = true;
    });
    _typeNextCharacter();
  }

  void _typeNextCharacter() {
    String textToType;
    if (currentQuestion < questions.length) {
      textToType = questions[currentQuestion];
    } else {
      textToType = '';
    }

    if (typingIndex < textToType.length) {
      setState(() {
        displayedText += textToType[typingIndex];
        typingIndex++;
      });
      typingTimer = Timer(const Duration(milliseconds: 15), _typeNextCharacter);
    } else {
      setState(() {
        isTyping = false;
      });
    }
  }

  void _startTeamSelectionTyping() {
    setState(() {
      _teamSelectionText = '';
      _teamSelectionTypingIndex = 0;
      _isTypingTeamSelection = true;
    });
    _typeTeamSelectionNextCharacter();
  }

  void _typeTeamSelectionNextCharacter() {
    const textToType = 'What teams are playing?';

    if (_teamSelectionTypingIndex < textToType.length) {
      setState(() {
        _teamSelectionText += textToType[_teamSelectionTypingIndex];
        _teamSelectionTypingIndex++;
      });
      _teamSelectionTypingTimer = Timer(
          const Duration(milliseconds: 15), _typeTeamSelectionNextCharacter);
    } else {
      setState(() {
        _isTypingTeamSelection = false;
      });
    }
  }

  String _formatDate(DateTime date) {
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _nextQuestion() {
    // Special case: skip directly to team selection when date inferred
    if (currentQuestion == 0 && hasImagesInFolder && selectedGameDate != null) {
      setState(() {
        currentQuestion = 2; // Go to team selection
        isTyping = false;
        displayedText = 'Where is your images folder?';
      });
      _startTeamSelectionTyping();
      return;
    }

    if (currentQuestion < questions.length - 1) {
      setState(() {
        currentQuestion++;
      });
      _startTyping();
      return;
    }

    if (currentQuestion == questions.length - 1) {
      // Move to team selection step with typing animation
      setState(() {
        currentQuestion = 2;
        isTyping = false;
        displayedText = 'Where is your images folder?';
      });
      _startTeamSelectionTyping();
    }
  }

  Future<void> _loadTeams() async {
    try {
      final teams = await _apiManager.fetchTeams();
      setState(() {
        // Remove duplicates by converting to Set, then back to List and sort
        availableTeams = teams.map((team) => team.name).toSet().toList()..sort();
        print('DEBUG _loadTeams: Loaded ${availableTeams.length} teams');
        // Restore favorite teams if they exist and are in the team list
        print('DEBUG _loadTeams: Checking home favorite: $_favoriteHomeTeam');
        if (_favoriteHomeTeam != null &&
            availableTeams.contains(_favoriteHomeTeam)) {
          selectedHomeTeam = _favoriteHomeTeam;
          print('DEBUG _loadTeams: Set selectedHomeTeam=$selectedHomeTeam');
        } else {
          print(
              'DEBUG _loadTeams: Home favorite not found in team list or null');
        }
        print('DEBUG _loadTeams: Checking away favorite: $_favoriteAwayTeam');
        if (_favoriteAwayTeam != null &&
            availableTeams.contains(_favoriteAwayTeam)) {
          selectedAwayTeam = _favoriteAwayTeam;
          print('DEBUG _loadTeams: Set selectedAwayTeam=$selectedAwayTeam');
        } else {
          print(
              'DEBUG _loadTeams: Away favorite not found in team list or null');
        }
        isLoadingTeams = false;
      });
    } catch (e) {
      print('Error loading teams: $e');
      // Fallback teams based on sport
      setState(() {
        _isOffline = true;
        final sport = widget.sport?.toLowerCase() ?? 'baseball';

        if (sport == 'hockey') {
          availableTeams = [
            'Anaheim Ducks',
            'Arizona Coyotes',
            'Boston Bruins',
            'Buffalo Sabres',
            'Calgary Flames',
            'Carolina Hurricanes',
            'Chicago Blackhawks',
            'Colorado Avalanche',
            'Columbus Blue Jackets',
            'Dallas Stars',
            'Detroit Red Wings',
            'Edmonton Oilers',
            'Florida Panthers',
            'Los Angeles Kings',
            'Minnesota Wild',
            'Montreal Canadiens',
            'Nashville Predators',
            'New Jersey Devils',
            'New York Islanders',
            'New York Rangers',
            'Ottawa Senators',
            'Philadelphia Flyers',
            'Pittsburgh Penguins',
            'San Jose Sharks',
            'Seattle Kraken',
            'St. Louis Blues',
            'Tampa Bay Lightning',
            'Toronto Maple Leafs',
            'Vancouver Canucks',
            'Vegas Golden Knights',
            'Washington Capitals',
            'Winnipeg Jets'
          ];
        } else if (sport == 'basketball') {
          availableTeams = [
            'Atlanta Hawks',
            'Boston Celtics',
            'Brooklyn Nets',
            'Charlotte Hornets',
            'Chicago Bulls',
            'Cleveland Cavaliers',
            'Dallas Mavericks',
            'Denver Nuggets',
            'Detroit Pistons',
            'Golden State Warriors',
            'Houston Rockets',
            'Indiana Pacers',
            'Los Angeles Clippers',
            'Los Angeles Lakers',
            'Memphis Grizzlies',
            'Miami Heat',
            'Milwaukee Bucks',
            'Minnesota Timberwolves',
            'New Orleans Pelicans',
            'New York Knicks',
            'Oklahoma City Thunder',
            'Orlando Magic',
            'Philadelphia 76ers',
            'Phoenix Suns',
            'Portland Trail Blazers',
            'Sacramento Kings',
            'San Antonio Spurs',
            'Toronto Raptors',
            'Utah Jazz',
            'Washington Wizards'
          ];
        } else {
          // Default to MLB teams
          availableTeams = [
            'Arizona Diamondbacks',
            'Atlanta Braves',
            'Baltimore Orioles',
            'Boston Red Sox',
            'Chicago Cubs',
            'Chicago White Sox',
            'Cincinnati Reds',
            'Cleveland Guardians',
            'Colorado Rockies',
            'Detroit Tigers',
            'Houston Astros',
            'Kansas City Royals',
            'Los Angeles Angels',
            'Los Angeles Dodgers',
            'Miami Marlins',
            'Milwaukee Brewers',
            'Minnesota Twins',
            'New York Mets',
            'New York Yankees',
            'Oakland Athletics',
            'Philadelphia Phillies',
            'Pittsburgh Pirates',
            'San Diego Padres',
            'San Francisco Giants',
            'Seattle Mariners',
            'St. Louis Cardinals',
            'Tampa Bay Rays',
            'Texas Rangers',
            'Toronto Blue Jays',
            'Washington Nationals'
          ];
        }
        print(
            'DEBUG _loadTeams (fallback): Loaded ${availableTeams.length} fallback teams for $sport');
        // Restore favorite teams if they exist and are in the team list
        print(
            'DEBUG _loadTeams (fallback): Checking home favorite: $_favoriteHomeTeam');
        if (_favoriteHomeTeam != null &&
            availableTeams.contains(_favoriteHomeTeam)) {
          selectedHomeTeam = _favoriteHomeTeam;
          print(
              'DEBUG _loadTeams (fallback): Set selectedHomeTeam=$selectedHomeTeam');
        } else {
          print(
              'DEBUG _loadTeams (fallback): Home favorite not found in team list or null');
        }
        print(
            'DEBUG _loadTeams (fallback): Checking away favorite: $_favoriteAwayTeam');
        if (_favoriteAwayTeam != null &&
            availableTeams.contains(_favoriteAwayTeam)) {
          selectedAwayTeam = _favoriteAwayTeam;
          print(
              'DEBUG _loadTeams (fallback): Set selectedAwayTeam=$selectedAwayTeam');
        } else {
          print(
              'DEBUG _loadTeams (fallback): Away favorite not found in team list or null');
        }
        isLoadingTeams = false;
      });
    }
  }

  Future<void> _pickFolder() async {
    setState(() {
      isLoadingFolder = true;
    });

    try {
      // Get the last used directory
      String? lastDirectory;
      try {
        final prefs = await SharedPreferences.getInstance();
        lastDirectory = prefs.getString('last_images_folder');
      } catch (prefsError) {
        print('SharedPreferences error: $prefsError');
        lastDirectory = null; // Continue without saved directory
      }

      String? result = await NativeFilePicker.pickDirectory(
        initialDirectory: lastDirectory,
      );

      if (result != null) {
        // Check if folder contains images
        final directory = Directory(result);
        final List<FileSystemEntity> entities = await directory.list().toList();

        final List<String> imageFiles = entities
            .whereType<File>()
            .map((entity) => entity.path)
            .where((path) =>
                path.toLowerCase().endsWith('.jpg') ||
                path.toLowerCase().endsWith('.jpeg') ||
                path.toLowerCase().endsWith('.png') ||
                path.toLowerCase().endsWith('.tiff') ||
                path.toLowerCase().endsWith('.bmp'))
            .toList();

        // Save the directory for next time
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('last_images_folder', result);
        } catch (prefsError) {
          print('SharedPreferences save error: $prefsError');
          // Continue without saving preference
        }

        setState(() {
          selectedFolderPath = result;
          hasImagesInFolder = imageFiles.isNotEmpty;
          isLoadingFolder = false;
        });

        // If images found, try to read date from first 5 images
        if (imageFiles.isNotEmpty) {
          setState(() {
            isExtractingDate = true;
          });
          await _extractDateFromImages(imageFiles);
          setState(() {
            isExtractingDate = false;
          });
        }

        // Automatically proceed to team selection after folder is selected
        _nextQuestion();
      } else {
        setState(() {
          isLoadingFolder = false;
        });
      }
    } catch (e) {
      print('Error picking folder: $e');
      setState(() {
        isLoadingFolder = false;
      });
    }
  }

  Future<void> _extractDateFromImages(List<String> imageFiles) async {
    try {
      // Take first 5 images
      final imagesToCheck = imageFiles.take(5).toList();
      List<DateTime?> dates = [];

      for (String imagePath in imagesToCheck) {
        try {
          // Extract metadata via exiftool
          final proc = await ExiftoolHelper.run([
            '-j', // JSON output
            '-DateTimeOriginal',
            '-CreateDate',
            '-ModifyDate',
            imagePath,
          ]);

          if (proc.isSuccess) {
            final List data = jsonDecode(proc.stdoutText);
            if (data.isNotEmpty) {
              final metadata = data.first as Map<String, dynamic>;

              // Try to get date from various EXIF fields
              String? dateString = metadata['DateTimeOriginal']?.toString() ??
                  metadata['CreateDate']?.toString() ??
                  metadata['ModifyDate']?.toString();

              if (dateString != null && dateString.isNotEmpty) {
                try {
                  // Parse EXIF date format (YYYY:MM:DD HH:MM:SS)
                  final parts = dateString.split(' ');
                  if (parts.isNotEmpty) {
                    final datePart = parts[0];
                    final dateComponents = datePart.split(':');
                    if (dateComponents.length >= 3) {
                      final year = int.parse(dateComponents[0]);
                      final month = int.parse(dateComponents[1]);
                      final day = int.parse(dateComponents[2]);
                      dates.add(DateTime(year, month, day));
                    }
                  }
                } catch (e) {
                  print('Error parsing date from $imagePath: $e');
                }
              }
            }
          }
        } catch (e) {
          print('Error reading metadata from $imagePath: $e');
        }
      }

      // If we found dates, use the most common date or the first one
      if (dates.isNotEmpty) {
        // Find the most common date
        Map<DateTime, int> dateCounts = {};
        for (DateTime? date in dates) {
          if (date != null) {
            // Normalize to just the date part
            final normalizedDate = DateTime(date.year, date.month, date.day);
            dateCounts[normalizedDate] = (dateCounts[normalizedDate] ?? 0) + 1;
          }
        }

        if (dateCounts.isNotEmpty) {
          // Find the date with the highest count
          final mostCommonDate = dateCounts.entries
              .reduce((a, b) => a.value > b.value ? a : b)
              .key;

          setState(() {
            selectedGameDate = mostCommonDate;
          });
          print(
              'Extracted game date from images: ${mostCommonDate.toIso8601String().split('T')[0]}');
        } else {
          print('No valid dates found in images');
        }
      }
    } catch (e) {
      print('Error extracting dates from images: $e');
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        selectedGameDate = picked;
      });
      _nextQuestion();
    }
  }

  void _openMetadataPreset() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => MetadataPresetDialog(
        currentPreset: null,
        detectedDate: selectedGameDate,
      ),
    );

    if (result != null) {
      // Extract metadata
      final metadata = result['metadata'] as Map<String, String>;

      // Store the selected preset data to be used when the app starts
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_metadata_preset', jsonEncode(metadata));

      // Automatically check the "Apply preset to all images" checkbox when template is applied
      setState(() {
        _applyPresetToAllImages = true;
      });

      // Store the checkbox value from the startup dialog
      await prefs.setBool(
          'apply_preset_to_all_images', _applyPresetToAllImages);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Metadata preset will be applied to all images in the session.'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  bool get _canProceed {
    if (hasImagesInFolder) {
      return selectedFolderPath != null &&
          selectedHomeTeam != null &&
          selectedAwayTeam != null &&
          selectedHomeTeam != selectedAwayTeam;
    } else {
      return selectedFolderPath != null &&
          selectedGameDate != null &&
          selectedHomeTeam != null &&
          selectedAwayTeam != null &&
          selectedHomeTeam != selectedAwayTeam;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.5), // Semi-transparent overlay
      child: Center(
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: 900, // Increased from 800
            height: 800, // Increased from 700 to accommodate debug info
            padding: const EdgeInsets.all(40), // Increased padding
            color: Colors.white, // Added white background
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                const Text(
                  'FLO FILE',
                  style: TextStyle(
                    fontSize: 24, // Increased from 20
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8), // Small spacing
                Container(
                  width: double.infinity,
                  height: 1,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(
                    height: 32), // Reduced from 40 to account for line

                // Question with typewriter effect
                Text(
                  displayedText + (isTyping ? '|' : ''),
                  style: const TextStyle(
                    fontSize: 16, // Match "Please select your teams:" size
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(
                    height:
                        16), // Reduced from 32 to bring button closer to header

                // Question-specific content
                if (currentQuestion == 0 && !isTyping) ...[
                  // Folder selection
                  FractionallySizedBox(
                    widthFactor: 0.75,
                    alignment: Alignment.centerLeft,
                    child: CustomButton(
                      onTap: isLoadingFolder ? null : _pickFolder,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: isLoadingFolder
                              ? Colors.grey.shade300
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            isLoadingFolder
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Icon(Icons.folder_open,
                                    size: 12, color: Colors.grey.shade700),
                            const SizedBox(width: 4),
                            Text(
                              isLoadingFolder
                                  ? 'Loading...'
                                  : 'Pick Images Folder',
                              style: TextStyle(
                                fontSize: 13,
                                color: isLoadingFolder
                                    ? Colors.grey.shade600
                                    : Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16), // Increased spacing
                ] else if (currentQuestion == 1) ...[
                  // Date selection (only show if no date was extracted from images)
                  if (selectedGameDate == null) ...[
                    CustomButton(
                      onTap: _selectDate,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.calendar_today,
                                size: 12, color: Colors.grey.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Select Game Date',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24), // Increased spacing
                    CustomButton(
                      onTap: () => _nextQuestion(),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.arrow_forward,
                                size: 12, color: Colors.grey.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Next',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ] else if (currentQuestion == 2) ...[
                  // Team selection
                  if (!isLoadingTeams) ...[
                    // Pick Images Folder option
                    FractionallySizedBox(
                      widthFactor: 0.75,
                      alignment: Alignment.centerLeft,
                      child: CustomButton(
                        onTap: isLoadingFolder ? null : _pickFolder,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: isLoadingFolder
                                ? Colors.grey.shade300
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              isLoadingFolder
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Icon(Icons.folder_open,
                                      size: 12, color: Colors.grey.shade700),
                              const SizedBox(width: 4),
                              Text(
                                isLoadingFolder
                                    ? 'Loading...'
                                    : 'Pick Images Folder',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isLoadingFolder
                                      ? Colors.grey.shade600
                                      : Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Display selected folder path if exists (no box)
                    if (selectedFolderPath != null) ...[
                      Row(
                        children: [
                          Text(
                            'Current Folder: ',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800,
                              fontSize: 13,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              selectedFolderPath!,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (selectedGameDate != null) ...[
                        Row(
                          children: [
                            Text(
                              'Date detected: ',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade800,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _formatDate(selectedGameDate!),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        Container(
                          width: double.infinity,
                          height: 1,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 40),
                      ] else ...[
                        const SizedBox(height: 16),
                      ],
                    ],

                    // Team selection header
                    Row(
                      children: [
                        Text(
                          _teamSelectionText +
                              (_isTypingTeamSelection ? '|' : ''),
                          style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                        ),
                        if (_isOffline) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.orange.shade300),
                            ),
                            child: const Text(
                              'Offline',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Show team dropdowns only after typewriter is done
                    if (!_isTypingTeamSelection) ...[
                      // Home Team
                      Text('Home Team:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                            fontSize: 13,
                          )),
                      const SizedBox(height: 4), // Reduced spacing
                      FractionallySizedBox(
                        widthFactor: 0.75,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2), // More compact padding
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(
                                      4), // Smaller radius
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: selectedHomeTeam,
                                    hint: const Text('Select home team',
                                        style: TextStyle(fontSize: 13)),
                                    isExpanded: true,
                                    items: availableTeams.map((team) {
                                      final isSelected =
                                          team == selectedHomeTeam;
                                      return DropdownMenuItem<String>(
                                        value: team,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(team,
                                                  style: const TextStyle(
                                                      fontSize: 13)),
                                            ),
                                            // Show star only for selected team
                                            if (isSelected) ...[
                                              MouseRegion(
                                                cursor:
                                                    SystemMouseCursors.click,
                                                child: GestureDetector(
                                                  onTap: () {
                                                    setState(() {
                                                      // Toggle home team favorite
                                                      if (_favoriteHomeTeam ==
                                                          selectedHomeTeam) {
                                                        _favoriteHomeTeam =
                                                            null;
                                                        _favoriteTeams.remove(
                                                            'HOME:$selectedHomeTeam');
                                                      } else {
                                                        // Remove old home favorite if exists
                                                        if (_favoriteHomeTeam !=
                                                            null) {
                                                          _favoriteTeams.remove(
                                                              'HOME:$_favoriteHomeTeam');
                                                        }
                                                        _favoriteHomeTeam =
                                                            selectedHomeTeam;
                                                        _favoriteTeams.add(
                                                            'HOME:$selectedHomeTeam');
                                                      }

                                                      // Save favorite teams preference for current sport
                                                      final sport = widget.sport
                                                              ?.toLowerCase() ??
                                                          'baseball';
                                                      _preferencesService
                                                          .saveFavoriteTeams(
                                                              _favoriteTeams,
                                                              sport: sport);
                                                    });
                                                  },
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(4),
                                                    child: Icon(
                                                      _favoriteHomeTeam ==
                                                              selectedHomeTeam
                                                          ? Icons.star
                                                          : Icons.star_border,
                                                      size: 16,
                                                      color: _favoriteHomeTeam ==
                                                              selectedHomeTeam
                                                          ? Colors.amber
                                                          : Colors
                                                              .grey.shade400,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      setState(() {
                                        selectedHomeTeam = value;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24), // Increased spacing

                      // Away Team
                      Text('Away Team:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                            fontSize: 13,
                          )),
                      const SizedBox(height: 4), // Reduced spacing
                      FractionallySizedBox(
                        widthFactor: 0.75,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2), // More compact padding
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(
                                      4), // Smaller radius
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: selectedAwayTeam,
                                    hint: const Text('Select away team',
                                        style: TextStyle(fontSize: 13)),
                                    isExpanded: true,
                                    items: availableTeams.map((team) {
                                      final isSelected =
                                          team == selectedAwayTeam;
                                      return DropdownMenuItem<String>(
                                        value: team,
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(team,
                                                  style: const TextStyle(
                                                      fontSize: 13)),
                                            ),
                                            // Show star only for selected team
                                            if (isSelected) ...[
                                              MouseRegion(
                                                cursor:
                                                    SystemMouseCursors.click,
                                                child: GestureDetector(
                                                  onTap: () {
                                                    setState(() {
                                                      // Toggle away team favorite
                                                      if (_favoriteAwayTeam ==
                                                          selectedAwayTeam) {
                                                        _favoriteAwayTeam =
                                                            null;
                                                        _favoriteTeams.remove(
                                                            'AWAY:$selectedAwayTeam');
                                                      } else {
                                                        // Remove old away favorite if exists
                                                        if (_favoriteAwayTeam !=
                                                            null) {
                                                          _favoriteTeams.remove(
                                                              'AWAY:$_favoriteAwayTeam');
                                                        }
                                                        _favoriteAwayTeam =
                                                            selectedAwayTeam;
                                                        _favoriteTeams.add(
                                                            'AWAY:$selectedAwayTeam');
                                                      }

                                                      // Save favorite teams preference for current sport
                                                      final sport = widget.sport
                                                              ?.toLowerCase() ??
                                                          'baseball';
                                                      _preferencesService
                                                          .saveFavoriteTeams(
                                                              _favoriteTeams,
                                                              sport: sport);
                                                    });
                                                  },
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(4),
                                                    child: Icon(
                                                      _favoriteAwayTeam ==
                                                              selectedAwayTeam
                                                          ? Icons.star
                                                          : Icons.star_border,
                                                      size: 16,
                                                      color: _favoriteAwayTeam ==
                                                              selectedAwayTeam
                                                          ? Colors.amber
                                                          : Colors
                                                              .grey.shade400,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      setState(() {
                                        selectedAwayTeam = value;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (selectedAwayTeam != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          height: 1,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        const SizedBox(height: 24), // Increased spacing
                      ],

                      // Date already shown under Current Folder when available

                      // Error message if same team selected
                      if (selectedHomeTeam != null &&
                          selectedAwayTeam != null &&
                          selectedHomeTeam == selectedAwayTeam)
                        Container(
                          padding:
                              const EdgeInsets.all(12), // Increased padding
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            border: Border.all(color: Colors.red.shade200),
                            borderRadius:
                                BorderRadius.circular(6), // Increased radius
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.error,
                                  color: Colors.red,
                                  size: 18), // Increased size
                              SizedBox(width: 8),
                              Text(
                                'Home and away teams must be different',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 14, // Added font size
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 24), // Increased spacing

                      // Optional section
                      const Text('Optional:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                            fontSize: 13,
                          )),
                      const SizedBox(height: 8),
                      FractionallySizedBox(
                        widthFactor: 0.75,
                        alignment: Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CustomButton(
                              onTap: _openMetadataPreset,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.description,
                                        size: 12, color: Colors.grey.shade700),
                                    const SizedBox(width: 4),
                                    Text('Metadata Preset',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade700,
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Checkbox(
                                  value: _applyPresetToAllImages,
                                  onChanged: (value) {
                                    setState(() {
                                      _applyPresetToAllImages = value ?? false;
                                    });
                                  },
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                Expanded(
                                  child: Text(
                                    'Apply preset to all images in session',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Start button
                      FractionallySizedBox(
                        widthFactor: 0.75,
                        alignment: Alignment.centerLeft,
                        child: CustomButton(
                          onTap: _canProceed
                              ? () {
                                  widget.onConfigurationComplete(
                                    selectedFolderPath!,
                                    selectedHomeTeam,
                                    selectedAwayTeam,
                                  );
                                }
                              : null,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: _canProceed
                                  ? const Color(0xFF0052CC)
                                  : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _canProceed
                                    ? const Color(0xFF0052CC)
                                    : Colors.grey.shade400,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.rocket_launch,
                                      size: 12,
                                      color: _canProceed
                                          ? Colors.white
                                          : Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Go Time',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: _canProceed
                                            ? Colors.white
                                            : Colors.grey.shade600,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                if (!_canProceed) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.warning,
                                        size: 10,
                                        color: Colors.red.shade600,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Select home and away teams',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.red.shade600,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ] else ...[
                    const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
