#!/usr/bin/env python3
"""効果音ドライバ (SPC700) と波形 (BRR) を生成して build/spc.bin に出力する。

build/spc.bin は音源 RAM の $0200 から置かれる一塊:
  $0200  ドライバ本体 + 効果音表
  $0300  サンプルディレクトリ
  $0400  BRR 波形

65816 側はポート0 ($2140) に効果音番号、ポート1 ($2141) に通し番号を書く。
ドライバはポート1 が変わったらポート0 の番号を、4 ボイスを順に使って鳴らす。
波形はすべてこのスクリプト内で合成した仮素材。
"""
import math
import os
import random
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "build"
os.makedirs(OUT, exist_ok=True)
RATE = 16000
rnd = random.Random(7)


# ---------------------------------------------------------------- 波形合成
def env(t, dur, attack=0.005, curve=3.0):
    if t < attack:
        return t / attack
    return max(0.0, 1.0 - (t - attack) / (dur - attack)) ** curve


def whoosh():
    dur = 0.17
    out, lp, hp_prev = [], 0.0, 0.0
    for i in range(int(dur * RATE)):
        t = i / RATE
        n = rnd.uniform(-1, 1)
        k = 0.15 + 0.6 * math.sin(math.pi * t / dur)      # フィルタを開いて閉じる
        lp += k * (n - lp)
        e = math.sin(math.pi * t / dur) ** 1.5
        out.append((lp - hp_prev * 0.5) * e * 1.6)
        hp_prev = lp
    return out


def thwack():
    dur = 0.16
    out, lp = [], 0.0
    for i in range(int(dur * RATE)):
        t = i / RATE
        lp += 0.5 * (rnd.uniform(-1, 1) - lp)
        f = 150 * math.exp(-t * 18) + 55
        body = math.sin(2 * math.pi * f * t)
        out.append(lp * env(t, 0.07, 0.001, 2) * 0.9 + body * env(t, dur, 0.002, 2) * 0.9)
    return out


def chime():
    dur = 0.42
    out = []
    for i in range(int(dur * RATE)):
        t = i / RATE
        s = (math.sin(2 * math.pi * 880 * t) + 0.5 * math.sin(2 * math.pi * 1320 * t)
             + 0.3 * math.sin(2 * math.pi * 2640 * t))
        out.append(s / 1.8 * env(t, dur, 0.003, 2.5))
    return out


def boom():
    dur = 0.5
    out, lp, ph = [], 0.0, 0.0
    for i in range(int(dur * RATE)):
        t = i / RATE
        f = 40 + 110 * math.exp(-t * 9)
        ph += 2 * math.pi * f / RATE
        lp += 0.2 * (rnd.uniform(-1, 1) - lp)
        out.append(math.sin(ph) * env(t, dur, 0.002, 1.8) + lp * env(t, 0.25, 0.001, 2) * 0.8)
    return out


def blip():
    dur = 0.07
    return [(0.6 if (i * 440 * 2 // RATE) % 2 else -0.6) * env(i / RATE, dur, 0.002, 1.5)
            for i in range(int(dur * RATE))]


# ---------------------------------------------------------------- BRR (フィルタ0のみ)
def brr(samples):
    pcm = [max(-32768, min(32767, int(s * 30000))) for s in samples]
    pcm = [0] * 16 + pcm                      # 先頭は無音ブロック (発音時のノイズ避け)
    while len(pcm) % 16:
        pcm.append(0)
    out = bytearray()
    blocks = len(pcm) // 16
    for b in range(blocks):
        blk = pcm[b * 16:b * 16 + 16]
        peak = max(abs(v) for v in blk)
        shift = 0
        while shift < 12 and (7 << shift) >> 1 < peak:
            shift += 1
        out.append((shift << 4) | (1 if b == blocks - 1 else 0))
        nib = [max(-8, min(7, int(round(v * 2 / (1 << shift))))) & 0xF for v in blk]
        for k in range(0, 16, 2):
            out.append((nib[k] << 4) | nib[k + 1])
    return bytes(out)


SAMPLES = [brr(f()) for f in (whoosh, thwack, chime, boom, blip)]
S_WHOOSH, S_THWACK, S_CHIME, S_BOOM, S_BLIP = range(5)

# 効果音表: 番号1から。 (サンプル, ピッチ, 音量)  ピッチ $1000 = 32kHz
SE = [
    (S_WHOOSH, 0x0800, 0x38),   # 1 斬る
    (S_THWACK, 0x0800, 0x70),   # 2 当たる
    (S_THWACK, 0x05C0, 0x7F),   # 3 重い一撃
    (S_CHIME,  0x1000, 0x60),   # 4 ジャスト回避
    (S_BOOM,   0x0D00, 0x70),   # 5 被弾
    (S_CHIME,  0x0600, 0x30),   # 6 詠唱開始
    (S_CHIME,  0x0800, 0x60),   # 7 癒やし
    (S_BOOM,   0x0800, 0x7F),   # 8 崩壊
    (S_BLIP,   0x0500, 0x40),   # 9 慈力不足
    (S_WHOOSH, 0x0C00, 0x28),   # 10 回避
]

BASE, DIR, DATA = 0x0200, 0x0300, 0x0400


# ---------------------------------------------------------------- SPC700 の極小アセンブラ
class Asm:
    def __init__(self, org):
        self.org, self.code, self.labels, self.fix = org, bytearray(), {}, []

    def label(self, name):
        self.labels[name] = self.org + len(self.code)

    def b(self, *bs):
        self.code += bytes(bs)

    def rel(self, op, target):          # 相対分岐
        self.b(op, 0)
        self.fix.append(("rel", len(self.code) - 1, target))

    def abs(self, op, target, off=0):   # 絶対アドレス
        self.b(op, 0, 0)
        self.fix.append(("abs", len(self.code) - 2, target, off))

    def done(self):
        for f in self.fix:
            if f[0] == "rel":
                d = self.labels[f[2]] - (self.org + f[1] + 1)
                assert -128 <= d <= 127
                self.code[f[1]] = d & 0xFF
            else:
                v = self.labels[f[2]] + f[3]
                self.code[f[1]], self.code[f[1] + 1] = v & 0xFF, v >> 8
        return bytes(self.code)


a = Asm(BASE)


def dsp(reg, val):                       # mov $F2,#reg / mov $F3,#val
    a.b(0x8F, reg, 0xF2)
    a.b(0x8F, val, 0xF3)


dsp(0x6C, 0x20)   # FLG: ミュート解除、エコー書き込み禁止
dsp(0x0C, 0x7F)   # 主音量 L
dsp(0x1C, 0x7F)   # 主音量 R
dsp(0x2C, 0x00)   # エコー音量
dsp(0x3C, 0x00)
dsp(0x5D, DIR >> 8)
dsp(0x4D, 0x00)   # EON
dsp(0x3D, 0x00)   # NON
dsp(0x2D, 0x00)   # PMON
dsp(0x5C, 0x00)   # KOF
a.b(0xE4, 0xF5)           # mov a,$F5
a.b(0xC4, 0x00)           # mov $00,a      ; 直前の通し番号
a.b(0x8F, 0x00, 0x01)     # mov $01,#0     ; 使うボイス
a.label("loop")
a.b(0xE4, 0xF5)           # mov a,$F5
a.b(0x64, 0x00)           # cmp a,$00
a.rel(0xF0, "loop")       # beq loop
a.b(0xC4, 0x00)           # mov $00,a
a.b(0xE4, 0xF4)           # mov a,$F4      ; 効果音番号
a.rel(0xF0, "loop")       # beq loop
a.b(0x68, len(SE) + 1)    # cmp a,#N+1
a.rel(0xB0, "loop")       # bcs loop
a.b(0x9C)                 # dec a
a.b(0x8D, 5)              # mov y,#5
a.b(0xCF)                 # mul ya
a.b(0x5D)                 # mov x,a        ; X = 表の位置
a.b(0xAB, 0x01)           # inc $01
a.b(0xE4, 0x01)           # mov a,$01
a.b(0x28, 0x03)           # and a,#3
a.b(0xC4, 0x01)           # mov $01,a
a.b(0x9F)                 # xcn a          ; ボイス番号 << 4
a.b(0xC4, 0x02)           # mov $02,a
for reg, col in ((0, 3), (1, 3), (2, 1), (3, 2), (4, 0), (5, 4)):
    a.b(0xE4, 0x02)       # mov a,$02
    a.b(0x08, reg)        # or a,#reg
    a.b(0xC4, 0xF2)       # mov $F2,a
    a.abs(0xF5, "table", col)   # mov a,!table+col+x
    a.b(0xC4, 0xF3)       # mov $F3,a
a.b(0xE4, 0x02)           # ADSR2
a.b(0x08, 6)
a.b(0xC4, 0xF2)
a.b(0x8F, 0xE0, 0xF3)
a.b(0xF8, 0x01)           # mov x,$01
a.abs(0xF5, "mask")       # mov a,!mask+x
a.b(0x8F, 0x4C, 0xF2)     # KON
a.b(0xC4, 0xF3)
a.abs(0x5F, "loop")       # jmp !loop
a.label("mask")
a.b(1, 2, 4, 8)
a.label("table")
for smp, pitch, vol in SE:
    a.b(smp, pitch & 0xFF, pitch >> 8, vol, 0x8F)   # 最後は ADSR1 (即アタック)
code = a.done()
assert len(code) <= DIR - BASE, len(code)

image = bytearray(code.ljust(DIR - BASE, b"\0"))
directory, data = bytearray(), bytearray()
for s in SAMPLES:
    addr = DATA + len(data)
    directory += bytes((addr & 0xFF, addr >> 8, addr & 0xFF, addr >> 8))
    data += s
image += directory.ljust(DATA - DIR, b"\0")
image += data
assert BASE + len(image) < 0xFFC0
open(f"{OUT}/spc.bin", "wb").write(image)
open(f"{OUT}/audio.inc", "w").write(
    f"; 自動生成 (tools/gen_audio.py)\nSPC_SIZE = {len(image)}\nSPC_BASE = ${BASE:04X}\n")
print(f"audio: driver {len(code)} bytes, samples {len(data)} bytes, total {len(image)}")
