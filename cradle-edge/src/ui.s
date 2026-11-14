; ============================================================================
;  画面の案内: 状態欄 (上 4 行)・お知らせ (下の帯)・操作の案内 (窓の上の帯)
;  文字とタイルは tools/gen_ui.py が作る (ui.inc)。1 字 = 2 バイト (タイル, 属性)。
; ============================================================================
HUD_ROW1    = 32*2*1
HUD_ROW2    = 32*2*2
HUD_ROW3    = 32*2*3
LOW_HELP    = 0             ; low_buf 内: 16 行目 (説明), 17 行目 (操作)
LOW_NAV     = 64
LOW_TOAST   = 128           ; 26 行目 (お知らせ)
TOAST_TIME  = 150
PANEL_W     = UI_PANEL | (($20 | (UP_TEXT << 2)) << 8)   ; 紺の帯
CLEAR_W     = $2000                                       ; 透明

; お知らせを頼む (その場では描かない。フレームの終わりにまとめて出す)

; ---- 文字列を書く -----------------------------------------------------------
; up = 文字列、X = 書く先 (hud_buf / low_buf 内のバイト位置)、ux = バッファの番地
; X は書き終えた次の位置になる
PutStr:
    .a8
    ldy #$0000
@l:
    lda (up),y
    cmp #$FF
    beq @done
    sta (ux)                ; ux は書く先の番地 (下で進める)
    iny
    lda (up),y
    phy
    ldy #$0001
    sta (ux),y
    ply
    iny
    rep #$20
    inc ux
    inc ux
    sep #$20
    inx
    inx
    bra @l
@done:
    rts

; X = hud_buf 内の位置、up = 文字列
HudStr:
    .a8
    rep #$20
    txa
    clc
    adc #hud_buf
    sta ux
    sep #$20
    jmp PutStr

; X = hud_buf 内の位置。A = 0-255 を全角 3 桁で (前の 0 は空白)
HudNum3:
    .a8
    sta $4204
    stz $4205
    lda #100
    sta $4206
    jsr DivWait
    lda $4216
    sta hn_rem
    stz hn_lead
    lda $4214
    jsr @dig
    lda hn_rem
    sta $4204
    stz $4205
    lda #10
    sta $4206
    jsr DivWait
    lda $4216
    sta hn_rem
    lda $4214
    jsr @dig
    lda #1                  ; 一の位はいつも数字
    sta hn_lead
    lda hn_rem
@dig:
    bne @num
    lda hn_lead             ; まだ数字が出ていない 0 は空白
    bne @zero
    lda #UI_SPACE
    bra @put
@zero:
    lda #0
@num:
    pha
    lda #1
    sta hn_lead
    pla
    clc
    adc #UI_D0
@put:
    sta hud_buf,x
    lda #($20 | (UP_TEXT << 2))
    sta hud_buf+1,x
    inx
    inx
    rts

; X = hud_buf 内の位置、A = マス数、t1 = 値 (1 マス = 10)、hb_pal = 色
; hb_hide が 0 でなければ、空のマスは描かない (過剰生命用)
HudBar:
    .a8
    sta t2
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
    bne @draw
    lda hb_hide
    beq @draw0
    rep #$20
    lda #PANEL_W
    sta hud_buf,x
    sep #$20
    bra @next
@draw0:
    lda #0
@draw:
    clc
    adc #UI_BAR0
    sta hud_buf,x
    lda hb_pal
    asl a
    asl a
    ora #$20
    sta hud_buf+1,x
@next:
    inx
    inx
    dec t2
    bne @cell
    rts

; ---- 状態欄 -----------------------------------------------------------------
BuildHud:
    .a8
    ; 1-3 行目を紺で塗る
    rep #$20
    ldx #HUD_ROW1
    lda #PANEL_W
@clr:
    sta hud_buf,x
    inx
    inx
    cpx #HUD_ROW3 + 64
    bne @clr
    sep #$20
    ; 1 行目: グレン ＨＰ ████ 数字
    ldx #HUD_ROW1 + 1*2
    ldy #.loword(US_H_GLEN)
    sty up
    jsr HudStr
    ldy #.loword(US_H_HP)
    sty up
    ldx #HUD_ROW1 + 5*2
    jsr HudStr
    rep #$20
    lda p_hp
    sta t1
    sep #$20
    stz hb_hide
    lda #UP_HP
    sta hb_pal
    ldx #HUD_ROW1 + 8*2
    lda #10
    jsr HudBar
    lda #UP_GOLD            ; 過剰生命 (最大を超えた分) は金色で、ある分だけ
    sta hb_pal
    inc hb_hide
    lda #5
    jsr HudBar
    lda p_hp
    ldx #HUD_ROW1 + 24*2
    jsr HudNum3
    ; 2 行目: ミレイユ ＨＰ ███  ＭＰ ████
    ldy #.loword(US_H_MOM)
    sty up
    ldx #HUD_ROW2 + 1*2
    jsr HudStr
    ldy #.loword(US_H_HP)
    sty up
    ldx #HUD_ROW2 + 6*2
    jsr HudStr
    lda m_down
    ora m_down+1
    beq @mom_up
    lda tick                ; 倒れている時は赤い字で点滅
    and #$10
    beq @mom_mp
    ldy #.loword(US_H_DOWN)
    sty up
    ldx #HUD_ROW2 + 8*2
    jsr HudStr
    bra @mom_mp
@mom_up:
    lda m_hp
    sta t1
    stz t1+1
    stz hb_hide
    lda #UP_HP
    sta hb_pal
    ldx #HUD_ROW2 + 8*2
    lda #7
    jsr HudBar
@mom_mp:
    ldy #.loword(US_H_MP)
    sty up
    ldx #HUD_ROW2 + 16*2
    jsr HudStr
    lda m_ji
    sta t1
    stz t1+1
    stz hb_hide
    lda #UP_MP
    sta hb_pal
    ldx #HUD_ROW2 + 18*2
    lda #10
    jsr HudBar
    ; 3 行目右: Ｌ くすりの名前 ×数
    ldy #.loword(US_H_L)
    sty up
    ldx #HUD_ROW3 + 21*2
    jsr HudStr
    lda med_sel
    asl a
    rep #$20
    and #$00FF
    tay
    lda us_med,y
    sta up
    sep #$20
    ldx #HUD_ROW3 + 23*2
    jsr HudStr
    lda #UI_TIMES
    sta hud_buf + HUD_ROW3 + 29*2
    lda #($20 | (UP_TEXT << 2))
    sta hud_buf + HUD_ROW3 + 29*2 + 1
    sta hud_buf + HUD_ROW3 + 30*2 + 1
    lda med_sel
    rep #$20
    and #$00FF
    tax
    sep #$20
    lda med,x
    clc
    adc #UI_D0
    sta hud_buf + HUD_ROW3 + 30*2
    ; 3 行目左: 母が狙う敵 (X の相手) の名前・体力・飽和
    jsr FindNearest
    bcs :+
    rep #$20
    lda #$FFFF
    sta hud_tgt
    sep #$20
    rts
:   ldx near_idx
    stx hud_tgt
    lda d_type,x
    asl a
    rep #$20
    and #$00FF
    tay
    lda us_enemy,y
    sta up
    sep #$20
    phx
    ldx #HUD_ROW3 + 1*2
    jsr HudStr
    plx
    ; 体力 6 マス: hp × 60 ÷ 最大 hp (割る数を 8 ビットに収めるため両方ずらす)
    rep #$20
    lda d_hp,x
    sta t1
    lda d_maxhp,x
    sta t2
    jsr Scale60
    sta t1
    sep #$20
    stz hb_hide
    lda #UP_RED
    sta hb_pal
    phx
    ldx #HUD_ROW3 + 8*2
    lda #6
    jsr HudBar
    plx
    lda #UI_CROSS           ; 飽和 5 マス
    sta hud_buf + HUD_ROW3 + 15*2
    lda #($20 | (UP_SAT << 2))
    sta hud_buf + HUD_ROW3 + 15*2 + 1
    rep #$20
    lda d_sat,x
    sta t1
    lda d_satmax,x
    sta t2
    jsr Scale50
    sta t1
    sep #$20
    lda #UP_SAT
    sta hb_pal
    ldx #HUD_ROW3 + 16*2
    lda #5
    jmp HudBar

; (A16) t1 / t2 を 60 倍 / 50 倍にした値 → A
Scale60:
    .a16
    lda #60
    bra Scale
Scale50:
    .a16
    lda #50
Scale:
    .a16
    sta t0
@shrink:
    lda t2
    cmp #$0100
    bcc @ok
    lsr t2
    lsr t1
    bra @shrink
@ok:
    lda t2
    bne :+
    lda #$0000
    rts
:   sep #$20
    lda t1
    sta $4202
    lda t0
    sta $4203
    nop
    nop
    nop
    nop
    rep #$20
    lda $4216
    sta $4204
    sep #$20
    lda t2
    sta $4206
    jsr DivWait
    rep #$20
    lda $4214
    rts

; ---- 狙っている敵の上に ▼ ---------------------------------------------------
DrawTarget:
    .a8
    ldx hud_tgt
    bmi @none
    lda d_type,x
    beq @none
    lda d_dead,x
    bne @none
    lda tick
    and #$10
    bne @none
    lda #SATBAR_TILE + 34
    sta spr_tile
    lda #(SATBAR_NAME | PAL_FX | PRIO | $10)
    sta spr_attr
    stz spr_size
    jsr TypeToY
    lda e_kind,y
    tay
    rep #$20
    lda d_x+1,x
    and #$00FF
    sec
    sbc #8
    sta spr_x
    lda d_y+1,x
    and #$00FF
    sec
    sbc tgt_dy,y
    sta spr_y
    sep #$20
    jmp AddSprite
@none:
    rts

tgt_dy: .word 52, 60, 84        ; 敵の大きさ (16 / 32 / 64) ごとの高さ

; ---- 下の帯 -----------------------------------------------------------------
; X = low_buf 内の位置から 1 行 (32 マス) を A16 の値で塗る
LowFill:
    .a16
    ldy #32
:   sta low_buf,x
    inx
    inx
    dey
    bne :-
    rts

; X = low_buf 内の行の頭、up = 文字列 (0 なら行を消す)
LowLine:
    .a8
    phx
    rep #$20
    lda up
    beq @clear
    lda #PANEL_W
    jsr LowFill
    sep #$20
    plx
    rep #$20
    txa
    clc
    adc #low_buf + 2*2      ; 左に 2 マス空ける
    sta ux
    sep #$20
    jmp PutStr
@clear:
    .a16
    lda #CLEAR_W
    jsr LowFill
    sep #$20
    plx
    rts

; 窓の上の帯: up = 説明 (0 で無し)、up2 = 操作
HelpShow:
    .a8
    ldx #LOW_HELP
    jsr LowLine
    rep #$20
    lda up2
    sta up
    sep #$20
    ldx #LOW_NAV
    jsr LowLine
    lda low_dirty
    ora #$01
    sta low_dirty
    rts

HelpClear:
    .a8
    rep #$20
    stz up
    stz up2
    sep #$20
    jmp HelpShow

; お知らせと「ここでできること」を毎フレーム整える (会話や窓の間は呼ばない)
UpdateToast:
    .a8
    rep #$20
    lda toast_req
    beq @no_req
    sta up
    stz toast_req
    sep #$20
    lda #TOAST_TIME
    sta toast_t
    rep #$20
    stz prompt_cur
    sep #$20
    bra @draw
@no_req:
    sep #$20
    lda toast_t
    beq @prompt
    dec toast_t
    bne @out
    rep #$20                ; 時間切れ: 消す
    stz up
    stz prompt_cur
    sep #$20
    bra @draw
@prompt:
    jsr NearPrompt          ; 近くの物に応じた案内 → up
    rep #$20
    lda up
    cmp prompt_cur
    beq @out16
    sta prompt_cur
    sep #$20
@draw:
    ldx #LOW_TOAST
    jsr LowLine
    lda low_dirty
    ora #$02
    sta low_dirty
@out:
    sep #$20
    rts
@out16:
    sep #$20
    rts

; 主人公の近くに調べられる物があれば、その案内の文字列を up に (無ければ 0)
NearPrompt:
    .a8
    rep #$20
    stz up
    sep #$20
    lda p_state
    bne @none
    ldx #$0000
@loop:
    lda it_kind,x
    beq @next
    lda it_x,x
    sec
    sbc p_x+1
    bcs :+
    eor #$FF
    inc a
:   cmp #24
    bcs @next
    lda it_y,x
    sec
    sbc p_y+1
    bcs :+
    eor #$FF
    inc a
:   cmp #28
    bcc @found
@next:
    inx
    cpx #NUM_ITEMS
    bne @loop
@none:
    rts
@found:
    lda it_kind,x
    asl a
    rep #$20
    and #$00FF
    tay
    lda prompt_tbl,y
    sta up
    sep #$20
    rts

;              -  敵 村人                 立て札                焚き火                 箱
prompt_tbl: .word 0, 0, .loword(US_P_TALK), .loword(US_P_READ), .loword(US_P_REST), .loword(US_P_OPEN), 0
