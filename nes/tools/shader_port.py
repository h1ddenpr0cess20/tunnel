"""Pixel-exact port of the tunnel part of src/shaders/tunnel.wgsl (walls, grout, lod blend, light bloom)."""
import numpy as np

N = 33.0
RING = 0.056
LIGHT_D = 29.0
C_DARK = np.array([117, 35, 39]) / 255.0
C_MID = np.array([164, 54, 57]) / 255.0
C_BRIGHT = np.array([223, 72, 77]) / 255.0
C_GROUT = np.array([16, 1, 1]) / 255.0
C_LIGHT = np.array([1.0, 0.98, 0.95])
M32 = 0xFFFFFFFF

def wgsl_hash(a, b, c):
    """The original _rand(ring, side, j); a, b, c are int arrays (i32 bit patterns)."""
    a = a.astype(np.int64) & M32; b = (b.astype(np.int64) + 1) & M32; c = (c.astype(np.int64) + 1) & M32
    h = ((a * 0x9E3779B1) & M32) ^ ((b * 0x85EBCA77) & M32) ^ ((c * 0xC2B2AE3D) & M32) ^ 7
    h = ((h ^ (h >> 16)) * 0x7FEB352D) & M32
    h = ((h ^ (h >> 15)) * 0x846CA68B) & M32
    h = h ^ (h >> 16)
    return h.astype(np.float64) / 4294967296.0

def palette(r):
    out = np.empty(r.shape + (3,))
    out[...] = C_BRIGHT
    out[r < 0.875] = C_MID
    out[r < 0.516] = C_DARK
    return out

def ginv(v):
    x = v.copy()
    for _ in range(3):
        x = x - (x - 0.0098 * np.sin(np.pi * x) - v) / (1.0 - 0.0098 * np.pi * np.cos(np.pi * x))
    return x

def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)

def grout(a, b, fa, fb, c, gpx):
    fr = lambda x: x - np.floor(x)
    da = np.minimum(fr(a), 1 - fr(a)) / np.maximum(fa, 1e-6)
    db = np.minimum(fr(b), 1 - fr(b)) / np.maximum(fb, 1e-6)
    half = gpx * 0.5
    cover = 1.0 - smoothstep(half - 0.5, half + 0.5, np.minimum(da, db))
    return c * (1 - cover[..., None]) + C_GROUT * cover[..., None]

def lod(s):
    return np.log2(np.maximum(1.0, s * 2.0 / (N * RING)))

def tunnel_tile(side, a, ring, lvl, fa, fdepth, gpx):
    sc = 2.0 ** lvl
    b = ring / sc
    k = np.floor(b).astype(np.int64)
    rk = ((k % 24) + 24) % 24
    j = np.clip(np.floor(a), 0, 32).astype(np.int64)
    c = palette(wgsl_hash(rk, side + 4 * lvl.astype(np.int64), j))
    return grout(a, b, fa, fdepth / (sc * RING), c, gpx)

def render(width, height, cam_ring, gpx=1.0, eye=(0.0, 0.0), y_center_px=None):
    """Returns float RGB image (height, width, 3). The camera looks straight down the tunnel."""
    tY = min(1.1, max(0.55, height / width))
    tX = tY * width / height
    xs = (np.arange(width) + 0.5) / width * 2 - 1
    ys = 1 - (np.arange(height) + 0.5) / height * 2
    ndcx, ndcy = np.meshgrid(xs, ys)
    d = np.stack([ndcx * tX, ndcy * tY, -np.ones_like(ndcx)], -1)
    d = d / np.linalg.norm(d, axis=-1, keepdims=True)
    r = np.stack([d[..., 0], d[..., 1], -d[..., 2]], -1)
    r[..., 0] = np.where(np.abs(r[..., 0]) < 1e-5, 1e-5, r[..., 0])
    r[..., 1] = np.where(np.abs(r[..., 1]) < 1e-5, 1e-5, r[..., 1])
    ox, oy = eye
    pixA = 2.0 * tY / height
    tx = np.where(r[..., 0] < 0, (-1.0 - ox) / r[..., 0], (1.0 - ox) / r[..., 0])
    ty = np.where(r[..., 1] < 0, (-1.0 - oy) / r[..., 1], (1.0 - oy) / r[..., 1])
    t = np.minimum(tx, ty)
    side = np.where(tx < ty, np.where(r[..., 0] < 0, 0, 1), np.where(r[..., 1] < 0, 3, 2))
    light = (r[..., 2] > 0) & (t * r[..., 2] > LIGHT_D)
    t = np.where(light, LIGHT_D / r[..., 2], t)
    px = ox + r[..., 0] * t; py = oy + r[..., 1] * t; pz = r[..., 2] * t
    w = t * pixA
    wall_x = side <= 1
    v = np.where(wall_x, -py, px)
    cosN = np.where(wall_x, np.abs(r[..., 0]), np.abs(r[..., 1]))
    a = (ginv(v) + 1.0) * 0.5 * N
    fa = w * N * 0.5
    fd = w / np.maximum(cosN, 0.02)
    ring = pz / RING + cam_ring
    L = lod(pz)
    L0 = np.floor(L)
    c0 = tunnel_tile(side, a, ring, L0, fa, fd, gpx)
    c1 = tunnel_tile(side, a, ring, L0 + 1.0, fa, fd, gpx)
    col = c0 * (1 - smoothstep(0.7, 1.0, L - L0)[..., None]) + c1 * smoothstep(0.7, 1.0, L - L0)[..., None]
    col = np.where(light[..., None], C_LIGHT, col)
    # bloom from the light at the end
    lc = np.array([-ox, -oy, LIGHT_D]); lc = lc / np.linalg.norm(lc)
    ang2 = np.maximum(0.0, 2.0 * (1.0 - (r @ lc)))
    sig2 = 1.0 / (LIGHT_D * LIGHT_D)
    glow = 0.55 * np.exp(-ang2 / (sig2 * 4.0)) + 0.16 * np.exp(-ang2 / (sig2 * 40.0))
    col = col + np.array([1.0, 0.86, 0.78]) * glow[..., None]
    return np.minimum(col, 1.0), light

if __name__ == '__main__':
    import sys
    from PIL import Image
    img, _ = render(1280, 800, 0.0, gpx=1.7)
    Image.fromarray((img * 255).astype(np.uint8)).save(sys.argv[1] if len(sys.argv) > 1 else 'port_check.png')
