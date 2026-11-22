; Neverending Tunnel -- NES (NROM-256, vertical mirroring)
; Pseudo-3D tunnel run: three lanes, jump pits and walls, slide under beams, dodge pillars.

.segment "HEADER"
  .byte "NES", $1A, 2, 1, $01, 0, 0, 0, 0, 0, 0, 0, 0, 0

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

.segment "BSS"
pal: .res 32

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
  lda #$88
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
  jsr build_sprites
  jsr tunnel_anim
  jsr update_pal
  jmp main

st_dying:
  jsr dying_update
  jsr build_sprites
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
  adc #$30
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

ppu_update:
  lda #0
  sta OAMADDR
  lda #>oam
  sta OAMDMA
  lda PPUSTAT
  lda #$3F
  sta PPUADDR
  lda #0
  sta PPUADDR
  ldx #0
: lda pal,x
  sta PPUDATA
  inx
  cpx #32
  bne :-
  ; HUD digits on nametable 1
  lda #$24
  sta PPUADDR
  lda #$26
  sta PPUADDR
  ldx #5
: lda digits,x
  clc
  adc #$30
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
  adc #$30
  sta PPUDATA
  dex
  bpl :-
  ; status line (row 28)
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
  lda #4
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
  lda #4
  sta cam
  lda #6
  sta cyy
  lda #120
  sta spd
  lda #$00
  sta spn_l
  lda #$30
  sta spn_h
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

toggle_pause:
  lda paused
  eor #1
  sta paused
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
  dec cycle
  bpl :+
  lda #2
  sta cycle
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

inc_dist:
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
  dec cycle
  bpl @r
  lda #2
  sta cycle
@r:
  rts

update_pal:
  ldx #31                ; start from the stock palettes so fades never stick
: lda INIT_PAL,x
  sta pal,x
  dex
  bpl :-
  ; tunnel ring colours: rotate the three shades
  lda theme
  asl a
  clc
  adc theme              ; theme*3
  sta t1
  lda cycle
  asl a
  clc
  adc cycle              ; cycle*3
  sta t2
  ldx #0
@rot:
  lda t2
  clc
  adc @idx,x
  tay
  lda ROT,y
  clc
  adc t1
  tay
  lda THEMES,y
  sta pal+1,x
  inx
  cpx #3
  bne @rot
  ; glow ring (pal 2): warm shades, same rotation
  ldx #0
@rot2:
  lda t2
  stx t0
  clc
  adc t0
  tay
  lda ROT,y
  tay
  lda @glow,y
  sta pal+9,x
  inx
  cpx #3
  bne @rot2
  ; the light flickers
  lda frame
  lsr a
  lsr a
  and #1
  tax
  lda @flick,x
  sta pal+5
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
@idx: .byte 0, 1, 2
@glow: .byte $16, $26, $36
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

build_sprites:
  lda #0
  sta oi
  sta slot
@loop:
  ldx slot
  lda o_type,x
  beq :+
  jsr draw_obstacle
: inc slot
  lda slot
  cmp #3
  bne @loop
  ; hide the rest
  ldx oi
  lda #$F0
: sta oam,x
  inx
  inx
  inx
  inx
  bne :-
  rts

; X = slot
draw_obstacle:
  lda o_dh,x
  lsr a
  lsr a
  sta stg
  lda o_type,x
  sec
  sbc #1
  sta t2                 ; also the sprite palette
  asl a
  asl a
  asl a
  asl a
  ora stg
  tay
  lda REC_LO,y
  sta ptr
  lda REC_HI,y
  sta ptr+1
  ldy stg
  lda FLOORY,y
  sta by
  tya
  asl a
  asl a
  asl a
  asl a
  ora cyy
  tay
  lda YOFF,y
  clc
  adc by
  sta by
  ldy stg
  lda LANE_LO,y
  sta ptr2
  lda LANE_HI,y
  sta ptr2+1
  lda o_lane,x
  asl a
  asl a
  sec
  sbc cam
  clc
  adc #8
  tay
  lda (ptr2),y
  clc
  adc #128
  sta bx
  ldy #0
  lda (ptr),y
  sta cnt
  iny
@tile:
  lda (ptr),y            ; dx
  iny
  clc
  adc bx
  sta t0
  lda (ptr),y            ; dy
  iny
  sta dyv
  lda dyv
  bmi @neg
  clc
  adc by
  bcs @skip
  cmp #239
  bcs @skip
  bcc @put
@neg:
  clc
  adc by
  bcc @skip
@put:
  sta t1
  lda (ptr),y            ; tile
  iny
  sta t3
  lda (ptr),y            ; palette
  iny
  sta t2
  sty tyv
  ldx oi
  lda t3
  sta oam+1,x
  lda t1
  sec
  sbc #1
  sta oam,x
  lda t2
  sta oam+2,x
  lda t0
  sta oam+3,x
  inx
  inx
  inx
  inx
  stx oi
  ldy tyv
  bne @fix               ; Y is never 0 here
@skip:
  iny
  iny
@fix:
  dec cnt
  bne @tile
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

.segment "VECTORS"
  .word nmi, reset, irq

.segment "CHARS"
  .incbin "../chr.bin"
