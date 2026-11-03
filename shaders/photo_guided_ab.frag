#version 460 core

#include <flutter/runtime_effect.glsl>

// Guided-filter coefficients:
//   a = var / (var + eps)
//   b = meanI * (1 − a)
// Packed as: R/G = a (0…1), B/A unused for a; we store a in RG and b remapped
// into a second target via two draws, OR pack a in RG and encode b in the same
// range. Here: RG = pack(a), BA unused → we output a in RG and b in BA as
// another packed pair (B=hi, A cannot hold lo easily).
//
// Flutter RGBA8: pack a → RG, pack bMapped → BA where b is shifted into 0…1
// via (b − uLogMin)/(uLogMax−uLogMin) since b ≈ mean log-luma.

uniform float uWidth;
uniform float uHeight;
uniform float uEps;
uniform float uLogMin;
uniform float uLogMax;

uniform sampler2D uMeanI;
uniform sampler2D uMeanI2;

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

void main() {
  vec2 uv = FlutterFragCoord().xy / vec2(uWidth, uHeight);
  float meanI = unpackF01(texture(uMeanI, uv));
  float meanI2 = unpackF01(texture(uMeanI2, uv));
  float variance = max(0.0, meanI2 - meanI * meanI);
  float a = variance / (variance + uEps);
  float b = meanI * (1.0 - a);
  // b is in the same 0…1 encoded-log space as meanI.
  vec2 pa = packF01(a);
  vec2 pb = packF01(clamp(b, 0.0, 1.0));
  fragColor = vec4(pa, pb);
}
