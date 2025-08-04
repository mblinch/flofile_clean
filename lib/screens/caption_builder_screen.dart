import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
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

  // Team selection
  String? selectedHomeTeam;
  String? selectedAwayTeam;

  // API selection
  String selectedApi = 'Balldontlie.io API'; // Default to new API

  // Personality override for reset
  String? _personalityOverride;

  // Startup configuration
  bool _isStartupComplete = false;
  String? _selectedFolderPath;

  // Loading states
  bool _isLoadingPlayers = false;
  bool _isLoadingThumbnails = false;
  double _playerLoadingProgress = 0.0;
  double _thumbnailLoadingProgress = 0.0;

  // Global keys for accessing widgets
  final GlobalKey _metadataKey1 = GlobalKey();
  final GlobalKey _metadataKey2 = GlobalKey();
  final GlobalKey _captionFieldsKey1 = GlobalKey();
  final GlobalKey _captionFieldsKey2 = GlobalKey();

  // Cached player data to prevent re-fetching
  List<Player> _cachedHomeRoster = [];
  List<Player> _cachedAwayRoster = [];

  void _handleReset() {
    setState(() {
      _personalityOverride = '';
    });
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

    // Step 2: Load thumbnails
    setState(() {
      _isLoadingThumbnails = true;
      _thumbnailLoadingProgress = 0.0;
    });

    // Load images from the selected folder
    await _loadImagesFromFolder(folderPath);

    // Go straight to app - no thumbnail loading screen
    setState(() {
      _isLoadingThumbnails = false;
    });

    print('Images loaded: ${imagePaths.length} - going straight to app');
  }

  Future<void> _loadImagesFromFolder(String folderPath) async {
    try {
      final directory = Directory(folderPath);
      final List<FileSystemEntity> entities = await directory.list().toList();

      // Filter for image files
      final List<String> imageFiles = entities
          .where((entity) => entity is File)
          .map((entity) => entity.path)
          .where((path) =>
              path.toLowerCase().endsWith('.jpg') ||
              path.toLowerCase().endsWith('.jpeg') ||
              path.toLowerCase().endsWith('.png') ||
              path.toLowerCase().endsWith('.tiff') ||
              path.toLowerCase().endsWith('.bmp'))
          .toList();

      // Sort files by date taken (DateTimeOriginal from EXIF)
      await _sortImagesByDateTaken(imageFiles);

      setState(() {
        imagePaths = imageFiles;
        currentIndex = 0;
      });

      print('Loaded ${imageFiles.length} images from folder: $folderPath');

      // Load metadata for the first image
      if (imageFiles.isNotEmpty) {
        _loadMetadata();
      }
    } catch (e) {
      print('Error loading images from folder: $e');
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
        '-DescriptionWriter',
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

  // Save IPTC metadata to the current image
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

    // For thumbnail loading, show the main app with a loading overlay
    if (_isLoadingThumbnails) {
      return Stack(
        children: [
          // Main app with thumbnails rendering
          Scaffold(
            backgroundColor: Colors.grey.shade100,
            body: Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 2.0, 8.0, 8.0),
              child: Column(
                children: [
                  // TOP ROW - Reduced height (43% instead of 50%)
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.43,
                    child: Row(
                      children: [
                        // TOP LEFT BOX - Picture Preview
                        Expanded(
                          child: PicturePreviewWidget(
                            imagePaths: imagePaths,
                            currentIndex: currentIndex,
                            onImageSelected: _onImageSelected,
                            onNextImage: () {
                              if (currentIndex < imagePaths.length - 1) {
                                _onImageSelected(currentIndex + 1);
                              }
                            },
                            onPreviousImage: () {
                              if (currentIndex > 0) {
                                _onImageSelected(currentIndex - 1);
                              }
                            },
                            onSaveIptc: _saveIptcMetadata,
                          ),
                        ),

                        // TOP RIGHT BOX - Thumbnail Grid (rendering)
                        Expanded(
                          child: ThumbnailGridWidget(
                            imagePaths: imagePaths,
                            currentIndex: currentIndex,
                            onImageSelected: _onImageSelected,
                            loadingProgress: _isLoadingThumbnails
                                ? _thumbnailLoadingProgress
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // BOTTOM ROW - Increased height (60% instead of 50%)
                  Expanded(
                    child: Row(
                      children: [
                        // BOTTOM LEFT BOX - Caption Fields
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final currentPath = imagePaths.isNotEmpty
                                  ? imagePaths[currentIndex]
                                  : null;
                              print(
                                  'DEBUG: CaptionBuilderScreen - Creating CaptionFieldsWidget with currentPath: "$currentPath"');
                              print(
                                  'DEBUG: CaptionBuilderScreen - imagePaths.length: ${imagePaths.length}, currentIndex: $currentIndex');
                              return CaptionFieldsWidget(
                                key: _captionFieldsKey1,
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
                                    _onImageSelected(currentIndex + 1);
                                  }
                                },
                                onPreviousImage: () {
                                  if (currentIndex > 0) {
                                    _onImageSelected(currentIndex - 1);
                                  }
                                },
                                onReset: _handleReset,
                                personalityOverride: _personalityOverride,
                                onImagesLoaded: (files) {
                                  print(
                                      'DEBUG: CaptionBuilderScreen - onImagesLoaded called with ${files.length} files');
                                  setState(() {
                                    imagePaths = files;
                                    currentIndex = 0;
                                  });
                                  print(
                                      'DEBUG: CaptionBuilderScreen - imagePaths.length: ${imagePaths.length}, currentIndex: $currentIndex');
                                },
                                preloadedHomeRoster:
                                    _cachedHomeRoster.isNotEmpty
                                        ? _cachedHomeRoster
                                        : null,
                                preloadedAwayRoster:
                                    _cachedAwayRoster.isNotEmpty
                                        ? _cachedAwayRoster
                                        : null,
                                currentImagePath: currentPath,
                                onSaveIptc: _saveIptcMetadata,
                              );
                            },
                          ),
                        ),

                        // BOTTOM RIGHT BOX - Metadata
                        Expanded(
                          child: MetadataWidget(
                            key: _metadataKey1,
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
          ),
          // Semi-transparent loading overlay
          Container(
            color: Colors.black.withOpacity(0.3),
            child: Center(
              child: Container(
                width: 300,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Loading Thumbnails...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: _thumbnailLoadingProgress,
                      backgroundColor: Colors.grey.shade200,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.green.shade600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(_thumbnailLoadingProgress * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
        padding: const EdgeInsets.fromLTRB(8.0, 2.0, 8.0, 8.0),
        child: Column(
          children: [
            // TOP ROW - Reduced height (43% instead of 50%)
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.43,
              child: Row(
                children: [
                  // TOP LEFT BOX - Picture Preview
                  Expanded(
                    child: PicturePreviewWidget(
                      imagePaths: imagePaths,
                      currentIndex: currentIndex,
                      onImageSelected: _onImageSelected,
                      onNextImage: () {
                        if (currentIndex < imagePaths.length - 1) {
                          _onImageSelected(currentIndex + 1);
                        }
                      },
                      onPreviousImage: () {
                        if (currentIndex > 0) {
                          _onImageSelected(currentIndex - 1);
                        }
                      },
                      onSaveIptc: _saveIptcMetadata,
                    ),
                  ),

                  // TOP RIGHT BOX - Thumbnail Grid
                  Expanded(
                    child: ThumbnailGridWidget(
                      imagePaths: imagePaths,
                      currentIndex: currentIndex,
                      onImageSelected: _onImageSelected,
                      loadingProgress: _isLoadingThumbnails
                          ? _thumbnailLoadingProgress
                          : null,
                    ),
                  ),
                ],
              ),
            ),

            // BOTTOM ROW - Increased height (60% instead of 50%)
            Expanded(
              child: Row(
                children: [
                  // BOTTOM LEFT BOX - Caption Fields
                  Expanded(
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
                          _onImageSelected(currentIndex + 1);
                        }
                      },
                      onPreviousImage: () {
                        if (currentIndex > 0) {
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
                      onSaveIptc: _saveIptcMetadata,
                    ),
                  ),

                  // BOTTOM RIGHT BOX - Metadata
                  Expanded(
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
