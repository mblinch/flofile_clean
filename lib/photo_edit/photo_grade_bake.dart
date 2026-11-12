import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../utils/exiftool_helper.dart';
import 'photo_adjust_config.dart';
import 'photo_adjustments.dart';
import 'photo_crop.dart';
import 'photo_grade_engine.dart';
import 'photo_tone_base.dart';

/// CPU bake used by isolates / tests. Prefer [writeGradedJpeg] (GPU) at runtime.
Uint8List bakeGradedJpeg(PhotoGradeBakeRequest request) {
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) {
    throw StateError('Could not read that photo.');
  }
  final hasExifOrientation = decoded.exif.imageIfd.hasOrientation &&
      decoded.exif.imageIfd.orientation != null &&
      decoded.exif.imageIfd.orientation != 1;
  final orientedImage =
      hasExifOrientation ? img.bakeOrientation(decoded) : decoded;
  final grade = PhotoAdjustments(
    exposure: request.exposure,
    contrast: request.contrast,
    shadows: request.shadows,
    highlights: request.highlights,
    whites: request.whites,
    blacks: request.blacks,
    temperature: request.temperature,
    tint: request.tint,
    vibrance: request.vibrance,
    saturation: request.saturation,
  );
  var oriented = orientedImage;
  final straighten = request.straightenDegrees;
  final hasStraighten = straighten.abs() > 1e-6;
  final fullFrame = request.cropLeft <= 0.0005 &&
      request.cropTop <= 0.0005 &&
      request.cropWidth >= 0.999 &&
      request.cropHeight >= 0.999;
  // Straighten rotates the full frame first; crop is in post-rotate space.
  if (!hasStraighten && !fullFrame) {
    oriented = _cropNormalized(
      oriented,
      left: request.cropLeft,
      top: request.cropTop,
      width: request.cropWidth,
      height: request.cropHeight,
    );
  }
  if (!grade.isNeutral) {
    Float32List? mask;
    var maskWidth = 0;
    var maskHeight = 0;
    if (grade.needsLocalTone) {
      final small = _toneBaseSource(oriented);
      final rgb = Uint8List(small.width * small.height * 3);
      var index = 0;
      for (final pixel in small) {
        rgb[index++] =
            (pixel.rNormalized.toDouble() * 255).round().clamp(0, 255);
        rgb[index++] =
            (pixel.gNormalized.toDouble() * 255).round().clamp(0, 255);
        rgb[index++] =
            (pixel.bNormalized.toDouble() * 255).round().clamp(0, 255);
      }
      mask = lumaMaskForDisplayRgb(rgb, small.width, small.height, grade);
      maskWidth = small.width;
      maskHeight = small.height;
    }
    var pixelIndex = 0;
    for (final pixel in oriented) {
      final x = pixelIndex % oriented.width;
      final y = pixelIndex ~/ oriented.width;
      pixelIndex++;
      final mask01 = mask == null
          ? null
          : sampleLumaBase(
              mask,
              maskWidth,
              maskHeight,
              x,
              y,
              oriented.width,
              oriented.height,
            );
      final graded = gradeDisplayRgb(
        pixel.rNormalized.toDouble(),
        pixel.gNormalized.toDouble(),
        pixel.bNormalized.toDouble(),
        grade,
        mask01: mask01,
        ditherX: x,
        ditherY: y,
      );
      pixel
        ..rNormalized = graded.r
        ..gNormalized = graded.g
        ..bNormalized = graded.b;
    }
  }
  if (hasStraighten) {
    oriented = img.copyRotate(oriented, angle: straighten);
    if (!fullFrame) {
      oriented = _cropNormalized(
        oriented,
        left: request.cropLeft,
        top: request.cropTop,
        width: request.cropWidth,
        height: request.cropHeight,
      );
    }
  }
  final turns = request.quarterTurns % 4;
  if (turns != 0) {
    oriented = img.copyRotate(oriented, angle: turns * 90);
  }
  return Uint8List.fromList(
    img.encodeJpg(oriented, quality: PhotoAdjustConfig.exportJpegQuality),
  );
}

img.Image _cropNormalized(
  img.Image source, {
  required double left,
  required double top,
  required double width,
  required double height,
}) {
  final x = (left * source.width).round().clamp(0, source.width - 1);
  final y = (top * source.height).round().clamp(0, source.height - 1);
  var w = (width * source.width).round();
  var h = (height * source.height).round();
  if (w < 1) w = 1;
  if (h < 1) h = 1;
  if (x + w > source.width) w = source.width - x;
  if (y + h > source.height) h = source.height - y;
  return img.copyCrop(source, x: x, y: y, width: w, height: h);
}

class PhotoGradeBakeRequest {
  const PhotoGradeBakeRequest({
    required this.bytes,
    required this.exposure,
    required this.contrast,
    required this.shadows,
    required this.highlights,
    required this.whites,
    required this.blacks,
    required this.temperature,
    required this.tint,
    this.vibrance = 0,
    this.saturation = 0,
    required this.cropLeft,
    required this.cropTop,
    required this.cropWidth,
    required this.cropHeight,
    this.quarterTurns = 0,
    this.straightenDegrees = 0,
  });

  final Uint8List bytes;
  final double exposure;
  final double contrast;
  final double shadows;
  final double highlights;
  final double whites;
  final double blacks;
  final double temperature;
  final double tint;
  final double vibrance;
  final double saturation;
  final double cropLeft;
  final double cropTop;
  final double cropWidth;
  final double cropHeight;
  /// Extra CW quarter-turns after crop (matches preview [RotatedBox]).
  final int quarterTurns;
  /// Fine CW straighten before crop (degrees).
  final double straightenDegrees;
}

/// Writes a graded JPEG over [path], copying ALL metadata back with exiftool.
///
/// Prefers the GPU engine (same shaders as preview). Falls back to the CPU
/// bake on a background isolate if the GPU path fails.
Future<void> writeGradedJpeg({
  required String path,
  required PhotoAdjustments adjustments,
  double cropLeft = 0,
  double cropTop = 0,
  double cropWidth = 1,
  double cropHeight = 1,
  int quarterTurns = 0,
  double straightenDegrees = 0,
}) async {
  final lower = p.extension(path).toLowerCase();
  if (lower != '.jpg' && lower != '.jpeg') {
    throw StateError('Only JPEG photos can be edited.');
  }
  final original = await File(path).readAsBytes();
  final crop = PhotoCrop(
    left: cropLeft,
    top: cropTop,
    width: cropWidth,
    height: cropHeight,
  );
  final turns = quarterTurns % 4;
  final straighten = clampStraightenDegrees(straightenDegrees);

  Uint8List graded;
  final gpuBytes = await _bakeOnGpu(
    bytes: original,
    adjustments: adjustments,
    crop: crop,
    quarterTurns: turns,
    straightenDegrees: straighten,
  );
  if (gpuBytes != null) {
    graded = gpuBytes;
  } else {
    graded = await compute(
      bakeGradedJpeg,
      PhotoGradeBakeRequest(
        bytes: original,
        exposure: adjustments.exposure,
        contrast: adjustments.contrast,
        shadows: adjustments.shadows,
        highlights: adjustments.highlights,
        whites: adjustments.whites,
        blacks: adjustments.blacks,
        temperature: adjustments.temperature,
        tint: adjustments.tint,
        vibrance: adjustments.vibrance,
        saturation: adjustments.saturation,
        cropLeft: cropLeft,
        cropTop: cropTop,
        cropWidth: cropWidth,
        cropHeight: cropHeight,
        quarterTurns: turns,
        straightenDegrees: straighten,
      ),
    );
  }

  final temp = File(
    p.join(
      Directory.systemTemp.path,
      'flofile-grade-${DateTime.now().microsecondsSinceEpoch}.jpg',
    ),
  );
  final staged = File('$path.flofile-grade');
  try {
    await temp.writeAsBytes(graded, flush: true);
    // Copy every tag from the original onto the graded pixels. Orientation is
    // reset because pixels are stored upright after bakeOrientation / GPU path.
    final copied = await ExiftoolHelper.run([
      '-overwrite_original',
      '-m',
      '-TagsFromFile',
      path,
      '-all:all',
      '-unsafe',
      '-Orientation#=1',
      '-ThumbnailImage=',
      temp.path,
    ]);
    if (!copied.isSuccess) {
      throw StateError(
        'Could not keep the caption metadata on the edited photo.',
      );
    }
    final withMeta = await temp.readAsBytes();
    await staged.writeAsBytes(withMeta, flush: true);
    await staged.rename(path);
  } finally {
    if (await temp.exists()) {
      await temp.delete();
    }
    if (await staged.exists()) {
      await staged.delete();
    }
  }
}

Future<Uint8List?> _bakeOnGpu({
  required Uint8List bytes,
  required PhotoAdjustments adjustments,
  required PhotoCrop crop,
  int quarterTurns = 0,
  double straightenDegrees = 0,
}) async {
  try {
    // Bake orientation into pixels first so GPU UVs match upright layout.
    final oriented = await _orientedJpegBytes(bytes);
    final hasStraighten = straightenDegrees.abs() > 1e-6;
    final engine = PhotoGradeEngine();
    // Straighten needs the full graded frame; crop afterward in CPU space.
    final gpuCrop = hasStraighten ? PhotoCrop.full : crop;
    final rgba = await engine.exportRgba(
      jpegBytes: oriented,
      adjustments: adjustments,
      crop: gpuCrop,
    );
    if (rgba == null) return null;

    // Infer dimensions from crop of decoded oriented image.
    final decoded = img.decodeImage(oriented);
    if (decoded == null) return null;
    final outW = gpuCrop.isFull
        ? decoded.width
        : (decoded.width * gpuCrop.width).round().clamp(1, decoded.width);
    final outH = gpuCrop.isFull
        ? decoded.height
        : (decoded.height * gpuCrop.height).round().clamp(1, decoded.height);
    if (rgba.length < outW * outH * 4) return null;

    var out = img.Image(width: outW, height: outH, numChannels: 3);
    for (var y = 0; y < outH; y++) {
      for (var x = 0; x < outW; x++) {
        final o = (y * outW + x) * 4;
        out.setPixelRgb(x, y, rgba[o], rgba[o + 1], rgba[o + 2]);
      }
    }
    if (hasStraighten) {
      out = img.copyRotate(out, angle: straightenDegrees);
      if (!crop.isFull) {
        out = _cropNormalized(
          out,
          left: crop.left,
          top: crop.top,
          width: crop.width,
          height: crop.height,
        );
      }
    }
    final turns = quarterTurns % 4;
    if (turns != 0) {
      out = img.copyRotate(out, angle: turns * 90);
    }
    return Uint8List.fromList(
      img.encodeJpg(out, quality: PhotoAdjustConfig.exportJpegQuality),
    );
  } catch (e, st) {
    debugPrint('GPU grade bake failed, falling back to CPU: $e\n$st');
    return null;
  }
}

Future<Uint8List> _orientedJpegBytes(Uint8List bytes) async {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final hasExifOrientation = decoded.exif.imageIfd.hasOrientation &&
      decoded.exif.imageIfd.orientation != null &&
      decoded.exif.imageIfd.orientation != 1;
  if (!hasExifOrientation) return bytes;
  final oriented = img.bakeOrientation(decoded);
  return Uint8List.fromList(
    img.encodeJpg(oriented, quality: PhotoAdjustConfig.exportJpegQuality),
  );
}

img.Image _toneBaseSource(img.Image source) {
  final maxEdge = (PhotoAdjustConfig.previewLongEdge *
          PhotoAdjustConfig.maskResolutionScale)
      .round()
      .clamp(256, 2048);
  if (source.width <= maxEdge && source.height <= maxEdge) return source;
  if (source.width >= source.height) {
    return img.copyResize(source, width: maxEdge);
  }
  return img.copyResize(source, height: maxEdge);
}
