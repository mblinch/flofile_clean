#version 460 core

#include <flutter/runtime_effect.glsl>

// Final local-tone mask:
//   filteredLog = meanA * I + meanB
//   convert log → linear → sRGB (perceptual 0…1)
//   mask = blend * filtered + (1 − blend) * sharp

uniform float uWidth;
uniform float uHeight;
uniform float uLogMin;
uniform float uLogMax;
uniform float uMaskBlend; // 0.8

uniform sampler2D uSharpI;  // packed encoded log-luma
uniform sampler2D uMeanA;  // packed a
uniform sampler2D uMeanB;  // packed b (in encoded-log space)

out vec4 fragColor;

float unpackF01(vec4 t) {
  return (t.r * 255.0 * 256.0 + t.g * 255.0) / 65535.0;
}

vec2 packF01(float v) {
  float x = clamp(v, 0.0, 1.0) * 65535.0;
  float hi = floor(x / 256.0);
  float lo = x - hi * 256.0;
  return vec2(hi, lo) / 255.0;
}

float linearToSrgb(float c) {
  if (c <= 0.0) return 0.0;
  return (c <= 0.0031308) ? 12.92 * c : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

float encToLinear(float enc) {
  float logv = uLogMin + clamp(enc, 0.0, 1.0) * (uLogMax - uLogMin);
  return max(exp2(logv) - 1e-4, 0.0);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / vec2(uWidth, uHeight);
  float I = unpackF01(texture(uSharpI, uv));
  float meanA = unpackF01(texture(uMeanA, uv));
  float meanB = unpackF01(texture(uMeanB, uv));
  float filteredEnc = clamp(meanA * I + meanB, 0.0, 1.0);

  float sharpLin = encToLinear(I);
  float filtLin = encToLinear(filteredEnc);
  float sharp = linearToSrgb(clamp(sharpLin, 0.0, 1.0));
  float filt = linearToSrgb(clamp(filtLin, 0.0, 1.0));
  float mask = uMaskBlend * filt + (1.0 - uMaskBlend) * sharp;

  vec2 rg = packF01(mask);
  fragColor = vec4(rg, 0.0, 1.0);
}
