import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
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
  // File system watcher for detecting new images
  StreamSubscription<FileSystemEvent>? _folderWatcher;

  // Loading states
  bool _isLoadingPlayers = false;
  double _playerLoadingProgress = 0.0;

  // Global keys for accessing widgets
  final GlobalKey _metadataKey2 = GlobalKey();
  final GlobalKey _captionFieldsKey2 = GlobalKey();
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
  // Track queued uploads
  final Set<String> _queuedUploads = {};
  // Track currently uploading images (max 2)
  final Set<String> _currentlyUploading = {};
  // Request id for centering selected thumbnail on arrow navigation
  int _thumbCenterRequestId = 0;

  void _handleReset() {
    setState(() {
      _personalityOverride = '';
    });
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

      // Clean up any temporary files that might have been loaded
      _removeTemporaryFiles();

      // In the background: batch EXIF read for DateTimeOriginal, compute formatted times, and sort
      // Fire-and-forget without awaiting
      Future(() => _loadExifTimesAndSort(imageFiles));

      print('Loaded ${imageFiles.length} images from folder: $folderPath');

      // Start folder watcher
      print(
          'DEBUG: Starting folder watcher from _loadImagesFromFolder: $folderPath');
      _startFolderWatcher(folderPath);

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
    dynamic metadataState = _metadataKey2.currentState;
    if (metadataState != null) {
      Map<String, String> metadataValues = metadataState.getCurrentValues();
      allValues.addAll(metadataValues);
      print('Retrieved metadata values: $metadataValues');
      print('DEBUG: Creator field value: "${metadataValues['Creator']}"');
    }

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
    dynamic metadataState = _metadataKey2.currentState;
    if (metadataState != null) {
      Map<String, String> metadataValues = metadataState.getCurrentValues();
      allValues.addAll(metadataValues);
    }

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
    final picturePreviewState2 =
        _picturePreviewKey2.currentState as PicturePreviewWidgetState?;

    if (picturePreviewState2 != null) {
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

  // Handle image deletion
  void _onImageDeleted(String imagePath) {
    setState(() {
      // Remove the deleted image from the list
      imagePaths.remove(imagePath);

      // Remove from uploaded images set
      _uploadedImages.remove(imagePath);

      // Remove from upload progress
      _uploadProgress.remove(imagePath);

      // Remove from EXIF times cache
      _exifTimes?.remove(imagePath);

      // Remove from XMP data
      _xmpRatings?.remove(imagePath);
      _xmpLabels?.remove(imagePath);
      _xmpTagged?.remove(imagePath);

      // Adjust current index if needed
      if (imagePaths.isEmpty) {
        currentIndex = 0;
      } else if (currentIndex >= imagePaths.length) {
        currentIndex = imagePaths.length - 1;
      }

      // Load metadata for the current image if there are any images left
      if (imagePaths.isNotEmpty) {
        _loadMetadata();
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

  // Save metadata directly to a specific image file
  Future<void> _saveMetadataToImage(
      String imagePath, Map<String, dynamic> metadata) async {
    print('Saving metadata to specific image: $imagePath');

    // Convert metadata to exiftool arguments
    List<String> args = [];

    // Add all metadata fields
    metadata.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) {
        args.addAll(['-$key=$value']);
      }
    });

    // Add the target file
    args.add(imagePath);

    try {
      final proc = await Process.run('exiftool', args);
      if (proc.exitCode == 0) {
        print('Successfully saved metadata to $imagePath');
      } else {
        print('Exiftool error saving metadata to $imagePath: ${proc.stderr}');
      }
    } catch (e) {
      print('Error saving metadata to $imagePath: $e');
    }
  }

  // Handle FTP image - Add to queue and process
  void _onFtpImage(String imagePath) {
    print('DEBUG: _onFtpImage called for: $imagePath');

    // Check if already uploaded, uploading, or queued
    if (_uploadedImages.contains(imagePath)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${p.basename(imagePath)} already uploaded'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
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

    // Add to queue
    setState(() {
      _queuedUploads.add(imagePath);
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

      // Start the upload
      captionState.uploadImageViaFtp(imagePath).then((_) {
        // Upload successful
        setState(() {
          _uploadedImages.add(imagePath);
          _currentlyUploading.remove(imagePath);
          _uploadProgress.remove(imagePath); // Clear progress
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

  // Handle multi-selection
  void _onMultiSelect(List<String> selectedPaths) {
    print('Multi-selection: ${selectedPaths.length} images selected');
    // For now, just log the selection
    // In the future, this could enable bulk operations
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
  }

  @override
  void dispose() {
    _thumbnailScrollController.dispose();
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
                      onCopyMetadata: _onCopyMetadata,
                      onPasteMetadata: _onPasteMetadata,
                      onFtpImage: _onFtpImage,
                      onImageDeleted: _onImageDeleted,
                      onImageRenamed: _onImageRenamed,
                      uploadedImages: _uploadedImages,
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
                      queuedUploads: _queuedUploads,
                      currentlyUploading: _currentlyUploading,
                      xmpRatings: _xmpRatings,
                      xmpLabels: _xmpLabels,
                      xmpTagged: _xmpTagged,
                      lockedPaths: _lockedPaths,
                      uploadProgress: _uploadProgress,
                      centerRequestId: _thumbCenterRequestId,
                      onImageDeleted: _onImageDeleted,
                      onCopyMetadata: _onCopyMetadata,
                      onPasteMetadata: _onPasteMetadata,
                      onFtpImage: _onFtpImage,
                      onImageRenamed: _onImageRenamed,
                      onMultiSelect: _onMultiSelect,
                    ),
                  ),
                ],
              ),
            ),

            // Divider between top and bottom quadrants
            Container(
              height: 1,
              color: Colors.grey.shade400,
              margin: const EdgeInsets.symmetric(vertical: 2),
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
                        print(
                            'DEBUG: onImagesLoaded called with ${files.length} files');
                        setState(() {
                          imagePaths = files;
                          currentIndex = 0;
                        });
                      },
                      onStartFolderWatcher: _startFolderWatcher,
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
                        // Queue manager handles adding to uploaded set
                        // This callback is mainly for the main FTP button
                        if (!_currentlyUploading.contains(imagePath)) {
                          setState(() {
                            _uploadedImages.add(imagePath);
                            _uploadProgress
                                .remove(imagePath); // Clear progress when done
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
