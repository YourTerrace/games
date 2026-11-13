; ============================================================================
;  部屋・会話・焚き火・セーブ・タイトル (M3)
;  部屋は1画面固定。画面端の切れ目から隣へ移る (暗転切替)。
;  会話や暗転は「その場で待つ」作りで、終わるまでゲームは止まる。
; ============================================================================
WIN_ADDR    = VRAM_BG3_MAP + 18*32      ; 会話窓 (10 行)
TXT_ORG     = VRAM_BG3_MAP + 19*32 + 2  ; 1 行目の左上
WIN_BYTES   = 640
C_END       = $FF
C_NL        = $FE
C_PAGE      = $FD
NUM_ITEMS   = 8
SRAM        = $700000

; 1 フレーム待つ (その間に NMI が OAM・HUD・予約した VRAM 書き込みを反映する)
WaitFrame:
    .a8
    lda #$01
    sta nmi_ready
    lda vbl_count
:   wai
    cmp vbl_count
    beq :-
    rts

; 決定系のボタン (A / B / Y / START) が押されるまで待つ
WaitButton:
    .a8
    stz pad_new
    stz pad_new+1
@loop:
    jsr WaitFrame
    jsr ReadPad
    lda pad_new+1
    and #$D0
    bne @ok
    lda pad_new
    bpl @loop
@ok:
    stz pad_new
    stz pad_new+1
    rts

FadeOut:
    .a8
@loop:
    lda bright
    beq @done
    dec bright
    jsr WaitFrame
    bra @loop
@done:
    rts

FadeIn:
    .a8
@loop:
    lda bright
    cmp #$0F
    bcs @done
    inc bright
    jsr WaitFrame
    bra @loop
@done:
    rts

; ---- 当たり判定 -------------------------------------------------------------
; cx, cy (ピクセル) が通れないマスならキャリーを立てる。X, Y は保存
SolidAt:
    .a8
    phx
    rep #$20
    lda cy
    and #$00F0
    sta t3
    lda cx
    and #$00FF
    lsr a
    lsr a
    lsr a
    lsr a
    clc
    adc t3
    tax
    sep #$20
    lda col_map,x
    cmp #$01
    plx
    rts

; 主人公の足元の四隅のどれかが壁ならキャリーを立てる
PlayerBlocked:
    .a8
    lda p_x+1
    sec
    sbc #5
    sta cx
    lda p_y+1
    sec
    sbc #3
    sta cy
    jsr SolidAt
    bcs @yes
    lda p_x+1
    clc
    adc #5
    sta cx
    jsr SolidAt
    bcs @yes
    lda p_y+1
    clc
    adc #3
    sta cy
    jsr SolidAt
    bcs @yes
    lda p_x+1
    sec
    sbc #5
    sta cx
    jsr SolidAt
@yes:
    rts

; X = 敵。動かす前の位置を覚える / 壁にめり込んだら戻して止める
EnemySavePos:
    .a8
    rep #$20
    lda d_x,x
    sta oe_x
    lda d_y,x
    sta oe_y
    sep #$20
    rts

EnemyClip:
    .a8
    lda d_x+1,x
    sta cx
    lda d_y+1,x
    sta cy
    jsr SolidAt
    bcc @ok
    lda oe_x+1              ; 元いた場所も壁なら (埋まっている) そのまま動かして抜けさせる
    sta cx
    lda oe_y+1
    sta cy
    jsr SolidAt
    bcs @ok
    rep #$20
    lda oe_x
    sta d_x,x
    lda oe_y
    sta d_y,x
    stz d_vx,x
    stz d_vy,x
    sep #$20
@ok:
    rts

; ---- 部屋 -------------------------------------------------------------------
; A = 部屋番号。画面は消したまま読み込む (呼び出し側でフェードイン)
LoadRoom:
    .a8
    sta room
    stz nmi_ready
    lda #$80
    sta $2100
    rep #$20
    lda room
    and #$00FF
    asl a
    tax
    lda room_tbl,x
    sta rp
    sep #$20
    ldy #$0000
    lda (rp),y              ; スプライト集
    cmp cur_set
    beq :+
    sta cur_set
    jsr LoadSet
:   ldy #$0001
    ldx #$0000
@exits:
    lda (rp),y
    sta room_exit,x
    iny
    inx
    cpx #$0006              ; 出入口4つ + 入室時の台本 + 曲
    bne @exits
    lda room_music
    jsr PlayMusic
    ; タイルマップ
    rep #$20
    lda (rp),y
    clc
    adc #.loword(RoomMaps)
    sta $4302
    sep #$20
    iny
    iny
    lda #$80
    sta $2115
    ldx #VRAM_BG1_MAP
    stx $2116
    lda #$01
    sta $4300
    lda #$18
    sta $4301
    lda #^RoomMaps
    sta $4304
    ldx #$0800
    stx $4305
    lda #$01
    sta $420B
    ; 当たり (16x14)。その下は壁扱い
    ldx #$0000
@col:
    lda (rp),y
    sta col_map,x
    iny
    inx
    cpx #224
    bne @col
    lda #$01
@pad:
    sta col_map,x
    inx
    cpx #256
    bne @pad
    ; 敵・置物を空に
    ldx #$0000
@clr:
    stz d_type,x
    inx
    inx
    cpx #DUMMY_END
    bne @clr
    ldx #$0000
@clr2:
    stz it_kind,x
    inx
    cpx #NUM_ITEMS
    bne @clr2
    ldx #$0000
@clr3:
    stz fx_t,x
    inx
    cpx #NUM_FX
    bne @clr3
    ldx #$0000
@clr4:
    stz sh_t,x
    inx
    inx
    cpx #NUM_SHOT*2
    bne @clr4
    ; 配置物: 種類, X, Y, a, b
@obj:
    lda (rp),y
    bne :+
    rts
:   sta t3                  ; 種類
    iny
    lda (rp),y
    sta t1
    iny
    lda (rp),y
    sta t2
    iny
    lda (rp),y
    sta bi                  ; a
    iny
    lda (rp),y
    sta bj                  ; b
    iny
    lda t3
    cmp #O_ENEMY
    bne @item
    lda bi
    cmp #TYPE_BOSS
    bne :+
    lda boss_dead           ; 倒したボスは出さない
    bne @obj
:   phy
    lda bi
    jsr SpawnEnemy
    ply
    bra @obj
@item:
    ldx #$0000
@find:
    lda it_kind,x
    beq @put
    inx
    cpx #NUM_ITEMS
    bne @find
    bra @obj
@put:
    lda t3
    sta it_kind,x
    lda t1
    sta it_x,x
    sta cx
    lda t2
    sta it_y,x
    sta cy
    lda bi
    sta it_a,x
    lda bj
    sta it_b,x
    lda t3                  ; 村人の立っているマスは通れない
    cmp #O_NPC
    bne @obj
    phx
    rep #$20
    lda cy
    and #$00F0
    sta t3
    lda cx
    and #$00FF
    lsr a
    lsr a
    lsr a
    lsr a
    clc
    adc t3
    tax
    sep #$20
    lda #$01
    sta col_map,x
    plx
    jmp @obj

; cur_set のスプライト 8 枚ぶんとパレットを読み込む (画面オフ中に呼ぶ)
LoadSet:
    .a8
    lda #$80
    sta $2115
    ldx #VRAM_OBJ_CHR + 384*16
    stx $2116
    lda #$01
    sta $4300
    lda #$18
    sta $4301
    ldx #.loword(SetChr)
    stx $4302
    lda cur_set             ; 1 集 = $1000 バイト
    asl a
    asl a
    asl a
    asl a
    clc
    adc $4303
    sta $4303
    lda #^SetChr
    sta $4304
    ldx #$1000
    stx $4305
    lda #$01
    sta $420B
    lda #192                ; OBJ パレット4
    sta $2121
    stz $4300
    lda #$22
    sta $4301
    rep #$20
    lda cur_set
    and #$00FF
    asl a
    asl a
    asl a
    asl a
    asl a
    clc
    adc #.loword(SetPal)
    sta $4302
    sep #$20
    lda #^SetPal
    sta $4304
    ldx #32
    stx $4305
    lda #$01
    sta $420B
    rts

; A = 行き先の部屋。主人公の位置は呼び出し側で決めておく
ChangeRoom:
    .a8
    pha
    stz p_state
    stz p_charge
    stz p_just
    stz hitstop
    stz dim_t
    stz m_state
    jsr FadeOut
    pla
    jsr LoadRoom
    rep #$20
    lda p_x
    sta m_x
    lda p_y
    sta m_y
    sep #$20
    lda p_x+1               ; 母は左隣に (壁ならいったん同じ場所)
    sec
    sbc #18
    sta cx
    lda p_y+1
    sta cy
    jsr SolidAt
    bcs :+
    lda cx
    sta m_x+1
:   jsr SetRestSwords
    lda swA_ang
    sta swA_prev
    lda swB_ang
    sta swB_prev
    jsr DrawAll
    jsr BuildHud
    jsr FadeIn
    lda room_enter          ; 初めて入った時の会話
    bmi @done
    rep #$20
    lda room
    and #$00FF
    tax
    sep #$20
    lda seen,x
    bne @done
    lda #$01
    sta seen,x
    lda room_enter
    jsr ShowScript
@done:
    stz pad_new
    stz pad_new+1
    rts

; 画面端の切れ目に来たら隣の部屋へ
CheckExits:
    .a8
    lda p_y+1
    cmp #30
    bcs @down
    lda room_exit
    bmi @none
    pha
    lda #212
    sta p_y+1
    pla
    jmp ChangeRoom
@down:
    cmp #219
    bcc @left
    lda room_exit+1
    bmi @none
    pha
    lda #36
    sta p_y+1
    pla
    jmp ChangeRoom
@left:
    lda p_x+1
    cmp #6
    bcs @right
    lda room_exit+2
    bmi @none
    pha
    lda #244
    sta p_x+1
    pla
    jmp ChangeRoom
@right:
    cmp #250
    bcc @none
    lda room_exit+3
    bmi @none
    pha
    lda #10
    sta p_x+1
    pla
    jmp ChangeRoom
@none:
    rts

; ---- 調べる・話す ----------------------------------------------------------
; 近くに話せる相手や焚き火があれば処理してキャリーを立てる
TryInteract:
    .a8
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
    clc
    rts
@found:
    lda it_kind,x
    cmp #O_FIRE
    beq @fire
    cmp #O_CHEST
    bne @talk
    lda it_a,x              ; 箱: 剣が入っていれば手に入れる
    rep #$20
    and #$00FF
    tay
    sep #$20
    lda own
    and bit_tbl,y
    bne @empty
    lda own
    ora bit_tbl,y
    sta own
    lda #SE_JUST
    jsr PlaySe
@talk:
    lda it_b,x
    jsr ShowScript
    sec
    rts
@empty:
    lda #SCR_EMPTY
    jsr ShowScript
    sec
    rts
@fire:
    ; 焚き火: 全快して記録。敵は元に戻る
    lda it_b,x
    pha
    rep #$20
    lda #HP_MAX
    sta p_hp
    stz m_down
    sep #$20
    lda #MOM_HP_MAX
    sta m_hp
    lda #100
    sta m_ji
    lda room
    sta chk_room
    lda p_x+1
    sta chk_x
    lda p_y+1
    sta chk_y
    lda #SE_HEAL
    jsr PlaySe
    jsr BuildHud
    pla
    jsr ShowScript
    jsr PrepMenu
    jsr SaveGame
    lda room
    jsr ChangeRoom
    sec
    rts

DrawNpcs:
    .a8
    ldx #$0000
@loop:
    lda it_kind,x
    cmp #O_NPC
    bne @next
    phx
    rep #$20
    lda it_a,x
    and #$00FF
    asl a
    tay
    sep #$20
    lda npc_frame_tbl,y
    sta spr_tile
    lda npc_frame_tbl+1,y
    ora #(PAL_ENEMY | PRIO)
    sta spr_attr
    lda #$02
    sta spr_size
    rep #$20
    lda it_x,x
    and #$00FF
    sec
    sbc #16
    sta spr_x
    lda it_y,x
    and #$00FF
    sec
    sbc #26
    sta spr_y
    sep #$20
    jsr AddSprite
    plx
@next:
    inx
    cpx #NUM_ITEMS
    bne @loop
    rts

; ---- 会話 -------------------------------------------------------------------
; A = 文字番号。txt_addr の位置に 1 字 (2x2 タイル) 書いて 1 フレーム待つ
PutGlyph:
    .a8
    rep #$20
    and #$00FF
    asl a
    asl a
    clc
    adc #(GLYPH_BASE | $2000)
    sta vq+2
    inc a
    sta vq+4
    inc a
    sta vq+8
    inc a
    sta vq+10
    lda txt_addr
    sta vq
    clc
    adc #32
    sta vq+6
    lda txt_addr
    inc a
    inc a
    sta txt_addr
    sep #$20
    lda #$01
    sta vq_n
    jmp WaitFrame

; 会話窓を (中身ごと) 描き直す
WinOpen:
    .a8
    rep #$20
    lda #.loword(WindowMap)
    sta vd_src
    lda #WIN_ADDR
    sta vd_dst
    lda #WIN_BYTES
    sta vd_len
    sep #$20
    jmp WaitFrame

; A = 台本番号。窓を開き、1 字ずつ表示し、ページごとにボタンを待つ
ShowScript:
    .a8
    rep #$20
    and #$00FF
    asl a
    tax
    lda script_tbl,x
    sta scp
    sep #$20
@page:
    jsr WinOpen
    rep #$20
    lda #TXT_ORG
    sta txt_line
    sta txt_addr
    sep #$20
@char:
    lda (scp)
    rep #$20
    inc scp
    sep #$20
    cmp #C_END
    beq @end
    cmp #C_PAGE
    beq @next
    cmp #C_NL
    bne @glyph
    rep #$20
    lda txt_line
    clc
    adc #64
    sta txt_line
    sta txt_addr
    sep #$20
    bra @char
@glyph:
    jsr PutGlyph
    bra @char
@next:
    jsr WaitButton
    bra @page
@end:
    jsr WaitButton
    rep #$20
    lda #.loword(BlankMap)
    sta vd_src
    lda #WIN_ADDR
    sta vd_dst
    lda #WIN_BYTES
    sta vd_len
    sep #$20
    jmp WaitFrame

; A = 台本番号。txt_addr から 1 行だけ窓なしで書く (タイトル用)
DrawLine:
    .a8
    rep #$20
    and #$00FF
    asl a
    tax
    lda script_tbl,x
    sta scp
    sep #$20
@char:
    lda (scp)
    rep #$20
    inc scp
    sep #$20
    cmp #C_END
    beq @done
    jsr PutGlyph
    bra @char
@done:
    rts

; ---- セーブ (バッテリーバックアップ) ----------------------------------------
;  +0 'C' +1 'E' +2 部屋 +3 X +4 Y +5 ボス撃破 +6..13 入室済み
;  +14 暁手 +15 宵手 +16 献立 +17 持っている剣 +18..21 見切り印(種別1-4) +22 薬箱 +23 検査用の和
SaveGame:
    .a8
    lda #'C'
    sta f:SRAM
    lda #'E'
    sta f:SRAM+1
    lda chk_room
    sta f:SRAM+2
    lda chk_x
    sta f:SRAM+3
    lda chk_y
    sta f:SRAM+4
    lda boss_dead
    sta f:SRAM+5
    ldx #$0000
@seen:
    lda seen,x
    sta f:SRAM+6,x
    inx
    cpx #$0008
    bne @seen
    lda eqA
    sta f:SRAM+14
    lda eqB
    sta f:SRAM+15
    lda meal
    sta f:SRAM+16
    lda own
    sta f:SRAM+17
    ldx #$0000
@mk:
    lda marks+1,x
    sta f:SRAM+18,x
    inx
    cpx #$0004
    bne @mk
    lda kit
    sta f:SRAM+22
    jsr SaveSum
    sta f:SRAM+23
    rts

SaveSum:
    .a8
    ldx #$0000
    lda #$5A
@loop:
    clc
    adc f:SRAM+2,x
    inx
    cpx #21
    bne @loop
    rts

; 正しい記録があればキャリーを立てる
HasSave:
    .a8
    lda f:SRAM
    cmp #'C'
    bne @no
    lda f:SRAM+1
    cmp #'E'
    bne @no
    jsr SaveSum
    cmp f:SRAM+23
    bne @no
    sec
    rts
@no:
    clc
    rts

LoadGame:
    .a8
    lda f:SRAM+2
    sta chk_room
    lda f:SRAM+3
    sta chk_x
    lda f:SRAM+4
    sta chk_y
    lda f:SRAM+5
    sta boss_dead
    ldx #$0000
@seen:
    lda f:SRAM+6,x
    sta seen,x
    inx
    cpx #$0008
    bne @seen
    lda f:SRAM+14
    sta eqA
    lda f:SRAM+15
    sta eqB
    lda f:SRAM+16
    sta meal
    lda f:SRAM+17
    sta own
    lda f:SRAM+22
    sta kit
    stz marks
    ldx #$0000
@mk:
    lda f:SRAM+18,x
    sta marks+1,x
    inx
    cpx #$0004
    bne @mk
    rts

NewGame:
    .a8
    stz boss_dead
    stz eqA
    lda #1
    sta eqB
    stz meal
    lda #%0011
    sta own
    stz kit
    stz med_sel
    stz m_tac
    ldx #$0000
@mk:
    stz marks,x
    inx
    cpx #$0005
    bne @mk
    ldx #$0000
@seen:
    stz seen,x
    inx
    cpx #$0008
    bne @seen
    stz chk_room
    lda #START_X
    sta chk_x
    lda #START_Y
    sta chk_y
    rts

; ---- タイトル ---------------------------------------------------------------
T_TITLE = VRAM_BG3_MAP + 8*32 + 9
T_NEW   = VRAM_BG3_MAP + 15*32 + 11
T_CONT  = VRAM_BG3_MAP + 18*32 + 11
CURSOR  = (BAR_TILE + 8) | $2000

TitleScreen:
    .a8
    jsr FadeOut
    lda #$FF
    sta cur_set
    lda #$04                ; BG3 だけ表示
    sta $212C
    ldy #$0000
    sty oam_idx
    jsr FinishOam
    ldx #$0000
@hud:
    stz hud_buf,x
    inx
    cpx #128
    bne @hud
    jsr WaitFrame
    ldx #T_TITLE
    stx txt_addr
    lda #SCR_TITLE
    jsr DrawLine
    ldx #T_NEW
    stx txt_addr
    lda #SCR_T_NEW
    jsr DrawLine
    stz title_has
    stz title_sel
    jsr HasSave
    bcc :+
    inc title_has
    inc title_sel           ; 記録があれば「つづきから」を選んでおく
    ldx #T_CONT
    stx txt_addr
    lda #SCR_T_CONT
    jsr DrawLine
:   lda #BGM_VILLAGE
    jsr PlayMusic
    jsr FadeIn
    stz pad_new
    stz pad_new+1
@loop:
    ; カーソル
    rep #$20
    lda #T_NEW - 2
    sta vq
    lda #T_CONT - 2
    sta vq+6
    lda #$2000
    sta vq+2
    sta vq+4
    sta vq+8
    sta vq+10
    lda title_sel
    and #$00FF
    beq :+
    lda #CURSOR
    sta vq+8
    bra :++
:   lda #CURSOR
    sta vq+2
:   sep #$20
    lda #$01
    sta vq_n
    jsr WaitFrame
    jsr ReadPad
    lda title_has
    beq @nomove
    lda pad_new+1
    and #$0C                ; 上下
    beq @nomove
    lda title_sel
    eor #$01
    sta title_sel
    lda #SE_DENY
    jsr PlaySe
@nomove:
    lda pad_new+1
    and #$D0
    bne @go
    lda pad_new
    bmi @go
    stz pad_new
    stz pad_new+1
    bra @loop
@go:
    lda #SE_JUST
    jsr PlaySe
    jsr FadeOut
    rep #$20                ; 文字を消す (8-17 行、12-21 行)
    lda #.loword(BlankMap)
    sta vd_src
    lda #VRAM_BG3_MAP + 8*32
    sta vd_dst
    lda #WIN_BYTES
    sta vd_len
    sep #$20
    jsr WaitFrame
    rep #$20
    lda #.loword(BlankMap)
    sta vd_src
    lda #VRAM_BG3_MAP + 12*32
    sta vd_dst
    lda #WIN_BYTES
    sta vd_len
    sep #$20
    jsr WaitFrame
    lda #$15
    sta $212C
    lda title_sel
    beq :+
    jmp LoadGame
:   jmp NewGame

; ボスを倒した後: 会話 → 記録 → タイトルへ
BossDefeated:
    .a8
    stz ev_boss
    lda #$01
    sta boss_dead
    lda own                 ; 水車の鉄軸
    ora #%1000
    sta own
    ldx #$0000
@kill:
    stz d_type,x
    inx
    inx
    cpx #DUMMY_END
    bne @kill
    stz p_state
    jsr SetRestSwords
    jsr DrawAll
    ldx #60
@wait:
    phx
    jsr WaitFrame
    plx
    dex
    bne @wait
    lda #BGM_VILLAGE
    jsr PlayMusic
    lda #SCR_BOSS_OUT
    jsr ShowScript
    jsr SaveGame
    ldx #$1FFF              ; スタックを捨ててタイトルから
    txs
    jmp Restart
