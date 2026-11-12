import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'photo_adjustments.dart';
import 'photo_crop.dart';
import 'photo_grade_bake.dart';

/// Per-photo draft grades and whether the edit sheet is open.
class PhotoEditSession extends ChangeNotifier {
  PhotoEditSession({required this.onReplaced});

  /// Called after a graded JPEG replaces [path] on disk.
  final Future<void> Function(String path) onReplaced;

  bool editing = false;
  bool cropping = false;
  bool saving = false;

  /// Hold backslash to flash the ungraded original.
  bool comparing = false;

  String? error;

  final Map<String, PhotoAdjustments> _drafts = {};
  final Map<String, PhotoCrop> _crops = {};
  final Map<String, double> _imageAspect = {};
  final Map<String, double> _lockedAspect = {};
  /// Clockwise quarter-turns (0…3) on top of the upright EXIF frame.
  final Map<String, int> _rotations = {};

  /// Fine CW straighten in degrees (−45…45), applied before crop.
  final Map<String, double> _straighten = {};

  PhotoAdjustments adjustmentsFor(String? path) {
    if (path == null) return PhotoAdjustments.neutral;
    return _drafts[path] ?? PhotoAdjustments.neutral;
  }

  PhotoCrop cropFor(String? path) {
    if (path == null) return PhotoCrop.full;
    return _crops[path] ?? PhotoCrop.full;
  }

  /// Extra CW quarter-turns for [path] (0 = upright).
  int rotationFor(String? path) {
    if (path == null) return 0;
    return _rotations[path] ?? 0;
  }

  /// Horizon straighten in degrees (CW positive).
  double straightenFor(String? path) {
    if (path == null) return 0;
    return _straighten[path] ?? 0;
  }

  /// Locked pixel aspect (width/height), or null for a free crop.
  double? aspectFor(String? path) {
    if (path == null) return null;
    return _lockedAspect[path];
  }

  /// Pixel width/height of the oriented source, when known.
  double? imageAspectFor(String? path) {
    if (path == null) return null;
    return _imageAspect[path];
  }

  /// Normalized width/height for the locked aspect on this photo.
  ///
  /// When straightened, crop space is the rotated AABB, so the ratio uses that.
  double? normAspectFor(String path) {
    final pixel = _lockedAspect[path];
    final image = _imageAspect[path];
    if (pixel == null || image == null || image <= 0) return null;
    final degrees = straightenFor(path);
    if (degrees.abs() <= 1e-6) return pixel / image;
    final rad = degrees * math.pi / 180.0;
    final cosA = math.cos(rad).abs();
    final sinA = math.sin(rad).abs();
    final aabbAspect = (image * cosA + sinA) / (image * sinA + cosA);
    if (aabbAspect <= 0) return pixel / image;
    return pixel / aabbAspect;
  }

  bool isDirty(String? path) =>
      !adjustmentsFor(path).isNeutral ||
      !cropFor(path).isFull ||
      rotationFor(path) != 0 ||
      straightenFor(path).abs() > 1e-6;

  void noteImageAspect(String path, double aspect) {
    if (aspect <= 0) return;
    final previous = _imageAspect[path];
    _imageAspect[path] = aspect;
    final locked = _lockedAspect[path];
    if (previous == null && locked != null && cropFor(path).isFull) {
      _crops[path] = PhotoCrop.largest(locked / aspect);
      notifyListeners();
    }
  }

  void toggleEditing() {
    if (saving) return;
    editing = !editing;
    if (!editing) {
      cropping = false;
      comparing = false;
    }
    error = null;
    notifyListeners();
  }

  /// Leaves edit/crop (e.g. when switching layouts).
  void exitEditing() {
    if (!editing && !cropping && !comparing) return;
    editing = false;
    cropping = false;
    comparing = false;
    error = null;
    notifyListeners();
  }

  void setComparing(bool value) {
    if (!editing || comparing == value) return;
    comparing = value;
    notifyListeners();
  }

  void toggleCropping() {
    if (saving) return;
    cropping = !cropping;
    if (cropping) editing = true;
    error = null;
    notifyListeners();
  }

  /// Leaves the crop tool so the preview shows the crop that was drawn.
  void finishCropping() {
    if (saving || !cropping) return;
    cropping = false;
    error = null;
    notifyListeners();
  }

  void setCrop(String path, PhotoCrop next) {
    if (saving) return;
    if (next.isFull) {
      _crops.remove(path);
    } else {
      _crops[path] = next;
    }
    error = null;
    notifyListeners();
  }

  void chooseAspect(String path, double? pixelAspect) {
    if (saving) return;
    if (pixelAspect == null || pixelAspect <= 0) {
      _lockedAspect.remove(path);
    } else {
      _lockedAspect[path] = pixelAspect;
      final image = _imageAspect[path];
      if (image != null && image > 0) {
        final degrees = straightenFor(path);
        if (degrees.abs() > 1e-6) {
          _crops[path] = safeCropForStraighten(
            imageAspect: image,
            degrees: degrees,
            pixelAspect: pixelAspect,
          );
        } else {
          _crops[path] = PhotoCrop.largest(pixelAspect / image);
        }
      }
    }
    error = null;
    notifyListeners();
  }

  /// Rotate 90° clockwise. Crop stays in source space; preview uses [RotatedBox].
  void rotateClockwise(String path) {
    if (saving) return;
    editing = true;
    _rotations[path] = (rotationFor(path) + 1) % 4;
    if (_rotations[path] == 0) _rotations.remove(path);
    error = null;
    notifyListeners();
  }

  /// Rotate 90° counter-clockwise.
  void rotateCounterClockwise(String path) {
    if (saving) return;
    editing = true;
    _rotations[path] = (rotationFor(path) + 3) % 4;
    if (_rotations[path] == 0) _rotations.remove(path);
    error = null;
    notifyListeners();
  }

  /// Fine straighten for horizon fixes. Crop is reset to a safe inscribed frame.
  void setStraighten(String path, double degrees) {
    if (saving) return;
    editing = true;
    cropping = true;
    final next = clampStraightenDegrees(degrees);
    if (next.abs() <= 1e-6) {
      _straighten.remove(path);
      // Leave crop as-is when returning to zero so the user can keep framing.
    } else {
      _straighten[path] = next;
      final image = _imageAspect[path];
      if (image != null && image > 0) {
        _crops[path] = safeCropForStraighten(
          imageAspect: image,
          degrees: next,
          pixelAspect: _lockedAspect[path],
        );
      }
    }
    error = null;
    notifyListeners();
  }

  void update(String path, PhotoAdjustments next) {
    if (saving) return;
    if (next.isNeutral) {
      _drafts.remove(path);
    } else {
      _drafts[path] = next;
    }
    error = null;
    notifyListeners();
  }

  void reset(String path) {
    if (saving) return;
    _drafts.remove(path);
    _crops.remove(path);
    _lockedAspect.remove(path);
    _rotations.remove(path);
    _straighten.remove(path);
    error = null;
    notifyListeners();
  }

  Future<void> apply(String path) async {
    final adjustments = adjustmentsFor(path);
    final crop = cropFor(path);
    final turns = rotationFor(path);
    final straighten = straightenFor(path);
    if ((adjustments.isNeutral &&
            crop.isFull &&
            turns == 0 &&
            straighten.abs() <= 1e-6) ||
        saving) {
      return;
    }
    saving = true;
    error = null;
    notifyListeners();
    try {
      await writeGradedJpeg(
        path: path,
        adjustments: adjustments,
        cropLeft: crop.left,
        cropTop: crop.top,
        cropWidth: crop.width,
        cropHeight: crop.height,
        quarterTurns: turns,
        straightenDegrees: straighten,
      );
      _drafts.remove(path);
      _crops.remove(path);
      _lockedAspect.remove(path);
      _rotations.remove(path);
      _straighten.remove(path);
      await onReplaced(path);
    } catch (e) {
      error = e is StateError ? e.message : 'Could not save the edited photo.';
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
