#!/usr/bin/env python3
"""通しの自動テスト: タイトル → 会話 → 焚き火の支度と記録 → 部屋移動 → 戦闘 → 箱 → ボス → 結末 → つづきから。

戦闘の細部 (ジャスト回避・崩壊など) も合わせて確かめる。道中は時間短縮のため、
テスト側で主人公の HP を書き戻したりボスの HP を減らしたりしている。

  python3 tests/test_game.py build/cradle-edge.sfc [--shots DIR] [--core bsnes]
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
    ok = ok and bool(cond)


def shot(name):
    if shots:
        os.makedirs(shots, exist_ok=True)
        emu.screenshot(os.path.join(shots, name + ".png"))


def b(name, i=0):
    return r[sym[name] + i]


def w(name, i=0):
    return emu.word(sym[name] + i)


def poke_w(name, v, i=0):
    r[sym[name] + i] = v & 0xFF
    r[sym[name] + i + 1] = v >> 8


def pos():
    return b("p_x", 1), b("p_y", 1)


def enemies():
    return [k for k in range(0, 12, 2) if b("d_type", k) and not b("d_dead", k)]


def skip_dialogue(limit=40):
    """会話が終わる (歩けるようになる) まで A を押す。"""
    for _ in range(limit):
        p0 = pos()
        emu.run(6, "RIGHT")
        moved = pos() != p0
        emu.run(6, "LEFT")
        if moved or pos() != p0:
            return True
        emu.run(2, "A")
        emu.run(40)
    return False


def walk_to(tx, ty, limit=600):
    for _ in range(limit):
        x, y = pos()
        keys = []
        if x < tx - 1:
            keys.append("RIGHT")
        elif x > tx + 1:
            keys.append("LEFT")
        if y < ty - 1:
            keys.append("DOWN")
        elif y > ty + 1:
            keys.append("UP")
        if not keys:
            return True
        emu.run(1, "+".join(keys))
    return False


print(f"core: {core}")
emu.run(120)
shot("01_title")
check("タイトルで曲が鳴る", emu.audio_peak() > 3000)
check("タイトルが出る (記録なし)", b("title_has") == 0 and emu.image().getextrema() != ((0, 0),) * 3)
emu.run(2, "START")
emu.run(150)
shot("02_opening")
check("はじめから: 村で始まる", b("room") == 0 and pos() == (128, 136), f"room={b('room')} pos={pos()}")
p0 = pos()
emu.run(20, "RIGHT")
check("会話中は動けない", pos() == p0)
check("会話を送ると動けるようになる", skip_dialogue())

# 木は通れない
walk_to(128, 170)
emu.run(120, "DOWN")
check("木の壁で止まる", pos()[1] < 200, f"y={pos()[1]}")

# 焚き火で記録
walk_to(216, 136)
emu.run(4, "UP")
fire_pos = pos()
emu.run(2, "Y")
emu.run(80)
emu.run(2, "A")             # 焚き火の会話を閉じると支度メニュー
emu.run(120)
check("焚き火で支度メニューが開く", b("menu_cur") == 0 and pos() == fire_pos)
emu.run(2, "DOWN")
emu.run(10)
emu.run(2, "DOWN")
emu.run(10)
emu.run(2, "A")             # 献立: なし → 鹿肉
emu.run(40)
shot("03_prep")
emu.run(2, "B")
emu.run(60)
check("献立を選ぶと力が上がる (鹿肉 +3)", b("meal") == 1 and b("p_str") == 13, f"str={b('p_str')}")
check("支度を終えると記録される", emu.sram is not None and bytes(emu.sram[0:2]) == b"CE" and emu.sram[16] == 1)
check("記録のあと歩ける", skip_dialogue())

# 村人と話す
walk_to(200, 112)
emu.run(4, "UP")
emu.run(2, "Y")
emu.run(60)
p0 = pos()
emu.run(10, "LEFT")
check("村人に話しかけると会話になる", pos() == p0)
shot("04_talk")
skip_dialogue()

# 北へ出ると次の部屋
walk_to(128, 112)
for _ in range(400):
    emu.run(1, "UP")
    if b("room") == 1:
        break
check("画面の切れ目から隣の部屋へ移る", b("room") == 1, f"room={b('room')}")
emu.run(40)
check("移った先に苔ネズミがいる", [b("d_type", k) for k in enemies()] == [1, 1])
check("母がそばについてくる", abs(b("m_x", 1) - pos()[0]) < 40 and abs(b("m_y", 1) - pos()[1]) < 40)
shot("05_room1")

# ジャスト回避 → 返し刃
def incoming():
    for k in enemies():
        if b("d_state", k) != 2 or b("d_tgt", k):
            continue
        if abs(b("d_x", k + 1) - pos()[0]) < 26 and abs(b("d_y", k + 1) - pos()[1]) < 22:
            return True
    return False


hp0 = w("p_hp")
for _ in range(900):
    emu.run(1, "B+LEFT" if incoming() and b("p_state") == 0 else "")
    if b("p_just"):
        break
check("引きつけて回避するとジャスト回避", b("p_just") > 0 and w("p_hp") == hp0)
check("ジャスト回避で見切り印がつく", b("marks", 1) == 1, f"marks={[b('marks', i) for i in range(5)]}")
emu.run(2, "Y")
emu.run(10)
check("直後の Y が返し刃になる", b("p_stage") == 4)
emu.run(40)
check("返し刃は大ダメージ", w("last_dmg") >= 80, f"dmg={w('last_dmg')}")

# 溜め斬り
emu.run(30)
emu.run(110, "Y")
check("Y を押し続けると溜まる", b("p_charge") >= 36, f"charge={b('p_charge')}")
emu.run(8)
check("離すと溜め斬り", b("p_stage") in (5, 6), f"stage={b('p_stage')}")
emu.run(60)
poke_w("p_hp", 40)
med0 = b("med")
emu.run(2, "L")
emu.run(4)
check("L で傷薬を使うと HP が戻る", b("med") == med0 - 1 and w("p_hp") == 100, f"med {med0}->{b('med')} hp={w('p_hp')}")
emu.run(2, "SELECT")
emu.run(2)
check("SELECT で薬の種類が切り替わる", b("med_sel") == 1)
emu.run(2, "SELECT")
emu.run(2, "SELECT")
emu.run(2)

# 以降は道中を急ぐ: HP を書き戻しながら北へ
def rush_up(target_room):
    for _ in range(2500):
        poke_w("p_hp", 100)
        r[sym["p_inv"]] = 30
        x = pos()[0]
        emu.run(1, "UP" + ("+RIGHT" if x < 126 else "+LEFT" if x > 130 else ""))
        if b("room") == target_room:
            return True
    return False


walk_to(128, pos()[1])
check("裏山 1 へ", rush_up(2))
# 箱から苔断ち
for _ in range(300):
    poke_w("p_hp", 100)
    r[sym["p_inv"]] = 30
    if walk_to(40, 152, 1):
        break
emu.run(4, "LEFT")
emu.run(2, "Y")
emu.run(60)
check("箱から苔断ちを手に入れる", b("own") & 4, f"own={b('own')}")
shot("05b_chest")
skip_dialogue()
emu.audio_peak()
# 過治癒 → 崩壊
collapsed = False
for _ in range(10):
    poke_w("p_hp", 100)
    r[sym["m_hp"]] = 70
    emu.run(2, "X")
    for _ in range(56):
        r[sym["p_inv"]] = 30
        r[sym["m_inv"]] = 30
        emu.run(1)
        collapsed = collapsed or any(b("d_col", k) for k in range(0, 12, 2))
    if collapsed:
        break
check("過治癒を重ねると敵が崩壊する", collapsed)
check("効果音が鳴っている", emu.audio_peak() > 1000)
shot("06_collapse")
check("裏山 2 へ", rush_up(3))
shot("07_room3")
check("水車小屋へ", rush_up(4))
emu.run(60)
shot("08_boss_intro")
emu.audio_peak()
emu.run(120)
check("ボス部屋で曲が鳴る", emu.audio_peak() > 3000)
check("ボス部屋に水車番がいる", 4 in [b("d_type", k) for k in enemies()])
check("ボス前の会話を送れる", skip_dialogue())

# ボスの技: 種撒き (飛び道具) が出るまで見る
seen_shot = False
for _ in range(900):
    poke_w("p_hp", 100)
    r[sym["p_inv"]] = 30
    emu.run(1)
    if any(b("sh_t", i) for i in range(0, 16, 2)):
        seen_shot = True
        break
check("ボスが種を撒く", seen_shot)

# ボス: HP を 1 にして斬る
boss = [k for k in enemies() if b("d_type", k) == 4][0]
shot("09_boss")
for _ in range(900):
    poke_w("p_hp", 100)
    r[sym["p_inv"]] = 30
    poke_w("d_hp", 1, boss)
    bx, by = b("d_x", boss + 1), b("d_y", boss + 1)
    x, y = pos()
    if abs(x - bx) > 6:
        emu.run(1, "RIGHT" if x < bx else "LEFT")
    elif y - by > 30:
        emu.run(1, "UP")
    else:
        emu.run(2, "UP+Y")
        emu.run(6, "UP")
    if b("d_dead", boss) or b("boss_dead"):
        break
for _ in range(200):
    emu.run(1)
    if b("boss_dead"):
        break
check("ボスを倒せる", b("boss_dead") == 1)
emu.run(120)
shot("10_ending")
for _ in range(12):
    emu.run(2, "A")
    emu.run(60)
    if b("title_has"):
        break
emu.run(120)
shot("11_title_again")
check("結末のあとタイトルに戻り、記録がある", b("title_has") == 1 and b("title_sel") == 1)
emu.run(2, "START")
emu.run(150)
check("つづきから: 最後の焚き火の位置で再開", b("room") == 0 and pos() == fire_pos and w("p_hp") == 100,
      f"room={b('room')} pos={pos()}")
shot("12_continue")

print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)

