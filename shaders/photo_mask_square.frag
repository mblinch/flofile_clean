#version 460 core

#include <flutter/runtime_effect.glsl>

// Square a packed float01 field (for guided-filter mean of I²).
// Output is remapped: I² of a 0…1 value still fits in 0…1.

uniform float uWidth;
uniform float uHeight;

uniform sampler2D uTex;

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
  float v = unpackF01(texture(uTex, uv));
  vec2 rg = packF01(v * v);
  fragColor = vec4(rg, 0.0, 1.0);
}
