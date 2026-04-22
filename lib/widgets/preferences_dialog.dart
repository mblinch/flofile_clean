import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_flutter/custom_dropdown.dart';

import '../services/camera_serial_service.dart';
import '../services/preferences_service.dart';
import '../utils/native_file_picker.dart';
import 'camera_serial_dialog.dart';
import 'app_compact_checkbox.dart';
import 'caption_layout_builder_dialog.dart';
import 'ftp_settings_panel.dart';

class PreferencesDialog extends StatefulWidget {
  /// When set, called to open the FTP Settings dialog (e.g. from right-click on FTP button). Shown as an option in the FTP section.
  final VoidCallback? onOpenFtpSettings;

  const PreferencesDialog({super.key, this.onOpenFtpSettings});

  @override
  State<PreferencesDialog> createState() => _PreferencesDialogState();
}

enum _PrefsCategory {
  application,
  ftp,
  teamVerb,
}

/// Same blue as the FTP button in the app.
const Color _prefsBlue = Color(0xFF0052CC);

class _PreferencesDialogState extends State<PreferencesDialog> {
  late PreferencesService _preferencesService;
  final TextEditingController _photoshopPathController = TextEditingController();
  final TextEditingController _resolutionController = TextEditingController();
  String _sportForDefault = 'baseball';
  Map<String, dynamic>? _currentPreferences;
  bool _isLoading = true;
  _PrefsCategory _selectedCategory = _PrefsCategory.application;

  @override
  void initState() {
    super.initState();
    _initializePreferences();
  }

  @override
  void dispose() {
    _photoshopPathController.dispose();
    _resolutionController.dispose();
    super.dispose();
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
      _photoshopPathController.text = _currentPreferences?['photoshopPath']?.toString() ?? '';
      final res = _currentPreferences?['resolutionWarningThreshold'] as int? ?? 3000;
      _resolutionController.text = '$res';
      final sport = _currentPreferences?['currentSport']?.toString();
      _sportForDefault = (sport == null || sport.isEmpty) ? '' : sport;
    });
  }

  @override
  Widget build(BuildContext context) {
    const sidebarWidth = 180.0;
    const contentPadding = 28.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 860,
        height: 640,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'Preferences',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const Spacer(),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.close, size: 20, color: Colors.grey.shade600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Sidebar + content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left: category list
                        Container(
                          width: sidebarWidth,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            border: Border(
                              right: BorderSide(color: Colors.grey.shade200),
                            ),
                          ),
                          child: ListView(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            children: [
                              _buildSidebarTile(
                                _PrefsCategory.application,
                                'Application',
                              ),
                              Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
                              _buildSidebarTile(
                                _PrefsCategory.ftp,
                                'FTP',
                              ),
                              Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
                              _buildSidebarTile(
                                _PrefsCategory.teamVerb,
                                'Team & Verb',
                              ),
                            ],
                          ),
                        ),
                        // Right: selected category content
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(contentPadding),
                            child: _buildCategoryContent(),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildSidebarTile(
    _PrefsCategory category,
    String label,
  ) {
    final selected = _selectedCategory == category;
    return Material(
      color: selected ? _prefsBlue.withOpacity(0.06) : Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedCategory = category),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            border: selected
                ? Border(
                    left: BorderSide(color: _prefsBlue, width: 2),
                  )
                : null,
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? _prefsBlue : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryContent() {
    switch (_selectedCategory) {
      case _PrefsCategory.application:
        return _buildApplicationContent();
      case _PrefsCategory.ftp:
        return _buildFtpContent();
      case _PrefsCategory.teamVerb:
        return _buildTeamVerbContent();
    }
  }

  Widget _buildApplicationContent() {
    final serialBylines = _currentPreferences?['serialNumberBylines'] == true;
    final burstOn = _currentPreferences?['burstDetectionEnabled'] == true;
    final resolutionThreshold = _currentPreferences?['resolutionWarningThreshold'] as int? ?? 3000;
    final resolutionEnabled = resolutionThreshold > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInlineRow(
          'Serial Number Bylines',
          child: Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AppCompactCheckbox(
                      value: serialBylines,
                      accentColor: _prefsBlue,
                      onChanged: (v) async {
                        await _preferencesService.saveSerialNumberBylines(v);
                        await _loadCurrentPreferences();
                      },
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () async {
                        final cameraService = CameraSerialService();
                        await cameraService.initialize();
                        if (!context.mounted) return;
                        await showDialog<void>(
                          context: context,
                          builder: (context) => CameraSerialDialog(cameraService: cameraService),
                        );
                      },
                      child: Text('Update Serial Number List', style: TextStyle(fontSize: 11, color: _prefsBlue)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Write photographer name and bylines according to camera serial numbers.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
        ),
        _buildInlineRow(
          'Burst sequence detection',
          child: Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AppCompactCheckbox(
                      value: burstOn,
                      accentColor: _prefsBlue,
                      onChanged: (v) async {
                        await _preferencesService.saveBurstDetectionEnabled(v);
                        await _loadCurrentPreferences();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'When saving, detect rapid bursts only forward in time from the current photo (each following shot ≤1s after the previous; earlier frames are ignored) and offer to apply the same caption to those frames. Default is off.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
        ),
        _buildInlineRow('Resolution (pixels)', child: Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AppCompactCheckbox(
                    value: resolutionEnabled,
                    accentColor: _prefsBlue,
                    onChanged: (v) async {
                      if (v) {
                        await _preferencesService
                            .saveResolutionWarningThreshold(3000);
                        _resolutionController.text = '3000';
                      } else {
                        await _preferencesService.saveResolutionWarningThreshold(0);
                        _resolutionController.text = '0';
                      }
                      await _loadCurrentPreferences();
                    },
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _resolutionController,
                      enabled: resolutionEnabled,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        hintText: 'e.g. 3000',
                        hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                      onSubmitted: (text) async {
                        if (!resolutionEnabled) return;
                        final v = int.tryParse(text);
                        if (v != null && v > 0) {
                          await _preferencesService.saveResolutionWarningThreshold(v);
                          await _loadCurrentPreferences();
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Threshold at which a warning is displayed if your picture is below a certain number of pixels on the longest side. Off or set 0 to disable.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        )),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
        ),
        _buildInlineRow('Photoshop Path', child: Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 320,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _photoshopPathController,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          hintText: 'Path to Photoshop.app',
                          hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                        onSubmitted: (text) async {
                          await _preferencesService.savePhotoshopPath(text.isEmpty ? null : text);
                          await _loadCurrentPreferences();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () async {
                        final path = await NativeFilePicker.pickFile(allowedExtensions: ['app']);
                        if (path == null || path.isEmpty || !mounted) return;
                        _photoshopPathController.text = path;
                        await _preferencesService.savePhotoshopPath(path);
                        await _loadCurrentPreferences();
                      },
                      child: Text('Browse', style: TextStyle(fontSize: 11, color: _prefsBlue)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Path to your Photoshop application.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        )),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
        ),
        _buildInlineRow(
          'Caption fields',
          child: Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCaptionFieldVisibilityRow(
                  label: 'Headline',
                  isOn: _currentPreferences?['showHeadlineField'] == true,
                  onChanged: (on) async {
                    await _preferencesService.saveShowHeadlineField(on);
                    await _loadCurrentPreferences();
                  },
                ),
                const SizedBox(height: 10),
                _buildCaptionFieldVisibilityRow(
                  label: 'Keywords',
                  isOn: _currentPreferences?['showKeywordsField'] == true,
                  onChanged: (on) async {
                    await _preferencesService.saveShowKeywordsField(on);
                    await _loadCurrentPreferences();
                  },
                ),
                const SizedBox(height: 10),
                _buildCaptionFieldVisibilityRow(
                  label: 'Personality',
                  isOn: _currentPreferences?['showPersonalityField'] != false,
                  onChanged: (on) async {
                    await _preferencesService.saveShowPersonalityField(on);
                    await _loadCurrentPreferences();
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Show or hide optional fields below the caption. The layout uses the full width for the fields that remain visible.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.view_agenda_outlined, size: 18),
                    label: const Text('Caption layout…'),
                    onPressed: () async {
                      await CaptionLayoutBuilderDialog.show(context);
                      if (!mounted) return;
                      await _loadCurrentPreferences();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
        ),
        _buildInlineRow('Sport Default', child: Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 220,
                child: DropdownFlutter<String>(
                  hintText: 'Select sport',
                  items: const ['None', 'Baseball', 'Hockey', 'Basketball', 'Soccer'],
                  initialItem: _sportForDefault.isEmpty
                      ? 'None'
                      : _sportForDefault[0].toUpperCase() + _sportForDefault.substring(1),
                  closedHeaderPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  expandedHeaderPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  listItemPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: CustomDropdownDecoration(
                    closedFillColor: Colors.grey.shade50,
                    expandedFillColor: Colors.white,
                    closedBorder: Border.all(color: Colors.grey.shade300),
                    expandedBorder: Border.all(color: Colors.grey.shade300),
                    closedBorderRadius: BorderRadius.circular(6),
                    expandedBorderRadius: BorderRadius.circular(8),
                    closedShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                    expandedShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.10),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    headerStyle: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                    listItemStyle: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                    listItemDecoration: ListItemDecoration(
                      selectedColor: Colors.grey.shade100,
                    ),
                  ),
                  onChanged: (label) async {
                    if (label == null) return;
                    final map = {
                      'None': '',
                      'Baseball': 'baseball',
                      'Hockey': 'hockey',
                      'Basketball': 'basketball',
                      'Soccer': 'soccer',
                    };
                    final v = map[label] ?? '';
                    setState(() => _sportForDefault = v);
                    try {
                      if (v.isEmpty) {
                        await _preferencesService.saveCurrentSport('');
                      } else {
                        await _preferencesService.setCurrentSportAsDefault(v);
                      }
                      await _loadCurrentPreferences();
                    } catch (_) {}
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select which sport is defaulted when you open the app.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildCaptionFieldVisibilityRow({
    required String label,
    required bool isOn,
    required Future<void> Function(bool on) onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 88,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(!isOn),
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
            ),
          ),
        ),
        AppCompactCheckbox(
          value: isOn,
          accentColor: _prefsBlue,
          onChanged: (v) => onChanged(v),
        ),
      ],
    );
  }

  Widget _buildInlineRow(String label, {required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade800),
              ),
            ),
          ),
          const SizedBox(width: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildTeamVerbContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildModernPreferenceItem(
          'Category Order',
          (_currentPreferences?['categoryOrder'] as List?)?.join(', ') ?? 'Default',
          icon: Icons.list,
        ),
        const SizedBox(height: 8),
        _buildModernPreferenceItem(
          'Favorite Verbs',
          '${(_currentPreferences?['favoriteVerbs'] as List?)?.length ?? 0} verbs',
          icon: Icons.star,
        ),
        const SizedBox(height: 8),
        _buildModernPreferenceItem(
          'Favorite Teams',
          '${(_currentPreferences?['favoriteTeams'] as List?)?.length ?? 0} teams',
          icon: Icons.sports_baseball,
        ),
      ],
    );
  }

  Widget _buildFtpContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Full FTP Server Settings panel (same as the FTP settings dialog)
        FtpSettingsPanel(
          embedded: true,
          onProfilesChanged: () => _loadCurrentPreferences(),
        ),
      ],
    );
  }

  // Build a traditional list row (no box, no icon): label and value with optional tap
  Widget _buildModernPreferenceItem(
    String label,
    String value, {
    VoidCallback? onTap,
    IconData? icon,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.chevron_right,
              size: 14,
              color: Colors.grey.shade400,
            ),
        ],
      ),
    );

    final withDivider = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
      ],
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: withDivider,
      );
    }

    return withDivider;
  }

}
