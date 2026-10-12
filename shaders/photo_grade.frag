#version 460 core

#include <flutter/runtime_effect.glsl>

// Keep in sync with gradeLinearRgb in photo_adjustments.dart.
uniform float uDestLeft;
uniform float uDestTop;
uniform float uDestWidth;
uniform float uDestHeight;
uniform float uExposure;
uniform float uContrast;
uniform float uShadows;
uniform float uHighlights;
uniform float uTemperature;
uniform float uTint;
uniform float uWhites;
uniform float uBlacks;
uniform float uHasBase;
uniform float uCropLeft;
uniform float uCropTop;
uniform float uCropWidth;
uniform float uCropHeight;

uniform sampler2D uTex;
uniform sampler2D uBase;

out vec4 fragColor;

const vec3 kLuma = vec3(0.2126729, 0.7151522, 0.0721750);
const float kLogMin = -13.287712379549449;
const float kLogMax = 2.0;

float srgbToLinear(float c) {
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

float temperatureKelvin(float slider) {
  float t = clamp(slider, -1.0, 1.0);
  if (abs(t) < 0.0005) return 6500.0;
  float curved = sign(t) * pow(abs(t), 1.6);
  if (curved >= 0.0) return 6500.0 * pow(2000.0 / 6500.0, curved);
  return 6500.0 * pow(50000.0 / 6500.0, -curved);
}

vec3 kelvinToRgb(float kelvin) {
  float k = clamp(kelvin, 1000.0, 50000.0) / 100.0;
  float r = (k <= 66.0)
      ? 1.0
      : clamp(1.2929361860620923 * pow(k - 60.0, -0.1332047592), 0.0, 1.0);
  float g = (k <= 66.0)
      ? clamp(0.3900815787690196 * log(k) - 0.6318414437886275, 0.0, 1.0)
      : clamp(1.129890860895294 * pow(k - 60.0, -0.0755148492), 0.0, 1.0);
  float b = 1.0;
  if (k < 66.0) {
    b = (k <= 19.0)
        ? 0.0
        : clamp(0.543206789110196 * log(k - 10.0) - 1.19625408914, 0.0, 1.0);
  }
  return vec3(r, g, b);
}

vec3 linearSrgbToXyz(vec3 c) {
  return vec3(
    dot(c, vec3(0.4124564, 0.3575761, 0.1804375)),
    dot(c, vec3(0.2126729, 0.7151522, 0.0721750)),
    dot(c, vec3(0.0193339, 0.1191920, 0.9503041))
  );
}

vec3 xyzToLinearSrgb(vec3 c) {
  return vec3(
    dot(c, vec3(3.2404542, -1.5371385, -0.4985314)),
    dot(c, vec3(-0.9692660, 1.8760108, 0.0415560)),
    dot(c, vec3(0.0556434, -0.2040259, 1.0572252))
  );
}

vec3 whiteBalanceGain(float temperature, float tint) {
  if (abs(temperature) < 0.0005 && abs(tint) < 0.0005) return vec3(1.0);
  vec3 gain = vec3(1.0);
  if (abs(temperature) >= 0.0005) {
    vec3 ill = kelvinToRgb(temperatureKelvin(temperature));
    vec3 d65 = kelvinToRgb(6500.0);
    gain = ill / d65;
  }
  if (abs(tint) >= 0.0005) {
    vec3 xyz = linearSrgbToXyz(gain);
    float sum = xyz.x + xyz.y + xyz.z;
    if (sum > 1e-8) {
      float chromaX = xyz.x / sum;
      float chromaY = clamp(xyz.y / sum - tint * 0.045, 0.04, 0.75);
      float bigX = chromaX / chromaY;
      float bigZ = (1.0 - chromaX - chromaY) / chromaY;
      gain = xyzToLinearSrgb(vec3(bigX, 1.0, bigZ));
    }
  }
  float y = dot(gain, kLuma);
  return gain / max(y, 1e-4);
}

float exposeLinear(float x, float ev) {
  if (abs(ev) < 0.0005) return x;
  float gained = x * exp2(ev);
  if (ev < 0.0 || gained <= 0.80) return gained;
  float over = gained - 0.80;
  return 0.80 + 0.20 * (over / (over + 0.20));
}

float contrastCurve(float y, float amount) {
  if (abs(amount) < 0.0005 || y <= 0.0) return y;
  float stops = log2(y / 0.18);
  float shaped = stops + amount * 1.15 * tanh(stops);
  return max(0.0, 0.18 * exp2(shaped));
}

float whitesBlacksCurve(float y, float whites, float blacks) {
  if (abs(whites) < 0.0005 && abs(blacks) < 0.0005) return y;
  float x = y;
  if (abs(blacks) >= 0.0005) {
    float knee = 1.0 - gradeSmoothstep(0.0, 0.02, x);
    if (blacks > 0.0) x += blacks * 0.045 * knee;
    else x *= 1.0 + blacks * knee;
  }
  if (abs(whites) >= 0.0005) {
    float knee = gradeSmoothstep(0.55, 1.0, x);
    x += whites * 0.40 * knee;
  }
  return max(x, 0.0);
}

float shadowMask(float linearBase) {
  float display = linearToSrgb(clamp(linearBase, 0.0, 1.0));
  float weight = 1.0 - gradeSmoothstep(0.05, 0.62, display);
  return pow(clamp(weight, 0.0, 1.0), 1.05);
}

float shadowTone(float linearY, float amount) {
  float display = linearToSrgb(clamp(linearY, 0.0, 1.0));
  float weight = pow(max(1.0 - gradeSmoothstep(0.0, 0.58, display), 0.0), 1.15);
  float next = (amount >= 0.0)
      ? display + amount * 0.34 * weight * (1.0 - display)
      : display * (1.0 + amount * 0.75 * weight);
  return srgbToLinear(clamp(next, 0.0, 1.0));
}

float highlightMask(float linearBase) {
  if (linearBase > 1.0) return exp(-(linearBase - 1.0));
  float display = linearToSrgb(clamp(linearBase, 0.0, 1.0));
  float rise = gradeSmoothstep(0.55, 0.82, display);
  float hold = 1.0 - gradeSmoothstep(0.94, 1.0, display);
  return rise * hold;
}

float highlightTone(float linearY, float amount) {
  float display = linearToSrgb(clamp(linearY, 0.0, 1.0));
  if (amount >= 0.0) {
    float weight = gradeSmoothstep(0.45, 0.90, display);
    return srgbToLinear(clamp(display + amount * 0.25 * weight * (1.0 - display), 0.0, 1.0));
  }
  float weight = gradeSmoothstep(0.50, 0.88, display) *
      (1.0 - gradeSmoothstep(0.96, 1.0, display));
  return srgbToLinear(clamp(display + amount * 0.28 * weight, 0.0, 1.0));
}

float decodeBase(float encoded) {
  float logv = kLogMin + encoded * (kLogMax - kLogMin);
  return exp2(logv) - 1e-4;
}

vec3 gradeLinear(vec3 c, float baseLuma) {
  c.r = exposeLinear(c.r, uExposure);
  c.g = exposeLinear(c.g, uExposure);
  c.b = exposeLinear(c.b, uExposure);
  float y = whitesBlacksCurve(contrastCurve(dot(max(c, 0.0), kLuma), uContrast), uWhites, uBlacks);
  float current = dot(max(c, 0.0), kLuma);
  if (current > 1e-8) c *= y / current;

  if (abs(uShadows) < 0.0005 && abs(uHighlights) < 0.0005) return c;
  y = dot(max(c, 0.0), kLuma);
  if (y < 1e-6) return c;
  float base = baseLuma >= 0.0 ? baseLuma : y;
  float tone = y;
  if (abs(uShadows) >= 0.0005) {
    float curved = shadowTone(tone, uShadows);
    tone += (curved - tone) * shadowMask(base);
  }
  if (abs(uHighlights) >= 0.0005) {
    float curved = highlightTone(tone, uHighlights);
    tone += (curved - tone) * highlightMask(base);
  }
  return c * clamp(tone / y, 0.05, 8.0);
}

void main() {
  vec2 uv = (FlutterFragCoord().xy - vec2(uDestLeft, uDestTop)) /
      vec2(uDestWidth, uDestHeight);
  uv = vec2(uCropLeft, uCropTop) + uv * vec2(uCropWidth, uCropHeight);
  vec4 src = texture(uTex, uv);
  vec3 lin = vec3(
    srgbToLinear(src.r),
    srgbToLinear(src.g),
    srgbToLinear(src.b)
  );
  lin *= whiteBalanceGain(uTemperature, uTint);
  float base = -1.0;
  if (uHasBase > 0.5) base = decodeBase(texture(uBase, uv).r);
  vec3 graded = gradeLinear(lin, base);
  fragColor = vec4(
    clamp(linearToSrgb(graded.r), 0.0, 1.0),
    clamp(linearToSrgb(graded.g), 0.0, 1.0),
    clamp(linearToSrgb(graded.b), 0.0, 1.0),
    src.a
  );
}
