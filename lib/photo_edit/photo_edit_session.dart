import 'package:flutter/foundation.dart';

import '../services/admin_service.dart';
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
  String? error;

  final Map<String, PhotoAdjustments> _drafts = {};
  final Map<String, PhotoCrop> _crops = {};
  final Map<String, double> _imageAspect = {};
  final Map<String, double> _lockedAspect = {};

  PhotoAdjustments adjustmentsFor(String? path) {
    if (path == null) return PhotoAdjustments.neutral;
    return _drafts[path] ?? PhotoAdjustments.neutral;
  }

  PhotoCrop cropFor(String? path) {
    if (path == null) return PhotoCrop.full;
    return _crops[path] ?? PhotoCrop.full;
  }

  /// Locked pixel aspect (width/height), or null for a free crop.
  double? aspectFor(String? path) {
    if (path == null) return null;
    return _lockedAspect[path];
  }

  /// Normalized width/height for the locked aspect on this photo.
  double? normAspectFor(String path) {
    final pixel = _lockedAspect[path];
    final image = _imageAspect[path];
    if (pixel == null || image == null || image <= 0) return null;
    return pixel / image;
  }

  bool isDirty(String? path) =>
      !adjustmentsFor(path).isNeutral || !cropFor(path).isFull;

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
    if (saving || !AdminService.isCurrentUserAdminSync()) return;
    editing = !editing;
    if (!editing) cropping = false;
    error = null;
    notifyListeners();
  }

  void toggleCropping() {
    if (saving || !AdminService.isCurrentUserAdminSync()) return;
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
        _crops[path] = PhotoCrop.largest(pixelAspect / image);
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
    error = null;
    notifyListeners();
  }

  Future<void> apply(String path) async {
    final adjustments = adjustmentsFor(path);
    final crop = cropFor(path);
    if ((adjustments.isNeutral && crop.isFull) || saving) return;
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
      );
      _drafts.remove(path);
      _crops.remove(path);
      _lockedAspect.remove(path);
      await onReplaced(path);
    } catch (e) {
      error = e is StateError ? e.message : 'Could not save the edited photo.';
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
