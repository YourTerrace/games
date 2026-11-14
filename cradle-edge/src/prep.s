; ============================================================================
;  支度と成長 (M4-a)
;   - 剣 4 振り: 暁手 / 宵手に 1 本ずつ。攻・重さ・特効
;   - 献立 3 品
;   - 見切り印: 敵の種別ごとに最大 3。合計が力に、3 つ揃うと受付と返し刃が伸びる
;  装備や印が変わったら RecalcStats で連斬の性能表 (r_*) を作り直す。
; ============================================================================
NUM_SWORDS  = 5
NUM_STAGES  = 7
MEAL_MEAT   = 1             ; 力 +3
MEAL_ROOT   = 2             ; 守 +3
MEAL_DEW    = 3             ; 慈力の回復が速い
MARK_MAX    = 3
CHART_MAX   = 3             ; カルテが完成するまでの崩壊回数
NUM_ROWS    = 6             ; 支度メニューの行数 (窓に見えるのは 4 行)
NUM_AMULETS = 7             ; なし + 6
AMB_FORGE   = 1 << 1        ; 鍛冶屋の前掛け: 守 +3
AMB_APRON   = 1 << 2        ; 母の割烹着: 母の受ける傷 3/4
AMB_SHOES   = 1 << 3        ; 軽業の靴: 回避 1.25 倍
AMB_PATCH   = 1 << 4        ; 見切りの眼帯: ジャスト回避 +2F、無敵 −2F
AMB_GLOVE   = 1 << 5        ; 父の手袋: 溜めが速い
AMB_QUICK   = 1 << 6        ; 早口の護符: 詠唱が速い

RecalcStats:
    .a8
    ; 熟練 Lv
    ldx #$0000
@mq:
    phx
    rep #$20
    txa
    asl a
    tax
    lda mq_exp,x
    ldy #$0000
@lvl:
    iny
    iny
    cpy #$000A
    bcs @got
    cmp mq_need,y
    bcs @lvl
@got:
    tya
    lsr a
    sep #$20
    plx
    sta mq_lv,x
    inx
    cpx #$0003
    bne @mq
    ; カルテ: 完成数 → 過治癒の量 (30 + 3 × 完成数)
    stz chart_done
    ldx #$0001
@ch:
    lda chart,x
    cmp #CHART_MAX
    bcc :+
    inc chart_done
:   inx
    cpx #NUM_TYPES
    bne @ch
    lda chart_done
    asl a
    clc
    adc chart_done
    clc
    adc #OVER_AMOUNT
    sta over_amt
    ; 力 = 10 + 見切り印の合計 ÷ 3 (+ 献立)
    jsr MarksTotal
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
    ; 護符
    ldx am1
    lda am1
    rep #$20
    and #$00FF
    tax
    sep #$20
    lda bit_tbl8,x
    sta am_on
    lda am2
    rep #$20
    and #$00FF
    tax
    sep #$20
    lda bit_tbl8,x
    ora am_on
    and #$FE                ; bit0 = なし
    sta am_on
    and #AMB_FORGE
    beq :+
    lda #3
    sta p_def
:   lda #CHARGE_LV1
    sta ch_lv1
    lda #CHARGE_LV2
    sta ch_lv2
    lda am_on
    and #AMB_GLOVE
    beq :+
    lda #30
    sta ch_lv1
    lda #70
    sta ch_lv2
:   lda #HEAL_TIME
    sta cast_heal
    lda #OVER_TIME
    sta cast_over
    lda am_on
    and #AMB_QUICK
    beq :+
    lda #HEAL_TIME*4/5
    sta cast_heal
    lda #OVER_TIME*4/5
    sta cast_over
:   lda meal
    cmp #MEAL_MEAT
    bne :+
    lda p_str
    clc
    adc #3
    sta p_str
:   lda meal
    cmp #MEAL_ROOT
    bne :+
    lda p_def
    clc
    adc #3
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
    cmp #NUM_SWORDS
    bcc :+
    lda #0
:   sta t1
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

; A = いまの護符, t0 = もう一方の護符 → A = 次の護符 (なし を含めて回る)
NextAmulet:
    .a8
    sta t1
    stz t1+1
@loop:
    lda t1
    inc a
    cmp #NUM_AMULETS
    bcc :+
    lda #0
:   sta t1
    beq @ok                 ; なし はいつでも
    cmp t0
    beq @loop
    ldx t1
    lda am_own
    and bit_tbl8,x
    beq @loop
@ok:
    lda t1
    rts

; ---- 焚き火の支度メニュー ---------------------------------------------------
PrepMenu:
    .a8
    stz menu_cur
    stz menu_top
    jsr MenuRedraw
    jsr PrepHelp
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
    bpl :+                  ; 端で反対側へ回る
    lda #NUM_ROWS-1
:   cmp #NUM_ROWS
    bcc :+
    lda #0
:   pha
    lda menu_cur
    sta menu_line
    pla
    sta menu_cur
    jsr PrepHelp
    jsr MenuScroll          ; 見えない行へ動いたら描き直す
    bcs @loop
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
    cmp #4
    beq @am1
    cmp #5
    beq @am2
    lda kit                 ; 薬箱
    inc a
    and #$03
    sta kit
    bra @redraw
@exit:
    jsr RecalcStats
    jsr RefillKit
    stz pad_new
    stz pad_new+1
    jmp WinClose
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
    bra @redraw
@am1:
    lda am2
    sta t0
    lda am1
    jsr NextAmulet
    sta am1
    bra @redraw
@am2:
    lda am1
    sta t0
    lda am2
    jsr NextAmulet
    sta am2
@redraw:
    lda #SE_DENY
    jsr PlaySe
    lda menu_cur
    jsr MenuLine
    jmp @loop

; 窓を開き直し、menu_top から 4 行描く
MenuRedraw:
    .a8
    jsr WinOpen
    lda menu_top
    sta t3+1
@l:
    lda t3+1
    jsr MenuLine
    inc t3+1
    lda t3+1
    sec
    sbc menu_top
    cmp #4
    bcc @l
    ; 窓の右の枠に、上下にまだ行があることを ▲▼ で示す
    rep #$20
    lda #WIN_ADDR + 1*32 + 30
    sta vq
    lda #WIN_ADDR + 8*32 + 30
    sta vq+6
    lda #79 | $2000         ; 枠 (縦線)
    sta vq+2
    sta vq+8
    lda #$2000
    sta vq+4
    sta vq+10
    sep #$20
    lda menu_top
    beq :+
    rep #$20
    lda #UI_ARROW_U | (($20 | (UP_GOLD << 2)) << 8)
    sta vq+2
    sep #$20
:   lda menu_top
    clc
    adc #4
    cmp #NUM_ROWS
    bcs :+
    rep #$20
    lda #UI_ARROW_D | (($20 | (UP_GOLD << 2)) << 8)
    sta vq+8
    sep #$20
:   lda #$01
    sta vq_n
    jmp WaitFrame

; カーソルが窓の外に出たら menu_top を動かして描き直し、キャリーを立てる
MenuScroll:
    .a8
    lda menu_cur
    cmp menu_top
    bcc @up
    sec
    sbc menu_top
    cmp #4
    bcs @down
    clc
    rts
@up:
    lda menu_cur
    sta menu_top
    bra @re
@down:
    lda menu_cur
    sec
    sbc #3
    sta menu_top
@re:
    jsr MenuRedraw
    sec
    rts

; A = 行。窓に見えている行ならキャリーを立てる
MenuVisible:
    .a8
    sec
    sbc menu_top
    cmp #4
    bcs @no
    sec
    rts
@no:
    clc
    rts

; A = 行。行頭のカーソルだけ書く
MenuCursor:
    .a8
    sta menu_line
    jsr MenuVisible
    bcs :+
    rts
:   jsr MenuAddr
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
    pha
    jsr MenuVisible
    pla
    bcs :+
    rts
:   jsr MenuCursor
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
    cmp #4
    beq @x1
    cmp #5
    beq @x2
    lda meal
    clc
    adc #SCR_MEAL0
    jmp DrawLine
@k:
    lda kit
    clc
    adc #SCR_KIT0
    jmp DrawLine
@x1:
    lda am1
    clc
    adc #SCR_AM0
    jmp DrawLine
@x2:
    lda am2
    clc
    adc #SCR_AM0
    jmp DrawLine

; menu_line の行頭の VRAM 番地を txt_addr に
MenuAddr:
    .a8
    rep #$20
    lda menu_line
    sec
    sbc menu_top
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
    stz pause_pg
PauseDraw:
    stz pad_new
    stz pad_new+1
    jsr WinOpen
    stz menu_cur
    stz menu_top
    jsr PauseHelp
    lda pause_pg
    beq :+
    jmp PausePage2
:   jsr PauseTac
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
    jsr MarksTotal
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
PauseLoop:
@loop:
    stz pad_new
    stz pad_new+1
    jsr WaitFrame
    jsr ReadPad
    lda pad_new+1
    and #$90                ; B / START で閉じる
    bne @exit
    lda pad_new+1
    and #$0C                ; 上下でページを替える
    beq :+
    lda pause_pg
    eor #$01
    sta pause_pg
    jmp PauseDraw
:   lda pause_pg
    bne @loop
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
    jsr PauseHelp
    bra @loop
@exit:
    stz pad_new
    stz pad_new+1
    jmp WinClose

; 2 ページ目: 熟練とカルテ
PausePage2:
    .a8
    ldx #$0000
@l:
    phx
    txa
    sta menu_line
    jsr MenuAddr
    plx
    phx
    txa
    clc
    adc #SCR_Q_L0
    jsr DrawLine
    plx
    phx
    lda mq_lv,x
    jsr PutNum
    plx
    inx
    cpx #$0003
    bne @l
    lda #3
    sta menu_line
    jsr MenuAddr
    lda #SCR_Q_L3
    jsr DrawLine
    lda chart_done
    jsr PutNum
    lda #SCR_Q_OF4
    jsr DrawLine
    jmp PauseLoop

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
    lda #$FFFF              ; 下の帯は窓で消えたので、描き直させる
    sta prompt_cur
    sep #$20
    stz toast_t
    jsr HelpClear
    jmp WaitFrame

; 支度メニューの説明 (選んでいる行) と操作
PrepHelp:
    .a8
    lda menu_cur
    asl a
    rep #$20
    and #$00FF
    tax
    lda prep_desc,x
    sta up
    lda #.loword(US_N_PREP)
    sta up2
    sep #$20
    jmp HelpShow

prep_desc: .word .loword(US_D_SWA), .loword(US_D_SWB), .loword(US_D_MEAL), .loword(US_D_KIT)
           .word .loword(US_D_AM), .loword(US_D_AM)

; 一時停止の説明と操作
PauseHelp:
    .a8
    lda pause_pg
    bne @p2
    lda m_tac
    asl a
    rep #$20
    and #$00FF
    tax
    lda tac_desc,x
    sta up
    lda #.loword(US_N_PAUSE1)
    sta up2
    sep #$20
    jmp HelpShow
@p2:
    rep #$20
    lda #.loword(US_D_PG2)
    sta up
    lda #.loword(US_N_PAUSE2)
    sta up2
    sep #$20
    jmp HelpShow

tac_desc: .word .loword(US_D_TAC0), .loword(US_D_TAC1), .loword(US_D_TAC2)

; A = 見切り印の合計
MarksTotal:
    .a8
    lda #0
    ldx #$0001
@l:
    clc
    adc marks,x
    inx
    cpx #NUM_TYPES
    bne @l
    rts

; ---- 熟練 ------------------------------------------------------------------
; Y = 段 → X = 熟練の種類 (連斬 0 / 溜め斬り 1 / 返し刃 2)
StageGroup:
    .a8
    lda stage_group,y
    rep #$20
    and #$00FF
    tax
    sep #$20
    rts

; Y = 段。t3 (16bit) に Lv × 1/16 を足す。X は保存
MasteryBoost:
    .a8
    phx
    jsr StageGroup
    lda mq_lv,x
    dec a
    beq @done
    sta t1
    stz t1+1
    rep #$20
    lda t3
    lsr a
    lsr a
    lsr a
    lsr a
    sta t2
@add:
    lda t3
    clc
    adc t2
    sta t3
    dec t1
    bne @add
    sep #$20
@done:
    plx
    rts

; Y = 段, X = 当たった敵。敵の格だけ経験。Lv が上がったら知らせる
MasteryGain:
    .a8
    lda d_type,x
    rep #$20
    and #$00FF
    phx
    tax
    lda e_grade,x
    and #$00FF
    sta t1
    sep #$20
    jsr StageGroup
    lda mq_lv,x
    sta t2
    rep #$20
    txa
    asl a
    tax
    lda mq_exp,x
    clc
    adc t1
    cmp #9999
    bcc :+
    lda #9999
:   sta mq_exp,x
    sep #$20
    phy
    jsr RecalcStats
    ply
    plx
    phx
    jsr StageGroup
    lda mq_lv,x
    plx
    cmp t2
    beq @same
    TOAST US_T_MQ
    lda #SE_JUST            ; 熟練 Lv が上がった
    jsr PlaySe
    lda p_x+1
    sta fx_ax
    lda p_y+1
    sec
    sbc #24
    sta fx_ay
    lda #PAL_HEAL
    sta fx_p
    jsr SpawnFx
@same:
    rts

; ---- 母のカルテ --------------------------------------------------------------
; X = 崩壊した敵。その種のカルテに 1 行
ChartWrite:
    .a8
    phx
    lda d_type,x
    rep #$20
    and #$00FF
    tax
    sep #$20
    lda chart,x
    cmp #CHART_MAX
    bcs :+
    inc a
    sta chart,x
    cmp #CHART_MAX
    bne @nc
    TOAST US_T_CHART3
@nc:
    jsr RecalcStats
:   plx
    rts

;               1   2    3    4    5
mq_need:  .word 0, 40, 120, 300, 600    ; Lv に必要な経験
stage_group: .byte 0, 0, 0, 0, 2, 1, 1  ; 段 → 熟練の種類
e_grade:  .byte 0, 1, 1, 2, 3, 2, 1, 1, 2, 4   ; 敵の格 (経験の量)

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
    asl a
    rep #$20
    and #$00FF
    tax
    lda med_sel_msg,x
    sta toast_req
    sep #$20
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
    bne :+
    TOAST US_T_NOMED
    bra @deny
:   cpx #1
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
    bcs @notneed
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
    beq @notneed
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
    TOAST US_T_USED
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
@notneed:
    TOAST US_T_NOUSE
@deny:
    lda #SE_DENY
    jmp PlaySe

med_sel_msg: .word .loword(US_T_SEL0), .loword(US_T_SEL1), .loword(US_T_SEL2)

;            傷薬3慈1  傷2慈2  傷2気2  傷4
kit_h:   .byte 3,       2,      2,      4
kit_j:   .byte 1,       2,      0,      0
kit_r:   .byte 0,       0,      2,      0
med_letter: .byte 18, 20, 28          ; HUD フォントの H / J / R

;             鉄塊「暁」 鉄塊「宵」 苔断ち  水車の鉄軸
sw_atk:  .byte 12,        10,        16,     22,     20     ; 最後は 角折り
sw_wt:   .byte 4,         4,         4,      8,      5
sw_flag: .byte 0,         0,         1,      0,      0      ; bit0 = 繁り特効
bit_tbl:
bit_tbl8: .byte 1, 2, 4, 8, 16, 32, 64, 128
; 段ごとに使う手: bit0 = 暁手, bit1 = 宵手
stage_hand: .byte 1, 2, 1, 3, 2, 3, 3
; 重さ合計 〜8 / 9〜12 / 13〜16 / 17〜 の、発生フレームの増減
weight_off: .byte <-2, 0, 3, 5
