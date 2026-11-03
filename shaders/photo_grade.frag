#version 460 core

#include <flutter/runtime_effect.glsl>

// Camera Raw–style grade. Keep formulas in sync with photo_adjustments.dart
// and constants in photo_adjust_config.dart.
//
// Pipeline (linear RGB):
//   1 sRGB→linear  2 WB  3 Exposure  4 Contrast
//   5 Highlights/Shadows (mask)  6 Whites/Blacks
//   7 Vibrance/Saturation  8 Soft shoulder
//   9 linear→sRGB  10 ordered dither

uniform float uDestLeft;
uniform float uDestTop;
uniform float uDestWidth;
uniform float uDestHeight;
uniform float uTemperature;   // eased −1…1
uniform float uTint;          // eased −1…1
uniform float uExposure;      // stops
uniform float uContrast;      // eased −1…1
uniform float uHighlights;    // eased −1…1
uniform float uShadows;       // eased −1…1
uniform float uWhites;        // eased −1…1
uniform float uBlacks;        // eased −1…1
uniform float uVibrance;      // eased −1…1
uniform float uSaturation;    // eased −1…1
uniform float uHasMask;       // 1 when local tone mask is bound
uniform float uDebugMask;     // 1 = show mask instead of graded image
uniform float uDither;        // 1 = apply ±0.5/255 ordered dither
uniform float uCropLeft;
uniform float uCropTop;
uniform float uCropWidth;
uniform float uCropHeight;
// Tunables mirrored from PhotoAdjustConfig (so one place in Dart can push them).
uniform float uTempStrength;
uniform float uTintStrength;
uniform float uContrastPivot;
uniform float uContrastStrength;
uniform float uHiMaskLo;
uniform float uHiMaskHi;
uniform float uShMaskLo;
uniform float uShMaskHi;
uniform float uLocalToneStrength;
uniform float uWhitesStart;
uniform float uWhitesAmount;
uniform float uBlacksEnd;
uniform float uBlacksAmount;
uniform float uVibranceAmount;
uniform float uSaturationAmount;
uniform float uSkinHueCenter;
uniform float uSkinHueWidth;
uniform float uSkinVibranceScale;
uniform float uShoulderKnee;
uniform float uShoulderRoom;
uniform float uDitherAmp;
uniform float uMaskBlend;     // 0.8 filtered + 0.2 sharp already baked into mask tex

uniform sampler2D uTex;
uniform sampler2D uMask;

out vec4 fragColor;

const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);

float srgbToLinear(float c) {
  // Piecewise sRGB EOTF — not pow(c, 2.2).
  return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

float linearToSrgb(float c) {
  if (c <= 0.0) return 0.0;
  return (c <= 0.0031308) ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

float gradeSmoothstep(float edge0, float edge1, float x) {
  float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

// Unpack ~16-bit value stored in R/G of the mask texture.
float unpackMask(vec4 texel) {
  return (texel.r * 255.0 * 256.0 + texel.g * 255.0) / 65535.0;
}

vec3 whiteBalance(vec3 c, float temperature, float tint) {
  if (abs(temperature) < 1e-6 && abs(tint) < 1e-6) return c;
  vec3 gain = vec3(
    max(1.0 + uTempStrength * temperature, 1e-4),
    max(1.0 - uTintStrength * tint, 1e-4),
    max(1.0 - uTempStrength * temperature, 1e-4)
  );
  // Renormalize so overall luminance is preserved.
  float y = dot(gain, kLuma);
  gain /= max(y, 1e-4);
  return c * gain;
}

// Contrast: stretch log2 stops about mid-grey, then rescale RGB (preserve hue).
vec3 applyContrast(vec3 c, float amount) {
  if (abs(amount) < 1e-6) return c;
  float y = dot(max(c, 0.0), kLuma);
  if (y <= 1e-8) return c;
  float stops = log2(y / uContrastPivot);
  float shaped = stops * (1.0 + uContrastStrength * amount);
  float y2 = max(0.0, uContrastPivot * exp2(shaped));
  return c * (y2 / y);
}

vec3 applyLocalTone(vec3 c, float mask01, float highlights, float shadows) {
  if (abs(highlights) < 1e-6 && abs(shadows) < 1e-6) return c;
  float hiW = gradeSmoothstep(uHiMaskLo, uHiMaskHi, mask01);
  float shW = 1.0 - gradeSmoothstep(uShMaskLo, uShMaskHi, mask01);
  // Negative highlights darken brights; positive shadows lift darks.
  float stops = hiW * highlights * uLocalToneStrength
              + shW * shadows * uLocalToneStrength;
  return c * exp2(stops);
}

vec3 applyWhitesBlacks(vec3 c, float whites, float blacks) {
  if (abs(whites) < 1e-6 && abs(blacks) < 1e-6) return c;
  float y = dot(max(c, 0.0), kLuma);
  float x = y;
  if (abs(blacks) >= 1e-6) {
    float knee = 1.0 - gradeSmoothstep(0.0, uBlacksEnd, x);
    if (blacks > 0.0) x += blacks * uBlacksAmount * knee;
    else x *= 1.0 + blacks * knee;
  }
  if (abs(whites) >= 1e-6) {
    float knee = gradeSmoothstep(uWhitesStart, 1.0, x);
    x += whites * uWhitesAmount * knee;
  }
  x = max(x, 0.0);
  if (y < 1e-8) return c;
  return c * (x / y);
}

float hueDegrees(vec3 c) {
  float maxC = max(c.r, max(c.g, c.b));
  float minC = min(c.r, min(c.g, c.b));
  float d = maxC - minC;
  if (d < 1e-8) return 0.0;
  float h;
  if (maxC == c.r) h = mod((c.g - c.b) / d, 6.0);
  else if (maxC == c.g) h = (c.b - c.r) / d + 2.0;
  else h = (c.r - c.g) / d + 4.0;
  h *= 60.0;
  if (h < 0.0) h += 360.0;
  return h;
}

float chroma(vec3 c, float y) {
  vec3 d = c - vec3(y);
  return sqrt(dot(d, d));
}

vec3 applyVibranceSaturation(vec3 c, float vibrance, float saturation) {
  if (abs(vibrance) < 1e-6 && abs(saturation) < 1e-6) return c;
  float y = dot(max(c, 0.0), kLuma);
  vec3 outc = c;

  if (abs(vibrance) >= 1e-6) {
    float sat = chroma(outc, y);
    float lowSatWeight = 1.0 - clamp(sat * 2.5, 0.0, 1.0);
    float hue = hueDegrees(outc);
    float skinDist = min(abs(hue - uSkinHueCenter), 360.0 - abs(hue - uSkinHueCenter));
    float skin = 1.0 - gradeSmoothstep(0.0, uSkinHueWidth, skinDist);
    float skinScale = pow(uSkinVibranceScale, skin);
    float amount = vibrance * uVibranceAmount * lowSatWeight * skinScale;
    outc = vec3(y) + (outc - vec3(y)) * (1.0 + amount);
  }

  if (abs(saturation) >= 1e-6) {
    float amount = saturation * uSaturationAmount;
    outc = vec3(y) + (outc - vec3(y)) * (1.0 + amount);
  }
  return outc;
}

// Soft highlight shoulder, hue-preserving via max-channel scale.
vec3 softShoulder(vec3 c) {
  float m = max(c.r, max(c.g, c.b));
  if (m <= uShoulderKnee || m < 1e-8) return c;
  float over = m - uShoulderKnee;
  float m2 = uShoulderKnee + over / (1.0 + over / uShoulderRoom);
  return c * (m2 / m);
}

// Bayer 4×4 → −1…1
float bayerDither(vec2 frag) {
  int x = int(mod(floor(frag.x), 4.0));
  int y = int(mod(floor(frag.y), 4.0));
  // 4×4 Bayer matrix / 16 − 0.5, then *2 → −1…1
  int idx = y * 4 + x;
  float v = 0.0;
  if (idx == 0) v = 0.0;
  else if (idx == 1) v = 8.0;
  else if (idx == 2) v = 2.0;
  else if (idx == 3) v = 10.0;
  else if (idx == 4) v = 12.0;
  else if (idx == 5) v = 4.0;
  else if (idx == 6) v = 14.0;
  else if (idx == 7) v = 6.0;
  else if (idx == 8) v = 3.0;
  else if (idx == 9) v = 11.0;
  else if (idx == 10) v = 1.0;
  else if (idx == 11) v = 9.0;
  else if (idx == 12) v = 15.0;
  else if (idx == 13) v = 7.0;
  else if (idx == 14) v = 13.0;
  else v = 5.0;
  return (v / 16.0 - 0.5) * 2.0;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = (frag - vec2(uDestLeft, uDestTop)) / vec2(uDestWidth, uDestHeight);
  uv = vec2(uCropLeft, uCropTop) + uv * vec2(uCropWidth, uCropHeight);

  // Mask is sampled with the sampler's LINEAR filter (never nearest).
  float mask01 = 0.5;
  if (uHasMask > 0.5) {
    mask01 = unpackMask(texture(uMask, uv));
  }

  if (uDebugMask > 0.5) {
    fragColor = vec4(vec3(mask01), 1.0);
    return;
  }

  vec4 src = texture(uTex, uv);
  vec3 lin = vec3(srgbToLinear(src.r), srgbToLinear(src.g), srgbToLinear(src.b));

  lin = whiteBalance(lin, uTemperature, uTint);
  lin *= exp2(uExposure);
  lin = applyContrast(lin, uContrast);
  lin = applyLocalTone(lin, mask01, uHighlights, uShadows);
  lin = applyWhitesBlacks(lin, uWhites, uBlacks);
  lin = applyVibranceSaturation(lin, uVibrance, uSaturation);
  lin = softShoulder(lin);

  vec3 srgb = vec3(
    linearToSrgb(lin.r),
    linearToSrgb(lin.g),
    linearToSrgb(lin.b)
  );

  if (uDither > 0.5) {
    float d = bayerDither(frag) * uDitherAmp;
    srgb += vec3(d);
  }

  fragColor = vec4(clamp(srgb, 0.0, 1.0), src.a);
}
