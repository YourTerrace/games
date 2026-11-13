#!/usr/bin/env python3
"""M1 自動テスト: 起動 → 歩く → 連斬4段 → 木人が吹き飛ぶ、を WRAM の値で検証する。

  python3 tests/test_m1.py build/cradle-edge.sfc [--shots DIR] [--core bsnes]
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from retro import Emu  # noqa: E402

rom = sys.argv[1]
shots = sys.argv[sys.argv.index("--shots") + 1] if "--shots" in sys.argv else None
core = sys.argv[sys.argv.index("--core") + 1] if "--core" in sys.argv else "snes9x"

# ラベル表 (ld65 -Ln) からアドレスを引く
sym = {}
for line in open(os.path.join(os.path.dirname(rom), "main.lbl")):
    _, addr, name = line.split()
    sym[name.lstrip(".")] = int(addr, 16)

emu = Emu(rom, core)
ok = True


def check(name, cond, detail=""):
    global ok
    print(f"  [{'OK' if cond else 'NG'}] {name} {detail}")
    ok = ok and cond


def shot(name):
    if shots:
        os.makedirs(shots, exist_ok=True)
        emu.screenshot(os.path.join(shots, name + ".png"))


def px(name, i=0):
    return emu.ram[sym[name] + i * 2 + 1]


print(f"core: {core}")
emu.run(30)
check("起動して初期位置にいる", (px("p_x"), px("p_y")) == (128, 168), f"({px('p_x')},{px('p_y')})")
check("画面が真っ黒ではない", emu.image().getextrema() != ((0, 0),) * 3)
shot("01_boot")

emu.run(20, "RIGHT")
check("右に歩く (1.5px/F)", px("p_x") == 158, f"x={px('p_x')}")
check("右を向く", emu.ram[sym["p_face"]] == 3)
emu.run(200, "RIGHT")
check("右の壁で止まる", px("p_x") == 0xE8, f"x={px('p_x')}")
emu.run(100, "LEFT")
x0 = px("p_x")
emu.run(1, "B+LEFT")
emu.run(19, "LEFT")
check("回避ステップで速く動く", x0 - px("p_x") >= 30, f"dx={x0 - px('p_x')}")
emu.run(5)

# 中央の木人の正面へ
while px("p_x") > 128:
    emu.run(1, "LEFT")
while px("p_x") < 128:
    emu.run(1, "RIGHT")
while px("p_y") > 110:
    emu.run(1, "UP")
emu.run(2)
shot("02_ready")
hp0 = emu.word(sym["d_hp"] + 2)
y0 = px("d_y", 1)

# 連斬 4 段: Y を刻んで押す
combo_seen = []
for i in range(130):
    pressing = i % 8 < 2 and emu.ram[sym["p_stage"]] < 3
    emu.run(1, "Y" if pressing else "")
    combo_seen.append(emu.ram[sym["combo"]])
    if i % 3 == 0:
        shot(f"03_combo_{i:03d}")
check("連斬が 4 ヒットする", max(combo_seen) == 4, f"combo={max(combo_seen)}")
check("木人が壊れるか HP が減る", emu.word(sym["d_hp"] + 2) < hp0 or emu.ram[sym["d_dead"] + 2] > 0,
      f"hp {hp0} -> {emu.word(sym['d_hp'] + 2)}")
check("木人が奥へ吹き飛ぶ", y0 - px("d_y", 1) >= 16 or emu.ram[sym["d_dead"] + 2] > 0,
      f"y {y0} -> {px('d_y', 1)}")
check("ダメージが表示用に記録される", emu.word(sym["last_dmg"]) > 0, f"dmg={emu.word(sym['last_dmg'])}")
check("攻撃後は操作可能に戻る", emu.ram[sym["p_state"]] == 0)
emu.run(200)
check("コンボ表示が時間で消える", emu.ram[sym["combo"]] == 0)
check("壊れた木人が復活する", emu.ram[sym["d_dead"] + 2] == 0 and emu.word(sym["d_hp"] + 2) == 100)
shot("04_after")

print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
