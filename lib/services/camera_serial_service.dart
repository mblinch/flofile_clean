import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CameraSerialService {
  static const String _cameraMappingsKey = 'camera_serial_mappings';

  // Map of camera serial numbers to photographer data
  Map<String, Map<String, String>> _cameraMappings = {};

  // Get camera mappings (for backward compatibility)
  Map<String, String> get cameraMappings {
    Map<String, String> simpleMappings = {};
    _cameraMappings.forEach((serial, data) {
      simpleMappings[serial] = data['name'] ?? '';
    });
    return simpleMappings;
  }

  // Get full camera data mappings
  Map<String, Map<String, String>> get fullCameraMappings =>
      Map.from(_cameraMappings);

  // Initialize the service and load saved mappings
  Future<void> initialize() async {
    await _loadMappings();
  }

  // Load camera mappings from SharedPreferences
  Future<void> _loadMappings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? mappingsJson = prefs.getString(_cameraMappingsKey);

      if (mappingsJson != null && mappingsJson.isNotEmpty) {
        final Map<String, dynamic> decoded = jsonDecode(mappingsJson);

        // Handle both old format (String) and new format (Map)
        _cameraMappings = decoded.map((key, value) {
          if (value is Map<String, dynamic>) {
            // New format with name and initials
            return MapEntry(key, Map<String, String>.from(value));
          } else {
            // Old format - convert to new format
            return MapEntry(key, {
              'name': value.toString(),
              'initials': '',
            });
          }
        });
      }

      print('Loaded ${_cameraMappings.length} camera serial mappings');
    } catch (e) {
      print('Error loading camera mappings: $e');
      _cameraMappings = {};
    }
  }

  // Save camera mappings to SharedPreferences
  Future<void> _saveMappings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String mappingsJson = jsonEncode(_cameraMappings);
      await prefs.setString(_cameraMappingsKey, mappingsJson);
      print('Saved ${_cameraMappings.length} camera serial mappings');
    } catch (e) {
      print('Error saving camera mappings: $e');
    }
  }

  // Add or update a camera serial number mapping
  Future<void> addCameraMapping(String serialNumber, String photographerName,
      {String initials = ''}) async {
    if (serialNumber.trim().isEmpty || photographerName.trim().isEmpty) {
      throw ArgumentError(
          'Serial number and photographer name cannot be empty');
    }

    // Ensure service is initialized
    await initialize();

    _cameraMappings[serialNumber.trim()] = {
      'name': photographerName.trim(),
      'initials': initials.trim(),
    };
    await _saveMappings();
  }

  // Remove a camera serial number mapping
  Future<void> removeCameraMapping(String serialNumber) async {
    await initialize();
    _cameraMappings.remove(serialNumber.trim());
    await _saveMappings();
  }

  // Get photographer name for a camera serial number
  String? getPhotographerForSerial(String serialNumber) {
    if (serialNumber.trim().isEmpty) return null;
    return _cameraMappings[serialNumber.trim()]?['name'];
  }

  // Get photographer initials for a camera serial number
  String? getPhotographerInitials(String serialNumber) {
    if (serialNumber.trim().isEmpty) return null;
    return _cameraMappings[serialNumber.trim()]?['initials'];
  }

  // Get full photographer data for a camera serial number
  Map<String, String>? getPhotographerData(String serialNumber) {
    if (serialNumber.trim().isEmpty) return null;
    return _cameraMappings[serialNumber.trim()];
  }

  // Check if a camera serial number is registered
  bool isCameraRegistered(String serialNumber) {
    if (serialNumber.trim().isEmpty) return false;
    return _cameraMappings.containsKey(serialNumber.trim());
  }

  // Get all camera serial numbers
  List<String> getAllSerialNumbers() {
    return _cameraMappings.keys.toList()..sort();
  }

  // Get all photographer names
  List<String> getAllPhotographerNames() {
    return _cameraMappings.values
        .map((data) => data['name'] ?? '')
        .toSet()
        .toList()
      ..sort();
  }

  // Clear all mappings
  Future<void> clearAllMappings() async {
    _cameraMappings.clear();
    await _saveMappings();
  }

  // Get camera info display string (Make Model • SN: SerialNumber)
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

  // Auto-detect photographer from camera serial number in EXIF data
  String? detectPhotographerFromExif(Map<String, dynamic> exifData) {
    final serialNumber = exifData['SerialNumber']?.toString();
    if (serialNumber != null && serialNumber.isNotEmpty) {
      return getPhotographerForSerial(serialNumber);
    }
    return null;
  }

  /// Get all unique photographer names for selection in unknown serial prompt
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

  /// Add a serial number to an existing photographer
  Future<void> addSerialToExistingPhotographer(
      String serialNumber, String photographerName) async {
    await initialize();
    _cameraMappings[serialNumber.trim()] = {
      'name': photographerName.trim(),
      'initials': '', // Keep empty for now, could be updated later
    };
    await _saveMappings();
  }

  /// Check if a serial number is unknown (not in mappings)
  bool isSerialNumberUnknown(String serialNumber) {
    return !_cameraMappings.containsKey(serialNumber.trim());
  }
}
