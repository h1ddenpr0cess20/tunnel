; game.s -- port of src/game.js: running, jumping, sliding, lanes, obstacles, collisions.
; World units are tunnel half-widths in 8.8 fixed point; time steps are 1/120 s like the original.
; Obstacles are tunnel geometry: their projected footprint is computed from the same perspective
; as the shader and drawn into the play nametable with the tunnel's own tile style.

.segment "CODE"

; ------------------------------------------------------------------ math
; (mAh:mAl) * (mBh:mBl) unsigned -> mR3..mR0
umul16:                    ; quarter-square partial products (Y kept; X = 0 and mB = 0 on return)
  sty qy
  lda mAl
  ldy mBl
  jsr qmul
  sta mR1
  lda qlo
  sta mR0
  lda #0
  sta mR2
  sta mR3
  lda mBh
  beq @b0
  ldy mAl
  jsr qmul               ; al * bh
  sta qt
  lda qlo
  clc
  adc mR1
  sta mR1
  lda qt
  adc mR2
  sta mR2
  bcc @b0
  inc mR3
@b0:
  lda mAh
  beq @done
  ldy mBl
  jsr qmul               ; ah * bl
  sta qt
  lda qlo
  clc
  adc mR1
  sta mR1
  lda qt
  adc mR2
  sta mR2
  bcc :+
  inc mR3
: lda mBh
  beq @done
  ldy mAh
  jsr qmul               ; ah * bh
  clc
  adc mR3
  sta mR3
  lda qlo
  clc
  adc mR2
  sta mR2
  bcc @done
  inc mR3
@done:
  lda #0
  sta mBl
  sta mBh
  tax
  ldy qy
  rts

; signed (mA) * unsigned (mB) -> signed 32-bit in mR3..mR0
smulu:
  lda mAh
  sta sgn
  bpl :+
  sec
  lda #0
  sbc mAl
  sta mAl
  lda #0
  sbc mAh
  sta mAh
: jsr umul16
  lda sgn
  bpl :+
  sec
  lda #0
  sbc mR0
  sta mR0
  lda #0
  sbc mR1
  sta mR1
  lda #0
  sbc mR2
  sta mR2
  lda #0
  sbc mR3
  sta mR3
: rts

; (mAh:mAl) * mB (8-bit) >> 8 -> (mR2:mR1) [bytes 1 and 2 of the 24-bit product]
umul16x8:
  lda #0
  sta mR0
  sta mR1
  sta mR2
  lda mAl
  sta mS0
  lda mAh
  sta mS1
  lda #0
  sta mS2
  ldx #8
@l:
  lsr mBl
  bcc @n
  clc
  lda mR0
  adc mS0
  sta mR0
  lda mR1
  adc mS1
  sta mR1
  lda mR2
  adc mS2
  sta mR2
@n:
  asl mS0
  rol mS1
  rol mS2
  dex
  bne @l
  rts

; 16-bit arithmetic shift right of (gt1:gt0) by X bits (X = 0 on return, Y kept)
asr16:
  cpx #8
  bcc @lt8
  lda gt1                ; 8 or more: move a byte first
  sta gt0
  asl a
  lda #0
  adc #$FF
  eor #$FF
  sta gt1
  txa
  sec
  sbc #8
  tax
  jmp @l0
@lt8:
  cpx #5
  bcc @l0
  lda gt1                ; 5 to 7: shift left by 8 - X into a third byte and drop the low one
  asl a
  lda #0
  adc #$FF
  eor #$FF
  sta qt
  txa
  eor #7
  tax
  inx
: asl gt0
  rol gt1
  rol qt
  dex
  bne :-
  lda gt1
  sta gt0
  lda qt
  sta gt1
  rts
@l0:
  cpx #0
  beq @r
@l:
  lda gt1
  cmp #$80
  ror gt1
  ror gt0
  dex
  bne @l
@r:
  rts

; ------------------------------------------------------------------ title / start
go_title:
  lda #0
  sta state
  sta fade
  sta shake
  sta flash
  sta slt
  lda #90                ; the title drifts at 0.35 units/s
  sta vl
  lda #0
  sta vh_
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
  sta slt
  sta fade
  sta fadet
  sta shake
  sta flash
  sta wh_t
  sta wh_i
  sta facc
  sta rtl
  sta rth
  sta m16l
  sta m16h
  sta wm
  sta hinted
  sta spawned
  sta xl
  sta xh
  sta hl
  sta hhi
  sta vvl
  sta vvh
  sta duck
  sta jbuf
  sta holddn
  sta L0
  sta L1
  sta L2
  lda #$FA               ; 1000 * 2^22
  sta L3
  lda #1
  sta lane
  lda #<(31*256)
  sta nxl
  lda #>(31*256)
  sta nxh
  lda vh_                ; S.speed = max(speed, 2)
  cmp #2
  bcs :+
  lda #0
  sta vl
  lda #2
  sta vh_
: ldx #2
  lda #0
: sta o_type,x
  sta o_prog,x
  dex
  bpl :-
  lda #$FF
  sta o_ds
  sta o_ds+1
  sta o_ds+2
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
  jsr format_light
  rts

reload_nt1:                ; forget any obstacle tiles left in the play nametable
  lda #1
  sta busy
  lda #0
  sta PPUMASK
  lda PPUSTAT
  lda #$20               ; the camera shear shows slivers of the other nametable: the wall edge filler
  sta PPUADDR
  lda #$00
  sta PPUADDR
  lda #<NT2
  sta ptr
  lda #>NT2
  sta ptr+1
  jsr copy_nt
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

; ------------------------------------------------------------------ per frame
game_update:
  inc rtl
  bne :+
  inc rth
: ; difficulty = min(1, runT/150) ~ frames/9000
  lda rth
  asl a
  asl a
  asl a
  sta gt0
  lda rtl
  lsr a
  lsr a
  lsr a
  lsr a
  lsr a
  ora gt0
  sta diff
  lda rth
  cmp #32
  bcc :+
  lda #255
  sta diff
: ; target speed = 5 + 6 (1 - e^(-t/100)); ease toward it
  lda rth
  cmp #128
  bcc :+
  lda #127
: tax
  lda TGT,x
  sta mBl
  lda #6
  sta mAl
  lda #0
  sta mAh
  sta mBh
  jsr umul16             ; t8 * 6
  clc
  lda mR0
  adc #<1280
  sta tgl
  lda mR1
  adc #>1280
  sta tgh
  sec                    ; diff = target - v
  lda tgl
  sbc vl
  sta gt0
  lda tgh
  sbc vh_
  sta gt1
  bcc @slower
  ldx #6
  lda gt0
  pha
  lda gt1
  pha
  jsr asr16
  lda gt0
  sta t0
  lda gt1
  sta t1
  pla
  sta gt1
  pla
  sta gt0
  ldx #7
  jsr asr16
  clc
  lda t0
  adc gt0
  sta gt0
  lda t1
  adc gt1
  sta gt1
  ora gt0                ; always creep the last few units in
  bne :+
  inc gt0
:   clc
  lda vl
  adc gt0
  sta vl
  lda vh_
  adc gt1
  sta vh_
@slower:
  ; metres: 1.25 m per unit, 60 frames/s
  lda vl
  sta gt0
  lda vh_
  sta gt1
  ldx #6
  jsr asr16
  lda gt0
  sta t2
  lda vl
  sta gt0
  lda vh_
  sta gt1
  ldx #8
  jsr asr16
  clc
  lda t2
  adc gt0
  sta t2
  lda vl
  sta gt0
  lda vh_
  sta gt1
  ldx #10
  jsr asr16
  clc
  lda t2
  adc gt0
  sta t2
  clc
  lda facc
  adc t2
  sta facc
  bcc :+
  jsr inc_dist
: jsr advance_tunnel
  ; ---- input
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
: lda pad
  and #(BTN_DOWN | BTN_B)
  sta holddn
  lda padn
  and #(BTN_A | BTN_UP)
  beq :+
  jsr want_jump
: lda padn
  and #(BTN_B | BTN_DOWN)
  beq :+
  jsr want_slide
: ; ---- two 1/120 s steps
  jsr sim_step
  lda state
  cmp #1
  bne @ret
  jsr sim_step
  lda state
  cmp #1
  bne @ret
  ; ---- spawn: while next < LIGHT_D + 4
@sp:
  lda nxh
  cmp #33
  bcs @nosp
  jsr spawn
  jmp @sp
@nosp:
  ; ---- housekeeping per obstacle: retire passed ones, hints
  ldx #2
@ob:
  lda o_type,x
  beq @on
  clc                    ; far end = d + len; gone when < -1
  lda o_dl,x
  adc o_ll,x
  sta gt0
  lda o_dh,x
  adc o_lh,x
  bpl @alive
  cmp #$FF
  bne @dead
@alive:
  jmp @hint
@dead:
  lda #0
  sta o_type,x
  beq @on
@hint:
  lda o_seen,x
  bne @on
  lda o_dh,x
  bmi @on
  cmp #17                ; LIGHT_D * 0.6 = 17.4 units
  bcs @on
  lda #1
  sta o_seen,x
  jsr give_hint
@on:
  dex
  bpl @ob
  lda wh_t
  beq :+
  dec wh_t
  bne :+
  lda #1
  sta wh_dirty
: ; camera for the obstacles
  lda xl                 ; obstacles are projected from the real camera (their sides stay upright);
  sta cwl                ; shear_rec then undoes the row scroll the picture is about to be moved by
  lda xh
  sta cwh
@ret:
  rts

; X = slot: show the control hint for its type, once per type
give_hint:
  lda o_type,x
  tay
  lda #1
: dey
  beq :+
  asl a
  jmp :-
: sta t0
  lda hinted
  and t0
  bne @r
  lda hinted
  ora t0
  sta hinted
  lda o_type,x
  tay
  lda HINT_IDX-1,y
  sta wh_i
  lda #108               ; 1.8 s
  sta wh_t
  lda #1
  sta wh_dirty
@r:
  rts
HINT_IDX: .byte 12, 13, 12, 14      ; pit: jump, pillar: change lanes, wall: jump, beam: slide

want_jump:
  jsr grounded
  bcc @buf
  jmp do_jump
@buf:
  lda #17                ; 0.14 s jump buffer
  sta jbuf
  rts

grounded:                 ; carry set when h <= 0.001, h > -0.1 and vh <= 0.01
  lda hhi
  bmi @neg
  bne @no
  lda hl
  bne @no
  jmp @v
@neg:
  cmp #$FF
  bne @no
  lda hl
  cmp #230               ; -26/256
  bcc @no
@v:
  lda vvh
  bmi @yes
  bne @no
  lda vvl
  cmp #3
  bcs @no
@yes:
  sec
  rts
@no:
  clc
  rts

do_jump:
  lda #<1024             ; V0 = 4 * JUMP_H / AIR = 4 u/s
  sta vvl
  lda #>1024
  sta vvh
  lda hhi
  bpl :+
  lda #0
  sta hl
  sta hhi
: lda #0
  sta slt
  sta jbuf
  lda #0
  jsr sfx_play
  rts

want_slide:
  lda hhi                ; in the air: slam down
  bmi @ground
  bne @air
  lda hl
  cmp #6
  bcc @ground
@air:
  lda vvh
  bpl @set               ; moving up: force -6 u/s
  cmp #$FA
  bcc @ground            ; already faster than that
@set:
  lda #<(-1536)
  sta vvl
  lda #>(-1536)
  sta vvh
@ground:
  lda #96                ; 0.8 s in 1/120 s steps
  sta slt
  lda #0
  sta jbuf
  lda #1
  jsr sfx_play
  rts

; ------------------------------------------------------------------ one 1/120 s step
sim_step:
  ; ds = v / 120
  lda vl
  sta gt0
  lda vh_
  sta gt1
  ldx #7
  jsr asr16
  lda gt0
  sta dsl
  lda gt1
  sta dsh
  lda vl
  sta gt0
  lda vh_
  sta gt1
  ldx #11
  jsr asr16
  clc
  lda dsl
  adc gt0
  sta dsl
  lda dsh
  adc gt1
  sta dsh
  ; obstacles and the spawn marker come toward us
  ldx #2
@mv:
  lda o_type,x
  beq @mn
  sec
  lda o_dl,x
  sbc dsl
  sta o_dl,x
  lda o_dh,x
  sbc dsh
  sta o_dh,x
@mn:
  dex
  bpl @mv
  sec
  lda nxl
  sbc dsl
  sta nxl
  lda nxh
  sbc dsh
  sta nxh
  ; x eases toward the lane centre: x += (c - x) * (1 - e^(-16 dt)) ~ 1/8
  ldx lane
  sec
  lda LANE_C_L,x
  sbc xl
  sta gt0
  lda LANE_C_H,x
  sbc xh
  sta gt1
  ldx #3
  jsr asr16
  clc
  lda xl
  adc gt0
  sta xl
  lda xh
  adc gt1
  sta xh
  ; slide timer
  lda slt
  beq @nos
  dec slt
  lda holddn
  beq @nos
  lda slt
  cmp #12
  bcs @nos
  lda #12
  sta slt
@nos:
  jsr over_pit
  ; on the ground?  h <= 0, vh <= 0 and not over a pit
  lda inpit
  bne @air
  lda hhi
  bmi @gnd1
  bne @air
  lda hl
  bne @air
@gnd1:
  lda vvh
  bmi @ground
  bne @air
  lda vvl
  bne @air
@ground:
  jmp @landed
@air:
  ; vh -= GRAV / 120 (23 in 8.8); h += vh / 120
  sec
  lda vvl
  sbc #23
  sta vvl
  lda vvh
  sbc #0
  sta vvh
  lda vvl
  sta gt0
  lda vvh
  sta gt1
  ldx #7
  jsr asr16
  lda gt0
  sta t0
  lda gt1
  sta t1
  lda vvl
  sta gt0
  lda vvh
  sta gt1
  ldx #11
  jsr asr16
  clc
  lda t0
  adc gt0
  sta t0
  lda t1
  adc gt1
  sta t1
  clc
  lda hl
  adc t0
  sta hl
  lda hhi
  adc t1
  sta hhi
@landed:
  lda inpit
  bne @inpit
  lda hhi                ; h <= 0 ?
  bmi @touch
  bne @airok
  lda hl
  bne @airok
@touch:
  lda hhi
  bpl @settle
  cmp #$FF
  bcc @fell
  lda hl
  cmp #220               ; h < -0.14 -> fell
  bcc @fell
@settle:
  lda vvh
  bpl @nol
  cmp #$FE
  bcs @nol
  lda #3                 ; vh < -1.5 -> land
  jsr sfx_play
@nol:
  lda vvl
  ora vvh
  beq @zero
  lda vvh
  bpl @airok             ; still moving up
@zero:
  lda #0
  sta hl
  sta hhi
  sta vvl
  sta vvh
  jmp @airok
@inpit:
  lda hhi                ; h < -0.12 -> fell
  bpl @airok
  cmp #$FF
  bcc @fell
  lda hl
  cmp #225
  bcc @fell
  jmp @airok
@fell:
  lda #0
  jmp die
@airok:
  ; jump buffer
  lda jbuf
  beq @nojb
  dec jbuf
  jsr grounded
  bcc @nojb
  jsr do_jump
@nojb:
  ; duck eases toward 1 while sliding on the ground (h <= 0.02), else toward 0
  ldx #0
  lda slt
  beq @dt
  lda hhi
  bmi @dd
  bne @dt
  lda hl
  cmp #6
  bcs @dt
@dd:
  ldx #255
@dt:
  stx t0
  sec
  lda t0
  sbc duck
  bcs @up
  eor #$FF               ; negative: |diff|
  clc
  adc #1
  sta t1
  lsr a
  lsr a
  lsr a
  sta t2
  lda t1
  lsr a
  lsr a
  lsr a
  lsr a
  lsr a
  clc
  adc t2
  sta t2
  lda duck
  sec
  sbc t2
  sta duck
  jmp @dn
@up:
  sta t1
  lsr a
  lsr a
  lsr a
  sta t2
  lda t1
  lsr a
  lsr a
  lsr a
  lsr a
  lsr a
  clc
  adc t2
  adc duck
  bcc :+
  lda #255
: sta duck
@dn:
  ; eye = h - duck * 0.55
  lda duck
  sta mBl
  lda #141
  sta mAl
  lda #0
  sta mAh
  jsr umul16x8           ; (141 * duck) >> 8 in mR1 (+mR2)
  sec
  lda hl
  sbc mR1
  sta eyel
  lda hhi
  sbc #0
  sta eyeh
  ; ---- collisions with boxes
  ldx #2
@col:
  jsr check_box
  bcs @died
  dex
  bpl @col
@died:
  rts

; X = slot: carry set if the runner hit this obstacle (die has been called)
check_box:
  lda o_type,x
  bne :+
  jmp @ok
:
  cmp #1
  bne :+
  jmp @ok
:
  ; s overlap: d < 0.15 and d + len > -0.15
  lda o_dh,x
  bmi @sin
  beq :+
  jmp @ok
:
  lda o_dl,x
  cmp #38
  bcc :+
  jmp @ok
:
@sin:
  clc
  lda o_dl,x
  adc o_ll,x
  sta gt0
  lda o_dh,x
  adc o_lh,x
  bmi @neg
  jmp @x
@neg:
  cmp #$FF
  beq :+
  jmp @ok
:
  lda gt0
  cmp #218               ; -38/256: passed
  bcs :+
  jmp @ok
:
  bne :+
  jmp @ok
:
@x:
  ; x overlap: x + 0.15 > xlo and x - 0.15 < xhi
  ldy o_lane,x
  clc
  lda xl
  adc #38
  sta gt0
  lda xh
  adc #0
  sta gt1
  sec
  lda gt0
  sbc LAN_XLO_L,y
  lda gt1
  sbc LAN_XLO_H,y
  bvc :+
  eor #$80
: bpl :+
  jmp @ok
:
  sec
  lda xl
  sbc #38
  sta gt0
  lda xh
  sbc #0
  sta gt1
  sec
  lda gt0
  sbc LAN_XHI_L,y
  lda gt1
  sbc LAN_XHI_H,y
  bvc :+
  eor #$80
: bmi :+
  jmp @ok
:
  lda o_type,x
  cmp #2
  beq @pil
  cmp #3
  beq @wall
  ; beam: safe when eye + 0.12 < -0.2  ->  eye < -82/256
  lda eyeh
  bpl @bdie
  cmp #$FF
  bcs :+
  jmp @ok
:
  lda eyel
  cmp #174
  bcs :+
  jmp @ok
:
@bdie:
  lda #2
  jsr die
  sec
  rts
@pil:
  lda #3
  jsr die
  sec
  rts
@wall:
  ; safe when eye - 1 > -0.63  ->  eye > 95/256
  lda eyeh
  bmi @wdie
  beq :+
  jmp @ok
:
  lda eyel
  cmp #96
  bcc :+
  jmp @ok
:
@wdie:
  lda #1
  jsr die
  sec
  rts
@ok:
  clc
  rts

; inpit = 1 when the player's centre is over a pit: d + 0.08 < 0 < d + len - 0.08 and x in lane
over_pit:
  lda #0
  sta inpit
  ldx #2
@l:
  lda o_type,x
  cmp #1
  bne @n
  clc                    ; d + 0.08 < 0 ?
  lda o_dl,x
  adc #20
  lda o_dh,x
  adc #0
  bpl @n
  clc                    ; d + len - 0.08 > 0 ?
  lda o_dl,x
  adc o_ll,x
  sta gt0
  lda o_dh,x
  adc o_lh,x
  sta gt1
  sec
  lda gt0
  sbc #20
  sta gt0
  lda gt1
  sbc #0
  bmi @n
  ora gt0
  beq @n
  ldy o_lane,x           ; x > xlo + 0.05 and x < xhi - 0.05
  clc
  lda LAN_XLO_L,y
  adc #13
  sta gt0
  lda LAN_XLO_H,y
  adc #0
  sta gt1
  sec
  lda xl
  sbc gt0
  lda xh
  sbc gt1
  bvc :+
  eor #$80
: bmi @n
  sec
  lda LAN_XHI_L,y
  sbc #13
  sta gt0
  lda LAN_XHI_H,y
  sbc #0
  sta gt1
  sec
  lda gt0
  sbc xl
  lda gt1
  sbc xh
  bvc :+
  eor #$80
: bmi @n
  lda #1
  sta inpit
@n:
  dex
  bpl @l
  rts

; ------------------------------------------------------------------ distance, light, milestones
inc_dist:
  lda #1
  sta hud_dirty
  inc m16l
  bne :+
  inc m16h
: ldx #0
: inc digits,x
  lda digits,x
  cmp #10
  bcc @digdone
  lda #0
  sta digits,x
  inx
  cpx #6
  bcc :-
@digdone:
  ; the light recedes: L *= 2^(-1/250)  ~  L -= L>>9 + L>>10 - L>>13 - L>>15
  jsr light_step
  jsr format_light
  ; milestone whisper
  ldx wm
  cpx #10
  bcs @r
  lda m16l
  cmp MILES_L,x
  lda m16h
  sbc MILES_H,x
  bcc @r
  stx wh_i
  inc wm
  lda #156               ; 2.6 s
  sta wh_t
  lda #1
  sta wh_dirty
@r:
  rts

; gt0..gt3 = L >> X (32-bit)
l_shift:
  lda L0
  sta gt0
  lda L1
  sta gt1
  lda L2
  sta gt2
  lda L3
  sta gt3
: lsr gt3
  ror gt2
  ror gt1
  ror gt0
  dex
  bne :-
  rts

light_step:
  ; delta = (L>>9) + (L>>10) - (L>>13) - (L>>15) -> stored in mR0..mR3
  ldx #9
  jsr l_shift
  lda gt0
  sta mR0
  lda gt1
  sta mR1
  lda gt2
  sta mR2
  lda gt3
  sta mR3
  ldx #10
  jsr l_shift
  clc
  lda mR0
  adc gt0
  sta mR0
  lda mR1
  adc gt1
  sta mR1
  lda mR2
  adc gt2
  sta mR2
  lda mR3
  adc gt3
  sta mR3
  ldx #13
  jsr l_shift
  sec
  lda mR0
  sbc gt0
  sta mR0
  lda mR1
  sbc gt1
  sta mR1
  lda mR2
  sbc gt2
  sta mR2
  lda mR3
  sbc gt3
  sta mR3
  ldx #15
  jsr l_shift
  sec
  lda mR0
  sbc gt0
  sta mR0
  lda mR1
  sbc gt1
  sta mR1
  lda mR2
  sbc gt2
  sta mR2
  lda mR3
  sbc gt3
  sta mR3
  sec
  lda L0
  sbc mR0
  sta L0
  lda L1
  sbc mR1
  sta L1
  lda L2
  sbc mR2
  sta L2
  lda L3
  sbc mR3
  sta L3
  rts

; lightbuf = six characters (font tiles): "997.2 ", "12.345", "0.1234"
format_light:
  lda L3                 ; integer part = L >> 22  (0..1000)
  sta gt1
  lda L2
  sta gt0
  ldx #6
: lsr gt1
  ror gt0
  dex
  bne :-
  lda #0
  sta mS0                ; hundreds, tens, ones
  sta mS1
  sta mS2
@h:
  lda gt1
  bne @sub100
  lda gt0
  cmp #100
  bcc @tens
@sub100:
  sec
  lda gt0
  sbc #100
  sta gt0
  lda gt1
  sbc #0
  sta gt1
  inc mS0
  jmp @h
@tens:
  lda gt0
  cmp #10
  bcc @ones
  sbc #10
  sta gt0
  inc mS1
  jmp @tens
@ones:
  lda gt0
  sta mS2
  ; four fractional digits of the 22-bit fraction: x = x * 10, digit = x >> 22
  lda L0
  sta mR0
  lda L1
  sta mR1
  lda L2
  and #$3F
  sta mR2
  ldy #0
@f:
  lda mR0                ; (gt3:gt2:gt1:gt0) = x << 3 ; (mBh:mBl:mAh:mAl) = x << 1
  sta gt0
  sta mAl
  lda mR1
  sta gt1
  sta mAh
  lda mR2
  sta gt2
  sta mBl
  lda #0
  sta gt3
  sta mBh
  asl mAl
  rol mAh
  rol mBl
  rol mBh
  asl gt0
  rol gt1
  rol gt2
  rol gt3
  asl gt0
  rol gt1
  rol gt2
  rol gt3
  asl gt0
  rol gt1
  rol gt2
  rol gt3
  clc
  lda gt0
  adc mAl
  sta mR0
  lda gt1
  adc mAh
  sta mR1
  lda gt2
  adc mBl
  sta mR2
  lda gt3
  adc mBh
  sta gt3
  lda mR2                ; digit = bits 22..25 = (gt3:mR2) >> 6
  lsr a
  lsr a
  lsr a
  lsr a
  lsr a
  lsr a
  sta t0
  lda gt3
  asl a
  asl a
  ora t0
  sta fdig,y
  lda mR2
  and #$3F
  sta mR2
  iny
  cpy #4
  bne @f
  ; compose
  lda mS0
  bne @big
  lda mS1
  bne @mid
  lda mS2                ; "d.dddd"
  jsr @dig
  sta lightbuf
  lda #$CE
  sta lightbuf+1
  ldx #0
: lda fdig,x
  jsr @dig
  sta lightbuf+2,x
  inx
  cpx #4
  bne :-
  rts
@mid:                    ; "dd.ddd"
  lda mS1
  jsr @dig
  sta lightbuf
  lda mS2
  jsr @dig
  sta lightbuf+1
  lda #$CE
  sta lightbuf+2
  ldx #0
: lda fdig,x
  jsr @dig
  sta lightbuf+3,x
  inx
  cpx #3
  bne :-
  rts
@big:                    ; "ddd.d "
  lda mS0
  jsr @dig
  sta lightbuf
  lda mS1
  jsr @dig
  sta lightbuf+1
  lda mS2
  jsr @dig
  sta lightbuf+2
  lda #$CE
  sta lightbuf+3
  lda fdig
  jsr @dig
  sta lightbuf+4
  lda #$C0               ; space
  sta lightbuf+5
  rts
@dig:
  clc
  adc #$D0
  rts

; ------------------------------------------------------------------ spawning (game.js spawn())
FIRST4: .byte 1, 2, 3, 4          ; pit, pillar, wall, beam to start with

spawn:
  ldx spawned
  cpx #4
  bcs @rnd
  lda FIRST4,x
  jmp @have
@rnd:
  jsr rand
  cmp #87                ; .34
  bcs :+
  lda #1
  jmp @have
: cmp #153               ; .60
  bcs :+
  lda #2
  jmp @have
: cmp #204               ; .80
  bcs :+
  lda #3
  jmp @have
: lda #4
@have:
  sta stype
  lda #0
  sta late
  lda spawned
  cmp #4
  bcc :+
  lda #1
  sta late
: lda stype
  cmp #1
  bne :+
  jmp @pit
: cmp #2
  bne :+
  jmp @pillar
: cmp #3
  bne :+
  jmp @wall
: ; beam: full width, len .15 + rand * .15
  lda #3
  sta slane
  jsr rand
  sta rr1
  lsr a
  lsr a
  lsr a
  sta t0
  lda rr1
  lsr a
  lsr a
  lsr a
  lsr a
  lsr a
  lsr a
  clc
  adc t0
  adc #38
  sta slen
  lda #0
  sta slen+1
  jmp @make
@wall:
  lda #3
  sta slane
  lda late
  beq :+
  jsr rand
  cmp #77                ; .3
  bcs :+
  jsr rand
  and #1
  clc
  adc #4
  sta slane
: jsr rand
  lsr a
  lsr a
  lsr a
  clc
  adc #20                ; .08 + rand * .08
  sta slen
  lda #0
  sta slen+1
  jmp @make
@pillar:
  jsr rand
  sta rr1
  lda late
  beq @one
  lda diff               ; rand < .35 + .2 * diff
  sta mBl
  lda #51
  sta mAl
  lda #0
  sta mAh
  jsr umul16x8
  lda mR1
  clc
  adc #90
  cmp rr1
  bcc @one
  jsr rand
  and #1
  clc
  adc #4
  sta slane
  jmp @plen
@one:
  jsr rand
  cmp #128
  bcs @rl
  lda lane
  jmp @ps
@rl:
  jsr rand               ; ri(3)
  and #$7F
  tax
: cpx #3
  bcc :+
  txa
  sec
  sbc #3
  tax
  jmp :-
: txa
@ps:
  sta slane
@plen:
  jsr rand
  lsr a
  lsr a
  clc
  adc #64                ; .25 + rand * .25
  sta slen
  lda #0
  sta slen+1
  jmp @make
@pit:
  lda #3
  sta slane
  lda late
  beq @plen2
  jsr rand
  cmp #90                ; .35: a partial pit
  bcs @plen2
  jsr rand
  and #7
  cmp #5
  bcc :+
  and #3
: tax
  lda PITLANES,x
  sta slane
@plen2:
  ; len = clamp(v * .75 * (.3 + .25 rand + .12 diff), 1, v * .75 - .7)
  lda vl
  sta gt0
  lda vh_
  sta gt1
  ldx #2
  jsr asr16
  sec                    ; a = v - v/4 = v * .75
  lda vl
  sbc gt0
  sta nzl
  lda vh_
  sbc gt1
  sta nzh
  jsr rand
  lsr a
  lsr a
  sta t0                 ; .25 * rand
  lda diff               ; .12 * diff = diff * 31 / 256
  sta mBl
  lda #31
  sta mAl
  lda #0
  sta mAh
  jsr umul16x8
  lda mR1
  clc
  adc t0
  adc #77                ; .3
  sta mBl
  lda nzl
  sta mAl
  lda nzh
  sta mAh
  jsr umul16x8           ; (mR2:mR1) = a * f
  lda mR1
  sta slen
  lda mR2
  sta slen+1
  lda slen+1             ; >= 1.0
  bne :+
  lda #0
  sta slen
  lda #1
  sta slen+1
: sec                    ; <= a - 0.7
  lda nzl
  sbc #179
  sta gt0
  lda nzh
  sbc #0
  sta gt1
  bmi @make
  lda slen
  cmp gt0
  lda slen+1
  sbc gt1
  bcc @make
  lda gt0
  sta slen
  lda gt1
  sta slen+1
@make:
  ; find a free slot
  ldx #2
: lda o_type,x
  beq @free
  dex
  bpl :-
  lda #33                ; none free: try again next frame
  sta nxh
  rts
@free:
  lda stype
  sta o_type,x
  lda slane
  sta o_lane,x
  lda nxl
  sta o_dl,x
  lda nxh
  sta o_dh,x
  lda slen
  sta o_ll,x
  lda slen+1
  sta o_lh,x
  lda #0
  sta o_seen,x
  sta o_prog,x
  lda #$FF
  sta o_ds,x
  inc spawned
  ; next = d + len + max(4, v * (1 - .3 diff) + rand * v * (.9 - .4 diff))
  lda diff
  sta mBl
  lda #77
  sta mAl
  lda #0
  sta mAh
  jsr umul16x8
  sec
  lda #0
  sbc mR1
  sta t0                 ; 256 - .3 diff
  lda vl
  sta mAl
  lda vh_
  sta mAh
  lda t0
  sta mBl
  jsr umul16x8
  lda mR1
  sta nzl
  lda mR2
  sta nzh                ; v * (1 - .3 diff)
  lda diff
  sta mBl
  lda #102
  sta mAl
  lda #0
  sta mAh
  jsr umul16x8
  sec
  lda #230
  sbc mR1
  sta t0                 ; .9 - .4 diff
  lda vl
  sta mAl
  lda vh_
  sta mAh
  lda t0
  sta mBl
  jsr umul16x8
  lda mR1
  sta mAl
  lda mR2
  sta mAh
  jsr rand
  sta mBl
  jsr umul16x8           ; * rand
  clc
  lda nzl
  adc mR1
  sta nzl
  lda nzh
  adc mR2
  sta nzh
  lda nzh                ; max(4, .)
  cmp #4
  bcs :+
  lda #0
  sta nzl
  lda #4
  sta nzh
: clc
  lda nxl
  adc slen
  sta nxl
  lda nxh
  adc slen+1
  sta nxh
  clc
  lda nxl
  adc nzl
  sta nxl
  lda nxh
  adc nzh
  sta nxh
  rts
PITLANES: .byte 0, 2, 1, 4, 5        ; [0,1]->lane 0 etc. as lane codes: [0,1] [2,3] [1,2] [0,2] [1,3]

; ------------------------------------------------------------------ crashes
die:                       ; A = 0 fell, 1 tripped, 2 hit head, 3 pillar
  sta kind
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
  lda #0
  sta vl
  sta vh_
  lda #4
  jsr sfx_play
  lda #5
  sta flash
  lda #24
  sta shake
@mus:
  lda #2
  jsr music_start
  rts

dying_update:
  inc deadt
  lda deadt
  and #3
  bne :+
  lda vh_                ; the speed dies away
  lsr a
  sta gt1
  lda vl
  ror a
  sta gt0
  lda vl
  sec
  sbc gt0
  sta vl
  lda vh_
  sbc gt1
  sta vh_
: lda flash
  beq :+
  dec flash
: lda shake
  beq :+
  dec shake
: lda kind
  bne @nofade
  lda deadt
  and #15
  bne @obs
  lda fade
  cmp #4
  bcs @obs
  inc fade
  jmp @obs
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
  lda vl                 ; obstacles keep coming: ds = v / 60
  sta gt0
  lda vh_
  sta gt1
  ldx #6
  jsr asr16
  ldx #2
: lda o_type,x
  beq :+
  sec
  lda o_dl,x
  sbc gt0
  sta o_dl,x
  lda o_dh,x
  sbc gt1
  sta o_dh,x
: dex
  bpl :--
  lda deadt
  cmp #110
  bcc @r
  ldx #5                 ; new best?
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

; ------------------------------------------------------------------ obstacles in the nametable
; Each frame the footprint of every obstacle is projected like the shader does it (columns from
; the lane edges and the camera, rows from the heights, all scaled by 1/z) and compared with what
; is drawn. Differences are streamed to the PPU through the queue.
ROW_BUDGET = 10
draw_obstacles:
  lda #ROW_BUDGET        ; rows redrawn per frame, all slots together: bounds the frame's work
  sta rbud
  lda #0
  sta slot
@l:
  ldx slot
  jsr update_slot
  inc slot
  lda slot
  cmp #3
  bne @l
  rts

update_slot:
  stx t3
  lda o_prog,x
  bne @go                ; a partly sent redraw always continues
  txa                    ; otherwise each obstacle updates every other frame
  eor frame
  and #1
  beq @go
  rts
@go:
  lda o_prog,x           ; a redraw split over frames keeps its target: the rows already sent were
  beq :+                 ; drawn for it, and only that target is recorded as on screen at the end
  jsr pend_ptr
  ldy #63
@cp:
  lda (ptr),y
  sta newrec,y
  dey
  bpl @cp
  jmp @have
: lda o_type,x
  beq @gone
  jsr build_new
  jsr shear_rec
  jmp @have
@gone:
  lda o_ds,x
  cmp #$FF
  bne :+
  rts
: lda #0
  sta newrec
  sta newrec+1
  sta newrec+2
@have:
  ldx t3
  lda o_ds,x
  cmp #$FF
  beq @redraw            ; nothing drawn yet
  lda o_prog,x
  bne @redraw            ; unfinished redraw
  jsr cmp_rec            ; carry set when identical
  bcc @redraw
  rts
@redraw:
  jsr old_ptr            ; set 0: what is on screen (or nothing)
  ldx t3
  lda o_ds,x
  cmp #$FF
  bne :+
  lda #0
  sta sn
  sta sr0
  jmp @set1
: ldx #0
  jsr setup_set
@set1:
  lda #<newrec           ; set 1: what should be there
  sta ptr
  lda #>newrec
  sta ptr+1
  ldx #1
  jsr setup_set
  lda #255
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
  dec rbud
  bmi @defer
  jsr do_row
  bcs @defer
  inc rr
  jmp @row
@defer:
  ldx t3
  lda rr
  sta o_prog,x
  jsr pend_ptr           ; remember the target for the next frames
  ldy #63
: lda newrec,y
  sta (ptr),y
  dey
  bpl :-
  rts
@finish:
  ldx t3
  lda #0
  sta o_prog,x
  jsr old_ptr            ; remember what is drawn now
  ldy #0
  lda newrec+2
  sta t0
  lda newrec
  and #$80
  beq :+
  lda t0                 ; list: 3 + 2n
  asl a
  clc
  adc #3
  jmp @len
: lda #5
@len:
  sta t1
: lda newrec,y
  sta (ptr),y
  iny
  cpy t1
  bne :-
  ldx t3
  lda newrec+2           ; nothing drawn (an erased obstacle): the slot is free; anything else, even a
  bne :+                 ; gone obstacle whose split redraw just finished, is on screen and gets erased
  lda o_type,x           ; on its next update
  bne :+
  lda #$FF
  sta o_ds,x
  rts
: lda #0
  sta o_ds,x
  rts

pend_ptr:                  ; ptr = pendrec + slot * 64
  lda t3
  asl a
  asl a
  asl a
  asl a
  asl a
  asl a
  clc
  adc #<pendrec
  sta ptr
  lda #>pendrec
  adc #0
  sta ptr+1
  rts

old_ptr:                   ; ptr = oldrec + slot * 64
  lda t3
  asl a
  asl a
  asl a
  asl a
  asl a
  asl a
  clc
  adc #<oldrec
  sta ptr
  lda #>oldrec
  adc #0
  sta ptr+1
  rts

; carry set when newrec equals the record on screen
cmp_rec:
  jsr old_ptr
  ldy #0
  lda newrec+2
  sta t0
  lda newrec
  and #$80
  beq :+
  lda t0
  asl a
  clc
  adc #3
  jmp @len
: lda #5
@len:
  sta t1
: lda newrec,y
  cmp (ptr),y
  bne @no
  iny
  cpy t1
  bne :-
  sec
  rts
@no:
  clc
  rts

; ptr -> record, X = set (0 / 1)
setup_set:
  ldy #0
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
  clc
  lda ptr
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

; ---- projection helpers
; (gt1:gt0) = z (8.8) -> A = table index z * 8 clamped to 5..255
zidx:
  lda gt1
  bmi @min
  cmp #32
  bcs @max
  asl a
  asl a
  asl a
  sta t0
  lda gt0
  lsr a
  lsr a
  lsr a
  lsr a
  lsr a
  ora t0
  cmp #5
  bcs :+
@min:
  lda #5
: rts
@max:
  lda #255
  rts

; mR3:mR2 = pixel offset from the centre; A = tile column 0..32
tocol:
  clc
  lda mR2
  adc #132               ; centre 128 + 4 for rounding
  sta gt0
  lda mR3
  adc #0
  sta gt1
  ldx #3
  jsr asr16
  lda gt1
  bmi @zero
  bne @max
  lda gt0
  cmp #33
  bcc @ok
@max:
  lda #32
  rts
@zero:
  lda #0
  rts
@ok:
  lda gt0
  rts

; mR3:mR2 = pixel offset up from the centre: A = tile row 2..28
torow:
  sec
  lda #132
  sbc mR2
  sta gt0
  lda #0
  sbc mR3
  sta gt1
  ldx #3
  jsr asr16
  lda gt1
  bmi @top
  bne @bot
  lda gt0
  cmp #29
  bcs @bot
  cmp #2
  bcs @ok
@top:
  lda #2
  rts
@bot:
  lda #28
  rts
@ok:
  rts

; X = idx: mB = 128 / z, 8.8
load_scx:
  lda SCX_LO,x
  sta mBl
  lda SCX_HI,x
  sta mBh
  rts
load_scy:
  lda SCY_LO,x
  sta mBl
  lda SCY_HI,x
  sta mBh
  rts

; column of (edge - camera) at scale idx X: edge in (gt3:gt2)
proj_col:
  sec
  lda gt2
  sbc cwl
  sta mAl
  lda gt3
  sbc cwh
  sta mAh
  jsr load_scx
  jsr smulu
  jmp tocol

; row of height (gt3:gt2) at scale idx X, seen from eye height cey (0 except for beams)
proj_row:
  sec
  lda gt2
  sbc cey_l
  sta mAl
  lda gt3
  sbc cey_h
  sta mAh
  jsr load_scy
  jsr smulu
  jmp torow

; builds newrec for the obstacle in slot t3
; Pits, walls and pillars stand on the floor: they are projected from the standing eye so they move up
; and down with the floor of the picture. A beam is about where your head is, so it is seen from the
; real eye height (shear_rec then undoes the picture's vertical scroll): slide and it passes overhead.
build_new:
  ldx t3
  lda #0
  sta cey_l
  sta cey_h
  lda o_type,x
  cmp #4
  bne :+
  lda eyel
  sta cey_l
  lda eyeh
  sta cey_h
: ldx t3
  lda o_dl,x
  sta gt0
  lda o_dh,x
  sta gt1
  jsr zidx
  sta zin
  ldx t3
  clc
  lda o_dl,x
  adc o_ll,x
  sta gt0
  lda o_dh,x
  adc o_lh,x
  sta gt1
  jsr zidx
  sta zif
  ; class: tile cell size follows the distance
  lda zin
  ldy #0
  cmp #10
  bcc :+
  iny
  cmp #21
  bcc :+
  iny
: sty cls_
  ; columns at the near and the far end
  ldx t3
  ldy o_lane,x
  lda LAN_XLO_L,y
  sta gt2
  lda LAN_XLO_H,y
  sta gt3
  ldx zin
  jsr proj_col
  sta nc0
  ldx t3
  ldy o_lane,x
  lda LAN_XHI_L,y
  sta gt2
  lda LAN_XHI_H,y
  sta gt3
  ldx zin
  jsr proj_col
  sta nc1
  ldx t3
  lda o_type,x
  cmp #1
  bne :+
  ; pits also need the far end columns
  ldy o_lane,x
  lda LAN_XLO_L,y
  sta gt2
  lda LAN_XLO_H,y
  sta gt3
  ldx zif
  jsr proj_col
  sta fc0
  ldx t3
  ldy o_lane,x
  lda LAN_XHI_L,y
  sta gt2
  lda LAN_XHI_H,y
  sta gt3
  ldx zif
  jsr proj_col
  sta fc1
  jmp build_pit
: tay
  ; rows of the near face
  lda YTOP_L,y
  sta gt2
  lda YTOP_H,y
  sta gt3
  ldx zin
  jsr proj_row
  sta nr0
  ldx t3
  lda o_type,x
  tay
  lda YBOT_L,y
  sta gt2
  lda YBOT_H,y
  sta gt3
  ldx zin
  jsr proj_row
  sta nr1
  lda nc1
  cmp nc0
  bcc @empty
  beq @empty
  lda nr1
  cmp nr0
  bcc @empty
  beq @empty
  lda nc0
  cmp #32
  bcs @empty
  lda cls_
  sta newrec
  lda nr0
  sta newrec+1
  sec
  lda nr1
  sbc nr0
  sta newrec+2
  lda nc0
  sta newrec+3
  lda nc1
  sta newrec+4
  rts
@empty:
  lda #0
  sta newrec
  sta newrec+1
  sta newrec+2
  rts

; pits: a strip of floor between the near and the far end, narrowing with distance
build_pit:
  lda #<(-256)           ; floor: Y = -1
  sta gt2
  lda #>(-256)
  sta gt3
  ldx zif
  jsr proj_row
  sta nr0                ; far row (smaller)
  lda #<(-256)
  sta gt2
  lda #>(-256)
  sta gt3
  ldx zin
  jsr proj_row
  sta nr1                ; near row
  lda nr0
  cmp #16
  bcs :+
  lda #16
  sta nr0
: lda nr1
  cmp #28
  bcc :+
  lda #27
  sta nr1
: lda nr1
  cmp nr0
  bcs :+
  lda nr0
  sta nr1
: inc nr1                ; rows nr0 .. nr1-1
  lda nr1
  cmp #29
  bcc :+
  lda #28
  sta nr1
: lda #$83
  sta newrec
  lda nr0
  sta newrec+1
  sec
  lda nr1
  sbc nr0
  sta tmpc               ; n rows
  sta newrec+2
  bne :+
  jmp @empty
: ; interpolate columns from the far to the near end
  ldx tmpc
  dex
  lda RECIP8,x           ; 256 / (n - 1); n = 1 uses 255
  sta t2
  ; steps (signed 16)
  sec
  lda nc0
  sbc fc0
  sta mAl
  lda #0
  sbc #0
  sta mAh
  lda t2
  sta mBl
  lda #0
  sta mBh
  jsr smulu
  lda mR0
  sta st0l
  lda mR1
  sta st0h
  sec
  lda nc1
  sbc fc1
  sta mAl
  lda #0
  sbc #0
  sta mAh
  lda t2
  sta mBl
  lda #0
  sta mBh
  jsr smulu
  lda mR0
  sta st1l
  lda mR1
  sta st1h
  lda #0
  sta ac0l
  sta ac0h
  sta ac1l
  sta ac1h
  ldy #0
  ldx #3
@r:
  clc
  lda fc0
  adc ac0h
  bpl :+
  lda #0
: cmp #32
  bcc :+
  lda #31
: sta newrec,x
  sta t0
  clc
  lda fc1
  adc ac1h
  bpl :+
  lda #1
: cmp #33
  bcc :+
  lda #32
: cmp t0
  beq @bump
  bcs @ok
@bump:
  lda t0
  clc
  adc #1
@ok:
  sta newrec+1,x
  inx
  inx
  clc
  lda ac0l
  adc st0l
  sta ac0l
  lda ac0h
  adc st0h
  sta ac0h
  clc
  lda ac1l
  adc st1l
  sta ac1l
  lda ac1h
  adc st1h
  sta ac1h
  iny
  cpy tmpc
  bne @r
  rts
@empty:
  lda #0
  sta newrec
  rts
RECIP8: .byte 255, 255, 128, 85, 64, 51, 43, 37, 32, 28, 26, 23, 21, 20, 19, 17, 16, 15, 14, 13, 13, 12, 12, 11, 11, 10, 10, 9, 9, 9, 8, 8

; ------------------------------------------------------------------ camera
; The tunnel is a fixed picture, so the camera is a shear of it: a floor or ceiling point that is
; (r - 120) pixels from the horizon is 128/z = (r - 120) / (1 + eye) units close, so an eye move of
; dx, dy shifts that row by dx * |r - 120| pixels sideways and dy * |r - 120| pixels vertically;
; roll turns the picture about the centre. Vertical motion is applied per 32-line band (scaled to a
; quarter and clamped to 16 px): the band's tile bank switches on the line where its source pixels
; start, so the per-band tile images always match. The sideways shift changes every 8 lines, so the
; shear is a smooth slope instead of a staircase. Both are mid-frame scroll writes from the MMC3
; scanline IRQ, driven by a list built here.
BAND_W:  .byte 96, 72, 40, 8, 24, 56, 88, 0
BOBY:    .byte 253,254,254,255,255,0,0,1,1,1,2,2,2,2,2,3,3,3,2,2,2,2,2,1,1,1,0,0,255,255,254,254

calc_bands:
  lda #0
  sta cdxl
  sta cdxh
  sta cdyl
  sta cdyh
  sta crll
  sta crlh
  lda state
  beq @flat              ; title / game over: the picture stays put
  cmp #3
  bne :+
@flat:
  jmp @bands
: ; --- head bob while running on the floor
  ldx #0
  lda state
  cmp #1
  bne @nobob
  lda hl
  ora hhi
  bne @nobob
  lda slt
  bne @nobob
  lda vh_
  lsr a
  lsr a
  lsr a
  sta ctx
  lda vh_
  sec
  sbc ctx
  clc
  adc #8                 ; 256 * (1.8 + 0.2 v) / 60 per frame
  clc
  adc bph
  sta bph
  lsr a
  lsr a
  lsr a
  tax                    ; (no sideways bob: under a pixel, and it would rebuild the scroll list)
  lda BOBY,x
  sta cdyl
  bpl :+
  lda #$FF
  sta cdyh
:
@nobob:
  ; x and eye height
  clc
  lda xl
  adc cdxl
  sta cdxl
  lda xh
  adc cdxh
  sta cdxh
  clc
  lda eyel
  adc cdyl
  sta cdyl
  lda eyeh
  adc cdyh
  sta cdyh
  lda cdyh                ; clamp to (-0.95, 0.9)
  bmi @neg
  beq @ycl
  lda #230
  sta cdyl
  lda #0
  sta cdyh
  jmp @ycl
@neg:
  cmp #$FF
  bne @low
  lda cdyl
  cmp #13
  bcs @ycl
@low:
  lda #13
  sta cdyl
  lda #$FF
  sta cdyh
@ycl:
  ; roll = (x - lane centre) * 0.07
  ldy lane
  sec
  lda xl
  sbc LANE_C_L,y
  sta mAl
  lda xh
  sbc LANE_C_H,y
  sta mAh
  lda #18
  sta mBl
  lda #0
  sta mBh
  jsr smulu
  lda mR1
  sta crll
  lda mR2
  sta crlh
@bands:
  ; --- vertical: f_b = -(dy * w_b) / 4 per 32-line band (pixels the band's picture moves up);
  ; only when its inputs changed (a lane change, for one, leaves them alone)
  ldy #0
  lda cdyl
  cmp vkey+0
  beq :+
  sta vkey+0
  iny
:
  lda cdyh
  cmp vkey+1
  beq :+
  sta vkey+1
  iny
:
  lda state
  cmp vkey+2
  beq :+
  sta vkey+2
  iny
:
  lda deadt
  cmp vkey+3
  beq :+
  sta vkey+3
  iny
:
  lda kind
  cmp vkey+4
  beq :+
  sta vkey+4
  iny
:
  lda vok                ; (never computed yet: RAM starts out equal to the inputs)
  bne :+
  iny
  sta vok
  inc vok
: tya
  bne :+
  jmp @lateral
:
  ldy #0                 ; dy magnitude and sign
  lda cdyl
  ldx cdyh
  bpl :+
  eor #$FF
  clc
  adc #1
  dey
: sta cmag
  sty csgn
  ldx #7
@b:
  stx t3
  lda #0
  sta nbf,x
  lda BAND_W,x
  beq @next
  tay
  lda cmag
  jsr qmul               ; |dy| * w / 256
  lsr a
  lsr a                  ; / 4
  ldy csgn
  bmi :+
  eor #$FF               ; the picture moves down when the eye rises
  clc
  adc #1
: ldx t3
  sta nbf,x
@next:
  ; falling into a pit: the camera pitches down
  lda state
  cmp #2
  bne @nopit
  lda kind
  bne @nopit
  lda deadt
  lsr a
  cmp #16
  bcc :+
  lda #16
: clc
  adc nbf,x
  sta nbf,x
@nopit:
  ; clamp f to -16..16 (band 0 must not reveal the HUD: f >= 0)
  lda nbf,x
  bmi @fneg
  cmp #17
  bcc @fok
  lda #16
  bne @fok
@fneg:
  cmp #$F0
  bcs @fok
  lda #$F0
@fok:
  cpx #0
  bne :+
  cmp #$80
  bcc :+
  lda #0
: cpx #7
  bne :+
  lda #0
: sta nbf,x
  dex
  bpl @b
  ; --- where each band's source starts: band 0 at line 16 + f0, band 7 (status line) at 224, the
  ; others at 32 b; and where it starts on the screen: S0 = 16, S_b = 32 b - max(f_b, f_(b-1)) (the
  ; later band never starts after the line where the previous band's source pixels run out)
  ldx #6
: txa
  asl a
  asl a
  asl a
  asl a
  asl a
  sta nby,x
  dex
  bne :-
  lda #16
  clc
  adc nbf
  sta nby
  lda #224
  sta nby+7
  lda #16
  sta nbs
  ldx #1
@s:
  lda nbf,x
  sta ctx
  lda nbf-1,x
  sec
  sbc ctx
  bvc :+
  eor #$80
: bmi :+                 ; f_(b-1) >= f_b: take f_(b-1)
  lda nbf-1,x
  sta ctx
: txa
  asl a
  asl a
  asl a
  asl a
  asl a
  sec
  sbc ctx
  sta cd
  lda nbs-1,x            ; every band keeps at least 4 lines, so the IRQs stay apart
  clc
  adc #4
  cmp cd
  bcs :+
  lda cd
: sta nbs,x
  inx
  cpx #8
  bne @s
@lateral:
  ; --- sideways shift per screen line: a floor or ceiling row w lines from the horizon moves by
  ; (x -/+ roll) * w, above / below the horizon. |x -/+ roll| < 1, kept as magnitude and sign.
  sec
  lda cdxl
  sbc crll
  tay
  lda cdxh
  sbc crlh
  jsr @mag
  sta cam_a
  sty cas_a
  ldx #0                 ; and per 8 lines
  asl a
  bcc :+
  inx
: stx sth_a
  asl a
  rol sth_a
  asl a
  rol sth_a
  sta stl_a
  clc
  lda cdxl
  adc crll
  tay
  lda cdxh
  adc crlh
  jsr @mag
  sta cam_b
  sty cas_b
  ldx #0                 ; and per 8 lines
  asl a
  bcc :+
  inx
: stx sth_b
  asl a
  rol sth_b
  asl a
  rol sth_b
  sta stl_b
  ; --- the scroll list. Every band starts with a tile bank switch and a full scroll write; after
  ; that only the sideways shift changes, every 8 lines. It goes into the buffer the IRQ is not
  ; reading; the NMI swaps them. Within a band the shift is accumulated: |A| * w moves by |A| * 8.
  ; Nothing to do when the camera has not moved since the last list.
  ldy #0
  lda cdxl
  cmp ckey+0
  beq :+
  sta ckey+0
  iny
:
  lda cdxh
  cmp ckey+1
  beq :+
  sta ckey+1
  iny
:
  lda crll
  cmp ckey+2
  beq :+
  sta ckey+2
  iny
:
  lda crlh
  cmp ckey+3
  beq :+
  sta ckey+3
  iny
:
  lda sx
  cmp ckey+4
  beq :+
  sta ckey+4
  iny
:
  lda ctrl
  cmp ckey+5
  beq :+
  sta ckey+5
  iny
:
  lda nbf+0
  cmp ckey+6
  beq :+
  sta ckey+6
  iny
:
  lda nbf+1
  cmp ckey+7
  beq :+
  sta ckey+7
  iny
:
  lda nbf+2
  cmp ckey+8
  beq :+
  sta ckey+8
  iny
:
  lda nbf+3
  cmp ckey+9
  beq :+
  sta ckey+9
  iny
:
  lda nbf+4
  cmp ckey+10
  beq :+
  sta ckey+10
  iny
:
  lda nbf+5
  cmp ckey+11
  beq :+
  sta ckey+11
  iny
:
  lda nbf+6
  cmp ckey+12
  beq :+
  sta ckey+12
  iny
:
  tya
  bne :+
  rts
: lda #$FF
  sta epend
  ldy #29                ; rows the strips below do not mark take the entry above them (see the end)
: sta rowev,y
  dey
  bpl :-
  lda efront
  eor #EVN
  sta eb
  sta ei
  lda ctrl
  and #$7F
  sta cctl               ; PPUCTRL for the sideways-only entries (the IRQ sets bit 7 again)
  and #1
  asl a
  asl a
  sta cnt_               ; nametable bits for the full entries
  lda #0
  sta cb
@band:
  ldy cb
  lda nbs,y
  sta cl
  lda nby,y
  sta cs
  lda nbs+1,y            ; strips after the first: cl + 8 k <= next band - 4, source line < 236
  clc
  sbc cl
  sec
  sbc #3
  bcs :+
  lda #0
: lsr a
  lsr a
  lsr a
  sta ccnt
  lda #235
  sec
  sbc cs
  lsr a
  lsr a
  lsr a
  cmp ccnt
  bcs :+
  sta ccnt
: jsr @start
  ldx ei
  jsr @fix
  jsr @x                 ; band start: bank switch, nametable, Y and X
  sta ev_x,x
  tay
  lsr a
  lsr a
  lsr a
  sta ctx
  lda cs
  sta ev_y,x
  and #$38
  asl a
  asl a
  ora ctx
  sta ev_o,x
  ldy ev_x,x
  lda cnt_
  cpy #$80
  bcc :+
  eor #4                 ; negative scroll: the left neighbour's right edge
: ora #$80
  sta ev_n,x
  lda #7
  sta ev_l,x
  lda cl                 ; the tile rows at the middle of each strip, for the obstacles
  clc
  adc #4
  lsr a
  lsr a
  lsr a
  tay
  txa
  sta rowev,y
  iny
  inx
  lda ccnt
  sta ctmp
  bne @sl
  jmp @bend
@sl:
  bit cside
  bpl @dn
  lda cwd                ; above the horizon: w shrinks by 8
  sec
  sbc #8
  bcc @cr
  sta cwd
  lda acl
  sbc stl_a
  sta acl
  lda ach
  sbc sth_a
  sta ach
  jmp @hv
@cr:
  stx ei                 ; crossing the horizon: below it, 8 - w lines from it
  sty crow
  lda #8
  sec
  sbc cwd
  tay
  lda cam_b
  jsr qmul
  sta ach
  lda qlo
  sta acl
  lda cas_b
  sta csd
  lda #0
  sta cside
  ldx ei
  ldy crow
  jmp @hv
@dn:
  clc
  lda acl
  adc stl_b
  sta acl
  lda ach
  adc sth_b
  sta ach
@hv:
  lda acl                ; X = sx +/- round(acc / 256)
  asl a
  lda ach
  adc #0
  bit csd
  bpl :+
  eor #$FF
  sec
  adc sx
  jmp @st
: clc
  adc sx
@st:
  sta ev_x,x
  asl a                  ; negative: the other nametable (bit 1 is ignored mid-frame)
  lda cctl
  adc #0
  sta ev_n,x
  lda #7
  sta ev_l,x
  txa
  sta rowev,y
  iny
  inx
  dec ctmp
  beq @bend
  jmp @sl
@bend:
  stx ei
  lda ccnt               ; the line of this band's last entry
  asl a
  asl a
  asl a
  clc
  adc cl
  sta cpl
  inc cb
  lda cb
  cmp #7
  beq :+
  jmp @band
: ; the status line: still, apart from the shake
  lda nbs+7
  sta cl
  jsr @fix
  lda #224
  sta ev_y,x
  lda sx
  sta ev_x,x
  lsr a
  lsr a
  lsr a
  ora #$80               ; (224 & $38) << 2
  sta ev_o,x
  lda #$C0               ; bank switch, last
  ldy sx
  bpl :+
  ora #4
: sta ev_n,x
  lda #0                 ; no IRQ after the last entry
  sta ev_l,x
  ldy #2                 ; every tile row needs this list's entry: fill the gaps at band joints
  lda eb
: ldx rowev,y
  bmi :+
  txa                    ; a marked row: the running entry
: sta rowev,y
  iny
  cpy #30
  bne :--
  lda eb
  sta epend              ; ready: the NMI may hand it to the IRQ
  rts

@fix:                    ; the previous band's last entry counts the lines to this one (at cl)
  cpx eb
  beq :+
  lda cl
  clc
  sbc cpl
  sta ev_l-1,x
: rts

@x:                      ; A = sx +/- round(acc / 256)
  lda acl
  asl a
  lda ach
  adc #0
  bit csd
  bpl :+
  eor #$FF
  sec
  adc sx
  rts
: clc
  adc sx
  rts

@mag:                    ; A:Y = signed 8.8 -> A = magnitude (at most 255), Y = 0 or $FF
  bmi @mneg
  beq :+
  lda #255
  ldy #0
  rts
: tya
  ldy #0
  rts
@mneg:
  cmp #$FF
  bne :+
  tya
  eor #$FF
  clc
  adc #1
  beq :+                 ; -256
  ldy #$FF
  rts
: lda #255
  ldy #$FF
  rts

@start:                  ; acc = |A| * w for the strip starting at source line cs; side and sign
  lda cs
  clc
  adc #4                 ; middle of the strip
  sec
  sbc #120
  bcs @below
  eor #$FF
  adc #1
  sta cwd
  tay
  lda #$FF
  sta cside
  lda cam_a
  jsr qmul
  sta ach
  lda qlo
  sta acl
  lda cas_a
  sta csd
  rts
@below:
  sta cwd
  tay
  lda #0
  sta cside
  lda cam_b
  jsr qmul
  sta ach
  lda qlo
  sta acl
  lda cas_b
  sta csd
  rts

; A * Y (both 0..255) -> A = high byte, qlo = low byte. Quarter squares: ab = (a+b)^2/4 - (a-b)^2/4.
qmul:
  sta qa
  sty qb
  sec
  sbc qb
  bcs :+
  eor #$FF
  adc #1
: tay                    ; |a - b|
  lda qa
  clc
  adc qb
  tax
  bcs @hi
  lda QS_LO,x
  sec
  sbc QS_LO,y
  sta qlo
  lda QS_HI,x
  sbc QS_HI,y
  rts
@hi:
  lda QS_LO+256,x
  sec
  sbc QS_LO,y
  sta qlo
  lda QS_HI+256,x
  sbc QS_HI,y
  rts

QS_LO:
.repeat 512, i
  .byte <((i * i) / 4)
.endrep
QS_HI:
.repeat 512, i
  .byte >((i * i) / 4)
.endrep

; ------------------------------------------------------------------ obstacles under the camera shear
; newrec is the footprint seen from the camera. The picture is scrolled sideways row by row (calc_bands),
; so the tiles must be drawn where that scroll will carry them onto the right place: row D of the screen
; shows column + sh. Without this a pillar would shear with the floor, bend, and stay in view when you
; move away from it. Rewrites newrec as a per-row list in drawn coordinates.
shear_rec:
  lda newrec+2
  bne :+
  rts                    ; empty footprint: nothing to move
: lda newrec+1           ; (tsp is only read for rows the footprint covers, which are written first)
  sta sh_r0
  lda newrec+2
  sta sh_n
  lda newrec
  and #$7F
  sta sh_cls
  lda newrec
  and #$80
  sta sh_flag
  ldx #0
@ex:
  cpx sh_n
  bcs @exd
  lda sh_flag
  beq @rect
  txa
  asl a
  tay
  lda newrec+3,y
  sta sh_c0
  lda newrec+4,y
  sta sh_c1
  jmp @st
@rect:
  lda newrec+3
  sta sh_c0
  lda newrec+4
  sta sh_c1
@st:
  txa
  clc
  adc sh_r0
  asl a
  tay
  lda sh_c0
  sta tsp,y
  lda sh_c1
  sta tsp+1,y
  inx
  jmp @ex
@exd:
  lda sh_r0
  cmp #4
  bcs :+
  lda #4
: sec
  sbc #2
  sta sh_lo
  lda sh_r0
  clc
  adc sh_n
  clc
  adc #2
  cmp #29
  bcc :+
  lda #29
: sta sh_hi
  lda #0
  sta sh_o
  ldx #0                 ; floor obstacles move with the picture's vertical band scroll; a beam, seen
  lda cey_l              ; from the real eye, is lifted by the scroll of the band at its bottom edge,
  ora cey_h              ; rounded to whole rows, as a whole (per-row offsets would skip or double rows
  beq @nofq              ; where neighbouring bands round differently)
  lda sh_r0
  clc
  adc sh_n
  sec
  sbc #1
  lsr a
  lsr a
  tay
  lda nbf,y
  clc
  adc #4
  cmp #$80
  ror a
  cmp #$80
  ror a
  cmp #$80
  ror a
  tax
@nofq:
  stx sh_fq
  lda sh_lo
  sta sh_d
@d:
  lda sh_d
  cmp sh_hi
  bcc :+
  jmp @done
: ldy sh_d
  ldx rowev,y            ; this screen row's sideways shift in tiles
  lda ev_x,x
  clc
  adc #4
  cmp #$80
  ror a
  cmp #$80
  ror a
  cmp #$80
  ror a
  sta sh_sh
  lda sh_d
  sec
  sbc sh_fq
  sta sh_t
  cmp sh_r0
  bcc @none
  sec
  sbc sh_r0
  cmp sh_n
  bcs @none
  lda sh_t
  asl a
  tay
  lda tsp,y
  clc
  adc sh_sh
  jsr @clamp
  sta sh_c0
  lda sh_t
  asl a
  tay
  lda tsp+1,y
  clc
  adc sh_sh
  jsr @clamp
  sta sh_c1
  jmp @put
@none:
  lda #0
  sta sh_c0
  sta sh_c1
@put:
  ldy sh_o
  lda sh_c0
  sta newrec+3,y
  lda sh_c1
  sta newrec+4,y
  iny
  iny
  sty sh_o
  inc sh_d
  jmp @d
@done:
  lda sh_cls
  ora #$80
  sta newrec
  lda sh_lo
  sta newrec+1
  lda sh_hi
  sec
  sbc sh_lo
  sta newrec+2
  rts
@clamp:                  ; A signed -> 0..32
  bmi @c0
  cmp #33
  bcc @cr
  lda #32
@cr:
  rts
@c0:
  lda #0
  rts
