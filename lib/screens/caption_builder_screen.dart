import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers.dart';
import '../widgets/app_header_widget.dart';
import '../widgets/picture_preview_widget.dart';
import '../widgets/caption_fields_widget.dart';
import '../widgets/thumbnail_grid_widget.dart';

import '../widgets/startup_dialog.dart';

import '../widgets/metadata_popup_dialog.dart';
import '../services/api_manager.dart';
import '../services/mlb_api_service.dart'; // For Player model
import '../utils/exiftool_helper.dart';

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
  Map<String, dynamic>?
      _originalMetadata; // Track original metadata for change detection
  Map<String, dynamic>?
      _originalCaptionData; // Track original caption data for change detection

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

  // Show metadata popup dialog
  void _showMetadataPopup() async {
    if (imagePaths.isEmpty || currentIndex >= imagePaths.length) return;

    // Load fresh metadata directly from the file for the popup
    // This ensures we get the actual file data, not processed widget data
    final imagePath = imagePaths[currentIndex];
    print('DEBUG: Loading fresh metadata for popup from: $imagePath');

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

    print('DEBUG: Fresh metadata for popup: $freshMetadata');
    print(
        'DEBUG: Fresh metadata SupplementalCategories: ${freshMetadata['SupplementalCategories']}');
    print(
        'DEBUG: Fresh metadata XMP-photoshop:SupplementalCategories: ${freshMetadata['XMP-photoshop:SupplementalCategories']}');
    print(
        'DEBUG: Fresh metadata IPTC:SupplementalCategories: ${freshMetadata['IPTC:SupplementalCategories']}');
    print(
        'DEBUG: Fresh metadata XMP:SupplementalCategories: ${freshMetadata['XMP:SupplementalCategories']}');
    print('DEBUG: Fresh metadata keys: ${freshMetadata.keys.toList()}');

    showDialog(
      context: context,
      builder: (context) => MetadataPopupDialog(
        metadata: freshMetadata,
        imagePath: imagePaths[currentIndex],
        onMetadataUpdated: (updatedMetadata) async {
          // Persist edits to the current file before any navigation
          await _saveExifToolMetadataToImage(
              imagePaths[currentIndex], updatedMetadata);

          setState(() {
            currentMetadata = updatedMetadata;
          });

          // Reload to reflect saved values
          await _loadMetadata();
        },
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
                  final subSecTime = item['SubSecTimeOriginal']?.toString();
                  final dt = _parseExifDateTime(dateStr, subSecTime);
                  times[sourceFile] = dt;
                  print(
                      'DEBUG: Parsed EXIF time for $sourceFile: $dateStr + $subSecTime = $dt');
                  // format to 12h as per preference, including milliseconds
                  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
                  final minute = dt.minute.toString().padLeft(2, '0');
                  final second = dt.second.toString().padLeft(2, '0');
                  final millisecond = dt.millisecond.toString().padLeft(3, '0');
                  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
                  formatted[sourceFile] =
                      '$hour:$minute:$second.$millisecond $ampm';
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
          // Format file time to 12h as per preference, including milliseconds
          final hour = fileTime.hour % 12 == 0 ? 12 : fileTime.hour % 12;
          final minute = fileTime.minute.toString().padLeft(2, '0');
          final second = fileTime.second.toString().padLeft(2, '0');
          final millisecond = fileTime.millisecond.toString().padLeft(3, '0');
          final ampm = fileTime.hour >= 12 ? 'PM' : 'AM';
          formatted[path] = '$hour:$minute:$second.$millisecond $ampm';
        }
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

  // Save IPTC metadata to the current image (with UI refresh)
  Future<void> _saveIptcMetadata() async {
    if (imagePaths.isEmpty || currentIndex >= imagePaths.length) return;

    final imagePath = imagePaths[currentIndex];
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

      // Handle supplemental categories with overwrite semantics
      final List<String> rawInputs = [
        allValues['SupplementalCategories1']?.toString() ?? '',
        allValues['SupplementalCategories2']?.toString() ?? '',
        allValues['SupplementalCategories3']?.toString() ?? '',
      ];

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

      // Handle supplemental categories with overwrite semantics
      final List<String> rawInputs = [
        allValues['SupplementalCategories1']?.toString() ?? '',
        allValues['SupplementalCategories2']?.toString() ?? '',
        allValues['SupplementalCategories3']?.toString() ?? '',
      ];

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

    for (String filePath in imageFiles) {
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

  // Handle image selection
  void _onImageSelected(int index) {
    print('DEBUG: _onImageSelected called with index: $index');
    print('DEBUG: _originalCaptionData is: $_originalCaptionData');

    // Directly switch to the selected image without checking for unsaved changes
    print('DEBUG: Switching directly to image $index');
    _switchToImage(index);
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
      await _saveIptcMetadata();

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
    print('DEBUG: _switchToImage called with index: $index');
    print('DEBUG: Clearing _originalCaptionData');

    setState(() {
      currentIndex = index;
    });

    // Clear the original caption data to prevent false change detection
    _originalCaptionData = null;
    print('DEBUG: _originalCaptionData after clearing: $_originalCaptionData');

    _loadMetadata();
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
        return 'IPTC:SubLocation'; // Photo Mechanic's preferred field
      case 'City':
        return 'IPTC:City'; // Photo Mechanic's preferred field
      case 'Province/State':
        return 'IPTC:ProvinceState'; // Photo Mechanic's preferred field

      case 'Special Instructions':
        return 'IPTC:SpecialInstructions'; // Photo Mechanic's preferred field
      case 'Personality':
        return 'XMP-getty:Personality';
      case 'Caption':
        return 'IPTC:Description'; // Photo Mechanic's preferred field
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

      // Handle supplemental categories with overwrite semantics
      final List<String> rawInputs = [
        allValues['SupplementalCategories1']?.toString() ?? '',
        allValues['SupplementalCategories2']?.toString() ?? '',
        allValues['SupplementalCategories3']?.toString() ?? '',
      ];

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

      // Collect supplemental categories using normalized approach
      // ONLY use the individual UI fields, NOT the corrupted SupplementalCategories array
      final List<String> rawInputs = [
        metadata['SupplementalCategories1']?.toString() ?? '',
        metadata['SupplementalCategories2']?.toString() ?? '',
        metadata['SupplementalCategories3']?.toString() ?? '',
      ];

      // Add each field that has a value
      metadata.forEach((key, value) {
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

      // Always overwrite original file
      args.add('-overwrite_original');
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
              exifMetadata['XMP:Subject'] = value;
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
        padding: const EdgeInsets.fromLTRB(0.0, 1.0, 0.0, 4.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // LEFT COLUMN - Picture Preview and Thumbnails
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  // Picture preview - 50% of screen height
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
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
                      onApplyIptcTemplate: _onApplyIptcTemplate,
                      onFtpImage: _onFtpImage,
                      onImageDeleted: _onImageDeleted,
                      onImageRenamed: _onImageRenamed,
                      uploadedImages: _uploadedImages,
                      queuedUploads: _queuedUploads,
                      currentlyUploading: _currentlyUploading,
                      uploadProgress: _uploadProgress,
                      xmpRatings: _xmpRatings,
                      xmpLabels: _xmpLabels,
                      xmpTagged: _xmpTagged,
                      lockedPaths: _lockedPaths,
                      onEditMetadata: _showMetadataPopup,
                    ),
                  ),

                  // Divider line between picture preview and thumbnails
                  Container(
                    height: 1,
                    color: Colors.grey.shade300,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                  ),

                  // Thumbnail grid - takes remaining space
                  Expanded(
                    child: ThumbnailGridWidget(
                      imagePaths: imagePaths,
                      currentIndex: currentIndex,
                      onImageSelected: _onImageSelected,
                      uploadedImages: _uploadedImages,
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
                    ),
                  ),
                ],
              ),
            ),

            // RIGHT COLUMN - Player picker, firebar, verbs
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
                getCurrentMetadataValues: () {
                  // Metadata values now come from popup dialog, not main UI widget
                  return {};
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
                preloadedHomeRoster:
                    _cachedHomeRoster.isNotEmpty ? _cachedHomeRoster : null,
                preloadedAwayRoster:
                    _cachedAwayRoster.isNotEmpty ? _cachedAwayRoster : null,
                currentImagePath:
                    imagePaths.isNotEmpty ? imagePaths[currentIndex] : null,
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
          ],
        ),
      ),
    );
  }
}
