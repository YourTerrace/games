; ============================================================================
;  母ミレイユ (M2): 追従、癒やしの手 (A)、過治癒 (X)、崩壊
; ============================================================================
MS_FOLLOW   = 0
MS_HEAL     = 1
MS_OVER     = 2
MS_PUNCH    = 3

TAC_NEAR    = 0             ; よりそう: そばにいて、危なくなったら勝手に癒やす
TAC_FRONT   = 1             ; まえにでる: 近くの敵を殴りに行く
TAC_BACK    = 2             ; さがってて: 狙われにくく、慈力の戻りが速い
MOM_FIST    = 14            ; 拳
PUNCH_TIME  = 16
XHOLD_TIME  = 18            ; X をこれだけ押し続けると「殴って！」
AUTO_HP     = 40            ; よりそう: HP がこれ未満で勝手に癒やす

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
    lda m_down
    ora m_down+1
    beq :+
    rts
:   lda m_state
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
    lda cast_heal
    sta m_timer
    lda #SE_CAST
    jmp PlaySe
@x:
    lda pad                 ; X: 短く押して離すと過治癒、押し続けると「殴って！」
    and #$40
    beq @xup
    lda pad_new
    and #$40
    beq :+
    lda #1
    sta m_xhold
    rts
:   lda m_xhold
    beq @out
    inc m_xhold
    lda m_xhold
    cmp #XHOLD_TIME
    bcc @out
    stz m_xhold
    lda #1
    sta m_order
    lda #SE_CAST
    jmp PlaySe
@xup:
    lda m_xhold
    beq @out
    stz m_xhold
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
    lda cast_over
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
    lda m_inv
    beq :+
    dec m_inv
:   rep #$20
    lda m_down
    beq @up
    dec m_down
    sep #$20
    bne @still
@revive:
    stz m_down
    stz m_down+1
    lda #MOM_HP_MAX*3/10
    sta m_hp
    lda #SE_HEAL
    jmp PlaySe
@still:
    ; そばで A を押し続けると 1.5 秒で助け起こせる
    lda pad
    bpl @no_rev
    lda p_x+1
    sec
    sbc m_x+1
    bcs :+
    eor #$FF
    inc a
:   cmp #24
    bcs @no_rev
    lda p_y+1
    sec
    sbc m_y+1
    bcs :+
    eor #$FF
    inc a
:   cmp #20
    bcs @no_rev
    inc m_rev
    lda m_rev
    cmp #90
    bcs @revive
    rts
@no_rev:
    stz m_rev
    rts
@up:
    sep #$20
    lda meal                ; 慈力は毎秒およそ2回復 (茸飯なら倍)
    cmp #MEAL_DEW
    bne :+
    lda #$0F
    bra :++
:   lda #$1F
:   sta t0                  ; さがってて なら さらに倍
    lda m_tac
    cmp #TAC_BACK
    lda t0
    bcc :+
    lsr a
:   and tick
    bne :+
    lda m_ji
    cmp #100
    bcs :+
    inc m_ji
:   lda m_cd
    beq :+
    dec m_cd
:   lda m_auto
    beq :+
    dec m_auto
:   lda m_state
    beq @follow
    cmp #MS_PUNCH
    bne :+
    jmp MotherPunch
:   ; 詠唱中: 動かない。手元がきらめく
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
    jsr MotherDecide        ; 勝手に癒やす / 殴りに行く。行き先を mdx, mdy に
    bcc :+
    rts
:   rep #$20
    lda mdx
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
    lda mdy
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
    cmp mstop_x
    bcs @go
    lda ady
    cmp mstop_y
    bcs @go
    sep #$20
    stz m_anim
    rts
@go:
    .a16
    lda m_x
    sta om_x
    lda m_y
    sta om_y
    lda adx                 ; はぐれたら主人公のそばへ跳ぶ
    clc
    adc ady
    cmp #150
    bcc :+
    lda p_x
    sta m_x
    lda p_y
    sta m_y
:   lda adx                 ; 離されたら小走り
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
    sep #$20                ; 壁にめり込むなら動かない
    lda m_x+1
    sta cx
    lda m_y+1
    sta cy
    jsr SolidAt
    rep #$20
    bcc :+
    lda om_x
    sta m_x
    lda om_y
    sta m_y
:   lda adx
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

; 作戦に従って次の行動を決める。行動を始めたらキャリーを立てる
MotherDecide:
    .a8
    lda p_x+1               ; ふつうは主人公のそばへ
    sta mdx
    lda p_y+1
    sta mdy
    lda #30
    sta mstop_x
    lda #26
    sta mstop_y
    stz mstop_x+1
    stz mstop_y+1
    lda m_tac               ; よりそう: 危なくなったら勝手に癒やす
    bne @chase
    lda m_auto
    bne @chase
    rep #$20
    lda p_hp
    cmp #AUTO_HP
    sep #$20
    bcs @chase
    lda m_ji
    cmp #HEAL_COST
    bcc @chase
    sbc #HEAL_COST
    sta m_ji
    lda #MS_HEAL
    sta m_state
    lda cast_heal
    sta m_timer
    lda #180
    sta m_auto
    lda #SE_CAST
    jsr PlaySe
    sec
    rts
@chase:
    lda m_order             ; 「殴って！」か、まえにでる なら敵へ
    bne :+
    lda m_tac
    cmp #TAC_FRONT
    bne @stay
:   jsr FindNearest
    bcs :+
    stz m_order
@stay:
    clc
    rts
:   ldx near_idx
    lda d_x+1,x
    sta mdx
    lda d_y+1,x
    sta mdy
    lda #10
    sta mstop_x
    lda #8
    sta mstop_y
    lda m_cd                ; 拳が届くなら殴る
    bne @stay
    lda mdx
    sec
    sbc m_x+1
    bcs :+
    eor #$FF
    inc a
:   cmp #20
    bcs @stay
    lda mdy
    sec
    sbc m_y+1
    bcs :+
    eor #$FF
    inc a
:   cmp #16
    bcs @stay
    stx m_target
    lda #MS_PUNCH
    sta m_state
    lda #PUNCH_TIME
    sta m_timer
    lda #50
    sta m_cd
    stz m_order
    sec
    rts

; 整骨拳: 構えて、半ばで当てる
MotherPunch:
    .a8
    dec m_timer
    bne :+
    stz m_state
    rts
:   lda m_timer
    cmp #PUNCH_TIME/2
    beq :+
    rts
:   ldx m_target
    lda d_type,x
    bne :+
    rts
:   lda d_dead,x
    beq :+
    rts
:   lda #MOM_FIST*3         ; 拳 × 3 − 守
    sec
    sbc d_def,x
    bcs :+
    lda #1
:   sta t3
    stz t3+1
    lda d_col,x             ; 崩壊中は2倍
    beq :+
    asl t3
:   rep #$20
    lda t3
    sta last_dmg
    lda d_hp,x
    sec
    sbc t3
    beq @dead
    bpl @alive
@dead:
    stz d_hp,x
    sep #$20
    lda #DEAD_TIME
    sta d_dead,x
    bra @knock
@alive:
    sta d_hp,x
    sep #$20
@knock:
    lda d_type,x            ; ボス以外は殴り飛ばす
    cmp #TYPE_BOSS
    beq @fx
    rep #$20
    lda d_x+1,x
    and #$00FF
    sta t1
    lda m_x+1
    and #$00FF
    cmp t1
    lda #$0500
    bcc :+
    lda #$10000-$0500
:   sta d_vx,x
    stz d_vy,x
    sep #$20
    lda #30
    sta d_stun,x
    stz d_state,x
@fx:
    lda #12
    sta d_flash,x
    lda #8
    sta hitstop
    lda #6
    sta shake_t
    lda #SE_HEAVY
    jsr PlaySe
    jmp SpawnSparkAtDummy

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
    lda m_hp                ; 母自身も少し回復
    clc
    adc #20
    cmp #MOM_HP_MAX
    bcc :+
    lda #MOM_HP_MAX
:   sta m_hp
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
    lda over_amt
    and #$00FF
    clc
    adc d_sat,x
    sta d_sat,x
    cmp d_satmax,x
    bcc @no
    ; ---- 崩壊 ----
    sep #$20
    jsr ChartWrite
    rep #$20
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
    lda m_inv               ; 被弾直後は点滅
    and #$02
    beq :+
    rts
:   lda #(PAL_MOM | PRIO)
    sta t3
    lda m_down
    ora m_down+1
    beq @standing
    ; ひざをつく (仮: 正面の立ち絵を低く描き、ゆっくり明滅)
    lda tick
    and #$10
    beq :+
    lda #(PAL_FLASH | PRIO)
    sta t3
:   lda mom_frame_tbl
    sta spr_tile
    lda mom_frame_tbl+1
    ora t3
    sta spr_attr
    lda #$02
    sta spr_size
    SPR_AT m_x, m_y, -16, -20
    jmp AddSprite
@standing:
    lda m_state
    beq @walk
    cmp #MS_PUNCH           ; 殴る: 構え → 打ち (正面の立ち絵を前へずらす)
    bne @cast
    lda m_timer
    cmp #PUNCH_TIME/2
    bcs @cast
    lda m_face
    asl a
    asl a
    rep #$20
    and #$00FF
    tax
    sep #$20
    lda mom_frame_tbl,x
    sta spr_tile
    lda mom_frame_tbl+1,x
    ora t3
    sta spr_attr
    lda #$02
    sta spr_size
    lda m_face
    asl a
    rep #$20
    and #$00FF
    tax
    lda m_x+1
    and #$00FF
    clc
    adc punch_dx,x
    sec
    sbc #16
    sta spr_x
    lda m_y+1
    and #$00FF
    clc
    adc punch_dy,x
    sec
    sbc #26
    sta spr_y
    sep #$20
    jmp AddSprite
@cast:
@castdraw:
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
    ora t3
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

; 殴る時に前へずらす量 (向き: 下, 上, 左, 右)
punch_dx: .word 0, 0, $10000-6, 6
punch_dy: .word 6, $10000-6, 0, 0
