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
MINX        = $0400         ; 画面内に収める範囲 (8.8)。壁は col_map で判定
MAXX        = $FC00
MINY        = $1800
MAXY        = $DE00

NUM_DUMMY   = 6             ; 敵の最大数。配列は2バイト刻み (X=0,2,..)
DUMMY_END   = NUM_DUMMY*2
DUMMY_HP    = 100
DUMMY_DEF   = 4
DEAD_TIME   = 40            ; 倒れてから消えるまで (点滅しながら吹き飛ぶ)
DEAD_VISIBLE= 0

NUM_FX      = 4
NUM_SHOT    = 8

ST_FREE     = 0
ST_ATTACK   = 1
ST_DODGE    = 2
ST_HURT     = 3

SE_SLASH    = 1
SE_HIT      = 2
SE_HEAVY    = 3
SE_JUST     = 4
SE_HURT     = 5
SE_CAST     = 6
SE_HEAL     = 7
SE_COLLAPSE = 8
SE_DENY     = 9
SE_DODGE    = 10

CHARGE_SHOW = 10            ; これ以上で構えが変わり、歩きが遅くなる
CHARGE_LV1  = 36            ; 0.6 秒: 双牙落とし
CHARGE_LV2  = 84            ; 1.4 秒: 地裂き
MOM_HP_MAX  = 70

PAL_HERO    = 0 << 1
PAL_SWORD_A = 2 << 1
PAL_SWORD_B = 3 << 1
PAL_MOM     = 1 << 1
PAL_ENEMY   = 4 << 1
PAL_HEAL    = 6 << 1
PAL_FLASH   = 5 << 1
PAL_FX      = 7 << 1
PRIO        = $20           ; OBJ 優先度2

; VRAM 配置 (ワードアドレス)
VRAM_BG1_MAP = $0000
VRAM_BG3_MAP = $0400
VRAM_BG1_CHR = $1000
VRAM_BG3_CHR = $6000
VRAM_OBJ_CHR = $4000

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
tick:        .res 1
p_hp:        .res 2
p_inv:       .res 1          ; 被弾後の無敵
p_just:      .res 1          ; ジャスト回避後、返し刃を出せる残り時間
just_idx:    .res 2
dim_t:       .res 1
dead_t:      .res 1
adx:         .res 2
ady:         .res 2
near_idx:    .res 2
fx_ax:       .res 1
fx_ay:       .res 1
fx_p:        .res 1
se_count:    .res 1
m_x:         .res 2
m_y:         .res 2
m_face:      .res 1
m_state:     .res 1
m_timer:     .res 1
m_anim:      .res 1
m_ji:        .res 1          ; 慈力
m_target:    .res 2
m_tac:       .res 1          ; 作戦
m_order:     .res 1          ; 「殴って！」を受けた
m_xhold:     .res 1          ; X を押し続けている長さ
m_cd:        .res 1          ; 次に殴れるまで
m_auto:      .res 1          ; 次に勝手に癒やせるまで
mdx:         .res 1          ; 母の行き先
mdy:         .res 1
mstop_x:     .res 2          ; 行き先にこれだけ近づいたら止まる
mstop_y:     .res 2
m_hp:        .res 1
m_inv:       .res 1
m_rev:       .res 1          ; 助け起こしの進み具合
m_down:      .res 2          ; ひざをついている残り時間
p_charge:    .res 1          ; 溜め
tpx:         .res 1          ; 敵が狙っている位置
tpy:         .res 1
bar_th:      .res 1
hit_w:       .res 1
hit_h:       .res 1
room:        .res 1
cur_set:     .res 1
rp:          .res 2
scp:         .res 2
bright:      .res 1
vq_n:        .res 1          ; VRAM 書き込み予約 (番地, 語, 語) x 2
vq:          .res 12
vd_src:      .res 2          ; VRAM への DMA 予約 (会話窓用)
vd_dst:      .res 2
vd_len:      .res 2
txt_addr:    .res 2
txt_line:    .res 2
gq_n:        .res 1          ; 字の絵の転送予約
gq_src:      .res 2
gq_dst:      .res 2
gw0:         .res 2
gw1:         .res 2
cx:          .res 1
cy:          .res 1
om_x:        .res 2
om_y:        .res 2
oe_x:        .res 2
oe_y:        .res 2

.bss
room_exit:   .res 4          ; 上下左右の行き先 ($FF = なし)
room_enter:  .res 1          ; 初入室時の台本 ($FF = なし)。room_exit の直後に置くこと
room_music:  .res 1          ; 部屋の曲。room_enter の直後に置くこと
boss_dead:   .res 1
ev_boss:     .res 1
chk_room:    .res 1          ; 最後に休んだ焚き火
chk_x:       .res 1
chk_y:       .res 1
title_sel:   .res 1
title_has:   .res 1
eqA:         .res 1          ; 暁手の剣
eqB:         .res 1          ; 宵手の剣
meal:        .res 1
own:         .res 1          ; 持っている剣 (bit)
marks:       .res 5          ; 見切り印 (敵の種別ごと)
p_str:       .res 1
p_def:       .res 1
p_justm:     .res 1          ; 見切った攻撃をジャスト回避した
sp_mask:     .res 1          ; 繁り特効の手
menu_cur:    .res 1
menu_line:   .res 1
kit:         .res 1          ; 薬箱の組み合わせ
med:         .res 3          ; 傷薬 / 慈力水 / 気付け薬 の残り
med_sel:     .res 1
am_own:      .res 1          ; 持っている護符 (bit 1-7)
am1:         .res 1          ; 身につけている護符 (0 = なし)
am2:         .res 1
am_on:       .res 1          ; 効いている護符 (bit)
menu_top:    .res 1          ; 支度メニューの表示の先頭行
ch_lv1:      .res 1          ; 溜めの段階 (護符で変わる)
ch_lv2:      .res 1
cast_heal:   .res 1          ; 詠唱の長さ (護符で変わる)
cast_over:   .res 1
mq_exp:      .res 6          ; 熟練の経験 (連斬 / 溜め斬り / 返し刃)
mq_lv:       .res 3          ; 熟練 Lv (1-5)
chart:       .res 5          ; 母のカルテ (敵の種別ごと、崩壊させた回数)
chart_done:  .res 1          ; 完成したカルテの数
over_amt:    .res 1          ; 過治癒 1 回で溜まる飽和
pause_pg:    .res 1
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
fx_pal:      .res NUM_FX
d_maxhp:     .res DUMMY_END
d_sat:       .res DUMMY_END
d_satmax:    .res DUMMY_END
d_def:       .res DUMMY_END
d_avx:       .res DUMMY_END
d_avy:       .res DUMMY_END
d_type:      .res DUMMY_END  ; 以下バイト
d_state:     .res DUMMY_END
d_timer:     .res DUMMY_END
d_stun:      .res DUMMY_END
d_col:       .res DUMMY_END
d_atkdone:   .res DUMMY_END
d_noregen:   .res DUMMY_END
d_flip:      .res DUMMY_END
d_tgt:       .res DUMMY_END
d_pat:       .res DUMMY_END  ; 次に出す技
sh_x:        .res NUM_SHOT*2 ; 飛び道具 (種)
sh_y:        .res NUM_SHOT*2
sh_vx:       .res NUM_SHOT*2
sh_vy:       .res NUM_SHOT*2
sh_t:        .res NUM_SHOT*2 ; 残り時間 (下位バイトのみ使う)
sh_src:      .res NUM_SHOT*2 ; 撃った敵
hud_buf:     .res 128
col_map:     .res 256
it_kind:     .res 8
it_x:        .res 8
it_y:        .res 8
it_a:        .res 8
it_b:        .res 8
seen:        .res 8
r_power:     .res 8          ; 装備から作った連斬の性能表
r_startup:   .res 8
r_actend:    .res 8
r_total:     .res 8

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
    VRAM_DMA BgChr,     BG_CHR_SIZE,    VRAM_BG1_CHR
    VRAM_DMA FontChr,   FONT_CHR_SIZE,  VRAM_BG3_CHR
    VRAM_DMA WindowChr, 48,             VRAM_BG3_CHR + 77*8
    VRAM_DMA HudMap,    $0800,          VRAM_BG3_MAP
    VRAM_DMA ObjChr,    OBJ_CHR_SIZE,   VRAM_OBJ_CHR

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
    lda #32                 ; 背景パレット 2 本
    sta $2121
    ldx #.loword(BgPal)
    stx $4302
    lda #^BgPal
    sta $4304
    ldx #64
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

    jsr UploadSpc
    lda #$81                ; NMI + 自動パッド読み
    sta $4200
Restart:
    jsr TitleScreen
    jsr InitGame

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
    lda pad_new+1           ; ヒットストップ中も Y の先行入力は拾う
    and #$40
    beq @draw
    lda #$01
    sta p_buf
    bra @draw
@update:
    inc tick
    lda dead_t
    beq @alive
    dec dead_t
    bne @world
    jsr InitGame            ; 倒れたら最後の焚き火から
    bra @draw
@alive:
    jsr UpdatePlayer
    jsr CheckExits
    jsr UpdateMother
@world:
    jsr UpdateEnemies
    jsr UpdateShots
    jsr UpdateDummies
    jsr BumpDummies
    lda ev_boss
    beq :+
    jmp BossDefeated
:
    jsr UpdateFx
    jsr UpdateTimers
    stz pad_new
    stz pad_new+1
@draw:
    lda dim_t
    beq :+
    dec dim_t
:   jsr UpdateShake
    jsr DrawAll
    jsr BuildHud
    lda #$01
    sta nmi_ready
    jmp MainLoop

; 音源の起動プログラム (IPL) に話しかけて、ドライバと波形を送り込む
UploadSpc:
    .a8
:   lda $2140
    cmp #$AA
    bne :-
:   lda $2141
    cmp #$BB
    bne :-
    ldx #SPC_BASE
    stx $2142
    lda #$01
    sta $2141
    lda #$CC
    sta $2140
:   cmp $2140
    bne :-
    stz t0                  ; 通し番号
    ldx #$0000
@byte:
    lda f:SpcData,x
    sta $2141
    lda t0
    sta $2140
:   cmp $2140
    bne :-
    inc t0
    inx
    cpx #SPC_SIZE
    bne @byte
    ldx #SPC_BASE           ; 実行開始番地
    stx $2142
    stz $2141
    lda t0
    clc
    adc #$02
    bne :+
    lda #$02
:   sta $2140
:   cmp $2140
    bne :-
    stz se_count
    rts

; A = 曲番号 (0 で止める)。音源のポート2に書く
PlayMusic:
    .a8
    sta $2142
    rts

; A = 効果音番号。APU のポート0に番号、ポート1に通し番号を書く
PlaySe:
    .a8
    sta $2140
    inc se_count
    lda se_count
    sta $2141
    rts

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
    bne :+
    jmp @skip
:   stz nmi_ready

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

    ; HUD 2行ぶんを転送
    lda #$80
    sta $2115
    ldx #VRAM_BG3_MAP + 32
    stx $2116
    lda #$01
    sta $4300
    lda #$18
    sta $4301
    ldx #hud_buf
    stx $4302
    stz $4304
    ldx #128
    stx $4305
    lda #$01
    sta $420B
    ; 予約された字の絵 (64 バイト)
    lda gq_n
    beq @no_gq
    stz gq_n
    ldx gq_dst
    stx $2116
    lda #$01
    sta $4300
    lda #$18
    sta $4301
    ldx gq_src
    stx $4302
    lda #^GlyphChr
    sta $4304
    ldx #64
    stx $4305
    lda #$01
    sta $420B
@no_gq:
    ; 予約された VRAM 書き込み (文字 1 字ぶん)
    lda vq_n
    beq @no_vq
    stz vq_n
    ldx vq
    stx $2116
    ldx vq+2
    stx $2118
    ldx vq+4
    stx $2118
    ldx vq+6
    stx $2116
    ldx vq+8
    stx $2118
    ldx vq+10
    stx $2118
@no_vq:
    ldx vd_len              ; 予約された DMA (会話窓)
    beq @no_vd
    ldx vd_dst
    stx $2116
    ldx vd_src
    stx $4302
    lda #^WindowMap
    sta $4304
    ldx vd_len
    stx $4305
    lda #$01
    sta $420B
    ldx #$0000
    stx vd_len
@no_vd:
    ; ジャスト回避の瞬間は画面を暗く
    lda dim_t
    beq :+
    lda bright
    lsr a
    bra :++
:   lda bright
:   sta $2100
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
; 最後の焚き火 (chk_*) から再開する。状態を戻して部屋を読み直す
InitGame:
    .a8
    jsr RecalcStats
    jsr RefillKit
    rep #$20
    lda #HP_MAX
    sta p_hp
    lda rng
    bne :+
    lda #$ACE1
    sta rng
:   stz p_x
    stz p_y
    stz m_down
    sep #$20
    lda chk_x
    sta p_x+1
    lda chk_y
    sta p_y+1
    lda #$00
    sta p_face
    sta m_face
    stz p_state
    stz p_timer
    stz p_inv
    stz p_just
    stz p_buf
    stz dead_t
    stz m_state
    stz combo
    stz hitstop
    stz p_charge
    stz m_inv
    stz m_rev
    stz ev_boss
    stz m_order
    stz m_xhold
    stz m_cd
    stz m_auto
    lda #MOM_HP_MAX
    sta m_hp
    lda #100
    sta m_ji
    ldx #$0000
@h:
    lda HudMap+64,x
    sta hud_buf,x
    inx
    cpx #128
    bne @h
    lda chk_room
    jmp ChangeRoom

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
    ora pad_new             ; ヒットストップ中の押下も次の更新まで覚えておく
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
    .a8
    lda p_inv
    beq :+
    dec p_inv
:   lda p_just
    beq :+
    dec p_just
:   jsr MotherCommands
    jsr UseMedicine
    lda p_state             ; START で一時停止 (自由に動ける時だけ)
    bne :+
    lda pad_new+1
    and #$10
    beq :+
    jmp PauseMenu
:
    lda p_state
    cmp #ST_HURT
    bne :+
    jmp PlayerHurt
:
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
    stz p_charge
    jsr TryInteract         ; 話す・調べる相手がいればそちらを優先
    bcc @slash
    rts
@slash:
    jmp StartAttack
:   lda pad_new+1
    bpl :+                  ; B
    stz p_charge
    jmp StartDodge
:   lda pad+1               ; Y を押し続けると溜め、離すと溜め斬り
    and #$40
    beq @released
    lda p_charge
    cmp ch_lv2
    bcs @move
    inc p_charge
    lda p_charge
    cmp ch_lv1
    beq @ding
    cmp ch_lv2
    bne @move
@ding:
    lda #SE_JUST
    jsr PlaySe
    bra @move
@released:
    lda p_charge
    stz p_charge
    cmp ch_lv1
    bcc @move
    ldx #$0005              ; 段5 = 双牙落とし, 段6 = 地裂き
    cmp ch_lv2
    bcc :+
    inx
:   txa
    sta p_stage
    lda #ST_ATTACK
    sta p_state
    stz p_timer
    stz p_buf
    stz p_anim
    inc swing_id
    lda #SE_SLASH
    jsr PlaySe
    jmp PlayerAttack
@move:
    lda pad+1
    and #$0F
    beq @idle
    jsr SetFacingFromPad
    jsr LoadPadVelocity
    lda p_charge            ; 溜め中は歩きが半分
    cmp #CHARGE_SHOW
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
    inc p_anim
    bra @rest
@idle:
    stz p_anim
@rest:
    jsr SetRestSwords
    lda p_charge            ; 溜め中は2本とも背中側へ振りかぶる
    cmp #CHARGE_SHOW
    bcc :+
    lda swA_ang
    clc
    adc #2
    and #$0F
    sta swA_ang
    lda swB_ang
    sec
    sbc #2
    and #$0F
    sta swB_ang
:   rts

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
    .a8
    lda pad+1
    and #$0F
    beq :+
    jsr SetFacingFromPad
:   lda #ST_ATTACK
    sta p_state
    stz p_stage
    lda p_just              ; ジャスト回避の直後なら「返し刃」
    beq :+
    stz p_just
    ldx just_idx
    jsr FacePlayerTo
    lda #4
    sta p_stage
:   stz p_timer
    stz p_buf
    inc swing_id
    stz p_anim
    lda #SE_SLASH
    jsr PlaySe
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
    cmp r_startup,x
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
    cmp r_startup,x
    bcc @no_hit
    cmp r_actend,x
    bcs @no_hit
    jsr AttackHit
@no_hit:
    inc p_timer
    jsr StageToX
    lda p_timer
    cmp r_total,x
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
    lda #SE_SLASH
    jsr PlaySe
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
    sbc r_startup,x
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
    cmp r_startup,x
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
    lda d_type,x
    beq @next
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

; X = 当たった敵
ApplyHit:
    .a8
    lda swing_id
    sta d_hitid,x
    phx
    jsr StageToX
    txy                     ; Y = 段
    plx
    ; ダメージ = 攻撃力 × 倍率 ÷ 16 − 守÷2 + 乱数(0-3)
    lda r_power,y
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
    clc
    adc t0
    sec
    sbc d_def,x
    bmi @min
    bne @pos
@min:
    lda #$0001
@pos:
    sta t3
    lda p_hp                ; 過剰生命があれば +25%
    cmp #HP_MAX+1
    bcc :+
    lda t3
    lsr a
    lsr a
    clc
    adc t3
    sta t3
:   sep #$20
    lda stage_hand,y        ; 繁り特効 ×1.5 (へび・案山子・水車番)
    and sp_mask
    beq @no_sp
    lda d_type,x
    cmp #TYPE_SNAKE
    bcc @no_sp
    jsr Boost150
@no_sp:
    cpy #$0004              ; 見切った攻撃への返し刃 ×1.5
    bne :+
    lda p_justm
    beq :+
    jsr Boost150
:   jsr MasteryBoost        ; 熟練 Lv ごとに +1/16
    lda d_col,x             ; 崩壊中の敵には2倍
    rep #$20
    beq :+
    asl t3
:   lda t3
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
    ; 案山子は崩壊中か3段目以降でないとひるまない
    lda d_dead,x
    bne @stagger
    lda d_type,x
    cmp #TYPE_SCARE
    bcc @stagger
    lda d_col,x
    bne @stagger
    lda d_type,x            ; ボスは崩壊中しかひるまない
    cmp #TYPE_BOSS
    beq @armor
    cpy #$0002
    bcs @stagger
@armor:
    rep #$20
    stz d_vx,x
    stz d_vy,x
    sep #$20
    bra @fx
@stagger:
    lda #20
    sta d_stun,x
    stz d_state,x
@fx:
    lda atk_hitstop,y
    sta hitstop
    lda #SE_HIT
    cpy #$0003
    bcc :+
    lda #10
    sta shake_t
    lda #SE_HEAVY
:   jsr PlaySe
    jsr SpawnSparkAtDummy
    jsr MasteryGain
    lda combo
    cmp #99
    bcs :+
    inc combo
:   lda #120
    sta combo_t
    rts

; t3 (16bit) を 1.5 倍に
Boost150:
    .a8
    rep #$20
    lda t3
    lsr a
    clc
    adc t3
    sta t3
    sep #$20
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
    lda am_on               ; 軽業の靴: 回避が 1.25 倍
    and #AMB_SHOES
    beq :+
    rep #$20
    lda dodge_vx
    ASR16
    ASR16
    clc
    adc dodge_vx
    sta dodge_vx
    lda dodge_vy
    ASR16
    ASR16
    clc
    adc dodge_vy
    sta dodge_vy
    sep #$20
:   lda #ST_DODGE
    sta p_state
    stz p_timer
    stz p_buf
    lda #SE_DODGE
    jsr PlaySe

PlayerDodge:
    .a8
    lda p_just              ; ジャスト回避が成立していれば Y で返し刃へ
    beq @no_counter
    lda p_buf
    bne @counter
    lda pad_new+1
    and #$40
    beq @no_counter
@counter:
    jmp StartAttack
@no_counter:
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
    .a8
    ldx #$0000
@loop:
    lda d_type,x
    bne :+
    jmp @next
:   jsr EnemySavePos
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
    lda d_type,x
    cmp #TYPE_BOSS
    bne :+
    lda #$01
    sta ev_boss
:   stz d_type,x            ; 消滅
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
    jsr EnemyClip
@next:
    inx
    inx
    cpx #DUMMY_END
    beq :+
    jmp @loop
:   rts

; 木人どうしの玉突き
BumpDummies:
    .a8
    ldx #$0000
@i:
    txy
    iny
    iny
@j:
    cpy #DUMMY_END
    bcs @ni
    lda d_type,x
    beq @ni
    lda d_type,y
    beq @nj
    phx
    phy
    jsr SeparatePair
    ply
    plx
    phx
    phy
    jsr BumpPair
    ply
    plx
@nj:
    iny
    iny
    bra @j
@ni:
    inx
    inx
    cpx #DUMMY_END-2
    bcc @i
    rts

; X, Y = 敵。ほぼ同じ場所に重なっていたら左右に少しずつ押し分ける
SeparatePair:
    .a8
    lda d_dead,x
    ora d_dead,y
    bne @out
    lda d_x+1,x
    sec
    sbc d_x+1,y
    bcs :+
    eor #$FF
    inc a
:   cmp #12
    bcs @out
    lda d_y+1,x
    sec
    sbc d_y+1,y
    bcs :+
    eor #$FF
    inc a
:   cmp #10
    bcs @out
    rep #$20
    lda d_x,x
    cmp d_x,y
    bcc @x_left
    clc
    adc #$00A0
    sta d_x,x
    lda d_x,y
    sec
    sbc #$00A0
    sta d_x,y
    sep #$20
    rts
@x_left:
    .a16
    sec
    sbc #$00A0
    sta d_x,x
    lda d_x,y
    clc
    adc #$00A0
    sta d_x,y
    sep #$20
@out:
    rts

; X, Y = 敵の添字
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
; X = 敵。その位置に火花
SpawnSparkAtDummy:
    .a8
    lda d_x+1,x
    sta fx_ax
    lda d_y+1,x
    sta fx_ay
    lda #PAL_FX
    sta fx_p
    ; fallthrough

; fx_ax, fx_ay = 位置, fx_p = パレット
SpawnFx:
    .a8
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
    lda fx_ax
    sta fx_x,y
    lda fx_ay
    sta fx_y,y
    lda fx_p
    sta fx_pal,y
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
    .a8
    lda tick                ; 過剰生命は少しずつ抜ける
    and #$1F
    bne :+
    rep #$20
    lda p_hp
    cmp #HP_MAX+1
    bcc @nodecay
    dec p_hp
@nodecay:
    sep #$20
:
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
    jsr DrawShots
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
    jsr DrawHeroAndMother
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
    jsr DrawNpcs
    jsr DrawShadows

    ; 残りを画面外へ
FinishOam:
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
    .a8
    lda dead_t              ; 倒れたら点滅して消える
    beq :+
    cmp #60
    bcc @hidden
    and #$04
    beq @hidden
:   lda p_inv               ; 被弾後の無敵中は点滅
    and #$02
    beq :+
@hidden:
    rts
:   ; コマ選択
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
    .a8
    lda p_charge            ; 溜まったら剣が光る
    cmp ch_lv1
    bcc @normal
    lda tick
    and #$02
    beq @normal
    lda swA_ang
    ldx #PAL_FLASH | PRIO
    ldy swA_rad
    jsr DrawSword
    lda swB_ang
    ldx #PAL_FLASH | PRIO
    ldy swB_rad
    jmp DrawSword
@normal:
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

DrawShadows:
    .a8
    lda #SHADOW_TILE
    sta spr_tile
    lda #(SHADOW_NAME | PAL_FX | PRIO)
    sta spr_attr
    lda #$02
    sta spr_size
    SPR_AT p_x, p_y, -16, -12
    jsr AddSprite
    SPR_AT m_x, m_y, -16, -12
    jsr AddSprite
    ldx #$0000
@loop:
    lda d_type,x
    beq @next
    cmp #TYPE_BOSS
    beq @next
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
    lda fx_pal,x
    ora #(SPARK_NAME | PRIO | $10)            ; 優先度3で最前面
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

.include "enemy.s"
.include "mother.s"
.include "world.s"
.include "prep.s"

; ---- HUD --------------------------------------------------------------------
; combo (2桁) と last_dmg (3桁) をタイル番号に (タイル1 = '0')
BuildHud:
    .a8
    lda #10                 ; HP: 10 マス + 過剰生命 5 マス (金)
    sta bar_th
    rep #$20
    lda p_hp
    sta t1
    sep #$20
    ldx #5*2
    lda #15
    jsr DrawBar
    lda m_hp                ; 母の HP: 7 マス
    sta t1
    stz t1+1
    ldx #64 + 5*2
    lda #7
    jsr DrawBar
    stz bar_th              ; 慈力: 10 マス (金)
    lda m_ji
    sta t1
    stz t1+1
    ldx #64 + 13*2
    lda #10
    jsr DrawBar
    lda med_sel             ; 薬: 種類の頭文字と残り (L:H 3)
    rep #$20
    and #$00FF
    tax
    sep #$20
    lda med_letter,x
    sta hud_buf+64+25*2
    lda med,x
    inc a
    sta hud_buf+64+27*2
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
    sta hud_buf+27*2
    lda $4216
    sta $4204
    stz $4205
    lda #10
    sta $4206
    jsr DivWait
    lda $4214
    inc a
    sta hud_buf+28*2
    lda $4216
    inc a
    sta hud_buf+29*2
    rts

; t1 = 値, X = hud_buf 内の位置, A = マス数 (1マス = 10)
; bar_th 番目以降のマスは金色。bar_th = 0 なら全体が金色のゲージ
DrawBar:
    .a8
    sta t2
    ldy #$0000
@cell:
    rep #$20
    lda t1
    cmp #10
    bcc :+
    lda #10
:   sta t0
    lda t1
    sec
    sbc t0
    sta t1
    sep #$20
    phx
    ldx t0
    lda bar_level,x
    plx
    sta t3
    tya
    cmp bar_th
    bcc @white
    lda t3
    bne @gold
    lda bar_th              ; 過剰生命の区間は、空なら何も出さない
    beq @gold
    lda #0
    bra @put
@gold:
    lda t3
    clc
    adc #BAR_TILE+9
    bra @put
@white:
    lda t3
    clc
    adc #BAR_TILE
@put:
    sta hud_buf,x
    inx
    inx
    iny
    tya
    cmp t2
    bne @cell
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
; 段4 = 返し刃, 段5 = 双牙落とし, 段6 = 地裂き
atk_startup: .byte 8, 8, 9, 11, 4, 6, 8
atk_actend:  .byte 14, 14, 15, 17, 10, 12, 14
atk_total:   .byte 22, 22, 25, 33, 26, 34, 40
atk_power:   .byte 22, 20, 22, 32, 20, 32, 32      ; 力10 + 暁12 / 宵10 / 暁 / 両方
atk_mult:    .byte 16, 16, 22, 36, 72, 40, 56 ; 返し刃 = 48 × 会心1.5 / 溜め1 / 溜め2
atk_hitstop: .byte 3, 3, 4, 8, 10, 10, 14
kb_power:    .word $0100, $0100, $0180, $0700, $0600, $0700, $0900   ; 1-3段は間合いに残し、4段目で飛ばす
sA_start:    .byte 3, <-3, 0, 4, 5, 7, 7
sA_step:     .byte $FF, 0, 0, $FF, 0, $FF, $FF
sB_start:    .byte <-5, <-3, 3, <-4, <-4, <-7, <-7
sB_step:     .byte 0, 1, 0, 1, 1, 1, 1

; 攻撃判定の矩形 (主人公の足元からの相対、向き別)
hit_xmin:   .word $10000-30, $10000-30, $10000-42, $10000-6
hit_xmax:   .word 30, 30, 6, 42
hit_ymin:   .word $10000-8, $10000-44, $10000-30, $10000-30
hit_ymax:   .word 44, 8, 30, 30

bar_level:  .byte 0, 1, 2, 2, 3, 4, 5, 6, 6, 7, 8    ; 0-10 → 8段階

.include "gfx.inc"
.include "audio.inc"
.include "rooms.inc"
.include "script.inc"
SetPal:     .incbin "set0.pal"
            .incbin "set1.pal"
            .incbin "set2.pal"
BgPal:      .incbin "bg.pal"
WindowChr:  .incbin "window.chr"
Palette:    .incbin "palette.bin"
FontChr:    .incbin "font.chr"
HudMap:     .incbin "hud.map"

.segment "BANK1"
ObjChr:     .incbin "obj.chr"
SetChr:     .incbin "set0.chr"
            .incbin "set1.chr"
            .incbin "set2.chr"
.segment "BANK2"
BgChr:      .incbin "bg.chr"

.segment "BANK3"
RoomMaps:   .incbin "rooms.bin"
WindowMap:  .incbin "window.map"
BlankMap:   .incbin "blank.map"

.segment "BANK4"
SpcData:    .incbin "spc.bin"          ; 音源ドライバ・波形・曲 (起動時に音源へ送る)

.segment "BANK5"
GlyphChr:   .incbin "glyph.chr"        ; 字の絵 (1 字 64 バイト、使う時に VRAM へ送る)

; ---- カートリッジヘッダ -----------------------------------------------------
.segment "HEADER"
    .byte "CRADLE EDGE          "   ; 21 文字
    .byte $30               ; LoROM / FastROM
    .byte $02               ; ROM + RAM + 電池
    .byte $08               ; 256KB
    .byte $03               ; SRAM 8KB
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
