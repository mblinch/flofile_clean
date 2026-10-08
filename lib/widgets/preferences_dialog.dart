import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dropdown_flutter/custom_dropdown.dart';

import '../services/admin_service.dart';
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

  /// Fired as soon as the verb editor bundle changes.
  final void Function(String sport, Map<String, dynamic> bundle)?
      onVerbCatalogChanged;

  /// Fired after the latest verb bundle is on disk.
  final Future<void> Function(String sport)? onVerbCatalogPersisted;

  const PreferencesDialog({
    super.key,
    this.onOpenFtpSettings,
    this.openVerbs = false,
    this.initialVerbKey,
    this.createVerbOnOpen = false,
    this.onVerbCatalogChanged,
    this.onVerbCatalogPersisted,
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
  final _ftpPanelKey = GlobalKey<FtpSettingsPanelState>();
  final TextEditingController _photoshopPathController =
      TextEditingController();
  final TextEditingController _resolutionController = TextEditingController();
  final TextEditingController _mlbInningTzController = TextEditingController();
  String _sportForDefault = 'baseball';
  Map<String, dynamic>? _currentPreferences;
  bool _isLoading = true;
  bool _isAdmin = false;
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

  Future<void> _setApplicationPref(
    String key,
    bool value,
    Future<void> Function(bool value) save,
  ) async {
    setState(() {
      final next = Map<String, dynamic>.from(_currentPreferences ?? {});
      next[key] = value;
      _currentPreferences = next;
    });
    await save(value);
  }

  Future<void> _loadCurrentPreferences() async {
    setState(() {
      _isLoading = true;
    });

    _currentPreferences = await _preferencesService.exportAllPreferences();
    final isAdmin = await AdminService.isCurrentUserAdmin();

    setState(() {
      _isLoading = false;
      _isAdmin = isAdmin;
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
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final ftp = _ftpPanelKey.currentState;
          if (ftp != null && !await ftp.confirmLeave()) return;
          if (!context.mounted) return;
          Navigator.of(context).pop();
        },
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
                          onTap: () => Navigator.maybePop(context),
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
        onTap: () async {
          if (_selectedCategory == _PrefsCategory.ftp &&
              category != _PrefsCategory.ftp) {
            final ftp = _ftpPanelKey.currentState;
            if (ftp != null && !await ftp.confirmLeave()) return;
          }
          if (!mounted) return;
          setState(() => _selectedCategory = category);
        },
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
        Text(
          'Modes',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _t.text,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            _PrefsModeBuffButton(
              icon: PhosphorIconsRegular.cloudArrowUp,
              label: 'FTP mode',
              tooltip:
                  'Show FTP transmit buttons and shortcuts. Turn off for caption-only sessions.',
              enabled: ftpMode,
              onToggle: () => _setApplicationPref(
                'ftpModeEnabled',
                !ftpMode,
                _preferencesService.saveFtpModeEnabled,
              ),
            ),
            _PrefsModeBuffButton(
              icon: PhosphorIconsRegular.stack,
              label: 'Burst mode',
              tooltip:
                  'When saving, detect rapid bursts forward from the current photo and offer to apply the same caption to those frames.',
              enabled: burstOn,
              onToggle: () => _setApplicationPref(
                'burstDetectionEnabled',
                !burstOn,
                _preferencesService.saveBurstDetectionEnabled,
              ),
            ),
            if (showJerseyOcr)
              _PrefsModeBuffButton(
                icon: PhosphorIconsRegular.scan,
                label: 'Text Recognition',
                tooltip:
                    'Scan jersey numbers and names on the current photo (macOS).',
                enabled: jerseyOcr,
                onToggle: () => _setApplicationPref(
                  'jerseyOcrEnabled',
                  !jerseyOcr,
                  _preferencesService.saveJerseyOcrEnabled,
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _PrefsModeBuffButton(
                  icon: PhosphorIconsRegular.camera,
                  label: 'Serial number mode',
                  tooltip:
                      'Write photographer name and bylines according to camera serial numbers.',
                  enabled: serialBylines,
                  onToggle: () => _setApplicationPref(
                    'serialNumberBylines',
                    !serialBylines,
                    _preferencesService.saveSerialNumberBylines,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: _PrefsModeBuffButton.width,
                  child: ElevatedGreyButton(
                    label: 'Serial number list',
                    fontSize: 10,
                    fullWidth: true,
                    onPressed: () async {
                      final cameraService = CameraSerialService.instance;
                      await cameraService.initialize();
                      if (!context.mounted) return;
                      await showDialog<void>(
                        context: context,
                        builder: (context) => CameraSerialDialog(
                          cameraService: cameraService,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Divider(height: 1, thickness: 1, color: _t.divider),
        ),
        _buildInlineRow('Resolution warning',
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
                            final path =
                                await NativeFilePicker.pickApplication();
                            if (path == null || path.isEmpty || !mounted) {
                              return;
                            }
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
        if (_isAdmin) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, thickness: 1, color: _t.divider),
          ),
          _buildInlineRow(
            'MLB inning (EXIF timezone)',
            adminOnly: true,
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
        ],
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

  Widget _buildInlineRow(
    String label, {
    required Widget child,
    bool adminOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _t.text,
                    ),
                  ),
                  if (adminOnly) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: FfTokens.gold,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Admin only',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: FfTokens.inkOnGold,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ],
                ],
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
      onCatalogPersisted: widget.onVerbCatalogPersisted,
    );
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Signed in as',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _t.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: _t.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedGreyButton(
              label: 'Sign out',
              fontSize: 11,
              isDanger: true,
              onPressed: () async {
                await AuthService.instance.signOut();
                if (!context.mounted) return;
                Navigator.maybePop(context);
              },
            ),
          ],
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
          key: _ftpPanelKey,
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(!value),
          child: Text(
            value ? 'On' : 'Off',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: value ? t.accent : t.textSecondary,
            ),
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
              activeThumbColor: Colors.white,
              inactiveTrackColor: t.sunken,
              inactiveThumbColor: Colors.white,
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
    );
  }
}

/// Mode buff toggle used in Preferences → Application.
class _PrefsModeBuffButton extends StatelessWidget {
  const _PrefsModeBuffButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.enabled,
    required this.onToggle,
  });

  static const double width = 132;

  final IconData icon;
  final String label;
  /// Shown under the button (also used as hover tooltip).
  final String tooltip;
  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    final on = enabled;
    final color = on ? t.accent : t.textSecondary;
    final fill = on ? t.accent.withValues(alpha: 0.18) : t.elevated;
    final border = on ? t.accent.withValues(alpha: 0.85) : t.divider;
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Tooltip(
            message: tooltip,
            waitDuration: const Duration(milliseconds: 350),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: border),
                    boxShadow: on
                        ? [
                            BoxShadow(
                              color: t.accent.withValues(alpha: 0.28),
                              blurRadius: 10,
                              spreadRadius: 0,
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PhosphorIcon(icon, size: 18, color: color),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: FfTokens.fontFamily,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tooltip,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 9.5,
              height: 1.3,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
