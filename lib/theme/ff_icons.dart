import 'package:flutter/material.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Shared Phosphor icon sizes and common action icons for FloFile UI.
///
/// Prefer [ffIcon] / these [IconData] constants over Material [Icons].
/// Omit [color] so icons inherit surrounding text / [IconTheme], except when
/// the icon encodes status (saved, danger, firebar, gold favourite).
abstract class FfIcons {
  FfIcons._();

  static const double size = 18;
  static const double toolbarSize = 16;

  // Common actions
  static const IconData trash = PhosphorIconsRegular.trash;
  static const IconData copy = PhosphorIconsRegular.copy;
  static const IconData moveCategory = PhosphorIconsRegular.arrowBendUpRight;
  static const IconData rename = PhosphorIconsRegular.pencilSimple;
  static const IconData edit = PhosphorIconsRegular.pencilSimple;
  static const IconData star = PhosphorIconsRegular.star;
  static const IconData starFill = PhosphorIconsFill.star;
  static const IconData search = PhosphorIconsRegular.magnifyingGlass;
  static const IconData reload = PhosphorIconsRegular.arrowClockwise;
  static const IconData close = PhosphorIconsRegular.x;
  static const IconData add = PhosphorIconsRegular.plus;
  static const IconData remove = PhosphorIconsRegular.minus;
  static const IconData settings = PhosphorIconsRegular.gear;
  static const IconData check = PhosphorIconsRegular.check;
  static const IconData pin = PhosphorIconsRegular.pushPin;
  static const IconData pinFill = PhosphorIconsFill.pushPin;
  static const IconData upload = PhosphorIconsRegular.cloudArrowUp;
  static const IconData caretDown = PhosphorIconsRegular.caretDown;
  static const IconData caretUp = PhosphorIconsRegular.caretUp;
  static const IconData caretLeft = PhosphorIconsRegular.caretLeft;
  static const IconData caretRight = PhosphorIconsRegular.caretRight;
  static const IconData drag = PhosphorIconsRegular.dotsSixVertical;
  static const IconData folder = PhosphorIconsRegular.folder;
  static const IconData folderOpen = PhosphorIconsRegular.folderOpen;
  static const IconData history = PhosphorIconsRegular.clockCounterClockwise;
  static const IconData paste = PhosphorIconsRegular.clipboardText;
  static const IconData fileText = PhosphorIconsRegular.fileText;
  static const IconData save = PhosphorIconsRegular.floppyDisk;
  static const IconData lock = PhosphorIconsRegular.lock;
  static const IconData eye = PhosphorIconsRegular.eye;
  static const IconData eyeSlash = PhosphorIconsRegular.eyeSlash;
  static const IconData warning = PhosphorIconsRegular.warning;
  static const IconData info = PhosphorIconsRegular.info;
  static const IconData flame = PhosphorIconsRegular.flame;
}

/// Phosphor icon with FloFile default size (18). Pass [toolbar] for size 16.
/// Omit [color] unless the icon encodes status.
PhosphorIcon ffIcon(
  IconData icon, {
  Key? key,
  double? size,
  bool toolbar = false,
  Color? color,
  String? semanticLabel,
}) {
  return PhosphorIcon(
    icon,
    key: key,
    size: size ?? (toolbar ? FfIcons.toolbarSize : FfIcons.size),
    color: color,
    semanticLabel: semanticLabel,
  );
}
