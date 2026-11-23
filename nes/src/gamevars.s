.segment "ZEROPAGE"
vl:      .res 1          ; run speed, units/s (8.8)
vh_:     .res 1
tgl:     .res 1          ; target run speed
tgh:     .res 1
rtl:     .res 1          ; run time in frames
rth:     .res 1
xl:      .res 1          ; player x (8.8 signed)
xh:      .res 1
hl:      .res 1          ; height above the floor (8.8 signed)
hhi:     .res 1
vvl:     .res 1          ; vertical velocity (8.8 signed)
vvh:     .res 1
duck:    .res 1          ; 0..255 = 0..1
jbuf:    .res 1
spawned: .res 1
nxl:     .res 1          ; distance ahead where the next obstacle starts
nxh:     .res 1
m16l:    .res 1          ; metres run
m16h:    .res 1
L0:      .res 1          ; light distance * 2^22
L1:      .res 1
L2:      .res 1
L3:      .res 1
wm:      .res 1          ; next milestone
hinted:  .res 1
diff:    .res 1
holddn:  .res 1
inpit:   .res 1
eyel:    .res 1          ; h - duck*0.55
eyeh:    .res 1
dsl:     .res 1          ; distance covered this substep
dsh:     .res 1
mAl:     .res 1
mAh:     .res 1
mBl:     .res 1
mBh:     .res 1
mR0:     .res 1
mR1:     .res 1
mR2:     .res 1
mR3:     .res 1
mS0:     .res 1
mS1:     .res 1
mS2:     .res 1
sgn:     .res 1
gt0:     .res 1
gt1:     .res 1
gt2:     .res 1
gt3:     .res 1
nzl:     .res 1
nzh:     .res 1
fzl:     .res 1
fzh:     .res 1
nc0:     .res 1
nc1:     .res 1
nr0:     .res 1
nr1:     .res 1
stype:   .res 1
late:    .res 1
slane:   .res 1
slen:    .res 2
rr1:     .res 1
zin:     .res 1
zif:     .res 1
cls_:    .res 1
fc0:     .res 1
fc1:     .res 1
fr0:     .res 1
fr1:     .res 1
st0l:    .res 1
st0h:    .res 1
st1l:    .res 1
st1h:    .res 1
ac0l:    .res 1
ac0h:    .res 1
ac1l:    .res 1
ac1h:    .res 1
o_ll:    .res 3
o_lh:    .res 3
o_seen:  .res 3

.segment "BSS2"
oldrec:  .res 192        ; per slot: what is drawn on screen (64 bytes each)
newrec:  .res 64
pendrec: .res 192       ; per slot: the target of a redraw that is split over frames
rowev:   .res 30        ; per screen tile row: the scroll list entry that shows it, for the obstacles
cwl:     .res 1          ; camera x for the obstacles
cwh:     .res 1
crow:    .res 1
cey_l:   .res 1          ; eye height the obstacle being built is seen from
cey_h:   .res 1
lightbuf: .res 6
fdig:    .res 4
iseq:    .res 1          ; IRQ: index of the next scroll list entry
ix:      .res 1
iy:      .res 1
ifx:     .res 1          ; IRQ: fine X currently in use
; The scroll list: one entry per IRQ (screen line, bank switch flag, scroll). Two buffers of EVN
; entries; the main loop fills one while the IRQ reads the other. ev_n/ev_y/ev_x share the page
; the sprite buffer used to have (sprites are off).
EVN = 36
ev_n = oam              ; $2006 high byte (nametable); bit 7: switch the tile bank, bit 6: last
ev_y = oam + 2 * EVN    ; Y scroll (source line)
ev_x = oam + 4 * EVN    ; X scroll
ev_o:    .res 2 * EVN   ; $2006 low byte
ev_l:    .res 2 * EVN   ; lines to the next entry minus one
efront:  .res 1         ; buffer the IRQ reads
epend:   .res 1         ; buffer ready for the next frame ($FF: none)
eb:      .res 1
ei:      .res 1
nbf:     .res 8          ; per band: vertical shift (pixels the picture moves up)
nby:     .res 8          ; per band: first source line
nbs:     .res 8          ; per band: first screen line
cmag:    .res 1
csgn:    .res 1
cam_a:   .res 1          ; |x - roll| and sign (above the horizon), |x + roll| and sign (below)
cas_a:   .res 1
cam_b:   .res 1
cas_b:   .res 1
cnt_:    .res 1
cb:      .res 1
cl:      .res 1
cs:      .res 1
ce:      .res 1
cd:      .res 1
qa:      .res 1
qb:      .res 1
qlo:     .res 1
qt:      .res 1
qy:      .res 1
cside:   .res 1          ; strip: $FF above the horizon
csd:     .res 1          ; strip: sign of the shift
cwd:     .res 1          ; strip: lines from the horizon
acl:     .res 1          ; strip: |A| * w
ach:     .res 1
stl_a:   .res 1          ; |A| * 8 above and below
sth_a:   .res 1
stl_b:   .res 1
sth_b:   .res 1
cpx_:    .res 1          ; last X scroll written
cpl:     .res 1          ; its screen line
cctl:    .res 1
ccnt:    .res 1          ; strips in this band after its first entry
ctmp:    .res 1
vok:     .res 1
rbud:    .res 1          ; obstacle rows left to redraw this frame
vkey:    .res 5          ; what the vertical bands were last computed from
ckey:    .res 13         ; what the last scroll list was built from: x, roll, shake, ctrl, vertical shifts
bph:     .res 1          ; head bob phase
cdxl:    .res 1          ; camera x, y (8.8) and roll
cdxh:    .res 1
cdyl:    .res 1
cdyh:    .res 1
crll:    .res 1
crlh:    .res 1
ctx:     .res 1

.segment "BSS"
tsp:     .res 64         ; shear_rec scratch: footprint columns by row
sh_r0:   .res 1
sh_n:    .res 1
sh_cls:  .res 1
sh_flag: .res 1
sh_c0:   .res 1
sh_c1:   .res 1
sh_lo:   .res 1
sh_hi:   .res 1
sh_d:    .res 1
sh_fq:   .res 1
sh_sh:   .res 1
sh_t:    .res 1
sh_o:    .res 1
