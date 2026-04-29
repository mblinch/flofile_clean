import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers.dart';
import '../widgets/app_header_widget.dart';
import '../widgets/picture_preview_widget.dart';
import '../widgets/caption_fields_widget.dart';
import '../widgets/thumbnail_grid_widget.dart';
import '../widgets/matrix_caption_board.dart';
import '../widgets/player_popup_caption_board.dart';

import '../widgets/startup_dialog.dart';
import '../widgets/sport_selection_dialog.dart';
import '../widgets/keyboard_fire_dialog.dart';
import '../widgets/burst_caption_confirm_dialog.dart';
import '../widgets/update_notes_dialog.dart';
import '../app_update_notes.dart';

import '../widgets/metadata_popup_dialog.dart';
import '../services/api_manager.dart';
import '../services/mlb_api_service.dart'; // For Player model
import '../caption_style/game_info.dart';
import '../services/preferences_service.dart';
import '../services/camera_serial_service.dart';
import '../utils/exiftool_helper.dart';
import '../utils/burst_chain_helper.dart';

/// Writes IPTC keyword bag and XMP/IPTC **Subject** so apps like Photo Mechanic
/// show keywords (PM often reads `Subject` / dc:subject; IPTC-only is easy to miss).
void _appendKeywordsExifArgs(List<String> args, String? keywordsValue) {
  if (keywordsValue == null || keywordsValue.trim().isEmpty) return;
  String cleanValue = keywordsValue.trim();
  if (cleanValue.startsWith('[') && cleanValue.endsWith(']')) {
    cleanValue = cleanValue.substring(1, cleanValue.length - 1);
  }
  final keywords = cleanValue
      .split(',')
      .map((k) => k.trim())
      .where((k) => k.isNotEmpty)
      .toSet()
      .toList();
  if (keywords.isEmpty) return;
  args.add('-IPTC:Keywords=');
  for (final keyword in keywords) {
    args.add('-IPTC:Keywords+=$keyword');
  }
  final joined = keywords.join(', ');
  args.add('-Subject=$joined');
}

/// Intent for Cmd+Shift+V — paste previous caption.
class _PastePreviousCaptionIntent extends Intent {
  const _PastePreviousCaptionIntent();
}

class _SaveAndNextIntent extends Intent {
  const _SaveAndNextIntent();
}

class _PreviousImageIntent extends Intent {
  const _PreviousImageIntent();
}

class _NextImageIntent extends Intent {
  const _NextImageIntent();
}

class _PreviousRowIntent extends Intent {
  const _PreviousRowIntent();
}

class _NextRowIntent extends Intent {
  const _NextRowIntent();
}

/// Arrow-key action that only consumes the key when [consumesKeyWhen] is true
/// (e.g. thumbnail area has focus). Otherwise the key is passed through to the
/// focused widget (e.g. text field for cursor movement).
class _ConditionalArrowAction extends CallbackAction<Intent> {
  _ConditionalArrowAction({
    required super.onInvoke,
    required this.consumesKeyWhen,
  });

  final bool Function() consumesKeyWhen;

  @override
  bool consumesKey(Intent intent) => consumesKeyWhen();
}

/// Result of [CaptionBuilderScreen] save so burst "apply to all" can move the
/// selection to the first frame after the saved chain.
class _IptcInternalSaveResult {
  final bool cancelled;
  /// When non-null, select this index after a successful save (burst apply-all).
  final int? selectIndexAfterSave;

  const _IptcInternalSaveResult._({
    required this.cancelled,
    this.selectIndexAfterSave,
  });

  factory _IptcInternalSaveResult.cancelled() =>
      const _IptcInternalSaveResult._(cancelled: true);

  factory _IptcInternalSaveResult.saved({int? selectIndexAfterSave}) =>
      _IptcInternalSaveResult._(
        cancelled: false,
        selectIndexAfterSave: selectIndexAfterSave,
      );
}

class CaptionBuilderScreen extends StatefulWidget {
  const CaptionBuilderScreen({super.key});

  @override
  _CaptionBuilderScreenState createState() => _CaptionBuilderScreenState();
}

class _CaptionBuilderScreenState extends State<CaptionBuilderScreen> {
  // API manager
  final ApiManager _apiManager = ApiManager();
  final CameraSerialService _cameraService = CameraSerialService();

  // Image state management
  List<String> imagePaths = [];
  int currentIndex = 0;

  // Metadata state
  Map<String, dynamic>? currentMetadata;
  Map<String, dynamic>?
      _originalMetadata; // Track original metadata for change detection
  Map<String, dynamic>?
      _originalCaptionData; // Track original caption data for change detection

  // Precomputed EXIF times for thumbnails
  Map<String, String> _exifTimes = {};
  /// Capture DateTime per path (for burst-chain detection); filled in _loadExifTimesAndSort.
  Map<String, DateTime> _captureDateTimeByPath = {};
  // XMP metadata for rating and color label
  Map<String, int> _xmpRatings = {};
  Map<String, String> _xmpLabels = {};

  // Resolution warning state
  int _resolutionWarningThreshold = 3000;
  bool _showResolutionWarning = false;

  // Photoshop path
  String? _photoshopPath;

  // Layout preference
  String _currentLayout = 'players_list_left';

  /// When true, caption entry uses Keyboard Fire panel; when false, classic CaptionFieldsWidget.
  bool _useKeyboardFireAsDefault = true;

  /// When true, rapid-sequence (burst) save prompt may appear. Default off; see Preferences / startup.
  bool _burstDetectionEnabled = false;

  // Player selection state
  List<Player> selectedHomePlayers = [];
  List<Player> selectedAwayPlayers = [];
  String? _firstPlayerSelected;
  bool? _firstTeamSelected;
  // XMP metadata for tagged/keep flags
  Map<String, bool> _xmpTagged = {};
  // Files that appear locked (not writable by owner)
  Set<String> _lockedPaths = {};

  // Team selection
  String? selectedHomeTeam;
  String? selectedAwayTeam;

  // API selection
  String selectedApi = 'MLB Stats API'; // Default to MLB

  // Personality override for reset
  String? _personalityOverride;

  // Startup configuration
  bool _isSportSelected = false;
  String? _selectedSport;
  bool _isStartupComplete = false;
  String? _selectedFolderPath;
  // File system watcher for detecting new images
  StreamSubscription<FileSystemEvent>? _folderWatcher;

  // Loading states
  bool _isLoadingPlayers = false;
  double _playerLoadingProgress = 0.0;
  bool _isLoadingImages = false;
  double _imageLoadingProgress = 0.0;

  // Global keys for accessing widgets

  final GlobalKey _captionFieldsKey2 = GlobalKey();
  final GlobalKey _picturePreviewKey2 = GlobalKey();
  final GlobalKey _playerPopupKey = GlobalKey();

  // Scroll controller for thumbnail grid
  final ScrollController _thumbnailScrollController = ScrollController();

  // Cached player data to prevent re-fetching
  List<Player> _cachedHomeRoster = [];
  List<Player> _cachedAwayRoster = [];

  // Multi-selection state (tracks Cmd+click selections from thumbnail grid)
  List<String> _multiSelectedImages = [];

  // Track uploaded images
  final Set<String> _uploadedImages = {};
  // Track images successfully saved via IPTC save actions (also persisted per folder)
  final Set<String> _savedImages = {};
  // Track upload progress for thumbnails
  final Map<String, double> _uploadProgress = {};
  // Track queued uploads
  final Set<String> _queuedUploads = {};
  // Track currently uploading images (max 2)
  final Set<String> _currentlyUploading = {};
  // Request id for centering selected thumbnail on arrow navigation
  int _thumbCenterRequestId = 0;
  // Column count from ThumbnailGridWidget (updated when thumb size or layout changes)
  int _lastThumbColumns = 4;
  // Focus for thumbnail area so arrow keys (incl. Up/Down) work when clicking there
  late FocusNode _thumbnailAreaFocusNode;

  // Option+digit shortcut: first digit = category (1-6), second = verb (0-9). No focus needed.
  String? _optionVerbBuffer;
  Timer? _optionVerbBufferTimer;
  // Key to ask the visible thumbnail grid for next index when moving up/down (keeps same column in visible grid)
  final GlobalKey<ThumbnailGridWidgetState> _thumbnailGridKey =
      GlobalKey<ThumbnailGridWidgetState>();

  // Show metadata popup dialog
  void _showMetadataPopup() async {
    if (imagePaths.isEmpty || currentIndex >= imagePaths.length) return;

    // Load fresh metadata directly from the file for the popup
    // This ensures we get the actual file data, not processed widget data
    final imagePath = imagePaths[currentIndex];
    print('📖 LOADING: Loading fresh metadata for popup from: $imagePath');

    Map<String, dynamic> freshMetadata = {};

    try {
      // Use the same ExifTool command as _loadMetadata() to get fresh data
      final proc = await ExiftoolHelper.run([
        '-a', // allow duplicate tags
        '-j', // JSON output
        '-IPTC:Description',
        '-Description',
        '-Caption-Abstract',
        '-ImageDescription',
        '-IPTC:Caption-Abstract',
        '-IPTC:By-line',
        '-By-line',
        '-Creator',
        '-XMP:Creator',
        '-IPTC:OriginalTransmissionReference',
        '-OriginalTransmissionReference',
        '-TransmissionReference',
        '-JobID',
        '-MEID',
        '-IPTC:By-lineTitle',
        '-By-lineTitle',
        '-AuthorsPosition',
        '-IPTC:CopyrightNotice',
        '-CopyrightNotice',
        '-Copyright',
        '-XMP:Rights',
        '-IPTC:Credit',
        '-Credit',
        '-IPTC:Source',
        '-Source',
        '-XMP:Source',
        '-IPTC:Headline',
        '-Headline',
        '-XMP:Title',
        '-IPTC:Keywords',
        '-Keywords',
        '-XMP:Subject',
        '-IPTC:Category',
        '-Category',
        '-XMP-photoshop:SupplementalCategories',
        '-IPTC:SupplementalCategories',
        '-XMP:SupplementalCategories',
        '-IPTC:ObjectName',
        '-ObjectName',
        '-IPTC:SubLocation',
        '-Sub-location',
        '-SubLocation',
        '-XMP:Location',
        '-IPTC:City',
        '-City',
        '-XMP:City',
        '-IPTC:ProvinceState',
        '-Province-State',
        '-ProvinceState',
        '-XMP:State',
        // Photo Mechanic's preferred country fields
        '-IPTC:CountryPrimaryLocationName',
        '-CountryPrimaryLocationName',
        '-Country',
        '-XMP:Country',
        '-IPTC:CountryPrimaryLocationCode',
        '-CountryPrimaryLocationCode',
        '-CountryCode',

        '-IPTC:SpecialInstructions',
        '-SpecialInstructions',
        '-XMP:Instructions',
        '-XMP-photoshop:Instructions',
        '-XMP-getty:Personality',
        '-XMP:Personality',
        '-Personality',
        '-CaptionWriter',
        '-TimeDate',
        '-DateTimeOriginal',
        '-CreateDate',
        '-ModifyDate',
        '-FileModifyDate',
        imagePath,
      ]);

      if (proc.exitCode == 0) {
        final List data = jsonDecode(proc.stdoutText);
        if (data.isNotEmpty) {
          freshMetadata = data.first as Map<String, dynamic>;

          // Update the main screen's cached metadata with fresh data
          // This ensures consistency between popup and main screen
          setState(() {
            currentMetadata = Map<String, dynamic>.from(freshMetadata);
          });

          print('DEBUG: Updated main screen currentMetadata with fresh data');
          print(
              'DEBUG: Main screen currentMetadata SupplementalCategories: ${currentMetadata?['SupplementalCategories']}');
        }
      }
    } catch (e) {
      print('DEBUG: Error loading fresh metadata for popup: $e');
      // Fallback to current metadata if fresh load fails
      freshMetadata = Map<String, dynamic>.from(currentMetadata ?? {});
    }

    showDialog(
      context: context,
      builder: (context) => MetadataPopupDialog(
        metadata: freshMetadata, // Use fresh data from file, not cached data
        onMetadataUpdated: (updatedMetadata) {
          // The popup is responsible for its own saving.
          // This callback should ONLY update the main screen's state.
          print('🔥 MAIN SCREEN: Popup closed, received updated metadata');
          print(
              '🔥 MAIN SCREEN: Updated metadata IPTC:Keywords: "${updatedMetadata['IPTC:Keywords']}"');
          print(
              '🔥 MAIN SCREEN: Updated metadata Subject: "${updatedMetadata['Subject']}"');
          setState(() {
            currentMetadata = updatedMetadata;
          });
          print('🔥 MAIN SCREEN: setState() called with new metadata');
        },
        imagePath: imagePaths[currentIndex],
        onPreviousImage: () async {
          print('DEBUG: Previous button clicked in popup');
          if (currentIndex > 0) {
            setState(() {
              currentIndex--;
            });
            print('DEBUG: Changed index to $currentIndex, closing popup');
            Navigator.of(context).pop(); // Close the popup
            // Wait a moment for the popup to close, then reopen with fresh metadata
            await Future.delayed(const Duration(milliseconds: 50));
            print('DEBUG: Reopening popup with new image');
            _showMetadataPopup(); // Reopen with new image
          }
        },
        onNextImage: () async {
          print('DEBUG: Next button clicked in popup');
          if (currentIndex < imagePaths.length - 1) {
            setState(() {
              currentIndex++;
            });
            print('DEBUG: Changed index to $currentIndex, closing popup');
            Navigator.of(context).pop(); // Close the popup
            // Wait a moment for the popup to close, then reopen with fresh metadata
            await Future.delayed(const Duration(milliseconds: 50));
            print('DEBUG: Reopening popup with new image');
            _showMetadataPopup(); // Reopen with new image
          }
        },
        onCopyMetadata: () {
          // Copy current metadata to clipboard
          final metadataText = jsonEncode(currentMetadata);
          Clipboard.setData(ClipboardData(text: metadataText));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Metadata copied to clipboard')),
          );
        },
        onPasteMetadata: () {
          // Paste metadata from clipboard
          Clipboard.getData('text/plain').then((data) {
            if (data?.text != null) {
              try {
                final pastedMetadata = jsonDecode(data!.text!);
                setState(() {
                  currentMetadata = Map<String, dynamic>.from(pastedMetadata);
                });
                _saveCurrentMetadata();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Metadata pasted from clipboard')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Invalid metadata format in clipboard')),
                );
              }
            }
          });
        },
        onRequestImageChange: (delta) async {
          // Change image without closing popup
          final newIndex = currentIndex + delta;
          if (newIndex >= 0 && newIndex < imagePaths.length) {
            setState(() {
              currentIndex = newIndex;
            });

            // Load fresh metadata for the new image
            final imagePath = imagePaths[currentIndex];
            Map<String, dynamic> freshMetadata = {};

            try {
              final proc = await ExiftoolHelper.run([
                '-a', // allow duplicate tags
                '-j', // JSON output
                '-IPTC:Description',
                '-Description',
                '-Caption-Abstract',
                '-ImageDescription',
                '-IPTC:Caption-Abstract',
                '-IPTC:By-line',
                '-By-line',
                '-Creator',
                '-XMP:Creator',
                '-IPTC:OriginalTransmissionReference',
                '-OriginalTransmissionReference',
                '-TransmissionReference',
                '-JobID',
                '-MEID',
                '-IPTC:By-lineTitle',
                '-By-lineTitle',
                '-AuthorsPosition',
                '-IPTC:CopyrightNotice',
                '-CopyrightNotice',
                '-Copyright',
                '-XMP:Rights',
                '-IPTC:Credit',
                '-Credit',
                '-IPTC:Source',
                '-Source',
                '-XMP:Source',
                '-IPTC:Headline',
                '-Headline',
                '-XMP:Title',
                '-IPTC:Keywords',
                '-Keywords',
                '-XMP:Subject',
                '-IPTC:Category',
                '-Category',
                '-XMP-photoshop:SupplementalCategories',
                '-IPTC:SupplementalCategories',
                '-XMP:SupplementalCategories',
                '-IPTC:ObjectName',
                '-ObjectName',
                '-IPTC:SubLocation',
                '-Sub-location',
                '-SubLocation',
                '-XMP:Location',
                '-IPTC:City',
                '-City',
                '-XMP:City',
                '-IPTC:ProvinceState',
                '-Province-State',
                '-ProvinceState',
                '-XMP:State',
                // Photo Mechanic's preferred country fields
                '-IPTC:CountryPrimaryLocationName',
                '-CountryPrimaryLocationName',
                '-Country',
                '-XMP:Country',
                '-IPTC:CountryPrimaryLocationCode',
                '-CountryPrimaryLocationCode',
                '-CountryCode',
                '-IPTC:SpecialInstructions',
                '-SpecialInstructions',
                '-XMP:Instructions',
                '-XMP-photoshop:Instructions',
                '-XMP-getty:Personality',
                '-XMP:Personality',
                '-Personality',
                '-CaptionWriter',
                '-TimeDate',
                '-DateTimeOriginal',
                '-CreateDate',
                '-ModifyDate',
                '-FileModifyDate',
                imagePath,
              ]);

              if (proc.exitCode == 0) {
                final List data = jsonDecode(proc.stdoutText);
                if (data.isNotEmpty) {
                  freshMetadata = data.first as Map<String, dynamic>;
                }
              }
            } catch (e) {
              print('DEBUG: Error loading fresh metadata for popup: $e');
            }

            print(
                'DEBUG: onRequestImageChange loaded metadata with SupplementalCategories: ${freshMetadata['SupplementalCategories']}');
            print(
                'DEBUG: onRequestImageChange loaded metadata with XMP-photoshop:SupplementalCategories: ${freshMetadata['XMP-photoshop:SupplementalCategories']}');
            print(
                'DEBUG: onRequestImageChange loaded metadata with IPTC:SupplementalCategories: ${freshMetadata['IPTC:SupplementalCategories']}');
            print(
                'DEBUG: onRequestImageChange loaded metadata with XMP:SupplementalCategories: ${freshMetadata['XMP:SupplementalCategories']}');
            print(
                'DEBUG: onRequestImageChange full metadata keys: ${freshMetadata.keys.toList()}');

            return {
              'path': imagePath,
              'metadata': freshMetadata,
            };
          }
          throw Exception('Invalid image index');
        },
      ),
    );
  }

  void _handleReset() {
    setState(() {
      _personalityOverride = '';
    });

    _clearPopupSelections();
  }

  void _clearPopupSelections() {
    final popupState = _playerPopupKey.currentState;
    if (popupState != null) {
      try {
        final dynamic state = popupState;
        state.resetSelections();
      } catch (e) {
        print('Error resetting player popup: $e');
      }
    }
  }

  // Start watching the selected folder for new images
  void _startFolderWatcher(String folderPath) {
    print('DEBUG: _startFolderWatcher called with: $folderPath');

    // Stop any existing watcher
    _stopFolderWatcher();

    try {
      final directory = Directory(folderPath);
      print('DEBUG: Created Directory object for: $folderPath');

      _folderWatcher = directory.watch(events: FileSystemEvent.create).listen(
        (FileSystemEvent event) {
          print(
              'DEBUG: File system event detected: ${event.type} - ${event.path}');
          if (event.type == FileSystemEvent.create) {
            print('DEBUG: File creation event detected: ${event.path}');
            _handleNewImageAdded(event.path);
          }
        },
        onError: (error) {
          print('Error watching folder: $error');
        },
      );
      print('DEBUG: Successfully started watching folder: $folderPath');
    } catch (e) {
      print('Error starting folder watcher: $e');
    }
  }

  // Stop watching the folder
  void _stopFolderWatcher() {
    _folderWatcher?.cancel();
    _folderWatcher = null;
  }

  // Handle new image added to folder
  void _handleNewImageAdded(String newImagePath) {
    print('DEBUG: _handleNewImageAdded called with: $newImagePath');

    // Check if it's an image file and not a temporary file
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

    // Exclude temporary and system files
    final excludeExtensions = [
      '.dbf',
      '.tmp',
      '.temp',
      '.db',
      '.lock',
      '.cache',
      '.DS_Store'
    ];

    final extension = p.extension(newImagePath).toLowerCase();
    final fileName = p.basename(newImagePath).toLowerCase();
    print('DEBUG: File extension: $extension');

    // Skip if it's a temporary/system file
    if (excludeExtensions.contains(extension) ||
        fileName.startsWith('.') ||
        fileName.startsWith('tmp.')) {
      print('DEBUG: Skipping temporary/system file: $newImagePath');
      return;
    }

    if (imageExtensions.contains(extension)) {
      print('DEBUG: Valid image file detected: $newImagePath');
      print('DEBUG: Current imagePaths count: ${imagePaths.length}');

      // Add to image paths if not already present
      if (!imagePaths.contains(newImagePath)) {
        print('DEBUG: Adding new image to imagePaths');
        setState(() {
          imagePaths.add(newImagePath);
          print('DEBUG: imagePaths count after adding: ${imagePaths.length}');
          // Sort images by date taken
          _sortImagesByDateTaken(imagePaths);
        });

        // Show notification
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New image added: ${p.basename(newImagePath)}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        print('DEBUG: Image already exists in imagePaths');
      }
    } else {
      print('DEBUG: Not a valid image file: $newImagePath');
    }
  }

  // Remove any temporary files that might already be in the image list
  void _removeTemporaryFiles() {
    final excludeExtensions = [
      '.dbf',
      '.tmp',
      '.temp',
      '.db',
      '.lock',
      '.cache',
      '.DS_Store'
    ];

    final validExtensions = ['.jpg', '.jpeg', '.png', '.tiff', '.bmp'];

    setState(() {
      final originalCount = imagePaths.length;
      imagePaths.removeWhere((path) {
        final extension = p.extension(path).toLowerCase();
        final fileName = p.basename(path).toLowerCase();

        // Remove if it's a temporary file or not a valid image
        return excludeExtensions.contains(extension) ||
            fileName.startsWith('.') ||
            fileName.startsWith('tmp.') ||
            !validExtensions.contains(extension);
      });

      final removedCount = originalCount - imagePaths.length;
      if (removedCount > 0) {
        print('DEBUG: Removed $removedCount temporary files from image list');

        // Adjust current index if needed
        if (imagePaths.isEmpty) {
          currentIndex = 0;
        } else if (currentIndex >= imagePaths.length) {
          currentIndex = imagePaths.length - 1;
        }

        // Reload metadata if we have images
        if (imagePaths.isNotEmpty) {
          _loadMetadata();
        }
      }
    });
  }

  // Scroll to current thumbnail
  void _scrollToCurrentThumbnail() {
    if (_thumbnailScrollController.hasClients && imagePaths.isNotEmpty) {
      // Calculate the position of the current thumbnail
      final containerWidth = MediaQuery.of(context).size.width * 0.4;
      const thumbSize = 140.0;
      const thumbSpacing = 14.0;
      final columns =
          ((containerWidth - thumbSpacing) / (thumbSize + thumbSpacing))
              .floor();

      if (columns > 0) {
        final row = currentIndex ~/ columns;
        final scrollPosition = row * (thumbSize + thumbSpacing);

        _thumbnailScrollController.animateTo(
          scrollPosition,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _handleSportSelected(String sport) {
    setState(() {
      _selectedSport = sport;
      _isSportSelected = true;
    });

    // Configure API Manager for the selected sport
    _apiManager.setSport(sport);
  }

  void _handleStartupComplete(
      String folderPath, String? homeTeam, String? awayTeam) {
    setState(() {
      _selectedFolderPath = folderPath;
      selectedHomeTeam = homeTeam;
      selectedAwayTeam = awayTeam;
      _isStartupComplete = true;
    });

    _reloadBurstDetectionFromPrefs();

    // Start sequential loading: players first, then thumbnails
    _startLoadingSequence(folderPath);

    // Folder watching disabled to prevent image jumping
  }

  Future<void> _startLoadingSequence(String folderPath) async {
    // Step 1: Load players
    setState(() {
      _isLoadingPlayers = true;
      _playerLoadingProgress = 0.0;
    });

    try {
      // Load home team players
      setState(() {
        _playerLoadingProgress = 0.1;
      });

      const rosterTimeout = Duration(seconds: 12);

      if (selectedHomeTeam != null) {
        print('Loading home team roster for: $selectedHomeTeam');
        final homeRoster = await _apiManager
            .fetchTeamRoster(selectedHomeTeam!)
            .timeout(rosterTimeout, onTimeout: () {
          throw TimeoutException(
              'Home roster request timed out after ${rosterTimeout.inSeconds}s');
        });
        print('Loaded ${homeRoster.length} home team players');
        setState(() {
          _cachedHomeRoster = homeRoster;
          _playerLoadingProgress = 0.5;
        });
      }

      // Brief pause before the second request to avoid rate-limiting
      if (selectedHomeTeam != null && selectedAwayTeam != null) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }

      // Load away team players
      if (selectedAwayTeam != null) {
        print('Loading away team roster for: $selectedAwayTeam');
        final awayRoster = await _apiManager
            .fetchTeamRoster(selectedAwayTeam!)
            .timeout(rosterTimeout, onTimeout: () {
          throw TimeoutException(
              'Away roster request timed out after ${rosterTimeout.inSeconds}s');
        });
        print('Loaded ${awayRoster.length} away team players');
        setState(() {
          _cachedAwayRoster = awayRoster;
          _playerLoadingProgress = 1.0;
        });
      }

      // Small delay to show completion
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (e) {
      print('Error loading players: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Roster load failed: ${e is Exception ? e.toString().replaceFirst('Exception: ', '') : e}',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }

    setState(() {
      _isLoadingPlayers = false;
    });

    // Step 2: Load images from the selected folder
    setState(() {
      _isLoadingImages = true;
      _imageLoadingProgress = 0.0;
    });

    await _loadImagesFromFolder(folderPath);

    setState(() {
      _isLoadingImages = false;
      _imageLoadingProgress = 1.0;
    });

    print('Images loaded: ${imagePaths.length} - going straight to app');
  }

  String _savedImagesPrefsKey(String folderPath) =>
      'caption_saved_paths_v1_${p.normalize(folderPath).hashCode}';

  Future<void> _persistSavedImages() async {
    if (_selectedFolderPath == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _savedImagesPrefsKey(_selectedFolderPath!),
        _savedImages.toList(),
      );
    } catch (e) {
      print('Persist saved images: $e');
    }
  }

  Future<void> _restoreSavedImagesForCurrentFolder() async {
    if (_selectedFolderPath == null || !mounted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored =
          prefs.getStringList(_savedImagesPrefsKey(_selectedFolderPath!));
      if (!mounted) return;
      if (stored == null || stored.isEmpty) {
        setState(() => _savedImages.clear());
        return;
      }
      final valid = stored.where((s) => imagePaths.contains(s)).toSet();
      setState(() {
        _savedImages
          ..clear()
          ..addAll(valid);
      });
    } catch (e) {
      print('Restore saved images: $e');
    }
  }

  Future<void> _loadImagesFromFolder(String folderPath) async {
    try {
      // Preserve currently selected image path (if any) to avoid jumps on reloads
      final String? previouslySelectedPath =
          imagePaths.isNotEmpty && currentIndex < imagePaths.length
              ? imagePaths[currentIndex]
              : null;

      final directory = Directory(folderPath);
      final List<FileSystemEntity> entities = await directory.list().toList();

      // Filter for image files and exclude temporary files
      final List<String> imageFiles =
          entities.whereType<File>().map((entity) => entity.path).where((path) {
        final extension = p.extension(path).toLowerCase();
        final fileName = p.basename(path).toLowerCase();

        // Valid image extensions
        final validExtensions = ['.jpg', '.jpeg', '.png', '.tiff', '.bmp'];

        // Exclude temporary and system files
        final excludeExtensions = [
          '.dbf',
          '.tmp',
          '.temp',
          '.db',
          '.lock',
          '.cache'
        ];

        // Include only valid image files, exclude temporary/system files
        return validExtensions.contains(extension) &&
            !excludeExtensions.contains(extension) &&
            !fileName.startsWith('.') &&
            !fileName.startsWith('tmp.');
      }).toList();

      // Sort images by capture time BEFORE setting the first image
      setState(() {
        _imageLoadingProgress = 0.3;
      });
      await _sortImagesByDateTaken(imageFiles);

      setState(() {
        _imageLoadingProgress = 0.8;
      });

      // Set images after sorting to ensure the first image is chronologically first
      setState(() {
        imagePaths = List.from(imageFiles);
        _savedImages.clear();
        if (previouslySelectedPath != null) {
          final idx = imageFiles.indexOf(previouslySelectedPath);
          currentIndex = idx >= 0 ? idx : 0;
        } else {
          currentIndex = 0;
        }
      });

      await _restoreSavedImagesForCurrentFolder();

      // Clean up any temporary files that might have been loaded
      _removeTemporaryFiles();

      // In the background: batch EXIF read for DateTimeOriginal, compute formatted times
      // Fire-and-forget without awaiting (sorting is already done above)
      Future(() async {
        try {
          await _loadExifTimesAndSort(imageFiles);
        } catch (e) {
          print('Error loading EXIF data: $e');
          // App continues to work without EXIF metadata
        }
      });

      print('Loaded ${imageFiles.length} images from folder: $folderPath');

      // Start folder watcher
      print(
          'DEBUG: Starting folder watcher from _loadImagesFromFolder: $folderPath');
      _startFolderWatcher(folderPath);

      // Load metadata for the first image
      if (imageFiles.isNotEmpty) {
        _loadMetadata();

        // Check if we should apply metadata preset to all images
        _checkAndApplyMetadataPreset();
      }
    } catch (e) {
      print('Error loading images from folder: $e');
    }
  }

  // Begin watching a folder and debounce reloads when image files change
  // Folder watching methods removed to prevent image jumping

  /// Sets session [GameInfo.gameDate] (calendar day) and sample IPTC date strings from the
  /// chronologically first imported image so Caption layout preview matches the folder.
  Future<void> _updateCaptionGameInfoFromImportedImages(
    List<String> sortedPaths,
    Map<String, DateTime> times,
    Map<String, String> rawDateTimeOriginalByPath,
  ) async {
    if (sortedPaths.isEmpty) return;
    final first = sortedPaths.first;
    final dt = times[first];
    if (dt == null) return;
    final gameDay = DateTime(dt.year, dt.month, dt.day);
    final prefs = await PreferencesService.getInstance();
    final existing = await prefs.getCaptionGameInfo();
    final meta = Map<String, String>.from(existing.iptcMetadata);
    final raw = rawDateTimeOriginalByPath[first];
    if (raw != null && raw.isNotEmpty) {
      meta['DateTimeOriginal'] = raw;
    }
    await prefs.saveCaptionGameInfo(
      existing.copyWith(
        gameDate: gameDay,
        iptcMetadata: meta,
      ),
    );
  }

  Future<void> _loadExifTimesAndSort(List<String> imageFiles) async {
    try {
      if (imageFiles.isEmpty) return;

      // Batch exiftool call for all files (DateTimeOriginal, Rating, Label, Tagged, Keep)
      final args = <String>[
        '-j',
        '-DateTimeOriginal',
        '-SubSecTimeOriginal',
        '-XMP:Rating',
        '-XMP:Label',
        '-XMP:Tagged',
        '-XMP:PMKeep'
      ];
      args.addAll(imageFiles);
      final proc = await ExiftoolHelper.run(args);
      final Map<String, DateTime> times = {};
      /// Raw EXIF `DateTimeOriginal` string per file (for caption date prefs / IPTC preview).
      final Map<String, String> rawDateTimeOriginalByPath = {};
      final Map<String, String> formatted = {};
      final Map<String, int> ratings = {};
      final Map<String, String> labels = {};
      final Map<String, bool> tagged = {};

      if (proc.exitCode == 0) {
        try {
          final List data = jsonDecode(proc.stdoutText);
          for (final item in data) {
            if (item is Map<String, dynamic>) {
              final sourceFile = item['SourceFile']?.toString();
              final dateStr = item['DateTimeOriginal']?.toString();
              // ExifTool normalizes keys to simple names like 'Rating' and 'Label'
              final ratingVal = item['Rating'];
              final labelVal = item['Label'];
              final taggedVal = item['Tagged'];
              final keepVal = item['PMKeep'];
              if (sourceFile != null && dateStr != null) {
                try {
                  rawDateTimeOriginalByPath[sourceFile] = dateStr;
                  final subSecTime = item['SubSecTimeOriginal']?.toString();
                  final dt = _parseExifDateTime(dateStr, subSecTime);
                  times[sourceFile] = dt;
                  print(
                      'DEBUG: Parsed EXIF time for $sourceFile: $dateStr + $subSecTime = $dt');
                  // format to 12h as per preference
                  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
                  final minute = dt.minute.toString().padLeft(2, '0');
                  final second = dt.second.toString().padLeft(2, '0');
                  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
                  formatted[sourceFile] = '$hour:$minute:$second $ampm';
                } catch (_) {}
              }
              if (sourceFile != null) {
                if (ratingVal != null) {
                  // Ratings are 0-5; ensure int
                  final r = int.tryParse(ratingVal.toString());
                  if (r != null) ratings[sourceFile] = r;
                }
                if (labelVal != null) {
                  labels[sourceFile] = labelVal.toString();
                }
                // Check for tagged/keep flags
                final isTagged = taggedVal == true ||
                    taggedVal == 'true' ||
                    taggedVal == '1' ||
                    keepVal == true ||
                    keepVal == 'true' ||
                    keepVal == '1';
                tagged[sourceFile] = isTagged;
              }
            }
          }
        } catch (e) {
          print('Error parsing ExifTool JSON output: $e');
          // Continue with fallback to file modified time
        }
      } else {
        print('ExifTool failed with exit code: ${proc.exitCode}');
        print('ExifTool error: ${proc.stderrText}');
        // Continue with fallback to file modified time
      }

      // Fallback to file modified time when missing (but preserve EXIF precision when available)
      for (final path in imageFiles) {
        if (!times.containsKey(path)) {
          // Only use file modification time if we don't have EXIF data
          final fileTime = await File(path).lastModified();
          times[path] = fileTime;
          // Format file time to 12h as per preference
          final hour = fileTime.hour % 12 == 0 ? 12 : fileTime.hour % 12;
          final minute = fileTime.minute.toString().padLeft(2, '0');
          final second = fileTime.second.toString().padLeft(2, '0');
          final ampm = fileTime.hour >= 12 ? 'PM' : 'AM';
          formatted[path] = '$hour:$minute:$second $ampm';
        }
        formatted[path] ??= '';
      }

      // Sort paths by time
      final sorted = List<String>.from(imageFiles)
        ..sort((a, b) => (times[a]!).compareTo(times[b]!));

      if (!mounted) return;

      await _updateCaptionGameInfoFromImportedImages(
        sorted,
        times,
        rawDateTimeOriginalByPath,
      );
      if (!mounted) return;

      // Preserve current image if possible
      final String? currentImagePath =
          imagePaths.isNotEmpty && currentIndex < imagePaths.length
              ? imagePaths[currentIndex]
              : null;

      final bool orderChanged = !listEquals(sorted, imagePaths);

      // Compute locked set based on file writability (owner write bit)
      final Set<String> locked = {};
      for (final path in imageFiles) {
        try {
          final stat = File(path).statSync();
          // If not writable by owner, treat as locked
          final modeStr = stat.modeString(); // e.g., rw-r--r--
          final ownerWritable = modeStr.length >= 2 && modeStr[1] == 'w';
          if (!ownerWritable) locked.add(path);
        } catch (_) {}
      }

      setState(() {
        _exifTimes = formatted;
        _captureDateTimeByPath = Map<String, DateTime>.from(times);
        _xmpRatings = ratings;
        _xmpLabels = labels;
        _xmpTagged = tagged;
        _lockedPaths = locked;
        if (orderChanged) {
          imagePaths = sorted;
          // Restore current image position if it still exists
          if (currentImagePath != null) {
            final newIndex = sorted.indexOf(currentImagePath);
            if (newIndex != -1) {
              currentIndex = newIndex;
            } else {
              currentIndex = 0;
            }
          } else {
            currentIndex = 0;
          }
        }
      });
    } catch (e) {
      print('Error in _loadExifTimesAndSort: $e');
    }
  }

  bool _handlePastePreviousKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyV) return false;
    final k = HardwareKeyboard.instance;
    if (!(k.isMetaPressed || k.isControlPressed) || !k.isShiftPressed) {
      return false;
    }
    final state = _captionFieldsKey2.currentState;
    (state as dynamic)?.pasteLastCaption();
    return true; // consume event to prevent system beep
  }

  /// Cmd+S: save current image and advance to the next one.
  bool _handleSaveAndNextShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyS) return false;
    final k = HardwareKeyboard.instance;
    if (!(k.isMetaPressed || k.isControlPressed) || k.isShiftPressed) {
      return false;
    }
    _saveIptcMetadataInternal().then((r) {
      if (r.cancelled || !mounted) return;
      // Snapshot the current caption (with verb) as "last saved" before moving on.
      (_captionFieldsKey2.currentState as dynamic)?.storeCurrentCaption();
      // Don't advance when multi-selection is active
      if (_multiSelectedImages.length > 1) return;
      if (imagePaths.isEmpty) return;
      final int nextIdx;
      if (r.selectIndexAfterSave != null) {
        nextIdx = r.selectIndexAfterSave!.clamp(0, imagePaths.length - 1);
      } else if (currentIndex < imagePaths.length - 1) {
        nextIdx = currentIndex + 1;
      } else {
        return;
      }
      setState(() => _thumbCenterRequestId++);
      _onImageSelected(nextIdx);
    });
    return true;
  }

  /// Cmd+Enter: save, FTP upload, then advance to the next image.
  bool _handleSaveFtpNextShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) return false;
    final k = HardwareKeyboard.instance;
    if (!(k.isMetaPressed || k.isControlPressed)) return false;
    _saveFtpAndNext();
    return true;
  }

  Future<void> _saveFtpAndNext() async {
    // 1. Save IPTC metadata
    final r = await _saveIptcMetadataInternal();
    if (r.cancelled || !mounted) return;

    // Snapshot the current caption (with verb) as "last saved" before moving on.
    (_captionFieldsKey2.currentState as dynamic)?.storeCurrentCaption();

    // 2. Trigger FTP upload via caption state
    try {
      final dynamic cs = _captionFieldsKey2.currentState;
      if (cs != null) await cs.triggerFtp();
    } catch (e) {
      print('FTP error in Cmd+Enter: $e');
    }
    if (!mounted) return;

    // 3. Advance to next image (skip when multi-selection is active)
    if (_multiSelectedImages.length > 1) return;
    if (imagePaths.isEmpty) return;
    final int nextIdx;
    if (r.selectIndexAfterSave != null) {
      nextIdx = r.selectIndexAfterSave!.clamp(0, imagePaths.length - 1);
    } else if (currentIndex < imagePaths.length - 1) {
      nextIdx = currentIndex + 1;
    } else {
      return;
    }
    setState(() => _thumbCenterRequestId++);
    _onImageSelected(nextIdx);
  }

  /// Option (Alt) + digit: no focus needed. First digit 1-6 = category, second 0-9 = verb.
  bool _handleOptionVerbShortcut(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final k = HardwareKeyboard.instance;
    if (!k.isAltPressed) {
      return false;
    }
    final logical = event.logicalKey;
    int? digit;
    if (logical == LogicalKeyboardKey.digit1 ||
        logical == LogicalKeyboardKey.numpad1)
      digit = 1;
    else if (logical == LogicalKeyboardKey.digit2 ||
        logical == LogicalKeyboardKey.numpad2)
      digit = 2;
    else if (logical == LogicalKeyboardKey.digit3 ||
        logical == LogicalKeyboardKey.numpad3)
      digit = 3;
    else if (logical == LogicalKeyboardKey.digit4 ||
        logical == LogicalKeyboardKey.numpad4)
      digit = 4;
    else if (logical == LogicalKeyboardKey.digit5 ||
        logical == LogicalKeyboardKey.numpad5)
      digit = 5;
    else if (logical == LogicalKeyboardKey.digit6 ||
        logical == LogicalKeyboardKey.numpad6)
      digit = 6;
    else if (logical == LogicalKeyboardKey.digit7 ||
        logical == LogicalKeyboardKey.numpad7)
      digit = 7;
    else if (logical == LogicalKeyboardKey.digit8 ||
        logical == LogicalKeyboardKey.numpad8)
      digit = 8;
    else if (logical == LogicalKeyboardKey.digit9 ||
        logical == LogicalKeyboardKey.numpad9)
      digit = 9;
    else if (logical == LogicalKeyboardKey.digit0 ||
        logical == LogicalKeyboardKey.numpad0) digit = 0;
    if (digit == null) return false;

    _optionVerbBufferTimer?.cancel();
    if (_optionVerbBuffer == null) {
      if (digit >= 1 && digit <= 6) {
        setState(() => _optionVerbBuffer = digit.toString());
        _optionVerbBufferTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _optionVerbBuffer = null);
        });
        return true;
      }
      return false;
    }
    final cat = int.tryParse(_optionVerbBuffer!) ?? 0;
    final verbNum = digit == 0 ? 10 : digit;
    setState(() => _optionVerbBuffer = null);
    final state = _captionFieldsKey2.currentState;
    (state as dynamic)?.selectVerbByCategoryAndIndex(cat, verbNum);
    return true;
  }

  @override
  void initState() {
    super.initState();
    _thumbnailAreaFocusNode = FocusNode();
    _initializeServices();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowUpdateNotes();
    });
    HardwareKeyboard.instance.addHandler(_handleSaveAndNextShortcut);
    HardwareKeyboard.instance.addHandler(_handleSaveFtpNextShortcut);
    HardwareKeyboard.instance.addHandler(_handlePastePreviousKeyEvent);
    HardwareKeyboard.instance.addHandler(_handleOptionVerbShortcut);
  }

  Future<void> _reloadBurstDetectionFromPrefs() async {
    final preferencesService = await PreferencesService.getInstance();
    final burst = await preferencesService.getBurstDetectionEnabled();
    if (mounted) setState(() => _burstDetectionEnabled = burst);
  }

  /// Shows [UpdateNotesDialog] once per install when build number increases.
  Future<void> _maybeShowUpdateNotes() async {
    if (!mounted) return;
    try {
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber) ?? 0;
      final prefs = await PreferencesService.getInstance();
      final last = await prefs.getLastAcknowledgedAppBuild();
      if (build <= last) return;
      if (kAppUpdateNotesBody.trim().isEmpty) {
        await prefs.setLastAcknowledgedAppBuild(build);
        return;
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => UpdateNotesDialog(
          versionLabel: '${info.version} (build ${info.buildNumber})',
        ),
      );
      await prefs.setLastAcknowledgedAppBuild(build);
    } catch (_) {}
  }

  Future<void> _initializeServices() async {
    await _cameraService.initialize();
    print('DEBUG: Camera service initialized successfully');

    // Load resolution warning threshold, Photoshop path, and layout
    final preferencesService = await PreferencesService.getInstance();
    _resolutionWarningThreshold =
        await preferencesService.getResolutionWarningThreshold();
    _photoshopPath = await preferencesService.getPhotoshopPath();
    _currentLayout = await preferencesService.getCurrentLayout();
    final captionMode = await preferencesService.getCaptionEntryMode();
    _useKeyboardFireAsDefault = captionMode == 'keyboard_fire';
    _burstDetectionEnabled =
        await preferencesService.getBurstDetectionEnabled();
    if (mounted) setState(() {});
  }

  // Load metadata from the current image
  Future<void> _loadMetadata() async {
    if (imagePaths.isEmpty || currentIndex >= imagePaths.length) return;

    final imagePath = imagePaths[currentIndex];
    print('Loading metadata from: $imagePath');

    try {
      // Extract metadata via exiftool in JSON format - using Photo Mechanic's preferred IPTC fields
      final proc = await ExiftoolHelper.run([
        '-a', // allow duplicate tags (return all values)
        '-j', // JSON output
        // Photo Mechanic's preferred caption field
        '-IPTC:Description',
        '-Description',
        // Standard IPTC fields
        '-Caption-Abstract',
        '-ImageDescription',
        '-IPTC:Caption-Abstract',
        // Photo Mechanic's preferred creator fields
        '-IPTC:By-line',
        '-By-line',
        '-Creator',
        '-XMP:Creator',
        // Camera info for automatic byline detection
        '-Make',
        '-Model',
        '-SerialNumber',
        // Image dimensions for resolution warning
        '-ImageWidth',
        '-ImageHeight',
        '-ExifImageWidth',
        '-ExifImageHeight',
        // Photo Mechanic's preferred job ID field
        '-IPTC:OriginalTransmissionReference',
        '-OriginalTransmissionReference',
        '-TransmissionReference',
        '-JobID',
        '-MEID',
        // Photo Mechanic's preferred job title field
        '-IPTC:By-lineTitle',
        '-By-lineTitle',
        '-AuthorsPosition',
        // Photo Mechanic's preferred copyright field
        '-IPTC:CopyrightNotice',
        '-CopyrightNotice',
        '-Copyright',
        '-XMP:Rights',
        // Photo Mechanic's preferred credit field
        '-IPTC:Credit',
        '-Credit',
        // Photo Mechanic's preferred source field
        '-IPTC:Source',
        '-Source',
        '-XMP:Source',
        // Photo Mechanic's preferred headline field
        '-IPTC:Headline',
        '-Headline',
        '-XMP:Title',
        // Photo Mechanic's preferred keywords field
        '-IPTC:Keywords',
        '-Keywords',
        '-XMP:Subject',
        // Photo Mechanic's preferred category fields
        '-IPTC:Category',
        '-Category',
        '-XMP-photoshop:SupplementalCategories',
        '-IPTC:SupplementalCategories',
        '-XMP:SupplementalCategories',
        // Photo Mechanic's preferred object name field
        '-IPTC:ObjectName',
        '-ObjectName',
        // Photo Mechanic's preferred location fields
        '-IPTC:SubLocation',
        '-Sub-location',
        '-SubLocation',
        '-XMP:Location',
        '-IPTC:City',
        '-City',
        '-XMP:City',
        '-IPTC:ProvinceState',
        '-Province-State',
        '-ProvinceState',
        '-XMP:State',
        // Photo Mechanic's preferred country fields
        '-IPTC:CountryPrimaryLocationName',
        '-CountryPrimaryLocationName',
        '-Country',
        '-XMP:Country',
        '-IPTC:CountryPrimaryLocationCode',
        '-CountryPrimaryLocationCode',
        '-CountryCode',

        // Photo Mechanic's preferred instructions field
        '-IPTC:SpecialInstructions',
        '-SpecialInstructions',
        '-XMP:Instructions',
        '-XMP-photoshop:Instructions',
        // Photo Mechanic's preferred personality field
        '-XMP-getty:Personality',
        '-XMP:Personality',
        '-Personality',
        // Additional fields for compatibility
        '-CaptionWriter',
        '-TimeDate',
        '-DateTimeOriginal',
        '-CreateDate',
        '-ModifyDate',
        '-FileModifyDate',
        imagePath,
      ]);

      if (proc.exitCode == 0) {
        try {
          print('DEBUG: Raw ExifTool JSON output: ${proc.stdoutText}');
          final List data = jsonDecode(proc.stdoutText);
          if (data.isNotEmpty) {
            final loadedMetadata = data.first as Map<String, dynamic>;
            print('DEBUG: Caption fields found:');
            print('  IPTC:Description: ${loadedMetadata['IPTC:Description']}');
            print('  Description: ${loadedMetadata['Description']}');
            print('  Caption-Abstract: ${loadedMetadata['Caption-Abstract']}');
            print(
                '  IPTC:Caption-Abstract: ${loadedMetadata['IPTC:Caption-Abstract']}');
            print('  ImageDescription: ${loadedMetadata['ImageDescription']}');
            print('DEBUG: Personality fields found:');
            print(
                '  XMP-getty:Personality: ${loadedMetadata['XMP-getty:Personality']}');
            print('  Personality: ${loadedMetadata['Personality']}');
            print(
                'DEBUG: Raw parsed SupplementalCategories: ${loadedMetadata['SupplementalCategories']} (${loadedMetadata['SupplementalCategories'].runtimeType})');
            print(
                'DEBUG: Parsed metadata SupplementalCategories: ${loadedMetadata['SupplementalCategories']}');
            setState(() {
              currentMetadata = loadedMetadata;
              _originalMetadata = Map<String, dynamic>.from(
                  loadedMetadata); // Store original for change detection

              // Check image resolution for warning
              _checkImageResolution(loadedMetadata);

              // Also track original caption data for change detection directly from loaded metadata
              final Map<String, dynamic> originalCaptionFromMeta = {
                'Caption-Abstract':
                    loadedMetadata['Caption-Abstract']?.toString() ?? '',
                'XMP:Description':
                    loadedMetadata['ImageDescription']?.toString() ?? '',
                'ImageDescription':
                    loadedMetadata['ImageDescription']?.toString() ?? '',
                'XMP-getty:Personality':
                    (loadedMetadata['XMP-getty:Personality'] ??
                                loadedMetadata['Personality'])
                            ?.toString() ??
                        '',
                'Sub-location':
                    loadedMetadata['Sub-location']?.toString() ?? '',
                'City': loadedMetadata['City']?.toString() ?? '',
                'Province-State':
                    loadedMetadata['Province-State']?.toString() ?? '',
              };
              _originalCaptionData = originalCaptionFromMeta;
              print(
                  'DEBUG: Set original caption data (from meta): $_originalCaptionData');
            });

            print('Metadata loaded successfully');
          }
        } catch (e) {
          print('Error parsing metadata JSON: $e');
          setState(() {
            currentMetadata = null;
            _originalMetadata = null;
            _originalCaptionData = null;
          });
        }
      } else {
        print('Exiftool error: ${proc.stderrText}');
        setState(() {
          currentMetadata = null;
          _originalMetadata = null;
          _originalCaptionData = null;
        });
      }
    } catch (e) {
      print('Error loading metadata: $e');
    }
  }

  /// Save caption metadata to multiple images at once.
  /// If [preCapturedValues] is provided, those values are used directly
  /// (avoids re-reading from controllers after an async gap like a dialog).
  Future<void> _saveIptcToMultipleImages(
    List<String> targets, {
    Map<String, String>? preCapturedValues,
  }) async {
    if (targets.isEmpty) return;

    Map<String, String> captionValues;
    if (preCapturedValues != null && preCapturedValues.isNotEmpty) {
      captionValues = preCapturedValues;
    } else {
      (_captionFieldsKey2.currentState as dynamic)?.storeCurrentCaption();
      dynamic captionState = _captionFieldsKey2.currentState;
      if (captionState == null) return;
      captionValues = captionState.getCurrentCaptionValues();
      if (captionValues.isEmpty) return;
    }

    try {
      final List<String> tagAndFlags = [];

      captionValues.forEach((key, value) {
        if (key == 'IPTC:Keywords' ||
            key == 'Keywords' ||
            key == 'Subject' ||
            key == 'XMP:Subject' ||
            key == 'XMP-dc:Subject') return;
        if (value.trim().isNotEmpty) {
          tagAndFlags.add('-$key=$value');
        }
      });

      final keywordsValue =
          captionValues['IPTC:Keywords'] ?? captionValues['Keywords'];
      _appendKeywordsExifArgs(tagAndFlags, keywordsValue);

      tagAndFlags.addAll(['-overwrite_original', '-P', '-m', '-charset', 'iptc=UTF8']);

      // Nothing to write (same guard as before, but per-field list).
      if (tagAndFlags.length <= 5) {
        print('No metadata values to save for bulk');
        return;
      }

      // One exiftool run per file so only [targets] are written (burst “skip” cannot pick up strays).
      print('Saving caption to ${targets.length} images (one process per file)...');
      int ok = 0;
      final succeeded = <String>[];
      for (final target in targets) {
        final args = [...tagAndFlags, target];
        final proc = await ExiftoolHelper.run(args);
        if (proc.exitCode == 0) {
          ok++;
          succeeded.add(target);
        } else {
          print('Exiftool error for $target: ${proc.stderrText}');
        }
      }
      if (succeeded.isNotEmpty && mounted) {
        setState(() => _savedImages.addAll(succeeded));
        unawaited(_persistSavedImages());
      }

      if (mounted) {
        if (ok == targets.length) {
          print('Caption saved to ${targets.length} images successfully');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Caption saved to ${targets.length} images'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else if (ok > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Caption saved to $ok of ${targets.length} images; see log for errors',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error saving to images'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('Error saving to multiple images: $e');
    }
  }

  /// First index after the last file in [chain], or the last index if [chain]
  /// ends at the end of the roll.
  int? _selectionIndexAfterBurstChain(List<String> chain) {
    if (chain.isEmpty || imagePaths.isEmpty) return null;
    final lastPath = chain.last;
    final li = imagePaths.indexOf(lastPath);
    if (li < 0) return null;
    if (li >= imagePaths.length - 1) return li;
    return li + 1;
  }

  /// After a burst save, move selection to the first skipped frame (burst order)
  /// so captioning can resume there; if every frame in the burst was written,
  /// keep the previous behavior (first index after the last written file).
  int? _selectionIndexAfterBurstApply(
    List<String> chain,
    List<String> targets,
  ) {
    if (chain.isEmpty || imagePaths.isEmpty) return null;
    final targetNorm = targets.map((t) => p.normalize(t)).toSet();
    for (final path in chain) {
      if (targetNorm.contains(p.normalize(path))) continue;
      final needle = p.normalize(path);
      for (var i = 0; i < imagePaths.length; i++) {
        if (p.normalize(imagePaths[i]) == needle) return i;
      }
    }
    return _selectionIndexAfterBurstChain(targets);
  }

  String _captionPreviewFromValues(Map<String, String>? v) {
    if (v == null) return '';
    const keys = [
      'IPTC:Caption-Abstract',
      'Caption-Abstract',
      'IPTC:Description',
      'Description',
      'XMP:Description',
    ];
    for (final k in keys) {
      final s = v[k]?.trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return '';
  }

  /// [cancelled] is true only when the user dismisses or cancels the burst dialog.
  /// [selectIndexAfterSave] is set after a successful burst "apply to all" save.
  Future<_IptcInternalSaveResult> _saveIptcMetadataInternal() async {
    if (_multiSelectedImages.length > 1) {
      await _saveIptcToMultipleImages(_multiSelectedImages);
      return _IptcInternalSaveResult.saved();
    }

    if (imagePaths.isEmpty || currentIndex >= imagePaths.length) {
      return _IptcInternalSaveResult.saved();
    }

    // Snapshot the current caption (with verb) BEFORE any async yields.
    (_captionFieldsKey2.currentState as dynamic)?.storeCurrentCaption();

    final anchor = imagePaths[currentIndex];
    final chain = burstChainAdjacentInList(
      imagePaths,
      anchor,
      _captureDateTimeByPath,
    );

    if (_burstDetectionEnabled && chain.length > 1 && mounted) {
      dynamic captionState = _captionFieldsKey2.currentState;
      Map<String, String>? vals;
      if (captionState != null) {
        vals = captionState.getCurrentCaptionValues();
      }

      // Freeze caption values NOW before any async gap (dialog / prefs).
      // After the dialog returns the controllers may be stale.
      final Map<String, String> frozenValues = vals != null ? Map.of(vals) : {};

      final captionPreview = _captionPreviewFromValues(vals);
      final dialogResult = await showBurstCaptionConfirmDialog(
        context: context,
        imagePathsInOrder: chain,
        captionPreview: captionPreview,
        onBurstDetectionDisabled: () {
          if (mounted) setState(() => _burstDetectionEnabled = false);
        },
      );
      if (!mounted) return _IptcInternalSaveResult.cancelled();
      if (dialogResult == null) {
        return _IptcInternalSaveResult.cancelled();
      }

      if (dialogResult.choice == BurstCaptionSaveChoice.cancel) {
        return _IptcInternalSaveResult.cancelled();
      }
      if (dialogResult.choice == BurstCaptionSaveChoice.applyToAll) {
        final targets = dialogResult.pathsToApply;
        if (targets.isEmpty) {
          return _IptcInternalSaveResult.cancelled();
        }
        await _saveIptcToMultipleImages(targets, preCapturedValues: frozenValues);
        _clearPopupSelections();
        final after = _selectionIndexAfterBurstApply(chain, targets);
        return _IptcInternalSaveResult.saved(selectIndexAfterSave: after);
      }
      if (dialogResult.choice == BurstCaptionSaveChoice.thisImageOnly) {
        if (!mounted) return _IptcInternalSaveResult.cancelled();
        await _saveIptcToMultipleImages([anchor], preCapturedValues: frozenValues);
        _clearPopupSelections();
        return _IptcInternalSaveResult.saved();
      }
    }

    await _saveIptcMetadataToImagePath(imagePaths[currentIndex]);
    return _IptcInternalSaveResult.saved();
  }

  // Save IPTC metadata to the current image (with UI refresh)
  Future<void> _saveIptcMetadata() async {
    final r = await _saveIptcMetadataInternal();
    if (r.cancelled || !mounted) return;
    if (r.selectIndexAfterSave != null) {
      final idx = r.selectIndexAfterSave!.clamp(0, imagePaths.length - 1);
      setState(() => _thumbCenterRequestId++);
      _onImageSelected(idx);
    }
  }

  Future<void> _saveIptcMetadataToImagePath(String imagePath) async {
    print('Saving IPTC metadata to: $imagePath');

    // Get values from both widgets
    Map<String, String> allValues = {};

    // Note: Metadata values now come from the popup dialog, not from a main UI widget

    // Get caption values from the caption fields widget
    dynamic captionState = _captionFieldsKey2.currentState;
    if (captionState != null) {
      Map<String, String> captionValues =
          captionState.getCurrentCaptionValues();
      allValues.addAll(captionValues);
      print('Retrieved caption values: $captionValues');
    }

    if (allValues.isEmpty) {
      print('Could not access widget states');
      return;
    }

    // Preserve location/headline fields if the caption form doesn't provide them.
    // This prevents accidental wipes of original IPTC values during normal saves.
    void preserveIfMissing(String key, List<String> fallbacks) {
      final existing = (allValues[key] ?? '').trim();
      if (existing.isNotEmpty) return;
      for (final fb in fallbacks) {
        final v = currentMetadata?[fb]?.toString().trim() ?? '';
        if (v.isNotEmpty) {
          allValues[key] = v;
          return;
        }
      }
    }

    preserveIfMissing('IPTC:Headline', ['IPTC:Headline', 'Headline']);
    preserveIfMissing('Headline', ['IPTC:Headline', 'Headline']);
    preserveIfMissing('IPTC:CountryPrimaryLocationName', [
      'IPTC:CountryPrimaryLocationName',
      'CountryPrimaryLocationName',
      'Country',
      'XMP:Country'
    ]);
    preserveIfMissing('CountryPrimaryLocationName', [
      'IPTC:CountryPrimaryLocationName',
      'CountryPrimaryLocationName',
      'Country',
      'XMP:Country'
    ]);
    preserveIfMissing('Country', [
      'IPTC:CountryPrimaryLocationName',
      'CountryPrimaryLocationName',
      'Country',
      'XMP:Country'
    ]);
    preserveIfMissing('IPTC:CountryPrimaryLocationCode', [
      'IPTC:CountryPrimaryLocationCode',
      'CountryPrimaryLocationCode',
      'CountryCode'
    ]);
    preserveIfMissing('CountryPrimaryLocationCode', [
      'IPTC:CountryPrimaryLocationCode',
      'CountryPrimaryLocationCode',
      'CountryCode'
    ]);
    preserveIfMissing('CountryCode', [
      'IPTC:CountryPrimaryLocationCode',
      'CountryPrimaryLocationCode',
      'CountryCode'
    ]);

    try {
      // Build exiftool command arguments
      List<String> args = [];

      // Fields that should be explicitly cleared in the file when the user empties them.
      const clearableFields = {
        'XMP-getty:Personality',
        'IPTC:Description',
        'Description',
        'Caption-Abstract',
        'IPTC:Caption-Abstract',
        'XMP:Description',
        'ImageDescription',
      };

      // Add each field that has a value, handle keywords specially
      allValues.forEach((key, value) {
        // Skip keyword fields — handled separately below
        if (key == 'IPTC:Keywords' ||
            key == 'Keywords' ||
            key == 'Subject' ||
            key == 'XMP:Subject' ||
            key == 'XMP-dc:Subject') return;

        if (value.trim().isNotEmpty) {
          args.add('-$key=$value');
          if (key == 'Creator') {
            print('DEBUG: Adding Creator to exiftool args: -$key=$value');
          }
        } else if (clearableFields.contains(key)) {
          // Explicitly clear the field so the old value is removed from the file
          args.add('-$key=');
        }
      });

      // Handle keywords with Photo Mechanic compatibility
      // Check current metadata if not found in form values
      print('DEBUG: Looking for keywords in save function:');
      print('  allValues[IPTC:Keywords]: ${allValues['IPTC:Keywords']}');
      print('  allValues[XMP-dc:Subject]: ${allValues['XMP-dc:Subject']}');
      print('  currentMetadata[Keywords]: ${currentMetadata?['Keywords']}');
      print(
          '  currentMetadata[IPTC:Keywords]: ${currentMetadata?['IPTC:Keywords']}');

      final keywordsValue = allValues['IPTC:Keywords'] ??
          allValues['XMP-dc:Subject'] ??
          currentMetadata?['Keywords'] ??
          currentMetadata?['IPTC:Keywords'];
      print('DEBUG: Final keywordsValue: $keywordsValue');

      // Check if keywords have changed to avoid unnecessary clear/write operations
      final String currentKeywords = keywordsValue?.toString() ?? '';
      final String originalKeywords =
          (currentMetadata?['IPTC:Keywords'] ?? currentMetadata?['Keywords'])
                  ?.toString() ??
              '';

      // Clean both values for comparison
      String cleanCurrent = currentKeywords.trim();
      String cleanOriginal = originalKeywords.trim();

      if (cleanCurrent.startsWith('[') && cleanCurrent.endsWith(']')) {
        cleanCurrent = cleanCurrent.substring(1, cleanCurrent.length - 1);
      }
      if (cleanOriginal.startsWith('[') && cleanOriginal.endsWith(']')) {
        cleanOriginal = cleanOriginal.substring(1, cleanOriginal.length - 1);
      }

      // Parse into sets for comparison (order doesn't matter)
      final Set<String> currentSet = cleanCurrent.isEmpty
          ? <String>{}
          : cleanCurrent
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet();
      final Set<String> originalSet = cleanOriginal.isEmpty
          ? <String>{}
          : cleanOriginal
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet();

      final bool keywordsChanged =
          !currentSet.difference(originalSet).isEmpty ||
              !originalSet.difference(currentSet).isEmpty;

      print('🔍 MAIN SAVE - KEYWORD CHANGE DETECTION:');
      print('🔍 Original: $originalSet');
      print('🔍 Current:  $currentSet');
      print('🔍 Changed:  $keywordsChanged');

      // TEMPORARILY DISABLE CHANGE DETECTION - CAUSING FILE CORRUPTION
      // Process keywords every time for now (safe mode)
      if (true) {
        // SIMPLE APPROACH - NO CLEARING, JUST OVERWRITE
        // Always process keywords
        print(
            '🔥 MAIN SAVE - PROCESSING KEYWORDS (SAFE MODE - NO CHANGE DETECTION)...');

        // Convert to string and check if not empty
        String? keywordsString = keywordsValue?.toString();
        if (keywordsString != null && keywordsString.trim().isNotEmpty) {
          print(
              '🔧 MAIN SAVE: Keywords (IPTC bag + Subject for Photo Mechanic): "$keywordsString"');
          _appendKeywordsExifArgs(args, keywordsString);
        } else {
          // If user cleared keywords, write empty IPTC:Keywords in a dedicated call
          print(
              '🔧 MAIN SAVE: User cleared keywords - clearing IPTC and related subject fields');
          final clearKwArgs = [
            '-IPTC:Keywords=',
            '-Subject=',
            '-XMP-dc:Subject=',
            '-XMP:Subject=',
            '-Keywords=',
            '-overwrite_original',
            imagePath,
          ];
          final kwClearProc = await ExiftoolHelper.run(clearKwArgs);
          if (kwClearProc.exitCode != 0) {
            print('DEBUG: Failed to clear keywords: ' + kwClearProc.stderrText);
          }
        }
        // Continue with the normal save since keywords are now part of main command
      }

      // Handle supplemental categories with overwrite semantics.
      // Merge currentMetadata — caption getCurrentCaptionValues() omits supp cats;
      // otherwise empty raw inputs would clear every supplemental field on save.
      final List<String> rawInputs =
          supplementalCategoryRawInputsForSave(allValues, currentMetadata);

      // Remove any existing supplemental category args to ensure clean state
      args.removeWhere((arg) =>
          arg.startsWith('-SupplementalCategories') ||
          arg.startsWith('-XMP-photoshop:SupplementalCategories'));

      args.addAll(buildSupplementalCategoriesArgs(rawInputs));

      // Always overwrite original file
      // Robust IPTC writes: preserve file time, be lenient, ensure UTF-8 for IPTC
      args.addAll(['-overwrite_original', '-P', '-m', '-charset', 'iptc=UTF8']);
      args.add(imagePath);

      // Only run exiftool if we have metadata to write
      if (args.length > 2) {
        // More than just -overwrite_original and path
        print('Running exiftool with args: $args');
        final proc = await ExiftoolHelper.run(args);

        if (proc.exitCode == 0) {
          print('IPTC metadata saved successfully');
          if (mounted) {
            setState(() => _savedImages.add(imagePath));
            unawaited(_persistSavedImages());
          }

          // Debug: Verify caption was actually written
          final verifyProc =
              await ExiftoolHelper.run(['-Caption-Abstract', imagePath]);
          print(
              'DEBUG: Caption verification after save: ${verifyProc.stdoutText}');

          // Don't refresh EXIF data for background saves to avoid UI glitches
        } else {
          print('Exiftool error saving metadata: ${proc.stderrText}');
        }
      } else {
        print('No metadata values to save');
      }

      // Clear player selections and custom verb after successful save
      _clearPopupSelections();
    } catch (e) {
      print('Error saving IPTC metadata: $e');
    }
  }

  // Save IPTC metadata in background (no UI refresh)
  Future<void> _saveIptcMetadataBackground() async {
    print('DEBUG: Background save function called');
    if (imagePaths.isEmpty || currentIndex >= imagePaths.length) {
      print('DEBUG: No images or invalid index');
      return;
    }

    // Snapshot caption before async yields (same race-condition fix as _saveIptcMetadata).
    (_captionFieldsKey2.currentState as dynamic)?.storeCurrentCaption();

    final imagePath = imagePaths[currentIndex];
    print('DEBUG: Saving IPTC metadata in background to: $imagePath');

    // Get values from both widgets
    Map<String, String> allValues = {};

    // Note: Metadata values now come from the popup dialog, not from a main UI widget

    // Get caption values from the caption fields widget
    dynamic captionState = _captionFieldsKey2.currentState;
    if (captionState != null) {
      Map<String, String> captionValues =
          captionState.getCurrentCaptionValues();
      allValues.addAll(captionValues);
    }

    if (allValues.isEmpty) {
      print('DEBUG: Could not access widget states for background save');
      return;
    }

    // Preserve location/headline fields if the caption form doesn't provide them.
    void preserveIfMissingBg(String key, List<String> fallbacks) {
      final existing = (allValues[key] ?? '').trim();
      if (existing.isNotEmpty) return;
      for (final fb in fallbacks) {
        final v = currentMetadata?[fb]?.toString().trim() ?? '';
        if (v.isNotEmpty) {
          allValues[key] = v;
          return;
        }
      }
    }

    preserveIfMissingBg('IPTC:Headline', ['IPTC:Headline', 'Headline']);
    preserveIfMissingBg('Headline', ['IPTC:Headline', 'Headline']);
    preserveIfMissingBg('IPTC:CountryPrimaryLocationName', [
      'IPTC:CountryPrimaryLocationName',
      'CountryPrimaryLocationName',
      'Country',
      'XMP:Country'
    ]);
    preserveIfMissingBg('CountryPrimaryLocationName', [
      'IPTC:CountryPrimaryLocationName',
      'CountryPrimaryLocationName',
      'Country',
      'XMP:Country'
    ]);
    preserveIfMissingBg('Country', [
      'IPTC:CountryPrimaryLocationName',
      'CountryPrimaryLocationName',
      'Country',
      'XMP:Country'
    ]);
    preserveIfMissingBg('IPTC:CountryPrimaryLocationCode', [
      'IPTC:CountryPrimaryLocationCode',
      'CountryPrimaryLocationCode',
      'CountryCode'
    ]);
    preserveIfMissingBg('CountryPrimaryLocationCode', [
      'IPTC:CountryPrimaryLocationCode',
      'CountryPrimaryLocationCode',
      'CountryCode'
    ]);
    preserveIfMissingBg('CountryCode', [
      'IPTC:CountryPrimaryLocationCode',
      'CountryPrimaryLocationCode',
      'CountryCode'
    ]);

    print('DEBUG: Background save - allValues: $allValues');

    try {
      // Build exiftool command arguments
      List<String> args = [];

      const clearableFieldsBg = {
        'XMP-getty:Personality',
        'IPTC:Description',
        'Description',
        'Caption-Abstract',
        'IPTC:Caption-Abstract',
        'XMP:Description',
        'ImageDescription',
      };

      // Add each field that has a value; explicitly clear clearable fields when empty
      allValues.forEach((key, value) {
        if (key == 'IPTC:Keywords' ||
            key == 'Keywords' ||
            key == 'Subject' ||
            key == 'XMP:Subject' ||
            key == 'XMP-dc:Subject') {
          return;
        }
        if (value.trim().isNotEmpty) {
          args.add('-$key=$value');
        } else if (clearableFieldsBg.contains(key)) {
          args.add('-$key=');
        }
      });

      // Same IPTC + Subject keyword handling as main save (Photo Mechanic compatibility)
      _appendKeywordsExifArgs(
        args,
        allValues['IPTC:Keywords'] ?? allValues['Keywords'],
      );

      // Handle supplemental categories (merge currentMetadata — same as main save)
      final List<String> rawInputs =
          supplementalCategoryRawInputsForSave(allValues, currentMetadata);

      // Remove any existing supplemental category args to ensure clean state
      args.removeWhere((arg) =>
          arg.startsWith('-SupplementalCategories') ||
          arg.startsWith('-XMP-photoshop:SupplementalCategories'));

      args.addAll(buildSupplementalCategoriesArgs(rawInputs));

      // Always overwrite original file
      args.add('-overwrite_original');
      args.add(imagePath);

      // Only run exiftool if we have metadata to write
      print('DEBUG: Background save - args: $args');
      if (args.length > 2) {
        print('DEBUG: Running exiftool for background save');
        final proc = await ExiftoolHelper.run(args);
        if (proc.exitCode == 0) {
          print('DEBUG: Background IPTC metadata saved successfully');
          if (mounted) {
            setState(() => _savedImages.add(imagePath));
            unawaited(_persistSavedImages());
          }
        } else {
          print('DEBUG: Background exiftool error: ${proc.stderrText}');
        }
      } else {
        print('DEBUG: No metadata to save in background');
      }
    } catch (e) {
      print('Background save error: $e');
    }
  }

  // Refresh the picture preview EXIF data
  void _refreshPicturePreviewExif() {
    print('DEBUG: Attempting to refresh picture preview EXIF data');
    print('DEBUG: Current image index: $currentIndex');
    print(
        'DEBUG: Current image path: ${imagePaths.isNotEmpty ? imagePaths[currentIndex] : "none"}');

    // Try to access the picture preview widget and refresh its EXIF data
    final picturePreviewState2 =
        _picturePreviewKey2.currentState as PicturePreviewWidgetState?;

    if (picturePreviewState2 != null) {
      print('DEBUG: Found picture preview state 2, refreshing EXIF data');
      picturePreviewState2.refreshExifData();
    } else {
      print('DEBUG: No picture preview state found');
    }
  }

  // Parse EXIF DateTime with support for milliseconds
  DateTime _parseExifDateTime(String dateStr, [String? subSecTime]) {
    // Handle EXIF date format: YYYY:MM:DD HH:MM:SS or YYYY:MM:DD HH:MM:SS.sss
    // Replace colons in date part with dashes for ISO format
    String isoStr = dateStr.replaceFirst(':', '-').replaceFirst(':', '-');

    print(
        'DEBUG: _parseExifDateTime called with dateStr="$dateStr", subSecTime="$subSecTime"');

    // Check if milliseconds are present in the main date string
    if (isoStr.contains('.')) {
      // Already has milliseconds, parse directly
      final result = DateTime.parse(isoStr);
      print('DEBUG: Parsed with existing milliseconds: $result');
      return result;
    } else if (subSecTime != null && subSecTime.isNotEmpty) {
      // Combine DateTimeOriginal with SubSecTimeOriginal for milliseconds
      // SubSecTimeOriginal is typically in format like "123" (milliseconds) or "1234" (microseconds)
      int milliseconds = 0;
      try {
        final subSec = int.parse(subSecTime);
        if (subSecTime.length <= 3) {
          // Direct milliseconds
          milliseconds = subSec;
        } else if (subSecTime.length == 4) {
          // Microseconds, convert to milliseconds
          milliseconds = subSec ~/ 10;
        } else if (subSecTime.length == 6) {
          // Nanoseconds, convert to milliseconds
          milliseconds = subSec ~/ 1000000;
        }
        print(
            'DEBUG: Converted subSecTime "$subSecTime" to milliseconds: $milliseconds');
      } catch (e) {
        print('Error parsing SubSecTimeOriginal: $e');
      }

      // Parse the base datetime and add milliseconds
      final baseDateTime = DateTime.parse(isoStr);
      final result = DateTime(
        baseDateTime.year,
        baseDateTime.month,
        baseDateTime.day,
        baseDateTime.hour,
        baseDateTime.minute,
        baseDateTime.second,
        milliseconds,
      );
      print('DEBUG: Combined DateTimeOriginal + SubSecTimeOriginal: $result');
      return result;
    } else {
      // No milliseconds, parse and return with 0 milliseconds
      final result = DateTime.parse(isoStr);
      print('DEBUG: Parsed without milliseconds: $result');
      return result;
    }
  }

  // Sort images by date taken from EXIF DateTimeOriginal
  Future<void> _sortImagesByDateTaken(List<String> imageFiles) async {
    print('Sorting ${imageFiles.length} images by date taken...');

    // Create a list of maps with file path and date taken
    List<Map<String, dynamic>> filesWithDates = [];

    for (int i = 0; i < imageFiles.length; i++) {
      final filePath = imageFiles[i];

      // Update progress during sorting
      if (imageFiles.length > 10) {
        // Only update progress for larger sets
        setState(() {
          _imageLoadingProgress = 0.3 + (0.5 * (i / imageFiles.length));
        });
      }
      try {
        final proc = await ExiftoolHelper.run([
          '-j',
          '-DateTimeOriginal',
          '-SubSecTimeOriginal',
          '-CreateDate',
          '-ModifyDate',
          filePath,
        ]);

        DateTime? dateTime;
        if (proc.exitCode == 0) {
          try {
            final List data = jsonDecode(proc.stdoutText);
            if (data.isNotEmpty) {
              final meta = data.first as Map<String, dynamic>;
              String? dateStr = meta['DateTimeOriginal']?.toString() ??
                  meta['CreateDate']?.toString() ??
                  meta['ModifyDate']?.toString();

              if (dateStr != null) {
                try {
                  // Parse EXIF date format (YYYY:MM:DD HH:MM:SS or YYYY:MM:DD HH:MM:SS.sss)
                  final subSecTime = meta['SubSecTimeOriginal']?.toString();
                  dateTime = _parseExifDateTime(dateStr, subSecTime);
                } catch (e) {
                  print('Error parsing date for $filePath: $e');
                }
              }
            }
          } catch (e) {
            print('Error parsing JSON for $filePath: $e');
          }
        }

        // If no EXIF date found, use file modification date as fallback
        if (dateTime == null) {
          try {
            final file = File(filePath);
            dateTime = await file.lastModified();
            print(
                'DEBUG: Using file modification time for $filePath: $dateTime');
          } catch (e) {
            print('Error getting file date for $filePath: $e');
            dateTime = DateTime.now(); // Ultimate fallback
          }
        } else {
          print('DEBUG: Using EXIF time for $filePath: $dateTime');
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

  /// Shown on Save buttons as "Save (N)" when multiple thumbs are selected for bulk caption.
  int? get _bulkSaveCount =>
      _multiSelectedImages.length > 1 ? _multiSelectedImages.length : null;

  // Clear multi-selection in both parent state and thumbnail grid
  void _clearMultiSelection() {
    if (_multiSelectedImages.isNotEmpty) {
      setState(() {
        _multiSelectedImages = [];
      });
    }
    _thumbnailGridKey.currentState?.clearMultiSelection();
  }

  // Handle image selection (single image navigation)
  void _onImageSelected(int index) {
    // TEMPORARILY DISABLED: Don't save on navigation to prevent conflicts with popup save
    // _saveIptcMetadata(); // DISABLED

    // Clear multi-selection — this is safe because the thumbnail grid no longer
    // calls onImageSelected during Cmd+click (it uses onMultiSelect only).
    _clearMultiSelection();

    // Switch to the selected image
    _switchToImage(index);

    // Return focus to the thumbnail area so arrow keys work immediately
    // after clicking a thumbnail without needing a second click.
    _thumbnailAreaFocusNode.requestFocus();
  }

  // Check if there are unsaved changes (only for the current image, not when switching)
  bool _hasUnsavedChanges() {
    // If we're in the middle of switching images, don't check for changes
    if (_originalCaptionData == null) {
      return false;
    }

    bool hasMetadataChanges = false;
    bool hasCaptionChanges = false;

    // Check metadata changes (using file metadata since main UI widget was removed)
    if (_originalMetadata != null && currentMetadata != null) {
      hasMetadataChanges = !_mapsAreEqual(_originalMetadata!, currentMetadata!);
      if (hasMetadataChanges) {
        print('DEBUG: Metadata changes detected');
      }
    }

    // Check caption changes
    if (_originalCaptionData != null) {
      final captionState = _captionFieldsKey2.currentState;
      if (captionState != null && captionState is State) {
        try {
          final currentCaptionData =
              (captionState as dynamic).getCurrentCaptionValues();
          hasCaptionChanges =
              !_mapsAreEqual(_originalCaptionData!, currentCaptionData);
          if (hasCaptionChanges) {
            print('DEBUG: Caption changes detected');
            print('  Original: $_originalCaptionData');
            print('  Current: $currentCaptionData');
          }
        } catch (e) {
          print('Error getting caption values: $e');
        }
      }
    }

    final hasChanges = hasMetadataChanges || hasCaptionChanges;
    print('DEBUG: _hasUnsavedChanges returning: $hasChanges');
    return hasChanges;
  }

  // Compare two maps for equality
  bool _mapsAreEqual(Map<String, dynamic> map1, Map<String, dynamic> map2) {
    if (map1.length != map2.length) {
      print(
          'DEBUG: Maps have different lengths: ${map1.length} vs ${map2.length}');
      return false;
    }

    for (String key in map1.keys) {
      if (!map2.containsKey(key)) {
        print('DEBUG: Key "$key" missing from second map');
        return false;
      }
      if (map1[key] != map2[key]) {
        print(
            'DEBUG: Value different for key "$key": "${map1[key]}" vs "${map2[key]}"');
        return false;
      }
    }
    return true;
  }

  void _showKeyboardFireDialog() {
    final state = _captionFieldsKey2.currentState;
    if (state == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Switch to a caption layout (not matrix or player popup) to use Keyboard Fire.',
            ),
          ),
        );
      }
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => KeyboardFireDialog(
        homeRoster: _cachedHomeRoster,
        awayRoster: _cachedAwayRoster,
        homeTeamName: selectedHomeTeam,
        awayTeamName: selectedAwayTeam,
        captionState: state,
        bulkSaveCount: _bulkSaveCount,
      ),
    );
  }

  // Show save changes confirmation dialog
  void _showSaveChangesDialog(int newIndex) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Unsaved Changes'),
          content: const Text(
              'You have unsaved changes to the current image. Do you want to save them before switching?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Don't save, just switch
                _switchToImage(newIndex);
              },
              child: const Text('Don\'t Save'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Cancel the switch
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                // Save changes first, then switch
                await _saveCurrentMetadata();
                _switchToImage(newIndex);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // Save current metadata to the current image
  Future<void> _saveCurrentMetadata() async {
    if (currentMetadata != null && imagePaths.isNotEmpty) {
      final currentImagePath = imagePaths[currentIndex];

      // Convert currentMetadata from ExifTool format to template format for _saveMetadataToImage
      final templateMetadata = <String, dynamic>{};

      // Map ExifTool fields back to template display names
      currentMetadata!.forEach((exifToolField, value) {
        switch (exifToolField) {
          case 'Creator':
            templateMetadata['Creator'] = value;
            break;
          case 'TransmissionReference':
            templateMetadata['MEID'] = value;
            break;
          case 'CaptionWriter':
            templateMetadata['Description Writers'] = value;
            break;
          case 'AuthorsPosition':
            templateMetadata['Creator\'s Job Title'] = value;
            break;
          case 'Copyright':
            templateMetadata['Copyright'] = value;
            break;
          case 'Credit':
            templateMetadata['Credit'] = value;
            break;
          case 'Source':
            templateMetadata['Source'] = value;
            break;
          case 'Headline':
            templateMetadata['Headline'] = value;
            break;
          case 'Keywords':
            templateMetadata['Keywords'] = value;
            break;
          case 'SupplementalCategories':
            // Split the comma-separated string back into individual fields
            final categories = value.toString().split(',');
            if (categories.isNotEmpty)
              templateMetadata['Supp Cat 1'] = categories[0].trim();
            if (categories.length > 1)
              templateMetadata['Supp Cat 2'] = categories[1].trim();
            if (categories.length > 2)
              templateMetadata['Supp Cat 3'] = categories[2].trim();
            break;
          case 'Category':
            templateMetadata['Category'] = value;
            break;
          case 'ObjectName':
            templateMetadata['Object Name'] = value;
            break;
          case 'Sub-location':
            templateMetadata['Stadium'] = value;
            break;
          case 'City':
            templateMetadata['City'] = value;
            break;
          case 'Province-State':
            templateMetadata['Province/State'] = value;
            break;
          case 'Country':
            templateMetadata['Country'] = value;
            break;
          case 'CountryCode':
            templateMetadata['Country Code'] = value;
            break;
          case 'Urgency':
            templateMetadata['Urgency'] = value;
            break;
          case 'SpecialInstructions':
          case 'Instructions':
          case 'XMP-photoshop:Instructions':
            templateMetadata['Special Instructions'] = value;
            break;
          case 'Caption-Abstract':
            templateMetadata['Caption'] = value;
            break;
          case 'XMP-getty:Personality':
            templateMetadata['Personality'] = value;
            break;
        }
      });

      // Save both metadata and caption changes
      final saved = await _saveIptcMetadataInternal();
      if (saved.cancelled) return;

      // Update original caption data to mark changes as saved
      final captionState = _captionFieldsKey2.currentState;
      if (captionState != null && captionState is State) {
        try {
          final currentCaptionData =
              (captionState as dynamic).getCurrentCaptionValues();
          _originalCaptionData = Map<String, dynamic>.from(currentCaptionData);
        } catch (e) {
          print('Error updating original caption data: $e');
        }
      }

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Changes saved to ${p.basename(currentImagePath)}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // Switch to a new image (internal method)
  void _switchToImage(int index) {
    setState(() {
      currentIndex = index;
    });

    // Clear the original caption data to prevent false change detection
    _originalCaptionData = null;

    _loadMetadata();
  }

  // Handle image deletion
  void _onImageDeleted(String imagePath) {
    setState(() {
      final deletedIndex = imagePaths.indexOf(imagePath);
      if (deletedIndex >= 0) {
        imagePaths.removeAt(deletedIndex);
        // If an image *before* the current selection is removed, indices shift
        // down by one; without this, the highlight skips the next thumbnail.
        if (deletedIndex < currentIndex) {
          currentIndex--;
        }
        if (imagePaths.isEmpty) {
          currentIndex = 0;
        } else if (currentIndex >= imagePaths.length) {
          currentIndex = imagePaths.length - 1;
        }
      }

      // Remove from uploaded images set
      _uploadedImages.remove(imagePath);
      // Remove from saved images set
      _savedImages.remove(imagePath);

      // Remove from upload progress
      _uploadProgress.remove(imagePath);

      // Remove from EXIF times cache
      _exifTimes?.remove(imagePath);
      _captureDateTimeByPath.remove(imagePath);

      // Remove from XMP data
      _xmpRatings?.remove(imagePath);
      _xmpLabels?.remove(imagePath);
      _xmpTagged?.remove(imagePath);

      // Load metadata for the current image if there are any images left
      if (imagePaths.isNotEmpty) {
        _loadMetadata();
      }
    });
    unawaited(_persistSavedImages());
  }

  // Keyboard-fire-specific copy: copies current UI caption + personality (not stale file metadata)
  void _onKeyboardFireCopy() {
    final cs = _captionFieldsKey2.currentState;
    if (cs == null) return;
    try {
      final dynamic state = cs;
      final caption =
          (state.captionTextController as TextEditingController).text;
      final personality =
          (state.personalityTextController as TextEditingController).text;
      final payload =
          jsonEncode({'caption': caption, 'personality': personality});
      Clipboard.setData(ClipboardData(text: payload));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Caption copied'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('KeyboardFire copy error: $e');
    }
  }

  // Keyboard-fire-specific paste: reads caption + personality from clipboard and
  // updates the UI immediately, then saves to file.
  void _onKeyboardFirePaste() {
    Clipboard.getData(Clipboard.kTextPlain).then((data) async {
      if (data?.text == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Nothing in clipboard'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2)),
        );
        return;
      }
      try {
        final map = jsonDecode(data!.text!) as Map<String, dynamic>;
        final caption = map['caption']?.toString() ?? '';
        final personality = map['personality']?.toString() ?? '';

        // Update UI controllers directly
        final cs = _captionFieldsKey2.currentState;
        if (cs != null) {
          try {
            final dynamic state = cs;
            (state.captionTextController as TextEditingController).text =
                caption;
            (state.personalityTextController as TextEditingController).text =
                personality;
          } catch (_) {}
        }

        // Write to file
        if (imagePaths.isNotEmpty && currentIndex < imagePaths.length) {
          final r = await _saveIptcMetadataInternal();
          if (!mounted) return;
          if (!r.cancelled) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Caption pasted'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2)),
            );
          }
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Caption pasted'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2)),
        );
      } catch (_) {
        // Fallback: try as plain text — just paste into caption field
        final text = data!.text!;
        final cs = _captionFieldsKey2.currentState;
        if (cs != null) {
          try {
            final dynamic state = cs;
            (state.captionTextController as TextEditingController).text = text;
          } catch (_) {}
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Caption pasted'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2)),
        );
      }
    });
  }

  // Handle metadata copy
  void _onCopyMetadata(String imagePath) {
    // Copy current metadata to clipboard
    final metadataJson = jsonEncode(currentMetadata);
    Clipboard.setData(ClipboardData(text: metadataJson));

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Metadata copied from ${p.basename(imagePath)}'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Handle metadata paste
  void _onPasteMetadata(String imagePath) {
    // Get metadata from clipboard
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      if (data?.text != null) {
        try {
          final Map<String, dynamic> pastedMetadata = jsonDecode(data!.text!);

          // Save the metadata directly to the specific image using exiftool
          _saveMetadataToImage(imagePath, pastedMetadata);

          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Metadata pasted to ${p.basename(imagePath)}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } catch (e) {
          // Show error if clipboard doesn't contain valid metadata
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No valid metadata found in clipboard'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No data found in clipboard'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  // Handle IPTC template application to a single image
  void _onApplyIptcTemplate(String imagePath) async {
    // Load the default IPTC template from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final defaultTemplateJson = prefs.getString('default_metadata_template');

    if (defaultTemplateJson != null) {
      try {
        final Map<String, dynamic> templateMetadata =
            jsonDecode(defaultTemplateJson);

        // Save the template metadata to the specific image
        await _saveMetadataToImage(imagePath, templateMetadata);

        // Check if this is the currently selected image and update UI if so
        if (imagePaths.isNotEmpty &&
            currentIndex < imagePaths.length &&
            imagePaths[currentIndex] == imagePath) {
          // Convert template display names to ExifTool field names for UI update
          final uiMetadata = <String, dynamic>{};

          // Collect supplemental categories to combine them
          List<String> suppCats = [];
          if (templateMetadata['Supp Cat 1']?.toString().isNotEmpty == true) {
            suppCats.add(templateMetadata['Supp Cat 1']!);
          }
          if (templateMetadata['Supp Cat 2']?.toString().isNotEmpty == true) {
            suppCats.add(templateMetadata['Supp Cat 2']!);
          }
          if (templateMetadata['Supp Cat 3']?.toString().isNotEmpty == true) {
            suppCats.add(templateMetadata['Supp Cat 3']!);
          }

          templateMetadata.forEach((displayName, value) {
            // Special handling for supplemental categories - combine into single field
            if (displayName == 'Supp Cat 1' ||
                displayName == 'Supp Cat 2' ||
                displayName == 'Supp Cat 3') {
              // Skip individual fields, we'll add the combined one
              return;
            } else {
              final exifToolField = _mapTemplateFieldToExifTool(displayName);
              uiMetadata[exifToolField] = value;
            }
          });

          // Add combined supplemental categories
          if (suppCats.isNotEmpty) {
            uiMetadata['SupplementalCategories'] = suppCats.join(',');
          }

          // Update the current metadata and original metadata to reflect the applied template
          setState(() {
            currentMetadata = uiMetadata;
            _originalMetadata = Map<String, dynamic>.from(uiMetadata);
          });
        }

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('IPTC template applied to ${p.basename(imagePath)}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (e) {
        // Show error if template is invalid
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error applying IPTC template'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      // Show error if no template is saved
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No IPTC template found. Please create one first.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // Map template display names to Photo Mechanic's preferred ExifTool field names
  String _mapTemplateFieldToExifTool(String templateField) {
    switch (templateField) {
      case 'Creator':
        return 'IPTC:By-line'; // Photo Mechanic's preferred field
      case 'MEID':
        return 'IPTC:OriginalTransmissionReference'; // Photo Mechanic's preferred field
      case 'Description Writers':
        return 'CaptionWriter';
      case 'Creator\'s Job Title':
        return 'IPTC:By-lineTitle'; // Photo Mechanic's preferred field
      case 'Copyright':
        return 'IPTC:CopyrightNotice'; // Photo Mechanic's preferred field
      case 'Credit':
        return 'IPTC:Credit'; // Photo Mechanic's preferred field
      case 'Source':
        return 'IPTC:Source'; // Photo Mechanic's preferred field
      case 'Headline':
        return 'IPTC:Headline'; // Photo Mechanic's preferred field
      case 'Keywords':
        return 'IPTC:Keywords'; // Photo Mechanic's preferred field
      case 'Supp Cat 1':
      case 'Supp Cat 2':
      case 'Supp Cat 3':
        return 'SupplementalCategories';
      case 'Category':
        return 'IPTC:Category'; // Photo Mechanic's preferred field
      case 'Object Name':
        return 'IPTC:ObjectName'; // Photo Mechanic's preferred field
      case 'Stadium':
        return 'IPTC:Sub-location'; // Photo Mechanic's preferred field (FIXED)
      case 'City':
        return 'IPTC:City'; // Photo Mechanic's preferred field
      case 'Province/State':
        return 'IPTC:Province-State'; // Photo Mechanic's preferred field (FIXED)
      case 'Country':
        return 'IPTC:Country-Primary-Location-Name'; // Photo Mechanic's preferred field (FIXED)
      case 'Country Code':
        return 'IPTC:Country-Primary-Location-Code'; // Photo Mechanic's preferred field (FIXED)

      case 'Special Instructions':
        return 'IPTC:Special-Instructions'; // Photo Mechanic's preferred field (FIXED)
      case 'Personality':
        return 'XMP-getty:Personality';
      case 'Caption':
        return 'IPTC:Caption-Abstract'; // Photo Mechanic's preferred field (FIXED)
      case 'Date':
        return 'TimeDate';
      case 'Time':
        return 'TimeDate';
      default:
        return templateField;
    }
  }

  // Save metadata directly to a specific image file using the exact same logic as the working batch function
  Future<void> _saveMetadataToImage(
      String imagePath, Map<String, dynamic> metadata) async {
    print('DEBUG: _saveMetadataToImage called with: $imagePath');

    // Get values from metadata widget in the exact same way as the working batch path
    Map<String, String> allValues = {};

    // Convert template metadata to the same format that _saveIptcMetadata uses
    metadata.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) {
        // Never write date/time from template
        if (key == 'Date' || key == 'Time') return;

        // Special handling for supplemental categories to match batch function format
        if (key == 'Supp Cat 1') {
          allValues['SupplementalCategories1'] = value.toString();
        } else if (key == 'Supp Cat 2') {
          allValues['SupplementalCategories2'] = value.toString();
        } else if (key == 'Supp Cat 3') {
          allValues['SupplementalCategories3'] = value.toString();
        } else {
          // Map other template display names to ExifTool field names
          final exifToolField = _mapTemplateFieldToExifTool(key);
          allValues[exifToolField] = value.toString();
        }
      }
    });

    print('DEBUG: Converted to allValues format: $allValues');

    try {
      // Build exiftool command arguments using EXACT same logic as _saveIptcMetadata
      List<String> args = [];

      // Add each field that has a value
      allValues.forEach((key, value) {
        if (value.trim().isNotEmpty) {
          args.add('-$key=$value');
        }
      });

      final List<String> rawInputs =
          supplementalCategoryRawInputsForSave(allValues, metadata);

      // Remove any existing supplemental category args to ensure clean state
      args.removeWhere((arg) =>
          arg.startsWith('-SupplementalCategories') ||
          arg.startsWith('-XMP-photoshop:SupplementalCategories'));

      args.addAll(buildSupplementalCategoriesArgs(rawInputs));

      // Always overwrite original file
      args.add('-overwrite_original');
      args.add(imagePath);

      print('DEBUG: Final exiftool args: $args');
      final proc = await ExiftoolHelper.run(args);

      if (proc.exitCode == 0) {
        print('DEBUG: Successfully saved metadata to $imagePath');
      } else {
        print('DEBUG: Exiftool error: ${proc.stderrText}');
      }
    } catch (e) {
      print('DEBUG: Error saving metadata: $e');
    }
  }

  // Save ExifTool-style metadata directly to a specific image file
  Future<void> _saveExifToolMetadataToImage(
      String imagePath, Map<String, dynamic> metadata) async {
    try {
      // Build exiftool command arguments directly from ExifTool-style metadata
      List<String> args = [];

      // Supplemental categories: merge split keys + combined IPTC/XMP (same as main save)
      final Map<String, String> suppAllValues = metadata.map(
        (k, v) => MapEntry(k, v?.toString() ?? ''),
      );
      final List<String> rawInputs =
          supplementalCategoryRawInputsForSave(suppAllValues, metadata);

      // Clone metadata to allow removals (e.g., keywords keys)
      final Map<String, dynamic> md = Map<String, dynamic>.from(metadata);

      // KEYWORDS ARE NOW HANDLED EXCLUSIVELY BY THE POPUP - MAIN SAVE IGNORES ALL KEYWORD FIELDS
      // This prevents the main save from overwriting popup keyword changes

      // Remove any keyword-related keys so they are not written generically below
      md.remove('IPTC:Keywords');
      md.remove('Keywords');
      md.remove('XMP:Subject');
      md.remove('XMP-dc:Subject');
      md.remove('Subject');
      md.remove('KeywordsTest');

      // Add each field that has a value
      md.forEach((key, value) {
        if (value != null && value.toString().trim().isNotEmpty) {
          // Skip date/time fields as they shouldn't be modified
          if ([
            'Date',
            'Time',
            'DateTimeOriginal',
            'CreateDate',
            'ModifyDate',
            'FileModifyDate'
          ].contains(key)) {
            return;
          }

          // Skip individual supplemental fields here; we'll add combined value once
          if (key == 'SupplementalCategories' ||
              key == 'SupplementalCategories1' ||
              key == 'SupplementalCategories2' ||
              key == 'SupplementalCategories3') {
            return;
          }

          args.add('-$key=${value.toString()}');
        }
      });

      // Handle supplemental categories with overwrite semantics
      args.addAll(buildSupplementalCategoriesArgs(rawInputs));

      // Always overwrite original file; keep times and ensure IPTC UTF-8
      args.addAll(['-overwrite_original', '-P', '-m', '-charset', 'iptc=UTF8']);
      args.add(imagePath);

      // Only run exiftool if we have metadata to write
      if (args.length > 2) {
        // More than just -overwrite_original and path
        final proc = await ExiftoolHelper.run(args);

        if (proc.exitCode == 0) {
        } else {}
      } else {
        print('DEBUG: No metadata values to save');
      }
    } catch (e) {
      print('DEBUG: Error saving ExifTool metadata: $e');
    }
  }

  // Apply metadata to all images in the session
  Future<void> _applyMetadataToAllImages(Map<String, String> metadata) async {
    if (imagePaths.isEmpty) return;

    print('Applying metadata to all ${imagePaths.length} images...');

    // Filter out locked files
    final writableImages =
        imagePaths.where((path) => !_lockedPaths.contains(path)).toList();

    if (writableImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No writable images found to apply metadata to.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Show progress dialog with progress bar
    ValueNotifier<int> processedNotifier = ValueNotifier<int>(0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return ValueListenableBuilder<int>(
          valueListenable: processedNotifier,
          builder: (context, processedCount, child) {
            return Dialog(
              child: Container(
                width: 400,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with title
                    Row(
                      children: [
                        Icon(Icons.settings,
                            size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 6),
                        Text(
                          'Applying IPTC Metadata',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Progress text
                    Text(
                      'Processed $processedCount of ${writableImages.length} images',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Progress bar
                    LinearProgressIndicator(
                      value: writableImages.length > 0
                          ? processedCount / writableImages.length
                          : 0.0,
                      backgroundColor: Colors.grey.shade300,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                    const SizedBox(height: 6),

                    // Percentage
                    Text(
                      '${writableImages.length > 0 ? ((processedCount / writableImages.length) * 100).toInt() : 0}%',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    // Ensure the dialog renders before heavy work begins
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      // Convert metadata to exiftool format
      Map<String, dynamic> exifMetadata = {};

      // Map the metadata fields to exiftool field names
      metadata.forEach((key, value) {
        if (value.isNotEmpty) {
          switch (key) {
            case 'Creator':
              exifMetadata['By-line'] = value;
              exifMetadata['XMP:Creator'] = value;
              break;
            case 'MEID':
              exifMetadata['TransmissionReference'] = value;
              break;
            case 'Description Writers':
              exifMetadata['CaptionWriter'] = value;
              break;
            case 'Creator\'s Job Title':
              exifMetadata['By-lineTitle'] = value;
              exifMetadata['AuthorsPosition'] = value;
              break;
            case 'Copyright':
              exifMetadata['CopyrightNotice'] = value;
              exifMetadata['XMP:Rights'] = value;
              break;
            case 'Credit':
              exifMetadata['Credit'] = value;
              break;
            case 'Source':
              exifMetadata['Source'] = value;
              exifMetadata['XMP:Source'] = value;
              break;
            case 'Headline':
              exifMetadata['Headline'] = value;
              exifMetadata['XMP:Title'] = value;
              break;
            case 'Keywords':
              exifMetadata['Keywords'] = value;
              // Do not mirror to XMP:Subject here; we handle keywords centrally when building exiftool args
              break;
            case 'Supp Cat 1':
            case 'Supp Cat 2':
            case 'Supp Cat 3':
              // Handle supplemental categories
              if (!exifMetadata.containsKey('SupplementalCategories')) {
                exifMetadata['SupplementalCategories'] = [];
              }
              (exifMetadata['SupplementalCategories'] as List).add(value);
              break;
            case 'Category':
              exifMetadata['Category'] = value;
              break;
            case 'Object Name':
              exifMetadata['ObjectName'] = value;
              break;
            case 'Stadium':
              exifMetadata['Sub-location'] = value;
              exifMetadata['XMP:Location'] = value;
              break;
            case 'City':
              exifMetadata['City'] = value;
              exifMetadata['XMP:City'] = value;
              break;
            case 'Province/State':
              exifMetadata['Province-State'] = value;
              exifMetadata['XMP:State'] = value;
              break;
            case 'Country':
              exifMetadata['Country-PrimaryLocationName'] = value;
              exifMetadata['XMP:Country'] = value;
              break;
            case 'Country Code':
              exifMetadata['Country-PrimaryLocationCode'] = value;
              break;
            case 'Urgency':
              exifMetadata['Urgency'] = value;
              break;
            case 'Special Instructions':
              exifMetadata['SpecialInstructions'] = value;
              exifMetadata['XMP:Instructions'] = value;
              break;
            case 'Personality':
              exifMetadata['XMP-getty:Personality'] = value;
              break;
            case 'Caption':
              exifMetadata['Caption-Abstract'] = value;
              exifMetadata['ImageDescription'] = value;
              break;
            case 'Date':
            case 'Time':
              // Handle date/time separately if needed
              break;
          }
        }
      });

      // Build exiftool arguments once
      // Include common flags to improve reliability on IPTC writes
      List<String> args = [
        '-overwrite_original',
        '-P',
        '-m',
        '-charset',
        'iptc=UTF8'
      ];
      exifMetadata.forEach((key, value) {
        if (value != null && value.toString().isNotEmpty) {
          if (key == 'SupplementalCategories' && value is List) {
            args.addAll(['-$key=${value.join(',')}']);
          } else {
            args.addAll(['-$key=$value']);
          }
        }
      });

      // Process images in batches for better performance
      const int batchSize = 5;
      int processedCount = 0;
      int totalImages = writableImages.length;
      String? lastError;

      for (int i = 0; i < writableImages.length; i += batchSize) {
        final batch = writableImages.skip(i).take(batchSize).toList();

        // Create batch command
        List<String> batchArgs = List.from(args);
        batchArgs.addAll(batch);

        try {
          final proc = await ExiftoolHelper.run(batchArgs);
          if (proc.exitCode == 0) {
            processedCount += batch.length;
            print(
                'Successfully processed batch ${(i ~/ batchSize) + 1}: ${batch.length} images (Total: $processedCount/$totalImages)');
          } else {
            print('Error processing batch: ${proc.stderrText}');
            lastError = proc.stderrText;
          }
        } catch (e) {
          print('Error processing batch: $e');
          lastError = e.toString();
        }

        // Update progress counter and yield a frame
        processedNotifier.value = processedCount;
        await Future.delayed(const Duration(milliseconds: 16));
      }

      // Close progress dialog
      if (mounted) {
        Navigator.of(context).pop();
      }
      processedNotifier.dispose();

      if (processedCount > 0) {
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Metadata applied to $processedCount of $totalImages images successfully!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        // Show error if nothing was processed
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'No images updated. ExifTool error: ${lastError ?? 'Unknown error'}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      // Close progress dialog
      if (mounted) {
        Navigator.of(context).pop();
      }
      processedNotifier.dispose();

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error applying metadata: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Check and apply metadata preset to all images if enabled
  Future<void> _checkAndApplyMetadataPreset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final applyToAllImages =
          prefs.getBool('apply_preset_to_all_images') ?? false;

      if (applyToAllImages) {
        final presetJson = prefs.getString('selected_metadata_preset');
        if (presetJson != null) {
          final presetData = jsonDecode(presetJson) as Map<String, dynamic>;
          final metadata = Map<String, String>.from(presetData);

          // Apply metadata to all images
          await _applyMetadataToAllImages(metadata);

          // Clear the flag after applying
          await prefs.setBool('apply_preset_to_all_images', false);
        }
      }
    } catch (e) {
      print('Error checking/applying metadata preset: $e');
    }
  }

  // Handle FTP image - Add to queue and process
  Future<void> _onFtpImage(String imagePath) async {
    print('DEBUG: _onFtpImage called for: $imagePath');

    // Check if already uploaded, uploading, or queued
    if (_uploadedImages.contains(imagePath)) {
      // Show dialog asking if user wants to upload again
      final shouldUpload = await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: Colors.black, width: 1),
          ),
          backgroundColor: Colors.white,
          child: Container(
            padding: const EdgeInsets.all(16),
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.black, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Already Uploaded',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${p.basename(imagePath)} has already been uploaded. Do you want to upload again?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          'Upload Again',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      if (shouldUpload != true) {
        return; // User cancelled
      }

      // Remove from uploaded images so it can be uploaded again
      setState(() {
        _uploadedImages.remove(imagePath);
        _uploadProgress.remove(imagePath);
      });
    }

    if (_currentlyUploading.contains(imagePath)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${p.basename(imagePath)} is currently uploading'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_queuedUploads.contains(imagePath)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${p.basename(imagePath)} is already queued'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Add to queue and initialize progress
    setState(() {
      _queuedUploads.add(imagePath);
      _uploadProgress[imagePath] =
          0.0; // Initialize progress so monitor shows immediately
    });

    // Try to process queue
    _processUploadQueue();
  }

  // Process the upload queue (max 2 concurrent uploads)
  void _processUploadQueue() {
    // Get the caption fields widget state to access FTP functionality
    dynamic captionState = _captionFieldsKey2.currentState;
    if (captionState == null) {
      print('DEBUG: Caption fields state not available for FTP');
      return;
    }

    // Process queue while we have capacity (max 2 concurrent uploads)
    while (_currentlyUploading.length < 2 && _queuedUploads.isNotEmpty) {
      final imagePath = _queuedUploads.first;
      _queuedUploads.remove(imagePath);
      _currentlyUploading.add(imagePath);

      print('DEBUG: Starting upload for: $imagePath');
      print('DEBUG: Currently uploading: ${_currentlyUploading.length}/2');
      print('DEBUG: Queued: ${_queuedUploads.length}');

      // Initialize progress to 0.0 when upload starts
      setState(() {
        _uploadProgress[imagePath] = 0.0;
      });

      // Start the upload
      captionState.uploadImageViaFtp(imagePath).then((_) {
        // Upload successful
        setState(() {
          _uploadedImages.add(imagePath);
          _currentlyUploading.remove(imagePath);
          _uploadProgress[imagePath] =
              1.0; // Set to 1.0 to show "Upload complete"
        });
        print('DEBUG: Successfully FTPd and marked: $imagePath');

        // Process next item in queue
        _processUploadQueue();
      }).catchError((error) {
        // Upload failed
        setState(() {
          _currentlyUploading.remove(imagePath);
          _uploadProgress.remove(imagePath); // Clear progress
        });
        print('DEBUG: FTP failed for $imagePath: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('FTP failed for ${p.basename(imagePath)}: $error'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );

        // Process next item in queue
        _processUploadQueue();
      });
    }
  }

  // Handle multi-selection from thumbnail grid
  void _onMultiSelect(List<String> selectedPaths) {
    print('Multi-selection: ${selectedPaths.length} images selected');
    setState(() {
      _multiSelectedImages = List.from(selectedPaths);
    });
    // Update currentIndex to the last selected image so caption fields load its data
    if (selectedPaths.isNotEmpty) {
      final lastPath = selectedPaths.last;
      final idx = imagePaths.indexOf(lastPath);
      if (idx != -1 && idx != currentIndex) {
        _switchToImage(idx);
      }
    }
  }

  // Handle image rename
  void _onImageRenamed(String oldPath, String newPath) {
    setState(() {
      // Update the image path in the list
      final index = imagePaths.indexOf(oldPath);
      if (index != -1) {
        imagePaths[index] = newPath;

        // Update uploaded images set if it was there
        if (_uploadedImages.contains(oldPath)) {
          _uploadedImages.remove(oldPath);
          _uploadedImages.add(newPath);
        }
        // Update saved images set if it was there
        if (_savedImages.contains(oldPath)) {
          _savedImages.remove(oldPath);
          _savedImages.add(newPath);
        }

        // Update upload progress if it was there
        if (_uploadProgress.containsKey(oldPath)) {
          final progress = _uploadProgress[oldPath]!;
          _uploadProgress.remove(oldPath);
          _uploadProgress[newPath] = progress;
        }

        // Update queue state if it was there
        if (_queuedUploads.contains(oldPath)) {
          _queuedUploads.remove(oldPath);
          _queuedUploads.add(newPath);
        }

        // Update currently uploading if it was there
        if (_currentlyUploading.contains(oldPath)) {
          _currentlyUploading.remove(oldPath);
          _currentlyUploading.add(newPath);
        }

        // Update EXIF times if they were cached
        if (_exifTimes?.containsKey(oldPath) ?? false) {
          final time = _exifTimes![oldPath]!;
          _exifTimes!.remove(oldPath);
          _exifTimes![newPath] = time;
        }
        if (_captureDateTimeByPath.containsKey(oldPath)) {
          final dt = _captureDateTimeByPath.remove(oldPath)!;
          _captureDateTimeByPath[newPath] = dt;
        }

        // Update XMP ratings if they were cached
        if (_xmpRatings?.containsKey(oldPath) ?? false) {
          final rating = _xmpRatings![oldPath]!;
          _xmpRatings!.remove(oldPath);
          _xmpRatings![newPath] = rating;
        }

        // Update XMP labels if they were cached
        if (_xmpLabels?.containsKey(oldPath) ?? false) {
          final label = _xmpLabels![oldPath]!;
          _xmpLabels!.remove(oldPath);
          _xmpLabels![newPath] = label;
        }

        // Update XMP tagged if they were cached
        if (_xmpTagged?.containsKey(oldPath) ?? false) {
          final tagged = _xmpTagged![oldPath]!;
          _xmpTagged!.remove(oldPath);
          _xmpTagged![newPath] = tagged;
        }

        // Update locked paths if it was there
        if (_lockedPaths?.contains(oldPath) ?? false) {
          _lockedPaths!.remove(oldPath);
          _lockedPaths!.add(newPath);
        }
      }
    });
    unawaited(_persistSavedImages());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleSaveAndNextShortcut);
    HardwareKeyboard.instance.removeHandler(_handleSaveFtpNextShortcut);
    HardwareKeyboard.instance.removeHandler(_handlePastePreviousKeyEvent);
    HardwareKeyboard.instance.removeHandler(_handleOptionVerbShortcut);
    _optionVerbBufferTimer?.cancel();
    _thumbnailScrollController.dispose();
    _thumbnailAreaFocusNode.dispose();
    _stopFolderWatcher();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Build the main app content
    Widget mainAppContent = Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Column(
        children: [
          // App header
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Text(
                  'FLO FILE',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                if (_isStartupComplete) ...[
                  Text(
                    'Ready to configure...',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Main content area
          Expanded(
            child: Container(
              color: Colors.grey.shade50,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_open,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Select your images folder to begin',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Configure teams and game date',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // Show sport selection dialog first if sport not selected
    if (!_isSportSelected) {
      return Stack(
        children: [
          // Main app in background
          mainAppContent,
          // Semi-transparent overlay
          Container(
            color: Colors.black.withOpacity(0.3),
            child: Center(
              child: SportSelectionDialog(
                onSportSelected: _handleSportSelected,
              ),
            ),
          ),
        ],
      );
    }

    // Show startup dialog overlay if configuration is not complete
    if (!_isStartupComplete) {
      return Stack(
        children: [
          // Main app in background
          mainAppContent,
          // Semi-transparent overlay
          Container(
            color: Colors.black.withOpacity(0.3),
            child: Center(
              child: StartupDialog(
                onConfigurationComplete: _handleStartupComplete,
                sport: _selectedSport,
                onBackToSportSelection: () {
                  setState(() => _isSportSelected = false);
                },
              ),
            ),
          ),
        ],
      );
    }

    // Show loading screen for players or images
    if (_isLoadingPlayers || _isLoadingImages) {
      return Scaffold(
        backgroundColor: Colors.grey.shade100,
        body: Center(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'FLO FILE',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  _isLoadingPlayers
                      ? 'Loading Players...'
                      : 'Loading Images...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: _isLoadingPlayers
                      ? _playerLoadingProgress
                      : _imageLoadingProgress,
                  backgroundColor: Colors.grey.shade200,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                ),
                const SizedBox(height: 8),
                Text(
                  '${((_isLoadingPlayers ? _playerLoadingProgress : _imageLoadingProgress) * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppHeaderWidget(
        cameraService: _cameraService,
        onImagesLoaded: (images) {
          print('CaptionBuilderScreen received ${images.length} images');
          setState(() {
            imagePaths = images;
            currentIndex = 0;
          });
          print(
              'Updated state: ${imagePaths.length} images, currentIndex: $currentIndex');

          // Load metadata for the first image
          if (images.isNotEmpty) {
            _loadMetadata();
          }
        },
        onStartFolderWatcher: _startFolderWatcher,
        onHomeTeamChanged: (team) {
          setState(() {
            selectedHomeTeam = team;
          });
        },
        onAwayTeamChanged: (team) {
          setState(() {
            selectedAwayTeam = team;
          });
        },
        onApiChanged: (api) {
          setState(() {
            selectedApi = api;
          });
          print('API changed in main screen: $api');
        },
        currentLayout: _currentLayout,
        onLayoutChanged: (String newLayout) async {
          setState(() {
            _currentLayout = newLayout;
          });
          // Save to preferences
          final preferencesService = await PreferencesService.getInstance();
          await preferencesService.saveCurrentLayout(newLayout);
        },
        onPreferencesClosed: () async {
          final preferencesService = await PreferencesService.getInstance();
          final mode = await preferencesService.getCaptionEntryMode();
          final burst = await preferencesService.getBurstDetectionEnabled();
          if (mounted) {
            setState(() {
              _useKeyboardFireAsDefault = mode == 'keyboard_fire';
              _burstDetectionEnabled = burst;
            });
          }
        },
        onBurstDetectionChanged: (enabled) {
          if (mounted) setState(() => _burstDetectionEnabled = enabled);
        },
        onOpenFtpSettings: () {
          try {
            (_captionFieldsKey2.currentState as dynamic)?.showFtpSettings();
          } catch (_) {}
        },
      ),
      body: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.keyV, meta: true, shift: true):
                _PastePreviousCaptionIntent(),
            SingleActivator(LogicalKeyboardKey.enter, meta: true):
                _SaveAndNextIntent(),
            SingleActivator(LogicalKeyboardKey.arrowLeft):
                _PreviousImageIntent(),
            SingleActivator(LogicalKeyboardKey.arrowUp): _PreviousRowIntent(),
            SingleActivator(LogicalKeyboardKey.arrowRight): _NextImageIntent(),
            SingleActivator(LogicalKeyboardKey.arrowDown): _NextRowIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _PastePreviousCaptionIntent:
                  CallbackAction<_PastePreviousCaptionIntent>(
                onInvoke: (_) {
                  final state = _captionFieldsKey2.currentState;
                  (state as dynamic)?.pasteLastCaption();
                  return null;
                },
              ),
              _SaveAndNextIntent: CallbackAction<_SaveAndNextIntent>(
                onInvoke: (_) async {
                  await _saveCurrentMetadata();
                  if (!mounted) return null;
                  if (currentIndex < imagePaths.length - 1) {
                    setState(() {
                      currentIndex = currentIndex + 1;
                    });
                    _loadMetadata();
                  }
                  return null;
                },
              ),
              _PreviousImageIntent: _ConditionalArrowAction(
                consumesKeyWhen: () => !_isTextInputFocused(),
                onInvoke: (_) {
                  if (_isTextInputFocused()) return null;
                  if (imagePaths.isEmpty) return null;
                  _clearMultiSelection();
                  if (currentIndex > 0) {
                    setState(() => _thumbCenterRequestId++);
                    _onImageSelected(currentIndex - 1);
                  }
                  return null;
                },
              ),
              _NextImageIntent: _ConditionalArrowAction(
                consumesKeyWhen: () => !_isTextInputFocused(),
                onInvoke: (_) {
                  if (_isTextInputFocused()) return null;
                  if (imagePaths.isEmpty) return null;
                  _clearMultiSelection();
                  if (currentIndex < imagePaths.length - 1) {
                    setState(() => _thumbCenterRequestId++);
                    _onImageSelected(currentIndex + 1);
                  }
                  return null;
                },
              ),
              _PreviousRowIntent: _ConditionalArrowAction(
                consumesKeyWhen: () => !_isTextInputFocused(),
                onInvoke: (_) {
                  if (_isTextInputFocused()) return null;
                  _clearMultiSelection();
                  return _handleArrowUpDownByRow(up: true);
                },
              ),
              _NextRowIntent: _ConditionalArrowAction(
                consumesKeyWhen: () => !_isTextInputFocused(),
                onInvoke: (_) {
                  if (_isTextInputFocused()) return null;
                  _clearMultiSelection();
                  return _handleArrowUpDownByRow(up: false);
                },
              ),
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 1.0, 4.0, 0.0),
              child: _buildLayout(),
            ),
          ),
        ),
    );
  }

  bool _isTextInputFocused() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return false;
    final context = primary.context;
    if (context == null) return false;
    if (context.widget is EditableText) return true;
    if (context.findAncestorWidgetOfExactType<EditableText>() != null) {
      return true;
    }
    if (context.findAncestorStateOfType<EditableTextState>() != null) {
      return true;
    }
    return false;
  }

  Object? _handleArrowUpDownByRow({required bool up}) {
    if (imagePaths.isEmpty || !mounted) return null;
    final direction = up ? -1 : 1;
    final nextIndex =
        _thumbnailGridKey.currentState?.getNextIndexVertical(direction);
    if (nextIndex != null && nextIndex != currentIndex) {
      setState(() => _thumbCenterRequestId++);
      _onImageSelected(nextIndex);
    }
    return null;
  }

  void _handleThumbnailAreaKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final k = event.logicalKey;
    if (imagePaths.isEmpty || !mounted) return;

    if (k == LogicalKeyboardKey.arrowLeft) {
      if (currentIndex > 0) {
        setState(() => _thumbCenterRequestId++);
        _onImageSelected(currentIndex - 1);
      }
      return;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (currentIndex < imagePaths.length - 1) {
        setState(() => _thumbCenterRequestId++);
        _onImageSelected(currentIndex + 1);
      }
      return;
    }
    // Up/Down: move one row in the visible grid (same column) so it doesn't go diagonal
    if (k == LogicalKeyboardKey.arrowUp) {
      final nextIndex =
          _thumbnailGridKey.currentState?.getNextIndexVertical(-1);
      if (nextIndex != null && nextIndex != currentIndex) {
        setState(() => _thumbCenterRequestId++);
        _onImageSelected(nextIndex);
      }
      return;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      final nextIndex = _thumbnailGridKey.currentState?.getNextIndexVertical(1);
      if (nextIndex != null && nextIndex != currentIndex) {
        setState(() => _thumbCenterRequestId++);
        _onImageSelected(nextIndex);
      }
    }
  }

  /// Wraps the thumbnail+preview column so a click there focuses it and arrow keys (incl. Up/Down) move selection.
  Widget _wrapThumbnailAreaWithFocus(Widget child) {
    return Listener(
      onPointerDown: (_) => _thumbnailAreaFocusNode.requestFocus(),
      child: KeyboardListener(
        focusNode: _thumbnailAreaFocusNode,
        autofocus: true,
        onKeyEvent: _handleThumbnailAreaKey,
        child: child,
      ),
    );
  }

  // Build layout based on current layout preference
  Widget _buildLayout() {
    switch (_currentLayout) {
      case 'players_list_left':
        return _buildPlayersListLeftLayout();
      case 'players_list_right':
        return _buildPlayersListRightLayout();
      case 'players_list_top':
        return _buildPlayersListTopLayout();
      case 'players_list_bottom':
        return _buildPlayersListBottomLayout();
      case 'compact_players_above':
        return _buildCompactPlayersAboveLayout();
      case 'matrix_board':
        return _buildMatrixBoardLayout();
      case 'player_popup_board':
        return _buildPlayerPopupLayout();
      default:
        return _buildPlayersListLeftLayout();
    }
  }

  /// Wraps caption UI: when [Keyboard Fire] is default, shows panel with classic widget offstage for state; otherwise shows classic only.
  /// Uses StackFit.expand so the Stack expands to fill whatever space it is given.
  Widget _buildCaptionEntryWidget(Widget captionWidget) {
    late final Widget entry;
    if (!_useKeyboardFireAsDefault) {
      entry = captionWidget;
    } else {
    final cs = _captionFieldsKey2.currentState;
    // If the CaptionFieldsWidget hasn't mounted yet (first frame), schedule a
    // rebuild so KeyboardFirePanel receives a non-null captionState immediately
    // after mount — without this, the caption text field in the panel renders
    // as a disconnected fallback and manual typing is never saved.
    if (cs == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    final dynamic state = cs;
    entry = Stack(
      fit: StackFit.expand,
      children: [
        Offstage(offstage: true, child: captionWidget),
        KeyboardFirePanel(
          homeRoster: _cachedHomeRoster,
          awayRoster: _cachedAwayRoster,
          homeTeamName: selectedHomeTeam,
          awayTeamName: selectedAwayTeam,
          captionState: cs,
          showDialogActions: false,
          currentIndex: imagePaths.isNotEmpty ? currentIndex : null,
          totalImages: imagePaths.length,
          onPreviousImage: () {
            if (currentIndex > 0) {
              setState(() => _thumbCenterRequestId++);
              _onImageSelected(currentIndex - 1);
            }
          },
          onNextImage: () {
            if (currentIndex < imagePaths.length - 1) {
              setState(() => _thumbCenterRequestId++);
              _onImageSelected(currentIndex + 1);
            }
          },
          onSaveIptc: _saveIptcMetadata,
          bulkSaveCount: _bulkSaveCount,
          onFtp: cs != null
              ? () {
                  try {
                    state.triggerFtp();
                  } catch (_) {}
                }
              : null,
          onFtpSettings: cs != null
              ? () {
                  try {
                    state.showFtpSettings();
                  } catch (_) {}
                }
              : null,
          onReset: _handleReset,
          onCopy: _onKeyboardFireCopy,
          onPaste: _onKeyboardFirePaste,
          onPastePrevious: cs != null
              ? () {
                  try {
                    state.pastePreviousCaption();
                  } catch (_) {}
                }
              : null,
          ftpDisabled: cs != null
              ? (() {
                  try {
                    return state.isFtpDisabled as bool;
                  } catch (_) {
                    return false;
                  }
                })()
              : false,
          currentFtpProfile: cs != null
              ? (() {
                  try {
                    return state.currentFtpProfile as String?;
                  } catch (_) {
                    return null;
                  }
                })()
              : null,
        ),
      ],
    );
    }
    return ColoredBox(
      color: Colors.grey.shade50,
      child: entry,
    );
  }

  // Current layout: Players List Left (default)
  Widget _buildPlayersListLeftLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // LEFT COLUMN - Picture Preview and Thumbnails
        Expanded(
          flex: 4,
          child: _wrapThumbnailAreaWithFocus(
            Column(
              children: [
                // Resolution warning (if applicable)
                _buildResolutionWarning(),

                // Picture preview - 50% of screen height
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: PicturePreviewWidget(
                    key: _picturePreviewKey2,
                    imagePaths: imagePaths,
                    currentIndex: currentIndex,
                    multiSelectedPaths: _multiSelectedImages,
                    onImageSelected: _onImageSelected,
                    onNextImage: () {
                      if (currentIndex < imagePaths.length - 1) {
                        setState(() {
                          _thumbCenterRequestId++;
                        });
                        _onImageSelected(currentIndex + 1);
                      }
                    },
                    onPreviousImage: () {
                      if (currentIndex > 0) {
                        setState(() {
                          _thumbCenterRequestId++;
                        });
                        _onImageSelected(currentIndex - 1);
                      }
                    },
                    onQuickNextImage: () {
                      print('DEBUG: Quick next image called');
                      if (currentIndex < imagePaths.length - 1) {
                        setState(() {
                          currentIndex = currentIndex + 1;
                        });
                        _loadMetadata();
                      }
                    },
                    onQuickPreviousImage: () {
                      if (currentIndex > 0) {
                        setState(() {
                          currentIndex = currentIndex - 1;
                        });
                        _loadMetadata();
                      }
                    },
                    onSaveIptc: _saveIptcMetadata,
                    onSaveIptcBackground: _saveIptcMetadataBackground,
                    onCopyMetadata: _onCopyMetadata,
                    onPasteMetadata: _onPasteMetadata,
                    onApplyIptcTemplate: _onApplyIptcTemplate,
                    onFtpImage: _onFtpImage,
                    onImageDeleted: _onImageDeleted,
                    onImageRenamed: _onImageRenamed,
                    uploadedImages: _uploadedImages,
                    savedImages: _savedImages,
                    queuedUploads: _queuedUploads,
                    currentlyUploading: _currentlyUploading,
                    uploadProgress: _uploadProgress,
                    xmpRatings: _xmpRatings,
                    xmpLabels: _xmpLabels,
                    xmpTagged: _xmpTagged,
                    lockedPaths: _lockedPaths,
                    onEditMetadata: _showMetadataPopup,
                    onEditInPhotoshop: _launchPhotoshop,
                  ),
                ),

                // Thumbnail grid - takes remaining space
                Expanded(
                  child: ThumbnailGridWidget(
                    key: _thumbnailGridKey,
                    imagePaths: imagePaths,
                    currentIndex: currentIndex,
                    onImageSelected: _onImageSelected,
                    uploadedImages: _uploadedImages,
                    savedImages: _savedImages,
                    queuedUploads: _queuedUploads,
                    currentlyUploading: _currentlyUploading,
                    uploadProgress: _uploadProgress,
                    xmpRatings: _xmpRatings,
                    xmpLabels: _xmpLabels,
                    xmpTagged: _xmpTagged,
                    lockedPaths: _lockedPaths,
                    centerRequestId: _thumbCenterRequestId,
                    onImageDeleted: _onImageDeleted,
                    onCopyMetadata: _onCopyMetadata,
                    onPasteMetadata: _onPasteMetadata,
                    onApplyIptcTemplate: _onApplyIptcTemplate,
                    onFtpImage: _onFtpImage,
                    onImageRenamed: _onImageRenamed,
                    onMultiSelect: _onMultiSelect,
                    onEditMetadata: _showMetadataPopup,
                    onEditInPhotoshop: _launchPhotoshop,
                    onColumnsComputed: (cols) {
                      if (_lastThumbColumns != cols) {
                        setState(() => _lastThumbColumns = cols);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // RIGHT COLUMN - Player picker, firebar, verbs
        Expanded(
          flex: 6,
          child: _buildCaptionEntryWidget(
            CaptionFieldsWidget(
              key: _captionFieldsKey2,
              metadata: currentMetadata,
              cameraService: _cameraService,
              onMetadataUpdated: (metadata) {
                setState(() {
                  currentMetadata = metadata;
                });
              },
              onVerbOverridesChanged: () => setState(() {}),
              getCurrentMetadataValues: () {
                return {};
              },
              homeTeam: selectedHomeTeam,
              awayTeam: selectedAwayTeam,
              sport: _selectedSport,
              onNextImage: () {
                if (currentIndex < imagePaths.length - 1) {
                  setState(() {
                    _thumbCenterRequestId++;
                  });
                  _onImageSelected(currentIndex + 1);
                }
              },
              onPreviousImage: () {
                if (currentIndex > 0) {
                  setState(() {
                    _thumbCenterRequestId++;
                  });
                  _onImageSelected(currentIndex - 1);
                }
              },
              onReset: _handleReset,
              personalityOverride: _personalityOverride,
              onImagesLoaded: (files) {
                print(
                    'DEBUG: onImagesLoaded called with ${files.length} files');
                setState(() {
                  imagePaths = files;
                  currentIndex = 0;
                });
              },
              onStartFolderWatcher: _startFolderWatcher,
              preloadedHomeRoster:
                  _cachedHomeRoster.isNotEmpty ? _cachedHomeRoster : null,
              preloadedAwayRoster:
                  _cachedAwayRoster.isNotEmpty ? _cachedAwayRoster : null,
              currentImagePath:
                  imagePaths.isNotEmpty ? imagePaths[currentIndex] : null,
              currentIndex: imagePaths.isNotEmpty ? currentIndex : null,
              totalImages: imagePaths.length,
              onSaveIptc: _saveIptcMetadata,
              bulkSaveCount: _bulkSaveCount,
              onImageUploaded: (imagePath) {
                if (!_currentlyUploading.contains(imagePath)) {
                  setState(() {
                    _uploadedImages.add(imagePath);
                    _uploadProgress[imagePath] = 1.0;
                  });
                }
              },
              onUploadProgress: (imagePath, progress) {
                setState(() {
                  _uploadProgress[imagePath] = progress;
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  // Players List Right Layout
  Widget _buildPlayersListRightLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // LEFT COLUMN - Player picker, firebar, verbs
        Expanded(
          flex: 6,
          child: _buildCaptionEntryWidget(
            CaptionFieldsWidget(
              key: _captionFieldsKey2,
              metadata: currentMetadata,
              cameraService: _cameraService,
              onMetadataUpdated: (metadata) {
                setState(() {
                  currentMetadata = metadata;
                });
              },
              onVerbOverridesChanged: () => setState(() {}),
              getCurrentMetadataValues: () {
                return {};
              },
              homeTeam: selectedHomeTeam,
              awayTeam: selectedAwayTeam,
              sport: _selectedSport,
              onNextImage: () {
                if (currentIndex < imagePaths.length - 1) {
                  setState(() {
                    _thumbCenterRequestId++;
                  });
                  _onImageSelected(currentIndex + 1);
                }
              },
              onPreviousImage: () {
                if (currentIndex > 0) {
                  setState(() {
                    _thumbCenterRequestId++;
                  });
                  _onImageSelected(currentIndex - 1);
                }
              },
              onReset: _handleReset,
              personalityOverride: _personalityOverride,
              onImagesLoaded: (files) {
                print(
                    'DEBUG: onImagesLoaded called with ${files.length} files');
                setState(() {
                  imagePaths = files;
                  currentIndex = 0;
                });
              },
              onStartFolderWatcher: _startFolderWatcher,
              preloadedHomeRoster:
                  _cachedHomeRoster.isNotEmpty ? _cachedHomeRoster : null,
              preloadedAwayRoster:
                  _cachedAwayRoster.isNotEmpty ? _cachedAwayRoster : null,
              currentImagePath:
                  imagePaths.isNotEmpty ? imagePaths[currentIndex] : null,
              currentIndex: imagePaths.isNotEmpty ? currentIndex : null,
              totalImages: imagePaths.length,
              onSaveIptc: _saveIptcMetadata,
              bulkSaveCount: _bulkSaveCount,
              onImageUploaded: (imagePath) {
                if (!_currentlyUploading.contains(imagePath)) {
                  setState(() {
                    _uploadedImages.add(imagePath);
                    _uploadProgress[imagePath] = 1.0;
                  });
                }
              },
              onUploadProgress: (imagePath, progress) {
                setState(() {
                  _uploadProgress[imagePath] = progress;
                });
              },
            ),
          ),
        ),

        // RIGHT COLUMN - Picture Preview and Thumbnails
        Expanded(
          flex: 4,
          child: Column(
            children: [
              // Resolution warning (if applicable)
              _buildResolutionWarning(),

              // Picture preview - 50% of screen height
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.5,
                child: PicturePreviewWidget(
                  key: _picturePreviewKey2,
                  imagePaths: imagePaths,
                  currentIndex: currentIndex,
                  multiSelectedPaths: _multiSelectedImages,
                  onImageSelected: _onImageSelected,
                  onNextImage: () {
                    if (currentIndex < imagePaths.length - 1) {
                      setState(() {
                        _thumbCenterRequestId++;
                      });
                      _onImageSelected(currentIndex + 1);
                    }
                  },
                  onPreviousImage: () {
                    if (currentIndex > 0) {
                      setState(() {
                        _thumbCenterRequestId++;
                      });
                      _onImageSelected(currentIndex - 1);
                    }
                  },
                  onQuickNextImage: () {
                    print('DEBUG: Quick next image called');
                    if (currentIndex < imagePaths.length - 1) {
                      setState(() {
                        currentIndex = currentIndex + 1;
                      });
                      _loadMetadata();
                    }
                  },
                  onQuickPreviousImage: () {
                    if (currentIndex > 0) {
                      setState(() {
                        currentIndex = currentIndex - 1;
                      });
                      _loadMetadata();
                    }
                  },
                  onSaveIptc: _saveIptcMetadata,
                  onSaveIptcBackground: _saveIptcMetadataBackground,
                  onCopyMetadata: _onCopyMetadata,
                  onPasteMetadata: _onPasteMetadata,
                  onApplyIptcTemplate: _onApplyIptcTemplate,
                  onFtpImage: _onFtpImage,
                  onImageDeleted: _onImageDeleted,
                  onImageRenamed: _onImageRenamed,
                  uploadedImages: _uploadedImages,
                    savedImages: _savedImages,
                  queuedUploads: _queuedUploads,
                  currentlyUploading: _currentlyUploading,
                  uploadProgress: _uploadProgress,
                  xmpRatings: _xmpRatings,
                  xmpLabels: _xmpLabels,
                  xmpTagged: _xmpTagged,
                  lockedPaths: _lockedPaths,
                  onEditMetadata: _showMetadataPopup,
                  onEditInPhotoshop: _launchPhotoshop,
                ),
              ),

              // Thumbnail grid - takes remaining space
              Expanded(
                child: ThumbnailGridWidget(
                  key: _thumbnailGridKey,
                  imagePaths: imagePaths,
                  currentIndex: currentIndex,
                  onImageSelected: _onImageSelected,
                  uploadedImages: _uploadedImages,
                    savedImages: _savedImages,
                  queuedUploads: _queuedUploads,
                  currentlyUploading: _currentlyUploading,
                  uploadProgress: _uploadProgress,
                  xmpRatings: _xmpRatings,
                  xmpLabels: _xmpLabels,
                  xmpTagged: _xmpTagged,
                  lockedPaths: _lockedPaths,
                  centerRequestId: _thumbCenterRequestId,
                  onImageDeleted: _onImageDeleted,
                  onCopyMetadata: _onCopyMetadata,
                  onPasteMetadata: _onPasteMetadata,
                  onApplyIptcTemplate: _onApplyIptcTemplate,
                  onFtpImage: _onFtpImage,
                  onImageRenamed: _onImageRenamed,
                  onMultiSelect: _onMultiSelect,
                  onEditMetadata: _showMetadataPopup,
                  onEditInPhotoshop: _launchPhotoshop,
                  onColumnsComputed: (cols) {
                    if (_lastThumbColumns != cols) {
                      setState(() => _lastThumbColumns = cols);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Players List Top Layout
  Widget _buildPlayersListTopLayout() {
    return Column(
      children: [
        // TOP ROW - Player picker, firebar, verbs
        Expanded(
          flex: 6,
          child: _buildCaptionEntryWidget(
            CaptionFieldsWidget(
              key: _captionFieldsKey2,
              metadata: currentMetadata,
              cameraService: _cameraService,
              onMetadataUpdated: (metadata) {
                setState(() {
                  currentMetadata = metadata;
                });
              },
              onVerbOverridesChanged: () => setState(() {}),
              getCurrentMetadataValues: () {
                return {};
              },
              homeTeam: selectedHomeTeam,
              awayTeam: selectedAwayTeam,
              sport: _selectedSport,
              onNextImage: () {
                if (currentIndex < imagePaths.length - 1) {
                  setState(() {
                    _thumbCenterRequestId++;
                  });
                  _onImageSelected(currentIndex + 1);
                }
              },
              onPreviousImage: () {
                if (currentIndex > 0) {
                  setState(() {
                    _thumbCenterRequestId++;
                  });
                  _onImageSelected(currentIndex - 1);
                }
              },
              onReset: _handleReset,
              personalityOverride: _personalityOverride,
              onImagesLoaded: (files) {
                print(
                    'DEBUG: onImagesLoaded called with ${files.length} files');
                setState(() {
                  imagePaths = files;
                  currentIndex = 0;
                });
              },
              onStartFolderWatcher: _startFolderWatcher,
              preloadedHomeRoster:
                  _cachedHomeRoster.isNotEmpty ? _cachedHomeRoster : null,
              preloadedAwayRoster:
                  _cachedAwayRoster.isNotEmpty ? _cachedAwayRoster : null,
              currentImagePath:
                  imagePaths.isNotEmpty ? imagePaths[currentIndex] : null,
              currentIndex: imagePaths.isNotEmpty ? currentIndex : null,
              totalImages: imagePaths.length,
              onSaveIptc: _saveIptcMetadata,
              bulkSaveCount: _bulkSaveCount,
              onImageUploaded: (imagePath) {
                if (!_currentlyUploading.contains(imagePath)) {
                  setState(() {
                    _uploadedImages.add(imagePath);
                    _uploadProgress.remove(imagePath);
                  });
                }
              },
              onUploadProgress: (imagePath, progress) {
                setState(() {
                  _uploadProgress[imagePath] = progress;
                });
              },
            ),
          ),
        ),

        // BOTTOM ROW - Picture Preview and Thumbnails
        Expanded(
          flex: 4,
          child: Row(
            children: [
              // Picture preview
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    // Resolution warning (if applicable)
                    _buildResolutionWarning(),
                    Expanded(
                      child: PicturePreviewWidget(
                        key: _picturePreviewKey2,
                        imagePaths: imagePaths,
                        currentIndex: currentIndex,
                        multiSelectedPaths: _multiSelectedImages,
                        onImageSelected: _onImageSelected,
                        onNextImage: () {
                          if (currentIndex < imagePaths.length - 1) {
                            setState(() {
                              _thumbCenterRequestId++;
                            });
                            _onImageSelected(currentIndex + 1);
                          }
                        },
                        onPreviousImage: () {
                          if (currentIndex > 0) {
                            setState(() {
                              _thumbCenterRequestId++;
                            });
                            _onImageSelected(currentIndex - 1);
                          }
                        },
                        onQuickNextImage: () {
                          print('DEBUG: Quick next image called');
                          if (currentIndex < imagePaths.length - 1) {
                            setState(() {
                              currentIndex = currentIndex + 1;
                            });
                            _loadMetadata();
                          }
                        },
                        onQuickPreviousImage: () {
                          if (currentIndex > 0) {
                            setState(() {
                              currentIndex = currentIndex - 1;
                            });
                            _loadMetadata();
                          }
                        },
                        onSaveIptc: _saveIptcMetadata,
                        onSaveIptcBackground: _saveIptcMetadataBackground,
                        onCopyMetadata: _onCopyMetadata,
                        onPasteMetadata: _onPasteMetadata,
                        onApplyIptcTemplate: _onApplyIptcTemplate,
                        onFtpImage: _onFtpImage,
                        onImageDeleted: _onImageDeleted,
                        onImageRenamed: _onImageRenamed,
                        uploadedImages: _uploadedImages,
                    savedImages: _savedImages,
                        queuedUploads: _queuedUploads,
                        currentlyUploading: _currentlyUploading,
                        uploadProgress: _uploadProgress,
                        xmpRatings: _xmpRatings,
                        xmpLabels: _xmpLabels,
                        xmpTagged: _xmpTagged,
                        lockedPaths: _lockedPaths,
                        onEditMetadata: _showMetadataPopup,
                        onEditInPhotoshop: _launchPhotoshop,
                      ),
                    ),
                  ],
                ),
              ),

              // Divider line
              Container(
                width: 1,
                color: Colors.grey.shade300,
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),

              // Thumbnail grid
              Expanded(
                flex: 1,
                child: ThumbnailGridWidget(
                  key: _thumbnailGridKey,
                  imagePaths: imagePaths,
                  currentIndex: currentIndex,
                  onImageSelected: _onImageSelected,
                  uploadedImages: _uploadedImages,
                    savedImages: _savedImages,
                  queuedUploads: _queuedUploads,
                  currentlyUploading: _currentlyUploading,
                  uploadProgress: _uploadProgress,
                  xmpRatings: _xmpRatings,
                  xmpLabels: _xmpLabels,
                  xmpTagged: _xmpTagged,
                  lockedPaths: _lockedPaths,
                  centerRequestId: _thumbCenterRequestId,
                  onImageDeleted: _onImageDeleted,
                  onCopyMetadata: _onCopyMetadata,
                  onPasteMetadata: _onPasteMetadata,
                  onApplyIptcTemplate: _onApplyIptcTemplate,
                  onFtpImage: _onFtpImage,
                  onImageRenamed: _onImageRenamed,
                  onMultiSelect: _onMultiSelect,
                  onEditMetadata: _showMetadataPopup,
                  onEditInPhotoshop: _launchPhotoshop,
                  onColumnsComputed: (cols) {
                    if (_lastThumbColumns != cols) {
                      setState(() => _lastThumbColumns = cols);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Players List Bottom Layout
  Widget _buildPlayersListBottomLayout() {
    return Column(
      children: [
        // TOP ROW - Picture Preview and Thumbnails
        Expanded(
          flex: 4,
          child: Row(
            children: [
              // Picture preview
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    // Resolution warning (if applicable)
                    _buildResolutionWarning(),
                    Expanded(
                      child: PicturePreviewWidget(
                        key: _picturePreviewKey2,
                        imagePaths: imagePaths,
                        currentIndex: currentIndex,
                        multiSelectedPaths: _multiSelectedImages,
                        onImageSelected: _onImageSelected,
                        onNextImage: () {
                          if (currentIndex < imagePaths.length - 1) {
                            setState(() {
                              _thumbCenterRequestId++;
                            });
                            _onImageSelected(currentIndex + 1);
                          }
                        },
                        onPreviousImage: () {
                          if (currentIndex > 0) {
                            setState(() {
                              _thumbCenterRequestId++;
                            });
                            _onImageSelected(currentIndex - 1);
                          }
                        },
                        onQuickNextImage: () {
                          print('DEBUG: Quick next image called');
                          if (currentIndex < imagePaths.length - 1) {
                            setState(() {
                              currentIndex = currentIndex + 1;
                            });
                            _loadMetadata();
                          }
                        },
                        onQuickPreviousImage: () {
                          if (currentIndex > 0) {
                            setState(() {
                              currentIndex = currentIndex - 1;
                            });
                            _loadMetadata();
                          }
                        },
                        onSaveIptc: _saveIptcMetadata,
                        onSaveIptcBackground: _saveIptcMetadataBackground,
                        onCopyMetadata: _onCopyMetadata,
                        onPasteMetadata: _onPasteMetadata,
                        onApplyIptcTemplate: _onApplyIptcTemplate,
                        onFtpImage: _onFtpImage,
                        onImageDeleted: _onImageDeleted,
                        onImageRenamed: _onImageRenamed,
                        uploadedImages: _uploadedImages,
                    savedImages: _savedImages,
                        queuedUploads: _queuedUploads,
                        currentlyUploading: _currentlyUploading,
                        uploadProgress: _uploadProgress,
                        xmpRatings: _xmpRatings,
                        xmpLabels: _xmpLabels,
                        xmpTagged: _xmpTagged,
                        lockedPaths: _lockedPaths,
                        onEditMetadata: _showMetadataPopup,
                        onEditInPhotoshop: _launchPhotoshop,
                      ),
                    ),
                  ],
                ),
              ),

              // Divider line
              Container(
                width: 1,
                color: Colors.grey.shade300,
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),

              // Thumbnail grid
              Expanded(
                flex: 1,
                child: ThumbnailGridWidget(
                  key: _thumbnailGridKey,
                  imagePaths: imagePaths,
                  currentIndex: currentIndex,
                  onImageSelected: _onImageSelected,
                  uploadedImages: _uploadedImages,
                    savedImages: _savedImages,
                  queuedUploads: _queuedUploads,
                  currentlyUploading: _currentlyUploading,
                  uploadProgress: _uploadProgress,
                  xmpRatings: _xmpRatings,
                  xmpLabels: _xmpLabels,
                  xmpTagged: _xmpTagged,
                  lockedPaths: _lockedPaths,
                  centerRequestId: _thumbCenterRequestId,
                  onImageDeleted: _onImageDeleted,
                  onCopyMetadata: _onCopyMetadata,
                  onPasteMetadata: _onPasteMetadata,
                  onApplyIptcTemplate: _onApplyIptcTemplate,
                  onFtpImage: _onFtpImage,
                  onImageRenamed: _onImageRenamed,
                  onMultiSelect: _onMultiSelect,
                  onEditMetadata: _showMetadataPopup,
                  onEditInPhotoshop: _launchPhotoshop,
                  onColumnsComputed: (cols) {
                    if (_lastThumbColumns != cols) {
                      setState(() => _lastThumbColumns = cols);
                    }
                  },
                ),
              ),
            ],
          ),
        ),

        // BOTTOM ROW - Player picker, firebar, verbs
        Expanded(
          flex: 6,
          child: _buildCaptionEntryWidget(
            CaptionFieldsWidget(
              key: _captionFieldsKey2,
              metadata: currentMetadata,
              cameraService: _cameraService,
              onMetadataUpdated: (metadata) {
                setState(() {
                  currentMetadata = metadata;
                });
              },
              onVerbOverridesChanged: () => setState(() {}),
              getCurrentMetadataValues: () {
                return {};
              },
              homeTeam: selectedHomeTeam,
              awayTeam: selectedAwayTeam,
              sport: _selectedSport,
              onNextImage: () {
                if (currentIndex < imagePaths.length - 1) {
                  setState(() {
                    _thumbCenterRequestId++;
                  });
                  _onImageSelected(currentIndex + 1);
                }
              },
              onPreviousImage: () {
                if (currentIndex > 0) {
                  setState(() {
                    _thumbCenterRequestId++;
                  });
                  _onImageSelected(currentIndex - 1);
                }
              },
              onReset: _handleReset,
              personalityOverride: _personalityOverride,
              onImagesLoaded: (files) {
                print(
                    'DEBUG: onImagesLoaded called with ${files.length} files');
                setState(() {
                  imagePaths = files;
                  currentIndex = 0;
                });
              },
              onStartFolderWatcher: _startFolderWatcher,
              preloadedHomeRoster:
                  _cachedHomeRoster.isNotEmpty ? _cachedHomeRoster : null,
              preloadedAwayRoster:
                  _cachedAwayRoster.isNotEmpty ? _cachedAwayRoster : null,
              currentImagePath:
                  imagePaths.isNotEmpty ? imagePaths[currentIndex] : null,
              currentIndex: imagePaths.isNotEmpty ? currentIndex : null,
              totalImages: imagePaths.length,
              onSaveIptc: _saveIptcMetadata,
              bulkSaveCount: _bulkSaveCount,
              onImageUploaded: (imagePath) {
                if (!_currentlyUploading.contains(imagePath)) {
                  setState(() {
                    _uploadedImages.add(imagePath);
                    _uploadProgress.remove(imagePath);
                  });
                }
              },
              onUploadProgress: (imagePath, progress) {
                setState(() {
                  _uploadProgress[imagePath] = progress;
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  // Compact Players Above Layout
  Widget _buildCompactPlayersAboveLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LEFT COLUMN - Picture Preview and Thumbnails
        Expanded(
          flex: 4,
          child: Column(
            children: [
              // Resolution warning (if applicable)
              _buildResolutionWarning(),

              // Picture preview - 50% of screen height
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.5,
                child: PicturePreviewWidget(
                  key: _picturePreviewKey2,
                  imagePaths: imagePaths,
                  currentIndex: currentIndex,
                  multiSelectedPaths: _multiSelectedImages,
                  onImageSelected: _onImageSelected,
                  onNextImage: () {
                    if (currentIndex < imagePaths.length - 1) {
                      setState(() {
                        _thumbCenterRequestId++;
                      });
                      _onImageSelected(currentIndex + 1);
                    }
                  },
                  onPreviousImage: () {
                    if (currentIndex > 0) {
                      setState(() {
                        _thumbCenterRequestId++;
                      });
                      _onImageSelected(currentIndex - 1);
                    }
                  },
                  onQuickNextImage: () {
                    print('DEBUG: Quick next image called');
                    if (currentIndex < imagePaths.length - 1) {
                      setState(() {
                        currentIndex = currentIndex + 1;
                      });
                      _loadMetadata();
                    }
                  },
                  onQuickPreviousImage: () {
                    if (currentIndex > 0) {
                      setState(() {
                        currentIndex = currentIndex - 1;
                      });
                      _loadMetadata();
                    }
                  },
                  onSaveIptc: _saveIptcMetadata,
                  onSaveIptcBackground: _saveIptcMetadataBackground,
                  onCopyMetadata: _onCopyMetadata,
                  onPasteMetadata: _onPasteMetadata,
                  onApplyIptcTemplate: _onApplyIptcTemplate,
                  onFtpImage: _onFtpImage,
                  onImageDeleted: _onImageDeleted,
                  onImageRenamed: _onImageRenamed,
                  uploadedImages: _uploadedImages,
                    savedImages: _savedImages,
                  queuedUploads: _queuedUploads,
                  currentlyUploading: _currentlyUploading,
                  uploadProgress: _uploadProgress,
                  xmpRatings: _xmpRatings,
                  xmpLabels: _xmpLabels,
                  xmpTagged: _xmpTagged,
                  lockedPaths: _lockedPaths,
                  onEditMetadata: _showMetadataPopup,
                  onEditInPhotoshop: _launchPhotoshop,
                ),
              ),

              // Thumbnail grid - takes remaining space
              Expanded(
                child: ThumbnailGridWidget(
                  key: _thumbnailGridKey,
                  imagePaths: imagePaths,
                  currentIndex: currentIndex,
                  onImageSelected: _onImageSelected,
                  uploadedImages: _uploadedImages,
                    savedImages: _savedImages,
                  queuedUploads: _queuedUploads,
                  currentlyUploading: _currentlyUploading,
                  uploadProgress: _uploadProgress,
                  xmpRatings: _xmpRatings,
                  xmpLabels: _xmpLabels,
                  xmpTagged: _xmpTagged,
                  lockedPaths: _lockedPaths,
                  centerRequestId: _thumbCenterRequestId,
                  onImageDeleted: _onImageDeleted,
                  onCopyMetadata: _onCopyMetadata,
                  onPasteMetadata: _onPasteMetadata,
                  onApplyIptcTemplate: _onApplyIptcTemplate,
                  onFtpImage: _onFtpImage,
                  onImageRenamed: _onImageRenamed,
                  onMultiSelect: _onMultiSelect,
                  onEditMetadata: _showMetadataPopup,
                  onEditInPhotoshop: _launchPhotoshop,
                  onColumnsComputed: (cols) {
                    if (_lastThumbColumns != cols) {
                      setState(() => _lastThumbColumns = cols);
                    }
                  },
                ),
              ),
            ],
          ),
        ),

        // RIGHT COLUMN - Compact Player Picker Above Verb Picker
        Expanded(
          flex: 6,
          child: Column(
            children: [
              // Compact Player Picker (spans full width)
              _buildCompactPlayerPicker(),

              // Divider line
              Container(
                height: 1,
                color: Colors.grey.shade300,
                margin: const EdgeInsets.symmetric(vertical: 8),
              ),

              // Verb Picker (takes remaining space)
              Expanded(
                child: _buildCaptionEntryWidget(
                  CaptionFieldsWidget(
                    key: _captionFieldsKey2,
                    metadata: currentMetadata,
                    cameraService: _cameraService,
                    onMetadataUpdated: (metadata) {
                      setState(() {
                        currentMetadata = metadata;
                      });
                    },
                    onVerbOverridesChanged: () => setState(() {}),
                    getCurrentMetadataValues: () {
                      return {};
                    },
                    homeTeam: selectedHomeTeam,
                    awayTeam: selectedAwayTeam,
                    sport: _selectedSport,
                    onNextImage: () {
                      if (currentIndex < imagePaths.length - 1) {
                        setState(() {
                          _thumbCenterRequestId++;
                        });
                        _onImageSelected(currentIndex + 1);
                      }
                    },
                    onPreviousImage: () {
                      if (currentIndex > 0) {
                        setState(() {
                          _thumbCenterRequestId++;
                        });
                        _onImageSelected(currentIndex - 1);
                      }
                    },
                    onReset: _handleReset,
                    personalityOverride: _personalityOverride,
                    onImagesLoaded: (files) {
                      print(
                          'DEBUG: onImagesLoaded called with ${files.length} files');
                      setState(() {
                        imagePaths = files;
                        currentIndex = 0;
                      });
                    },
                    onStartFolderWatcher: _startFolderWatcher,
                    preloadedHomeRoster:
                        _cachedHomeRoster.isNotEmpty ? _cachedHomeRoster : null,
                    preloadedAwayRoster:
                        _cachedAwayRoster.isNotEmpty ? _cachedAwayRoster : null,
                    currentImagePath:
                        imagePaths.isNotEmpty ? imagePaths[currentIndex] : null,
                    currentIndex: imagePaths.isNotEmpty ? currentIndex : null,
                    totalImages: imagePaths.length,
                    onSaveIptc: _saveIptcMetadata,
                    bulkSaveCount: _bulkSaveCount,
                    onImageUploaded: (imagePath) {
                      if (!_currentlyUploading.contains(imagePath)) {
                        setState(() {
                          _uploadedImages.add(imagePath);
                          _uploadProgress.remove(imagePath);
                        });
                      }
                    },
                    onUploadProgress: (imagePath, progress) {
                      setState(() {
                        _uploadProgress[imagePath] = progress;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Matrix Board Layout - Fast caption building with matrix grid
  Widget _buildMatrixBoardLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LEFT COLUMN - Matrix Caption Board
        Expanded(
          flex: 7,
          child: Container(
            padding: const EdgeInsets.all(16),
            child: MatrixCaptionBoard(
              homeTeamName: selectedHomeTeam,
              awayTeamName: selectedAwayTeam,
              homeTeamAbbr: _getTeamAbbreviation(selectedHomeTeam),
              awayTeamAbbr: _getTeamAbbreviation(selectedAwayTeam),
              homeRoster: _cachedHomeRoster,
              awayRoster: _cachedAwayRoster,
              venue: currentMetadata?['Headline']?.toString(),
              gameDate: _getPhotoDate(),
              period: _selectedSport?.toLowerCase() == 'baseball'
                  ? 'the first inning'
                  : (_selectedSport?.toLowerCase() == 'soccer'
                      ? 'the first half'
                      : 'the first period'),
              metadata: currentMetadata,
              onCaptionGenerated: (caption) {
                // Update caption in metadata
                setState(() {
                  if (currentMetadata != null) {
                    currentMetadata!['Caption-Abstract'] = caption;
                  }
                });
              },
            ),
          ),
        ),

        // RIGHT COLUMN - Picture Preview and Thumbnails
        Expanded(
          flex: 3,
          child: Column(
            children: [
              // Resolution warning (if applicable)
              _buildResolutionWarning(),

              // Picture preview
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.5,
                child: PicturePreviewWidget(
                  key: _picturePreviewKey2,
                  imagePaths: imagePaths,
                  currentIndex: currentIndex,
                  multiSelectedPaths: _multiSelectedImages,
                  onImageSelected: _onImageSelected,
                  onNextImage: () {
                    if (currentIndex < imagePaths.length - 1) {
                      setState(() {
                        _thumbCenterRequestId++;
                      });
                      _onImageSelected(currentIndex + 1);
                    }
                  },
                  onPreviousImage: () {
                    if (currentIndex > 0) {
                      setState(() {
                        _thumbCenterRequestId++;
                      });
                      _onImageSelected(currentIndex - 1);
                    }
                  },
                  onQuickNextImage: () {
                    if (currentIndex < imagePaths.length - 1) {
                      setState(() {
                        currentIndex = currentIndex + 1;
                      });
                      _loadMetadata();
                    }
                  },
                  onQuickPreviousImage: () {
                    if (currentIndex > 0) {
                      setState(() {
                        currentIndex = currentIndex - 1;
                      });
                      _loadMetadata();
                    }
                  },
                  onSaveIptc: _saveIptcMetadata,
                  onSaveIptcBackground: _saveIptcMetadataBackground,
                  onCopyMetadata: _onCopyMetadata,
                  onPasteMetadata: _onPasteMetadata,
                  onApplyIptcTemplate: _onApplyIptcTemplate,
                  onFtpImage: _onFtpImage,
                  onImageDeleted: _onImageDeleted,
                  onImageRenamed: _onImageRenamed,
                  uploadedImages: _uploadedImages,
                    savedImages: _savedImages,
                  queuedUploads: _queuedUploads,
                  currentlyUploading: _currentlyUploading,
                  uploadProgress: _uploadProgress,
                  xmpRatings: _xmpRatings,
                  xmpLabels: _xmpLabels,
                  xmpTagged: _xmpTagged,
                  lockedPaths: _lockedPaths,
                  onEditMetadata: _showMetadataPopup,
                  onEditInPhotoshop: _launchPhotoshop,
                ),
              ),

              // Divider line
              Container(
                height: 1,
                color: Colors.grey.shade300,
                margin: const EdgeInsets.symmetric(vertical: 12),
              ),

              // Thumbnail grid
              Expanded(
                child: ThumbnailGridWidget(
                  key: _thumbnailGridKey,
                  imagePaths: imagePaths,
                  currentIndex: currentIndex,
                  onImageSelected: _onImageSelected,
                  uploadedImages: _uploadedImages,
                    savedImages: _savedImages,
                  queuedUploads: _queuedUploads,
                  currentlyUploading: _currentlyUploading,
                  uploadProgress: _uploadProgress,
                  xmpRatings: _xmpRatings,
                  xmpLabels: _xmpLabels,
                  xmpTagged: _xmpTagged,
                  lockedPaths: _lockedPaths,
                  centerRequestId: _thumbCenterRequestId,
                  onImageDeleted: _onImageDeleted,
                  onCopyMetadata: _onCopyMetadata,
                  onPasteMetadata: _onPasteMetadata,
                  onApplyIptcTemplate: _onApplyIptcTemplate,
                  onFtpImage: _onFtpImage,
                  onImageRenamed: _onImageRenamed,
                  onMultiSelect: _onMultiSelect,
                  onEditMetadata: _showMetadataPopup,
                  onEditInPhotoshop: _launchPhotoshop,
                  onColumnsComputed: (cols) {
                    if (_lastThumbColumns != cols) {
                      setState(() => _lastThumbColumns = cols);
                    }
                  },
                  exifTimes: _exifTimes,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Helper method to get team abbreviation
  String? _getTeamAbbreviation(String? teamName) {
    if (teamName == null) return null;

    final abbreviations = {
      'Edmonton Oilers': 'EDM',
      'Toronto Maple Leafs': 'TOR',
      'Calgary Flames': 'CGY',
      'Vancouver Canucks': 'VAN',
      'Montreal Canadiens': 'MTL',
      'Ottawa Senators': 'OTT',
      'Winnipeg Jets': 'WPG',
      'Boston Bruins': 'BOS',
      'Buffalo Sabres': 'BUF',
      'Detroit Red Wings': 'DET',
      'Florida Panthers': 'FLA',
      'Tampa Bay Lightning': 'TBL',
      'Carolina Hurricanes': 'CAR',
      'Columbus Blue Jackets': 'CBJ',
      'New Jersey Devils': 'NJD',
      'New York Islanders': 'NYI',
      'New York Rangers': 'NYR',
      'Philadelphia Flyers': 'PHI',
      'Pittsburgh Penguins': 'PIT',
      'Washington Capitals': 'WSH',
      'Chicago Blackhawks': 'CHI',
      'Colorado Avalanche': 'COL',
      'Dallas Stars': 'DAL',
      'Minnesota Wild': 'MIN',
      'Nashville Predators': 'NSH',
      'St. Louis Blues': 'STL',
      'Anaheim Ducks': 'ANA',
      'Arizona Coyotes': 'ARI',
      'Las Vegas Golden Knights': 'VGK',
      'Los Angeles Kings': 'LAK',
      'San Jose Sharks': 'SJS',
      'Seattle Kraken': 'SEA',
      // MLB teams
      'Arizona Diamondbacks': 'ARI',
      'Atlanta Braves': 'ATL',
      'Baltimore Orioles': 'BAL',
      'Boston Red Sox': 'BOS',
      'Chicago Cubs': 'CHC',
      'Chicago White Sox': 'CHW',
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

    return abbreviations[teamName];
  }

  // Helper method to get photo date from metadata
  DateTime? _getPhotoDate() {
    if (currentMetadata == null) return DateTime.now();

    final dateTimeOriginal = currentMetadata!['DateTimeOriginal']?.toString();
    final createDate = currentMetadata!['CreateDate']?.toString();
    final modifyDate = currentMetadata!['ModifyDate']?.toString();

    final dateString = dateTimeOriginal ?? createDate ?? modifyDate;
    if (dateString != null && dateString.isNotEmpty) {
      try {
        final parts = dateString.split(' ');
        if (parts.isNotEmpty) {
          final datePart = parts[0];
          final dateComponents = datePart.split(':');
          if (dateComponents.length >= 3) {
            final year = int.parse(dateComponents[0]);
            final month = int.parse(dateComponents[1]);
            final day = int.parse(dateComponents[2]);
            return DateTime(year, month, day);
          }
        }
      } catch (e) {
        print('Error parsing photo date: $e');
      }
    }

    return DateTime.now();
  }

  // Player Popup Layout - Content at top, full player picker at bottom
  Widget _buildPlayerPopupLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LEFT COLUMN - Picture Preview and Thumbnails
        Expanded(
          flex: 4,
          child: Column(
            children: [
              // Resolution warning (if applicable)
              _buildResolutionWarning(),

              // Picture preview - 50% of screen height
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.5,
                child: PicturePreviewWidget(
                  key: _picturePreviewKey2,
                  imagePaths: imagePaths,
                  currentIndex: currentIndex,
                  multiSelectedPaths: _multiSelectedImages,
                  onImageSelected: _onImageSelected,
                  onNextImage: () {
                    if (currentIndex < imagePaths.length - 1) {
                      setState(() {
                        _thumbCenterRequestId++;
                      });
                      _onImageSelected(currentIndex + 1);
                    }
                  },
                  onPreviousImage: () {
                    if (currentIndex > 0) {
                      setState(() {
                        _thumbCenterRequestId++;
                      });
                      _onImageSelected(currentIndex - 1);
                    }
                  },
                  onQuickNextImage: () {
                    if (currentIndex < imagePaths.length - 1) {
                      setState(() {
                        currentIndex = currentIndex + 1;
                      });
                      _loadMetadata();
                    }
                  },
                  onQuickPreviousImage: () {
                    if (currentIndex > 0) {
                      setState(() {
                        currentIndex = currentIndex - 1;
                      });
                      _loadMetadata();
                    }
                  },
                  onSaveIptc: _saveIptcMetadata,
                  onSaveIptcBackground: _saveIptcMetadataBackground,
                  onCopyMetadata: _onCopyMetadata,
                  onPasteMetadata: _onPasteMetadata,
                  onApplyIptcTemplate: _onApplyIptcTemplate,
                  onFtpImage: _onFtpImage,
                  onImageDeleted: _onImageDeleted,
                  onImageRenamed: _onImageRenamed,
                  uploadedImages: _uploadedImages,
                    savedImages: _savedImages,
                  queuedUploads: _queuedUploads,
                  currentlyUploading: _currentlyUploading,
                  uploadProgress: _uploadProgress,
                  xmpRatings: _xmpRatings,
                  xmpLabels: _xmpLabels,
                  xmpTagged: _xmpTagged,
                  lockedPaths: _lockedPaths,
                  onEditMetadata: _showMetadataPopup,
                  onEditInPhotoshop: _launchPhotoshop,
                ),
              ),

              // Thumbnail grid - remaining space
              Expanded(
                child: ThumbnailGridWidget(
                  key: _thumbnailGridKey,
                  imagePaths: imagePaths,
                  currentIndex: currentIndex,
                  onImageSelected: _onImageSelected,
                  uploadedImages: _uploadedImages,
                    savedImages: _savedImages,
                  queuedUploads: _queuedUploads,
                  currentlyUploading: _currentlyUploading,
                  uploadProgress: _uploadProgress,
                  xmpRatings: _xmpRatings,
                  xmpLabels: _xmpLabels,
                  xmpTagged: _xmpTagged,
                  lockedPaths: _lockedPaths,
                  centerRequestId: _thumbCenterRequestId,
                  onImageDeleted: _onImageDeleted,
                  onCopyMetadata: _onCopyMetadata,
                  onPasteMetadata: _onPasteMetadata,
                  onApplyIptcTemplate: _onApplyIptcTemplate,
                  onFtpImage: _onFtpImage,
                  onImageRenamed: _onImageRenamed,
                  onMultiSelect: _onMultiSelect,
                  onEditMetadata: _showMetadataPopup,
                  onEditInPhotoshop: _launchPhotoshop,
                  onColumnsComputed: (cols) {
                    if (_lastThumbColumns != cols) {
                      setState(() => _lastThumbColumns = cols);
                    }
                  },
                  exifTimes: _exifTimes,
                ),
              ),
            ],
          ),
        ),

        // RIGHT COLUMN - Caption Fields and Player Picker
        Expanded(
          flex: 6,
          child: ColoredBox(
            color: Colors.grey.shade50,
            child: _useKeyboardFireAsDefault
                ? Stack(
                  fit: StackFit.expand,
                  children: [
                    // Keep CaptionFieldsWidget alive offstage so its state is preserved
                    Offstage(
                      offstage: true,
                      child: SizedBox(
                        height: 1,
                        child: CaptionFieldsWidget(
                          key: _captionFieldsKey2,
                          metadata: currentMetadata,
                          cameraService: _cameraService,
                          onMetadataUpdated: (_) {},
                          getCurrentMetadataValues: () => {},
                          homeTeam: selectedHomeTeam,
                          awayTeam: selectedAwayTeam,
                          sport: _selectedSport,
                          onNextImage: () {},
                          onPreviousImage: () {},
                          onReset: _handleReset,
                          preloadedHomeRoster: _cachedHomeRoster.isNotEmpty
                              ? _cachedHomeRoster
                              : null,
                          preloadedAwayRoster: _cachedAwayRoster.isNotEmpty
                              ? _cachedAwayRoster
                              : null,
                          hidePlayerPicker: true,
                          onSaveIptc: _saveIptcMetadata,
                          bulkSaveCount: _bulkSaveCount,
                          onSaveIptcBackground: _saveIptcMetadataBackground,
                        ),
                      ),
                    ),
                    Builder(builder: (context) {
                      final cs = _captionFieldsKey2.currentState;
                      final dynamic state = cs;
                      return KeyboardFirePanel(
                        homeRoster: _cachedHomeRoster,
                        awayRoster: _cachedAwayRoster,
                        homeTeamName: selectedHomeTeam,
                        awayTeamName: selectedAwayTeam,
                        captionState: cs,
                        showDialogActions: false,
                        currentIndex:
                            imagePaths.isNotEmpty ? currentIndex : null,
                        totalImages: imagePaths.length,
                        onPreviousImage: () {
                          if (currentIndex > 0) {
                            setState(() => _thumbCenterRequestId++);
                            _onImageSelected(currentIndex - 1);
                          }
                        },
                        onNextImage: () {
                          if (currentIndex < imagePaths.length - 1) {
                            setState(() => _thumbCenterRequestId++);
                            _onImageSelected(currentIndex + 1);
                          }
                        },
                        onSaveIptc: _saveIptcMetadata,
                        bulkSaveCount: _bulkSaveCount,
                        onFtp: cs != null
                            ? () {
                                try {
                                  state.triggerFtp();
                                } catch (_) {}
                              }
                            : null,
                        onFtpSettings: cs != null
                            ? () {
                                try {
                                  state.showFtpSettings();
                                } catch (_) {}
                              }
                            : null,
                        onReset: _handleReset,
                        onCopy: _onKeyboardFireCopy,
                        onPaste: _onKeyboardFirePaste,
                        onPastePrevious: cs != null
                            ? () {
                                try {
                                  state.pastePreviousCaption();
                                } catch (_) {}
                              }
                            : null,
                        ftpDisabled: cs != null
                            ? (() {
                                try {
                                  return state.isFtpDisabled as bool;
                                } catch (_) {
                                  return false;
                                }
                              })()
                            : false,
                        currentFtpProfile: cs != null
                            ? (() {
                                try {
                                  return state.currentFtpProfile as String?;
                                } catch (_) {
                                  return null;
                                }
                              })()
                            : null,
                      );
                    }),
                  ],
                )
                : Column(
                  children: [
                    // Caption area: tall enough for caption + optional Headline/Keywords/Personality row
                    SizedBox(
                      height: (MediaQuery.sizeOf(context).height * 0.36)
                          .clamp(260.0, 540.0)
                          .toDouble(),
                      child: CaptionFieldsWidget(
                        key: _captionFieldsKey2,
                        metadata: currentMetadata,
                        cameraService: _cameraService,
                        onMetadataUpdated: (metadata) {
                          setState(() {
                            currentMetadata = metadata;
                          });
                        },
                        getCurrentMetadataValues: () {
                          return {};
                        },
                        homeTeam: selectedHomeTeam,
                        awayTeam: selectedAwayTeam,
                        sport: _selectedSport,
                        currentImagePath: imagePaths.isNotEmpty &&
                                currentIndex >= 0 &&
                                currentIndex < imagePaths.length
                            ? imagePaths[currentIndex]
                            : null,
                        currentIndex: currentIndex,
                        totalImages: imagePaths.length,
                        onNextImage: () {
                          if (currentIndex < imagePaths.length - 1) {
                            setState(() {
                              _thumbCenterRequestId++;
                            });
                            _onImageSelected(currentIndex + 1);
                          }
                        },
                        onPreviousImage: () {
                          if (currentIndex > 0) {
                            setState(() {
                              _thumbCenterRequestId++;
                            });
                            _onImageSelected(currentIndex - 1);
                          }
                        },
                        onReset: _handleReset,
                        personalityOverride: _personalityOverride,
                        onImagesLoaded: (files) {
                          setState(() {
                            imagePaths = files;
                            currentIndex = 0;
                          });
                        },
                        preloadedHomeRoster: _cachedHomeRoster.isNotEmpty
                            ? _cachedHomeRoster
                            : null,
                        preloadedAwayRoster: _cachedAwayRoster.isNotEmpty
                            ? _cachedAwayRoster
                            : null,
                        hidePlayerPicker:
                            true, // Hide old player picker for this layout
                        onSaveIptc: _saveIptcMetadata,
                        bulkSaveCount: _bulkSaveCount,
                        onSaveIptcBackground: _saveIptcMetadataBackground,
                        onCopyMetadata: () =>
                            _onCopyMetadata(imagePaths[currentIndex]),
                        onImageUploaded: (imagePath) {
                          if (!_currentlyUploading.contains(imagePath)) {
                            setState(() {
                              _uploadedImages.add(imagePath);
                              _uploadProgress[imagePath] =
                                  1.0; // Set to 1.0 to show "Upload complete"
                            });
                          }
                        },
                        onUploadProgress: (imagePath, progress) {
                          setState(() {
                            _uploadProgress[imagePath] = progress;
                          });
                        },
                        isImageUploaded: (imagePath) {
                          return _uploadedImages.contains(imagePath);
                        },
                        onClearUploadStatus: (imagePath) {
                          setState(() {
                            _uploadedImages.remove(imagePath);
                            _uploadProgress.remove(imagePath);
                          });
                        },
                      ), // end CaptionFieldsWidget
                    ), // end SizedBox(height:175)
                    // Player picker with popup verbs (remaining space)
                    Expanded(
                      child: PlayerPopupCaptionBoard(
                        key: _playerPopupKey,
                        sport: _selectedSport,
                        homeTeamName: selectedHomeTeam,
                        awayTeamName: selectedAwayTeam,
                        homeRoster: _cachedHomeRoster,
                        awayRoster: _cachedAwayRoster,
                        homeOnLeft: () {
                          final captionState = _captionFieldsKey2.currentState;
                          if (captionState != null) {
                            try {
                              final dynamic state = captionState;
                              return state.homeOnLeft ?? true;
                            } catch (e) {
                              return true;
                            }
                          }
                          return true;
                        }(),
                        venue: currentMetadata?['Headline']?.toString(),
                        gameDate: _getPhotoDate(),
                        period: _selectedSport?.toLowerCase() == 'baseball'
                            ? 'the first inning'
                            : (_selectedSport?.toLowerCase() == 'soccer'
                                ? 'the first half'
                                : 'the first period'),
                        metadata: currentMetadata,
                        onCaptionGenerated:
                            (Player player, String verb, bool isHome) {
                          // Use the existing Getty caption generation system
                          final captionState = _captionFieldsKey2.currentState;
                          if (captionState != null) {
                            try {
                              final dynamic state = captionState;
                              if (state.mounted) {
                                // Call the public method to select player and verb
                                state.selectPlayerAndVerb(player, verb, isHome);
                              }
                            } catch (e) {
                              print('Error triggering caption generation: $e');
                            }
                          }
                        },
                        onSelectionChanged: (
                          Set<Player> homePlayers,
                          Set<Player> awayPlayers,
                          Player? firstPlayer,
                          bool? firstIsHome,
                        ) {
                          final captionState = _captionFieldsKey2.currentState;
                          if (captionState != null) {
                            try {
                              final dynamic state = captionState;
                              if (state.mounted) {
                                state.updatePlayersFromPopup(
                                  homePlayers,
                                  awayPlayers,
                                  firstPlayer,
                                  firstIsHome,
                                );
                              }
                            } catch (e) {
                              print('Error updating players from popup: $e');
                            }
                          }
                        },
                        onCustomVerbChanged: (String verb) {
                          final captionState = _captionFieldsKey2.currentState;
                          if (captionState != null) {
                            try {
                              final dynamic state = captionState;
                              if (state.mounted) {
                                state.updateCustomVerbFromPopup(verb);
                              }
                            } catch (e) {
                              print('Error updating custom verb: $e');
                            }
                          }
                        },
                        onPeriodChanged: (String? period) {
                          final captionState = _captionFieldsKey2.currentState;
                          if (captionState != null) {
                            try {
                              final dynamic state = captionState;
                              if (state.mounted) {
                                state.updatePeriodFromPopup(period);
                              }
                            } catch (e) {
                              print('Error updating period from popup: $e');
                            }
                          }
                        },
                        onInningChanged: (int? inning) {
                          final captionState = _captionFieldsKey2.currentState;
                          if (captionState != null) {
                            try {
                              final dynamic state = captionState;
                              if (state.mounted) {
                                state.updateInningFromPopup(inning);
                              }
                            } catch (e) {
                              print('Error updating inning from popup: $e');
                            }
                          }
                        },
                        onSwitchTeams: () {
                          print('DEBUG: onSwitchTeams callback triggered');
                          final captionState = _captionFieldsKey2.currentState;
                          print(
                              'DEBUG: captionState is null: ${captionState == null}');
                          if (captionState != null) {
                            try {
                              final dynamic state = captionState;
                              print('DEBUG: state.mounted: ${state.mounted}');
                              if (state.mounted) {
                                state.switchTeams();
                                // Force rebuild of this widget to update PlayerPopupCaptionBoard with new homeOnLeft
                                setState(() {});
                              } else {
                                print(
                                    'DEBUG: State not mounted, cannot switch teams');
                              }
                            } catch (e) {
                              print('Error switching teams: $e');
                            }
                          } else {
                            print(
                                'DEBUG: captionState is null, cannot switch teams');
                          }
                        },
                        onSaveIptc: _saveIptcMetadata,
                        onNextImage: () {
                          if (currentIndex < imagePaths.length - 1) {
                            setState(() {
                              _thumbCenterRequestId++;
                            });
                            _onImageSelected(currentIndex + 1);
                          }
                        },
                        onCopyMetadata: () =>
                            _onCopyMetadata(imagePaths[currentIndex]),
                        onFtp: () => _onFtpImage(imagePaths[currentIndex]),
                        isFtpDisabled: false,
                        uploadProgress: _uploadProgress,
                        currentImagePath: imagePaths.isNotEmpty &&
                                currentIndex < imagePaths.length
                            ? imagePaths[currentIndex]
                            : null,
                        queuedUploads: _queuedUploads,
                        currentlyUploading: _currentlyUploading,
                      ),
                    ),
                  ], // end classic Column children
                ), // end classic Column
            ), // end ColoredBox
        ), // end Expanded(flex:6)
      ],
    );
  }

  // Build compact player picker with numbers only
  Widget _buildCompactPlayerPicker() {
    return Container(
      height: 120, // Fixed height for compact picker
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          // Team headers
          Row(
            children: [
              Expanded(
                child: Text(
                  selectedHomeTeam ?? 'Home Team',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Container(
                width: 1,
                height: 20,
                color: Colors.grey.shade400,
              ),
              Expanded(
                child: Text(
                  selectedAwayTeam ?? 'Away Team',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Player number grids
          Expanded(
            child: Row(
              children: [
                // Home team players
                Expanded(
                  child: _buildCompactPlayerGrid(true),
                ),
                Container(
                  width: 1,
                  color: Colors.grey.shade400,
                ),
                // Away team players
                Expanded(
                  child: _buildCompactPlayerGrid(false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Build compact player grid for one team
  Widget _buildCompactPlayerGrid(bool isHomeTeam) {
    final players = isHomeTeam ? _cachedHomeRoster : _cachedAwayRoster;
    final selectedPlayers =
        isHomeTeam ? selectedHomePlayers : selectedAwayPlayers;

    if (players.isEmpty) {
      return Center(
        child: Text(
          'No players loaded',
          style: TextStyle(
            fontSize: 9,
            color: Colors.grey.shade600,
          ),
        ),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6, // 6 columns for compact layout
        childAspectRatio: 1.0,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: players.length,
      itemBuilder: (context, index) {
        final player = players[index];
        final playerName = player.fullName;
        final isSelected =
            selectedPlayers.any((p) => p.fullName == player.fullName);
        final isMainPlayer = _firstPlayerSelected == playerName;

        return GestureDetector(
          onTap: () => _onPlayerSelected(player, isHomeTeam),
          child: Container(
            decoration: BoxDecoration(
              color: isMainPlayer
                  ? Colors.red.shade100
                  : isSelected
                      ? Colors.blue.shade100
                      : Colors.white,
              border: Border.all(
                color: isMainPlayer
                    ? Colors.red.shade400
                    : isSelected
                        ? Colors.blue.shade400
                        : Colors.grey.shade300,
                width: isMainPlayer || isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Center(
              child: Text(
                player.jerseyNumber ?? '?',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isMainPlayer || isSelected
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: isMainPlayer
                      ? Colors.red.shade700
                      : isSelected
                          ? Colors.blue.shade700
                          : Colors.black87,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Extract jersey number from player name
  String _extractJerseyNumber(String playerName) {
    final match = RegExp(r'#(\d+)').firstMatch(playerName);
    return match?.group(1) ?? '?';
  }

  // Handle player selection in compact picker
  void _onPlayerSelected(Player player, bool isHomeTeam) {
    setState(() {
      if (isHomeTeam) {
        final existingIndex = selectedHomePlayers
            .indexWhere((p) => p.fullName == player.fullName);
        if (existingIndex != -1) {
          selectedHomePlayers.removeAt(existingIndex);
        } else {
          selectedHomePlayers.add(player);
        }
      } else {
        final existingIndex = selectedAwayPlayers
            .indexWhere((p) => p.fullName == player.fullName);
        if (existingIndex != -1) {
          selectedAwayPlayers.removeAt(existingIndex);
        } else {
          selectedAwayPlayers.add(player);
        }
      }

      // Set first player selected for caption generation
      if (_firstPlayerSelected == null) {
        _firstPlayerSelected = player.fullName;
        _firstTeamSelected = isHomeTeam;
      }
    });

    // Update caption with new player selection
    _updateCaption();
  }

  // Remove jersey number from player name
  String _removeJerseyNumberFromName(String playerName) {
    return playerName.replaceAll(RegExp(r'#\d+\s*'), '').trim();
  }

  // Update caption based on current selections
  void _updateCaption() {
    // This method would be implemented to update the caption
    // For now, it's a placeholder that can be expanded
    print(
        'DEBUG: Updating caption with players: ${selectedHomePlayers.length} home, ${selectedAwayPlayers.length} away');
  }

  // Check image resolution and update warning state
  void _checkImageResolution(Map<String, dynamic> metadata) {
    // Try to get image dimensions from various EXIF fields
    int? width;
    int? height;

    // Try different possible field names for image dimensions
    width = _parseIntFromMetadata(metadata, ['ImageWidth', 'ExifImageWidth']);
    height =
        _parseIntFromMetadata(metadata, ['ImageHeight', 'ExifImageHeight']);

    if (width != null && height != null) {
      // Use the larger dimension for comparison
      final maxDimension = width > height ? width : height;
      _showResolutionWarning = maxDimension < _resolutionWarningThreshold;

      print(
          'DEBUG: Image resolution: ${width}x${height}, max dimension: $maxDimension, threshold: $_resolutionWarningThreshold, warning: $_showResolutionWarning');
    } else {
      _showResolutionWarning = false;
      print('DEBUG: Could not determine image resolution from metadata');
    }
  }

  // Helper method to parse integer from metadata with fallback field names
  int? _parseIntFromMetadata(
      Map<String, dynamic> metadata, List<String> fieldNames) {
    for (final fieldName in fieldNames) {
      final value = metadata[fieldName];
      if (value != null) {
        if (value is int) {
          return value;
        } else if (value is String) {
          final parsed = int.tryParse(value);
          if (parsed != null) {
            return parsed;
          }
        }
      }
    }
    return null;
  }

  // Build resolution warning widget
  Widget _buildResolutionWarning() {
    if (!_showResolutionWarning) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade300, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning,
            color: Colors.red.shade600,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Low Resolution Warning: Image resolution is below ${_resolutionWarningThreshold}px threshold',
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Launch Photoshop with the specified image
  Future<void> _launchPhotoshop(String imagePath) async {
    if (_photoshopPath == null || _photoshopPath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Photoshop path not configured. Please set it in Preferences.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // Launch Photoshop with the image file
      final result =
          await Process.run('open', ['-a', _photoshopPath!, imagePath]);

      if (result.exitCode == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Opening ${p.basename(imagePath)} in Photoshop...'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('Failed to launch Photoshop: ${result.stderr}');
      }
    } catch (e) {
      print('Error launching Photoshop: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to launch Photoshop: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
