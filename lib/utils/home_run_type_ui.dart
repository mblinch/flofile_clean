/// Compact chip labels for Home Run type (narrow sidebars / Keyboard Fire).
/// Canonical values remain Solo / Two-Run / Three-Run / Grand Slam.
String shortHomeRunTypeLabel(String type) {
  switch (type) {
    case 'Solo':
      return '1R';
    case 'Two-Run':
      return '2R';
    case 'Three-Run':
      return '3R';
    case 'Grand Slam':
      return 'GS';
    default:
      return type;
  }
}
