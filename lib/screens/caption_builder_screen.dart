import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import '../widgets/app_header_widget.dart';
import '../widgets/picture_preview_widget.dart';
import '../widgets/thumbnail_grid_widget.dart';
import '../widgets/caption_fields_widget.dart';
import '../widgets/metadata_widget.dart';
import '../widgets/startup_dialog.dart';
import '../services/api_manager.dart';
import '../services/mlb_api_service.dart'; // For Player model

class CaptionBuilderScreen extends StatefulWidget {
  const CaptionBuilderScreen({super.key});

  @override
  _CaptionBuilderScreenState createState() => _CaptionBuilderScreenState();
}

class _CaptionBuilderScreenState extends State<CaptionBuilderScreen> {
  // API manager
  final ApiManager _apiManager = ApiManager();

  // Image state management
  List<String> imagePaths = [];
  int currentIndex = 0;

  // Metadata state
  Map<String, dynamic>? currentMetadata;
  // Precomputed EXIF times for thumbnails
  Map<String, String> _exifTimes = {};
  // XMP metadata for rating and color label
  Map<String, int> _xmpRatings = {};
  Map<String, String> _xmpLabels = {};
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
  bool _isStartupComplete = false;
  String? _selectedFolderPath;
  // Folder watcher disabled to prevent image jumping

  // Loading states
  bool _isLoadingPlayers = false;
  double _playerLoadingProgress = 0.0;

  // Global keys for accessing widgets
  final GlobalKey _metadataKey1 = GlobalKey();
  final GlobalKey _metadataKey2 = GlobalKey();
  final GlobalKey _captionFieldsKey1 = GlobalKey();
  final GlobalKey _captionFieldsKey2 = GlobalKey();
  final GlobalKey _picturePreviewKey1 = GlobalKey();
  final GlobalKey _picturePreviewKey2 = GlobalKey();

  // Scroll controller for thumbnail grid
  final ScrollController _thumbnailScrollController = ScrollController();

  // Cached player data to prevent re-fetching
  List<Player> _cachedHomeRoster = [];
  List<Player> _cachedAwayRoster = [];

  // Track uploaded images
  final Set<String> _uploadedImages = {};
  // Track upload progress for thumbnails
  final Map<String, double> _uploadProgress = {};
  // Request id for centering selected thumbnail on arrow navigation
  int _thumbCenterRequestId = 0;

  void _handleReset() {
    setState(() {
      _personalityOverride = '';
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

  void _handleStartupComplete(
      String folderPath, String? homeTeam, String? awayTeam) {
    setState(() {
      _selectedFolderPath = folderPath;
      selectedHomeTeam = homeTeam;
      selectedAwayTeam = awayTeam;
      _isStartupComplete = true;
    });

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

      if (selectedHomeTeam != null) {
        final homeRoster = await _apiManager.fetchTeamRoster(selectedHomeTeam!);
        setState(() {
          _cachedHomeRoster = homeRoster;
          _playerLoadingProgress = 0.5;
        });
      }

      // Load away team players
      if (selectedAwayTeam != null) {
        final awayRoster = await _apiManager.fetchTeamRoster(selectedAwayTeam!);
        setState(() {
          _cachedAwayRoster = awayRoster;
          _playerLoadingProgress = 1.0;
        });
      }

      // Small delay to show completion
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (e) {
      print('Error loading players: $e');
      // Continue even if player loading fails
    }

    setState(() {
      _isLoadingPlayers = false;
    });

    // Load images from the selected folder
    await _loadImagesFromFolder(folderPath);

    print('Images loaded: ${imagePaths.length} - going straight to app');
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

      // Filter for image files
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

      // Set images immediately for instant thumbnail rendering and try to
      // preserve the previously selected image (if it still exists)
      setState(() {
        imagePaths = List.from(imageFiles);
        if (previouslySelectedPath != null) {
          final idx = imageFiles.indexOf(previouslySelectedPath);
          currentIndex = idx >= 0 ? idx : 0;
        } else {
          currentIndex = 0;
        }
      });

      // In the background: batch EXIF read for DateTimeOriginal, compute formatted times, and sort
      // Fire-and-forget without awaiting
      Future(() => _loadExifTimesAndSort(imageFiles));

      print('Loaded ${imageFiles.length} images from folder: $folderPath');

      // Load metadata for the first image
      if (imageFiles.isNotEmpty) {
        _loadMetadata();
      }
    } catch (e) {
      print('Error loading images from folder: $e');
    }
  }

  // Begin watching a folder and debounce reloads when image files change
  // Folder watching methods removed to prevent image jumping

  Future<void> _loadExifTimesAndSort(List<String> imageFiles) async {
    try {
      if (imageFiles.isEmpty) return;

      // Batch exiftool call for all files (DateTimeOriginal, Rating, Label, Tagged, Keep)
      final args = <String>[
        '-j',
        '-DateTimeOriginal',
        '-XMP:Rating',
        '-XMP:Label',
        '-XMP:Tagged',
        '-XMP:PMKeep'
      ];
      args.addAll(imageFiles);
      final proc = await Process.run('exiftool', args);
      final Map<String, DateTime> times = {};
      final Map<String, String> formatted = {};
      final Map<String, int> ratings = {};
      final Map<String, String> labels = {};
      final Map<String, bool> tagged = {};

      if (proc.exitCode == 0) {
        final List data = jsonDecode(proc.stdout as String);
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
                final dt = DateTime.parse(
                    dateStr.replaceFirst(':', '-').replaceFirst(':', '-'));
                times[sourceFile] = dt;
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
      }

      // Fallback to file modified time when missing
      for (final path in imageFiles) {
        times[path] ??= await File(path).lastModified();
        formatted[path] ??= '';
      }

      // Sort paths by time
      final sorted = List<String>.from(imageFiles)
        ..sort((a, b) => (times[a]!).compareTo(times[b]!));

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

  @override
  void initState() {
    super.initState();
  }

  // Load metadata from the current image
  Future<void> _loadMetadata() async {
    if (imagePaths.isEmpty || currentIndex >= imagePaths.length) return;

    final imagePath = imagePaths[currentIndex];
    print('Loading metadata from: $imagePath');

    try {
      // Extract metadata via exiftool in JSON format
      final proc = await Process.run('exiftool', [
        '-j', // JSON output
        '-Caption-Abstract',
        '-ImageDescription',
        '-XMP-getty:Personality',
        '-TransmissionReference',
        '-CaptionWriter',
        '-Headline',
        '-Keywords',
        '-Creator',
        '-AuthorsPosition',
        '-Credit',
        '-Copyright',
        '-Source',
        '-ObjectName',
        '-Category',
        '-SupplementalCategories',
        '-XMP-photoshop:Instructions',
        '-Sub-location',
        '-City',
        '-Province-State',
        '-Urgency',
        '-Country',
        '-CountryCode',
        '-TimeDate',
        '-DateTimeOriginal',
        '-CreateDate',
        '-ModifyDate',
        '-FileModifyDate',
        imagePath,
      ]);

      if (proc.exitCode == 0) {
        final List data = jsonDecode(proc.stdout as String);
        if (data.isNotEmpty) {
          setState(() {
            currentMetadata = data.first as Map<String, dynamic>;
          });
          print('Metadata loaded successfully');
        }
      } else {
        print('Exiftool error: ${proc.stderr}');
      }
    } catch (e) {
      print('Error loading metadata: $e');
    }
  }

  // Save IPTC metadata to the current image (with UI refresh)
  Future<void> _saveIptcMetadata() async {
    if (imagePaths.isEmpty || currentIndex >= imagePaths.length) return;

    final imagePath = imagePaths[currentIndex];
    print('Saving IPTC metadata to: $imagePath');

    // Get values from both widgets
    Map<String, String> allValues = {};

    // Get metadata values from the metadata widget
    dynamic metadataState =
        _metadataKey1.currentState ?? _metadataKey2.currentState;
    if (metadataState != null) {
      Map<String, String> metadataValues = metadataState.getCurrentValues();
      allValues.addAll(metadataValues);
      print('Retrieved metadata values: $metadataValues');
      print('DEBUG: Creator field value: "${metadataValues['Creator']}"');
    }

    // Get caption values from the caption fields widget
    dynamic captionState =
        _captionFieldsKey1.currentState ?? _captionFieldsKey2.currentState;
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

    try {
      // Build exiftool command arguments
      List<String> args = [];

      // Add each field that has a value
      allValues.forEach((key, value) {
        if (value.trim().isNotEmpty) {
          args.add('-$key=$value');
          if (key == 'Creator') {
            print('DEBUG: Adding Creator to exiftool args: -$key=$value');
          }
        }
      });

      // Handle supplemental categories specially (combine them into array)
      List<String> suppCats = [];
      if (allValues['SupplementalCategories1']?.trim().isNotEmpty == true) {
        suppCats.add(allValues['SupplementalCategories1']!);
      }
      if (allValues['SupplementalCategories2']?.trim().isNotEmpty == true) {
        suppCats.add(allValues['SupplementalCategories2']!);
      }
      if (allValues['SupplementalCategories3']?.trim().isNotEmpty == true) {
        suppCats.add(allValues['SupplementalCategories3']!);
      }

      // Remove individual supplemental category args and add combined one
      args.removeWhere((arg) => arg.startsWith('-SupplementalCategories'));
      if (suppCats.isNotEmpty) {
        args.add('-SupplementalCategories=${suppCats.join(',')}');
      }

      // Always overwrite original file
      args.add('-overwrite_original');
      args.add(imagePath);

      // Only run exiftool if we have metadata to write
      if (args.length > 2) {
        // More than just -overwrite_original and path
        print('Running exiftool with args: $args');
        final proc = await Process.run('exiftool', args);

        if (proc.exitCode == 0) {
          print('IPTC metadata saved successfully');

          // Debug: Verify caption was actually written
          final verifyProc =
              await Process.run('exiftool', ['-Caption-Abstract', imagePath]);
          print('DEBUG: Caption verification after save: ${verifyProc.stdout}');

          // Don't refresh EXIF data for background saves to avoid UI glitches
        } else {
          print('Exiftool error saving metadata: ${proc.stderr}');
        }
      } else {
        print('No metadata values to save');
      }
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

    final imagePath = imagePaths[currentIndex];
    print('DEBUG: Saving IPTC metadata in background to: $imagePath');

    // Get values from both widgets
    Map<String, String> allValues = {};

    // Get metadata values from the metadata widget
    dynamic metadataState =
        _metadataKey1.currentState ?? _metadataKey2.currentState;
    if (metadataState != null) {
      Map<String, String> metadataValues = metadataState.getCurrentValues();
      allValues.addAll(metadataValues);
    }

    // Get caption values from the caption fields widget
    dynamic captionState =
        _captionFieldsKey1.currentState ?? _captionFieldsKey2.currentState;
    if (captionState != null) {
      Map<String, String> captionValues =
          captionState.getCurrentCaptionValues();
      allValues.addAll(captionValues);
    }

    if (allValues.isEmpty) {
      print('DEBUG: Could not access widget states for background save');
      return;
    }

    print('DEBUG: Background save - allValues: $allValues');

    try {
      // Build exiftool command arguments
      List<String> args = [];

      // Add each field that has a value
      allValues.forEach((key, value) {
        if (value.trim().isNotEmpty) {
          args.add('-$key=$value');
        }
      });

      // Handle supplemental categories specially (combine them into array)
      List<String> suppCats = [];
      if (allValues['SupplementalCategories1']?.trim().isNotEmpty == true) {
        suppCats.add(allValues['SupplementalCategories1']!);
      }
      if (allValues['SupplementalCategories2']?.trim().isNotEmpty == true) {
        suppCats.add(allValues['SupplementalCategories2']!);
      }
      if (allValues['SupplementalCategories3']?.trim().isNotEmpty == true) {
        suppCats.add(allValues['SupplementalCategories3']!);
      }

      // Remove individual supplemental category args and add combined one
      args.removeWhere((arg) => arg.startsWith('-SupplementalCategories'));
      if (suppCats.isNotEmpty) {
        args.add('-SupplementalCategories=${suppCats.join(',')}');
      }

      // Always overwrite original file
      args.add('-overwrite_original');
      args.add(imagePath);

      // Only run exiftool if we have metadata to write
      print('DEBUG: Background save - args: $args');
      if (args.length > 2) {
        print('DEBUG: Running exiftool for background save');
        final proc = await Process.run('exiftool', args);
        if (proc.exitCode == 0) {
          print('DEBUG: Background IPTC metadata saved successfully');
        } else {
          print('DEBUG: Background exiftool error: ${proc.stderr}');
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
    final picturePreviewState1 =
        _picturePreviewKey1.currentState as PicturePreviewWidgetState?;
    final picturePreviewState2 =
        _picturePreviewKey2.currentState as PicturePreviewWidgetState?;

    if (picturePreviewState1 != null) {
      print('DEBUG: Found picture preview state 1, refreshing EXIF data');
      picturePreviewState1.refreshExifData();
    } else if (picturePreviewState2 != null) {
      print('DEBUG: Found picture preview state 2, refreshing EXIF data');
      picturePreviewState2.refreshExifData();
    } else {
      print('DEBUG: No picture preview state found');
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

  // Handle image selection
  void _onImageSelected(int index) {
    setState(() {
      currentIndex = index;
    });
    _loadMetadata();
    // Center thumbnails only when arrow navigation explicitly requests it
  }

  @override
  void dispose() {
    _thumbnailScrollController.dispose();
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
              ),
            ),
          ),
        ],
      );
    }

    // Show loading screen only for players
    if (_isLoadingPlayers) {
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
                const Text(
                  'Loading Players...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: _playerLoadingProgress,
                  backgroundColor: Colors.grey.shade200,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(_playerLoadingProgress * 100).toInt()}%',
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
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(4.0, 1.0, 4.0, 4.0),
        child: Column(
          children: [
            // TOP ROW - Increased height (40% instead of 35%)
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.40,
              child: Row(
                children: [
                  // TOP LEFT BOX - Picture Preview
                  Expanded(
                    flex: 6,
                    child: PicturePreviewWidget(
                      key: _picturePreviewKey2,
                      imagePaths: imagePaths,
                      currentIndex: currentIndex,
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
                      // Quick navigation (no thumbnail centering or extra state churn)
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
                        print('DEBUG: Quick previous image called');
                        if (currentIndex > 0) {
                          setState(() {
                            currentIndex = currentIndex - 1;
                          });
                          _loadMetadata();
                        }
                      },
                      onSaveIptc: _saveIptcMetadata,
                      onSaveIptcBackground: _saveIptcMetadataBackground,
                    ),
                  ),

                  // TOP RIGHT BOX - Thumbnail Grid
                  Expanded(
                    flex: 4,
                    child: ThumbnailGridWidget(
                      imagePaths: imagePaths,
                      currentIndex: currentIndex,
                      onImageSelected: _onImageSelected,
                      scrollController: _thumbnailScrollController,
                      exifTimes: _exifTimes,
                      uploadedImages: _uploadedImages,
                      xmpRatings: _xmpRatings,
                      xmpLabels: _xmpLabels,
                      xmpTagged: _xmpTagged,
                      lockedPaths: _lockedPaths,
                      uploadProgress: _uploadProgress,
                      centerRequestId: _thumbCenterRequestId,
                    ),
                  ),
                ],
              ),
            ),

            // BOTTOM ROW - Increased height (68% instead of 60%)
            Expanded(
              child: Row(
                children: [
                  // BOTTOM LEFT BOX - Caption Fields
                  Expanded(
                    flex: 6,
                    child: CaptionFieldsWidget(
                      key: _captionFieldsKey2,
                      metadata: currentMetadata,
                      onMetadataUpdated: (metadata) {
                        setState(() {
                          currentMetadata = metadata;
                        });
                      },
                      homeTeam: selectedHomeTeam,
                      awayTeam: selectedAwayTeam,
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
                      currentImagePath: imagePaths.isNotEmpty
                          ? imagePaths[currentIndex]
                          : null,
                      currentIndex: imagePaths.isNotEmpty ? currentIndex : null,
                      totalImages: imagePaths.length,
                      onSaveIptc: _saveIptcMetadata,
                      onImageUploaded: (imagePath) {
                        setState(() {
                          _uploadedImages.add(imagePath);
                          _uploadProgress
                              .remove(imagePath); // Clear progress when done
                        });
                      },
                      onUploadProgress: (imagePath, progress) {
                        setState(() {
                          _uploadProgress[imagePath] = progress;
                        });
                      },
                    ),
                  ),

                  // BOTTOM RIGHT BOX - Metadata
                  Expanded(
                    flex: 4,
                    child: MetadataWidget(
                      key: _metadataKey2,
                      metadata: currentMetadata,
                      onMetadataUpdated: (metadata) {
                        setState(() {
                          currentMetadata = metadata;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
