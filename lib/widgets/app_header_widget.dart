import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:adaptive_navigation/adaptive_navigation.dart';
import '../utils/native_file_picker.dart';
import 'dart:io';
import 'dart:async';
import '../services/api_manager.dart';
import '../services/preferences_service.dart';
import 'preferences_dialog.dart';
import '../services/camera_serial_service.dart';
import 'app_compact_checkbox.dart';

/// Accent for compact checkboxes (matches Preferences / FTP blue).
const Color _kHeaderPrefsBlue = Color(0xFF0052CC);

class AppHeaderWidget extends StatefulWidget implements PreferredSizeWidget {
  final Function(List<String>) onImagesLoaded;
  final Function(String?)? onHomeTeamChanged;
  final Function(String?)? onAwayTeamChanged;
  final Function(String)? onApiChanged;
  final Function(String)? onStartFolderWatcher;
  final CameraSerialService cameraService;
  final String? currentLayout;
  final Function(String)? onLayoutChanged;
  /// Called when the preferences dialog is closed (so the screen can reload caption entry mode etc.).
  final VoidCallback? onPreferencesClosed;
  /// Called to open FTP Settings (e.g. from Preferences > FTP). When set, Preferences dialog shows "Open FTP Settings" in the FTP section.
  final VoidCallback? onOpenFtpSettings;
  /// Burst detection toggled from the title bar; keeps [CaptionBuilderScreen] in sync.
  final ValueChanged<bool>? onBurstDetectionChanged;
  /// Current image path, index, total, and EXIF data for title bar display.
  final String? currentImagePath;
  final int currentIndex;
  final int totalImages;
  final Map<String, dynamic>? currentExifData;

  const AppHeaderWidget({
    super.key,
    required this.onImagesLoaded,
    required this.cameraService,
    this.onHomeTeamChanged,
    this.onAwayTeamChanged,
    this.onApiChanged,
    this.onStartFolderWatcher,
    this.currentLayout,
    this.onLayoutChanged,
    this.onPreferencesClosed,
    this.onOpenFtpSettings,
    this.onBurstDetectionChanged,
    this.currentImagePath,
    this.currentIndex = 0,
    this.totalImages = 0,
    this.currentExifData,
  });

  @override
  _AppHeaderWidgetState createState() => _AppHeaderWidgetState();

  @override
  Size get preferredSize => const Size.fromHeight(34);
}

class _AppHeaderWidgetState extends State<AppHeaderWidget> {
  // API Manager
  final ApiManager _apiManager = ApiManager();

  // Preferences service
  late PreferencesService _preferencesService;

  // Platform channel for window operations
  static const MethodChannel _windowChannel = MethodChannel('window_control');

  // State variables for team selection
  String? selectedAwayTeam;
  String? selectedHomeTeam;

  // Serial number bylines state
  bool _serialNumberBylinesEnabled = true;
  bool _burstDetectionEnabled = false;
  String selectedApi = 'MLB Stats API'; // API selection
  final bool _isConnectedToApi =
      false; // This would be connected to your API service
  final Set<String> _favoriteTeams =
      {}; // This would be loaded from preferences

  // Folder picking state
  String? _selectedFolderPath;
  List<String> imagePaths = [];
  int currentIndex = 0;

  // Test API connection
  Future<bool> _testApiConnection() async {
    try {
      // Removed debug print for cleaner console output
      final teams = await _apiManager.fetchTeams();
      // Removed debug prints for cleaner console output
      return teams.isNotEmpty;
    } catch (e) {
      print('Error testing API connection: $e');
      return false;
    }
  }

  // Show current window size and resize instructions
  void _showResizeInstructions() {
    final screenSize = MediaQuery.of(context).size;
    final currentWidth = screenSize.width.round();
    final currentHeight = screenSize.height.round();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Test at 1200x800'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current window size: ${currentWidth}x${currentHeight}'),
            const SizedBox(height: 16),
            const Text('To test at 1200x800:'),
            const SizedBox(height: 8),
            const Text('1. Grab the bottom-right corner of this window'),
            const Text('2. Drag it to make the window smaller'),
            const Text('3. The window will stop at 1200x800 (minimum size)'),
            const SizedBox(height: 8),
            const Text('This simulates MacBook 13-inch screen size!',
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  // Teams list
  final List<String> teams = [
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

  @override
  void initState() {
    super.initState();
    _initializePreferences();
    // Test initial API connection
    _testApiConnection();
  }

  Future<void> _initializePreferences() async {
    _preferencesService = await PreferencesService.getInstance();
    await _loadFavoriteTeams();
    await _loadSerialNumberBylines();
    _burstDetectionEnabled =
        await _preferencesService.getBurstDetectionEnabled();
    if (mounted) setState(() {});
  }

  Future<void> _loadFavoriteTeams() async {
    _favoriteTeams.clear();
    _favoriteTeams
        .addAll(await _preferencesService.getFavoriteTeams(sport: 'baseball'));
    setState(() {});
  }

  Future<void> _loadSerialNumberBylines() async {
    _serialNumberBylinesEnabled =
        await _preferencesService.getSerialNumberBylines();
    setState(() {});
  }

  Future<void> _applySerialNumberBylines(bool enabled) async {
    if (_serialNumberBylinesEnabled == enabled) return;
    _serialNumberBylinesEnabled = enabled;
    await _preferencesService.saveSerialNumberBylines(enabled);
    if (mounted) setState(() {});
  }

  Future<void> _applyBurstDetection(bool enabled) async {
    if (_burstDetectionEnabled == enabled) return;
    await _preferencesService.saveBurstDetectionEnabled(enabled);
    if (mounted) setState(() => _burstDetectionEnabled = enabled);
    widget.onBurstDetectionChanged?.call(enabled);
  }

  static const String _kTooltipSerialBylines =
      'When on, the app uses camera serial numbers from image EXIF,\n'
      'and your serial list in Preferences, to fill photographer\n'
      'names and bylines.';

  static const String _kTooltipBurstDetection =
      'When on, saving a caption can detect a burst of shots taken\n'
      'right after this frame (each following shot within one second\n'
      'of the previous) and offer to apply the same caption to\n'
      'those images.';

  Widget _headerHelpHint(BuildContext context, String message) {
    final baseStyle = Theme.of(context).tooltipTheme.textStyle ??
        const TextStyle(color: Colors.white);
    return Tooltip(
      message: message,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      textStyle: baseStyle.copyWith(
        fontSize: 12,
        height: 1.5,
      ),
      waitDuration: const Duration(milliseconds: 350),
      child: MouseRegion(
        cursor: SystemMouseCursors.help,
        child: Padding(
          padding: const EdgeInsets.only(right: 3),
          child: Icon(
            Icons.help_outline,
            size: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _headerPrefsCheckbox({
    required bool isOn,
    required Future<void> Function(bool enabled) onApply,
  }) {
    return AppCompactCheckbox(
      value: isOn,
      accentColor: _kHeaderPrefsBlue,
      onChanged: (v) => onApply(v),
    );
  }

  Widget _topbarBadge(String label, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: (color ?? Colors.white.withOpacity(0.15)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          color: Colors.white70,
          height: 1.0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAppBar(
      toolbarHeight: 34,
      titleSpacing: 0,
      centerTitle: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3A5F78), Color(0xFF2A4858)],
          ),
        ),
      ),
      title: Padding(
        padding: const EdgeInsets.only(left: 10, right: 6),
        child: _buildFileInfoTitle(),
      ),
      actions: [
        IconButton(
          onPressed: () async {
            await showDialog(
              context: context,
              builder: (context) => PreferencesDialog(onOpenFtpSettings: widget.onOpenFtpSettings),
            );
            _serialNumberBylinesEnabled =
                await _preferencesService.getSerialNumberBylines();
            _burstDetectionEnabled =
                await _preferencesService.getBurstDetectionEnabled();
            if (mounted) setState(() {});
            widget.onBurstDetectionChanged?.call(_burstDetectionEnabled);
            widget.onPreferencesClosed?.call();
          },
          icon: const Icon(Icons.settings, color: Colors.white70),
          tooltip: 'Preferences',
          iconSize: 16,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          style: IconButton.styleFrom(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _buildFileInfoTitle() {
    final exif = widget.currentExifData;
    final path = widget.currentImagePath;
    final total = widget.totalImages;
    final idx = widget.currentIndex;

    if (path == null || total == 0) {
      // No file loaded — show app name
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'FLO FILE',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.5,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 8),
          _topbarBadge('Beta'),
        ],
      );
    }

    final fileName = path.split('/').last;

    // Format date/time from EXIF
    String dateTime = '';
    if (exif != null && exif['DateTimeOriginal'] != null) {
      final raw = exif['DateTimeOriginal'].toString();
      // EXIF format: "2024:01:15 14:32:00"
      final parts = raw.split(' ');
      if (parts.length == 2) {
        final dateParts = parts[0].split(':');
        final timeParts = parts[1].split(':');
        if (dateParts.length == 3 && timeParts.length == 3) {
          const months = [
            'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
            'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
          ];
          final year = dateParts[0];
          final monthIdx = int.tryParse(dateParts[1]) ?? 0;
          final day = int.tryParse(dateParts[2]) ?? 0;
          final monthName = (monthIdx >= 1 && monthIdx <= 12)
              ? months[monthIdx - 1]
              : dateParts[1];
          final hour24 = int.tryParse(timeParts[0]) ?? 0;
          final minute = timeParts[1];
          final second = timeParts[2];
          final ampm = hour24 >= 12 ? 'PM' : 'AM';
          final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
          // Append sub-second if available
          final subSec = exif?['SubSecTimeOriginal']?.toString() ?? '';
          final ms = subSec.isNotEmpty ? '.$subSec' : '';
          dateTime = '$monthName $day, $year at $hour12:$minute:$second${ms} $ampm';
        } else {
          dateTime = raw;
        }
      } else {
        dateTime = raw;
      }
    }

    // Resolution
    String resolution = '';
    if (exif != null && exif['ImageWidth'] != null && exif['ImageHeight'] != null) {
      resolution = '${exif['ImageWidth']}×${exif['ImageHeight']}';
    }

    // Camera
    String camera = '';
    if (exif != null) {
      final make = exif['Make']?.toString() ?? '';
      final model = exif['Model']?.toString() ?? '';
      camera = '$make $model'.trim();
    }

    // Lens
    String lens = '';
    if (exif != null) {
      lens = (exif['LensModel'] ?? exif['Lens'] ?? exif['LensID'] ?? '').toString().trim();
    }

    // Exposure parts split individually so each gets its own separator
    String shutterStr = '';
    String apertureStr = '';
    String focalStr = '';
    String isoStr = '';
    if (exif != null) {
      if (exif['ShutterSpeed'] != null) {
        final s = exif['ShutterSpeed'].toString();
        if (s.contains('/')) {
          shutterStr = s;
        } else {
          final d = double.tryParse(s);
          if (d != null && d > 0) {
            shutterStr = d < 1 ? '1/${(1 / d).round()}s' : '${d.toStringAsFixed(1)}s';
          } else {
            shutterStr = s;
          }
        }
      }
      if (exif['FNumber'] != null) {
        final f = double.tryParse(exif['FNumber'].toString());
        if (f != null) apertureStr = 'f/${f.toStringAsFixed(1)}';
      }
      if (exif['FocalLength'] != null) {
        final raw = exif['FocalLength'].toString().replaceAll(RegExp(r'm+$'), '').trim();
        final d = double.tryParse(raw);
        focalStr = d != null ? '${d.toInt()}mm' : '${raw}mm';
      }
      if (exif['ISO'] != null) isoStr = 'ISO ${exif['ISO']}';
    }

    const sep = TextSpan(
      text: '    |    ',
      style: TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.w200),
    );

    const sepStrong = sep;

    const TextStyle _bold = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Colors.white,
      height: 1.0,
    );

    const TextStyle _regular = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w400,
      color: Colors.white70,
      height: 1.0,
    );

    // keep _val/_dim as aliases so the spans below compile unchanged
    TextStyle _val({double size = 10}) => _regular;
    final TextStyle _dim = _regular;

    final spans = <InlineSpan>[
      // File name
      TextSpan(text: fileName, style: _bold),
      if (dateTime.isNotEmpty) ...[sep, TextSpan(text: dateTime, style: _val())],
      if (resolution.isNotEmpty) ...[sepStrong, TextSpan(text: resolution, style: _dim)],
      if (camera.isNotEmpty) ...[sep, TextSpan(text: camera, style: _val())],
      if (lens.isNotEmpty) ...[sep, TextSpan(text: lens, style: _dim)],
      if (shutterStr.isNotEmpty || apertureStr.isNotEmpty) ...[
        sep,
        TextSpan(
          text: [shutterStr, apertureStr].where((s) => s.isNotEmpty).join('  '),
          style: _regular,
        ),
      ],
      if (focalStr.isNotEmpty) ...[sep, TextSpan(text: focalStr, style: _regular)],
      if (isoStr.isNotEmpty) ...[sep, TextSpan(text: isoStr, style: _regular)],
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        // Counter badge on the far left
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${idx + 1} / $total',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.0,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Remaining file info
        Flexible(
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(children: spans),
          ),
        ),
      ],
    );
  }

  // Helper for building team dropdowns
  Widget _buildTeamDropdown({
    required String label,
    required String? value,
    required List<String> allItems,
    required ValueChanged<String?> onChanged,
    String? excludeTeam,
    bool useExpanded = true,
  }) {
    // Filter out the excluded team
    final availableTeams = excludeTeam != null
        ? allItems.where((team) => team != excludeTeam).toList()
        : allItems;

    // Sort teams with favorites first, then alphabetically
    final sortedTeams = List<String>.from(availableTeams);
    sortedTeams.sort((a, b) {
      final aIsFavorite = _favoriteTeams.contains(a);
      final bIsFavorite = _favoriteTeams.contains(b);

      if (aIsFavorite && !bIsFavorite) return -1;
      if (!aIsFavorite && bIsFavorite) return 1;

      return a.compareTo(b);
    });

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
          initialValue: value,
          onSelected: onChanged,
          constraints: const BoxConstraints(maxHeight: 600),
          itemBuilder: (context) => sortedTeams
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
                        if (label == 'Home Team')
                          Icon(Icons.home,
                              size: 12, color: Colors.grey.shade700),
                        if (label == 'Away Team')
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
                        // Clickable star icon to toggle favorite
                        InkWell(
                          onTap: () {
                            setState(() {
                              if (_favoriteTeams.contains(item)) {
                                _favoriteTeams.remove(item);
                              } else {
                                _favoriteTeams.add(item);
                              }

                              // Save favorite teams preference for baseball
                              _preferencesService.saveFavoriteTeams(
                                  _favoriteTeams,
                                  sport: 'baseball');
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              _favoriteTeams.contains(item)
                                  ? Icons.star
                                  : Icons.star_border,
                              size: 12,
                              color: _favoriteTeams.contains(item)
                                  ? Colors.amber
                                  : Colors.grey.shade400,
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
                  '${label.replaceAll(' Team', '')}: ',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                // Home/Away symbol for selected item
                if (value != null) ...[
                  if (label == 'Home Team')
                    Icon(Icons.home, size: 11, color: Colors.grey.shade700),
                  if (label == 'Away Team')
                    Icon(Icons.flight_takeoff,
                        size: 11, color: Colors.grey.shade700),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      value ?? 'Select Team',
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

    return useExpanded ? Expanded(child: dropdown) : dropdown;
  }

  void _showAutoFillDialog(String teamName) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Auto-fill Metadata?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Would you like to auto-fill the following location fields for this team?',
              style: TextStyle(fontSize: 15),
            ),
            SizedBox(height: 12),
            Text('• City: Toronto', style: TextStyle(fontSize: 13)),
            Text('• Province/State: Ontario', style: TextStyle(fontSize: 13)),
            Text('• Country: Canada', style: TextStyle(fontSize: 13)),
            Text('• Country Code: CAN', style: TextStyle(fontSize: 13)),
            Text('• Stadium: Rogers Centre', style: TextStyle(fontSize: 13)),
          ],
        ),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildStyledButton('No', () => Navigator.pop(context, false)),
              const SizedBox(width: 12),
              _buildStyledButton('Yes', () => Navigator.pop(context, true),
                  isBlue: true),
            ],
          ),
        ],
      ),
    );
  }

  void _showManageFavoritesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manage Favorite Teams'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: Column(
            children: [
              const Text('Select teams to add to favorites:'),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: teams.length,
                  itemBuilder: (context, index) {
                    final team = teams[index];
                    final isFavorite = _favoriteTeams.contains(team);
                    return ListTile(
                      title: Text(team),
                      trailing: Icon(
                        isFavorite ? Icons.star : Icons.star_border,
                        color: isFavorite ? Colors.amber : Colors.grey,
                      ),
                      onTap: () {
                        setState(() {
                          if (isFavorite) {
                            _favoriteTeams.remove(team);
                          } else {
                            _favoriteTeams.add(team);
                          }

                          // Save favorite teams preference for baseball
                          _preferencesService.saveFavoriteTeams(_favoriteTeams,
                              sport: 'baseball');
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildStyledButton(String text, VoidCallback onPressed,
      {bool isBlue = false}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isBlue ? Colors.blue : Colors.grey.shade300,
        foregroundColor: isBlue ? Colors.white : Colors.black87,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: Text(text),
    );
  }

  // Folder picking functionality
  Future<void> _pickFolder() async {
    String? dirPath;
    try {
      print('Starting folder picker...');
      print('DEBUG: getDirectoryPath() called');

      // Add a try-catch specifically around file selector
      try {
        dirPath = await NativeFilePicker.pickDirectory();
        print('DEBUG: File selector returned: $dirPath');
      } catch (filePickerError) {
        print('ERROR in FilePicker: $filePickerError');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting folder: $filePickerError')),
        );
        return;
      }

      if (dirPath == null) {
        print('No folder selected');
        return;
      }

      print('Selected folder: $dirPath');
      print('DEBUG: About to check directory permissions...');
    } catch (e, stackTrace) {
      print('ERROR in _pickFolder: $e');
      print('Stack trace: $stackTrace');
      // Show error to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting folder: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    // Store the selected folder path
    setState(() {
      _selectedFolderPath = dirPath;
    });

    // List image files
    List<String> files;
    try {
      files = await _listImageFiles(dirPath);
    } catch (e, stackTrace) {
      print('ERROR in _listImageFiles: $e');
      print('Stack trace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error listing images: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    if (files.isNotEmpty) {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            title: const Text('Loading Images'),
            content: SizedBox(
              width: 300,
              height: 120,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Loading ${files.length} images...',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      );

      // Close loading dialog
      Navigator.of(context).pop();

      try {
        setState(() {
          imagePaths = files;
          currentIndex = 0;
        });

        // Notify parent about loaded images
        print('Notifying parent with ${files.length} images');
        widget.onImagesLoaded(files);

        // Start folder watcher
        print('DEBUG: Starting folder watcher for: $dirPath');
        if (widget.onStartFolderWatcher != null) {
          widget.onStartFolderWatcher!(dirPath!);
        } else {
          print('DEBUG: onStartFolderWatcher callback is null');
        }

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded ${files.length} images from folder'),
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (e, stackTrace) {
        print('ERROR in image loading: $e');
        print('Stack trace: $stackTrace');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading images: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // Helper method to list image files
  Future<List<String>> _listImageFiles(String dirPath) async {
    try {
      print('DEBUG: Attempting to access directory: $dirPath');
      final directory = Directory(dirPath);

      // Check if directory exists and is accessible
      if (!await directory.exists()) {
        print('ERROR: Directory does not exist: $dirPath');
        throw Exception('Directory does not exist: $dirPath');
      }

      print('DEBUG: Directory exists, checking permissions...');

      // Test read permissions
      try {
        print('DEBUG: Testing directory.list().first...');
        await directory.list().first;
        print('DEBUG: Directory is readable');
      } catch (e) {
        print('ERROR: Cannot read directory contents: $e');
        throw Exception('Cannot read directory contents: $e');
      }

      print('DEBUG: About to call directory.listSync()...');
      List<FileSystemEntity> files;
      try {
        files = directory.listSync();
        print('DEBUG: Successfully listed ${files.length} files in directory');
      } catch (listError) {
        print('ERROR in directory.listSync(): $listError');
        throw Exception('Failed to list directory contents: $listError');
      }

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

            print('Checking file: $path with extension: $extension');

            return imageExtensions.contains('.$extension');
          })
          .map((file) => file.path)
          .toList();

      print('Found ${imageFiles.length} image files in $dirPath');
      if (imageFiles.isNotEmpty) {
        print('First few files: ${imageFiles.take(3).toList()}');
      }

      return imageFiles;
    } catch (e) {
      print('Error listing image files: $e');
      return [];
    }
  }
}
