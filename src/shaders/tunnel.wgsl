// Neverending Tunnel, ray traced. The tiles, colours and grout follow the
// original 2D painter exactly: 33 tiles per side warped toward the corners,
// the same hash and shade thresholds, a pattern that repeats every 24 rings,
// and grout a fixed 1.7 CSS pixels wide.
//
// Space: x right, y up, s forward (distance ahead of the eye). The tunnel is
// the square |x| < 1, |y| < 1. The camera always sits at s = 0.

struct Uniforms {
  a: vec4f,                    // resolution.xy, time, tan(vertical fov / 2)
  b: vec4f,                    // eye x, eye y, roll, pitch
  c: vec4f,                    // eye ring (wrapped), pit count, box count, light distance
  d: vec4f,                    // grout px, fade, flash, glow
  pits: array<vec4f, 8>,       // s0, s1, x0, x1
  bmin: array<vec4f, 16>,      // x0, y0, s0, id
  bmax: array<vec4f, 16>,      // x1, y1, s1, unused
};
@group(0) @binding(0) var<uniform> u: Uniforms;

const N = 33.0;
const RING = 0.056;            // ring depth: square tiles where the walls meet the screen edge
const PIT_DEPTH = 1.2;
const PI = 3.14159265;

const C_DARK = vec3f(117.0, 35.0, 39.0) / 255.0;    // #752327
const C_MID = vec3f(164.0, 54.0, 57.0) / 255.0;     // #a43639
const C_BRIGHT = vec3f(223.0, 72.0, 77.0) / 255.0;  // #df484d
const C_GROUT = vec3f(16.0, 1.0, 1.0) / 255.0;      // #100101
const C_LIGHT = vec3f(1.0, 0.98, 0.95);

@vertex
fn vs(@builtin(vertex_index) i: u32) -> @builtin(position) vec4f {
  var p = array<vec2f, 3>(vec2f(-1.0, -3.0), vec2f(-1.0, 1.0), vec2f(3.0, 1.0));
  return vec4f(p[i], 0.0, 1.0);
}

// The original _rand(ring, side, j), bit for bit.
fn hash(a: i32, b: i32, c: i32) -> f32 {
  var h = (bitcast<u32>(a) * 0x9E3779B1u) ^ (bitcast<u32>(b + 1) * 0x85EBCA77u) ^ (bitcast<u32>(c + 1) * 0xC2B2AE3Du) ^ 7u;
  h = (h ^ (h >> 16u)) * 0x7FEB352Du;
  h = (h ^ (h >> 15u)) * 0x846CA68Bu;
  h = h ^ (h >> 16u);
  return f32(h) / 4294967296.0;
}

fn palette(r: f32) -> vec3f {
  if (r < 0.516) { return C_DARK; }
  if (r < 0.875) { return C_MID; }
  return C_BRIGHT;
}

// Inverse of the original corner warp g(u) = u - 0.0098 sin(pi u).
fn ginv(v: f32) -> f32 {
  var x = v;
  for (var i = 0; i < 3; i++) {
    x = x - (x - 0.0098 * sin(PI * x) - v) / (1.0 - 0.0098 * PI * cos(PI * x));
  }
  return x;
}

// Tile colour with grout. a, b are tile coordinates; fa, fb are tile units per pixel.
fn grout(a: f32, b: f32, fa: f32, fb: f32, c: vec3f) -> vec3f {
  let da = min(fract(a), 1.0 - fract(a)) / max(fa, 1e-6);
  let db = min(fract(b), 1.0 - fract(b)) / max(fb, 1e-6);
  let half = u.d.x * 0.5;
  let cover = 1.0 - smoothstep(half - 0.5, half + 0.5, min(da, db));
  return mix(c, C_GROUT, cover);
}

// Far away, rings merge in powers of two so tiles stay square on screen,
// the way the original's rings shrink by a constant ratio.
fn lod(s: f32) -> f32 {
  return log2(max(1.0, s * 2.0 / (N * RING)));
}

fn tunnelTile(side: i32, a: f32, ring: f32, lvl: f32, fa: f32, fdepth: f32) -> vec3f {
  let sc = exp2(lvl);
  let b = ring / sc;
  let k = i32(floor(b));
  let rk = ((k % 24) + 24) % 24;
  let j = clamp(i32(floor(a)), 0, 32);
  let c = palette(hash(rk, side + 4 * i32(lvl), j));
  return grout(a, b, fa, fdepth / (sc * RING), c);
}

@fragment
fn fs(@builtin(position) fc: vec4f) -> @location(0) vec4f {
  let res = u.a.xy;
  let tY = u.a.w;
  let tX = tY * res.x / res.y;
  let ndc = vec2f(fc.x / res.x * 2.0 - 1.0, 1.0 - fc.y / res.y * 2.0);
  var dir = normalize(vec3f(ndc.x * tX, ndc.y * tY, -1.0));
  let cp = cos(u.b.w);
  let sp = sin(u.b.w);
  dir = vec3f(dir.x, dir.y * cp - dir.z * sp, dir.y * sp + dir.z * cp);
  let cr = cos(u.b.z);
  let sr = sin(u.b.z);
  dir = vec3f(dir.x * cr - dir.y * sr, dir.x * sr + dir.y * cr, dir.z);

  let o = vec3f(u.b.x, u.b.y, 0.0);
  var r = vec3f(dir.x, dir.y, -dir.z);
  if (abs(r.x) < 1e-5) { r.x = 1e-5; }
  if (abs(r.y) < 1e-5) { r.y = 1e-5; }
  let pixA = 2.0 * tY / res.y;
  let camRing = u.c.x;
  let np = min(i32(u.c.y), 8);
  let nb = min(i32(u.c.z), 16);
  let lightD = u.c.w;

  // Tunnel walls, or the light at the end.
  let tx = select((1.0 - o.x) / r.x, (-1.0 - o.x) / r.x, r.x < 0.0);
  let ty = select((1.0 - o.y) / r.y, (-1.0 - o.y) / r.y, r.y < 0.0);
  var t = min(tx, ty);
  var side = 0;
  if (tx < ty) { side = select(1, 0, r.x < 0.0); } else { side = select(2, 3, r.y < 0.0); }
  var kind = 0;  // 0 tunnel, 1 light, 2 pit
  if (r.z > 0.0 && t * r.z > lightD) {
    t = lightD / r.z;
    kind = 1;
  }

  // Through the floor into a pit.
  var pitIdx = -1;
  var pitFace = 0;  // 0 side wall, 1 far wall, 2 bottom
  if (kind == 0 && side == 3) {
    let p = o + r * t;
    for (var i = 0; i < np; i++) {
      let q = u.pits[i];
      if (p.z > q.x && p.z < q.y && p.x > q.z && p.x < q.w) { pitIdx = i; }
    }
    if (pitIdx >= 0) {
      let q = u.pits[pitIdx];
      let txw = select((q.w - o.x) / r.x, (q.z - o.x) / r.x, r.x < 0.0);
      let ts = select(1e9, (q.y - o.z) / r.z, r.z > 0.0);
      let tb = (-1.0 - PIT_DEPTH - o.y) / r.y;
      t = min(txw, min(ts, tb));
      if (tb <= t) { pitFace = 2; } else if (ts <= t) { pitFace = 1; } else { pitFace = 0; }
      kind = 2;
    }
  }

  // Obstacles.
  var boxIdx = -1;
  var boxAxis = 0;
  let inv = 1.0 / r;
  for (var i = 0; i < nb; i++) {
    let t0 = (u.bmin[i].xyz - o) * inv;
    let t1 = (u.bmax[i].xyz - o) * inv;
    let lo = min(t0, t1);
    let hi = max(t0, t1);
    let tn = max(max(lo.x, lo.y), lo.z);
    let tf = min(min(hi.x, hi.y), hi.z);
    if (tn <= tf && tn > 0.0 && tn < t) {
      t = tn;
      boxIdx = i;
      if (tn == lo.x) { boxAxis = 0; } else if (tn == lo.y) { boxAxis = 1; } else { boxAxis = 2; }
    }
  }

  let p = o + r * t;
  let w = t * pixA;
  var col = C_GROUT;
  var glowMul = 1.0;

  if (boxIdx >= 0) {
    let mn = u.bmin[boxIdx];
    let id = i32(mn.w);
    var tint = 0.42;
    var face = 4;
    var a = (p.x + 1.0) * N * 0.5;
    var b = (1.0 - p.y) * N * 0.5;
    var fa = w * N * 0.5;
    var fb = fa;
    if (boxAxis == 0) {
      tint = 0.62;
      face = select(0, 1, r.x < 0.0);
      a = (1.0 - p.y) * N * 0.5;
      b = (p.z - mn.z) / RING;
      fb = w / max(abs(r.x), 0.05) / RING;
    } else if (boxAxis == 1) {
      tint = select(0.92, 0.34, r.y > 0.0);
      face = select(2, 3, r.y > 0.0);
      b = (p.z - mn.z) / RING;
      fb = w / max(abs(r.y), 0.05) / RING;
    }
    if (boxAxis != 2) {
      let sc = exp2(floor(lod(p.z) + 0.5));
      b = b / sc;
      fb = fb / sc;
    }
    let c = palette(hash(id * 8 + face, i32(floor(b)), i32(floor(a))));
    col = grout(a, b, fa, fb, c * tint);
    glowMul = 0.3;
  } else if (kind == 1) {
    col = C_LIGHT;
  } else if (kind == 2) {
    let depth = clamp((-1.0 - p.y) / PIT_DEPTH, 0.0, 1.0);
    let dk = 0.5 * pow(1.0 - depth, 1.8) + 0.04;
    let q = u.pits[pitIdx];
    let rows = (-1.0 - p.y) * N * 0.5;
    if (pitFace == 1) {
      let a = (p.x + 1.0) * N * 0.5;
      let seed = i32(floor(q.y / RING + camRing));
      let c = palette(hash(seed, 4, i32(floor(a)) * 64 + i32(floor(rows))));
      col = grout(a, rows, w * N * 0.5, w * N * 0.5, c * dk);
    } else if (pitFace == 0) {
      let b = p.z / RING + camRing;
      let c = palette(hash(((i32(floor(b)) % 24) + 24) % 24, select(6, 5, r.x < 0.0), i32(floor(rows))));
      col = grout(rows, b, w * N * 0.5, w / max(abs(r.x), 0.05) / RING, c * dk);
    }
  } else {
    var v = p.x;
    var cosN = abs(r.y);
    if (side <= 1) {
      v = -p.y;
      cosN = abs(r.x);
    }
    let a = (ginv(v) + 1.0) * 0.5 * N;
    let fa = w * N * 0.5;
    let fd = w / max(cosN, 0.02);
    let ring = p.z / RING + camRing;
    let L = lod(p.z);
    let L0 = floor(L);
    let c0 = tunnelTile(side, a, ring, L0, fa, fd);
    let c1 = tunnelTile(side, a, ring, L0 + 1.0, fa, fd);
    col = mix(c0, c1, smoothstep(0.7, 1.0, L - L0));
  }

  // Bloom from the light at the end.
  let lc = normalize(vec3f(-o.x, -o.y, lightD));
  let ang2 = max(0.0, 2.0 * (1.0 - dot(r, lc)));
  let sig2 = 1.0 / (lightD * lightD);
  let glow = u.d.w * (0.55 * exp(-ang2 / (sig2 * 4.0)) + 0.16 * exp(-ang2 / (sig2 * 40.0)));
  col = col + vec3f(1.0, 0.86, 0.78) * glow * glowMul;

  col = mix(col, C_BRIGHT, u.d.z * 0.3);
  col = mix(col, vec3f(0.024, 0.0, 0.0), u.d.y);
  return vec4f(min(col, vec3f(1.0)), 1.0);
}
