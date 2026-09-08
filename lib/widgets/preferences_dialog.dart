import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_flutter/custom_dropdown.dart';

import '../services/admin_service.dart';
import '../services/app_defaults_firestore_service.dart';
import '../services/auth_service.dart';
import '../services/camera_serial_service.dart';
import '../services/preferences_service.dart';
import '../theme/ff_tokens.dart';
import '../utils/native_file_picker.dart';
import 'camera_serial_dialog.dart';
import 'app_compact_checkbox.dart';
import 'app_styled_dialogs.dart';
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

class _PreferencesDialogState extends State<PreferencesDialog> {
  late PreferencesService _preferencesService;
  final TextEditingController _photoshopPathController =
      TextEditingController();
  final TextEditingController _resolutionController = TextEditingController();
  final TextEditingController _mlbInningTzController = TextEditingController();
  String _sportForDefault = 'baseball';
  String _publishSport = 'baseball';
  Map<String, dynamic>? _currentPreferences;
  bool _isLoading = true;
  bool _isAdmin = false;
  bool _appDefaultsBusy = false;
  _PrefsCategory _selectedCategory = _PrefsCategory.application;
  FfTokens get _t => Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;

  @override
  void initState() {
    super.initState();
    _initializePreferences();
  }

  @override
  void dispose() {
    _photoshopPathController.dispose();
    _resolutionController.dispose();
    _mlbInningTzController.dispose();
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
    final admin = await AdminService.isCurrentUserAdmin();

    setState(() {
      _isAdmin = admin;
      _isLoading = false;
      _photoshopPathController.text =
          _currentPreferences?['photoshopPath']?.toString() ?? '';
      final res =
          _currentPreferences?['resolutionWarningThreshold'] as int? ?? 3000;
      _resolutionController.text = '$res';
      _mlbInningTzController.text =
          _currentPreferences?['mlbInningExifTimezone']?.toString() ??
              PreferencesService.mlbInningExifTimezoneDefault;
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
          color: _t.surface,
          borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
          border: Border.all(color: _t.divider),
          boxShadow: [
            BoxShadow(
              color: _t.bg.withValues(alpha: 0.55),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
          child: Column(
            children: [
              // Header
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: _t.surface,
                  border: Border(
                    bottom: BorderSide(color: _t.divider, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'Preferences',
                      style: _t.labelStyle.copyWith(
                        fontSize: 13,
                        color: _t.text,
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
                          child: Icon(
                            Icons.close,
                            size: 20,
                            color: _t.textSecondary,
                          ),
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
                              color: _t.sunken,
                              border: Border(
                                right: BorderSide(color: _t.divider),
                              ),
                            ),
                            child: ListView(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              children: [
                                _buildSidebarTile(
                                  _PrefsCategory.application,
                                  'Application',
                                ),
                                Divider(
                                    height: 1, thickness: 1, color: _t.divider),
                                _buildSidebarTile(
                                  _PrefsCategory.ftp,
                                  'FTP',
                                ),
                                Divider(
                                    height: 1, thickness: 1, color: _t.divider),
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
      color: selected ? _t.selectedFill : Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedCategory = category),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            border: selected
                ? Border(
                    left: BorderSide(color: _t.accent, width: 2),
                  )
                : null,
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? _t.accent : _t.textSecondary,
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
    final resolutionThreshold =
        _currentPreferences?['resolutionWarningThreshold'] as int? ?? 3000;
    final resolutionEnabled = resolutionThreshold > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (AuthService.instance.isFirebaseReady) ...[
          _buildAccountSection(),
          const SizedBox(height: 20),
          Divider(height: 1, color: _t.divider),
          const SizedBox(height: 20),
        ],
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
                      accentColor: _t.accent,
                      onChanged: (v) async {
                        await _preferencesService.saveSerialNumberBylines(v);
                        await _loadCurrentPreferences();
                      },
                    ),
                    const SizedBox(width: 12),
                    ElevatedGreyButton(
                      label: 'Update Serial Number List',
                      fontSize: 11,
                      onPressed: () async {
                        final cameraService = CameraSerialService();
                        await cameraService.initialize();
                        if (!context.mounted) return;
                        await showDialog<void>(
                          context: context,
                          builder: (context) =>
                              CameraSerialDialog(cameraService: cameraService),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Write photographer name and bylines according to camera serial numbers.',
                  style: TextStyle(fontSize: 11, color: _t.textSecondary),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, thickness: 1, color: _t.divider),
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
                      accentColor: _t.accent,
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
                  style: TextStyle(fontSize: 11, color: _t.textSecondary),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, thickness: 1, color: _t.divider),
        ),
        _buildInlineRow('Resolution (pixels)',
            child: Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AppCompactCheckbox(
                        value: resolutionEnabled,
                        accentColor: _t.accent,
                        onChanged: (v) async {
                          if (v) {
                            await _preferencesService
                                .saveResolutionWarningThreshold(3000);
                            _resolutionController.text = '3000';
                          } else {
                            await _preferencesService
                                .saveResolutionWarningThreshold(0);
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
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          style: TextStyle(fontSize: 11, color: _t.text),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: _t.divider),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: _t.divider),
                            ),
                            hintText: 'e.g. 3000',
                            hintStyle: TextStyle(
                              fontSize: 11,
                              color: _t.textSecondary,
                            ),
                          ),
                          onSubmitted: (text) async {
                            if (!resolutionEnabled) return;
                            final v = int.tryParse(text);
                            if (v != null && v > 0) {
                              await _preferencesService
                                  .saveResolutionWarningThreshold(v);
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
                    style: TextStyle(fontSize: 11, color: _t.textSecondary),
                  ),
                ],
              ),
            )),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, thickness: 1, color: _t.divider),
        ),
        _buildInlineRow('Photoshop Path',
            child: Expanded(
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
                            style: TextStyle(fontSize: 11, color: _t.text),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: _t.divider),
                              ),
                              hintText: 'Path to Photoshop.app',
                              hintStyle: TextStyle(
                                fontSize: 11,
                                color: _t.textSecondary,
                              ),
                            ),
                            onSubmitted: (text) async {
                              await _preferencesService.savePhotoshopPath(
                                  text.isEmpty ? null : text);
                              await _loadCurrentPreferences();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedGreyButton(
                          label: 'Browse',
                          fontSize: 11,
                          onPressed: () async {
                            final path = await NativeFilePicker.pickFile(
                                allowedExtensions: ['app']);
                            if (path == null || path.isEmpty || !mounted)
                              return;
                            _photoshopPathController.text = path;
                            await _preferencesService.savePhotoshopPath(path);
                            await _loadCurrentPreferences();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Path to your Photoshop application.',
                    style: TextStyle(fontSize: 11, color: _t.textSecondary),
                  ),
                ],
              ),
            )),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, thickness: 1, color: _t.divider),
        ),
        _buildInlineRow(
          'MLB inning (EXIF timezone)',
          child: Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _mlbInningTzController,
                    style: TextStyle(fontSize: 11, color: _t.text),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: _t.divider),
                      ),
                      hintText: 'e.g. America/New_York',
                      hintStyle:
                          TextStyle(fontSize: 11, color: _t.textSecondary),
                    ),
                    onSubmitted: (text) async {
                      await _preferencesService.setMlbInningExifTimezone(text);
                      await _loadCurrentPreferences();
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Used only when the MLB inning-from-photo-time feature is on for '
                  'your account: EXIF time is read as local time in this zone, then '
                  'matched to MLB play-by-play (UTC). Examples: America/New_York, '
                  'America/Los_Angeles.',
                  style: TextStyle(fontSize: 11, color: _t.textSecondary),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, thickness: 1, color: _t.divider),
        ),
        _buildInlineRow(
          'Caption fields',
          child: Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  'Show or hide optional Personality and Keywords beside the main caption. '
                  'They stack in a column to the right; Keywords is the field after Personality.',
                  style: TextStyle(fontSize: 11, color: _t.textSecondary),
                ),
                const SizedBox(height: 10),
                ElevatedGreyButton(
                  label: 'Caption Layout',
                  fontSize: 11,
                  icon: Icons.view_agenda_outlined,
                  onPressed: () async {
                    await CaptionLayoutBuilderDialog.show(context);
                    if (!mounted) return;
                    await _loadCurrentPreferences();
                  },
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, thickness: 1, color: _t.divider),
        ),
        _buildInlineRow('Sport Default',
            child: Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 220,
                    child: DropdownFlutter<String>(
                      hintText: 'Select sport',
                      items: const [
                        'None',
                        'Baseball',
                        'Hockey',
                        'Basketball',
                        'WNBA',
                        'Soccer'
                      ],
                      initialItem: _sportForDefault.isEmpty
                          ? 'None'
                          : (_sportForDefault == 'wnba'
                              ? 'WNBA'
                              : _sportForDefault[0].toUpperCase() +
                                  _sportForDefault.substring(1)),
                      closedHeaderPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      expandedHeaderPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      listItemPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: CustomDropdownDecoration(
                        closedFillColor: _t.sunken,
                        expandedFillColor: _t.surface,
                        closedBorder: Border.all(color: _t.divider),
                        expandedBorder: Border.all(color: _t.divider),
                        closedBorderRadius: BorderRadius.circular(6),
                        expandedBorderRadius: BorderRadius.circular(8),
                        closedShadow: [
                          BoxShadow(
                            color: _t.bg.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                        expandedShadow: [
                          BoxShadow(
                            color: _t.bg.withValues(alpha: 0.55),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        hintStyle:
                            TextStyle(fontSize: 11, color: _t.textSecondary),
                        headerStyle: TextStyle(fontSize: 11, color: _t.text),
                        listItemStyle: TextStyle(fontSize: 11, color: _t.text),
                        listItemDecoration: ListItemDecoration(
                          selectedColor: _t.selectedFill,
                        ),
                      ),
                      onChanged: (label) async {
                        if (label == null) return;
                        final map = {
                          'None': '',
                          'Baseball': 'baseball',
                          'Hockey': 'hockey',
                          'Basketball': 'basketball',
                          'WNBA': 'wnba',
                          'Soccer': 'soccer',
                        };
                        final v = map[label] ?? '';
                        setState(() => _sportForDefault = v);
                        try {
                          if (v.isEmpty) {
                            await _preferencesService.saveCurrentSport('');
                          } else {
                            await _preferencesService
                                .setCurrentSportAsDefault(v);
                          }
                          await _loadCurrentPreferences();
                        } catch (_) {}
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select which sport is defaulted when you open the app.',
                    style: TextStyle(fontSize: 11, color: _t.textSecondary),
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
        AppCompactCheckbox(
          value: isOn,
          accentColor: _t.accent,
          onChanged: (v) => onChanged(v),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(!isOn),
            child: Text(
              label,
              style: TextStyle(fontSize: 11, color: _t.text),
            ),
          ),
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
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _t.text,
                ),
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
          (_currentPreferences?['categoryOrder'] as List?)?.join(', ') ??
              'Default',
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
        const SizedBox(height: 16),
        Text(
          'App originals',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _t.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Restore verb layouts and caption structures from the cloud catalog '
          'published by FloFile admins. Your FTP and caption library are not changed.',
          style: TextStyle(fontSize: 11, color: _t.textSecondary),
        ),
        if (AuthService.instance.isSignedIn) ...[
          const SizedBox(height: 8),
          Text(
            'While signed in, your personal settings (captions, verbs, FTP) '
            'sync to your account automatically.',
            style: TextStyle(fontSize: 11, color: _t.textSecondary),
          ),
        ],
        const SizedBox(height: 10),
        ElevatedGreyButton(
          label: _appDefaultsBusy ? 'Restoring…' : 'Restore app originals',
          fontSize: 11,
          icon: Icons.cloud_download_outlined,
          onPressed: _appDefaultsBusy ? null : _restoreAppOriginals,
        ),
        if (_isAdmin) ...[
          const SizedBox(height: 20),
          Text(
            'Admin — publish defaults',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _t.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Saves your current verb arrangement to Firebase for all users '
            '(used on restore and first sign-in).',
            style: TextStyle(fontSize: 11, color: _t.textSecondary),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 220,
            child: DropdownFlutter<String>(
              hintText: 'Sport',
              items: const [
                'Baseball',
                'Hockey',
                'Basketball',
                'WNBA',
                'Soccer'
              ],
              initialItem: _publishSport == 'wnba'
                  ? 'WNBA'
                  : _publishSport[0].toUpperCase() + _publishSport.substring(1),
              closedHeaderPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              expandedHeaderPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              listItemPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: CustomDropdownDecoration(
                closedFillColor: _t.sunken,
                expandedFillColor: _t.surface,
                closedBorder: Border.all(color: _t.divider),
                expandedBorder: Border.all(color: _t.divider),
                closedBorderRadius: BorderRadius.circular(6),
                expandedBorderRadius: BorderRadius.circular(8),
                hintStyle: TextStyle(fontSize: 11, color: _t.textSecondary),
                headerStyle: TextStyle(fontSize: 11, color: _t.text),
                listItemStyle: TextStyle(fontSize: 11, color: _t.text),
              ),
              onChanged: (label) {
                if (label == null) return;
                final map = {
                  'Baseball': 'baseball',
                  'Hockey': 'hockey',
                  'Basketball': 'basketball',
                  'WNBA': 'wnba',
                  'Soccer': 'soccer',
                };
                setState(() => _publishSport = map[label] ?? 'baseball');
              },
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedGreyButton(
                label: _appDefaultsBusy
                    ? 'Publishing…'
                    : 'Publish verb defaults (sport)',
                fontSize: 11,
                icon: Icons.cloud_upload_outlined,
                isAdmin: true,
                onPressed: _appDefaultsBusy
                    ? null
                    : () => _publishVerbsForSport(_publishSport),
              ),
              ElevatedGreyButton(
                label: _appDefaultsBusy ? 'Publishing…' : 'Publish all sports',
                fontSize: 11,
                icon: Icons.cloud_upload_outlined,
                isAdmin: true,
                onPressed: _appDefaultsBusy ? null : _publishAllVerbs,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _restoreAppOriginals() async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Restore app originals?',
      message:
          'This replaces your verb layouts and IPTC wire templates with the '
          'latest catalog from Firebase. Hidden IPTC templates will reappear.',
      cancelLabel: 'Cancel',
      confirmLabel: 'Restore',
    );
    if (ok != true || !mounted) return;
    setState(() => _appDefaultsBusy = true);
    try {
      await _preferencesService.restoreAppOriginals();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('App originals restored from Firebase.'),
          backgroundColor: Color(0xFF4A7A96),
        ),
      );
      await _loadCurrentPreferences();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _appDefaultsBusy = false);
    }
  }

  Future<void> _publishVerbsForSport(String sport) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Publish verb defaults?',
      message: 'This updates app originals for $sport for all signed-in users '
          '(on restore and new installs). Continue?',
      cancelLabel: 'Cancel',
      confirmLabel: 'Publish',
    );
    if (ok != true || !mounted) return;
    setState(() => _appDefaultsBusy = true);
    try {
      final bySport = await _preferencesService.exportVerbSettingsBySport();
      final data = bySport[sport];
      if (data == null) throw StateError('No verb data for $sport');
      await AppDefaultsFirestoreService.publishVerbsForSport(sport, data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Published verb defaults for $sport.'),
          backgroundColor: const Color(0xFF4A7A96),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Publish failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _appDefaultsBusy = false);
    }
  }

  Future<void> _publishAllVerbs() async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Publish all verb defaults?',
      message:
          'This updates app originals for every sport in Firebase. Continue?',
      cancelLabel: 'Cancel',
      confirmLabel: 'Publish all',
    );
    if (ok != true || !mounted) return;
    setState(() => _appDefaultsBusy = true);
    try {
      final bySport = await _preferencesService.exportVerbSettingsBySport();
      await AppDefaultsFirestoreService.publishAllVerbs(bySport);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Published verb defaults for all sports.'),
          backgroundColor: Color(0xFF4A7A96),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Publish failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _appDefaultsBusy = false);
    }
  }

  Widget _buildAccountSection() {
    final user = AuthService.instance.currentUser;
    final email = user?.email?.trim();
    final label = (email != null && email.isNotEmpty)
        ? email
        : (user?.uid ?? 'Signed in');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Account',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _t.text,
          ),
        ),
        const SizedBox(height: 10),
        _buildModernPreferenceItem(
          'Signed in as',
          label,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ElevatedGreyButton(
            label: 'Sign out',
            fontSize: 11,
            isDanger: true,
            onPressed: () async {
              await AuthService.instance.signOut();
              if (!context.mounted) return;
              Navigator.pop(context);
            },
          ),
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
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _t.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 11,
                    color: _t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.chevron_right,
              size: 14,
              color: _t.textSecondary,
            ),
        ],
      ),
    );

    final withDivider = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        Divider(height: 1, thickness: 1, color: _t.divider),
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
