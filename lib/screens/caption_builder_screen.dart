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
        await _apiManager.fetchTeamRoster(selectedHomeTeam!);
        setState(() {
          _playerLoadingProgress = 0.5;
        });
      }

      // Load away team players
      if (selectedAwayTeam != null) {
        await _apiManager.fetchTeamRoster(selectedAwayTeam!);
        setState(() {
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

    setState(() {
      _isLoadingThumbnails = false;
    });
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

      // Sort files by name
      imageFiles.sort();

      // Simulate thumbnail loading progress
      final int totalImages = imageFiles.length;
      for (int i = 0; i < totalImages; i++) {
        await Future.delayed(const Duration(milliseconds: 20));
        setState(() {
          _thumbnailLoadingProgress = (i + 1) / totalImages;
        });
      }

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
        '-CreatorJobTitle',
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
          print('DEBUG: Metadata keys: ${currentMetadata?.keys.toList()}');
          print(
              'DEBUG: DateTimeOriginal = ${currentMetadata?['DateTimeOriginal']}');
          print('DEBUG: CreateDate = ${currentMetadata?['CreateDate']}');
          print('DEBUG: ModifyDate = ${currentMetadata?['ModifyDate']}');
        }
      } else {
        print('Exiftool error: ${proc.stderr}');
      }
    } catch (e) {
      print('Error loading metadata: $e');
    }
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
    // Build the main app content with full skeleton
    Widget mainAppContent = Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(28),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              const Text(
                'FLO FILE',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 16),
              // Team selection dropdowns (disabled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  'Home Team',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  'Away Team',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              const Spacer(),
              // API selector (disabled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  'API: Balldontlie.io',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(8.0, 2.0, 8.0, 8.0),
        child: Column(
          children: [
            // TOP ROW - Picture Preview and Thumbnail Grid
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.43,
              child: Row(
                children: [
                  // TOP LEFT BOX - Picture Preview (skeleton)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          // Header
                          Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.image,
                                  size: 16,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Picture Preview',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Image placeholder
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.image,
                                      size: 48,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No image selected',
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
                    ),
                  ),

                  // TOP RIGHT BOX - Thumbnail Grid (skeleton)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          // Header
                          Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.grid_view,
                                  size: 16,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Thumbnails',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Grid placeholder
                          Expanded(
                            child: Container(
                              margin: const EdgeInsets.all(8),
                              child: GridView.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  crossAxisSpacing: 4,
                                  mainAxisSpacing: 4,
                                ),
                                itemCount: 12,
                                itemBuilder: (context, index) {
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.image,
                                        size: 16,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                  );
                                },
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

            // BOTTOM ROW - Caption Fields and Metadata
            Expanded(
              child: Row(
                children: [
                  // BOTTOM LEFT BOX - Caption Fields (skeleton)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          // Header
                          Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Caption Fields',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Fields placeholder
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                children: [
                                  // Player selection
                                  Container(
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                          color: Colors.grey.shade300),
                                    ),
                                    child: Row(
                                      children: [
                                        const SizedBox(width: 12),
                                        Icon(
                                          Icons.person,
                                          size: 16,
                                          color: Colors.grey.shade500,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Select player...',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // Caption text field
                                  Expanded(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: Colors.grey.shade300),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Text(
                                          'Caption will appear here...',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  // Buttons row
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                                color: Colors.grey.shade300),
                                          ),
                                          child: Center(
                                            child: Text(
                                              'Previous',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade500,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Container(
                                          height: 32,
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            border: Border.all(
                                                color: Colors.grey.shade300),
                                          ),
                                          child: Center(
                                            child: Text(
                                              'Next',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade500,
                                              ),
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
                        ],
                      ),
                    ),
                  ),

                  // BOTTOM RIGHT BOX - Metadata (skeleton)
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        children: [
                          // Header
                          Container(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info,
                                  size: 16,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Metadata',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Metadata fields placeholder
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildMetadataField(
                                      'Date', 'No date detected'),
                                  const SizedBox(height: 8),
                                  _buildMetadataField(
                                      'Time', 'No time detected'),
                                  const SizedBox(height: 8),
                                  _buildMetadataField(
                                      'Location', 'No location detected'),
                                  const SizedBox(height: 8),
                                  _buildMetadataField(
                                      'Camera', 'No camera info'),
                                  const SizedBox(height: 8),
                                  _buildMetadataField(
                                      'Settings', 'No settings info'),
                                ],
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
          ],
        ),
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

    // Show loading screen if loading players or thumbnails
    if (_isLoadingPlayers || _isLoadingThumbnails) {
      return Stack(
        children: [
          // Main app skeleton in background
          mainAppContent,
          // Semi-transparent overlay with loading dialog
          Container(
            color: Colors.black.withOpacity(0.3),
            child: Center(
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
                    if (_isLoadingPlayers) ...[
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
                    ] else if (_isLoadingThumbnails) ...[
                      const Text(
                        'Loading Thumbnails...',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: _thumbnailLoadingProgress,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.green.shade600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(_thumbnailLoadingProgress * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
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
                    ),
                  ),

                  // TOP RIGHT BOX - Thumbnail Grid
                  Expanded(
                    child: ThumbnailGridWidget(
                      imagePaths: imagePaths,
                      currentIndex: currentIndex,
                      onImageSelected: _onImageSelected,
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
                    ),
                  ),

                  // BOTTOM RIGHT BOX - Metadata
                  Expanded(
                    child: MetadataWidget(
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

  Widget _buildMetadataField(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 60,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }
}
