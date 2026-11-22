; Neverending Tunnel -- NES (NROM-256, vertical mirroring)
; Pseudo-3D tunnel run: three lanes, jump pits and walls, slide under beams, dodge pillars.

.segment "HEADER"
  .byte "NES", $1A, 2, 7, $41, 0, 0, 0, 0, 0, 0, 0, 0, 0   ; MMC3, 32K PRG, 56K CHR

PPUCTRL = $2000
PPUMASK = $2001
PPUSTAT = $2002
OAMADDR = $2003
PPUSCRL = $2005
PPUADDR = $2006
PPUDATA = $2007
OAMDMA  = $4014
JOY1    = $4016

BTN_A = $80
BTN_B = $40
BTN_SEL = $20
BTN_START = $10
BTN_UP = $08
BTN_DOWN = $04
BTN_LEFT = $02
BTN_RIGHT = $01

.segment "ZEROPAGE"
t0: .res 1
t1: .res 1
t2: .res 1
t3: .res 1
ptr: .res 2
ptr2: .res 2
nmi_cnt: .res 1
busy: .res 1
mask: .res 1
ctrl: .res 1
sx: .res 1
pad: .res 1
padn: .res 1
state: .res 1          ; 0 title, 1 run, 2 dying, 3 game over
paused: .res 1
lane: .res 1
cam: .res 1
jt: .res 1
slt: .res 1
cyy: .res 1
hh: .res 1
spd: .res 1
facc: .res 1
tick8: .res 1
cycle: .res 1
theme: .res 1
ftick: .res 1
rnd: .res 1
digits: .res 6
best: .res 6
o_type: .res 3
o_lane: .res 3
o_dl: .res 3
o_dh: .res 3
o_chk: .res 3
spn_l: .res 1
spn_h: .res 1
fade: .res 1
fadet: .res 1
shake: .res 1
flash: .res 1
deadt: .res 1
kind: .res 1
oi: .res 1
stg: .res 1
bx: .res 1
by: .res 1
cnt: .res 1
dyv: .res 1
wh_i: .res 1
wh_t: .res 1
frame: .res 1
slot: .res 1
tmpc: .res 1
q_wr: .res 1
q_rd: .res 1
hud_dirty: .res 1
wh_dirty: .res 1
o_ds: .res 3           ; drawn stage ($FF = nothing drawn)
o_dc: .res 3           ; drawn camera position
o_dty: .res 3          ; drawn type / lane (an obstacle may be gone before it is erased)
o_dla: .res 3
o_prog: .res 3         ; row to resume a partly sent redraw at
gtype: .res 1
gcam: .res 1
glane: .res 1
gstage: .res 1
sr0: .res 2
sn: .res 2
scls: .res 1
slst: .res 2
sdl: .res 2
sdh: .res 2
scl2: .res 1
rr: .res 1
rmin: .res 1
rmax: .res 1
havo: .res 1
havn: .res 1
c0o: .res 1
c1o: .res 1
c0n: .res 1
c1n: .res 1
u0: .res 1
u1: .res 1
hsh: .res 1
tbase: .res 1
spc0: .res 1
spc1: .res 1
tyv: .res 1
np: .res 2
nt0: .res 1
nt1: .res 1
nt2: .res 1
; music
mus_on: .res 1
tempo: .res 1
tickc: .res 1
song4: .res 1
m_pl: .res 4
m_ph: .res 4
m_tm: .res 4
m_note: .res 4
m_age: .res 4
m_vol: .res 4
m_lh: .res 4
; sfx
sp_t: .res 1
sp_lo: .res 1
sp_hi: .res 1
sp_d: .res 1
sp_v: .res 1
sp_vd: .res 1
sp_duty: .res 1
sp_lh: .res 1
sn_t: .res 1
sn_v: .res 1
sn_vd: .res 1
sn_per: .res 1
sn_first: .res 1

.segment "OAM"
oam: .res 256

.segment "QUEUE"
qbuf: .res 256

.segment "BSS"
pal: .res 32
rowbuf: .res 32

.segment "CODE"

; ------------------------------------------------------------------ reset
reset:
  sei
  cld
  ldx #$40
  stx $4017
  ldx #$FF
  txs
  inx
  stx PPUCTRL
  stx PPUMASK
  stx $4010
  bit PPUSTAT
: bit PPUSTAT
  bpl :-
  lda #0
  tax
: sta $00,x
  sta $0300,x
  sta $0400,x
  sta $0500,x
  sta $0600,x
  sta $0700,x
  lda #$F0
  sta oam,x
  lda #0
  inx
  bne :-
: bit PPUSTAT
  bpl :-

  lda #0
  sta $8000
  lda #0
  sta $8001              ; R0 = sprite tiles 0-127
  lda #1
  sta $8000
  lda #2
  sta $8001              ; R1 = sprite tiles 128-255
  lda #0
  sta OAMADDR
  lda #>oam
  sta OAMDMA             ; sprites stay hidden: obstacles are background tiles
  lda #$0F
  sta $4015
  lda #$C7
  sta rnd
  ; palettes
  ldx #31
: lda INIT_PAL,x
  sta pal,x
  dex
  bpl :-
  jsr load_nametables
  jsr draw_title
  lda #2
  sta state
  jsr go_title
  lda #$1E
  sta mask
  lda #$90
  sta ctrl
  lda PPUSTAT
  lda ctrl
  sta PPUCTRL
main:
  jsr wait_nmi
  inc frame
  jsr rand
  jsr read_pad
  lda padn
  eor rnd
  sta rnd
  bne :+
  inc rnd
:
  lda state
  beq st_title
  cmp #1
  beq st_run
  cmp #2
  beq st_dying
  jmp st_over

st_title:
  jsr tunnel_anim
  jsr clear_sprites
  jsr update_pal
  lda padn
  and #BTN_START
  beq main
  jsr start_game
  jmp main

st_over:
  jsr tunnel_anim
  jsr clear_sprites
  jsr update_pal
  lda padn
  and #BTN_START
  beq main
  jsr start_game
  jmp main

st_run:
  lda padn
  and #BTN_START
  beq :+
  jsr toggle_pause
: lda paused
  beq :+
  jsr update_pal
  jmp main
: jsr game_update
  jsr draw_obstacles
  jsr tunnel_anim
  jsr update_pal
  jmp main

st_dying:
  jsr dying_update
  jsr draw_obstacles
  jsr tunnel_anim
  jsr update_pal
  jmp main

wait_nmi:
  lda nmi_cnt
: cmp nmi_cnt
  beq :-
  rts

read_pad:
  lda pad
  pha
  lda #1
  sta JOY1
  lda #0
  sta JOY1
  sta pad
  ldx #8
: lda JOY1
  lsr a
  rol pad
  dex
  bne :-
  pla
  eor #$FF
  and pad
  sta padn
  rts

rand:
  lda rnd
  asl a
  bcc :+
  eor #$1D
: sta rnd
  rts

; ------------------------------------------------------------------ PPU setup
load_nametables:
  lda PPUSTAT
  lda #$20
  sta PPUADDR
  lda #$00
  sta PPUADDR
  lda #<NT0
  sta ptr
  lda #>NT0
  sta ptr+1
  jsr copy_nt
  lda #$24
  sta PPUADDR
  lda #$00
  sta PPUADDR
  lda #<NT1
  sta ptr
  lda #>NT1
  sta ptr+1
copy_nt:                 ; 1024 bytes from (ptr)
  ldx #4
  ldy #0
: lda (ptr),y
  sta PPUDATA
  iny
  bne :-
  inc ptr+1
  dex
  bne :-
  rts

; A = row, ptr -> 24 characters
draw_text:
  sta t0
  lda PPUSTAT
  lda t0
  lsr a
  lsr a
  lsr a
  clc
  adc #$20
  sta PPUADDR
  lda t0
  and #7
  asl a
  asl a
  asl a
  asl a
  asl a
  ora #4
  sta PPUADDR
  ldy #0
: lda (ptr),y
  sta PPUDATA
  iny
  cpy #24
  bne :-
  rts

; t0 = row, t1 = column, ptr -> six digits (least significant first)
put_digits:
  lda PPUSTAT
  lda t0
  lsr a
  lsr a
  lsr a
  clc
  adc #$20
  sta PPUADDR
  lda t0
  and #7
  asl a
  asl a
  asl a
  asl a
  asl a
  ora t1
  sta PPUADDR
  ldy #5
: lda (ptr),y
  clc
  adc #$D0
  sta PPUDATA
  dey
  bpl :-
  rts

; ptr2 = &string table (24 bytes each), X = index -> ptr
str_ptr:
  lda ptr2
  sta ptr
  lda ptr2+1
  sta ptr+1
  txa
  beq @r
: lda ptr
  clc
  adc #24
  sta ptr
  bcc :+
  inc ptr+1
: dex
  bne :--
@r:
  rts

.macro SETSTR tab, idx, row
  lda #<tab
  sta ptr2
  lda #>tab
  sta ptr2+1
  ldx #idx
  jsr str_ptr
  lda #row
  jsr draw_text
.endmacro

draw_title:
  lda #0
  sta PPUMASK
  SETSTR STR_TITLE, 0, 5
  SETSTR STR_TITLE, 1, 6
  lda #<STR_BEST
  sta ptr
  lda #>STR_BEST
  sta ptr+1
  lda #23
  jsr draw_text_wide
  SETSTR STR_TITLE, 2, 24
  lda #<best
  sta ptr
  lda #0
  sta ptr+1
  lda #23
  sta t0
  lda #4+6+5
  sta t1
  jsr put_digits
  rts

; same as draw_text (alias kept for readability)
draw_text_wide:
  jmp draw_text

show_over:
  lda #1
  sta busy
  lda #0
  sta PPUMASK
  SETSTR STR_OVER, 0, 5
  lda kind
  clc
  adc #1
  tax
  lda #<STR_OVER
  sta ptr2
  lda #>STR_OVER
  sta ptr2+1
  jsr str_ptr
  lda #6
  jsr draw_text
  lda #<STR_DIST
  sta ptr
  lda #>STR_DIST
  sta ptr+1
  lda #23
  jsr draw_text
  lda #<digits
  sta ptr
  lda #0
  sta ptr+1
  lda #23
  sta t0
  lda #4+5
  sta t1
  jsr put_digits
  lda #<best
  sta ptr
  lda #23
  sta t0
  lda #4+18
  sta t1
  jsr put_digits
  SETSTR STR_OVER, 5, 24
  lda #0
  sta busy
  rts

; ------------------------------------------------------------------ NMI
nmi:
  pha
  txa
  pha
  tya
  pha
  inc nmi_cnt
  jsr set_banks
  lda busy
  bne :+
  jsr ppu_update
: jsr music_update
  pla
  tay
  pla
  tax
  pla
  rti

set_banks:                 ; the tunnel mosaic is advanced by swapping CHR banks
  ldx cycle
  lda BANKSEL,x
  ldy #2
  sty $8000
  sta $8001              ; R2: ring tiles 0-63
  clc
  adc #1
  ldy #3
  sty $8000
  sta $8001              ; R3: ring tiles 64-127
  ldy #4
  sty $8000
  lda #5
  sta $8001              ; R4: obstacle tiles
  ldy #5
  sty $8000
  lda #4
  sta $8001              ; R5: font
  rts

ppu_update:
  lda PPUSTAT
  lda #$3F
  sta PPUADDR
  lda #0
  sta PPUADDR
  ldx #0
: lda pal,x
  sta PPUDATA
  inx
  cpx #16                ; background palettes only: there are no sprites
  bne :-
  lda hud_dirty
  beq @nohud
  lda #0
  sta hud_dirty
  lda #$24
  sta PPUADDR
  lda #$26
  sta PPUADDR
  ldx #5
: lda digits,x
  clc
  adc #$D0
  sta PPUDATA
  dex
  bpl :-
  lda #$24
  sta PPUADDR
  lda #$37
  sta PPUADDR
  ldx #5
: lda best,x
  clc
  adc #$D0
  sta PPUDATA
  dex
  bpl :-
@nohud:
  lda wh_dirty
  beq @nowh
  lda #0
  sta wh_dirty
  lda #$27
  sta PPUADDR
  lda #$84
  sta PPUADDR
  ldx #9
  lda wh_t
  beq :+
  ldx wh_i
: lda paused
  beq :+
  ldx #8
: lda #<STR_WHISPER
  sta np
  lda #>STR_WHISPER
  sta np+1
  txa
  beq @go
: lda np
  clc
  adc #24
  sta np
  bcc :+
  inc np+1
: dex
  bne :--
@go:
  ldy #0
: lda (np),y
  sta PPUDATA
  iny
  cpy #24
  bne :-
@nowh:
  ; drain the tile queue: runs of (addr hi, addr lo, length, tiles...)
  lda #64
  sta nt0
@q:
  lda q_rd
  cmp q_wr
  beq @qdone
  tax
  lda qbuf,x
  sta PPUADDR
  inx
  lda qbuf,x
  sta PPUADDR
  inx
  lda qbuf,x
  inx
  tay
  sty nt1
: lda qbuf,x
  sta PPUDATA
  inx
  dey
  bne :-
  stx q_rd
  lda nt0
  sec
  sbc nt1
  bcc @qdone
  sbc #3
  bcc @qdone
  sta nt0
  jmp @q
@qdone:
  lda PPUSTAT
  lda sx
  sta PPUSCRL
  lda #0
  sta PPUSCRL
  lda ctrl
  sta PPUCTRL
  lda mask
  sta PPUMASK
  rts

irq:
  rti

; ------------------------------------------------------------------ game flow
go_title:
  lda #0
  sta state
  sta fade
  sta shake
  sta flash
  sta jt
  sta slt
  lda #2
  sta cam
  lda #6
  sta cyy
  lda #50
  sta spd
  lda #0
  jsr music_start
  rts

start_game:
  lda #1
  sta state
  lda #0
  ldx #5
: sta digits,x
  dex
  bpl :-
  sta paused
  sta jt
  sta slt
  sta fade
  sta fadet
  sta shake
  sta flash
  sta wh_t
  sta wh_i
  sta ftick
  sta facc
  sta theme
  ldx #2
: sta o_type,x
  dex
  bpl :-
  lda #1
  sta lane
  lda #2
  sta cam
  lda #6
  sta cyy
  lda #120
  sta spd
  lda #$00
  sta spn_l
  lda #$30
  sta spn_h
  ldx #2
  lda #$FF
: sta o_ds,x
  dex
  bpl :-
  lda #0
  sta o_prog
  sta o_prog+1
  sta o_prog+2
  jsr reload_nt1
  lda #1
  sta hud_dirty
  sta wh_dirty
  lda ctrl
  ora #1
  sta ctrl
  lda frame
  eor rnd
  ora #1
  sta rnd
  lda #1
  jsr music_start
  lda #6
  jsr sfx_play
  rts

reload_nt1:                ; forget any obstacle tiles left in the play nametable
  lda #1
  sta busy
  lda #0
  sta PPUMASK
  lda PPUSTAT
  lda #$24
  sta PPUADDR
  lda #$00
  sta PPUADDR
  lda #<NT1
  sta ptr
  lda #>NT1
  sta ptr+1
  jsr copy_nt
  lda #0
  sta q_rd
  sta q_wr
  sta busy
  rts

toggle_pause:
  lda paused
  eor #1
  sta paused
  lda #1
  sta wh_dirty
  lda paused
  beq @unp
  lda #0
  sta mus_on
  sta $4015
  rts
@unp:
  lda #1
  sta mus_on
  lda #$0F
  sta $4015
  ldx #3
  lda #$FF
: sta m_lh,x
  dex
  bpl :-
  rts

; ------------------------------------------------------------------ simulation
game_update:
  ; speed ramp
  inc ftick
  bne :+
  lda spd
  cmp #230
  bcs :+
  clc
  adc #4
  sta spd
: lda spd
  lsr a
  sta t0
  ; distance
  clc
  lda facc
  adc t0
  sta facc
  bcc :+
  jsr inc_dist
: ; tunnel colour cycling
  lda tick8
  clc
  adc t0
  sta tick8
  bcc :+
  jsr step_state
: ; input
  lda padn
  and #BTN_LEFT
  beq :+
  lda lane
  beq :+
  dec lane
  lda #2
  jsr sfx_play
: lda padn
  and #BTN_RIGHT
  beq :+
  lda lane
  cmp #2
  bcs :+
  inc lane
  lda #2
  jsr sfx_play
: lda padn
  and #(BTN_A | BTN_UP)
  beq :+
  lda jt
  bne :+
  lda #1
  sta jt
  lda #0
  sta slt
  jsr sfx_play        ; A=0 jump
: lda padn
  and #(BTN_B | BTN_DOWN)
  beq :+
  lda jt
  bne :+
  lda slt
  bne :+
  lda #26
  sta slt
  lda #1
  jsr sfx_play
: ; jump arc
  lda jt
  beq @nojump
  inc jt
  lda jt
  cmp #28
  bcc :+
  lda #0
  sta jt
  lda #3
  jsr sfx_play
: ldx jt
  lda JUMPH,x
  jmp @sethh
@nojump:
  lda #0
@sethh:
  sta hh
  clc
  adc #6
  sta cyy
  lda slt
  beq :+
  dec slt
  lda #1
  sta cyy
: ; camera follows lane (quarter-lane steps)
  lda frame
  and #1
  bne @camdone
  lda lane
  asl a
  cmp cam
  beq @camdone
  bcc @camdn
  inc cam
  jmp @camdone
@camdn:
  dec cam
@camdone:
  ; theme follows hundreds digit
  lda digits+2
@th:
  cmp #6
  bcc :+
  sbc #6
  jmp @th
: sta theme
  ; whisper timer
  lda wh_t
  beq :+
  dec wh_t
  bne :+
  lda #1
  sta wh_dirty
: ; obstacles
  ldx #2
@ob:
  lda o_type,x
  beq @obnext
  lda o_dl,x
  sec
  sbc spd
  sta o_dl,x
  lda o_dh,x
  sbc #0
  sta o_dh,x
  bcs :+
  lda #0
  sta o_type,x
  beq @obnext
: lda o_chk,x
  bne @obnext
  lda o_dh,x
  cmp #6
  bcs @obnext
  lda #1
  sta o_chk,x
  jsr check_hit
@obnext:
  dex
  bpl @ob
  lda state
  cmp #1
  bne @ret
  ; spawn
  lda spn_l
  sec
  sbc spd
  sta spn_l
  lda spn_h
  sbc #0
  sta spn_h
  bcs @ret
  jsr spawn
@ret:
  rts

step_state:
  inc cycle
  lda cycle
  cmp #24
  bcc :+
  lda #0
  sta cycle
: rts

inc_dist:
  lda #1
  sta hud_dirty
  ldx #0
: inc digits,x
  lda digits,x
  cmp #10
  bcc @done
  lda #0
  sta digits,x
  inx
  cpx #6
  bcc :-
  rts
@done:
  ; every 100 m a whisper
  cpx #2
  bne :+
  lda wh_i
  clc
  adc #1
  and #7
  sta wh_i
  lda #200
  sta wh_t
  lda #1
  sta wh_dirty
: rts

; spawn an obstacle (and sometimes a second one in another lane)
spawn:
  jsr rand
  and #3
  sta t0                  ; type 0..3
  jsr rand
  sta t1
  and #$7F
  tay
: cpy #3
  bcc :+
  tya
  sec
  sbc #3
  tay
  jmp :-
: sty t2                  ; lane 0..2
  jsr add_obstacle
  ; a second obstacle once past 1000 m ... or 100 m
  lda digits+2
  ora digits+3
  beq @gap
  lda t1
  bpl @gap
  jsr rand
  and #3
  sta t0
  lda t2
  clc
  adc #1
  ldx t1
  cpx #$C0
  bcc :+
  adc #0                  ; skip one more lane
: cmp #3
  bcc :+
  sbc #3
  cmp #3
  bcc :+
  sbc #3
: sta t2
  jsr add_obstacle
@gap:
  jsr rand
  lda rnd
  lsr a
  lsr a
  lsr a
  lsr a                   ; 0..15 (x 256)
  clc
  adc #$14
  sta spn_h
  lda spd                 ; plus speed * 32
  asl a
  asl a
  asl a
  asl a
  asl a
  sta spn_l
  lda spd
  lsr a
  lsr a
  lsr a
  clc
  adc spn_h
  sta spn_h
  rts

add_obstacle:
  ldx #2
: lda o_type,x
  beq @free
  dex
  bpl :-
  rts
@free:
  lda t0
  clc
  adc #1
  sta o_type,x
  lda t2
  sta o_lane,x
  lda #0
  sta o_dl,x
  sta o_chk,x
  sta o_prog,x
  lda #$FF
  sta o_ds,x
  lda #63
  sta o_dh,x
  rts

; X = obstacle slot; decides whether the runner survives it
check_hit:
  lda o_lane,x
  cmp lane
  bne @safe
  lda o_type,x
  cmp #1
  beq @pit
  cmp #2
  beq @pillar
  cmp #3
  beq @wall
  ; beam: need to be sliding
  lda slt
  bne @safe
  lda #2
  jmp die
@pit:
  lda hh
  cmp #2
  bcs @safe
  lda #0
  jmp die
@pillar:
  lda #3
  jmp die
@wall:
  lda hh
  cmp #5
  bcs @safe
  lda #1
  jmp die
@safe:
  rts

; A = kind (0 fell, 1 tripped, 2 hit head, 3 pillar)
die:
  sta kind
  stx t3
  lda #2
  sta state
  lda #0
  sta deadt
  sta fadet
  lda kind
  bne @crash
  lda #5
  jsr sfx_play
  lda #1
  sta fade
  jmp @mus
@crash:
  lda #4
  jsr sfx_play
  lda #5
  sta flash
  lda #24
  sta shake
@mus:
  lda #2
  jsr music_start
  ldx t3
  rts

dying_update:
  inc deadt
  lda frame
  and #7
  bne :+
  lsr spd
: lda flash
  beq :+
  dec flash
: lda shake
  beq :+
  dec shake
: lda kind
  bne @nofade
  ; fall: sink and fade out
  lda #2
  sta cyy
  lda deadt
  and #15
  bne :+
  lda fade
  cmp #4
  bcs :+
  inc fade
: jmp @obs
@nofade:
  lda deadt
  cmp #40
  bcc @obs
  and #15
  bne @obs
  lda fade
  cmp #3
  bcs @obs
  inc fade
@obs:
  ; obstacles keep approaching, slowly
  ldx #2
: lda o_type,x
  beq :+
  lda o_dl,x
  sec
  sbc spd
  sta o_dl,x
  lda o_dh,x
  sbc #0
  sta o_dh,x
  bcs :+
  lda #0
  sta o_type,x
: dex
  bpl :--
  lda deadt
  cmp #110
  bcc @r
  ; compare against best
  ldx #5
: lda digits,x
  cmp best,x
  bcc @nobest
  bne @newbest
  dex
  bpl :-
  jmp @nobest
@newbest:
  ldx #5
: lda digits,x
  sta best,x
  dex
  bpl :-
@nobest:
  lda #3
  sta state
  lda ctrl
  and #$FE
  sta ctrl
  lda #0
  sta fade
  sta shake
  sta flash
  jsr show_over
@r:
  rts

; ------------------------------------------------------------------ visuals
tunnel_anim:               ; tunnel keeps flowing in title / game over screens
  lda state
  cmp #1
  beq @r
  cmp #2
  beq @r
  lda spd
  lsr a
  sta t0
  lda state
  beq @title
  lda #0
  sta t0
@title:
  lda tick8
  clc
  adc t0
  sta tick8
  bcc @r
  jsr step_state
@r:
  rts

update_pal:
  ldx #31                ; start from the stock palettes so fades never stick
: lda INIT_PAL,x
  sta pal,x
  dex
  bpl :-
  ; the light flickers
  lda frame
  lsr a
  lsr a
  and #1
  tax
  lda @flick,x
  sta pal+14
  ; apply flash / fade
  lda #$0F
  sta pal
  lda flash
  beq :+
  lda #$30
  sta pal
: lda fade
  beq @nofade
  sta t0
  ldx #31
@fd:
  lda pal,x
  ldy t0
@fy:
  cmp #$10
  bcc @blk
  sec
  sbc #$10
  jmp @fn
@blk:
  lda #$0F
@fn:
  dey
  bne @fy
  sta pal,x
  dex
  bpl @fd
@nofade:
  ; crash shake
  lda shake
  beq @noshake
  and #3
  tax
  lda @shk,x
  sta sx
  rts
@noshake:
  lda #0
  sta sx
  rts
@shk: .byte 0, 3, 0, 253
@flick: .byte $20, $30

clear_sprites:
  lda #$F0
  ldx #0
: sta oam,x
  inx
  inx
  inx
  inx
  bne :-
  rts

; ------------------------------------------------------------------ obstacles in the nametable
; Obstacles are tunnel geometry: blocks of tiles drawn into the play nametable at their perspective
; position and streamed to the PPU through a queue. Footprints are precomputed per
; (type, camera, lane, depth stage) -- see tools_assets.py.
draw_obstacles:
  lda #0
  sta slot
@loop:
  ldx slot
  jsr update_slot
  inc slot
  lda slot
  cmp #3
  bne @loop
  rts

; X = slot
update_slot:
  stx t3
  lda o_type,x
  beq @gone
  lda o_dh,x
  lsr a
  lsr a
  sta stg
  cmp o_ds,x
  bne @redraw
  lda cam
  cmp o_dc,x
  bne @redraw
  rts
@gone:
  lda o_ds,x
  cmp #$FF
  bne @redraw
  rts
@redraw:
  lda o_dty,x            ; set 0 = what is on screen now
  sta gtype
  lda o_dla,x
  sta glane
  lda o_dc,x
  sta gcam
  lda o_ds,x
  sta gstage
  ldx #0
  jsr load_set
  ldx t3                 ; set 1 = what should be there
  lda o_type,x
  beq @none
  sec
  sbc #1
  sta gtype
  lda o_lane,x
  sta glane
  lda cam
  sta gcam
  lda stg
  sta gstage
  jmp @ld1
@none:
  lda #$FF
  sta gstage
@ld1:
  ldx #1
  jsr load_set
  lda #255               ; the rows to touch
  sta rmin
  lda #0
  sta rmax
  ldx #1
@mm:
  lda sn,x
  beq @mnext
  lda sr0,x
  cmp rmin
  bcs :+
  sta rmin
: lda sr0,x
  clc
  adc sn,x
  cmp rmax
  bcc @mnext
  sta rmax
@mnext:
  dex
  bpl @mm
  lda rmin
  cmp rmax
  bcs @finish
  ldx t3
  lda o_prog,x
  cmp rmin
  bcs :+
  lda rmin
: sta rr
  lda scls
  asl a
  asl a
  asl a
  asl a
  clc
  adc #128
  sta tbase
@row:
  lda rr
  cmp rmax
  bcs @finish
  jsr do_row
  bcs @defer
  inc rr
  jmp @row
@defer:                  ; queue full: carry on next frame
  ldx t3
  lda rr
  sta o_prog,x
  rts
@finish:
  ldx t3
  lda #0
  sta o_prog,x
  lda o_type,x
  bne @keep
  lda #$FF
  sta o_ds,x
  rts
@keep:
  sec
  sbc #1
  sta o_dty,x
  lda o_lane,x
  sta o_dla,x
  lda cam
  sta o_dc,x
  lda stg
  sta o_ds,x
  rts

; X = set (0 old / 1 new); uses gtype gcam glane gstage
load_set:
  lda gstage
  cmp #$FF
  bne :+
  lda #0
  sta sn,x
  sta sr0,x
  rts
: stx t2
  lda gtype
  asl a
  asl a
  clc
  adc gtype              ; type * 5
  clc
  adc gcam
  sta t0
  asl a
  clc
  adc t0                 ; * 3
  clc
  adc glane
  sta t0                 ; v = (type*5+cam)*3+lane, 0..59
  lsr a
  lsr a
  lsr a
  lsr a
  sta t1                 ; high byte of v*16
  lda t0
  asl a
  asl a
  asl a
  asl a
  ora gstage
  sta t0                 ; low byte of v*16+stage
  lda #<SPAN_LO
  clc
  adc t0
  sta ptr
  lda #>SPAN_LO
  adc t1
  sta ptr+1
  ldy #0
  lda (ptr),y
  pha
  lda #<SPAN_HI
  clc
  adc t0
  sta ptr
  lda #>SPAN_HI
  adc t1
  sta ptr+1
  lda (ptr),y
  sta ptr+1
  pla
  sta ptr                ; ptr -> footprint record
  ldx t2
  lda (ptr),y
  pha
  and #$7F
  sta scl2
  pla
  and #$80
  sta slst,x
  iny
  lda (ptr),y
  sta sr0,x
  iny
  lda (ptr),y
  sta sn,x
  lda ptr
  clc
  adc #3
  sta sdl,x
  lda ptr+1
  adc #0
  sta sdh,x
  cpx #1
  bne :+
  lda scl2
  sta scls
: rts

; rr = row, X = set: carry set if the row is not covered, else spc0/spc1 = first/last+1 column
span_at:
  lda rr
  sec
  sbc sr0,x
  bcc @empty
  cmp sn,x
  bcs @empty
  sta t2
  lda sdl,x
  sta ptr2
  lda sdh,x
  sta ptr2+1
  lda slst,x
  beq @rect
  lda t2
  asl a
  tay
  jmp @get
@rect:
  ldy #0
@get:
  lda (ptr2),y
  sta spc0
  iny
  lda (ptr2),y
  sta spc1
  clc
  rts
@empty:
  sec
  rts

; Redraws row rr: tiles under the new footprint become obstacle, tiles that only the old
; footprint covered are restored from the stock nametable. Carry set = queue full.
do_row:
  lda #0
  sta havo
  sta havn
  ldx #0
  jsr span_at
  bcs @n
  lda spc0
  sta c0o
  lda spc1
  sta c1o
  lda #1
  sta havo
@n:
  ldx #1
  jsr span_at
  bcs @u
  lda spc0
  sta c0n
  lda spc1
  sta c1n
  lda #1
  sta havn
@u:
  lda havo
  ora havn
  bne :+
  clc
  rts
: lda havo
  beq @unew
  lda havn
  beq @uold
  lda c0o
  cmp c0n
  bcc :+
  lda c0n
: sta u0
  lda c1o
  cmp c1n
  bcs :+
  lda c1n
: sta u1
  jmp @build
@uold:
  lda c0o
  sta u0
  lda c1o
  sta u1
  jmp @build
@unew:
  lda c0n
  sta u0
  lda c1n
  sta u1
@build:
  lda rr                 ; ptr = stock nametable row
  lsr a
  lsr a
  lsr a
  sta t0
  lda rr
  asl a
  asl a
  asl a
  asl a
  asl a
  clc
  adc #<NT1
  sta ptr
  lda t0
  adc #>NT1
  sta ptr+1
  lda rr                 ; hash start = (rr*7 + u0*5) & 63
  asl a
  asl a
  asl a
  sec
  sbc rr
  sta t0
  lda u0
  asl a
  asl a
  clc
  adc u0
  clc
  adc t0
  and #63
  sta hsh
  ldy u0
  ldx #0
@col:
  lda havn
  beq @base
  cpy c0n
  bcc @base
  cpy c1n
  bcs @base
  stx tmpc
  ldx hsh
  lda OBS_HASH,x
  clc
  adc tbase
  ldx tmpc
  jmp @put
@base:
  lda (ptr),y
@put:
  sta rowbuf,x
  inx
  lda hsh
  clc
  adc #5
  and #63
  sta hsh
  iny
  cpy u1
  bne @col
  stx t2                 ; run length
  lda q_rd               ; room in the queue?
  sec
  sbc q_wr
  sec
  sbc #1
  sta t0
  lda t2
  clc
  adc #3
  cmp t0
  beq :+
  bcs @full
: lda rr                 ; PPU address = $2400 + rr*32 + u0
  asl a
  asl a
  asl a
  asl a
  asl a
  clc
  adc u0
  sta t0
  lda #0
  adc #0
  sta tmpc
  lda rr
  lsr a
  lsr a
  lsr a
  clc
  adc tmpc
  clc
  adc #$24
  sta t1
  ldx q_wr
  lda t1
  sta qbuf,x
  inx
  lda t0
  sta qbuf,x
  inx
  lda t2
  sta qbuf,x
  inx
  ldy #0
: lda rowbuf,y
  sta qbuf,x
  inx
  iny
  cpy t2
  bne :-
  stx q_wr
  clc
  rts
@full:
  sec
  rts

; ------------------------------------------------------------------ sound
; sfx ids: 0 jump, 1 slide, 2 lane, 3 land, 4 crash, 5 fall, 6 start
sfx_play:
  tay
  lda SFX_CH,y
  bne @noise
  lda SFX_PLO,y
  sta sp_lo
  lda SFX_PHI,y
  sta sp_hi
  lda SFX_D,y
  sta sp_d
  lda SFX_V,y
  sta sp_v
  lda SFX_VD,y
  sta sp_vd
  lda SFX_DUTY,y
  sta sp_duty
  lda SFX_DUR,y
  sta sp_t
  lda #$FF
  sta sp_lh
  rts
@noise:
  lda SFX_PLO,y
  sta sn_per
  lda SFX_V,y
  sta sn_v
  lda SFX_VD,y
  sta sn_vd
  lda SFX_DUR,y
  sta sn_t
  lda #1
  sta sn_first
  rts

SFX_CH:   .byte 0,   1,   0,   1,   1,   0,   0
SFX_PLO:  .byte $50, $05, $00, $0A, $0B, $00, $00
SFX_PHI:  .byte $01, $00, $01, $00, $00, $01, $03
SFX_D:    .byte $F2, $00, $F8, $00, $00, $0A, $EC
SFX_V:    .byte $B0, $80, $90, $C0, $F0, $B0, $A0
SFX_VD:   .byte $0C, $06, $18, $18, $08, $06, $08
SFX_DUR:  .byte 14,  22,  7,   7,   34,  44,  22
SFX_DUTY: .byte 2,   0,   2,   0,   0,   2,   1

sfx_update:
  lda sp_t
  beq @noise
  dec sp_t
  bne @run
  lda #$30               ; end: silence, let music retrigger
  sta $4004
  lda #$FF
  sta m_lh+1
  jmp @noise
@run:
  ; period += sign-extended delta
  lda sp_d
  bpl @pos
  clc
  adc sp_lo
  sta sp_lo
  lda sp_hi
  adc #$FF
  and #7
  sta sp_hi
  jmp @vol
@pos:
  clc
  adc sp_lo
  sta sp_lo
  lda sp_hi
  adc #0
  and #7
  sta sp_hi
@vol:
  lda sp_v
  sec
  sbc sp_vd
  bcs :+
  lda #0
: sta sp_v
  lsr a
  lsr a
  lsr a
  lsr a
  sta nt0
  lda sp_duty
  asl a
  asl a
  asl a
  asl a
  asl a
  asl a
  ora #$30
  ora nt0
  sta $4004
  lda sp_lo
  sta $4006
  lda sp_hi
  cmp sp_lh
  beq :+
  sta sp_lh
  ora #$08
  sta $4007
: 
@noise:
  lda sn_t
  beq @r
  dec sn_t
  bne @nrun
  lda #$30
  sta $400C
  rts
@nrun:
  lda sn_v
  sec
  sbc sn_vd
  bcs :+
  lda #0
: sta sn_v
  lsr a
  lsr a
  lsr a
  lsr a
  ora #$30
  sta $400C
  lda sn_first
  beq @r
  lda #0
  sta sn_first
  lda sn_per
  sta $400E
  lda #$08
  sta $400F
@r:
  rts

music_start:               ; A = song
  ldx #0
  stx mus_on
  asl a
  asl a
  sta song4
  lsr a
  lsr a
  tay
  lda SONG_TEMPO,y
  sta tempo
  lda #0
  sta tickc
  ldx #3
@ch:
  txa
  clc
  adc song4
  tay
  lda SONG_PLO,y
  sta m_pl,x
  lda SONG_PHI,y
  sta m_ph,x
  lda #1
  sta m_tm,x
  lda #0
  sta m_note,x
  sta m_age,x
  lda #$FF
  sta m_lh,x
  dex
  bpl @ch
  lda #1
  sta mus_on
  lda #$0B
  sta $4015              ; triangle off until the first note
  lda #$0F
  sta $4015
  rts

music_update:
  jsr sfx_update
  lda mus_on
  bne :+
  rts
: dec tickc
  bpl @frame
  ldx tempo
  dex
  stx tickc
  ldx #3
@rows:
  dec m_tm,x
  bne :+
  jsr fetch
: dex
  bpl @rows
@frame:
  jsr upd_p1
  jsr upd_p2
  jsr upd_tri
  jsr upd_noise
  rts

; X = channel
fetch:
@again:
  lda m_pl,x
  sta np
  lda m_ph,x
  sta np+1
  ldy #0
  lda (np),y
  cmp #$FF
  beq @loop
  cmp #$FE
  beq @stop
  sta m_note,x
  iny
  lda (np),y
  sta m_tm,x
  lda m_pl,x
  clc
  adc #2
  sta m_pl,x
  bcc :+
  inc m_ph,x
: lda #0
  sta m_age,x
  lda INIT_VOL,x
  sta m_vol,x
  lda #$FF
  sta m_lh,x
  lda m_note,x
  beq @r
  cpx #3
  bne @r
  tay
  lda DRUM_VOL,y
  sta m_vol,x
@r:
  rts
@loop:
  txa
  clc
  adc song4
  tay
  lda SONG_PLO,y
  sta m_pl,x
  lda SONG_PHI,y
  sta m_ph,x
  jmp @again
@stop:
  lda #0
  sta m_note,x
  lda #255
  sta m_tm,x
  rts

INIT_VOL: .byte $D0, $A0, $F0, $00
DECAY:    .byte $04, $0E, $00, $00
FLOOR:    .byte $80, $30, $F0, $00
VIB:      .byte 0, 1, 2, 1, 0, $FF, $FE, $FF
DRUM_VOL: .byte 0, $E0, $D0, $80, $80, $E0
DRUM_DEC: .byte 0, $18, $20, $30, $0C, $0A
DRUM_PER: .byte 0, $0C, $06, $03, $04, $02

; common envelope step: X = channel; returns vol (0-15) in A
env:
  lda m_vol,x
  sec
  sbc DECAY,x
  bcc :+
  cmp FLOOR,x
  bcs :++
: lda FLOOR,x
: sta m_vol,x
  lsr a
  lsr a
  lsr a
  lsr a
  inc m_age,x
  bne :+
  dec m_age,x
: rts

upd_p1:
  ldx #0
  lda m_note,x
  bne :+
  lda #$30
  sta $4000
  rts
: jsr env
  sta nt0
  lda #$70               ; duty 1, const volume
  ora nt0
  sta $4000
  ldy m_note,x
  dey
  lda PLO,y
  sta nt1
  lda PHI,y
  sta nt2
  lda m_age,x
  cmp #12
  bcc @novib
  lsr a
  lsr a
  and #7
  tay
  lda VIB,y
  bpl @vp
  clc
  adc nt1
  sta nt1
  lda nt2
  adc #$FF
  sta nt2
  jmp @novib
@vp:
  clc
  adc nt1
  sta nt1
  bcc @novib
  inc nt2
@novib:
  lda nt1
  sta $4002
  lda nt2
  cmp m_lh,x
  beq :+
  sta m_lh,x
  ora #$08
  sta $4003
: rts

upd_p2:
  lda sp_t
  beq :+
  rts
: ldx #1
  lda m_note,x
  bne :+
  lda #$30
  sta $4004
  rts
: jsr env
  sta nt0
  lda #$B0               ; duty 2, const volume
  ora nt0
  sta $4004
  ldy m_note,x
  dey
  lda PLO,y
  sta $4006
  lda PHI,y
  cmp m_lh,x
  beq :+
  sta m_lh,x
  ora #$08
  sta $4007
: rts

upd_tri:
  ldx #2
  lda m_note,x
  bne :+
  lda #$0B
  sta $4015
  rts
: lda #$0F
  sta $4015
  lda #$FF
  sta $4008
  ldy m_note,x
  dey
  lda TLO,y
  sta $400A
  lda THI,y
  cmp m_lh,x
  beq :+
  sta m_lh,x
  ora #$08
  sta $400B
: rts

upd_noise:
  lda sn_t
  beq :+
  rts
: ldx #3
  lda m_note,x
  bne :+
  lda #$30
  sta $400C
  rts
: ldy m_note,x
  lda m_vol,x
  sec
  sbc DRUM_DEC,y
  bcs :+
  lda #0
: sta m_vol,x
  lsr a
  lsr a
  lsr a
  lsr a
  ora #$30
  sta $400C
  lda m_age,x
  bne @aged
  lda DRUM_PER,y
  sta $400E
  lda #$08
  sta $400F
@aged:
  inc m_age,x
  bne :+
  dec m_age,x
: rts

.include "../data.inc"

.segment "STUB"
stub:                      ; lives in the fixed last bank: set up MMC3 before anything else
  sei
  cld
  ldx #$FF
  txs
  lda #6
  sta $8000
  lda #0
  sta $8001              ; R6 = PRG bank 0 at $8000
  lda #7
  sta $8000
  lda #1
  sta $8001              ; R7 = PRG bank 1 at $A000
  lda #0
  sta $A000              ; vertical mirroring
  sta $E000              ; IRQ off
  jmp reset

.segment "VECTORS"
  .word nmi, stub, irq

.segment "CHARS"
  .incbin "../chr.bin"
