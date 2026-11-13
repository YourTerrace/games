#!/usr/bin/env python3
"""仮素材ジェネレータ (M1)。

ドット絵をコードで描き、SNES 形式 (2bpp/4bpp タイル、タイルマップ、BGR555 パレット)
と ca65 用のテーブル (gfx.inc) を build/ に出力する。
確認用に build/preview_*.png も出す。
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw

OUT = sys.argv[1] if len(sys.argv) > 1 else "build"
os.makedirs(OUT, exist_ok=True)


# ---------------------------------------------------------------- SNES 変換
def bgr555(rgb):
    r, g, b = rgb
    return (r >> 3) | ((g >> 3) << 5) | ((b >> 3) << 10)


def pal_bytes(colors):
    out = bytearray()
    for c in colors:
        v = bgr555(c)
        out += bytes((v & 0xFF, v >> 8))
    return out


def tile_bytes(px, bpp):
    """px: 8x8 のパレット番号リスト(行ごと)。"""
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


def img_tiles(img):
    """P モード画像を 8x8 タイル(行リスト)の並びに。"""
    w, h = img.size
    data = img.load()
    for ty in range(0, h, 8):
        for tx in range(0, w, 8):
            yield [[data[tx + x, ty + y] for x in range(8)] for y in range(8)]


def outline(img, color=1):
    """透明(0)に隣接する不透明ピクセルの外側に輪郭線を引く。"""
    w, h = img.size
    src = img.copy().load()
    dst = img.load()
    for y in range(h):
        for x in range(w):
            if src[x, y] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and src[nx, ny] not in (0, color):
                    dst[x, y] = color
                    break
    return img


def new32():
    return Image.new("P", (32, 32), 0)


# ---------------------------------------------------------------- パレット
HERO_PAL = [
    (0, 0, 0), (26, 20, 32), (240, 184, 144), (200, 136, 96),
    (160, 56, 32), (216, 104, 48), (56, 88, 168), (40, 60, 120),
    (128, 80, 48), (88, 52, 24), (240, 240, 232), (200, 184, 136),
    (152, 136, 88), (168, 176, 192), (96, 104, 128), (208, 48, 48),
]
SKIN, SKIN_S, HAIR, HAIR_H, TUN, TUN_S, LEA, LEA_D, WHT, PNT, PNT_S, STL, STL_D, RED = (
    2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)

# 剣: 1 輪郭, 2 刃(明), 3 刃(中), 4 刃(暗), 5 鍔, 6 鍔(暗), 7 柄, 8 光
SWORD_A_PAL = [(0, 0, 0), (32, 20, 16), (248, 232, 200), (216, 176, 128), (152, 104, 72),
               (224, 168, 48), (152, 96, 24), (112, 48, 32), (255, 255, 240)] + [(0, 0, 0)] * 7
SWORD_B_PAL = [(0, 0, 0), (16, 20, 40), (208, 224, 248), (136, 160, 216), (72, 88, 152),
               (160, 168, 184), (88, 96, 120), (56, 48, 96), (240, 248, 255)] + [(0, 0, 0)] * 7
# 木人
DUMMY_PAL = [(0, 0, 0), (32, 20, 12), (184, 128, 72), (136, 88, 48), (96, 60, 32),
             (232, 208, 120), (192, 160, 80), (144, 112, 48), (160, 168, 176), (104, 112, 128),
             (200, 56, 48), (240, 240, 224)] + [(0, 0, 0)] * 4
FLASH_PAL = [(0, 0, 0)] + [(255, 255, 255)] * 15
# エフェクト: 1 白, 2 黄, 3 橙, 4 影
FX_PAL = [(0, 0, 0), (255, 255, 255), (255, 240, 128), (255, 168, 56), (24, 40, 24)] + [(0, 0, 0)] * 11


# ---------------------------------------------------------------- 主人公
def hero(direction, pose):
    im = new32()
    d = ImageDraw.Draw(im)
    R = d.rectangle
    bob = 1 if pose in ("walk1", "walk2") else 0
    atk = pose == "atk"
    ty = 14 + bob  # 胴体の上端

    if direction in ("down", "up"):
        # 脚
        la = ra = 0
        if pose == "walk1":
            la, ra = 1, -2
        elif pose == "walk2":
            la, ra = -2, 1
        lx, rx = (10, 18) if atk else (11, 17)
        for x0, off in ((lx, la), (rx, ra)):
            R([x0, 23, x0 + 3, 27 + off], fill=PNT)
            R([x0 + 3, 23, x0 + 3, 27 + off], fill=PNT_S)
            R([x0, 27 + off, x0 + 3, 29 + off], fill=LEA_D)
        # 胴
        R([10, ty, 21, 23], fill=TUN)
        R([19, ty, 21, 23], fill=TUN_S)
        R([10, 21, 21, 22], fill=LEA)
        R([15, 21, 16, 22], fill=STL)
        # 腕
        ay = -3 if atk else 0
        sl = (1 if pose == "walk1" else -1 if pose == "walk2" else 0)
        for x0, s in ((7, sl), (22, -sl)):
            R([x0, ty + 2 + ay + s, x0 + 2, ty + 7 + ay + s], fill=SKIN)
            R([x0, ty + 6 + ay + s, x0 + 2, ty + 8 + ay + s], fill=LEA)
        # 肩当て
        d.ellipse([6, ty - 1, 11, ty + 3], fill=LEA)
        d.ellipse([20, ty - 1, 25, ty + 3], fill=LEA)
        d.point([(8, ty), (22, ty)], fill=STL)
        # 頭
        hy = 3 + bob
        d.ellipse([10, hy, 21, hy + 10], fill=SKIN)
        if direction == "down":
            R([12, ty - 1, 19, ty], fill=RED)  # 襟巻
            d.pieslice([9, hy - 2, 22, hy + 9], 180, 360, fill=HAIR)
            R([10, hy + 3, 11, hy + 6], fill=HAIR)
            R([20, hy + 3, 21, hy + 6], fill=HAIR)
            d.point([(12, hy + 4), (15, hy + 4), (18, hy + 4)], fill=HAIR)
            d.point([(13, hy), (14, hy - 1), (17, hy)], fill=HAIR_H)
            d.point([(13, hy + 6), (18, hy + 6)], fill=1)  # 目
            d.point([(13, hy + 7), (18, hy + 7)], fill=SKIN_S)
            d.line([(14, hy + 9), (17, hy + 9)], fill=SKIN_S)
        else:
            d.ellipse([9, hy - 2, 22, hy + 10], fill=HAIR)
            d.point([(12, hy), (14, hy - 1), (17, hy + 1), (19, hy + 3)], fill=HAIR_H)
            d.point([(11, hy + 10), (14, hy + 11), (17, hy + 11), (20, hy + 10)], fill=HAIR)
            R([12, ty - 1, 19, ty], fill=RED)
            R([14, ty, 17, ty + 6 + bob], fill=RED)  # 襟巻のたれ
    else:  # side (右向き)
        f = b = 0
        if pose == "walk1":
            f, b = 3, -3
        elif pose == "walk2":
            f, b = -2, 2
        elif atk:
            f, b = 3, -2
        # 奥の脚 → 手前の脚
        for x0, c in ((13 + b, PNT_S), (15 + f, PNT)):
            R([x0, 23, x0 + 3, 27], fill=c)
            R([x0, 27, x0 + 4, 29], fill=LEA_D)
        R([12, ty, 19, 23], fill=TUN)
        R([12, ty, 13, 23], fill=TUN_S)
        R([12, 21, 19, 22], fill=LEA)
        # 襟巻
        R([13, ty - 1, 19, ty], fill=RED)
        R([10, ty, 12, ty + 3], fill=RED)
        # 腕
        ax = 3 if atk else (1 if pose == "walk2" else -1 if pose == "walk1" else 0)
        R([14 + ax, ty + 2, 16 + ax, ty + 7], fill=SKIN)
        R([14 + ax, ty + 6, 16 + ax, ty + 8], fill=LEA)
        d.ellipse([12, ty - 1, 18, ty + 3], fill=LEA)
        d.point([(15, ty)], fill=STL)
        hy = 3 + bob
        d.ellipse([11, hy, 21, hy + 10], fill=SKIN)
        d.pieslice([9, hy - 2, 21, hy + 9], 180, 360, fill=HAIR)
        R([10, hy + 3, 14, hy + 8], fill=HAIR)
        d.point([(11, hy + 9), (13, hy + 9)], fill=HAIR)
        d.point([(13, hy), (16, hy - 1), (18, hy + 1)], fill=HAIR_H)
        d.point([(19, hy + 6)], fill=1)
        d.point([(19, hy + 7)], fill=SKIN_S)
    return outline(im)


# ---------------------------------------------------------------- 大剣
def sword(angle_deg):
    """画像中心を回転中心として、東(0度)から時計回り(画面座標)に向いた大剣。"""
    im = new32()
    d = ImageDraw.Draw(im)
    a = math.radians(angle_deg)
    ux, uy = math.cos(a), math.sin(a)
    vx, vy = -uy, ux
    cx = cy = 15.5

    def P(along, across):
        return (cx + ux * along + vx * across, cy + uy * along + vy * across)

    # 柄
    d.line([P(-15, 0), P(-9, 0)], fill=7, width=2)
    # 刃 (暗い側 / 明るい側)
    d.polygon([P(-8, -3.2), P(11, -3.2), P(15.5, 0), P(-8, 0)], fill=4)
    d.polygon([P(-8, 0), P(15.5, 0), P(11, 3.2), P(-8, 3.2)], fill=2)
    d.line([P(-8, 0), P(13, 0)], fill=3, width=1)
    d.line([P(-4, 1.8), P(8, 1.8)], fill=8, width=1)
    # 鍔
    d.line([P(-9, -5), P(-9, 5)], fill=5, width=2)
    d.point([P(-9, -5), P(-9, 5)], fill=6)
    d.point([P(-15, 0)], fill=5)
    return outline(im)


# ---------------------------------------------------------------- 木人
def dummy(hit):
    im = new32()
    d = ImageDraw.Draw(im)
    lean = 2 if hit else 0
    # 土台
    d.ellipse([9, 25, 22, 30], fill=4)
    d.ellipse([10, 25, 21, 28], fill=3)
    # 柱
    d.polygon([(14, 27), (17, 27), (17 + lean, 8), (14 + lean, 8)], fill=2)
    d.line([(17, 27), (17 + lean, 8)], fill=3)
    # 藁の胴
    bx = 10 + lean
    d.rounded_rectangle([bx, 12, bx + 11, 23], radius=3, fill=5)
    d.rectangle([bx + 9, 13, bx + 11, 22], fill=6)
    for y in (14, 17, 20):
        d.line([(bx, y), (bx + 11, y)], fill=7)
    d.line([(bx + 3, 15), (bx + 8, 21)], fill=10)  # 的の赤い印
    d.line([(bx + 8, 15), (bx + 3, 21)], fill=10)
    # 腕木
    d.rectangle([5 + lean, 13, 26 + lean, 15], fill=3)
    d.line([(5 + lean, 13), (26 + lean, 13)], fill=2)
    # 兜 (古い鍋)
    hx = 11 + lean + (1 if hit else 0)
    d.ellipse([hx, 2, hx + 9, 11], fill=8)
    d.pieslice([hx, 2, hx + 9, 11], 300, 90, fill=9)
    d.rectangle([hx - 1, 8, hx + 10, 9], fill=9)
    d.point([(hx + 3, 4), (hx + 4, 4)], fill=11)
    return outline(im)


def shadow():
    im = new32()
    d = ImageDraw.Draw(im)
    tmp = Image.new("P", (32, 32), 0)
    ImageDraw.Draw(tmp).ellipse([5, 11, 26, 20], fill=4)
    t = tmp.load()
    o = im.load()
    for y in range(32):
        for x in range(32):
            if t[x, y] and (x + y) % 2 == 0:
                o[x, y] = 4
    return im


def sparks():
    """32x32 スロットに 16x16 を 4 コマ。"""
    im = new32()
    d = ImageDraw.Draw(im)
    # コマ0: 大きな星
    cx, cy = 7.5, 7.5
    for k in range(8):
        a = k * math.pi / 4
        r = 7 if k % 2 == 0 else 4
        d.line([(cx, cy), (cx + math.cos(a) * r, cy + math.sin(a) * r)], fill=2 if k % 2 else 1)
    d.ellipse([5, 5, 10, 10], fill=1)
    # コマ1: 散った火花
    ox = 16
    for k in range(8):
        a = k * math.pi / 4 + 0.4
        x0, y0 = ox + 7.5 + math.cos(a) * 4, 7.5 + math.sin(a) * 4
        x1, y1 = ox + 7.5 + math.cos(a) * 7, 7.5 + math.sin(a) * 7
        d.line([(x0, y0), (x1, y1)], fill=3 if k % 2 else 2)
    return im


# ---------------------------------------------------------------- OBJ シート
SLOTS = []  # (name, image, palette)


def add(name, im, pal):
    SLOTS.append((name, im, pal))
    return len(SLOTS) - 1


HERO_SLOT = {}
for dname in ("down", "up", "side"):
    for pose in ("stand", "walk1", "walk2", "atk"):
        HERO_SLOT[(dname, pose)] = add(f"hero_{dname}_{pose}", hero(dname, pose), HERO_PAL)
SWORD_SLOT = [add(f"sword_{i}", sword(i * 22.5), SWORD_A_PAL) for i in range(5)]
DUMMY_SLOT = [add("dummy", dummy(False), DUMMY_PAL), add("dummy_hit", dummy(True), DUMMY_PAL)]
SHADOW_SLOT = add("shadow", shadow(), FX_PAL)
SPARK_SLOT = add("spark", sparks(), FX_PAL)
assert len(SLOTS) <= 32


def slot_tile(i):
    """(タイル番号下位8bit, ネームビット)"""
    page, j = divmod(i, 16)
    return (j // 4) * 64 + (j % 4) * 4, page


sheet = Image.new("P", (128, 256), 0)
for i, (_, im, _) in enumerate(SLOTS):
    sheet.paste(im, ((i % 4) * 32, (i // 4) * 32))
obj_chr = b"".join(tile_bytes(t, 4) for t in img_tiles(sheet))
open(f"{OUT}/obj.chr", "wb").write(obj_chr)

# 確認用プレビュー
prev = Image.new("RGB", (128, 256), (64, 96, 64))
for i, (_, im, pal) in enumerate(SLOTS):
    rgb = Image.new("RGB", (32, 32))
    src = im.load()
    for y in range(32):
        for x in range(32):
            v = src[x, y]
            rgb.putpixel((x, y), pal[v] if v else (64, 96, 64))
    prev.paste(rgb, ((i % 4) * 32, (i // 4) * 32))
prev.resize((128 * 6, 256 * 6), Image.NEAREST).save(f"{OUT}/preview_obj.png")

# ---------------------------------------------------------------- 背景 (鍛冶場裏の稽古場)
BG_PAL = [
    (0, 0, 0), (72, 136, 64), (88, 152, 72), (56, 112, 56),   # 草
    (168, 136, 88), (144, 112, 72), (192, 160, 112),            # 土
    (120, 124, 136), (88, 92, 108), (152, 156, 168), (56, 60, 76),  # 石
    (232, 216, 96), (224, 120, 136), (240, 240, 232),           # 花
    (40, 80, 48), (24, 28, 40),
]
rnd = random.Random(1994)
W, H = 256, 224
bg = Image.new("P", (W, H), 1)
p = bg.load()

# 草の模様は 16x16 の 4 種を敷き詰める (タイル重複を稼ぐ)
variants = []
for v in range(4):
    cell = [[1] * 16 for _ in range(16)]
    for _ in range(10):
        cell[rnd.randrange(16)][rnd.randrange(16)] = 2
    for _ in range(5):
        cell[rnd.randrange(16)][rnd.randrange(16)] = 3
    if v >= 2:  # 草むら
        x0, y0 = rnd.randrange(3, 12), rnd.randrange(5, 13)
        for dx, dy in ((0, 0), (1, -1), (2, 0), (1, -2), (3, -1)):
            cell[y0 + dy][x0 + dx] = 14 if dx % 2 else 3
    if v == 3:  # 花
        x0, y0 = rnd.randrange(2, 13), rnd.randrange(2, 13)
        cell[y0][x0] = 11
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            cell[y0 + dy][x0 + dx] = 12 if (x0 + y0) % 2 else 13
    variants.append(cell)
for cy in range(H // 16):
    for cx in range(W // 16):
        cell = variants[rnd.choice((0, 0, 0, 1, 1, 2, 3))]
        for y in range(16):
            for x in range(16):
                p[cx * 16 + x, cy * 16 + y] = cell[y][x]

# 土の稽古場 (楕円、縁はディザ)
dirt_tex = [[4] * 16 for _ in range(16)]
for _ in range(14):
    dirt_tex[rnd.randrange(16)][rnd.randrange(16)] = 5
for _ in range(8):
    dirt_tex[rnd.randrange(16)][rnd.randrange(16)] = 6
for y in range(H):
    for x in range(W):
        e = ((x - 128) / 92.0) ** 2 + ((y - 122) / 62.0) ** 2
        if e < 0.86 or (e < 1.0 and (x + y) % 2 == 0):
            p[x, y] = dirt_tex[y % 16][x % 16]


def stone(x0, y0, w, h, face=False):
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            bx, by = x % 16, y % 8
            row = (y // 8) % 2
            bx = (bx + 8 * row) % 16
            c = 7
            if by == 7 or bx == 15:
                c = 10
            elif by == 0 or bx == 0:
                c = 9
            elif (bx * 7 + by * 13 + row * 5) % 23 == 0:
                c = 8
            if face and y >= y0 + h - 8:
                c = 8 if c == 7 else 10 if c == 10 else 7
            p[x, y] = c


stone(0, 0, W, 24, face=True)      # 上の壁 (HUD の下地)
stone(0, H - 16, W, 16)            # 下
stone(0, 24, 16, H - 40)           # 左
stone(W - 16, 24, 16, H - 40)      # 右
for x in range(16, W - 16):        # 壁の影
    for y in range(24, 27):
        if (x + y) % 2 == 0:
            p[x, y] = 14
for y in range(24, H - 16):
    for x in (16, 17):
        if (x + y) % 2 == 0:
            p[x, y] = 14

tiles, tmap, index = [], [], {}
for t in img_tiles(bg):
    b = tile_bytes(t, 4)
    if b not in index:
        index[b] = len(tiles)
        tiles.append(b)
    tmap.append(index[b])
assert len(tiles) <= 512, len(tiles)
open(f"{OUT}/bg.chr", "wb").write(b"".join(tiles))
full = [0] * (32 * 32)
for i, t in enumerate(tmap):
    full[(i // 32) * 32 + i % 32] = t | (2 << 10)  # パレット2
open(f"{OUT}/bg.map", "wb").write(b"".join(bytes((v & 0xFF, v >> 8)) for v in full))
rgb = Image.new("RGB", (W, H))
rgb.putdata([BG_PAL[v] for v in bg.getdata()])
rgb.resize((W * 3, H * 3), Image.NEAREST).save(f"{OUT}/preview_bg.png")

# ---------------------------------------------------------------- フォント / HUD (BG3, 2bpp)
FONT = {
    "0": "0E11131519110E", "1": "040C040404040E", "2": "0E11010204081F", "3": "1F02040201110E",
    "4": "02060A121F0202", "5": "1F101E0101110E", "6": "0608101E11110E", "7": "1F010204080808",
    "8": "0E11110E11110E", "9": "0E11110F01020C",
    "A": "0E1111111F1111", "B": "1E11111E11111E", "C": "0E11101010110E", "D": "1C12111111121C",
    "E": "1F10101E10101F", "F": "1F10101E101010", "G": "0E11101711110F", "H": "1111111F111111",
    "I": "0E04040404040E", "J": "0702020202120C", "K": "11121418141211", "L": "1010101010101F",
    "M": "111B1515111111", "N": "11111915131111", "O": "0E11111111110E", "P": "1E11111E101010",
    "Q": "0E11111115120D", "R": "1E11111E141211", "S": "0F10100E01011E", "T": "1F040404040404",
    "U": "1111111111110E", "V": "1111111111 0A04".replace(" ", ""), "W": "1111111515150A",
    "X": "11110A040A1111", "Y": "1111110A040404", "Z": "1F01020408101F",
    "-": "0000001F000000", ".": "00000000000C0C", ":": "000C0C000C0C00", "+": "0004041F040400",
}
CHARS = " 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-.:+"
font_chr = bytearray()
for ch in CHARS:
    px = [[0] * 8 for _ in range(8)]
    if ch != " ":
        rows = bytes.fromhex(FONT[ch])
        for y, r in enumerate(rows):
            for x in range(5):
                if r & (0x10 >> x):
                    px[y][x + 1] = 1
        for y in range(7):
            for x in range(7):
                if px[y][x] == 1 and px[y + 1][x + 1] == 0:
                    px[y + 1][x + 1] = 2
    font_chr += tile_bytes(px, 2)
open(f"{OUT}/font.chr", "wb").write(font_chr)

hud = [0] * (32 * 32)


def text(col, row, s):
    for i, ch in enumerate(s):
        hud[row * 32 + col + i] = CHARS.index(ch) | 0x2000  # 優先度ビット


text(2, 1, "COMBO 00   DMG 000")
text(3, 26, "Y:SLASH  B:DODGE  +:MOVE")
open(f"{OUT}/hud.map", "wb").write(b"".join(bytes((v & 0xFF, v >> 8)) for v in hud))

# ---------------------------------------------------------------- パレット (CGRAM 256色)
cg = [(0, 0, 0)] * 256
cg[0:4] = [(0, 0, 0), (255, 255, 255), (16, 16, 32), (255, 224, 96)]
cg[32:48] = BG_PAL
for n, pal in ((0, HERO_PAL), (2, SWORD_A_PAL), (3, SWORD_B_PAL), (4, DUMMY_PAL),
               (5, FLASH_PAL), (7, FX_PAL)):
    cg[128 + n * 16:128 + n * 16 + 16] = pal
open(f"{OUT}/palette.bin", "wb").write(pal_bytes(cg))

# ---------------------------------------------------------------- ca65 用テーブル
L = ["; 自動生成 (tools/gen_gfx.py) — 手で編集しない", ""]


def entry(slot, flip=0):
    t, page = slot_tile(slot)
    return f"${t:02X}, ${page | flip:02X}"


L.append("; 主人公: 向き(下,上,左,右) x コマ(立ち,歩1,歩2,攻撃) = tile, flags")
L.append("hero_frame_tbl:")
for face, (dname, flip) in enumerate((("down", 0), ("up", 0), ("side", 0x40), ("side", 0))):
    L.append("  .byte " + ", ".join(entry(HERO_SLOT[(dname, pz)], flip)
                                     for pz in ("stand", "walk1", "walk2", "atk")))
L.append("")
L.append("; 大剣: 16方位 (0=東, 時計回り) = tile, flags")
L.append("sword_tbl:")
for a in range(16):
    if a <= 4:
        img, flip = a, 0
    elif a <= 8:
        img, flip = 8 - a, 0x40
    elif a <= 12:
        img, flip = a - 8, 0xC0
    else:
        img, flip = 16 - a, 0x80
    L.append(f"  .byte {entry(SWORD_SLOT[img], flip)}")
for name, r in (("sw_off0", 18), ("sw_off1", 26)):
    xs = [round(math.cos(a * math.pi / 8) * r) for a in range(16)]
    ys = [round(math.sin(a * math.pi / 8) * r) for a in range(16)]
    L.append(f"{name}_x: .word " + ", ".join(f"${v & 0xFFFF:04X}" for v in xs))
    L.append(f"{name}_y: .word " + ", ".join(f"${v & 0xFFFF:04X}" for v in ys))
L.append("")
for nm, slot in (("DUMMY", DUMMY_SLOT[0]), ("DUMMY_HIT", DUMMY_SLOT[1]),
                 ("SHADOW", SHADOW_SLOT), ("SPARK", SPARK_SLOT)):
    t, page = slot_tile(slot)
    L.append(f"{nm}_TILE = ${t:02X}")
    L.append(f"{nm}_NAME = ${page:02X}")
L.append(f"BG_CHR_SIZE = {len(tiles) * 32}")
L.append(f"FONT_CHR_SIZE = {len(font_chr)}")
L.append(f"OBJ_CHR_SIZE = {len(obj_chr)}")
open(f"{OUT}/gfx.inc", "w").write("\n".join(L) + "\n")
print(f"gfx: {len(SLOTS)} obj slots, {len(tiles)} bg tiles")
