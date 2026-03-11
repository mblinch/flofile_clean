import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../services/preferences_service.dart';
import '../utils/native_file_picker.dart';

class PreferencesDialog extends StatefulWidget {
  const PreferencesDialog({super.key});

  @override
  State<PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends State<PreferencesDialog> {
  late PreferencesService _preferencesService;
  Map<String, dynamic>? _currentPreferences;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializePreferences();
  }

  Future<void> _initializePreferences() async {
    _preferencesService = await PreferencesService.getInstance();
    await _loadCurrentPreferences();
  }

  Future<void> _loadCurrentPreferences() async {
    setState(() {
      _isLoading = true;
    });

    _currentPreferences = await _preferencesService.exportAllPreferences();

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Preferences'),
        content: const Text(
          'Are you sure you want to reset all preferences to their default values? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _preferencesService.resetToDefaults();
      await _loadCurrentPreferences();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preferences reset to defaults')),
        );
      }
    }
  }

  Future<void> _exportPreferences() async {
    try {
      final preferences = await _preferencesService.exportAllPreferences();
      final jsonString =
          const JsonEncoder.withIndent('  ').convert(preferences);

      await Clipboard.setData(ClipboardData(text: jsonString));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preferences copied to clipboard')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting preferences: $e')),
        );
      }
    }
  }

  Future<void> _importPreferences() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No data found in clipboard')),
          );
        }
        return;
      }

      final preferences =
          json.decode(clipboardData!.text!) as Map<String, dynamic>;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import Preferences'),
          content: const Text(
            'Are you sure you want to import preferences from clipboard? This will overwrite your current preferences.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await _preferencesService.importPreferences(preferences);
        await _loadCurrentPreferences();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Preferences imported successfully')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing preferences: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        height: 600,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.settings, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    'Preferences',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close,
                        size: 16, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Application Settings Section
                          _buildSectionHeader('Application Settings'),
                          const SizedBox(height: 8),

                          _buildModernPreferenceItem(
                            'Serial Number Bylines',
                            (_currentPreferences?['serialNumberBylines'] ==
                                    true)
                                ? 'Enabled'
                                : 'Disabled',
                            onTap: () => _toggleSerialNumberBylines(),
                            icon: Icons.auto_awesome,
                          ),

                          _buildModernPreferenceItem(
                            'Resolution Warning Threshold',
                            '${_currentPreferences?['resolutionWarningThreshold'] ?? 3000}px',
                            onTap: () => _editResolutionWarningThreshold(),
                            icon: Icons.warning,
                          ),

                          _buildModernPreferenceItem(
                            'Photoshop Application',
                            _currentPreferences?['photoshopPath'] != null
                                ? _getPhotoshopDisplayName(
                                    _currentPreferences!['photoshopPath'])
                                : 'Not configured',
                            onTap: () => _editPhotoshopPath(),
                            icon: Icons.brush,
                          ),

                          _buildModernPreferenceItem(
                            'Current Layout',
                            _getLayoutDisplayName(
                                _currentPreferences?['currentLayout'] ??
                                    'players_list_left'),
                            onTap: () => _editCurrentLayout(),
                            icon: Icons.view_quilt,
                          ),
                          _buildModernPreferenceItem(
                            'Caption Entry',
                            _currentPreferences?['captionEntryMode'] == 'classic'
                                ? 'Classic'
                                : 'Keyboard Fire (default)',
                            onTap: () => _editCaptionEntryMode(),
                            icon: Icons.keyboard,
                          ),

                          const SizedBox(height: 16),

                          // Team & Verb Settings Section
                          _buildSectionHeader('Team & Verb Settings'),
                          const SizedBox(height: 8),

                          _buildModernPreferenceItem(
                            'Category Order',
                            (_currentPreferences?['categoryOrder'] as List?)
                                    ?.join(', ') ??
                                'Default',
                            icon: Icons.list,
                          ),

                          _buildModernPreferenceItem(
                            'Favorite Verbs',
                            '${(_currentPreferences?['favoriteVerbs'] as List?)?.length ?? 0} verbs',
                            icon: Icons.star,
                          ),

                          _buildModernPreferenceItem(
                            'Favorite Teams',
                            '${(_currentPreferences?['favoriteTeams'] as List?)?.length ?? 0} teams',
                            icon: Icons.sports_baseball,
                          ),

                          const SizedBox(height: 16),

                          // FTP Settings Section
                          _buildSectionHeader('FTP Settings'),
                          const SizedBox(height: 8),

                          _buildModernPreferenceItem(
                            'FTP Profiles',
                            '${(_currentPreferences?['ftpProfiles'] as Map?)?.length ?? 0} profiles',
                            icon: Icons.cloud_upload,
                          ),

                          _buildModernPreferenceItem(
                            'Current FTP Profile',
                            (_currentPreferences?['currentFtpProfile']
                                    as String?) ??
                                'None',
                            icon: Icons.account_circle,
                          ),

                          _buildModernPreferenceItem(
                            'Firebar Position',
                            (_currentPreferences?['placeFirebarOnRight'] ==
                                    true)
                                ? 'Right'
                                : 'Left',
                            icon: Icons.swap_horiz,
                          ),
                        ],
                      ),
                    ),
            ),

            // Footer with action buttons
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    'Export',
                    Icons.download,
                    _exportPreferences,
                    Colors.blue.shade600,
                  ),
                  _buildActionButton(
                    'Import',
                    Icons.upload,
                    _importPreferences,
                    Colors.green.shade600,
                  ),
                  _buildActionButton(
                    'Reset',
                    Icons.refresh,
                    _resetToDefaults,
                    Colors.red.shade600,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build section header
  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
    );
  }

  // Build modern preference item
  Widget _buildModernPreferenceItem(
    String label,
    String value, {
    VoidCallback? onTap,
    IconData? icon,
  }) {
    Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.chevron_right,
              size: 16,
              color: Colors.grey.shade400,
            ),
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: content,
      );
    }

    return content;
  }

  // Build action button
  Widget _buildActionButton(
    String label,
    IconData icon,
    VoidCallback onPressed,
    Color color,
  ) {
    return SizedBox(
      height: 32,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        label: Text(
          label,
          style: const TextStyle(fontSize: 11),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(3),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
      ),
    );
  }

  // Get display name for Photoshop path
  String _getPhotoshopDisplayName(String path) {
    final fileName = path.split('/').last;
    if (fileName.endsWith('.app')) {
      return fileName.substring(0, fileName.length - 4);
    }
    return fileName;
  }

  // Get display name for layout
  String _getLayoutDisplayName(String layout) {
    switch (layout) {
      case 'players_list_left':
        return 'Players List Left';
      case 'players_list_right':
        return 'Players List Right';
      case 'players_list_top':
        return 'Players List Top';
      case 'players_list_bottom':
        return 'Players List Bottom';
      case 'compact_players_above':
        return 'Compact Players Above';
      case 'matrix_board':
        return 'Matrix Board (Fast Caption Builder)';
      case 'player_popup_board':
        return 'Player Popup (Click Player → Select Verb)';
      default:
        return 'Players List Left';
    }
  }

  Future<void> _toggleSerialNumberBylines() async {
    final currentValue = _currentPreferences?['serialNumberBylines'] ?? true;
    final newValue = !currentValue;

    await _preferencesService.saveSerialNumberBylines(newValue);
    await _loadCurrentPreferences();
  }

  Future<void> _editResolutionWarningThreshold() async {
    final currentValue =
        _currentPreferences?['resolutionWarningThreshold'] ?? 3000;
    final controller = TextEditingController(text: currentValue.toString());

    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resolution Warning Threshold'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Set the minimum resolution threshold (in pixels) for showing warnings.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Threshold (pixels)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value != null && value > 0) {
                Navigator.pop(context, value);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      await _preferencesService.saveResolutionWarningThreshold(result);
      await _loadCurrentPreferences();
    }
  }

  Future<void> _editPhotoshopPath() async {
    final currentValue = _currentPreferences?['photoshopPath'] ?? '';
    final controller = TextEditingController(text: currentValue);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 500,
          height: 400,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: [
              // Header
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.brush, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Text(
                      'Photoshop Application Path',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.close,
                          size: 16, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select your Photoshop application:',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 12),

                      // File picker button
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            try {
                              final result = await NativeFilePicker.pickFile();

                              if (result != null && result.isNotEmpty) {
                                controller.text = result;
                              }
                            } catch (e) {
                              print('Error picking file: $e');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error selecting file: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.folder_open, size: 16),
                          label: const Text('Browse for Photoshop App',
                              style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      const Text(
                        'Or enter the path manually:',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),

                      TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          hintText:
                              '/Applications/Adobe Photoshop 2024/Adobe Photoshop 2024.app',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(3),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                        ),
                        style: const TextStyle(fontSize: 11),
                      ),

                      const SizedBox(height: 12),

                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: const Text(
                          'Common locations:\n• /Applications/Adobe Photoshop 2024/Adobe Photoshop 2024.app\n• /Applications/Adobe Photoshop 2023/Adobe Photoshop 2023.app',
                          style: TextStyle(fontSize: 10, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Footer
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child:
                          const Text('Cancel', style: TextStyle(fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context, ''); // Clear the path
                      },
                      child:
                          const Text('Clear', style: TextStyle(fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, controller.text.trim());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(3),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                      ),
                      child: const Text('Save', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result != null) {
      await _preferencesService
          .savePhotoshopPath(result.isEmpty ? null : result);
      await _loadCurrentPreferences();
    }
  }

  Future<void> _editCurrentLayout() async {
    final currentValue =
        _currentPreferences?['currentLayout'] ?? 'players_list_left';

    final result = await showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 400,
          height: 300,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            children: [
              // Header
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.view_quilt,
                        size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Text(
                      'Select Layout',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.close,
                          size: 16, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Choose your preferred layout:',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 12),
                      _buildLayoutOption('players_list_left',
                          'Players List Left', currentValue),
                      _buildLayoutOption('players_list_right',
                          'Players List Right', currentValue),
                      _buildLayoutOption(
                          'players_list_top', 'Players List Top', currentValue),
                      _buildLayoutOption('players_list_bottom',
                          'Players List Bottom', currentValue),
                      _buildLayoutOption('compact_players_above',
                          'Compact Players Above', currentValue),
                      _buildLayoutOption('matrix_board',
                          'Matrix Board (Fast Caption Builder)', currentValue),
                      _buildLayoutOption(
                          'player_popup_board',
                          'Player Popup (Click Player → Select Verb)',
                          currentValue),
                    ],
                  ),
                ),
              ),

              // Footer
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child:
                          const Text('Cancel', style: TextStyle(fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context, _selectedLayout);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(3),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                      ),
                      child: const Text('Save', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result != null) {
      await _preferencesService.saveCurrentLayout(result);
      await _loadCurrentPreferences();
    }
  }

  Future<void> _editCaptionEntryMode() async {
    final currentValue =
        _currentPreferences?['captionEntryMode'] ?? 'keyboard_fire';

    final result = await showDialog<String>(
      context: context,
      builder: (context) => _CaptionEntryModeDialog(initialValue: currentValue),
    );

    if (result != null) {
      await _preferencesService.saveCaptionEntryMode(result);
      await _loadCurrentPreferences();
    }
  }

  String _selectedLayout = 'players_list_left';

  Widget _buildLayoutOption(
      String value, String displayName, String currentValue) {
    final isSelected = value == currentValue;
    _selectedLayout = isSelected ? value : _selectedLayout;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedLayout = value;
        });
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _selectedLayout == value ? Colors.blue.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: _selectedLayout == value
                ? Colors.blue.shade300
                : Colors.grey.shade300,
            width: _selectedLayout == value ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              _selectedLayout == value
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 16,
              color: _selectedLayout == value
                  ? Colors.blue.shade600
                  : Colors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Text(
              displayName,
              style: TextStyle(
                fontSize: 11,
                fontWeight: _selectedLayout == value
                    ? FontWeight.w600
                    : FontWeight.w500,
                color: _selectedLayout == value
                    ? Colors.blue.shade700
                    : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptionEntryModeDialog extends StatefulWidget {
  final String initialValue;

  const _CaptionEntryModeDialog({required this.initialValue});

  @override
  State<_CaptionEntryModeDialog> createState() => _CaptionEntryModeDialogState();
}

class _CaptionEntryModeDialogState extends State<_CaptionEntryModeDialog> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Caption Entry'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose how you write captions. You can switch back anytime.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          RadioListTile<String>(
            title: const Text('Keyboard Fire (default)'),
            subtitle: const Text(
              'Number-first flow: home → away → category → verb',
              style: TextStyle(fontSize: 11),
            ),
            value: 'keyboard_fire',
            groupValue: _selected,
            onChanged: (v) {
              if (v != null) setState(() => _selected = v);
            },
          ),
          RadioListTile<String>(
            title: const Text('Classic'),
            subtitle: const Text(
              'Original player picker and verb list layout',
              style: TextStyle(fontSize: 11),
            ),
            value: 'classic',
            groupValue: _selected,
            onChanged: (v) {
              if (v != null) setState(() => _selected = v);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
