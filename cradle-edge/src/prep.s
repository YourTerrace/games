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
    bmi @exit               ; B
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
@exit:
    jsr RecalcStats
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
    beq @m
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
    lda meal
    clc
    adc #SCR_MEAL0
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

;             鉄塊「暁」 鉄塊「宵」 苔断ち  水車の鉄軸
sw_atk:  .byte 12,        10,        16,     22
sw_wt:   .byte 4,         4,         4,      8
sw_flag: .byte 0,         0,         1,      0      ; bit0 = 繁り特効
bit_tbl: .byte 1, 2, 4, 8
; 段ごとに使う手: bit0 = 暁手, bit1 = 宵手
stage_hand: .byte 1, 2, 1, 3, 2, 3, 3
; 重さ合計 〜8 / 9〜12 / 13〜16 / 17〜 の、発生フレームの増減
weight_off: .byte <-2, 0, 3, 5
