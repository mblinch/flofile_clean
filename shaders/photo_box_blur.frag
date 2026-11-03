#version 460 core

#include <flutter/runtime_effect.glsl>

// Separable box blur on a packed RG float01 field.
// uHorizontal = 1 → blur X; 0 → blur Y.
// Radius is in pixels of this buffer (already a fraction of image width).

uniform float uWidth;
uniform float uHeight;
uniform float uRadius;       // pixels
uniform float uHorizontal;   // 1 or 0
uniform float uUseBA;        // 0 = blur packed RG; 1 = blur packed BA

uniform sampler2D uTex;

out vec4 fragColor;

float unpackRG(vec4 t) {
  return (t.r * 255.0 * 256.0 + t.g * 255.0) / 65535.0;
}

float unpackBA(vec4 t) {
  return (t.b * 255.0 * 256.0 + t.a * 255.0) / 65535.0;
}

vec2 packF01(float v) {
  float x = clamp(v, 0.0, 1.0) * 65535.0;
  float hi = floor(x / 256.0);
  float lo = x - hi * 256.0;
  return vec2(hi, lo) / 255.0;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 texel = 1.0 / vec2(uWidth, uHeight);
  vec2 uv = frag * texel;

  float radius = max(uRadius, 0.0);
  // Fixed max taps keeps Impeller happy; early-out beyond radius.
  const int kMax = 64;
  float sum = 0.0;
  float count = 0.0;

  for (int i = -kMax; i <= kMax; i++) {
    float fi = float(i);
    if (abs(fi) > radius + 0.01) continue;
    vec2 off = (uHorizontal > 0.5)
        ? vec2(fi * texel.x, 0.0)
        : vec2(0.0, fi * texel.y);
    vec2 sampleUv = clamp(uv + off, vec2(0.0), vec2(1.0));
    vec4 s = texture(uTex, sampleUv);
    sum += (uUseBA > 0.5) ? unpackBA(s) : unpackRG(s);
    count += 1.0;
  }

  float mean = sum / max(count, 1.0);
  vec2 rg = packF01(mean);
  fragColor = vec4(rg, 0.0, 1.0);
}
