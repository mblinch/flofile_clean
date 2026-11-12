#version 460 core

#include <flutter/runtime_effect.glsl>

// Pass 0 of the local-tone mask: decode sRGB → linear, apply WB / exposure /
// contrast, write log-luminance packed into RG (~16-bit).

uniform float uWidth;
uniform float uHeight;
uniform float uTemperature;
uniform float uTint;
uniform float uExposure;
uniform float uContrast;
uniform float uTempStrengthPos;
uniform float uTempStrengthNeg;
uniform float uTintStrengthPos;
uniform float uTintStrengthNeg;
uniform float uContrastPivot;
uniform float uContrastStrengthLo;
uniform float uContrastStrengthHi;
uniform float uContrastFadeLo;
uniform float uContrastFadeHi;
uniform float uLogMin;
uniform float uLogMax;

uniform sampler2D uTex;

out vec4 fragColor;

const vec3 kLuma = vec3(0.2126, 0.7152, 0.0722);

float srgbToLinear(float c) {
  return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

vec2 packF01(float v) {
  float x = clamp(v, 0.0, 1.0) * 65535.0;
  float hi = floor(x / 256.0);
  float lo = x - hi * 256.0;
  return vec2(hi, lo) / 255.0;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / vec2(uWidth, uHeight);
  vec4 src = texture(uTex, uv);
  vec3 lin = vec3(srgbToLinear(src.r), srgbToLinear(src.g), srgbToLinear(src.b));

  float tempStrength = (uTemperature < 0.0) ? uTempStrengthNeg : uTempStrengthPos;
  float tintStrength = (uTint < 0.0) ? uTintStrengthNeg : uTintStrengthPos;
  vec3 gain = vec3(
    max(1.0 + tempStrength * uTemperature, 1e-4),
    max(1.0 - tintStrength * uTint, 1e-4),
    max(1.0 - tempStrength * uTemperature, 1e-4)
  );
  float gy = dot(gain, kLuma);
  gain /= max(gy, 1e-4);
  lin *= gain;
  lin *= exp2(uExposure);

  float y = dot(max(lin, 0.0), kLuma);
  if (abs(uContrast) >= 1e-6 && y > 1e-8) {
    float stops = log2(y / uContrastPivot);
    float strength = (stops < 0.0) ? uContrastStrengthLo : uContrastStrengthHi;
    float t = clamp((y - uContrastFadeLo) / max(uContrastFadeHi - uContrastFadeLo, 1e-6), 0.0, 1.0);
    float fade = 1.0 - t * t * (3.0 - 2.0 * t);
    float shaped = stops * (1.0 + strength * fade * uContrast);
    float y2 = max(0.0, uContrastPivot * exp2(shaped));
    lin *= y2 / y;
    y = y2;
  }

  float logv = log2(max(y, 0.0) + 1e-4);
  float enc = (logv - uLogMin) / (uLogMax - uLogMin);
  vec2 rg = packF01(enc);
  fragColor = vec4(rg, 0.0, 1.0);
}
