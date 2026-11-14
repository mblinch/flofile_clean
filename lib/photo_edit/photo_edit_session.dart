import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'photo_adjustments.dart';
import 'photo_crop.dart';
import 'photo_grade_bake.dart';

/// Photo-stage surround behind Fit/Crop (right-click to change).
enum PhotoEditBackdrop {
  black,
  grey18,
  white;

  String get label => switch (this) {
        PhotoEditBackdrop.black => 'Black',
        PhotoEditBackdrop.grey18 => '18% grey',
        PhotoEditBackdrop.white => 'White',
      };

  Color get color => switch (this) {
        PhotoEditBackdrop.black => const Color(0xFF000000),
        // ~18% reflectance mid grey
        PhotoEditBackdrop.grey18 => const Color(0xFF777777),
        PhotoEditBackdrop.white => const Color(0xFFFFFFFF),
      };
}

class _PhotoEditSnapshot {
  const _PhotoEditSnapshot({
    required this.adjustments,
    required this.crop,
    required this.lockedAspect,
    required this.rotation,
    required this.straighten,
  });

  final PhotoAdjustments adjustments;
  final PhotoCrop crop;
  final double? lockedAspect;
  final int rotation;
  final double straighten;

  bool matches(PhotoEditSession session, String path) {
    final a = session.adjustmentsFor(path);
    final c = session.cropFor(path);
    final locked = session.aspectFor(path);
    final rot = session.rotationFor(path);
    final straight = session.straightenFor(path);
    return _sameAdjustments(a, adjustments) &&
        _sameCrop(c, crop) &&
        _sameAspect(locked, lockedAspect) &&
        rot == rotation &&
        (straight - straighten).abs() <= 1e-6;
  }
}

bool _sameAdjustments(PhotoAdjustments a, PhotoAdjustments b) {
  return (a.temperature - b.temperature).abs() <= 1e-6 &&
      (a.tint - b.tint).abs() <= 1e-6 &&
      (a.exposure - b.exposure).abs() <= 1e-6 &&
      (a.contrast - b.contrast).abs() <= 1e-6 &&
      (a.highlights - b.highlights).abs() <= 1e-6 &&
      (a.shadows - b.shadows).abs() <= 1e-6 &&
      (a.whites - b.whites).abs() <= 1e-6 &&
      (a.blacks - b.blacks).abs() <= 1e-6 &&
      (a.vibrance - b.vibrance).abs() <= 1e-6 &&
      (a.saturation - b.saturation).abs() <= 1e-6;
}

bool _sameCrop(PhotoCrop a, PhotoCrop b) {
  return (a.left - b.left).abs() <= 1e-6 &&
      (a.top - b.top).abs() <= 1e-6 &&
      (a.width - b.width).abs() <= 1e-6 &&
      (a.height - b.height).abs() <= 1e-6;
}

bool _sameAspect(double? a, double? b) {
  if (a == null && b == null) return true;
  if (a == null || b == null) return false;
  return (a - b).abs() <= 1e-6;
}

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

  /// Stage surround behind the photo (Fit letterboxing).
  PhotoEditBackdrop backdrop = PhotoEditBackdrop.black;

  String? error;

  final Map<String, PhotoAdjustments> _drafts = {};
  final Map<String, PhotoCrop> _crops = {};
  final Map<String, double> _imageAspect = {};
  final Map<String, double> _lockedAspect = {};
  /// Clockwise quarter-turns (0…3) on top of the upright EXIF frame.
  final Map<String, int> _rotations = {};

  /// Fine CW straighten in degrees (−45…45), applied before crop.
  final Map<String, double> _straighten = {};

  final Map<String, List<_PhotoEditSnapshot>> _undo = {};
  final Map<String, List<_PhotoEditSnapshot>> _redo = {};
  static const _historyLimit = 40;

  /// Path whose continuous gesture (slider / crop drag) already checkpointed.
  String? _activeGesturePath;

  /// Coalesce [notifyListeners] to one per frame while a gesture is active.
  bool _gestureNotifyScheduled = false;

  /// When true, crop handles keep the current ratio. Off lets them reshape.
  bool ratioLocked = true;

  void setRatioLocked(String path, bool locked) {
    if (ratioLocked == locked) return;
    ratioLocked = locked;
    // A preset ratio can't survive an unlocked crop — fall back to Free.
    if (!locked && _lockedAspect.containsKey(path)) {
      checkpoint(path);
      _lockedAspect.remove(path);
    }
    notifyListeners();
  }

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

  bool canUndo(String? path) =>
      path != null && (_undo[path]?.isNotEmpty ?? false);

  bool canRedo(String? path) =>
      path != null && (_redo[path]?.isNotEmpty ?? false);

  _PhotoEditSnapshot _snapshotFor(String path) => _PhotoEditSnapshot(
        adjustments: adjustmentsFor(path),
        crop: cropFor(path),
        lockedAspect: aspectFor(path),
        rotation: rotationFor(path),
        straighten: straightenFor(path),
      );

  void _applySnapshot(String path, _PhotoEditSnapshot snap) {
    if (snap.adjustments.isNeutral) {
      _drafts.remove(path);
    } else {
      _drafts[path] = snap.adjustments;
    }
    if (snap.crop.isFull) {
      _crops.remove(path);
    } else {
      _crops[path] = snap.crop;
    }
    if (snap.lockedAspect == null || snap.lockedAspect! <= 0) {
      _lockedAspect.remove(path);
    } else {
      _lockedAspect[path] = snap.lockedAspect!;
    }
    if (snap.rotation == 0) {
      _rotations.remove(path);
    } else {
      _rotations[path] = snap.rotation % 4;
    }
    if (snap.straighten.abs() <= 1e-6) {
      _straighten.remove(path);
    } else {
      _straighten[path] = clampStraightenDegrees(snap.straighten);
    }
  }

  void _clearHistory(String path) {
    _undo.remove(path);
    _redo.remove(path);
  }

  /// Push the current edit state before a new change (once per gesture).
  void checkpoint(String path) {
    if (saving) return;
    final stack = _undo.putIfAbsent(path, () => <_PhotoEditSnapshot>[]);
    if (stack.isNotEmpty && stack.last.matches(this, path)) return;
    stack.add(_snapshotFor(path));
    if (stack.length > _historyLimit) {
      stack.removeAt(0);
    }
    _redo.remove(path);
  }

  /// Start a continuous edit (slider / drag). Checkpoints once until [endGesture].
  void beginGesture(String path) {
    if (saving) return;
    if (_activeGesturePath == path) return;
    checkpoint(path);
    _activeGesturePath = path;
  }

  void endGesture() {
    final path = _activeGesturePath;
    _activeGesturePath = null;
    _gestureNotifyScheduled = false;
    // Soft settle only — never recenter/snap edges on release.
    if (path != null) {
      _clampCropToSource(path);
    }
    notifyListeners();
  }

  /// Fan-out to listeners. During a gesture, coalesce to one rebuild per
  /// frame but always flush the latest crop/straighten on that frame.
  void _notifyEdit() {
    if (_activeGesturePath == null) {
      notifyListeners();
      return;
    }
    if (_gestureNotifyScheduled) return;
    _gestureNotifyScheduled = true;
    // Paint this delta now; if more land before the frame ends, flush again.
    notifyListeners();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _gestureNotifyScheduled = false;
      if (_activeGesturePath != null && hasListeners) {
        notifyListeners();
      }
    });
  }

  void _clampCropToSource(String path) {
    final image = _imageAspect[path];
    if (image == null || image <= 0) return;
    final framed = cropFor(path);
    if (framed.isFull && straightenFor(path).abs() <= 1e-6) return;
    final next = constrainCropToSource(
      crop: framed,
      imageAspect: image,
      degrees: straightenFor(path),
    );
    if (next.isFull && straightenFor(path).abs() <= 1e-6) {
      _crops.remove(path);
    } else {
      _crops[path] = next;
    }
  }

  bool undo(String path) {
    if (saving) return false;
    final stack = _undo[path];
    if (stack == null || stack.isEmpty) return false;
    final redoStack = _redo.putIfAbsent(path, () => <_PhotoEditSnapshot>[]);
    redoStack.add(_snapshotFor(path));
    if (redoStack.length > _historyLimit) {
      redoStack.removeAt(0);
    }
    final previous = stack.removeLast();
    _applySnapshot(path, previous);
    editing = true;
    error = null;
    notifyListeners();
    return true;
  }

  bool redo(String path) {
    if (saving) return false;
    final stack = _redo[path];
    if (stack == null || stack.isEmpty) return false;
    final undoStack = _undo.putIfAbsent(path, () => <_PhotoEditSnapshot>[]);
    undoStack.add(_snapshotFor(path));
    if (undoStack.length > _historyLimit) {
      undoStack.removeAt(0);
    }
    final next = stack.removeLast();
    _applySnapshot(path, next);
    editing = true;
    error = null;
    notifyListeners();
    return true;
  }

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

  void setBackdrop(PhotoEditBackdrop next) {
    if (backdrop == next) return;
    backdrop = next;
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

  bool _cropShortcutArmed = true;

  /// Keyboard C: enter or finish crop. Collapses duplicate handlers in the
  /// same event turn (nested binders / screen + panel) into one toggle.
  bool shortcutToggleCrop() {
    if (saving || !editing) return false;
    if (!_cropShortcutArmed) return true;
    _cropShortcutArmed = false;
    if (cropping) {
      finishCropping();
    } else {
      toggleCropping();
    }
    SchedulerBinding.instance
        .addPostFrameCallback((_) => _cropShortcutArmed = true);
    return true;
  }

  void setCrop(String path, PhotoCrop next) {
    if (saving) return;
    final image = _imageAspect[path] ?? 1.5;
    final degrees = straightenFor(path);
    // Always stay inside the photo — including during live drags.
    final crop = constrainCropToSource(
      crop: next,
      imageAspect: image,
      degrees: degrees,
    );
    _followOrientation(path, crop, image, degrees);
    // During a drag, keep the exact frame — don't collapse near-full crops to
    // PhotoCrop.full (that snaps every edge flush with the image).
    if (_activeGesturePath != null) {
      _crops[path] = crop;
    } else if (crop.isFull) {
      _crops.remove(path);
    } else {
      _crops[path] = crop;
    }
    error = null;
    _notifyEdit();
  }

  /// A corner drag can flip a preset (3:2 → 2:3); keep the preset in step.
  void _followOrientation(
    String path,
    PhotoCrop crop,
    double image,
    double degrees,
  ) {
    final locked = _lockedAspect[path];
    if (locked == null || locked <= 0 || (locked - 1).abs() < 1e-6) return;
    final pixel = cropPixelAspect(
      crop: crop,
      imageAspect: image,
      degrees: degrees,
    );
    if (pixel <= 0) return;
    final asIs = (math.log(pixel) - math.log(locked)).abs();
    final flipped = (math.log(pixel) + math.log(locked)).abs();
    if (flipped < asIs) _lockedAspect[path] = 1 / locked;
  }

  /// Portrait ↔ landscape for the current crop (X key / swap button).
  void swapOrientation(String path) {
    if (saving) return;
    final image = _imageAspect[path];
    if (image == null || image <= 0) return;
    checkpoint(path);
    final degrees = straightenFor(path);
    final framed = cropFor(path);
    final source = framed.isFull && degrees.abs() > 1e-6
        ? safeCropForStraighten(imageAspect: image, degrees: degrees)
        : framed;
    _crops[path] = swapCropOrientation(
      crop: source,
      imageAspect: image,
      degrees: degrees,
    );
    final locked = _lockedAspect[path];
    if (locked != null && locked > 0) _lockedAspect[path] = 1 / locked;
    editing = true;
    cropping = true;
    error = null;
    notifyListeners();
  }

  void chooseAspect(String path, double? pixelAspect) {
    if (saving) return;
    checkpoint(path);
    if (pixelAspect == null || pixelAspect <= 0) {
      _lockedAspect.remove(path);
    } else {
      ratioLocked = true;
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
    checkpoint(path);
    editing = true;
    _rotations[path] = (rotationFor(path) + 1) % 4;
    if (_rotations[path] == 0) _rotations.remove(path);
    error = null;
    notifyListeners();
  }

  /// Rotate 90° counter-clockwise.
  void rotateCounterClockwise(String path) {
    if (saving) return;
    checkpoint(path);
    editing = true;
    _rotations[path] = (rotationFor(path) + 3) % 4;
    if (_rotations[path] == 0) _rotations.remove(path);
    error = null;
    notifyListeners();
  }

  /// Fine straighten for horizon fixes.
  ///
  /// Prefers keeping the current crop size and limiting the angle so straighten
  /// doesn't continuously shrink the frame (which felt like zooming in).
  /// More angle is allowed by tightening the crop only when the user asks for
  /// more straighten than the current frame can hold.
  void setStraighten(String path, double degrees) {
    if (saving) return;
    editing = true;
    cropping = true;
    final image = _imageAspect[path];
    final requested = clampStraightenDegrees(degrees);
    final previous = straightenFor(path);
    var next = requested;
    final framed = cropFor(path);
    if (image != null && image > 0) {
      if (framed.isFull && previous.abs() <= 1e-6) {
        if (requested.abs() > 1e-6) {
          // Full frame can't straighten without an inset; keep its ratio.
          _crops[path] = safeCropForStraighten(
            imageAspect: image,
            degrees: requested,
            pixelAspect: _lockedAspect[path] ?? image,
          );
        }
      } else {
        // Crop space is the rotated AABB — re-express the same pixel frame
        // at the new angle so straightening never changes its aspect ratio.
        PhotoCrop at(double deg) => reprojectCropForStraighten(
              crop: framed,
              imageAspect: image,
              fromDegrees: previous,
              toDegrees: deg,
            );
        bool fits(double deg) => cropFitsStraightenedSource(
              crop: at(deg),
              imageAspect: image,
              degrees: deg,
            );
        if (!fits(requested)) {
          // Keep size and limit the angle, unless the user pushes clearly
          // past what this frame can hold — then shrink (same aspect).
          var lo = 0.0;
          var hi = 1.0;
          for (var i = 0; i < 28; i++) {
            final mid = (lo + hi) / 2;
            if (fits(previous + (requested - previous) * mid)) {
              lo = mid;
            } else {
              hi = mid;
            }
          }
          final limited = previous + (requested - previous) * lo;
          if ((limited - requested).abs() > 0.08) {
            next = requested;
          } else {
            next = limited;
          }
        }
        final moved = at(next);
        _crops[path] = shrinkCropKeepingAspect(
          crop: moved,
          imageAspect: image,
          degrees: next,
        );
      }
    }
    if (next.abs() <= 1e-6) {
      _straighten.remove(path);
    } else {
      _straighten[path] = next;
    }
    error = null;
    _notifyEdit();
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
    if (!isDirty(path)) return;
    checkpoint(path);
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
    final turns = rotationFor(path);
    final straighten = straightenFor(path);
    final image = _imageAspect[path];
    // Same frame the preview shows — never bake empty corners into the file.
    final crop = straighten.abs() > 1e-6 && image != null && image > 0
        ? shrinkCropToSource(
            crop: cropFor(path),
            imageAspect: image,
            degrees: straighten,
          )
        : cropFor(path);
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
      _clearHistory(path);
      await onReplaced(path);
    } catch (e) {
      error = e is StateError ? e.message : 'Could not save the edited photo.';
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
