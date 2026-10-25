#version 300 es
// GLSL port of tunnel.wgsl for browsers without WebGPU. Keep the two in sync.
//
// Space: x right, y up, s forward (distance ahead of the eye). The tunnel is
// the square |x| < 1, |y| < 1. The camera always sits at s = 0.
precision highp float;
precision highp int;

// Same layout as struct Uniforms in tunnel.wgsl, as a flat vec4 array:
//   [0] resolution.xy, time, tan(vertical fov / 2)
//   [1] eye x, eye y, roll, pitch
//   [2] eye ring (wrapped), pit count, box count, light distance
//   [3] grout px, fade, flash, glow
//   [4..11]  pits: s0, s1, x0, x1
//   [12..27] box min: x0, y0, s0, id
//   [28..43] box max: x1, y1, s1, unused
uniform vec4 U[44];

out vec4 fragColor;

const float N = 33.0;
const float RING = 0.056;
const float PIT_DEPTH = 1.2;
const float PI = 3.14159265;

const vec3 C_DARK = vec3(117.0, 35.0, 39.0) / 255.0;
const vec3 C_MID = vec3(164.0, 54.0, 57.0) / 255.0;
const vec3 C_BRIGHT = vec3(223.0, 72.0, 77.0) / 255.0;
const vec3 C_GROUT = vec3(16.0, 1.0, 1.0) / 255.0;
const vec3 C_LIGHT = vec3(1.0, 0.98, 0.95);

// GLSL leaves % undefined for negative operands.
int imod(int a, int m) {
  return a - m * int(floor(float(a) / float(m)));
}

// The original _rand(ring, side, j), bit for bit.
float hash(int a, int b, int c) {
  uint h = (uint(a) * 0x9E3779B1u) ^ (uint(b + 1) * 0x85EBCA77u) ^ (uint(c + 1) * 0xC2B2AE3Du) ^ 7u;
  h = (h ^ (h >> 16u)) * 0x7FEB352Du;
  h = (h ^ (h >> 15u)) * 0x846CA68Bu;
  h = h ^ (h >> 16u);
  return float(h) / 4294967296.0;
}

vec3 palette(float r) {
  if (r < 0.516) return C_DARK;
  if (r < 0.875) return C_MID;
  return C_BRIGHT;
}

// Inverse of the original corner warp g(u) = u - 0.0098 sin(pi u).
float ginv(float v) {
  float x = v;
  for (int i = 0; i < 3; i++) {
    x = x - (x - 0.0098 * sin(PI * x) - v) / (1.0 - 0.0098 * PI * cos(PI * x));
  }
  return x;
}

// Tile colour with grout. a, b are tile coordinates; fa, fb are tile units per pixel.
vec3 grout(float a, float b, float fa, float fb, vec3 c) {
  float da = min(fract(a), 1.0 - fract(a)) / max(fa, 1e-6);
  float db = min(fract(b), 1.0 - fract(b)) / max(fb, 1e-6);
  float hw = U[3].x * 0.5;
  float cover = 1.0 - smoothstep(hw - 0.5, hw + 0.5, min(da, db));
  return mix(c, C_GROUT, cover);
}

// Far away, rings merge in powers of two so tiles stay square on screen.
float lod(float s) {
  return log2(max(1.0, s * 2.0 / (N * RING)));
}

vec3 tunnelTile(int side, float a, float ring, float lvl, float fa, float fdepth) {
  float sc = exp2(lvl);
  float b = ring / sc;
  int k = int(floor(b));
  int rk = imod(k, 24);
  int j = clamp(int(floor(a)), 0, 32);
  vec3 c = palette(hash(rk, side + 4 * int(lvl), j));
  return grout(a, b, fa, fdepth / (sc * RING), c);
}

void main() {
  vec2 res = U[0].xy;
  float tY = U[0].w;
  float tX = tY * res.x / res.y;
  vec2 ndc = vec2(gl_FragCoord.x / res.x * 2.0 - 1.0, gl_FragCoord.y / res.y * 2.0 - 1.0);
  vec3 dir = normalize(vec3(ndc.x * tX, ndc.y * tY, -1.0));
  float cp = cos(U[1].w);
  float sp = sin(U[1].w);
  dir = vec3(dir.x, dir.y * cp - dir.z * sp, dir.y * sp + dir.z * cp);
  float cr = cos(U[1].z);
  float sr = sin(U[1].z);
  dir = vec3(dir.x * cr - dir.y * sr, dir.x * sr + dir.y * cr, dir.z);

  vec3 o = vec3(U[1].x, U[1].y, 0.0);
  vec3 r = vec3(dir.x, dir.y, -dir.z);
  if (abs(r.x) < 1e-5) r.x = 1e-5;
  if (abs(r.y) < 1e-5) r.y = 1e-5;
  float pixA = 2.0 * tY / res.y;
  float camRing = U[2].x;
  int np = min(int(U[2].y), 8);
  int nb = min(int(U[2].z), 16);
  float lightD = U[2].w;

  // Tunnel walls, or the light at the end.
  float tx = r.x < 0.0 ? (-1.0 - o.x) / r.x : (1.0 - o.x) / r.x;
  float ty = r.y < 0.0 ? (-1.0 - o.y) / r.y : (1.0 - o.y) / r.y;
  float t = min(tx, ty);
  int side = 0;
  if (tx < ty) { side = r.x < 0.0 ? 0 : 1; } else { side = r.y < 0.0 ? 3 : 2; }
  int kind = 0;  // 0 tunnel, 1 light, 2 pit
  if (r.z > 0.0 && t * r.z > lightD) {
    t = lightD / r.z;
    kind = 1;
  }

  // Through the floor into a pit.
  int pitIdx = -1;
  int pitFace = 0;  // 0 side wall, 1 far wall, 2 bottom
  if (kind == 0 && side == 3) {
    vec3 p = o + r * t;
    for (int i = 0; i < np; i++) {
      vec4 q = U[4 + i];
      if (p.z > q.x && p.z < q.y && p.x > q.z && p.x < q.w) pitIdx = i;
    }
    if (pitIdx >= 0) {
      vec4 q = U[4 + pitIdx];
      float txw = r.x < 0.0 ? (q.z - o.x) / r.x : (q.w - o.x) / r.x;
      float ts = r.z > 0.0 ? (q.y - o.z) / r.z : 1e9;
      float tb = (-1.0 - PIT_DEPTH - o.y) / r.y;
      t = min(txw, min(ts, tb));
      if (tb <= t) pitFace = 2; else if (ts <= t) pitFace = 1; else pitFace = 0;
      kind = 2;
    }
  }

  // Obstacles.
  int boxIdx = -1;
  int boxAxis = 0;
  vec3 inv = 1.0 / r;
  for (int i = 0; i < nb; i++) {
    vec3 t0 = (U[12 + i].xyz - o) * inv;
    vec3 t1 = (U[28 + i].xyz - o) * inv;
    vec3 lo = min(t0, t1);
    vec3 hi = max(t0, t1);
    float tn = max(max(lo.x, lo.y), lo.z);
    float tf = min(min(hi.x, hi.y), hi.z);
    if (tn <= tf && tn > 0.0 && tn < t) {
      t = tn;
      boxIdx = i;
      if (tn == lo.x) boxAxis = 0; else if (tn == lo.y) boxAxis = 1; else boxAxis = 2;
    }
  }

  vec3 p = o + r * t;
  float w = t * pixA;
  vec3 col = C_GROUT;
  float glowMul = 1.0;

  if (boxIdx >= 0) {
    vec4 mn = U[12 + boxIdx];
    int id = int(mn.w);
    float tint = 0.42;
    int face = 4;
    float a = (p.x + 1.0) * N * 0.5;
    float b = (1.0 - p.y) * N * 0.5;
    float fa = w * N * 0.5;
    float fb = fa;
    if (boxAxis == 0) {
      tint = 0.62;
      face = r.x < 0.0 ? 1 : 0;
      a = (1.0 - p.y) * N * 0.5;
      b = (p.z - mn.z) / RING;
      fb = w / max(abs(r.x), 0.05) / RING;
    } else if (boxAxis == 1) {
      tint = r.y > 0.0 ? 0.34 : 0.92;
      face = r.y > 0.0 ? 3 : 2;
      b = (p.z - mn.z) / RING;
      fb = w / max(abs(r.y), 0.05) / RING;
    }
    if (boxAxis != 2) {
      float sc = exp2(floor(lod(p.z) + 0.5));
      b = b / sc;
      fb = fb / sc;
    }
    vec3 c = palette(hash(id * 8 + face, int(floor(b)), int(floor(a))));
    col = grout(a, b, fa, fb, c * tint);
    glowMul = 0.3;
  } else if (kind == 1) {
    col = C_LIGHT;
  } else if (kind == 2) {
    float depth = clamp((-1.0 - p.y) / PIT_DEPTH, 0.0, 1.0);
    float dk = 0.5 * pow(1.0 - depth, 1.8) + 0.04;
    vec4 q = U[4 + pitIdx];
    float rows = (-1.0 - p.y) * N * 0.5;
    if (pitFace == 1) {
      float a = (p.x + 1.0) * N * 0.5;
      int seed = int(floor(q.y / RING + camRing));
      vec3 c = palette(hash(seed, 4, int(floor(a)) * 64 + int(floor(rows))));
      col = grout(a, rows, w * N * 0.5, w * N * 0.5, c * dk);
    } else if (pitFace == 0) {
      float b = p.z / RING + camRing;
      vec3 c = palette(hash(imod(int(floor(b)), 24), r.x < 0.0 ? 5 : 6, int(floor(rows))));
      col = grout(rows, b, w * N * 0.5, w / max(abs(r.x), 0.05) / RING, c * dk);
    }
  } else {
    float v = p.x;
    float cosN = abs(r.y);
    if (side <= 1) {
      v = -p.y;
      cosN = abs(r.x);
    }
    float a = (ginv(v) + 1.0) * 0.5 * N;
    float fa = w * N * 0.5;
    float fd = w / max(cosN, 0.02);
    float ring = p.z / RING + camRing;
    float L = lod(p.z);
    float L0 = floor(L);
    vec3 c0 = tunnelTile(side, a, ring, L0, fa, fd);
    vec3 c1 = tunnelTile(side, a, ring, L0 + 1.0, fa, fd);
    col = mix(c0, c1, smoothstep(0.7, 1.0, L - L0));
  }

  // Bloom from the light at the end.
  vec3 lc = normalize(vec3(-o.x, -o.y, lightD));
  float ang2 = max(0.0, 2.0 * (1.0 - dot(r, lc)));
  float sig2 = 1.0 / (lightD * lightD);
  float glow = U[3].w * (0.55 * exp(-ang2 / (sig2 * 4.0)) + 0.16 * exp(-ang2 / (sig2 * 40.0)));
  col = col + vec3(1.0, 0.86, 0.78) * glow * glowMul;

  col = mix(col, C_BRIGHT, U[3].z * 0.3);
  col = mix(col, vec3(0.024, 0.0, 0.0), U[3].y);
  fragColor = vec4(min(col, vec3(1.0)), 1.0);
}
