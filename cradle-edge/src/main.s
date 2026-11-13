; ============================================================================
;  ゆりかごの双刃 / CRADLE EDGE  —  M1 技術試作
;  1部屋でグレンが歩き、連斬(4段)で木人が吹き飛ぶ。
;
;  規約: 通常は A=8bit / X,Y=16bit。16bit A を使う区間は rep/sep で囲む。
;        座標は 8.8 固定小数 (上位バイト=ピクセル)。M1 は1画面なのでこれで足りる。
; ============================================================================
.p816
.smart +

; ---- 定数 -------------------------------------------------------------------
MINX        = $1800         ; 移動可能範囲 (8.8)
MAXX        = $E800
MINY        = $2800
MAXY        = $CC00

NUM_DUMMY   = 3             ; 配列は2バイト刻み (X=0,2,4)
DUMMY_END   = NUM_DUMMY*2
DUMMY_HP    = 100
DUMMY_DEF   = 4
DEAD_TIME   = 120           ; 壊れてから復活まで
DEAD_VISIBLE= 60            ; これより大きい間は点滅しながら飛ぶ

NUM_FX      = 4

ST_FREE     = 0
ST_ATTACK   = 1
ST_DODGE    = 2

PAL_HERO    = 0 << 1
PAL_SWORD_A = 2 << 1
PAL_SWORD_B = 3 << 1
PAL_DUMMY   = 4 << 1
PAL_FLASH   = 5 << 1
PAL_FX      = 7 << 1
PRIO        = $20           ; OBJ 優先度2

; VRAM 配置 (ワードアドレス)
VRAM_BG1_MAP = $0000
VRAM_BG3_MAP = $0400
VRAM_BG1_CHR = $1000
VRAM_BG3_CHR = $3000
VRAM_OBJ_CHR = $4000
HUD_COMBO    = VRAM_BG3_MAP + 32*1 + 8
HUD_DMG      = VRAM_BG3_MAP + 32*1 + 17

; ---- 変数 -------------------------------------------------------------------
.zeropage
vbl_count:   .res 1
nmi_ready:   .res 1
pad:         .res 2
pad_prev:    .res 2
pad_new:     .res 2
rng:         .res 2
hitstop:     .res 1
shake_t:     .res 1
shake_x:     .res 2
t0:          .res 2
t1:          .res 2
t2:          .res 2
t3:          .res 2
vx:          .res 2
vy:          .res 2
old_pos:     .res 2
was_blocked: .res 1
oam_idx:     .res 2
spr_x:       .res 2
spr_y:       .res 2
spr_tile:    .res 1
spr_attr:    .res 1
spr_size:    .res 1
spr_tx:      .res 2
bi:          .res 2
bj:          .res 2

p_x:         .res 2
p_y:         .res 2
p_face:      .res 1          ; 0下 1上 2左 3右
p_state:     .res 1
p_timer:     .res 1
p_stage:     .res 1          ; 連斬の段 (0-3)
p_buf:       .res 1          ; 先行入力
p_anim:      .res 1
swing_id:    .res 1
swA_ang:     .res 1
swB_ang:     .res 1
swA_prev:    .res 1
swB_prev:    .res 1
swA_rad:     .res 1
swB_rad:     .res 1
dodge_vx:    .res 2
dodge_vy:    .res 2

combo:       .res 1
combo_t:     .res 1
last_dmg:    .res 2
hud_digits:  .res 5

.bss
oam_buf:     .res 512
oam_hi:      .res 32
oam_hi_tmp:  .res 128
d_x:         .res DUMMY_END
d_y:         .res DUMMY_END
d_vx:        .res DUMMY_END
d_vy:        .res DUMMY_END
d_hp:        .res DUMMY_END
d_flash:     .res DUMMY_END  ; 以下はバイトだが同じ添字で引く
d_hitid:     .res DUMMY_END
d_dead:      .res DUMMY_END
d_bump:      .res DUMMY_END
fx_t:        .res NUM_FX
fx_x:        .res NUM_FX
fx_y:        .res NUM_FX

; ---- マクロ -----------------------------------------------------------------
.macro VRAM_DMA src, len, dest
    ldx #dest
    stx $2116
    lda #$01
    sta $4300
    lda #$18
    sta $4301
    ldx #.loword(src)
    stx $4302
    lda #^src
    sta $4304
    ldx #len
    stx $4305
    lda #$01
    sta $420B
.endmacro

; 符号付き 16bit を 1bit 算術右シフト (A16)
.macro ASR16
    cmp #$8000
    ror a
.endmacro

; ============================================================================
.segment "CODE"

Reset:
    sei
    clc
    xce
    jml f:ResetFast
ResetFast:
    rep #$38                ; A/X/Y 16bit, 10進オフ
    ldx #$1FFF
    txs
    lda #$0000
    tcd
    sep #$20
    phk
    plb
    lda #$01
    sta $420D               ; FastROM
    lda #$8F
    sta $2100               ; 画面オフ
    stz $4200

    ; PPU レジスタ初期化
    ldx #$2101
@ppu:
    stz $00,x
    inx
    cpx #$2134
    bne @ppu
    ldx #$210D              ; スクロールは2回書き
@scr:
    stz $00,x
    stz $00,x
    inx
    cpx #$2115
    bne @scr

    ; WRAM $0000-$1FFF をクリア (スタック使用前)
    ldx #$0000
@wram:
    stz $00,x
    inx
    cpx #$1F00
    bne @wram

    ; VRAM 全クリア
    lda #$80
    sta $2115
    ldx #$0000
    stx $2116
    lda #$09                ; 固定ソース、2レジスタ
    sta $4300
    lda #$18
    sta $4301
    ldx #.loword(ZeroByte)
    stx $4302
    lda #^ZeroByte
    sta $4304
    ldx #$0000              ; 65536 バイト
    stx $4305
    lda #$01
    sta $420B

    ; 画像転送
    VRAM_DMA BgChr,   BG_CHR_SIZE,   VRAM_BG1_CHR
    VRAM_DMA BgMap,   $0800,         VRAM_BG1_MAP
    VRAM_DMA FontChr, FONT_CHR_SIZE, VRAM_BG3_CHR
    VRAM_DMA HudMap,  $0800,         VRAM_BG3_MAP
    VRAM_DMA ObjChr,  OBJ_CHR_SIZE,  VRAM_OBJ_CHR

    ; パレット
    stz $2121
    stz $4300
    lda #$22
    sta $4301
    ldx #.loword(Palette)
    stx $4302
    lda #^Palette
    sta $4304
    ldx #$0200
    stx $4305
    lda #$01
    sta $420B

    ; 画面設定
    lda #$09                ; Mode 1, BG3 優先
    sta $2105
    lda #(VRAM_BG1_MAP >> 8)
    sta $2107
    lda #(VRAM_BG3_MAP >> 8)
    sta $2109
    lda #(VRAM_BG1_CHR >> 12)
    sta $210B
    lda #(VRAM_BG3_CHR >> 12)
    sta $210C
    lda #$62                ; OBJ 16x16/32x32, chr=$4000
    sta $2101
    lda #$15                ; BG1 + BG3 + OBJ
    sta $212C

    jsr InitGame
    jsr DrawAll
    jsr BuildHud
    lda #$01
    sta nmi_ready

    lda #$81                ; NMI + 自動パッド読み
    sta $4200
    lda #$0F
    sta $2100

; ---- メインループ -----------------------------------------------------------
MainLoop:
    lda vbl_count
@wait:
    wai
    cmp vbl_count
    beq @wait

    jsr ReadPad
    lda hitstop
    beq @update
    dec hitstop
    ; ヒットストップ中も先行入力だけは拾う
    lda p_state
    cmp #ST_ATTACK
    bne @draw
    lda pad_new+1
    and #$40
    beq @draw
    lda #$01
    sta p_buf
    bra @draw
@update:
    jsr UpdatePlayer
    jsr UpdateDummies
    jsr BumpDummies
    jsr UpdateFx
    jsr UpdateTimers
@draw:
    jsr UpdateShake
    jsr DrawAll
    jsr BuildHud
    lda #$01
    sta nmi_ready
    bra MainLoop

; ---- NMI --------------------------------------------------------------------
Nmi:
    jml f:NmiFast
NmiFast:
    rep #$30
    pha
    phx
    phy
    phb
    phd
    lda #$0000
    tcd
    sep #$20
    phk
    plb
    lda $4210
    lda nmi_ready
    beq @skip
    stz nmi_ready

    ; OAM
    stz $2102
    stz $2103
    stz $4300
    lda #$04
    sta $4301
    ldx #oam_buf
    stx $4302
    stz $4304
    ldx #544
    stx $4305
    lda #$01
    sta $420B

    ; 画面揺れ (BG は逆向きにスクロール)
    rep #$20
    lda #$0000
    sec
    sbc shake_x
    sep #$20
    sta $210D
    xba
    sta $210D

    ; HUD の数字
    lda #$80
    sta $2115
    ldx #HUD_COMBO
    stx $2116
    lda hud_digits+0
    sta $2118
    lda #$20
    sta $2119
    lda hud_digits+1
    sta $2118
    lda #$20
    sta $2119
    ldx #HUD_DMG
    stx $2116
    lda hud_digits+2
    sta $2118
    lda #$20
    sta $2119
    lda hud_digits+3
    sta $2118
    lda #$20
    sta $2119
    lda hud_digits+4
    sta $2118
    lda #$20
    sta $2119
@skip:
    inc vbl_count
    rep #$30
    pld
    plb
    ply
    plx
    pla
    rti

IrqStub:
    rti

; ---- 初期化 -----------------------------------------------------------------
InitGame:
    rep #$20
    lda #$8000
    sta p_x
    lda #$A800
    sta p_y
    lda #$ACE1
    sta rng
    sep #$20
    lda #$01
    sta p_face
    ldx #$0000
@d:
    jsr RespawnDummy
    stz d_flash,x
    inx
    inx
    cpx #DUMMY_END
    bne @d
    jsr SetRestSwords
    lda swA_ang
    sta swA_prev
    lda swB_ang
    sta swB_prev
    rts

; X = 木人の添字
RespawnDummy:
    rep #$20
    lda dummy_home_x,x
    sta d_x,x
    lda dummy_home_y,x
    sta d_y,x
    stz d_vx,x
    stz d_vy,x
    lda #DUMMY_HP
    sta d_hp,x
    sep #$20
    stz d_dead,x
    stz d_bump,x
    lda #$FF
    sta d_hitid,x
    lda #12
    sta d_flash,x
    rts

; ---- 入力 -------------------------------------------------------------------
ReadPad:
@w:
    lda $4212
    and #$01
    bne @w
    rep #$20
    lda pad
    sta pad_prev
    lda $4218
    sta pad
    eor pad_prev
    and pad
    sta pad_new
    sep #$20
    rts

; 乱数 (16bit xorshift)。A8 で下位バイトを返す
Rand:
    rep #$20
    lda rng
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    eor rng
    sta rng
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    lsr a
    eor rng
    sta rng
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    eor rng
    sta rng
    sep #$20
    rts

; ============================================================================
;  プレイヤー
; ============================================================================
UpdatePlayer:
    lda swA_ang
    sta swA_prev
    lda swB_ang
    sta swB_prev
    lda p_state
    beq @free
    cmp #ST_ATTACK
    bne :+
    jmp PlayerAttack
:   jmp PlayerDodge
@free:
    lda pad_new+1
    and #$40                ; Y
    beq :+
    jmp StartAttack
:   lda pad_new+1
    bpl :+                  ; B
    jmp StartDodge
:   lda pad+1
    and #$0F
    beq @idle
    jsr SetFacingFromPad
    jsr LoadPadVelocity
    jsr MovePlayer
    inc p_anim
    bra @rest
@idle:
    stz p_anim
@rest:
    jmp SetRestSwords

; 十字キーの状態から vx, vy を引く
LoadPadVelocity:
    rep #$20
    lda pad
    xba
    and #$000F
    asl a
    tax
    lda mv_vx,x
    sta vx
    lda mv_vy,x
    sta vy
    sep #$20
    rts

; 十字キーから向きを決める。斜めは今の向きが成分に含まれていれば維持
SetFacingFromPad:
    rep #$20
    lda pad
    xba
    and #$000F
    tax
    sep #$20
    lda face_h,x
    bmi @no_h
    sta t0
    lda face_v,x
    bmi @use_h
    cmp p_face
    beq @done
@use_h:
    lda t0
    sta p_face
    rts
@no_h:
    lda face_v,x
    bmi @done
    sta p_face
@done:
    rts

; vx, vy だけ動かす。壁でクランプ、木人には軸ごとに止められる
MovePlayer:
    jsr PlayerBlocked
    lda #$00
    rol a
    sta was_blocked         ; すでに重なっているなら抜け出せるよう判定しない
    rep #$20
    lda p_x
    sta old_pos
    clc
    adc vx
    cmp #MINX
    bcs :+
    lda #MINX
:   cmp #MAXX
    bcc :+
    lda #MAXX
:   sta p_x
    sep #$20
    lda was_blocked
    bne @y
    jsr PlayerBlocked
    bcc @y
    rep #$20
    lda old_pos
    sta p_x
    sep #$20
@y:
    rep #$20
    lda p_y
    sta old_pos
    clc
    adc vy
    cmp #MINY
    bcs :+
    lda #MINY
:   cmp #MAXY
    bcc :+
    lda #MAXY
:   sta p_y
    sep #$20
    lda was_blocked
    bne @done
    jsr PlayerBlocked
    bcc @done
    rep #$20
    lda old_pos
    sta p_y
    sep #$20
@done:
    rts

; 木人と重なっていればキャリーを立てる
PlayerBlocked:
    ldx #$0000
@loop:
    lda d_dead,x
    bne @next
    lda d_x+1,x
    sec
    sbc p_x+1
    bcs :+
    eor #$FF
    inc a
:   cmp #14
    bcs @next
    lda d_y+1,x
    sec
    sbc p_y+1
    bcs :+
    eor #$FF
    inc a
:   cmp #10
    bcs @next
    sec
    rts
@next:
    inx
    inx
    cpx #DUMMY_END
    bne @loop
    clc
    rts

; 待機時の剣: 左右やや後ろに開いて構える
SetRestSwords:
    ldx #$0000
    rep #$20
    lda p_face
    and #$00FF
    tax
    sep #$20
    lda face_ang,x
    clc
    adc #5
    and #$0F
    sta swA_ang
    lda face_ang,x
    sec
    sbc #5
    and #$0F
    sta swB_ang
    stz swA_rad
    stz swB_rad
    rts

; ---- 連斬 -------------------------------------------------------------------
StartAttack:
    lda pad+1
    and #$0F
    beq :+
    jsr SetFacingFromPad
:   lda #ST_ATTACK
    sta p_state
    stz p_stage
    stz p_timer
    stz p_buf
    inc swing_id
    stz p_anim
    ; このフレームから構えを見せる

PlayerAttack:
    lda pad_new+1
    and #$40
    beq :+
    lda p_timer
    cmp #3                  ; 出がかりの連打は無視
    bcc :+
    lda #$01
    sta p_buf
:   jsr StageToX
    lda p_timer
    cmp atk_startup,x
    bcs @no_lunge
    ; 踏み込み
    rep #$20
    lda p_face
    and #$00FF
    asl a
    tax
    lda lunge_vx,x
    sta vx
    lda lunge_vy,x
    sta vy
    sep #$20
    jsr MovePlayer
@no_lunge:
    jsr CalcSwingSwords
    jsr StageToX
    lda p_timer
    cmp atk_startup,x
    bcc @no_hit
    cmp atk_actend,x
    bcs @no_hit
    jsr AttackHit
@no_hit:
    inc p_timer
    jsr StageToX
    lda p_timer
    cmp atk_total,x
    bcc @done
    lda p_buf
    beq @end
    lda p_stage
    cmp #3
    bcs @end
    inc p_stage
    stz p_timer
    stz p_buf
    inc swing_id
    lda pad+1               ; 段の合間に向き直せる
    and #$0F
    beq @done
    jsr SetFacingFromPad
@done:
    rts
@end:
    stz p_state
    rts

StageToX:
    rep #$20
    lda p_stage
    and #$00FF
    tax
    sep #$20
    rts

; 現在の段・経過フレームから2本の剣の角度を決める
CalcSwingSwords:
    jsr StageToX
    ; t0 = clamp(timer - startup, 0, 6)
    lda p_timer
    sec
    sbc atk_startup,x
    bcs :+
    lda #$00
:   cmp #6
    bcc :+
    lda #6
:   sta t0
    ; t1 = 正面の方位
    phx
    rep #$20
    lda p_face
    and #$00FF
    tax
    sep #$20
    lda face_ang,x
    sta t1
    plx
    stz swA_rad
    stz swB_rad
    ; 暁
    lda sA_step,x
    jsr StepTimesT
    clc
    adc sA_start,x
    clc
    adc t1
    and #$0F
    sta swA_ang
    ; 宵
    lda sB_step,x
    jsr StepTimesT
    clc
    adc sB_start,x
    clc
    adc t1
    and #$0F
    sta swB_ang
    ; 3段目 (叩きつけ): 振りかぶり → 前方へ伸ばす
    cpx #$0002
    bne @done
    lda p_timer
    cmp atk_startup,x
    bcs @slam
    lda t1
    clc
    adc #8
    and #$0F
    sta swA_ang
    rts
@slam:
    lda t1
    sta swA_ang
    lda #$01
    sta swA_rad
@done:
    rts

; A = 刻み (0 / 1 / $FF) → A = 刻み × t0
StepTimesT:
    beq @zero
    bmi @neg
    lda t0
    rts
@neg:
    lda #$00
    sec
    sbc t0
    rts
@zero:
    rts

; 攻撃判定: 向きごとの矩形と木人の中心点
AttackHit:
    ldx #$0000
@loop:
    lda d_dead,x
    bne @next
    lda d_hitid,x
    cmp swing_id
    beq @next
    rep #$20
    lda p_face
    and #$00FF
    asl a
    tay
    lda d_x+1,x
    and #$00FF
    sta t1
    lda p_x+1
    and #$00FF
    sta t2
    lda t1
    sec
    sbc t2
    sta t1                  ; 相対X
    sec
    sbc hit_xmin,y
    bmi @next16
    lda hit_xmax,y
    sec
    sbc t1
    bmi @next16
    lda d_y+1,x
    and #$00FF
    sta t1
    lda p_y+1
    and #$00FF
    sta t2
    lda t1
    sec
    sbc t2
    sta t1                  ; 相対Y
    sec
    sbc hit_ymin,y
    bmi @next16
    lda hit_ymax,y
    sec
    sbc t1
    bmi @next16
    sep #$20
    jsr ApplyHit
    bra @next
@next16:
    sep #$20
@next:
    inx
    inx
    cpx #DUMMY_END
    bne @loop
    rts

; X = 当たった木人
ApplyHit:
    lda swing_id
    sta d_hitid,x
    phx
    jsr StageToX
    txy                     ; Y = 段
    plx
    ; ダメージ = 攻撃力 × 倍率 ÷ 16 − 守÷2 + 乱数(0-3)
    lda atk_power,y
    sta $4202
    lda atk_mult,y
    sta $4203
    jsr Rand
    and #$03
    sta t0
    stz t0+1
    rep #$20
    lda $4216
    lsr a
    lsr a
    lsr a
    lsr a
    sec
    sbc #DUMMY_DEF/2
    clc
    adc t0
    sta last_dmg
    lda d_hp,x
    sec
    sbc last_dmg
    beq @dead
    bpl @alive
@dead:
    lda #$0000
    sta d_hp,x
    sep #$20
    lda #DEAD_TIME
    sta d_dead,x
    rep #$20
    bra @knock
@alive:
    sta d_hp,x
@knock:
    ; 吹き飛ばし: 向きベクトル × 段ごとの力
    phy
    tya
    asl a
    tay
    lda kb_power,y
    sta t0
    ply
    stz d_vx,x
    stz d_vy,x
    sep #$20
    lda p_face
    beq @down
    cmp #1
    beq @up
    cmp #2
    beq @left
    rep #$20
    lda t0
    sta d_vx,x
    bra @kdone
@left:
    rep #$20
    lda #$0000
    sec
    sbc t0
    sta d_vx,x
    bra @kdone
@up:
    rep #$20
    lda #$0000
    sec
    sbc t0
    sta d_vy,x
    bra @kdone
@down:
    rep #$20
    lda t0
    sta d_vy,x
@kdone:
    sep #$20
    lda #12
    sta d_flash,x
    lda atk_hitstop,y
    sta hitstop
    cpy #$0003
    bne :+
    lda #10
    sta shake_t
:   jsr SpawnSparkAtDummy
    lda combo
    cmp #99
    bcs :+
    inc combo
:   lda #120
    sta combo_t
    rts

; ---- 回避ステップ -----------------------------------------------------------
StartDodge:
    lda pad+1
    and #$0F
    beq @back
    jsr SetFacingFromPad
    jsr LoadPadVelocity
    rep #$20
    lda vx                  ; 歩きの 4/3 倍 ≒ 2px/F
    ASR16
    ASR16
    clc
    adc vx
    sta dodge_vx
    lda vy
    ASR16
    ASR16
    clc
    adc vy
    sta dodge_vy
    sep #$20
    bra @go
@back:
    rep #$20
    lda p_face
    and #$00FF
    asl a
    tax
    lda back_vx,x
    sta dodge_vx
    lda back_vy,x
    sta dodge_vy
    sep #$20
@go:
    lda #ST_DODGE
    sta p_state
    stz p_timer

PlayerDodge:
    rep #$20
    lda dodge_vx
    sta vx
    lda dodge_vy
    sta vy
    sep #$20
    lda p_timer
    cmp #14                 ; 終わり際は減速
    bcc :+
    rep #$20
    lda vx
    ASR16
    sta vx
    lda vy
    ASR16
    sta vy
    sep #$20
:   jsr MovePlayer
    jsr SetRestSwords
    inc p_anim
    inc p_timer
    lda p_timer
    cmp #20
    bcc :+
    stz p_state
:   rts

; ============================================================================
;  木人
; ============================================================================
UpdateDummies:
    ldx #$0000
@loop:
    lda d_flash,x
    beq :+
    dec d_flash,x
:   lda d_bump,x
    beq :+
    dec d_bump,x
:   lda d_dead,x
    beq @move
    dec d_dead,x
    bne @move
    jsr RespawnDummy
    jmp @next
@move:
    rep #$20
    ; X
    lda d_x,x
    clc
    adc d_vx,x
    cmp #MINX
    bcs :+
    lda #MINX
    bra @bx
:   cmp #MAXX
    bcc @sx
    lda #MAXX
@bx:
    pha
    lda #$0000
    sec
    sbc d_vx,x
    ASR16
    sta d_vx,x
    pla
@sx:
    sta d_x,x
    ; Y
    lda d_y,x
    clc
    adc d_vy,x
    cmp #MINY
    bcs :+
    lda #MINY
    bra @by
:   cmp #MAXY
    bcc @sy
    lda #MAXY
@by:
    pha
    lda #$0000
    sec
    sbc d_vy,x
    ASR16
    sta d_vy,x
    pla
@sy:
    sta d_y,x
    ; 摩擦 v -= v/8、十分小さければ止める
    lda d_vx,x
    ASR16
    ASR16
    ASR16
    sta t0
    lda d_vx,x
    sec
    sbc t0
    sta d_vx,x
    clc
    adc #$0020
    cmp #$0040
    bcs :+
    stz d_vx,x
:   lda d_vy,x
    ASR16
    ASR16
    ASR16
    sta t0
    lda d_vy,x
    sec
    sbc t0
    sta d_vy,x
    clc
    adc #$0020
    cmp #$0040
    bcs :+
    stz d_vy,x
:   sep #$20
@next:
    inx
    inx
    cpx #DUMMY_END
    beq :+
    jmp @loop
:   rts

; 木人どうしの玉突き
BumpDummies:
    ldx #$0000
    ldy #$0002
    jsr BumpPair
    ldx #$0000
    ldy #$0004
    jsr BumpPair
    ldx #$0002
    ldy #$0004
    ; fallthrough

; X, Y = 木人の添字
BumpPair:
    stx bi
    sty bj
    lda d_bump,x
    bne @out
    lda d_bump,y
    bne @out
    ; 消えている木人は対象外
    lda d_dead,x
    beq :+
    cmp #DEAD_VISIBLE+1
    bcc @out
:   lda d_dead,y
    beq :+
    cmp #DEAD_VISIBLE+1
    bcc @out
:   lda d_x+1,x
    sec
    sbc d_x+1,y
    bcs :+
    eor #$FF
    inc a
:   cmp #18
    bcs @out
    lda d_y+1,x
    sec
    sbc d_y+1,y
    bcs :+
    eor #$FF
    inc a
:   cmp #14
    bcc @hit
@out:
    rts
@hit:
    ; 速い方を「ぶつかった側」にする
    jsr DummySpeed          ; X の速さ → A16
    rep #$20
    sta t1
    sep #$20
    ldx bj
    jsr DummySpeed
    rep #$20
    sta t2
    cmp t1
    bcc @i_faster           ; t2 < t1
    ; j の方が速い: 入れ替え
    lda t2
    sta t1
    ldx bi
    ldy bj
    stx bj
    sty bi
@i_faster:
    lda t1
    cmp #$0180
    bcs :+
    sep #$20
    rts
:   .a16                    ; bi = ぶつかった側, bj = ぶつけられた側
    ldx bi
    ldy bj
    lda d_vx,x
    ASR16
    ASR16
    sta t0                  ; v/4
    lda d_vx,x
    sec
    sbc t0
    sta d_vx,y              ; 相手は 3/4 を受け取る
    lda t0
    sta d_vx,x
    lda d_vy,x
    ASR16
    ASR16
    sta t0
    lda d_vy,x
    sec
    sbc t0
    sta d_vy,y
    lda t0
    sta d_vy,x
    sep #$20
    lda #10
    sta d_bump,x
    sta d_bump,y
    lda #8
    sta d_flash,y
    lda hitstop
    bne :+
    lda #2
    sta hitstop
:   ; 巻き添えダメージ
    lda d_dead,y
    bne @spark
    rep #$20
    lda d_hp,y
    sec
    sbc #8
    beq @kill
    bpl @store
@kill:
    lda #$0000
    sta d_hp,y
    sep #$20
    lda #DEAD_TIME
    sta d_dead,y
    bra @spark
@store:
    sta d_hp,y
    sep #$20
@spark:
    ldx bj
    jmp SpawnSparkAtDummy

; X = 木人 → A16 = |vx| + |vy|  (A16 のまま返す…呼び出し側で注意)
DummySpeed:
    rep #$20
    lda d_vx,x
    bpl :+
    eor #$FFFF
    inc a
:   sta t0
    lda d_vy,x
    bpl :+
    eor #$FFFF
    inc a
:   clc
    adc t0
    sep #$20                ; 上位バイトは B に残る
    rts

; ============================================================================
;  エフェクト・タイマー
; ============================================================================
; X = 木人。空きスロットに火花を出す
SpawnSparkAtDummy:
    phy
    ldy #$0000
@find:
    lda fx_t,y
    beq @use
    iny
    cpy #NUM_FX
    bne @find
    ldy #$0000              ; 空きが無ければ先頭を上書き
@use:
    lda #8
    sta fx_t,y
    lda d_x+1,x
    sta fx_x,y
    lda d_y+1,x
    sta fx_y,y
    ply
    rts

UpdateFx:
    ldx #$0000
@loop:
    lda fx_t,x
    beq :+
    dec fx_t,x
:   inx
    cpx #NUM_FX
    bne @loop
    rts

UpdateTimers:
    lda combo_t
    beq @done
    dec combo_t
    bne @done
    stz combo
@done:
    rts

UpdateShake:
    rep #$20
    stz shake_x
    sep #$20
    lda shake_t
    beq @done
    dec shake_t
    rep #$20
    lda shake_t
    and #$0002
    beq @neg
    lda #$0002
    bra @set
@neg:
    lda #$FFFE
@set:
    sta shake_x
    sep #$20
@done:
    rts

; ============================================================================
;  描画
; ============================================================================
DrawAll:
    ldy #$0000
    sty oam_idx
    jsr DrawFx
    ; 手前の木人 → 剣 → 主人公 → 奥の木人 → 影
    ldx #$0000
@front:
    rep #$20
    lda d_y,x
    cmp p_y
    sep #$20
    bcc :+
    jsr DrawDummy
:   inx
    inx
    cpx #DUMMY_END
    bne @front
    jsr DrawSwords
    jsr DrawPlayer
    ldx #$0000
@back:
    rep #$20
    lda d_y,x
    cmp p_y
    sep #$20
    bcs :+
    jsr DrawDummy
:   inx
    inx
    cpx #DUMMY_END
    bne @back
    jsr DrawShadows

    ; 残りを画面外へ
    ldy oam_idx
@hide:
    cpy #512
    bcs @pack
    lda #$E0
    sta oam_buf+1,y
    rep #$20
    tya
    lsr a
    lsr a
    tax
    sep #$20
    stz oam_hi_tmp,x
    iny
    iny
    iny
    iny
    bra @hide
@pack:
    ; 上位テーブル (スプライト4枚で1バイト) に詰める
    ldx #$0000
    ldy #$0000
@p:
    lda oam_hi_tmp+3,x
    asl a
    asl a
    ora oam_hi_tmp+2,x
    asl a
    asl a
    ora oam_hi_tmp+1,x
    asl a
    asl a
    ora oam_hi_tmp,x
    sta oam_hi,y
    inx
    inx
    inx
    inx
    iny
    cpy #32
    bne @p
    rts

; spr_x, spr_y (16bit 画面座標・左上), spr_tile, spr_attr, spr_size(0/2)
; X, Y レジスタは保存する
AddSprite:
    phx
    phy
    ldy oam_idx
    cpy #512
    bcs @cull8
    rep #$20
    lda spr_x
    clc
    adc shake_x
    cmp #$0100
    bcc @xok
    cmp #$FFE1
    bcc @cull
@xok:
    sta spr_tx
    lda spr_y
    cmp #224
    bcc @yok
    cmp #$FFE1
    bcc @cull
@yok:
    tya
    lsr a
    lsr a
    tax
    sep #$20
    lda spr_tx
    sta oam_buf,y
    lda spr_y
    sta oam_buf+1,y
    lda spr_tile
    sta oam_buf+2,y
    lda spr_attr
    sta oam_buf+3,y
    lda spr_tx+1
    and #$01
    ora spr_size
    sta oam_hi_tmp,x
    iny
    iny
    iny
    iny
    sty oam_idx
    bra @cull8
@cull:
    sep #$20
@cull8:
    ply
    plx
    rts

; 主人公の画面位置 (足元基準) を spr_x/y に。A16 で dx, dy を足す用
.macro SPR_AT posx, posy, dx, dy
    rep #$20
    lda posx+1
    and #$00FF
    clc
    adc #.loword(dx)
    sta spr_x
    lda posy+1
    and #$00FF
    clc
    adc #.loword(dy)
    sta spr_y
    sep #$20
.endmacro

DrawPlayer:
    ; コマ選択
    lda p_state
    cmp #ST_ATTACK
    bne :+
    lda #3
    bra @frame
:   cmp #ST_DODGE
    bne :+
    lda #1
    bra @frame
:   lda p_anim
    beq @frame              ; 0 = 立ち
    lsr a
    lsr a
    lsr a
    and #$03
    tax
    lda walk_cycle,x
@frame:
    asl a
    sta t0
    lda p_face
    asl a
    asl a
    asl a
    clc
    adc t0
    rep #$20
    and #$00FF
    tax
    sep #$20
    lda hero_frame_tbl,x
    sta spr_tile
    lda hero_frame_tbl+1,x
    ora #(PAL_HERO | PRIO)
    sta spr_attr
    lda #$02
    sta spr_size
    SPR_AT p_x, p_y, -16, -26
    jmp AddSprite

; 剣2本 (＋振っている最中は残像)
DrawSwords:
    lda swA_ang
    ldx #PAL_SWORD_A | PRIO
    ldy swA_rad
    jsr DrawSword
    lda swB_ang
    ldx #PAL_SWORD_B | PRIO
    ldy swB_rad
    jsr DrawSword
    lda p_state
    cmp #ST_ATTACK
    bne @done
    lda swA_prev
    cmp swA_ang
    beq :+
    ldx #PAL_FLASH | PRIO
    ldy swA_rad
    jsr DrawSword
:   lda swB_prev
    cmp swB_ang
    beq @done
    ldx #PAL_FLASH | PRIO
    ldy swB_rad
    jsr DrawSword
@done:
    rts

; A = 方位(0-15), X(下位) = パレット|優先度, Y(下位) = 半径の種類(0/1)
DrawSword:
    sta t0
    stz t0+1
    stx t1
    sty t2
    rep #$20
    lda t0
    asl a
    tax
    sep #$20
    lda sword_tbl,x
    sta spr_tile
    lda sword_tbl+1,x
    ora t1
    sta spr_attr
    lda #$02
    sta spr_size
    lda t2
    bne @far
    rep #$20
    lda p_x+1
    and #$00FF
    clc
    adc sw_off0_x,x
    sec
    sbc #16
    sta spr_x
    lda p_y+1
    and #$00FF
    clc
    adc sw_off0_y,x
    sec
    sbc #26
    sta spr_y
    sep #$20
    jmp AddSprite
@far:
    rep #$20
    lda p_x+1
    and #$00FF
    clc
    adc sw_off1_x,x
    sec
    sbc #16
    sta spr_x
    lda p_y+1
    and #$00FF
    clc
    adc sw_off1_y,x
    sec
    sbc #26
    sta spr_y
    sep #$20
    jmp AddSprite

; X = 木人
DrawDummy:
    lda d_dead,x
    beq @vis
    cmp #DEAD_VISIBLE+1
    bcc @skip
    and #$02                ; 壊れて飛んでいる間は点滅
    beq @skip
@vis:
    lda #$02
    sta spr_size
    lda d_flash,x
    beq @normal
    lda #DUMMY_HIT_TILE
    sta spr_tile
    lda d_flash,x
    and #$02
    beq :+
    lda #(DUMMY_HIT_NAME | PAL_FLASH | PRIO)
    bra @attr
:   lda #(DUMMY_HIT_NAME | PAL_DUMMY | PRIO)
    bra @attr
@normal:
    lda #DUMMY_TILE
    sta spr_tile
    lda #(DUMMY_NAME | PAL_DUMMY | PRIO)
@attr:
    sta spr_attr
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
    jmp AddSprite
@skip:
    rts

DrawShadows:
    lda #SHADOW_TILE
    sta spr_tile
    lda #(SHADOW_NAME | PAL_FX | PRIO)
    sta spr_attr
    lda #$02
    sta spr_size
    SPR_AT p_x, p_y, -16, -12
    jsr AddSprite
    ldx #$0000
@loop:
    lda d_dead,x
    bne @next
    rep #$20
    lda d_x+1,x
    and #$00FF
    sec
    sbc #16
    sta spr_x
    lda d_y+1,x
    and #$00FF
    sec
    sbc #12
    sta spr_y
    sep #$20
    jsr AddSprite
@next:
    inx
    inx
    cpx #DUMMY_END
    bne @loop
    rts

DrawFx:
    ldx #$0000
@loop:
    lda fx_t,x
    beq @next
    cmp #5
    lda #SPARK_TILE
    bcs :+
    lda #SPARK_TILE+2
:   sta spr_tile
    lda #(SPARK_NAME | PAL_FX | PRIO | $10)   ; 優先度3で最前面
    sta spr_attr
    stz spr_size
    rep #$20
    lda fx_x,x
    and #$00FF
    sec
    sbc #8
    sta spr_x
    lda fx_y,x
    and #$00FF
    sec
    sbc #20
    sta spr_y
    sep #$20
    jsr AddSprite
@next:
    inx
    cpx #NUM_FX
    bne @loop
    rts

; ---- HUD --------------------------------------------------------------------
; combo (2桁) と last_dmg (3桁) をタイル番号に (タイル1 = '0')
BuildHud:
    lda combo
    sta $4204
    stz $4205
    lda #10
    sta $4206
    jsr DivWait
    lda $4214
    inc a
    sta hud_digits+0
    lda $4216
    inc a
    sta hud_digits+1
    rep #$20
    lda last_dmg
    cmp #1000
    bcc :+
    lda #999
:   sta $4204
    sep #$20
    lda #100
    sta $4206
    jsr DivWait
    lda $4214
    inc a
    sta hud_digits+2
    lda $4216
    sta $4204
    stz $4205
    lda #10
    sta $4206
    jsr DivWait
    lda $4214
    inc a
    sta hud_digits+3
    lda $4216
    inc a
    sta hud_digits+4
    rts

DivWait:                    ; 除算器の結果待ち (16サイクル以上)
    nop
    nop
    nop
    nop
    rts

; ============================================================================
;  データ
; ============================================================================
.segment "RODATA"
ZeroByte: .byte 0

; 十字キー下位4bit (上=8 下=4 左=2 右=1) → 速度
SPD  = $0180
DIAG = $010F
mv_vx:
    .word 0, SPD, $10000-SPD, 0
    .word 0, DIAG, $10000-DIAG, 0
    .word 0, DIAG, $10000-DIAG, 0
    .word 0, SPD, $10000-SPD, 0
mv_vy:
    .word 0, 0, 0, 0
    .word SPD, DIAG, DIAG, SPD
    .word $10000-SPD, $10000-DIAG, $10000-DIAG, $10000-SPD
    .word 0, 0, 0, 0
face_h:
    .byte $FF, 3, 2, $FF, $FF, 3, 2, $FF, $FF, 3, 2, $FF, $FF, 3, 2, $FF
face_v:
    .byte $FF, $FF, $FF, $FF, 0, 0, 0, 0, 1, 1, 1, 1, $FF, $FF, $FF, $FF

; 向き(下,上,左,右) → 方位(0=東, 時計回り16方位)
face_ang:   .byte 4, 12, 8, 0
LUNGE = $00C0
lunge_vx:   .word 0, 0, $10000-LUNGE, LUNGE
lunge_vy:   .word LUNGE, $10000-LUNGE, 0, 0
BACK = $0200
back_vx:    .word 0, 0, BACK, $10000-BACK
back_vy:    .word $10000-BACK, BACK, 0, 0
walk_cycle: .byte 1, 0, 2, 0

; 連斬 4 段 (重さ「標準」)
atk_startup: .byte 8, 8, 9, 11
atk_actend:  .byte 14, 14, 15, 17
atk_total:   .byte 22, 22, 25, 33
atk_power:   .byte 22, 20, 22, 32      ; 力10 + 暁12 / 宵10 / 暁 / 両方
atk_mult:    .byte 16, 16, 22, 36
atk_hitstop: .byte 3, 3, 4, 8
kb_power:    .word $0100, $0100, $0180, $0700   ; 1-3段は間合いに残し、4段目で飛ばす
sA_start:    .byte 3, <-3, 0, 4
sA_step:     .byte $FF, 0, 0, $FF
sB_start:    .byte <-5, <-3, 3, <-4
sB_step:     .byte 0, 1, 0, 1

; 攻撃判定の矩形 (主人公の足元からの相対、向き別)
hit_xmin:   .word $10000-30, $10000-30, $10000-42, $10000-6
hit_xmax:   .word 30, 30, 6, 42
hit_ymin:   .word $10000-8, $10000-44, $10000-30, $10000-30
hit_ymax:   .word 44, 8, 30, 30

dummy_home_x: .word $5000, $8000, $B000
dummy_home_y: .word $5800, $4800, $5800

.include "gfx.inc"
Palette:    .incbin "palette.bin"
FontChr:    .incbin "font.chr"
HudMap:     .incbin "hud.map"
BgMap:      .incbin "bg.map"

.segment "BANK1"
ObjChr:     .incbin "obj.chr"
.segment "BANK2"
BgChr:      .incbin "bg.chr"

; ---- カートリッジヘッダ -----------------------------------------------------
.segment "HEADER"
    .byte "CRADLE EDGE M1       "   ; 21 文字
    .byte $30               ; LoROM / FastROM
    .byte $00               ; ROM のみ
    .byte $08               ; 256KB
    .byte $00               ; SRAM なし
    .byte $00               ; 日本
    .byte $00               ; メーカーコード (未割当)
    .byte $00               ; バージョン
    .word $FFFF             ; チェックサム補数 (tools/fix_checksum.py が埋める)
    .word $0000             ; チェックサム

.segment "VECTORS"
    ; ネイティブ: -, -, COP, BRK, ABORT, NMI, -, IRQ
    .word 0, 0, .loword(IrqStub), .loword(IrqStub), .loword(IrqStub), .loword(Nmi), 0, .loword(IrqStub)
    ; エミュレーション: -, -, COP, -, ABORT, NMI, RESET, IRQ
    .word 0, 0, .loword(IrqStub), 0, .loword(IrqStub), .loword(IrqStub), .loword(Reset), .loword(IrqStub)
