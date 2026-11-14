#!/usr/bin/env python3
"""画面の小さな文字 (状態欄・案内の帯・お知らせ) の文字タイルと文字列を作る。

美咲ゴシック (8x8) から、ここに書いた文字列に出てくる字だけをタイルにする。
BG3 (2bpp) のタイル 0-207 を使う (77-79 は会話窓の枠、208 以降は会話の字)。

出力 (build/):
  ui.chr     文字・ゲージ・記号のタイル
  ui.pal     BG3 のパレット 8 本 (CGRAM 0-31)
  hud.map    BG3 のタイルマップの初期値 (上 4 行が状態欄、残りは透明)
  ui.inc     タイル番号と文字列 (ca65)
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "build"
os.makedirs(OUT, exist_ok=True)
FONT = ImageFont.truetype("/usr/share/fonts/truetype/misaki/misaki_gothic.ttf", 8)


def bgr555(rgb):
    r, g, b = rgb
    return (r >> 3) | ((g >> 3) << 5) | ((b >> 3) << 10)


def tile2(px):
    out = bytearray()
    for y in range(8):
        b0 = b1 = 0
        for x in range(8):
            v = px[y][x]
            b0 = (b0 << 1) | (v & 1)
            b1 = (b1 << 1) | ((v >> 1) & 1)
        out += bytes((b0, b1))
    return bytes(out)


# ---------------------------------------------------------------- パレット
NAVY, WHITE, GOLD, GRAY = (16, 16, 40), (248, 248, 240), (255, 216, 72), (64, 64, 80)
PALS = [   # 色 0 は透明。色 2 は帯の地 (紺)
    [(16, 16, 40), WHITE, NAVY, GOLD],              # 0 ふつうの字 (色 0 = 背景色も紺に)
    [(0, 0, 0), (104, 224, 96), NAVY, GRAY],        # 1 体力 (緑)
    [(0, 0, 0), (96, 160, 255), NAVY, GRAY],        # 2 慈力 (青)
    [(0, 0, 0), GOLD, NAVY, GRAY],                  # 3 過剰生命 / 見出し (金)
    [(0, 0, 0), (240, 88, 64), NAVY, GRAY],         # 4 敵の体力 / 危ない (赤)
    [(0, 0, 0), (136, 248, 176), NAVY, GRAY],       # 5 飽和 (薄緑)
    [(0, 0, 0), (200, 200, 216), NAVY, GRAY],       # 6 控えめな字 (灰)
    [(0, 0, 0), WHITE, NAVY, GOLD],                 # 7 予備
]
P_TEXT, P_HP, P_MP, P_GOLD, P_RED, P_SAT, P_DIM = range(7)
open(f"{OUT}/ui.pal", "wb").write(
    b"".join(bytes((bgr555(c) & 0xFF, bgr555(c) >> 8)) for p in PALS for c in p))

# ---------------------------------------------------------------- 文字列
# 名前 → 文字列。{色} で以降の色を変えられる (例: "{gold}ＨＰ")
STRINGS = {
    # 状態欄
    "H_GLEN": "グレン", "H_MOM": "ミレイユ", "H_HP": "{gold}ＨＰ", "H_MP": "{gold}ＭＰ",
    "H_DOWN": "{red}たおれた", "H_L": "{gold}Ｌ",
    # 敵の名前 (種別の順)
    "EN0": "", "EN1": "コケネズミ", "EN2": "ツルヘビ", "EN3": "カカシ", "EN4": "スイシャバン",
    "EN5": "イノシシ", "EN6": "ハナバチ", "EN7": "ホウシダケ", "EN8": "バンケン", "EN9": "オオジカ",
    # 薬
    "MED0": "きずぐすり", "MED1": "じりきすい", "MED2": "きつけぐすり",
    # 近くにある物で、できること
    "P_TALK": "{gold}Ｙ{text}：はなす", "P_REST": "{gold}Ｙ{text}：たきびで やすむ・したくする",
    "P_OPEN": "{gold}Ｙ{text}：はこを あける", "P_READ": "{gold}Ｙ{text}：たてふだを よむ",
    # お知らせ
    "T_MARK": "みきりじるし{gold}＋１{text}　ひきつけて よけた！",
    "T_MARK3": "{gold}みきった！{text}　この てきは よけやすい",
    "T_MQ": "{gold}わざが じょうたつした！",
    "T_CHART": "ははが カルテに しるした",
    "T_CHART3": "{gold}カルテ かんせい！{text}　ほうかい しやすい",
    "T_COLLAPSE": "{sat}ほうかい！{text}　しばらく うごけず さいせいも とまる",
    "T_STUN": "{gold}めを まわした！{text}　いまだ！",
    "T_DOWN": "まだ うごく…　{gold}Ｘ{text}で ははに おくってもらえ",
    "T_SENT": "{sat}おくった。{text}　もう おきあがらない",
    "T_MOMDOWN": "{red}ははが たおれた！{text}　そばで {gold}Ａ{text}ながおし",
    "T_MOMUP": "ははが おきあがった",
    "T_BURN": "{red}いやしすぎ！{text}　からだが やけた",
    "T_NOMP": "{red}ＭＰが たりない",
    "T_NOMED": "{red}その くすりは もう ない",
    "T_NOUSE": "いまは つかわなくて いい",
    "T_USED": "くすりを つかった",
    "T_SEL0": "{gold}Ｌ{text}で つかう：きずぐすり　ＨＰを もどす",
    "T_SEL1": "{gold}Ｌ{text}で つかう：じりきすい　ははの ＭＰ",
    "T_SEL2": "{gold}Ｌ{text}で つかう：きつけぐすり　ははを おこす",
    "T_ORDER": "ははに {gold}なぐって！{text}と たのんだ",
    "T_NOTGT": "ちかくに てきが いない",
    "T_LVUP": "{gold}ちからが あがった！",
    # 案内の帯 (上: 説明 / 下: 操作)
    "N_TALK": "{gold}Ａ{text}：つぎへ",
    "N_PREP": "{gold}↑↓{text}：えらぶ　{gold}Ａ{text}：かえる　{gold}Ｂ{text}：おわる",
    "N_PAUSE1": "{gold}↑↓{text}：ページ　{gold}Ａ{text}：さくせん　{gold}Ｂ{text}：とじる",
    "N_PAUSE2": "{gold}↑↓{text}：ページ　{gold}Ｂ{text}：とじる",
    "N_TITLE": "{gold}↑↓{text}：えらぶ　{gold}Ａ{text}：けってい",
    "D_SWA": "みぎての けん。れんざん１・３だんめ と ためぎり",
    "D_SWB": "ひだりての けん。れんざん２だんめ と ためぎり",
    "D_MEAL": "りょうり。つぎに やすむまで きく",
    "D_KIT": "くすりばこ。やすむたびに つめなおす",
    "D_AM": "ごふ。２つまで みにつけられる",
    "D_TAC0": "よりそう：あぶないと かってに いやす",
    "D_TAC1": "まえにでる：ちかくの てきを なぐりに いく",
    "D_TAC2": "さがってて：ねらわれにくく ＭＰが はやく たまる",
    "D_PG2": "わざは あてるほど じょうたつ。カルテは ほうかいで かく",
}
COLORS = {"text": P_TEXT, "gold": P_GOLD, "red": P_RED, "sat": P_SAT, "dim": P_DIM, "hp": P_HP,
          "mp": P_MP}

# ---------------------------------------------------------------- タイル
WIN_TILES = (77, 78, 79)       # 会話窓の枠 (gen_world.py が作る)
MAX_TILE = 208
tiles = [None] * MAX_TILE
names = {}


def put(name, px):
    i = next(k for k in range(MAX_TILE) if tiles[k] is None and k not in WIN_TILES)
    tiles[i] = tile2(px)
    names[name] = i
    return i


put("BLANK", [[0] * 8 for _ in range(8)])
put("PANEL", [[2] * 8 for _ in range(8)])
for lv in range(9):            # ゲージ: 0-8 段
    put(f"BAR{lv}", [[2] * 8] + [[1 if x < lv else 3 for x in range(8)] for _ in range(5)]
        + [[2] * 8, [2] * 8])
put("ARROW_R", [[2] * 8 for _ in range(1)] + [[1 if x <= y and x < 6 else 2 for x in range(8)]
                                              for y in range(3)]
    + [[1 if x <= 4 - (y - 3) and x < 6 else 2 for x in range(8)] for y in range(3, 6)] + [[2] * 8])
put("ARROW_D", [[2] * 8, [2] * 8] + [[1 if abs(x - 3.5) <= 3.5 - y else 2 for x in range(8)]
                                     for y in range(4)] + [[2] * 8, [2] * 8])
put("ARROW_U", [[2] * 8, [2] * 8] + [[1 if abs(x - 3.5) <= 0.5 + y else 2 for x in range(8)]
                                     for y in range(4)] + [[2] * 8, [2] * 8])
put("CROSS", [[1 if (2 <= x <= 5 and 1 <= y <= 6) and (3 <= x <= 4 or 3 <= y <= 4) else 2
               for x in range(8)] for y in range(8)])

chars = list("０１２３４５６７８９") + ["×", "　"]   # 数字は並べておく
for text in STRINGS.values():
    plain = text
    for c in COLORS:
        plain = plain.replace("{" + c + "}", "")
    for ch in plain:
        if ch not in chars:
            chars.append(ch)
for ch in chars:
    im = Image.new("L", (8, 8), 0)
    if ch not in " 　":
        ImageDraw.Draw(im).text((0, 0), ch, font=FONT, fill=255)
    p = im.load()
    put("CH_" + ch, [[1 if p[x, y] > 100 else 2 for x in range(8)] for y in range(8)])
used = sum(1 for t in tiles if t is not None)
blank = tile2([[0] * 8 for _ in range(8)])
open(f"{OUT}/ui.chr", "wb").write(b"".join(t if t is not None else blank for t in tiles))

# ---------------------------------------------------------------- 文字列 → タイル番号の列
L = ["; 自動生成 (tools/gen_ui.py)", f"UI_CHR_SIZE = {MAX_TILE * 16}"]
for n in ("BLANK", "PANEL", "BAR0", "ARROW_R", "ARROW_D", "ARROW_U", "CROSS"):
    L.append(f"UI_{n} = {names[n]}")
L.append(f"UI_D0 = {names['CH_０']}           ; 全角数字 0-9 が並ぶ")
for i, c in enumerate("０１２３４５６７８９"):
    assert names["CH_" + c] == names["CH_０"] + i
L.append(f"UI_SPACE = {names['CH_　']}")
L.append(f"UI_TIMES = {names['CH_×']}")
for k, v in COLORS.items():
    L.append(f"UP_{k.upper()} = {v}")
# 1 字 = 2 バイト (タイル番号, 属性: 優先度 | パレット)。$FF $FF で終わり
for name, text in STRINGS.items():
    pal, out, i = P_TEXT, [], 0
    while i < len(text):
        if text[i] == "{":
            j = text.index("}", i)
            pal = COLORS[text[i + 1:j]]
            i = j + 1
            continue
        out.append(f"{names['CH_' + text[i]]}, ${0x20 | (pal << 2):02X}")
        i += 1
    L.append(f"US_{name}: .byte " + ", ".join(out + ["$FF, $FF"]))
L.append("us_enemy: .word " + ", ".join(f".loword(US_EN{i})" for i in range(10)))
L.append("us_med: .word " + ", ".join(f".loword(US_MED{i})" for i in range(3)))
open(f"{OUT}/ui.inc", "w").write("\n".join(L) + "\n")

# 状態欄の下地: 上 4 行は紺の帯、残りは透明 (どちらも BG3 を手前に出す優先度付き)
m = [(names["PANEL"] if r < 4 else 0) | 0x2000 for r in range(32) for _ in range(32)]
open(f"{OUT}/hudmap.bin", "wb").write(b"".join(bytes((v & 0xFF, v >> 8)) for v in m))

# 確認用
prev = Image.new("RGB", (16 * 8, (MAX_TILE // 16) * 8))
pal = PALS[0]
for i, t in enumerate(tiles):
    if t is None:
        continue
    for y in range(8):
        b0, b1 = t[y * 2], t[y * 2 + 1]
        for x in range(8):
            v = ((b0 >> (7 - x)) & 1) | (((b1 >> (7 - x)) & 1) << 1)
            prev.putpixel(((i % 16) * 8 + x, (i // 16) * 8 + y), pal[v] if v else (0, 0, 0))
prev.resize((prev.width * 4, prev.height * 4), Image.NEAREST).save(f"{OUT}/preview_ui.png")
print(f"ui: {used} tiles used of {MAX_TILE - 3}, {len(chars)} chars, {len(STRINGS)} strings")
