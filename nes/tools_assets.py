#!/usr/bin/env python3
"""Generates chr.bin and data.inc (tables, nametables, music) for the Neverending Tunnel NES ROM."""
import math, re, sys

out = []
def emit(s=''): out.append(s)
def label(n): emit(f'{n}:')
def bytes_(vals, per=16):
    vals = [v & 0xFF for v in vals]
    for i in range(0, len(vals), per):
        emit('  .byte ' + ','.join(f'${v:02X}' for v in vals[i:i+per]))

# ---------------------------------------------------------------- CHR
FONT = {  # 5x7 column-major, bit0 = top row
 ' ':[0,0,0,0,0],'0':[0x3E,0x51,0x49,0x45,0x3E],'1':[0,0x42,0x7F,0x40,0],'2':[0x42,0x61,0x51,0x49,0x46],
 '3':[0x21,0x41,0x45,0x4B,0x31],'4':[0x18,0x14,0x12,0x7F,0x10],'5':[0x27,0x45,0x45,0x45,0x39],
 '6':[0x3C,0x4A,0x49,0x49,0x30],'7':[0x01,0x71,0x09,0x05,0x03],'8':[0x36,0x49,0x49,0x49,0x36],
 '9':[0x06,0x49,0x49,0x29,0x1E],'A':[0x7E,0x11,0x11,0x11,0x7E],'B':[0x7F,0x49,0x49,0x49,0x36],
 'C':[0x3E,0x41,0x41,0x41,0x22],'D':[0x7F,0x41,0x41,0x22,0x1C],'E':[0x7F,0x49,0x49,0x49,0x41],
 'F':[0x7F,0x09,0x09,0x09,0x01],'G':[0x3E,0x41,0x49,0x49,0x7A],'H':[0x7F,0x08,0x08,0x08,0x7F],
 'I':[0,0x41,0x7F,0x41,0],'J':[0x20,0x40,0x41,0x3F,0x01],'K':[0x7F,0x08,0x14,0x22,0x41],
 'L':[0x7F,0x40,0x40,0x40,0x40],'M':[0x7F,0x02,0x0C,0x02,0x7F],'N':[0x7F,0x04,0x08,0x10,0x7F],
 'O':[0x3E,0x41,0x41,0x41,0x3E],'P':[0x7F,0x09,0x09,0x09,0x06],'Q':[0x3E,0x41,0x51,0x21,0x5E],
 'R':[0x7F,0x09,0x19,0x29,0x46],'S':[0x46,0x49,0x49,0x49,0x31],'T':[0x01,0x01,0x7F,0x01,0x01],
 'U':[0x3F,0x40,0x40,0x40,0x3F],'V':[0x1F,0x20,0x40,0x20,0x1F],'W':[0x3F,0x40,0x38,0x40,0x3F],
 'X':[0x63,0x14,0x08,0x14,0x63],'Y':[0x07,0x08,0x70,0x08,0x07],'Z':[0x61,0x51,0x49,0x45,0x43],
 '.':[0,0x60,0x60,0,0],'-':[8,8,8,8,8],':':[0,0x36,0x36,0,0],'!':[0,0,0x5F,0,0],
 '?':[2,1,0x51,9,6],',':[0,0x50,0x30,0,0],'/':[0x20,0x10,8,4,2],
}

def tile_bytes(px):  # px: 8x8 of 0..3
    p0 = [sum(((px[y][x] & 1) << (7 - x)) for x in range(8)) for y in range(8)]
    p1 = [sum((((px[y][x] >> 1) & 1) << (7 - x)) for x in range(8)) for y in range(8)]
    return bytes(p0 + p1)

def solid_grid(c):   # an 8x8 tunnel tile: one fill colour with 1px grout on the right and bottom
    return tile_bytes([[0 if (x == 7 or y == 7) else c for x in range(8)] for y in range(8)])

blank = [[0]*8 for _ in range(8)]
FONT_OFF = 160                      # text tile = ascii + 160, so the font lives in the fixed 1KB page
font_page = [tile_bytes(blank)] * 64
for ch, cols in FONT.items():
    px = [[0]*8 for _ in range(8)]
    for cx, col in enumerate(cols):
        for y in range(7):
            if col >> y & 1: px[y][cx + 1] = 2
    font_page[ord(ch) - 0x20] = tile_bytes(px)
font_page[0x40 - 0x20] = tile_bytes([[2]*8 for _ in range(8)])   # '@' slot = the light (solid white)
LIGHT_TILE = 0x40 + FONT_OFF
BLANK_TILE = 0x20 + FONT_OFF

# The tunnel is a pixel-exact raster of the original shader (tools/shader_port.py), fitted to NES
# palettes and cut into 8x8 tiles. Every tile position gets its own image per animation state, so the
# CHR is split into 2KB bands that the MMC3 scanline IRQ swaps in as the beam goes down the screen.
import numpy as np
sys.path.insert(0, 'tools')
import shader_port as SP

def _h(a, b, c):
    h = (a * 374761393 + b * 668265263 + c * 2246822519 + 7) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = ((h ^ (h >> 16)) * 2654435761) & 0xFFFFFFFF
    return ((h ^ (h >> 15)) & 0xFFFFFF) / float(1 << 24)

NES_RGB = np.array([[v & 255, (v >> 8) & 255, (v >> 16) & 255] for v in [
 0x525252,0xB40000,0xA00000,0xB1003D,0x740069,0x00005B,0x00005F,0x001840,0x002F10,0x084A08,0x006700,0x124200,0x6D2800,0x000000,0x000000,0x000000,
 0xC4D5E7,0xFF4000,0xDC0E22,0xFF476B,0xD7009F,0x680AD7,0x0019BC,0x0054B1,0x006A5B,0x008C03,0x00AB00,0x2C8800,0xA47200,0x000000,0x000000,0x000000,
 0xF8F8F8,0xFFAB3C,0xFF7981,0xFF5BC5,0xFF48F2,0xDF49FF,0x476DFF,0x00B4F7,0x00E0FF,0x00E375,0x03F42B,0x78B82E,0xE5E218,0x787878,0x000000,0x000000,
 0xFFFFFF,0xFFF2BE,0xF8B8B8,0xF8B8D8,0xFFB6FF,0xFFC3FF,0xC7D1FF,0x9ADAFF,0x88EDF8,0x83FFDD,0xB8F8B8,0xF5F8AC,0xFFFFB0,0xF8D8F8,0x000000,0x000000]], float)
NES_OK = [i for i in range(64) if (i & 15) < 13 or i == 0x0F]
def to_lab(rgb):
    c = np.asarray(rgb, float) / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = (c @ M.T) / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116.0)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)
NES_LAB = to_lab(NES_RGB)
def nes_near(rgb, avoid=()):
    lab = to_lab(rgb)
    best, bd = None, 1e18
    for i in NES_OK:
        if i in avoid: continue
        d = float(((NES_LAB[i] - lab) ** 2).sum())
        if d < bd: best, bd = i, d
    return best

STATES = 16
TW, TH = 256, 208                         # tunnel area: tile rows 2..27
SS = 2                                    # supersampling
GPX = 1.0                                 # grout width in NES pixels

def raster(state):
    img, light = SP.render(TW * SS, TH * SS, state * 24.0 / STATES, gpx=GPX * SS)
    img = img.reshape(TH, SS, TW, SS, 3).mean(axis=(1, 3))
    lt = light.reshape(TH, SS, TW, SS).mean(axis=(1, 3)) > 0.5
    return img * 255.0, lt

def glow_field():
    xs = (np.arange(TW) + 0.5) / TW * 2 - 1; ys = 1 - (np.arange(TH) + 0.5) / TH * 2
    tY = min(1.1, max(0.55, TH / TW)); tX = tY * TW / TH
    X, Y = np.meshgrid(xs, ys)
    d = np.stack([X * tX, Y * tY, -np.ones_like(X)], -1); d /= np.linalg.norm(d, axis=-1, keepdims=True)
    rz = -d[..., 2]
    ang2 = np.maximum(0.0, 2.0 * (1.0 - rz)); sig2 = 1.0 / (SP.LIGHT_D ** 2)
    return 0.55 * np.exp(-ang2 / (sig2 * 4.0)) + 0.16 * np.exp(-ang2 / (sig2 * 40.0))

print('rendering tunnel states...', file=sys.stderr)
RASTERS = [raster(k) for k in range(STATES)]
GLOW = glow_field()

# block palettes: 0 plain, 1 bloom, 2 strong bloom (3 is the text palette)
BR, BC = TH // 16, TW // 16
blk_glow = GLOW.reshape(BR, 16, BC, 16).mean(axis=(1, 3))
blk_pal = np.zeros((BR, BC), int)
blk_pal[blk_glow >= 0.10] = 1
blk_pal[blk_glow >= 0.28] = 2

# The three tile reds map to the NES red ramp ($06 dark, $16 red, $26 light red); the bloom palettes
# step that ramp up by one and by two, ending in white at the light.
PALS = [[0x0F, 0x06, 0x16, 0x26], [0x0F, 0x16, 0x26, 0x36], [0x0F, 0x26, 0x36, 0x30]]
print('bg palettes', [[hex(c) for c in p] for p in PALS], file=sys.stderr)
base = np.array([SP.C_DARK, SP.C_MID, SP.C_BRIGHT]) * 255.0
tint = np.array([1.0, 0.86, 0.78]) * 255.0
ANCHORS = []
for pi in range(3):
    sel = np.kron(blk_pal == pi, np.ones((16, 16), bool))
    g = float(GLOW[sel].mean()) if sel.any() else 0.0
    cols = np.minimum(255.0, base + tint * g)
    if pi == 2: cols[2] = SP.C_LIGHT * 255.0
    ANCHORS.append(np.vstack([SP.C_GROUT * 255.0, cols]))
ANCHORS.append(NES_RGB[[0x0F, 0x06, 0x30, 0x30]])
PALS.append([0x0F, 0x06, 0x30, 0x30])                              # text palette
                              # text palette

DITHER_TOL = 500.0       # only dither where no single palette colour is close
BAYER = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0
PAIRS_IJ = [(i, j) for i in range(4) for j in range(i + 1, 4)]
def fit_tile(img, r, c, pal_idx):
    """Quantize an 8x8 block to the 4 palette entries, using the best two-colour mix + ordered dither."""
    blk = img[(r - 2) * 8:(r - 2) * 8 + 8, c * 8:c * 8 + 8]
    cols = ANCHORS[pal_idx]
    best_res = np.full((8, 8), 1e18); out = np.zeros((8, 8), int)
    ys, xs = np.mgrid[0:8, 0:8]
    thr = BAYER[(ys + (r - 2) * 8) % 4, (xs + c * 8) % 4]
    for i, j in PAIRS_IJ:
        d = cols[j] - cols[i]
        t = np.clip(((blk - cols[i]) @ d) / max(float(d @ d), 1e-6), 0, 1)
        res = ((blk - (cols[i] + t[..., None] * d)) ** 2).sum(-1)
        pick = np.where(thr < t, j, i)
        better = res < best_res
        out = np.where(better, pick, out); best_res = np.where(better, res, best_res)
    d1 = ((blk[:, :, None, :] - cols[None, None]) ** 2).sum(-1)
    nearest = d1.argmin(axis=2)
    return np.where(d1.min(axis=2) < DITHER_TOL, nearest, out)

CHR_TILE = {}      # (state, row, col) -> 8x8 index image
for st, (img, lt) in enumerate(RASTERS):
    for r in range(2, 28):
        for c in range(32):
            CHR_TILE[(st, r, c)] = fit_tile(img, r, c, int(blk_pal[(r - 2) // 2, c // 2]))

bg = None

# ---------------------------------------------------------------- obstacles (background tiles)
# Obstacles are part of the tunnel: blocks of grouted tiles drawn into the nametable at their
# perspective position. Tiles are dark and sparse so they read as a darker mass.
STAGES = 16
def Zst(k): return 0.9 + 0.5 * k
HS, VS = 128.0, 112.0
LANES = [(-1 + l * 2 / 3.0, -1 + (l + 1) * 2 / 3.0) for l in range(3)]
def camx(c2): return (c2 - 2) / 3.0
KINDS = ['pit', 'pillar', 'wall', 'beam']

def obs_tile(cls, var):
    """Box faces in the original use the tunnel's tile colours darkened to 0.42 with grout:
    bright tiles -> NES $06, mid tiles -> half dithered with black, dark tiles -> black."""
    cell = [8, 5, 3, 3][cls]
    px = [[0]*8 for _ in range(8)]
    for y in range(8):
        for x in range(8):
            if cls == 3: continue                                              # pit: black hole
            if x % cell == cell - 1 or y % cell == cell - 1: continue          # grout
            r = _h(var, (y // cell) * 8 + x // cell, 11 + cls)
            if r < 0.516: continue                                             # dark tile -> black
            px[y][x] = 1 if (r >= 0.875 or (x + y) % 2 == 0) else 0
    return tile_bytes(px)
obs_page = [obs_tile(c, v) for c in range(4) for v in range(16)]

def clampi(v, lo, hi): return max(lo, min(hi, v))
def cols(x0, x1):
    c0, c1 = int(round(x0 / 8.0)), int(round(x1 / 8.0))
    if c1 <= c0: c1 = c0 + 1
    return clampi(c0, 0, 32), clampi(c1, 0, 32)
def rows(y0, y1):
    r0, r1 = int(round(y0 / 8.0)), int(round(y1 / 8.0))
    if r1 <= r0: r1 = r0 + 1
    return clampi(r0, 2, 28), clampi(r1, 2, 28)

def span_record(t, c2, lane, k):
    z = Zst(k); cx = camx(c2)
    X0, X1 = LANES[lane]
    cls = 3 if t == 0 else (0 if k == 0 else (1 if k <= 2 else 2))
    if t == 0:       # pit: a strip of floor between z and z+0.5, narrowing with distance
        z1 = z + 0.5
        r_top = int(round((128 + VS / z1) / 8.0)); r_bot = int(round((128 + VS / z) / 8.0))
        r_top, r_bot = clampi(r_top, 2, 28), clampi(r_bot + 1, 2, 28)
        pairs = []
        for r in range(r_top, r_bot):
            y = r * 8 + 4
            zz = clampi(VS / max(1.0, y - 128), z, z1)
            pairs.append(cols(128 + (X0 - cx) * HS / zz, 128 + (X1 - cx) * HS / zz))
        pairs = [pr for pr in pairs if pr[1] > pr[0]]
        if not pairs: return [0x80 | cls, 2, 0]
        return [0x80 | cls, r_top, len(pairs)] + [v for pr in pairs for v in pr]
    ys = {1: (1.0, -1.0), 2: (-0.6, -1.0), 3: (1.0, -0.2)}[t]
    r0, r1 = rows(128 - ys[0] * VS / z, 128 - ys[1] * VS / z)
    c0, c1 = cols(128 + (X0 - cx) * HS / z, 128 + (X1 - cx) * HS / z)
    if c1 <= c0 or r1 <= r0: return [cls, 2, 0, 0, 0]
    return [cls, r0, r1 - r0, c0, c1]

# CHR layout: STATES x 7 bands of 2KB (rows 4g..4g+3, tile = (row%4)*32+col), then one fixed 2KB
# bank with the obstacle tiles (128-191) and the font (192-255).
chunks = []
for st in range(STATES):
    for g in range(7):
        band = []
        for t in range(128):
            r, c = 4 * g + t // 32, t % 32
            if (st, r, c) in CHR_TILE:
                px = CHR_TILE[(st, r, c)]
                band.append(tile_bytes([[int(px[y][x]) for x in range(8)] for y in range(8)]))
            else:
                band.append(tile_bytes(blank))
        chunks.append(b''.join(band))
chunks.append(b''.join(obs_page))
chunks.append(b''.join(font_page))
chr_data = b''.join(chunks)
CHR_BANKS = (len(chr_data) + 8191) // 8192
chr_data += bytes(CHR_BANKS * 8192 - len(chr_data))
open('chr.bin', 'wb').write(chr_data)
print(f'chr {len(chr_data)//1024}KB ({CHR_BANKS} x 8KB)', file=sys.stderr)

# preview of what the PPU will show for a state (for checking the fit)
def preview(state, path):
    from PIL import Image
    out = np.zeros((TH, TW, 3), np.uint8)
    for r in range(2, 28):
        for c in range(32):
            pal = PALS[int(blk_pal[(r - 2) // 2, c // 2])]
            px = CHR_TILE[(state, r, c)]
            out[(r - 2) * 8:(r - 2) * 8 + 8, c * 8:c * 8 + 8] = NES_RGB[np.array(pal)[px]].astype(np.uint8)
    Image.fromarray(out).resize((TW * 3, TH * 3), Image.NEAREST).save(path)
if '--preview' in sys.argv: preview(0, 'preview0.png'); preview(5, 'preview5.png')

# ---------------------------------------------------------------- tables
emit('; generated by tools_assets.py -- do not edit')
emit('.segment "RODATA"')
blobs, blob_idx, ptrs = [], {}, []
for t in range(4):
    for c2 in range(5):
        for lane in range(3):
            for k in range(STAGES):
                rec = tuple(span_record(t, c2, lane, k))
                if rec not in blob_idx:
                    blob_idx[rec] = len(blobs); blobs.append(rec)
                ptrs.append(blob_idx[rec])
emit('SPAN_LO:'); emit('  .lobytes ' + ','.join(f'sp{i}' for i in ptrs))
emit('SPAN_HI:'); emit('  .hibytes ' + ','.join(f'sp{i}' for i in ptrs))
for i, rec in enumerate(blobs):
    label(f'sp{i}'); bytes_(list(rec), 16)
print(f'span records {len(blobs)} unique, {sum(len(r) for r in blobs)} bytes', file=sys.stderr)
label('OBS_HASH'); bytes_([int(_h(i, 3, 9) * 16) % 16 for i in range(64)])
label('JUMPH')
bytes_([round(8 * 4 * t * (28 - t) / 28.0**2) for t in range(29)])

# palettes
label('THEMES')   # 3 shades dark -> light, per theme
THEMES = [(0x06,0x16,0x26),(0x06,0x16,0x26),(0x06,0x16,0x26),(0x05,0x15,0x25),(0x07,0x17,0x27),(0x06,0x16,0x26)]  # reds, like the original
bytes_([c for t in THEMES for c in t], 3)
label('INIT_PAL')
bytes_([v for p_ in PALS for v in p_] + [0x0F] * 16, 4)
label('STATEBANK'); bytes_([14 * st for st in range(STATES)], 16)

# ---------------------------------------------------------------- nametables
def nametable(hud_digits_row=True):
    tiles = [[BLANK_TILE]*32 for _ in range(30)]
    attr_blocks = [[3]*16 for _ in range(15)]          # default: text palette (HUD rows, status bar)
    for r in range(2, 28):
        for c in range(32):
            tiles[r][c] = (r % 4) * 32 + c
    for br in range(1, 14):
        for bc in range(16):
            attr_blocks[br][bc] = int(blk_pal[br - 1][bc])
    return tiles, attr_blocks

def pack_attr(blocks):
    a = []
    for ar in range(8):
        for ac in range(8):
            v = 0
            for i, (dr, dc) in enumerate([(0,0),(0,1),(1,0),(1,1)]):
                br, bc = ar*2+dr, ac*2+dc
                p = blocks[br][bc] if br < 15 else 0
                v |= p << (i*2)
            a.append(v)
    return a

def put(tiles, row, col, s):
    for i, ch in enumerate(s): tiles[row][col+i] = ord(ch) + FONT_OFF

t0, a0 = nametable()
for r in list(range(4, 8)) + list(range(22, 26)):
    for c in range(4, 28):
        t0[r][c] = BLANK_TILE; a0[r//2][c//2] = 3
t1, a1 = nametable()
put(t1, 1, 1, 'DIST 000000 M')
put(t1, 1, 18, 'BEST 000000 M')
for r in (28, 29):
    for c in range(4, 28): t1[r][c] = BLANK_TILE; a1[r//2][c//2] = 3
for name, (t, a) in (('NT0', (t0, a0)), ('NT1', (t1, a1))):
    label(name)
    bytes_([v for row in t for v in row] + pack_attr(a), 32)

# text strings (24 chars each)
def pad24(s):
    s = s.upper(); n = 24 - len(s); l = n // 2
    return ' '*l + s + ' '*(n-l-len(s)+len(s)-len(s)) if False else (' '*l + s + ' '*(n-l))
def strtab(name, items):
    label(name)
    for s in items:
        assert len(s) <= 24, s
        emit('  .byte ' + ','.join(f'${ord(c)+FONT_OFF:02X}' for c in pad24(s)) + f'  ; {s}')
strtab('STR_TITLE', ['NEVERENDING TUNNEL', 'RUN FOR THE LIGHT', 'PRESS START'])
strtab('STR_OVER',  ['GAME OVER', 'YOU FELL', 'YOU TRIPPED', 'YOU HIT YOUR HEAD', 'YOU RAN INTO A PILLAR', 'PRESS START'])
strtab('STR_WHISPER', ['KEEP GOING', 'IT IS GETTING BRIGHTER', 'ALMOST THERE', 'JUST A LITTLE FURTHER',
                       'YOU CAN ALMOST TOUCH IT', 'IT WAS RIGHT THERE', 'CLOSER THAN EVER', 'ANY MOMENT NOW',
                       'PAUSED', ''])
label('STR_DIST'); emit('  .byte ' + ','.join(f'${ord(c)+FONT_OFF:02X}' for c in 'DIST 000000  BEST 000000'))
label('STR_BEST'); emit('  .byte ' + ','.join(f'${ord(c)+FONT_OFF:02X}' for c in '      BEST 000000       '))

# ---------------------------------------------------------------- pitch tables
def freq(m): return 440.0 * 2 ** ((m - 69) / 12)
ms = range(24, 96)
plo = [round(1789773 / (16 * freq(m))) - 1 for m in ms]
tri = [round(1789773 / (32 * freq(m))) - 1 for m in ms]
assert all(p < 2048 for p in plo[9:]), 'pulse range'
plo = [min(p, 2047) for p in plo]
label('PLO'); bytes_([p & 255 for p in plo])
label('PHI'); bytes_([p >> 8 for p in plo])
label('TLO'); bytes_([p & 255 for p in tri])
label('THI'); bytes_([p >> 8 for p in tri])

# ---------------------------------------------------------------- music
NOTE = {'C':0,'D':2,'E':4,'F':5,'G':7,'A':9,'B':11}
def midi(name):
    m = re.fullmatch(r'([A-G])(#?)(\d)', name)
    return 12 * (int(m.group(3)) + 1) + NOTE[m.group(1)] + (1 if m.group(2) else 0)
def n(name): return midi(name) - 23      # token value: 1 = C1 (midi 24)
REST = 0

def seq(s):
    r = []
    for tok in s.split():
        nm, d = tok.split('/')
        r.append((REST if nm == '-' else n(nm), int(d)))
    return r

def finish(tokens, loop=True):
    b = []
    for note, dur in tokens:
        while dur > 255: b += [note, 255]; dur -= 255
        b += [note, dur]
    b += [0xFF if loop else 0xFE]
    return b
def rows(tokens): return sum(d for _, d in tokens)

CHORDS = [  # name: root bass midi, arp tones (4)
    ('Em', 'E2', ['E4','G4','B4','E5']),
    ('C',  'C2', ['C4','E4','G4','C5']),
    ('G',  'G2', ['G3','B3','D4','G4']),
    ('D',  'D2', ['D4','F#4','A4','D5']),
]
def bass_bar(root, variant=0):
    r = midi(root) - 23
    o = r + 12
    pat = [r, r, o, r, r, o, r, o] if variant == 0 else [r, o, r, o, r, o, o + 2 if False else o, r]
    t = []
    for x in pat: t += [(x, 1), (REST, 1)]
    return t
def arp_bar(tones, variant=0):
    t = [n(x) for x in tones]
    pat = [0,1,2,3,2,1,0,1,2,3,2,1,0,1,2,3] if variant == 0 else [3,2,1,0,1,2,3,2,1,0,1,2,3,2,1,0]
    return [(t[i], 1) for i in pat]
K, SN, H, OH, CR = 1, 2, 3, 4, 5
def drum_bar(variant):
    P = {0: {0:K, 2:H, 4:SN, 6:H, 8:K, 10:H, 12:SN, 14:H},
         1: {0:K, 2:H, 4:SN, 6:H, 8:K, 9:K, 10:H, 12:SN, 14:OH},
         2: {0:K, 1:H, 2:H, 4:SN, 6:H, 8:K, 10:K, 12:SN, 13:SN, 14:SN, 15:SN}}[variant]
    t, r = [], 0
    for i in range(16):
        if i in P: t.append((P[i], 1))
        else: t.append((REST, 1))
    return t
def rle(tokens):  # merge consecutive rests
    out_ = []
    for note, dur in tokens:
        if out_ and note == REST and out_[-1][0] == REST: out_[-1] = (REST, out_[-1][1] + dur)
        else: out_.append((note, dur))
    return out_

LEAD_A = ['E5/3 G5/1 B5/4 A5/2 G5/2 E5/4', 'G5/3 E5/1 C5/4 E5/4 G5/4', 'D5/3 G5/1 B5/4 A5/2 G5/2 D5/4',
          'F#5/4 A5/4 D6/4 C#6/2 A5/2', 'B5/6 A5/2 G5/4 E5/4', 'E5/2 G5/2 C6/4 B5/2 G5/2 E5/4',
          'D5/2 G5/2 B5/4 D6/4 B5/2 A5/2', 'A5/2 F#5/2 D5/4 E5/2 F#5/2 A5/4']
LEAD_B = ['E6/2 B5/2 G5/2 B5/2 E6/2 B5/2 G5/2 B5/2', 'E6/2 C6/2 G5/2 C6/2 E6/2 C6/2 G5/2 C6/2',
          'D6/2 B5/2 G5/2 B5/2 D6/2 B5/2 G5/2 B5/2', 'D6/2 A5/2 F#5/2 A5/2 F#6/4 E6/2 D6/2',
          'G6/4 F#6/2 E6/2 B5/4 E6/4', 'E6/4 D6/2 C6/2 G5/4 C6/4',
          'D6/4 B5/2 G5/2 B5/2 D6/2 G6/4', 'A5/2 A5/2 D6/4 C#6/2 A5/2 F#5/4']
for b in LEAD_A + LEAD_B: assert rows(seq(b)) == 16, b

game = [[], [], [], []]
for sec in range(2):
    leads = LEAD_A if sec == 0 else LEAD_B
    for bar in range(8):
        name, root, tones = CHORDS[bar % 4]
        game[0] += seq(leads[bar])
        game[1] += arp_bar(tones, (bar // 4) % 2 if sec else 0)
        game[2] += bass_bar(root, sec)
        dv = 0 if (sec == 0 and bar < 4) else (1 if sec == 0 or bar < 7 else 2)
        game[3] += drum_bar(dv)
game = [rle(c) for c in game]
assert len({rows(c) for c in game}) == 1, [rows(c) for c in game]

# title: slow, spacious
title = [[], [], [], []]
TL = ['E5/16', 'G5/12 E5/4', 'B4/16', 'A5/8 F#5/8']
TL2 = ['B5/8 G5/8', 'E5/8 C6/8', 'D6/12 B5/4', 'F#5/8 A5/8']
for bar in range(8):
    name, root, tones = CHORDS[bar % 4]
    title[0] += seq((TL if bar < 4 else TL2)[bar % 4])
    t = [n(x) for x in tones]
    title[1] += [(t[i], 2) for i in [0,1,2,3,2,1,0,1]]
    title[2] += [(midi(root) - 23, 14), (REST, 2)]
    title[3] += [(REST, 16)]
title = [rle(c) for c in title]
assert len({rows(c) for c in title}) == 1

over = [seq('E5/4 D5/4 B4/4 G4/4 E4/16 -/32'), seq('B4/4 A4/4 F#4/4 D4/4 B3/16 -/32'),
        seq('E3/32 -/32'), seq('CR/0') if False else [(REST, 64)]]
over[3] = [(CR, 2), (REST, 62)]
def lenfix(c, total=64):
    r = rows(c)
    return c + ([(REST, total - r)] if r < total else [])
over = [lenfix(c) for c in over]

songs = [(9, title, True), (6, game, True), (8, over, False)]
emit('SONG_TEMPO:'); bytes_([s[0] for s in songs])
emit('SONG_PLO:'); emit('  .lobytes ' + ','.join(f'song{i}_{c}' for i in range(len(songs)) for c in range(4)))
emit('SONG_PHI:'); emit('  .hibytes ' + ','.join(f'song{i}_{c}' for i in range(len(songs)) for c in range(4)))
for i, (tempo, chans, loop) in enumerate(songs):
    for c in range(4):
        label(f'song{i}_{c}'); bytes_(finish(chans[c], loop))
for i, (tempo, chans, loop) in enumerate(songs):
    print(f'song {i}: {rows(chans[0])} rows, {rows(chans[0])*tempo/60:.1f}s', file=sys.stderr)

open('data.inc', 'w').write('\n'.join(out) + '\n')
