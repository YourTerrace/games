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
# 母: 1 輪郭, 2 肌, 3 肌影, 4 髪, 5 髪(明), 6 服, 7 服影, 8 肩掛け, 9 肩掛け影, 10 白, 11 靴
MOM_PAL = [(0, 0, 0), (36, 24, 32), (244, 200, 164), (208, 152, 116), (120, 72, 40), (168, 112, 64),
           (240, 228, 196), (200, 180, 144), (72, 144, 104), (44, 100, 76), (255, 255, 248),
           (112, 72, 48), (224, 96, 96), (0, 0, 0), (0, 0, 0), (0, 0, 0)]
# 敵共通: 2 毛, 3 毛影, 4 苔(明), 5 苔, 6 苔影, 7 桃, 8 赤目, 9 白, 10 藁, 11 藁影, 12 木, 13 木影, 14 若葉, 15 布
ENEMY_PAL = [(0, 0, 0), (28, 24, 20), (152, 136, 120), (104, 88, 80), (136, 200, 88), (88, 152, 64),
             (48, 96, 48), (232, 144, 152), (224, 48, 48), (248, 248, 232), (232, 208, 120),
             (184, 152, 72), (152, 100, 56), (104, 64, 36), (184, 240, 112), (120, 88, 136)]
# 癒やしの光 / 崩壊中の色
HEAL_PAL = [(0, 0, 0), (255, 255, 255), (176, 255, 192), (72, 216, 128)] + [(168, 248, 184)] * 12
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


def mother(direction, pose):
    im = new32()
    d = ImageDraw.Draw(im)
    R = d.rectangle
    walk = pose == "walk"
    cast = pose == "cast"
    bob = 1 if walk else 0
    ty = 15 + bob
    hy = 4 + bob
    if direction in ("down", "up"):
        # 長い服 (裾広がり)
        d.polygon([(11, ty), (20, ty), (23, 28), (8, 28)], fill=6)
        d.polygon([(19, ty), (20, ty), (23, 28), (21, 28)], fill=7)
        R([9 + (1 if walk else 0), 28, 12 + (1 if walk else 0), 29], fill=11)
        R([19 - (1 if walk else 0), 28, 22 - (1 if walk else 0), 29], fill=11)
        if direction == "down":
            R([13, ty + 3, 18, 26], fill=10)          # 前掛け
            d.line([(13, ty + 3), (18, ty + 3)], fill=8)
        # 肩掛け
        d.polygon([(9, ty - 1), (22, ty - 1), (23, ty + 4), (8, ty + 4)], fill=8)
        d.line([(8, ty + 4), (23, ty + 4)], fill=9)
        # 腕
        if cast:
            R([6, ty - 6, 8, ty], fill=2)
            R([23, ty - 6, 25, ty], fill=2)
            d.point([(7, ty - 8), (24, ty - 8)], fill=10)
        else:
            s1 = 1 if walk else 0
            R([7, ty + 4 + s1, 9, ty + 8 + s1], fill=2)
            R([22, ty + 4 - s1, 24, ty + 8 - s1], fill=2)
        # 頭
        d.ellipse([11, hy, 20, hy + 10], fill=2)
        d.ellipse([13, hy - 4, 18, hy], fill=4)        # おだんご
        if direction == "down":
            d.pieslice([10, hy - 2, 21, hy + 8], 180, 360, fill=4)
            R([10, hy + 3, 11, hy + 8], fill=4)
            R([20, hy + 3, 21, hy + 8], fill=4)
            d.point([(14, hy - 3), (13, hy), (16, hy - 1)], fill=5)
            if cast:
                d.line([(13, hy + 6), (14, hy + 6)], fill=1)
                d.line([(17, hy + 6), (18, hy + 6)], fill=1)
            else:
                d.point([(13, hy + 6), (18, hy + 6)], fill=1)
            d.point([(12, hy + 7), (19, hy + 7)], fill=12)   # ほお
            d.line([(15, hy + 8), (16, hy + 8)], fill=3)
        else:
            d.ellipse([10, hy - 1, 21, hy + 10], fill=4)
            d.ellipse([13, hy - 4, 18, hy + 1], fill=4)
            d.point([(14, hy - 3), (13, hy + 2), (17, hy + 4)], fill=5)
            R([14, hy - 1, 17, hy - 1], fill=12)             # 髪ひも
    else:
        d.polygon([(12, ty), (19, ty), (21, 28), (10, 28)], fill=6)
        d.polygon([(12, ty), (13, ty), (12, 28), (10, 28)], fill=7)
        R([13 + (2 if walk else 0), 28, 17 + (2 if walk else 0), 29], fill=11)
        R([15, ty + 3, 19, 25], fill=10)
        d.polygon([(11, ty - 1), (20, ty - 1), (21, ty + 4), (10, ty + 4)], fill=8)
        d.line([(10, ty + 4), (21, ty + 4)], fill=9)
        ax = 1 if walk else 0
        R([15 + ax, ty + 4, 17 + ax, ty + 8], fill=2)
        d.ellipse([11, hy, 20, hy + 10], fill=2)
        d.pieslice([10, hy - 2, 20, hy + 8], 180, 360, fill=4)
        R([10, hy + 3, 13, hy + 8], fill=4)
        d.ellipse([8, hy - 2, 13, hy + 3], fill=4)
        d.point([(10, hy - 1), (14, hy)], fill=5)
        d.point([(18, hy + 6)], fill=1)
        d.point([(17, hy + 7)], fill=12)
    return outline(im)


def small4(fn):
    """16x16 を 4 コマ、32x32 スロットに詰める。"""
    im = new32()
    for k in range(4):
        q = Image.new("P", (16, 16), 0)
        fn(ImageDraw.Draw(q), k)
        outline(q)
        im.paste(q, ((k % 2) * 16, (k // 2) * 16))
    return im


def rat(d, k):
    """苔ネズミ (右向き)。0,1=走り 2=溜め 3=飛びつき"""
    if k == 3:
        d.ellipse([2, 5, 13, 11], fill=2)
        d.ellipse([3, 4, 9, 8], fill=5)
        d.point([(5, 5), (7, 4)], fill=4)
        d.line([(0, 7), (2, 8)], fill=7)
        d.polygon([(11, 5), (15, 7), (11, 10)], fill=2)
        d.point([(13, 7)], fill=8)
        d.point([(14, 9)], fill=9)
        d.line([(3, 12), (1, 13)], fill=3)
        d.line([(11, 12), (13, 13)], fill=3)
        return
    y = 2 if k == 2 else 0
    d.ellipse([2, 6 + y, 12, 13], fill=2)
    d.ellipse([3, 5 + y, 9, 9 + y], fill=5)
    d.point([(4, 6 + y), (7, 5 + y)], fill=4)
    d.point([(6, 7 + y)], fill=6)
    d.line([(0, 9), (2, 11)], fill=7)
    d.ellipse([9, 6 + y, 14, 11 + y // 2 + 1], fill=2)
    d.rectangle([9, 5 + y, 10, 6 + y], fill=7)
    d.point([(12, 8 + y)], fill=8)
    d.point([(14, 9 + y)], fill=7)
    if k == 0:
        d.point([(4, 14), (10, 14)], fill=3)
    elif k == 1:
        d.point([(6, 14), (12, 14)], fill=3)


def snake(d, k):
    """蔓へび (右向き)。0,1=這う 2=溜め 3=噛みつき"""
    if k == 3:
        d.line([(1, 12), (5, 10), (9, 9), (13, 8)], fill=5, width=3)
        d.ellipse([10, 5, 15, 10], fill=4)
        d.point([(13, 7)], fill=8)
        d.line([(14, 9), (15, 10)], fill=9)
        d.point([(4, 8), (5, 7)], fill=14)
        return
    if k == 2:
        d.ellipse([3, 7, 12, 14], fill=5)
        d.ellipse([5, 9, 10, 12], fill=6)
        d.ellipse([4, 2, 9, 7], fill=4)
        d.point([(7, 4)], fill=8)
        d.point([(11, 6), (12, 5)], fill=14)
        return
    w = 1 if k else 0
    pts = [(1, 12 - w), (4, 13), (7, 11 + w), (9, 9), (10, 6)]
    d.line(pts, fill=5, width=3)
    d.line([(2, 13 - w), (6, 12 + w)], fill=6)
    d.ellipse([8, 2, 14, 7], fill=4)
    d.point([(12, 4)], fill=8)
    d.point([(14, 6)], fill=7)
    d.point([(5, 9 + w), (6, 8 + w)], fill=14)


def scarecrow(k):
    """芽吹き案山子。0=立ち 1=振りかぶり 2=振り下ろし"""
    im = new32()
    d = ImageDraw.Draw(im)
    d.rectangle([15, 22, 16, 29], fill=12)
    d.point([(16, 23), (16, 26)], fill=13)
    d.rounded_rectangle([10, 12, 21, 23], radius=3, fill=10)
    d.rectangle([19, 13, 21, 22], fill=11)
    for y in (15, 18, 21):
        d.line([(10, y), (21, y)], fill=11)
    d.polygon([(11, 12), (20, 12), (17, 17), (14, 17)], fill=15)
    if k == 0:
        d.line([(4, 15), (27, 15)], fill=12, width=2)
        hands = [(4, 15), (27, 15)]
    elif k == 1:
        d.line([(10, 14), (5, 5)], fill=12, width=2)
        d.line([(21, 14), (26, 5)], fill=12, width=2)
        hands = [(5, 5), (26, 5)]
    else:
        d.line([(10, 15), (4, 23)], fill=12, width=2)
        d.line([(21, 15), (27, 23)], fill=12, width=2)
        hands = [(4, 23), (27, 23)]
    for hx, hyy in hands:
        d.ellipse([hx - 2, hyy - 2, hx + 2, hyy + 2], fill=10)
        d.point([(hx, hyy - 3)], fill=14)
    d.ellipse([11, 2, 20, 11], fill=10)
    d.pieslice([11, 2, 20, 11], 300, 80, fill=11)
    d.point([(14, 6), (17, 6)], fill=1)
    d.line([(14, 9), (17, 9)], fill=1)
    d.point([(13, 8), (18, 8)], fill=8 if k else 1)
    d.line([(15, 2), (14, 0)], fill=5)
    d.line([(16, 2), (18, 0)], fill=14)
    d.point([(13, 0), (19, 0)], fill=4)
    return outline(im)


def satbar():
    """飽和ゲージ 4 段階 (16x16 x 4)。"""
    im = new32()
    d = ImageDraw.Draw(im)
    for k in range(4):
        ox, oy = (k % 2) * 16, (k // 2) * 16
        d.rectangle([ox + 1, oy + 6, ox + 14, oy + 9], fill=4)
        fill = 3 * (k + 1)
        d.rectangle([ox + 2, oy + 7, ox + 1 + fill, oy + 8], fill=3 if k == 3 else 2)
    return im


# 村人: 1 輪郭, 2 肌, 3 肌影, 4 白髪, 5 服, 6 服影, 7 赤, 8 白, 9 法衣, 10 法衣影, 11 緑, 12 靴
NPC_PAL = [(0, 0, 0), (32, 24, 28), (236, 188, 148), (196, 140, 104), (200, 200, 208), (160, 112, 72),
           (112, 76, 48), (200, 72, 64), (244, 240, 228), (216, 224, 240), (160, 172, 200),
           (72, 152, 96), (88, 56, 36), (0, 0, 0), (0, 0, 0), (0, 0, 0)]


def villager(kind):
    """0=老人 1=おばさん 2=巡回司祭 (正面の立ち絵)"""
    im = new32()
    d = ImageDraw.Draw(im)
    R = d.rectangle
    body, shade = (5, 6) if kind < 2 else (9, 10)
    if kind == 0:
        R([11, 15, 20, 25], fill=body)
        R([19, 15, 20, 25], fill=shade)
        R([11, 25, 14, 29], fill=12)
        R([17, 25, 20, 29], fill=12)
        d.line([(23, 12), (23, 29)], fill=6)             # 杖
    else:
        d.polygon([(11, 15), (20, 15), (23, 28), (8, 28)], fill=body)
        d.polygon([(19, 15), (20, 15), (23, 28), (21, 28)], fill=shade)
        R([10, 28, 13, 29], fill=12)
        R([18, 28, 21, 29], fill=12)
        if kind == 1:
            R([13, 18, 18, 26], fill=8)
        else:
            R([15, 15, 16, 27], fill=11)                 # 法衣の帯
    R([8, 17, 10, 22], fill=2)
    R([21, 17, 23, 22], fill=2)
    d.ellipse([11, 5, 20, 15], fill=2)
    if kind == 0:
        d.pieslice([10, 3, 21, 12], 180, 360, fill=4)
        d.polygon([(12, 12), (19, 12), (17, 17), (14, 17)], fill=4)   # ひげ
    elif kind == 1:
        d.pieslice([9, 2, 22, 13], 180, 360, fill=7)     # ずきん
        R([10, 7, 11, 12], fill=7)
        R([20, 7, 21, 12], fill=7)
    else:
        d.polygon([(12, 6), (19, 6), (17, 0), (14, 0)], fill=9)       # 司祭の帽子
        d.line([(12, 6), (19, 6)], fill=11)
    d.point([(13, 10), (18, 10)], fill=1)
    d.line([(15, 13), (16, 13)], fill=3)
    return outline(im)


def boss_parts():
    """茂みに呑まれた水車番 (64x64) を 32x32 の4枚に。"""
    im = Image.new("P", (64, 64), 0)
    d = ImageDraw.Draw(im)
    r = random.Random(3)
    # 水車の残骸
    d.line([(6, 50), (58, 14)], fill=12, width=3)
    d.line([(8, 16), (56, 52)], fill=13, width=3)
    # 茂みの塊
    d.ellipse([8, 14, 56, 60], fill=5)
    d.ellipse([4, 30, 30, 60], fill=5)
    d.ellipse([34, 30, 60, 60], fill=5)
    d.ellipse([16, 6, 48, 36], fill=5)
    for _ in range(90):
        x, y = r.randrange(6, 58), r.randrange(8, 58)
        if im.getpixel((x, y)) == 5:
            c = r.choice((4, 4, 6, 6, 14))
            d.line([(x, y), (x + r.choice((-2, 2)), y + 1)], fill=c)
    for _ in range(8):
        x, y = r.randrange(10, 54), r.randrange(12, 54)
        if im.getpixel((x, y)) in (4, 5, 6):
            d.point([(x, y)], fill=9)
            d.point([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)], fill=7)
    # 呑まれた顔
    d.ellipse([24, 18, 40, 34], fill=3)
    d.pieslice([21, 12, 43, 30], 180, 360, fill=10)     # 麦わら帽
    d.line([(19, 22), (45, 22)], fill=11, width=2)
    d.rectangle([27, 25, 29, 27], fill=8)
    d.rectangle([35, 25, 37, 27], fill=8)
    d.line([(28, 31), (36, 31)], fill=1)
    # 蔓の腕
    d.line([(8, 40), (2, 52), (6, 60)], fill=6, width=3)
    d.line([(56, 40), (62, 52), (58, 60)], fill=6, width=3)
    outline(im)
    return [im.crop((x, y, x + 32, y + 32)) for y in (0, 32) for x in (0, 32)]


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
MOM_SLOT = {}
for dname in ("down", "up", "side"):
    MOM_SLOT[dname] = add(f"mom_{dname}", mother(dname, "stand"), MOM_PAL)
MOM_CAST_SLOT = add("mom_cast", mother("down", "cast"), MOM_PAL)
SATBAR_SLOT = add("satbar", satbar(), FX_PAL)
SHADOW_SLOT = add("shadow", shadow(), FX_PAL)
SPARK_SLOT = add("spark", sparks(), FX_PAL)
assert len(SLOTS) == 24, len(SLOTS)     # 共通 24 枚。残り 8 枚は部屋ごとに差し替える

# 部屋ごとに差し替えるスプライト集 (各8枚ぶん = 4096 バイト)。ネズミは常に先頭
SET_BASE = 24
SETS = [
    ("village", NPC_PAL, [villager(0), villager(1), villager(2)]),
    ("field", ENEMY_PAL, [small4(rat), small4(snake), scarecrow(0), scarecrow(1), scarecrow(2)]),
    ("boss", ENEMY_PAL, [small4(rat), small4(snake)] + [new32(), new32()] + boss_parts()),
]
for n, (name, pal, imgs) in enumerate(SETS):
    assert len(imgs) <= 8
    sh = Image.new("P", (128, 64), 0)
    for i, im in enumerate(imgs):
        sh.paste(im, ((i % 4) * 32, (i // 4) * 32))
    open(f"{OUT}/set{n}.chr", "wb").write(b"".join(tile_bytes(t, 4) for t in img_tiles(sh)))
    open(f"{OUT}/set{n}.pal", "wb").write(pal_bytes(pal))
    for i, im in enumerate(imgs):
        SLOTS.append((f"{name}_{i}", im, pal))
RAT_SLOT, SNAKE_SLOT = SET_BASE, SET_BASE + 1
SCARE_SLOT = [SET_BASE + 2, SET_BASE + 3, SET_BASE + 4]
BOSS_SLOT = [SET_BASE + 4, SET_BASE + 5, SET_BASE + 6, SET_BASE + 7]
NPC_SLOT = [SET_BASE, SET_BASE + 1, SET_BASE + 2]


def slot_tile(i):
    """(タイル番号下位8bit, ネームビット)"""
    page, j = divmod(i, 16)
    return (j // 4) * 64 + (j % 4) * 4, page


sheet = Image.new("P", (128, 192), 0)
for i, (_, im, _) in enumerate(SLOTS[:24]):
    sheet.paste(im, ((i % 4) * 32, (i // 4) * 32))
obj_chr = b"".join(tile_bytes(t, 4) for t in img_tiles(sheet))
open(f"{OUT}/obj.chr", "wb").write(obj_chr)

# 確認用プレビュー
prev = Image.new("RGB", (128, 32 * ((len(SLOTS) + 3) // 4)), (64, 96, 64))
for i, (_, im, pal) in enumerate(SLOTS):
    rgb = Image.new("RGB", (32, 32))
    src = im.load()
    for y in range(32):
        for x in range(32):
            v = src[x, y]
            rgb.putpixel((x, y), pal[v] if v else (64, 96, 64))
    prev.paste(rgb, ((i % 4) * 32, (i // 4) * 32))
prev.resize((prev.width * 4, prev.height * 4), Image.NEAREST).save(f"{OUT}/preview_obj.png")

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
BAR_BASE = len(CHARS)
for color in (1, 3):
    for lv in range(9):
        px = [[0] * 8 for _ in range(8)]
        for x in range(8):
            px[1][x] = px[6][x] = 2
            for y in range(2, 6):
                px[y][x] = color if x < lv else 2
        font_chr += tile_bytes(px, 2)
open(f"{OUT}/font.chr", "wb").write(font_chr)

hud = [0x2000] * (32 * 32)  # 空白にも優先度ビット (後からゲージを書き込むため)


def text(col, row, s):
    for i, ch in enumerate(s):
        hud[row * 32 + col + i] = CHARS.index(ch) | 0x2000  # 優先度ビット


text(1, 1, "GLEN")
text(1, 2, "MOM")
text(23, 1, "DMG 000")
text(23, 2, "HIT  00")
open(f"{OUT}/hud.map", "wb").write(b"".join(bytes((v & 0xFF, v >> 8)) for v in hud))

# ---------------------------------------------------------------- パレット (CGRAM 256色)
cg = [(0, 0, 0)] * 256
cg[0:4] = [(0, 0, 0), (255, 255, 255), (16, 16, 32), (255, 224, 96)]
for n, pal in ((0, HERO_PAL), (1, MOM_PAL), (2, SWORD_A_PAL), (3, SWORD_B_PAL), (4, ENEMY_PAL),
               (5, FLASH_PAL), (6, HEAL_PAL), (7, FX_PAL)):
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
L.append("; 母: 向き(下,上,左,右) x (立ち,歩き) = tile, flags / 最後に詠唱")
L.append("mom_frame_tbl:")
for dname, flip in (("down", 0), ("up", 0), ("side", 0x40), ("side", 0)):
    L.append("  .byte " + ", ".join(entry(MOM_SLOT[dname], flip) for pz in ("stand", "walk")))
L.append(f"mom_cast_frame: .byte {entry(MOM_CAST_SLOT)}")
L.append("scare_frame_tbl: .byte " + ", ".join(entry(x) for x in SCARE_SLOT))
L.append("boss_frame_tbl: .byte " + ", ".join(entry(x) for x in BOSS_SLOT))
L.append("npc_frame_tbl: .byte " + ", ".join(entry(x) for x in NPC_SLOT))
L.append("quad_tile: .byte 0, 2, 32, 34   ; 32x32 スロット内の 16x16 コマ")
for nm, slot in (("RAT", RAT_SLOT), ("SNAKE", SNAKE_SLOT), ("SATBAR", SATBAR_SLOT),
                 ("SHADOW", SHADOW_SLOT), ("SPARK", SPARK_SLOT)):
    t, page = slot_tile(slot)
    L.append(f"{nm}_TILE = ${t:02X}")
    L.append(f"{nm}_NAME = ${page:02X}")
L.append(f"BAR_TILE = {BAR_BASE}")
L.append(f"FONT_CHR_SIZE = {len(font_chr)}")
L.append(f"OBJ_CHR_SIZE = {len(obj_chr)}")
open(f"{OUT}/gfx.inc", "w").write("\n".join(L) + "\n")
print(f"gfx: {len(SLOTS)} common obj slots, {len(SETS)} sets")
