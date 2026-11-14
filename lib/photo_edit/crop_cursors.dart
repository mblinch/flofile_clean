import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'photo_crop.dart';

/// Custom crop-tool cursors (32×32 SVG, hotspot at centre 16,16).
///
/// Visuals only — hit testing stays in [cropHandleAt].
abstract final class CropCursors {
  static const size = 32.0;
  static const hotspot = 16.0;

  static const crosshair = 'assets/cursors/crosshair.svg';
  static const move = 'assets/cursors/move.svg';
  static const resizeEw = 'assets/cursors/resize-ew.svg';
  static const resizeNs = 'assets/cursors/resize-ns.svg';
  static const resizeNwse = 'assets/cursors/resize-nwse.svg';
  static const resizeNesw = 'assets/cursors/resize-nesw.svg';
  static const rotateTl = 'assets/cursors/rotate-tl.svg';
  static const rotateTr = 'assets/cursors/rotate-tr.svg';
  static const rotateBr = 'assets/cursors/rotate-br.svg';
  static const rotateBl = 'assets/cursors/rotate-bl.svg';

  static String rotateAssetFor(CropHandle corner) => switch (corner) {
        CropHandle.topLeft => rotateTl,
        CropHandle.topRight => rotateTr,
        CropHandle.bottomLeft => rotateBl,
        _ => rotateBr,
      };

  /// Asset for the active crop handle (and rotate corner when needed).
  static String assetFor(CropHandle? handle, {CropHandle? rotateCorner}) {
    return switch (handle) {
      CropHandle.topLeft || CropHandle.bottomRight => resizeNwse,
      CropHandle.topRight || CropHandle.bottomLeft => resizeNesw,
      CropHandle.top || CropHandle.bottom => resizeNs,
      CropHandle.left || CropHandle.right => resizeEw,
      CropHandle.move => move,
      CropHandle.rotate => rotateAssetFor(rotateCorner ?? CropHandle.bottomRight),
      null => crosshair,
    };
  }

  /// CSS-style system fallbacks when the SVG overlay isn't shown.
  static MouseCursor fallbackFor(CropHandle? handle) {
    return switch (handle) {
      CropHandle.rotate => SystemMouseCursors.grab,
      CropHandle.topLeft || CropHandle.bottomRight =>
        SystemMouseCursors.resizeUpLeftDownRight,
      CropHandle.topRight || CropHandle.bottomLeft =>
        SystemMouseCursors.resizeUpRightDownLeft,
      CropHandle.top || CropHandle.bottom => SystemMouseCursors.resizeUpDown,
      CropHandle.left || CropHandle.right => SystemMouseCursors.resizeLeftRight,
      CropHandle.move => SystemMouseCursors.move,
      null => SystemMouseCursors.precise,
    };
  }

  /// Draws the SVG cursor with its hotspot under [pointer].
  static Widget overlay({
    required Offset pointer,
    required CropHandle? handle,
    CropHandle? rotateCorner,
  }) {
    final asset = assetFor(handle, rotateCorner: rotateCorner);
    return Positioned(
      left: pointer.dx - hotspot,
      top: pointer.dy - hotspot,
      width: size,
      height: size,
      child: IgnorePointer(
        child: SvgPicture.asset(
          asset,
          width: size,
          height: size,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
