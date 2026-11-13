; ============================================================================
;  母ミレイユ (M2): 追従、癒やしの手 (A)、過治癒 (X)、崩壊
; ============================================================================
MS_FOLLOW   = 0
MS_HEAL     = 1
MS_OVER     = 2

HEAL_COST   = 20
HEAL_TIME   = 60            ; 詠唱 1.0 秒
HEAL_AMOUNT = 40
OVER_COST   = 15
OVER_TIME   = 48            ; 詠唱 0.8 秒
OVER_AMOUNT = 30
HP_MAX      = 100
HP_LIMIT    = 150           ; これを超える回復で「癒え焼け」
COLLAPSE_TIME = 180

; A / X の合図を受ける (主人公の状態に関係なく出せる)
MotherCommands:
    .a8
    lda m_state
    bne @out
    lda dead_t
    bne @out
    lda pad_new
    bpl @x                  ; bit7 = A
    lda m_ji
    cmp #HEAL_COST
    bcc @deny
    sbc #HEAL_COST
    sta m_ji
    lda #MS_HEAL
    sta m_state
    lda #HEAL_TIME
    sta m_timer
    lda #SE_CAST
    jmp PlaySe
@x:
    lda pad_new
    and #$40                ; X
    beq @out
    lda m_ji
    cmp #OVER_COST
    bcc @deny
    jsr FindNearest
    bcc @out
    lda m_ji
    sec
    sbc #OVER_COST
    sta m_ji
    ldx near_idx
    stx m_target
    lda #MS_OVER
    sta m_state
    lda #OVER_TIME
    sta m_timer
    lda #SE_CAST
    jmp PlaySe
@deny:
    lda #SE_DENY
    jmp PlaySe
@out:
    rts

; 主人公にいちばん近い生きた敵 → near_idx。見つかればキャリーを立てる
FindNearest:
    .a8
    rep #$20
    lda #$FFFF
    sta near_idx
    lda #$7FFF
    sta bi
    sep #$20
    ldx #$0000
@loop:
    lda d_type,x
    beq @next
    lda d_dead,x
    bne @next
    jsr EnemyDelta
    rep #$20
    lda adx
    clc
    adc ady
    cmp bi
    bcs :+
    sta bi
    stx near_idx
:   sep #$20
@next:
    inx
    inx
    cpx #DUMMY_END
    bne @loop
    lda near_idx+1
    bmi :+
    sec
    rts
:   clc
    rts

UpdateMother:
    .a8
    lda tick                ; 慈力は毎秒およそ2回復
    and #$1F
    bne :+
    lda m_ji
    cmp #100
    bcs :+
    inc m_ji
:   lda m_state
    beq @follow
    ; 詠唱中: 動かない。手元がきらめく
    lda tick
    and #$07
    bne :+
    lda m_x+1
    sta fx_ax
    lda m_y+1
    sec
    sbc #12
    sta fx_ay
    lda #PAL_HEAL
    sta fx_p
    jsr SpawnFx
:   dec m_timer
    beq :+
    rts
:   lda m_state
    stz m_state
    cmp #MS_HEAL
    bne :+
    jmp MotherHeal
:   jmp MotherOverdrive

@follow:
    rep #$20
    lda p_x+1
    and #$00FF
    sta t1
    lda m_x+1
    and #$00FF
    sta t3
    lda t1
    sec
    sbc t3
    sta t1
    bpl :+
    eor #$FFFF
    inc a
:   sta adx
    lda p_y+1
    and #$00FF
    sta t2
    lda m_y+1
    and #$00FF
    sta t3
    lda t2
    sec
    sbc t3
    sta t2
    bpl :+
    eor #$FFFF
    inc a
:   sta ady
    lda adx
    cmp #30
    bcs @go
    lda ady
    cmp #26
    bcs @go
    sep #$20
    stz m_anim
    rts
@go:
    .a16
    lda adx                 ; 離されたら小走り
    clc
    adc ady
    cmp #70
    lda #$0150
    bcc :+
    lda #$01E0
:   sta t0
    lda adx
    cmp #6
    bcc @y
    lda t1
    bmi @xn
    lda m_x
    clc
    adc t0
    sta m_x
    bra @y
@xn:
    lda m_x
    sec
    sbc t0
    sta m_x
@y:
    lda ady
    cmp #6
    bcc @face
    lda t2
    bmi @yn
    lda m_y
    clc
    adc t0
    sta m_y
    bra @face
@yn:
    lda m_y
    sec
    sbc t0
    sta m_y
@face:
    lda adx
    cmp ady
    sep #$20
    bcc @vert
    lda #3
    ldy t1
    bpl :+
    lda #2
:   sta m_face
    inc m_anim
    rts
@vert:
    lda #0
    ldy t2
    bpl :+
    lda #1
:   sta m_face
    inc m_anim
    rts

; 癒やしの手。最大HPを超えた分は「過剰生命」、超えすぎると「癒え焼け」
MotherHeal:
    .a8
    lda p_x+1
    sta fx_ax
    lda p_y+1
    sta fx_ay
    rep #$20
    lda p_hp
    clc
    adc #HEAL_AMOUNT
    cmp #HP_LIMIT+1
    bcs @burn
    sta p_hp
    sep #$20
    lda #PAL_HEAL
    sta fx_p
    jsr SpawnFx
    lda #SE_HEAL
    jmp PlaySe
@burn:
    .a16
    lda #HP_MAX-10
    sta p_hp
    stz dodge_vx
    stz dodge_vy
    sep #$20
    lda #ST_HURT
    sta p_state
    stz p_timer
    lda #8
    sta hitstop
    sta shake_t
    lda #PAL_FX
    sta fx_p
    jsr SpawnFx
    lda #SE_HURT
    jmp PlaySe

; 過治癒。飽和が満ちたら崩壊
MotherOverdrive:
    .a8
    ldx m_target
    lda d_type,x
    beq @gone
    lda d_dead,x
    beq :+
@gone:
    rts
:
    lda d_x+1,x
    sta fx_ax
    lda d_y+1,x
    sta fx_ay
    lda #PAL_HEAL
    sta fx_p
    jsr SpawnFx
    lda d_col,x
    bne @gone
    rep #$20
    lda d_sat,x
    clc
    adc #OVER_AMOUNT
    sta d_sat,x
    cmp d_satmax,x
    bcc @no
    ; ---- 崩壊 ----
    stz d_sat,x
    lda d_satmax,x          ; 次は 1.5 倍必要
    lsr a
    clc
    adc d_satmax,x
    sta d_satmax,x
    lda d_maxhp,x           ; 最大HPの 25%
    lsr a
    lsr a
    sta t0
    sta last_dmg
    lda d_hp,x
    sec
    sbc t0
    beq @kill
    bpl @live
@kill:
    stz d_hp,x
    sep #$20
    lda #DEAD_TIME
    sta d_dead,x
    bra @col
@live:
    sta d_hp,x
    sep #$20
@col:
    lda #COLLAPSE_TIME
    sta d_col,x
    lda #$01
    sta d_noregen,x         ; この戦闘中は再生を封じる
    stz d_state,x
    stz d_stun,x
    lda #12
    sta hitstop
    sta d_flash,x
    lda #10
    sta shake_t
    lda #SE_COLLAPSE
    jmp PlaySe
@no:
    sep #$20
    lda #SE_HEAL
    jmp PlaySe
@out:
    rts

DrawMother:
    .a8
    lda m_state
    beq @walk
    lda mom_cast_frame
    sta spr_tile
    lda mom_cast_frame+1
    bra @attr
@walk:
    lda m_anim
    lsr a
    lsr a
    lsr a
    and #$01
    asl a
    sta t0
    lda m_face
    asl a
    asl a
    clc
    adc t0
    rep #$20
    and #$00FF
    tax
    sep #$20
    lda mom_frame_tbl,x
    sta spr_tile
    lda mom_frame_tbl+1,x
@attr:
    ora #(PAL_MOM | PRIO)
    sta spr_attr
    lda #$02
    sta spr_size
    SPR_AT m_x, m_y, -16, -26
    jmp AddSprite

; 主人公と母を奥行き順に
DrawHeroAndMother:
    .a8
    rep #$20
    lda m_y
    cmp p_y
    sep #$20
    bcc @behind
    jsr DrawMother
    jsr DrawSwords
    jmp DrawPlayer
@behind:
    jsr DrawSwords
    jsr DrawPlayer
    jmp DrawMother
