import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'photo_adjust_config.dart';
import 'photo_adjustments.dart';
import 'photo_crop.dart';
import 'photo_tone_base.dart';

/// Loads and caches FragmentPrograms for the grade pipeline.
class PhotoGradeShaders {
  PhotoGradeShaders._();

  static ui.FragmentProgram? grade;
  static ui.FragmentProgram? maskLuma;
  static ui.FragmentProgram? boxBlur;
  static ui.FragmentProgram? maskSquare;
  static ui.FragmentProgram? guidedAb;
  static ui.FragmentProgram? guidedCompose;
  static ui.Image? placeholder;
  static Future<void>? _loading;

  static Future<void> ensure() {
    return _loading ??= () async {
      try {
        grade = await ui.FragmentProgram.fromAsset('shaders/photo_grade.frag');
        maskLuma =
            await ui.FragmentProgram.fromAsset('shaders/photo_mask_luma.frag');
        boxBlur =
            await ui.FragmentProgram.fromAsset('shaders/photo_box_blur.frag');
        maskSquare =
            await ui.FragmentProgram.fromAsset('shaders/photo_mask_square.frag');
        guidedAb =
            await ui.FragmentProgram.fromAsset('shaders/photo_guided_ab.frag');
        guidedCompose = await ui.FragmentProgram.fromAsset(
          'shaders/photo_guided_compose.frag',
        );
        placeholder ??= await _solidPixel();
      } catch (e, st) {
        debugPrint('PhotoGradeShaders load failed: $e\n$st');
        grade = null;
      }
    }();
  }

  static Future<ui.Image> _solidPixel() async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      Uint8List.fromList(const [0, 0, 0, 255]),
    );
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: 1,
      height: 1,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  }
}

/// GPU grade + guided-filter mask. Preview and export share the same shaders.
class PhotoGradeEngine {
  PhotoGradeEngine();

  int _frameToken = 0;

  /// Bumps when a newer request supersedes an in-flight mask/export.
  int get frameToken => _frameToken;

  int beginFrame() => ++_frameToken;

  bool isStale(int token) => token != _frameToken;

  /// Long-edge size for a preview of [source], capped by [displayLongEdge].
  static int previewEdge(int srcW, int srcH, {int? displayLongEdge}) {
    final srcLong = math.max(srcW, srcH);
    final display = displayLongEdge ?? PhotoAdjustConfig.previewLongEdge;
    return math.min(srcLong, math.min(display, PhotoAdjustConfig.previewLongEdge));
  }

  static (int, int) sizeForLongEdge(int w, int h, int longEdge) {
    final srcLong = math.max(w, h);
    if (srcLong <= longEdge) return (w, h);
    final scale = longEdge / srcLong;
    return (
      math.max(1, (w * scale).round()),
      math.max(1, (h * scale).round()),
    );
  }

  /// Decode [bytes] scaled so the long edge is ≤ [longEdge].
  static Future<ui.Image> decodeScaled(Uint8List bytes, int longEdge) async {
    ui.Codec codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      var image = frame.image;
      final long = math.max(image.width, image.height);
      if (long <= longEdge) return image;
      final wide = image.width >= image.height;
      image.dispose();
      codec.dispose();
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: wide ? longEdge : null,
        targetHeight: wide ? null : longEdge,
      );
      final scaled = await codec.getNextFrame();
      return scaled.image;
    } finally {
      codec.dispose();
    }
  }

  /// Build the perceptual H/S mask (packed RG ~16-bit) on the GPU.
  ///
  /// Computed at ≥ 1/4 of [source] resolution. Sample later with LINEAR.
  Future<ui.Image?> buildMask({
    required ui.Image source,
    required PhotoAdjustments adjustments,
    required int token,
  }) async {
    await PhotoGradeShaders.ensure();
    if (PhotoGradeShaders.maskLuma == null) return null;
    if (isStale(token)) return null;

    final maskW = math.max(
      1,
      (source.width * PhotoAdjustConfig.maskResolutionScale).round(),
    );
    final maskH = math.max(
      1,
      (source.height * PhotoAdjustConfig.maskResolutionScale).round(),
    );
    final radius = math.max(
      1.0,
      maskW * PhotoAdjustConfig.guidedRadiusWidthFraction,
    );
    final p = adjustments.eased;

    // 1) Log-luma after WB / exposure / contrast.
    var sharp = await _drawPass(
      program: PhotoGradeShaders.maskLuma!,
      width: maskW,
      height: maskH,
      setup: (s) {
        var i = 0;
        s.setFloat(i++, maskW.toDouble());
        s.setFloat(i++, maskH.toDouble());
        s.setFloat(i++, p.temperature);
        s.setFloat(i++, p.tint);
        s.setFloat(i++, p.exposure);
        s.setFloat(i++, p.contrast);
        s.setFloat(i++, PhotoAdjustConfig.tempStrengthPos);
        s.setFloat(i++, PhotoAdjustConfig.tempStrengthNeg);
        s.setFloat(i++, PhotoAdjustConfig.tintStrengthPos);
        s.setFloat(i++, PhotoAdjustConfig.tintStrengthNeg);
        s.setFloat(i++, PhotoAdjustConfig.contrastPivot);
        s.setFloat(i++, PhotoAdjustConfig.contrastStrengthLo);
        s.setFloat(i++, PhotoAdjustConfig.contrastStrengthHi);
        s.setFloat(i++, PhotoAdjustConfig.contrastFadeLo);
        s.setFloat(i++, PhotoAdjustConfig.contrastFadeHi);
        s.setFloat(i++, PhotoAdjustConfig.maskLogMin);
        s.setFloat(i++, PhotoAdjustConfig.maskLogMax);
        s.setImageSampler(0, source);
      },
    );
    if (isStale(token)) {
      sharp.dispose();
      return null;
    }

    // 2) meanI = box(I)
    final meanI = await _boxBlur2D(sharp, maskW, maskH, radius, token);
    if (meanI == null) {
      sharp.dispose();
      return null;
    }

    // 3) I² then meanI2 = box(I²)
    final squared = await _drawPass(
      program: PhotoGradeShaders.maskSquare!,
      width: maskW,
      height: maskH,
      setup: (s) {
        s.setFloat(0, maskW.toDouble());
        s.setFloat(1, maskH.toDouble());
        s.setImageSampler(0, sharp);
      },
    );
    if (isStale(token)) {
      sharp.dispose();
      meanI.dispose();
      squared.dispose();
      return null;
    }
    final meanI2 = await _boxBlur2D(squared, maskW, maskH, radius, token);
    squared.dispose();
    if (meanI2 == null) {
      sharp.dispose();
      meanI.dispose();
      return null;
    }

    // 4) a, b
    final ab = await _drawPass(
      program: PhotoGradeShaders.guidedAb!,
      width: maskW,
      height: maskH,
      setup: (s) {
        var i = 0;
        s.setFloat(i++, maskW.toDouble());
        s.setFloat(i++, maskH.toDouble());
        s.setFloat(i++, PhotoAdjustConfig.guidedEps);
        s.setFloat(i++, PhotoAdjustConfig.maskLogMin);
        s.setFloat(i++, PhotoAdjustConfig.maskLogMax);
        s.setImageSampler(0, meanI);
        s.setImageSampler(1, meanI2);
      },
    );
    meanI.dispose();
    meanI2.dispose();
    if (isStale(token)) {
      sharp.dispose();
      ab.dispose();
      return null;
    }

    // 5) meanA, meanB from AB texture (RG = a, BA = b)
    final meanA = await _boxBlur2D(
      ab,
      maskW,
      maskH,
      radius,
      token,
      useBA: false,
    );
    final meanB = await _boxBlur2D(
      ab,
      maskW,
      maskH,
      radius,
      token,
      useBA: true,
    );
    ab.dispose();
    if (meanA == null || meanB == null) {
      sharp.dispose();
      meanA?.dispose();
      meanB?.dispose();
      return null;
    }

    // 6) Compose perceptual mask.
    final mask = await _drawPass(
      program: PhotoGradeShaders.guidedCompose!,
      width: maskW,
      height: maskH,
      setup: (s) {
        var i = 0;
        s.setFloat(i++, maskW.toDouble());
        s.setFloat(i++, maskH.toDouble());
        s.setFloat(i++, PhotoAdjustConfig.maskLogMin);
        s.setFloat(i++, PhotoAdjustConfig.maskLogMax);
        s.setFloat(i++, PhotoAdjustConfig.maskFilterBlend);
        s.setImageSampler(0, sharp);
        s.setImageSampler(1, meanA);
        s.setImageSampler(2, meanB);
      },
    );
    sharp.dispose();
    meanA.dispose();
    meanB.dispose();
    if (isStale(token)) {
      mask.dispose();
      return null;
    }
    return mask;
  }

  /// CPU fallback mask (same math) when GPU mask programs fail to load.
  Future<ui.Image?> buildMaskCpu({
    required ui.Image source,
    required PhotoAdjustments adjustments,
    required int token,
  }) async {
    final maskW = math.max(
      1,
      (source.width * PhotoAdjustConfig.maskResolutionScale).round(),
    );
    final maskH = math.max(
      1,
      (source.height * PhotoAdjustConfig.maskResolutionScale).round(),
    );
    final scaled = await _resizeImage(source, maskW, maskH);
    if (isStale(token)) {
      scaled.dispose();
      return null;
    }
    final data = await scaled.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = scaled.width;
    final h = scaled.height;
    scaled.dispose();
    if (data == null || isStale(token)) return null;
    final rgba = data.buffer.asUint8List();
    final rgb = Uint8List(w * h * 3);
    for (var i = 0; i < w * h; i++) {
      rgb[i * 3] = rgba[i * 4];
      rgb[i * 3 + 1] = rgba[i * 4 + 1];
      rgb[i * 3 + 2] = rgba[i * 4 + 2];
    }
    final mask = lumaMaskForDisplayRgb(rgb, w, h, adjustments);
    final packed = Uint8List(w * h * 4);
    for (var i = 0; i < w * h; i++) {
      packFloat01(mask[i], packed, i * 4);
    }
    return _imageFromRgba(packed, w, h);
  }

  Future<ui.Image?> _boxBlur2D(
    ui.Image src,
    int w,
    int h,
    double radius,
    int token, {
    bool useBA = false,
  }) async {
    final prog = PhotoGradeShaders.boxBlur;
    if (prog == null) return null;
    final tmp = await _drawPass(
      program: prog,
      width: w,
      height: h,
      setup: (s) {
        var i = 0;
        s.setFloat(i++, w.toDouble());
        s.setFloat(i++, h.toDouble());
        s.setFloat(i++, radius);
        s.setFloat(i++, 1); // horizontal
        s.setFloat(i++, useBA ? 1 : 0);
        s.setImageSampler(0, src);
      },
    );
    if (isStale(token)) {
      tmp.dispose();
      return null;
    }
    final out = await _drawPass(
      program: prog,
      width: w,
      height: h,
      setup: (s) {
        var i = 0;
        s.setFloat(i++, w.toDouble());
        s.setFloat(i++, h.toDouble());
        s.setFloat(i++, radius);
        s.setFloat(i++, 0); // vertical
        s.setFloat(i++, 0); // RG of tmp
        s.setImageSampler(0, tmp);
      },
    );
    tmp.dispose();
    if (isStale(token)) {
      out.dispose();
      return null;
    }
    return out;
  }

  /// Bind grade uniforms onto [shader] for a live CustomPaint or offscreen pass.
  static void bindGradeUniforms(
    ui.FragmentShader shader, {
    required ui.Image image,
    required ui.Image? mask,
    required PhotoAdjustments adjustments,
    required PhotoCrop crop,
    required ui.Rect dest,
    bool debugMask = false,
    bool dither = true,
  }) {
    final p = adjustments.eased;
    var i = 0;
    shader.setFloat(i++, dest.left);
    shader.setFloat(i++, dest.top);
    shader.setFloat(i++, dest.width);
    shader.setFloat(i++, dest.height);
    shader.setFloat(i++, p.temperature);
    shader.setFloat(i++, p.tint);
    shader.setFloat(i++, p.exposure);
    shader.setFloat(i++, p.contrast);
    shader.setFloat(i++, p.highlights);
    shader.setFloat(i++, p.shadows);
    shader.setFloat(i++, p.whites);
    shader.setFloat(i++, p.blacks);
    shader.setFloat(i++, p.vibrance);
    shader.setFloat(i++, p.saturation);
    shader.setFloat(i++, mask == null ? 0 : 1);
    shader.setFloat(i++, debugMask ? 1 : 0);
    shader.setFloat(i++, dither ? 1 : 0);
    shader.setFloat(i++, crop.left);
    shader.setFloat(i++, crop.top);
    shader.setFloat(i++, crop.width);
    shader.setFloat(i++, crop.height);
    shader.setFloat(i++, PhotoAdjustConfig.tempStrengthPos);
    shader.setFloat(i++, PhotoAdjustConfig.tempStrengthNeg);
    shader.setFloat(i++, PhotoAdjustConfig.tintStrengthPos);
    shader.setFloat(i++, PhotoAdjustConfig.tintStrengthNeg);
    shader.setFloat(i++, PhotoAdjustConfig.contrastPivot);
    shader.setFloat(i++, PhotoAdjustConfig.contrastStrengthLo);
    shader.setFloat(i++, PhotoAdjustConfig.contrastStrengthHi);
    shader.setFloat(i++, PhotoAdjustConfig.contrastFadeLo);
    shader.setFloat(i++, PhotoAdjustConfig.contrastFadeHi);
    shader.setFloat(i++, PhotoAdjustConfig.highlightMaskLo);
    shader.setFloat(i++, PhotoAdjustConfig.highlightMaskHi);
    shader.setFloat(i++, PhotoAdjustConfig.highlightFadeLo);
    shader.setFloat(i++, PhotoAdjustConfig.highlightFadeHi);
    shader.setFloat(i++, PhotoAdjustConfig.highlightStrengthNeg);
    shader.setFloat(i++, PhotoAdjustConfig.highlightStrengthPos);
    shader.setFloat(i++, PhotoAdjustConfig.shadowMaskPower);
    shader.setFloat(i++, PhotoAdjustConfig.shadowFadeLo);
    shader.setFloat(i++, PhotoAdjustConfig.shadowFadeHi);
    shader.setFloat(i++, PhotoAdjustConfig.shadowStrengthPos);
    shader.setFloat(i++, PhotoAdjustConfig.shadowStrengthNeg);
    shader.setFloat(i++, PhotoAdjustConfig.whitesMaskLo);
    shader.setFloat(i++, PhotoAdjustConfig.whitesMaskHi);
    shader.setFloat(i++, PhotoAdjustConfig.whitesFadeLo);
    shader.setFloat(i++, PhotoAdjustConfig.whitesFadeHi);
    shader.setFloat(i++, PhotoAdjustConfig.whitesAmount);
    shader.setFloat(i++, PhotoAdjustConfig.blacksEnd);
    shader.setFloat(i++, PhotoAdjustConfig.blacksMaskPower);
    shader.setFloat(i++, PhotoAdjustConfig.blacksAmountPos);
    shader.setFloat(i++, PhotoAdjustConfig.blacksAmountNeg);
    shader.setFloat(i++, PhotoAdjustConfig.vibranceAmountPos);
    shader.setFloat(i++, PhotoAdjustConfig.vibranceAmountNeg);
    shader.setFloat(i++, PhotoAdjustConfig.vibranceChromaFadeLo);
    shader.setFloat(i++, PhotoAdjustConfig.vibranceChromaFadeHi);
    shader.setFloat(i++, PhotoAdjustConfig.vibranceChromaFloorNeg);
    shader.setFloat(i++, PhotoAdjustConfig.saturationAmountPos);
    shader.setFloat(i++, PhotoAdjustConfig.saturationAmountNeg);
    shader.setFloat(i++, PhotoAdjustConfig.saturationChromaFadeLo);
    shader.setFloat(i++, PhotoAdjustConfig.saturationChromaFadeHi);
    shader.setFloat(i++, PhotoAdjustConfig.skinHueCenter);
    shader.setFloat(i++, PhotoAdjustConfig.skinHueWidth);
    shader.setFloat(i++, PhotoAdjustConfig.skinVibranceScale);
    shader.setFloat(i++, PhotoAdjustConfig.shoulderKnee);
    shader.setFloat(i++, PhotoAdjustConfig.shoulderRoom);
    shader.setFloat(i++, PhotoAdjustConfig.ditherAmplitude);
    shader.setFloat(i++, PhotoAdjustConfig.maskFilterBlend);
    shader.setImageSampler(0, image);
    shader.setImageSampler(
      1,
      mask ?? PhotoGradeShaders.placeholder ?? image,
    );
  }

  /// Render a full graded frame (or tile) to a [ui.Image].
  Future<ui.Image?> renderGrade({
    required ui.Image source,
    required ui.Image? mask,
    required PhotoAdjustments adjustments,
    PhotoCrop crop = PhotoCrop.full,
    bool debugMask = false,
    bool dither = true,
    int? token,
  }) async {
    await PhotoGradeShaders.ensure();
    final program = PhotoGradeShaders.grade;
    if (program == null) return null;
    if (token != null && isStale(token)) return null;

    final w = source.width;
    final h = source.height;
    final shader = program.fragmentShader();
    try {
      bindGradeUniforms(
        shader,
        image: source,
        mask: mask,
        adjustments: adjustments,
        crop: crop,
        dest: ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        debugMask: debugMask,
        dither: dither,
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ui.Paint()..shader = shader,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(w, h);
      picture.dispose();
      if (token != null && isStale(token)) {
        image.dispose();
        return null;
      }
      return image;
    } finally {
      shader.dispose();
    }
  }

  /// Full-resolution export. Tiles when the frame exceeds the GPU texture cap.
  Future<Uint8List?> exportRgba({
    required Uint8List jpegBytes,
    required PhotoAdjustments adjustments,
    PhotoCrop crop = PhotoCrop.full,
    void Function(double progress)? onProgress,
  }) async {
    await PhotoGradeShaders.ensure();
    if (PhotoGradeShaders.grade == null) return null;

    final token = beginFrame();
    final full = await decodeScaled(jpegBytes, 1 << 30); // native size
    if (isStale(token)) {
      full.dispose();
      return null;
    }

    // Work in the oriented full buffer; crop is applied in the shader UVs.
    final outW = math.max(1, (full.width * crop.width).round());
    final outH = math.max(1, (full.height * crop.height).round());

    ui.Image? mask;
    if (adjustments.needsLocalTone) {
      mask = await buildMask(
        source: full,
        adjustments: adjustments,
        token: token,
      );
      mask ??= await buildMaskCpu(
        source: full,
        adjustments: adjustments,
        token: token,
      );
    }
    if (isStale(token)) {
      full.dispose();
      mask?.dispose();
      return null;
    }

    final needsTiles = full.width > PhotoAdjustConfig.maxTextureEdge ||
        full.height > PhotoAdjustConfig.maxTextureEdge ||
        outW * outH > PhotoAdjustConfig.maxTextureEdge *
            PhotoAdjustConfig.maxTextureEdge;

    if (!needsTiles && crop.isFull) {
      final graded = await renderGrade(
        source: full,
        mask: mask,
        adjustments: adjustments,
        crop: crop,
        dither: true,
        token: token,
      );
      full.dispose();
      mask?.dispose();
      if (graded == null) return null;
      final data = await graded.toByteData(format: ui.ImageByteFormat.rawRgba);
      graded.dispose();
      onProgress?.call(1);
      return data?.buffer.asUint8List();
    }

    // Tiled path: render overlapping full-frame grade via crop UV windows.
    const tile = PhotoAdjustConfig.exportTileEdge;
    final out = Uint8List(outW * outH * 4);
    var done = 0;
    final tilesX = (outW + tile - 1) ~/ tile;
    final tilesY = (outH + tile - 1) ~/ tile;
    final total = tilesX * tilesY;

    for (var ty = 0; ty < outH; ty += tile) {
      for (var tx = 0; tx < outW; tx += tile) {
        if (isStale(token)) {
          full.dispose();
          mask?.dispose();
          return null;
        }
        final tw = math.min(tile, outW - tx);
        final th = math.min(tile, outH - ty);
        final tileCrop = PhotoCrop(
          left: crop.left + crop.width * tx / outW,
          top: crop.top + crop.height * ty / outH,
          width: crop.width * tw / outW,
          height: crop.height * th / outH,
        );
        // Render by drawing the grade shader into a tw×th picture with
        // dest covering the whole tile and UVs = tileCrop.
        final program = PhotoGradeShaders.grade!;
        final shader = program.fragmentShader();
        bindGradeUniforms(
          shader,
          image: full,
          mask: mask,
          adjustments: adjustments,
          crop: tileCrop,
          dest: ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
          dither: true,
        );
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawRect(
          ui.Rect.fromLTWH(0, 0, tw.toDouble(), th.toDouble()),
          ui.Paint()..shader = shader,
        );
        final picture = recorder.endRecording();
        final tileImg = await picture.toImage(tw, th);
        picture.dispose();
        shader.dispose();
        final bytes =
            await tileImg.toByteData(format: ui.ImageByteFormat.rawRgba);
        tileImg.dispose();
        if (bytes == null) continue;
        final src = bytes.buffer.asUint8List();
        for (var row = 0; row < th; row++) {
          final dstOff = ((ty + row) * outW + tx) * 4;
          final srcOff = row * tw * 4;
          out.setRange(dstOff, dstOff + tw * 4, src, srcOff);
        }
        done++;
        onProgress?.call(done / total);
      }
    }

    full.dispose();
    mask?.dispose();
    return out;
  }

  static Future<ui.Image> _drawPass({
    required ui.FragmentProgram program,
    required int width,
    required int height,
    required void Function(ui.FragmentShader shader) setup,
  }) async {
    final shader = program.fragmentShader();
    try {
      setup(shader);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint()..shader = shader,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      picture.dispose();
      return image;
    } finally {
      shader.dispose();
    }
  }

  static Future<ui.Image> _resizeImage(ui.Image src, int w, int h) async {
    if (src.width == w && src.height == h) {
      // Caller owns src; duplicate via toByteData round-trip is heavy —
      // draw into a new picture instead so ownership stays clear.
    }
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      src,
      ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(w, h);
    picture.dispose();
    return image;
  }

  static Future<ui.Image> _imageFromRgba(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  }
}
