import 'package:flutter/material.dart';
import '../utils/native_file_picker.dart';
import 'dart:async';
import 'dart:io';
import '../services/api_manager.dart';
import 'dart:convert'; // Added for jsonDecode
import 'package:dropdown_flutter/custom_dropdown.dart';
import '../utils/exiftool_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_compact_checkbox.dart';
import 'app_styled_dialogs.dart';
import 'metadata_preset_dialog.dart';
import '../services/preferences_service.dart';
import 'startup_caption_layout_preview.dart';

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
  final VoidCallback? onBackToSportSelection;

  const StartupDialog({
    Key? key,
    required this.onConfigurationComplete,
    this.sport,
    this.onBackToSportSelection,
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
  bool _burstDetectionEnabled = false;

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
  String? _goTimeWarningText;
  static const bool _showStartupCoachInfo = false;
  String? _homeCoachRole;
  String? _awayCoachRole;
  bool _homeCoachLoading = false;
  bool _awayCoachLoading = false;
  String _homeCoachName = '';
  String _awayCoachName = '';

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

    _burstDetectionEnabled =
        await _preferencesService.getBurstDetectionEnabled();

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

  Future<void> _retryLoadTeams() async {
    setState(() => isLoadingTeams = true);
    await _loadTeams();
  }

  Future<void> _loadTeams() async {
    try {
      final teams = await _apiManager.fetchTeams();
      if (!mounted) return;
      setState(() {
        _isOffline = false;
        // Remove duplicates by converting to Set, then back to List and sort
        availableTeams = teams.map((team) => team.name).toSet().toList()..sort();
        print('DEBUG _loadTeams: Loaded ${availableTeams.length} teams');
        // Clear selection if no longer in list (e.g. after switching API)
        if (selectedHomeTeam != null && !availableTeams.contains(selectedHomeTeam)) {
          selectedHomeTeam = null;
        }
        if (selectedAwayTeam != null && !availableTeams.contains(selectedAwayTeam)) {
          selectedAwayTeam = null;
        }
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
      if (_showStartupCoachInfo && selectedHomeTeam != null) {
        _refreshCoachLabelForTeam(isHome: true);
      }
      if (_showStartupCoachInfo && selectedAwayTeam != null) {
        _refreshCoachLabelForTeam(isHome: false);
      }
    } catch (e) {
      print('Error loading teams: $e');
      if (!mounted) return;
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
        } else if (sport == 'soccer') {
          availableTeams = [
            'Atlanta United FC',
            'Austin FC',
            'CF Montréal',
            'Charlotte FC',
            'Chicago Fire FC',
            'Colorado Rapids',
            'Columbus Crew',
            'D.C. United',
            'FC Cincinnati',
            'FC Dallas',
            'Houston Dynamo FC',
            'Inter Miami CF',
            'LA Galaxy',
            'LAFC',
            'Minnesota United FC',
            'Nashville SC',
            'New England Revolution',
            'New York City FC',
            'Orlando City SC',
            'Philadelphia Union',
            'Portland Timbers',
            'Real Salt Lake',
            'Red Bull New York',
            'San Diego FC',
            'San Jose Earthquakes',
            'Seattle Sounders FC',
            'Sporting Kansas City',
            'St. Louis CITY SC',
            'Toronto FC',
            'Vancouver Whitecaps',
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
        if (selectedHomeTeam != null && !availableTeams.contains(selectedHomeTeam)) {
          selectedHomeTeam = null;
        }
        if (selectedAwayTeam != null && !availableTeams.contains(selectedAwayTeam)) {
          selectedAwayTeam = null;
        }
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

  Future<void> _toggleFavoriteTeam({required bool isHome}) async {
    setState(() {
      final selectedTeam = isHome ? selectedHomeTeam : selectedAwayTeam;
      if (selectedTeam == null) return;
      if (isHome) {
        if (_favoriteHomeTeam == selectedTeam) {
          _favoriteHomeTeam = null;
          _favoriteTeams.remove('HOME:$selectedTeam');
        } else {
          if (_favoriteHomeTeam != null) {
            _favoriteTeams.remove('HOME:$_favoriteHomeTeam');
          }
          _favoriteHomeTeam = selectedTeam;
          _favoriteTeams.add('HOME:$selectedTeam');
        }
      } else {
        if (_favoriteAwayTeam == selectedTeam) {
          _favoriteAwayTeam = null;
          _favoriteTeams.remove('AWAY:$selectedTeam');
        } else {
          if (_favoriteAwayTeam != null) {
            _favoriteTeams.remove('AWAY:$_favoriteAwayTeam');
          }
          _favoriteAwayTeam = selectedTeam;
          _favoriteTeams.add('AWAY:$selectedTeam');
        }
      }
    });

    final sport = widget.sport?.toLowerCase() ?? 'baseball';
    await _preferencesService.saveFavoriteTeams(_favoriteTeams, sport: sport);
  }


  Future<void> _refreshCoachLabelForTeam({required bool isHome}) async {
    final teamName = isHome ? selectedHomeTeam : selectedAwayTeam;
    if (teamName == null || teamName.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        if (isHome) {
          _homeCoachRole = null;
          _homeCoachLoading = false;
          _homeCoachName = '';
        } else {
          _awayCoachRole = null;
          _awayCoachLoading = false;
          _awayCoachName = '';
        }
      });
      return;
    }

    final sport = widget.sport?.toLowerCase() ?? 'baseball';
    final String headTitle = (sport == 'baseball' || sport == 'soccer')
        ? 'Manager'
        : 'Head Coach';

    if (mounted) {
      setState(() {
        if (isHome) {
          _homeCoachRole = headTitle;
          _homeCoachLoading = true;
          _homeCoachName = '';
        } else {
          _awayCoachRole = headTitle;
          _awayCoachLoading = true;
          _awayCoachName = '';
        }
      });
    }

    try {
      final staff = await _apiManager.fetchTeamStaff(teamName);
      final headCoach = (staff['headCoach'] ?? '').trim();
      final name =
          headCoach.isNotEmpty ? headCoach : 'data missing';
      if (!mounted) return;
      setState(() {
        if (isHome) {
          _homeCoachRole = headTitle;
          _homeCoachLoading = false;
          _homeCoachName = name;
        } else {
          _awayCoachRole = headTitle;
          _awayCoachLoading = false;
          _awayCoachName = name;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (isHome) {
          _homeCoachRole = headTitle;
          _homeCoachLoading = false;
          _homeCoachName = 'data missing';
        } else {
          _awayCoachRole = headTitle;
          _awayCoachLoading = false;
          _awayCoachName = 'data missing';
        }
      });
    }
  }

  /// Same typography as Keyboard Fire roster rows (jersey-style role + name).
  Widget _buildStartupCoachRichText({
    required String? role,
    required bool loading,
    required String nameOrStatus,
  }) {
    if (role == null) return const SizedBox.shrink();
    final titleStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Colors.grey.shade800,
    );
    final suffix = loading ? 'loading…' : nameOrStatus;
    final suffixStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.normal,
      fontStyle: loading || nameOrStatus == 'data missing'
          ? FontStyle.italic
          : FontStyle.normal,
      color: loading
          ? Colors.grey.shade600
          : (nameOrStatus == 'data missing'
              ? Colors.grey.shade500
              : Colors.black87),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(role, style: titleStyle),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            suffix,
            style: suffixStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildStyledTeamDropdown({
    required bool isHome,
    required String hintText,
  }) {
    final selectedTeam = isHome ? selectedHomeTeam : selectedAwayTeam;
    final initial = (selectedTeam != null && availableTeams.contains(selectedTeam))
        ? selectedTeam
        : null;
    return DropdownFlutter<String>(
      hintText: hintText,
      items: availableTeams,
      initialItem: initial,
      overlayHeight: 220,
      closedHeaderPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      expandedHeaderPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      listItemPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: CustomDropdownDecoration(
        closedFillColor: Colors.grey.shade100,
        expandedFillColor: Colors.white,
        closedBorder: Border.all(color: Colors.grey.shade300),
        expandedBorder: Border.all(color: Colors.grey.shade300),
        closedBorderRadius: BorderRadius.circular(4),
        expandedBorderRadius: BorderRadius.circular(8),
        hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        headerStyle: TextStyle(fontSize: 11, color: Colors.grey.shade800),
        listItemStyle: const TextStyle(fontSize: 11),
        listItemDecoration: ListItemDecoration(
          selectedColor: Colors.grey.shade100,
        ),
      ),
      listItemBuilder: (context, item, isSelected, onItemSelect) {
        final team = item;
        final blockedByOtherSelection =
            (isHome && selectedAwayTeam == team) ||
                (!isHome && selectedHomeTeam == team);
        final isFavForSlot =
            isHome ? _favoriteHomeTeam == team : _favoriteAwayTeam == team;
        return InkWell(
          onTap: blockedByOtherSelection ? null : onItemSelect,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  team,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: blockedByOtherSelection
                        ? Colors.grey.shade400
                        : Colors.grey.shade800,
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  if (blockedByOtherSelection) return;
                  setState(() {
                    if (isHome) {
                      selectedHomeTeam = team;
                    } else {
                      selectedAwayTeam = team;
                    }
                  });
                  if (_showStartupCoachInfo) {
                    _refreshCoachLabelForTeam(isHome: isHome);
                  }
                  await _toggleFavoriteTeam(isHome: isHome);
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    isFavForSlot ? Icons.star : Icons.star_border,
                    size: 16,
                    color: isFavForSlot ? Colors.amber : Colors.grey.shade400,
                  ),
                ),
              ),
            ],
          ),
        );
      },
      onChanged: (value) {
        if (value == null) return;
        final blockedByOtherSelection =
            (isHome && selectedAwayTeam == value) ||
                (!isHome && selectedHomeTeam == value);
        if (blockedByOtherSelection) return;
        setState(() {
          if (isHome) {
            selectedHomeTeam = value;
          } else {
            selectedAwayTeam = value;
          }
          _goTimeWarningText = null;
        });
        if (_showStartupCoachInfo) {
          _refreshCoachLabelForTeam(isHome: isHome);
        }
      },
    );
  }

  Widget _buildTeamDropdownWithFavoriteIndicator({
    required bool isHome,
    required String hintText,
  }) {
    final selectedTeam = isHome ? selectedHomeTeam : selectedAwayTeam;
    final isFavoriteSelected =
        selectedTeam != null &&
            ((isHome && _favoriteHomeTeam == selectedTeam) ||
                (!isHome && _favoriteAwayTeam == selectedTeam));

    return Stack(
      alignment: Alignment.centerRight,
      children: [
        _buildStyledTeamDropdown(isHome: isHome, hintText: hintText),
        if (isFavoriteSelected)
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.only(right: 34),
              child: Icon(
                Icons.star,
                size: 14,
                color: Colors.amber.shade700,
              ),
            ),
          ),
      ],
    );
  }

  /// Match button width to full Away + @ + Home row width.
  Widget _sectionCard({
    required String label,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade800,
                  letterSpacing: 0.8,
                ),
              ),
              if (trailing != null) ...[
                const Spacer(),
                trailing,
              ],
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _pill({
    required IconData icon,
    required String text,
    double iconSize = 11,
    Color? iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: iconColor ?? Colors.grey.shade600),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
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
    final mq = MediaQuery.sizeOf(context);
    final dialogWidth = (mq.width - 64).clamp(600.0, 1220.0);
    final dialogHeight = (mq.height - 64).clamp(500.0, 760.0);
    return Material(
      color: Colors.black.withOpacity(0.5),
      child: Center(
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            width: dialogWidth,
            height: dialogHeight,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with optional back to sport
                Row(
                  children: [
                    const Text(
                      'FLO FILE',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (widget.onBackToSportSelection != null) ...[
                      const Spacer(),
                      ElevatedGreyButton(
                        label: '← Back to sports selection',
                        fontSize: 11,
                        onPressed: widget.onBackToSportSelection,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  height: 1,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 6),

                // Scrollable body so content never overflows
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                // Question with typewriter effect
                Text(
                  displayedText + (isTyping ? '|' : ''),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 6),

                // Question-specific content
                if (currentQuestion == 0 && !isTyping) ...[
                  // Folder selection
                  FractionallySizedBox(
                    widthFactor: 0.75,
                    alignment: Alignment.centerLeft,
                    child: ElevatedGreyButton(
                      label: isLoadingFolder ? 'Loading...' : 'Pick Images Folder',
                      fontSize: 11,
                      icon: Icons.folder_open,
                      fullWidth: true,
                      onPressed: isLoadingFolder ? null : _pickFolder,
                    ),
                  ),
                  const SizedBox(height: 10),
                ] else if (currentQuestion == 1) ...[
                  // Date selection (only show if no date was extracted from images)
                  if (selectedGameDate == null) ...[
                    ElevatedGreyButton(
                      label: 'Select Game Date',
                      fontSize: 11,
                      icon: Icons.calendar_today,
                      fullWidth: true,
                      onPressed: _selectDate,
                    ),
                    const SizedBox(height: 12),
                    ElevatedGreyButton(
                      label: 'Skip →',
                      fontSize: 11,
                      icon: Icons.arrow_forward,
                      fullWidth: true,
                      onPressed: () => _nextQuestion(),
                    ),
                  ],
                ] else if (currentQuestion == 2) ...[
                  if (!isLoadingTeams) ...[
                    // ── IMAGES FOLDER card ──
                    _sectionCard(
                      label: 'IMAGES FOLDER',
                      children: [
                        ElevatedGreyButton(
                          label: isLoadingFolder ? 'Loading...' : 'Pick images folder',
                          fontSize: 11,
                          icon: Icons.folder_open,
                          onPressed: isLoadingFolder ? null : _pickFolder,
                        ),
                        if (selectedFolderPath != null) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _pill(
                                icon: Icons.folder_outlined,
                                text: selectedFolderPath!,
                              ),
                              if (selectedGameDate != null)
                                _pill(
                                  icon: Icons.circle,
                                  iconSize: 6,
                                  iconColor: Colors.green,
                                  text: _formatDate(selectedGameDate!),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── TEAMS card ──
                    _sectionCard(
                      label: 'TEAMS',
                      trailing: _isOffline
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                    border:
                                        Border.all(color: Colors.orange.shade300),
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
                                const SizedBox(width: 6),
                                ElevatedGreyButton(
                                  label: isLoadingTeams ? 'Loading…' : 'Retry',
                                  fontSize: 11,
                                  onPressed: isLoadingTeams ? null : _retryLoadTeams,
                                ),
                              ],
                            )
                          : null,
                      children: [
                        if (!_isTypingTeamSelection) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: _buildTeamDropdownWithFavoriteIndicator(
                                  isHome: false,
                                  hintText: 'Away team',
                                ),
                              ),
                              SizedBox(
                                width: 28,
                                child: Center(
                                  child: Text(
                                    '@',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: _buildTeamDropdownWithFavoriteIndicator(
                                  isHome: true,
                                  hintText: 'Home team',
                                ),
                              ),
                            ],
                          ),
                          if (_showStartupCoachInfo) ...[
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _buildStartupCoachRichText(
                                    role: _awayCoachRole,
                                    loading: _awayCoachLoading,
                                    nameOrStatus: _awayCoachName,
                                  ),
                                ),
                                const SizedBox(width: 28),
                                Expanded(
                                  child: _buildStartupCoachRichText(
                                    role: _homeCoachRole,
                                    loading: _homeCoachLoading,
                                    nameOrStatus: _homeCoachName,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (selectedHomeTeam != null &&
                              selectedAwayTeam != null &&
                              selectedHomeTeam == selectedAwayTeam) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                border: Border.all(color: Colors.red.shade200),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.error,
                                      color: Colors.red, size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    'Home and away teams must be different',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ] else ...[
                          Text(
                            _teamSelectionText +
                                (_isTypingTeamSelection ? '|' : ''),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── CAPTION LAYOUT card ──
                    _sectionCard(
                      label: 'CAPTION LAYOUT',
                      children: [
                        StartupCaptionLayoutPreview(sport: widget.sport),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── OPTIONAL card ──
                    _sectionCard(
                      label: 'OPTIONAL',
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            AppCompactCheckbox(
                              value: _burstDetectionEnabled,
                              onChanged: (v) async {
                                await _preferencesService
                                    .saveBurstDetectionEnabled(v);
                                setState(() => _burstDetectionEnabled = v);
                              },
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Burst sequence detection',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    'Offer to caption following frames only (≤1s apart, not earlier shots). Off by default.',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ElevatedGreyButton(
                          label: 'Metadata preset',
                          fontSize: 11,
                          icon: Icons.description_outlined,
                          onPressed: _openMetadataPreset,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            AppCompactCheckbox(
                              value: _applyPresetToAllImages,
                              onChanged: (v) {
                                setState(() {
                                  _applyPresetToAllImages = v;
                                });
                              },
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Apply preset to all images in session',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── GO TIME button ──
                    Center(
                      child: CustomButton(
                        onTap: () {
                          if (_canProceed) {
                            setState(() => _goTimeWarningText = null);
                            widget.onConfigurationComplete(
                              selectedFolderPath!,
                              selectedHomeTeam,
                              selectedAwayTeam,
                            );
                            return;
                          }
                          final missingTeams =
                              selectedHomeTeam == null ||
                                  selectedAwayTeam == null;
                          final sameTeam = selectedHomeTeam != null &&
                              selectedAwayTeam != null &&
                              selectedHomeTeam == selectedAwayTeam;
                          String message = 'Complete setup before continuing.';
                          if (missingTeams) {
                            message = 'Select both Away and Home teams.';
                          } else if (sameTeam) {
                            message = 'Home and away teams must be different.';
                          }
                          setState(() => _goTimeWarningText = message);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: _canProceed
                                ? const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Color(0xFF3A5F78), Color(0xFF2A4858)],
                                  )
                                : null,
                            color: _canProceed ? null : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.play_arrow_rounded,
                                    size: 16,
                                    color: _canProceed
                                        ? Colors.white
                                        : Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Go Time',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: _canProceed
                                          ? Colors.white
                                          : Colors.grey.shade600,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                              if (_goTimeWarningText != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _goTimeWarningText!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.red.shade400,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
