; ============================================================================
;  敵 (M2): 苔ネズミ / 蔓へび / 芽吹き案山子
;  行動は共通の型: 接近 → 溜め(予備動作) → 突進攻撃 → 硬直
;  配列は main.s の d_* (2バイト刻み、X=0,2,..)
; ============================================================================
TYPE_RAT    = 1
TYPE_SNAKE  = 2
TYPE_SCARE  = 3
; TYPE_BOSS = 4 は rooms.inc で定義

ES_APPROACH = 0
ES_WINDUP   = 1
ES_ATTACK   = 2
ES_RECOVER  = 3

; X = 敵 → Y = 種別 (バイト表の添字)
TypeToY:
    .a8
    rep #$20
    lda d_type,x
    and #$00FF
    tay
    sep #$20
    rts

; A = 種別, t1 = X(ピクセル), t2 = Y(ピクセル)。空きが無ければ何もしない
SpawnEnemy:
    .a8
    sta t0
    stz t0+1
    ldx #$0000
@find:
    lda d_type,x
    beq @use
    inx
    inx
    cpx #DUMMY_END
    bne @find
    rts
@use:
    lda t0
    sta d_type,x
    stz d_state,x
    stz d_timer,x
    stz d_stun,x
    stz d_col,x
    stz d_atkdone,x
    stz d_noregen,x
    stz d_dead,x
    stz d_bump,x
    stz d_flip,x
    lda #$FF
    sta d_hitid,x
    lda #12
    sta d_flash,x
    rep #$20
    lda t1
    and #$00FF
    xba
    sta d_x,x
    lda t2
    and #$00FF
    xba
    sta d_y,x
    stz d_vx,x
    stz d_vy,x
    stz d_sat,x
    lda t0
    asl a
    tay
    lda e_hp,y
    sta d_hp,x
    sta d_maxhp,x
    lda e_satmax,y
    sta d_satmax,x
    lda e_defh,y
    sta d_def,x
    sep #$20
    rts

; X = 敵 → t1 = 主人公X − 敵X, t2 = 同Y (符号付き16bit)、adx/ady = 絶対値
EnemyDelta:
    .a8
    lda p_x+1
    sta tpx
    lda p_y+1
    sta tpy
; 同じく、tpx/tpy に入っている位置との差
EnemyDeltaT:
    .a8
    rep #$20
    lda tpx
    and #$00FF
    sta t1
    lda d_x+1,x
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
    lda tpy
    and #$00FF
    sta t2
    lda d_y+1,x
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
    sep #$20
    rts

UpdateEnemies:
    .a8
    ldx #$0000
@loop:
    lda d_type,x
    bne :+
    jmp @next
:   lda d_dead,x
    beq :+
    jmp @next
:   jsr EnemySavePos
    jsr EnemyRegen
    lda d_col,x             ; 崩壊中は動けない
    beq :+
    dec d_col,x
    jmp @next
:   lda d_stun,x            ; のけぞり中
    beq :+
    dec d_stun,x
    jmp @next
:   jsr EnemyTarget
    lda d_state,x
    beq @approach
    cmp #ES_WINDUP
    beq @windup
    cmp #ES_ATTACK
    beq @attack
    dec d_timer,x           ; 硬直
    bne @next
    stz d_state,x
    jsr BossSummon
    bra @next
@windup:
    dec d_timer,x
    bne @next
    lda #ES_ATTACK
    sta d_state,x
    jsr TypeToY
    lda e_atkfr,y
    sta d_timer,x
    stz d_atkdone,x
    jsr PatternStart
    jmp @next
@attack:
    jsr EnemyAttackMove
    dec d_timer,x
    bne @next
    lda #ES_RECOVER
    sta d_state,x
    jsr TypeToY
    lda e_recover,y
    sta d_timer,x
    bra @next
@approach:
    jsr EnemyApproach
@next:
    lda d_type,x
    beq :+
    jsr EnemyClip
:   inx
    inx
    cpx #DUMMY_END
    beq :+
    jmp @loop
:   rts

; 狙う相手を決めて差分を出す。詠唱中の母は全員に狙われ、蔓へびは常に母を狙う
EnemyTarget:
    .a8
    stz d_tgt,x
    lda m_down
    ora m_down+1
    bne @player
    lda m_state
    bne @mom
    lda m_tac               ; さがってて の母は、詠唱していなければ狙われない
    cmp #TAC_BACK
    beq @player
    lda d_type,x
    cmp #TYPE_SNAKE
    bne @player
@mom:
    lda #$01
    sta d_tgt,x
    lda m_x+1
    sta tpx
    lda m_y+1
    sta tpy
    jmp EnemyDeltaT
@player:
    jmp EnemyDelta

; 飽和の自然減衰と、繁り属性の再生
EnemyRegen:
    .a8
    lda tick
    and #$0F
    bne @regen
    rep #$20
    lda d_sat,x
    beq :+
    dec a
    sta d_sat,x
:   sep #$20
@regen:
    lda tick
    and #$1F
    bne @done
    lda d_noregen,x
    bne @done
    jsr TypeToY
    lda e_regen,y
    beq @done
    sta t0
    stz t0+1
    rep #$20
    lda d_hp,x
    clc
    adc t0
    cmp d_maxhp,x
    bcc :+
    lda d_maxhp,x
:   sta d_hp,x
    sep #$20
@done:
    rts

; 主人公へ歩く。間合いに入ったら狙いを定めて溜めに入る
EnemyApproach:
    .a8
    stz d_flip,x
    lda t1+1
    bpl :+
    lda #$40
    sta d_flip,x
:   jsr TypeToY
    lda adx+1
    bne @move
    lda ady+1
    bne @move
    lda adx
    cmp e_range,y
    bcs @move
    lda ady
    cmp e_range,y
    bcs @move
    lda #ES_WINDUP
    sta d_state,x
    lda e_windup,y
    sta d_timer,x
    lda d_pat,x             ; 技を順に回す
    inc a
    cmp e_npat,y
    bcc :+
    lda #0
:   sta d_pat,x
    jmp EnemyAim
@move:
    rep #$20
    tya
    asl a
    tay
    lda adx
    cmp #4
    bcc @my
    lda t1
    bmi @mxn
    lda d_x,x
    clc
    adc e_speed,y
    sta d_x,x
    bra @my
@mxn:
    lda d_x,x
    sec
    sbc e_speed,y
    sta d_x,x
@my:
    lda ady
    cmp #4
    bcc @mdone
    lda t2
    bmi @myn
    lda d_y,x
    clc
    adc e_speed,y
    sta d_y,x
    bra @mdone
@myn:
    lda d_y,x
    sec
    sbc e_speed,y
    sta d_y,x
@mdone:
    sep #$20
    rts

; 溜めの開始時点の主人公の方向へ、突進の速度を決める (8方向)
; Y = 種別
EnemyAim:
    .a8
    rep #$20
    tya
    asl a
    tay
    lda e_atkspd,y
    sta t0
    stz d_avx,x
    stz d_avy,x
    lda ady
    asl a
    cmp adx
    bcc @x_only
    lda adx
    asl a
    cmp ady
    bcc @y_only
    lda t0                  ; 斜めは 3/4
    lsr a
    lsr a
    sta t3
    lda t0
    sec
    sbc t3
    sta t0
    jsr AimX
    jsr AimY
    sep #$20
    rts
@x_only:
    jsr AimX
    sep #$20
    rts
@y_only:
    jsr AimY
    sep #$20
    rts

AimX:
    .a16
    lda t1
    bmi :+
    lda t0
    sta d_avx,x
    rts
:   lda #$0000
    sec
    sbc t0
    sta d_avx,x
    rts
AimY:
    .a16
    lda t2
    bmi :+
    lda t0
    sta d_avy,x
    rts
:   lda #$0000
    sec
    sbc t0
    sta d_avy,x
    rts

; 突進して、主人公に重なったら当てる
EnemyAttackMove:
    .a8
    rep #$20
    lda d_x,x
    clc
    adc d_avx,x
    cmp #MINX
    bcs :+
    lda #MINX
:   cmp #MAXX
    bcc :+
    lda #MAXX
:   sta d_x,x
    lda d_y,x
    clc
    adc d_avy,x
    cmp #MINY
    bcs :+
    lda #MINY
:   cmp #MAXY
    bcc :+
    lda #MAXY
:   sta d_y,x
    sep #$20
    lda d_atkdone,x
    beq :+
    rts
:   jsr TypeToY
    lda e_hitw,y            ; 当たりの大きさ (薙ぎ払いは広い)
    sta hit_w
    lda e_hith,y
    sta hit_h
    lda d_pat,x
    cmp #PAT_SWEEP
    bne :+
    lda #56
    sta hit_w
    lda #44
    sta hit_h
:   jsr EnemyDelta
    jsr TypeToY
    lda adx+1
    ora ady+1
    bne @mom
    lda adx
    cmp hit_w
    bcs @mom
    lda ady
    cmp hit_h
    bcs @mom
    lda e_atk,y
    jmp HurtPlayer
@mom:
    lda m_down
    ora m_down+1
    bne @done
    lda m_x+1
    sta tpx
    lda m_y+1
    sta tpy
    jsr EnemyDeltaT
    lda adx+1
    ora ady+1
    bne @done
    lda adx
    cmp hit_w
    bcs @done
    lda ady
    cmp hit_h
    bcs @done
    lda e_atk,y
    jmp HurtMother
@done:
    rts

; A = ダメージ, X = 当ててきた敵。詠唱は中断され、HP が尽きるとひざをつく
HurtMother:
    .a8
    sta t0
    lda am_on               ; 母の割烹着: 3/4 に
    and #AMB_APRON
    beq :+
    lda t0
    lsr a
    lsr a
    sta t1
    lda t0
    sec
    sbc t1
    sta t0
:
    lda #$01
    sta d_atkdone,x
    lda m_inv
    bne @out
    stz m_state
    lda #60
    sta m_inv
    lda #4
    sta hitstop
    lda m_hp
    sec
    sbc t0
    beq @down
    bcs @ok
@down:
    stz m_hp
    stz m_rev
    rep #$20
    lda #900                ; 15 秒で自力復帰
    sta m_down
    sep #$20
    lda #SE_COLLAPSE
    jmp PlaySe
@ok:
    sta m_hp
    lda #SE_HURT
    jmp PlaySe
@out:
    rts

; A = ダメージ, X = 当ててきた敵
HurtPlayer:
    .a8
    sta t0
    stz t0+1
    lda #$01
    sta d_atkdone,x
    lda dead_t
    beq :+
    rts
:   lda p_state
    cmp #ST_DODGE
    bne @no_dodge
    lda #10                 ; 無敵は回避の最初の10F (眼帯なら 8F)
    sta t2
    lda am_on
    and #AMB_PATCH
    beq :+
    lda #8
    sta t2
:   lda p_timer
    cmp t2
    bcs @no_dodge
    sta t1
    jsr TypeToY             ; 見切った (印3つ) 攻撃は受付 6F → 9F。眼帯で +2F
    lda #6
    sta t2
    stz p_justm
    lda marks,y
    cmp #MARK_MAX
    bcc :+
    lda #9
    sta t2
    inc p_justm
:   lda am_on
    and #AMB_PATCH
    beq :+
    inc t2
    inc t2
:   lda t1
    cmp t2
    bcs @out
    lda marks,y             ; 見切り印を 1 つ
    cmp #MARK_MAX
    bcs :+
    inc a
    sta marks,y
    phx
    jsr RecalcStats
    plx
:   lda #50
    sta p_just
    stx just_idx
    lda #10
    sta hitstop
    sta dim_t
    lda #SE_JUST
    jsr PlaySe
    rts
@no_dodge:
    lda p_inv
    bne @out
    lda t0                  ; 守の分だけ軽く (最低 1)
    sec
    sbc p_def
    beq :+
    bcs :++
:   lda #1
:   sta t0
    rep #$20
    lda p_hp
    sec
    sbc t0
    beq @die
    bpl @ok
@die:
    stz p_hp
    sep #$20
    lda #120
    sta dead_t
    rep #$20
    bra @knock
@ok:
    sta p_hp
@knock:
    lda d_avx,x
    ASR16
    sta dodge_vx
    lda d_avy,x
    ASR16
    sta dodge_vy
    sep #$20
    lda #ST_HURT
    sta p_state
    stz p_timer
    stz p_charge
    lda #60
    sta p_inv
    lda #5
    sta hitstop
    lda #6
    sta shake_t
    stz combo
    lda #SE_HURT
    jsr PlaySe
@out:
    rts

; 被弾のけぞり
PlayerHurt:
    .a8
    rep #$20
    lda dodge_vx
    sta vx
    lda dodge_vy
    sta vy
    sep #$20
    jsr MovePlayer
    jsr SetRestSwords
    inc p_timer
    lda p_timer
    cmp #14
    bcc :+
    stz p_state
:   rts

; X = 敵。主人公をその敵の方へ向ける (返し刃用)
FacePlayerTo:
    .a8
    lda d_type,x
    beq @done
    jsr EnemyDelta
    rep #$20
    lda adx
    cmp ady
    sep #$20
    bcc @vert
    lda #3
    ldy t1                  ; t1 = 主人公 − 敵。負なら敵は右
    bmi :+
    lda #2
:   sta p_face
    rts
@vert:
    lda #0
    ldy t2
    bmi :+
    lda #1
:   sta p_face
@done:
    rts

; ボスは硬直が明けるたび、手下が少なければ苔ネズミを呼ぶ
BossSummon:
    .a8
    lda d_type,x
    cmp #TYPE_BOSS
    bne @out
    ldy #$0000
    stz t0
@count:
    lda d_type,y
    beq :+
    inc t0
:   iny
    iny
    cpy #DUMMY_END
    bne @count
    lda t0
    cmp #3
    bcs @out
    phx
    lda d_x+1,x
    clc
    adc #28
    sta t1
    lda d_y+1,x
    clc
    adc #20
    sta t2
    lda #TYPE_RAT
    jsr SpawnEnemy
    plx
@out:
    rts

; ---- 敵の描画 ---------------------------------------------------------------
; X = 敵 → A = コマ番号
EnemyFrame:
    .a8
    lda d_col,x
    bne @two
    lda d_stun,x
    bne @two
    lda d_state,x
    beq @walk
    cmp #ES_WINDUP
    beq @wind
    cmp #ES_ATTACK
    beq @atk
@zero:
    lda #0
    rts
@walk:
    lda d_type,x
    cmp #TYPE_SCARE
    beq @zero
    lda tick
    lsr a
    lsr a
    lsr a
    and #$01
    rts
@wind:
    lda d_type,x
    cmp #TYPE_SCARE
    beq @one
@two:
    lda #2
    rts
@one:
    lda #1
    rts
@atk:
    lda d_type,x
    cmp #TYPE_SCARE
    beq @two
    lda #3
    rts

; X = 敵
DrawDummy:
    .a8
    lda d_type,x
    bne :+
    rts
:   lda d_dead,x
    beq @vis
    and #$02
    bne @vis
    rts
@vis:
    lda #(PAL_ENEMY | PRIO)
    sta t3
    lda d_col,x             ; 崩壊中は緑に明滅
    beq :+
    lda tick
    and #$04
    beq :+
    lda #(PAL_HEAL | PRIO)
    sta t3
:   lda d_state,x           ; 攻撃の直前は白く点滅 (見切りの合図)
    cmp #ES_WINDUP
    bne :+
    lda d_timer,x
    cmp #12
    bcs :+
    and #$02
    beq :+
    lda #(PAL_FLASH | PRIO)
    sta t3
:   lda d_flash,x
    and #$02
    beq :+
    lda #(PAL_FLASH | PRIO)
    sta t3
:   lda d_type,x
    cmp #TYPE_BOSS
    bne :+
    jmp DrawBoss
:   jsr EnemyFrame
    sta t0
    stz t0+1
    lda d_type,x
    cmp #TYPE_SCARE
    beq @big
    ; 16x16 の小型
    ldy t0
    lda quad_tile,y
    sta spr_tile
    lda d_type,x
    cmp #TYPE_RAT
    bne @snake
    lda spr_tile
    clc
    adc #RAT_TILE
    sta spr_tile
    lda #RAT_NAME
    bra @sattr
@snake:
    lda spr_tile
    clc
    adc #SNAKE_TILE
    sta spr_tile
    lda #SNAKE_NAME
@sattr:
    ora t3
    ora d_flip,x
    sta spr_attr
    stz spr_size
    rep #$20
    lda d_x+1,x
    and #$00FF
    sec
    sbc #8
    sta spr_x
    lda d_y+1,x
    and #$00FF
    sec
    sbc #14
    sta spr_y
    sep #$20
    jsr AddSprite
    jmp DrawSatBar
@big:
    rep #$20
    lda t0
    asl a
    tay
    sep #$20
    lda scare_frame_tbl,y
    sta spr_tile
    lda scare_frame_tbl+1,y
    ora t3
    sta spr_attr
    lda #$02
    sta spr_size
    rep #$20
    lda d_x+1,x
    and #$00FF
    sec
    sbc #16
    sta spr_x
    lda d_y+1,x
    and #$00FF
    sec
    sbc #26
    sta spr_y
    sep #$20
    jsr AddSprite
    ; fallthrough

; X = ボス。32x32 を 2x2 枚並べる。t3 = パレット
DrawBoss:
    .a8
    lda #$02
    sta spr_size
    ldy #$0000
@part:
    lda boss_frame_tbl,y
    sta spr_tile
    lda boss_frame_tbl+1,y
    ora t3
    sta spr_attr
    rep #$20
    lda d_x+1,x
    and #$00FF
    sec
    sbc #32
    sta spr_x
    lda d_y+1,x
    and #$00FF
    sec
    sbc #48
    sta spr_y
    tya
    and #$0002
    beq :+
    lda spr_x
    clc
    adc #32
    sta spr_x
:   tya
    and #$0004
    beq :+
    lda spr_y
    clc
    adc #32
    sta spr_y
:   sep #$20
    jsr AddSprite
    iny
    iny
    cpy #$0008
    bne @part
    jmp DrawSatBar

; X = 敵。飽和が溜まっていれば頭上にゲージ
DrawSatBar:
    .a8
    rep #$20
    lda d_sat,x
    beq @none
    sta t1
    lda d_satmax,x
    lsr a
    lsr a
    sta t2
    ldy #$0000
@lv:
    lda t1
    sec
    sbc t2
    bcc @got
    sta t1
    iny
    cpy #$0003
    bcc @lv
@got:
    sep #$20
    lda quad_tile,y
    clc
    adc #SATBAR_TILE
    sta spr_tile
    lda #(SATBAR_NAME | PAL_FX | PRIO | $10)
    sta spr_attr
    stz spr_size
    rep #$20
    lda d_x+1,x
    and #$00FF
    sec
    sbc #8
    sta spr_x
    lda d_y+1,x
    and #$00FF
    sec
    sbc #40
    sta spr_y
    sep #$20
    jmp AddSprite
@none:
    sep #$20
    rts

; ---- 技 ---------------------------------------------------------------------
PAT_LUNGE   = 0             ; 突進
PAT_SEEDS   = 1             ; 種を撒く (その場で)
PAT_SWEEP   = 2             ; 薙ぎ払い (その場で、広い)
SHOT_DMG    = 12

; X = 敵。攻撃に入った瞬間の処理
PatternStart:
    .a8
    lda d_pat,x
    beq @done
    rep #$20                ; 突進以外はその場で
    stz d_avx,x
    stz d_avy,x
    sep #$20
    cmp #PAT_SEEDS
    bne @sweep
    lda #$01                ; 種は体当たりしない
    sta d_atkdone,x
    lda #SE_DODGE
    jsr PlaySe
    ldy #$0000              ; 案山子は斜め 4 方向、ボスは 8 方向
    lda d_type,x
    cmp #TYPE_BOSS
    beq @ring
    ldy #$0002
@ring:
    phy
    jsr SpawnShot
    ply
    iny
    iny
    lda d_type,x
    cmp #TYPE_BOSS
    beq :+
    iny
    iny
:   cpy #$0010
    bcc @ring
    rts
@sweep:
    lda #8
    sta shake_t
    lda #SE_HEAVY
    jmp PlaySe
@done:
    rts

; X = 撃つ敵, Y = 方向 (0,2,..14)。X, Y は保存
SpawnShot:
    .a8
    phx
    stx bi
    sty bj
    ldy #$0000
@find:
    lda sh_t,y
    beq @use
    iny
    iny
    cpy #NUM_SHOT*2
    bne @find
    plx
    rts
@use:
    lda #90
    sta sh_t,y
    lda bi
    sta sh_src,y
    rep #$20
    lda d_x,x
    sta sh_x,y
    lda d_y,x
    sec
    sbc #$1000              ; 胴の高さから
    sta sh_y,y
    ldx bj
    lda shot_vx,x
    sta sh_vx,y
    lda shot_vy,x
    sta sh_vy,y
    sep #$20
    plx
    ldy bj
    rts

UpdateShots:
    .a8
    ldy #$0000
@loop:
    lda sh_t,y
    bne :+
    jmp @next
:   dec a
    sta sh_t,y
    rep #$20
    lda sh_x,y
    clc
    adc sh_vx,y
    sta sh_x,y
    lda sh_y,y
    clc
    adc sh_vy,y
    sta sh_y,y
    sep #$20
    lda sh_x+1,y            ; 壁や画面外で消える
    sta cx
    lda sh_y+1,y
    clc
    adc #8
    bcs @kill
    sta cy
    cmp #20
    bcc @kill
    lda cx
    cmp #4
    bcc @kill
    cmp #252
    bcs @kill
    jsr SolidAt
    bcs @kill
    ; 主人公に当たったか
    lda sh_x+1,y
    sec
    sbc p_x+1
    bcs :+
    eor #$FF
    inc a
:   cmp #8
    bcs @next
    lda sh_y+1,y
    clc
    adc #8
    sec
    sbc p_y+1
    bcs :+
    eor #$FF
    inc a
:   cmp #10
    bcs @next
    phy
    lda sh_src,y
    rep #$20
    and #$00FF
    tax
    sep #$20
    lda #SHOT_DMG
    jsr HurtPlayer
    ply
    lda p_state             ; 避けている最中は種がすり抜ける
    cmp #ST_DODGE
    beq @next
@kill:
    lda #0
    sta sh_t,y
@next:
    iny
    iny
    cpy #NUM_SHOT*2
    beq :+
    jmp @loop
:   rts

DrawShots:
    .a8
    ldx #$0000
@loop:
    lda sh_t,x
    beq @next
    and #$04
    lsr a
    lsr a
    clc
    adc #2
    tay
    lda quad_tile,y
    clc
    adc #SPARK_TILE
    sta spr_tile
    lda #(SPARK_NAME | PAL_FX | PRIO | $10)
    sta spr_attr
    stz spr_size
    rep #$20
    lda sh_x+1,x
    and #$00FF
    sec
    sbc #8
    sta spr_x
    lda sh_y+1,x
    and #$00FF
    sec
    sbc #8
    sta spr_y
    sep #$20
    jsr AddSprite
@next:
    inx
    inx
    cpx #NUM_SHOT*2
    bne @loop
    rts

SHOT_S = $0160
SHOT_D = $00F8
shot_vx: .word SHOT_S, SHOT_D, 0, $10000-SHOT_D, $10000-SHOT_S, $10000-SHOT_D, 0, SHOT_D
shot_vy: .word 0, SHOT_D, SHOT_S, SHOT_D, 0, $10000-SHOT_D, $10000-SHOT_S, $10000-SHOT_D

; ---- 種別ごとの性能 (添字 = 種別) -------------------------------------------
;                  -      ネズミ  へび    案山子  水車番
e_speed:   .word 0,     $00C0,  $0070,  $0050,  $0030
e_atkspd:  .word 0,     $0300,  $0280,  $0200,  $0180
e_hp:      .word 0,     45,     60,     140,    500
e_defh:    .word 0,     2,      1,      3,      3   ; 守 ÷ 2
e_satmax:  .word 0,     40,     50,     60,     90
e_range:   .byte 0,     40,     28,     38,     52
e_windup:  .byte 0,     24,     30,     40,     50
e_atkfr:   .byte 0,     14,     10,     16,     22
e_recover: .byte 0,     30,     40,     50,     70
e_atk:     .byte 0,     12,     15,     20,     28
e_regen:   .byte 0,     0,      1,      2,      3   ; 32F ごとの再生量
e_hitw:    .byte 0,     12,     12,     18,     34
e_npat:    .byte 1,     1,      1,      2,     3       ; 技の数
e_hith:    .byte 0,     10,     10,     14,     30

