import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../services/mlb_api_service.dart';
import '../services/api_manager.dart';
import '../services/ftpclient_service.dart';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Custom button widget with cursor styling and press feedback
class CustomButton extends StatefulWidget {
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
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          transform: _isPressed
              ? Matrix4.translationValues(0, 2, 0)
              : Matrix4.translationValues(0, 0, 0),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 100),
            opacity: _isPressed ? 0.8 : 1.0,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class CaptionFieldsWidget extends StatefulWidget {
  final Map<String, dynamic>? metadata;
  final Function(Map<String, dynamic>?)? onMetadataUpdated;
  final String? homeTeam;
  final String? awayTeam;
  final VoidCallback? onNextImage;
  final VoidCallback? onPreviousImage;
  final VoidCallback? onReset;
  final String? personalityOverride;
  final Function(List<String>)? onImagesLoaded;
  final List<Player>? preloadedHomeRoster;
  final List<Player>? preloadedAwayRoster;
  final String? currentImagePath;
  final Future<void> Function()? onSaveIptc;
  final Future<void> Function()? onSaveIptcBackground;

  const CaptionFieldsWidget({
    super.key,
    this.metadata,
    this.onMetadataUpdated,
    this.homeTeam,
    this.awayTeam,
    this.onNextImage,
    this.onPreviousImage,
    this.onReset,
    this.personalityOverride,
    this.onImagesLoaded,
    this.preloadedHomeRoster,
    this.preloadedAwayRoster,
    this.currentImagePath,
    this.onSaveIptc,
    this.onSaveIptcBackground,
  });

  @override
  State<CaptionFieldsWidget> createState() => _CaptionFieldsWidgetState();
}

class _CaptionFieldsWidgetState extends State<CaptionFieldsWidget> {
  // Controllers
  final TextEditingController captionController = TextEditingController();
  final TextEditingController personalityController = TextEditingController();
  TextEditingController _homeSearchController = TextEditingController();
  TextEditingController _awaySearchController = TextEditingController();
  final TextEditingController cityController = TextEditingController();
  final TextEditingController provinceController = TextEditingController();
  final TextEditingController stadiumController = TextEditingController();
  // Creator field is now handled by metadata widget only
  final TextEditingController customCelebrationController =
      TextEditingController();
  final TextEditingController customDejectionController =
      TextEditingController();
  final TextEditingController customBetweenPlayersController =
      TextEditingController();
  final TextEditingController _managerNameController = TextEditingController();
  String _homeSearchText = '';
  String _awaySearchText = '';
  String _managerName = '';

  // Date
  DateTime selectedDate = DateTime.now();

  // Verb selection
  String? _selectedVerb;
  String? _selectedActionVerb; // Stores the verb for caption generation
  String? _selectedHittingAction;
  bool _showExtraInnings = false;
  int _extraInningsPage = 0;

  String? _selectedHomeRunType;
  String? _selectedTagsAction; // For Tags submenu
  String? _selectedBase; // Track which base is selected for options
  String?
      _selectedBaseBeforeTaggedOut; // Track base before Tagged Out was selected
  int? _rbiCount;
  bool _isBatterRunning = false;
  bool _isSliding = false;
  bool _showFieldingOptions = false;
  bool _removeAccent = false; // Disabled diacritic removal
  bool _disableFtp = false; // Default to false (FTP enabled)
  int _ftpPictureNumber = 1; // Counter for FTP picture number, starting at 001

  // FTP Settings
  String _ftpHost = 'ftp.photoshelter.com';
  String _ftpUsername = 'mb1';
  String _ftpPassword = '';
  int _ftpPort = 21;
  String _ftpRemotePath = '';
  bool _ftpPassiveMode = true;

  // FTP Profile Management
  Map<String, Map<String, dynamic>> _ftpProfiles = {};
  String? _currentFtpProfile;
  String? _selectedFieldingAction;
  String? _selectedBaseRunningAction;
  String? _selectedStealBase;
  bool _showStealAgainstPlayer = false;
  bool _isSoloCelebration = false;
  Set<String> celebrateWith = {};
  Set<String> celebrateAgainst = {};
  String? _selectedCelebrationType;
  String? _selectedDejectionType;
  bool _isCelebratingScoring = false;
  bool _isCelebratingWithTeammates = false;
  bool _cameFromCelebration =
      false; // Track if we came from celebration section
  String? _selectedAtBatAction;
  String? _selectedBattingAction;

  // Custom text inning selector
  bool _showCustomTextInningSelector = false;
  int? _selectedCustomTextInning;

  // Smart custom text field state
  bool _isPlayerSearchMode = true;
  List<Player> _filteredPlayers = [];
  Set<String> _selectedPlayerNumbers = {};
  String _playerSearchText = '';
  bool _noPlayersFound = false;

  // Magic input player selection state
  List<Player> _magicInputMatchingPlayers = [];
  String _magicInputActionText = '';
  bool _showMagicInputPlayerOptions = false;
  bool _waitingForHomeVisitorChoice = false;

  // Team data
  bool _isConnectedToApi = false;
  String? homeTeamStadium;
  String? awayTeamStadium;

  // Caption building data
  String? selectedHomeTeam;
  String? selectedAwayTeam;
  Set<String> selectedHomePlayers = {};
  Set<String> selectedAwayPlayers = {};

  // Sort options for player lists
  String _homeSortOption = 'number'; // 'number', 'lastName', 'firstName'
  String _awaySortOption = 'number';
  bool _homeSortAscending = true; // true = ascending, false = descending
  bool _awaySortAscending = true;

  // Player display mode - list or grid
  bool _homePlayerGridMode = true; // false = list, true = grid
  bool _awayPlayerGridMode = true;

  String? selectedCaptionVerb;

  // Track which team was selected first (for determining main subject)
  bool? _firstTeamSelected;

  // Track the first player selected (for star indicator)
  String? _firstPlayerSelected;

  // API Manager and roster data
  final ApiManager _apiManager = ApiManager();
  List<Player> _homeRoster = [];
  List<Player> _awayRoster = [];
  bool _isLoadingRosters = false;

  // Static teams list for dropdown
  final List<String> teamsList = [
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
    'Washington Nationals',
  ];

  // Additional verb building state
  int? _selectedRbiInning;
  bool _isDivingCatch = false;
  bool _walkOff = false;
  bool _isPriorToGame = false; // Track if "prior to the game" is selected

  // Preserve per-hit-type selections
  final Map<String, int?> _rbiCountByHit = {};
  final Map<String, String?> _homeRunTypeByHit = {};
  final Map<String, int?> _inningByHit = {};
  final Map<String, bool?> _batterRunningByHit = {};

  // Caption state
  String _lastCaption = '';

  // Verb categories
  final Map<String, List<String>> verbCategories = {
    'Offense': [
      'Single',
      'Double',
      'Triple',
      'Home Run',
      'At Bat',
      'Swings',
      'Bunts',
      'Hit by Pitch'
    ],
    'Defense': [
      'Pitching',
      'Catches',
      'Throws',
      'Tags',
      'Groundball',
      'Fielding Position',
      'Double Play',
      'Triple Play'
    ],
    'Running': ['Steals', 'Slides', 'Runs', 'Rounds'],
    'Reactions': ['Celebrates', 'Dejection', 'Post Game Win', 'Post Game Loss'],
    'Non Game-Action': [
      'Looks On',
      'Batting Practice',
      'Fielding Practice',
      'Takes the Field',
      'Comes Off the Field',
      'National Anthem',
      'Stretching',
      'Warm Ups',
      'Pitching Change'
    ],
  };

  bool _isResetting = false;

  // Add a flag to track if the user has manually reset the fields.
  bool _hasBeenReset = false;

  // Track team positioning (true = home on left, false = home on right)
  bool _homeOnLeft = true;

  // Build team dropdown widget
  Widget _buildTeamDropdown({
    required bool isHome,
    required String? selectedTeam,
    required ValueChanged<String?> onTeamChanged,
  }) {
    // Filter out the other team
    final availableTeams = isHome
        ? teamsList.where((team) => team != selectedAwayTeam).toList()
        : teamsList.where((team) => team != selectedHomeTeam).toList();

    final dropdown = Material(
      elevation: 2.0,
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300, width: 1.0),
          borderRadius: BorderRadius.circular(4),
          color: Colors.white,
        ),
        child: PopupMenuButton<String>(
          initialValue: selectedTeam,
          onSelected: onTeamChanged,
          constraints: const BoxConstraints(maxHeight: 600),
          itemBuilder: (context) => availableTeams
              .map(
                (item) => PopupMenuItem<String>(
                  value: item,
                  height: 14,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  child: Container(
                    height: 14,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Row(
                      children: [
                        // Home/Away symbol
                        if (isHome)
                          Icon(Icons.home,
                              size: 12, color: Colors.grey.shade700),
                        if (!isHome)
                          Icon(Icons.flight_takeoff,
                              size: 12, color: Colors.grey.shade700),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            item,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              children: [
                // Label
                Text(
                  '${isHome ? "Home" : "Away"}: ',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                // Home/Away symbol for selected item
                if (selectedTeam != null) ...[
                  if (isHome)
                    Icon(Icons.home, size: 11, color: Colors.grey.shade700),
                  if (!isHome)
                    Icon(Icons.flight_takeoff,
                        size: 11, color: Colors.grey.shade700),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      selectedTeam,
                      style: const TextStyle(fontSize: 11, color: Colors.black),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else ...[
                  const Expanded(
                    child: Text(
                      'Select Team',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                ],
                const Icon(Icons.arrow_drop_down, size: 14),
              ],
            ),
          ),
        ),
      ),
    );

    return dropdown;
  }

  // Team color mapping
  Color _getTeamColor(String? teamName) {
    if (teamName == null) return Colors.grey.shade700;

    final teamColors = {
      'New York Yankees': Colors.blue.shade900,
      'Boston Red Sox': Colors.red.shade700,
      'Toronto Blue Jays': Colors.blue.shade600,
      'Baltimore Orioles': Colors.orange.shade700,
      'Tampa Bay Rays': Colors.blue.shade400,
      'Cleveland Guardians': Colors.red.shade800,
      'Minnesota Twins': Colors.blue.shade700,
      'Detroit Tigers': Colors.orange.shade600,
      'Chicago White Sox': Colors.black,
      'Kansas City Royals': Colors.amber.shade600, // Gold
      'Houston Astros': Colors.blue.shade800, // Navy blue
      'Texas Rangers': Colors.blue.shade800, // Navy blue
      'Seattle Mariners': Colors.teal.shade600, // Teal
      'Los Angeles Angels': Colors.white, // White
      'Oakland Athletics': Colors.yellow.shade600, // Yellow
      'Atlanta Braves': Colors.red.shade700,
      'Philadelphia Phillies': Colors.red.shade600,
      'New York Mets': Colors.blue.shade600,
      'Washington Nationals': Colors.red.shade700,
      'Miami Marlins': Colors.orange.shade600,
      'Milwaukee Brewers': Colors.blue.shade700,
      'Chicago Cubs': Colors.blue.shade800,
      'St. Louis Cardinals': Colors.red.shade700,
      'Cincinnati Reds': Colors.red.shade600,
      'Pittsburgh Pirates': Colors.black,
      'Los Angeles Dodgers': Colors.blue.shade800,
      'San Francisco Giants': Colors.orange.shade600,
      'San Diego Padres': Colors.brown.shade600,
      'Colorado Rockies': Colors.purple.shade700,
      'Arizona Diamondbacks': Colors.red.shade700,
    };

    return teamColors[teamName] ?? Colors.grey.shade700;
  }

  // Secondary team color mapping for contrast
  Color _getTeamSecondaryColor(String? teamName) {
    if (teamName == null) return Colors.grey.shade500;

    final teamSecondaryColors = {
      'New York Yankees': Colors.white, // White pinstripes
      'Boston Red Sox': Colors.blue.shade800, // Navy blue
      'Toronto Blue Jays': Colors.white, // White
      'Baltimore Orioles': Colors.black, // Black
      'Tampa Bay Rays': Colors.yellow.shade600, // Yellow
      'Cleveland Guardians': Colors.blue.shade800, // Navy blue
      'Minnesota Twins': Colors.red.shade600, // Red
      'Detroit Tigers': Colors.white, // White
      'Chicago White Sox': Colors.white, // White
      'Kansas City Royals': Colors.amber.shade600, // Gold
      'Houston Astros': Colors.blue.shade800, // Navy blue
      'Texas Rangers': Colors.blue.shade800, // Navy blue
      'Seattle Mariners': Colors.teal.shade600, // Teal
      'Los Angeles Angels': Colors.white, // White
      'Oakland Athletics': Colors.yellow.shade600, // Yellow
      'Atlanta Braves': Colors.blue.shade800, // Navy blue
      'Philadelphia Phillies': Colors.blue.shade800, // Navy blue
      'New York Mets': Colors.orange.shade600, // Orange
      'Washington Nationals': Colors.blue.shade800, // Navy blue
      'Miami Marlins': Colors.black, // Black
      'Milwaukee Brewers': Colors.yellow.shade600, // Gold
      'Chicago Cubs': Colors.red.shade600, // Red
      'St. Louis Cardinals': Colors.white, // White
      'Cincinnati Reds': Colors.white, // White
      'Pittsburgh Pirates': Colors.yellow.shade600, // Gold
      'Los Angeles Dodgers': Colors.white, // White
      'San Francisco Giants': Colors.black, // Black
      'San Diego Padres': Colors.yellow.shade600, // Gold
      'Colorado Rockies': Colors.black, // Black
      'Arizona Diamondbacks': Colors.teal.shade600, // Teal
    };

    return teamSecondaryColors[teamName] ?? Colors.grey.shade500;
  }

  // Method to get current values from caption-related controllers
  Map<String, String> getCurrentCaptionValues() {
    return {
      'Caption-Abstract': captionController.text,
      'XMP:Description':
          captionController.text, // Photo Mechanic compatible caption field
      'ImageDescription': captionController.text, // EXIF description field
      'XMP-getty:Personality': personalityController.text,
      'Sub-location': stadiumController.text,
      'City': cityController.text,
      'Province-State': provinceController.text,
    };
  }

  @override
  void initState() {
    super.initState();
    _homeSearchController.addListener(() {
      setState(() {
        _homeSearchText = _homeSearchController.text;
      });
    });
    _awaySearchController.addListener(() {
      setState(() {
        _awaySearchText = _awaySearchController.text;
      });
    });
    _initializeSampleData();
    if (widget.personalityOverride != null) {
      personalityController.text = widget.personalityOverride!;
    }
    _loadFtpProfiles();
  }

  @override
  void dispose() {
    _homeSearchController.dispose();
    _awaySearchController.dispose();
    super.dispose();
  }

  void _initializeSampleData() {
    // Initialize with teams from app bar, or null if not provided
    selectedHomeTeam = widget.homeTeam;
    selectedAwayTeam = widget.awayTeam;

    // Don't initialize controllers with default values - only load from EXIF data

    // Load rosters from MLB API only if both teams are provided
    if (selectedHomeTeam != null && selectedAwayTeam != null) {
      _loadTeamRosters();
    }
  }

  Future<void> _fetchAndSetVenueForGame() async {
    if (selectedHomeTeam == null || selectedAwayTeam == null) return;

    // Get the photo date from metadata
    DateTime gameDate = DateTime.now();
    if (widget.metadata != null) {
      final dateTimeOriginal = widget.metadata!['DateTimeOriginal']?.toString();
      final createDate = widget.metadata!['CreateDate']?.toString();
      final modifyDate = widget.metadata!['ModifyDate']?.toString();

      // Try to parse the date from EXIF data
      final dateString = dateTimeOriginal ?? createDate ?? modifyDate;
      if (dateString != null && dateString.isNotEmpty) {
        try {
          // Parse EXIF date format (YYYY:MM:DD HH:MM:SS)
          final parts = dateString.split(' ');
          if (parts.length >= 1) {
            final datePart = parts[0];
            final dateComponents = datePart.split(':');
            if (dateComponents.length >= 3) {
              final year = int.parse(dateComponents[0]);
              final month = int.parse(dateComponents[1]);
              final day = int.parse(dateComponents[2]);
              gameDate = DateTime(year, month, day);
              print(
                  'DEBUG: Venue fetch - Parsed game date: ${gameDate.toIso8601String().split('T')[0]}');
            }
          }
        } catch (e) {
          print('Error parsing photo date: $e');
          // Fallback to current date
        }
      } else {
        print(
            'DEBUG: Venue fetch - No date string found in metadata, using current date');
      }
    } else {}

    try {
      final venue = await _apiManager.fetchVenueForGame(
          selectedHomeTeam!, selectedAwayTeam!, gameDate);
      // Removed auto-population of stadium and city/state from venue data
      // Only load values from EXIF metadata, not from API
    } catch (e) {
      print('Error fetching venue for game: $e');
    }
  }

  // Removed _setCityFromStadium function - no auto-population of city/state

  Future<void> _loadTeamRosters() async {
    if (selectedHomeTeam == null || selectedAwayTeam == null) return;

    // Check if we have preloaded roster data
    if (widget.preloadedHomeRoster != null &&
        widget.preloadedAwayRoster != null) {
      setState(() {
        _homeRoster = widget.preloadedHomeRoster!;
        _awayRoster = widget.preloadedAwayRoster!;
        _isLoadingRosters = false;

        // Clear any existing selections since rosters have changed
        selectedHomePlayers.clear();
        selectedAwayPlayers.clear();
        _firstTeamSelected = null; // Reset first team selection
        _firstPlayerSelected = null; // Reset first player selection
        print(
            'DEBUG: Using preloaded rosters: ${_homeRoster.length} home players, ${_awayRoster.length} away players');
      });

      // Fetch venue information for the specific game and update stadium field
      if (selectedHomeTeam != null &&
          selectedAwayTeam != null &&
          stadiumController.text.isEmpty) {
        _fetchAndSetVenueForGame();
      }

      return; // Skip API calls since we have preloaded data
    }

    setState(() {
      _isLoadingRosters = true;
    });

    try {
      // Load both team rosters and team info in parallel
      final futures = await Future.wait([
        _apiManager.fetchTeamRoster(selectedHomeTeam!),
        _apiManager.fetchTeamRoster(selectedAwayTeam!),
        _apiManager.fetchTeams().then((teams) => teams.firstWhere(
              (team) => team.name == selectedHomeTeam,
              orElse: () => throw Exception('Team not found'),
            )),
        _apiManager.fetchTeams().then((teams) => teams.firstWhere(
              (team) => team.name == selectedAwayTeam,
              orElse: () => throw Exception('Team not found'),
            )),
      ]);

      setState(() {
        _homeRoster = futures[0] as List<Player>;
        _awayRoster = futures[1] as List<Player>;
        final homeTeamInfo = futures[2] as TeamInfo?;
        final awayTeamInfo = futures[3] as TeamInfo?;

        // Set stadium names from API (will be fetched separately for balldontlie)
        homeTeamStadium = null; // Will be fetched separately
        awayTeamStadium = null; // Will be fetched separately

        // Fetch venue information for the specific game and update stadium field
        if (selectedHomeTeam != null &&
            selectedAwayTeam != null &&
            stadiumController.text.isEmpty) {
          _fetchAndSetVenueForGame();
        }

        _isLoadingRosters = false;

        // Clear any existing selections since rosters have changed
        selectedHomePlayers.clear();
        selectedAwayPlayers.clear();
        _firstTeamSelected = null; // Reset first team selection
        _firstPlayerSelected = null; // Reset first player selection
      });

      print(
          'Successfully loaded rosters: ${_homeRoster.length} home players, ${_awayRoster.length} away players');
      print('Home team stadium: $homeTeamStadium');
      print('Away team stadium: $awayTeamStadium');
    } catch (e) {
      print('Error loading team rosters: $e');
      setState(() {
        _isLoadingRosters = false;
      });

      // Show error message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load team rosters: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void didUpdateWidget(CaptionFieldsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.personalityOverride != null &&
        widget.personalityOverride != oldWidget.personalityOverride) {
      personalityController.text = widget.personalityOverride!;
    }
    if (widget.metadata != oldWidget.metadata) {
      // Reset selections when metadata changes (new image loaded)
      resetCaptionSelections();
      _loadMetadata();
    }

    // Check if teams have changed
    if (oldWidget.homeTeam != widget.homeTeam ||
        oldWidget.awayTeam != widget.awayTeam) {
      setState(() {
        selectedHomeTeam = widget.homeTeam;
        selectedAwayTeam = widget.awayTeam;

        // Clear existing selections and rosters
        selectedHomePlayers.clear();
        selectedAwayPlayers.clear();
        _firstTeamSelected = null; // Reset first team selection
        _firstPlayerSelected = null; // Reset first player selection

        _homeRoster.clear();
        _awayRoster.clear();
      });

      // Load new rosters if both teams are selected
      if (selectedHomeTeam != null && selectedAwayTeam != null) {
        _loadTeamRosters();
      }
    }
  }

  void _loadMetadata() {
    // If a reset has been performed, do not load metadata again.
    if (_hasBeenReset) return;

    if (widget.metadata == null) return;
    final meta = widget.metadata!;

    // Load Caption: Prefer IPTC "Caption-Abstract", fallback to EXIF "ImageDescription"
    final dynamic captionAbstract = meta['Caption-Abstract'];
    final dynamic imageDescription = meta['ImageDescription'];
    final extractedCaption =
        (captionAbstract is String ? captionAbstract : '') ??
            (imageDescription is String ? imageDescription : '') ??
            '';

    // Load Personality: Read from XMP-getty:Personality
    final dynamic extractedPersonality =
        meta['XMP-getty:Personality'] ?? meta['Personality'];
    final personInImageText = (extractedPersonality is List)
        ? extractedPersonality.join(';')
        : (extractedPersonality is String ? extractedPersonality : '');

    // Load location fields from metadata
    final dynamic subLocation = meta['Sub-location'];
    final dynamic city = meta['City'];
    final dynamic province = meta['Province-State'];
    final extractedStadium = subLocation is String ? subLocation : '';
    final extractedCity = city is String ? city : '';
    final extractedProvince = province is String ? province : '';

    // Creator field is now handled by metadata widget only

    setState(() {
      captionController.text = extractedCaption;
      personalityController.text = personInImageText;

      // Only set personality from metadata if the user hasn't manually reset.
      if (!_hasBeenReset) {
        personalityController.text = personInImageText;
      }

      // Load location fields from metadata
      stadiumController.text = extractedStadium;
      cityController.text = extractedCity;
      provinceController.text = extractedProvince;

      // Creator field is now handled by metadata widget only
    });
  }

  // Reset all caption building selections when navigating to a new image
  void resetCaptionSelections() {
    setState(() {
      // Clear player selections
      selectedHomePlayers.clear();
      selectedAwayPlayers.clear();
      _firstPlayerSelected = null;
      _firstTeamSelected = null;

      // Clear verb selections
      _selectedVerb = null;
      _selectedActionVerb = null;
      _selectedHittingAction = null;

      // Clear celebration settings
      _isCelebratingWithTeammates = false;

      // Clear other selections
      _rbiCount = null;
      _selectedRbiInning = null;
      _selectedCustomTextInning = null;

      // Clear search states
      _filteredPlayers.clear();
      _noPlayersFound = false;
      _isPlayerSearchMode = false;
      _magicInputMatchingPlayers.clear();
      _magicInputActionText = '';
      _waitingForHomeVisitorChoice = false;

      // Clear custom text fields
      customCelebrationController.clear();
      customDejectionController.clear();
      customBetweenPlayersController.clear();

      // Clear search bars
      _homeSearchController.clear();
      _awaySearchController.clear();
      _homeSearchText = '';
      _awaySearchText = '';

      // Reset hasBeenReset flag to allow metadata loading
      _hasBeenReset = false;
    });
  }

  // Public method to reset caption selections (can be called from parent)
  void resetSelections() {
    resetCaptionSelections();
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
          // Caption Builder Section
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Left side: Caption, Personality, and Player/Verb area (70%)
                  Expanded(
                    flex: 8,
                    child: Column(
                      children: [
                        // Caption and Personality boxes side by side
                        Row(
                          children: [
                            // Caption Preview (Left side) - Moderate width
                            Expanded(
                              flex: 5,
                              child: TextField(
                                controller: captionController,
                                maxLines: 3,
                                style: const TextStyle(fontSize: 12),
                                decoration: InputDecoration(
                                  labelText: 'Caption',
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  hintText:
                                      'Generated caption will appear here...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide:
                                        BorderSide(color: Colors.grey.shade400),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide:
                                        BorderSide(color: Colors.grey.shade400),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(
                                        color: Colors.blue.shade400, width: 2),
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
                              ),
                            ),
                            const SizedBox(width: 9),
                            // Personality Box (Right side) - Reduced to make room for caption
                            Expanded(
                              flex: 1,
                              child: TextField(
                                controller: personalityController,
                                maxLines: 3,
                                style: const TextStyle(fontSize: 12),
                                decoration: InputDecoration(
                                  labelText: 'Personality',
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  hintText: 'Personality tags...',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide:
                                        BorderSide(color: Colors.grey.shade400),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide:
                                        BorderSide(color: Colors.grey.shade400),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(
                                        color: Colors.blue.shade400, width: 2),
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
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 6),

                        // Action buttons row (aligned with caption box)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            // Navigation buttons: Prev, Copy, Paste, Next (aligned with caption box)
                            Expanded(
                              flex: 5, // Match caption box width
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Prev button
                                  CustomButton(
                                    onTap: () async {
                                      // Save metadata to current image in background (don't await)
                                      if (widget.onSaveIptc != null) {
                                        widget.onSaveIptc!();
                                      }
                                      // Move to previous image immediately
                                      widget.onPreviousImage?.call();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: Colors.grey.shade300),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.arrow_back,
                                              size: 12,
                                              color: Colors.grey.shade700),
                                          const SizedBox(width: 2),
                                          Text('Prev',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade700,
                                                  fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  // Copy button
                                  CustomButton(
                                    onTap: () {
                                      _copyMetadataFromCaptionWidget();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: Colors.grey.shade300),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.copy,
                                              size: 12,
                                              color: Colors.grey.shade700),
                                          const SizedBox(width: 2),
                                          Text('Copy',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade700,
                                                  fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  // Paste button
                                  CustomButton(
                                    onTap: _pasteMetadataToCaptionWidget,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: Colors.grey.shade300),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.paste,
                                              size: 12,
                                              color: Colors.grey.shade700),
                                          const SizedBox(width: 2),
                                          Text('Paste',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade700,
                                                  fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  // Next button
                                  CustomButton(
                                    onTap: () async {
                                      // Save metadata to current image in background (don't await)
                                      if (widget.onSaveIptc != null) {
                                        widget.onSaveIptc!();
                                      }
                                      // Move to next image immediately
                                      widget.onNextImage?.call();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: Colors.grey.shade300),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text('Next',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade700,
                                                  fontWeight: FontWeight.w500)),
                                          const SizedBox(width: 2),
                                          Icon(Icons.arrow_forward,
                                              size: 12,
                                              color: Colors.grey.shade700),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(
                                width: 9), // Match caption/personality spacing
                            // Reset, Settings, and FTP buttons (aligned with personality box)
                            Expanded(
                              flex: 1, // Match personality box width
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  // Reset button
                                  CustomButton(
                                    onTap: _resetCaption,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: Colors.grey.shade300),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.refresh,
                                              size: 12,
                                              color: Colors.grey.shade700),
                                          const SizedBox(width: 2),
                                          Text('Reset',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey.shade700,
                                                  fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  // Settings button (now between reset and FTP)
                                  CustomButton(
                                    onTap: _showFtpSettings,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4A90E2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: const Color(0xFF4A90E2)),
                                      ),
                                      child: Icon(Icons.settings,
                                          size: 14, color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  // FTP button
                                  CustomButton(
                                    onTap: _disableFtp ? null : _onFtpPressed,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _disableFtp
                                            ? Colors.grey.shade300
                                            : const Color(0xFF0052CC),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: _disableFtp
                                                ? Colors.grey.shade300
                                                : const Color(0xFF0052CC)),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.cloud_upload,
                                              size: 14,
                                              color: _disableFtp
                                                  ? Colors.grey.shade600
                                                  : Colors.white),
                                          const SizedBox(width: 4),
                                          Text(
                                              _disableFtp
                                                  ? 'FTP OFF'
                                                  : (_currentFtpProfile != null
                                                      ? 'FTP: $_currentFtpProfile'
                                                      : 'FTP'),
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: _disableFtp
                                                      ? Colors.grey.shade600
                                                      : Colors.white,
                                                  fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 6),

                        // Player and Verb Selection Area
                        Expanded(
                          child: _buildCaptionBuildingSection(),
                        ),
                      ],
                    ),
                  ),

                  // Right side removed - personality box is now beside caption box
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptionBuildingSection() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400, width: 1),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Row(
        children: [
          // Left Team (Home or Away depending on _homeOnLeft)
          Expanded(
            flex: 2,
            child: _buildCompactTeamColumn(_homeOnLeft ? true : false),
          ),

          const SizedBox(width: 4),

          // Verbs (Center) - 80% of space
          Expanded(
            flex: 8,
            child: _buildCompactVerbColumn(),
          ),

          const SizedBox(width: 4),

          // Right Team (Away or Home depending on _homeOnLeft)
          Expanded(
            flex: 2,
            child: _buildCompactTeamColumn(_homeOnLeft ? false : true),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamColumn(String title, String? teamName, bool isHome) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Team name display
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
                color: isHome ? Colors.grey.shade700 : Colors.grey.shade400),
            borderRadius: BorderRadius.circular(6),
            color: isHome ? Colors.grey.shade700 : Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: isHome ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                teamName ?? 'No Team Selected',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isHome ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Player selection area
        Container(
          width: double.infinity,
          height: 80,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(6),
            color: Colors.white,
          ),
          child: _isLoadingRosters
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Loading roster...',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Add players button
                    GestureDetector(
                      onTap: () => _showPlayerSelectionDialog(isHome),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.grey.shade50,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add,
                              size: 14,
                              color: isHome
                                  ? Colors.blue.shade600
                                  : Colors.orange.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Add Players',
                              style: TextStyle(
                                fontSize: 10,
                                color: isHome
                                    ? Colors.blue.shade700
                                    : Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Selected player chips
                    if ((isHome ? selectedHomePlayers : selectedAwayPlayers)
                        .isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: _sortPlayersByNumber(isHome
                                ? selectedHomePlayers
                                : selectedAwayPlayers)
                            .map((playerName) =>
                                _buildPlayerChip(playerName, isHome))
                            .toList(),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildVerbColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Action',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(6),
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Main verb selection
              _buildMainVerbSelector(),

              // Hit type options (when "hit" is selected)
              if (_selectedVerb == 'Single' ||
                  _selectedVerb == 'Double' ||
                  _selectedVerb == 'Triple' ||
                  _selectedVerb == 'Home Run' ||
                  _selectedVerb == 'Grand Slam') ...[
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCaptionPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note, size: 16, color: Colors.black87),
              const SizedBox(width: 8),
              const Text(
                'Generated Caption:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              captionController.text.isEmpty
                  ? 'No caption generated yet...'
                  : captionController.text,
              style: TextStyle(
                fontSize: 12,
                color: captionController.text.isEmpty
                    ? Colors.grey.shade600
                    : Colors.black87,
                fontStyle: captionController.text.isEmpty
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ),
          if (captionController.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactTeamColumn(bool isHome) {
    final roster = isHome ? _homeRoster : _awayRoster;
    final selectedPlayers = isHome ? selectedHomePlayers : selectedAwayPlayers;
    final searchController =
        isHome ? _homeSearchController : _awaySearchController;
    final searchText = isHome ? _homeSearchText : _awaySearchText;

    // Filtered roster
    final filteredRosterUnsorted = searchText.isEmpty
        ? roster
        : roster
            .where((player) => player.displayName
                .toLowerCase()
                .contains(searchText.toLowerCase()))
            .toList();

    // Sort the filtered roster by current sort option
    final sortOption = isHome ? _homeSortOption : _awaySortOption;
    final ascending = isHome ? _homeSortAscending : _awaySortAscending;
    final filteredRoster =
        _sortPlayerObjects(filteredRosterUnsorted, sortOption, ascending);

    // Debug output
    // print(
    //     '${isHome ? "HOME" : "AWAY"} Search: "$searchText", Roster: ${roster.length}, Filtered: ${filteredRoster.length}');

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Team header with symbol and search bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            child: Row(
              children: [
                // Show team dropdown when no team selected, or team name + controls when team selected
                if (isHome
                    ? selectedHomeTeam == null
                    : selectedAwayTeam == null) ...[
                  // Team selection area when no team selected
                  Expanded(
                    child: _buildTeamDropdown(
                      isHome: isHome,
                      selectedTeam:
                          isHome ? selectedHomeTeam : selectedAwayTeam,
                      onTeamChanged: (String? newValue) async {
                        if (newValue == null) return;
                        setState(() {
                          if (isHome) {
                            selectedHomeTeam = newValue;
                          } else {
                            selectedAwayTeam = newValue;
                          }
                        });

                        // Load rosters and show debug popup
                        await _loadTeamRosters();
                        _showTeamSelectionDebug(newValue, isHome);
                      },
                    ),
                  ),
                ] else ...[
                  // Team name and controls when team is selected
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Team name row
                        Row(
                          children: [
                            Icon(
                              isHome ? Icons.home : Icons.flight,
                              size: 12,
                              color: Colors.black87,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getTeamAbbreviation(isHome
                                  ? selectedHomeTeam!
                                  : selectedAwayTeam!),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Search field on top line
                            Expanded(
                              child: SizedBox(
                                height: 24,
                                child: TextField(
                                  controller: searchController,
                                  style: const TextStyle(fontSize: 10),
                                  onChanged: (value) {
                                    setState(() {
                                      if (isHome) {
                                        _homeSearchText = value;
                                      } else {
                                        _awaySearchText = value;
                                      }
                                    });
                                  },
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 0),
                                    hintText: 'Search',
                                    prefixIcon: Icon(Icons.search,
                                        size: 14, color: Colors.grey),
                                    prefixIconConstraints: BoxConstraints(
                                        minWidth: 20, minHeight: 20),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(4),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade400),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(4),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade400),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(4),
                                      borderSide: BorderSide(
                                          color: Colors.blue.shade400,
                                          width: 1),
                                    ),
                                    hintStyle: const TextStyle(
                                        fontSize: 10, color: Colors.grey),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        // Controls row
                        Row(
                          children: [
                            // Type label
                            Text(
                              'Display Type: ',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey),
                            ),
                            // Type button
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (isHome) {
                                      _homePlayerGridMode =
                                          !_homePlayerGridMode;
                                      // Reset sort order when switching to grid mode
                                      if (_homePlayerGridMode) {
                                        _homeSortOption = 'number';
                                        _homeSortAscending = true;
                                      }
                                    } else {
                                      _awayPlayerGridMode =
                                          !_awayPlayerGridMode;
                                      // Reset sort order when switching to grid mode
                                      if (_awayPlayerGridMode) {
                                        _awaySortOption = 'number';
                                        _awaySortAscending = true;
                                      }
                                    }
                                  });
                                },
                                child: Text(
                                  isHome
                                      ? (_homePlayerGridMode ? 'Grid' : 'List')
                                      : (_awayPlayerGridMode ? 'Grid' : 'List'),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w500),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Sort by options (only show when in List mode)
                            if (!(isHome
                                ? _homePlayerGridMode
                                : _awayPlayerGridMode)) ...[
                              Text(
                                'Sort by: ',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey),
                              ),
                              MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      if (isHome) {
                                        if (_homeSortOption == 'number') {
                                          _homeSortOption = 'lastName';
                                        } else if (_homeSortOption ==
                                            'lastName') {
                                          _homeSortOption = 'firstName';
                                        } else {
                                          _homeSortOption = 'number';
                                        }
                                      } else {
                                        if (_awaySortOption == 'number') {
                                          _awaySortOption = 'lastName';
                                        } else if (_awaySortOption ==
                                            'lastName') {
                                          _awaySortOption = 'firstName';
                                        } else {
                                          _awaySortOption = 'number';
                                        }
                                      }
                                    });
                                  },
                                  child: Text(
                                    isHome
                                        ? (_homeSortOption == 'number'
                                            ? 'Number'
                                            : _homeSortOption == 'lastName'
                                                ? 'Last Name'
                                                : 'First Name')
                                        : (_awaySortOption == 'number'
                                            ? 'Number'
                                            : _awaySortOption == 'lastName'
                                                ? 'Last Name'
                                                : 'First Name'),
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            // Ascending/Descending button
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (isHome) {
                                      _homeSortAscending = !_homeSortAscending;
                                    } else {
                                      _awaySortAscending = !_awaySortAscending;
                                    }
                                  });
                                },
                                child: Text(
                                  isHome
                                      ? (_homeSortAscending ? '↑' : '↓')
                                      : (_awaySortAscending ? '↑' : '↓'),
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.black87,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Player list
          Expanded(
            child: _isLoadingRosters
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : filteredRoster.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text(
                            'No players',
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ),
                      )
                    : (isHome ? _homePlayerGridMode : _awayPlayerGridMode)
                        ? _buildPlayerGrid(
                            filteredRoster, selectedPlayers, isHome)
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: filteredRoster.length,
                            itemBuilder: (context, index) {
                              final player = filteredRoster[index];
                              final isSelected =
                                  selectedPlayers.contains(player.displayName);
                              final isHomePlayer = selectedHomePlayers
                                  .contains(player.displayName);

                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      if (isHome) {
                                        selectedHomePlayers
                                            .remove(player.displayName);
                                      } else {
                                        selectedAwayPlayers
                                            .remove(player.displayName);
                                      }
                                    } else {
                                      // Track which team was selected first
                                      if (_firstTeamSelected == null) {
                                        _firstTeamSelected = isHome;
                                        _firstPlayerSelected =
                                            player.displayName;
                                      } else {}
                                      if (isHome) {
                                        selectedHomePlayers
                                            .add(player.displayName);
                                      } else {
                                        selectedAwayPlayers
                                            .add(player.displayName);
                                      }
                                    }
                                  });
                                  _updateCaption();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? (isHomePlayer
                                            ? Colors.grey.shade700
                                            : Colors.white)
                                        : Colors.grey.shade100,
                                    border: Border(
                                      bottom: BorderSide(
                                          color: isSelected
                                              ? (isHomePlayer
                                                  ? Colors.grey.shade700
                                                  : Colors.grey.shade400)
                                              : Colors.grey.shade200,
                                          width: 0.5),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Red star for first selected player
                                      if (isSelected &&
                                          _isFirstSelectedPlayer(
                                              player.displayName))
                                        Container(
                                          margin:
                                              const EdgeInsets.only(right: 4),
                                          padding: const EdgeInsets.all(1),
                                          decoration: BoxDecoration(
                                            color: Colors.red,
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                          child: Icon(
                                            Icons.star,
                                            size: 8,
                                            color: Colors.white,
                                          ),
                                        ),
                                      Expanded(
                                        child: Text(
                                          _getFormattedPlayerName(
                                              player.displayName,
                                              isHome
                                                  ? _homeSortOption
                                                  : _awaySortOption),
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                            color: isSelected
                                                ? (isHomePlayer
                                                    ? Colors.white
                                                    : Colors.grey.shade800)
                                                : Colors.black87,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerGrid(
      List<Player> roster, Set<String> selectedPlayers, bool isHome) {
    // Create a map to track which numbers have players
    Map<int, Player> playersByNumber = {};
    for (Player player in roster) {
      int jerseyNum = int.tryParse(player.jerseyNumber ?? '0') ?? 0;
      playersByNumber[jerseyNum] = player;
    }

    // Get sorted list based on current sort option
    List<int> jerseyNumbers;
    final sortOption = isHome ? _homeSortOption : _awaySortOption;
    final ascending = isHome ? _homeSortAscending : _awaySortAscending;

    if (sortOption == 'number') {
      // Sort by jersey number
      jerseyNumbers = playersByNumber.keys.toList();
      if (ascending) {
        jerseyNumbers.sort();
      } else {
        jerseyNumbers.sort((a, b) => b.compareTo(a));
      }
    } else {
      // For lastName and firstName, sort the roster first, then get jersey numbers in that order
      List<Player> sortedRoster = List.from(roster);
      if (sortOption == 'lastName') {
        sortedRoster.sort((a, b) {
          String lastNameA = a.fullName.split(' ').skip(1).join(' ');
          String lastNameB = b.fullName.split(' ').skip(1).join(' ');
          return ascending
              ? lastNameA.compareTo(lastNameB)
              : lastNameB.compareTo(lastNameA);
        });
      } else if (sortOption == 'firstName') {
        sortedRoster.sort((a, b) {
          String firstNameA = a.fullName.split(' ').first;
          String firstNameB = b.fullName.split(' ').first;
          return ascending
              ? firstNameA.compareTo(firstNameB)
              : firstNameB.compareTo(firstNameA);
        });
      }

      // Get jersey numbers in the sorted order
      jerseyNumbers = sortedRoster.map((player) {
        return int.tryParse(player.jerseyNumber ?? '0') ?? 0;
      }).toList();
    }

    // Create rows with 4 squares per row
    List<Widget> rows = [];
    List<Widget> currentRow = [];

    for (int jerseyNum in jerseyNumbers) {
      Player player = playersByNumber[jerseyNum]!;
      bool isSelected = selectedPlayers.contains(player.displayName);
      bool isHomePlayer = selectedHomePlayers.contains(player.displayName);

      currentRow.add(
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                if (isSelected) {
                  if (isHome) {
                    selectedHomePlayers.remove(player.displayName);
                  } else {
                    selectedAwayPlayers.remove(player.displayName);
                  }
                } else {
                  // Track which team was selected first
                  if (_firstTeamSelected == null) {
                    _firstTeamSelected = isHome;
                    _firstPlayerSelected = player.displayName;
                  }
                  if (isHome) {
                    selectedHomePlayers.add(player.displayName);
                  } else {
                    selectedAwayPlayers.add(player.displayName);
                  }
                }
              });
              _updateCaption();
            },
            child: Container(
              margin: const EdgeInsets.all(1),
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? (isHomePlayer ? Colors.grey.shade700 : Colors.white)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isSelected
                      ? (isHomePlayer
                          ? Colors.grey.shade700
                          : Colors.grey.shade400)
                      : Colors.grey.shade300,
                  width: 0.5,
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          jerseyNum.toString(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected
                                ? (isHomePlayer ? Colors.white : Colors.black87)
                                : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          player.fullName.split(' ').skip(1).join(' '),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSelected
                                ? (isHomePlayer ? Colors.white : Colors.black87)
                                : Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  // Red star for first selected player
                  if (isSelected && _isFirstSelectedPlayer(player.displayName))
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Icon(
                          Icons.star,
                          size: 8,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      // When we have 4 items in the current row, add it to rows and start a new row
      if (currentRow.length == 4) {
        rows.add(Row(children: currentRow));
        currentRow = [];
      }
    }

    // Add any remaining items in the last row
    if (currentRow.isNotEmpty) {
      // Fill the remaining slots with empty containers to maintain 4-column layout
      while (currentRow.length < 4) {
        currentRow.add(
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(1),
              height: 40,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.transparent, width: 0.5),
              ),
            ),
          ),
        );
      }
      rows.add(Row(children: currentRow));
    }

    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: rows,
      ),
    );
  }

  Widget _buildCompactVerbColumn() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Verb categories with compact layout
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: _selectedVerb == 'Single' ||
                      _selectedVerb == 'Double' ||
                      _selectedVerb == 'Triple'
                  ? _buildHittingSubOptions()
                  : _selectedVerb == 'RBI Sacrifice Fly'
                      ? _buildSacrificeFlySubOptions()
                      : _selectedVerb == 'Home Run'
                          ? _buildHomeRunSubOptions()
                          : _selectedVerb == 'Tags'
                              ? _buildTagsSubOptions()
                              : _selectedVerb == 'Catches'
                                  ? _buildCatchesSubOptions()
                                  : _selectedVerb == 'Groundball'
                                      ? _buildGroundballSubOptions()
                                      : (_selectedVerb == 'At Bat' ||
                                              _selectedVerb == 'Pitching' ||
                                              _selectedVerb == 'Swings' ||
                                              _selectedVerb == 'Throws' ||
                                              _selectedVerb ==
                                                  'Fielding Position' ||
                                              _selectedVerb == 'Bunts' ||
                                              _selectedVerb == 'Walks' ||
                                              _selectedVerb == 'Hit by Pitch' ||
                                              _selectedVerb == 'Strikeout' ||
                                              _selectedVerb == 'Looks On' ||
                                              _selectedVerb ==
                                                  'Walks Off Field' ||
                                              _selectedVerb ==
                                                  'Runs Off Field' ||
                                              _selectedVerb ==
                                                  'Takes the Field' ||
                                              _selectedVerb ==
                                                  'Comes Off the Field' ||
                                              _selectedVerb ==
                                                  'Post Game Win' ||
                                              _selectedVerb == 'Post Game Loss')
                                          ? _buildInningOnlyInterface()
                                          : (_selectedVerb ==
                                                      'Batting Practice' ||
                                                  _selectedVerb ==
                                                      'Fielding Practice')
                                              ? _buildPracticeInterface()
                                              : (_selectedVerb ==
                                                          'Steals' ||
                                                      _selectedVerb ==
                                                          'Slides' ||
                                                      _selectedVerb == 'Runs' ||
                                                      _selectedVerb ==
                                                          'Rounds' ||
                                                      _selectedVerb ==
                                                          'Double Play' ||
                                                      _selectedVerb ==
                                                          'Triple Play')
                                                  ? _buildBaseSelectionInterface()
                                                  : (_selectedVerb ==
                                                              'Celebration' ||
                                                          _selectedVerb ==
                                                              'Celebrates' ||
                                                          _selectedVerb ==
                                                              'Celebrates With' ||
                                                          _selectedVerb ==
                                                              'Celebrates Against')
                                                      ? _buildCelebrationInterface()
                                                      : (_selectedVerb ==
                                                              'Dejection')
                                                          ? _buildDejectionInterface()
                                                                                                                    : (_selectedVerb ==
                                                              'National Anthem' ||
                                                              _selectedVerb ==
                                                              'Stretching' ||
                                                              _selectedVerb ==
                                                              'Warm Ups')
                                                          ? _buildNationalAnthemInterface()
                                                          : (_selectedVerb ==
                                                              'Pitching Change')
                                                          ? _buildPitchingChangeInterface()
                                                              : Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  children: [
                                                                    // Player chips row (moved from above caption building section)
                                                                    Container(
                                                                      width: double
                                                                          .infinity,
                                                                      height:
                                                                          32,
                                                                      padding: const EdgeInsets
                                                                          .symmetric(
                                                                          horizontal:
                                                                              12,
                                                                          vertical:
                                                                              6),
                                                                      decoration:
                                                                          BoxDecoration(
                                                                        color: Colors
                                                                            .grey
                                                                            .shade50,
                                                                        borderRadius:
                                                                            BorderRadius.circular(6),
                                                                        border: Border.all(
                                                                            color:
                                                                                Colors.grey.shade300),
                                                                      ),
                                                                      child:
                                                                          _buildPlayerChipsHeader(),
                                                                    ),
                                                                    const SizedBox(
                                                                        height:
                                                                            4),
                                                                    // Custom text field for between players
                                                                    Container(
                                                                      width: double
                                                                          .infinity,
                                                                      height:
                                                                          32,
                                                                      decoration:
                                                                          BoxDecoration(
                                                                        color: Colors
                                                                            .white,
                                                                        borderRadius:
                                                                            BorderRadius.circular(2),
                                                                        border: Border.all(
                                                                            color:
                                                                                Colors.grey.shade300),
                                                                      ),
                                                                      child:
                                                                          Column(
                                                                        children: [
                                                                          // Text field
                                                                          TextField(
                                                                            controller:
                                                                                customBetweenPlayersController,
                                                                            cursorWidth:
                                                                                1.5,
                                                                            cursorHeight:
                                                                                16,
                                                                            style:
                                                                                const TextStyle(fontSize: 12, height: 2.3),
                                                                            decoration:
                                                                                InputDecoration(
                                                                              hintText: _isPlayerSearchMode ? 'Magic Bar: Type player numbers (e.g., 75, 23) or magic input (e.g., "27 hr 1")...' : 'Magic Bar: Type custom action...',
                                                                              border: InputBorder.none,
                                                                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                                              isDense: true,
                                                                            ),
                                                                            onChanged:
                                                                                (value) {
                                                                              // Check for magic input format (e.g., "27 hr 1")
                                                                              if (_isMagicInput(value)) {
                                                                                _parseMagicInput(value);
                                                                                // Don't return - let the text stay in the field
                                                                              }

                                                                              setState(() {
                                                                                if (_isPlayerSearchMode && _isNumeric(value)) {
                                                                                  // print(
                                                                                  //     'DEBUG: Calling _filterPlayersByNumber');
                                                                                  _filterPlayersByNumber(value);
                                                                                } else if (_isPlayerSearchMode && value.isEmpty) {
                                                                                  // print(
                                                                                  //     'DEBUG: Clearing filtered players');
                                                                                  _filteredPlayers.clear();
                                                                                } else if (!_isPlayerSearchMode) {
                                                                                  // print(
                                                                                  //     'DEBUG: In custom verb mode');
                                                                                  _showCustomTextInningSelector = value.isNotEmpty;
                                                                                  _updateCaption();
                                                                                }
                                                                              });
                                                                            },
                                                                          ),
                                                                          // Player selection overlay
                                                                          if (_filteredPlayers.isNotEmpty ||
                                                                              _noPlayersFound)
                                                                            Material(
                                                                              elevation: 8,
                                                                              borderRadius: BorderRadius.circular(4),
                                                                              child: Container(
                                                                                decoration: BoxDecoration(
                                                                                  color: Colors.white,
                                                                                  borderRadius: BorderRadius.circular(4),
                                                                                  border: Border.all(color: Colors.grey.shade300),
                                                                                ),
                                                                                child: Column(
                                                                                  mainAxisSize: MainAxisSize.min,
                                                                                  children: [
                                                                                    if (_noPlayersFound)
                                                                                      Container(
                                                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                                                        child: Row(
                                                                                          children: [
                                                                                            Icon(Icons.info_outline, size: 16, color: Colors.orange.shade600),
                                                                                            const SizedBox(width: 8),
                                                                                            Text(
                                                                                              'No player with number ${_playerSearchText}',
                                                                                              style: TextStyle(
                                                                                                fontSize: 12,
                                                                                                color: Colors.orange.shade700,
                                                                                                fontWeight: FontWeight.w500,
                                                                                              ),
                                                                                            ),
                                                                                          ],
                                                                                        ),
                                                                                      )
                                                                                    else ...[
                                                                                      ..._filteredPlayers.map(
                                                                                        (player) => GestureDetector(
                                                                                          onTap: () => _selectPlayer(player),
                                                                                          child: Container(
                                                                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                                                            child: Row(
                                                                                              children: [
                                                                                                Text(
                                                                                                  '#${player.jerseyNumber}',
                                                                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                                                                                                ),
                                                                                                const SizedBox(width: 4),
                                                                                                Text(
                                                                                                  _getTeamAbbreviation(_isHomePlayer(player) ? selectedHomeTeam ?? '' : selectedAwayTeam ?? '') ?? '',
                                                                                                  style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                                                                                                ),
                                                                                                const SizedBox(width: 2),
                                                                                                Icon(
                                                                                                  _isHomePlayer(player) ? Icons.home : Icons.flight,
                                                                                                  size: 10,
                                                                                                  color: _isHomePlayer(player) ? Colors.blue.shade600 : Colors.red.shade600,
                                                                                                ),
                                                                                                const SizedBox(width: 4),
                                                                                                Expanded(
                                                                                                  child: Text(
                                                                                                    _removeJerseyNumberFromName(player.displayName ?? 'Unknown'),
                                                                                                    style: const TextStyle(fontSize: 10),
                                                                                                    overflow: TextOverflow.ellipsis,
                                                                                                  ),
                                                                                                ),
                                                                                              ],
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                      ),
                                                                                    ],
                                                                                    if (_selectedPlayerNumbers.isNotEmpty)
                                                                                      GestureDetector(
                                                                                        onTap: _finishPlayerSelection,
                                                                                        child: Container(
                                                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                                                          decoration: BoxDecoration(
                                                                                            color: Colors.blue.shade50,
                                                                                            border: Border(top: BorderSide(color: Colors.grey.shade200)),
                                                                                          ),
                                                                                          child: Row(
                                                                                            children: [
                                                                                              Icon(Icons.check, size: 16, color: Colors.blue.shade700),
                                                                                              const SizedBox(width: 8),
                                                                                              Text(
                                                                                                'Done selecting players (${_selectedPlayerNumbers.length})',
                                                                                                style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w500),
                                                                                              ),
                                                                                            ],
                                                                                          ),
                                                                                        ),
                                                                                      ),
                                                                                  ],
                                                                                ),
                                                                              ),
                                                                            ),
                                                                          // Inning selector
                                                                          if (_showCustomTextInningSelector)
                                                                            Container(
                                                                              height: 80,
                                                                              child: _buildCustomTextInningSelector(),
                                                                            ),
                                                                        ],
                                                                      ),
                                                                    ),

                                                                    const SizedBox(
                                                                        height:
                                                                            4), // Padding between Magic Bar and verb categories

                                                                    // Verb categories (hidden when custom text is being used, except for Pre Game verbs)
                                                                    if (!customBetweenPlayersController
                                                                        .text
                                                                        .isNotEmpty) ...[
                                                                      Container(
                                                                        height:
                                                                            500, // Increased height for verb area
                                                                        // Removed debug background for cleaner appearance
                                                                        child:
                                                                            SingleChildScrollView(
                                                                          child:
                                                                              Padding(
                                                                            padding:
                                                                                const EdgeInsets.all(4),
                                                                            child:
                                                                                LayoutBuilder(
                                                                              builder: (context, constraints) {
                                                                                // Calculate width for exactly 3 columns
                                                                                final columnWidth = (constraints.maxWidth - 8) / 3; // Subtract spacing between columns (4px * 2 gaps)

                                                                                return Container(
                                                                                  // 6 columns in one row
                                                                                  child: Row(
                                                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                                                    children: [
                                                                                      // Offense column
                                                                                      Expanded(
                                                                                        child: _buildVerbCategory('Offense', [
                                                                                          'Single',
                                                                                          'Double',
                                                                                          'Triple',
                                                                                          'Home Run',
                                                                                          'RBI Sacrifice Fly',
                                                                                          'At Bat',
                                                                                          'Swings',
                                                                                          'Bunts',
                                                                                          'Walks',
                                                                                          'Hit by Pitch'
                                                                                        ]),
                                                                                      ),
                                                                                      const SizedBox(width: 2),
                                                                                      // Defense column
                                                                                      Expanded(
                                                                                        child: _buildVerbCategory('Defense', [
                                                                                          'Pitching',
                                                                                          'Pitching Change',
                                                                                          'Catches',
                                                                                          'Throws',
                                                                                          'Tags',
                                                                                          'Groundball',
                                                                                          'Fielding Position',
                                                                                          'Double Play',
                                                                                          'Triple Play',
                                                                                          ''
                                                                                        ]),
                                                                                      ),
                                                                                      const SizedBox(width: 2),
                                                                                      // Running column
                                                                                      Expanded(
                                                                                        child: _buildVerbCategory('Running', [
                                                                                          'Steals',
                                                                                          'Slides',
                                                                                          'Runs',
                                                                                          'Rounds',
                                                                                          '',
                                                                                          '',
                                                                                          '',
                                                                                          '',
                                                                                          '',
                                                                                          ''
                                                                                        ]),
                                                                                      ),
                                                                                      const SizedBox(width: 2),
                                                                                      // Reactions column
                                                                                      Expanded(
                                                                                        child: _buildVerbCategory('Reactions', [
                                                                                          'Celebrates',
                                                                                          'Dejection',
                                                                                          'Post Game Win',
                                                                                          'Post Game Loss',
                                                                                          '',
                                                                                          '',
                                                                                          '',
                                                                                          '',
                                                                                          '',
                                                                                          ''
                                                                                        ]),
                                                                                      ),
                                                                                      const SizedBox(width: 2),
                                                                                      // Non Game-Action column
                                                                                      Expanded(
                                                                                        child: _buildVerbCategory('Non Game-Action', [
                                                                                          'Looks On',
                                                                                          'Batting Practice',
                                                                                          'Fielding Practice',
                                                                                          'Takes the Field',
                                                                                          'Comes Off the Field',
                                                                                          'National Anthem',
                                                                                          'Stretching',
                                                                                          'Warm Ups',
                                                                                          '',
                                                                                          ''
                                                                                        ]),
                                                                                      ),
                                                                                      const SizedBox(width: 2),
                                                                                    ],
                                                                                  ),
                                                                                ); // Close Container for Wrap
                                                                              },
                                                                            ),
                                                                          ),
                                                                        ), // Close SingleChildScrollView
                                                                      ),
                                                                    ],

                                                                    const SizedBox(
                                                                        height:
                                                                            4),
                                                                    // Third row: Dynamic content
                                                                    Expanded(
                                                                      // Fills remaining space after verb area takes what it needs
                                                                      child:
                                                                          Row(
                                                                        children: [
                                                                          Expanded(
                                                                            child:
                                                                                Container(), // Empty space
                                                                          ),
                                                                          const SizedBox(
                                                                              width: 1),
                                                                          Expanded(
                                                                            child:
                                                                                Container(), // Empty space
                                                                          ),
                                                                          const SizedBox(
                                                                              width: 1),
                                                                          Expanded(
                                                                            child:
                                                                                Column(
                                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                                              children: [
                                                                                // Home run types (when home run is selected)
                                                                                if (_selectedVerb == 'Home Run')
                                                                                  _buildVerbCategory('Home Run Types', [
                                                                                    'Solo',
                                                                                    'Two-Run',
                                                                                    'Three-Run',
                                                                                    'Grand Slam'
                                                                                  ]),

                                                                                // Inning only (when simple verbs are selected)
                                                                                if (_selectedVerb == 'At Bat' || _selectedVerb == 'Pitching' || _selectedVerb == 'Swings' || _selectedVerb == 'Catches' || _selectedVerb == 'Throws' || _selectedVerb == 'Groundball' || _selectedVerb == 'Fielding Position') ...[
                                                                                  const SizedBox(height: 1),
                                                                                  Container(
                                                                                    decoration: BoxDecoration(
                                                                                      border: Border.all(color: Colors.grey.shade400),
                                                                                      borderRadius: BorderRadius.circular(2),
                                                                                    ),
                                                                                    child: Column(
                                                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                                                      children: [
                                                                                        Container(
                                                                                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                                                          child: const Text(
                                                                                            'INN',
                                                                                            style: TextStyle(
                                                                                              fontSize: 8,
                                                                                              fontWeight: FontWeight.w500,
                                                                                              color: Colors.grey,
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                        GestureDetector(
                                                                                          onTap: _showCompactInningSelector,
                                                                                          child: Container(
                                                                                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                                                                                            child: Text(
                                                                                              _selectedRbiInning != null ? '${_getOrdinalSuffix(_selectedRbiInning!)}' : '',
                                                                                              style: const TextStyle(fontSize: 8),
                                                                                              textAlign: TextAlign.center,
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                      ],
                                                                                    ),
                                                                                  ),
                                                                                ],

                                                                                // RBI & Inning (when any hitting verb is selected)
                                                                                if (_selectedVerb == 'Single' || _selectedVerb == 'Double' || _selectedVerb == 'Triple' || _selectedVerb == 'Home Run' || _selectedVerb == 'Grand Slam' || _selectedVerb == 'Walks') ...[
                                                                                  const SizedBox(height: 1),
                                                                                  Row(
                                                                                    children: [
                                                                                      Expanded(
                                                                                        child: Container(
                                                                                          decoration: BoxDecoration(
                                                                                            border: Border.all(color: Colors.grey.shade400),
                                                                                            borderRadius: BorderRadius.circular(2),
                                                                                          ),
                                                                                          child: Column(
                                                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                                                            children: [
                                                                                              Container(
                                                                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                                                                child: const Text(
                                                                                                  'RBI',
                                                                                                  style: TextStyle(
                                                                                                    fontSize: 8,
                                                                                                    fontWeight: FontWeight.w500,
                                                                                                    color: Colors.grey,
                                                                                                  ),
                                                                                                ),
                                                                                              ),
                                                                                              DropdownButtonFormField<int>(
                                                                                                value: _rbiCount,
                                                                                                decoration: const InputDecoration(
                                                                                                  isDense: true,
                                                                                                  contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                                                                                                  border: InputBorder.none,
                                                                                                  labelText: null,
                                                                                                ),
                                                                                                items: [0, 1, 2, 3, 4].map((rbi) {
                                                                                                  return DropdownMenuItem(
                                                                                                    value: rbi,
                                                                                                    child: Text(rbi == 0 ? '0' : '$rbi', style: const TextStyle(fontSize: 8)),
                                                                                                  );
                                                                                                }).toList(),
                                                                                                onChanged: (value) {
                                                                                                  setState(() {
                                                                                                    _rbiCount = value;
                                                                                                  });
                                                                                                  _updateCaption();
                                                                                                },
                                                                                              ),
                                                                                            ],
                                                                                          ),
                                                                                        ),
                                                                                      ),
                                                                                      const SizedBox(width: 1),
                                                                                      Expanded(
                                                                                        child: Container(
                                                                                          decoration: BoxDecoration(
                                                                                            border: Border.all(color: Colors.grey.shade400),
                                                                                            borderRadius: BorderRadius.circular(2),
                                                                                          ),
                                                                                          child: Column(
                                                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                                                            children: [
                                                                                              Container(
                                                                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                                                                child: const Text(
                                                                                                  'INN',
                                                                                                  style: TextStyle(
                                                                                                    fontSize: 8,
                                                                                                    fontWeight: FontWeight.w500,
                                                                                                    color: Colors.grey,
                                                                                                  ),
                                                                                                ),
                                                                                              ),
                                                                                              GestureDetector(
                                                                                                onTap: _showCompactInningSelector,
                                                                                                child: Container(
                                                                                                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                                                                                                  child: Text(
                                                                                                    _selectedRbiInning != null ? '${_getOrdinalSuffix(_selectedRbiInning!)}' : '',
                                                                                                    style: const TextStyle(fontSize: 8),
                                                                                                    textAlign: TextAlign.center,
                                                                                                  ),
                                                                                                ),
                                                                                              ),
                                                                                            ],
                                                                                          ),
                                                                                        ),
                                                                                      ),
                                                                                    ],
                                                                                  ),
                                                                                ],
                                                                              ],
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerbCategory(String title, List<String> verbs) {
    return Container(
      // Removed debug background for cleaner appearance
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title with background span
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Verb options
          ...verbs.map((verb) => _buildVerbOption(verb)).toList(),
        ],
      ),
    );
  }

  Widget _buildVerbOption(String verb) {
    final isSelected = _selectedVerb == verb;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedVerb = null;
            _selectedActionVerb = null; // Clear action verb when deselecting
            _selectedHomeRunType = null;
            _selectedTagsAction = null; // Clear tags action when deselecting
            _selectedBase = null; // Clear selected base when deselecting
            _rbiCount = null;
            _selectedRbiInning = null;
          } else {
            _selectedVerb = verb;
            _selectedActionVerb = verb; // Store for caption generation
            _selectedHomeRunType = null;
            _rbiCount = null;
            _selectedRbiInning = null;
          }
        });
        _updateCaption();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        margin: const EdgeInsets.only(bottom: 1),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade300 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isSelected ? Colors.grey.shade400 : Colors.grey.shade300,
            width: 0.5,
          ),
        ),
        child: Text(
          verb,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.grey.shade800 : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildCompactVerbChip(String verb, String label) {
    final isSelected = _selectedVerb == verb;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedVerb = null;
            _selectedActionVerb = null; // Clear action verb when deselecting
            _selectedHomeRunType = null;
            _selectedTagsAction = null; // Clear tags action when deselecting
            _selectedBase = null; // Clear selected base when deselecting
            _rbiCount = null;
            _selectedRbiInning = null;
            _isBatterRunning = false;
          } else {
            _selectedVerb = verb;
            _selectedActionVerb = verb; // Store for caption generation
            _selectedHomeRunType = null;
            _rbiCount = null;
            _selectedRbiInning = null;
            _isBatterRunning = false;
          }
        });
        _updateCaption();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade300 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.grey.shade400 : Colors.grey.shade300,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.grey.shade800 : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildCompactHomeRunTypeChip(String hrType, String label) {
    final isSelected = _selectedHomeRunType == hrType;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedHomeRunType = null;
          } else {
            _selectedHomeRunType = hrType;
            switch (hrType) {
              case 'Solo':
                _rbiCount = 1;
                break;
              case 'Two-Run':
                _rbiCount = 2;
                break;
              case 'Three-Run':
                _rbiCount = 3;
                break;
              case 'Grand Slam':
                _rbiCount = 4;
                break;
            }
          }
        });
        _updateCaption();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade300 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.grey.shade400 : Colors.grey.shade300,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.grey.shade800 : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  void _showCompactInningSelector() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Inning', style: TextStyle(fontSize: 14)),
        content: SizedBox(
          width: 200,
          height: 300,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: 13,
            itemBuilder: (context, index) {
              final inning = index + 1;
              final isSelected = _selectedRbiInning == inning;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedRbiInning = inning;
                    _isPriorToGame = false;
                  });
                  _updateCaption();
                  Navigator.pop(context);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.grey.shade300
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected
                          ? Colors.grey.shade400
                          : Colors.grey.shade400,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      inning == 13
                          ? 'Prior to Game'
                          : _getOrdinalSuffix(inning),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? Colors.grey.shade800
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactCaptionPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note, size: 12, color: Colors.black87),
              const SizedBox(width: 4),
              const Text(
                'Caption:',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              captionController.text.isEmpty
                  ? 'No caption generated yet...'
                  : captionController.text,
              style: TextStyle(
                fontSize: 10,
                color: captionController.text.isEmpty
                    ? Colors.grey.shade600
                    : Colors.black87,
                fontStyle: captionController.text.isEmpty
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainVerbSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Main Action:',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildVerbChip('Offense', 'Offense')),
            const SizedBox(width: 2),
            Expanded(child: _buildVerbChip('Defense', 'Defense')),
            const SizedBox(width: 2),
            Expanded(child: _buildVerbChip('Running', 'Running')),
            const SizedBox(width: 2),
            Expanded(child: _buildVerbChip('Reactions', 'Reactions')),
            const SizedBox(width: 2),
            Expanded(child: _buildVerbChip('Magic', 'Magic')),
          ],
        ),
      ],
    );
  }

  Widget _buildVerbChip(String verb, String label) {
    final isSelected = _selectedVerb == verb;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedVerb = null;
            _selectedActionVerb = null; // Clear action verb when deselecting
            _selectedHomeRunType = null;
            _selectedTagsAction = null; // Clear tags action when deselecting
            _selectedBase = null; // Clear selected base when deselecting
            _rbiCount = null;
            _selectedRbiInning = null;
            _isBatterRunning = false;
          } else {
            _selectedVerb = verb;
            _selectedActionVerb = verb; // Store for caption generation
            // Reset other states when selecting a new verb
            _selectedHomeRunType = null;
            _rbiCount = null;
            _selectedRbiInning = null;
            _isBatterRunning = false;
          }
          _updateCaption();
        });
      },
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade100 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.blue.shade300 : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.blue.shade700 : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildHomeRunOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Home Run Type:',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            _buildHomeRunTypeChip('Solo', 'Solo HR'),
            _buildHomeRunTypeChip('Two-Run', '2-Run HR'),
            _buildHomeRunTypeChip('Three-Run', '3-Run HR'),
            _buildHomeRunTypeChip('Grand Slam', 'Grand Slam'),
          ],
        ),
      ],
    );
  }

  Widget _buildHomeRunTypeChip(String hrType, String label) {
    final isSelected = _selectedHomeRunType == hrType;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedHomeRunType = null;
          } else {
            _selectedHomeRunType = hrType;
            // Set RBI count based on HR type
            switch (hrType) {
              case 'Solo':
                _rbiCount = 1;
                break;
              case 'Two-Run':
                _rbiCount = 2;
                break;
              case 'Three-Run':
                _rbiCount = 3;
                break;
              case 'Grand Slam':
                _rbiCount = 4;
                break;
            }
          }
          _updateCaption();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange.shade100 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.orange.shade300 : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.orange.shade700 : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildRbiAndInningOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RBI & Inning:',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            // RBI Count
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('RBI:', style: TextStyle(fontSize: 10)),
                  const SizedBox(height: 2),
                  DropdownButtonFormField<int>(
                    value: _rbiCount,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    items: [0, 1, 2, 3, 4].map((rbi) {
                      return DropdownMenuItem(
                        value: rbi,
                        child: Text(rbi == 0 ? 'No RBI' : '$rbi RBI',
                            style: const TextStyle(fontSize: 10)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _rbiCount = value;
                      });
                      _updateCaption();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Inning
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Inning:', style: TextStyle(fontSize: 10)),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: _showInningSelector,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedRbiInning != null
                                  ? '${_getOrdinalSuffix(_selectedRbiInning!)}'
                                  : 'Select',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down, size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showInningSelector() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Inning'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: 12, // 1-9 + 10, 11, 12
            itemBuilder: (context, index) {
              final inning = index < 9 ? index + 1 : index + 1;
              final isSelected = _selectedRbiInning == inning;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedRbiInning = inning;
                  });
                  _updateCaption();
                  Navigator.pop(context);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.blue.shade100
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? Colors.blue.shade300
                          : Colors.grey.shade400,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _getOrdinalSuffix(inning),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? Colors.blue.shade700
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  String _getOrdinalSuffix(int number) {
    switch (number) {
      case 1:
        return 'first';
      case 2:
        return 'second';
      case 3:
        return 'third';
      case 4:
        return 'fourth';
      case 5:
        return 'fifth';
      case 6:
        return 'sixth';
      case 7:
        return 'seventh';
      case 8:
        return 'eighth';
      case 9:
        return 'ninth';
      case 10:
        return 'tenth';
      case 11:
        return 'eleventh';
      case 12:
        return 'twelfth';
      case 13:
        return 'thirteenth';
      case 14:
        return 'fourteenth';
      case 15:
        return 'fifteenth';
      case 16:
        return 'sixteenth';
      case 17:
        return 'seventeenth';
      case 18:
        return 'eighteenth';
      case 19:
        return 'nineteenth';
      case 20:
        return 'twentieth';
      case 21:
        return 'twenty-first';
      case 22:
        return 'twenty-second';
      case 23:
        return 'twenty-third';
      case 24:
        return 'twenty-fourth';
      case 25:
        return 'twenty-fifth';
      case 26:
        return 'twenty-sixth';
      case 27:
        return 'twenty-seventh';
      case 28:
        return 'twenty-eighth';
      case 29:
        return 'twenty-ninth';
      case 30:
        return 'thirtieth';
      default:
        return '${number}th';
    }
  }

  // Magic input parsing methods
  bool _isMagicInput(String input) {
    if (input.isEmpty) return false;

    final parts = input.trim().toLowerCase().split(' ');
    if (parts.length < 2) return false;

    // Check if first part is a number
    if (!_isNumeric(parts[0])) return false;

    // Check if there's an action word
    final actionWords = [
      'hr',
      'homerun',
      'homer',
      'single',
      '1b',
      'double',
      '2b',
      'triple',
      '3b',
      'walks',
      'walk',
      'bb',
      'strikeout',
      'k',
      'steals',
      'steal',
      'sb',
      'catches',
      'catch',
      'throws',
      'throw',
      'tags',
      'tag',
      'pitches',
      'pitch',
      'pitching',
      'swings',
      'swing',
      'bunts',
      'bunt',
      'hbp',
      'hitbypitch',
      'celebrates',
      'celebrate',
      'dejection',
      'dejected',
      'looks',
      'look',
      'runs',
      'run',
      'slides',
      'slide',
      'rounds',
      'round',
      'groundball',
      'ground',
      'doubleplay',
      'dp',
      'tripleplay',
      'tp',
      'atbat',
      'at-bat',
      'bat',
      'fielding',
      'field',
      'warmup',
      'warm',
      'stretching',
      'stretch',
      'battingpractice',
      'bp',
      'fieldingpractice',
      'fp',
      'takesthefield',
      'takesfield',
      'comesofffield',
      'offfield',
      'nationalanthem',
      'anthem',
      'pitchingchange',
      'pitchchange',
      'postgamewin',
      'win',
      'postgameloss',
      'loss',
      'walksofffield',
      'walksoff',
      'runsofffield',
      'runsoff'
    ];

    for (int i = 1; i < parts.length; i++) {
      if (actionWords.contains(parts[i])) {
        return true;
      }
    }

    return false;
  }

  void _parseMagicInput(String input) {
    print('DEBUG: _parseMagicInput called with: "$input"');
    if (input.isEmpty) return;

    // Clear existing selections
    setState(() {
      selectedHomePlayers.clear();
      selectedAwayPlayers.clear();
      _selectedVerb = null;
      _selectedActionVerb = null;
      _rbiCount = null;
      _selectedRbiInning = null;
      _firstTeamSelected = null;
      _firstPlayerSelected = null;

      // Clear player search state to prevent conflicts
      _filteredPlayers.clear();
      _noPlayersFound = false;
      _isPlayerSearchMode = false;
    });

    // Show a brief success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Processing magic input: "$input"'),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.blue,
      ),
    );

    // Parse the magic input
    final parts = input.trim().toLowerCase().split(' ');
    print('DEBUG: Parts: $parts');
    if (parts.length < 2) {
      print('DEBUG: Not enough parts, returning');
      return;
    }

    // Extract player number
    final playerNumber = parts[0];
    print('DEBUG: Player number: $playerNumber');
    if (!_isNumeric(playerNumber)) {
      print('DEBUG: Player number is not numeric, returning');
      return;
    }

    // Find all players with this number
    List<Player> matchingPlayers = [];

    // Search in both rosters
    for (final player in _homeRoster) {
      if (player.jerseyNumber == playerNumber) {
        matchingPlayers.add(player);
      }
    }
    for (final player in _awayRoster) {
      if (player.jerseyNumber == playerNumber) {
        matchingPlayers.add(player);
      }
    }

    print('DEBUG: Found ${matchingPlayers.length} matching players');
    if (matchingPlayers.isEmpty) {
      print('DEBUG: No matching players found, returning');
      return;
    }

    // If multiple players found, ask for home/visitor choice
    if (matchingPlayers.length > 1) {
      print('DEBUG: Multiple players found, asking for home/visitor choice');
      setState(() {
        // Clear regular player search state to prevent conflicts
        _filteredPlayers.clear();
        _noPlayersFound = false;
        _isPlayerSearchMode = false;

        _magicInputMatchingPlayers = matchingPlayers;
        _magicInputActionText = parts.sublist(1).join(' ');
        _waitingForHomeVisitorChoice = true;

        // Store the original magic input text before showing dialog
        final originalText = customBetweenPlayersController.text;
        print('DEBUG: Storing original text: "$originalText"');

        // Show popup dialog for home/visitor choice
        print('DEBUG: Set _waitingForHomeVisitorChoice = true');
        print('DEBUG: Will show Home/Visitor choice dialog');
        _showHomeVisitorChoiceDialog(originalText);
      });
      return;
    }

    // Single player found, proceed normally
    final foundPlayer = matchingPlayers.first;
    final isHomePlayer = _homeRoster.contains(foundPlayer);

    // Select the player
    setState(() {
      if (isHomePlayer) {
        selectedHomePlayers.add(foundPlayer?.displayName ?? 'Unknown Player');
        _firstTeamSelected = true;
        _firstPlayerSelected = foundPlayer?.displayName ?? 'Unknown Player';
      } else {
        selectedAwayPlayers.add(foundPlayer?.displayName ?? 'Unknown Player');
        _firstTeamSelected = false;
        _firstPlayerSelected = foundPlayer?.displayName ?? 'Unknown Player';
      }
    });

    // Parse action and inning
    String action = '';
    int? inning;

    for (int i = 1; i < parts.length; i++) {
      final part = parts[i];

      // Check for inning number
      if (_isNumeric(part)) {
        inning = int.parse(part);
        continue;
      }

      // Parse action
      switch (part) {
        case 'hr':
        case 'homerun':
        case 'homer':
          action = 'Home Run';
          break;
        case 'single':
        case '1b':
          action = 'Single';
          break;
        case 'double':
        case '2b':
          action = 'Double';
          break;
        case 'triple':
        case '3b':
          action = 'Triple';
          break;
        case 'walks':
        case 'walk':
        case 'bb':
          action = 'Walks';
          break;
        case 'strikeout':
        case 'k':
          action = 'Strikeout';
          break;
        case 'steals':
        case 'steal':
        case 'sb':
          action = 'Steals';
          break;
        case 'catches':
        case 'catch':
          action = 'Catches';
          break;
        case 'throws':
        case 'throw':
          action = 'Throws';
          break;
        case 'tags':
        case 'tag':
          action = 'Tags';
          break;
        case 'pitches':
        case 'pitch':
        case 'pitching':
          action = 'Pitching';
          break;
        case 'swings':
        case 'swing':
          action = 'Swings';
          break;
        case 'bunts':
        case 'bunt':
          action = 'Bunts';
          break;
        case 'hbp':
        case 'hitbypitch':
          action = 'Hit by Pitch';
          break;
        case 'celebrates':
        case 'celebrate':
          action = 'Celebrates';
          break;
        case 'dejection':
        case 'dejected':
          action = 'Dejection';
          break;
        case 'looks':
        case 'look':
          action = 'Looks On';
          break;
        case 'runs':
        case 'run':
          action = 'Runs';
          break;
        case 'slides':
        case 'slide':
          action = 'Slides';
          break;
        case 'rounds':
        case 'round':
          action = 'Rounds';
          break;
        case 'groundball':
        case 'ground':
          action = 'Groundball';
          break;
        case 'doubleplay':
        case 'dp':
          action = 'Double Play';
          break;
        case 'tripleplay':
        case 'tp':
          action = 'Triple Play';
          break;
        case 'atbat':
        case 'at-bat':
        case 'bat':
          action = 'At Bat';
          break;
        case 'fielding':
        case 'field':
          action = 'Fielding Position';
          break;
        case 'warmup':
        case 'warm':
          action = 'Warm Ups';
          break;
        case 'stretching':
        case 'stretch':
          action = 'Stretching';
          break;
        case 'battingpractice':
        case 'bp':
          action = 'Batting Practice';
          break;
        case 'fieldingpractice':
        case 'fp':
          action = 'Fielding Practice';
          break;
        case 'takesthefield':
        case 'takesfield':
          action = 'Takes the Field';
          break;
        case 'comesofffield':
        case 'offfield':
          action = 'Comes Off the Field';
          break;
        case 'nationalanthem':
        case 'anthem':
          action = 'National Anthem';
          break;
        case 'pitchingchange':
        case 'pitchchange':
          action = 'Pitching Change';
          break;
        case 'postgamewin':
        case 'win':
          action = 'Post Game Win';
          break;
        case 'postgameloss':
        case 'loss':
          action = 'Post Game Loss';
          break;
        case 'walksoffield':
        case 'walksoff':
          action = 'Walks Off Field';
          break;
        case 'runsoffield':
        case 'runsoff':
          action = 'Runs Off Field';
          break;
      }
    }

    // Set the action and inning
    if (action.isNotEmpty) {
      setState(() {
        _selectedVerb = action;
        _selectedActionVerb = action;
        _selectedRbiInning = inning;

        // Only set RBI count if inning is provided (indicating RBI was specified)
        // For magic input like "27 hr", don't set RBI count
        // For magic input like "27 hr 1", set RBI count to 1
        if (inning != null &&
            (action == 'Home Run' ||
                action == 'Single' ||
                action == 'Double' ||
                action == 'Triple')) {
          _rbiCount = inning; // Use the inning number as RBI count
        } else {
          _rbiCount = null; // Don't set RBI count for solo actions
        }
      });
    }

    // Update caption
    _updateCaption();

    // Keep the magic input visible in the field
    // (The magic input text is filtered out in _updateCaption)
  }

  void _showMagicInputPlayerSelectionDialog(
      List<Player> players, String actionText) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select Player'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Multiple players found with this number:'),
            const SizedBox(height: 16),
            ...players.map((player) {
              final isHome = _homeRoster.contains(player);
              final teamName = isHome ? selectedHomeTeam : selectedAwayTeam;
              final teamAbbr = _getTeamAbbreviation(teamName ?? '') ?? '';

              return ListTile(
                leading: Icon(
                  isHome ? Icons.home : Icons.flight,
                  color: isHome ? Colors.blue.shade600 : Colors.red.shade600,
                ),
                title: Text('${player.fullName} #${player.jerseyNumber}'),
                subtitle: Text('$teamAbbr (${isHome ? 'Home' : 'Away'})'),
                onTap: () {
                  Navigator.of(context).pop();
                  _processMagicInputWithPlayer(player, actionText);
                },
              );
            }).toList(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showHomeVisitorChoiceDialog(String originalText) {
    // Find home and visitor players
    Player? homePlayer = _magicInputMatchingPlayers.firstWhere(
      (player) => _homeRoster.contains(player),
      orElse: () => _magicInputMatchingPlayers.first,
    );
    Player? visitorPlayer = _magicInputMatchingPlayers.firstWhere(
      (player) => _awayRoster.contains(player),
      orElse: () => _magicInputMatchingPlayers.first,
    );

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => RawKeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        autofocus: true,
        onKey: (RawKeyEvent event) {
          if (event is RawKeyDownEvent) {
            final key = event.logicalKey;
            print('DEBUG: Key pressed in dialog: ${key.keyLabel}');

            if (key.keyLabel.toLowerCase() == 'h') {
              print('DEBUG: H key detected, closing dialog and selecting home');
              Navigator.of(context).pop();
              _processHomeVisitorChoiceAndRestore('h', originalText);
              return; // Prevent the key from reaching other listeners
            } else if (key.keyLabel.toLowerCase() == 'v') {
              print(
                  'DEBUG: V key detected, closing dialog and selecting visitor');
              Navigator.of(context).pop();
              _processHomeVisitorChoiceAndRestore('v', originalText);
              return; // Prevent the key from reaching other listeners
            }
          }
        },
        child: AlertDialog(
          title: const Text('Select Player'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Multiple players found with this number.'),
              const SizedBox(height: 16),
              // Home player option
              Container(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _processHomeVisitorChoiceAndRestore('h', originalText);
                  },
                  icon: const Icon(Icons.home, size: 20),
                  label: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${homePlayer.fullName} #${homePlayer.jerseyNumber}'),
                      Text(
                        'Home Team',
                        style: TextStyle(
                            fontSize: 12, color: Colors.blue.shade100),
                      ),
                    ],
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Visitor player option
              Container(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _processHomeVisitorChoiceAndRestore('v', originalText);
                  },
                  icon: const Icon(Icons.flight, size: 20),
                  label: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${visitorPlayer.fullName} #${visitorPlayer.jerseyNumber}'),
                      Text(
                        'Visitor Team',
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange.shade100),
                      ),
                    ],
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                    alignment: Alignment.centerLeft,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: const [
                    Text(
                      'Keyboard shortcuts:',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Press H for Home, V for Visitor',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Reset the waiting state
                setState(() {
                  _waitingForHomeVisitorChoice = false;
                  _magicInputMatchingPlayers.clear();
                });
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  void _processHomeVisitorChoice(String choice) {
    print('DEBUG: Processing home/visitor choice: $choice');
    print(
        'DEBUG: Available players: ${_magicInputMatchingPlayers.map((p) => '${p.fullName} (${_homeRoster.contains(p) ? 'Home' : 'Away'})').join(', ')}');

    // Find the appropriate player based on choice
    Player? selectedPlayer;
    if (choice == 'h') {
      // Find home player
      selectedPlayer = _magicInputMatchingPlayers.firstWhere(
        (player) => _homeRoster.contains(player),
        orElse: () => _magicInputMatchingPlayers.first,
      );
      print('DEBUG: Selected home player: ${selectedPlayer?.fullName}');
    } else if (choice == 'v') {
      // Find away player
      selectedPlayer = _magicInputMatchingPlayers.firstWhere(
        (player) => _awayRoster.contains(player),
        orElse: () => _magicInputMatchingPlayers.first,
      );
      print('DEBUG: Selected away player: ${selectedPlayer?.fullName}');
    }

    if (selectedPlayer != null) {
      print('DEBUG: Clearing waiting state and processing magic input');

      // Store the original magic input text to restore it
      final originalMagicInput =
          '${selectedPlayer.jerseyNumber} ${_magicInputActionText}';
      print('DEBUG: Original magic input was: "$originalMagicInput"');

      // Clear the waiting state
      setState(() {
        _waitingForHomeVisitorChoice = false;
        _magicInputMatchingPlayers.clear();
        // Restore the original magic input text
        customBetweenPlayersController.text = originalMagicInput;
      });

      // Process the magic input with the selected player
      _processMagicInputWithPlayer(selectedPlayer, _magicInputActionText);
    } else {
      print('DEBUG: No player found for choice: $choice');
    }
  }

  void _processHomeVisitorChoiceAndRestore(String choice, String originalText) {
    print(
        'DEBUG: Processing home/visitor choice: $choice with original text: "$originalText"');
    print(
        'DEBUG: Available players: ${_magicInputMatchingPlayers.map((p) => '${p.fullName} (${_homeRoster.contains(p) ? 'Home' : 'Away'})').join(', ')}');

    // Find the appropriate player based on choice
    Player? selectedPlayer;
    if (choice == 'h') {
      // Find home player
      selectedPlayer = _magicInputMatchingPlayers.firstWhere(
        (player) => _homeRoster.contains(player),
        orElse: () => _magicInputMatchingPlayers.first,
      );
      print('DEBUG: Selected home player: ${selectedPlayer?.fullName}');
    } else if (choice == 'v') {
      // Find away player
      selectedPlayer = _magicInputMatchingPlayers.firstWhere(
        (player) => _awayRoster.contains(player),
        orElse: () => _magicInputMatchingPlayers.first,
      );
      print('DEBUG: Selected away player: ${selectedPlayer?.fullName}');
    }

    if (selectedPlayer != null) {
      print('DEBUG: Clearing waiting state and restoring original text');

      // Clear the waiting state and restore original text
      setState(() {
        _waitingForHomeVisitorChoice = false;
        _magicInputMatchingPlayers.clear();
        // Restore the original magic input text and keep it editable
        customBetweenPlayersController.text = originalText;
      });

      // Process the magic input with the selected player but don't clear the magic bar
      _processMagicInputWithPlayerKeepBar(
          selectedPlayer, _magicInputActionText);
    } else {
      print('DEBUG: No player found for choice: $choice');
    }
  }

  void _selectMagicInputPlayer(Player selectedPlayer) {
    // Clear the magic input options
    setState(() {
      _showMagicInputPlayerOptions = false;
      _magicInputMatchingPlayers.clear();
    });

    // Process the magic input with the selected player
    _processMagicInputWithPlayer(selectedPlayer, _magicInputActionText);
  }

  void _processMagicInputWithPlayer(Player selectedPlayer, String actionText) {
    // Clear existing selections
    setState(() {
      selectedHomePlayers.clear();
      selectedAwayPlayers.clear();
      _selectedVerb = null;
      _selectedActionVerb = null;
      _rbiCount = null;
      _selectedRbiInning = null;
      _firstTeamSelected = null;
      _firstPlayerSelected = null;

      // Clear player search state to prevent conflicts
      _filteredPlayers.clear();
      _noPlayersFound = false;
      _isPlayerSearchMode = false;
    });

    // Select the chosen player
    final isHomePlayer = _homeRoster.contains(selectedPlayer);
    setState(() {
      if (isHomePlayer) {
        selectedHomePlayers.add(selectedPlayer.displayName ?? 'Unknown Player');
        _firstTeamSelected = true;
        _firstPlayerSelected = selectedPlayer.displayName ?? 'Unknown Player';
      } else {
        selectedAwayPlayers.add(selectedPlayer.displayName ?? 'Unknown Player');
        _firstTeamSelected = false;
        _firstPlayerSelected = selectedPlayer.displayName ?? 'Unknown Player';
      }
    });

    // Parse the action text
    final parts = actionText.trim().toLowerCase().split(' ');
    String action = '';
    int? inning;

    for (final part in parts) {
      // Check for inning number
      if (_isNumeric(part)) {
        inning = int.parse(part);
        continue;
      }

      // Parse action (same switch statement as in _parseMagicInput)
      switch (part) {
        case 'hr':
        case 'homerun':
        case 'homer':
          action = 'Home Run';
          break;
        case 'single':
        case '1b':
          action = 'Single';
          break;
        case 'double':
        case '2b':
          action = 'Double';
          break;
        case 'triple':
        case '3b':
          action = 'Triple';
          break;
        case 'walks':
        case 'walk':
        case 'bb':
          action = 'Walks';
          break;
        case 'strikeout':
        case 'k':
          action = 'Strikeout';
          break;
        case 'steals':
        case 'steal':
        case 'sb':
          action = 'Steals';
          break;
        case 'catches':
        case 'catch':
          action = 'Catches';
          break;
        case 'throws':
        case 'throw':
          action = 'Throws';
          break;
        case 'tags':
        case 'tag':
          action = 'Tags';
          break;
        case 'pitches':
        case 'pitch':
        case 'pitching':
          action = 'Pitching';
          break;
        case 'swings':
        case 'swing':
          action = 'Swings';
          break;
        case 'bunts':
        case 'bunt':
          action = 'Bunts';
          break;
        case 'hbp':
        case 'hitbypitch':
          action = 'Hit by Pitch';
          break;
        case 'celebrates':
        case 'celebrate':
          action = 'Celebrates';
          break;
        case 'dejection':
        case 'dejected':
          action = 'Dejection';
          break;
        case 'looks':
        case 'look':
          action = 'Looks On';
          break;
        case 'runs':
        case 'run':
          action = 'Runs';
          break;
        case 'slides':
        case 'slide':
          action = 'Slides';
          break;
        case 'rounds':
        case 'round':
          action = 'Rounds';
          break;
        case 'groundball':
        case 'ground':
          action = 'Groundball';
          break;
        case 'doubleplay':
        case 'dp':
          action = 'Double Play';
          break;
        case 'tripleplay':
        case 'tp':
          action = 'Triple Play';
          break;
        case 'atbat':
        case 'at-bat':
        case 'bat':
          action = 'At Bat';
          break;
        case 'fielding':
        case 'field':
          action = 'Fielding Position';
          break;
        case 'warmup':
        case 'warm':
          action = 'Warm Ups';
          break;
        case 'stretching':
        case 'stretch':
          action = 'Stretching';
          break;
        case 'battingpractice':
        case 'bp':
          action = 'Batting Practice';
          break;
        case 'fieldingpractice':
        case 'fp':
          action = 'Fielding Practice';
          break;
        case 'takesthefield':
        case 'takesfield':
          action = 'Takes the Field';
          break;
        case 'comesofffield':
        case 'offfield':
          action = 'Comes Off the Field';
          break;
        case 'nationalanthem':
        case 'anthem':
          action = 'National Anthem';
          break;
        case 'pitchingchange':
        case 'pitchchange':
          action = 'Pitching Change';
          break;
        case 'postgamewin':
        case 'win':
          action = 'Post Game Win';
          break;
        case 'postgameloss':
        case 'loss':
          action = 'Post Game Loss';
          break;
        case 'walksoffield':
        case 'walksoff':
          action = 'Walks Off Field';
          break;
        case 'runsoffield':
        case 'runsoff':
          action = 'Runs Off Field';
          break;
      }
    }

    // Set the action and inning
    if (action.isNotEmpty) {
      setState(() {
        _selectedVerb = action;
        _selectedActionVerb = action;
        _selectedRbiInning = inning;

        // Only set RBI count if inning is provided (indicating RBI was specified)
        // For magic input like "27 hr", don't set RBI count
        // For magic input like "27 hr 1", set RBI count to 1
        if (inning != null &&
            (action == 'Home Run' ||
                action == 'Single' ||
                action == 'Double' ||
                action == 'Triple')) {
          _rbiCount = inning; // Use the inning number as RBI count
        } else {
          _rbiCount = null; // Don't set RBI count for solo actions
        }
      });
    }

    // Update caption
    _updateCaption();
  }

  void _processMagicInputWithPlayerKeepBar(
      Player selectedPlayer, String actionText) {
    // Clear existing selections but keep the magic bar active
    setState(() {
      selectedHomePlayers.clear();
      selectedAwayPlayers.clear();
      _selectedVerb = null;
      _selectedActionVerb = null;
      _rbiCount = null;
      _selectedRbiInning = null;
      _firstTeamSelected = null;
      _firstPlayerSelected = null;

      // DON'T clear player search state - keep the magic bar active
      // _filteredPlayers.clear();
      // _noPlayersFound = false;
      // _isPlayerSearchMode = false;
    });

    // Select the chosen player
    final isHomePlayer = _homeRoster.contains(selectedPlayer);
    setState(() {
      if (isHomePlayer) {
        selectedHomePlayers.add(selectedPlayer.displayName ?? 'Unknown Player');
        _firstTeamSelected = true;
        _firstPlayerSelected = selectedPlayer.displayName ?? 'Unknown Player';
      } else {
        selectedAwayPlayers.add(selectedPlayer.displayName ?? 'Unknown Player');
        _firstTeamSelected = false;
        _firstPlayerSelected = selectedPlayer.displayName ?? 'Unknown Player';
      }
    });

    // Parse the action text (same as original method)
    final parts = actionText.trim().toLowerCase().split(' ');
    String action = '';
    int? inning;

    for (final part in parts) {
      // Check for inning number
      if (_isNumeric(part)) {
        inning = int.parse(part);
        continue;
      }

      // Parse action (using same switch as original)
      switch (part) {
        case 'hr':
        case 'homerun':
        case 'homer':
          action = 'Home Run';
          break;
        // Add more cases as needed
      }
    }

    // Set the action and inning
    if (action.isNotEmpty) {
      setState(() {
        _selectedVerb = action;
        _selectedActionVerb = action;
        _selectedRbiInning = inning;

        // Only set RBI count if inning is provided
        if (inning != null &&
            (action == 'Home Run' ||
                action == 'Single' ||
                action == 'Double' ||
                action == 'Triple')) {
          _rbiCount = inning;
        } else {
          _rbiCount = null;
        }
      });
    }

    // Update caption but DON'T clear the magic bar
    _updateCaption();
  }

  void _showTeamSelectionDebug(String teamName, bool isHome) {
    final roster = isHome ? _homeRoster : _awayRoster;
    final teamType = isHome ? 'HOME' : 'AWAY';

    String debugInfo = '=== TEAM SELECTION DEBUG ===\n\n';
    debugInfo += 'TEAM: $teamName ($teamType)\n';
    debugInfo += 'API: ${_apiManager.currentApi}\n';
    debugInfo += 'TOTAL PLAYERS: ${roster.length}\n\n';

    // Add API debugging info
    debugInfo += '=== API DEBUG ===\n';
    debugInfo += 'Current API: ${_apiManager.currentApi}\n';
    debugInfo +=
        'Connection Status: ${_apiManager.getConnectionStatusMessage()}\n\n';

    // Count players with jersey numbers
    int playersWithNumbers = 0;
    int playersWithoutNumbers = 0;

    // Sort roster by jersey number for easier reading
    final sortedRoster = List<Player>.from(roster);
    sortedRoster.sort((a, b) {
      final aNum = int.tryParse(a.jerseyNumber ?? '999') ?? 999;
      final bNum = int.tryParse(b.jerseyNumber ?? '999') ?? 999;
      return aNum.compareTo(bNum);
    });

    debugInfo += 'ALL PLAYERS (sorted by jersey number):\n';
    for (final player in sortedRoster) {
      final hasNumber =
          player.jerseyNumber != null && player.jerseyNumber!.isNotEmpty;
      if (hasNumber) {
        playersWithNumbers++;
        debugInfo += '  #${player.jerseyNumber}: ${player.fullName}\n';
      } else {
        playersWithoutNumbers++;
        debugInfo += '  #N/A: ${player.fullName}\n';
      }
    }

    debugInfo += '\n=== SUMMARY ===\n';
    debugInfo += 'Players WITH jersey numbers: $playersWithNumbers\n';
    debugInfo += 'Players WITHOUT jersey numbers: $playersWithoutNumbers\n';
    debugInfo += 'Total players: ${roster.length}\n';

    // Show popup
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Team Selection: $teamName'),
        content: SingleChildScrollView(
          child: Text(
            debugInfo,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              // Copy to clipboard
              Clipboard.setData(ClipboardData(text: debugInfo));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Team info copied to clipboard!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  void _debugRosters() {
    String debugInfo = '=== ROSTER DEBUG INFO ===\n\n';

    // API info
    debugInfo += 'CURRENT API: ${_apiManager.currentApi}\n';
    debugInfo += 'API STATUS: ${_apiManager.getConnectionStatusMessage()}\n\n';

    // Home team info
    debugInfo += 'HOME TEAM: ${selectedHomeTeam ?? "Not selected"}\n';
    debugInfo += 'Home roster count: ${_homeRoster.length}\n';
    debugInfo += 'Home players with jersey numbers:\n';

    // Sort home roster by jersey number for easier reading
    final sortedHomeRoster = List<Player>.from(_homeRoster);
    sortedHomeRoster.sort((a, b) {
      final aNum = int.tryParse(a.jerseyNumber ?? '999') ?? 999;
      final bNum = int.tryParse(b.jerseyNumber ?? '999') ?? 999;
      return aNum.compareTo(bNum);
    });

    int homePlayersWithNumbers = 0;
    for (final player in sortedHomeRoster) {
      final hasNumber =
          player.jerseyNumber != null && player.jerseyNumber!.isNotEmpty;
      if (hasNumber) homePlayersWithNumbers++;
      debugInfo += '  #${player.jerseyNumber ?? "N/A"}: ${player.fullName}\n';
    }

    debugInfo +=
        '\nHome players WITH jersey numbers: $homePlayersWithNumbers\n';
    debugInfo +=
        'Home players WITHOUT jersey numbers: ${_homeRoster.length - homePlayersWithNumbers}\n';

    debugInfo += '\nAWAY TEAM: ${selectedAwayTeam ?? "Not selected"}\n';
    debugInfo += 'Away roster count: ${_awayRoster.length}\n';
    debugInfo += 'Away players with jersey numbers:\n';

    // Sort away roster by jersey number for easier reading
    final sortedAwayRoster = List<Player>.from(_awayRoster);
    sortedAwayRoster.sort((a, b) {
      final aNum = int.tryParse(a.jerseyNumber ?? '999') ?? 999;
      final bNum = int.tryParse(b.jerseyNumber ?? '999') ?? 999;
      return aNum.compareTo(bNum);
    });

    int awayPlayersWithNumbers = 0;
    for (final player in sortedAwayRoster) {
      final hasNumber =
          player.jerseyNumber != null && player.jerseyNumber!.isNotEmpty;
      if (hasNumber) awayPlayersWithNumbers++;
      debugInfo += '  #${player.jerseyNumber ?? "N/A"}: ${player.fullName}\n';
    }

    debugInfo +=
        '\nAway players WITH jersey numbers: $awayPlayersWithNumbers\n';
    debugInfo +=
        'Away players WITHOUT jersey numbers: ${_awayRoster.length - awayPlayersWithNumbers}\n';

    debugInfo += '\n=== END DEBUG INFO ===';

    // Show debug info in a dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Roster Debug Info'),
        content: SingleChildScrollView(
          child: Text(
            debugInfo,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              // Copy to clipboard
              Clipboard.setData(ClipboardData(text: debugInfo));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Debug info copied to clipboard!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  void _testApiDirectly() async {
    String debugInfo = '=== DIRECT API TEST ===\n\n';

    try {
      debugInfo += 'Testing API: ${_apiManager.currentApi}\n\n';

      // Test fetching all teams
      debugInfo += '1. Testing team fetch...\n';
      final teams = await _apiManager.fetchTeams();
      debugInfo += 'Found ${teams.length} teams\n';
      debugInfo += 'Sample teams:\n';
      for (int i = 0; i < teams.length.clamp(0, 5); i++) {
        debugInfo += '  - ${teams[i].name}\n';
      }

      // Test fetching players for a specific team (Toronto Blue Jays)
      debugInfo += '\n2. Testing player fetch for Toronto Blue Jays...\n';
      try {
        final players = await _apiManager.fetchTeamRoster('Toronto Blue Jays');
        debugInfo += 'Found ${players.length} players for Toronto Blue Jays\n';
        debugInfo += 'Players with jersey numbers:\n';

        int playersWithNumbers = 0;
        for (final player in players) {
          if (player.jerseyNumber != null && player.jerseyNumber!.isNotEmpty) {
            playersWithNumbers++;
            debugInfo += '  #${player.jerseyNumber}: ${player.fullName}\n';
          }
        }

        debugInfo += '\nSummary for Toronto Blue Jays:\n';
        debugInfo += 'Players WITH jersey numbers: $playersWithNumbers\n';
        debugInfo +=
            'Players WITHOUT jersey numbers: ${players.length - playersWithNumbers}\n';
        debugInfo += 'Total players: ${players.length}\n';

        // Check for player #27 specifically
        final player27 = players.where((p) => p.jerseyNumber == '27').toList();
        if (player27.isNotEmpty) {
          debugInfo += '\nPlayer #27 found: ${player27.first.fullName}\n';
        } else {
          debugInfo += '\nPlayer #27 NOT found in roster\n';
        }
      } catch (e) {
        debugInfo += 'Error fetching Toronto Blue Jays players: $e\n';
      }
    } catch (e) {
      debugInfo += 'Error during API test: $e\n';
    }

    // Show debug info in a dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Direct API Test Results'),
        content: SingleChildScrollView(
          child: Text(
            debugInfo,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              // Copy to clipboard
              Clipboard.setData(ClipboardData(text: debugInfo));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('API test results copied to clipboard!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  void _updateCaption() {
    // Safety check: if either team is not selected, don't try to generate captions
    if (selectedHomeTeam == null || selectedAwayTeam == null) {
      captionController.clear();
      return;
    }

    // Get photo date from metadata, fallback to current date
    DateTime photoDate = DateTime.now();
    if (widget.metadata != null) {
      final dateTimeOriginal = widget.metadata!['DateTimeOriginal']?.toString();
      final createDate = widget.metadata!['CreateDate']?.toString();
      final modifyDate = widget.metadata!['ModifyDate']?.toString();

      // Try to parse the date from EXIF data
      final dateString = dateTimeOriginal ?? createDate ?? modifyDate;
      if (dateString != null && dateString.isNotEmpty) {
        try {
          // Parse EXIF date format (YYYY:MM:DD HH:MM:SS)
          final parts = dateString.split(' ');
          if (parts.length >= 1) {
            final datePart = parts[0];
            final dateComponents = datePart.split(':');
            if (dateComponents.length >= 3) {
              final year = int.parse(dateComponents[0]);
              final month = int.parse(dateComponents[1]);
              final day = int.parse(dateComponents[2]);
              photoDate = DateTime(year, month, day);
            }
          }
        } catch (e) {
          print('Error parsing photo date: $e');
          // Fallback to current date
        }
      } else {}
    } else {}

    // Get date components
    final city = cityController.text;
    final prov = provinceController.text;
    final monLC = _month(photoDate.month);
    final day = photoDate.day;
    final year = photoDate.year;
    final monthUpper = monLC.toUpperCase();
    final formattedDate = '$monLC $day, $year';
    final dateline = _formatDateline(city, prov, monthUpper, day);
    final locationSuffix = _formatLocationSuffix(city, prov, formattedDate);

    // Determine which team the selected players belong to
    // First player selected = Main focus, opposite team players = always "against"
    Set<String> activePlayers;
    Set<String> opponentPlayers;
    String? opponentTeamName;

    if (selectedAwayPlayers.isNotEmpty && selectedHomePlayers.isEmpty) {
      // Only away team players are selected
      activePlayers = selectedAwayPlayers;
      opponentPlayers = <String>{};
      opponentTeamName = selectedHomeTeam;
    } else if (selectedHomePlayers.isNotEmpty && selectedAwayPlayers.isEmpty) {
      // Only home team players are selected
      activePlayers = selectedHomePlayers;
      opponentPlayers = <String>{};
      opponentTeamName = selectedAwayTeam;
    } else if (selectedHomePlayers.isNotEmpty &&
        selectedAwayPlayers.isNotEmpty) {
      // Both teams have players - use the first team selected as main focus

      if (_firstTeamSelected == true) {
        // Home team was selected first, so they're the main focus

        activePlayers = selectedHomePlayers;
        opponentPlayers = selectedAwayPlayers;
        opponentTeamName = selectedAwayTeam;
      } else if (_firstTeamSelected == false) {
        // Away team was selected first, so they're the main focus

        activePlayers = selectedAwayPlayers;
        opponentPlayers = selectedHomePlayers;
        opponentTeamName = selectedHomeTeam;
      } else {
        // Fallback: if _firstTeamSelected is null, use home team as default

        activePlayers = selectedHomePlayers;
        opponentPlayers = selectedAwayPlayers;
        opponentTeamName = selectedAwayTeam;
      }
    } else {
      // No players selected
      captionController.clear();
      _updatePersonalityField(); // Clear personality field when no players selected
      return;
    }

    if (activePlayers.isEmpty) {
      captionController.clear();
      return;
    }

    // Get the verb to use for player formatting
    final verbToUse = _selectedActionVerb ?? _selectedVerb;

    // Format the main player(s)
    String playerName;

    if ((_selectedHittingAction == 'celebrates' ||
            _selectedHittingAction == 'celebrates_in_dugout' ||
            verbToUse == 'Celebration' ||
            verbToUse == 'Celebrates' ||
            verbToUse == 'Celebrates With' ||
            verbToUse == 'Celebrates Against') &&
        _firstPlayerSelected != null) {
      // For celebration actions, check if "with teammates" is selected OR if we're in a hit interface OR celebration interface with multiple players
      final isHitInterface = (verbToUse == 'Single' ||
          verbToUse == 'Double' ||
          verbToUse == 'Triple' ||
          verbToUse == 'Home Run' ||
          verbToUse == 'Grand Slam');
      final isCelebrationInterface = (verbToUse == 'Celebration' ||
          verbToUse == 'Celebrates' ||
          verbToUse == 'Celebrates With' ||
          verbToUse == 'Celebrates Against');
      final hasMultiplePlayers = activePlayers.length > 1;

      // print(
      //     'DEBUG: _isCelebratingWithTeammates = $_isCelebratingWithTeammates');
      // print(
      //     'DEBUG: isHitInterface = $isHitInterface, isCelebrationInterface = $isCelebrationInterface, hasMultiplePlayers = $hasMultiplePlayers');

      if (_isCelebratingWithTeammates ||
          (isHitInterface && hasMultiplePlayers) ||
          (isCelebrationInterface && hasMultiplePlayers)) {
        // If "with teammates" is selected OR we're in a hit interface with multiple players, only use the main player
        final mainPlayerTeam =
            selectedHomePlayers.contains(_firstPlayerSelected)
                ? selectedHomeTeam
                : selectedAwayTeam;
        playerName = '$_firstPlayerSelected of the $mainPlayerTeam';
      } else {
        // If "with teammates" is NOT selected and not a multi-player hit interface, use all active players
        playerName = _combinePlayersWithSingleTeam(activePlayers.toList());
      }
    } else {
      // For other actions, use all active players
      playerName = _combinePlayersWithSingleTeam(activePlayers.toList());
    }

    // Build the action phrase based on selected verb
    String actionPhrase = '';

    final verbForAction = _selectedActionVerb ?? _selectedVerb;
    if (verbForAction != null) {
      actionPhrase = _buildActionPhrase();
    }

    // Handle opponent players if selected
    String opponentPart = '';
    if (_selectedHittingAction == 'celebrates' ||
        _selectedHittingAction == 'celebrates_in_dugout' ||
        _selectedHittingAction == 'trots_the_bases' ||
        verbToUse == 'At Bat' ||
        verbToUse == 'Pitching' ||
        verbToUse == 'Swings' ||
        verbToUse == 'Fielding Position' ||
        verbToUse == 'Catches' ||
        verbToUse == 'Throws' ||
        verbToUse == 'Tags' ||
        verbToUse == 'Groundball' ||
        verbToUse == 'Steals' ||
        verbToUse == 'Slides' ||
        verbToUse == 'Runs' ||
        verbToUse == 'Rounds' ||
        verbToUse == 'Double Play' ||
        verbToUse == 'Triple Play' ||
        verbToUse == 'Celebration' ||
        verbToUse == 'Celebrates' ||
        verbToUse == 'Celebrates With' ||
        verbToUse == 'Celebrates Against' ||
        verbToUse == 'Walks' ||
        verbToUse == 'Dejection' ||
        verbToUse == 'Looks On' ||
        verbToUse == 'Walks Off Field' ||
        verbToUse == 'Runs Off Field' ||
        verbToUse == 'Takes the Field' ||
        verbToUse == 'Comes Off the Field' ||
        verbToUse == 'National Anthem' ||
        verbToUse == 'Post Game Win' ||
        verbToUse == 'Post Game Loss' ||
        verbToUse == 'Batting Practice' ||
        verbToUse == 'Fielding Practice' ||
        verbToUse == 'Warm Ups' ||
        verbToUse == 'Walks On Field' ||
        verbToUse == 'Runs On Field' ||
        verbToUse == 'Stretching' ||
        customCelebrationController.text.isNotEmpty ||
        customDejectionController.text.isNotEmpty) {
      // For these actions, don't add opponent part here - it's handled in the action phrase
      opponentPart = '';
    } else {
      // For other actions, include specific players if selected
      if (opponentPlayers.isNotEmpty) {
        final opponentNames =
            _combinePlayersWithSingleTeam(opponentPlayers.toList());
        opponentPart = ' against $opponentNames';
      } else if (opponentTeamName != null) {
        opponentPart = ' against the $opponentTeamName';
      }
    }

    // Add inning if specified (but not for post-game verbs)
    String inningPart = '';
    final isPostGameVerb =
        _selectedVerb == 'Post Game Win' || _selectedVerb == 'Post Game Loss';

    if (!isPostGameVerb) {
      if (_selectedRbiInning != null) {
        inningPart =
            ' during the ${_getOrdinalSuffix(_selectedRbiInning!)} inning';
      } else if (_selectedCustomTextInning != null) {
        inningPart =
            ' during the ${_getOrdinalSuffix(_selectedCustomTextInning!)} inning';
      }
      // Note: _isPriorToGame is handled separately in the gamePart logic
    }

    // Use home team stadium from API, fallback to controller if not available
    final stadium = homeTeamStadium ?? stadiumController.text;
    // Get creator from metadata widget or use default
    final creatorValue = widget.metadata?['Creator'];
    String photoBy;
    if (creatorValue is List) {
      // If it's a list, take the first value only
      photoBy = creatorValue.isNotEmpty
          ? creatorValue.first.toString()
          : 'Mark Blinch';
    } else {
      photoBy = creatorValue?.toString() ?? 'Mark Blinch';
    }

    // Add custom text between players if provided (but not magic input)
    String customTextPart = '';
    if (customBetweenPlayersController.text.isNotEmpty &&
        !_isMagicInput(customBetweenPlayersController.text)) {
      customTextPart = ' ${customBetweenPlayersController.text}';
    }

    // Build the final caption
    String gamePart;
    String opponentPartModified;

    if (_isPriorToGame) {
      gamePart = 'in their MLB game';
      // For "prior to game", we need to extract just the team name from opponentPart
      String teamName = '';
      if (opponentPart.contains('against the ')) {
        teamName = opponentPart.replaceAll(' against the ', '');
      } else if (opponentPart.contains('against ')) {
        teamName = opponentPart.replaceAll(' against ', '');
      }

      // If teamName is empty, try to get it from the opponent team
      if (teamName.isEmpty && opponentTeamName != null) {
        teamName = opponentTeamName;
      }

      // Check if action phrase already contains "against" or "playing" to avoid duplication
      if (actionPhrase.contains('against') ||
          actionPhrase.contains('playing')) {
        opponentPartModified = ' prior to play';
      } else {
        opponentPartModified = ' prior to play against the $teamName';
      }
    } else {
      gamePart = 'in their MLB game';
      opponentPartModified = opponentPart;
    }

    final caption = '$dateline '
        '$playerName${customTextPart}${actionPhrase.isNotEmpty ? ' $actionPhrase' : ''}$opponentPartModified$inningPart '
        '$gamePart at $stadium on $formattedDate $locationSuffix. (Photo by $photoBy/Getty Images)';

    // Set caption text directly (no diacritic removal)
    captionController.text = caption;

    // Update personality field with all selected players (always call to handle empty case)
    _updatePersonalityField();
  }

  Future<void> _onFtpPressed() async {
    // Save IPTC metadata before uploading
    if (widget.onSaveIptc != null) {
      await widget.onSaveIptc!();
    }

    // Check if FTP settings are configured
    if (_ftpHost.isEmpty || _ftpUsername.isEmpty || _ftpPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please configure FTP settings first!'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Check if an image is selected
    print('DEBUG: FTP Upload - currentImagePath: "${widget.currentImagePath}"');
    print(
        'DEBUG: FTP Upload - currentImagePath is null: ${widget.currentImagePath == null}');
    print(
        'DEBUG: FTP Upload - currentImagePath is empty: ${widget.currentImagePath?.isEmpty}');

    if (widget.currentImagePath == null || widget.currentImagePath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an image first!'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Use original filename
    final originalFileName = p.basename(widget.currentImagePath!);
    final remoteFileName = originalFileName;

    // Build full remote path
    final fullRemotePath = _ftpRemotePath.isNotEmpty
        ? '${_ftpRemotePath.endsWith('/') ? _ftpRemotePath : '$_ftpRemotePath/'}$remoteFileName'
        : remoteFileName;

    print('FTP: Generated remote filename: $remoteFileName');
    print('FTP: Remote path: $_ftpRemotePath');
    print('FTP: Full remote path: $fullRemotePath');

    // Show progress dialog with progress bar
    double uploadProgress = 0.0;
    String statusText = 'Connecting to FTP server...';
    String? errorText;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Uploading Image...'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: uploadProgress,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  errorText != null ? Colors.red : Colors.blue,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                statusText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: errorText != null ? Colors.red : Colors.black87,
                  fontWeight:
                      errorText != null ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Text(
                    errorText!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    try {
      final result = await FtpClientService.uploadFile(
        host: _ftpHost,
        username: _ftpUsername,
        password: _ftpPassword,
        localFilePath: widget.currentImagePath!,
        remoteFilePath: fullRemotePath,
        port: _ftpPort,
        passiveMode: _ftpPassiveMode,
        onProgress: (status, progress, error) {
          uploadProgress = progress;
          statusText = status;
          errorText = error;
          setState(() {});
        },
      );

      // Wait a moment to show completion
      await Future.delayed(const Duration(milliseconds: 500));

      Navigator.pop(context); // Close progress dialog

      if (result.success) {
        setState(() {
          // No need to increment picture number when using original filenames
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully uploaded: $remoteFileName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${result.error}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      Navigator.pop(context); // Close progress dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // Folder picking functionality
  Future<void> _pickFolder() async {
    print('Starting folder picker...');
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) {
      print('No folder selected');
      return;
    }

    print('Selected folder: $dirPath');

    // List image files
    final files = await _listImageFiles(dirPath);

    if (files.isNotEmpty) {
      // Notify parent about loaded images
      if (widget.onImagesLoaded != null) {
        widget.onImagesLoaded!(files);
      }

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loaded ${files.length} images from folder'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Test API connection
  Future<bool> _testApiConnection() async {
    try {
      final teams = await _apiManager.fetchTeams();
      return teams.isNotEmpty;
    } catch (e) {
      print('Error testing API connection: $e');
      return false;
    }
  }

  // Helper method to list image files
  Future<List<String>> _listImageFiles(String dirPath) async {
    try {
      final directory = Directory(dirPath);
      final files = directory.listSync();

      final imageExtensions = [
        '.jpg',
        '.jpeg',
        '.png',
        '.tiff',
        '.bmp',
        '.JPG',
        '.JPEG',
        '.PNG',
        '.TIFF',
        '.BMP'
      ];

      final imageFiles = files
          .where((file) {
            if (file is! File) return false;

            final path = file.path;
            final extension = path.split('.').last.toLowerCase();
            return imageExtensions.contains('.$extension');
          })
          .map((file) => file.path)
          .toList();

      // Sort files by date taken (DateTimeOriginal from EXIF)
      await _sortImagesByDateTaken(imageFiles);

      return imageFiles;
    } catch (e) {
      print('Error listing image files: $e');
      return [];
    }
  }

  // Sort images by date taken from EXIF DateTimeOriginal
  Future<void> _sortImagesByDateTaken(List<String> imageFiles) async {
    print('Sorting ${imageFiles.length} images by date taken...');

    // Create a list of maps with file path and date taken
    List<Map<String, dynamic>> filesWithDates = [];

    for (String filePath in imageFiles) {
      try {
        final proc = await Process.run('exiftool', [
          '-j',
          '-DateTimeOriginal',
          '-CreateDate',
          '-ModifyDate',
          filePath,
        ]);

        DateTime? dateTime;
        if (proc.exitCode == 0) {
          final List data = jsonDecode(proc.stdout as String);
          if (data.isNotEmpty) {
            final meta = data.first as Map<String, dynamic>;
            String? dateStr = meta['DateTimeOriginal']?.toString() ??
                meta['CreateDate']?.toString() ??
                meta['ModifyDate']?.toString();

            if (dateStr != null) {
              try {
                // Parse EXIF date format (YYYY:MM:DD HH:MM:SS)
                dateTime = DateTime.parse(
                    dateStr.replaceFirst(':', '-').replaceFirst(':', '-'));
              } catch (e) {
                print('Error parsing date for $filePath: $e');
              }
            }
          }
        }

        // If no EXIF date found, use file modification date as fallback
        if (dateTime == null) {
          try {
            final file = File(filePath);
            dateTime = await file.lastModified();
          } catch (e) {
            print('Error getting file date for $filePath: $e');
            dateTime = DateTime.now(); // Ultimate fallback
          }
        }

        filesWithDates.add({
          'path': filePath,
          'date': dateTime,
        });
      } catch (e) {
        print('Error processing $filePath: $e');
        // Add file with current date as fallback
        filesWithDates.add({
          'path': filePath,
          'date': DateTime.now(),
        });
      }
    }

    // Sort by date (earliest to latest)
    filesWithDates.sort((a, b) => a['date'].compareTo(b['date']));

    // Update the imageFiles list with sorted paths
    imageFiles.clear();
    imageFiles.addAll(filesWithDates.map((item) => item['path'] as String));

    print('Images sorted by date taken (earliest to latest)');
  }

  void _updatePersonalityField() {
    // Combine all selected players from both teams
    final allSelectedPlayers = <String>[];
    allSelectedPlayers.addAll(selectedHomePlayers);
    allSelectedPlayers.addAll(selectedAwayPlayers);

    // If no players are selected, clear the personality field
    if (allSelectedPlayers.isEmpty) {
      personalityController.text = '';
      return;
    }

    // Remove jersey numbers and # symbols from player names
    final cleanPlayerNames = allSelectedPlayers.map((playerName) {
      // Remove numbers, # symbols, and extra spaces, keep only the name
      return playerName.replaceAll(RegExp(r'\s*[#\d]+\s*'), '').trim();
    }).toList();

    // Join players with semicolons, no semicolon after the last player
    final personalityText = cleanPlayerNames.join(';');

    // Update the personality field directly (no diacritic removal)
    personalityController.text = personalityText;
  }

  String _getTeamAbbreviation(String teamName) {
    // Map of full team names to their abbreviations
    const Map<String, String> teamAbbreviations = {
      'Arizona Diamondbacks': 'ARI',
      'Atlanta Braves': 'ATL',
      'Baltimore Orioles': 'BAL',
      'Boston Red Sox': 'BOS',
      'Chicago Cubs': 'CHC',
      'Chicago White Sox': 'CWS',
      'Cincinnati Reds': 'CIN',
      'Cleveland Guardians': 'CLE',
      'Colorado Rockies': 'COL',
      'Detroit Tigers': 'DET',
      'Houston Astros': 'HOU',
      'Kansas City Royals': 'KC',
      'Los Angeles Angels': 'LAA',
      'Los Angeles Dodgers': 'LAD',
      'Miami Marlins': 'MIA',
      'Milwaukee Brewers': 'MIL',
      'Minnesota Twins': 'MIN',
      'New York Mets': 'NYM',
      'New York Yankees': 'NYY',
      'Oakland Athletics': 'OAK',
      'Philadelphia Phillies': 'PHI',
      'Pittsburgh Pirates': 'PIT',
      'San Diego Padres': 'SD',
      'San Francisco Giants': 'SF',
      'Seattle Mariners': 'SEA',
      'St. Louis Cardinals': 'STL',
      'Tampa Bay Rays': 'TB',
      'Texas Rangers': 'TEX',
      'Toronto Blue Jays': 'TOR',
      'Washington Nationals': 'WSH',
    };

    final abbreviation = teamAbbreviations[teamName];
    // print('DEBUG: Converting team name "$teamName" to abbreviation: "$abbreviation"');
    return abbreviation ?? teamName;
  }

  Widget _buildPlayerChip(String playerName, bool isHome) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isHome ? Colors.blue.shade100 : Colors.orange.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHome ? Colors.blue.shade300 : Colors.orange.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatChipName(playerName),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: isHome ? Colors.blue.shade700 : Colors.orange.shade700,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              setState(() {
                // Check if this is the first selected player (main player)
                final isMainPlayer = _isFirstSelectedPlayer(playerName);

                if (isHome) {
                  selectedHomePlayers.remove(playerName);
                } else {
                  selectedAwayPlayers.remove(playerName);
                }

                // If removing the main player, reset everything
                if (isMainPlayer) {
                  _resetCaption();
                  return; // _resetCaption already calls _updateCaption and _updatePersonalityField
                }
              });
              _updateCaption();
              _updatePersonalityField();
            },
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isHome ? Colors.blue.shade200 : Colors.orange.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.close,
                size: 10,
                color: isHome ? Colors.blue.shade700 : Colors.orange.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCaptionVerbPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Action Verb'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: ListView(
            children: verbCategories.entries.map((category) {
              return ExpansionTile(
                title: Text(
                  category.key,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                children: category.value.map((verb) {
                  return ListTile(
                    title: Text(verb),
                    onTap: () {
                      setState(() {
                        selectedCaptionVerb = verb;
                      });
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showPlayerSelectionDialog(bool isHome) {
    final roster = isHome ? _homeRoster : _awayRoster;
    final selectedPlayers = isHome ? selectedHomePlayers : selectedAwayPlayers;
    final teamName = isHome ? selectedHomeTeam : selectedAwayTeam;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select ${teamName ?? 'Team'} Players'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: roster.isEmpty
              ? const Center(
                  child: Text('No players available'),
                )
              : ListView.builder(
                  itemCount: roster.length,
                  itemBuilder: (context, index) {
                    final player = roster[index];
                    final isSelected =
                        selectedPlayers.contains(player.displayName);

                    return CheckboxListTile(
                      title: Text(
                        player.displayName,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        'Position: Unknown', // Could add position data later
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                      value: isSelected,
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            // Track which team was selected first
                            if (_firstTeamSelected == null) {
                              _firstTeamSelected = isHome;
                              _firstPlayerSelected = player.displayName;
                              // print(
                              //     'DEBUG: First team selected (dialog): ${isHome ? "HOME" : "AWAY"}');
                              // print(
                              //     'DEBUG: First player selected (dialog): ${player.displayName}');
                            } else {}
                            if (isHome) {
                              selectedHomePlayers.add(player.displayName);
                            } else {
                              selectedAwayPlayers.add(player.displayName);
                            }
                          } else {
                            if (isHome) {
                              selectedHomePlayers.remove(player.displayName);
                            } else {
                              selectedAwayPlayers.remove(player.displayName);
                            }
                          }
                        });
                        _updateCaption();
                        Navigator.of(context).pop();
                      },
                      controlAffinity: ListTileControlAffinity.trailing,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildVerbSelectionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6),
              topRight: Radius.circular(6),
            ),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Text(
            'Verb Selection',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Verb categories
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: verbCategories.entries.map((category) {
            return FilterChip(
              label: Text(
                category.key,
                style: const TextStyle(fontSize: 9),
              ),
              selected: _selectedVerb != null &&
                  category.value.contains(_selectedVerb),
              onSelected: (_) => _showVerbPicker(category.key),
              backgroundColor: Colors.grey.shade100,
              selectedColor: Colors.blue.shade100,
              checkmarkColor: Colors.blue.shade700,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),

        const SizedBox(height: 8),

        // Selected verb display
        if (_selectedVerb != null)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, size: 12, color: Colors.blue),
                const SizedBox(width: 4),
                Text(
                  'Selected: $_selectedVerb',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.blue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedVerb = null;
                      _clearVerbSubSelections();
                    });
                  },
                  child: const Icon(Icons.close, size: 12, color: Colors.blue),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Prev button
            CustomButton(
              onTap: () async {
                if (widget.onSaveIptc != null) {
                  await widget.onSaveIptc!();
                }
                widget.onPreviousImage?.call();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_back,
                        size: 12, color: Colors.grey.shade700),
                    const SizedBox(width: 2),
                    Text('Prev',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Copy button
            CustomButton(
              onTap: () {
                _copyMetadataFromCaptionWidget();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.copy, size: 12, color: Colors.grey.shade700),
                    const SizedBox(width: 2),
                    Text('Copy',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Paste button
            CustomButton(
              onTap: _pasteMetadataToCaptionWidget,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.paste, size: 12, color: Colors.grey.shade700),
                    const SizedBox(width: 2),
                    Text('Paste',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Next button
            CustomButton(
              onTap: () async {
                if (widget.onSaveIptc != null) {
                  await widget.onSaveIptc!();
                }
                widget.onNextImage?.call();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Next',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_forward,
                        size: 12, color: Colors.grey.shade700),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _onFtpPressed,
                icon: const Icon(Icons.cloud_upload, size: 14),
                label: const Text('FTP Upload', style: TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _showFtpSettings,
                icon: const Icon(Icons.settings, size: 14),
                label:
                    const Text('FTP Settings', style: TextStyle(fontSize: 10)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(child: SizedBox()), // Empty space for alignment
          ],
        ),
      ],
    );
  }

  void _showVerbPicker(String category) {
    final verbs = verbCategories[category] ?? [];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select $category Verb'),
        content: SizedBox(
          width: 200,
          height: 200,
          child: ListView.builder(
            itemCount: verbs.length,
            itemBuilder: (context, index) {
              final verb = verbs[index];
              return ListTile(
                title: Text(verb),
                onTap: () {
                  setState(() {
                    _selectedVerb = verb;
                    _selectedActionVerb = verb; // Store for caption generation
                    _clearVerbSubSelections();
                  });
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _clearVerbSubSelections() {
    _selectedHomeRunType = null;
    _rbiCount = null;
    _isBatterRunning = false;
    _isSliding = false;
    _showFieldingOptions = false;
    _selectedFieldingAction = null;
    _selectedBaseRunningAction = null;
    _selectedStealBase = null;
    _showStealAgainstPlayer = false;
    _isSoloCelebration = false;
    celebrateWith.clear();
    celebrateAgainst.clear();
    _selectedCelebrationType = null;
    _selectedAtBatAction = null;
    _selectedBattingAction = null;
  }

  void _onCopyPressed() {
    final captionText = captionController.text;
    final personalityText = personalityController.text;

    String clipboardText = captionText;
    if (personalityText.isNotEmpty) {
      clipboardText += '\n\nPERSONALITY:\n$personalityText';
    }

    Clipboard.setData(ClipboardData(text: clipboardText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Caption and personality copied to clipboard!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onPastePressed() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData != null && clipboardData.text != null) {
      final text = clipboardData.text!;

      // Try to parse caption and personality
      if (text.contains('PERSONALITY:')) {
        final parts = text.split('PERSONALITY:');
        captionController.text = parts[0].trim();
        if (parts.length > 1) {
          personalityController.text = parts[1].trim();
        }
      } else {
        captionController.text = text;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Content pasted from clipboard!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // Copy metadata from caption widget (excluding date/time)
  void _copyMetadataFromCaptionWidget() {
    print('=== COPY FUNCTION CALLED ===');

    // Build complete metadata from all sources
    final allMetadata = <String, String>{};

    // Add metadata from widget if available
    if (widget.metadata != null) {
      // Convert all values to strings to handle int/string mixed types
      widget.metadata!.forEach((key, value) {
        if (value is String) {
          allMetadata[key] = value;
        } else if (value is List) {
          // For Keywords field, preserve commas; for other fields, use semicolons
          if (key == 'Keywords') {
            allMetadata[key] = value.join(', ');
          } else {
            allMetadata[key] = value.join(';');
          }
        } else if (value != null) {
          allMetadata[key] = value.toString();
        } else {
          allMetadata[key] = '';
        }
      });
    }

    // Add caption fields from controllers
    allMetadata['Caption-Abstract'] = captionController.text;
    allMetadata['XMP:Description'] = captionController.text;
    allMetadata['ImageDescription'] = captionController.text;
    allMetadata['XMP-getty:Personality'] = personalityController.text;
    allMetadata['Sub-location'] = stadiumController.text;
    allMetadata['City'] = cityController.text;
    allMetadata['Province-State'] = provinceController.text;

    print(
        'DEBUG: personalityController.text = "${personalityController.text}"');
    print(
        'DEBUG: allMetadata["XMP-getty:Personality"] = "${allMetadata['XMP-getty:Personality']}"');
    print(
        'DEBUG: personalityController.text length: ${personalityController.text.length}');
    print(
        'DEBUG: personalityController.text isEmpty: ${personalityController.text.isEmpty}');

    print('DEBUG: All metadata before filtering: $allMetadata');

    // Remove date and time fields
    allMetadata.remove('Date');
    allMetadata.remove('Time');
    allMetadata.remove('DateTimeOriginal');
    allMetadata.remove('CreateDate');
    allMetadata.remove('ModifyDate');

    print('DEBUG: Metadata after filtering: $allMetadata');

    final jsonString = jsonEncode(allMetadata);
    print('DEBUG: JSON being copied: ${jsonString.substring(0, 200)}...');

    Clipboard.setData(ClipboardData(text: jsonString));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Metadata copied (${allMetadata.length} fields)!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // Paste metadata to caption widget (excluding date/time)
  Future<void> _pasteMetadataToCaptionWidget() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);

      if (clipboardData != null && clipboardData.text != null) {
        final Map<String, dynamic> metadataMap =
            jsonDecode(clipboardData.text!);

        // Update the metadata in the parent widget
        if (widget.onMetadataUpdated != null) {
          final updatedMetadata =
              Map<String, dynamic>.from(widget.metadata ?? {});

          // Apply all fields except date and time
          if (metadataMap['TransmissionReference'] != null)
            updatedMetadata['TransmissionReference'] =
                metadataMap['TransmissionReference'].toString();
          if (metadataMap['CaptionWriter'] != null)
            updatedMetadata['CaptionWriter'] =
                metadataMap['CaptionWriter'].toString();
          if (metadataMap['Headline'] != null)
            updatedMetadata['Headline'] = metadataMap['Headline'].toString();
          if (metadataMap['Keywords'] != null)
            updatedMetadata['Keywords'] = metadataMap['Keywords'].toString();

          if (metadataMap['AuthorsPosition'] != null)
            updatedMetadata['AuthorsPosition'] =
                metadataMap['AuthorsPosition'].toString();
          if (metadataMap['Credit'] != null)
            updatedMetadata['Credit'] = metadataMap['Credit'].toString();
          if (metadataMap['Copyright'] != null)
            updatedMetadata['Copyright'] = metadataMap['Copyright'].toString();
          if (metadataMap['Source'] != null)
            updatedMetadata['Source'] = metadataMap['Source'].toString();
          if (metadataMap['Urgency'] != null)
            updatedMetadata['Urgency'] = metadataMap['Urgency'].toString();
          if (metadataMap['Country'] != null)
            updatedMetadata['Country'] = metadataMap['Country'].toString();
          if (metadataMap['CountryCode'] != null)
            updatedMetadata['CountryCode'] =
                metadataMap['CountryCode'].toString();
          if (metadataMap['Sub-location'] != null) {
            final stadiumValue = metadataMap['Sub-location'].toString();
            updatedMetadata['Sub-location'] = stadiumValue;
            // Update the stadium controller directly
            stadiumController.text = stadiumValue;
          }
          if (metadataMap['City'] != null) {
            final cityValue = metadataMap['City'].toString();
            updatedMetadata['City'] = cityValue;
            // Update the city controller directly
            cityController.text = cityValue;
          }
          if (metadataMap['Province-State'] != null) {
            final provinceValue = metadataMap['Province-State'].toString();
            updatedMetadata['Province-State'] = provinceValue;
            // Update the province controller directly
            provinceController.text = provinceValue;
          }
          if (metadataMap['ObjectName'] != null)
            updatedMetadata['ObjectName'] =
                metadataMap['ObjectName'].toString();
          if (metadataMap['Category'] != null)
            updatedMetadata['Category'] = metadataMap['Category'].toString();
          if (metadataMap['SupplementalCategories1'] != null)
            updatedMetadata['SupplementalCategories1'] =
                metadataMap['SupplementalCategories1'].toString();
          if (metadataMap['SupplementalCategories2'] != null)
            updatedMetadata['SupplementalCategories2'] =
                metadataMap['SupplementalCategories2'].toString();
          if (metadataMap['SupplementalCategories3'] != null)
            updatedMetadata['SupplementalCategories3'] =
                metadataMap['SupplementalCategories3'].toString();
          if (metadataMap['SpecialInstructions'] != null)
            updatedMetadata['SpecialInstructions'] =
                metadataMap['SpecialInstructions'].toString();

          // Caption and personality fields
          if (metadataMap['Caption-Abstract'] != null) {
            final captionValue = metadataMap['Caption-Abstract'].toString();
            updatedMetadata['Caption-Abstract'] = captionValue;
            // Update the caption controller directly
            captionController.text = captionValue;
          }
          if (metadataMap['XMP:Description'] != null)
            updatedMetadata['XMP:Description'] =
                metadataMap['XMP:Description'].toString();
          if (metadataMap['ImageDescription'] != null)
            updatedMetadata['ImageDescription'] =
                metadataMap['ImageDescription'].toString();
          if (metadataMap['XMP-getty:Personality'] != null) {
            final personalityValue =
                metadataMap['XMP-getty:Personality'].toString();
            updatedMetadata['XMP-getty:Personality'] = personalityValue;
            // Update the personality controller directly
            personalityController.text = personalityValue;
            print('DEBUG: Pasting personality value: "$personalityValue"');
            print(
                'DEBUG: Updated personalityController.text to: "${personalityController.text}"');
          } else {
            print('DEBUG: No XMP-getty:Personality found in metadataMap');
            print(
                'DEBUG: Available keys in metadataMap: ${metadataMap.keys.toList()}');
          }

          // Date and time are intentionally NOT pasted

          widget.onMetadataUpdated!(updatedMetadata);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Metadata pasted (date/time preserved)!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('DEBUG: Error pasting metadata: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error pasting metadata: $e'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _resetCaption() {
    setState(() {
      captionController.clear();
      personalityController.clear();
      customCelebrationController.clear();
      customBetweenPlayersController.clear();
      _selectedCustomTextInning = null;
      _showCustomTextInningSelector = false;

      // Reset all verb-related state
      _selectedVerb = null;
      _selectedActionVerb = null; // Clear action verb
      _selectedHittingAction = null;
      _selectedHomeRunType = null;
      _selectedTagsAction = null; // Clear tags action
      _selectedBase = null; // Clear selected base
      _selectedFieldingAction = null;
      _selectedBaseRunningAction = null;
      _selectedStealBase = null;
      _selectedCelebrationType = null;
      _isCelebratingScoring = false; // Reset scoring celebration selection
      _isCelebratingWithTeammates =
          false; // Reset teammates celebration selection
      _selectedAtBatAction = null;
      _selectedBattingAction = null;
      _selectedRbiInning = null;

      // Reset other verb-related state
      _rbiCount = null;
      _isBatterRunning = false;
      _isSliding = false;
      _showFieldingOptions = false;
      _showStealAgainstPlayer = false;
      _isSoloCelebration = false;
      _isDivingCatch = false;
      _walkOff = false;
      _showExtraInnings = false;
      _extraInningsPage = 0;
      _isPriorToGame = false; // Reset "prior to the game" selection

      // Clear collections
      celebrateWith.clear();
      celebrateAgainst.clear();

      // Clear per-hit-type selections
      _rbiCountByHit.clear();
      _homeRunTypeByHit.clear();
      _inningByHit.clear();
      _batterRunningByHit.clear();

      _clearVerbSubSelections();
      _firstTeamSelected = null;
      _firstPlayerSelected = null;
      selectedHomePlayers.clear();
      selectedAwayPlayers.clear();

      // Clear magic input related state
      _isPlayerSearchMode = true;
      _filteredPlayers.clear();
      _selectedPlayerNumbers.clear();
      _playerSearchText = '';
      _noPlayersFound = false;

      // Clear magic input player selection state
      _showMagicInputPlayerOptions = false;
      _magicInputMatchingPlayers.clear();
      _magicInputActionText = '';
      _waitingForHomeVisitorChoice = false;

      _updatePersonalityField();
    });

    if (widget.onReset != null) widget.onReset!();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Caption fields reset!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // FTP Profile Management Methods
  void _saveFtpProfile(
    String profileName, {
    String? host,
    String? username,
    String? password,
    int? port,
    String? remotePath,
    bool? passiveMode,
  }) {
    // Use provided values or fall back to current state values
    final profileData = {
      'host': host ?? _ftpHost,
      'username': username ?? _ftpUsername,
      'password': password ?? _ftpPassword,
      'port': port ?? _ftpPort,
      'remotePath': remotePath ?? _ftpRemotePath,
      'passiveMode': passiveMode ?? _ftpPassiveMode,
    };

    setState(() {
      _ftpProfiles[profileName] = profileData;
      _currentFtpProfile = profileName;

      // Update current state with the saved values
      _ftpHost = profileData['host'] as String;
      _ftpUsername = profileData['username'] as String;
      _ftpPassword = profileData['password'] as String;
      _ftpPort = profileData['port'] as int;
      _ftpRemotePath = profileData['remotePath'] as String;
      _ftpPassiveMode = profileData['passiveMode'] as bool;
    });

    // Save to persistent storage
    _saveFtpProfilesToStorage();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('FTP profile "$profileName" saved successfully!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _loadFtpProfile(String profileName) {
    final profile = _ftpProfiles[profileName];
    if (profile != null) {
      setState(() {
        _ftpHost = profile['host'] ?? '';
        _ftpUsername = profile['username'] ?? '';
        _ftpPassword = profile['password'] ?? '';
        _ftpPort = profile['port'] ?? 21;
        _ftpRemotePath = profile['remotePath'] ?? '';
        _ftpPassiveMode = profile['passiveMode'] ?? true;
        _currentFtpProfile = profileName;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('FTP profile "$profileName" loaded successfully!'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _deleteFtpProfile(String profileName) {
    setState(() {
      _ftpProfiles.remove(profileName);
      if (_currentFtpProfile == profileName) {
        _currentFtpProfile = null;
      }
    });

    // Save to persistent storage
    _saveFtpProfilesToStorage();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('FTP profile "$profileName" deleted successfully!'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // FTP Profile Persistence Methods
  Future<void> _saveFtpProfilesToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profilesJson = jsonEncode(_ftpProfiles);
      final currentProfile = _currentFtpProfile;

      await prefs.setString('ftp_profiles', profilesJson);
      if (currentProfile != null) {
        await prefs.setString('current_ftp_profile', currentProfile);
      }
    } catch (e) {
      print('Error saving FTP profiles: $e');
    }
  }

  Future<void> _loadFtpProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profilesJson = prefs.getString('ftp_profiles');
      final currentProfile = prefs.getString('current_ftp_profile');

      if (profilesJson != null) {
        final profiles = jsonDecode(profilesJson) as Map<String, dynamic>;
        setState(() {
          _ftpProfiles = Map<String, Map<String, dynamic>>.from(profiles);
          _currentFtpProfile = currentProfile;
        });
      }
    } catch (e) {
      print('Error loading FTP profiles: $e');
    }
  }

  void _showFtpProfileManager() {
    final profileNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('FTP Profile Manager'),
        content: SizedBox(
          width: 500,
          height: 400,
          child: Column(
            children: [
              // Profile List
              Expanded(
                child: _ftpProfiles.isEmpty
                    ? const Center(
                        child: Text(
                          'No saved profiles yet.\nCreate your first profile below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _ftpProfiles.length,
                        itemBuilder: (context, index) {
                          final profileName =
                              _ftpProfiles.keys.elementAt(index);
                          final profile = _ftpProfiles[profileName]!;
                          final isCurrent = _currentFtpProfile == profileName;

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color:
                                isCurrent ? Colors.blue.withOpacity(0.1) : null,
                            child: ListTile(
                              leading: Icon(
                                isCurrent ? Icons.check_circle : Icons.storage,
                                color: isCurrent ? Colors.blue : Colors.grey,
                              ),
                              title: Text(
                                profileName,
                                style: TextStyle(
                                  fontWeight: isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle:
                                  Text('${profile['host']}:${profile['port']}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!isCurrent)
                                    IconButton(
                                      icon: const Icon(Icons.play_arrow),
                                      onPressed: () =>
                                          _loadFtpProfile(profileName),
                                      tooltip: 'Load Profile',
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () =>
                                        _deleteFtpProfile(profileName),
                                    tooltip: 'Delete Profile',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const Divider(),
              // Create New Profile Section
              const Text(
                'Create New Profile',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: profileNameController,
                      decoration: const InputDecoration(
                        labelText: 'Profile Name',
                        hintText: 'e.g., Work Server, Home Server',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        if (value.trim().isNotEmpty) {
                          _saveFtpProfile(value.trim());
                          Navigator.pop(context);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final profileName = profileNameController.text.trim();
                      if (profileName.isNotEmpty) {
                        _saveFtpProfile(profileName);
                        Navigator.pop(context);
                      }
                    },
                    child: const Text('Save Current Settings'),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // FTP Methods
  void _showFtpSettings() {
    final hostController = TextEditingController(text: _ftpHost);
    final usernameController = TextEditingController(text: _ftpUsername);
    final passwordController = TextEditingController(text: _ftpPassword);
    final portController = TextEditingController(text: _ftpPort.toString());
    final remotePathController = TextEditingController(text: _ftpRemotePath);
    final profileNameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Text('FTP Server Settings'),
            const Spacer(),
            if (_currentFtpProfile != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Profile: $_currentFtpProfile',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Profile Management Row
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _showFtpProfileManager,
                      icon: const Icon(Icons.folder),
                      label: const Text('Manage Profiles'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[200],
                        foregroundColor: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_currentFtpProfile != null)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _saveFtpProfile(
                          _currentFtpProfile!,
                          host: hostController.text,
                          username: usernameController.text,
                          password: passwordController.text,
                          port: int.tryParse(portController.text) ?? 21,
                          remotePath: remotePathController.text,
                          passiveMode: _ftpPassiveMode,
                        ),
                        icon: const Icon(Icons.save),
                        label: const Text('Update Profile'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: hostController,
                decoration: const InputDecoration(
                  labelText: 'FTP Host',
                  hintText: 'ftp.example.com',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: portController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        hintText: '21',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: remotePathController,
                decoration: const InputDecoration(
                  labelText: 'Remote Upload Path (optional)',
                  hintText: 'Leave blank for root directory',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _ftpPassiveMode,
                    onChanged: (value) {
                      setState(() {
                        _ftpPassiveMode = value ?? true;
                      });
                    },
                  ),
                  const Expanded(
                    child: Text(
                      'Use Passive Mode',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Save Profile Section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Save as Profile',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: profileNameController,
                            decoration: const InputDecoration(
                              labelText: 'Profile Name',
                              hintText: 'e.g., Work Server, Home Server',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            // Profile saving handled by button click
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            final profileName =
                                profileNameController.text.trim();
                            if (profileName.isNotEmpty) {
                              _saveFtpProfile(
                                profileName,
                                host: hostController.text,
                                username: usernameController.text,
                                password: passwordController.text,
                                port: int.tryParse(portController.text) ?? 21,
                                remotePath: remotePathController.text,
                                passiveMode: _ftpPassiveMode,
                              );
                              Navigator.pop(context);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter a profile name'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.save),
                          label: const Text('Save Profile'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Files will be uploaded with the format: YYYY-MM-DD_001.jpg, 002.jpg, etc.\nLeave remote path blank to upload to root directory.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _ftpHost = hostController.text;
                _ftpUsername = usernameController.text;
                _ftpPassword = passwordController.text;
                _ftpPort = int.tryParse(portController.text) ?? 21;
                _ftpRemotePath = remotePathController.text;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('FTP settings saved!'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Helper methods for caption building
  String _month(int month) {
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

  String _formatDateline(
      String city, String stateOrProvince, String monthUpper, int day) {
    if (_isGameInUnitedStates()) {
      // US format: CITY, STATE - DATE
      return '${city.toUpperCase()}, ${stateOrProvince.toUpperCase()} - $monthUpper $day:';
    } else {
      // Canadian format: CITY, PROVINCE_ABBREVIATION - DATE
      final provAbbr = _abbr(stateOrProvince);
      return '${city.toUpperCase()}, $provAbbr - $monthUpper $day:';
    }
  }

  String _formatLocationSuffix(
      String city, String stateOrProvince, String formattedDate) {
    if (_isGameInUnitedStates()) {
      // US format: in City, State (no country needed)
      // Special case for Washington DC - keep DC capitalized
      final formattedState =
          stateOrProvince == 'DC' ? 'DC' : _capitalize(stateOrProvince);
      return 'in ${_capitalize(city)}, $formattedState';
    } else {
      // Canadian format: in City, Province, Canada
      return 'in ${_capitalize(city)}, ${_capitalize(stateOrProvince)}, Canada';
    }
  }

  bool _isGameInUnitedStates() {
    // Check if the province/state is a Canadian province
    final canadianProvinces = {
      'Ontario',
      'Quebec',
      'British Columbia',
      'Alberta',
      'Saskatchewan',
      'Manitoba',
      'New Brunswick',
      'Nova Scotia',
      'Prince Edward Island',
      'Newfoundland and Labrador',
      'Northwest Territories',
      'Nunavut',
      'Yukon'
    };

    return !canadianProvinces.contains(provinceController.text);
  }

  String _abbr(String province) {
    const abbreviations = {
      'Ontario': 'ON',
      'Quebec': 'QC',
      'British Columbia': 'BC',
      'Alberta': 'AB',
      'Manitoba': 'MB',
      'Saskatchewan': 'SK',
      'Nova Scotia': 'NS',
      'New Brunswick': 'NB',
      'Newfoundland and Labrador': 'NL',
      'Prince Edward Island': 'PE',
      'Northwest Territories': 'NT',
      'Nunavut': 'NU',
      'Yukon': 'YT',
    };
    return abbreviations[province] ?? province;
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    // Handle multi-word cities like "New York"
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  String _combinePlayersWithSingleTeam(List<String> players) {
    if (players.isEmpty) return '';

    // Get full player names
    final playerNames = players.toList();

    // Determine the team from the first player's selection context
    final isHomeTeamPlayer = selectedHomePlayers.contains(players.first);
    final teamName = isHomeTeamPlayer ? selectedHomeTeam : selectedAwayTeam;

    if (teamName == null) {
      // Fallback to just player names if team is not available
      if (playerNames.length == 1) {
        return playerNames.first;
      } else if (playerNames.length == 2) {
        return '${playerNames[0]} and ${playerNames[1]}';
      } else {
        final last = playerNames.removeLast();
        return '${playerNames.join(', ')}, and $last';
      }
    }

    if (playerNames.length == 1) {
      return '${playerNames.first} of the $teamName';
    } else if (playerNames.length == 2) {
      // Two players: "Player1 and Player2 of the team"
      return '${playerNames[0]} and ${playerNames[1]} of the $teamName';
    } else {
      // Three or more players: "Player1, Player2, and Player3 of the team"
      final last = playerNames.removeLast();
      return '${playerNames.join(', ')}, and $last of the $teamName';
    }
  }

  String _buildActionPhrase() {
    String baseAction = '';
    final verbToUse = _selectedActionVerb ?? _selectedVerb;
    if (verbToUse == null) return '';

    // Get the count of active players for plural/singular verb forms
    final activePlayerCount =
        selectedHomePlayers.length + selectedAwayPlayers.length;

    switch (verbToUse) {
      case 'Single':
        baseAction = 'single';
        break;
      case 'Double':
        baseAction = 'double';
        break;
      case 'Triple':
        baseAction = 'triple';
        break;
      case 'Home Run':
        baseAction = _buildHomeRunPhrase();
        break;
      case 'RBI Sacrifice Fly':
        baseAction = 'RBI sacrifice fly';
        break;
      case 'Strikeout':
        baseAction = 'strikeout';
        break;
      case 'Grand Slam':
        baseAction = 'grand slam';
        break;
      case 'At Bat':
        return 'takes an at bat in his batting stance against the ${_getOpposingTeamName()}';
      case 'Pitching':
        return 'delivers a pitch against the ${_getOpposingTeamName()}';
      case 'Swings':
        return 'swings against the ${_getOpposingTeamName()}';
      case 'Bunts':
        return 'bunts against the ${_getOpposingTeamName()}';
      case 'Hit by Pitch':
        // Check if opposing players are selected
        final opposingPlayers = _getOpposingPlayers();
        if (opposingPlayers.isNotEmpty) {
          final pitcherName = _formatPlayersWithTeam(opposingPlayers);
          return 'is hit by a pitch by $pitcherName';
        } else {
          final opposingTeam = _getOpposingTeamName();
          return 'gets hit by a pitch against the $opposingTeam';
        }
      case 'Walks':
        // Check if opposing players are selected
        final opposingPlayersWalks = _getOpposingPlayers();
        if (opposingPlayersWalks.isNotEmpty) {
          final pitcherName = _formatPlayersWithTeam(opposingPlayersWalks);
          return 'takes a walk against $pitcherName';
        } else {
          final opposingTeam = _getOpposingTeamName();
          return 'takes a walk against the $opposingTeam';
        }
      case 'Fielding Position':
        return 'takes fielding position against the ${_getOpposingTeamName()}';

      case 'Looks On':
        // Check if multiple players are selected
        final activePlayers = selectedHomePlayers.union(selectedAwayPlayers);
        final isMultiplePlayers = activePlayers.length > 1;

        if (_isPriorToGame) {
          return isMultiplePlayers ? 'look on' : 'looks on';
        } else {
          final action = isMultiplePlayers ? 'look on' : 'looks on';
          return '$action against the ${_getOpposingTeamName()}';
        }
      case 'Walks Off Field':
        return 'walks off the field against the ${_getOpposingTeamName()}';
      case 'Runs Off Field':
        return 'runs off the field against the ${_getOpposingTeamName()}';
      case 'Takes the Field':
        if (_isPriorToGame) {
          return 'takes the field';
        } else {
          return 'takes the field against the ${_getOpposingTeamName()}';
        }
      case 'Comes Off the Field':
        if (_isPriorToGame) {
          return 'comes off the field';
        } else {
          return 'comes off the field against the ${_getOpposingTeamName()}';
        }
      case 'National Anthem':
        // Check if multiple players are selected
        final activePlayers = selectedHomePlayers.union(selectedAwayPlayers);
        final isMultiplePlayers = activePlayers.length > 1;

        final action = isMultiplePlayers ? 'look on' : 'looks on';
        return '$action during the national anthem prior to play against the ${_getOpposingTeamName()}';
      case 'Stretching':
        // Check if multiple players are selected
        final activePlayersStretching =
            selectedHomePlayers.union(selectedAwayPlayers);
        final isMultiplePlayersStretching = activePlayersStretching.length > 1;

        final actionStretching =
            isMultiplePlayersStretching ? 'stretch' : 'stretches';
        return '$actionStretching prior to play against the ${_getOpposingTeamName()}';
      case 'Warm Ups':
        // Check if multiple players are selected
        final activePlayersWarmUps =
            selectedHomePlayers.union(selectedAwayPlayers);
        final isMultiplePlayersWarmUps = activePlayersWarmUps.length > 1;

        final actionWarmUps = isMultiplePlayersWarmUps
            ? 'take part in warm ups'
            : 'takes part in warm ups';
        return '$actionWarmUps prior to play against the ${_getOpposingTeamName()}';
      case 'Pitching Change':
        if (_managerName.isNotEmpty) {
          return 'pitcher taken out of the game by manager $_managerName during a break in play against the ${_getOpposingTeamName()}';
        } else {
          return 'pitcher taken out of the game during a break in play against the ${_getOpposingTeamName()}';
        }
      case 'Catches':
        if (_selectedFieldingAction == 'Diving Catch' || _isDivingCatch) {
          return 'makes a diving catch against the ${_getOpposingTeamName()}';
        } else {
          return 'catches a ball against the ${_getOpposingTeamName()}';
        }
      case 'Throws':
        return 'throws a ball against the ${_getOpposingTeamName()}';
      case 'Tags':
        if (_selectedTagsAction != null) {
          // Handle On the Base Path as a special case first
          if (_selectedTagsAction == 'Tags Runner Out at: On the Base Path') {
            final opposingTeam = _getOpposingTeamName();
            final secondPlayer = _getSecondPlayer();
            if (secondPlayer != null) {
              return 'tags $secondPlayer out on the base path against the $opposingTeam';
            } else {
              return 'tags a runner out on the base path against the $opposingTeam';
            }
          }

          // Parse the tags action to build proper caption
          final parts = _selectedTagsAction!.split(' - ');
          if (parts.length == 2) {
            final base = parts[0].replaceAll('Tags Runner Out at: ', '');
            final action = parts[1].toLowerCase();

            // Convert base to full word
            String fullBaseName;
            switch (base) {
              case '1st':
                fullBaseName = 'first base';
                break;
              case '2nd':
                fullBaseName = 'second base';
                break;
              case '3rd':
                fullBaseName = 'third base';
                break;
              case 'Home':
                fullBaseName = 'home plate';
                break;
              case 'On the Base Path':
                fullBaseName = 'on the base path';
                break;
              default:
                fullBaseName = base.toLowerCase();
            }

            // Get the second player (the one being tagged out)
            final secondPlayer = _getSecondPlayer();
            if (secondPlayer != null) {
              if (action == 'stealing') {
                return 'tags $secondPlayer out at $fullBaseName on a stealing attempt';
              } else if (action == 'pickoff') {
                return 'tags $secondPlayer out at $fullBaseName on a pickoff';
              } else if (action == 'attempting to advance') {
                return 'tags $secondPlayer out at $fullBaseName attempting to advance';
              } else if (action == 'attempting to score') {
                return 'tags $secondPlayer out at $fullBaseName attempting to score';
              } else if (fullBaseName == 'on the base path') {
                final opposingTeam = _getOpposingTeamName();
                return 'tags $secondPlayer out on the base path against the $opposingTeam';
              } else {
                return 'tags $secondPlayer out at $fullBaseName $action';
              }
            } else {
              if (action == 'stealing') {
                return 'tags a runner out at $fullBaseName on a stealing attempt';
              } else if (action == 'pickoff') {
                return 'tags a runner out at $fullBaseName on a pickoff';
              } else if (action == 'attempting to advance') {
                return 'tags a runner out at $fullBaseName attempting to advance';
              } else if (action == 'attempting to score') {
                return 'tags a runner out at $fullBaseName attempting to score';
              } else if (fullBaseName == 'on the base path') {
                final opposingTeam = _getOpposingTeamName();
                return 'tags a runner out on the base path against the $opposingTeam';
              } else {
                return 'tags a runner out at $fullBaseName $action';
              }
            }
          }
          return _selectedTagsAction!.toLowerCase();
        }
        return 'tags a player out of the ${_getOpposingTeamName()}';
      case 'Groundball':
        if (_isDivingCatch) {
          return 'dives for a groundball against the ${_getOpposingTeamName()}';
        } else {
          return 'fields a groundball against the ${_getOpposingTeamName()}';
        }
      case 'Double Play':
        // Check if opposing players are selected
        final opposingPlayers = _getOpposingPlayers();
        if (_selectedBase != null) {
          final baseName = _getFullBaseName(_selectedBase!);
          if (opposingPlayers.isNotEmpty) {
            final opponentName = _formatPlayersWithTeam(opposingPlayers);
            return 'turns a double play at $baseName against $opponentName';
          } else {
            final opposingTeam = _getOpposingTeamName();
            return 'turns a double play at $baseName against the $opposingTeam';
          }
        } else {
          if (opposingPlayers.isNotEmpty) {
            final opponentName = _formatPlayersWithTeam(opposingPlayers);
            return 'turns a double play against $opponentName';
          } else {
            final opposingTeam = _getOpposingTeamName();
            return 'turns a double play against the $opposingTeam';
          }
        }
      case 'Triple Play':
        // Check if opposing players are selected
        final opposingPlayers2 = _getOpposingPlayers();
        if (_selectedBase != null) {
          final baseName = _getFullBaseName(_selectedBase!);
          if (opposingPlayers2.isNotEmpty) {
            final opponentName = _formatPlayersWithTeam(opposingPlayers2);
            return 'turns a triple play at $baseName against $opponentName';
          } else {
            final opposingTeam = _getOpposingTeamName();
            return 'turns a triple play at $baseName against the $opposingTeam';
          }
        } else {
          if (opposingPlayers2.isNotEmpty) {
            final opponentName = _formatPlayersWithTeam(opposingPlayers2);
            return 'turns a triple play against $opponentName';
          } else {
            final opposingTeam = _getOpposingTeamName();
            return 'turns a triple play against the $opposingTeam';
          }
        }
      case 'Steals':
        if (_selectedBase != null) {
          final opposingPlayers = _getOpposingPlayers();
          if (_selectedBase == 'Tagged Out') {
            // Use the stored base that was selected before Tagged Out
            final baseName = _selectedBaseBeforeTaggedOut != null
                ? _getFullBaseName(_selectedBaseBeforeTaggedOut!)
                : 'a base';
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'is tagged out attempting to steal $baseName against $playerNames';
            } else {
              return 'is tagged out attempting to steal $baseName against the ${_getOpposingTeamName()}';
            }
          } else {
            final baseName = _getFullBaseName(_selectedBase!);
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'steals $baseName against $playerNames';
            } else {
              return 'steals $baseName against the ${_getOpposingTeamName()}';
            }
          }
        } else {
          final opposingPlayers = _getOpposingPlayers();
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return 'steals a base against $playerNames';
          } else {
            return 'steals a base against the ${_getOpposingTeamName()}';
          }
        }
      case 'Slides':
        if (_selectedBase != null) {
          final opposingPlayers = _getOpposingPlayers();
          if (_selectedBase == 'Tagged Out') {
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'gets tagged out sliding against $playerNames';
            } else {
              return 'gets tagged out sliding against the ${_getOpposingTeamName()}';
            }
          } else {
            final baseName = _getFullBaseName(_selectedBase!);
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'slides into $baseName against $playerNames';
            } else {
              return 'slides into $baseName against the ${_getOpposingTeamName()}';
            }
          }
        } else {
          final opposingPlayers = _getOpposingPlayers();
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return 'slides into a base against $playerNames';
          } else {
            return 'slides into a base against the ${_getOpposingTeamName()}';
          }
        }
      case 'Runs':
        if (_selectedBase != null) {
          final opposingPlayers = _getOpposingPlayers();
          if (_selectedBase == 'Tagged Out') {
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'gets tagged out running against $playerNames';
            } else {
              return 'gets tagged out running against the ${_getOpposingTeamName()}';
            }
          } else {
            final baseName = _getFullBaseName(_selectedBase!);
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'runs to $baseName against $playerNames';
            } else {
              return 'runs to $baseName against the ${_getOpposingTeamName()}';
            }
          }
        } else {
          final opposingPlayers = _getOpposingPlayers();
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return 'runs to a base against $playerNames';
          } else {
            return 'runs to a base against the ${_getOpposingTeamName()}';
          }
        }
      case 'Rounds':
        if (_selectedBase != null) {
          final opposingPlayers = _getOpposingPlayers();
          if (_selectedBase == 'Home') {
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'crosses home plate to score against $playerNames';
            } else {
              return 'crosses home plate to score against the ${_getOpposingTeamName()}';
            }
          } else if (_selectedBase == 'Tagged Out') {
            // Use the stored base that was selected before Tagged Out
            final baseName = _selectedBaseBeforeTaggedOut != null
                ? _getFullBaseName(_selectedBaseBeforeTaggedOut!)
                : 'a base';
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'is tagged out attempting to round $baseName against $playerNames';
            } else {
              return 'is tagged out attempting to round $baseName against the ${_getOpposingTeamName()}';
            }
          } else {
            final baseName = _getFullBaseName(_selectedBase!);
            if (opposingPlayers.isNotEmpty) {
              final playerNames = _formatPlayersWithTeam(opposingPlayers);
              return 'rounds $baseName against $playerNames';
            } else {
              return 'rounds $baseName against the ${_getOpposingTeamName()}';
            }
          }
        } else {
          final opposingPlayers = _getOpposingPlayers();
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return 'rounds a base against $playerNames';
          } else {
            return 'rounds a base against the ${_getOpposingTeamName()}';
          }
        }
      case 'Celebration':
      case 'Celebrates':
      case 'Celebrates With':
      case 'Celebrates Against':
        // Check if custom celebration text is provided
        if (customCelebrationController.text.isNotEmpty) {
          final opposingPlayers = _getOpposingPlayers();
          final opposingTeam = _getOpposingTeamName();

          // Use custom celebration text
          String customCelebration = customCelebrationController.text.trim();

          // Add teammates if there are multiple players
          Set<String> activePlayers;
          if (selectedAwayPlayers.isNotEmpty && selectedHomePlayers.isEmpty) {
            activePlayers = selectedAwayPlayers;
          } else if (selectedHomePlayers.isNotEmpty &&
              selectedAwayPlayers.isEmpty) {
            activePlayers = selectedHomePlayers;
          } else if (selectedHomePlayers.isNotEmpty &&
              selectedAwayPlayers.isNotEmpty) {
            activePlayers = (_firstTeamSelected == true)
                ? selectedHomePlayers
                : selectedAwayPlayers;
          } else {
            activePlayers = <String>{};
          }

          if (activePlayers.length > 1) {
            final teammates = _getTeammates();
            if (teammates.isNotEmpty) {
              final teammateWord =
                  teammates.length == 1 ? 'teammate' : 'teammates';
              customCelebration +=
                  ' with $teammateWord ${_formatPlayerNames(teammates)}';
            }
          }

          // Add opponent
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return '$customCelebration against $playerNames';
          } else {
            return '$customCelebration against the $opposingTeam';
          }
        }

        final opposingPlayers = _getOpposingPlayers();
        final opposingTeam = _getOpposingTeamName();

        // Build the celebration phrase - always use main player format when multiple players are selected
        // Determine the active players (same logic as in _updateCaption)
        Set<String> activePlayers;
        if (selectedAwayPlayers.isNotEmpty && selectedHomePlayers.isEmpty) {
          activePlayers = selectedAwayPlayers;
        } else if (selectedHomePlayers.isNotEmpty &&
            selectedAwayPlayers.isEmpty) {
          activePlayers = selectedHomePlayers;
        } else if (selectedHomePlayers.isNotEmpty &&
            selectedAwayPlayers.isNotEmpty) {
          // Use first team selected as main focus
          activePlayers = (_firstTeamSelected == true)
              ? selectedHomePlayers
              : selectedAwayPlayers;
        } else {
          activePlayers = <String>{};
        }

        // Always use singular "celebrates" since we're using main player format
        String celebrationPhrase = 'celebrates';

        // Add scoring if selected
        if (_isCelebratingScoring) {
          celebrationPhrase += ' scoring';
        }

        // Add teammates if there are multiple players (always format with teammates)
        if (activePlayers.length > 1) {
          final teammates = _getTeammates();
          if (teammates.isNotEmpty) {
            final teammateWord =
                teammates.length == 1 ? 'teammate' : 'teammates';
            celebrationPhrase +=
                ' with $teammateWord ${_formatPlayerNames(teammates)}';
          }
        }

        // Add opponent
        if (opposingPlayers.isNotEmpty) {
          final playerNames = _formatPlayersWithTeam(opposingPlayers);
          return '$celebrationPhrase against $playerNames';
        } else {
          return '$celebrationPhrase against the $opposingTeam';
        }
      case 'Dejection':
        // Check if custom dejection text is provided
        if (customDejectionController.text.isNotEmpty) {
          final opposingPlayers = _getOpposingPlayers();
          final opposingTeam = _getOpposingTeamName();

          // Use custom dejection text
          String customDejection = customDejectionController.text.trim();

          // Add opponent
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return '$customDejection against $playerNames';
          } else {
            return '$customDejection against the $opposingTeam';
          }
        }

        // Handle specific dejection types
        final opposingPlayers = _getOpposingPlayers();
        final opposingTeam = _getOpposingTeamName();

        if (_selectedDejectionType == 'Strikeout') {
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return 'reacts to striking out against $playerNames';
          } else {
            return 'reacts to striking out against the $opposingTeam';
          }
        } else if (_selectedDejectionType == 'Pitcher Taken Out') {
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return 'reacts to being taken out of the game against $playerNames';
          } else {
            return 'reacts to being taken out of the game against the $opposingTeam';
          }
        } else {
          // Default dejection
          if (opposingPlayers.isNotEmpty) {
            final playerNames = _formatPlayersWithTeam(opposingPlayers);
            return 'reacts with dejection against $playerNames';
          } else {
            return 'reacts with dejection against the $opposingTeam';
          }
        }
      case 'Post Game Win':
        final opposingTeam = _getOpposingTeamName();
        final activePlayerCount =
            selectedHomePlayers.length + selectedAwayPlayers.length;
        if (activePlayerCount > 1) {
          return 'celebrate after their team defeated the $opposingTeam';
        } else {
          return 'celebrates their team defeating the $opposingTeam';
        }
      case 'Post Game Loss':
        final opposingTeam2 = _getOpposingTeamName();
        final activePlayerCount2 =
            selectedHomePlayers.length + selectedAwayPlayers.length;
        if (activePlayerCount2 > 1) {
          return 'react to their team losing to the $opposingTeam2';
        } else {
          return 'reacts to their team losing to the $opposingTeam2';
        }
      case 'Stretches':
        if (activePlayerCount >= 2) {
          return 'stretch prior to playing the ${_getOpposingTeamName()}';
        } else {
          return 'stretches prior to playing the ${_getOpposingTeamName()}';
        }
      case 'Batting Practice':
        if (activePlayerCount >= 2) {
          return 'take batting practice prior to playing the ${_getOpposingTeamName()}';
        } else {
          return 'takes batting practice prior to playing the ${_getOpposingTeamName()}';
        }
      case 'Fielding Practice':
        if (activePlayerCount >= 2) {
          return 'take fielding practice prior to playing the ${_getOpposingTeamName()}';
        } else {
          return 'takes fielding practice prior to playing the ${_getOpposingTeamName()}';
        }
      case 'Warm Ups':
        if (activePlayerCount >= 2) {
          return 'take part in warm-ups prior to playing the ${_getOpposingTeamName()}';
        } else {
          return 'takes part in warm-ups prior to playing the ${_getOpposingTeamName()}';
        }
      case 'Walks On Field':
        if (activePlayerCount >= 2) {
          return 'walk on the field prior to playing the ${_getOpposingTeamName()}';
        } else {
          return 'walks on the field prior to playing the ${_getOpposingTeamName()}';
        }
      case 'Runs On Field':
        if (activePlayerCount >= 2) {
          return 'run on the field prior to playing the ${_getOpposingTeamName()}';
        } else {
          return 'runs on the field prior to playing the ${_getOpposingTeamName()}';
        }
      default:
        baseAction = verbToUse.toLowerCase();
    }

    // Build the hit phrase
    String hitPhrase = '';
    if (_rbiCount != null && _rbiCount! > 0) {
      final rbiText =
          _rbiCount == 1 ? 'RBI' : '${_numberToWord(_rbiCount!)}-RBI';
      hitPhrase = 'hits a $rbiText $baseAction';
    } else {
      hitPhrase = 'hits a $baseAction';
    }

    // Add celebration action if specified
    if (_selectedHittingAction != null) {
      switch (_selectedHittingAction!) {
        case 'celebrates':
        case 'celebrates_in_dugout':
          // Get teammates (other players from the same team as the main player)
          final teammates = _getTeammates();

          // For dugout celebration, if no teammates, don't include teammate phrase
          final teammatePhrase = (_selectedHittingAction ==
                      'celebrates_in_dugout' &&
                  teammates.isEmpty)
              ? ''
              : (teammates.isNotEmpty
                  ? ' with ${teammates.length == 1 ? 'teammate' : 'teammates'} ${_formatPlayerNames(teammates)}'
                  : '');

          // Include opposing players if selected, otherwise use opposing team
          final opposingPlayers = _getOpposingPlayers();
          final opposingTeam = _getOpposingTeamName();
          final againstPhrase = opposingPlayers.isNotEmpty
              ? ' against ${_formatPlayerNames(opposingPlayers)}${opposingTeam != null ? ' of the $opposingTeam' : ''}'
              : (opposingTeam != null ? ' against the $opposingTeam' : '');

          final celebrationType = 'celebrates';
          final dugoutPhrase = _selectedHittingAction == 'celebrates_in_dugout'
              ? ' in the dugout'
              : '';

          if (_rbiCount != null && _rbiCount! > 0) {
            final rbiText =
                _rbiCount == 1 ? 'RBI' : '${_numberToWord(_rbiCount!)}-RBI';
            return '$celebrationType a $rbiText $baseAction$dugoutPhrase$teammatePhrase$againstPhrase';
          } else {
            return '$celebrationType a $baseAction$dugoutPhrase$teammatePhrase$againstPhrase';
          }
        case 'runs_base_paths':
          return 'runs the base path on $baseAction';
        case 'runs to first base':
          return 'runs to first base on a $baseAction';
        case 'trots_the_bases':
          // Get opposing players if any are selected
          final opposingPlayers = _getOpposingPlayers();
          final opposingTeam = _getOpposingTeamName();

          if (opposingPlayers.isNotEmpty) {
            // If opposing players are selected, use "past [player names] of the [team]"
            final playerNames = _formatPlayerNames(opposingPlayers);
            final teamPhrase =
                opposingTeam != null ? ' of the $opposingTeam' : '';
            return 'trots the bases on his $baseAction past $playerNames$teamPhrase';
          } else if (opposingTeam != null) {
            // If no opposing players but team is available, use "against the [team]"
            return 'trots the bases on his $baseAction against the $opposingTeam';
          } else {
            // Fallback
            return 'trots the bases on his $baseAction';
          }
        case 'slides_into_base':
          final baseToSlideInto = _getBaseToSlideInto(baseAction);
          return 'slides into $baseToSlideInto on a $baseAction';
        default:
          return hitPhrase;
      }
    }

    return hitPhrase;
  }

  String _numberToWord(int number) {
    switch (number) {
      case 1:
        return 'one';
      case 2:
        return 'two';
      case 3:
        return 'three';
      case 4:
        return 'four';
      case 5:
        return 'five';
      case 6:
        return 'six';
      case 7:
        return 'seven';
      case 8:
        return 'eight';
      case 9:
        return 'nine';
      case 10:
        return 'ten';
      default:
        return number.toString();
    }
  }

  String _getBaseToSlideInto(String hitType) {
    switch (hitType) {
      case 'single':
        return 'first base';
      case 'double':
        return 'second base';
      case 'triple':
        return 'third base';
      case 'home run':
      case 'solo home run':
      case 'two-run home run':
      case 'three-run home run':
      case 'grand slam':
        return 'home plate';
      default:
        return 'base';
    }
  }

  List<String> _getTeammates() {
    // Get teammates (other players from the same team as the main player)
    if (_firstPlayerSelected == null) return [];

    // Determine which team the main player is from
    final isMainPlayerHome = selectedHomePlayers.contains(_firstPlayerSelected);

    // Get all players from the same team, excluding the main player
    final teammates = isMainPlayerHome
        ? selectedHomePlayers
            .where((player) => player != _firstPlayerSelected)
            .toList()
        : selectedAwayPlayers
            .where((player) => player != _firstPlayerSelected)
            .toList();

    return teammates;
  }

  String? _getOpposingTeamName() {
    // Get the opposing team name based on the main player's team
    if (_firstPlayerSelected == null) {
      // Fallback: if no main player is selected, use the first team logic
      if (selectedHomePlayers.isNotEmpty && selectedAwayPlayers.isEmpty) {
        return selectedAwayTeam;
      } else if (selectedAwayPlayers.isNotEmpty &&
          selectedHomePlayers.isEmpty) {
        return selectedHomeTeam;
      } else if (_firstTeamSelected == true) {
        return selectedAwayTeam;
      } else if (_firstTeamSelected == false) {
        return selectedHomeTeam;
      }
      return selectedAwayTeam; // Final fallback
    }

    // Determine which team the main player is from
    final isMainPlayerHome = selectedHomePlayers.contains(_firstPlayerSelected);

    // Return the opposing team name
    final opposingTeam = isMainPlayerHome ? selectedAwayTeam : selectedHomeTeam;
    final mainTeam = isMainPlayerHome ? selectedHomeTeam : selectedAwayTeam;

    // If the opposing team is the same as the main player's team,
    // we need to find a different team from the teams list
    if (opposingTeam == mainTeam || opposingTeam == null) {
      // Find a team from the list that's not the main team
      final alternativeTeam = teamsList.firstWhere(
        (team) => team != mainTeam,
        orElse: () => "the opposing team",
      );
      return alternativeTeam;
    }

    return opposingTeam;
  }

  String? _getSecondPlayer() {
    // Get all selected players
    final allPlayers = {...selectedHomePlayers, ...selectedAwayPlayers};

    // If we have exactly 2 players, return the second one (not the first selected)
    if (allPlayers.length == 2 && _firstPlayerSelected != null) {
      final secondPlayer = allPlayers.firstWhere(
        (player) => player != _firstPlayerSelected,
        orElse: () => _firstPlayerSelected!,
      );

      // Get the full player name and team
      final isSecondPlayerHome = selectedHomePlayers.contains(secondPlayer);
      final teamName = isSecondPlayerHome ? selectedHomeTeam : selectedAwayTeam;

      if (teamName != null) {
        return '$secondPlayer of the $teamName';
      } else {
        return secondPlayer;
      }
    }

    return null;
  }

  List<String> _getOpposingPlayers() {
    // Get opposing players based on the current caption logic
    // If home team is the main subject (active players), then away players are opposing
    // If away team is the main subject (active players), then home players are opposing

    // Determine which team is the main subject based on current logic
    bool isHomeTeamMainSubject;

    if (selectedAwayPlayers.isNotEmpty && selectedHomePlayers.isEmpty) {
      // Only away team players are selected - away team is main subject
      isHomeTeamMainSubject = false;
    } else if (selectedHomePlayers.isNotEmpty && selectedAwayPlayers.isEmpty) {
      // Only home team players are selected - home team is main subject
      isHomeTeamMainSubject = true;
    } else if (selectedHomePlayers.isNotEmpty &&
        selectedAwayPlayers.isNotEmpty) {
      // Both teams have players - use the first team selected as main subject
      isHomeTeamMainSubject = _firstTeamSelected == true;
    } else {
      // No players selected
      return [];
    }

    // Return the opposing team's players
    return isHomeTeamMainSubject
        ? selectedAwayPlayers.toList()
        : selectedHomePlayers.toList();
  }

  String _formatPlayerNames(List<String> players) {
    if (players.isEmpty) return '';
    if (players.length == 1) return players.first;
    if (players.length == 2) return '${players.first} and ${players.last}';

    // For 3+ players, use commas and "and"
    final allButLast = players.take(players.length - 1).join(', ');
    return '$allButLast and ${players.last}';
  }

  String _formatPlayersWithTeam(List<String> players) {
    if (players.isEmpty) return '';

    // Determine which team these players belong to
    final isHomeTeamPlayers = selectedHomePlayers.contains(players.first);
    final teamName = isHomeTeamPlayers ? selectedHomeTeam : selectedAwayTeam;

    if (teamName == null) {
      // Fallback to just player names if team is not available
      return _formatPlayerNames(players);
    }

    if (players.length == 1) {
      return '${players.first} of the $teamName';
    } else if (players.length == 2) {
      return '${players.first} and ${players.last} of the $teamName';
    } else {
      // For 3+ players, use commas and "and"
      final allButLast = players.take(players.length - 1).join(', ');
      return '$allButLast and ${players.last} of the $teamName';
    }
  }

  Widget _buildPlayerChipsHeader() {
    if (selectedHomePlayers.isEmpty && selectedAwayPlayers.isEmpty) {
      return Center(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _homeOnLeft = !_homeOnLeft;
              });
              _updateCaption();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Colors.grey.shade400,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Left icon (switches based on _homeOnLeft)
                  Icon(
                    _homeOnLeft ? Icons.home : Icons.flight,
                    size: 12,
                    color: Colors.black87,
                  ),
                  const SizedBox(width: 4),
                  // Arrow in the middle
                  Icon(
                    Icons.swap_horiz,
                    size: 16,
                    color: Colors.black87,
                  ),
                  const SizedBox(width: 4),
                  // Right icon (switches based on _homeOnLeft)
                  Icon(
                    _homeOnLeft ? Icons.flight : Icons.home,
                    size: 12,
                    color: Colors.black87,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        // Left side (Home or Away depending on _homeOnLeft)
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 2,
            alignment: _homeOnLeft ? WrapAlignment.start : WrapAlignment.end,
            children: _sortPlayersByNumber(
                    _homeOnLeft ? selectedHomePlayers : selectedAwayPlayers)
                .map((playerName) {
              final isFirstSelected = _isFirstSelectedPlayer(playerName);
              final isHomePlayer = selectedHomePlayers.contains(playerName);

              return Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isHomePlayer ? Colors.grey.shade700 : Colors.white,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: isHomePlayer
                        ? Colors.grey.shade700
                        : Colors.grey.shade400,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Star for first selected player
                    if (isFirstSelected) ...[
                      Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Icon(
                          Icons.star,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                    // Team icon
                    Icon(
                      isHomePlayer ? Icons.home : Icons.flight,
                      size: 10,
                      color: isHomePlayer ? Colors.white : Colors.black87,
                    ),
                    const SizedBox(width: 2),
                    // Player name
                    Text(
                      _formatChipName(playerName),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: isHomePlayer ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // X button to remove player
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          // Check if this is the first selected player (main player)
                          final isMainPlayer =
                              _isFirstSelectedPlayer(playerName);

                          if (isHomePlayer) {
                            selectedHomePlayers.remove(playerName);
                          } else {
                            selectedAwayPlayers.remove(playerName);
                          }

                          // If removing the main player, reset everything
                          if (isMainPlayer) {
                            _resetCaption();
                            return;
                          }
                        });
                        _updateCaption();
                        _updatePersonalityField();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: isHomePlayer
                              ? Colors.white.withOpacity(0.3)
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.close,
                          size: 8,
                          color: isHomePlayer ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(width: 8),

        // Right side (Away or Home depending on _homeOnLeft)
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 2,
            alignment: _homeOnLeft ? WrapAlignment.end : WrapAlignment.start,
            children: _sortPlayersByNumber(
                    _homeOnLeft ? selectedAwayPlayers : selectedHomePlayers)
                .map((playerName) {
              final isFirstSelected = _isFirstSelectedPlayer(playerName);
              final isHomePlayer = selectedHomePlayers.contains(playerName);

              return Container(
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isHomePlayer ? Colors.grey.shade700 : Colors.white,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: isHomePlayer
                        ? Colors.grey.shade700
                        : Colors.grey.shade400,
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Star for first selected player
                    if (isFirstSelected) ...[
                      Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Icon(
                          Icons.star,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                    // Team icon
                    Icon(
                      isHomePlayer ? Icons.home : Icons.flight,
                      size: 10,
                      color: isHomePlayer ? Colors.white : Colors.black87,
                    ),
                    const SizedBox(width: 2),
                    // Player name
                    Text(
                      _formatChipName(playerName),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: isHomePlayer ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // X button to remove player
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          // Check if this is the first selected player (main player)
                          final isMainPlayer =
                              _isFirstSelectedPlayer(playerName);

                          if (isHomePlayer) {
                            selectedHomePlayers.remove(playerName);
                          } else {
                            selectedAwayPlayers.remove(playerName);
                          }

                          // If removing the main player, reset everything
                          if (isMainPlayer) {
                            _resetCaption();
                            return;
                          }
                        });
                        _updateCaption();
                        _updatePersonalityField();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: isHomePlayer
                              ? Colors.white.withOpacity(0.3)
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.close,
                          size: 8,
                          color: isHomePlayer ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  bool _isFirstSelectedPlayer(String playerName) {
    // Check if this player was the first one selected
    if (_firstPlayerSelected == null) return false;

    final isFirst = _firstPlayerSelected == playerName;

    return isFirst;
  }

  Widget _buildHomeRunSubOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Magic bar (always visible)
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: [
              // Text field
              TextField(
                controller: customBetweenPlayersController,
                enabled:
                    !_waitingForHomeVisitorChoice, // Disable when waiting for choice
                cursorWidth: 1.5,
                cursorHeight: 16,
                style: const TextStyle(fontSize: 12, height: 2.3),
                decoration: InputDecoration(
                  hintText: _waitingForHomeVisitorChoice
                      ? '🏠 Type H for Home or 🚍 V for Visitor 🏠'
                      : _isPlayerSearchMode
                          ? 'Magic Bar: Type player numbers (e.g., 75, 23) or magic input (e.g., "27 hr 1")...'
                          : 'Magic Bar: Type custom action...',
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  isDense: true,
                ),
                onChanged: (value) {
                  // Debug output
                  print('DEBUG: Magic bar onChanged: "$value"');
                  print('DEBUG: _isMagicInput: ${_isMagicInput(value)}');
                  print(
                      'DEBUG: _waitingForHomeVisitorChoice: $_waitingForHomeVisitorChoice');

                  // If magic bar is completely cleared, reset everything
                  if (value.isEmpty) {
                    _resetCaption();
                    return;
                  }

                  // If we're waiting for home/visitor choice, ignore all input
                  // The dialog will handle the choice selection
                  if (_waitingForHomeVisitorChoice) {
                    print(
                        'DEBUG: Ignoring input while waiting for dialog choice: "$value"');
                    // Restore the original text if it was changed
                    final expectedText =
                        '${_magicInputMatchingPlayers.first.jerseyNumber} ${_magicInputActionText}';
                    if (value != expectedText) {
                      print('DEBUG: Restoring original text: "$expectedText"');
                      Future.microtask(() {
                        customBetweenPlayersController.text = expectedText;
                        customBetweenPlayersController.selection =
                            TextSelection.fromPosition(
                          TextPosition(offset: expectedText.length),
                        );
                      });
                    }
                    return;
                  }

                  // Check for magic input format (e.g., "27 hr 1")
                  if (_isMagicInput(value)) {
                    print('DEBUG: Processing magic input: "$value"');
                    _parseMagicInput(value);
                    return; // Return to prevent additional setState calls
                  }

                  setState(() {
                    if (_isPlayerSearchMode && _isNumeric(value)) {
                      _filterPlayersByNumber(value);
                    } else if (_isPlayerSearchMode && value.isEmpty) {
                      _filteredPlayers.clear();
                    } else if (!_isPlayerSearchMode) {
                      _showCustomTextInningSelector = value.isNotEmpty;
                      _updateCaption();
                    }
                  });
                },
              ),

              // Magic input player selection overlay
              if (_showMagicInputPlayerOptions)
                Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors
                          .yellow.shade100, // Bright background for debugging
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue.shade300, width: 2),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          child: Row(
                            children: [
                              Icon(Icons.help_outline,
                                  size: 16, color: Colors.blue.shade600),
                              const SizedBox(width: 8),
                              Text(
                                'Multiple players found - select one:',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ..._magicInputMatchingPlayers.map(
                          (player) => GestureDetector(
                            onTap: () => _selectMagicInputPlayer(player),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: Row(
                                children: [
                                  Text(
                                    '#${player.jerseyNumber}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _getTeamAbbreviation(_isHomePlayer(player)
                                            ? selectedHomeTeam ?? ''
                                            : selectedAwayTeam ?? '') ??
                                        '',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey.shade600),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(
                                    _isHomePlayer(player)
                                        ? Icons.home
                                        : Icons.flight,
                                    size: 10,
                                    color: _isHomePlayer(player)
                                        ? Colors.blue.shade600
                                        : Colors.red.shade600,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _removeJerseyNumberFromName(
                                          player.displayName ?? 'Unknown'),
                                      style: const TextStyle(fontSize: 10),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Player selection overlay
              if (_filteredPlayers.isNotEmpty || _noPlayersFound)
                Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_noPlayersFound)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline,
                                    size: 16, color: Colors.orange.shade600),
                                const SizedBox(width: 8),
                                Text(
                                  'No player with number ${_playerSearchText}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else ...[
                          ..._filteredPlayers.map(
                            (player) => GestureDetector(
                              onTap: () => _selectPlayer(player),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: Row(
                                  children: [
                                    Text(
                                      '#${player.jerseyNumber}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _getTeamAbbreviation(_isHomePlayer(player)
                                              ? selectedHomeTeam ?? ''
                                              : selectedAwayTeam ?? '') ??
                                          '',
                                      style: TextStyle(
                                          fontSize: 9,
                                          color: Colors.grey.shade600),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      _isHomePlayer(player)
                                          ? Icons.home
                                          : Icons.flight,
                                      size: 10,
                                      color: _isHomePlayer(player)
                                          ? Colors.blue.shade600
                                          : Colors.red.shade600,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        _removeJerseyNumberFromName(
                                            player.displayName ?? 'Unknown'),
                                        style: const TextStyle(fontSize: 10),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (_selectedPlayerNumbers.isNotEmpty)
                          GestureDetector(
                            onTap: _finishPlayerSelection,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                border: Border(
                                    top: BorderSide(
                                        color: Colors.grey.shade200)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check,
                                      size: 16, color: Colors.blue.shade700),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Done selecting players (${_selectedPlayerNumbers.length})',
                                    style: TextStyle(
                                        color: Colors.blue.shade700,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              // Inning selector
              if (_showCustomTextInningSelector)
                Container(
                  height: 80,
                  child: _buildCustomTextInningSelector(),
                ),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // Selected home run type indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedHomeRunType ?? 'Home Run',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Action options
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Home Run Type section with buttons
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                    child: const Text(
                      'Home Run Type',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                    child: Wrap(
                      spacing: 2,
                      runSpacing: 2,
                      children: ['Solo', 'Two-Run', 'Three-Run', 'Grand Slam']
                          .map((hrType) {
                        final isSelected = _selectedHomeRunType == hrType;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedHomeRunType =
                                  _selectedHomeRunType == hrType
                                      ? null
                                      : hrType;
                            });
                            _updateCaption();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.grey.shade300
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: Colors.grey.shade300,
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              hrType,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Options section
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                    child: const Text(
                      'Options',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                  ),

                  // Celebrates option
                  _buildSubOption('Celebrates', 'celebrates'),

                  // Celebrates in dugout option
                  _buildSubOption(
                      'Celebrates in Dugout', 'celebrates_in_dugout'),

                  // Trots the bases option
                  _buildSubOption('Trots the Bases', 'trots_the_bases'),
                ],
              ),

              const SizedBox(height: 8),

              // Inning section with reusable widget
              SizedBox(
                height: 100, // Increased height to accommodate Prior button
                child: _buildReusableInningSelector(),
              ),

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAtBatSubOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected action indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? 'At Bat',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Inning section with buttons
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Innings',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    // Back arrow for extra innings
                    if (_showExtraInnings)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            if (_extraInningsPage > 0) {
                              _extraInningsPage--;
                            } else {
                              // Go back to regular innings
                              _showExtraInnings = false;
                              _extraInningsPage = 0;
                              _selectedRbiInning = null;
                            }
                          });
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '←',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ),
                    // Innings (regular or extra based on state)
                    ...(_showExtraInnings
                            ? _getExtraInningsForPage()
                            : List.generate(9, (index) => index + 1))
                        .map((inning) {
                      final isSelected = _selectedRbiInning == inning;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedRbiInning =
                                _selectedRbiInning == inning ? null : inning;
                          });
                          _updateCaption();
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.grey.shade300
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '$inning',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      );
                    }),
                    // EXT button that cycles through extra innings
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_showExtraInnings) {
                            // If already showing extra innings, go to next page
                            if (_extraInningsPage < 3) {
                              _extraInningsPage++;
                            } else {
                              // Go back to regular innings
                              _showExtraInnings = false;
                              _extraInningsPage = 0;
                              _selectedRbiInning = null;
                            }
                          } else {
                            // Start showing extra innings
                            _showExtraInnings = true;
                            _extraInningsPage = 0;
                            _selectedRbiInning = null;
                          }
                        });
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _showExtraInnings
                              ? Colors.grey.shade300
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: Colors.grey.shade300,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          'XTRA',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTagsSubOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected tags action indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedTagsAction ?? 'Tags',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Action options
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // All tag options listed vertically
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1st Base options
                      _buildTagOptionWithChevron(
                          '1st Base', ['Pickoff', 'Stealing']),

                      // 2nd Base options
                      _buildTagOptionWithChevron('2nd Base', [
                        'Pickoff',
                        'Stealing',
                        'Attempting to Stretch a Single',
                        'Attempting to Tag Up',
                        'Attempting to Advance'
                      ]),

                      // 3rd Base options
                      _buildTagOptionWithChevron('3rd Base', [
                        'Pickoff',
                        'Stealing',
                        'Attempting to Stretch a Double',
                        'Attempting to Tag Up',
                        'Attempting to Advance'
                      ]),

                      // Home Base options
                      _buildTagOptionWithChevron('Home Plate', [
                        'Stealing',
                        'Attempting to Stretch a Triple',
                        'Attempting to Tag Up',
                        'Attempting to Score'
                      ]),

                      // On the Base Path (direct selection)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            final isSelected = _selectedTagsAction ==
                                'Tags Runner Out at: On the Base Path';
                            _selectedTagsAction = isSelected
                                ? null
                                : 'Tags Runner Out at: On the Base Path';
                            _selectedBase = null;
                          });
                          _updateCaption();
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          margin: const EdgeInsets.only(bottom: 2),
                          decoration: BoxDecoration(
                            color: _selectedTagsAction ==
                                    'Tags Runner Out at: On the Base Path'
                                ? Colors.grey.shade300
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'On the Base Path',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                const SizedBox(height: 8),

                // Inning selection section using reusable widget
                SizedBox(
                  height: 100, // Increased height to accommodate Prior button
                  child: _buildReusableInningSelector(),
                ),

                // Back button
                _buildVerbOptionsBackButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showBaseOptions(String base) {
    setState(() {
      _selectedBase = base;
      _selectedTagsAction = null; // Clear any previous selection
    });
  }

  Widget _buildTagOptionWithChevron(String baseName, List<String> options) {
    final isExpanded = _selectedBase ==
        baseName.replaceAll(' Base', '').replaceAll(' Plate', '');
    final hasSelection = _selectedTagsAction != null &&
        _selectedTagsAction!.startsWith(
            'Tags Runner Out at: ${baseName.replaceAll(' Base', '').replaceAll(' Plate', '')}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _selectedBase = null;
                _selectedTagsAction = null;
              } else {
                _selectedBase =
                    baseName.replaceAll(' Base', '').replaceAll(' Plate', '');
                _selectedTagsAction = null;
              }
            });
            _updateCaption();
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: (isExpanded || hasSelection)
                  ? Colors.grey.shade300
                  : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: Colors.grey.shade300,
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    baseName,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
              ],
            ),
          ),
        ),

        // Show options when expanded
        if (isExpanded) ...[
          Container(
            margin: const EdgeInsets.only(left: 12, right: 8, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: options.map((option) {
                final tagAction =
                    'Tags Runner Out at: ${baseName.replaceAll(' Base', '').replaceAll(' Plate', '')} - $option';
                final isSelected = _selectedTagsAction == tagAction;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedTagsAction = isSelected ? null : tagAction;
                    });
                    _updateCaption();
                  },
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(bottom: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.grey.shade200
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: Colors.grey.shade200,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      option,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBaseOptions() {
    if (_selectedBase == null) return const SizedBox.shrink();

    List<String> options = [];

    switch (_selectedBase) {
      case '1st':
        options = ['Pickoff'];
        break;
      case '2nd':
        options = [
          'Pickoff',
          'Stealing',
          'Attempting to Stretch a Single',
          'Attempting to Tag Up',
          'Attempting to Advance'
        ];
        break;
      case '3rd':
        options = [
          'Pickoff',
          'Stealing',
          'Attempting to Stretch a Double',
          'Attempting to Tag Up',
          'Attempting to Advance'
        ];
        break;
      case 'Home':
        options = [
          'Stealing',
          'Attempting to Stretch a Triple',
          'Attempting to Tag Up',
          'Attempting to Score'
        ];
        break;
      case 'On the Base Path':
        options = [];
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
          child: Text(
            '$_selectedBase Base Options',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
          child: Wrap(
            spacing: 2,
            runSpacing: 2,
            children: options.map((option) {
              final tagAction = 'Tags Runner Out at: $_selectedBase - $option';
              final isSelected = _selectedTagsAction == tagAction;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedTagsAction = isSelected ? null : tagAction;
                  });
                  _updateCaption();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        isSelected ? Colors.grey.shade300 : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: Colors.grey.shade300,
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    option,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildAtBatInterface() {
    return Stack(
      children: [
        // Background with greyed out verb categories
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Offense, Defense, Running (greyed out)
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  Expanded(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.3,
                        child: _buildVerbCategory('Offense', [
                          'Single',
                          'Double',
                          'Triple',
                          'Home Run',
                          'At Bat',
                          'Swings'
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 1),
                  Expanded(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.3,
                        child: _buildVerbCategory('Defense', [
                          'Pitching',
                          'Catches',
                          'Throws',
                          'Tags',
                          'Groundball',
                          'Fielding Position'
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 1),
                  Expanded(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.3,
                        child: _buildVerbCategory(
                            'Running', ['Steals', 'Slides', 'Runs', 'Rounds']),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // Bottom row: Reactions and Non Game-Action
            Expanded(
              flex: 1,
              child: Row(
                children: [
                  Expanded(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.3,
                        child: _buildVerbCategory('Reactions', [
                          'Celebrates',
                          'Dejection',
                          'Post Game Win',
                          'Post Game Loss',
                          '',
                          '',
                          ''
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 1),
                  Expanded(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.3,
                        child: _buildVerbCategory('Non Game-Action', [
                          'Looks On',
                          'Batting Practice',
                          'Fielding Practice',
                          'Takes the Field',
                          'Comes Off the Field',
                          'National Anthem',
                          'Stretching',
                          'Warm Ups',
                          'Pitching Change'
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 1),
                  const Expanded(child: SizedBox()), // Empty space
                ],
              ),
            ),
          ],
        ),

        // Click outside to close overlay
        Positioned.fill(
          child: GestureDetector(
            onTap: () {
              // Close when clicking outside the overlay
              setState(() {
                _selectedVerb = null;
                _selectedRbiInning = null;
              });
            },
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),

        // Inning picker overlay
        Positioned(
          top: 80, // Adjust this to position over the At Bat button
          left: 20, // Adjust this to position over the At Bat button
          child: GestureDetector(
            onTap: () {
              // Prevent closing when clicking inside the overlay
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: SizedBox(
                width: 300, // Adjust width as needed
                height: 200, // Adjust height as needed
                child: _buildReusableInningSelector(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _buildHomeRunPhrase() {
    if (_selectedHomeRunType == null) return 'home run';

    switch (_selectedHomeRunType!) {
      case 'Solo':
        return 'solo home run';
      case 'Two-Run':
        return 'two-run home run';
      case 'Three-Run':
        return 'three-run home run';
      case 'Grand Slam':
        return 'grand slam home run';
      default:
        return 'home run';
    }
  }

  Widget _buildSacrificeFlySubOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected hit type indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Action options
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Inning section with reusable widget
              SizedBox(
                height: 100, // Increased height to accommodate Prior button
                child: _buildReusableInningSelector(),
              ),

              // Options header
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Options',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              // Celebrates option
              _buildSubOption('Celebrates', 'celebrates'),

              // Runs to first base option
              _buildSubOption('Runs to First Base', 'runs to first base'),

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHittingSubOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected hit type indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Action options
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // RBI section with buttons
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                    child: const Text(
                      'RBI',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                    child: Wrap(
                      spacing: 2,
                      runSpacing: 2,
                      children: [1, 2, 3].map((rbi) {
                        final isSelected = _rbiCount == rbi;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _rbiCount = _rbiCount == rbi ? null : rbi;
                            });
                            _updateCaption();
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.grey.shade300
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: Colors.grey.shade300,
                                width: 0.5,
                              ),
                            ),
                            child: Text(
                              '$rbi',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Inning section with reusable widget
              SizedBox(
                height: 100, // Increased height to accommodate Prior button
                child: _buildReusableInningSelector(),
              ),

              // Options header
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Options',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),

              // Celebrates option
              _buildSubOption('Celebrates', 'celebrates'),

              // Runs the base paths option
              _buildSubOption('Runs the Base Paths', 'runs_base_paths'),

              // Slides into base option (not for Single)
              if (_selectedVerb != 'Single')
                _buildSubOption('Slides into Base', 'slides_into_base'),

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubOption(String label, String action) {
    final isSelected = _selectedHittingAction == action;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedHittingAction = null;
          } else {
            _selectedHittingAction = action;
          }
        });
        _updateCaption();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        margin: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: [
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color:
                      isSelected ? Colors.grey.shade300 : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: Colors.grey.shade300,
                    width: 0.5,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? Colors.grey.shade800
                        : Colors.grey.shade700,
                  ),
                ),
              ),
            ),
            const Expanded(flex: 1, child: SizedBox()),
          ],
        ),
      ),
    );
  }

  List<int> _getExtraInningsForPage() {
    if (_extraInningsPage == 0) {
      return [10, 11, 12, 13, 14, 15, 16];
    } else if (_extraInningsPage == 1) {
      return [17, 18, 19, 20, 21, 22, 23];
    } else if (_extraInningsPage == 2) {
      return [24, 25, 26, 27, 28, 29, 30];
    } else {
      return [24, 25, 26, 27, 28, 29, 30];
    }
  }

  String _formatChipName(String playerName) {
    // Extract jersey number
    final numberMatch = RegExp(r'#(\d+)').firstMatch(playerName);
    final number = numberMatch?.group(1) ?? '';

    // Remove jersey number from name for processing
    final nameWithoutNumber = playerName.replaceAll(RegExp(r'\s*#\d+'), '');

    // Split by spaces and get everything after first name
    final nameParts = nameWithoutNumber.split(' ');
    if (nameParts.length > 1) {
      final lastName = nameParts.skip(1).join(' ');
      return '#$number $lastName';
    }

    // Fallback if no last name found
    return playerName;
  }

  // Extract jersey number from player name for sorting
  int _extractJerseyNumber(String playerName) {
    // Try to match jersey number at the end of the string
    final nameMatch = RegExp(r'#(\d+)$').firstMatch(playerName);
    if (nameMatch != null) {
      final number = int.tryParse(nameMatch.group(1) ?? '0') ?? 0;
      return number;
    }
    return 999; // Return high number for players without numbers to put them at end
  }

  // Sort players by jersey number
  List<String> _sortPlayersByNumber(Set<String> players) {
    if (players.isEmpty) return [];

    final sortedPlayers = players.toList();
    sortedPlayers.sort((a, b) {
      final numberA = _extractJerseyNumber(a);
      final numberB = _extractJerseyNumber(b);
      return numberA.compareTo(numberB);
    });

    return sortedPlayers;
  }

  // Sort Player objects by different criteria
  List<Player> _sortPlayerObjects(
      List<Player> players, String sortOption, bool ascending) {
    if (players.isEmpty) return [];

    final sortedPlayers = List<Player>.from(players);

    switch (sortOption) {
      case 'number':
        sortedPlayers.sort((a, b) {
          final numberA = int.tryParse(a.jerseyNumber ?? '999') ?? 999;
          final numberB = int.tryParse(b.jerseyNumber ?? '999') ?? 999;
          return ascending
              ? numberA.compareTo(numberB)
              : numberB.compareTo(numberA);
        });
        break;
      case 'lastName':
        sortedPlayers.sort((a, b) {
          final lastNameA = _extractLastName(a.displayName ?? '');
          final lastNameB = _extractLastName(b.displayName ?? '');
          return ascending
              ? lastNameA.compareTo(lastNameB)
              : lastNameB.compareTo(lastNameA);
        });
        break;
      case 'firstName':
        sortedPlayers.sort((a, b) {
          final firstNameA = _extractFirstName(a.displayName ?? '');
          final firstNameB = _extractFirstName(b.displayName ?? '');
          return ascending
              ? firstNameA.compareTo(firstNameB)
              : firstNameB.compareTo(firstNameA);
        });
        break;
    }

    return sortedPlayers;
  }

  // Extract last name from display name (e.g., "John Smith #23" -> "Smith")
  String _extractLastName(String displayName) {
    final parts = displayName.split(' ');
    if (parts.length >= 2) {
      // Remove jersey number if present
      final nameParts = parts.where((part) => !part.startsWith('#')).toList();
      return nameParts.isNotEmpty ? nameParts.last : displayName;
    }
    return displayName;
  }

  // Extract first name from display name (e.g., "John Smith #23" -> "John")
  String _extractFirstName(String displayName) {
    final parts = displayName.split(' ');
    if (parts.length >= 2) {
      // Remove jersey number if present
      final nameParts = parts.where((part) => !part.startsWith('#')).toList();
      return nameParts.isNotEmpty ? nameParts.first : displayName;
    }
    return displayName;
  }

  // Get appropriate icon widget for current sort option
  Widget _getSortIconWidget(String sortOption) {
    switch (sortOption) {
      case 'number':
        return Icon(
          Icons.numbers,
          size: 12,
          color: Colors.grey.shade600,
        );
      case 'lastName':
        return Text(
          'ZA',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
          ),
        );
      case 'firstName':
        return Text(
          'AZ',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
          ),
        );
      default:
        return Icon(
          Icons.sort,
          size: 12,
          color: Colors.grey.shade600,
        );
    }
  }

  // Get sort text for button display
  String _getSortText(String sortOption) {
    switch (sortOption) {
      case 'number':
        return 'Number';
      case 'lastName':
        return 'Last Name';
      case 'firstName':
        return 'First Name';
      default:
        return 'Number';
    }
  }

  // Format player name based on current sort option
  String _getFormattedPlayerName(String displayName, String sortOption) {
    final parts = displayName.split(' ');
    final jerseyNumber = parts.last.startsWith('#') ? parts.last : '';
    final nameParts = parts.where((part) => !part.startsWith('#')).toList();

    if (sortOption == 'number') {
      // Extract jersey number and put it at the beginning
      final nameWithoutNumber = nameParts.join(' ');

      if (jerseyNumber.isNotEmpty) {
        return '$jerseyNumber $nameWithoutNumber';
      }
    } else if (sortOption == 'lastName' && nameParts.length >= 2) {
      // Format as "Last Name, First Name #"
      final firstName = nameParts.first;
      final lastName = nameParts.last;

      if (jerseyNumber.isNotEmpty) {
        return '$lastName, $firstName $jerseyNumber';
      } else {
        return '$lastName, $firstName';
      }
    }
    // For other sort options, return original format
    return displayName;
  }

  // Helper functions for smart text field
  bool _isNumeric(String text) {
    return text.isNotEmpty && int.tryParse(text) != null;
  }

  void _filterPlayersByNumber(String number) {
    // Debug output
    print('DEBUG: Searching for player #$number');
    print('DEBUG: Home roster count: ${_homeRoster.length}');
    print('DEBUG: Away roster count: ${_awayRoster.length}');

    // Count players with jersey numbers
    int homeWithNumbers = 0;
    int awayWithNumbers = 0;
    for (Player player in _homeRoster) {
      if (player.jerseyNumber != null && player.jerseyNumber!.isNotEmpty) {
        homeWithNumbers++;
      }
    }
    for (Player player in _awayRoster) {
      if (player.jerseyNumber != null && player.jerseyNumber!.isNotEmpty) {
        awayWithNumbers++;
      }
    }
    print('DEBUG: Home players with jersey numbers: $homeWithNumbers');
    print('DEBUG: Away players with jersey numbers: $awayWithNumbers');

    setState(() {
      _playerSearchText = number;
      _filteredPlayers = [];
      _noPlayersFound = false;

      // Search in both home and away rosters for exact matches only
      for (Player player in _homeRoster) {
        if (player.jerseyNumber == number) {
          _filteredPlayers.add(player);
          print(
              'DEBUG: Found player in home roster: ${player.fullName} #${player.jerseyNumber}');
        }
      }
      for (Player player in _awayRoster) {
        if (player.jerseyNumber == number) {
          _filteredPlayers.add(player);
          print(
              'DEBUG: Found player in away roster: ${player.fullName} #${player.jerseyNumber}');
        }
      }

      // Set flag if no players found
      if (_filteredPlayers.isEmpty) {
        _noPlayersFound = true;
        print('DEBUG: No players found with number $number');

        // Show some sample players for debugging
        print('DEBUG: Sample home players:');
        for (int i = 0; i < _homeRoster.length.clamp(0, 3); i++) {
          final player = _homeRoster[i];
          print('DEBUG: - ${player.fullName} #${player.jerseyNumber ?? "N/A"}');
        }
        print('DEBUG: Sample away players:');
        for (int i = 0; i < _awayRoster.length.clamp(0, 3); i++) {
          final player = _awayRoster[i];
          print('DEBUG: - ${player.fullName} #${player.jerseyNumber ?? "N/A"}');
        }
      } else {
        print(
            'DEBUG: Found ${_filteredPlayers.length} players with number $number');
      }
    });
  }

  void _selectPlayer(Player player) {
    setState(() {
      if (player.jerseyNumber != null) {
        _selectedPlayerNumbers.add(player.jerseyNumber!);
      }

      // Add player to the appropriate team's selected players
      final playerName = player.displayName ?? 'Unknown';
      final cleanedPlayerName = _removeJerseyNumberFromName(playerName);

      if (_isHomePlayer(player)) {
        selectedHomePlayers
            .add(playerName); // Use original display name for side lists
        // Set as first player selected if none selected yet
        if (_firstPlayerSelected == null) {
          _firstPlayerSelected =
              cleanedPlayerName; // Use cleaned name for caption
          // print(
          //     'DEBUG: First player selected from overlay: $cleanedPlayerName');
        }
      } else {
        selectedAwayPlayers
            .add(playerName); // Use original display name for side lists
        // Set as first player selected if none selected yet
        if (_firstPlayerSelected == null) {
          _firstPlayerSelected =
              cleanedPlayerName; // Use cleaned name for caption
          // print(
          //     'DEBUG: First player selected from overlay: $cleanedPlayerName');
        }
      }

      _playerSearchText = '';
      customBetweenPlayersController.clear();
      _filteredPlayers.clear();
    });

    // Update caption when player is selected from Magic Bar
    _updateCaption();
  }

  void _finishPlayerSelection() {
    setState(() {
      _isPlayerSearchMode = false;
      customBetweenPlayersController.text = '';
    });
  }

  void _resetSmartTextField() {
    setState(() {
      _isPlayerSearchMode = true;
      _filteredPlayers.clear();
      _selectedPlayerNumbers.clear();
      _playerSearchText = '';
      customBetweenPlayersController.clear();
    });
  }

  bool _isHomePlayer(Player player) {
    return _homeRoster.contains(player);
  }

  String _removeJerseyNumberFromName(String playerName) {
    // Remove jersey number patterns like "#23" or " #23" from the end of the name
    return playerName.replaceAll(RegExp(r'\s*#\d+\s*$'), '').trim();
  }

  // Reusable back button widget
  Widget _buildCustomTextInningSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          // Innings 1-9
          Expanded(
            child: Row(
              children: List.generate(9, (index) {
                final inning = index + 1;
                final isSelected = _selectedCustomTextInning == inning;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedCustomTextInning = inning;
                        _updateCaption();
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.blue.shade100
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(
                          color: isSelected
                              ? Colors.blue.shade300
                              : Colors.grey.shade300,
                          width: 0.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$inning',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? Colors.blue.shade700
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          // Navigation and extras row
          Expanded(
            child: Row(
              children: [
                // Clear button
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedCustomTextInning = null;
                        _updateCaption();
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(2),
                        border:
                            Border.all(color: Colors.grey.shade300, width: 0.5),
                      ),
                      child: Center(
                        child: Text(
                          'Clear',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactActionButtons() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          // Reset button (aligned to left)
          CustomButton(
            onTap: _resetCaption,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.refresh, size: 12, color: Colors.grey.shade700),
                  const SizedBox(width: 2),
                  Text('Reset',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Settings button
          CustomButton(
            onTap: _showFtpSettings,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF4A90E2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF4A90E2)),
              ),
              child: Icon(Icons.settings, size: 14, color: Colors.white),
            ),
          ),
          const SizedBox(width: 4),
          // FTP button
          CustomButton(
            onTap: _disableFtp ? null : _onFtpPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: _disableFtp
                    ? Colors.grey.shade300
                    : const Color(0xFF0052CC),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: _disableFtp
                        ? Colors.grey.shade300
                        : const Color(0xFF0052CC)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_upload,
                      size: 14,
                      color: _disableFtp ? Colors.grey.shade600 : Colors.white),
                  const SizedBox(width: 2),
                  Text(
                      _disableFtp
                          ? 'FTP OFF'
                          : (_currentFtpProfile != null
                              ? 'FTP: $_currentFtpProfile'
                              : 'FTP'),
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              _disableFtp ? Colors.grey.shade600 : Colors.white,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackButton({VoidCallback? onPressed}) {
    return _buildBackButtonWithWidth(MediaQuery.of(context).size.width * 0.5,
        onPressed: onPressed);
  }

  Widget _buildBackButtonWithWidth(double width, {VoidCallback? onPressed}) {
    return Column(
      children: [
        const SizedBox(height: 8),
        // Compact action buttons
        _buildCompactActionButtons(),
        const SizedBox(height: 8),
        // Back button
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: width, // Use passed width parameter
            margin: const EdgeInsets.symmetric(
                horizontal: 5), // 5px padding from left and right
            child: CustomButton(
              onTap: onPressed ??
                  () {
                    setState(() {
                      if (_cameFromCelebration) {
                        // Return to celebration section
                        _selectedVerb = 'Celebration';
                        _selectedActionVerb =
                            null; // Reset action verb to clear caption
                        _selectedHittingAction = null;
                        _selectedCelebrationType =
                            null; // Reset celebration type
                        _isCelebratingScoring =
                            false; // Reset scoring celebration
                        _isCelebratingWithTeammates =
                            false; // Reset teammates celebration
                        _cameFromCelebration = false; // Reset the flag
                        // Reset all menu items
                        _rbiCount = null;
                        _selectedRbiInning = null;
                        _showExtraInnings = false;
                        _extraInningsPage = 0;
                      } else {
                        // Return to main verb menu
                        _selectedVerb = null;
                        _selectedActionVerb =
                            null; // Reset action verb to clear caption
                        _selectedHittingAction = null;
                        _rbiCount = null;
                        _selectedRbiInning = null;
                        _showExtraInnings = false;
                        _extraInningsPage = 0;
                      }
                    });
                    _updateCaption();
                  },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const SizedBox(
                        width: 15), // 15px padding from the left edge
                    Icon(
                      Icons.arrow_back,
                      size: 14,
                      color: Colors.grey.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Back',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVerbOptionsBackButton({VoidCallback? onPressed}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return _buildBackButtonWithWidth(constraints.maxWidth * 0.5,
            onPressed: onPressed);
      },
    );
  }

  // Reusable inning selector widget
  Widget _buildReusableInningSelector() {
    // Determine which innings to show based on the current state
    List<int> inningsToShow;
    int currentPage =
        _extraInningsPage; // Use existing _extraInningsPage variable

    if (currentPage == 0) {
      inningsToShow = List.generate(9, (index) => index + 1); // 1-9
    } else if (currentPage == 1) {
      inningsToShow = List.generate(9, (index) => index + 10); // 10-18
    } else {
      inningsToShow = List.generate(9, (index) => index + 19); // 19-27
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
          child: const Text(
            'Inning',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Innings section (changes content based on state)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Innings row
              Wrap(
                spacing: 2,
                runSpacing: 2,
                children: [
                  // Current set of innings
                  ...inningsToShow.map((inning) {
                    final isSelected = _selectedRbiInning == inning;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedRbiInning =
                              _selectedRbiInning == inning ? null : inning;
                          if (_selectedRbiInning != null) {
                            _isPriorToGame = false;
                          }
                        });
                        _updateCaption();
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.grey.shade300
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: Colors.grey.shade300,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          '$inning',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    );
                  }),

                  // Minus button (go back to previous set)
                  GestureDetector(
                    onTap: currentPage > 0
                        ? () {
                            setState(() {
                              _extraInningsPage--;
                              if (_extraInningsPage == 0) {
                                _showExtraInnings = false;
                              }
                              _selectedRbiInning =
                                  null; // Clear selection when switching
                              _isPriorToGame = false; // Clear prior selection
                            });
                            _updateCaption();
                          }
                        : null,
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: currentPage > 0
                            ? Colors.grey.shade50
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        '-',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: currentPage > 0
                              ? Colors.grey.shade700
                              : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),

                  // Plus button (go to next set)
                  GestureDetector(
                    onTap: currentPage < 2
                        ? () {
                            setState(() {
                              _extraInningsPage++;
                              _showExtraInnings = true;
                              _selectedRbiInning =
                                  null; // Clear selection when switching
                              _isPriorToGame = false; // Clear prior selection
                            });
                            _updateCaption();
                          }
                        : null,
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: currentPage < 2
                            ? Colors.grey.shade50
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        '+',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: currentPage < 2
                              ? Colors.grey.shade700
                              : Colors.grey.shade400,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Prior to the game option (for "Looks On", "Takes the Field", "Comes Off the Field", and "National Anthem" verbs) - placed below innings
              if (_selectedVerb == 'Looks On' ||
                  _selectedVerb == 'Takes the Field' ||
                  _selectedVerb == 'Comes Off the Field') ...[
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isPriorToGame = !_isPriorToGame;
                      if (_isPriorToGame) {
                        _selectedRbiInning = null;
                      }
                    });
                    _updateCaption();
                  },
                  child: Container(
                    width: 100,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _isPriorToGame
                          ? Colors.grey.shade300
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: Colors.grey.shade300,
                        width: 0.5,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Prior to Game',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _isPriorToGame
                              ? Colors.white
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // Base selection interface for running verbs
  Widget _buildBaseSelectionInterface() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected verb indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Base selection section
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Base',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    if (_selectedVerb != 'Steals')
                      _buildBaseChip('1st', '1st Base'),
                    _buildBaseChip('2nd', '2nd Base'),
                    _buildBaseChip('3rd', '3rd Base'),
                    _buildBaseChip('Home', 'Home Plate'),
                  ],
                ),
              ),
              const SizedBox(height: 4),

              // Optional section
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Optional',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    if (_selectedVerb != 'Double Play' &&
                        _selectedVerb != 'Triple Play')
                      _buildBaseChip('Tagged Out', 'Tagged Out'),
                  ],
                ),
              ),
              const SizedBox(height: 4),

              // Inning selection section using reusable widget
              SizedBox(
                height: 80, // Reduced height for compact layout
                child: _buildReusableInningSelector(),
              ),

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBaseChip(String base, String label) {
    // For regular bases, check if it's selected OR if it's the stored base when Tagged Out is selected
    final isSelected = _selectedBase == base ||
        (base != 'Tagged Out' &&
            _selectedBase == 'Tagged Out' &&
            _selectedBaseBeforeTaggedOut == base);
    // For Tagged Out, check if it's directly selected
    final isTaggedOutSelected =
        base == 'Tagged Out' && _selectedBase == 'Tagged Out';

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected || isTaggedOutSelected) {
            _selectedBase = null;
            if (base == 'Tagged Out') {
              _selectedBaseBeforeTaggedOut = null;
            }
          } else {
            if (base == 'Tagged Out') {
              // Store the current base before selecting Tagged Out
              _selectedBaseBeforeTaggedOut = _selectedBase;
              _selectedBase = base;
            } else {
              // When selecting a regular base, keep Tagged Out selected if it was already selected
              if (_selectedBase == 'Tagged Out') {
                _selectedBaseBeforeTaggedOut = base;
                // Keep Tagged Out selected
              } else {
                // Normal case - select the new base
                _selectedBase = base;
                _selectedBaseBeforeTaggedOut = null;
              }
            }
          }
        });
        _updateCaption();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade300 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isSelected ? Colors.grey.shade400 : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.grey.shade800 : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  // Helper function to convert base shorthand to full name
  String _getFullBaseName(String base) {
    switch (base) {
      case '1st':
        return 'first base';
      case '2nd':
        return 'second base';
      case '3rd':
        return 'third base';
      case 'Home':
        return 'home plate';
      case 'Tagged Out':
        return 'tagged out';
      default:
        return '$base base';
    }
  }

  // Celebration interface for celebration verbs
  Widget _buildCelebrationInterface() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected verb indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Celebration options section
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Celebrating:',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    _buildCelebrationChip('Scoring', 'Scoring'),
                    _buildCelebrationChip('Single', 'Single'),
                    _buildCelebrationChip('Double', 'Double'),
                    _buildCelebrationChip('Triple', 'Triple'),
                    _buildCelebrationChip('Home Run', 'Home Run'),
                    _buildCelebrationChip('Strikeout', 'Strikeout'),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Custom celebration text field
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Or write custom celebration:',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: customCelebrationController,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'e.g., celebrates a walk-off hit',
                        hintStyle: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: Colors.grey.shade500),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        isDense: true,
                      ),
                      onTap: () {
                        // When text field is tapped, insert "celebrates " if empty
                        if (customCelebrationController.text.isEmpty) {
                          customCelebrationController.text = 'celebrates ';
                          customCelebrationController.selection =
                              TextSelection.fromPosition(
                            TextPosition(
                                offset:
                                    customCelebrationController.text.length),
                          );
                          setState(() {
                            // Clear selected celebration chips when custom text is entered
                            _selectedCelebrationType = null;
                            _isCelebratingScoring = false;
                          });
                          _updateCaption();
                        }
                      },
                      onChanged: (value) {
                        setState(() {
                          // Clear selected celebration chips when custom text is entered
                          if (value.isNotEmpty) {
                            _selectedCelebrationType = null;
                            _isCelebratingScoring = false;
                          }
                        });
                        _updateCaption();
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Inning section
              SizedBox(
                height: 80, // Reduced height for compact layout
                child: _buildReusableInningSelector(),
              ),

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  // Dejection interface for dejection verbs
  Widget _buildDejectionInterface() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected verb indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Dejection options section
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Dejection Type:',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    _buildDejectionChip('Strikeout', 'Strikeout'),
                    _buildDejectionChip(
                        'Pitcher Taken Out', 'Pitcher Taken Out'),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Custom dejection text field
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Or write custom dejection:',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: customDejectionController,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'e.g., reacts to a bad call',
                        hintStyle: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: BorderSide(color: Colors.grey.shade500),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        isDense: true,
                      ),
                      onTap: () {
                        // When text field is tapped, insert "reacts to " if empty
                        if (customDejectionController.text.isEmpty) {
                          customDejectionController.text = 'reacts to ';
                          customDejectionController.selection =
                              TextSelection.fromPosition(
                            TextPosition(
                                offset: customDejectionController.text.length),
                          );
                          setState(() {
                            // Clear selected dejection chips when custom text is entered
                            _selectedDejectionType = null;
                          });
                          _updateCaption();
                        }
                      },
                      onChanged: (value) {
                        setState(() {
                          // Clear selected dejection chips when custom text is entered
                          if (value.isNotEmpty) {
                            _selectedDejectionType = null;
                          }
                        });
                        _updateCaption();
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Inning section
              SizedBox(
                height: 80, // Reduced height for compact layout
                child: _buildReusableInningSelector(),
              ),

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDejectionChip(String dejection, String label) {
    final isSelected = _selectedDejectionType == dejection;

    return GestureDetector(
      onTap: () {
        setState(() {
          // Clear custom dejection text when chips are selected
          customDejectionController.clear();

          if (isSelected) {
            _selectedDejectionType = null;
          } else {
            _selectedDejectionType = dejection;
          }
        });
        _updateCaption();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade300 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.grey.shade400 : Colors.grey.shade300,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.grey.shade800 : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildCelebrationChip(String celebration, String label) {
    bool isSelected;
    if (celebration == 'Scoring') {
      isSelected = _isCelebratingScoring;
    } else if (celebration == 'With Teammates') {
      isSelected = _isCelebratingWithTeammates;
    } else if (celebration == 'Hit') {
      isSelected = _selectedCelebrationType == celebration;
    } else {
      isSelected = _selectedCelebrationType == celebration;
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          // Clear custom celebration text when chips are selected
          customCelebrationController.clear();

          if (celebration == 'Scoring') {
            _isCelebratingScoring = !_isCelebratingScoring;
          } else if (celebration == 'With Teammates') {
            _isCelebratingWithTeammates = !_isCelebratingWithTeammates;
          } else if (celebration == 'Hit') {
            // Navigate to hit submenu with celebration selected
            _selectedVerb = 'Hit';
            _selectedHittingAction = 'celebrates';
            _selectedCelebrationType = celebration;
          } else if (celebration == 'Single' ||
              celebration == 'Double' ||
              celebration == 'Triple' ||
              celebration == 'Home Run') {
            // Set up for hit type celebration - keep current inning selection
            _selectedVerb = celebration;
            _selectedActionVerb =
                celebration; // Also set action verb to ensure it's used
            _selectedHittingAction = 'celebrates';
            _selectedCelebrationType = celebration;
            _cameFromCelebration = true; // Mark that we came from celebration
            // Don't clear inning selection - let it carry over
          } else if (celebration == 'Strikeout') {
            // Handle strikeout as a simple celebration action
            _selectedVerb = 'Celebration'; // Keep in celebration interface
            _selectedActionVerb = celebration; // Set action verb to Strikeout
            _selectedHittingAction = 'celebrates';
            _selectedCelebrationType = celebration;
            // Don't navigate to submenu - stay in celebration interface
          } else {
            if (isSelected) {
              _selectedCelebrationType = null;
            } else {
              _selectedCelebrationType = celebration;
            }
          }
        });
        _updateCaption();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey.shade300 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isSelected ? Colors.grey.shade400 : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isSelected ? Colors.grey.shade800 : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  // Practice interface for Batting Practice and Fielding Practice (no inning selection)
  Widget _buildPracticeInterface() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected verb indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Back button
        _buildVerbOptionsBackButton(),
      ],
    );
  }

  // National Anthem interface
  Widget _buildNationalAnthemInterface() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected verb indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Back button with compact action buttons
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  // Pitching Change interface
  Widget _buildPitchingChangeInterface() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected verb indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Manager name input
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Manager Name:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _managerNameController,
                      decoration: const InputDecoration(
                        hintText: 'Enter manager name...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                      style: const TextStyle(fontSize: 12),
                      onChanged: (value) {
                        setState(() {
                          _managerName = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  // Add this new function right before _buildAtBatInterface()
  Widget _buildInningOnlyInterface() {
    // Check if this is a post-game verb that shouldn't show inning selector
    final isPostGameVerb =
        _selectedVerb == 'Post Game Win' || _selectedVerb == 'Post Game Loss';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected verb indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            _selectedVerb ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Inning section with reusable widget (only for non-post-game verbs)
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isPostGameVerb) ...[
                SizedBox(
                  height: 100, // Increased height to accommodate Prior button
                  child: _buildReusableInningSelector(),
                ),
              ],

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCatchesSubOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected catch action indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            'Catches',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Action options
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Options',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isDivingCatch = !_isDivingCatch;
                      if (_isDivingCatch) {
                        _selectedFieldingAction = 'Diving Catch';
                      } else {
                        _selectedFieldingAction = null;
                      }
                    });
                    _updateCaption();
                  },
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isDivingCatch
                          ? Colors.grey.shade300
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: Colors.grey.shade300,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      'Diving Catch',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Inning section with reusable widget
              SizedBox(
                height: 80, // Reduced height for compact layout
                child: _buildReusableInningSelector(),
              ),

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGroundballSubOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected groundball action indicator
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            'Groundball',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Action options
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: const Text(
                  'Options',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isDivingCatch = !_isDivingCatch;
                      if (_isDivingCatch) {
                        _selectedFieldingAction = 'Diving Groundball';
                      } else {
                        _selectedFieldingAction = null;
                      }
                    });
                    _updateCaption();
                  },
                  child: Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isDivingCatch
                          ? Colors.grey.shade300
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: Colors.grey.shade300,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      'Diving Play',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              const SizedBox(height: 8),

              // Inning section with reusable widget
              SizedBox(
                height: 100, // Increased height to accommodate Prior button
                child: _buildReusableInningSelector(),
              ),

              // Back button
              _buildVerbOptionsBackButton(),
            ],
          ),
        ),
      ],
    );
  }
}
