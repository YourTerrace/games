#!/usr/bin/env python3
"""M2 自動テスト: 敵・被弾・ジャスト回避→返し刃・過治癒→崩壊・癒やし・効果音・全滅後の再開。

  python3 tests/test_m2.py build/cradle-edge.sfc [--shots DIR] [--core bsnes]
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from retro import Emu  # noqa: E402

rom = sys.argv[1]
shots = sys.argv[sys.argv.index("--shots") + 1] if "--shots" in sys.argv else None
core = sys.argv[sys.argv.index("--core") + 1] if "--core" in sys.argv else "snes9x"

sym = {}
for line in open(os.path.join(os.path.dirname(rom), "main.lbl")):
    _, addr, name = line.split()
    sym[name.lstrip(".")] = int(addr, 16)

emu = Emu(rom, core)
r = emu.ram
ok = True


def check(name, cond, detail=""):
    global ok
    print(f"  [{'OK' if cond else 'NG'}] {name} {detail}")
    ok = ok and cond


def shot(name):
    if shots:
        os.makedirs(shots, exist_ok=True)
        emu.screenshot(os.path.join(shots, name + ".png"))


def b(name, i=0):
    return r[sym[name] + i]


def w(name, i=0):
    return emu.word(sym[name] + i)


def enemies():
    return [k for k in range(0, 12, 2) if b("d_type", k) and not b("d_dead", k)]


print(f"core: {core}")
emu.run(40)
check("起動: HP と慈力が満タン", (w("p_hp"), b("m_ji")) == (100, 100), f"hp={w('p_hp')} ji={b('m_ji')}")
check("起動直後は無音", emu.audio_peak() == 0)
emu.run(2, "Y")
emu.run(30)
check("斬ると効果音が鳴る", emu.audio_peak() > 1000)
emu.run(40)
check("最初の群れ (苔ネズミ2匹) が出る", [b("d_type", k) for k in enemies()] == [1, 1], str(enemies()))
shot("01_wave1")

# 突進してくる敵を引きつけて (当たる数フレーム前に) 回避 → ジャスト回避 → 返し刃
def incoming():
    for k in enemies():
        if b("d_state", k) != 2:
            continue
        dx = abs(b("d_x", k + 1) - b("p_x", 1))
        dy = abs(b("d_y", k + 1) - b("p_y", 1))
        if dx < 26 and dy < 22:
            return True
    return False


for _ in range(900):
    emu.run(1, "B+LEFT" if incoming() and b("p_state") == 0 else "")
    if b("p_just"):
        break
check("突進を引きつけて回避するとジャスト回避になる", b("p_just") > 0)
check("ジャスト回避ではダメージを受けない", w("p_hp") == 100, f"hp={w('p_hp')}")
shot("02_just")
emu.run(2, "Y")
emu.run(10)
check("直後の Y が返し刃になる", b("p_stage") == 4)
shot("03_counter")
emu.run(30)
check("返し刃は大ダメージ", w("last_dmg") >= 80, f"dmg={w('last_dmg')}")

# 立ち止まっていると殴られる
hp0 = w("p_hp")
for _ in range(600):
    emu.run(1)
    if w("p_hp") < hp0:
        break
check("敵の攻撃で HP が減る", w("p_hp") < hp0, f"hp {hp0} -> {w('p_hp')}")
check("被弾後は無敵時間がある", b("p_inv") > 0)

# 過治癒を重ねて崩壊させる
collapsed = False
ji0 = b("m_ji")
for _ in range(8):
    emu.run(2, "X")
    for _ in range(56):
        emu.run(1)
        collapsed = collapsed or any(b("d_col", k) for k in range(0, 12, 2))
    if collapsed:
        break
check("過治癒を重ねると敵が崩壊する", collapsed)
check("過治癒は慈力を使う", b("m_ji") < ji0, f"ji {ji0} -> {b('m_ji')}")
shot("04_collapse")

# 癒やしの手
emu.run(120)
ji0 = b("m_ji")
emu.audio_peak()
emu.run(2, "A")
emu.run(3)
check("A で母が詠唱に入る", b("m_state") == 1)
emu.run(70)
check("詠唱が終わると慈力が減っている", b("m_ji") <= ji0 - 15, f"ji {ji0} -> {b('m_ji')}")
check("癒やしの効果音が鳴る", emu.audio_peak() > 1000)

# 放置すれば倒され、最初からやり直しになる
died = False
for _ in range(4000):
    emu.run(1)
    if b("dead_t"):
        died = True
        break
check("HP が尽きると倒れる", died and w("p_hp") == 0)
emu.run(130)
check("倒れたあと最初からやり直せる", w("p_hp") == 100 and b("dead_t") == 0)
shot("05_restart")

print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
