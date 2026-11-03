import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

import '../services/camera_serial_service.dart';
import '../services/ftp_rename_template.dart';
import '../services/ftpclient_service.dart';
import '../services/number_sequence_service.dart';
import '../services/preferences_service.dart';
import '../theme/ff_tokens.dart';
import '../utils/native_file_picker.dart';
import 'app_styled_dialogs.dart';
import 'camera_serial_dialog.dart';
import 'number_sequence_dialog.dart';

/// Standalone FTP Server Settings panel. Can be shown in a dialog or embedded
/// (e.g. in Preferences > FTP).
///
/// Layout matches Downloads/FTP Profiles.html: left profile list, connection
/// fields, rename variables + sequence preview, footer status/actions.
class FtpSettingsPanel extends StatefulWidget {
  /// When true, panel is embedded (e.g. in Preferences); no Cancel/X at bottom.
  final bool embedded;

  /// When in dialog mode, called when user taps Close or Cancel.
  final VoidCallback? onClose;

  /// Called whenever profiles or current profile are saved (so parent can refresh).
  final VoidCallback? onProfilesChanged;

  const FtpSettingsPanel({
    super.key,
    this.embedded = false,
    this.onClose,
    this.onProfilesChanged,
  });

  @override
  State<FtpSettingsPanel> createState() => FtpSettingsPanelState();
}

class FtpSettingsPanelState extends State<FtpSettingsPanel> {
  late PreferencesService _prefs;
  Map<String, Map<String, dynamic>> _profiles = {};
  String? _currentProfile;
  bool _creatingNew = false;
  bool _passiveMode = true;
  bool _testing = false;
  String? _statusMessage;
  bool _statusError = false;
  bool _statusNeutral = true;

  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _portController = TextEditingController(text: '21');
  final _remotePathController = TextEditingController();
  final _renameController = TextEditingController();
  final _initialsController = TextEditingController();
  final _duplicateFolderController = TextEditingController();
  final _renameFocus = FocusNode();
  bool _serialBylines = false;
  String _dateFormat = FtpRenameDateFormats.defaultFormat;

  String get _newProfileLabel {
    final typed = _nameController.text.trim();
    return typed.isEmpty ? 'New profile' : typed;
  }

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
    _hostController.addListener(_onHostChanged);
    _renameController.addListener(_onRenameChanged);
    _initialsController.addListener(_onRenameChanged);
    _loadProfiles();
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _hostController.removeListener(_onHostChanged);
    _renameController.removeListener(_onRenameChanged);
    _initialsController.removeListener(_onRenameChanged);
    _nameController.dispose();
    _hostController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    _remotePathController.dispose();
    _renameController.dispose();
    _initialsController.dispose();
    _duplicateFolderController.dispose();
    _renameFocus.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onHostChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onRenameChanged() {
    if (!mounted) return;
    final from =
        FtpRenameDateFormats.formatInTemplate(_renameController.text);
    setState(() {
      if (from != null) _dateFormat = from;
    });
  }

  Future<void> _loadProfiles() async {
    _prefs = await PreferencesService.getInstance();
    final profiles = await _prefs.getFtpProfiles();
    final current = await _prefs.getCurrentFtpProfile();
    final serialOn = await _prefs.getSerialNumberBylines();
    final initials = await _prefs.getRenameInitials();
    await NumberSequenceService.instance.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _profiles = Map.from(profiles);
      _currentProfile = current != null && profiles.containsKey(current)
          ? current
          : (profiles.isNotEmpty ? profiles.keys.first : null);
      _creatingNew = _currentProfile == null;
      _serialBylines = serialOn;
      _initialsController.text = initials;
      _applyProfile(_currentProfile);
      _statusNeutral = true;
      _statusMessage = null;
    });
  }

  void _applyProfile(String? name) {
    final p = name == null ? null : _profiles[name];
    _nameController.text = name ?? '';
    _hostController.text = p?['host']?.toString() ?? '';
    _usernameController.text = p?['username']?.toString() ?? '';
    _passwordController.text = p?['password']?.toString() ?? '';
    _portController.text = (p?['port'] ?? 21).toString();
    _remotePathController.text = p?['remotePath']?.toString() ?? '';
    _renameController.text = p?['renameAs']?.toString() ?? '';
    _dateFormat = FtpRenameDateFormats.formatInTemplate(_renameController.text) ??
        FtpRenameDateFormats.defaultFormat;
    _duplicateFolderController.text = p?['duplicateFolder']?.toString() ?? '';
    _passiveMode = p?['passiveMode'] as bool? ?? true;
    _savedFields = _fieldSnapshot();
    final test = p?['lastTestOk'];
    if (test is bool) {
      _statusNeutral = false;
      _statusError = !test;
      _statusMessage = test ? 'Connected' : 'Didn’t connect';
    } else {
      _statusNeutral = true;
      _statusError = false;
      _statusMessage = null;
    }
  }

  Map<String, String> _savedFields = {
    'name': '',
    'host': '',
    'username': '',
    'password': '',
    'port': '21',
    'remotePath': '',
    'passive': '1',
    'rename': '',
    'duplicate': '',
  };

  Map<String, String> _fieldSnapshot() => {
        'name': _nameController.text.trim(),
        'host': _hostController.text.trim(),
        'username': _usernameController.text.trim(),
        'password': _passwordController.text,
        'port': _portController.text.trim(),
        'remotePath': _remotePathController.text.trim(),
        'passive': _passiveMode ? '1' : '0',
        'rename': _renameController.text.trim(),
        'duplicate': _duplicateFolderController.text.trim(),
      };

  bool get hasUnsavedChanges {
    final now = _fieldSnapshot();
    for (final entry in now.entries) {
      if (_savedFields[entry.key] != entry.value) return true;
    }
    return false;
  }

  Future<bool> save() => _save();

  Future<void> _persist() async {
    await _prefs.saveFtpProfiles(_profiles);
    await _prefs.saveCurrentFtpProfile(_currentProfile);
    widget.onProfilesChanged?.call();
  }

  /// Returns true when the caller may leave this form.
  Future<bool> confirmLeave() async {
    if (!hasUnsavedChanges) return true;
    final choice = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) {
        return Dialog(
          backgroundColor: FfTokens.sessionPanel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: FfTokens.sessionLn),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Save FTP changes?',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: FfTokens.sessionTx,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This profile has changes that aren’t saved yet.',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 13,
                      height: 1.35,
                      color: FfTokens.sessionT2,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _SessionBtn(
                        label: 'Don’t save',
                        onTap: () => Navigator.pop(ctx, false),
                      ),
                      const SizedBox(width: 8),
                      _SessionBtn(
                        label: 'Save',
                        primary: true,
                        onTap: () => Navigator.pop(ctx, true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!mounted || choice == null) return false;
    if (choice == false) return true;
    return save();
  }

  Future<void> _selectProfile(String name) async {
    if (!_creatingNew && name == _currentProfile) return;
    if (!await confirmLeave()) return;
    if (!mounted) return;
    setState(() {
      _creatingNew = false;
      _currentProfile = name;
      _applyProfile(name);
    });
    _persist();
  }

  Future<void> _startNewProfile() async {
    if (!await confirmLeave()) return;
    if (!mounted) return;
    setState(() {
      _creatingNew = true;
      _currentProfile = null;
      _applyProfile(null);
      _nameController.clear();
      _statusNeutral = true;
      _statusMessage = null;
    });
  }

  Future<void> _duplicateProfile() async {
    if (_creatingNew) return;
    final name = _currentProfile;
    if (name == null) return;
    if (!await confirmLeave()) return;
    if (!mounted) return;
    final base = _profiles[name];
    if (base == null) return;
    var copyName = '$name copy';
    var i = 2;
    while (_profiles.containsKey(copyName)) {
      copyName = '$name copy $i';
      i++;
    }
    setState(() {
      _profiles = {
        ..._profiles,
        copyName: Map<String, dynamic>.from(base)..remove('lastTestOk'),
      };
      _creatingNew = false;
      _currentProfile = copyName;
      _applyProfile(copyName);
      _statusNeutral = true;
      _statusMessage = null;
    });
    await _persist();
  }

  Future<bool> _save() async {
    final name = _nameController.text.trim();
    final host = _hostController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (name.isEmpty || host.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() {
        _statusNeutral = false;
        _statusError = true;
        _statusMessage =
            'Profile name, host, username, and password are required.';
      });
      return false;
    }
    final previous = _creatingNew ? null : _currentProfile;
    final existing = previous != null ? _profiles[previous] : null;
    final data = <String, dynamic>{
      'host': host,
      'username': username,
      'password': password,
      'port': int.tryParse(_portController.text.trim()) ?? 21,
      'remotePath': _remotePathController.text.trim(),
      'passiveMode': _passiveMode,
      'renameAs': FtpRenameTemplate.ensureSequenceToken(
        _renameController.text,
      ),
      'duplicateFolder': _duplicateFolderController.text.trim(),
      if (existing?['lastTestOk'] is bool) 'lastTestOk': existing!['lastTestOk'],
    };
    await _prefs.saveRenameInitials(_initialsController.text);
    setState(() {
      _renameController.text = data['renameAs'] as String;
      final next = Map<String, Map<String, dynamic>>.from(_profiles);
      if (previous != null && previous != name) {
        next.remove(previous);
      }
      next[name] = data;
      _profiles = next;
      _currentProfile = name;
      _creatingNew = false;
      _statusNeutral = false;
      _statusError = false;
      _statusMessage = 'Saved “$name".';
    });
    await _persist();
    _savedFields = _fieldSnapshot();
    return true;
  }

  Future<void> _delete() async {
    final name = _currentProfile;
    if (name == null) return;
    if (_profiles.length < 2 && !_creatingNew) {
      // Allow deleting the last profile — leave empty / new state.
    }
    final ok = await showAppConfirmDialog(
      context: context,
      title: 'Delete profile?',
      message: 'Are you sure you want to delete “$name”?',
      cancelLabel: 'Cancel',
      confirmLabel: 'Delete',
    );
    if (ok != true || !mounted) return;
    setState(() {
      _profiles.remove(name);
      _currentProfile = _profiles.isEmpty ? null : _profiles.keys.first;
      _creatingNew = _currentProfile == null;
      _applyProfile(_currentProfile);
      _statusNeutral = false;
      _statusError = false;
      _statusMessage = 'Deleted “$name”.';
    });
    await _persist();
  }

  Future<void> _browseDuplicateFolder() async {
    final current = _duplicateFolderController.text.trim();
    final picked = await NativeFilePicker.pickDirectory(
      initialDirectory: current.isEmpty ? null : current,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _duplicateFolderController.text = picked);
  }

  Future<void> _testConnection() async {
    final host = _hostController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (host.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() {
        _statusNeutral = false;
        _statusError = true;
        _statusMessage = 'Host, username, and password are required to test.';
      });
      return;
    }
    setState(() {
      _testing = true;
      _statusNeutral = false;
      _statusError = false;
      _statusMessage = 'Connecting…';
    });
    final result = await FtpClientService.testConnection(
      host: host,
      username: username,
      password: password,
      port: int.tryParse(_portController.text.trim()) ?? 21,
      remotePath: _remotePathController.text.trim(),
      passiveMode: _passiveMode,
    );
    if (!mounted) return;
    final name = _creatingNew ? null : _currentProfile;
    setState(() {
      _testing = false;
      _statusNeutral = false;
      _statusError = !result.success;
      _statusMessage = result.success ? 'Connected' : 'Didn’t connect';
      if (name != null && _profiles.containsKey(name)) {
        _profiles = {
          ..._profiles,
          name: {
            ..._profiles[name]!,
            'lastTestOk': result.success,
          },
        };
      }
    });
    if (name != null) await _persist();
  }

  bool get _renameHasSequence =>
      FtpRenameTemplate.hasSequenceToken(_renameController.text);

  Future<void> _configureRenameSequence() async {
    final saved = await NumberSequenceDialog.show(context);
    if (!mounted) return;
    if (saved != true) return;
    if (!_renameHasSequence) {
      _insertRenameToken(FtpRenameTokens.n);
    }
    setState(() {});
  }

  Future<void> _openCameraSerials() async {
    final camera = CameraSerialService.instance;
    await camera.initialize();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) => CameraSerialDialog(cameraService: camera),
    );
    if (!mounted) return;
    setState(() {});
  }

  void _insertRenameToken(String token) {
    final brace = token == FtpRenameTokens.date
        ? FtpRenameDateFormats.brace(_dateFormat)
        : FtpRenameTokens.brace(token);
    // Always append — a selected range would replace the whole pattern.
    final next = '${_renameController.text}$brace';
    _renameController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _renameFocus.requestFocus();
  }

  void _cycleDateFormat() {
    final next = FtpRenameDateFormats.next(_dateFormat);
    final text = _renameController.text;
    setState(() {
      _dateFormat = next;
      if (FtpRenameDateFormats.hasDateToken(text)) {
        final updated = FtpRenameDateFormats.applyFormat(text, next);
        _renameController.value = TextEditingValue(
          text: updated,
          selection: TextSelection.collapsed(offset: updated.length),
        );
      }
    });
  }

  String get _renamePreview {
    final seq = NumberSequenceService.instance;
    return FtpRenameTemplate.preview(
      _renameController.text,
      awayTeam: 'LAK',
      homeTeam: 'TOR',
      photographer: 'Mark Blinch',
      initials: _initialsController.text,
      sequence: seq.nextOrDefault,
      sequenceWidth: seq.digitsOrDefault,
    );
  }

  String? _profileStatus(String name) {
    final ok = _profiles[name]?['lastTestOk'];
    if (ok is bool) return ok ? 'ok' : 'bad';
    return null;
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: FfTokens.fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.88,
        color: FfTokens.sessionT3,
      ),
    );
  }

  Widget _fieldLabel(String text, {String? opt, bool required = false}) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: FfTokens.sessionT2,
          ),
        ),
        if (required) ...[
          const SizedBox(width: 6),
          Container(
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: FfTokens.sessionT3,
              shape: BoxShape.circle,
            ),
          ),
        ],
        if (opt != null) ...[
          const Spacer(),
          Text(
            opt,
            style: const TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: FfTokens.sessionT3,
            ),
          ),
        ],
      ],
    );
  }

  Widget _twoUp({required Widget left, required Widget right, double rightWidth = 0}) {
    if (rightWidth > 0) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 10),
          SizedBox(width: rightWidth, child: right),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );
  }

  Widget _buildSidebar() {
    final names = _profiles.keys.toList();
    return Container(
      width: 220,
      color: FfTokens.sessionBg,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: _sectionLabel('Profiles'),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (_creatingNew)
                  _ProfileRow(
                    name: _newProfileLabel,
                    selected: true,
                    status: null,
                    isDefault: false,
                    onTap: () {},
                  ),
                for (final name in names)
                  _ProfileRow(
                    name: name,
                    selected: !_creatingNew && name == _currentProfile,
                    status: _profileStatus(name),
                    isDefault: !_creatingNew &&
                        name == _currentProfile &&
                        names.length == 1,
                    onTap: () => _selectProfile(name),
                  ),
                const SizedBox(height: 4),
                _AddProfileButton(onTap: _startNewProfile),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    const gap = 10.0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  autofocus: _creatingNew,
                  style: const TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: FfTokens.sessionTx,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (!_creatingNew && _currentProfile != null) ...[
                _IconTextBtn(
                  icon: PhosphorIconsRegular.copy,
                  label: 'Duplicate',
                  onTap: _duplicateProfile,
                ),
                _IconTextBtn(
                  icon: PhosphorIconsRegular.trash,
                  label: 'Delete',
                  danger: true,
                  onTap: _testing ? null : _delete,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          AppDialogFfStyle(
            enabled: true,
            child: Column(
              children: [
                _twoUp(
                  rightWidth: 92,
                  left: AppDialogLabeledTextField(
                    label: 'Host',
                    controller: _hostController,
                    required: true,
                    bottomGap: gap,
                  ),
                  right: AppDialogLabeledTextField(
                    label: 'Port',
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    bottomGap: gap,
                  ),
                ),
                _twoUp(
                  left: AppDialogLabeledTextField(
                    label: 'Username',
                    controller: _usernameController,
                    required: true,
                    bottomGap: gap,
                  ),
                  right: AppDialogLabeledTextField(
                    label: 'Password',
                    controller: _passwordController,
                    obscureText: true,
                    required: true,
                    bottomGap: gap,
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: AppDialogLabeledTextField(
                        label: 'Remote path',
                        controller: _remotePathController,
                        bottomGap: 0,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: kAppDialogControlHeight,
                        child: _PassiveToggle(
                          value: _passiveMode,
                          onChanged: (v) => setState(() => _passiveMode = v),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: FfTokens.sessionLn),
          const SizedBox(height: 16),
          _sectionLabel('Upload options'),
          const SizedBox(height: 10),
          _fieldLabel('Copy file to', opt: 'Optional'),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: AppDialogFfStyle(
                  enabled: true,
                  child: AppDialogControlShell(
                    child: TextField(
                      controller: _duplicateFolderController,
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 12.5,
                        color: FfTokens.sessionTx,
                      ),
                      decoration: appDialogBareFieldDecoration().copyWith(
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: PhosphorIcon(
                            PhosphorIconsRegular.folderSimple,
                            size: 15,
                            color: FfTokens.sessionT3,
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SessionBtn(
                label: 'Browse…',
                onTap: _browseDuplicateFolder,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _fieldLabel(
            'Rename uploaded file',
            opt: 'Initials + sequence required',
          ),
          const SizedBox(height: 5),
          _RenameSequenceRow(
            preview: FtpRenameTemplate.formatSequence(
              NumberSequenceService.instance.nextOrDefault,
              width: NumberSequenceService.instance.digitsOrDefault,
            ),
            included: _renameHasSequence,
            onConfigure: () => unawaited(_configureRenameSequence()),
            onAdd: _renameHasSequence
                ? null
                : () => _insertRenameToken(FtpRenameTokens.n),
          ),
          const SizedBox(height: 8),
          const Text(
            'Optional variables',
            style: TextStyle(
              fontFamily: FfTokens.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: FfTokens.sessionT2,
            ),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final token in FtpRenameTokens.chipTokens)
                if (token == FtpRenameTokens.date)
                  _DateFormatChip(
                    format: _dateFormat,
                    sample: FtpRenameDateFormats.formatDate(
                      DateTime.now(),
                      _dateFormat,
                    ),
                    onInsert: () => _insertRenameToken(FtpRenameTokens.date),
                    onCycle: _cycleDateFormat,
                  )
                else
                  _TokenChip(
                    label: FtpRenameTokens.brace(token),
                    onTap: () => _insertRenameToken(token),
                  ),
            ],
          ),
          const SizedBox(height: 10),
          _RenameInitialsConfig(
            serialBylines: _serialBylines,
            controller: _initialsController,
            onOpenCameraSerials: () => unawaited(_openCameraSerials()),
          ),
          const SizedBox(height: 6),
          AppDialogFfStyle(
            enabled: true,
            child: AppDialogControlShell(
              child: TextField(
                controller: _renameController,
                focusNode: _renameFocus,
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 12.5,
                  color: FfTokens.sessionTx,
                ),
                decoration: appDialogBareFieldDecoration(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _renamePreview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: FfTokens.sessionT3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final Color statusColor;
    final IconData statusIcon;
    final String statusText;
    if (_testing) {
      statusColor = FfTokens.sessionT3;
      statusIcon = PhosphorIconsRegular.circleNotch;
      statusText = 'Connecting…';
    } else if (_statusMessage != null && !_statusNeutral) {
      statusColor = _statusError ? FfTokens.danger : FfTokens.sessionOk;
      statusIcon = _statusError
          ? PhosphorIconsFill.warningCircle
          : PhosphorIconsFill.checkCircle;
      statusText = _statusMessage!;
    } else {
      statusColor = FfTokens.sessionT3;
      statusIcon = PhosphorIconsRegular.plugs;
      statusText = '';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 14, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: FfTokens.sessionLn)),
      ),
      child: Row(
        children: [
          Expanded(
            child: statusText.isEmpty
                ? const SizedBox.shrink()
                : Row(
                    children: [
                      PhosphorIcon(statusIcon, size: 15, color: statusColor),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: FfTokens.fontFamily,
                            fontSize: 12,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          _SessionBtn(
            icon: PhosphorIconsRegular.plugsConnected,
            label: _testing ? 'Testing…' : 'Test connection',
            onTap: _testing ? null : _testConnection,
          ),
          if (!widget.embedded) ...[
            const SizedBox(width: 8),
            _SessionBtn(
              label: 'Cancel',
              ghost: true,
              onTap: () async {
                if (!await confirmLeave()) return;
                widget.onClose?.call();
              },
            ),
          ],
          const SizedBox(width: 8),
          _SessionBtn(
            label: 'Save',
            primary: true,
            onTap: _testing ? null : () => _save(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 10, 0),
            child: Row(
              children: [
                const PhosphorIcon(
                  PhosphorIconsRegular.cloudArrowUp,
                  size: 18,
                  color: FfTokens.accentHover,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'FTP profiles',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: FfTokens.sessionTx,
                    ),
                  ),
                ),
                if (!widget.embedded)
                  _CloseIconButton(
                    onTap: () async {
                      if (!await confirmLeave()) return;
                      widget.onClose?.call();
                    },
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: FfTokens.sessionLn),
        // Body: sidebar + form
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSidebar(),
              const VerticalDivider(width: 1, color: FfTokens.sessionLn),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
        _buildFooter(),
      ],
    );
  }
}

class _ProfileRow extends StatefulWidget {
  const _ProfileRow({
    required this.name,
    required this.selected,
    required this.status,
    required this.isDefault,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final String? status;
  final bool isDefault;
  final VoidCallback onTap;

  @override
  State<_ProfileRow> createState() => _ProfileRowState();
}

class _ProfileRowState extends State<_ProfileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final bg = selected
        ? FfTokens.nocturneAccentRow
        : (_hover ? FfTokens.sessionHv : Colors.transparent);
    final Color dot;
    if (widget.status == 'ok') {
      dot = FfTokens.sessionOk;
    } else if (widget.status == 'bad') {
      dot = FfTokens.danger;
    } else {
      dot = FfTokens.sessionT3;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(9),
              border: selected
                  ? Border.all(color: FfTokens.nocturneAccentEdge)
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected || _hover
                          ? FfTokens.sessionTx
                          : FfTokens.sessionT2,
                    ),
                  ),
                ),
                if (widget.isDefault)
                  const Text(
                    'DEFAULT',
                    style: TextStyle(
                      fontFamily: FfTokens.fontFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: FfTokens.sessionWarn,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddProfileButton extends StatefulWidget {
  const _AddProfileButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AddProfileButton> createState() => _AddProfileButtonState();
}

class _AddProfileButtonState extends State<_AddProfileButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hover ? FfTokens.sessionHv : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              PhosphorIcon(
                PhosphorIconsRegular.plus,
                size: 15,
                color: _hover ? FfTokens.sessionTx : FfTokens.sessionT2,
              ),
              const SizedBox(width: 8),
              Text(
                'New profile',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _hover ? FfTokens.sessionTx : FfTokens.sessionT2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateFormatChip extends StatefulWidget {
  const _DateFormatChip({
    required this.format,
    required this.sample,
    required this.onInsert,
    required this.onCycle,
  });

  final String format;
  final String sample;
  final VoidCallback onInsert;
  final VoidCallback onCycle;

  @override
  State<_DateFormatChip> createState() => _DateFormatChipState();
}

class _DateFormatChipState extends State<_DateFormatChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 22,
        padding: const EdgeInsets.only(left: 7, right: 2),
        decoration: BoxDecoration(
          color: _hover ? FfTokens.sessionOnSoft : FfTokens.nocturneSf,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: FfTokens.sessionLn),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onInsert,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '{date}',
                      softWrap: false,
                      style: TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        height: 1,
                        color: _hover ? FfTokens.sessionTx : FfTokens.sessionT2,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      widget.sample,
                      softWrap: false,
                      style: const TextStyle(
                        fontFamily: 'JetBrains Mono',
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        height: 1,
                        color: FfTokens.sessionT3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 2),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onCycle,
                behavior: HitTestBehavior.opaque,
                child: Tooltip(
                  message: 'Date format · ${widget.format}',
                  waitDuration: const Duration(milliseconds: 400),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: PhosphorIcon(
                      PhosphorIconsRegular.arrowsClockwise,
                      size: 12,
                      color: _hover ? FfTokens.sessionTx : FfTokens.sessionT2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameInitialsConfig extends StatelessWidget {
  const _RenameInitialsConfig({
    required this.serialBylines,
    required this.controller,
    required this.onOpenCameraSerials,
  });

  final bool serialBylines;
  final TextEditingController controller;
  final VoidCallback onOpenCameraSerials;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Your initials',
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: FfTokens.sessionT2,
                ),
              ),
            ),
            if (serialBylines)
              _SessionBtn(
                label: 'Cameras',
                onTap: onOpenCameraSerials,
              ),
          ],
        ),
        const SizedBox(height: 5),
        AppDialogFfStyle(
          enabled: true,
          child: AppDialogControlShell(
            child: TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 12.5,
                color: FfTokens.sessionTx,
              ),
              decoration: appDialogBareFieldDecoration(),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Used for {initials}. Leave blank to use the first letter of every '
          'name in Creator.',
          style: TextStyle(
            fontFamily: FfTokens.fontFamily,
            fontSize: 11,
            height: 1.35,
            color: FfTokens.sessionT3,
          ),
        ),
      ],
    );
  }
}

class _RenameSequenceRow extends StatelessWidget {
  const _RenameSequenceRow({
    required this.preview,
    required this.included,
    required this.onConfigure,
    required this.onAdd,
  });

  final String preview;
  final bool included;
  final VoidCallback onConfigure;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: FfTokens.nocturneSf,
        borderRadius: BorderRadius.circular(FfTokens.radiusChip),
        border: Border.all(
          color: included
              ? FfTokens.sessionOn.withValues(alpha: 0.55)
              : FfTokens.sessionLn,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sequence  {n}',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: FfTokens.sessionTx,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  included
                      ? 'Required · next $preview'
                      : 'Required · add {n} to the pattern',
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 11,
                    color: included ? FfTokens.sessionT2 : FfTokens.danger,
                  ),
                ),
              ],
            ),
          ),
          if (!included && onAdd != null) ...[
            _SessionBtn(
              label: 'Add {n}',
              onTap: onAdd!,
            ),
            const SizedBox(width: 6),
          ],
          _SessionBtn(
            label: 'Digits',
            primary: included,
            onTap: onConfigure,
          ),
        ],
      ),
    );
  }
}

class _TokenChip extends StatefulWidget {
  const _TokenChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_TokenChip> createState() => _TokenChipState();
}

class _TokenChipState extends State<_TokenChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? FfTokens.sessionOnSoft : FfTokens.nocturneSf,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: FfTokens.sessionLn),
          ),
          child: Text(
            widget.label,
            softWrap: false,
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1,
              color: _hover ? FfTokens.sessionTx : FfTokens.sessionT2,
            ),
          ),
        ),
      ),
    );
  }
}

class _PassiveToggle extends StatefulWidget {
  const _PassiveToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<_PassiveToggle> createState() => _PassiveToggleState();
}

class _PassiveToggleState extends State<_PassiveToggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = appDialogTokens(context) ?? FfTokens.dark;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => widget.onChanged(!widget.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: kAppDialogControlHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: _hover ? t.hover : t.sunken,
            borderRadius: BorderRadius.circular(FfTokens.radiusChip),
            border: Border.all(color: t.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Passive mode',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                    color: t.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 34,
                height: 20,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: widget.value ? t.accent : t.hover,
                  borderRadius: BorderRadius.circular(10),
                  border: widget.value
                      ? null
                      : Border.all(color: t.divider),
                ),
                alignment:
                    widget.value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.value ? Colors.white : t.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconTextBtn extends StatefulWidget {
  const _IconTextBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  State<_IconTextBtn> createState() => _IconTextBtnState();
}

class _IconTextBtnState extends State<_IconTextBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final Color fg;
    if (!enabled) {
      fg = FfTokens.sessionT3;
    } else if (widget.danger && _hover) {
      fg = FfTokens.danger;
    } else if (_hover) {
      fg = FfTokens.sessionTx;
    } else {
      fg = FfTokens.sessionT3;
    }

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: !enabled
                  ? Colors.transparent
                  : widget.danger && _hover
                      ? FfTokens.dangerBg
                      : _hover
                          ? FfTokens.sessionHv
                          : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PhosphorIcon(widget.icon, size: 14, color: fg),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontFamily: FfTokens.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseIconButton extends StatefulWidget {
  const _CloseIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_CloseIconButton> createState() => _CloseIconButtonState();
}

class _CloseIconButtonState extends State<_CloseIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Close',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? FfTokens.sessionHv : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: PhosphorIcon(
              PhosphorIconsRegular.x,
              size: 16,
              color: _hover ? FfTokens.sessionTx : FfTokens.sessionT3,
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionBtn extends StatefulWidget {
  const _SessionBtn({
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = false,
    this.danger = false,
    this.ghost = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool primary;
  final bool danger;
  final bool ghost;

  @override
  State<_SessionBtn> createState() => _SessionBtnState();
}

class _SessionBtnState extends State<_SessionBtn> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final primary = widget.primary && enabled;

    final Color? bg;
    final Color fg;
    final Color border;
    Gradient? gradient;
    List<BoxShadow>? glow;

    if (!enabled) {
      bg = FfTokens.sessionEl;
      fg = FfTokens.sessionT3;
      border = Colors.transparent;
    } else if (widget.danger) {
      bg = _hover ? FfTokens.dangerBg : Colors.transparent;
      fg = FfTokens.danger;
      border = FfTokens.dangerBorder;
    } else if (widget.primary) {
      bg = null;
      fg = Colors.white;
      border = _hover
          ? Colors.white.withValues(alpha: 0.92)
          : FfTokens.nocturneAc.withValues(alpha: 0.95);
      gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: _pressed
            ? const [
                Color(0xFF1A2A36),
                Color(0xFF0C141A),
                Color(0xFF080E12),
              ]
            : _hover
                ? const [
                    Color(0xFF2E4658),
                    Color(0xFF1A2E3A),
                    Color(0xFF121F28),
                  ]
                : const [
                    Color(0xFF243848),
                    Color(0xFF15242E),
                    Color(0xFF0E181F),
                  ],
        stops: const [0.0, 0.45, 1.0],
      );
      glow = FfTokens.accentButtonGlow(
        _hover ? Colors.white : FfTokens.nocturneAc,
      );
    } else if (widget.ghost) {
      bg = _hover ? FfTokens.sessionHv : Colors.transparent;
      fg = _hover ? FfTokens.sessionTx : FfTokens.sessionT2;
      border = Colors.transparent;
    } else {
      bg = _hover ? FfTokens.sessionHv : FfTokens.sessionEl;
      fg = FfTokens.sessionTx;
      border = Colors.transparent;
    }

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 36,
          padding: EdgeInsets.symmetric(horizontal: primary ? 20 : 14),
          decoration: BoxDecoration(
            color: bg,
            gradient: gradient,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: border),
            boxShadow: glow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                PhosphorIcon(widget.icon!, size: 15, color: fg),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: FfTokens.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
