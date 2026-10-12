import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../utils/exiftool_helper.dart';
import 'photo_adjustments.dart';
import 'photo_tone_base.dart';

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
    required this.cropLeft,
    required this.cropTop,
    required this.cropWidth,
    required this.cropHeight,
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
  final double cropLeft;
  final double cropTop;
  final double cropWidth;
  final double cropHeight;
}

/// Decodes [request] bytes, bakes orientation, grades, and returns a JPEG.
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
  );
  var oriented = orientedImage;
  final fullFrame = request.cropLeft <= 0.0005 &&
      request.cropTop <= 0.0005 &&
      request.cropWidth >= 0.999 &&
      request.cropHeight >= 0.999;
  if (!fullFrame) {
    final x = (request.cropLeft * oriented.width)
        .round()
        .clamp(0, oriented.width - 1);
    final y = (request.cropTop * oriented.height)
        .round()
        .clamp(0, oriented.height - 1);
    var width = (request.cropWidth * oriented.width).round();
    var height = (request.cropHeight * oriented.height).round();
    if (width < 1) width = 1;
    if (height < 1) height = 1;
    oriented = img.copyCrop(
      oriented,
      x: x,
      y: y,
      width: width,
      height: height,
    );
  }
  if (!grade.isNeutral) {
    Float32List? base;
    var baseWidth = 0;
    var baseHeight = 0;
    if (grade.needsLocalTone) {
      final small = _toneBaseSource(oriented);
      final rgb = Uint8List(small.width * small.height * 3);
      var index = 0;
      for (final pixel in small) {
        rgb[index++] = (pixel.rNormalized.toDouble() * 255).round().clamp(0, 255);
        rgb[index++] = (pixel.gNormalized.toDouble() * 255).round().clamp(0, 255);
        rgb[index++] = (pixel.bNormalized.toDouble() * 255).round().clamp(0, 255);
      }
      base = lumaBaseForDisplayRgb(rgb, small.width, small.height, grade);
      baseWidth = small.width;
      baseHeight = small.height;
    }
    var pixelIndex = 0;
    for (final pixel in oriented) {
      final x = pixelIndex % oriented.width;
      final y = pixelIndex ~/ oriented.width;
      pixelIndex++;
      final baseLuma = base == null
          ? null
          : sampleLumaBase(
              base,
              baseWidth,
              baseHeight,
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
        baseLuma: baseLuma,
      );
      pixel
        ..rNormalized = graded.r
        ..gNormalized = graded.g
        ..bNormalized = graded.b;
    }
  }
  return Uint8List.fromList(img.encodeJpg(oriented, quality: 92));
}

/// Writes a graded JPEG over [path], copying caption and camera metadata
/// back on with exiftool. Pixels are stored upright, so orientation is reset.
Future<void> writeGradedJpeg({
  required String path,
  required PhotoAdjustments adjustments,
  double cropLeft = 0,
  double cropTop = 0,
  double cropWidth = 1,
  double cropHeight = 1,
}) async {
  final lower = p.extension(path).toLowerCase();
  if (lower != '.jpg' && lower != '.jpeg') {
    throw StateError('Only JPEG photos can be edited.');
  }
  final original = await File(path).readAsBytes();
  final graded = await compute(
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
      cropLeft: cropLeft,
      cropTop: cropTop,
      cropWidth: cropWidth,
      cropHeight: cropHeight,
    ),
  );

  final temp = File(
    p.join(
      Directory.systemTemp.path,
      'flofile-grade-${DateTime.now().microsecondsSinceEpoch}.jpg',
    ),
  );
  final staged = File('$path.flofile-grade');
  try {
    await temp.writeAsBytes(graded, flush: true);
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

img.Image _toneBaseSource(img.Image source) {
  const maxEdge = 1280;
  if (source.width <= maxEdge && source.height <= maxEdge) return source;
  if (source.width >= source.height) {
    return img.copyResize(source, width: maxEdge);
  }
  return img.copyResize(source, height: maxEdge);
}
