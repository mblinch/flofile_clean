import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../services/preferences_service.dart';

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
    return AlertDialog(
      title: const Text('Preferences'),
      content: SizedBox(
        width: 400,
        height: 500,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current Preferences:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPreferenceItem(
                            'Category Order',
                            (_currentPreferences?['categoryOrder'] as List?)
                                    ?.join(', ') ??
                                'Default',
                          ),
                          _buildPreferenceItem(
                            'Favorite Verbs',
                            '${(_currentPreferences?['favoriteVerbs'] as List?)?.length ?? 0} verbs',
                          ),
                          _buildPreferenceItem(
                            'Favorite Teams',
                            '${(_currentPreferences?['favoriteTeams'] as List?)?.length ?? 0} teams',
                          ),
                          _buildPreferenceItem(
                            'FTP Profiles',
                            '${(_currentPreferences?['ftpProfiles'] as Map?)?.length ?? 0} profiles',
                          ),
                          _buildPreferenceItem(
                            'Firebar Position',
                            (_currentPreferences?['placeFirebarOnRight'] ==
                                    true)
                                ? 'Right'
                                : 'Left',
                          ),
                          _buildPreferenceItem(
                            'Current FTP Profile',
                            (_currentPreferences?['currentFtpProfile']
                                    as String?) ??
                                'None',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _exportPreferences,
                        icon: const Icon(Icons.download),
                        label: const Text('Export'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _importPreferences,
                        icon: const Icon(Icons.upload),
                        label: const Text('Import'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _resetToDefaults,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reset'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildPreferenceItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

