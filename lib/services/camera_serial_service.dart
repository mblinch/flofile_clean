import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Camera serial → photographer mappings.
///
/// Stored locally in SharedPreferences and included in the signed-in user's
/// Firebase prefs sync (`users/{uid}/preferences/current`).
class CameraSerialService {
  CameraSerialService._();

  static final CameraSerialService instance = CameraSerialService._();

  /// Backward-compatible constructor — always returns [instance].
  factory CameraSerialService() => instance;

  static const String _cameraMappingsKey = 'camera_serial_mappings';

  /// Optional hook so [PreferencesService] can schedule a cloud upload without
  /// a circular import.
  static Future<void> Function()? onChangedForCloudSync;

  Map<String, Map<String, String>> _cameraMappings = {};
  bool _initialized = false;
  bool _suppressCloudSync = false;

  /// Bumped after local or cloud updates so open UIs can refresh.
  final ValueNotifier<int> mappingsRevision = ValueNotifier<int>(0);

  Map<String, String> get cameraMappings {
    final simpleMappings = <String, String>{};
    _cameraMappings.forEach((serial, data) {
      simpleMappings[serial] = data['name'] ?? '';
    });
    return simpleMappings;
  }

  Map<String, Map<String, String>> get fullCameraMappings =>
      Map.from(_cameraMappings);

  Future<void> initialize() async {
    if (_initialized) return;
    await _loadMappings();
    _initialized = true;
  }

  Future<void> _loadMappings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? mappingsJson = prefs.getString(_cameraMappingsKey);

      if (mappingsJson != null && mappingsJson.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(mappingsJson);
        _cameraMappings = decoded.map((key, value) {
          if (value is Map) {
            return MapEntry(
              key,
              value.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
            );
          }
          return MapEntry(key, {
            'name': value.toString(),
            'initials': '',
          });
        });
      }
    } catch (e) {
      print('Error loading camera mappings: $e');
      _cameraMappings = {};
    }
  }

  Future<void> _saveMappings({bool syncCloud = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String mappingsJson = jsonEncode(_cameraMappings);
      await prefs.setString(_cameraMappingsKey, mappingsJson);
      mappingsRevision.value++;
      if (syncCloud && !_suppressCloudSync) {
        final hook = onChangedForCloudSync;
        if (hook != null) {
          try {
            await hook();
          } catch (e) {
            print('Camera serial cloud sync schedule failed: $e');
          }
        }
      }
    } catch (e) {
      print('Error saving camera mappings: $e');
    }
  }

  /// JSON-ready map for prefs / Firebase sync.
  Map<String, Map<String, String>> exportMappings() {
    return {
      for (final entry in _cameraMappings.entries)
        entry.key: Map<String, String>.from(entry.value),
    };
  }

  /// Replace all mappings from a cloud/import bundle.
  Future<void> importMappings(
    dynamic raw, {
    bool syncCloud = false,
  }) async {
    await initialize();
    final next = <String, Map<String, String>>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        final serial = normalizeSerial(key.toString());
        if (serial.isEmpty) return;
        // Collapse case-variant duplicates onto one key.
        String target = serial;
        final lower = serial.toLowerCase();
        for (final existing in next.keys) {
          if (existing.toLowerCase() == lower) {
            target = existing;
            break;
          }
        }
        if (value is Map) {
          next[target] = {
            'name': value['name']?.toString() ?? '',
            'initials': value['initials']?.toString() ?? '',
          };
        } else if (value != null) {
          next[target] = {
            'name': value.toString(),
            'initials': '',
          };
        }
      });
    }
    _suppressCloudSync = !syncCloud;
    try {
      _cameraMappings = next;
      await _saveMappings(syncCloud: syncCloud);
    } finally {
      _suppressCloudSync = false;
    }
  }

  /// Trimmed serial used as the map key. Matching is case-insensitive so the
  /// same camera cannot be stored twice under different casing.
  static String normalizeSerial(String serialNumber) => serialNumber.trim();

  /// Existing map key for [serialNumber], if any (case-insensitive).
  String? existingSerialKey(String serialNumber) {
    final needle = normalizeSerial(serialNumber);
    if (needle.isEmpty) return null;
    if (_cameraMappings.containsKey(needle)) return needle;
    final lower = needle.toLowerCase();
    for (final key in _cameraMappings.keys) {
      if (key.toLowerCase() == lower) return key;
    }
    return null;
  }

  /// Adds or updates a mapping. Returns `true` if an existing serial was
  /// updated (no second entry is created).
  Future<bool> addCameraMapping(String serialNumber, String photographerName,
      {String initials = ''}) async {
    final result = await mergeMappings([
      (
        serial: serialNumber,
        name: photographerName,
        initials: initials,
      ),
    ]);
    if (result.errors.isNotEmpty) {
      throw ArgumentError(result.errors.first);
    }
    return result.updated > 0;
  }

  /// Bulk merge for Import / Paste. Same serial never creates a second row
  /// (case-insensitive); later rows in [rows] win. Saves once.
  Future<CameraSerialMergeResult> mergeMappings(
    Iterable<({String serial, String name, String initials})> rows,
  ) async {
    await initialize();

    // Dedupe within the import payload first (last occurrence wins).
    final incoming = <String, Map<String, String>>{};
    // Map lowercase serial → canonical key used in [incoming].
    final incomingKeyByLower = <String, String>{};
    final errors = <String>[];
    var rowIndex = 0;
    for (final row in rows) {
      rowIndex++;
      final serial = normalizeSerial(row.serial);
      final name = row.name.trim();
      if (serial.isEmpty || name.isEmpty) {
        errors.add('Row $rowIndex: serial and name are required');
        continue;
      }
      final lower = serial.toLowerCase();
      final existingIncoming = incomingKeyByLower[lower];
      if (existingIncoming != null && existingIncoming != serial) {
        incoming.remove(existingIncoming);
      }
      incomingKeyByLower[lower] = serial;
      incoming[serial] = {
        'name': name,
        'initials': row.initials.trim(),
      };
    }

    var added = 0;
    var updated = 0;
    for (final entry in incoming.entries) {
      final existingKey = existingSerialKey(entry.key);
      if (existingKey != null) {
        updated++;
        if (existingKey != entry.key) {
          _cameraMappings.remove(existingKey);
        }
      } else {
        added++;
      }
      _cameraMappings[entry.key] = entry.value;
    }

    if (added > 0 || updated > 0) {
      await _saveMappings();
    }
    return CameraSerialMergeResult(
      added: added,
      updated: updated,
      errors: errors,
    );
  }

  Future<void> removeCameraMapping(String serialNumber) async {
    await initialize();
    final key = existingSerialKey(serialNumber);
    if (key == null) return;
    _cameraMappings.remove(key);
    await _saveMappings();
  }

  String? getPhotographerForSerial(String serialNumber) {
    final key = existingSerialKey(serialNumber);
    if (key == null) return null;
    return _cameraMappings[key]?['name'];
  }

  String? getPhotographerInitials(String serialNumber) {
    final key = existingSerialKey(serialNumber);
    if (key == null) return null;
    return _cameraMappings[key]?['initials'];
  }

  Map<String, String>? getPhotographerData(String serialNumber) {
    final key = existingSerialKey(serialNumber);
    if (key == null) return null;
    return _cameraMappings[key];
  }

  bool isCameraRegistered(String serialNumber) {
    return existingSerialKey(serialNumber) != null;
  }

  List<String> getAllSerialNumbers() {
    return _cameraMappings.keys.toList()..sort();
  }

  List<String> getAllPhotographerNames() {
    return _cameraMappings.values
        .map((data) => data['name'] ?? '')
        .toSet()
        .toList()
      ..sort();
  }

  Future<void> clearAllMappings() async {
    _cameraMappings.clear();
    await _saveMappings();
  }

  String getCameraDisplayInfo(Map<String, dynamic> exifData) {
    final make = exifData['Make']?.toString() ?? '';
    final model = exifData['Model']?.toString() ?? '';
    final serialNumber = exifData['SerialNumber']?.toString() ?? '';

    if (make.isNotEmpty && model.isNotEmpty) {
      if (serialNumber.isNotEmpty) {
        return '$make $model • SN: $serialNumber';
      } else {
        return '$make $model'.trim();
      }
    } else if (make.isNotEmpty) {
      return make;
    } else if (model.isNotEmpty) {
      return model;
    }

    return 'Unknown Camera';
  }

  String? detectPhotographerFromExif(Map<String, dynamic> exifData) {
    for (final key in const [
      'SerialNumber',
      'BodySerialNumber',
      'InternalSerialNumber',
      'CameraSerialNumber',
    ]) {
      final serialNumber = exifData[key]?.toString().trim() ?? '';
      if (serialNumber.isNotEmpty) {
        return getPhotographerForSerial(serialNumber);
      }
    }
    return null;
  }

  List<String> getUniquePhotographerNames() {
    final names = <String>{};
    for (final mapping in _cameraMappings.values) {
      final name = mapping['name'];
      if (name != null && name.isNotEmpty) {
        names.add(name);
      }
    }
    return names.toList()..sort();
  }

  Future<void> addSerialToExistingPhotographer(
      String serialNumber, String photographerName) async {
    await addCameraMapping(serialNumber, photographerName);
  }

  bool isSerialNumberUnknown(String serialNumber) {
    return !isCameraRegistered(serialNumber);
  }
}

class CameraSerialMergeResult {
  const CameraSerialMergeResult({
    required this.added,
    required this.updated,
    this.errors = const [],
  });

  final int added;
  final int updated;
  final List<String> errors;

  int get touched => added + updated;
}
