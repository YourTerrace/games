#!/usr/bin/env python3
"""序章の部屋 (背景タイル・当たり判定・配置) と会話テキストを生成する。

部屋は 1 画面固定 (16x14 マス、1 マス = 16x16 ドット)。画面端の切れ目から隣の部屋へ移る。
文字は GNU Unifont (16x16) から、台本に出てくる字だけをタイル化する。

出力 (build/):
  bg.chr        背景タイル (4bpp、全部屋で共有)
  bg.pal        背景パレット 2 本 (CGRAM 32-63)
  rooms.inc     部屋ごとのタイルマップ・当たり・出入口・配置物
  glyph.chr     文字タイル (2bpp、1 字 = 4 タイル)
  script.inc    台本 (文字番号の列)
  window.map    会話窓 / blank.map 窓を消す用
"""
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else "build"
os.makedirs(OUT, exist_ok=True)
rnd = random.Random(1994)


def bgr555(rgb):
    r, g, b = rgb
    return (r >> 3) | ((g >> 3) << 5) | ((b >> 3) << 10)


def tile_bytes(px, bpp):
    out = bytearray()
    for pair in range(bpp // 2):
        for y in range(8):
            b0 = b1 = 0
            for x in range(8):
                v = px[y][x]
                b0 = (b0 << 1) | ((v >> (pair * 2)) & 1)
                b1 = (b1 << 1) | ((v >> (pair * 2 + 1)) & 1)
            out += bytes((b0, b1))
    return bytes(out)


# ---------------------------------------------------------------- 背景パレット
# A (BG パレット2): 地面と石
PAL_A = [(0, 0, 0), (72, 136, 64), (88, 152, 72), (56, 112, 56), (168, 136, 88), (144, 112, 72),
         (192, 160, 112), (120, 124, 136), (88, 92, 108), (152, 156, 168), (56, 60, 76),
         (232, 216, 96), (224, 120, 136), (240, 240, 232), (40, 80, 48), (24, 28, 40)]
# B (BG パレット3): 木・建物・水・火
PAL_B = [(0, 0, 0), (184, 136, 80), (144, 100, 56), (96, 64, 36), (184, 72, 56), (136, 48, 40),
         (216, 112, 80), (72, 136, 200), (136, 192, 232), (48, 96, 160), (240, 240, 232),
         (248, 216, 112), (72, 136, 64), (40, 80, 48), (104, 176, 80), (24, 28, 40)]
open(f"{OUT}/bg.pal", "wb").write(
    b"".join(bytes((bgr555(c) & 0xFF, bgr555(c) >> 8)) for c in PAL_A + PAL_B))


# ---------------------------------------------------------------- マスの絵
def cell():
    return [[0] * 16 for _ in range(16)]


def grass(v):
    r = random.Random(100 + v)
    c = [[1] * 16 for _ in range(16)]
    for _ in range(10):
        c[r.randrange(16)][r.randrange(16)] = 2
    for _ in range(5):
        c[r.randrange(16)][r.randrange(16)] = 3
    if v >= 2:
        x0, y0 = r.randrange(3, 12), r.randrange(5, 13)
        for dx, dy in ((0, 0), (1, -1), (2, 0), (1, -2), (3, -1)):
            c[y0 + dy][x0 + dx] = 14 if dx % 2 else 3
    if v == 3:
        x0, y0 = r.randrange(2, 13), r.randrange(2, 13)
        c[y0][x0] = 11
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            c[y0 + dy][x0 + dx] = 13
    return c, 0


def dirt(v):
    r = random.Random(200 + v)
    c = [[4] * 16 for _ in range(16)]
    for _ in range(12):
        c[r.randrange(16)][r.randrange(16)] = 5
    for _ in range(6):
        c[r.randrange(16)][r.randrange(16)] = 6
    return c, 0


def stone(v):
    c = cell()
    for y in range(16):
        for x in range(16):
            bx, by = (x + 8 * ((y // 8) % 2)) % 16, y % 8
            k = 7
            if by == 7 or bx == 15:
                k = 10
            elif by == 0 or bx == 0:
                k = 9
            elif (bx * 7 + by * 13) % 23 == 0:
                k = 8
            c[y][x] = k
    return c, 0


def boulder(v):
    c, _ = grass(0)
    im = Image.new("P", (16, 16), 0)
    d = ImageDraw.Draw(im)
    d.ellipse([1, 3, 14, 14], fill=7)
    d.ellipse([3, 4, 10, 9], fill=9)
    d.arc([1, 3, 14, 14], 20, 160, fill=10)
    d.arc([1, 3, 14, 14], 160, 380, fill=8)
    p = im.load()
    for y in range(16):
        for x in range(16):
            if p[x, y]:
                c[y][x] = p[x, y]
    return c, 0


def draw_b(fn, bg=12):
    im = Image.new("P", (16, 16), bg)
    fn(ImageDraw.Draw(im), im)
    p = im.load()
    return [[p[x, y] for x in range(16)] for y in range(16)], 1


def tree(v):
    def f(d, im):
        d.rectangle([6, 10, 9, 15], fill=3)
        d.line([(7, 10), (7, 15)], fill=2)
        d.ellipse([0, 0, 15, 12], fill=13)
        d.ellipse([2, 1, 12, 9], fill=12)
        d.ellipse([4, 2, 9, 6], fill=14)
        for x, y in ((3, 8), (11, 6), (8, 10), (13, 9)):
            d.point([(x, y)], fill=14 if v else 12)
    return draw_b(f)


def bush(v):
    """繁り病の茂み。"""
    def f(d, im):
        r = random.Random(300 + v)
        d.rectangle([0, 0, 15, 15], fill=13)
        for _ in range(26):
            x, y = r.randrange(16), r.randrange(16)
            d.line([(x, y), (x + r.choice((-2, 2)), y + 1)], fill=r.choice((12, 14, 14)))
        for _ in range(2):
            x, y = r.randrange(2, 14), r.randrange(2, 14)
            d.point([(x, y)], fill=11)
            d.point([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)], fill=6)
    return draw_b(f)


def water(v):
    def f(d, im):
        d.rectangle([0, 0, 15, 15], fill=7)
        for x, y in ((2, 3), (10, 6), (5, 11), (12, 13)):
            d.line([(x, y), (x + 3, y)], fill=8)
            d.line([(x + 1, y + 1), (x + 2, y + 1)], fill=9)
    return draw_b(f)


def roof(v):
    def f(d, im):
        d.rectangle([0, 0, 15, 15], fill=4)
        for y in (3, 7, 11, 15):
            d.line([(0, y), (15, y)], fill=5)
        for y, off in ((0, 2), (4, 6), (8, 2), (12, 6)):
            for x in range(off, 16, 8):
                d.line([(x, y), (x, y + 3)], fill=5)
                d.point([(x + 1, y)], fill=6)
    return draw_b(f)


def wall(v):
    def f(d, im):
        d.rectangle([0, 0, 15, 15], fill=1)
        for x in (3, 7, 11, 15):
            d.line([(x, 0), (x, 15)], fill=2)
        d.line([(0, 0), (15, 0)], fill=3)
        d.line([(0, 15), (15, 15)], fill=3)
        if v == 1:   # 窓
            d.rectangle([4, 4, 11, 11], fill=3)
            d.rectangle([5, 5, 10, 10], fill=11)
            d.line([(8, 5), (8, 10)], fill=3)
        if v == 2:   # 戸
            d.rectangle([3, 2, 12, 15], fill=3)
            d.rectangle([4, 3, 11, 15], fill=2)
            d.point([(10, 9)], fill=11)
    return draw_b(f)


def fence(v):
    def f(d, im):
        d.line([(0, 6), (15, 6)], fill=2, width=2)
        d.line([(0, 11), (15, 11)], fill=2, width=2)
        for x in (3, 11):
            d.rectangle([x, 3, x + 2, 14], fill=1)
            d.line([(x + 2, 3), (x + 2, 14)], fill=3)
    return draw_b(f)


def fire(v):
    def f(d, im):
        d.ellipse([1, 9, 14, 15], fill=13)
        d.line([(2, 13), (13, 10)], fill=3, width=2)
        d.line([(2, 10), (13, 13)], fill=2, width=2)
        d.polygon([(7, 1), (11, 8), (8, 11), (4, 8)], fill=4)
        d.polygon([(7, 4), (9, 8), (7, 10), (5, 8)], fill=6)
        d.point([(7, 7), (7, 8)], fill=11)
    return draw_b(f)


def sign(v):
    def f(d, im):
        d.rectangle([7, 8, 8, 15], fill=3)
        d.rectangle([2, 2, 13, 9], fill=1)
        d.rectangle([2, 2, 13, 2], fill=10)
        d.line([(4, 5), (11, 5)], fill=3)
        d.line([(4, 7), (9, 7)], fill=3)
    return draw_b(f)


def chest(v):
    def f(d, im):
        d.rectangle([1, 5, 14, 14], fill=3)
        d.rectangle([2, 6, 13, 13], fill=1)
        d.rectangle([2, 6, 13, 8], fill=2)
        d.line([(2, 9), (13, 9)], fill=3)
        d.rectangle([7, 8, 8, 11], fill=11)
    return draw_b(f)


def mill(v):
    def f(d, im):
        d.rectangle([0, 0, 15, 15], fill=2)
        d.line([(0, 0), (15, 15)], fill=1, width=2)
        d.line([(15, 0), (0, 15)], fill=3, width=2)
        r = random.Random(400 + v)
        for _ in range(10):
            x, y = r.randrange(16), r.randrange(16)
            d.line([(x, y), (x + 2, y + 1)], fill=r.choice((13, 14)))
    return draw_b(f)


# 記号 → (描画関数, 変種の数, 通れないか)
LEGEND = {
    ".": (grass, 4, False), ",": (dirt, 3, False), "f": (lambda v: grass(3), 1, False),
    "#": (tree, 2, True), "W": (stone, 1, True), "X": (boulder, 1, True), "b": (bush, 3, True),
    "~": (water, 1, True), "R": (roof, 1, True), "H": (wall, 1, True),
    "w": (lambda v: wall(1), 1, True), "D": (lambda v: wall(2), 1, True),
    "F": (fence, 1, True), "C": (fire, 1, True), "S": (sign, 1, True), "M": (mill, 3, True),
    "T": (chest, 1, True),
}

# ---------------------------------------------------------------- 台本
# 1 行 14 字まで、1 ページ 4 行まで (話者名 + 3 行)。空行でページ送り。
SCRIPTS = {
    "OPEN": """ミレイユ
「グレン！　いつまで
　寝てるの」

ミレイユ
「裏山の水車小屋が
　ひと晩で茂みに
　呑まれたんだって」

ミレイユ
「水車番のじいさんが
　戻らないの。
　見に行きましょう」

グレン
「……わかった」""",
    "ELDER": """老人
「雨はやまん。
　草はのびる。
　ありがたいことじゃ」

老人
「……たぶんな」""",
    "AUNT": """おばさん
「北の道にネズミが
　出るよ。白く光ったら
　よけるんだよ！」""",
    "PRIEST": """巡回司祭
「繁りは恵みです。
　祈りなさい」""",
    "SIGN1": """＜立て札＞
Ｙ：斬る
　　押し続けて溜め斬り

Ｂ：よける
ひきつけてよけたら
すぐＹで「返し刃」""",
    "SIGN2": """＜立て札＞
Ａ：母さんに
　　癒やしてもらう

Ｘ：母さんが敵を
　　過治癒する
満ちれば敵は崩壊！""",
    "FIRE": """焚き火で休んだ。
体力がもどった。
支度をととのえよう。""",
    "CHEST": """箱の中に
大剣「苔断ち」が
入っていた！

苔断ち　攻１６　重さ４
繁るものに強い。
焚き火で持ちかえよう。""",
    "EMPTY": """からっぽだ。""",
    "SIGN3": """＜立て札＞
見切り印
ひきつけてよけるたび
敵ごとに印がつく

印３つで
その敵は見切った。
よけやすくなる""",
    "M_L0": """暁手　""",
    "M_L1": """宵手　""",
    "M_L2": """献立　""",
    "M_L3": """支度を終える""",
    "SW0": """鉄塊・暁　攻１２""",
    "SW1": """鉄塊・宵　攻１０""",
    "SW2": """苔断ち　　攻１６""",
    "SW3": """水車鉄軸　攻２２""",
    "MEAL0": """なし　　　　　　""",
    "MEAL1": """鹿肉　　　力＋３""",
    "MEAL2": """根菜煮　　守＋３""",
    "MEAL3": """茸飯　慈力回復倍""",
    "GLYPHS": """▶　""",
    "BOSS_IN": """ミレイユ
「……じいさん？」

ミレイユ
「グレン、斬っても
　治ってしまうわ。
　母さんに合図して！」""",
    "BOSS_OUT": """グレン
「母さん、いまの何」

ミレイユ
「……あとで話すわ」

水車の鉄軸を
手に入れた。

序章　雨漏り　完

ここまで遊んでくれて
ありがとう。""",
    "TITLE": """ゆりかごの双刃""",
    "T_NEW": """はじめから""",
    "T_CONT": """つづきから""",
}
SCRIPT_ORDER = list(SCRIPTS)
C_END, C_NL, C_PAGE = 0xFF, 0xFE, 0xFD
GLYPH_BASE = 80           # HUD 用フォントの後ろ
MAX_GLYPHS = (1024 - GLYPH_BASE) // 4

glyphs = []               # 出現順の文字
script_bytes = {}
for name in SCRIPT_ORDER:
    out = []
    pages = SCRIPTS[name].split("\n\n")
    for pi, page in enumerate(pages):
        lines = page.split("\n")
        assert len(lines) <= 4, (name, page)
        for li, line in enumerate(lines):
            assert len(line) <= 14, (name, line, len(line))
            for ch in line:
                if ch not in glyphs:
                    glyphs.append(ch)
                out.append(glyphs.index(ch))
            if li < len(lines) - 1:
                out.append(C_NL)
        out.append(C_PAGE if pi < len(pages) - 1 else C_END)
    script_bytes[name] = out
assert len(glyphs) <= MAX_GLYPHS, len(glyphs)

font = ImageFont.truetype("/usr/share/fonts/opentype/unifont/unifont_jp.otf", 16)
glyph_chr = bytearray()
for ch in glyphs:
    im = Image.new("1", (16, 16), 0)
    if ch != "　":
        ImageDraw.Draw(im).text((0, 0), ch, font=font, fill=1)
    p = im.load()
    for ty in (0, 8):
        for tx in (0, 8):   # 地は色2 (窓の地色)、字は色1
            glyph_chr += tile_bytes([[1 if p[tx + x, ty + y] else 2 for x in range(8)]
                                     for y in range(8)], 2)
open(f"{OUT}/glyph.chr", "wb").write(glyph_chr)

L = ["; 自動生成 (tools/gen_world.py)", f"GLYPH_BASE = {GLYPH_BASE}",
     f"GLYPH_CHR_SIZE = {len(glyph_chr)}"]
for i, name in enumerate(SCRIPT_ORDER):
    L.append(f"SCR_{name} = {i}")
L.append(f"GL_CURSOR = {glyphs.index('▶')}")
L.append(f"GL_SPACE = {glyphs.index('　')}")
L.append("script_tbl: .word " + ", ".join(f".loword(scr_{n})" for n in SCRIPT_ORDER))
for name in SCRIPT_ORDER:
    b = script_bytes[name]
    L.append(f"scr_{name}:")
    for k in range(0, len(b), 24):
        L.append("  .byte " + ", ".join(str(v) for v in b[k:k + 24]))
open(f"{OUT}/script.inc", "w").write("\n".join(L) + "\n")

# 会話窓 (BG3 の 18-27 行目、10 行ぶん)。枠は HUD フォントの後ろに足したタイルを使う
WIN_TILE = 77             # 77 = 地, 78 = 横枠, 79 = 縦枠
win = []
for row in range(10):
    for col in range(32):
        if col in (0, 31):
            t = 0
        elif row in (0, 9):
            t = 78
        elif col in (1, 30):
            t = 79
        else:
            t = 77
        win.append(t | 0x2000)
open(f"{OUT}/window.map", "wb").write(b"".join(bytes((v & 0xFF, v >> 8)) for v in win))
open(f"{OUT}/blank.map", "wb").write(bytes((0x00, 0x20)) * (32 * 10))
win_chr = bytearray()
win_chr += tile_bytes([[2] * 8 for _ in range(8)], 2)
win_chr += tile_bytes([[2] * 8 if y not in (3, 4) else [1] * 8 for y in range(8)], 2)
win_chr += tile_bytes([[1 if x in (3, 4) else 2 for x in range(8)] for _ in range(8)], 2)
open(f"{OUT}/window.chr", "wb").write(win_chr)

# ---------------------------------------------------------------- 部屋
T_RAT, T_SNAKE, T_SCARE, T_BOSS = 1, 2, 3, 4
O_ENEMY, O_NPC, O_TALK, O_FIRE, O_CHEST = 1, 2, 3, 4, 5
SET_VILLAGE, SET_FIELD, SET_BOSS = 0, 1, 2
NONE = 0xFF

ROOMS = [
    dict(name="village", set=SET_VILLAGE, up=1, enter="OPEN", map="""
################
#######,,#######
#RRRR..,,..RRRR#
#HwDH..,,..HDwH#
#....,,,,,,....#
#.S..,,,,,,..f.#
#....,,,,,,....#
#..f.,,,,,,..C.#
#....,,,,,,....#
#FFFF.,,,,.FFFF#
#.....,,,,.....#
#..f..........f#
################
################""", objs=[
        (O_NPC, 56, 168, 0, "ELDER"), (O_NPC, 200, 88, 1, "AUNT"), (O_NPC, 184, 172, 2, "PRIEST"),
        (O_TALK, 40, 88, 0, "SIGN1"), (O_FIRE, 216, 120, 0, "FIRE")], start=(128, 136)),
    dict(name="outskirts", set=SET_FIELD, up=2, down=0, map="""
################
#######,,#######
#......,,......#
#..b...,,...b..#
#......,,......#
#...,,,,,,,,...#
#...,......,...#
#.S.,......,.f.#
#...,,,,,,,,...#
#......,,......#
#..f...,,....b.#
#......,,......#
#######,,#######
#######,,#######""", objs=[
        (O_ENEMY, 72, 72, T_RAT, None), (O_ENEMY, 184, 72, T_RAT, None),
        (O_TALK, 40, 120, 0, "SIGN2")]),
    dict(name="hill1", set=SET_FIELD, up=3, down=1, map="""
################
#######,,#######
#~~~...,,....b##
#~~~...,,.....##
#~~....,,......#
#~~..b.,,......#
#~.....,,..X...#
#......,,......#
#..X...,,......#
#T.....,,...b..#
#b.....,,..S...#
##.....,,.....##
#######,,#######
#######,,#######""", objs=[
        (O_ENEMY, 128, 56, T_SNAKE, None), (O_ENEMY, 88, 104, T_RAT, None),
        (O_ENEMY, 200, 120, T_RAT, None), (O_ENEMY, 216, 56, T_SNAKE, None),
        (O_CHEST, 24, 152, 2, "CHEST"), (O_TALK, 184, 168, 0, "SIGN3")]),
    dict(name="hill2", set=SET_FIELD, up=4, down=2, map="""
################
#######,,#######
##b....,,....b##
#......,,......#
#..b...,,......#
#......,,......#
#......,,......#
#.X....,,....X.#
#......,,......#
#......,,..b...#
#..b...,,...C..#
##.....,,.....##
#######,,#######
#######,,#######""", objs=[
        (O_ENEMY, 128, 72, T_SCARE, None), (O_ENEMY, 56, 56, T_SNAKE, None),
        (O_ENEMY, 200, 56, T_SNAKE, None), (O_FIRE, 200, 168, 0, "FIRE")]),
    dict(name="mill", set=SET_BOSS, down=3, enter="BOSS_IN", map="""
################
################
#bbbbMMMMMMbbbb#
#bb..MMMMMM..bb#
#b............b#
#..............#
#~~..........~~#
#~~..........~~#
#..............#
#..............#
#b............b#
#bb....,,....bb#
#######,,#######
#######,,#######""", objs=[(O_ENEMY, 128, 96, T_BOSS, None)]),
]

tiles, index = [], {}


def add_tile(px, pal):
    b = tile_bytes(px, 4)
    if b not in index:
        index[b] = len(tiles)
        tiles.append(b)
    return index[b] | ((2 + pal) << 10)


R = ["; 自動生成 (tools/gen_world.py)", f"NUM_ROOMS = {len(ROOMS)}",
     f"O_ENEMY = {O_ENEMY}", f"O_NPC = {O_NPC}", f"O_TALK = {O_TALK}", f"O_FIRE = {O_FIRE}", f"O_CHEST = {O_CHEST}",
     f"TYPE_BOSS = {T_BOSS}", f"BOSS_ROOM = {len(ROOMS) - 1}",
     f"START_X = {ROOMS[0]['start'][0]}", f"START_Y = {ROOMS[0]['start'][1]}",
     "room_tbl: .word " + ", ".join(f".loword(room_{r['name']})" for r in ROOMS)]
maps = bytearray()
preview = Image.new("RGB", (256 * len(ROOMS), 224))
for ri, room in enumerate(ROOMS):
    rows = room["map"].strip("\n").split("\n")
    assert len(rows) == 14 and all(len(r) == 16 for r in rows), room["name"]
    tmap = [0] * (32 * 32)
    col = []
    for cy, row in enumerate(rows):
        for cx, ch in enumerate(row):
            fn, nvar, solid = LEGEND[ch]
            px, pal = fn(rnd.randrange(nvar))
            col.append(1 if solid else 0)
            for qy in (0, 1):
                for qx in (0, 1):
                    sub = [r[qx * 8:qx * 8 + 8] for r in px[qy * 8:qy * 8 + 8]]
                    tmap[(cy * 2 + qy) * 32 + cx * 2 + qx] = add_tile(sub, pal)
            colors = PAL_B if pal else PAL_A
            for y in range(16):
                for x in range(16):
                    preview.putpixel((ri * 256 + cx * 16 + x, cy * 16 + y), colors[px[y][x]])
    off = len(maps)
    maps += b"".join(bytes((v & 0xFF, v >> 8)) for v in tmap)
    n = room["name"]
    enter = f"SCR_{room['enter']}" if room.get("enter") else "$FF"
    R.append(f"room_{n}:")
    R.append(f"  .byte {room['set']}, {room.get('up', NONE)}, {room.get('down', NONE)}, "
             f"{room.get('left', NONE)}, {room.get('right', NONE)}, {enter}")
    R.append(f"  .word {off}                 ; RoomMaps 内の位置")
    for k in range(0, 224, 16):
        R.append("  .byte " + ", ".join(str(v) for v in col[k:k + 16]))
    for kind, x, y, a, scr in room["objs"]:
        if kind == O_ENEMY:
            assert not col[(y // 16) * 16 + x // 16], (room['name'], x, y)
        R.append(f"  .byte {kind}, {x}, {y}, {a}, {'SCR_' + scr if scr else 0}")
    R.append("  .byte 0")
assert len(tiles) <= 512, len(tiles)
open(f"{OUT}/bg.chr", "wb").write(b"".join(tiles))
open(f"{OUT}/rooms.bin", "wb").write(maps)
R.append(f"BG_CHR_SIZE = {len(tiles) * 32}")
open(f"{OUT}/rooms.inc", "w").write("\n".join(R) + "\n")
preview.save(f"{OUT}/preview_rooms.png")
print(f"world: {len(ROOMS)} rooms, {len(tiles)} bg tiles, {len(glyphs)} glyphs")
