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
cwl:     .res 1          ; camera x
cwh:     .res 1
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
lightbuf: .res 6
fdig:    .res 4
iseq:    .res 1          ; IRQ sequence number (band)
ix:      .res 1
bsx:     .res 8          ; per band: horizontal scroll, nametable select, vertical scroll
bsc:     .res 8
bsy:     .res 8
nbx:     .res 8          ; next frame's values, copied in the NMI
nbc:     .res 8
nby:     .res 8

