#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform float uIntensity;

out vec4 fragColor;

// Soft horizontal ribbon of light: a band whose centre wanders with sine waves.
float ribbon(vec2 uv, float t, float seed, float speed, float width) {
  float x = uv.x * 2.2 + seed;
  float centre = 0.50
      + 0.18 * sin(x * 1.3 + t * speed)
      + 0.10 * sin(x * 2.7 - t * speed * 0.7 + seed * 3.0)
      + 0.05 * sin(x * 5.1 + t * speed * 1.3);
  float d = abs(uv.y - centre);
  float core = exp(-d * d / (width * width));
  float halo = exp(-d * d / (width * width * 9.0)) * 0.25;
  return core + halo;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  uv.x *= uSize.x / uSize.y * 0.6;      // keep waves from stretching on wide windows

  float t = uTime * 0.05;               // slow, ambient motion

  vec3 teal   = vec3(0.00, 0.78, 0.67);
  vec3 cyan   = vec3(0.00, 0.90, 1.00);
  vec3 purple = vec3(0.55, 0.25, 0.95);

  vec3 base = mix(vec3(0.02, 0.03, 0.07), vec3(0.04, 0.02, 0.10), uv.y);

  float a = ribbon(uv, t, 0.0, 1.0, 0.17);
  float b = ribbon(uv, t, 2.4, 0.8, 0.20);
  float c = ribbon(uv, t, 5.1, 1.2, 0.16);

  vec3 col = base;
  col += teal   * a * 0.55 * uIntensity;
  col += cyan   * b * 0.40 * uIntensity;
  col += purple * c * 0.55 * uIntensity;

  // Gentle vignette so the edges stay dark and UI stays readable.
  vec2 q = frag / uSize - 0.5;
  col *= 1.0 - dot(q, q) * 0.9;

  fragColor = vec4(col, 1.0);
}
