import 'package:flutter/material.dart';

import '../services/preferences_service.dart';

/// Standalone FTP Server Settings panel. Can be shown in a dialog or embedded (e.g. in Preferences > FTP).
/// Uses the same storage keys as the caption widget (ftp_profiles, current_ftp_profile).
class FtpSettingsPanel extends StatefulWidget {
  /// When true, panel is embedded (e.g. in Preferences); no Cancel/Save Settings buttons at bottom.
  final bool embedded;
  /// When in dialog mode, called when user taps Cancel or Save Settings.
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
  late PreferencesService _prefs;
  Map<String, Map<String, dynamic>> _profiles = {};
  String? _currentProfile;
  String _host = '';
  String _username = '';
  String _password = '';
  int _port = 21;
  String _remotePath = '';
  bool _passiveMode = true;
  bool _showProfileManager = false;
  String? _successMessage;

  final _hostController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _portController = TextEditingController();
  final _remotePathController = TextEditingController();
  final _renameController = TextEditingController();
  final _duplicateFolderController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    _prefs = await PreferencesService.getInstance();
    final profiles = await _prefs.getFtpProfiles();
    final current = await _prefs.getCurrentFtpProfile();
    if (!mounted) return;
    setState(() {
      _profiles = Map.from(profiles);
      _currentProfile = current;
      if (current != null && _profiles.containsKey(current)) {
        final p = _profiles[current]!;
        _host = p['host']?.toString() ?? '';
        _username = p['username']?.toString() ?? '';
        _password = p['password']?.toString() ?? '';
        _port = (p['port'] is int) ? p['port'] as int : int.tryParse(p['port']?.toString() ?? '21') ?? 21;
        _remotePath = p['remotePath']?.toString() ?? '';
        _passiveMode = p['passiveMode'] as bool? ?? true;
      }
      _hostController.text = _host;
      _usernameController.text = _username;
      _passwordController.text = _password;
      _portController.text = _port.toString();
      _remotePathController.text = _remotePath;
    });
  }

  Future<void> _saveProfiles() async {
    await _prefs.saveFtpProfiles(_profiles);
    await _prefs.saveCurrentFtpProfile(_currentProfile);
    widget.onProfilesChanged?.call();
  }

  void _loadProfile(String name) {
    final p = _profiles[name];
    if (p == null) return;
    setState(() {
      _currentProfile = name;
      _host = p['host']?.toString() ?? '';
      _username = p['username']?.toString() ?? '';
      _password = p['password']?.toString() ?? '';
      _port = (p['port'] is int) ? p['port'] as int : int.tryParse(p['port']?.toString() ?? '21') ?? 21;
      _remotePath = p['remotePath']?.toString() ?? '';
      _passiveMode = p['passiveMode'] as bool? ?? true;
      _hostController.text = _host;
      _usernameController.text = _username;
      _passwordController.text = _password;
      _portController.text = _port.toString();
      _remotePathController.text = _remotePath;
    });
    _saveProfiles();
  }

  void _saveCurrentAsProfile(String profileName) {
    final data = {
      'host': _hostController.text,
      'username': _usernameController.text,
      'password': _passwordController.text,
      'port': int.tryParse(_portController.text) ?? 21,
      'remotePath': _remotePathController.text,
      'passiveMode': _passiveMode,
    };
    setState(() {
      _profiles[profileName] = data;
      _currentProfile = profileName;
      _host = data['host'] as String;
      _username = data['username'] as String;
      _password = data['password'] as String;
      _port = data['port'] as int;
      _remotePath = data['remotePath'] as String;
    });
    _saveProfiles();
    setState(() => _successMessage = 'Profile "$profileName" saved.');
  }

  void _deleteProfile(String name) {
    setState(() {
      _profiles.remove(name);
      if (_currentProfile == name) {
        _currentProfile = null;
        _host = '';
        _username = '';
        _password = '';
        _port = 21;
        _remotePath = '';
        _hostController.clear();
        _usernameController.clear();
        _passwordController.clear();
        _portController.text = '21';
        _remotePathController.clear();
      }
    });
    _saveProfiles();
  }

  void _showCreateProfileDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create New FTP Profile'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Profile Name',
            hintText: 'e.g. Work Server',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                _saveCurrentAsProfile(name);
              }
            },
            child: const Text('Create Profile'),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog(String profileName) {
    final p = _profiles[profileName];
    if (p == null) return;
    final hostController = TextEditingController(text: p['host']?.toString() ?? '');
    final usernameController = TextEditingController(text: p['username']?.toString() ?? '');
    final passwordController = TextEditingController(text: p['password']?.toString() ?? '');
    final portController = TextEditingController(text: (p['port'] ?? 21).toString());
    final remotePathController = TextEditingController(text: p['remotePath']?.toString() ?? '');
    bool passiveMode = p['passiveMode'] as bool? ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Edit Profile: $profileName', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
                const SizedBox(height: 12),
                TextField(controller: hostController, decoration: const InputDecoration(labelText: 'FTP Host', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: TextField(controller: usernameController, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()))),
                    const SizedBox(width: 8),
                    SizedBox(width: 80, child: TextField(controller: portController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()))),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(controller: remotePathController, decoration: const InputDecoration(labelText: 'Remote Path (optional)', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Checkbox(value: passiveMode, onChanged: (v) => setDialogState(() => passiveMode = v ?? true)),
                    const Text('Use Passive Mode'),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _profiles[profileName] = {
                            'host': hostController.text,
                            'username': usernameController.text,
                            'password': passwordController.text,
                            'port': int.tryParse(portController.text) ?? 21,
                            'remotePath': remotePathController.text,
                            'passiveMode': passiveMode,
                          };
                          if (_currentProfile == profileName) _loadProfile(profileName);
                        });
                        _saveProfiles();
                        Navigator.pop(ctx);
                        setState(() => _successMessage = 'Profile updated.');
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    _remotePathController.dispose();
    _renameController.dispose();
    _duplicateFolderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(_showProfileManager ? Icons.folder : Icons.settings, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(
                _showProfileManager ? 'FTP Profile Manager' : 'FTP Server Settings',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
              ),
              const Spacer(),
              _buildPillButton(Icons.add, 'Create New Profile', onTap: _showCreateProfileDialog),
              const SizedBox(width: 8),
              _buildPillButton(
                _showProfileManager ? Icons.settings : Icons.folder,
                _showProfileManager ? 'Back to Settings' : 'Manage Profiles',
                onTap: () => setState(() => _showProfileManager = !_showProfileManager),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_successMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.green.shade300)),
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: Colors.green.shade600),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_successMessage!, style: TextStyle(fontSize: 11, color: Colors.green.shade700))),
                  GestureDetector(onTap: () => setState(() => _successMessage = null), child: Icon(Icons.close, size: 14, color: Colors.green.shade600)),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (!_showProfileManager) ...[
            Text('Select Profile', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _currentProfile,
                  isExpanded: true,
                  hint: Text('No Profile Selected', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('No Profile Selected')),
                    ..._profiles.keys.map((name) => DropdownMenuItem<String?>(
                          value: name,
                          child: Row(
                            children: [
                              Expanded(child: Text(name, style: TextStyle(fontSize: 11, color: Colors.grey.shade800), overflow: TextOverflow.ellipsis)),
                              GestureDetector(
                                onTap: () => _showEditProfileDialog(name),
                                child: Icon(Icons.settings, size: 14, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        )),
                  ],
                  onChanged: (v) {
                    if (v != null) _loadProfile(v);
                    else {
                      setState(() => _currentProfile = null);
                      _saveProfiles();
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Upload Options
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Upload Options', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _renameController,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'Rename uploaded file as',
                      hintText: 'Enter custom filename (optional)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _duplicateFolderController,
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'Save a duplicate version in another folder',
                      hintText: 'Enter folder path (optional)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(width: 20, height: 20, child: Checkbox(value: false, onChanged: (_) {}, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)),
                      const SizedBox(width: 8),
                      Text('Enable duplicate file saving', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            Text('Profile Manager', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
            const SizedBox(height: 8),
            Container(
              height: 220,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300)),
              child: _profiles.isEmpty
                  ? Center(child: Text('No saved profiles yet.\nCreate one using "Create New Profile".', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _profiles.length,
                      itemBuilder: (context, index) {
                        final name = _profiles.keys.elementAt(index);
                        final p = _profiles[name]!;
                        final isCurrent = _currentProfile == name;
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: isCurrent ? const Color(0xFF0052CC).withOpacity(0.1) : null,
                          child: ListTile(
                            leading: Icon(isCurrent ? Icons.check_circle : Icons.storage, color: isCurrent ? const Color(0xFF0052CC) : Colors.grey, size: 18),
                            title: Text(name, style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, fontSize: 12)),
                            subtitle: Text('${p['host']}:${p['port']}', style: const TextStyle(fontSize: 10)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isCurrent) IconButton(icon: const Icon(Icons.play_arrow, size: 20), onPressed: () => _loadProfile(name), tooltip: 'Load'),
                                IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _showEditProfileDialog(name), tooltip: 'Edit'),
                                IconButton(icon: const Icon(Icons.delete, size: 18), onPressed: () => _deleteProfile(name), tooltip: 'Delete'),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
          if (!widget.embedded) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: widget.onClose, child: const Text('Cancel')),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    if (_currentProfile != null) _saveCurrentAsProfile(_currentProfile!);
                    widget.onClose?.call();
                  },
                  child: const Text('Save Settings'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPillButton(IconData icon, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade400)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.grey.shade600),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
