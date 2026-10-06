import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_flutter/custom_dropdown.dart';

import '../services/auth_service.dart';
import '../services/camera_serial_service.dart';
import '../services/preferences_service.dart';
import '../theme/ff_tokens.dart';
import '../utils/native_file_picker.dart';
import 'camera_serial_dialog.dart';
import 'app_styled_dialogs.dart';
import 'caption_layout_builder_dialog.dart';
import 'ftp_settings_panel.dart';
import 'personal_verb_editor.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

class PreferencesDialog extends StatefulWidget {
  /// When set, called to open the FTP Settings dialog (e.g. from right-click on FTP button). Shown as an option in the FTP section.
  final VoidCallback? onOpenFtpSettings;

  /// Open on the Verbs tab (e.g. right-click → Edit verb).
  final bool openVerbs;

  /// Verb to select when [openVerbs] is true.
  final String? initialVerbKey;

  /// When true with [openVerbs], start creating a new verb.
  final bool createVerbOnOpen;

  /// Fired after personal verb catalog saves (e.g. reload live caption session).
  final Future<void> Function(String sport)? onVerbCatalogChanged;

  const PreferencesDialog({
    super.key,
    this.onOpenFtpSettings,
    this.openVerbs = false,
    this.initialVerbKey,
    this.createVerbOnOpen = false,
    this.onVerbCatalogChanged,
  });

  @override
  State<PreferencesDialog> createState() => _PreferencesDialogState();
}

enum _PrefsCategory {
  application,
  ftp,
  verbs,
}

class _PreferencesDialogState extends State<PreferencesDialog> {
  late PreferencesService _preferencesService;
  final TextEditingController _photoshopPathController =
      TextEditingController();
  final TextEditingController _resolutionController = TextEditingController();
  final TextEditingController _mlbInningTzController = TextEditingController();
  String _sportForDefault = 'baseball';
  Map<String, dynamic>? _currentPreferences;
  bool _isLoading = true;
  bool _appDefaultsBusy = false;
  late _PrefsCategory _selectedCategory;

  FfTokens get _t => Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;

  @override
  void initState() {
    super.initState();
    _selectedCategory =
        widget.openVerbs ? _PrefsCategory.verbs : _PrefsCategory.application;
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

    setState(() {
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

  InputDecoration _fieldDecoration({String? hintText}) {
    final radius = BorderRadius.circular(6);
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: _t.sunken,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      hintText: hintText,
      hintStyle: TextStyle(fontSize: 11, color: _t.textTertiary),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: _t.accent.withValues(alpha: 0.55)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: _t.accent.withValues(alpha: 0.55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: _t.accent, width: 1.2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: _t.divider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const sidebarWidth = 180.0;
    const contentPadding = 28.0;
    final size = MediaQuery.sizeOf(context);
    final width = math.min(1200.0, size.width * 0.94);
    final height = math.min(720.0, size.height * 0.90);

    return AppDialogFfStyle(
      enabled: true,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: _t.surface,
            borderRadius: BorderRadius.circular(FfTokens.radiusWindow),
            border: Border.all(color: _t.accent.withValues(alpha: 0.85)),
            boxShadow: [
              ...FfTokens.accentButtonGlow(_t.accent),
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
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.lerp(_t.accent, _t.surface, 0.82)!,
                        _t.surface,
                      ],
                    ),
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
                            child: PhosphorIcon(
                              PhosphorIconsRegular.x,
                              size: 20,
                              color: _t.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _t.accent,
                          ),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: sidebarWidth,
                              decoration: BoxDecoration(
                                color: _t.sunken,
                                border: Border(
                                  right: BorderSide(color: _t.divider),
                                ),
                              ),
                              child: ListView(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                children: [
                                  _buildSidebarTile(
                                    _PrefsCategory.application,
                                    'Application',
                                  ),
                                  Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: _t.divider),
                                  _buildSidebarTile(
                                    _PrefsCategory.ftp,
                                    'FTP',
                                  ),
                                  Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: _t.divider),
                                  _buildSidebarTile(
                                    _PrefsCategory.verbs,
                                    'Verbs',
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color.lerp(_t.accent, _t.bg, 0.88)!,
                                      _t.bg,
                                    ],
                                  ),
                                ),
                                child: _selectedCategory ==
                                        _PrefsCategory.verbs
                                    ? Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          12,
                                          16,
                                          12,
                                        ),
                                        child: _buildVerbsContent(),
                                      )
                                    : SingleChildScrollView(
                                        padding: const EdgeInsets.all(
                                            contentPadding),
                                        child: _buildCategoryContent(),
                                      ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
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
      case _PrefsCategory.verbs:
        return const SizedBox.shrink();
    }
  }

  Widget _buildApplicationContent() {
    final ftpMode = _currentPreferences?['ftpModeEnabled'] != false;
    final serialBylines = _currentPreferences?['serialNumberBylines'] == true;
    final burstOn = _currentPreferences?['burstDetectionEnabled'] == true;
    final jerseyOcr = _currentPreferences?['jerseyOcrEnabled'] == true;
    final showJerseyOcr = defaultTargetPlatform == TargetPlatform.macOS;
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
          'FTP Mode',
          child: Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _PrefsToggle(
                      value: ftpMode,
                      onChanged: (v) async {
                        await _preferencesService.saveFtpModeEnabled(v);
                        await _loadCurrentPreferences();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Show FTP buttons and shortcuts. Turn off for caption-only sessions.',
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
          'Serial Number Bylines',
          child: Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _PrefsToggle(
                      value: serialBylines,
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
                        final cameraService = CameraSerialService.instance;
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
                    _PrefsToggle(
                      value: burstOn,
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
        if (showJerseyOcr) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, thickness: 1, color: _t.divider),
          ),
          _buildInlineRow(
            'Jersey OCR',
            child: Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _PrefsToggle(
                        value: jerseyOcr,
                        onChanged: (v) async {
                          await _preferencesService.saveJerseyOcrEnabled(v);
                          await _loadCurrentPreferences();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scan jersey numbers and names on the current photo (macOS admin).',
                    style: TextStyle(fontSize: 11, color: _t.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
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
                      _PrefsToggle(
                        value: resolutionEnabled,
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
                          decoration: _fieldDecoration(hintText: 'e.g. 3000'),
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
                            decoration: _fieldDecoration(
                              hintText: 'Path to Photoshop.app',
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
                    decoration: _fieldDecoration(
                      hintText: 'e.g. America/New_York',
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
                  icon: PhosphorIconsRegular.rows,
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
                        closedBorder: Border.all(
                          color: _t.accent.withValues(alpha: 0.55),
                        ),
                        expandedBorder: Border.all(
                          color: _t.accent.withValues(alpha: 0.85),
                        ),
                        closedBorderRadius: BorderRadius.circular(6),
                        expandedBorderRadius: BorderRadius.circular(8),
                        closedShadow: FfTokens.accentButtonGlow(_t.accent),
                        expandedShadow: [
                          ...FfTokens.accentButtonGlow(_t.accent),
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
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, thickness: 1, color: _t.divider),
        ),
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
          icon: PhosphorIconsRegular.cloudArrowDown,
          onPressed: _appDefaultsBusy ? null : _restoreAppOriginals,
        ),
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
        const SizedBox(width: 8),
        _PrefsToggle(
          value: isOn,
          onChanged: onChanged,
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

  Widget _buildVerbsContent() {
    final sport =
        _sportForDefault.isEmpty ? 'baseball' : _sportForDefault;
    return PersonalVerbEditor(
      key: ValueKey(
        'prefs-verbs-$sport-${widget.initialVerbKey ?? ''}-'
        '${widget.createVerbOnOpen}',
      ),
      prefs: _preferencesService,
      initialSport: sport,
      initialVerbKey: widget.initialVerbKey,
      createOnOpen: widget.createVerbOnOpen,
      onCatalogChanged: widget.onVerbCatalogChanged,
    );
  }

  Future<void> _restoreAppOriginals() async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Restore app originals?',
      message:
          'This replaces your verb layouts, caption styles, and IPTC wire '
          'templates with the latest app defaults from Firebase. Your personal '
          'settings are not updated when defaults change unless you restore '
          'here. Hidden IPTC templates will reappear.',
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
            fontFamily: FfTokens.fontFamily,
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
        ),
      ],
    );
  }

  // Build a traditional list row (no box, no icon): label and value with optional tap
  Widget _buildModernPreferenceItem(
    String label,
    String value, {
    VoidCallback? onTap,
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
            PhosphorIcon(PhosphorIconsRegular.caretRight,
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

/// Compact on/off switch for Preferences → Application.
class _PrefsToggle extends StatelessWidget {
  const _PrefsToggle({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value ? 'On' : 'Off',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: value ? t.accent : t.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            height: 24,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.center,
              child: Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: t.accent,
                activeThumbColor: t.inkOnAccent,
                inactiveTrackColor: t.sunken,
                inactiveThumbColor: t.textSecondary,
                trackOutlineColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return t.accent;
                  }
                  return t.divider;
                }),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
