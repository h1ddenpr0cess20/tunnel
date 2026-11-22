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
            if col >> y & 1: px[y][cx + 1] = 1
    font_page[ord(ch) - 0x20] = tile_bytes(px)
font_page[0x40 - 0x20] = tile_bytes([[1]*8 for _ in range(8)])   # '@' slot = the light (solid white)
LIGHT_TILE = 0x40 + FONT_OFF
BLANK_TILE = 0x20 + FONT_OFF

# The tunnel's tiles are random per tile, like the original: tile = hash(ring, side, column),
# 24-ring repeat. A ring tile is (ring a, pattern b); CHR bank state s recolours them so the
# whole mosaic shifts one ring outward each state.
def _h(a, b, c):
    h = (a * 374761393 + b * 668265263 + c * 2246822519 + 7) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = ((h ^ (h >> 16)) * 2654435761) & 0xFFFFFFFF
    return ((h ^ (h >> 15)) & 0xFFFFFF) / float(1 << 24)
def pal3(r): return 1 if r < 0.516 else (2 if r < 0.875 else 3)   # dark / mid / bright, as in the shader
NRINGS, NPAT, STATES = 14, 13, 24
def ring_tile(a, b): return a * NPAT + b
bg = None

# Sprite tiles: shaded boxes, generated per depth stage.
spr = [tile_bytes(blank)]
spr_idx = {spr[0]: 0}
def tile_id(px):
    b = tile_bytes(px)
    if b not in spr_idx:
        spr_idx[b] = len(spr); spr.append(b)
    return spr_idx[b]

STAGES = 16
def S(k): return 1.0 / (1.6 + 0.5 * k)
LS, U = 75.0, 112.0
KINDS = ['pit', 'pillar', 'wall', 'beam']

def _hash(x, y):
    h = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 255) / 256.0

# Obstacles are blocks of the same grouted tiles as the tunnel. The tile size follows
# perspective (8px * scale), colours are the same random dark / mid / bright reds. A sprite tile has
# two fills plus grout, so each 8x8 picks the pair of reds that covers it best.
PAIRS = [(1, 2), (2, 3), (1, 3)]      # sprite palette 0: dark+mid, 1: mid+bright, 2: dark+bright
def box_classes(w, h, kind, s):
    cell = max(2, round(8 * s))
    img = [[0]*w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if x % cell == cell - 1 or y % cell == cell - 1: img[y][x] = 9       # grout
            else: img[y][x] = 1 if kind == 'pit' else pal3(_h(x // cell, y // cell, 5))
    return img

def slice_tile(img, w, h, tx, ty):
    cls = [[img[ty+y][tx+x] if (ty+y < h and tx+x < w) else None for x in range(8)] for y in range(8)]
    counts = {1: 0, 2: 0, 3: 0}
    for r in cls:
        for v in r:
            if v in counts: counts[v] += 1
    best = max(range(3), key=lambda i: counts[PAIRS[i][0]] + counts[PAIRS[i][1]])
    pair = PAIRS[best]
    px = []
    for r in cls:
        row = []
        for v in r:
            if v is None: row.append(0)
            elif v == 9: row.append(3)
            else:
                row.append(1 if abs(v - pair[0]) <= abs(v - pair[1]) else 2)
        px.append(row)
    return px, best

recs, recptr = [], {}
for t, kind in enumerate(KINDS):
    for k in range(STAGES):
        s = S(k)
        w = max(3, round({'pit':0.85,'pillar':0.7,'wall':0.85,'beam':0.85}[kind] * LS * s))
        h = {'pit': max(2, round(0.12*U*s*1.6)), 'pillar': max(4, round(0.9*U*s)),
             'wall': max(3, round(0.4*U*s)), 'beam': max(3, round(0.7*U*s))}[kind]
        top = -224*s if kind == 'beam' else -h
        top = round(top)
        img = box_classes(w, h, kind, s)
        tiles = []
        for ty in range(0, h, 8):
            for tx in range(0, w, 8):
                px, pa = slice_tile(img, w, h, tx, ty)
                tiles.append((tx - w//2, top + ty, tile_id(px), pa))
        recptr[(t, k)] = len(recs)
        recs.append((t, k, tiles))
if len(spr) > 256: sys.exit(f'too many sprite tiles: {len(spr)}')
maxspr = max(len(r[2]) for r in recs)
print(f'sprite tiles {len(spr)}, max sprites per obstacle {maxspr}', file=sys.stderr)

sprite_page = spr + [tile_bytes(blank)] * (256 - len(spr))        # 4KB: units 0-3
chunks = [b''.join(sprite_page)]
chunks.append(b''.join(font_page))                                  # unit 4
for st in range(STATES):
    tiles_ = []
    for a_ in range(NRINGS):
        d_ = a_ + 2
        for b_ in range(NPAT):
            # tile size on screen shrinks progressively toward the light: a ring at tile radius d
            # shows cells of about 0.28*d px; the fractional part is spread over the ring's patterns
            f = 0.25 * d_ + 0.1
            cell = int(f) + (1 if (b_ + 0.5) / NPAT < f - int(f) else 0)
            cell = max(2, min(4, cell))
            k_ = (a_ - st) % 24
            px = [[0]*8 for _ in range(8)]
            for y in range(8):
                for x in range(8):
                    if cell > 1 and (x % cell == cell - 1 or y % cell == cell - 1): continue
                    px[y][x] = pal3(_h(k_, b_ * 64 + (y // cell) * 8 + (x // cell), 1))
            tiles_.append(tile_bytes(px))
    tiles_ += [tile_bytes(blank)] * (192 - len(tiles_))
    chunks.append(b''.join(tiles_))                                 # three 1KB units per state
chr_data = b''.join(chunks)
chr_data += bytes(10 * 8192 - len(chr_data))
open('chr.bin', 'wb').write(chr_data)
print(f'chr {len(chr_data)//1024}KB', file=sys.stderr)

# ---------------------------------------------------------------- tables
emit('; generated by tools_assets.py -- do not edit')
emit('.segment "RODATA"')
for t, kind in enumerate(KINDS):
    for k in range(STAGES):
        pass
emit('REC_LO:'); bytes_([0]*0)  # placeholder to keep labels ordered
out.pop(); out.pop()
emit('REC_LO:'); emit('  .lobytes ' + ','.join(f'rec_{t}_{k}' for t in range(4) for k in range(STAGES)))
emit('REC_HI:'); emit('  .hibytes ' + ','.join(f'rec_{t}_{k}' for t in range(4) for k in range(STAGES)))
for t, k, tiles in recs:
    label(f'rec_{t}_{k}')
    bytes_([len(tiles)] + [v for (dx, dy, ti, pa) in tiles for v in (dx, dy, ti, pa)], 16)

label('FLOORY'); bytes_([round(128 + U*S(k)) for k in range(STAGES)])
label('YOFF')
for k in range(STAGES):
    bytes_([round((c-6) * 7.84 * S(k)) for c in range(16)])
label('LANEOFF')
for k in range(STAGES):
    bytes_([round((i-8)/4.0 * LS * S(k)) for i in range(17)], 17)
emit('LANE_LO:'); emit('  .lobytes ' + ','.join(f'LANEOFF+{k*17}' for k in range(STAGES)))
emit('LANE_HI:'); emit('  .hibytes ' + ','.join(f'LANEOFF+{k*17}' for k in range(STAGES)))
label('JUMPH')
bytes_([round(8 * 4 * t * (28 - t) / 28.0**2) for t in range(29)])

# palettes
label('THEMES')   # 3 shades dark -> light, per theme
THEMES = [(0x06,0x16,0x26),(0x06,0x16,0x26),(0x06,0x16,0x26),(0x05,0x15,0x25),(0x07,0x17,0x27),(0x06,0x16,0x26)]  # reds, like the original
bytes_([c for t in THEMES for c in t], 3)
label('INIT_PAL')
bytes_([0x0F,0x06,0x16,0x26,  0x0F,0x05,0x06,0x16,  0x0F,0x16,0x26,0x36,  0x0F,0x30,0x2C,0x00,
        0x0F,0x06,0x16,0x0F,  0x0F,0x16,0x26,0x0F,  0x0F,0x06,0x26,0x0F,  0x0F,0x06,0x16,0x0F], 4)
label('BANKSEL'); bytes_([5 + 3*st for st in range(STATES)], 12)

# ---------------------------------------------------------------- nametables
def nametable(hud_digits_row=True):
    tiles = [[BLANK_TILE]*32 for _ in range(30)]
    attr_blocks = [[0]*16 for _ in range(15)]
    for r in range(2, 30):
        for c in range(32):
            dx = 15 - c if c <= 15 else c - 16
            dy = 15 - r if r <= 15 else r - 16
            d = max(dx, dy)
            if d <= 1:
                tiles[r][c] = LIGHT_TILE
            else:
                if dx > dy: side, j = (0 if c <= 15 else 1), r
                else:       side, j = (2 if r <= 15 else 3), c
                b_ = int(_h(side, j, 3) * NPAT) % NPAT
                tiles[r][c] = ring_tile(d - 2, b_)
    for br in range(1, 15):
        for bc in range(16):
            # block centre in tile units
            rr = [br * 2, br * 2 + 1]; cc = [bc * 2, bc * 2 + 1]
            dxs = [15 - c if c <= 15 else c - 16 for c in cc]; dys = [15 - r_ if r_ <= 15 else r_ - 16 for r_ in rr]
            dx, dy, r = min(dxs), min(dys), rr[0]
            d = max(dx, dy)
            if d <= 1: attr_blocks[br][bc] = 3          # the light: white from the text palette
            elif d <= 3: attr_blocks[br][bc] = 2        # glow around it
            elif d <= 6: attr_blocks[br][bc] = 1        # fog: far rings are a little darker
            elif dy > dx and r <= 15: attr_blocks[br][bc] = 1   # ceiling is darker
    for bc in range(16): attr_blocks[0][bc] = 3
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
