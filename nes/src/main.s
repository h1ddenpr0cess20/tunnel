; Neverending Tunnel -- NES (NROM-256, vertical mirroring)
; Pseudo-3D tunnel run: three lanes, jump pits and walls, slide under beams, dodge pillars.

.segment "HEADER"
  .byte "NES", $1A, 2, 29, $41, 0, 0, 0, 0, 0, 0, 0, 0, 0   ; MMC3, 32K PRG, 232K CHR

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
slt: .res 1
facc: .res 1
cycle: .res 1
rnd: .res 1
digits: .res 6
best: .res 6
o_type: .res 3
o_lane: .res 3
o_dl: .res 3
o_dh: .res 3
fade: .res 1
fadet: .res 1
shake: .res 1
flash: .res 1
deadt: .res 1
kind: .res 1
wh_i: .res 1
wh_t: .res 1
frame: .res 1
slot: .res 1
tmpc: .res 1
tposl: .res 1
tposh: .res 1
ia: .res 1
ibank: .res 1
q_wr: .res 1
q_rd: .res 1
hud_dirty: .res 1
wh_dirty: .res 1
o_ds: .res 3           ; drawn stage ($FF = nothing drawn)
o_dc: .res 3           ; drawn camera position
o_dty: .res 3          ; drawn type / lane (an obstacle may be gone before it is erased)
o_dla: .res 3
o_prog: .res 3         ; row to resume a partly sent redraw at
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

.include "gamevars.s"

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

  ldx #1                 ; R1 = the fixed bank (obstacle tiles + font); R2-R5 are unused
: stx $8000
  lda #224
  sta $8001
  inx
  cpx #6
  bne :-
  lda #0
  sta $8000              ; R0 stays selected: the scanline IRQ only ever writes $8001
  sta $8001
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
  lda #$0E               ; background only (the sprite page holds the camera's scroll list); both
                         ; left-column bits set, or jsnes blanks the left 8 pixels
  sta mask
  lda #$88
  sta ctrl
  jsr calc_bands
  lda PPUSTAT
  lda ctrl
  sta PPUCTRL
  cli
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
  jsr update_pal
  jsr calc_bands
  lda padn
  and #BTN_START
  beq main
  jsr start_game
  jmp main

st_over:
  jsr tunnel_anim
  jsr update_pal
  jsr calc_bands
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
  jsr tunnel_anim
  jsr update_pal
  jsr calc_bands
  jsr draw_obstacles
  jmp main

st_dying:
  jsr dying_update
  jsr tunnel_anim
  jsr update_pal
  jsr calc_bands
  jsr draw_obstacles
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
  lda PPUSTAT            ; while playing, the first nametable holds the camera's edge filler
  lda #$20
  sta PPUADDR
  lda #$00
  sta PPUADDR
  lda #<NT0
  sta ptr
  lda #>NT0
  sta ptr+1
  jsr copy_nt
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

IRQ_FIRST = 15             ; the HUD rows stay still; the camera scroll starts below them
IRQ_LATCH = 31
BANK_DELAY = 3            ; IRQ busy-wait (5 cycles per step) so the bank write lands in hblank

set_banks:                 ; vblank: pick this frame's tunnel state, arm the band IRQ
  lda #0
  sta $8000              ; R0 selected
  ldx cycle
  lda STATEBANK,x
  sta $8001              ; band 0 for the top of the screen
  sta ibank              ; the IRQ rewrites band 0, then moves on to band 1, 2, ...
  lda epend              ; the camera's scroll list for this frame, if the main loop finished one
  bmi :+
  sta efront
  lda #$FF
  sta epend
: lda efront
  sta iseq
  sta $E000              ; acknowledge / disable
  lda #IRQ_FIRST
  sta $C000
  sta $C001
  sta $E001              ; enable
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
  lda #$25
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
  lda #$38
  sta PPUADDR
  ldx #0
: lda lightbuf,x
  sta PPUDATA
  inx
  cpx #6
  bne :-
@nohud:
  lda wh_dirty
  beq @nowh
  lda #0
  sta wh_dirty
  lda #$23               ; the status line lives in the first nametable
  sta PPUADDR
  lda #$80
  sta PPUADDR
  ldx #10
  lda wh_t
  beq :+
  ldx wh_i
: lda paused
  beq :+
  ldx #11
: lda #<STR_WHISPER
  sta np
  lda #>STR_WHISPER
  sta np+1
  txa
  beq @go
: lda np
  clc
  adc #32
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
  cpy #32
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

irq:                       ; one per scroll list entry: full scroll and tile bank at band starts, else X only
  sta ia                 ; (the writes land late on the line before the entry's line, before the PPU's
  stx ix                 ; end-of-line Y increment, so the full entries hold their source line minus one)
  ldx iseq
  inc iseq
  lda ev_n,x
  bpl @xonly
  lda busy               ; the main loop is writing VRAM with rendering off: leave the PPU alone
  bne :+
  bit PPUSTAT            ; mid-frame scroll: nametable, Y, X, then the low address byte loads v
  lda ev_n,x
  sta PPUADDR
  lda ev_y,x
  sta PPUSCRL
  lda ev_x,x
  sta PPUSCRL
  lda ev_o,x
  sta PPUADDR
: sta $E000              ; acknowledge
  sta $E001              ; re-arm
  lda ev_l,x             ; lines until the next entry, minus one
  sta $C000
  sta $C001
  ldx #BANK_DELAY        ; the tile bank switches in hblank, after this line's last fetches
: dex
  bne :-
  ldx iseq
  dex
  lda ibank
  sta $8001              ; (the first IRQ rewrites band 0)
  clc
  adc #2
  sta ibank
  lda ev_n,x
  and #$40
  beq @r
  sta $E000              ; last entry: no more IRQs this frame
  bne @r
@xonly:                    ; coarse X and the nametable bit reach v at the end of this line
  sta $E000
  sta $E001
  lda ev_l,x
  sta $C000
  sta $C001
  lda busy
  bne @r
  bit PPUSTAT
  lda ev_n,x
  ora #$80
  sta PPUCTRL
  lda ev_x,x
  sta PPUSCRL
@r:
  ldx ix
  lda ia
  rti

; ------------------------------------------------------------------ visuals
tunnel_anim:               ; the tunnel keeps flowing on the title screen
  lda state
  bne @r
  jsr advance_tunnel
@r:
  rts

; the tunnel advances v * 0.1984 rendered states per frame (1.5 rings per state, v in units/s)
advance_tunnel:
  lda vl
  sta gt0
  lda vh_
  sta gt1
  ldx #3
  jsr asr16
  lda gt0
  sta t1
  lda gt1
  sta t2
  lda vl
  sta gt0
  lda vh_
  sta gt1
  ldx #4
  jsr asr16
  clc
  lda t1
  adc gt0
  sta t1
  lda t2
  adc gt1
  sta t2
  lda vl
  sta gt0
  lda vh_
  sta gt1
  ldx #7
  jsr asr16
  clc
  lda t1
  adc gt0
  sta t1
  lda t2
  adc gt1
  sta t2
  clc
  lda tposl
  adc t1
  sta tposl
  lda tposh
  adc t2
  sta tposh
  and #15
  sta cycle
  rts

update_pal:
  ldx #31                ; start from the stock palettes so fades never stick
: lda INIT_PAL,x
  sta pal,x
  dex
  bpl :-
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
  cmp spc0
  beq @empty             ; zero width: nothing here
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
  and havn
  beq @diff
  lda c0o                ; same footprint on this row: nothing to send
  cmp c0n
  bne @diff
  lda c1o
  cmp c1n
  bne @diff
  clc
  rts
@diff:
  lda havo
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

.include "game.s"
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
