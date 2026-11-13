# ゆりかごの双刃 — ビルド
#   make        ROM を build/cradle-edge.sfc に出力
#   make test   ヘッドレスのエミュレータで自動テスト
#   make dist   配布用に dist/ へコピー
ROM    := build/cradle-edge.sfc
GFX    := build/gfx.inc
PYTHON ?= python3

all: $(ROM)

$(GFX): tools/gen_gfx.py
	@mkdir -p build
	$(PYTHON) -W ignore tools/gen_gfx.py build

build/audio.inc: tools/gen_audio.py
	@mkdir -p build
	$(PYTHON) tools/gen_audio.py build

build/rooms.inc: tools/gen_world.py
	@mkdir -p build
	$(PYTHON) -W ignore tools/gen_world.py build

build/main.o: src/main.s src/enemy.s src/mother.s src/world.s src/prep.s $(GFX) build/audio.inc build/rooms.inc Makefile
	ca65 -g --cpu 65816 -I build --bin-include-dir build -o $@ -l build/main.lst src/main.s

$(ROM): build/main.o lorom.cfg tools/fix_checksum.py
	ld65 -C lorom.cfg -o $@ -m build/main.map -Ln build/main.lbl build/main.o
	$(PYTHON) tools/fix_checksum.py $@

test: $(ROM)
	$(PYTHON) tests/test_game.py $(ROM)

dist: $(ROM)
	@mkdir -p dist
	cp $(ROM) dist/cradle-edge-m3.sfc

clean:
	rm -rf build

.PHONY: all test dist clean
