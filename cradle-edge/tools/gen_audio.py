#!/usr/bin/env python3
"""音源ドライバ (SPC700)・波形 (BRR)・曲データを生成して build/spc.bin に出力する。

build/spc.bin は音源 RAM の $0200 から置かれる一塊:
  $0200  ドライバ本体 + 表 (音程・楽器・効果音・曲の目次)
  $0800  サンプルディレクトリ
  $0900  BRR 波形、続いて曲データ

65816 側からの指示:
  ポート0 ($2140) = 効果音番号、ポート1 ($2141) = 通し番号 (変わったら鳴らす)
  ポート2 ($2142) = 曲番号 (変わったら切り替え、0 で止める)
効果音はボイス 0-3、曲はボイス 4-7 を使う。波形も曲もすべてこのスクリプト内で作った仮素材。
"""
import math
import os
import random
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "build"
os.makedirs(OUT, exist_ok=True)
RATE = 16000
rnd = random.Random(7)
BASE, DIR, DATA = 0x0200, 0x0800, 0x0900
TICK_DIV = 67               # タイマー0: 8000Hz / 67 ≒ 119.4 回/秒
QUARTER = 48                # 4分音符 = 48 tick (約 149 BPM)


# ---------------------------------------------------------------- 効果音の波形
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
        k = 0.15 + 0.6 * math.sin(math.pi * t / dur)
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


# ---------------------------------------------------------------- 楽器の波形
CYCLE = 64                  # 1 周期 = 64 サンプルのループ波形


def cycle(harmonics):
    return [sum(a * math.sin(2 * math.pi * h * i / CYCLE) for h, a in harmonics)
            for i in range(CYCLE)]


def norm(w, peak=0.9):
    m = max(abs(v) for v in w)
    return [v / m * peak for v in w]


flute = norm(cycle([(1, 1.0), (2, 0.12), (3, 0.22), (4, 0.04)]))
harp = norm(cycle([(h, 1.0 / h ** 1.6) for h in range(1, 12)]))
bass = norm(cycle([(1, 1.0), (2, 0.5), (3, 0.25), (5, 0.08)]))
strings = norm(cycle([(h, 1.0 / h) for h in range(1, 14)]), 0.8)


def kick():
    dur, out, ph = 0.22, [], 0.0
    for i in range(int(dur * RATE)):
        t = i / RATE
        ph += 2 * math.pi * (45 + 120 * math.exp(-t * 30)) / RATE
        out.append(math.sin(ph) * env(t, dur, 0.001, 2.2))
    return out


def snare():
    dur, out, lp = 0.16, [], 0.0
    for i in range(int(dur * RATE)):
        t = i / RATE
        lp += 0.7 * (rnd.uniform(-1, 1) - lp)
        out.append((lp * 0.9 + 0.4 * math.sin(2 * math.pi * 190 * t)) * env(t, dur, 0.001, 2.5))
    return out


def hat():
    dur, out, prev = 0.05, [], 0.0
    for i in range(int(dur * RATE)):
        t = i / RATE
        n = rnd.uniform(-1, 1)
        out.append((n - prev) * 0.5 * env(t, dur, 0.0005, 2))
        prev = n
    return out


# ---------------------------------------------------------------- BRR (フィルタ0のみ)
def brr(samples, loop=False):
    pcm = [max(-32768, min(32767, int(s * 30000))) for s in samples]
    if not loop:
        pcm = [0] * 16 + pcm                  # 先頭は無音ブロック (発音時のノイズ避け)
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
        last = b == blocks - 1
        out.append((shift << 4) | ((3 if loop else 1) if last else 0))
        nib = [max(-8, min(7, int(round(v * 2 / (1 << shift))))) & 0xF for v in blk]
        for k in range(0, 16, 2):
            out.append((nib[k] << 4) | nib[k + 1])
    return bytes(out)


WAVES = [  # (BRR, ループするか)
    (whoosh(), False), (thwack(), False), (chime(), False), (boom(), False), (blip(), False),
    (flute, True), (harp, True), (bass, True), (strings, True), (kick(), False), (snare(), False),
    (hat(), False),
]
SAMPLES = [(brr(w, lp), lp) for w, lp in WAVES]
(S_WHOOSH, S_THWACK, S_CHIME, S_BOOM, S_BLIP, S_FLUTE, S_HARP, S_BASS, S_STR,
 S_KICK, S_SNARE, S_HAT) = range(len(WAVES))

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

# 楽器表: (サンプル, ADSR1, ADSR2, 音量)
INST = [
    (S_FLUTE, 0xAC, 0xC8, 0x1E),   # 0 笛
    (S_HARP,  0x8F, 0x52, 0x16),   # 1 竪琴 (はじいて減衰)
    (S_BASS,  0x8F, 0xAA, 0x22),   # 2 低音
    (S_KICK,  0x8F, 0xE0, 0x28),   # 3 大太鼓
    (S_SNARE, 0x8F, 0xE0, 0x1A),   # 4 小太鼓
    (S_HAT,   0x8F, 0xE0, 0x10),   # 5 鈴
    (S_STR,   0xF8, 0xE4, 0x14),   # 6 弦 (ゆっくり立ち上がる)
]
DRUM_NOTE = 59              # ワンショット波形をほぼ原音の高さで鳴らす音程


# ---------------------------------------------------------------- 曲 (簡易 MML)
#  o4 オクターブ / < > 上下 / l8 既定の長さ / c+ d- 半音 / 4. 付点 / r 休符 / ^ タイ
#  @2 楽器 / L ループ位置 / | は読み飛ばす / k s h は太鼓 (大・小・鈴)
NAMES = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}
CMD_LOOP, CMD_END, TIE = 0xFE, 0xFF, 0x7F


def mml(text):
    """MML を (イベント, tick) の列に。イベント: ('n', 音程) ('r',) ('t',) ('i', 楽器) ('L',)"""
    ev, i, octave, deflen = [], 0, 4, 8
    text = text.replace("|", " ")

    def length():
        nonlocal i
        num = ""
        while i < len(text) and text[i].isdigit():
            num += text[i]
            i += 1
        ticks = QUARTER * 4 // int(num) if num else QUARTER * 4 // deflen
        d = ticks
        while i < len(text) and text[i] == ".":
            d //= 2
            ticks += d
            i += 1
        return ticks

    while i < len(text):
        c = text[i]
        i += 1
        if c.isspace():
            continue
        if c == "o":
            octave = int(text[i])
            i += 1
        elif c == "<":
            octave -= 1
        elif c == ">":
            octave += 1
        elif c == "l":
            deflen = 0
            num = ""
            while text[i].isdigit():
                num += text[i]
                i += 1
            deflen = int(num)
        elif c == "@":
            num = ""
            while text[i].isdigit():
                num += text[i]
                i += 1
            ev.append((("i", int(num)), 0))
        elif c == "L":
            ev.append((("L",), 0))
        elif c in NAMES:
            n = NAMES[c] + 12 * (octave + 1)
            while i < len(text) and text[i] in "+-":
                n += 1 if text[i] == "+" else -1
                i += 1
            ev.append((("n", n), length()))
        elif c in "ksh":
            inst = {"k": 3, "s": 4, "h": 5}[c]
            ev.append((("i", inst), 0))
            ev.append((("n", DRUM_NOTE), length()))
        elif c == "r":
            ev.append((("r",), length()))
        elif c == "^":
            ev.append((("t",), length()))
        else:
            raise ValueError(f"MML: {c!r} at {i}")
    return ev


def compile_channel(events, addr):
    """イベント列 → バイト列。addr はこの列が置かれる音源 RAM 上の番地。"""
    out, dur, loop_at = bytearray(), None, None
    for e, ticks in events:
        if e[0] == "i":
            out.append(0xC0 | e[1])
            continue
        if e[0] == "L":
            loop_at = addr + len(out)
            continue
        first = True
        while ticks > 0:
            chunk = min(ticks, 63)
            if chunk != dur:
                out.append(0x80 | chunk)
                dur = chunk
            if e[0] == "n":
                out.append(e[1] if first else TIE)
            elif e[0] == "r":
                out.append(0)
            else:
                out.append(TIE)
            first = False
            ticks -= chunk
    if loop_at is not None:
        out += bytes((CMD_LOOP, loop_at & 0xFF, loop_at >> 8))
    else:
        out.append(CMD_END)
    return bytes(out)


def ticks_of(text):
    return sum(t for _, t in mml(text))


def note_name(n):
    names = ["c", "c+", "d", "e-", "e", "f", "f+", "g", "a-", "a", "b-", "b"]
    return f"o{n // 12 - 1}{names[n % 12]}"


def arp(chords, pattern, length):
    """和音 (根音の MIDI 番号と構成音の差) を、型 (構成音の添字の並び) で分散和音にする。"""
    s = ""
    for root, tones in chords:
        for k in pattern:
            octave_up, idx = divmod(k, len(tones))
            s += note_name(root + tones[idx] + 12 * octave_up) + str(length) + " "
    return s


MAJ, MIN, DOM7 = (0, 4, 7), (0, 3, 7), (0, 4, 7, 10)


def bass_line(chords, pattern):
    s = ""
    for root, _ in chords:
        for p in pattern.split():
            if p == "r":
                s += "r8 "
            else:
                n, ln = p.split(":")
                s += note_name(root - 12 + int(n)) + ln + " "
    return s


# ---- 1. あさごはん (村・タイトル・結末)  ヘ長調 6/8
F3, BB2, C3, D3, G2, A2 = 53, 46, 48, 50, 43, 45
village_chords = [(F3, MAJ), (F3, MAJ), (BB2, MAJ), (F3, MAJ), (C3, MAJ), (C3, DOM7), (C3, MAJ), (F3, MAJ),
                  (F3, MAJ), (C3, MAJ), (F3, MAJ), (C3, MAJ), (BB2, MAJ), (F3, MAJ), (C3, DOM7), (F3, MAJ)]
village = [
    "L @0 o5 l8 c4 f a4 g | f4. c4. | d4 f a4 >c | <b-4. a4. | g4 a b-4 a | g4 f e4 d | c4 d e4 g | f2. |"
    " a4 b- >c4 <a | b-4 g e4. | f4 g a4 f | g2. | a4 b- >c4 d | c4 <a f4 g | a4 g e4 c | f2. |",
    "L @1 " + arp(village_chords, (0, 1, 2, 3, 2, 1), 8),
    "L @2 " + bass_line(village_chords, "12:4. 7:4."),
    "",
]

# ---- 2. 苔むす街道 (野外)  ニ短調 4/4
D3_, BB2_, C3_, G2_, A2_, F2_ = 50, 46, 48, 43, 45, 41
field_chords = [(D3_, MIN), (D3_, MIN), (BB2_, MAJ), (C3_, MAJ), (D3_, MIN), (D3_, MIN), (G2_ + 12, MIN), (A2_, MAJ),
                (BB2_, MAJ), (C3_, MAJ), (A2_, MIN), (D3_, MIN), (G2_ + 12, MIN), (C3_, MAJ), (F2_ + 12, MAJ),
                (A2_, MAJ)]
field = [
    "L @0 l8 o5 d4 a4 g f e f | o5 d2 r4 c d | o5 f4. g f4 d4 | o5 e4. f e4 c4 |"
    " o5 d4 a4 >c <b- a g | o5 a2 r4 a b- | o6 c4 <b- a g4 f g | o5 a2 c+4 e4 |"
    " o5 b-4. a b-4 >d4 | o6 c4. <b- >c4 e4 | o5 e4 a4 g e c e | o5 d2 r2 |"
    " o5 g4. a b-4 g4 | o5 g4. f e4 c4 | o5 f4 a4 >c4 <a4 | o5 a2 g+4 e4 |",
    "L @6 " + "".join(note_name(r + t[1] + 12) + "1 " for r, t in field_chords),
    "L @2 " + bass_line(field_chords, "12:8 12:8 12:8 12:8 12:8 12:8 24:8 12:8"),
    "L " + "k8 h8 s8 h8 k8 k8 s8 h8 " * 15 + "k8 s8 s8 s8 k8 s8 s16 s16 s8",
]

# ---- 3. 送り (ボス)  ハ短調 4/4
C3b, AB2, G2b, DB3 = 48, 44, 43, 49
boss_chords = [(C3b, MIN), (C3b, MIN), (AB2, MAJ), (G2b, MAJ), (C3b, MIN), (C3b, MIN), (DB3, MAJ), (G2b, MAJ)]
boss = [
    "L @6 o5 c2. d4 | o5 e-2 d4 c4 | o5 c2. <b-4 | o4 b2 >d2 | o5 g2. f4 | o5 e-2 f4 g4 | o5 a-2. f4 | o5 g1 |",
    "L @1 " + arp(boss_chords, (0, 1, 2, 3, 2, 1, 2, 1), 8),
    "L @2 " + bass_line(boss_chords, " ".join(["12:16"] * 6 + ["24:16", "12:16"] * 1 + ["12:16"] * 6
                                             + ["24:16", "12:16"])),
    "L " + "k8 h8 k8 s8 h8 k8 s8 s8 " * 7 + "k8 s16 s16 s8 s8 k8 s8 s8 s8",
]

SONGS = [village, field, boss]
for si, song in enumerate(SONGS, 1):        # 全パートの長さが揃っているか
    lens = {ticks_of(p) for p in song if p}
    assert len(lens) == 1, (si, [ticks_of(p) for p in song if p])

# ---------------------------------------------------------------- 音程表
PITCH = []
for n in range(128):
    f = 440.0 * 2 ** ((n - 69) / 12)
    PITCH.append(min(0x3FFF, int(round(f * CYCLE * 4096 / 32000))))


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
                assert -128 <= d <= 127, f
                self.code[f[1]] = d & 0xFF
            else:
                v = self.labels[f[2]] + f[3]
                self.code[f[1]], self.code[f[1] + 1] = v & 0xFF, v >> 8
        return bytes(self.code)


# 直接ページの割り当て
SE_LAST, SE_VOICE, SE_REG = 0x00, 0x01, 0x02
PTR_LO, PTR_HI, WAIT, DUR, INST_ = 0x10, 0x14, 0x18, 0x1C, 0x20
SONG, KOF, VREG, VBIT, FP = 0x28, 0x29, 0x2A, 0x2B, 0x2C

a = Asm(BASE)
mov_dp_imm = lambda dp, v: a.b(0x8F, v, dp)            # mov dp,#v
mov_a_dp = lambda dp: a.b(0xE4, dp)
mov_dp_a = lambda dp: a.b(0xC4, dp)
mov_a_dpx = lambda dp: a.b(0xF4, dp)
mov_dpx_a = lambda dp: a.b(0xD4, dp)


def dsp(reg, val):
    mov_dp_imm(0xF2, reg)
    mov_dp_imm(0xF3, val)


def dsp_voice(reg, src_label, off):
    """mov a,VREG / or a,#reg / mov $F2,a / mov a,!src+off+y / mov $F3,a"""
    mov_a_dp(VREG)
    if reg:
        a.b(0x08, reg)
    mov_dp_a(0xF2)
    a.abs(0xF6, src_label, off)
    mov_dp_a(0xF3)


# ---- 初期化
dsp(0x6C, 0x20)   # FLG: ミュート解除、エコー書き込み禁止
dsp(0x0C, 0x7F)
dsp(0x1C, 0x7F)
dsp(0x2C, 0x00)
dsp(0x3C, 0x00)
dsp(0x5D, DIR >> 8)
dsp(0x4D, 0x00)
dsp(0x3D, 0x00)
dsp(0x2D, 0x00)
dsp(0x5C, 0x00)
a.b(0xE8, 0x00)                 # mov a,#0
a.b(0xCD, 0x00)                 # mov x,#0
a.label("clr")
mov_dpx_a(PTR_LO)
a.b(0x3D)                       # inc x
a.b(0xC8, 0x18)                 # cmp x,#$18
a.rel(0xD0, "clr")
mov_dp_imm(KOF, 0)
mov_dp_imm(0xFA, TICK_DIV)      # タイマー0
mov_dp_imm(0xF1, 0x01)
mov_a_dp(0xF5)
mov_dp_a(SE_LAST)
mov_a_dp(0xF6)
mov_dp_a(SONG)
mov_dp_imm(SE_VOICE, 0)

# ---- 本体ループ
a.label("loop")
mov_a_dp(0xFD)                  # タイマーが進んだら曲を 1 tick 進める
a.rel(0xF0, "l1")
a.abs(0x3F, "tick")
a.label("l1")
mov_a_dp(0xF6)                  # 曲の切り替え
a.b(0x64, SONG)
a.rel(0xF0, "l2")
mov_dp_a(SONG)
a.abs(0x3F, "startsong")
a.label("l2")
mov_a_dp(0xF5)                  # 効果音
a.b(0x64, SE_LAST)
a.rel(0xF0, "loop")
mov_dp_a(SE_LAST)
mov_a_dp(0xF4)
a.rel(0xF0, "loop")
a.b(0x68, len(SE) + 1)
a.rel(0xB0, "loop")
a.b(0x9C)                       # dec a
a.b(0x8D, 5)                    # mov y,#5
a.b(0xCF)                       # mul ya
a.b(0x5D)                       # mov x,a
a.b(0xAB, SE_VOICE)
mov_a_dp(SE_VOICE)
a.b(0x28, 0x03)
mov_dp_a(SE_VOICE)
a.b(0x9F)                       # xcn a
mov_dp_a(SE_REG)
for reg, col in ((0, 3), (1, 3), (2, 1), (3, 2), (4, 0), (5, 4)):
    mov_a_dp(SE_REG)
    a.b(0x08, reg)
    mov_dp_a(0xF2)
    a.abs(0xF5, "setbl", col)   # mov a,!setbl+col+x
    mov_dp_a(0xF3)
mov_a_dp(SE_REG)
a.b(0x08, 6)
mov_dp_a(0xF2)
mov_dp_imm(0xF3, 0xE0)
a.b(0xF8, SE_VOICE)             # mov x,dp
a.abs(0xF5, "semask")
mov_dp_imm(0xF2, 0x4C)
mov_dp_a(0xF3)
a.abs(0x5F, "loop")

# ---- 曲の開始 (A = 曲番号)
a.label("startsong")
a.b(0x2D)                       # push a
mov_dp_imm(KOF, 0xF0)           # 曲のボイスを全部止める
mov_dp_imm(0xF2, 0x5C)
mov_dp_imm(0xF3, 0xF0)
a.b(0xAE)                       # pop a
a.b(0xCD, 0x00)                 # mov x,#0
a.b(0x68, 0x00)                 # cmp a,#0
a.rel(0xF0, "stopall")
a.b(0x9C)                       # dec a
a.b(0x1C, 0x1C, 0x1C)           # asl a x3
a.b(0xFD)                       # mov y,a
a.label("ss")
a.abs(0xF6, "songtbl")
mov_dpx_a(PTR_LO)
a.b(0xFC)                       # inc y
a.abs(0xF6, "songtbl")
mov_dpx_a(PTR_HI)
a.b(0xFC)
a.b(0xE8, 1)
mov_dpx_a(WAIT)
a.b(0xE8, QUARTER // 2)
mov_dpx_a(DUR)
a.b(0xE8, 0)
mov_dpx_a(INST_)
a.b(0x3D)
a.b(0xC8, 4)
a.rel(0xD0, "ss")
a.b(0x6F)
a.label("stopall")
a.b(0xE8, 0)
a.label("sa")
mov_dpx_a(PTR_HI)
a.b(0x3D)
a.b(0xC8, 4)
a.rel(0xD0, "sa")
a.b(0x6F)

# ---- 1 tick
a.label("tick")
a.b(0xCD, 0x00)
a.label("t1")
mov_a_dpx(PTR_HI)
a.rel(0xF0, "tn")
a.b(0x9B, WAIT)                 # dec dp+x
a.rel(0xD0, "tn")
a.abs(0x3F, "chan")
a.label("tn")
a.b(0x3D)
a.b(0xC8, 4)
a.rel(0xD0, "t1")
a.b(0x6F)

# ---- 1 バイト読む (X = チャンネル) → A
a.label("fetch")
mov_a_dpx(PTR_LO)
mov_dp_a(FP)
mov_a_dpx(PTR_HI)
mov_dp_a(FP + 1)
a.b(0x8D, 0)                    # mov y,#0
a.b(0xF7, FP)                   # mov a,[FP]+y
a.b(0x2D)                       # push a
a.b(0xBB, PTR_LO)               # inc dp+x
a.rel(0xD0, "f1")
a.b(0xBB, PTR_HI)
a.label("f1")
a.b(0xAE)                       # pop a
a.b(0x6F)

# ---- チャンネルを、音か休符が出るまで読み進める
a.label("chan")
a.abs(0x3F, "fetch")
a.b(0x68, 0x80)
a.rel(0x90, "note")
a.b(0x68, 0xC0)
a.rel(0xB0, "c1")
a.b(0x28, 0x3F)
mov_dpx_a(DUR)
a.rel(0x2F, "chan")
a.label("c1")
a.b(0x68, 0xE0)
a.rel(0xB0, "c2")
a.b(0x28, 0x1F)
mov_dpx_a(INST_)
a.rel(0x2F, "chan")
a.label("c2")
a.b(0x68, CMD_LOOP)
a.rel(0xD0, "c3")
a.abs(0x3F, "fetch")
a.b(0x2D)
a.abs(0x3F, "fetch")
mov_dpx_a(PTR_HI)
a.b(0xAE)
mov_dpx_a(PTR_LO)
a.rel(0x2F, "chan")
a.label("c3")
a.b(0xE8, 0)
mov_dpx_a(PTR_HI)
a.b(0x6F)

a.label("note")
a.b(0x2D)                       # push a (音程)
mov_a_dpx(DUR)
mov_dpx_a(WAIT)
a.b(0x7D)                       # mov a,x
a.b(0x60)                       # clrc
a.b(0x88, 4)                    # adc a,#4
a.b(0x9F)                       # xcn a
mov_dp_a(VREG)
a.abs(0xF5, "vbit")             # mov a,!vbit+x
mov_dp_a(VBIT)
a.b(0xAE)                       # pop a
a.b(0x68, 0)
a.rel(0xF0, "rest")
a.b(0x68, TIE)
a.rel(0xF0, "tie")
a.b(0x1C)                       # asl a
a.b(0xFD)                       # mov y,a
dsp_voice(2, "pitch", 0)
dsp_voice(3, "pitch", 1)
mov_a_dpx(INST_)
a.b(0x1C, 0x1C)
a.b(0xFD)
dsp_voice(4, "itbl", 0)
dsp_voice(5, "itbl", 1)
dsp_voice(6, "itbl", 2)
dsp_voice(0, "itbl", 3)
dsp_voice(1, "itbl", 3)
mov_a_dp(VBIT)                  # キーオフを外してからキーオン
a.b(0x48, 0xFF)
a.b(0x24, KOF)
mov_dp_a(KOF)
mov_dp_imm(0xF2, 0x5C)
mov_dp_a(0xF3)
mov_dp_imm(0xF2, 0x4C)
mov_a_dp(VBIT)
mov_dp_a(0xF3)
a.label("tie")
a.b(0x6F)
a.label("rest")
mov_a_dp(VBIT)
a.b(0x04, KOF)                  # or a,dp
mov_dp_a(KOF)
mov_dp_imm(0xF2, 0x5C)
mov_dp_a(0xF3)
a.b(0x6F)

# ---- 表
a.label("semask")
a.b(1, 2, 4, 8)
a.label("vbit")
a.b(0x10, 0x20, 0x40, 0x80)
a.label("setbl")
for smp, pitch, vol in SE:
    a.b(smp, pitch & 0xFF, pitch >> 8, vol, 0x8F)
a.label("itbl")
for smp, a1, a2, vol in INST:
    a.b(smp, a1, a2, vol)
a.label("pitch")
for p in PITCH:
    a.b(p & 0xFF, p >> 8)
a.label("songtbl")
songtbl_at = len(a.code)
a.b(*([0] * (8 * len(SONGS))))
code = bytearray(a.done())
assert BASE + len(code) <= DIR, hex(BASE + len(code))

# ---- 波形と曲を並べる
directory, data = bytearray(), bytearray()
for s, loop in SAMPLES:
    addr = DATA + len(data)
    directory += bytes((addr & 0xFF, addr >> 8, addr & 0xFF, addr >> 8))
    data += s
song_bytes = 0
for si, song in enumerate(SONGS):
    for ci in range(4):
        text = song[ci] if ci < len(song) else ""
        if not text:
            continue
        addr = DATA + len(data)
        blob = compile_channel(mml(text), addr)
        data += blob
        song_bytes += len(blob)
        k = songtbl_at + si * 8 + ci * 2
        code[k], code[k + 1] = addr & 0xFF, addr >> 8

image = bytearray(code.ljust(DIR - BASE, b"\0"))
image += directory.ljust(DATA - DIR, b"\0")
image += data
assert BASE + len(image) < 0xFF00, hex(BASE + len(image))
open(f"{OUT}/spc.bin", "wb").write(image)
open(f"{OUT}/audio.inc", "w").write(
    f"; 自動生成 (tools/gen_audio.py)\nSPC_SIZE = {len(image)}\nSPC_BASE = ${BASE:04X}\n"
    "BGM_VILLAGE = 1\nBGM_FIELD = 2\nBGM_BOSS = 3\n")
print(f"audio: driver {len(code)} bytes, samples {len(data) - song_bytes} bytes, "
      f"songs {song_bytes} bytes, total {len(image)}")
