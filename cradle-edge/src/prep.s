; ============================================================================
;  支度と成長 (M4-a)
;   - 剣 4 振り: 暁手 / 宵手に 1 本ずつ。攻・重さ・特効
;   - 献立 3 品
;   - 見切り印: 敵の種別ごとに最大 3。合計が力に、3 つ揃うと受付と返し刃が伸びる
;  装備や印が変わったら RecalcStats で連斬の性能表 (r_*) を作り直す。
; ============================================================================
NUM_SWORDS  = 4
NUM_STAGES  = 7
MEAL_MEAT   = 1             ; 力 +3
MEAL_ROOT   = 2             ; 守 +3
MEAL_DEW    = 3             ; 慈力の回復が速い
MARK_MAX    = 3

RecalcStats:
    .a8
    ; 力 = 10 + 見切り印の合計 ÷ 3 (+ 献立)
    lda marks+1
    clc
    adc marks+2
    clc
    adc marks+3
    clc
    adc marks+4
    ldx #$0000
@div:
    cmp #3
    bcc @divd
    sbc #3
    inx
    bra @div
@divd:
    txa
    clc
    adc #10
    sta p_str
    stz p_def
    lda meal
    cmp #MEAL_MEAT
    bne :+
    lda p_str
    clc
    adc #3
    sta p_str
:   lda meal
    cmp #MEAL_ROOT
    bne :+
    lda #3
    sta p_def
:   ; 剣
    rep #$20
    lda eqA
    and #$00FF
    tax
    sep #$20
    lda sw_atk,x
    sta t1                  ; 暁手の攻
    lda sw_wt,x
    sta t2
    lda sw_flag,x
    and #$01
    sta sp_mask
    rep #$20
    lda eqB
    and #$00FF
    tax
    sep #$20
    lda sw_atk,x
    sta t1+1                ; 宵手の攻
    lda sw_wt,x
    clc
    adc t2
    sta t2                  ; 重さの合計
    lda sw_flag,x
    and #$01
    asl a
    ora sp_mask
    sta sp_mask
    ; 段ごとの攻撃力
    ldx #$0000
@pow:
    lda stage_hand,x
    sta t3
    lda p_str
    lsr t3
    bcc :+
    clc
    adc t1
:   lsr t3
    bcc :+
    clc
    adc t1+1
:   sta r_power,x
    inx
    cpx #NUM_STAGES
    bne @pow
    ; 重さの区分 → 振りの速さ (フレームの増減)
    lda t2
    ldx #$0000
    cmp #9
    bcc @cls
    inx
    cmp #13
    bcc @cls
    inx
    cmp #17
    bcc @cls
    inx
@cls:
    lda weight_off,x
    sta t0
    ldx #$0000
@frm:
    lda atk_startup,x
    clc
    adc t0
    sta r_startup,x
    lda atk_actend,x
    clc
    adc t0
    sta r_actend,x
    lda atk_total,x
    clc
    adc t0
    clc
    adc t0
    sta r_total,x
    inx
    cpx #NUM_STAGES
    bne @frm
    rts

; A = いまの剣, t0 = もう片方の手の剣 → A = 次に持てる剣 (無ければそのまま)
NextSword:
    .a8
    sta t1
    stz t1+1
    sta t2
    lda #NUM_SWORDS
    sta t3
@loop:
    lda t1
    inc a
    and #$03
    sta t1
    cmp t0
    beq @skip
    ldx t1
    lda own
    and bit_tbl,x
    beq @skip
    lda t1
    rts
@skip:
    dec t3
    bne @loop
    lda t2
    rts

; ---- 焚き火の支度メニュー ---------------------------------------------------
PrepMenu:
    .a8
    jsr WinOpen
    stz menu_cur
    lda #0
    jsr MenuLine
    lda #1
    jsr MenuLine
    lda #2
    jsr MenuLine
    lda #3
    jsr MenuLine
@loop:
    stz pad_new
    stz pad_new+1
    jsr WaitFrame
    jsr ReadPad
    lda pad_new+1
    and #$08                ; 上
    beq :+
    lda menu_cur
    dec a
    bra @move
:   lda pad_new+1
    and #$04                ; 下
    beq @act
    lda menu_cur
    inc a
@move:
    and #$03
    pha
    lda menu_cur
    sta menu_line
    pla
    sta menu_cur
    lda menu_line           ; 前の行と今の行のカーソルを書き直す
    jsr MenuCursor
    lda menu_cur
    jsr MenuCursor
    bra @loop
@act:
    lda pad_new+1
    and #$90                ; B / START で終える
    bne @exit
    lda pad_new+1
    and #$43                ; Y / 左右
    bne @change
    lda pad_new
    bpl @loop               ; A
@change:
    lda menu_cur
    beq @swA
    cmp #1
    beq @swB
    cmp #2
    beq @meal
    lda kit                 ; 薬箱
    inc a
    and #$03
    sta kit
    bra @redraw
@exit:
    jsr RecalcStats
    jsr RefillKit
    rep #$20
    lda #.loword(BlankMap)
    sta vd_src
    lda #WIN_ADDR
    sta vd_dst
    lda #WIN_BYTES
    sta vd_len
    sep #$20
    stz pad_new
    stz pad_new+1
    jmp WaitFrame
@swA:
    lda eqB
    sta t0
    lda eqA
    jsr NextSword
    sta eqA
    bra @redraw
@swB:
    lda eqA
    sta t0
    lda eqB
    jsr NextSword
    sta eqB
    bra @redraw
@meal:
    lda meal
    inc a
    and #$03
    sta meal
@redraw:
    lda #SE_DENY
    jsr PlaySe
    lda menu_cur
    jsr MenuLine
    jmp @loop

; A = 行。行頭のカーソルだけ書く
MenuCursor:
    .a8
    sta menu_line
    jsr MenuAddr
    lda menu_line
    cmp menu_cur
    bne :+
    lda #GL_CURSOR
    jmp PutGlyph
:   lda #GL_SPACE
    jmp PutGlyph

; A = 行。カーソル + 見出し + 値
MenuLine:
    .a8
    jsr MenuCursor
    lda menu_line
    clc
    adc #SCR_M_L0
    jsr DrawLine
    lda menu_line
    beq @a
    cmp #1
    beq @b
    cmp #2
    bcs @m
    rts
@a:
    lda eqA
    clc
    adc #SCR_SW0
    jmp DrawLine
@b:
    lda eqB
    clc
    adc #SCR_SW0
    jmp DrawLine
@m:
    lda menu_line
    cmp #3
    beq @k
    lda meal
    clc
    adc #SCR_MEAL0
    jmp DrawLine
@k:
    lda kit
    clc
    adc #SCR_KIT0
    jmp DrawLine

; menu_line の行頭の VRAM 番地を txt_addr に
MenuAddr:
    .a8
    rep #$20
    lda menu_line
    and #$00FF
    xba
    lsr a
    lsr a                   ; × 64
    clc
    adc #TXT_ORG
    sta txt_addr
    sep #$20
    rts

; ---- 一時停止 (START): 母の作戦・力・見切り印 ----------------------------
PauseMenu:
    .a8
    stz pad_new
    stz pad_new+1
    jsr WinOpen
    stz menu_cur
    jsr PauseTac
    ; 2 行目: 力 守 印
    lda #1
    sta menu_line
    jsr MenuAddr
    lda #SCR_P_STR
    jsr DrawLine
    lda p_str
    jsr PutNum
    lda #SCR_P_DEF
    jsr DrawLine
    lda p_def
    jsr PutNum
    lda #SCR_P_MK
    jsr DrawLine
    lda marks+1
    clc
    adc marks+2
    clc
    adc marks+3
    clc
    adc marks+4
    jsr PutNum
    ; 3, 4 行目: 敵ごとの見切り印
    lda #2
    sta menu_line
    jsr MenuAddr
    lda #SCR_P_E1
    jsr DrawLine
    lda marks+1
    jsr PutMarks
    lda #SCR_P_E2
    jsr DrawLine
    lda marks+2
    jsr PutMarks
    lda #3
    sta menu_line
    jsr MenuAddr
    lda #SCR_P_E3
    jsr DrawLine
    lda marks+3
    jsr PutMarks
    lda #SCR_P_E4
    jsr DrawLine
    lda marks+4
    jsr PutMarks
@loop:
    stz pad_new
    stz pad_new+1
    jsr WaitFrame
    jsr ReadPad
    lda pad_new+1
    and #$90                ; B / START で閉じる
    bne @exit
    lda pad_new+1
    and #$43                ; Y / 左右
    bne @tac
    lda pad_new
    bpl @loop               ; A
@tac:
    lda m_tac
    inc a
    cmp #3
    bcc :+
    lda #0
:   sta m_tac
    stz m_order
    lda #SE_DENY
    jsr PlaySe
    jsr PauseTac
    bra @loop
@exit:
    stz pad_new
    stz pad_new+1
    jmp WinClose

PauseTac:
    .a8
    lda #0
    jsr MenuCursor
    lda #SCR_P_TAC
    jsr DrawLine
    lda m_tac
    clc
    adc #SCR_TAC0
    jmp DrawLine

; A = 0-99。全角 2 桁 (十の位が 0 なら空白)
PutNum:
    .a8
    sta $4204
    stz $4205
    lda #10
    sta $4206
    jsr DivWait
    lda $4216
    pha
    lda $4214
    beq @sp
    rep #$20
    and #$00FF
    tax
    sep #$20
    lda digit_glyph,x
    bra @t
@sp:
    lda #GL_SPACE
@t:
    jsr PutGlyph
    pla
    rep #$20
    and #$00FF
    tax
    sep #$20
    lda digit_glyph,x
    jmp PutGlyph

; A = 印の数 → ●●○
PutMarks:
    .a8
    sta t2
    lda #0
    sta t3
@loop:
    lda t3
    cmp t2
    lda #GL_FULL
    bcc :+
    lda #GL_EMPTY
:   jsr PutGlyph
    inc t3
    lda t3
    cmp #MARK_MAX
    bcc @loop
    rts

WinClose:
    .a8
    rep #$20
    lda #.loword(BlankMap)
    sta vd_src
    lda #WIN_ADDR
    sta vd_dst
    lda #WIN_BYTES
    sta vd_len
    sep #$20
    jmp WaitFrame

; ---- 薬箱 ------------------------------------------------------------------
MED_HEAL    = 60
MED_JI      = 50

; 組み合わせどおりに詰め直す (焚き火で休んだ時・やり直す時)
RefillKit:
    .a8
    lda kit
    rep #$20
    and #$00FF
    tax
    sep #$20
    lda kit_h,x
    sta med
    lda kit_j,x
    sta med+1
    lda kit_r,x
    sta med+2
    rts

; SELECT で種類を切り替え、L で使う
UseMedicine:
    .a8
    lda pad_new+1
    and #$20                ; SELECT
    beq @use
    lda med_sel
    inc a
    cmp #3
    bcc :+
    lda #0
:   sta med_sel
    lda #SE_DENY
    jmp PlaySe
@use:
    lda pad_new
    and #$20                ; L
    bne :+
    rts
:   lda med_sel
    rep #$20
    and #$00FF
    tax
    sep #$20
    lda med,x
    beq @deny
    cpx #1
    beq @ji
    bcs @rev
    rep #$20                ; 傷薬: 最大までしか戻らない (過剰生命にはならない)
    lda p_hp
    cmp #HP_MAX
    bcs @deny16
    clc
    adc #MED_HEAL
    cmp #HP_MAX
    bcc :+
    lda #HP_MAX
:   sta p_hp
    sep #$20
    bra @used
@ji:
    lda m_ji
    cmp #100
    bcs @deny
    clc
    adc #MED_JI
    cmp #100
    bcc :+
    lda #100
:   sta m_ji
    bra @used
@rev:
    lda m_down              ; 気付け薬: 倒れた母をすぐ起こす
    ora m_down+1
    beq @deny
    stz m_down
    stz m_down+1
    lda #MOM_HP_MAX/2
    sta m_hp
@used:
    lda med_sel
    rep #$20
    and #$00FF
    tax
    sep #$20
    dec med,x
    lda p_x+1
    sta fx_ax
    lda p_y+1
    sta fx_ay
    lda #PAL_HEAL
    sta fx_p
    jsr SpawnFx
    lda #SE_HEAL
    jmp PlaySe
@deny16:
    sep #$20
@deny:
    lda #SE_DENY
    jmp PlaySe

;            傷薬3慈1  傷2慈2  傷2気2  傷4
kit_h:   .byte 3,       2,      2,      4
kit_j:   .byte 1,       2,      0,      0
kit_r:   .byte 0,       0,      2,      0
med_letter: .byte 18, 20, 28          ; HUD フォントの H / J / R

;             鉄塊「暁」 鉄塊「宵」 苔断ち  水車の鉄軸
sw_atk:  .byte 12,        10,        16,     22
sw_wt:   .byte 4,         4,         4,      8
sw_flag: .byte 0,         0,         1,      0      ; bit0 = 繁り特効
bit_tbl: .byte 1, 2, 4, 8
; 段ごとに使う手: bit0 = 暁手, bit1 = 宵手
stage_hand: .byte 1, 2, 1, 3, 2, 3, 3
; 重さ合計 〜8 / 9〜12 / 13〜16 / 17〜 の、発生フレームの増減
weight_off: .byte <-2, 0, 3, 5
