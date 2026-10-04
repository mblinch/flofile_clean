import 'package:flutter/material.dart';

import '../services/ftpclient_service.dart';
import '../services/preferences_service.dart';
import '../theme/ff_tokens.dart';
import 'app_styled_dialogs.dart';

/// Standalone FTP Server Settings panel. Can be shown in a dialog or embedded
/// (e.g. in Preferences > FTP).
///
/// Credentials are edited inline — no nested create/edit popups.
class FtpSettingsPanel extends StatefulWidget {
  /// When true, panel is embedded (e.g. in Preferences); no Cancel/Save at bottom.
  final bool embedded;

  /// When in dialog mode, called when user taps Close or Save Settings.
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
  State<FtpSettingsPanel> createState() => _FtpSettingsPanelState();
}

class _FtpSettingsPanelState extends State<FtpSettingsPanel> {
  static const _newProfileValue = '__new_profile__';

  late PreferencesService _prefs;
  Map<String, Map<String, dynamic>> _profiles = {};
  String? _currentProfile;
  bool _creatingNew = false;
  bool _confirmDelete = false;
  bool _passiveMode = true;
  bool _testing = false;
  String? _statusMessage;
  bool _statusError = false;

  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _portController = TextEditingController(text: '21');
  final _remotePathController = TextEditingController();
  final _renameController = TextEditingController();
  final _duplicateFolderController = TextEditingController();

  String get _newProfileLabel {
    final typed = _nameController.text.trim();
    return typed.isEmpty ? 'New profile' : typed;
  }

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
    _loadProfiles();
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _hostController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    _remotePathController.dispose();
    _renameController.dispose();
    _duplicateFolderController.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (!_creatingNew || !mounted) return;
    setState(() {});
  }

  Future<void> _loadProfiles() async {
    _prefs = await PreferencesService.getInstance();
    final profiles = await _prefs.getFtpProfiles();
    final current = await _prefs.getCurrentFtpProfile();
    if (!mounted) return;
    setState(() {
      _profiles = Map.from(profiles);
      _currentProfile = current != null && profiles.containsKey(current)
          ? current
          : (profiles.isNotEmpty ? profiles.keys.first : null);
      _creatingNew = _currentProfile == null;
      _applyProfile(_currentProfile);
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
    _passiveMode = p?['passiveMode'] as bool? ?? true;
    _confirmDelete = false;
  }

  Future<void> _persist() async {
    await _prefs.saveFtpProfiles(_profiles);
    await _prefs.saveCurrentFtpProfile(_currentProfile);
    widget.onProfilesChanged?.call();
  }

  void _selectProfile(String name) {
    setState(() {
      _creatingNew = false;
      _currentProfile = name;
      _statusMessage = null;
      _applyProfile(name);
    });
    _persist();
  }

  void _startNewProfile() {
    setState(() {
      _creatingNew = true;
      _currentProfile = null;
      _statusMessage = null;
      _applyProfile(null);
      _nameController.clear();
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final host = _hostController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (name.isEmpty || host.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() {
        _statusError = true;
        _statusMessage =
            'Profile name, host, username, and password are required.';
      });
      return;
    }
    final data = {
      'host': host,
      'username': username,
      'password': password,
      'port': int.tryParse(_portController.text.trim()) ?? 21,
      'remotePath': _remotePathController.text.trim(),
      'passiveMode': _passiveMode,
    };
    final previous = _creatingNew ? null : _currentProfile;
    setState(() {
      final next = Map<String, Map<String, dynamic>>.from(_profiles);
      if (previous != null && previous != name) {
        next.remove(previous);
      }
      next[name] = data;
      _profiles = next;
      _currentProfile = name;
      _creatingNew = false;
      _statusError = false;
      _statusMessage = 'Saved “$name”.';
      _confirmDelete = false;
    });
    await _persist();
  }

  Future<void> _delete() async {
    final name = _currentProfile;
    if (name == null) return;
    if (!_confirmDelete) {
      setState(() => _confirmDelete = true);
      return;
    }
    setState(() {
      _profiles.remove(name);
      _currentProfile = _profiles.isEmpty ? null : _profiles.keys.first;
      _creatingNew = _currentProfile == null;
      _applyProfile(_currentProfile);
      _statusError = false;
      _statusMessage = 'Deleted “$name”.';
    });
    await _persist();
  }

  Future<void> _testConnection() async {
    final host = _hostController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (host.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() {
        _statusError = true;
        _statusMessage = 'Host, username, and password are required to test.';
      });
      return;
    }
    setState(() {
      _testing = true;
      _statusError = false;
      _statusMessage = 'Testing connection…';
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
    setState(() {
      _testing = false;
      _statusError = !result.success;
      _statusMessage = result.success
          ? (result.details ?? 'Connection OK.')
          : (result.details ?? result.error ?? 'Connection failed.');
    });
  }

  Widget _twoUp({
    required Widget left,
    required Widget right,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<FfTokens>() ?? FfTokens.dark;
    const gap = 8.0;
    return AppDialogFfStyle(
      enabled: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_upload_outlined,
                  size: 15, color: t.textSecondary),
              const SizedBox(width: 8),
              Text(
                'FTP',
                style: t.labelStyle.copyWith(fontSize: 13, color: t.text),
              ),
              if (_profiles.isNotEmpty || _creatingNew) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: _ProfileDropdown(
                        key: ValueKey(
                          _creatingNew
                              ? 'new:$_newProfileLabel'
                              : 'cur:$_currentProfile',
                        ),
                        tokens: t,
                        profiles: _profiles.keys.toList()..sort(),
                        value: _creatingNew
                            ? _newProfileValue
                            : _currentProfile,
                        newProfileValue: _newProfileValue,
                        newProfileLabel: _newProfileLabel,
                        showNewProfile: _creatingNew,
                        onChanged: (name) {
                          if (name == null) return;
                          if (name == _newProfileValue) {
                            _startNewProfile();
                            return;
                          }
                          _selectProfile(name);
                        },
                      ),
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              _GhostBtn(
                tokens: t,
                icon: Icons.add,
                label: 'New profile',
                onTap: _startNewProfile,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_statusMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (_statusError
                        ? const Color(0xFFD64545)
                        : const Color(0xFF6EC8C4))
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: (_statusError
                          ? const Color(0xFFD64545)
                          : const Color(0xFF6EC8C4))
                      .withValues(alpha: 0.34),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: t.metaStyle.copyWith(
                        color: _statusError
                            ? const Color(0xFFD64545)
                            : t.text,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _statusMessage = null),
                    child: Icon(Icons.close, size: 14, color: t.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          _twoUp(
            left: AppDialogLabeledTextField(
              label: 'Profile name',
              controller: _nameController,
              autofocus: _creatingNew,
              required: true,
              onChanged: (_) {
                if (_creatingNew) setState(() {});
              },
              bottomGap: gap,
            ),
            right: AppDialogLabeledTextField(
              label: 'Host',
              controller: _hostController,
              required: true,
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
          _twoUp(
            left: AppDialogLabeledTextField(
              label: 'Port',
              controller: _portController,
              keyboardType: TextInputType.number,
              bottomGap: gap,
            ),
            right: AppDialogLabeledTextField(
              label: 'Remote path',
              controller: _remotePathController,
              bottomGap: gap,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text('Passive mode', style: t.metaStyle),
                const SizedBox(width: 8),
                Transform.scale(
                  scale: 0.72,
                  alignment: Alignment.centerLeft,
                  child: Switch.adaptive(
                    value: _passiveMode,
                    activeColor: t.accent,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => setState(() => _passiveMode = v),
                  ),
                ),
                const Spacer(),
                _FillBtn(
                  tokens: t,
                  label: _testing ? 'Testing…' : 'Test',
                  onTap: _testing ? null : _testConnection,
                ),
                const SizedBox(width: 8),
                _FillBtn(
                  tokens: t,
                  label: _creatingNew ? 'Save profile' : 'Save',
                  emphasized: true,
                  onTap: _testing ? null : _save,
                ),
                if (!_creatingNew && _currentProfile != null) ...[
                  const SizedBox(width: 8),
                  _FillBtn(
                    tokens: t,
                    label: _confirmDelete ? 'Confirm delete' : 'Delete',
                    danger: true,
                    onTap: _testing ? null : _delete,
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: t.divider),
          const SizedBox(height: 10),
          Text(
            'Upload options',
            style: t.metaStyle.copyWith(
              fontWeight: FontWeight.w600,
              color: t.text.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 8),
          _twoUp(
            left: AppDialogLabeledTextField(
              label: 'Rename uploaded file as',
              controller: _renameController,
              bottomGap: 0,
            ),
            right: AppDialogLabeledTextField(
              label: 'Duplicate folder',
              controller: _duplicateFolderController,
              bottomGap: 0,
            ),
          ),
          if (!widget.embedded) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: _GhostBtn(
                tokens: t,
                label: 'Close',
                onTap: () => widget.onClose?.call(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileDropdown extends StatelessWidget {
  const _ProfileDropdown({
    super.key,
    required this.tokens,
    required this.profiles,
    required this.value,
    required this.onChanged,
    required this.newProfileValue,
    required this.newProfileLabel,
    required this.showNewProfile,
  });

  final FfTokens tokens;
  final List<String> profiles;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String newProfileValue;
  final String newProfileLabel;
  final bool showNewProfile;

  @override
  Widget build(BuildContext context) {
    final validSaved = value != null && profiles.contains(value);
    final effectiveValue = showNewProfile && value == newProfileValue
        ? newProfileValue
        : (validSaved ? value : null);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: tokens.sunken,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tokens.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: effectiveValue,
          isExpanded: true,
          isDense: true,
          dropdownColor: tokens.surface,
          iconEnabledColor: tokens.textSecondary,
          hint: Text(
            'Select profile',
            style: tokens.metaStyle.copyWith(
              fontSize: 11,
              color: tokens.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          style: tokens.metaStyle.copyWith(
            fontSize: 11,
            color: tokens.text,
            fontWeight: FontWeight.w500,
          ),
          selectedItemBuilder: (context) {
            final labels = <String>[
              if (showNewProfile) newProfileLabel,
              ...profiles,
            ];
            return [
              for (final label in labels)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.metaStyle.copyWith(
                      fontSize: 11,
                      color: tokens.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ];
          },
          items: [
            if (showNewProfile)
              DropdownMenuItem<String>(
                value: newProfileValue,
                child: Text(
                  newProfileLabel,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.metaStyle.copyWith(
                    fontSize: 11,
                    color: tokens.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            for (final name in profiles)
              DropdownMenuItem<String>(
                value: name,
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.metaStyle.copyWith(
                    fontSize: 11,
                    color: name == effectiveValue ? tokens.accent : tokens.text,
                    fontWeight: name == effectiveValue
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _GhostBtn extends StatelessWidget {
  const _GhostBtn({
    required this.tokens,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final FfTokens tokens;
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tokens.sunken,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: tokens.textSecondary),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: FfTokens.labelFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: tokens.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FillBtn extends StatelessWidget {
  const _FillBtn({
    required this.tokens,
    required this.label,
    required this.onTap,
    this.emphasized = false,
    this.danger = false,
  });

  final FfTokens tokens;
  final String label;
  final VoidCallback? onTap;
  final bool emphasized;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fill = !enabled
        ? tokens.sunken
        : danger
            ? tokens.accent.withValues(alpha: 0.16)
            : emphasized
                ? tokens.accent.withValues(alpha: 0.22)
                : tokens.selectedFill;
    final border = !enabled
        ? tokens.divider
        : (danger || emphasized ? tokens.accent : tokens.divider);
    final textColor = !enabled
        ? tokens.text.withValues(alpha: 0.38)
        : (danger || emphasized ? tokens.accent : tokens.text);
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: FfTokens.labelFamily,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
